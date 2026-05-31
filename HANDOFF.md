# Handoff, 2026-05-31

## Where we are
Two threads this session, both committed:

1. **Phase 8 cluster C wedge bug: FIXED** (commit 521d9a6). Verified headless and
   confirmed in-editor by the user.
2. **Phase 9 tutorials: STARTED EARLY.** A Tutorials submenu + the first two
   movement tutorials. One known bug in T2 (below), deferred to next session at the
   user's request (out of tokens). FIX THAT FIRST.

## Wedge fix (done, 521d9a6)
Three stacked changes in `player.gd` (`_tip_collides_at` + the `_process` falling
block):
- Inset the wedge sample box on x, z AND y (`WEDGE_INSET = 0.05`): boundary corners
  map to the cube's own column (kills a frame-1 false fire), and a snug-fitting cube
  drops in instead of catching the far rim.
- `_wedged` / `_wedge_hold_t` hold state (`WEDGE_HOLD_TIME = 0.8`): a real wedge
  hangs ~0.8s so it is visible before the Fell panel.
- Cap the tip at `TIP_END_ANGLE` and hand to the straight drop BEFORE the wedge
  check runs: a step overshoots 90 deg near the end, and past vertical the low
  corner swings back under the near floor and false-reads as a wedge.

## Tutorial slice (built + committed this session)
New "movement-first" tutorial set in its own submenu. NOTE: this framing diverges
from the task list's Phase 9 ("signature situations, not bare mechanics"); reconcile
the task list later.

Menu flow: main menu "Tutorials" -> `tutorials_menu.tscn` -> pick a tutorial ->
level -> finish -> Esc returns to the MAIN menu (not the submenu; minor, refine later).

Files:
- `main_menu.tscn` / `main_menu.gd`: old "Tutorial 1" button is now "Tutorials" ->
  loads `tutorials_menu.tscn`. Sandbox + Quit unchanged.
- `tutorials_menu.tscn` / `tutorials_menu.gd`: submenu. Buttons "1: Movement",
  "2: Maneuvering", "Back". Add the T3 button here next.
- `levels/tutorial_01_move.tscn`: T1. 1x10 corridor, runs left->right along +X
  (start cell (0,0), finish (9,0)). Bounded by perimeter colliders.
- `levels/tutorial_02_gaps.tscn`: T2. 20x5, weave through 4 single-gap walls. Start
  (0,2), finish (19,0). Gaps alternate top/bottom. Walls = grey StaticBody blocks
  (BoxMesh/BoxShape 1x1x4, mat 0.4,0.4,0.5).

Conventions established:
- **Safety edge** = a level boundary: a collision-only perimeter wall, auto-marked
  by `level.gd` with a red line. `_build_safety_edges` draws the red line where a
  floor cell meets a WALL collider (layer 1) at the neighbor; OPEN void edges get
  nothing (blankness = "you can fall here"). Internal walls sit ON floor cells, so
  they get no red line; only the outer boundary is outlined.
- New levels are cloned from the `level_01_movement.tscn` rig (Player + casts +
  Camera + Level + UI). `level.gd` auto-builds the floor from FloorRect/FloorMissing
  and the safety edges; it reads start from the Player node, end from EndTile.position.
- `level_01_movement.tscn` (27x27 open) is now ORPHANED (nothing links it). Delete
  whenever.

## Open bug: T2 first-move north jump (FIX FIRST)
Repro: in T2 the cube jumps 2 tiles north after its first move, regardless of move
direction. A first move north clips it through the north safety wall into a fall.

Root cause (confirmed): `player.gd:60` defaults `var grid_pos := Vector2i(0, 0)` and
`_ready()` (line 123) never syncs it to the player's authored node position. T2 places
the Player at cell (0,2); grid_pos stays (0,0); the first settle snaps position from
grid_pos (`position = Vector3(grid_pos.x, 0.5, grid_pos.y)`), so z jumps 2 -> 0 (two
north). T1 was immune only because it starts at (0,0). This is latent and affects ANY
level not starting the player at (0,0).

Fix: in `player.gd _ready()`, add (after the node is in place):
    grid_pos = Vector2i(roundi(position.x), roundi(position.z))
Then re-test T2; T1 still starts at (0,0), unaffected.

## Next session
1. Fix the T2 grid_pos bug (one line in `player.gd _ready()`), re-test T2.
2. Build T3: extend-lock 3-tall-pillar bridging. ~1x20 corridor: ExtendLockZone
   (LOCK, required_dims (1,3,1)) -> ExtendLockGate (open while locked) -> a gap to
   bridge with the locked pillar -> ExtendLockZone (UNLOCK) -> finish. The mechanic
   ALREADY EXISTS: `extend_lock_zone.gd` (LOCK arms when footprint+dims match a
   required cuboid; UNLOCK releases when the cuboid covers its cell) and
   `extend_lock_gate.gd` (open/green while `player.is_extend_locked()`, else
   closed/red). See `mechanics_sandbox.tscn` for placed Zone + Gate examples and the
   Gate sub-resources (BoxMesh_Gate 0.4x1.5x3, Mat_Gate red-transparent).
3. Add the T3 button to `tutorials_menu`.

## Verify recipe (headless, Godot CLI at ~/.local/bin/godot, v4.6)
- Parse-check: `godot --headless --editor --quit 2>&1 | grep -E "SCRIPT ERROR|Parse Error|SHADER ERROR"`
- Smoke-load: `godot --headless --quit-after 60 res://<scene> 2>&1 | grep -iE "ERROR|nil|invalid"` (filter vulkan/driver/audio noise)
- Exit code is 0 even on errors; always grep.

## Carried from earlier (unchanged)
- Phase 8 D (juice), E (audio): not started. F parked (grow tall, pre-spawn flythrough).
- Camera stays put during a fall; cube exits the bottom (slice D will refine: follow
  Y, fog, fade). No fall SFX (cluster E).
- Stale enemy path / search-through-corner / pursuit direct-line `_move_toward` /
  unused WallRay nodes / `DEBUG_DETECTION = true` / tall-pillar false blend / cover
  counts the perimeter / two scenes diverge / LoS centre-to-centre per cell: all
  carried from previous handoffs, all unchanged.

## Memory notes worth checking
- Read HANDOFF.md first at session start.
- Active verbs (sprint/dodge/knock) are cube-only; extension is a positional
  commitment for motion but NOT a safety lock (extending into instability is allowed;
  the cube falls).
- No Co-Authored-By trailer; no em/en dashes; commit at session end or on request.
  Transform3D row-major; ink/water binary cleanse; GDScript inference with untyped
  arrays needs annotation.
