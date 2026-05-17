# Handoff, 2026-05-17

## Where we are
Major visibility/audio rework done this session. The silhouette-tuning task
expanded into "out of sight = truly out of sight" plus per-fragment fog of war
plus partial cone visibility. Symmetric Caught panel landed. Patrol redesigned
to actually exercise pathfinding. Pursuit gained an off-grid mode for an
aggression tier.

All changes are local; commit + push pending at handoff time.

## Completed this session

### Visibility/audio rework (started as a tuning task)
- `SILHOUETTE_ALPHA` 0.3 → **0.0**. Enemy fades to fully invisible behind walls.
  Constant kept its name even though it no longer renders a silhouette; rename
  later if desired.
- Visibility init flash fix: first `_process` tick now snaps `_visibility_alpha`
  to its target instead of lerping from 1.0. A hidden-at-start enemy stays
  hidden on frame 0.
- Cone overlay alpha now scaled by `_visibility_alpha` in
  `_update_cone_uniforms` so the cone fades together with the enemy.
- Per-enemy hum: new `HumSound` AudioStreamPlayer3D child of `Enemy`. Stream is
  procedurally generated in `_make_hum_sound()`: 147Hz fundamental + 294Hz
  octave + 3Hz amplitude tremolo, 14700-sample buffer that loops seamlessly
  (integer cycles for all three components). Current 3D settings: unit_size 6,
  max_distance 20, volume_db -10.

### Fog of war (Flavor B, real LoS)
- `grid_ground.gdshader` now has uniforms `player_xz`, `wall_mins[16]`,
  `wall_maxs[16]`, `wall_count`, `dark_factor` (default 0.25) and a
  `segment_blocked()` 2D slab test.
- Per fragment: `visibility = segment_blocked(player_xz, world_xz) ? 0 : 1`.
  Cone intensity is multiplied by visibility (so cone draws only on visible
  ground — partial-cone visibility from the prior "slice 4" backlog item is
  done for free). Final ALBEDO multiplied by `mix(dark_factor, 1.0, visibility)`
  so footprints/waves/grid all dim in shadowed regions.
- `player.gd` enumerates `Wall*` children in `_push_walls_to_shader()` at
  `_ready`, reads each `MeshInstance3D.mesh` (BoxMesh) for size, builds AABB
  arrays. `Perimeter*` walls are skipped (the ground strip under them is
  hidden anyway). Player pushes `player_xz` each frame alongside the wave
  uniforms.
- Tutorial 1 has no walls → wall_count is 0 → no darkening, no cone (no enemy
  either). Plays unchanged.

### Symmetric Caught panel
- `player.gd`: new `caught` signal. Enemy contact emits it instead of
  immediately reloading the scene.
- `level.gd`: new `CAUGHT` state alongside `COMPLETE`. `_enter_caught()` sets
  title to "Caught", hides the Spotted line (always Yes if caught, redundant).
  Restart logic shared between both terminal states.
- Title label is now driven by code so each ending sets its own text.

### Patrol shape redesigned
- Waypoints changed from `(±10, ±8)` perimeter rectangle to a wall-hugging
  pattern: `(8,0), (-8,0), (-8,1), (8,1)`. Both horizontal legs traverse a
  blocked nav cell (`(3,0)` and `(2,1)`), so 2 of 4 legs force the sphere to
  route around walls. The other two are 1-cell verticals.
- Important context: pathfinder is **4-connected**. A previous attempt at a
  figure-X with diagonal waypoints failed visually because the pathfinder
  resolves diagonals as L-shapes that happen to skirt the wall cluster instead
  of crossing it. Any future patrol redesign must account for this — or move
  the pathfinder to 8-connected.

### Off-grid pursuit (aggression tier)
- PATROL / SUSPICIOUS / INVESTIGATE: unchanged, still 4-connected grid A*.
- PURSUIT: `_pursue` now branches on `_has_pursuit_corridor()`. When the
  3-ray check (center + perpendicular offset by `PURSUIT_LOS_PADDING` 0.45)
  passes, the sphere clears its path and calls `_move_toward(_player.position,
  ...)` directly — off-grid, smooth-turning, no cell snap. When the corridor
  is blocked, falls back to existing A* + `_follow_path`.
- The single-ray `_visible_to_player()` is retained for the silhouette fade
  (center-to-center is the right semantic there).

### Polish
- Unused `RayCast3D` on Enemy in `main.tscn` deleted.

## Tuning backlog (next session candidates)

### Pursuit corridor
- Per-frame corridor check could oscillate at wall transitions (one frame
  blocked, next frame clear). Watch for one-frame jitter when LoS reopens
  just past a wall corner. Fix would be hysteresis (stick to current mode
  for N frames after a transition).
- `PURSUIT_LOS_PADDING` 0.45 is paired with the default sphere radius 0.5.
  If sphere size changes, update.

### Patrol
- Current waypoints are a thin near-wall pattern (z=0/z=1). Visually less
  varied than the old perimeter rectangle. If feel suggests boredom, consider
  more waypoints or 8-connected A*.

