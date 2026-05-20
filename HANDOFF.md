# Handoff, 2026-05-20

## Where we are
Design-heavy session. Stepped back from building tutorials to lock down the
game's design (v0.2), then started Phase 7 (reactive stealth depth): graduated
detection, the focusing cone, and a navigation feel pass. All cube code
committed; design docs and task list committed in the game-dev repo.

## Completed this session

### Design v0.2 (`game-dev/Cube Game.md`)
- Center of gravity: reactive stealth spine with puzzle-forward extension
  setpieces woven in (user's call, not the puzzle-forward option I first pushed).
- Anchor tension: the shape that lets you move/reach/hide is the shape that gets
  you seen, slows you, and makes noise.
- Doc now holds pillars, core loop, detection/readability spec, a systems-vs-props
  mechanic taxonomy, six signature situations, and a decisions log.
- Decisions: **jump cut** (grid tumble identity; extension height is the only,
  priced, verticality), extension cost resolved (free to change, priced in
  speed/noise/silhouette), detection graduated not binary.
- See memory `project-design-direction-v02`.

### Docs hygiene
- `CLAUDE.md` no longer tracks progress (removed Current Status); it points to the
  task list and HANDOFF instead.
- Task list reorged: Phase 6 trimmed to its done items; new **Phase 7 (Reactive
  Stealth Depth)** ahead of **Phase 8 (Tutorials)**, which is re-scoped so each
  tutorial teaches a signature situation, not a bare mechanic. LoS-tuning and
  caught-panel items checked off.

### Phase 7, task 1: Graduated detection model (committed ec3815b)
- `_detection` accumulator [0,1] in `enemy_sphere.gd`. Fills by
  `proximity * size * alert-mult` while seeing, drains otherwise. Hiding feeds in
  only via the blend short-circuit (covered sides are NOT a detection input, per
  user). Thresholds drive PATROL/SUSPICIOUS/PURSUIT; retired CONFIRM_DURATION,
  SUSPICIOUS_TIMEOUT, PURSUIT_LOSE_TIMEOUT.
- Noise seeds `_detection` to DETECT_NOISE_SEED. Getters `get_detection_level()`
  / `get_detection_state()` for downstream readability tasks. `get_extension_sum()`
  added to `player.gd`.
- Spec: `cube/SPEC_graduated_detection.md`.

### Phase 7, task 2: Focusing cone (committed 7d2d5aa)
- The ground cone now reads off `_detection`: narrows from the patrol sweep to a
  tight beam, ramps grey -> yellow -> red, and aims at the suspect (the beam
  doubles as a last-known-position marker). INVESTIGATE opens to a 360 orange
  search sweep. Pure uniform changes, no shader edit.

### Navigation feel pass (committed 3234119)
- **8-connected A\*** (octile heuristic, SQRT2 diagonal cost, no corner cutting):
  direct diagonal routes instead of 4-connected staircases.
- **Move-while-turning** in `_move_toward`: speed eases to TURN_CRAWL_FRACTION
  through sharp turns instead of the old dead-stop-and-pivot (TURN_LEAD_THRESHOLD,
  removed).
- **Pursuit corridor hysteresis**: off-grid seek engages only after the corridor
  stays clear for CORRIDOR_HYSTERESIS; any block reverts to A* immediately. Kills
  the corner jiggle.
- Removed dead NEIGHBORS (4-conn).

## Temporary / to remove
- `DEBUG_DETECTION := true` in `enemy_sphere.gd` draws an on-screen `_detection`
  readout (top-left). Drop the flag plus `_setup_debug_label` /
  `_update_debug_label` / `_state_name` once the cone is verified.

## Phase 7 remaining
- State-encoded hum audio + transition stings (occlusion-proof alert channel).
- Alert glyph `?` -> `!` above the enemy.
- Floor cone stays visible when the enemy body is occluded (decouple `cone_alpha`
  from `_visibility_alpha`).
- Wall-knock distraction (deliberate re-press into an adjacent wall emits noise).
- Extend-lock system (forced shape, locked until a requirement is met).

## Tuning backlog
- Detection (`DETECT_*`): noise dwell ~0.6s feels short (seed/intensity coupling
  in a single accumulator). INVESTIGATE re-acquire now ramps (~0.5-0.7s) rather
  than snapping to pursuit. Fill/drain rates and thresholds all tunable.
- Cone: CONE_FOCUS_COS, CONE_PATROL_ALPHA, CONE_LOCKED_ALPHA, CONE_SEARCH_ALPHA.
- Nav: TURN_CRAWL_FRACTION 0.5 (higher = more relentless, lower = more arc),
  CORRIDOR_HYSTERESIS 0.2, TURN_RATE 5.0 (bump for snappier facing).
- Fog: `dark_factor` 0.25 still a placeholder.

## Cleared from previous backlog
- 8-connected pathfinder switch: done.
- Pursuit corridor hysteresis: done.
- (Player LoS silhouette tuning was done last session.)

## Deferred / parked (unchanged)
- Per-face cube ink visualisation; extended-cuboid per-cell footprints.
- Pyramid / composite enemies; optional-objective definition; recovery-when-spotted
  variety. See `Cube Game.md` open questions.
- Shelved props: conveyor belts (off the reactive-stealth centre), timed noisemaker.

## Key files
- `player.gd`: tumble, extension, dodge, blend, ink, audio waves, footprints,
  water cleanse, wall-AABB enumeration, caught signal, **get_extension_sum**.
- `enemy_sphere.gd`: PATROL/SUSPICIOUS/INVESTIGATE/PURSUIT, math cone vision,
  footprint trail, smooth rotation, **graduated detection accumulator**,
  **detection-driven focusing cone**, **8-connected A* + move-while-turning +
  corridor hysteresis**, per-enemy hum, **debug detection readout (temp)**.
- `level.gd`: state machine (READY/PLAYING/COMPLETE/CAUGHT), stats, pause, Escape.
- `shaders/grid_ground.gdshader`: grid + waves + vision cone + footprints + LoS
  fog of war. Hardcodes 30x30 UV mapping.
- `SPEC_graduated_detection.md`: the detection model spec.

## Input map
| Action | Controller | Keyboard |
|--------|-----------|---------|
| Move | D-pad / left stick | WASD / arrows |
| Sprint | R2 | Left Shift |
| Dodge | Circle (hold + dir) | Space |
| Extend mode | R1 | E |
| Extend depth fwd/back | L1 / L2 (+ R1) | Q / C |
| Blend (hide) | Square | V |
| Camera tilt | Right stick Y | R / F |
| Back to menu / quit menu | (none) | Escape |

(Jump is cut by design; no binding.)

## Memory notes worth checking
- Read HANDOFF.md first thing at session start.
- Design direction v0.2 (reactive-stealth, shape-vs-exposure, jump cut).
- No Co-Authored-By trailer on commits.
- Transform3D row-major; GDScript can't infer types from untyped Array / a
  Node3D-typed `_player` method call (annotate explicitly). SQRT2 is not a
  GDScript global; define it.
- Commit at session end or on request; no em/en dashes; ink/water binary cleanse.
- Task list at `/home/steven_long/game-dev/Cube Game Tasks.md`.
