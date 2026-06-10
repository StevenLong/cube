# Handoff, 2026-06-10

## Headline: audit done (verticality CUT, docs synced); editor slice 4 done (patrol + gate node paths, lock/unlock variants); user-notes batch fixed (nav void, menus, READY, editor session/Continue). NEXT = pre-authoring fixes, then the 3-LEVEL VALIDATION GATE.

## What happened this session
- **Audit** (user asked for blind spots): three findings: content drought (nothing has validated
  the core loop), a verticality gap, and scaling caps. The user then **cut verticality entirely**
  (platforms/ledges/climbing/jump = sequel). Docs updated: Cube Game.md (Decisions Log entry,
  gap bridge + periscope replace bridge-and-trap, elevated interactable shelved, user leans
  keep-shelved) and tasks (new **Phase 8.5** with the plan below, Deferred additions).
- **Slice 4, editor objects**: patrol paths authored by node (A = start/add, A on last node =
  finish, X/LT = undo, tap-tap = stationary guard); **Lock Zone + Unlock Zone** menu variants
  (mode stays a param, file format unchanged); serializer min-corner shift now covers node lists
  (waypoints were silently wrong for levels not anchored at 0,0).
- **User-notes batch**: enemy off-grid motion (pursuit corridor, final straight approach, per-step
  backstop) now requires floor, no more floating over gaps; `follow_focus` on tool + levels menu
  scrolls; **WASD added to ui_*** (arrows + dpad kept; overrides in project.godot); **READY
  releases on ANY gameplay press** (move/extend/collapse/dodge/sprint), event-driven so the
  opening input applies the same frame; **editor auto-saves a session on every exit**
  (`user://_editor_session.json`) and the main menu Editor button is now a submenu:
  **Continue / New Level / Edit a Level**; the playtest return restores the session (also fixes
  the old scratch-file overwrite reprompt).
- **Regression fixes** (user caught all three): **UNLOCK dims check restored**: tumbling
  reorients a locked shape, so arrival orientation is a real demand; the softlock guard moved to
  the loader, which rewrites only unlock dims that are NOT a permutation of the lock's
  (permutations are reachable by tumbling; editor warns when stamping an unreachable shape).
  **Zones stamp at the footprint MIN corner** (grid_pos is the base cell and diverges when
  extended left/fwd, which offset the ghost). **Gates reworked to node fences**: 0.4u post per
  node + 0.2u panel between consecutive nodes, height captured from the cube at the first node
  (extend up first for taller), authored exactly like patrol paths (one shared code path);
  diagonal panels just rotate; hold-open samples every cell under the fence. level_01's gate is
  now a door frame (posts in the flanking walls, panel across the corridor).

## Editor controls (current)
Move/extend = drive + shape the cube. **Y/Tab** = tool menu (Lock and Unlock zones are separate
entries). **A/Enter** = place; paint tiles: hold-drag = rectangle; path tools (Patrol Guard,
Gate): A = add node, A on last node = finish, X/LT = undo node. **B** = collapse. **Back/grave**
= None. **X/Backspace/LT** = erase footprint. **F5** = finish/name. **P** = playtest.
**Start/Esc** = exit to menu (session auto-saved; Continue restores).

## NEXT (tasks Phase 8.5)
1. **Pre-authoring fixes**: merge contiguous wall cells into one Wall* body (player.gd
   MAX_WALLS=16 caps the ground shader's occlusion list; per-cell bodies blow past it silently);
   loader checks the JSON "version" field; enemy vision samples the cuboid's TOP cells so a tall
   cube pokes visibly over a 1u wall (periscope symmetry; also folds in the safety_edge see-over).
2. **VALIDATION GATE: author 3 levels in one session.** Editor exit criterion AND the first real
   test of whether reactive stealth is fun. Findings decide everything after.
3. Post-gate: paint-model revision (only if authoring proved it blocking), tall-for-intel player
   side, UI button-prompt overlay.

## Open / loose (carried)
- Gate fence corners: post/panel overlap shows seams through the shared translucent material (cosmetic).
- Still one global lock per level (link layer pending); editor warns, loader syncs stale unlocks.
- Pause in a normal LEVEL still insta-quits the run (the editor is safe now); pause menu deferred.
- DEBUG_DETECTION still true in enemy_sphere.gd (remove when tuning starts).
- Tab can be eaten by GUI focus; Y is the robust menu open.
- levels/data/editor_test.json stray was deleted this session.

## Verify recipe (`~/.local/bin/godot` v4.6; exit code 0 even on errors, so grep)
- Parse: `godot --headless --editor --quit 2>&1 | grep -E "SCRIPT ERROR|Parse Error|SHADER ERROR|Busy"`
- Smoke: `godot --headless --quit-after 120 res://<scene>.tscn 2>&1 | grep -iE "ERROR|nil|invalid|cannot|failed"` (filter vulkan/audio/display/leaked)
- Headless can't press keys. A throwaway `extends SceneTree` script run with `-s` drives editor
  methods directly; ADD NODES BEFORE USING THEM ACROSS A FRAME: `await process_frame` after
  add_child or @onready refs are still Nil. Delete the script + its `.uid` after.

## Memory
- Updated `project_editor_interaction_model` (slice 4 done, gate = node fence, session/Continue,
  new NEXT) and `project_design_direction_v02` (verticality cut). Index updated. Plus the
  standing cube memories (read-HANDOFF-first, no dashes, no co-author trailer, commit cadence,
  Wall* nav, etc.).
