# Handoff, 2026-06-07

## Headline: pivot from building levels to FORMALIZING game objects (registry first)
This session turned a corner. After a long stretch of hand-authoring a tutorial through
description plus agent spatial reasoning (too slow, too error-prone), we stopped and committed
to the foundation: a typed set of game OBJECTS, then a level-data-storage rework, then an
in-game EDITOR, before any more hand-built levels. The object anatomy is now specced in
`SPEC_object_anatomy.md` (the reference to build against). See memory
`project_editor_objects_first`.

## What happened this session
1. **Bug bash (committed, 9649c33):**
   - Per-enemy vision cones: the cone was one set of scalar shader uniforms shared by all
     enemies, so a 2nd enemy erased the 1st's cone. Now an 8-slot array in
     `grid_ground.gdshader`; each enemy writes its `cone_index` slot (loader assigns it),
     cleared on `_exit_tree`.
   - `extend_lock_gate`: hold open while the player footprint covers the gate cell, so the gate
     can't shut on the cube and trap it.
   - `level.gd`: guard the deferred `_build_world` (bail if not `is_inside_tree()`) against the
     scene-teardown race that nulled `get_tree()`.
   - `level_loader`: renamed local `floor` to `floor_cells` (shadowed the `floor()` builtin).
   - `main.tscn` (the menu Sandbox): removed a stray Enemy node plus its orphaned resources.
2. **Extend-lock option 2 + tutorial_03 (committed, 29fdc27):**
   - `extend_lock_zone`: UNLOCK now uses the same exact match as LOCK (shape + orientation at
     `footprint_min == cell`, at rest) instead of loose `footprint_covers`, with a matching
     blueprint shown while locked. Fixes the reverse-through-the-gate lockout.
   - `tutorial_03_bridge.tscn`: rebuilt 3-deep as a single travel-bar course. FIRST PASS,
     spatially untuned, NOT playtested. (This is the level that convinced us to pivot.)
3. **Object anatomy (`SPEC_object_anatomy.md`, committed this wrap):**
   - 9 facets (Identity, Placement, Footprint, Params, Semantics, Presentation, Build,
     Authoring, Dependencies). Rules: glyph iff parameterless; Semantics(flags) vs
     Behavior(logic in Build); paint mode independent of storage; tiles declare a base/overlay
     layer.
   - Closed paint-mode vocab: `paint` / `single` / `region` / `path`, plus `link` (relational).
   - Three schemas, kept separate: object registry / relationship layer (links are directed
     edges, so 1:1, 1:N, N:1 all work) / level config + rules.
   - Ran every current object through it. Two corrections it CAUGHT (now in the spec):
     a. `safety_edge` (the drifted "low rail"): one invisible blocker shown only as a red line;
        the visible half-height box + the auto-derived red strip collapse into it.
     b. ink/water are surface-OVERLAY tiles (paint onto floor), not instances; this added the
        tile "layer" notion and retired "puddles need region".

## NEXT (the chapter)
1. Resolve the STORAGE FORMAT fork (the talk we paused): ASCII grid + structured object section
   vs JSON vs Godot Resource. Lean: registry-first; format likely LAYERED (base grid + overlay
   grid + object list). The ink/water-overlay and safety_edge corrections both push to layers.
2. Build the object REGISTRY against `SPEC_object_anatomy.md`. It absorbs today's scattered
   constants: wall/rail heights + materials (level_loader), enemy view/cone/colour/speed consts
   (enemy_sphere), zone + gate colours (extend_lock_*), and the safety-edge consts in level.gd
   (which become `safety_edge`'s Presentation, not a separate system).
3. Build the EDITOR: 4 paint tools (paint/single/region/path) + the linker, reading the registry.
4. Capstone: an `/add-obj` skill that walks the 9 facets and scaffolds a new object. Build once
   the registry/editor pattern is stable.

## Open design decisions to settle
- `safety_edge`: occupies a cell or sits on the boundary? which edges draw the red line?
- The gate coordinates via a single GLOBAL player flag (`is_extend_locked`), so only ONE lock
  puzzle works per level. Moving the gate onto the link layer (gate references its lock) lifts
  that. Worth deciding before the editor (changes whether a gate needs a "which lock" reference).
- `region` tool is for true multi-cell instances (trigger volumes, platforms), not puddles.

## Uncommitted / loose
- `levels/data/level_01.txt`: dangling WIP grid resize with broken patrols (cols 6/11 cross the
  wall blocks; clear lanes are 7/12). Likely superseded by the format rework; decide keep/revert
  then.

## Carry-over still true
- Debug aids may still be on in `enemy_sphere` (`DEBUG_DETECTION` + the V x-ray); with 2+ enemies
  the readouts overlap. Remove in a tidy pass when done tuning.
- `game-dev/Cube Game Tasks.md` (sibling repo) is stale re: the data loader, the pivot, and this
  object-anatomy chapter. Reconcile.
- Tutorials + sandbox are still hand-authored `.tscn`.

## Verify recipe (`~/.local/bin/godot` v4.6; exit code is 0 even on errors, so grep)
- Parse: `godot --headless --editor --quit 2>&1 | grep -E "SCRIPT ERROR|Parse Error|SHADER ERROR"`
- Smoke: `godot --headless --quit-after 120 res://<scene>.tscn 2>&1 | grep -iE "ERROR|nil|invalid|cannot|failed"` (filter vulkan/audio/display noise)

## Memory
- `project_editor_objects_first` (the pivot + a pointer to `SPEC_object_anatomy.md`). Plus the
  standing cube memories (read-HANDOFF-first, no dashes, no co-author trailer, commit cadence,
  Transform3D row-major, blend flush-match, data-driven levels, Wall* nav naming, etc.).
