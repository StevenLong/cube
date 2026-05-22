# Handoff, 2026-05-22

## Where we are
**Phase 7 (Reactive Stealth Depth) is COMPLETE.** This session built the last item,
the extend-lock system (spine + gate + ghost blueprint), added an enemy-free
mechanics sandbox, and fixed a run of collision/input bugs. Phase 8 (Tutorials) is
next. All cube code committed to `main`; task list updated in the game-dev repo.

Next session you wanted to recap and plan; see "Directions from here" below.

## Completed this session

### Extend-lock system (Phase 7 item done)
The puzzle-forward setpiece: a zone requires a specific cuboid shape on specific
tiles; you must BE that shape there (you choose to extend into it, the zone only
checks), then you are locked into the shape until you reach an unlock.
- **Player API** (`player.gd`): `_extend_locked` flag blocks extend/collapse and
  tints the cube (COLOR_LOCKED); grid accessors `get_dimensions`,
  `get_footprint_min`, `footprint_covers`, `is_moving`.
- **Zone** (`extend_lock_zone.gd`, LOCK/UNLOCK modes): grid-exact. LOCK arms when
  the player's footprint min-corner == the zone cell AND dimensions == required_dims,
  checked on the integer grid only at rest. So it can't be satisfied a tile off,
  rotated, or mid-tumble. Orientation matters (deterministic start for later
  movement challenges). The zone cell is the footprint MIN corner; footprint extends
  +x, +z. UNLOCK releases when the locked cuboid covers the zone cell.
- **Gate** (`extend_lock_gate.gd`): a slab driven by lock state. Red and solid when
  closed, green and passable while locked, so you must commit to the shape to pass
  and it shuts behind you on release.
- **Ghost blueprint**: blinking translucent ghost of the required cuboid (conveys
  height + orientation) over the footprint tiles, hidden once the lock arms. All
  generated in code from required_dims (no manual marker setup).
- Sandbox setpiece in both scenes: lock pad (-3,3) needs a 1x1x3 bar, gate at
  (-5,3), unlock pad (-7,3).

### Collapse moved to the dodge button
Collapse was on the extend button's release, where pressing a direction to
collapse-and-move re-extended. It is now on the dodge button (idle while extended).
The collapsing dodge press is consumed until released so it can't also fire a dodge.

### Enemy-free mechanics sandbox
`mechanics_sandbox.tscn` = `main.tscn` minus the enemy, for testing mechanics/props
without dodging the sphere. `level.gd` already null-guards the enemy. Open it and
Run Current Scene (F6).

### Full-footprint wall collision for extended cuboids (two bug fixes)
- **Tumble**: `_can_move_cuboid` sweeps the base box along the roll at each cell
  offset perpendicular to it, covering the cuboid's full width, so it can't clip
  through a wall beside its base. (Cube/dodge unchanged: zero perpendicular extent.)
- **Extend**: `_try_extend` refuses to grow a side into a wall (point-queries the
  new footprint cells against layer 1; EXT_UP exempt, grows into air).

### Player class_name (root-cause inference fix)
`player.gd` now has `class_name Player`, and `_player` is typed `Player` in
enemy_sphere / extend_lock_zone / extend_lock_gate. Player method calls now carry
real return types, so `:=` no longer fails to infer on them (what bit `matched`
and `show_bp`). NOTE: Godot must re-scan to register the class; reload the project
if you see "Could not find type Player".

## Phase 7 status: COMPLETE
Graduated detection, focusing cone, nav pass, alert glyph, wall-knock, floor-cone-
through-walls, state-encoded hum + stings, and extend-lock are all done.

## Directions from here (for next session's plan)
- **Phase 8 (Tutorials)**: re-scoped so each teaches a signature situation, not a
  bare mechanic. Tutorials 2-6 (sprint/noise, extension, blend, ink/water, enemy/
  detection). See task list + Cube Game.md signature situations.
- **End-of-phase tuning pass**: all Phase 7 systems are in, so the deferred tuning
  (detection, cone, hum, knock, footprints, nav, extend-lock) can happen as a block.
  Remove `DEBUG_DETECTION` then.
- **First real level / signature situations**: compose the 6 signature situations
  (Cube Game.md) into a designed level now that the toolkit exists.
- **Open design questions**: pyramid/composite enemies, optional-objective definition,
  recovery-when-spotted variety (Cube Game.md open questions).

## Temporary / to remove
- `DEBUG_DETECTION := true` in `enemy_sphere.gd` (top-left detection readout). Drop
  the flag plus `_setup_debug_label` / `_update_debug_label` / `_state_name` at the
  tuning pass.

## Watch items / project notes
- After this session, **reload the project** in Godot once: registers `class_name
  Player` and the new script UIDs (extend_lock_zone/gate). Until then you may see a
  "Could not find type Player" or an "invalid UID" warning (benign, recovers via
  path).
