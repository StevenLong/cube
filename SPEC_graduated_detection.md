# Spec: Graduated Detection Model

Phase 7, first task. Replaces the near-binary visual detection with a graduated
accumulator. This is the data layer the focusing cone, alert glyph, and state
audio all read from, so it lands first. See `Cube Game.md` (design v0.2) for the
why.

## Goal / success

Visual detection becomes a continuous value the player can feel ramping, not an
instant flip. Concretely, after this task:

- Standing far inside the cone, detection rises slowly: there is a visible window
  to react before SUSPICIOUS, and a longer one before PURSUIT.
- Up close, detection rises fast.
- A large or extended cube is detected faster than a compact one at the same range.
- Pressing blend (only possible at 3+ covered sides) makes the cube unseen, so
  detection drains. Covered sides otherwise do not affect detection.
- Breaking line of sight drains detection over a grace window; re-acquiring before
  it empties resumes quickly (and stays in pursuit through a brief loss).
- No more instant PATROL to SUSPICIOUS to PURSUIT jumps. Every visual transition
  is a threshold crossing on one accumulator.
- The accumulator is readable by other systems via a getter, so the cone/glyph/
  audio tasks can render it without re-deriving anything.

## The model

One new float on the enemy, `_detection` in [0, 1]. It is the enemy's visual
certainty about the player. It governs the visual ladder PATROL -> SUSPICIOUS ->
PURSUIT. INVESTIGATE stays a footprint/last-known search state (see Integration).

Each frame:

- **When seeing the player** (reuse `_is_seeing_player()`, which already returns
  false while blending, out of cone, occluded, or out of range):

  ```
  var dist := to_player.length()  # already computed in the sight check
  var proximity := clampf(1.0 - dist / VIEW_RADIUS, DETECT_MIN_PROXIMITY, 1.0)
  var size := 1.0 + _player.get_extension_sum() * DETECT_SIZE_WEIGHT
  var alert := DETECT_ALERT_FILL_MULT if _state != State.PATROL else 1.0
  _detection += DETECT_FILL_RATE * proximity * size * alert * delta
  ```

- **When not seeing the player:**

  ```
  _detection -= DETECT_DRAIN_RATE * delta
  ```

- Clamp `_detection` to [0, 1] every frame.

`proximity` keeps a small floor so the edge of vision still creeps the bar instead
of stalling at zero. Hiding affects detection only through the existing blend gate:
while `is_blending` is true the sight check returns false, so detection drains.
Covered sides are not a detection input on their own; they exist solely to enable
blend (3+ covered), per design.

### Proposed constants (enemy_sphere.gd, all tunable)

```
const DETECT_FILL_RATE        := 2.0   # per second at full exposure factors
const DETECT_DRAIN_RATE       := 0.4   # per second when not seeing
const DETECT_SUSPICIOUS       := 0.25  # PATROL -> SUSPICIOUS
const DETECT_PURSUIT          := 1.0   # -> PURSUIT (full bar)
const DETECT_PURSUIT_KEEP     := 0.5   # stay in PURSUIT until drained below this
const DETECT_MIN_PROXIMITY    := 0.15  # fill floor at cone edge
const DETECT_SIZE_WEIGHT      := 0.15  # per extension unit (mirrors noise size)
const DETECT_ALERT_FILL_MULT  := 1.5   # faster fill when already alert
```

These are starting guesses. Expect a play pass to dial fill/drain and thresholds.

## Integration with the state machine

The accumulator owns the visual ladder. The footprint and noise paths stay, with
one change to keep one source of truth (see Open Decision 1).

- **PATROL**: `if _detection >= DETECT_SUSPICIOUS -> SUSPICIOUS`. Footprint sighting
  still routes to INVESTIGATE as today.
