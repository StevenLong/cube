# Handoff, 2026-05-30

## Where we are
Phase 8 cluster **C (floating void world)** slice 2 in progress with one
known design bug. Slice 1 done and polished last session. Slice 2 brought
in the fall mechanic, stability rules, tipping animation, and a wedge
check. The wedge logic is correct in geometry but emits the fail signal
too eagerly: `fell.emit()` fires the moment a wedge is detected, which
pauses the tree on the same frame and pops the results panel before the
tip or wedge is ever visible. Fix is small but design-touched; deferred
to next session along with a roundi sanity check that may also be
contributing.

Slice 3 (build a real demo level shape) is still open and unchanged.

Verified headless: parse-check + smoke-load of all three scenes after
every change in this session. In-editor verification of the fall family
done piecewise by the user; the wedge regression was caught visually.

## The Phase 8 backlog
- **A. Extended-state mechanic gaps**: DONE.
- **B. Blend redesign**: DONE.
- **C. Floating void world**:
  - Slice 1 (data model + per-tile render + perimeter visuals stripped +
    red safety lines + extension/nav rewired): DONE.
  - Slice 1 polish (Tron neon edges, doubled slab height, lighter void):
    DONE.
  - Slice 2 (real fall behavior): IN PROGRESS. Center-of-gravity
    stability, tumble + extension allowed over void, tip animation,
    wedge detection all in. **Open bug**: wedge fires the fail signal
    instantly, hiding the tip and wedge from the player. Details below.
  - Slice 3 (build a non-trivial demo shape): NOT STARTED.
- **D. Animation / juice**: NOT STARTED.
- **E. Audio**: NOT STARTED.
- **F. Parked**: grow tall, pre-spawn demo flythrough.

## Completed this session

### Fall mechanic (slice 2 v1)
- New `Player.fell` signal, `Level.State.FELL`, mirror of `CAUGHT` with
  title "Fell". Restart key handler covers FELL like the other end states.
- `_falling` + `_fall_vel` + `FALL_GRAVITY` (25 units/s^2) + `FALL_END_Y`
  (-6.0) on Player. Falling block in `_process` skips blend / input /
  animation; gravity Y until threshold, then `fell.emit()`.
- `_check_fall_at_settle` called after every settle event (tumble end,
  dodge end, extension, collapse). Idempotent so a second settle inside
  the same fall doesn't restart it.

### Stability model
- `_is_stable_at(grid_pos, ext)`: cuboid is stable iff its geometric
  centre sits strictly inside the axis-aligned bounding box of supported
  (floor) footprint cells. Strict so a 1x2 with one cell over void
  (centre exactly on the boundary) counts as a tip.
- Falls through every common bridge / overhang / knife-edge case
  consistently with user spec:
  - 1x3 bridging (both ends supported, void centre): stable.
  - 1x3 with only centre supported: stable.
  - 1x3 with end-only support: unstable.
  - 1x2 with one cell over void: unstable (knife edge).
- Bounding box not convex hull: loose for diagonal supports, but every
  common case lands the same answer either way.

