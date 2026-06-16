# Handoff, 2026-06-16

## Headline: reoriented after drift, then built the save / progression system end to end (4 slices, all verified). The cube now records per-level completion + best time + perfect-stealth, the levels menu shows it, and a new best time shows a gold-chevron face on the cube. Trackers re-synced to reality first; we held one spine the whole way and nothing drifted in.

## The reorientation (why this session started)
The dev flagged that things felt "lost and forgotten." Diagnosis: since the validation
gate passed (06-12) every session had been reactive playtest polish, and the task list
had drifted from reality (per-face ink + fall-off-level were done but unchecked; the whole
cube-as-display system wasn't in the plan). Fixes:
- Re-synced game-dev/Cube Game Tasks.md to match the build (cube-as-display block added,
  done items checked, save promoted out of Deferred into Phase 8.6).
- Adopted an anti-drift rule: ONE spine at a time; playtest notes go to this parking list,
  not into the live session, unless a note is blocking.
- Picked the next spine deliberately: save / progression (the documented gate before a
  level set; also unblocks the PB cube face we'd stubbed).

## Save / progression (the spine, complete) -- Phase 8.6
Static `SaveManager` class (save_manager.gd), same pattern as LevelLoader/LevelEditor (NO
autoload). File: user://save.json, lazy-loaded, full flush per write, version + _migrate so
a bad/old file can't crash a load. Levels keyed by resource path.
- **Slice 1**: SaveManager + schema. `get_record(path)` (defensive copy; empty defaults),
  `is_completed(path)`, `record_result(path, time, perfect)` (marks complete, keeps faster
  time, perfect sticky-OR).
- **Slice 2**: `level.gd _enter_complete()` records on a real clear. GUARDED: skips when
  `LevelLoader.return_to_editor` or the path is empty, so editor playtests (scratch file)
  never write a record.
- **Slice 3**: `levels_menu.gd` shows a status column per row, read from the save: blank if
  unplayed, `✓ 9.0s` if cleared, `✓ 9.0s ★` if perfect.
- **Slice 4**: new-best cube face. `player.gd` NEW_BEST_EXPR = 8, `show_success(perfect,
  new_best)` with precedence **perfect (7) > new-best (8) > ordinary success (4..6)**.
  cube.gdshader index 8 = gold forward chevrons on dark (a speed/record motif, kept distinct
  from the perfect rainbow and the menu ★). `_enter_complete` reads the OLD record before
  overwriting to detect a genuine new best (first clear is ordinary, not a PB).

All four verified headless (SaveManager persistence + merge rules; real-play-records vs
playtest-skipped; menu row wiring; precedence across runs; shader compiles in a smoke load).

## Expression index map (cube.gdshader expr_color + player.gd constants)
FAIL 0..3 (checker / red X / glitch bars / sad face) ; SUCCESS 4..6 (smiley / check /
sunglasses) ; PERFECT 7 (rainbow) ; NEW_BEST 8 (gold chevrons). Add one: new expr_color
branch + bump the matching constant; the player picks via `_trigger_fail_face()` (fail) or
`show_success(perfect, new_best)` (clear).

## NEXT (parking list; pick ONE as the next spine)
1. **Level set + content** -- the natural follow-on now that progress is tracked. A handful
   of real levels (the editor can author them) gives the save data something to measure.
   Tutorials (Phase 9) ride on top; their old scenes are stale and controller-broken, so
   rebuild as data levels.
2. **Start/end-of-level screen pass** -- results panel still covers the cube, so the new
   success/fail faces are barely seen. Intro/outro (camera + timing) to show them + goal/par.
   Ties to Phase 8 "Level intro/outro".
3. **Broader save vision (DEFERRED until a level set exists)**: unlock chain, cosmetics,
   optional-objective tracking. No point building these against a single level.
4. **Right-stick extend drift** (carried) -- needs the dev's hands to dial deadzone.

## Tuning dials (cube display)
- cube.gdshader: edge_band / edge_darken / glow_strength / heat_color / ready_color (dodge
  heat); expr_color patterns (incl. the new chevron geometry at index 8).
- player.gd: DODGE_FLASH_TIME, _ready_player.volume_db (-15), DODGE_COOLDOWN, FALL_END_Y (-25),
  FAIL_EXPR_COUNT / SUCCESS_EXPR_* / PERFECT_EXPR / NEW_BEST_EXPR.

## Open / loose (carried)
- Infinite floor: deep columns + side fade to void (fade_start/fade_end; FLOOR_DEPTH > fade_end).
- Lock-puzzle telegraphs reworked (lock = tile+icon+expand ghost; unlock = placement ghost
  shown only when gate open). Gate = raised/lowered red floor tiles.
- Editor previews for gate + lock zone still draw OLD ghosts (preview != play).
- DEBUG_DETECTION still true in enemy_sphere.gd. One global extend-lock per level (link layer pending).

## Verify recipe (`~/.local/bin/godot` v4.6; exit 0 even on errors, so grep). RUN FROM THE cube DIR.
- Parse: `godot --headless --editor --quit 2>&1 | grep -E "SCRIPT ERROR|Parse Error|SHADER ERROR"`
- SHADER runtime/compile errors (e.g. `return` in fragment) are NOT caught by parse; only a
  smoke run is: `godot --headless --quit-after 30 res://painted_level.tscn 2>&1 | grep -i "SHADER ERROR"`.
- Logic: throwaway `extends SceneTree` run with `-s`; the loader builds via call_deferred so
  await ~6 frames after add_child before finding the Level node; set test var types; clean
  user://save.json between cases (and after); delete the script + `.uid` when done.

## Memory
- Updated `project_cube_display` (expression map now includes NEW_BEST = 8; how to extend).
  Standing cube + save memories otherwise unchanged.
