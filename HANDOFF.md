# Handoff, 2026-05-26

## Where we are
Phase 8 (Presentation and Mechanic Completeness) progressing. Last session
landed clusters **A (extended-state mechanic gaps)** and **B (auto-blend)**.
This session was a **deep-clean follow-up pass**: every reported bug got
fixed, a parallel-bug scan found three more in the same family (extended
vs cube parity), those got fixed too, and the blend visual got the polish
it was missing. All in-editor verification was done as we went; remaining
work in Phase 8 is unchanged (clusters C, D, E).

Headless Godot 4.6 CLI is now installed in WSL at `~/.local/bin/godot`,
used for parse-check + scene smoke-load before handing back changes.
Does not replace in-editor verification (no rendering). Setup details in
the memory file `project-godot-headless`.

## The Phase 8 backlog (task list has canonical checkboxes)
- **A. Extended-state mechanic gaps**: DONE (last session + this session's deep-clean).
- **B. Blend redesign (auto-blend + visual polish)**: DONE (this session added delay/fade/wall-color).
- **C. Floating void world**: no edge walls, grid edge = level edge, depth under floor, fall off. NOT STARTED. Foundational + biggest visual payoff.
- **D. Animation / juice**: extend/collapse anim, spawn rise, death, completion, intro/outro. NOT STARTED. Spawn/death/complete read best after C.
- **E. Audio**: more SFX, music. NOT STARTED.
- **F. Parked**: grow tall to see over objects, pre-spawn demo flythrough.

## Completed this session

### Cluster A deep-clean (extended/cube parity)
Each fix follows the same pattern: replace 1x1 center-cell behavior with
full-footprint behavior, mirroring what the ink fix already did last session.

- **Extension is a shape-change event** (player.gd, `_try_extend`): now
  calls `_check_ink_contact_footprint`, `_check_water_contact_footprint`,
  `_maybe_deposit_footprint`, then emits `move_settled`. Fixes three bugs at
  once: growing onto ink wasn't marking the face, growing onto water wasn't
  cleansing, and the level wouldn't complete when an extended bar covered the
  end tile without a follow-up tumble.
- **Water cleanse is cell-based** (player.gd): replaced `_water_overlap_count`
  + the two `_on_water_*` handlers with a `_water_cells` dictionary built at
  `_ready` (same loop as ink, via shared helper `_collect_puddle_cells`). New
  `_check_water_contact` (single-cell, dodge) and `_check_water_contact_footprint`
  (tumble/extend) called at the same sites as the ink checks. Refactored
  `_check_water_cleanse` into `_try_cleanse` shared by both entry points.
- **Enemy contact: full-footprint DetectionArea** (player.gd, `_update_mesh`):
  the DetectionArea's `BoxShape3D` is duplicated at `_ready` (otherwise it's
  shared with walls via `BoxShape3D_1`) and resized + re-posed every frame to
  match the visual cuboid. An enemy touching any cell of the extended footprint
  now triggers caught. Was: only the 1x1 base cell registered.
- **Enemy LoS: per-cell raycasts** (enemy_sphere.gd, `_is_seeing_player`):
  iterates the player's footprint cells; for each runs the same range + cone
  + LoS test, returns true on the first that passes. A bar's end poking out
  of cover is now detectable when the base cell's ray is occluded by a wall.
  Added `_last_visible_sample` so `_last_seen_pos` captures the cell that was
  actually visible, not the player's center; investigation pathing aims at
  the exposed end, not the hidden base.
- **Nav block while hiding** (player.gd + enemy_sphere.gd, `_cell_blocked`):
  new `is_hiding` flag on Player (at-rest + in cover + not animating, regardless
  of fade phase). Enemy treats hiding-player cells as walls; `_find_path`'s
  existing goal-blocked fallback snaps to the nearest open neighbour, so
  investigating a noise at the player's cell ends adjacent to the footprint,
  not on it. Gated on `is_hiding` not `is_blending` so the block engages the
  moment the player settles, before the 0.4s visual fade completes.

