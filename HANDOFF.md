# Handoff, 2026-05-21

## Where we are
Phase 7 (Reactive Stealth Depth), building on last session's graduated detection
+ focusing cone + nav pass. This session was alert feedback and a run of
investigate/ink/knock fixes, mostly driven by playtesting. All cube code committed
to `main`; task list updated in the game-dev repo.

## Completed this session

### Alert glyph (Phase 7 item done)
- Billboarded `Label3D` above the enemy (`_setup_alert_glyph` / `_update_alert_glyph`
  in `enemy_sphere.gd`): hidden on patrol, yellow `?` (suspicious), orange `?`
  (investigate), red `!` (pursuit). Fades with `_visibility_alpha` like the mesh so
  it never leaks position when the player has no LoS.
- Scale-pop on every state change (`GLYPH_POP_SCALE` 1.6 over `GLYPH_POP_TIME` 0.25,
  fired from `_enter_state`).

### Focusing cone: no acquire snap + new INVESTIGATE look
- INVESTIGATE cone is now a rotating 90 deg beacon (`_update_search_cone`,
  `CONE_SEARCH_HALF_COS`, `CONE_SEARCH_SWEEP_RATE` 3.0). As detection climbs from
  the suspicious threshold to pursuit, a `lock` factor slows/stops the sweep,
  narrows it to the focus beam, slides orange -> red, and homes on the suspect. At
  lock 1 it matches the PURSUIT branch exactly, so INVESTIGATE -> PURSUIT no longer
  snaps. Sweep is seeded toward the last-seen spot on entry so SUSPICIOUS ->
  INVESTIGATE picks up smoothly too.
- Extracting `_update_search_cone` also cleared the `CONFUSABLE_LOCAL_DECLARATION`
  warnings (the branch's locals collided with the ladder branch's).

### Noise -> INVESTIGATE (two bugs, one fix)
- `_on_sound_heard` now enters INVESTIGATE (was SUSPICIOUS). Fixes (a) pursuit-loss
  sliding through suspicious to patrol because footstep noise downgraded the active
  search, and (b) makes noise a usable lure. A repeat noise while already searching
  retargets + refreshes the dwell without re-popping the glyph. PURSUIT still
  ignores noise. SUSPICIOUS is now reached only by the visual accumulator.
- Spec updated: `SPEC_graduated_detection.md` decision 1.

### Footprint trail follows toward the player + fades
- `_visible_footprint_pos` returns the freshest in-view print (iterates newest ->
  oldest), so the search heads up the trail toward the player instead of back down
  it. INVESTIGATE consumes the print underfoot so a checked cell can't lure it back.
- Footprints fade with age and clear (`FOOTPRINT_FADE_TIME` 12.0 in `player.gd`,
  `_decay_footprints`); the shader already multiplies ink by `footprint_alphas`, so
  the trail visibly fades from its oldest end. Enemy only follows live prints.

### Slide ink contact is cell-based + multi-cell puddles
- Ink contact during a dodge was gated on the Area3D overlap count, which lags the
  render-frame position lerp and swallowed the first tiles of the trail. Now
  cell-based: `_build_ink_cells` records each puddle's `BoxShape3D` footprint at
  ready, `_check_ink_contact` reads the current cell. Trail starts on the first dry
  cell past the ink.
- `_build_ink_cells` enumerates every cell a puddle box covers, so multi-cell
  puddles and adjacent clusters work. Added a 3-cell ink puddle (`PuddleWide`) to
  `main.tscn` at cells (-1,-3),(0,-3),(1,-3).

### Wall-knock distraction (Phase 7 item done)
- A deliberate directional tap into an adjacent wall (the move is blocked, no tumble
  started) emits a loud noise at the wall cell: `_emit_knock` in `player.gd`,
  `KNOCK_RADIUS` 10.0 (+ extension size), `KNOCK_COOLDOWN` 0.4. Reuses the wave +
  `noise_emitted` plumbing and the step sound at pitch 0.65. Just-pressed edge means
  holding into a wall can't spam it. No new input binding (reuses move dirs).

### Corner-catch fix (knock in the hiding pocket)
- `_follow_path` ended with an unconditional `_move_toward(final_target)`, which is
  collision-free. A knock's target is a wall cell, so the sphere drove into the wall
  and reached the player through the shared edge/corner. Now it only closes the
  final gap if the target cell is open; otherwise it stops at the path end (an open
  neighbour) and searches there. Pursuit unaffected (player cell is open).

## Temporary / to remove
- `DEBUG_DETECTION := true` in `enemy_sphere.gd` still draws the on-screen detection
  readout (top-left). Keeping it for the end-of-phase tuning pass; drop the flag plus
  `_setup_debug_label` / `_update_debug_label` / `_state_name` when done.

