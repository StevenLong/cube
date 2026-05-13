# Handoff, 2026-05-13

## Where we are
Phase 5 done. Sphere pathfinding done. Project now has a main menu and a level
loader pattern, with Tutorial 1: Movement as the first level. Enemy fades to
silhouette when out of the cube's line of sight. New systems need tuning, but
everything functions.

All commits on `main` are pushed to origin. Last session ended with one local
commit that needed pushing; that's done.

## Completed this session

### Water puddle (Phase 5 Slice 5)
- Water is binary, whole-cube cleanse. Touching water with any face marked
  clears all of `_face_marks` and plays the splash sound. No step counter,
  no per-face dilution. See `project_ink_water_binary` memory for design
  rationale. Existing footprints on the ground are left in place.
- New `WaterPuddle` node in `main.tscn`, cyan transparent material, in the
  `water_puddles` group. Position `(4, 0.01, 1)` is arbitrary, move as needed.
- New player state `_water_overlap_count`; handler `_on_water_entered` calls
  `_check_water_cleanse()` on entry.

### Sphere pathfinding (grid A*)
- New nav grid built in `_ready` from `StaticBody3D` children of root whose
  names start with "Wall". Cell pitch is 1u. Bounds are [-13, 13] inclusive.
  Perimeter walls sit outside those bounds and are handled implicitly.
- `_find_path(start, goal)` runs A* with Manhattan heuristic, 4-connected.
  Goal-blocked fallback snaps to nearest open 8-neighbour so footprints on
  wall cells still produce a reachable target.
- `_follow_path(delta, mult, final_target)` walks cell-to-cell via the
  existing `_move_toward`. When the path is exhausted, falls back to direct
  seek so the final sub-cell distance closes.
- All four states pathfind now: PATROL recomputes on entry and waypoint
  advance, SUSPICIOUS on entry, INVESTIGATE on entry and on footprint
  retarget, PURSUIT on entry and every `PURSUIT_REPATH_INTERVAL` (0.3s).

### Main menu + level loader + Tutorial 1
- New `main_menu.tscn` + `main_menu.gd`. Three buttons: Tutorial 1: Movement,
  Sandbox, Quit. Sandbox loads the existing `main.tscn` unchanged. Tutorial 1
  loads `levels/level_01_movement.tscn`. Escape on the menu quits.
- `project.godot` entry scene is now `res://main_menu.tscn`.
- Escape behaviour moved from `player.gd` to `level.gd`. In any level, Escape
  unpauses the tree and calls `change_scene_to_file("res://main_menu.tscn")`.
- `level.gd` made the enemy optional: `get_node_or_null("../Enemy")`. If no
  enemy is present, the pursuit signal is not connected and the Spotted
  results label is hidden.
- Tutorial 1 scene: player, ground, start tile at `(0, 0.01, 0)`, end tile at
  `(3, 0.01, 3)` so the player has to tumble in two axes. No enemy, walls,
  perimeters, or puddles.

### Enemy line-of-sight silhouette fade
- Each frame, raycast from player global position to enemy global position
  against bodies only. If unblocked, target alpha is 1.0. If a wall blocks
  the line, target alpha is `SILHOUETTE_ALPHA` (0.3).
- Current alpha lerps toward the target at `VISIBILITY_LERP_RATE` (8.0/s),
  giving roughly a 0.3 second crossfade. Material transparency is set to
  `TRANSPARENCY_ALPHA` in `_ready` so the alpha channel actually renders.
- Tutorial 1 has no enemy, so this is sandbox-only behaviour.

## Phase status
- [x] Phase 1, core movement
- [x] Phase 2, extension
- [x] Phase 3, detection and hiding
- [x] Phase 4, first playable level
- [x] Phase 5, environmental detection (all six items done)
- [x] Sphere pathfinding (was deferred from prior session)
- [x] Main menu and level loader
- [x] Tutorial 1: Movement

## Tuning backlog (next session's first focus)
User flagged these as needing pass before moving on.

### Player LoS silhouette
- `SILHOUETTE_ALPHA` (0.3) and `VISIBILITY_LERP_RATE` (8.0) are placeholders.
  Likely want to tune by feel.
- The enemy's ground-projected vision cone (drawn in `grid_ground.gdshader`,
  not on the mesh) is currently still visible when the enemy itself is faded.
  If you can't see the enemy you shouldn't see where it's looking. Easiest
  fix: scale `cone_alpha` uniform by `_visibility_alpha` in
  `_update_cone_uniforms`, so the cone fades with the enemy.