### Cluster B blend polish (player.gd)
- **Delay + fade**: blend driven by `_blend_phase` (0→1). Rises over
  `BLEND_ENTER_TIME = 0.4s`, falls over `BLEND_EXIT_TIME = 0.15s`. `is_blending`
  (enemy invisibility) flips true only at full phase; the slower enter is the
  fade, the faster exit means peeking out is detectable almost instantly.
- **Camouflage colour**: `_sample_cover_color` walks the footprint perimeter
  and reads the first `StandardMaterial3D.albedo_color` it finds on a touching
  wall. Cached in `_cover_color` on the wants-blend transition. Fallback
  `COLOR_BLENDING` if no usable material. `_player_material.albedo_color =
  _base_color().lerp(_cover_color, _blend_phase)`.
- **Phase decays during animations**: lifted the blend update before the
  `_dodging`/`_tumbling`/`_bumping` early-returns, with `is_animating` forcing
  `wants_blend` false. The cube visibly fades back out as motion starts
  instead of freezing mid-fade.
- **Refactored** `_current_color` → `_base_color` (no blend branch); the lerp
  applies in `_process`.

### Footprint visual (slice 2, player.gd + shaders/grid_ground.gdshader)
- Shader: each footprint draws as a 0.8u soft-edge tile (rectangle-distance
  with half-extent 0.4 and a 0.1u smoothstep falloff), so adjacent same-deposit
  cells tile into a continuous oblong matching the down-face shape. A 1x3 bar
  deposit reads as one 3x1 mark, not three separate dots.
- `_deposit_streak_cell` simplified to one footprint per slide cell (was 4
  sub-samples). Removed `SLIDE_SUBSAMPLES` and `_slide_dir` (dead).
- Data model unchanged (`_footprints` still position+alpha), so the enemy's
  `get_footprint_positions` and `consume_footprints_in_cell` still work.

### Sandbox (mechanics_sandbox.tscn)
- Added `GapWallW` at (-7, 0.5, -5) and `GapWallE` at (-3, 0.5, -5): two walls
  three cells apart along x. A horizontal bar at (-5,-5) with EXT_LEFT=1 and
  EXT_RIGHT=1 plugs the gap; opposite-column-pair rule triggers blend. Test
  spot for the bar-plug-blend case that previously had nowhere to verify.

## Watch items / known edge cases
- **Stale enemy path through a freshly-hiding cell**: a path computed BEFORE
  the player started hiding stays valid; the enemy keeps walking along it.
  Investigates only re-path on new footprint detection, not on `is_hiding`
  changes. Rare in practice (the user-reported scenario is correctly fixed).
  Close it later by adding a per-step `_cell_blocked` check in `_follow_path`,
  or wiring an "is_hiding changed" signal that forces a re-path.
- **Search-through-corner**: when a noise originates in a spot only reachable
  through an impassable wall-corner gap, the enemy walks to the closest
  reachable cell adjacent to the corner and "stares through" it. Decided this
  is acceptable (it IS investigating where it heard the noise) and a
  **level-design** concern: avoid hiding spots behind corner gaps when
  building levels. No code fix.
- **Wall-colour camouflage caches at blend entry**. If the player extends to a
  cell with a differently-coloured wall while already hiding, the cached
  `_cover_color` doesn't refresh. Minor; only matters with multi-coloured
  walls in the same shape. Upgrade to per-frame sampling later if needed
  (cheap; 4-8 physics queries).
- **Pursuit's direct-line `_move_toward`** doesn't consult `_cell_blocked`.
  But pursuit only runs while the enemy sees the player, which requires
  is_blending = false. Player can't enter the blend ramp during pursuit
  (visible to enemy), so this is a non-issue in normal flow.
- **Unused WallRay nodes** (`WallRayN/S/E/W` under Player in scenes): still
  dead from last session. Delete in-editor when convenient.
- **DEBUG_DETECTION := true** in enemy_sphere.gd (top-left readout): to drop
  at end-of-phase tuning.
- **Tall-pillar false blend**: cover sensed at ground level, so a 3-tall
  pillar behind 1-tall walls would wrongly blend. Parked for the wall-height
  / void pass (cluster C territory).
- **Cover counts the perimeter** (layer 1). Moot once C removes edge walls.
- **Two scenes still diverge**: main.tscn (with enemy) and mechanics_sandbox.tscn
  (enemy-free). New props/nodes go in both, or pick one as canonical.
