# Handoff, 2026-05-25

## Where we are
Phase 7 (Reactive Stealth Depth) was already complete. This session opened a new
**Phase 8: Presentation and Mechanic Completeness** (in the task list, ahead of the
old tutorials phase, which is now Phase 9) and worked through the first two clusters:
**A (extended-state mechanic gaps)** and **B (blend redesign)**. All code is on
`main` but UNCOMMITTED at the time of writing this paragraph (commit happens at
wrap-up). Nothing has been run in Godot this session (no Godot binary in WSL), so
everything below needs an in-editor verification pass.

## The Phase 8 backlog (task list has the canonical checkboxes)
Clusters, in the order we planned them:
- **A. Extended-state mechanic gaps** — DONE this session.
- **B. Blend redesign (auto-blend)** — DONE this session.
- **C. Floating void world** — no edge walls, grid edge = level edge, depth under
  floor, fall off level. NOT STARTED. Foundational + biggest visual payoff.
- **D. Animation / juice** — extend/collapse anim, spawn rise, death, completion,
  intro/outro. NOT STARTED. Spawn/death/complete read best after C.
- **E. Audio** — more SFX, music. NOT STARTED.
- **F. Parked** — grow tall to see over objects, pre-spawn demo flythrough.

## Completed this session

### Cluster A — extended-state mechanic gaps (player.gd, level.gd)
- **Extended ink + footprints**: ink contact on a tumble landing now checks the whole
  resting footprint (`_check_ink_contact_footprint`), and footprint deposit lays a
  print on every off-ink cell under the down face (`_maybe_deposit_footprint`
  rewritten), so a marked bar leaves a continuous trail. Removed the orphaned
  `_puddle_overlap_count` the per-cell ink test made dead.
- **Extended level-complete** (level.gd): completes when the footprint *covers* the
  end cell at rest (`footprint_covers(_end_cell)`), not just when the 1x1 base-cell
  Area3D overlaps it. Cube/dodge-through path unchanged.
- **Extended bump / wall-knock redesign** (the big one, see Design Decisions): knock
  is now cube-only; an extended shape that cannot tumble does a "won't-fit" lean +
  thud instead of knocking.

### Cluster B — auto-blend (player.gd, project.godot)
- Blend is automatic: `is_blending = (no move input) and _is_in_cover()`, computed
  every at-rest frame (so it stays fresh even while extending). No button, no
  movement-blocking early return (a move just ends blend; collapse still works while
  blended).
- Removed the unused `blend` input action from project.godot.
- **Cover rule rewritten to full-footprint "opposite pair"** (see Design Decisions):
  `_is_in_cover` + `_column_walled` / `_row_walled`. Replaced `_count_covered_sides`
  and the `_wall_rays` array (both removed).

## Design decisions locked this session
1. **Knock is a cube-only ability**, consistent with sprint and dodge (both already
   cube-only). Rule for the player: "extend to commit to a shape, collapse to act."
   An extended shape pressing into a wall it cannot tumble into gets won't-fit
   feedback (lean toward the move, scaled by free space so it never clips the wall,
   then rock back, plus a soft non-alerting thud). No noise wave (not a distraction).
2. **Auto-blend**: hiding is "freeze in cover," no button. (Updated Cube Game.md.)
3. **Hiding is purely emergent (no designated spots) and uses the "opposite pair"
   rule**: you blend when one pair of opposite sides is fully walled (every adjacent
   cell on both sides is a wall). This is the formalization of "looks like part of a
   flat wall." One pair is enough, so plugging a gap (2 covered sides) counts; a
   free-standing or single-wall cube does not. Consequence (accepted): a cube in the
   middle of a 1-wide corridor blends (same topology as a gap-plug); balanced by
   patrols walking into you. (Updated Cube Game.md Hiding section.)

## Temporary / to remove
- Placeholder **thud** for the won't-fit bump reuses the step waveform (low + quiet,
  `_play_thud`). Replace in the audio pass (cluster E).
- `DEBUG_DETECTION := true` in enemy_sphere.gd (top-left readout) — still to drop at
  the end-of-phase tuning pass, with `_setup_debug_label` / `_update_debug_label` /
  `_state_name`.

## Watch items / cleanup
- **Unused WallRay nodes**: `WallRayN/S/E/W` under `Player` in the scenes are now
  dead (cover no longer uses raycasts). Delete them in-editor when convenient; they
  still tick as enabled raycasts otherwise. Left the .tscn files alone to avoid
  hand-editing both copies.
