# Handoff, 2026-06-12

## Headline: VALIDATION GATE PASSED (user authored 3 levels; "the loop can work"). Pre-authoring fixes done, plus two playtest-notes batches (audio, noise muffling, wall restyle, camera, controller revision, editor QoL, ink-trail fix). NEXT = user keeps playtesting and feeding notes; tuning dials below.

## Gate result
The user built 3 levels in the editor and judged the reactive-stealth loop workable. Still
playtesting; expect more note batches. Phase 8.5's gate and pre-authoring items are ticked in
the game-dev task list.

## What happened this session
- **Pre-authoring fixes**: contiguous wall cells merge into one Wall* body (greedy rect cover;
  the shader's MAX_WALLS=16 now counts regions, not cells); loader rejects version != 1; enemy
  vision samples the cuboid's full height (tall cube is seen over a 1u wall; also closes the
  old safety_edge see-over item). **Latent bug found**: runtime add_child auto-names children
  ("@MeshInstance3D@25"), so player._push_walls_to_shader's name lookup found nothing: painted
  levels had ZERO shader wall occlusion since the data-driven pivot. Fixed with an explicit
  mesh.name in the loader.
- **Notes batch 1**: STEP_GAIN 0.4 on the player's own step audio (noise radius untouched);
  NOISE_WALL_MUFFLE 0.45 (a wall-blocked sound path cuts heard radius; a knock's origin is
  inside the knocked wall and rays skip the shape they start in, so knock carries through its
  own wall but further walls muffle it); camera defaults to 45 deg and the chosen angle
  persists via a static across restarts and levels; editor grid plane trails the cube
  (infinite canvas); READY/menus polish carried from last session held up.
- **Controller revision (user call)**: RB = extend-up (extend cluster on the right), RT =
  collapse, LB/LT = camera tilt up/down, B FREED in gameplay; editor erase = B (L3 unbound).
- **Ink-trail fix** (user-reported alcove loop): trail memory. The enemy records the freshness
  (alpha) of the newest print it has investigated; only strictly fresher prints can retarget
  it. _trail_alpha decays at the print fade rate so a cleared trail stays cleared while
  genuinely new prints still trigger. Kills the walk-the-trail-backwards INVESTIGATE/PATROL
  ping-pong.
- **Notes batch 2 (wall look)**: dedicated STATIC wall shader (shaders/wall.gdshader +
  wall_material.tres): thin per-cell lines on top (no gradient halo), floor-slab side styling,
  and NONE of the floor's dynamic overlays, so waves/cones no longer paint wall tops. Wall
  boxes extend down to the floor tiles' bottom (risen-tile read, no void gap beneath).
  GOTCHA learned: the floor's look lives in grid_ground_material.tres PARAMETER OVERRIDES, not
  the shader defaults; copy instance values when cloning a look. Safety edges deliberately
  have NO tile (user affirmed the pattern: boundary marker, not terrain). Editor: B/X/Backspace
  erase now mirrors place (tap = footprint top layer, hold = rectangle with red preview).

## Tuning dials the user may ask to turn
- player.gd STEP_GAIN (0.4), KNOCK volume (still full).
- enemy_sphere.gd NOISE_WALL_MUFFLE (0.45), DETECT_* table (untouched, tuning pass pending).
- camera_controller.gd ELEV_DEFAULT (0.7854 = 45 deg).
- wall_material.tres line params (top core 0.008 vs floor's 0.005; sides match floor exactly).

## Controls (current)
Game pad: left stick/dpad move, right stick extend w/d, RB extend-up, RT collapse, A dodge,
X sprint, LB/LT camera tilt, Start pause; B unused in gameplay. Menus: A accept, B back,
WASD/arrows/dpad navigate. Editor: A place (hold = rect), B/X/Backspace erase (hold = rect;
path authoring: undo node), Y/Tab menu, Back/grave None, RT collapse brush, F5 finish,
P playtest, Start/Esc exit (session auto-saved; main menu Editor > Continue restores).

## NEXT
1. User continues playtesting; act on the next notes batch.
2. Post-gate queue when notes settle: paint-model revision ONLY if authoring keeps hurting;
   tall-for-intel player side (see over 1u walls when extended up); UI button-prompt overlay.
3. Start sketching the progression/save phase (task-list Deferred flags it as must-have before
   level-set production).

## Open / loose (carried)
- DEBUG_DETECTION still true in enemy_sphere.gd (remove when the detection tuning pass starts).
- Pause in a normal level still insta-quits the run (editor side is safe); pause menu deferred.
- One global extend-lock per level (link layer pending); editor warns, loader syncs stale unlocks.
- Editor preview vs loader drift (shared LevelBuilder) grows with each object type.
- Gate fence corners: translucent post/panel overlap seams (cosmetic).
- Tab can be eaten by GUI focus; Y is the robust menu open.

## Verify recipe (`~/.local/bin/godot` v4.6; exit code 0 even on errors, so grep)
- Parse: `godot --headless --editor --quit 2>&1 | grep -E "SCRIPT ERROR|Parse Error|SHADER ERROR|Busy"`
- Smoke: `godot --headless --quit-after 120 res://<scene>.tscn 2>&1 | grep -iE "ERROR|nil|invalid|cannot|failed"` (filter vulkan/audio/display/leaked)
- Headless can't press keys: drive editor/enemy methods from a throwaway `extends SceneTree`
  script run with `-s`. `await process_frame` after add_child or @onready refs are Nil.
  Compare PackedFloat32Array values with a tolerance (float32 truncation). Delete the script
  and its `.uid` after.

## Memory
- Updated `project_control_remap_plan` (revised pad layout). New `feedback_godot_runtime_gotchas`
  (runtime auto-naming breaks name lookups; .tres overrides shadow shader defaults). Editor
  model memory still current except erase = B. Plus the standing cube memories.