- **LoS now multi-cell**, but still a centre-to-centre ray per cell. A bar's
  end could still thread a corner for a frame. Wider rays not needed for now.

## Verification status
All fixes verified in-editor by the user as we went. The corner-search
behaviour was reviewed and accepted as level-design territory. Nothing
outstanding from this session.

## Key files
- `player.gd`: `class_name Player`. Tumble (footprint-aware wall collision), extension
  (wall-blocked + shape-change side effects), dodge, **auto-blend with phase
  delay/fade + wall-colour sampling (`_is_in_cover`, `_sample_cover_color`,
  `_blend_phase`, `is_hiding`)**, ink + water (cell-set + footprint-aware
  contact, shared `_try_cleanse`), audio waves, footprints (per-cell tile),
  water cleanse, **cube-only wall-knock + won't-fit lean/thud**,
  collapse-on-dodge, extend-lock state + grid accessors (`footprint_covers`,
  `get_dimensions`, etc.), **DetectionArea resized to footprint** (`_update_mesh`,
  duplicates shape at `_ready`).
- `enemy_sphere.gd`: PATROL/SUSPICIOUS/INVESTIGATE/PURSUIT, graduated detection,
  detection-driven cone, alert glyph, noise -> investigate, footprint follow,
  A* nav with **hiding-player cells blocked** (`_cell_blocked`), **multi-cell LoS**
  (`_is_seeing_player`, `_last_visible_sample`), state hum + stings, debug
  readout (temp).
- `level.gd`: state machine (READY/PLAYING/COMPLETE/CAUGHT); completion via end-tile
  Area3D OR `footprint_covers(_end_cell)`; null-guards the enemy.
- `extend_lock_zone.gd` / `extend_lock_gate.gd`: grid-exact lock zone + ghost
  blueprint + lock-driven gate.
- `shaders/grid_ground.gdshader`: grid + waves + vision cone + **footprint tile
  rendering** (soft-edge rectangle, adjacent cells tile into oblong) + LoS fog.
- `main.tscn` (with enemy) / `mechanics_sandbox.tscn` (enemy-free copy, includes
  gap-plug test walls at z=-5).
- Design: `game-dev/Cube Game.md` (v0.2, hiding section updated). Tasks:
  `game-dev/Cube Game Tasks.md` (Phase 8 = Presentation/Mechanic Completeness).

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

Blend is automatic (stand still in cover). Jump cut by design. Won't-fit
lean and knock reuse the move input.

## Tuning backlog (end-of-phase pass)
- **Blend**: `BLEND_ENTER_TIME` 0.4, `BLEND_EXIT_TIME` 0.15. Footprint tile
  half-extent 0.4 and falloff 0.1 (hardcoded in `grid_ground.gdshader`).
- Won't-fit bump: `BUMP_DURATION` 0.25, `BUMP_ANGLE` PI/10 (push toward
  ~PI/5 for a visible distance gradient), `BUMP_CLEARANCE` 0.15, thud
  volume 0.35 / pitch 0.5.
- Detection (`DETECT_*`), cone (`CONE_*`), glyph, hum/stings, footprints
  (`FOOTPRINT_FADE_TIME` 12.0), knock (`KNOCK_RADIUS` 10.0, `KNOCK_COOLDOWN`
  0.4), extend-lock (`GHOST_*`), nav (`TURN_*`, `CORRIDOR_HYSTERESIS`),
  fog `dark_factor`.

## Memory notes worth checking
- Read HANDOFF.md first thing at session start.
- Godot headless CLI at `~/.local/bin/godot` (WSL only). Parse-check via
  `godot --headless --editor --quit 2>&1 | grep -E "SCRIPT ERROR|Parse Error"`.
  Exit code is 0 even on parse errors so always grep.
- Active verbs (sprint/dodge/knock) are cube-only; extension is a positional
  commitment. Apply to any new active ability.
- Design v0.2 (reactive-stealth, shape-vs-exposure, jump cut).
- No Co-Authored-By trailer; no em/en dashes; commit at session end or on
  request. Transform3D row-major; ink/water binary cleanse; GDScript inference
  with untyped arrays.
