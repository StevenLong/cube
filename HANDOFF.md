# Handoff, 2026-06-07 (cont. 2)

## Headline: the EDITOR has a first slice (cube-as-cursor). Foundation done; now iterating the editor.
The pivot's foundation (JSON level format + registry-driven loader, with `ObjectRegistry` the
single source of truth) is in. We chose the editor's direction: an in-world **cube-as-cursor**
editor (it plays like the game, god-mode), NOT a mouse 2D painter. First slice is built and feels
like a good start. Now iterating the editor. See `SPEC_object_anatomy.md`, memory
`project_editor_objects_first`.

## What happened this session (already committed unless noted)
- **JSON format + registry-driven loader** (`level_loader.gd` + `object_registry.gd`): base +
  overlay glyph grids and a typed-objects list; `ObjectRegistry` single-sources the vocabulary
  (id / kind / glyph / paint_mode / scene / params); the loader reads glyphs, scenes, and param
  defaults from it. (Commits `270049d`, `1aa4a3a`.)
- **safety_edge fixed**: `=` is now an invisible 0.4u `Wall*` blocker plus a red line on its
  floor-facing sides, built in the loader; the `level.gd` auto-strip was removed. Memory
  `project_safety_edge_implemented`. (In `270049d`.)
- **Editor first slice** (`editor.tscn` + `editor.gd`, UNCOMMITTED until this wrap): a god-mode
  cursor cube in the void, a grid reference (the game's grid shader), a palette read from
  `ObjectRegistry` (Q/E to cycle), place/erase at the cursor cell, save to JSON
  (`levels/data/editor_test.json`). Floor/ink/water stamp the real (scriptless) scenes;
  walls/objects/start/end stamp lightweight PREVIEWS, because the scripted game objects
  (enemy/lock/gate) need a Player sibling and crash if instantiated bare. Run it: open
  `editor.tscn`, F6 (no menu hook yet).

## Why cube-as-cursor (the editor decision)
Reuses the game's tech (movement / camera / grid / loader / registry) instead of a parallel 2D
app; it IS the player-facing editor feature, not a throwaway dev tool; edit and play can be the
same scene with a mode flag (instant playtest); zero movement learning curve; on-brand. "Tools for
me vs players" is mostly a false dichotomy (shared registry + JSON + edit-state); the real edge is
bulk-edit ergonomics, answered by an area-select mode. A designer mouse layer can bolt onto the
same foundation later if it's ever wanted.

## NEXT (editor iteration). The USER also has their own notes for next time.
1. **Area-select bulk**: on bulk-paint start, the cursor becomes a resizable selection you fill
   (the controller-friendly answer to mouse drag-paint).
2. **Play-mode toggle**: flip the same scene to real play and back (the killer feature).
3. A proper palette **menu** (button opens a menu) instead of Q/E cycle; **load** an existing level
   to edit; render **real objects inert** in edit mode for true WYSIWYG (an editor flag on the game
   scripts); a menu **"Editor" button**.
4. Unify the editor's build with the loader via a shared **LevelBuilder**, so previews match the
   game exactly and the per-type visuals / y-offsets stop being duplicated (current drift seam).

## Open / loose (carried)
- `levels/data/level_01.txt`: dead now (loader reads JSON), still dangling, left uncommitted.
  Remove when convenient (levels get rebuilt in the editor anyway).
- safety_edge "see over" for enemy sight: it's a `Wall*` body, so it blocks line-of-sight like the
  old rail did; a sight-system follow-up. Do NOT re-add an auto-strip.
- The gate rides the GLOBAL lock flag, so one lock puzzle per level until it moves to the link
  layer (see SPEC).

## Verify recipe (`~/.local/bin/godot` v4.6; exit code is 0 even on errors, so grep)
- Parse: `godot --headless --editor --quit 2>&1 | grep -E "SCRIPT ERROR|Parse Error|SHADER ERROR"`
- Smoke: `godot --headless --quit-after 120 res://<scene>.tscn 2>&1 | grep -iE "ERROR|nil|invalid|cannot|failed"` (filter vulkan/audio/display noise)

## Memory
- `project_editor_objects_first` (pivot + spec + editor direction), `project_safety_edge_implemented`
  (the fix + open sight bit), plus the standing cube memories (read-HANDOFF-first, no dashes, no
  co-author trailer, commit cadence, Transform3D row-major, blend flush-match, Wall* nav, etc.).
