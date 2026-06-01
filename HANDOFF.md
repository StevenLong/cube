# Handoff, 2026-06-01

## Where we are
Ran the project assessment, then hardened the sphere (the flagged next area). All
sphere-behavior fixes below were playtested-and-approved by the user this session
and are committed. We stopped at a "what's next" fork (asked, not yet chosen).

## Sphere hardening done this session (player.gd / enemy_sphere.gd)
- **Blend = flush height MATCH.** Hiding requires the flanking walls to equal the
  player's exact height, not merely cover it. Short-in-tall and tall-over-short both
  fail. (`_column_walled`/`_row_walled` probe the player's top cell AND just above.)
  See memory `project_blend_flush_height_match`.
- **Pursuit chases the visible end**, not the hidden base cell (`_last_seen_pos`, not
  `_player.position`); `_has_pursuit_corridor` now takes the target.
- **Knock ignored during pursuit** (not queued; in-flight `_pending_sounds` cleared on
  pursuit entry).
- **Repeated-knock stunlock fixed** (same-spot knocks no longer reset the dwell timer
  or churn the path; only a meaningfully different source redirects).
- **Search-and-clear investigate.** The sphere visits the open, reachable tiles AROUND
  the source (orthogonal neighbours, nearest-first, ~5 cap, ~0.6s dwell each), so it
  comes around a knocked wall instead of glancing at one face. Ends when all tiles are
  checked or a 12s safety cap. (`_begin_search` / `_build_search_cells` /
  `_investigate_search`; `INVESTIGATE_TIMEOUT` is now the safety cap.)
- **Wall-clipping fixed.** `_follow_path`'s collision-less final `_move_toward` is gated
  by `_clear_walk_to` (a layer-1 ray), so the sphere can't straight-line through
  geometry. Root cause was a path/search desync in the knock handler (it called
  `_set_path_to` instead of `_begin_search`); now synced.

## New debug + readout aids
- **V = debug reveal toggle** (project.godot action `debug_reveal`): x-rays the sphere
  body + alert glyph through walls to watch it while occluded. Pause-gated (works in
  active play, not on menus/results). Debug only; remove when done tuning.
- **DEBUG_DETECTION readout** still ON (`enemy_sphere.gd` ~line 49): shows state +
  detection + `[REVEAL]`. Kept on intentionally while tuning.
- **Last-known ghost** (`_setup_ghost`/`_update_ghost`): translucent cube tinted by
  alert state, shown ONLY when alerted and NOT currently seeing the player (i.e. once
  it has lost sight). This is a GAMEPLAY readout now, not debug.
- **Blend gallery in main.tscn** (the Sandbox): labeled 1u/2u/3u slots + a single-wall
  no-blend control, in the z=-8 lane north of start. Walls `WallS1L`..`WallSingle`
  (2u/3u use new `BoxMesh_2u`/`_3u` + `BoxShape3D_2u`/`_3u`). Built to verify the flush
  blend rule.

## NEXT SESSION: pick the fork (I asked, user wrapped before answering)
1. **First real level** (my recommendation): use the hardened sphere to build the void
   world's first non-tutorial showcase (Phase 8C never got one). The design's named
   gate before new enemy types; surfaces real-play needs.
2. **New enemy type** (pyramid/cylinder): the user's originally-flagged gap. NOTE: the
   v0.2 doc defers new types until the sphere has carried a full level set (none exists
   yet), so choosing this is a deliberate divergence from the locked design.
3. **Tidy & verify the sphere**: the leftover stale-pile items below.

## Sphere leftovers (the "tidy & verify" option)
- Dead `WallRay{N,S,E,W}` nodes under Player in EVERY scene (main, all tutorials,
  level_01, sandbox); referenced in zero .gd. Strip them (hand-edit .tscn).
- Two sandbox scenes diverged: main.tscn (wired as "Sandbox", has the enemy) vs
  mechanics_sandbox.tscn (orphaned, no enemy). Reconcile or delete the orphan.
- LoS center-to-center per cell (`_is_seeing_player`, `_visible_to_player`): likely fine
  for the grid; verify, fix only if a real fairness hole.
- Perimeter cover (`_extend_cell_clear` counts collision-only perimeter walls): moot in
  the void world (no perimeter walls); main.tscn still has legacy perimeter colliders.
- Remove DEBUG_DETECTION readout + the V reveal x-ray once tuning is done. KEEP the
  last-known ghost (it graduated to gameplay).

## Assessment recap (still to reconcile)
- Task-list stale boxes in `Cube Game Tasks.md`: Phase 8C (void world) is built in code
  but unchecked. Phase 9 tutorials we built (move/gaps/bridge) diverge from the task
  list's situation-first list. Reconcile both.
- `levels/level_01_movement.tscn` is orphaned (delete whenever).

## Verify recipe (~/.local/bin/godot, v4.6; exit code is 0 even on errors, so grep)
- Parse: `godot --headless --editor --quit 2>&1 | grep -E "SCRIPT ERROR|Parse Error|SHADER ERROR"`
- Smoke: `godot --headless --quit-after 150 res://main.tscn 2>&1 | grep -iE "ERROR|nil|invalid|cannot|failed"` (filter vulkan/audio/driver/display noise)

## Memory notes
- Read HANDOFF.md first at session start.
- Blend needs flush height match (memory `project_blend_flush_height_match`, new this session).
- Active verbs are cube-only; ink/water binary cleanse; Transform3D row-major.
- No Co-Authored-By trailer; no em/en dashes; commit at session end or on request.
