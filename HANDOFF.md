# Handoff, 2026-06-07 (cont.)

## Headline: JSON level format + registry-driven loader are IN. Next: the editor.
The pivot's foundation is built. Levels are now JSON (not the old `.txt`), loaded by a
registry-driven loader. `ObjectRegistry` (`object_registry.gd`) is the single source of truth
for the paintable vocabulary; the loader reads it, and the EDITOR (next big piece) will read
the same registry for its palette. See `SPEC_object_anatomy.md` and memory
`project_editor_objects_first`.

## What happened this session
1. **JSON loader.** `level_loader.gd` now reads a JSON level (format in its header and in
   `level_01.json`): `base` + `overlay` glyph grids, an `objects` list, with `links`/`config`
   stubbed. Replaced the old `.txt` parser. `painted_level.tscn` (menu "Crossing") loads
   `level_01.json`.
2. **safety_edge FIXED** (the long-standing drift). `=` is now an invisible 0.4u `Wall*`
   blocker plus a red line on its floor-facing sides, built in `level_loader`; the `level.gd`
   auto-strip (its call, the `SAFETY_EDGE_*` consts, and four functions) was REMOVED. Red lines
   come only from `safety_edge` now. Memory: `project_safety_edge_implemented`. OPEN: "see over"
   for enemy line-of-sight (it's a `Wall*` body, so it blocks sight like the old rail did; a
   sight-system follow-up). Do NOT re-add an auto-strip.
3. **Prefabs (Build facet = packed scene):** `extend_lock_zone.tscn`, `extend_lock_gate.tscn`,
   `ink_overlay.tscn`, `water_overlay.tscn`. The loader instantiates and configures them.
4. **Builders.** The loader builds enemy_sphere, extend_lock_zone (`mode` + `required_dims`),
   extend_lock_gate, and ink/water overlay tiles, all from JSON.
5. **ObjectRegistry STARTED** (`object_registry.gd`). `TYPES` table (id -> name / kind / glyph /
   paint_mode / scene / params) plus helpers `glyph_to_id`, `ids_of_kind`, `scene_for`. The
   loader sources glyphs and scenes from it (single source); the bespoke build code stays in the
   loader, keyed by id.

## Where the loader stands
JSON format + registry-driven loader handle: base tiles (floor / tall_wall / safety_edge / void
/ start / end), overlay tiles (ink / water), objects (enemy_sphere / extend_lock_zone /
extend_lock_gate). Only `links` and `config` are stubbed (nothing needs them yet). Adding a type
is one registry entry, plus a build case only for code-built tiles or a configure step for
objects.

## NEXT
1. **The EDITOR** (the big one): an in-game painter reading `ObjectRegistry` for its palette
   (`ids_of_kind` for groups, `name` for labels, `paint_mode` to pick the tool
   paint/single/region/path, `glyph` to serialize tiles, `scene`/`params` to instantiate and
   seed defaults). Paint the base + overlay grids, place objects, save to the JSON format. This
   is the pivot's payoff.
2. Smaller follow-ups: have the builders pull param DEFAULTS from the registry (a couple, e.g.
   enemy `speed` 1.8, are still duplicated in loader + registry). Wire `links` + `config` when an
   object needs them. The `/add-obj` skill once the editor pattern is stable.

## Open / loose
- `levels/data/level_01.txt`: now DEAD (loader reads JSON); still sitting modified, left
  uncommitted. Remove when convenient (levels get rebuilt in the editor anyway).
- safety_edge "see over" for enemy sight (item 2 above).
- The gate still rides the GLOBAL lock flag, so one lock puzzle per level until it moves to the
  link layer (see SPEC).

## Verify recipe (`~/.local/bin/godot` v4.6; exit code is 0 even on errors, so grep)
- Parse: `godot --headless --editor --quit 2>&1 | grep -E "SCRIPT ERROR|Parse Error|SHADER ERROR"`
- Smoke: `godot --headless --quit-after 120 res://painted_level.tscn 2>&1 | grep -iE "ERROR|nil|invalid|cannot|failed"` (filter vulkan/audio/display noise)

## Memory
- `project_editor_objects_first` (pivot + spec pointer), `project_safety_edge_implemented` (the
  fix + open sight bit), plus the standing cube memories (read-HANDOFF-first, no dashes, no
  co-author trailer, commit cadence, Transform3D row-major, blend flush-match, Wall* nav, etc.).
