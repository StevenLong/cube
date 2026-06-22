# Handoff

## Session 9 (2026-06-22): OFF-PROJECT tooling, NO cube code changed
Side/tooling work only:
- Built the user-level `/idea` capture skill (`~/.claude/skills/idea/SKILL.md`): near-frictionless
  game-idea capture into the game-dev vault.
- Fixed the status-line script (`~/.claude/statusline.py`): it read the wrong rate-limit fields
  (`utilization`, ISO reset) vs the real schema (`used_percentage`, epoch `resets_at`). Now correct,
  shows percent-remaining plus a live countdown; `settings.json` got `refreshInterval: 60`.
- Dogfooded `/idea` by capturing a new game idea, "Quiet Town" (music-first owl game), into game-dev
  (committed + pushed). USER HAS NOT YET REVIEWED that capture or the skill's output quality.
- Skill 2 (idea EXPANSION, grill+teach style) is DESIGNED in conversation but NOT built. Details in
  auto-memory: project_idea_pipeline.

The cube link-layer state below is UNCHANGED and remains the cube NEXT (slice 4 wizard, etc.).

---

# Handoff, 2026-06-22 (session 8)

## Headline
Link layer LARGELY BUILT (runtime + content), the editor wizard FULLY DESIGNED (not built),
two guide-line polish notes triaged, plus a status-line side quest.
1. **Link layer slices 1, 2, 3 DONE + slice 5 CONTENT** (tut_07 hand-authored). All three shipped
   lock levels run on explicit links; per-lock guide lines; tut_07 has two independent puzzles.
   Behavioral feel-check CONFIRMED by user (all working as expected).
2. **Wizard (slice 4) fully designed via a grill** (grouped-sequence, OR all-to-all within a group).
   NOT built. Full buildable spec is in the task list "Link layer" slice 4.
3. **N5c + N5d** guide-line notes triaged (see task list "Lock/gate guide lines").
4. Status line now shows ctx% + 5h rate-limit% + reset countdown (`~/.claude/statusline.py`; user
   config, NOT a repo file).

## Link layer -- what's BUILT (level_loader.gd, player.gd, extend_lock_zone.gd, extend_lock_gate.gd, guide_line.gd)
- **Slice 1 (schema):** `_parse_links` / `_object_ids` parse + validate the generic `{from,to,kind}`
  edge list (structure + endpoints), drop malformed/dangling with a warning, store `data["links"]`.
  Object `id` is the per-instance key (distinct from `type`). `kind` is opaque (generic plumbing).
- **Slice 2 (runtime):** player holds `_active_lock_id` (ONE at a time, since the cube is one shape)
  + `set_active_lock`/`clear_active_lock`/`active_lock_id`; `is_extend_locked()` == id != "". Loader
  `_wire_lock_links` injects `gate.opener_ids` / `unlock.release_lock_ids` (ARRAYS -> many-to-many
  capable) / `lock.link_id`; objects react per-id, EXPLICIT-LINKS-ONLY. `is_extend_locked()` still
  gates the global concerns (extend/collapse barred, locked colour).
- **TRANSITIONAL `_backfill_global_coupling`:** any level with locks but no links gets the OLD global
  behaviour reproduced (all-to-all, minted `__lockN` ids) through the explicit machinery. KEEP IT
  until the wizard authors links everywhere -- it protects user-made lock levels with no links.
- **Slice 3 (migration + guide lines):** level_01 + tut_03 carry real links now. `guide_line.gd` is
  per-lock (a `lock_id` tag tracks that lock; `lock_id == ""` is the legacy global mode for backfill
  levels). `_build_lock_links` draws per-edge for linked levels, the old locks[0] anchor for backfill.
- **Slice 5 content:** tut_07 hand-authored -- puzzle A `lock_a`[8,27] 3x3x3 -> gate_a -> unlock_a;
  puzzle B `lock_b`[27,9] 1x3x1 -> gate_b -> unlock_b. Headless 7/7: each gate opens for its OWN lock
  only. STILL OPEN: dogfood the WIZARD on tut_07 (slice 5 proper) and retire the backfill afterward.

## Wizard (slice 4) -- DESIGNED, ready to build. FULL SPEC: task list "Link layer" slice 4.
Grouped-sequence wizard: a "Lock Puzzle" tool, explicit-advance stages (1+ locks -> 0+ gates -> 0+
unlocks -> finish group, loop per puzzle), all-to-all OR wiring within a group. Reuses existing
zone/gate placement. Hook points: `_objects` entry gains a `group` tag; `_serialize` (~L939) mints
ids + emits the links; tool menu adds the mode + stage counter; round-trip stashes loaded links and
unions new ones (object ids already ride in params). All logic is data/serialize side, so the future
editor overhaul (WYSIWYG inert objects + shared LevelBuilder) won't disturb it. Boundaries: no
in-place re-wire, no sub-pairing within a group, no AND, no generic link tool.

## OPEN / NEXT (pick ONE)
1. **Slice 4 (wizard)** -- fully designed, ready to build. The big remaining link-layer piece.
2. **N5c then N5d** guide-line polish (jump cost should scale with void width; line origin at the
   tile edge not centre). Small, contained, independent of the wizard.
3. **Slice 6** editor warnings panel. After the wizard.

## Verify recipe (unchanged; ~/.local/bin/godot v4.6; FROM cube dir; exit 0 even on errors)
- Parse: `godot --headless --editor --quit 2>&1 | grep -E "SCRIPT ERROR|Parse Error|SHADER ERROR|SHADOWED"`
- Logic test: throwaway `extends SceneTree`; `LevelLoader.new()` then call _parse_links/_wire_lock_links/_route directly.
- Smoke-load: throwaway SceneTree sets `LevelLoader.requested_file`, instantiates painted_level.tscn
  into root, awaits ~30 process_frame, finds nodes (LockZone%d/Gate%d) and asserts. Clean up .gd + .uid after.