### Extension / tumble void rules (revised by user)
- Initial slice-2 design blocked unstable extensions ("positional
  commitment"). User flipped this: extensions are now allowed even if
  unstable, and the resulting unstable shape falls, same as a tumble.
  Rationale: removes an arbitrary asymmetry with tumble, opens up the
  "self-yeet" move, gives the player faster feedback on bad gap
  judgement.
- `_extend_side_clear` and `_gap_ahead` reverted to `_extend_cell_clear`
  (wall-only); `_cell_buildable` is gone. `_begin_tumble`'s slice-1
  floor-block is gone. The settle check handles all cases.
- Settle-time side effects (`_play_step`, ink / water contact, footprint
  deposit, `move_settled.emit`) are gated on `not _falling` so the cube
  doesn't make footstep noise on a step into air or fire level
  completion mid-fall.

### Tipping animation
- When a settle puts the cuboid in an unstable state and any footprint
  cell IS supported, the cube tips around the support-bbox edge nearest
  the centre of mass. Pivot point + tip axis computed in `_setup_tip`;
  axis is horizontal, perpendicular to the overhang direction.
- Knife-edge case (centre exactly on the support boundary, e.g., 1x2
  with one cell over void) uses footprint-centre vs support-centre as
  the tip direction; `TIP_INITIAL_VEL = 1.5 rad/s` gives the equilibrium
  a kick so it doesn't stall.
- Constant angular acceleration `TIP_ANGULAR_ACCEL = 25.0 rad/s^2`.
- At `TIP_END_ANGLE = PI/2` the cube has cleared the edge; transitions
  to straight gravity drop, inheriting the tangent's downward component
  as initial `_fall_vel` for a smooth blend.
- With no support at all (cube tumbled or collapsed onto void): no
  pivot, straight drop, no tip.

### Wedge detection (the bug)
- `_tip_collides_at(angle)` walks the cuboid's 8 corners, rotates them
  to the test angle around the pivot, and returns true if any corner
  dips below y=0 (floor surface) at an xz on a floor cell. Geometry is
  correct: cuboid is convex so corners bound its lowest reach.
- Triggers in real configurations like a tall+deep cuboid tipping back
  into a 1-cell gap with floor behind it: the top-rear corner reaches
  floor on the far side at roughly 63 degrees, before TIP_END_ANGLE.
- **Bug**: when collision is detected, `fell.emit()` fires on the same
  frame. Level's `_enter_fell` immediately pauses the tree and shows the
  results panel. Player never sees the tip or the wedge. From the user's
  POV: as soon as the unbalanced state begins, the game ends.

## Open items / next session

### Wedge bug fix (highest priority before slice 3)
Two things probably need to happen together:

1. **Hold the wedge before emitting.** Add a `_wedged` state that holds
   the cube frozen at the wedged angle for ~0.7-1.0s with the tree
   running, then emits `fell`. Could be a simple timer or a frame
   countdown. Same shape as the straight-drop path's FALL_END_Y delay
   that the player implicitly sees as "cube falls out of view, then
   panel".
2. **Audit cell mapping for spurious immediate detections.** `roundi(1.5)`
   in Godot 4 may not return what the wedge check assumes. The bottom-rear
   corner of a tipping cuboid sits exactly on a cell boundary at angle 0
   and moves slightly past it on the first frame; if `roundi` flips the
   wrong way, the corner maps to the supported cell, registers a floor
   hit, and the wedge fires immediately. Verify what `roundi(0.5)` and
   `roundi(1.5)` actually return in Godot 4, and either:
   - switch to `int(floor(x + 0.5 + epsilon))` with `epsilon` biased in
     the corner's motion direction, or
   - inset the corner sample by a small amount toward the pivot before
     rounding, or
   - exclude cells inside the support bbox from the wedge hit set (those
     cells are the ones the corner is rotating AWAY from, so they
     shouldn't register).

The combination should give the player a visible tip + wedge before the
panel.

### Test recipe once fixed
Sandbox setup (will need a `FloorMissing` node added in editor):
- `FloorMissing` at `(0, 0, 2)` size `(1, 1)` for a single-cell gap at
  cell `(0, 2)` running between start cells and the existing walls.

Cases to step through:
1. Cube tumble onto the void → straight drop, "Fell" panel.
2. Cube dodge OVER the void → safe; dodge that lands ON the void → falls.
3. Extend right at `(1, 0)` toward void at `(2, 0)`: now creates a 1x2
   unstable → tips into the hole.
4. Build a 1x2 left-bar from a cell two south of the void, then extend
   into the void cell: 1x3 with both ends supported → stable bridge.
5. Get tall (EXT_UP twice), tumble across the gap: lands as a horizontal
   1x3 spanning the gap → bridge.
6. **The wedge case**: build a 1x2x2 (2 deep + 2 tall) two cells north
   of the gap; tumble south once; the bar should tip back into the gap
   and wedge against the floor north of it for ~1s, then "Fell".

### Smaller open items
- `roundi` behavior verified in Godot 4 (small unknown; doc check needed).
- Tip axis can be diagonal in pathological 2x2 cases with corner-only
  support; current code handles it but the wedge corner check loops
  rotate around an arbitrary axis. Should still be correct but untested
  visually.
- Camera stays put during the fall; cube exits view from the bottom.
  Slice D juice will refine this (follow Y, fog, fade).
- No fall SFX. Cluster E will add it.
- Stale enemy path / search-through-corner / pursuit's direct-line
  `_move_toward` / unused WallRay nodes / `DEBUG_DETECTION = true` /
  tall-pillar false blend / `Cover counts the perimeter` / two scenes
  diverge / LoS centre-to-centre per cell: all carried from previous
  handoffs, all unchanged.

## Key files (slice 2 additions in **bold**)
- `player.gd`: `class_name Player`. Tumble, extension (now allowed
  unstable), dodge, auto-blend, ink + water, audio waves, footprints,
  collapse-on-dodge, extend-lock state. **`fell` signal**;
  **`_is_stable_at`, `_check_fall_at_settle`, `_begin_fall`,
  `_setup_tip`, `_tip_collides_at`**; **falling block in `_process`
  handling tip + drop + wedge**; **settle-time side-effect gates on
  `not _falling`**.
- `enemy_sphere.gd`: PATROL/SUSPICIOUS/INVESTIGATE/PURSUIT, graduated
  detection, A* nav via `Level.is_floor` in `_cell_blocked`. Unchanged
  this session.
- `level.gd`: `class_name Level`. **`State.FELL` + `_enter_fell` +
  `_on_player_fell`; restart key handler now covers FELL.** Floor data,
  safety edges, completion logic otherwise unchanged.
- `floor_rect.gd` / `floor_missing.gd` / `FloorTile.tscn` /
  `grid_ground_material.tres` / `shaders/grid_ground.gdshader`: slice 1
  + polish. Unchanged this session.
- `main.tscn` / `mechanics_sandbox.tscn` / `levels/level_01_movement.tscn`:
  slice 1. Unchanged this session.

## Input map
| Action | Controller | Keyboard |
|--------|-----------|---------|
| Move | D-pad / left stick | WASD / arrows |
| Wall-knock (cube only) | tap move into a wall | tap move into a wall |
| Sprint | R2 | Left Shift |
| Dodge (cube) / Collapse (while extended) | Circle | Space |
| Extend mode | R1 | E |
| Extend depth fwd/back | L1 / L2 (+ R1) | Q / C |
| Camera tilt | Right stick Y | R / F |
| Back to menu / quit | (none) | Escape |

Blend is automatic (stand still in cover). Jump cut by design.

## Tuning backlog
- **Fall**: `FALL_GRAVITY` 25.0, `FALL_END_Y` -6.0. ~0.7s straight drop.
- **Tip**: `TIP_ANGULAR_ACCEL` 25.0, `TIP_INITIAL_VEL` 1.5,
  `TIP_END_ANGLE` PI/2. ~0.3s tip then drop.
- **Wedge hold (proposed)**: 0.7-1.0s freeze before `fell.emit()`.
- **Floor / void contrast** (slice 1): WorldEnvironment background
  `(0.2, 0.2, 0.24)`, top_base_color `(0.06, 0.06, 0.12)`, side_color
  `(0.04, 0.04, 0.08)`. Tron neon edge uniforms tuned in `.tres`:
  `line_core_width` 0.005, `line_falloff_width` 0.5, `line_falloff_exp`
  10, `line_glow_strength` 1.5; side core 0.01 with zero glow.
- **Safety edge** (slice 1): `SAFETY_EDGE_Y` 0.02, `_PERP` 0.04, `_VERT`
  0.02, `_ENERGY` 0.6.
- Blend: `BLEND_ENTER_TIME` 0.4, `BLEND_EXIT_TIME` 0.15.
- Won't-fit bump: `BUMP_DURATION` 0.25, `BUMP_ANGLE` PI/10,
  `BUMP_CLEARANCE` 0.15.
- Detection, cone, glyph, hum / stings, footprints, knock, extend-lock,
  nav, fog: untouched, see previous handoff for the list.

## Memory notes worth checking
- Read HANDOFF.md first thing at session start.
- Godot headless CLI at `~/.local/bin/godot`. Parse-check via
  `godot --headless --editor --quit 2>&1 | grep -E "SCRIPT ERROR|Parse Error|SHADER ERROR"`.
  Smoke-load via `godot --headless --quit-after 30 <scene>` and grep for
  `ERROR|error`. Exit code is 0 even on errors, always grep.
- Active verbs (sprint / dodge / knock) are cube-only; extension is a
  positional commitment for MOTION (no dodge while extended) but NOT a
  safety lock (extending into an unstable state is allowed; cube falls).
  This is a deliberate revision from the slice-1 reading.
- Design v0.2 (reactive-stealth, shape-vs-exposure, jump cut).
- No Co-Authored-By trailer; no em / en dashes; commit at session end or
  on request. Transform3D row-major; ink / water binary cleanse; GDScript
  inference with untyped arrays.
