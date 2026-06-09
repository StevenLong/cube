# Handoff, 2026-06-09

## Headline: control remap fully done (keyboard + controller + menu nav); editor is now a MODAL tool (slices 1-3). Next = the paint-model revision, then objects.
This session finished the controller half of the control remap, added controller menu navigation, and
built the editor's modal interaction in three slices. Next is revising the paint model (tap-toggle
paint + hold-rectangle), then slice 4 (objects). All four commits below are pushed.

## What happened this session (commits ce7dd06, 5027145, a92ad7d, 1ddcab4)
- **Controller pass for the remap** (ce7dd06): right stick = extend width/depth, LB = extend-up,
  RB/RT = camera tilt. The user then set **A = dodge, B = collapse, X = sprint** (LT and L3 freed).
  Menu nav: `ui_accept` += A, `ui_cancel` += B (keyboard defaults preserved); a new **`pause`** action
  (Start + Esc) exits a level/editor to the menu, so **in-game B only collapses** (level.gd, editor.gd
  moved their exit off `ui_cancel`).
- **Editor modal slice 1** (5027145): **Tab / Y** opens a **tool menu** (None + every type); pick one
  to enter its placement mode; cube freezes while open; the `[ ]` cycle is gone; place requires a tool.
- **Slice 2** (a92ad7d): **hold place + tumble to the opposite corner + release = fill the rectangle**
  (paint tiles); tap = one stamp; live preview box; an extended/resized cube widens the rect.
- **Slice 3** (1ddcab4): **A = place** (added to the `place` action) with a `suppress_dodge` flag so
  the cube doesn't dodge while a tool is active; **Back/Select (or grave) = drop to None**; **erase
  (X / Backspace / LT)** clears the footprint (controller quick-delete).

## NEXT
1. **Paint-model revision** (user's latest call): **tap A = toggle a continuous "move-to-paint" brush
   on/off** (paints the footprint wherever the cube tumbles); **hold A = the rectangle** (keep slice 2).
   Tap-vs-hold on one button is finicky, so we may **split the two over two buttons**. Single tiles
   (Start/End) and objects stay **tap = place one**. LT could pair as hold-to-erase-as-you-move.
2. **Slice 4: objects** — patrol-path mode and per-object params, including placing the **unlock zone**
   (still hardcoded to "lock" in `_stamp_object`).
3. **UI button-prompt overlay** — reads the action list, shows live controller/keyboard prompts.

## Editor controls (current)
Move/extend = drive + shape the cube. **Y/Tab** = tool menu. **A/Enter** = place (tap; hold-drag =
rectangle). **B** = collapse (resize brush). **Back / grave** = drop to None. **X/Backspace/LT** =
erase footprint. **F5** = finish/name. **P** = playtest. **Start/Esc** = leave to menu.
Memory: `project_editor_interaction_model`.

## Open / loose (carried)
- Editor places only the LOCK variant of `extend_lock_zone` (no unlock yet); fixed by slice 4 params.
- `levels/data/editor_test.json`: orphaned stray, safe to delete. `user://_playtest.json`: scratch, harmless.
- **Tab** may be eaten by GUI focus on keyboard; **Y is the robust open**. If Tab is flaky, swap the key.
- ScrollContainer (levels menu + tool menu) untested past a screenful. Gate still on the global lock
  flag (one lock puzzle per level). safety_edge "see over" for enemy sight still pending.
- After a playtest the editor's current file is the scratch file, so the next save may re-confirm overwrite.

## Verify recipe (`~/.local/bin/godot` v4.6; exit code 0 even on errors, so grep)
- Parse: `godot --headless --editor --quit 2>&1 | grep -E "SCRIPT ERROR|Parse Error|SHADER ERROR|Busy"`
- Smoke: `godot --headless --quit-after 120 res://<scene>.tscn 2>&1 | grep -iE "ERROR|nil|invalid|cannot|failed"` (filter vulkan/audio/display/leaked)
- Headless can't press keys. A throwaway `extends SceneTree` script run with `-s` that sets the statics
  and calls editor methods proves the wiring (used it for the menu build, the rect drag, suppress_dodge,
  and every input-map binding). Delete the script + its `.uid` after.

## Memory
- Updated `project_control_remap_plan` (controller DONE, final bindings). New
  `project_editor_interaction_model` (modal editor controls, slice progress, the paint-model decision).
  Plus the standing cube memories (read-HANDOFF-first, no dashes, no co-author trailer, commit cadence,
  Wall* nav, etc.).
