# Handoff, 2026-06-18 (session 3)

## Headline: a big clearing session. Enemy pursuit feel-tuning, PROMOTED tutorials 1-5, cleared the whole editor-QoL backlog (N4/N6/N7) and the whole presentation backlog (N10/N9a/N9b/N1), then triaged a fresh notes batch and shipped 3 of its 4 (N14 blocker, N13, N12). Only N11 (Next Level button) is left from that batch. Everything is committed + pushed. The dev is now exploring/verifying; the FEEL-CHECKS below are the next-session agenda.

## PENDING FEEL-CHECKS (the dev verifies these next time; all shipped but eyes/ears not yet on them)
Every item below is live in code and headless-verified, but needs the dev's in-game judgement. Tunable knobs named so they can be dialed without re-deriving.
- **Enemy pursuit (commit 6d2bc5d):** speed RAMPS to pursuit speed over ~0.6s instead of snapping (`SPEED_RAMP` u/s^2); pursuit is STICKIER, ~3.3s of lost sight before de-escalating (`DETECT_PURSUIT_DRAIN_RATE` 0.2, `DETECT_PURSUIT_KEEP` 0.35); blending directly in front of an active pursuer no longer escapes (only blending out of sight works).
- **Editor dodge (N4, 41ae8f0):** dodge works in the editor under the None tool (judge distance, move faster).
- **Presentation (76b34cc, 7513ccb):** scan-line beam replaces the ghost (state-tinted, NOT flat red, my call, one-liner to force red); blend matches the wall colour now (`COLOR_WALL_SIDE`); dodge chime is a bell pluck (distinct from the alert sting); breathing edge glow while blended+idle (`BLEND_PULSE_AMOUNT` 0.3, `BLEND_PULSE_RATE` 0.4Hz).
- **N12 guard vision (4e15ceb):** sprinting across a guard's FRONT now gets you caught; slipping behind/side still works. Tunables `AIM_TURN_RATE` 11, `VIEW_CONE_COS` 0.643 (50deg), `DETECT_FILL_RATE` 2.5. Dial down if guards feel too sharp.
- **N14 (85e19ed):** CONFIRM AGAINST THE REPRO -- two locks of DIFFERENT shapes, each with its own unlock, should now both unlock. (Fix assumes a second LOCK exists for the second unlock's shape; if the repro was two unlocks for ONE lock, that needs the link layer instead.)
- **N13 (0d990a6):** type a level name in the editor and hit R/F -- camera should stay put; R/F also shouldn't move the camera while any menu is open.

## What shipped (cube repo, all on main, pushed)
6d2bc5d enemy pursuit feel | 30b939d tutorials 1-5 promoted | 41ae8f0 editor QoL N4/N6/N7 |
76b34cc presentation N10/N9a/N1 | 7513ccb presentation N9b | 85e19ed N14 | 0d990a6 N13 | 4e15ceb N12

## Tutorials promoted (the level-set spine moved)
Tutorials 1-5 (Movement, Sphere, Extension, Blend, Ink) are in res://levels/data/tut_0N_*.json and
registered in tutorials_menu.gd, teaching order. Dev said more tutorials to add later; Tutorial 6
(detection+pursuit capstone) still to build. KEY DISCOVERY: the dev runs Godot on WINDOWS, so user://
is `/mnt/c/Users/steve/AppData/Roaming/Godot/app_userdata/Cube/levels/`, NOT the WSL `~/.local/share/godot`
(that's only the headless Godot's userdata and looks empty). Match levels by `meta.name` inside the JSON,
not filename (move.json is a scratch "Move"). Saved to memory project_tutorial_pipeline.

## Notes batch (2026-06-18) -- triaged + filed in game-dev/Cube Game Tasks.md, 3 of 4 done
- N14 [BLOCKER, done]: 2nd unlock of a different shape was clobbered to the first lock's dims. Loader
  now keeps an unlock's dims if they match ANY lock (sequential multi-shape puzzles on the single
  global lock state). REAL FIX still open: explicit lock<->unlock LINK LAYER (also fixes N5 guide
  lines + catches mis-sequenced softlocks). Not yet a formal task beyond the N14/N5 anchors.
- N13 [done]: camera R/F gated on no visible focused Control.
- N12 [done]: guard-vision tightening (option B, dev-chosen). Diagnosis + numbers in the task list.
- **N11 [ONLY OPEN ITEM]: "Next Level / Tutorial" button on the level-complete screen.** Not started.
  Needs decisions: ordering source (tutorial order vs levels-menu order), and end-of-set behaviour
  (back to menu? grey out?). The complete screen is the results panel (see level.gd show_success path
  + the cube-display success faces). Small.

## NEXT (pick ONE)
1. **N11** -- finish the notes batch (the Next Level button). Small, mostly mechanical + 2 small choices.
2. **Tutorial 6** capstone -- now unblocked (tutorials promoted, enemy correct).
3. **Link layer** (real N14/N5 fix) -- explicit lock<->unlock pairing; bigger, currently only anchored.
4. Whatever the dev's feel-checks surface as needing a tune.

## Verify recipe (`~/.local/bin/godot` v4.6; exit 0 even on errors, so grep). FROM cube DIR.
- Parse: `godot --headless --editor --quit 2>&1 | grep -E "SCRIPT ERROR|Parse Error|SHADER ERROR"`
  (NOTE: this also parses any throwaway `_*.gd` test scripts in the dir -- clean them up or a test
  bug shows here.)
- Logic test: throwaway `extends SceneTree` with `-s`; instantiate painted_level.tscn, set
  LevelLoader.requested_file BEFORE adding it, await ~3 frames (build is call_deferred), find_child
  the nodes. Template pauses the tree, so call a node's per-frame methods directly to test logic
  (used this for N6/N9a/N10/N12/N14; N7/N13 drove Input via action_press + process_frames). Clean
  up the .gd + .uid + any user://*.json after.
- Gotcha hit this session: `focus` is a reserved/built-in name -- don't use it as a local var (parse error).

## Memory updated this session
- project_tutorial_pipeline: corrected the user:// path to the Windows side; match by meta.name.
- Followed feedback_notes_intake for the batch (triage-first, blocker exception). No new memories needed.