- **Tall-pillar false blend**: cover is sensed at ground level, so a 3-tall pillar
  behind 1-tall walls would wrongly blend. Parked for the wall-height / void pass.
  Likely resolution: "can't blend while taller than your cover," or factor wall
  heights in.
- **Cover counts the perimeter** (layer 1) as wall, so a cube against the arena edge
  with an opposite wall blends. Becomes moot once C removes edge walls.
- Two scenes still diverge: main.tscn (with enemy) and mechanics_sandbox.tscn
  (enemy-free). New props/nodes must go in both, or pick one as canonical.
- LoS is a single centre-to-centre ray; can thread a wall corner for a frame (only
  grants detection, never a through-wall catch). Widen if it shows up.

## Verification still owed (nothing run in Godot this session)
- A1: extend a bar, tumble through ink then over dry ground → a print on every cell
  under it (continuous trail).
- Bump: extend a pillar flush to a wall, press in → thud, no lean, no clipping. Leave
  one empty cell before the wall → tips in cleanly and rocks back, no clip. A remote
  block (wall ~3 tiles ahead, adjacent clear) → bump, not a knock at empty space.
- A3: extend a bar so only its end overlaps the end tile, settle → completes.
- Cube knock still works: tap a 1x1 into a wall → knock ring at the adjacent wall.
- Blend: 1x1 cube still in a 1-wide slot (opposite walls) → blend-grey, enemy loses
  you; step out → exposed. Bar plugging a gap (2 ends walled) → blends. Cube on a
  single wall or an L-corner (two adjacent, non-opposite walls) → stays exposed.

## Key files
- `player.gd`: `class_name Player`. Tumble (footprint-aware wall collision), extension
  (wall-blocked), dodge, **auto-blend (opposite-pair cover: `_is_in_cover`,
  `_column_walled`, `_row_walled`)**, ink (footprint-aware contact + per-cell deposit),
  audio waves, footprints, water cleanse, **cube-only wall-knock + won't-fit lean/thud
  (`_begin_blocked_bump`, `_gap_ahead`, `_play_thud`)**, collapse-on-dodge, extend-lock
  state + grid accessors (`footprint_covers`, `get_dimensions`, etc.).
- `enemy_sphere.gd`: PATROL/SUSPICIOUS/INVESTIGATE/PURSUIT, graduated detection,
  detection-driven cone, alert glyph, noise -> investigate, footprint follow, A* nav,
  state hum + stings, debug readout (temp). Reads `_player.is_blending` (blend ==
  invisible).
- `level.gd`: state machine (READY/PLAYING/COMPLETE/CAUGHT); completion via end-tile
  Area3D OR `footprint_covers(_end_cell)`; null-guards the enemy.
- `extend_lock_zone.gd` / `extend_lock_gate.gd`: grid-exact lock zone + ghost
  blueprint + lock-driven gate.
- `shaders/grid_ground.gdshader`: grid + waves + vision cone + footprints + LoS fog.
- `main.tscn` (with enemy) / `mechanics_sandbox.tscn` (enemy-free copy).
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

Blend is now automatic (stand still in cover); the old Square / V blend button was
removed. Jump cut by design. Won't-fit lean and knock reuse the move input.

## Tuning backlog (end-of-phase pass)
- Won't-fit bump: `BUMP_DURATION` 0.25, `BUMP_ANGLE` PI/10 (push toward ~PI/5 for a
  visible distance gradient), `BUMP_CLEARANCE` 0.15, thud volume 0.35 / pitch 0.5.
- Detection (`DETECT_*`), cone (`CONE_*`), glyph, hum/stings, footprints
  (`FOOTPRINT_FADE_TIME` 12.0), knock (`KNOCK_RADIUS` 10.0, `KNOCK_COOLDOWN` 0.4),
  extend-lock (`GHOST_*`), nav (`TURN_*`, `CORRIDOR_HYSTERESIS`), fog `dark_factor`.

## Memory notes worth checking
- Read HANDOFF.md first thing at session start.
- Active verbs (sprint/dodge/knock) are cube-only; extension is a positional
  commitment. Apply to any new active ability.
- Design v0.2 (reactive-stealth, shape-vs-exposure, jump cut).
- No Co-Authored-By trailer; no em/en dashes; commit at session end or on request.
- Transform3D row-major; ink/water binary cleanse; GDScript inference with untyped
  arrays.