### Fog of war
- `dark_factor` 0.25 is a placeholder. User said "works well enough" but never
  tuned. Try 0.15 (harsher) or 0.4 (subtler) if you want a feel pass.
- Perimeter walls are excluded from the LoS array — fine today; revisit if
  arena layouts change.
- `MAX_WALLS` is 16 in shader + player. Plenty for current arena (~3 walls).

### Hum
- Volume / range still placeholder. unit_size 6, max_distance 20, volume_db
  -10. Adjust on `HumSound` in `main.tscn`.
- Tremolo at 3Hz / depth 0.3 — feel-tunable in `_make_hum_sound()`.

## Deferred / parked

### From earlier sessions (still parked)
- Per-face cube ink visualisation. Whole-cube tint still used.
- Extended-cuboid footprints. One deposit at cuboid centre, not per cell.
- Polish backlog: sfx + particles for end/caught, smooth respawn camera,
  spawn elevator animation.
- More tutorials: sprint and noise next, then extension, blend, ink and
  water, enemy.

### From this session
- 8-connected pathfinder switch. Would enable more interesting patrol shapes
  and smoother pursuit grid paths. Currently 4-connected works for everything
  needed; only worth doing if patrol/investigate feel mechanical.
- Hysteresis on pursuit corridor check (see Tuning backlog).
- Rename `SILHOUETTE_ALPHA` to something honest (e.g. `HIDDEN_ALPHA`).

## Tunable constants worth knowing
- `enemy_sphere.gd`
  - Vision: `VIEW_RADIUS` 8.0, `VIEW_CONE_COS` 0.766 (80° cone)
  - Footprint vision: `FOOTPRINT_VIEW_RADIUS` 5.0, `FOOTPRINT_VIEW_CONE_COS`
    0.866 (60°)
  - Timeouts: `INVESTIGATE_TIMEOUT` 3.0s, `SUSPICIOUS_TIMEOUT` 2.0s,
    `PURSUIT_LOSE_TIMEOUT` 1.5s
  - Speed mults: PATROL 1.0, SUSPICIOUS 0.5, INVESTIGATE 1.0, PURSUIT 1.5
  - `TURN_RATE` 5.0 rad/s, `TURN_LEAD_THRESHOLD` PI/6
  - `FOOTPRINT_VISIT_DIST` 0.6u
  - Navigation: `NAV_MIN`/`NAV_MAX` -13/13, `PATH_CELL_ARRIVE` 0.15,
    `PURSUIT_REPATH_INTERVAL` 0.3s
  - Visibility: `SILHOUETTE_ALPHA` 0.0, `VISIBILITY_LERP_RATE` 8.0,
    `PURSUIT_LOS_PADDING` 0.45
- `grid_ground.gdshader`
  - `dark_factor` 0.25 (default)
  - Hardcoded UV map: 30x30, so all ground planes must be 30x30
- `main.tscn` HumSound: unit_size 6, max_distance 20, volume_db -10

## Key files
- `player.gd`: tumble, extension, dodge, blend, face tracking, ink, audio
  waves, footprint API, water cleanse, **wall-AABB enumeration for the fog
  shader**, **caught signal**. No longer handles Escape.
- `enemy_sphere.gd`: PATROL/SUSPICIOUS/INVESTIGATE/PURSUIT, math-based cone
  vision, footprint trail logic, smooth rotation, cone shader uniform
  updates, grid A* pathfinding, LoS silhouette fade, **per-enemy hum
  generation**, **off-grid pursuit corridor check**.
- `level.gd`: state machine (READY/PLAYING/COMPLETE/**CAUGHT**), stats,
  end tile, pause, Escape -> menu, optional enemy, **handles caught**.
- `camera_controller.gd`: fixed follow + tilt; `process_mode = ALWAYS`.
- `main_menu.gd`: button signals, Escape quits.
- `main.tscn`: sandbox scene, full arena, **HumSound on Enemy**, RayCast3D
  on Enemy removed.
- `main_menu.tscn`: title and three buttons.
- `levels/level_01_movement.tscn`: stripped movement-only tutorial.
- `shaders/grid_ground.gdshader`: grid + waves + vision cone + footprints
  + **player LoS fog of war**, all in fragment. Hardcodes 30x30 UV mapping.

## Input map
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

## Memory notes worth checking
- Read HANDOFF.md first thing at session start (new this session)
- Transform3D is row-major in `.tscn`
- GDScript can't infer types from untyped Array element access
- Commit/push cadence: end of session
- HANDOFF.md is read at session start and rewritten at session end, not
  edited mid-session
- Ink/water mechanic is binary, whole-cube cleanse (no step counter)
- No em or en dashes in any output
- Task list at `/home/steven_long/game-dev/Cube Game Tasks.md` (WSL canonical)

## Task list source
`/home/steven_long/game-dev/Cube Game Tasks.md`, unchanged this session.
