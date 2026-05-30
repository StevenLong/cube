# Handoff, 2026-05-29

## Where we are
Phase 8 cluster **C (floating void world)** slice 1 of 3 done. The world is
now a finite cell-set of floor tiles in a void background, perimeter visuals
are gone, edges are marked with auto-generated red safety lines, and
extension + enemy nav read floor data instead of a hardcoded NAV band.
Falling off works in a placeholder sense (cube ends at y=0.5 in mid-air).
Slice 2 (real fall + Fell results panel) and slice 3 (a non-trivial demo
shape) remain.

Verified clean: headless parse-check + smoke-load of `main.tscn`,
`mechanics_sandbox.tscn`, and `levels/level_01_movement.tscn`. No in-editor
verification yet from the user; that's the immediate next step.

## The Phase 8 backlog
- **A. Extended-state mechanic gaps**: DONE.
- **B. Blend redesign (auto-blend + visual polish)**: DONE.
- **C. Floating void world**:
  - Slice 1 (data model + per-tile rendering + perimeter visuals stripped +
    red safety lines + extension/nav rewired): **DONE this session**.
  - Slice 2 (real fall behavior: animation, camera follow, Fell results
    panel): NOT STARTED.
  - Slice 3 (build a non-trivial demo shape: tightrope, notch, or gap, to
    prove the painting workflow): NOT STARTED.
- **D. Animation / juice**: extend/collapse anim, spawn rise, death,
  completion, intro/outro. NOT STARTED.
- **E. Audio**: more SFX, music. NOT STARTED.
- **F. Parked**: grow tall to see over objects, pre-spawn demo flythrough.

## Completed this session

### Floor data model
- `Level.is_floor(cell)` + `Level.get_floor_bounds()` are the new bounds
  source. Both player and enemy reach Level via `@onready var _level`.
- `Level._build_world` is deferred from `_ready` (via `call_deferred`)
  because spawning floor tiles into the world root during the scene's load
  chain raises Godot's "Parent node is busy setting up children" error.
- Build pipeline: phase 1 adds cells from every `FloorRect`, phase 2 carves
  cells under every `FloorMissing`, phase 3 walks pre-placed `FloorTile`
  instances (they override missing and are snap-positioned), phase 4
  instantiates a `FloorTile` for every remaining cell.

### Authoring helpers
- `floor_tile.tscn` (named `FloorTile.tscn` on disk): StaticBody3D on layer
  1, BoxMesh + BoxShape3D (1u cube), shared shader material via
  `grid_ground_material.tres`, in group `"floor_tiles"`. Drop one anywhere
  in a level scene to add a single cell.
- `floor_rect.gd` (`class_name FloorRect`): Node3D with exported
  `size: Vector2i` (default 27x27). Position is the min-corner cell.
- `floor_missing.gd` (`class_name FloorMissing`): same shape, marks the
  rect for removal during the floor build.

### Shader rewrite
- `shaders/grid_ground.gdshader` uses world-space vertex position
  (`MODEL_MATRIX * VERTEX`) and world-space normal as varyings. Top face
  (world_norm.y > 0.5) renders the full pipeline: grid lines, waves,
  footprints, LoS-gated cone, fog. Side and bottom faces flat-fill with
  `side_color`.