### Pathfinding
- PATROL waypoint default in `enemy_sphere.gd` is still the 4-corner
  rectangle. Hasn't been re-evaluated post-pathfinding (could now be a
  tighter shape that the sphere would route through).
- `PURSUIT_REPATH_INTERVAL` 0.3s feels responsive in casual testing but has
  not been stress-tested.

## Deferred / parked

### From prior session (still parked)
- Unused `RayCast3D` on Enemy in `main.tscn`; replaced by the math-based
  cone but the node was never removed. Safe to delete.
- Per-face cube ink visualisation. Cube tints whole-body when any face is
  marked. Per-face decals or shader trick still TODO.
- No fail-state results screen. Enemy contact still instantly reloads the
  scene; not symmetric with the Complete results panel.
- Extended-cuboid footprints. One deposit at cuboid centre, not per contact
  cell.

### From this session
- Polish backlog: sfx + particles for end/caught, smooth respawn camera,
  spawn elevator animation, symmetric Caught results panel.
- More tutorials: sprint and noise next, then extension, blend, ink and
  water, enemy. Each is a stripped scene loaded from the menu.
- Level select grows organically as tutorials are added; no scrolling or
  paging needed yet.

## Tunable constants worth knowing
- `enemy_sphere.gd`
  - `VIEW_RADIUS` 8.0, `VIEW_CONE_COS` 0.766 (80° forward cone), player vision
  - `FOOTPRINT_VIEW_RADIUS` 5.0, `FOOTPRINT_VIEW_CONE_COS` 0.866 (60°)
  - `INVESTIGATE_TIMEOUT` 3.0s, `SUSPICIOUS_TIMEOUT` 2.0s,
    `PURSUIT_LOSE_TIMEOUT` 1.5s
  - Speed mults: PATROL 1.0, SUSPICIOUS 0.5, INVESTIGATE 1.0, PURSUIT 1.5
  - `TURN_RATE` 5.0 rad/s, `TURN_LEAD_THRESHOLD` PI/6
  - `FOOTPRINT_VISIT_DIST` 0.6u
  - New: `NAV_MIN`/`NAV_MAX` -13/13, `PATH_CELL_ARRIVE` 0.15,
    `PURSUIT_REPATH_INTERVAL` 0.3s, `SILHOUETTE_ALPHA` 0.3,
    `VISIBILITY_LERP_RATE` 8.0

## Key files
- `player.gd`: tumble, extension, dodge, blend, face tracking, ink, audio
  waves, footprint API, water cleanse. No longer handles Escape.
- `enemy_sphere.gd`: PATROL/SUSPICIOUS/INVESTIGATE/PURSUIT, math-based cone
  vision, footprint trail logic, smooth rotation, cone shader uniform updates,
  grid A* pathfinding, LoS silhouette fade.
- `level.gd`: state machine (READY/PLAYING/COMPLETE), stats, end tile, pause,
  Escape -> menu, optional enemy.
- `camera_controller.gd`: fixed follow + tilt; `process_mode = ALWAYS`.
- `main_menu.gd`: button signals, Escape quits.
- `main.tscn`: sandbox scene, full arena with everything in it.
- `main_menu.tscn`: title and three buttons.
- `levels/level_01_movement.tscn`: stripped movement-only tutorial.
- `shaders/grid_ground.gdshader`: grid + waves + vision cone + footprints,
  all in fragment. Hardcodes 30x30 UV mapping, so all ground planes are 30x30.

## Input map (updated)
| Action | Controller | Keyboard |
|--------|-----------|---------|
| Move | D-pad / left stick | WASD / arrows |
| Sprint | R2 | Left Shift |
| Dodge | Circle (hold + dir) | Space |
| Extend mode | R1 | E |
| Extend depth fwd | L1 (+ R1) | Q |
| Extend depth back | L2 (+ R1) | C |
| Blend (hide) | Square | V |
| Camera tilt | Right stick Y | R / F |
| Back to menu / quit menu | (none) | Escape |

Escape used to quit the game outright; now it returns to the main menu inside
a level, and quits only from the main menu itself.

## Memory notes worth checking
- Transform3D is row-major in `.tscn`
- GDScript can't infer types from untyped Array element access
- Commit/push cadence: end of session
- HANDOFF.md is read at session start and rewritten at session end, not
  edited mid-session
- Ink/water mechanic is binary, whole-cube cleanse (no step counter)
- No em or en dashes in any output
- Task list at `/home/steven_long/game-dev/Cube Game Tasks.md` (WSL canonical)

## Task list source
`/home/steven_long/game-dev/Cube Game Tasks.md`, updated this session to add
Phase 6 (loader and tutorials) and tick remaining Phase 5 items. Committed
and pushed in that repo.
