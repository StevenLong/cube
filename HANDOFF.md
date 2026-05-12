# Handoff - 2026-05-12

## Where we are
Phases 1-4 complete. Phase 5 (Environmental Detection) nearly done — only
water-puddle dilution remains. Enemy now follows footprint trails through
a dedicated INVESTIGATE state, scans 360° while alert, and has math-based
cone vision with a ground-projected visual indicator. Arena expanded to
30×30 with perimeter walls and a 4-corner sphere patrol.

Local commit `a06a415` covers this session's work but is NOT pushed —
WSL machine has no GitHub credentials. Set up next session before doing
more work.

## Completed this session
- **Slice 4 — enemy sees footprints (INVESTIGATE state)**: enemy reads
  player's footprint list, filters by range + facing cone (60°/5u) +
  LoS raycast (`collide_with_areas = false` to ignore the player's own
  Area3D). On finding a print, enters INVESTIGATE, walks to the print,
  calls `player.consume_footprints_in_cell(cell)` on arrival — the
  print pops off the ground. Scans for next visible print; follows the
  trail. Times out after 3s with no new evidence → PATROL.
- **Player detection rewrite**: original single forward `RayCast3D` was
  too narrow — cube could stand directly beside the sphere and not be
  detected. Replaced with math-based cone scan + LoS raycast (80°/8u
  by default). Same pattern as footprint detection. The RayCast3D node
  is still in main.tscn but unreferenced; can be deleted any time.
- **Power-mode framing**:
  - PATROL: forward cone (80°/8u) + audio.
  - SUSPICIOUS: forward cone, slow creep (0.5×).
  - INVESTIGATE: 360° scan for both player and footprints, walks at base
    speed (1.0×). PURSUIT_LOSE timeout drops into INVESTIGATE (not
    SUSPICIOUS) so the sphere actively hunts.
  - PURSUIT: tracks player at 1.5×.
- **Visual sensor indicator**: ground-shader-projected cone in front of
  the sphere. Colour matches state; alpha rises with alertness; expands
  to a full circle during INVESTIGATE. Same `VIEW_RADIUS`/`VIEW_CONE_COS`
  drive both detection and visual, so tuning one updates the other.
- **Smooth rotation**: all movement goes through `_move_toward(target,
  delta, speed_mult)`. Sphere yaws at `TURN_RATE` rad/s toward the
  target, holds position while more than `TURN_LEAD_THRESHOLD` (PI/6)
  off so it doesn't slide sideways during the turn. Replaces snap
  `look_at` at every waypoint.
- **Puddle deposit fix**: prints no longer deposited while the cube is
  over a puddle. Removed the entry-cell streak deposit from
  `_on_puddle_entered`; added `_puddle_overlap_count > 0` guards to
  `_maybe_deposit_footprint` and `_deposit_streak_cell`.
- **Larger arena**: ground 20×20 → 30×30. Shader UV scaling and offset
  updated. Added 4 perimeter walls (`PerimeterN/S/E/W`) as StaticBody3D
  with new `BoxMesh_PerimeterNS/EW` and matching shapes. Inner
  playable cells ≈ -13..13.
- **Sphere patrol path**: 4-corner rectangle (10,-8) → (-10,-8) → (-10,8)
  → (10,8) at y=0.4. Set as the script default; scene has no override.

## Bugs found and fixed
- **`Cannot infer the type of "positions"`**: `_player` was typed
  `Node3D`, so the parser couldn't see `get_footprint_positions`'s
  return type. Annotated `var positions: PackedVector2Array` at the
  call site.
- **`_last_seen_pos.y` tilting the enemy**: footprint world Y = 0.05;
  using that directly tilts the sphere's look_at down and pulls the
  raycast off-axis. Now pegged to `position.y` everywhere
  `_last_seen_pos` is set from a footprint or PURSUIT_LOSE.