- LoS is a single centre-to-centre ray; can thread the exact point where two walls
  meet for a frame and grant vision through a corner. Only lets the enemy detect you
  (then it pursues around via A*), never catch through the wall. Widen if it shows up.
- PURSUIT -> INVESTIGATE (losing at detection 0.5) has a small colour seam (ladder
  yellow vs search orange). Aim stays continuous; cosmetic.
- Two sandboxes diverge: `main.tscn` (with enemy) and `mechanics_sandbox.tscn`
  (enemy-free copy). New props must be added to both, or pick one as canonical.
- Extend-lock orientation-agnostic match was tried and reverted: matching is EXACT
  size + orientation + location on purpose (known starting shape for movement
  puzzles).

## Tuning backlog (end-of-phase pass)
- Detection (`DETECT_*`): fill/drain/thresholds; `DETECT_NOISE_SEED` 0.5 sets a
  knock's starting alarm (drop to ~0.25 for a calmer wide search).
- Cone: `CONE_FOCUS_COS`, `CONE_*_ALPHA`, `CONE_SEARCH_HALF_COS`, `CONE_SEARCH_SWEEP_RATE` 3.0.
- Glyph: `GLYPH_POP_SCALE` 1.6, `GLYPH_POP_TIME` 0.25.
- Hum: `HUM_PITCH` / `HUM_VOL` arrays, `HUM_LERP_RATE` 4.0; sting freq/dur/peak in
  `_setup_stings`, `_sting_player.volume_db`.
- Footprints: `FOOTPRINT_FADE_TIME` 12.0, `FOOTPRINT_RETARGET_DIST` 0.3.
- Knock: `KNOCK_RADIUS` 10.0, `KNOCK_COOLDOWN` 0.4, knock pitch 0.65.
- Extend-lock: `GHOST_BLINK_RATE` 3.0, `GHOST_ALPHA_MIN/MAX`; gate colours in
  `extend_lock_gate.gd`; per-zone `required_dims`.
- Nav: `TURN_CRAWL_FRACTION` 0.5, `CORRIDOR_HYSTERESIS` 0.2, `TURN_RATE` 5.0.
- Fog: `dark_factor` 0.25 placeholder.

## Key files
- `player.gd`: `class_name Player`. Tumble (footprint-aware wall collision
  `_can_move_cuboid`), extension (wall-blocked `_try_extend`), dodge, blend, ink,
  audio waves, footprints (fade), water cleanse, wall-knock, collapse-on-dodge,
  **extend-lock state + grid accessors**.
- `enemy_sphere.gd`: PATROL/SUSPICIOUS/INVESTIGATE/PURSUIT, graduated detection,
  detection-driven cone incl. rotating beacon search (cone alpha decoupled from body
  visibility), alert glyph, noise -> investigate, freshest-footprint follow, 8-conn
  A* + move-while-turning + corridor hysteresis (blocked-final-target guard),
  state-encoded hum + stings, debug detection readout (temp).
- `extend_lock_zone.gd`: grid-exact LOCK/UNLOCK zone + ghost-blueprint telegraph.
- `extend_lock_gate.gd`: lock-driven red/green gate.
- `level.gd`: state machine (READY/PLAYING/COMPLETE/CAUGHT), null-guards the enemy.
- `shaders/grid_ground.gdshader`: grid + waves + vision cone + footprints + LoS fog.
- `main.tscn`: with-enemy scene; puddles, walls, extend-lock setpiece.
- `mechanics_sandbox.tscn`: enemy-free copy for testing.
- `SPEC_graduated_detection.md`: detection model spec (noise -> INVESTIGATE).

## Input map
| Action | Controller | Keyboard |
|--------|-----------|---------|
| Move | D-pad / left stick | WASD / arrows |
| Wall-knock | tap move into a wall | tap move into a wall |
| Sprint | R2 | Left Shift |
| Dodge (cube) / Collapse (while extended) | Circle (hold + dir) / Circle | Space |
| Extend mode | R1 | E |
| Extend depth fwd/back | L1 / L2 (+ R1) | Q / C |
| Blend (hide) | Square | V |
| Camera tilt | Right stick Y | R / F |
| Back to menu / quit menu | (none) | Escape |

(Jump cut by design. Wall-knock and collapse reuse existing inputs, no new binds.)

## Memory notes worth checking
- Read HANDOFF.md first thing at session start.
- Design direction v0.2 (reactive-stealth, shape-vs-exposure, jump cut).
- No Co-Authored-By trailer; no em/en dashes; commit at session end or on request.
- `class_name Player` now exists; type `_player: Player` for inferable method calls.
- Transform3D row-major; ink/water binary cleanse.
- Task list at `/home/steven_long/game-dev/Cube Game Tasks.md`; design at Cube Game.md.