- `cull_disabled` dropped (boxes don't need it). `return` inside `fragment`
  is not legal in Godot's shading language, so the top-vs-side branch is a
  single `if`/`else`.
- Three new color uniforms exposed for tuning: `top_base_color`,
  `side_color`, `grid_line_color`. Defaults match the previous look.
- `grid_ground_material.tres`: single `ShaderMaterial` resource referenced
  by every FloorTile via the scene's `surface_material_override`, and by
  Player and Enemy via `preload`. Uniforms set once on the shared resource
  propagate to every tile.

### Auto safety-edge red lines
- `Level._build_safety_edges` walks every floor cell and each cardinal
  neighbor. When the neighbor is non-floor AND a layer-1 physics point
  query at `(cell.x, 0.5, cell.y)` hits a wall, a thin red emissive box
  (0.05 x 0.05 x 1) is spawned 0.5u above the floor edge. Open-void
  neighbors get nothing: their absence IS the "you can fall here" signal.
- Mesh + material made in code (`_make_safety_edge_mesh`,
  `_make_safety_edge_material`); single shared material per scene.
- The wall query at y=0.5 sits above floor tiles (`y in [-1, 0]`) and
  inside walls (`y in [0, 1]`), so floor tiles never false-positive.

### Player + enemy rewiring
- New `Player._cell_buildable(cell)`: `_extend_cell_clear(cell) and
  _level.is_floor(cell)`. Used by `_extend_side_clear` and `_gap_ahead`.
  Extension growing over void is blocked the same as into a wall.
- Cube tumble over void: still allowed (placeholder fall). Extended
  cuboid tumble over void: blocked in `_begin_tumble` after
  `_can_move_cuboid` passes, by checking every new-footprint cell against
  `_level.is_floor`. Falls through to `_begin_blocked_bump`, which with
  gap=0 plays a soft thud.
- `_extend_cell_clear` keeps its original "no wall" semantics (cover
  detection still uses it; void must count as exposed-from-that-direction).
- Enemy `_cell_blocked` now uses `not _level.is_floor(cell)` instead of
  the hardcoded `NAV_MIN/NAV_MAX = ±13`. Constants deleted.
- Player + Enemy `_ground_material` populated from
  `preload("res://grid_ground_material.tres")` instead of reaching into
  the deleted Ground node.

### Scene migration
- `main.tscn`, `mechanics_sandbox.tscn`, `levels/level_01_movement.tscn`:
  - `Ground` node deleted (PlaneMesh + ShaderMaterial + WorldBoundary).
  - PerimeterN/S/E/W: MeshInstance3D child deleted, StaticBody +
    CollisionShape kept. Walls now invisible; red lines auto-render.
  - `FloorRect` added at (-13, 0, -13) with size (27, 27).
  - `WorldEnvironment.background_color` bumped from black to
    `Color(0.1, 0.1, 0.12)` so the slab reads against the void.
  - Tutorial level (`level_01_movement.tscn`) didn't have perimeter walls
    before; added invisible collision so the tutorial doesn't accidentally
    become a fall-off tutorial.

## Watch items / known edge cases

### New this session
- **Cube fall-off is placeholder**: cube ends up at world y=0.5 over void.
  Slice 2 turns that into a real fall + Fell panel.
- **Background / side / top contrast is untuned in-editor**: defaults are
  background `(0.1, 0.1, 0.12)`, top `(0.06, 0.06, 0.12)`, side
  `(0.04, 0.04, 0.08)`. May need a tweak after eyes-on.
- **Floor build is deferred one tick**: between scene `_ready` and the
  first idle frame, `_floor_cells` is empty. Player and enemy only query
  it from `_process` / pathfinding, so this is invisible in practice, but
  any future code that needs the floor synchronously from `_ready` should
  also defer or `await`.
- **No FloorRect editor gizmo**: dragging the node in the viewport gives
  no visual hint of which cells it'll spawn. Worth a small gizmo plugin
  later if authoring gets tedious.
- **Cover still counts the perimeter**: `_is_in_cover` reads physics walls
  via `_extend_cell_clear`. Perimeter walls have collision, so blending
  against an edge still works. Slice 1 doesn't change this behavior. If
  it ever feels wrong design-wise, gate cover on `is_floor` neighbors.
- **`FloorTile.tscn` is PascalCase on disk** while other scenes are
  snake_case. Cosmetic; rename later if it bugs you.

### Carried from last session (still applicable)
- **Stale enemy path through a freshly-hiding cell**: same as before.
- **Search-through-corner**: same; level-design concern.
- **Wall-colour camouflage caches at blend entry**: same.
- **Pursuit's direct-line `_move_toward`**: same; non-issue in normal flow,
  and now also bypasses the floor check, so pursuit will chase the player
  off a cliff. Slice 2 fall will end the chase naturally.
- **Unused WallRay nodes** under Player: still dead. Delete when convenient.
- **DEBUG_DETECTION := true** in enemy_sphere.gd: drop at end of phase.
- **Tall-pillar false blend**: same; parked.
- **`GapWall*` and `Perimeter*` absent from shader LoS** because the
  `_push_walls_to_shader` name filter is `Wall*`. Pre-existing. Not a
  regression: the perimeter walls weren't in the LoS list before either.
- **Two scenes still diverge**: main + sandbox.
- **LoS multi-cell but centre-to-centre per cell**: same.

## Verification status
None in-editor yet. Slice 1 needs eyes-on for: void contrast, slab look,
red lines on perimeter, waves / footprints / cone all still rendering on
tiles, enemy stays inside the floor, extension blocked at the edge,
extended tumble blocked at the edge, cube tumble off the edge ends in
placeholder mid-air (slice 2 will fix). User should verify before
starting slice 2.

## Key files
- `player.gd`: `class_name Player`. Tumble (footprint-aware wall + extended-
  shape void block), extension via `_cell_buildable` (wall + floor combined),
  dodge, auto-blend, ink + water, audio waves, footprints,
  collapse-on-dodge, extend-lock state, grid accessors, DetectionArea
  resized to footprint. `_ground_material` from
  `preload("res://grid_ground_material.tres")`. `@onready _level` for
  `is_floor` lookups.
- `enemy_sphere.gd`: PATROL/SUSPICIOUS/INVESTIGATE/PURSUIT, graduated
  detection, detection-driven cone, alert glyph, noise -> investigate,
  footprint follow, A* nav with floor-data bounds (`_level.is_floor` in
  `_cell_blocked`), multi-cell LoS, state hum + stings, debug readout.
  `_ground_material` from preload.
- `level.gd`: `class_name Level`. State machine (READY/PLAYING/COMPLETE/
  CAUGHT); completion via end-tile Area3D OR `footprint_covers(_end_cell)`;
  null-guards the enemy. NEW: `_floor_cells`, `is_floor`,
  `get_floor_bounds`, `_build_world` (deferred), `_build_floor`,
  `_build_safety_edges`.
- `floor_rect.gd` / `floor_missing.gd`: `class_name` config nodes;
  `size: Vector2i`; `cell_rect()` returns an absolute Rect2i using the
  node's XZ position as min corner.
- `FloorTile.tscn` + `grid_ground_material.tres`: per-cell unit; shared
  shader material.
- `shaders/grid_ground.gdshader`: world-space vertex + normal varyings;
  top face = grid + waves + footprints + cone + fog; side = flat
  `side_color`. Color uniforms: `top_base_color`, `side_color`,
  `grid_line_color`.
- `extend_lock_zone.gd` / `extend_lock_gate.gd`: unchanged.
- `main.tscn` / `mechanics_sandbox.tscn` / `levels/level_01_movement.tscn`:
  FloorRect-based floor; perimeter walls invisible-collision-only; void
  background `(0.1, 0.1, 0.12)`.
- Design: `game-dev/Cube Game.md` (v0.2). Tasks:
  `game-dev/Cube Game Tasks.md` (Phase 8).

## Input map
| Action | Controller | Keyboard |
|--------|-----------|---------|
| Move | D-pad / left stick | WASD / arrows |
| Wall-knock (cube only) | tap move into a wall | tap move into a wall |
| Sprint | R2 | Left Shift |
| Dodge (cube) / Collapse (while extended) | Circle | Space |
| Extend mode | R1 | E |
| Extend depth fwd/back | L1 / L2 (+ R1) | Q / C |
| Camera tilt | Right stick Y | R / F |
| Back to menu / quit | (none) | Escape |

Blend is automatic (stand still in cover). Jump cut by design.

## Tuning backlog (end-of-phase pass)
- **Floor / void contrast** (slice 1): WorldEnvironment background
  `(0.1, 0.1, 0.12)`, shader uniforms `top_base_color` `(0.06, 0.06, 0.12)`,
  `side_color` `(0.04, 0.04, 0.08)`, `grid_line_color` `(0, 1, 1)`. Tune
  any of these without code changes via the `.tres` and the
  WorldEnvironment.
- **Safety edge** (slice 1): hardcoded red `(0.9, 0.15, 0.15)` with
  emission energy 1.5, box (0.05 x 0.05 x 1), y=0.5. Lift into named
  constants when tuning.
- Blend: `BLEND_ENTER_TIME` 0.4, `BLEND_EXIT_TIME` 0.15. Footprint tile
  half-extent 0.4 and falloff 0.1.
- Won't-fit bump: `BUMP_DURATION` 0.25, `BUMP_ANGLE` PI/10,
  `BUMP_CLEARANCE` 0.15, thud volume 0.35 / pitch 0.5.
- Detection (`DETECT_*`), cone (`CONE_*`), glyph, hum/stings, footprints
  (`FOOTPRINT_FADE_TIME` 12.0), knock (`KNOCK_RADIUS` 10.0,
  `KNOCK_COOLDOWN` 0.4), extend-lock (`GHOST_*`), nav (`TURN_*`,
  `CORRIDOR_HYSTERESIS`), fog `dark_factor` 0.25.

## Memory notes worth checking
- Read HANDOFF.md first thing at session start.
- Godot headless CLI at `~/.local/bin/godot`. Parse-check via
  `godot --headless --editor --quit 2>&1 | grep -E "SCRIPT ERROR|Parse Error|SHADER ERROR"`.
  Smoke-load a scene via `godot --headless --quit-after 30 <scene>` and
  grep for `ERROR|error`. Exit code is 0 even on errors, so always grep.
- Active verbs (sprint/dodge/knock) are cube-only; extension is a
  positional commitment, including the "won't tumble into void" rule.
- Design v0.2 (reactive-stealth, shape-vs-exposure, jump cut).
- No Co-Authored-By trailer; no em/en dashes; commit at session end or on
  request. Transform3D row-major; ink/water binary cleanse; GDScript
  inference with untyped arrays.
