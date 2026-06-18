# Handoff, 2026-06-18 (session 5)

## Headline: short session. Built N11, the only open flow-QoL item: a "Next" button on
the level-complete (success) screen that steps through whichever menu's set launched the
level. Two decisions resolved with the dev: it appears in BOTH menus (each passes its own
ordered list), and it's HIDDEN on the last entry of a set. Parse-clean + logic-tested
headless. Committed + pushed. The dev feel-checks it next.

## PENDING FEEL-CHECKS (shipped + headless-verified, but the dev hasn't eyed/eared them yet)
This session:
- **N11 (Next button):** clear a tutorial from the Tutorials menu -> the success panel shows
  "Next Tutorial" (top button, above Restart) and it loads the next one in order; on tutorial 7
  (Convergence) the button is gone, just Restart / Quit. Same in the Levels menu ("Next Level":
  Crossing -> user levels in the order the menu lists them). Confirm the extra button sits
  cleanly in the fixed-size panel and that gamepad/keyboard focus lands on Next when it's shown.
  Should NOT appear on a Caught/Fell/Wedged end, nor during an editor playtest (P).

Still pending from session 4 (not re-verified): N15 (pursuit catch-in-cover), N16 (footprint
trail-follow), tutorials 6 (Dodge) + 7 (Convergence) load+teach.
Older, still pending: enemy pursuit feel (6d2bc5d), editor dodge (N4), presentation
N10/N9a/N9b/N1, N12 guard vision, N13 editor camera, N14 multi-shape locks.

## What shipped this session (cube repo, on main, pushed)
- N11 [flow QoL]: Next button on the success results panel (commit 3525577).
  - level_loader.gd: two new statics, `sequence: Array[String]` (the active set's ordered file
    paths) and `sequence_noun` ("Level"/"Tutorial"). Persist across reloads like requested_file.
  - tutorials_menu.gd / levels_menu.gd: each `_play` now sets `sequence` from its own list
    (tutorials in TUTORIALS order; levels = BUILTINS then _user_level_files(), the row order)
    plus the noun, before launching painted_level.
  - level_template.tscn: hidden NextButton added above RestartButton in ResultsPanel/VBox.
  - level.gd: resolves/connects NextButton; `_enter_complete` shows it (with the noun) only when
    `_has_next_level()` (in a set, not last, not return_to_editor); `_next_level()` advances
    requested_file to the next entry and reload_current_scene (same mechanism as Restart);
    `_show_results` focuses Next when shown, else Restart. Only _enter_complete ever shows it, so
    the loss screens leave it hidden by default.

## Verification done (headless, ~/.local/bin/godot v4.6)
- Parse clean before and after.
- Throwaway extends-SceneTree test: instantiated painted_level with a tutorial set, awaited the
  deferred build, confirmed _result_next resolves at ResultsPanel/VBox/NextButton and starts
  hidden, and that _has_next_level() == true for a middle entry, false for the last entry, false
  for an off-set requested_file, and false when return_to_editor is set. Test .gd + .uid removed.

## OPEN / NEXT (pick ONE)
1. **Feel-checks** above (N11 this session; N15/N16/tut6/tut7 from session 4) -- cheapest to
   close out, all just need the dev to play.
2. **N5 [older backlog]:** lock-to-gate guide line beelines over a void gap; also no editor
   preview for these lines, and only one global lock per level until the LINK LAYER.
3. **Link layer** (real N14/N5 fix): explicit lock<->unlock pairing. Biggest; only anchored.

## Verify recipe (~/.local/bin/godot v4.6; exit 0 even on errors, so grep). FROM cube DIR.
- Parse: `godot --headless --editor --quit 2>&1 | grep -E "SCRIPT ERROR|Parse Error|SHADER ERROR"`
  (also parses throwaway _*.gd test scripts in the dir; clean them up or a test bug shows here).
- Logic/UI test: throwaway `extends SceneTree`; set LevelLoader statics (requested_file, and now
  `sequence`/`sequence_noun` for the Next button), instantiate painted_level.tscn, add_child,
  await ~8 frames (build is call_deferred), recurse to the node by name (`Level`, `NextButton`).
  Calling level._enter_complete() WRITES a save record (skips only return_to_editor), so prefer
  calling the pure helpers (_has_next_level) directly over driving the full success path.
  TYPE-ANNOTATE locals off untyped node access or inference fails. Clean up the .gd + .uid after.

## Tutorial pipeline (unchanged, see memory project_tutorial_pipeline)
Dev saves a level in the editor (lands on the Windows user:// path
/mnt/c/Users/steve/AppData/Roaming/Godot/app_userdata/Cube/levels/<slug>.json), says "X is
tutorial N"; copy to res://levels/data/tut_0N_*.json + register in tutorials_menu.gd. Match by
meta.name inside the JSON, not filename.

## Memory updated this session
- None needed (N11 is ordinary feature work; the mechanism lives in the code + this handoff).
