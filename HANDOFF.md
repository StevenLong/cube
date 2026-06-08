# Handoff, 2026-06-08

## Headline: the editor ROUND-TRIP is complete. Next session = the control remap (user's pick).
You can now go main-menu -> Editor -> build a level -> name + save it -> back to menu -> play it
from the Levels list -> restart stays on it. The next chosen task is reworking the extend controls
(hold-to-extend is out). It waits for the usage-limit reset. Plan in memory
`project_control_remap_plan`.

## What happened this session (committed in this wrap unless noted)
- **Editor v2: the cursor is the REAL player cube** (god-mode). Extracted the player subtree to
  `player.tscn`; `player.gd` got `god_mode` (no fall, no-clip) and a null-safe `_is_floor` so it
  runs standalone with no `Level` sibling. `editor.tscn` / `editor.gd` rewritten to instance
  `player.tscn`, follow it with the game camera, and dim the void grid so painted floor reads.
  BE-the-shape: placing a Lock Zone captures the cube's live `get_dimensions()` into `required_dims`.
- **Menu integration**: main menu has an **Editor** button; **Esc** leaves the editor to the menu.
- **Play your level**: `level_loader.gd` is now `class_name LevelLoader` with a
  `static var requested_file`; a launcher sets it, the loader uses it. RESTART BUG fixed: it no
  longer clears the static, and both Levels buttons route through one `_play(file)`, so
  `reload_current_scene` replays the same level (it had been reverting to level_01).
- **Finish / name interface**: in the editor, **F5** opens a panel that freezes the cube
  (`process_mode`) so typing cannot drive it, names the level, and writes
  `user://levels/<slug>.json` with `meta.name`. Esc / Cancel backs out without leaving.
- **Dynamic level list**: the Levels menu drops the fixed button and scans `user://levels/*.json`,
  one button per file labelled by `meta.name` (filename fallback), Back pinned last.
- **Cleanup**: removed dead `levels/data/level_01.txt` (loader reads JSON; nothing referenced it).
- All scenes verified by the parse + smoke recipe at every step. Three things only a human can
  click-test (do these on your end): F5 -> type -> Save writes the file; the cube stays frozen
  while typing; a named level launches from the list and restart keeps you on it.

## The control remap (next session, keyboard-first). See memory `project_control_remap_plan`.
KEYBOARD: Move = WASD (arrows freed); Extend width = Left/Right arrow; Extend depth = Up/Down arrow;
Extend up = E; Collapse = Q; Camera = R/F. No held modifier. Default mechanic = grow + full-collapse
(a pure remap of today's behavior). Edit `project.godot` `[input]` and the extend block in `player.gd`
(~lines 1115 to 1135). The editor inherits this for free (it drives the real cube). CONTROLLER is a
deferred follow-up (conflicts: right stick was camera tilt, RT was sprint, so sprint needs a new
home). TWO OPEN QUESTIONS for the user: collapse-only vs opposite-arrow-retracts; controller in the
same pass or after.

## Open / loose (carried)
- `levels/data/editor_test.json`: a stray test save from before saves moved to `user://`;
  unreferenced, left untracked, safe to delete (kept it for you to judge).
- Editor: enemy / lock / gate render as inert ghost previews; a **play-mode toggle** (inert <-> live)
  is still pending (the paused-ghost idea).
- Levels menu wants a **ScrollContainer** once the list runs past a screen; same-name save
  overwrites with no confirm.
- safety_edge "see over" for enemy sight is still a sight-system follow-up. Gate still rides the
  GLOBAL lock flag, so one lock puzzle per level until it moves to the link layer (see SPEC).
- Shared **LevelBuilder** still wanted: editor previews and loader builds duplicate the per-type
  visuals / y-offsets (a drift seam).

## User notes parked for later (from this session)
- Open an existing level back INTO the editor, with shipped levels READ-ONLY (Save As a custom copy,
  never overwrite) and a DELETE for custom levels. This is the well-shaped slice right after the remap.
- Premade vs custom levels in separate menus; folders / grouping for portability; sharing (needs an
  in-game "open levels folder" affordance or hosting, since dropping files into an export is not
  obvious to players). Way out ahead, parked.

## Verify recipe (`~/.local/bin/godot` v4.6; exit code is 0 even on errors, so grep)
- Parse: `godot --headless --editor --quit 2>&1 | grep -E "SCRIPT ERROR|Parse Error|SHADER ERROR"`
- Smoke: `godot --headless --quit-after 120 res://<scene>.tscn 2>&1 | grep -iE "ERROR|nil|invalid|cannot|failed"`
  (filter vulkan / audio / display / leaked noise)

## Memory
- NEW `project_control_remap_plan` (the next task, with current bindings + open questions).
- Updated `project_editor_objects_first` (round-trip + naming done) and the data-driven index hook
  (JSON, not .txt). Plus the standing cube memories (read-HANDOFF-first, no dashes, no co-author
  trailer, commit cadence, Transform3D row-major, Wall* nav, blend flush-match, active-verbs-cube-only).
