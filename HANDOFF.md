# Handoff, 2026-06-22 (session 7)

## Headline
Shipped (committed 9d1bf56), then a long design grill and a toolkit side quest:
1. **N5 guide-line routing: DONE.** Jump-edge router + weighted Dijkstra (prefers floor, jumps
   only when forced). Feel-check confirmed.
2. **Extend/collapse + spawn-rise animations** (Phase 8 juice, 2 of 5). Feel-check PENDING.
3. **Link layer: fully DESIGNED via a grill** (NOT built). Slices in the task list + memory.
4. Added user-level skills `/grill` `/diagnose` `/teach` (`~/.claude/skills/`).

## N5 routing (level_loader.gd) -- DONE, feel-check confirmed
- Jump edges in `_neighbors`: a straight cardinal hop of 2..JUMP_MAX(5) cells over a PURE-VOID
  span (no floor, no wall/glass/safety-edge) landing on floor. `_blocked_cells` is the no-cross set.
- Render: solid translucent line on floor steps; at each jump NO line over the void, a floor
  ARROW (`_make_link_arrow`/`_arrow_mesh`) on the take-off cell, pulled in so it never paints void.
- `_route` is WEIGHTED Dijkstra: walk = 1 cell, jump = cells + JUMP_PENALTY(100000). So it PREFERS
  floor and only jumps when forced (the playtest fix: plain BFS jumped at everything). JUMP_PENALTY
  is the one knob. Removed `_draw_dashed` + route-as-far. Kept `_nearest_walkable`, translucency.
- Verified: parse clean; throwaway logic test 18/18.

## Animations (player.gd) -- feel-check PENDING
- `_update_mesh(snap=false)`: displayed size/offset (`_disp_size`/`_disp_offset`) ease toward the
  `_ext` target (EXTEND_ANIM_RATE 22, ~0.15s). `_ext` stays gameplay-exact; detection box follows
  the displayed shape (visible == catchable). Collapse compensates `_disp_offset` for the grid-shift
  so it shrinks IN PLACE. Tumble/dodge/bump pass snap=true (rigid rolls; reorientation instant).
- Spawn-rise: `_spawning` + `_advance_spawn` ease position.y up out of the floor over
  SPAWN_DURATION(0.45). Gated `_level != null and not god_mode`. Lands on the READY beat.
- Knobs: EXTEND_ANIM_RATE, SPAWN_DURATION, SPAWN_RISE_HEIGHT. Verified: parse clean; smoke-load OK.
- FEEL-CHECK: extend/collapse speed; collapse shrink-in-place on odd-dimension shapes; a tumble
  fired mid-grow snaps to full (abrupt?); spawn height/speed; detection easing near an enemy.

## Link layer -- DESIGNED 2026-06-22 (grill), NOT built
Full design: memory `project_link_layer_design` + task list "Link layer" section (6 slices). Settled:
- Gameplay pairing (B); player tracks `_active_lock_id` (one active at a time).
- EXPLICIT-LINKS-ONLY coupling, no global fallback. Optionality = not linking a component (no flag);
  only the lock is meaningful standalone (finishing locked is valid).
- Generic data: string `id`s + `{from, to, kind}` edges (kinds `opens`, `released_by`).
- Decentralised runtime: loader injects partner ids; objects self-update reading `active_lock_id()`.
- Editor lock-puzzle WIZARD (skippable gate/unlock steps); generic link tool DEFERRED.
- Migration: auto for level_01 + tut_03; re-author tut_07 (the multi-lock test).
- Validation: linked pairs only; absent components valid; findings feed a future editor WARNINGS PANEL.
- START at slice 1 (schema: string ids + parse `links`).

## Design fact recorded (memory project_player_los_removed)
Player line of sight was REMOVED (perfect level vision). "Tall-for-intel" is moot and was DEFERRED
(revives only with a future blindness / restore-LoS modifier). Height's live roles: fill shapes,
reach, being seen over cover.

## Toolkit added this session: user-level skills
`~/.claude/skills/`: `/grill` (pre-build plan interview, one question at a time, recommends answers),
`/diagnose` (tight-red-loop debugging discipline), `/teach` (multi-session learning workspace, for
the asset-creation goal). Adapted from github.com/mattpocock/skills. RESTART a session to register
them. See memory `user_growth_goals_and_skills`.

## OPEN / NEXT (pick ONE)
1. **Link layer, slice 1** (schema: string ids + parse generic `links`). Design is settled; this is
   the foundation every later slice needs. Strongest pick if tackling the big rock.
2. **Remaining Phase 8 juice**: death animation, level-completion animation, level intro/outro
   (results panel currently covers the cube). Small, visible, low-risk.

## Verify recipe (unchanged; ~/.local/bin/godot v4.6; FROM cube dir; exit 0 even on errors)
- Parse: godot --headless --editor --quit 2>&1 | grep -E "SCRIPT ERROR|Parse Error|SHADER ERROR|SHADOWED"
- Logic test: throwaway `extends SceneTree`; `LevelLoader.new()` then call _route/_neighbors directly.
- Smoke-load: throwaway SceneTree sets `LevelLoader.requested_file`, instantiates painted_level.tscn
  into root, awaits ~40 process_frame, greps errors. Clean up .gd + .uid after.
