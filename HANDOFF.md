# Handoff

## Session 12 (2026-06-27): Glass fix + PITFALL tiles + ECHO PYRAMID enemy built; Exposed/overheat GRILLED (not built)
Stage 1 toolkit work. Four things shipped, one design fully settled and queued.

GLASS-BLEND FIX (commit c1322b4) -- the filed exploit. `_extend_cell_clear` gained `ignore_glass`; the
cover probes `_column_walled`/`_row_walled` (player.gd) pass it so a glass-only cell reads CLEAR (can't hide
behind a window), while extension-collision callers keep glass solid. Glass already in group "glass". Headless
branch test green. Feel-check still owed (30s: cube flanked by glass = no blend; by real walls = still blends).

PITFALL TILES (commits 3631cdf, 37e81da, 2c75602) -- BUILT + dev-driven, "good for now". New `pitfall`
BASE_TILE (glyph p): walkable floor that breaks when the cube's WHOLE footprint vacates it -> ordinary void.
ONE mechanism: footprint-before/after diff on every settle (tumble/collapse/extend/dodge); a dodge also breaks
pitfalls it sweeps OVER (dev's call). Player-only trigger; a broken cell blocks enemies free via live is_floor.
Each break = a moderate ~5-cell noise ping with the player-step wave ring + a low crumble (own _crumble_player,
since a tumble plays a step the same frame). Loader tags tiles group "pitfall_tiles"; level.gd break_pitfall()
erases floor + frees tile. Verified headless (unit + full-pipeline smoke). OPEN: amber telegraph visual needs
work (-> UI/UX pass); the 5-cell ping radius "feels a bit much", first knob to lower after more play.

ECHO PYRAMID enemy (commits 24ae5ca, 43447c7, 2184843) -- BUILT, design grilled first. Stationary FLOATING
sonar pylon that DEFEATS COVER (the sphere's opposite: non-visual, immobile, no LoS). Fixed-beat pulse: charge
tell, then a detection FRONT expands centre->R; caught the instant it reaches your cell inside R (edge =
dodge out ahead, centre = near-instant). On a CATCH, every guard CURRENTLY inside the radius gets your exact
position (enemy_sphere.reveal_player_at() -> reuses ungated _on_sound_heard -> _last_seen_pos + INVESTIGATE,
bypassing LoS/walls). No standalone fail, no global alert, no links; lone pyramid = inert. Recoverable: leave
the field. Registry OBJECT (per-instance radius+interval, editor auto-lists). Readout is drawn on the FLOOR
TILES via the ground shader (pyr_* uniforms, per-slot like cones; loader wipes slots each load): persistent
outer ring + a per-tile step-wave SCAN (after two visual reworks -- first floating meshes overhung void + the
TorusMesh was a glitchy diamond). DEMO LEVEL: user://levels/echo_pyramid_demo.json. KEY TUNABLE: front_speed
vs dodge distance. Verified headless (parse + smoke: proximity gate reveals in-range guard only). Feel-check
of the per-tile scan + an audio cue on catch still owed.

EXPOSED / OVERHEAT ON A CATCH -- GRILLED + FULLY SETTLED 2026-06-27, NOT BUILT (the obvious NEXT). Fixes:
blending currently shrugs off a catch (re-blend and vanish). Settled spec (full version + build hooks in the
task list "PYRAMID CATCH -> OVERHEAT + EXPOSED" item, and terms in GLOSSARY.md): a catch ALSO (a) OVERHEATS
(max dodge cooldown, no dodge) and (b) applies EXPOSED (force-break blend + block re-entry, no hide), both on
ONE shared timer = a new CATCH_OVERHEAT const (default DODGE_COOLDOWN 1.5s, tunable up), re-maxed per catch.
Only dodge+blend lock; walk/tumble/extend free (walk out exposed = the escape). Pyramid-SPECIFIC (not all
overheat). TELL: distinct red "Exposed" cube-display look. Build is small (apply_catch_overheat() + one
`wants_blend` condition + cube-display red state + the _on_catch call). I asked "green light to build?" -- not
yet answered; START HERE next session.

NEW THIS SESSION: GLOSSARY.md (repo root) -- a Domain-Driven-Design ubiquitous-language doc (dev's request).
Pins ambiguous/coined gameplay terms ([settled]/[proposed]/[contested]) before they drive a build; CLAUDE.md
points at it. Already settled: Blend, Cover, Catch (vs guard Detection), Echo Pyramid/Zone/Pulse/Scan, Dodge
cooldown, Overheat, Exposed, Worming. Keep it updated when coining/disambiguating terms (auto-memory
feedback_glossary_ubiquitous_language).

PARKED/OWED FEEL-CHECKS: glass-blend (30s), pitfall amber visual + ping radius, pyramid per-tile scan +
catch audio cue. Per-object grills still owed for: cylinder, floor button, closing gate, remote-noise, laser.

## Session 11 (2026-06-26): Link layer SLICE 6 (editor lint) DONE + endgame REPLANNED
Link layer is now COMPLETE end to end (all 6 slices + backfill retired).

SLICE 6 -- EDITOR LINT PANEL (committed 3cf82ca, marker tweak b0e0c07). Top-right ⚠ warnings Label in
editor.gd (`_compute_warnings`/`_update_warnings`, recomputed on a 0.5s timer so it never serializes/
BFSs on the per-frame readout path). Findings: no start, no end, orphan gate (no `opens`), orphan unlock
(no `released_by`), unlock shape not a permutation of its lock's, and end unreachable from start.
Reachability REUSES the loader's real router (LevelLoader._parse_base -> _walkable_cells/_blocked_cells
-> _route), so floor steps + void jumps + wall/edge blocking all count (no false "unreachable"). Orphan
checks iterate `_objects`, so a manually-placed id-less gate/unlock is flagged too. Verified headless
(4-case reachability test + parse-clean). USER feel-checked the panel: reads well; only change was the
warn marker `!` -> `⚠`. NOT in v1 (cheap to add): "floating overlay" (ink/water over void) -- loader
auto-floors overlay cells so it's harmless. Slice 6 marked done in the task list.

GODOT 4.7 BUMP (committed f4cbb1e). User opened the project in Godot 4.7 (was 4.6). One-line conversion:
config/features "4.6"->"4.7"; config_version stays 5, no scenes touched. NOTE: the WSL headless binary
`~/.local/bin/godot` is still 4.6 -- it opens the 4.7 project fine for parse/headless checks but prints a
version warning. Bump it to 4.7 only if a clean headless run is wanted.

ENDGAME REPLANNED (grill 2026-06-26) -- full plan is in the task list under "## Stage 1 - Alpha demo"
(CURRENT WORKSTREAM). Summary: engine/editor/link-layer/save/tutorials are all DONE, so the remaining
work is a 2-stage CONTENT plan, not a systems gap. STAGE 1 = expand the toolkit (2 enemy candidates
pyramid+cylinder, design-spec-then-build; 3+ props -- floor button, closing/airlock gate, remote-noise
button, laser/tripwire, PITFALL TILES) + a gizmo tutorial each, then ship an EXPORTED Windows build to an
alpha squad with a level-making + best-capstone-time contest (sharing/voting low-tech/external via the
existing user://levels menu + Discord; NO export_presets.cfg yet -- de-risk with a throwaway export EARLY).
STAGE 2 = fold in alpha feedback, amass content, polish to a price tag (this is the priced-release goal;
the 15-20 level grind + composites + cosmetics + new enemies all live here). An editor-usability pass
(readable control hints + sane bindings) gates the demo since strangers will author levels.

PITFALL TILES decided this session (collapsing floor; full SPEC in the task list): new BASE_TILE, breaks
when the cube's WHOLE footprint vacates it -> becomes ordinary void (impassable gap, not a death-fall).
PLAYER-only trigger (broken void blocks enemies for free via enemy_sphere's live is_floor check). Visibly
fragile from the start, breaks INSTANTLY on vacate. OPEN EDGE CASE flagged by the dev: does an extend-then-
collapse (shape-change) vacate count, or only a tumble? -> resolve in the pitfall spec pass.

EVENING NOTES (2026-06-26, triaged into the task list, NOT implemented):
- UI/UX not user-friendly -> widened the pre-demo polish item to a "UI/UX + accessibility pass
  (ALPHA-BLOCKING)": general UI cleanup + a SETTINGS menu (accessibility + user-facing control REMAPPING;
  collect the squad's remaps as feedback) + fold in the deferred control-scheme overhaul.
- WORMING: dev's emergent movement tech (extend-then-collapse repeatedly = silent fast travel). Exploitable
  but maybe a feature -- WATCH in alpha, don't preemptively nerf; reserve lever is an extend OVERHEAT reusing
  the dodge cooldown (single timer). Replaces the vague "movement tech" parked thread.
- BLEND between mismatched walls: ANSWERED (working-as-designed, no partial blend). _is_in_cover needs an
  opposite pair of sides walled to EXACTLY the cube's top height per-cell; mismatched heights can't both
  match so it just doesn't blend. Logged as a design note, no action.
- BLEND in GLASS: DECIDED no -- glass must NOT count as cover (it's see-through, so blending against it =
  invisible-behind-a-window, an exploit). Today it DOES (glass is a layer-1 Wall* solid). Fix filed in the
  task list: cover probe ignores group "glass", glass stays solid for movement. Small (~5-10 lines), do
  before alpha. NOT yet implemented.

PARKED THREADS: (1) WORMING (see evening notes) -- decide after alpha. (2) Per-object design grills owed
before building each enemy/prop (pyramid, cylinder, floor button, closing gate, remote-noise, laser/
tripwire, pitfall).

NEXT (obvious first move): the throwaway Windows export to de-risk distribution, or kick off the first
per-object design grill (pyramid or pitfall). Optional voice setup still pending the user's `sudo apt
install sox pulseaudio-utils` (WSL mic for the native voice skill; WSLg PulseServer is live).

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

BACKFILL RETIRED (2026-06-23, user approved): removed `_backfill_global_coupling` + `_has_lock_edges`
(level_loader) and the `lock_id==""` legacy mode (guide_line); `_wire_lock_links`/`_build_lock_links`
run the explicit path unconditionally. A no-edge lock level now wires nothing + draws no guide lines
(+ warns per id-less lock). Verified: parse clean, no shipped level affected (all 3 carry links), and
_wire_lock_links on real tut_07 nodes injects each gate/unlock to its own lock, no cross-talk. The
runtime is purely explicit-links-only now. COLLATERAL (accepted): 4 pre-wizard user:// scratch levels
went inert (convergence, extension, fun_game_1, my_level_2) -- re-author via the wizard if wanted.

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

OPEN / NEXT (pick ONE) -- link layer is now COMPLETE (slices 1-5 done + backfill retired)
1. **Slice 6** editor warnings panel (gate with no opener, unlock with no lock, missing start/end,
   end unreachable, unlock dims not a permutation, floating overlay). Now that the runtime is
   explicit-links-only, "id-less lock / unlinked gate" are real authoring mistakes worth surfacing.
2. **Closing/airlock gate** candidate (new `closes` link kind) -- see task list Link layer Candidates.
3. **N5c then N5d** guide-line polish (jump cost scales with void width; line origin at tile edge).
4. Optional: re-author the 4 now-inert user:// scratch levels (convergence, extension, fun_game_1,
   my_level_2) via the wizard, or delete them.

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
