# Handoff, 2026-05-31

## Where we are
First tutorial slice complete and committed: three tutorials (movement,
maneuvering, extend-and-bridge) plus the Tutorials submenu. The T2 first-move
desync bug is fixed.

Commits this stretch:
- `521d9a6` Phase 8 C wedge fix (tip/fall spurious triggers).
- `2a416d3` Phase 9 tutorials: T1 + T2 + submenu.
- `acca158` Phase 9: T2 grid_pos fix + T3 (extend-lock bridge).

## Next session (per the user)
1. **Assessment first, before building more.** Take stock of where the project is
   and what needs fleshing out before moving on. Status snapshot below to seed it.
2. **Enemy types and behaviors** are the flagged gap: only one enemy exists
   (`enemy_sphere.gd`: PATROL / SUSPICIOUS / INVESTIGATE / PURSUIT), no variety, and
   several stale enemy issues are carried (bottom). The user wants this fleshed out
   soon.

## Status snapshot (to seed the assessment)
- **Phase 8 A (extended-state gaps)**: DONE.
- **Phase 8 B (blend redesign)**: DONE.
- **Phase 8 C (floating void world)**: data model + per-tile render + fall/tip/wedge
  DONE (slices 1-2). Slice 3 (a real demo level shape) was SKIPPED; we pivoted to
  tutorials. The void mechanics still have no showcase level.
- **Phase 8 D (animation/juice)**: NOT started.
- **Phase 8 E (audio)**: NOT started.
- **Phase 9 (tutorials)**: T1-T3 built this slice (a movement-first framing). The
  task list's Phase 9 lists different tutorials (sprint/noise, extension, blend =
  "signature situations"); our framing diverges. RECONCILE the task list.
- **Enemies**: one type (sphere). No variety. Known stale issues carried (bottom).
  Flagged by the user as the next area to flesh out.

## Tutorial slice reference
Menu: main menu "Tutorials" -> `tutorials_menu.tscn` (buttons 1/2/3 + Back) ->
tutorial -> finish -> Esc returns to the MAIN menu (not the submenu; minor polish).

- `tutorials_menu.tscn` / `.gd`: the submenu. Add future tutorial buttons here.
- `levels/tutorial_01_move.tscn`: 1x10 corridor, left->right (start (0,0), finish (9,0)).
- `levels/tutorial_02_gaps.tscn`: 20x5, weave through 4 single-gap walls (start (0,2),
  finish (19,0)).
- `levels/tutorial_03_bridge.tscn`: 1x20 corridor. Lock zone (1,3,1) at x=4 -> gate at
  x=6 (open while locked) -> 1-wide gap at x=10 -> unlock zone at x=12 -> finish x=18.
- `level_01_movement.tscn` (27x27 open) is ORPHANED; delete whenever.

Conventions:
- **Safety edge** = a collision-only boundary wall; `level.gd._build_safety_edges`
  auto-draws a red line where a floor cell meets a WALL collider (layer 1). Open void
  edges get no line (their blankness = "you can fall here").
- New levels clone the `level_01_movement.tscn` rig. `level.gd` auto-builds floor
  (FloorRect/FloorMissing) + safety edges; reads start from the Player node, end from
  EndTile.position. The player start cell now syncs via grid_pos in `_ready`.

## T3 watch item (confirm / tune)
Bridging depends on the player reaching the gap (x=10) on the tumble step where the
3-tall pillar lays its 1x3 bar across it (x=10 is the middle of a bar-phase from the
lock at x=4, so it should bridge: ends on floor at 9 and 11, void centre at 10 =
stable). If on playtest the pillar drops in instead, shift the gap by +/-1 cell.
Committed as-is; the user opened it in-editor and approved the commit.

## Extend-lock mechanic reference (for reuse)
- `extend_lock_zone.gd` (Area3D, monitoring off, grid-checked): `mode` LOCK/UNLOCK,
  `required_dims` (w x, h y, d z). LOCK arms when the player is at rest, not already
  locked, dims == required_dims, and footprint_min == the zone's cell; shows a
  blinking ghost blueprint. UNLOCK releases when the locked cuboid covers its cell.
  Set the zone's collision_layer = 0 so its shape never blocks the player's MoveCast.
- `extend_lock_gate.gd` (StaticBody3D, layer 1): collision disabled + green while
  `player.is_extend_locked()`, else red and blocking.
- The player forms a 3-tall pillar by holding "extend" and tapping "move_forward"
  twice (`_try_extend(EXT_UP)`); move_left/right extend in x; extend_depth_fwd/back
  (Q/C) extend in z.

## Verify recipe (headless, ~/.local/bin/godot, v4.6)
- Parse-check: `godot --headless --editor --quit 2>&1 | grep -E "SCRIPT ERROR|Parse Error|SHADER ERROR"`
- Smoke-load: `godot --headless --quit-after 60 res://<scene> 2>&1 | grep -iE "ERROR|nil|invalid"` (filter vulkan/driver/audio noise)
- Exit code is 0 even on errors; always grep.

## Carried (unchanged)
- Phase 8 D (juice), E (audio): not started. F parked (grow tall, pre-spawn flythrough).
- Camera stays put during a fall; cube exits the bottom (slice D will refine: follow
  Y, fog, fade). No fall SFX (cluster E).
- **Enemy stale items** (relevant to the enemy fleshing-out next session): stale enemy
  path / search-through-corner / pursuit direct-line `_move_toward` / unused WallRay
  nodes / `DEBUG_DETECTION = true` / tall-pillar false blend / cover counts the
  perimeter / two scenes diverge / LoS centre-to-centre per cell. All carried.

## Memory notes
- Read HANDOFF.md first at session start.
- Active verbs (sprint/dodge/knock) are cube-only; extension is a positional
  commitment for motion, not a safety lock (extending into instability is allowed;
  the cube falls).
- No Co-Authored-By trailer; no em/en dashes; commit at session end or on request.
  Transform3D row-major; ink/water binary cleanse; GDScript untyped-array inference
  needs annotation.
