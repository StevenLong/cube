# Handoff

## Session 10 (2026-06-23): Link layer SLICE 4 (wizard) BUILT + SLICE 5 (dogfood) DONE
Built the wizard end to end in `editor.gd`. The big remaining link-layer piece is now in.

SLICE 5 DOGFOOD + PROMOTE (2026-06-23): user drove the actual wizard on a stripped tut_07 base I
dropped in their user:// (full level minus the 6 lock components), authored both puzzles, playtested,
and tweaked unlock2 to (36,14)[1,1,3] (a permutation of lock2's [1,3,1], reachable, no softlock).
Wizard emitted byte-correct independent links (loader keeps 4/4; lock1 wired to gate1+unlock1 only,
no cross-talk). PROMOTED to res://levels/data/tut_07_convergence.json (name restored to "Convergence";
parse-clean). The wizard now authors SHIPPED content. NOTE: user runs NATIVE WINDOWS Godot, so user://
is at /mnt/c/Users/steve/AppData/Roaming/Godot/app_userdata/Cube/ -- NOT the WSL path (see auto-memory
project_windows_userdata_path). The dogfood file tut07_wizard_dogfood.json is still in their user://.

BACKFILL RETIREMENT -- NEXT DECISION, NOT DONE: all 3 shipped lock levels now carry real links, but
`_backfill_global_coupling` (level_loader) + guide_line lock_id=="" still protect the user's pre-wizard
user:// lock levels (manual locks, no links, e.g. double_gate_one). Retiring breaks those until
re-authored via the wizard. ASK the user before retiring.

POST-PLAYTEST FIXES (2026-06-23, user drove the wizard; "it passes for now")
- Wizard back rebound off pad-X (clashed with sprint) to **L3** (button 7, free). Keyboard Shift+Tab
  unchanged. project.godot + editor.gd labels updated.
- LOCK attention fix (extend_lock_zone.gd + guide_line.gd), a GAMEPLAY bug surfaced while testing:
  arming a lock used to HIDE every lock's telegraph (its own shape-ghost, the floor tile, and all
  OTHER locks) because the telegraph keyed off the global `is_extend_locked()`. Now while any lock is
  engaged, every lock drops to a quiet DISABLED state (dim grey unlit tile, no icon, no expand ghost)
  instead of vanishing; the live unlock + its guide line keep attention. Guide-line cross-puzzle bleed
  also fixed: a lock->gate line shows only while NOTHING is engaged (was visible for a different
  puzzle while you were committed elsewhere). Single-lock shipped levels unchanged (truth-table
  verified). User picked "dim ALL locks" (not just the active one). See task list N15. NEEDS a visual
  feel-check on a multi-lock level (e.g. tut_07 or a 2-puzzle wizard playtest).
- Deferred (task list): holistic control-scheme rebind + more readable editor on-screen control hints.

WHAT IT DOES
- New tool-menu entry "Lock Puzzle (wizard)". Grouped-sequence flow: place lock(s) -> gate(s) ->
  unlock(s) -> finish; finishing loops to a fresh independent puzzle.
- CONTROLS (tunable on feel-check), keyboard / controller:
  - next stage: **Tab / Y** -- past the unlock stage this finishes the puzzle and starts the next one.
  - previous stage: **Shift+Tab / L3** (`editor_wizard_back`, NEW action in project.godot) -- steps
    back within the SAME puzzle to add more of an earlier role; stops at lock, never crosses into the
    prior puzzle. Safe because wiring is all-to-all / order-independent. Checked BEFORE editor_menu in
    `_unhandled_input` (and guarded by `_wizard_active`) because Shift+Tab also matches plain-Tab
    editor_menu; handling back first + returning shadows that. Verified by an InputMap-match test.
    (Originally pad-X, but X=sprint in gameplay; moved to L3/button 7, free. A holistic control-scheme
    rebind is deferred -- see task list Deferred.)
  - finish & exit: **` / View(Back) button**.
  - erase a placed object (drops it + its group): **X-key or Backspace / B**.
  Placement itself is the EXISTING zone (BE-the-shape) / gate (node-path) tooling, untouched.
- Each placed lock/gate/unlock gets an in-memory `group` tag (sibling to id/params in `_objects`,
  NOT serialized). On save, `_serialize` -> `_build_links`:
  - `_mint_link_ids` gives every grouped object a scan-unique id (lock1/gate1/unlock1...), written
    into `params` so it's stable + idempotent (re-saving never renames).
  - `_emit_group_links` emits all-to-all OR within a group (every lock `opens` every gate, every
    lock `released_by` every unlock). Separate groups = independent puzzles.
  - Unions those with the level's LOADED links (now stashed in `_load_data` as `_loaded_links`),
    pruning edges whose endpoints were deleted. This fixes a latent bug: serialize used to hardcode
    `"links": []`, so editing+saving ANY linked level silently dropped its relationships. Now links
    round-trip (object ids already rode in params).
- Readout shows the active puzzle number, stage, and L/G/U counts.

VERIFIED (headless, ~/.local/bin/godot v4.6)
- Parse clean (no SCRIPT/SHADER errors).
- 19 link-logic checks pass: single all-to-all puzzle, two-puzzle independence (no cross-talk),
  lock-only commit-to-shape (id minted, no edges), round-trip + dangling-edge prune, mint-uniqueness
  vs loaded ids, idempotent re-build.
- Serialize->loader e2e: a wizard puzzle's emitted edges parse via `LevelLoader._parse_links` with
  zero dropped, and all objects carry ids. Emitted format is byte-identical to the migrated levels
  (level_01/tut_03/tut_07) the user already confirmed behaviorally.
- InputMap match: plain Tab matches editor_menu but NOT editor_wizard_back; Shift+Tab matches the
  back action. So forward/back never collide.

NOT VERIFIED (needs the user, can't drive the editor GUI headless)
- The interactive feel: Tab/stage flow, per-stage placement, the readout, the wizard controls.
  Drive it on a real playtest. Controls are explicitly "tunable on feel-check".

OPEN / NEXT (pick ONE)
1. **Backfill retirement DECISION** (slices 4+5 done): retiring `_backfill_global_coupling` +
   guide_line.gd's `lock_id==""` global mode is now unblocked for shipped levels, but it breaks the
   user's pre-wizard user:// lock levels (manual locks, no links). ASK first; if yes, the user
   re-authors those via the wizard (or accepts they break).
2. **Slice 6** editor warnings panel (gate with no opener, unlock with no lock, missing start/end,
   end unreachable, unlock dims not a permutation, floating overlay).
3. **N5c then N5d** guide-line polish (jump cost scales with void width; line origin at tile edge).
4. **Closing/airlock gate** candidate (new `closes` link kind) -- see task list Link layer Candidates.

---

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
