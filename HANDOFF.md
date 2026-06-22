# Handoff, 2026-06-22 (session 7)

## Headline
Three things landed, all feel-checked or verified, none pushed beyond this commit:
1. **N5 guide-line routing: DONE.** Replaced the WIP gap-rendering with the real jump-edge
   router. Then a playtest fix: it was too eager to jump, so the BFS became weighted Dijkstra.
2. **Extend/collapse animation** + **spawn-rise animation** (Phase 8 juice, 2 of 5 items).
3. **Task-list cleanup** of stale items (edge walls, tut 6/7, tall-for-intel).

## N5 routing (level_loader.gd) -- DONE, feel-check confirmed
- Jump edges in `_neighbors`: a straight cardinal hop of 2..JUMP_MAX(5) cells over a PURE-VOID
  span (no floor, no wall/glass/safety-edge) landing on floor. `_blocked_cells` is the no-cross set.
- Render: solid translucent line on floor steps; at each jump NO line over the void, a floor
  ARROW (`_make_link_arrow`/`_arrow_mesh`) on the take-off cell, pulled in so it never paints void.
- `_route` is now WEIGHTED Dijkstra: walk = 1 cell, jump = cells + JUMP_PENALTY(100000). So it
  PREFERS staying on tiles and only jumps when no floor path exists (the playtest complaint: plain
  BFS minimised edge count and jumped at everything). JUMP_PENALTY is the one knob to trade that off.
- Removed `_draw_dashed` + route-as-far dashing. Kept `_nearest_walkable`, LINK_ALPHA/EMISSION.
- Verified: parse clean; throwaway logic test 18/18 (walk-connected, 1- and 4-cell jumps, 5-void
  unreachable, blocker-in-span blocks, routes around a U-wall, floor-detour-beats-jump, no overshoot).

## Animations (player.gd) -- feel-check PENDING
- `_update_mesh(snap=false)`: displayed size/offset (`_disp_size`/`_disp_offset`) ease toward the
  `_ext` target via exponential smoothing (EXTEND_ANIM_RATE 22, ~0.15s). `_ext` stays gameplay-exact
  (collision/fall/lock-dims/cover read it, untouched). Detection box follows the displayed shape
  (visible == catchable). Collapse compensates `_disp_offset` for the grid-origin shift so it
  shrinks IN PLACE (no jump). Tumble/dodge/bump pass snap=true (rigid rolls; reorientation instant).
- Spawn-rise: `_spawning` + `_advance_spawn`; eases position.y up out of the floor over
  SPAWN_DURATION(0.45) on level start. Gated `_level != null and not god_mode` (no editor cursor).
  `_process` early-returns while spawning (input locked). Lands on the existing READY beat.
- Knobs: EXTEND_ANIM_RATE, SPAWN_DURATION, SPAWN_RISE_HEIGHT.
- Verified: parse clean; headless smoke-load of tut_01 ran _ready+spawn+ease 40 frames, no errors.
- FEEL-CHECK these: extend/collapse speed; collapse shrink-in-place on odd-dimension shapes; a
  tumble fired mid-grow snaps to full (abrupt?); spawn height/speed; detection easing near an enemy.

## Design fact recorded (memory project_player_los_removed)
Player line of sight was REMOVED: the player has perfect level vision. So "tall-for-intel" is moot
and was DEFERRED (revives only with a future blindness / restore-LoS modifier). Height's live roles:
fill lock shapes, reach, and being seen over cover by enemies.

## Known blind spot (parked, dev called it future): multi-lock guide lines
`_build_lock_links` anchors every line to `locks[0]`, so with >1 lock zone only the first draws
(to all gates/unlocks) and the rest draw nothing. The real fix is the LINK LAYER (N14 deeper):
explicit lock<->unlock pairing, which also fixes the dims-clobber softlock. Biggest open rock.

## OPEN / NEXT (pick ONE)
1. **Link layer** (N14 real fix): per-lock pairing. Fixes multi-lock guide lines + softlock. BIG.
   Dev has parked it as "future" but it's the most valuable systems work left.
2. **Remaining Phase 8 juice**: death animation, level-completion animation, level intro/outro
   (results panel currently covers the cube). Small, visible, low-risk.

## Verify recipe (unchanged; ~/.local/bin/godot v4.6; FROM cube dir; exit 0 even on errors)
- Parse: godot --headless --editor --quit 2>&1 | grep -E "SCRIPT ERROR|Parse Error|SHADER ERROR|SHADOWED"
- Logic test: throwaway `extends SceneTree`; `LevelLoader.new()` then call _route/_neighbors directly.
- Smoke-load: throwaway SceneTree sets `LevelLoader.requested_file`, instantiates painted_level.tscn
  into root, awaits ~40 process_frame, greps errors. Clean up .gd + .uid after.
