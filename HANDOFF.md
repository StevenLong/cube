# Handoff, 2026-06-13

## Headline: third playtest-notes batch landed (dodge feel + cooldown HUD, input buffering, in-game pause menu + editor command menu for controller, quieter steps, wall-muffled... wait that was last time; this time: dodge priming/HUD, buffer, pause menus, step volume, knock gate, wave-clear, dodge-escape-by-geography). Loop validated; user is iterating on feel. NEXT = right-stick extend precision (drift), then continue playtest notes.

## What happened this session (all tested headless, NOT yet hand-tested by user beyond a first run)
- **Dodge (#1)**: holding dodge now LOCKS OUT tumbling (prime without stepping); a charged dodge
  fires on a direction, a cooling one holds still. New **DODGE recharge bar** (bottom-center of the
  level UI) fills as cooldown drains, bright when usable. Dodge also gated on `not god_mode` (fixes a
  latent editor-cursor dodge when holding A/place in free control).
- **Input buffering (#2)**: discrete shape presses (collapse + all extends) made mid-tumble are
  buffered (`_buf_action`/`_take_action`, 0.3s grace that does NOT expire mid-animation) and applied
  on settle instead of being dropped. Editor single/object placement is gated to fire only when the
  cube is settled (rect drag still begins settled then grows while tumbling). Movement TAPS are NOT
  buffered (held movement already chains) — easy follow-up if step-chaining feels off.
- **Controller menus (#3)**: in-game **pause menu** (Start/Esc: Resume / Restart / Quit) replaces the
  old instant-quit; **editor command menu** (Start/Esc: Resume / Playtest / Save / Quit) makes
  playtest+save reachable on the pad. Both controller-navigable. Caveat: editor Save overwrites
  silently once named; naming a NEW level still needs the keyboard once (no controller text entry).
- **Noise waves persisting (#4)**: cleared on spawn (`_reset_ground_overlays`, also zeros stale
  footprints from the shared material) AND on every game-over state (tree pauses there, so a live
  wave would freeze on the floor). New `clear_noise_waves()` on the player.
- **Dodge escape (#5)**: the enemy now tracks the cube's VISUAL position during a dodge, not the
  landing `grid_pos` (which snaps at dodge start). Dodge only shakes a pursuer when the geometry
  actually breaks line of sight — geography-dependent, as the user wanted. Code comment in
  enemy_sphere `_is_seeing_player` explains it; do NOT "fix" it back.
- **Steps too loud (#6)**: noise radius now `STEP_RADIUS_NORMAL = 2.5` / `STEP_RADIUS_SPRINT = 5.0`
  (+ extension), down from 4/8. Top-of-file constants, tune freely.
- **Knock on safety edges (#7)**: knock only fires against a full-height wall (`_has_tall_wall`,
  probes above the 0.4u edge top); safety edges and void no longer knock.
- **Editor tool menu (#8)**: focus now WRAPS (down past the bottom loops to top). Tiled-grid menu
  redesign still deferred (user said later).

## NEXT (priority order)
1. **Right-stick extend precision / drift** (user note 2026-06-13). The right stick is extend
   width/depth only (camera is on LB/LT now), so a generous deadzone is safe. Drift + diagonal
   axis cross-talk make isolating one axis hard. Candidate fixes, in order of effort: raise the
   right-stick extend action deadzones in project.godot (currently 0.5; try ~0.6-0.7, needs the
   user's feel); OR handle extend in code with dominant-axis filtering (only the larger axis
   registers) instead of per-axis InputMap events; OR move extend to the d-pad/face buttons. Dial
   the deadzone WITH the user, do not guess a value.
2. Continue acting on playtest-notes batches.
3. Post-gate queue when notes settle: paint-model revision (only if authoring keeps hurting);
   tall-for-intel player side (see over 1u walls when extended up); UI button-prompt overlay;
   progression/save phase (flagged must-have before level-set production).

## Tuning dials
- player.gd STEP_RADIUS_NORMAL (2.5) / STEP_RADIUS_SPRINT (5.0); INPUT_BUFFER_TIME (0.3); KNOCK full.
- enemy_sphere.gd NOISE_WALL_MUFFLE (0.45), DETECT_* table (still untuned).
- camera_controller.gd ELEV_DEFAULT (45 deg).
- level.gd DODGE_BAR_W / colors.
- project.godot right-stick extend deadzones (see NEXT 1).

## Controls (current)
Pad: left stick/dpad move, right stick extend w/d, RB extend-up, RT collapse, A dodge (hold = prime,
locks movement), X sprint, LB/LT camera tilt, Start pause menu; B = unused in gameplay / editor erase.
Menus: A accept, B back, WASD/arrows/dpad navigate. Editor: A place (hold = rect), B/X/Backspace erase
(hold = rect; path tools: undo node), Y/Tab tool menu (loops), Back/grave None, Start/Esc command menu
(resume/playtest/save/quit), F5 finish, P playtest.

## Open / loose (carried)
- HIDAPI "Error opening gamepad at index N" on launch = engine-level phantom-device warning (Steam
  build of Godot virtualizes pads); harmless, the real controller works. Not our code.
- DEBUG_DETECTION still true in enemy_sphere.gd (remove when detection tuning starts).
- Dodge bar + pause menu only in level_template (painted levels). Old tutorial/sandbox scenes lack
  them; level.gd resolves those nodes null-safely and falls back to exit-on-pause, so no crash.
- One global extend-lock per level (link layer pending); editor warns, loader syncs stale unlocks.
- Editor preview vs loader drift (shared LevelBuilder) grows with each object type.
- Gate fence corners: translucent post/panel overlap seams (cosmetic).

## Verify recipe (`~/.local/bin/godot` v4.6; exit code 0 even on errors, so grep)
- Parse: `godot --headless --editor --quit 2>&1 | grep -E "SCRIPT ERROR|Parse Error|SHADER ERROR|Busy"`
- Smoke: `godot --headless --quit-after 90 res://<scene>.tscn 2>&1 | grep -iE "ERROR|nil|invalid|cannot|failed"` (filter vulkan/audio/display/leaked)
- Logic: throwaway `extends SceneTree` run with `-s`; `await process_frame` after add_child (or
  @onready/refs are Nil); compare PackedFloat32Array with a tolerance (float32 truncation). For
  physics point/ray queries (e.g. `_has_tall_wall`) await ~6-8 frames so static bodies register.
  Delete the script + its `.uid` after.

## Memory
- No new memory this session; the durable design intent (dodge escape = geography, not a timer) lives
  as a code comment in enemy_sphere `_is_seeing_player`. Standing cube memories unchanged.