- **Sphere "stuck looking at print forever"**: the closest-visible-print
  was itself once arrived → kept resetting timer. Fixed by consuming
  prints on arrival (now they're gone from the list) + INVESTIGATE
  timeout.

## Phase status
- [x] Phase 1 — core movement
- [x] Phase 2 — extension
- [x] Phase 3 — detection and hiding
- [x] Phase 4 — first playable level
- [ ] Phase 5 — environmental detection
  - [x] Ink puddle object
  - [x] Ink mark on cube side on contact, splash sound
  - [x] Ink footprints on ground from marked side
  - [x] Suspicious state triggered by enemy seeing footprints
    (implemented as INVESTIGATE; SUSPICIOUS now reserved for
    audio/brief-visual)
  - [ ] Water puddle dilutes ink (10 steps to 3)
  - [x] Enemy reacts to movement noise

## Tunable constants worth knowing (enemy_sphere.gd)
- `VIEW_RADIUS` 8.0, `VIEW_CONE_COS` 0.766 (80° cone) — player vision
- `FOOTPRINT_VIEW_RADIUS` 5.0, `FOOTPRINT_VIEW_CONE_COS` 0.866 (60°)
- `INVESTIGATE_TIMEOUT` 3.0s, `SUSPICIOUS_TIMEOUT` 2.0s,
  `PURSUIT_LOSE_TIMEOUT` 1.5s
- Speed mults: PATROL 1.0, SUSPICIOUS 0.5, INVESTIGATE 1.0, PURSUIT 1.5
- `TURN_RATE` 5.0 rad/s, `TURN_LEAD_THRESHOLD` PI/6
- `FOOTPRINT_VISIT_DIST` 0.6u (consume radius)

## Deferred / known limitations
- **Sphere doesn't navigate around walls**. Patrol path is straight-line
  clear of the 3 interior walls, but INVESTIGATE can drag the sphere
  toward a print behind an interior wall and it'll clip through. Next
  task: navmesh or A* on the grid.
- **GitHub auth not set up on this WSL** — commits stay local until
  configured (`gh auth login` or switch remote to SSH).
- **Unused `RayCast3D` on Enemy** in main.tscn (replaced by math). Can
  be deleted whenever.
- **Per-face cube ink visualisation** still parked. Cube tints
  whole-body when any face is marked.
- **No fail-state results screen**: enemy contact instantly reloads.
- **Extended-cuboid footprints**: one deposit at cuboid centre, not
  per contact cell.

## Polish backlog (parked)
- sfx + particles for end/caught
- smooth respawn camera transition
- spawn elevator animation
- symmetric "Caught" results panel
- per-face ink visualisation on cube

## Phase 5 next step (the only one left)
**Slice 5 — water dilution**:
- Water puddle object (cyan, transparent visual). Mirror the ink puddle
  structure (MeshInstance3D + Area3D, on a new `water_puddles` group).
- On contact with a marked face, reduce a per-face "ink steps remaining"
  counter from 10 to 3.
- Each footprint deposit decrements that face's counter; at 0 the mark
  is cleared (face no longer prints).
- Per-face counter array on the player (parallel to `_face_marks`).

## After Phase 5
- **Sphere pathfinding** (deferred from this session). Either NavMesh3D
  or grid-based A* with the existing wall colliders as blockers.
  Probably easier to go grid-A* given the integer cell pitch.
- More level content / per-mechanic challenge levels.

## Key files
- `player.gd` — tumble + extension + dodge + blend + face tracking + ink
  + audio waves + footprint API (`get_footprint_positions`,
  `consume_footprints_in_cell`)
- `enemy_sphere.gd` — PATROL/SUSPICIOUS/INVESTIGATE/PURSUIT,
  math-based cone vision, footprint trail logic, smooth rotation,
  cone shader uniform updates
- `level.gd` — state machine (READY/PLAYING/COMPLETE), stats, end tile,
  pause
- `camera_controller.gd` — fixed follow + tilt; `process_mode = ALWAYS`
- `main.tscn` — Player + colliders + audio, Enemy, interior Walls,
  Perimeter walls (N/S/E/W), Ground (30×30), StartTile, EndTile + Area,
  Puddle + Area, Level, UI
- `shaders/grid_ground.gdshader` — grid + waves + vision cone +
  footprints, all in fragment

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
| Quit | — | Escape |

## Memory notes worth checking
- Transform3D is row-major in .tscn
- GDScript can't infer types from untyped Array element access (and
  often can't from `Node3D._player.method()` either — annotate the var
  explicitly)
- Commit/push cadence: end of session
- Task list at `/home/steven_long/game-dev/Cube Game Tasks.md` (was
  `Documents/game-dev/...` on the Windows side; the WSL repo is the
  canonical copy now)

## Task list source
`/home/steven_long/game-dev/Cube Game Tasks.md` — updated this session
to reflect actual completion state (committed + pushed in that repo).
