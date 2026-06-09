# Handoff, 2026-06-08 (cont.)

## Headline: control remap shipped (keyboard) + the editor is a real tool now (playtest, reopen, delete).
Big session. Hold-to-extend is gone on keyboard, and the editor grew a full loop: build, name/save,
list, **playtest live**, reopen, delete. The clean next is the **controller half** of the remap (a
pad currently cannot extend), or the editor's remaining UX. Everything below is committed and pushed.

## What happened this session (commits c3a33c2, fbe37f0)
- **Control remap, KEYBOARD** (`project.godot` + `player.gd`): hold-to-extend removed. WASD move
  (arrows freed), **arrows extend width/depth, E up, Q collapse**, no held modifier, movement and
  extension on separate keys. Collapse left the dodge button (retired `_dodge_held_consumed`). Editor
  palette cycle moved off Q/E to `[` and `]`. Decisions: collapse-only (no per-axis retract),
  up-arrow = away from camera. Both felt good in playtest. CONTROLLER is still keyboard-only, see
  memory `project_control_remap_plan`.
- **Editor footprint stamp/erase**: the extended cube stamps AND erases its whole footprint for
  paint-mode tiles (one cell when compact).
- **Reopen + delete**: Levels menu is now per-level rows (Play / Edit / Delete), no Delete on
  built-ins, delete confirm, inside a ScrollContainer. **Edit reopens** a level into the editor
  (`LevelEditor.open_path`); built-ins open read-only and **save as a custom copy "X (copy)"**.
  Editor save **guards against overwriting a different existing level** (confirm dialog).
- **Playtest (`P`)**: a scene-swap playtest through the real loader. `P` serializes the level to
  `user://_playtest.json` and runs `painted_level`; **Esc returns to the editor** with the level
  reloaded. Requires a Start and an End tile. A 3s status flash makes save/playtest messages visible
  (the per-frame `_refresh` had been stomping them).
- **Fixes**: broke a real cyclic dependency (`level.gd` -> `LevelLoader` -> `preload(level_template)`
  -> `level.gd`, a "Busy" parse error) by loading the template lazily in `level_loader`. `level.gd`
  restart key uses `extend_up`.

## NEXT (pick one; user has not chosen)
1. **Controller pass for the remap** (clean completion): right stick = extend width/depth, LB = up,
   LT = collapse, RB/RT = camera; decide where **sprint** goes (RT is taken). player.gd needs no
   change (it already reads the actions). See `project_control_remap_plan`.
2. **Menu-first selection** (note 3) + erase-as-a-button (note 7): a palette menu dissolves the last
   editor key overlaps (Space still = place + dodge).
3. **Area-select bulk paint** (note 4): the footprint-stamp covers rectangles; this is the general case.
4. **WYSIWYG inert objects** (the paused-ghost upgrade to today's scene-swap playtest): place real
   objects inert, toggle live in place. Bigger; pairs with a shared LevelBuilder to kill the
   preview-vs-loader duplication.

## Open / loose (carried)
- `levels/data/editor_test.json`: orphaned stray (pre user:// save path), untracked, safe to delete.
- `user://_playtest.json`: the scratch playtest file; harmless, overwritten each `P`.
- After returning from a playtest, the editor's current file is the scratch file, so the next save may
  re-confirm the overwrite (safe; the v1 tradeoff for not threading the original path through play).
- Editor places only the LOCK variant of `extend_lock_zone` (`mode` is hardcoded to "lock" in
  `_stamp_object`); no way to place an UNLOCK zone yet. Needs per-object param editing (lands with the
  menu-first / param UI). Flagged 2026-06-09.
- Tabbed assemblies (note 5) for multi-part objects still pending. ScrollContainer is in but untested
  past a screenful. safety_edge "see over" for sight; gate still on the global lock flag.

## Verify recipe (`~/.local/bin/godot` v4.6; exit code 0 even on errors, so grep)
- Parse: `godot --headless --editor --quit 2>&1 | grep -E "SCRIPT ERROR|Parse Error|SHADER ERROR|Busy"`
- Smoke: `godot --headless --quit-after 120 res://<scene>.tscn 2>&1 | grep -iE "ERROR|nil|invalid|cannot|failed"` (filter vulkan/audio/display/leaked)
- Headless can't press keys or change scenes interactively. For those, a throwaway `extends SceneTree`
  script run with `-s` that sets the statics and instantiates the scene proves the wiring (used it to
  prove reopen-load and the playtest launch). Delete the script + its `.uid` after.

## Memory
- Updated `project_control_remap_plan` (keyboard done, controller pass remains) and
  `project_editor_objects_first` (editor loop: playtest/reopen/delete done). Plus the standing cube
  memories (read-HANDOFF-first, no dashes, no co-author trailer, commit cadence, Wall* nav, etc.).
