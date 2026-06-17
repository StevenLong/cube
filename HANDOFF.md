# Handoff, 2026-06-17 (session 2)

## Headline: stood up a notes-intake protocol, then cleared the whole Phase 10 enemy/detection spine (N2, N8, N3) from the dev's playtest batch. N2 and N8 confirmed in playtest; N3 verified headless (feel-check pending). The dev also finished tutorials 1-5, but their files are not on this machine yet, so promotion is still blocked.

## Notes-intake protocol (new standing rule)
The dev wanted batches of notes triaged into a plan instead of derailing each session.
Agreed protocol (saved as memory feedback_notes_intake): on a notes batch, itemize ->
classify -> flag urgency -> ask clarifications (batched) -> file into the task list with
a proposed order -> pick ONE spine. Triage is the deliverable; never implement from notes
in the same pass; notes never change the active spine unless flagged Blocking and approved.

## Playtest batch triaged (game-dev/Cube Game Tasks.md)
10 items filed. Phase 10 (the dev's chosen spine) = N2 + N8 + N3, now DONE. The rest is in
a Backlog section: N4 (editor dodge), N6 (ink implies floor), N7 (place input buffering),
N10 (remove last-known ghost, add a LoS scan line), N9a (blend colour match), N9b (blend
idle animation), N1 (dodge chime clash), N5 (guide line beelines over a gap in PLAY).

## Phase 10: enemy/detection correctness (DONE, all in enemy_sphere.gd)
- **N2**: vision cone decoupled from movement facing. New `_aim_dir` + `_update_aim`
  (called at the top of `_process`): locks onto the last-seen cell in any alert state,
  follows body forward in patrol (drifting toward a rising suspect as a telegraph). BOTH
  the detection test (`_is_seeing_player`, footprint cone) and the visual cone
  (`_update_cone_uniforms`) read it, so visible == detectable. Killed the corner-reroute
  oscillation. Side effect (intended): once alerted, circling behind a guard no longer
  drops detection; only breaking LoS or leaving range does. Dev confirmed fixed.
- **N8**: `_visible_footprint_pos` skips any print on a cell the player currently occupies
  (`_player.footprint_covers`), so the fresh print under a hidden cube stops pinning the
  search onto the exact hiding spot and re-triggering alerts. Trail behind still followed.
  Dev confirmed fixed.
- **N3**: pursuit-speed floor. In `_pursue`, `pmult = maxf(PURSUIT_SPEED_MULT, PURSUIT_SPEED
  / speed)`, so pursuit is at least PURSUIT_SPEED (4.5 u/s) whatever the patrol speed; a
  fast guard keeps `speed * mult`. Walk is 3.33 u/s (1/TUMBLE_DURATION), sprint 6.67.
  Measured pursuit 4.39 u/s (was 2.70, slower than walk). FEEL-CHECK PENDING; tune
  PURSUIT_SPEED if a chase feels too sticky or too easy.

## Tutorials (still the level-set spine)
- Tutorials 1-5 AUTHORED by the dev (Movement, Sphere, Extension, Blend, Ink), but the
  .json files are NOT on this machine. user:// does not sync across the dev's two machines.
  To promote: bring the 5 files from ~/.local/share/godot/app_userdata/Cube/levels/ into
  the cube repo (then git carries them), or paste the JSON. Then copy into
  res://levels/data/tut_0N_*.json + register in tutorials_menu.gd TUTORIALS.
- Tutorial 6 (Detection + pursuit capstone) should be built AFTER promotion, now that the
  enemy behaves correctly.

## NEXT (pick ONE; Phase 10 is closed)
1. **Promote tutorials 1-5** once the files reach this machine (quick, finishes the spine).
2. **Backlog spine: editor QoL** (N4 + N6 + N7) to smooth authoring. N4 cause is known
   (editor sets god_mode true; dodge gate blocks on it).
3. **Backlog spine: presentation** (N10 ghost -> scan line, N9a blend colour, N1 audio).
4. **Tutorial 6 capstone** (after promotion).
5. **N5 guide-line pathfinding** (PLAY-time BFS falls back to a straight line across a gap).

## Verify recipe (`~/.local/bin/godot` v4.6; exit 0 even on errors, so grep). FROM cube DIR.
- Parse: `godot --headless --editor --quit 2>&1 | grep -E "SCRIPT ERROR|Parse Error|SHADER ERROR"`
- Scene smoke: `godot --headless --quit-after 30 res://painted_level.tscn 2>&1 | grep -i "SHADER ERROR"`.
- Logic: throwaway `extends SceneTree` with `-s`; add a LevelLoader, set
  LevelLoader.requested_file, await ~10 frames (build is call_deferred), find_child the
  nodes. The template's Level pauses the tree on _ready, so to test a node's per-frame
  logic call its method directly (e.g. enemy.call("_pursue", dt)) rather than relying on
  _process. Clean user://*.json after; delete the script + .uid when done.

## Memory updated this session
- Added feedback_notes_intake (the triage protocol) and project_tutorial_pipeline (promotion).
- Standing cube/save/glass memories unchanged.
