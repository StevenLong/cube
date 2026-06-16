# Handoff, 2026-06-16

## Headline: lock-puzzle clarity + "infinite floor" visual pass, all from playtest feedback. Loop is validated; we're deep in feel/clarity iteration. Next direction is open (see NEXT) — likely per-face ink / cube-as-display or save/progression.

## State of the build
Core loop validated (3 levels authored, "the loop can work"). Editor is a full tool. Controls
reworked. Recent work has been playtest-driven polish, now mostly visual coherence and lock-puzzle
readability. Everything below is committed and pushed.

## What landed since the last handoff (commits e01a9f0, 7c6f0c1, 8c7debe; earlier batch 1c4deeb..a0deb75)
- **Perfect vision is the default** (LoS off; shader `player_los_enabled` / enemy `ENEMY_LOS_FADE`
  flags reserved for a future "blinded" debuff). Cones clip on walls from the enemy's viewpoint.
  Wall buffer raised to 64. (batch a0deb75)
- **Gate = raised/lowered floor tiles** (red grid, rises to block / sinks to walkable), no more
  bright ghost fence. End screens have Restart/Quit buttons + Back to Editor (playtest only).
  Anti-aliasing on (MSAA 4x + FXAA). Playtest "Quit to Menu" goes to the main menu. (batch a0deb75)
- **Extend-lock telegraph rework** (e01a9f0):
  - LOCK zone: quiet full-footprint marker + floating padlock icon (primitive placeholder);
    standing in the footprint swaps the icon for a ghost of the cube EXPANDING to the required
    shape, grown CENTERED on the footprint, ending exactly filling it.
  - UNLOCK zone: kept the persistent placement/orientation ghost cuboid, now hidden until the gate
    opens (player extend-locked).
  - Loader floors the full footprint of every lock/unlock zone (and gate span) so wide/deep shapes
    have ground; guide lines route to the CENTER cells of lock/gate/unlock.
- **Editor**: self-heals a stuck area-select highlight (stray preview is freed when no drag is
  active; `_create_preview` never orphans one). (7c6f0c1)
- **Infinite floor** (8c7debe): floor + walls are deep columns (60u visual mesh, shallow collision,
  is_floor unchanged) whose SIDES fade to the void colour from y=-0.5 to y=-45, so they dissolve
  into nothing instead of showing a bottom at steep camera angles. Void darkened to (0.03,0.03,0.04)
  everywhere, matching the shader fade target. Gate hides its tiles once fully sunk (no z-fight in
  the deep column).

## Pending the user's eyes (committed, visual, not yet confirmed in play)
- Gate red-tile look (rise/sink), AA, the new lock/unlock telegraphs, and the infinite-floor fade
  depth/darkness. Fade is tunable: `fade_start`(-0.5)/`fade_end`(-45)/`void_color` shader uniforms;
  `FLOOR_DEPTH`(60, loader) + FloorTile mesh depth must stay above fade_end and match each other.

## NEXT — direction to be decided this session
Candidates, roughly highest-value first:
1. **Per-face ink -> cube-as-display.** The inked-face info still isn't shown (gameplay gap), and it
   bootstraps the cube-faces-as-screens idea (state, expressions, debuff/timing readouts, maybe move
   the dodge cooldown onto the cube). Needs a per-face shader/material on the cube (currently one
   surface, one tint).
2. **Save / progression.** Completion tracking, per-level bests, par. Unblocks the level-intro/par/
   high-score screen and is needed before producing a level set. Bigger, touches results panel +
   levels menu + (later) cosmetics + optional objectives.
3. **Right-stick extend drift.** Carried friction; needs the user's hands to dial deadzone /
   dominant-axis filtering.
4. Smaller: icon system (padlock/key/droplet; primitive padlock placeholder exists); editor preview
   drift (gate/lock previews still show the OLD ghosts, != in-game); fade-to-void refinement if the
   infinite-floor look needs it.

## Tuning dials
- Infinite floor: shaders `fade_start`/`fade_end`/`void_color`; loader `FLOOR_DEPTH` + FloorTile mesh.
- player.gd STEP_RADIUS_*, INPUT_BUFFER_TIME, EXTEND_PROBE_Y, MAX_WALLS(64), camera ELEV_DEFAULT.
- enemy_sphere NOISE_WALL_MUFFLE, DETECT_* (still untuned); ENEMY_LOS_FADE / shader player_los_enabled (debuff).
- extend_lock_gate RAISE_TIME/RAISED_TOP/BOX_H; extend_lock_zone GHOST_GROW_TIME/ICON_*.

## Open / loose (carried)
- **Tutorials**: old hand-authored scenes; their end screen predates the controller/results rework.
  Rebuild as data levels in Phase 9 (fixes it for free). Also in Cube Game Tasks Phase 9.
- Editor previews for gate + lock zone still draw the OLD ghost shapes (preview != play).
- Cones clip on `Wall*` only, so a raised gate (named "Gate") doesn't clip the cone VISUAL (enemy
  real sight IS blocked by it via raycast). Add gates to the shader wall list if it reads wrong.
- One global extend-lock per level (link layer pending); editor warns, loader syncs stale unlocks.
- DEBUG_DETECTION still true in enemy_sphere.gd (remove when detection tuning starts).
- HIDAPI "gamepad index N" warning on launch = harmless Steam-build phantom-device noise.

## Verify recipe (`~/.local/bin/godot` v4.6; exit 0 even on errors, so grep)
- Parse/shader: `godot --headless --editor --quit 2>&1 | grep -E "SCRIPT ERROR|Parse Error|SHADER ERROR"`
- Smoke: `godot --headless --quit-after 90 res://<scene>.tscn 2>&1 | grep -iE "ERROR|nil|invalid|cannot|failed"` (filter vulkan/audio/display/leaked)
- Logic: throwaway `extends SceneTree` run with `-s`; RUN FROM THE cube DIR (shell cwd drifts after a
  game-dev push). `await process_frame` after add_child; physics queries need ~6-8 frames; annotate
  test var types (untyped dynamic access fails inference); PackedFloat32 compare with tolerance.
  Delete the script + `.uid` after.

## Memory
- Durable design intents live as code comments (perfect-vision flags, dodge-escape-by-geography).
  Standing cube memories unchanged.
