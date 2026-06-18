# Handoff, 2026-06-18 (session 4)

## Headline: short, focused session. Promoted the last two tutorials (Dodge, Convergence),
then fixed the two enemy bugs the dev hit playtesting Convergence: pursuit couldn't catch
you in a hide spot (N15) and the guard snapped to the freshest footprint anywhere in range
(N16). Both fixed + headless-verified. The tutorial set is now SEVEN, all promoted.
Everything committed + pushed. The dev verifies the feel-checks below next.

## PENDING FEEL-CHECKS (shipped + headless-verified, but the dev hasn't eyed/eared them yet)
This session:
- **N15 (pursuit catch-in-cover):** get spotted, run into a hide spot with a guard right
  behind you -> it should now walk IN and catch you (blend is not an escape from an active
  pursuer). Then break line of sight FIRST (drop the guard out of PURSUIT) and tuck into
  cover -> it should lose you and search AROUND the cell as before. The hide spot still
  protects against unaware/searching guards; just not one actively chasing you into it.
- **N16 (footprint trail-following):** lay an ink trail, get a guard searching (INVESTIGATE)
  -> its rotating search beam should sweep and pick up prints one at a time as the beam
  crosses them, walking the trail, instead of instantly whipping toward the newest print.
  Knob if pickup reaches too far: FOOTPRINT_VIEW_RADIUS (5u) in enemy_sphere.gd.
- **Tutorials 6 (Dodge) + 7 (Convergence):** play them from the Tutorials menu; confirm they
  load and teach right. Convergence is the detection+pursuit capstone and now benefits from
  the N15/N16 fixes (it was the level that surfaced them).

Still pending from session 3 (not re-verified): enemy pursuit feel (6d2bc5d), editor dodge
(N4), presentation N10/N9a/N9b/N1, N12 guard vision, N13 editor camera, N14 multi-shape locks.

## What shipped this session (cube repo, on main, pushed)
- Promote Dodge + Convergence as tutorials 6 and 7 (tut_06_dodge.json, tut_07_convergence.json
  copied from the Windows user:// path; registered in tutorials_menu.gd). Set is now 7.
- N15 [stealth integrity]: _cell_blocked (enemy_sphere.gd) marked any is_hiding player's cell
  nav-blocked in EVERY state, so a pursuer's A* snapped to the adjacent cell and _follow_path
  refused the final step -> it parked next to you forever while still seeing through blend.
  FIX: gate that block on `_state != State.PURSUIT`, symmetric with the line-622 vision rule.
- N16 [naturalism]: _visible_footprint_pos dropped the cone in INVESTIGATE and grabbed the
  freshest print in a 5u circle (incl. behind it). FIX: cone-gate pickup in every state;
  INVESTIGATE now gates on its rotating search beam via a new shared _search_beam_dir() helper
  (so visible == detectable). Player-BODY detection in INVESTIGATE stays 360 (unchanged).

## Verification done (headless, ~/.local/bin/godot v4.6)
- Parse clean after each change.
- N15: a throwaway test confirmed _cell_blocked on a hiding cell is true in SUSPICIOUS,
  false in PURSUIT (floor/wall checks precede the gate, so a bad cell would block in both
  and fail -> the flip is purely the hiding gate).
- N16: a throwaway test planted a print, proved it valid via the PATROL forward cone, then
  in INVESTIGATE showed the search beam aimed AWAY no longer picks it up while aimed AT it does.
- Both test scripts cleaned up (.gd + .uid removed).

## OPEN / NEXT (pick ONE)
1. **N11 [flow QoL, the only open item from the 06-18 batches]:** "Next Level / Tutorial"
   button on the level-complete screen. Small + mostly mechanical. Needs 2 decisions: ordering
   source (tutorial order vs levels-menu order) and end-of-set behaviour (back to menu? grey
   out?). Complete screen = the results panel (level.gd show_success path).
2. **N5 [older backlog]:** lock-to-gate guide line beelines over a void gap; also no editor
   preview for these lines, and only one global lock per level until the deferred LINK LAYER.
3. **Link layer** (real N14/N5 fix): explicit lock<->unlock pairing. Biggest; only anchored.
4. Whatever the feel-checks above surface as needing a tune.

## Verify recipe (~/.local/bin/godot v4.6; exit 0 even on errors, so grep). FROM cube DIR.
- Parse: `godot --headless --editor --quit 2>&1 | grep -E "SCRIPT ERROR|Parse Error|SHADER ERROR"`
  (also parses throwaway _*.gd test scripts in the dir; clean them up or a test bug shows here).
- Logic test: throwaway `extends SceneTree`; set LevelLoader.requested_file, instantiate
  painted_level.tscn, add_child, await ~6 frames (build is call_deferred), find the nodes
  (_find_with_method recursion by a unique method name works well). To plant a print:
  player._add_footprint(Vector2(x,z)). To drive enemy state: set _state (PATROL 0, SUSPICIOUS
  1, INVESTIGATE 2, PURSUIT 3), _detection, _aim_dir, _investigate_sweep_angle, then call the
  private method directly. TYPE-ANNOTATE locals off untyped node access or inference fails.
  Clean up the .gd + .uid after.

## Tutorial pipeline (unchanged, see memory project_tutorial_pipeline)
Dev saves a level in the editor (lands on the Windows user:// path
/mnt/c/Users/steve/AppData/Roaming/Godot/app_userdata/Cube/levels/<slug>.json), says "X is
tutorial N"; copy to res://levels/data/tut_0N_*.json + register in tutorials_menu.gd. Match by
meta.name inside the JSON, not filename.

## Memory updated this session
- project_tutorial_pipeline + MEMORY.md index: set is now SEVEN, all promoted.
- Followed feedback_notes_intake for the batch (triage-first, filed N15/N16, then executed).