## Phase 7 remaining
- State-encoded hum audio + transition stings (occlusion-proof alert channel).
- Floor cone stays visible when the enemy body is occluded (decouple `cone_alpha`
  from `_visibility_alpha`).
- Extend-lock system (a trigger forces a shape, locked until a requirement is met).

## Known watch items (not bugs blocking us)
- LoS is a single centre-to-centre ray; it can thread the exact point where two
  walls meet for a frame and grant vision through a corner. That only lets the enemy
  *detect* you (then it pursues around via A*), never catch through the wall. Widen
  to a multi-ray / body-width check if it shows up in play.
- PURSUIT -> INVESTIGATE (losing the player at detection 0.5) has a small colour
  seam: the pursuit ladder is yellow at 0.5 while the search cone is orange. Aim
  stays continuous; cosmetic only.
- Multi-cell puddles: keep the visual `PlaneMesh` and the collision `BoxShape3D`
  sized together (the player sees the plane, the box decides what inks you).
  `_build_ink_cells` assumes axis-aligned boxes, like the wall enumeration.

## Tuning backlog (end-of-phase pass)
- Detection (`DETECT_*`): fill/drain/thresholds. `DETECT_NOISE_SEED` 0.5 sets a
  knock's starting "alarm" (cone starts ~1/3 focused); drop to ~0.25 for a calmer
  wide search read.
- Cone: `CONE_FOCUS_COS`, `CONE_*_ALPHA`, `CONE_SEARCH_HALF_COS`,
  `CONE_SEARCH_SWEEP_RATE` 3.0.
- Glyph: `GLYPH_POP_SCALE` 1.6, `GLYPH_POP_TIME` 0.25.
- Footprints: `FOOTPRINT_FADE_TIME` 12.0, `FOOTPRINT_RETARGET_DIST` 0.3.
- Knock: `KNOCK_RADIUS` 10.0, `KNOCK_COOLDOWN` 0.4, knock pitch 0.65.
- Nav: `TURN_CRAWL_FRACTION` 0.5, `CORRIDOR_HYSTERESIS` 0.2, `TURN_RATE` 5.0.
- Fog: `dark_factor` 0.25 still a placeholder.

## Key files
- `player.gd`: tumble, extension, dodge, blend, ink (cell-based contact +
  `_build_ink_cells`), audio waves, footprints (**fade**, freshest exposed in
  order), water cleanse, **wall-knock** (`_emit_knock`), `get_extension_sum`.
- `enemy_sphere.gd`: PATROL/SUSPICIOUS/INVESTIGATE/PURSUIT, math cone vision,
  graduated detection accumulator, **detection-driven cone incl. rotating beacon
  search (`_update_search_cone`)**, **alert glyph**, **noise -> investigate**,
  **freshest-footprint follow + consume-underfoot**, 8-connected A* +
  move-while-turning + corridor hysteresis (**blocked-final-target guard**),
  per-enemy hum, debug detection readout (temp).
- `level.gd`: state machine (READY/PLAYING/COMPLETE/CAUGHT), stats, pause, Escape.
- `shaders/grid_ground.gdshader`: grid + waves + vision cone + footprints + LoS
  fog. Hardcodes 30x30 UV mapping.
- `main.tscn`: sandbox. Ink puddle (1,1), water (4,1), `PuddleWide` 3-cell ink at
  z=-3. Walls (3,0)/(2,-1)/(2,1) form the corner hiding pocket at (2,0).
- `SPEC_graduated_detection.md`: detection model spec (noise -> INVESTIGATE).

## Input map
| Action | Controller | Keyboard |
|--------|-----------|---------|
| Move | D-pad / left stick | WASD / arrows |
| Wall-knock | tap move into a wall | tap move into a wall |
| Sprint | R2 | Left Shift |
| Dodge | Circle (hold + dir) | Space |
| Extend mode | R1 | E |
| Extend depth fwd/back | L1 / L2 (+ R1) | Q / C |
| Blend (hide) | Square | V |
| Camera tilt | Right stick Y | R / F |
| Back to menu / quit menu | (none) | Escape |

(Jump is cut by design; no binding. Wall-knock reuses the move inputs, no new bind.)

## Memory notes worth checking
- Read HANDOFF.md first thing at session start.
- Design direction v0.2 (reactive-stealth, shape-vs-exposure, jump cut).
- No Co-Authored-By trailer on commits; no em/en dashes.
- Commit at session end or on request; ink/water binary cleanse.
- Transform3D row-major; GDScript can't infer types from untyped Array; define
  SQRT2 yourself; GDScript locals are block-scoped (extract to a function to avoid
  confusable-declaration warnings across branches).
- Task list at `/home/steven_long/game-dev/Cube Game Tasks.md`.