- **SUSPICIOUS**: `if _detection >= DETECT_PURSUIT -> PURSUIT`; else
  `if _detection < DETECT_SUSPICIOUS -> PATROL`. Movement still creeps toward
  `_last_seen_pos`. This retires `CONFIRM_DURATION` and `SUSPICIOUS_TIMEOUT`
  (fill replaces the confirm timer, drain replaces the timeout).
- **INVESTIGATE**: keep the footprint search, retargeting, and `INVESTIGATE_TIMEOUT`
  as-is. Change only the re-acquire: instead of jumping to PURSUIT the instant it
  sees the player, it fills detection (with the alert multiplier) and enters
  PURSUIT at `DETECT_PURSUIT`.
- **PURSUIT**: while seeing, `_detection` pins at 1.0. When line of sight is lost
  it drains; `if _detection < DETECT_PURSUIT_KEEP -> INVESTIGATE` at last seen.
  This retires `PURSUIT_LOSE_TIMEOUT` (drain plus the keep threshold is the grace
  window). `entered_pursuit` still fires from `_enter_state(PURSUIT)`, unchanged.

Untouched: pathfinding, off-grid pursuit corridor, footprint trail logic, the
silhouette fade, and the blend cutoff.

## Code changes

### player.gd (two getters)

```
func get_extension_sum() -> int:
    return _ext[EXT_LEFT] + _ext[EXT_RIGHT] + _ext[EXT_UP] + _ext[EXT_FWD] + _ext[EXT_BACK]
```

(Exposes a value that already exists. `is_blending` is already public, and is the
only hiding signal the detection model needs.)

### enemy_sphere.gd

- Add the constants above and `var _detection := 0.0`.
- In `_process`, after computing `seeing`, update `_detection` per the model
  (needs the player distance; surface it from the sight check or recompute the
  `to_player` length, which is cheap).
- Rewrite the per-state transition conditions in the `match` block per Integration.
- Remove the now-dead `_confirm_timer` and the retired timeout comparisons. Keep
  `_state_timer` only where INVESTIGATE still uses it.
- Add the downstream getters:

  ```
  func get_detection_level() -> float:
      return _detection

  func get_detection_state() -> int:
      return _state
  ```

## Out of scope (separate Phase 7 tasks that consume this)

- Focusing cone visuals (narrow + colour ramp driven by `_detection`).
- Alert glyph (`?` fill -> `!`).
- State-encoded audio and transition stings.
- Floor cone staying visible when the body is occluded.

This task ships the model and the getters only. A temporary debug print or label
of `_detection` is fine for verifying it before the cone task renders it.

## Decisions (locked 2026-05-20)

1. **Noise seeds the accumulator: yes.** A noise-triggered SUSPICIOUS would start
   with `_detection` near 0 and the drain rule would bounce it straight back to
   PATROL. So on noise heard, set `_detection = maxf(_detection, DETECT_SUSPICIOUS)`;
   heard-suspicion then lives and drains on one model (this is what retires
   `SUSPICIOUS_TIMEOUT` cleanly). Footprint sighting stays independent: it routes
   to INVESTIGATE, which keeps its own timeout.
2. **Exposure inputs: extension size + proximity only.** Covered sides are NOT a
   detection input. They exist solely to gate the blend (3+ covered), which is the
   only hiding mechanic that affects detection, and it does so through the existing
   sight-check short-circuit, not through the accumulator math.

## Acceptance criteria

- [ ] Walking into the far edge of a stationary enemy's cone takes clearly longer
      to reach SUSPICIOUS than walking up close does.
- [ ] An extended cube trips SUSPICIOUS faster than a compact one at equal range.
- [ ] Pressing blend (3+ sides covered) halts the fill and drains detection;
      partial cover on its own does not change the fill.
- [ ] After being seen then breaking line of sight, the enemy stays in PURSUIT for
      a short grace window, then drops to INVESTIGATE, not instantly.
- [ ] No transition happens in a single frame from a cold start; every visual
      escalation passes through a rising `_detection`.
- [ ] `get_detection_level()` returns a sane 0..1 value that another node can read.
