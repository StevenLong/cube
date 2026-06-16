class_name Player
extends Node3D

signal tumbled
signal move_settled
signal noise_emitted(origin: Vector2, max_radius: float, duration: float)
signal caught
signal fell
signal wedged  # tipped into a gap but jammed before clearing it; its own fail, not a fall

const TUMBLE_DURATION := 0.3
const STEP_GAIN := 0.4  # master loudness of the player's own step audio (~ -8 dB); the gameplay noise radius is unaffected
const STEP_RADIUS_NORMAL := 2.5  # walk-step noise wave radius in cells (tactical, not whole-level)
const STEP_RADIUS_SPRINT := 5.0  # sprint-step noise radius: the loud, risky option
const INPUT_BUFFER_TIME := 0.3   # grace window to apply a shape/collapse press made mid-move
const SAFETY_EDGE_PROBE_Y := 0.7 # above the 0.4u safety-edge top: a wall here is full-height (knockable)
const BUFFERABLE: Array[String] = ["collapse", "extend_left", "extend_right", "extend_fwd", "extend_back", "extend_up"]
const SPRINT_DURATION := 0.15
const DODGE_DISTANCE := 5
const DODGE_DURATION := 0.4
const DODGE_COOLDOWN := 1.5
const DODGE_FLASH_TIME := 0.3  # green "ready" edge blink duration when the cooldown completes
const WAVE_DURATION := 0.4
const KNOCK_RADIUS := 10.0  # wall-knock noise radius (knock is a cube-only ability)
const KNOCK_COOLDOWN := 0.4  # min seconds between wall knocks
const BUMP_DURATION := 0.25  # won't-fit lean-and-rock-back for a blocked extended move
const BUMP_ANGLE := PI / 10.0  # peak lean (~18 deg) before rocking back, scaled down near a wall
const BUMP_CLEARANCE := 0.15  # air gap kept between the lean's leading corner and the wall
const FALL_GRAVITY := 25.0  # units/s^2; accelerates the cube straight down after settling on void
const FALL_END_Y := -25.0  # let the cube plunge well into the void (visible fall) before `fell` hands off to the level
const EXPRESSION_COUNT := 4  # fail-state "broken screen" faces in the cube shader's expr_color
const TIP_ANGULAR_ACCEL := 25.0  # rad/s^2 — rotational gravity tipping the cube into the hole
const TIP_INITIAL_VEL := 1.5  # rad/s initial kick; handles the knife-edge balance case
const TIP_END_ANGLE := PI / 2.0  # at 90° the cuboid has tipped past the edge; hand off to straight drop
const WEDGE_HOLD_TIME := 0.8  # seconds the cube hangs jammed in the wedged pose before fell.emit, so the wedge reads
const WEDGE_INSET := 0.05  # shrink the sampled box in _tip_collides_at: keeps roundi off cell boundaries, and a snug-fitting cube drops instead of catching on the far rim
const MAX_WAVES := 8
const MAX_FOOTPRINTS := 64
const FOOTPRINT_FADE_TIME := 12.0  # seconds for a deposited print to fade out and clear
const MAX_WALLS := 64  # shader occlusion list (cone clipping); large levels exceed 16 wall regions
const EXTEND_PROBE_Y := 0.2  # below the 0.4u safety-edge top: extension is blocked by edges, not just tall walls
const FOCUS_SMOOTH_RATE := 25.0
const BLEND_ENTER_TIME := 0.4  # seconds in cover + still before is_blending engages (and visual fully fades)
const BLEND_EXIT_TIME := 0.15  # faster fade-out so peeking out is visible to enemies sooner than re-blending
const COLOR_NORMAL := Color(0.9, 0.9, 0.9)
const COLOR_BLENDING := Color(0.4, 0.4, 0.45)  # fallback when no wall material can be sampled
const COLOR_MARKED := Color(0.25, 0.35, 0.55)
const COLOR_LOCKED := Color(0.85, 0.5, 0.15)  # extend-locked: committed to a forced shape

const EXT_LEFT  := 0
const EXT_RIGHT := 1
const EXT_FWD   := 2
const EXT_BACK  := 3
const EXT_UP    := 4

const GROUND_MATERIAL := preload("res://grid_ground_material.tres")

# Face IDs map cube-local axis directions to indices 0-5.
# Used to track which physical face is in contact with ground/puddles.
const FACE_X_POS := 0
const FACE_X_NEG := 1
const FACE_Y_POS := 2
const FACE_Y_NEG := 3
const FACE_Z_POS := 4
const FACE_Z_NEG := 5

const LAYER_ENEMY := 4
const LAYER_PUDDLE := 16

var grid_pos := Vector2i(0, 0)
var _tumbling := false
var _t := 0.0
var _pivot := Vector3.ZERO
var _axis := Vector3.ZERO
var _angle := 0.0
var _start_pos := Vector3.ZERO
var _start_basis := Basis.IDENTITY
var _dodging := false
var _dodge_t := 0.0
var _dodge_start_pos := Vector3.ZERO
var _dodge_end_pos := Vector3.ZERO
var _dodge_cooldown_t := 0.0
var _knock_cooldown_t := 0.0
var _buf_action := ""   # latest buffered discrete shape press (see _capture_buffer)
var _buf_t := 0.0       # remaining grace on the buffered action
var _dodge_flash := 0.0 # counts down the green "ready" edge blink after the cooldown ends
var _dodge_heat_max := 0.0  # peak heat for the current/last dodge (= distance / DODGE_DISTANCE)
var _ready_player: AudioStreamPlayer  # soft chime when the dodge cools to ready
var _expression := -1   # active fail-screen face index (-1 = none); chosen at random on a fail
var _dodge_duration := DODGE_DURATION
var _slide_last_cell: Vector2i = Vector2i.ZERO
var _ext := [0, 0, 0, 0, 0]
var _pending_ext := [0, 0, 0, 0, 0]
var _tumble_distance := 1
var _bumping := false
var _bump_t := 0.0
var _bump_pivot := Vector3.ZERO
var _bump_axis := Vector3.ZERO
var _bump_angle := 0.0
var _falling := false
var _fall_vel: float = 0.0
var _tipping := false
var _tip_pivot := Vector3.ZERO
var _tip_axis := Vector3.UP  # recomputed in _setup_tip
var _tip_angle: float = 0.0
var _tip_vel: float = 0.0
var _tip_start_pos := Vector3.ZERO
var _tip_start_basis := Basis.IDENTITY
var _wedged := false  # tip hit a wedge; holding the jammed pose before fell.emit
var _wedge_hold_t := 0.0
var _smoothed_focus := Vector3.ZERO
var _extend_locked := false
var is_blending := false  # gameplay state (enemy invisibility); true only at full phase
var is_hiding := false  # at-rest + in cover + not animating; enemy nav treats hiding cells as walls so investigations don't barge through
var _blend_phase: float = 0.0  # 0 exposed -> 1 hidden; rises over BLEND_ENTER_TIME, falls over BLEND_EXIT_TIME
var _cover_color: Color = COLOR_BLENDING  # sampled from a covering wall on blend entry, else fallback
var _was_wanting_blend := false  # for one-shot cover-color sampling at the transition
var _ground_material: ShaderMaterial
var _player_material: ShaderMaterial
var _waves: Array = []
var _footprints: Array = []
var _box_mesh: BoxMesh
var _detection_shape: BoxShape3D  # owned copy so resizing doesn't mutate the wall shape (both use BoxShape3D_1)
var _detection_collider: CollisionShape3D  # cached so _update_mesh can re-pose it with the visual mesh
var _face_marks: Array[bool] = [false, false, false, false, false, false]
var _ink_cells: Dictionary = {}
var _water_cells: Dictionary = {}
var _orient: Basis = Basis.IDENTITY

@onready var _step_player: AudioStreamPlayer = $StepSound
@onready var _splash_player: AudioStreamPlayer = $SplashSound
@onready var _mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var _move_cast: ShapeCast3D = $MoveCast
@onready var _detection_area: Area3D = $DetectionArea
@onready var _level: Level = get_node_or_null("../Level")  # absent when standalone (editor)
var god_mode := false  # editor cursor: no fall, no-clip. The game leaves this false.
var suppress_dodge := false  # editor placement mode: A is "place", not dodge. The game leaves this false.


func _ready() -> void:
	# Sync grid_pos to the authored start cell so a level can place the player
	# anywhere. Without this it stays at the (0,0) default and the first settle
	# snaps position to (0,0)-relative coords, lurching the cube off its start.
	grid_pos = Vector2i(roundi(position.x), roundi(position.z))
	_step_player.stream = _make_step_sound()
	_splash_player.stream = _make_splash_sound()
	_ready_player = AudioStreamPlayer.new()
	_ready_player.stream = _make_ready_sound()
	_ready_player.volume_db = -15.0   # soft hint, not a klaxon
	add_child(_ready_player)
	# Shared resource across every FloorTile and this player; uniforms set on it
	# here push to every tile's top surface in one go.
	_ground_material = GROUND_MATERIAL
	_push_walls_to_shader()
	_reset_ground_overlays()
	_box_mesh = _mesh_instance.mesh.duplicate() as BoxMesh
	_mesh_instance.mesh = _box_mesh
	# Per-face cube shader (the cube's faces are info "screens"; first use is ink).
	_player_material = ShaderMaterial.new()
	_player_material.shader = preload("res://shaders/cube.gdshader")
	_player_material.set_shader_parameter("ink_color", COLOR_MARKED)
	_mesh_instance.set_surface_override_material(0, _player_material)
	_push_cube_material()
	_smoothed_focus = _mesh_instance.global_position
	_detection_collider = _detection_area.get_node("CollisionShape3D") as CollisionShape3D
	_detection_shape = (_detection_collider.shape as BoxShape3D).duplicate() as BoxShape3D
	_detection_collider.shape = _detection_shape
	_detection_area.area_entered.connect(_on_contact)
	for puddle in get_tree().get_nodes_in_group("ink_puddles"):
		puddle.area_entered.connect(_on_puddle_entered)
	_build_puddle_cells()


func _build_puddle_cells() -> void:
	# Record every cell ink and water puddles cover, so contact and cleanse can read
	# off the current footprint rather than an Area3D overlap count (which lags the
	# render-frame position lerp during a dodge AND is sized to the 1x1 DetectionArea,
	# so it misses cells touched only by an extended cuboid). Reads each puddle's
	# BoxShape3D footprint to support multi-cell puddles and clusters. Assumes
	# axis-aligned boxes, like the walls.
	_ink_cells = _collect_puddle_cells("ink_puddles")
	_water_cells = _collect_puddle_cells("water_puddles")


func _collect_puddle_cells(group: String) -> Dictionary:
	var out: Dictionary = {}
	for puddle in get_tree().get_nodes_in_group(group):
		var area := puddle as Area3D
		if area == null:
			continue
		var center := area.global_position
		var box: BoxShape3D = null
		for child in area.get_children():
			if child is CollisionShape3D:
				center = child.global_position
				box = child.shape as BoxShape3D
				break
		if box == null:
			out[Vector2i(roundi(center.x), roundi(center.z))] = true
			continue
		var half := box.size * 0.5
		for cx in range(ceili(center.x - half.x), floori(center.x + half.x) + 1):
			for cz in range(ceili(center.z - half.z), floori(center.z + half.z) + 1):
				out[Vector2i(cx, cz)] = true
	return out


func _on_contact(area: Area3D) -> void:
	if (area.collision_layer & LAYER_ENEMY) != 0:
		_trigger_fail_face()   # show the broken-screen face before the level pauses
		caught.emit()


func _trigger_fail_face() -> void:
	# Pick a random fail "screen" and push it immediately, so the cube shows it
	# even if the tree pauses (caught) the same frame before the next _process.
	_expression = randi() % EXPRESSION_COUNT
	_push_cube_material()


func _on_puddle_entered(area: Area3D) -> void:
	# A dodge can slide onto an ink cell between cell-transition checks; recheck on
	# overlap so the entering face still inks. Off-dodge tumbles ink on landing.
	if area == _detection_area and _dodging:
		_check_ink_contact()




func _can_move(delta_world: Vector3) -> bool:
	if god_mode:
		return true
	_move_cast.target_position = delta_world
	_move_cast.force_shapecast_update()
	return not _move_cast.is_colliding()


func _can_move_cuboid(dir: Vector2i, dist: int) -> bool:
	if god_mode:
		return true
	# Tumble collision for an extended cuboid: sweep the base box along dir by dist
	# at every cell offset perpendicular to the roll, covering the cuboid's full
	# perpendicular width (a tumble preserves that width; the along-roll extent is
	# already covered by dist). Without this only the base cell is checked and the
	# extended cells clip through walls.
	var perp: Vector3
	var lo: int
	var hi: int
	if dir.x != 0:
		perp = Vector3(0.0, 0.0, 1.0)
		lo = -int(_ext[EXT_FWD])
		hi = int(_ext[EXT_BACK])
	else:
		perp = Vector3(1.0, 0.0, 0.0)
		lo = -int(_ext[EXT_LEFT])
		hi = int(_ext[EXT_RIGHT])
	var delta_world := Vector3(dir.x * dist, 0.0, dir.y * dist)
	var clear := true
	for j in range(lo, hi + 1):
		_move_cast.position = perp * float(j)
		_move_cast.target_position = delta_world
		_move_cast.force_shapecast_update()
		if _move_cast.is_colliding():
			clear = false
			break
	_move_cast.position = Vector3.ZERO
	return clear


func _is_in_cover() -> bool:
	# Blend gate: hidden when one pair of opposite footprint sides is fully walled
	# (every adjacent cell on that side is a wall). That is exactly "looks like part
	# of a flat wall": from the two open directions the cube's face lines up coplanar
	# with the flanking walls; from the walled directions it is buried. One pair is
	# enough, so an entrance-plug (two opposite sides walled, two open ends) counts.
	var minx: int = grid_pos.x - _ext[EXT_LEFT]
	var maxx: int = grid_pos.x + _ext[EXT_RIGHT]
	var minz: int = grid_pos.y - _ext[EXT_FWD]
	var maxz: int = grid_pos.y + _ext[EXT_BACK]
	if _column_walled(minx - 1, minz, maxz) and _column_walled(maxx + 1, minz, maxz):
		return true
	return _row_walled(minz - 1, minx, maxx) and _row_walled(maxz + 1, minx, maxx)


func _column_walled(x: int, z0: int, z1: int) -> bool:
	# Flush-blend test for one side. Each cell must be walled to exactly the player's
	# height: a wall at the player's top cell AND no wall just above it. A shorter
	# wall lets the player overtop; a taller wall leaves the player recessed in a
	# notch. Both break the flat-wall look from the open directions, so neither hides.
	var top_y := 0.5 + float(_ext[EXT_UP])
	var above_y := top_y + 1.0
	for z in range(z0, z1 + 1):
		var cell := Vector2i(x, z)
		if _extend_cell_clear(cell, top_y) or not _extend_cell_clear(cell, above_y):
			return false
	return true


func _row_walled(z: int, x0: int, x1: int) -> bool:
	var top_y := 0.5 + float(_ext[EXT_UP])
	var above_y := top_y + 1.0
	for x in range(x0, x1 + 1):
		var cell := Vector2i(x, z)
		if _extend_cell_clear(cell, top_y) or not _extend_cell_clear(cell, above_y):
			return false
	return true


func _sample_cover_color() -> Color:
	# Camouflage: read the albedo of the first standard-material wall adjacent to
	# the footprint. Walk the perimeter (N, E, S, W) and return the first hit;
	# fall back to COLOR_BLENDING if none of the touching walls have a usable
	# material (e.g. perimeter walls without a surface override).
	var minx: int = grid_pos.x - _ext[EXT_LEFT]
	var maxx: int = grid_pos.x + _ext[EXT_RIGHT]
	var minz: int = grid_pos.y - _ext[EXT_FWD]
	var maxz: int = grid_pos.y + _ext[EXT_BACK]
	for x in range(minx, maxx + 1):
		var c := _cell_wall_color(Vector2i(x, minz - 1))
		if c.a > 0.0:
			return c
	for z in range(minz, maxz + 1):
		var c := _cell_wall_color(Vector2i(maxx + 1, z))
		if c.a > 0.0:
			return c
	for x in range(maxx, minx - 1, -1):
		var c := _cell_wall_color(Vector2i(x, maxz + 1))
		if c.a > 0.0:
			return c
	for z in range(maxz, minz - 1, -1):
		var c := _cell_wall_color(Vector2i(minx - 1, z))
		if c.a > 0.0:
			return c
	return COLOR_BLENDING


func _cell_wall_color(cell: Vector2i) -> Color:
	# Albedo of a StandardMaterial3D on the wall at this cell, or transparent
	# sentinel if no wall / no usable material. Looks at surface_override_material
	# first, then the mesh's own surface material as fallback.
	var space := get_world_3d().direct_space_state
	var params := PhysicsPointQueryParameters3D.new()
	params.position = Vector3(cell.x, 0.5, cell.y)
	params.collision_mask = 1
	params.collide_with_areas = false
	var hits := space.intersect_point(params, 1)
	if hits.is_empty():
		return Color(0, 0, 0, 0)
	var body: Object = hits[0].collider
	for child in (body as Node).get_children():
		if child is MeshInstance3D:
			var mi := child as MeshInstance3D
			var mat: Material = mi.get_surface_override_material(0)
			if mat == null and mi.mesh != null:
				mat = mi.mesh.surface_get_material(0)
			if mat is StandardMaterial3D:
				return (mat as StandardMaterial3D).albedo_color
	return Color(0, 0, 0, 0)


func _axis_total(side: int) -> int:
	match side:
		EXT_LEFT, EXT_RIGHT: return _ext[EXT_LEFT] + _ext[EXT_RIGHT]
		EXT_FWD, EXT_BACK:   return _ext[EXT_FWD] + _ext[EXT_BACK]
		_:                   return _ext[EXT_UP]


func _try_extend(side: int) -> void:
	if _axis_total(side) >= 2:
		return
	if not _extend_side_clear(side):
		return
	_ext[side] += 1
	# Extension is a shape-change settle: run the same fall check tumbles do,
	# so an extension that tips the cuboid past its support starts falling. The
	# ink / water / footprint / move_settled side effects gate on not _falling
	# for parity with the tumble path.
	_check_fall_at_settle()
	if not _falling and side != EXT_UP:
		_check_ink_contact_footprint()
		_check_water_contact_footprint()
		_maybe_deposit_footprint()
	if not _falling:
		move_settled.emit()


func _extend_side_clear(side: int) -> bool:
	# An extension may not grow into a wall. EXT_UP grows into the air, always
	# clear; otherwise check every new footprint cell along that side for wall
	# collision. Floor-vs-void is handled separately by the stability test in
	# _try_extend: void is reachable if the resulting shape stays balanced.
	if side == EXT_UP:
		return true
	var minx: int = grid_pos.x - _ext[EXT_LEFT]
	var maxx: int = grid_pos.x + _ext[EXT_RIGHT]
	var minz: int = grid_pos.y - _ext[EXT_FWD]
	var maxz: int = grid_pos.y + _ext[EXT_BACK]
	# Probe low (EXTEND_PROBE_Y) so a safety edge (a short 0.4u blocker) stops the
	# extension too, not just full-height walls. The default 0.5 probe sailed over
	# the edge and let the cube extend across an impassable boundary.
	match side:
		EXT_LEFT:
			for z in range(minz, maxz + 1):
				if not _extend_cell_clear(Vector2i(minx - 1, z), EXTEND_PROBE_Y):
					return false
		EXT_RIGHT:
			for z in range(minz, maxz + 1):
				if not _extend_cell_clear(Vector2i(maxx + 1, z), EXTEND_PROBE_Y):
					return false
		EXT_FWD:
			for x in range(minx, maxx + 1):
				if not _extend_cell_clear(Vector2i(x, minz - 1), EXTEND_PROBE_Y):
					return false
		EXT_BACK:
			for x in range(minx, maxx + 1):
				if not _extend_cell_clear(Vector2i(x, maxz + 1), EXTEND_PROBE_Y):
					return false
	return true


func _extend_cell_clear(cell: Vector2i, probe_y: float = 0.5) -> bool:
	# True if the cell has no wall to grow into. Queries live physics (layer 1), so
	# it respects the perimeter walls (now collision-only) and the gate's current
	# open/closed collision state. "Clear" here means "not a wall" — cover
	# detection uses this to decide whether a neighbor is open from that side.
	# A void cell (no floor) is also "clear" by this definition; cover logic
	# wants that, since you're exposed across a void, not hidden by it.
	# probe_y defaults to base level (the extension-collision callers). The cover
	# check (_column_walled / _row_walled) probes at the player's top cell and just
	# above it to require the wall height to match the player's, not merely exceed it.
	var space := get_world_3d().direct_space_state
	var params := PhysicsPointQueryParameters3D.new()
	params.position = Vector3(cell.x, probe_y, cell.y)
	params.collision_mask = 1
	params.collide_with_areas = false
	return space.intersect_point(params).is_empty()


func _reset_extensions() -> void:
	# Move grid_pos to the cuboid's centre so the visual collapses in place
	# instead of snapping to the original base corner.
	var shift_x: int = roundi((_ext[EXT_RIGHT] - _ext[EXT_LEFT]) / 2.0)
	var shift_z: int = roundi((_ext[EXT_BACK] - _ext[EXT_FWD]) / 2.0)
	grid_pos += Vector2i(shift_x, shift_z)
	position = Vector3(grid_pos.x, 0.5, grid_pos.y)
	_ext = [0, 0, 0, 0, 0]
	# Sync mesh immediately — _reset is called from _input, which runs before
	# camera _process. Without this the camera would read a stale mesh offset.
	_update_mesh()


func _is_extended() -> bool:
	for v in _ext:
		if v > 0:
			return true
	return false


func get_extension_sum() -> int:
	# Total extension units across all axes. Drives the detection size factor and
	# mirrors the noise size factor in _play_step.
	var total: int = _ext[EXT_LEFT] + _ext[EXT_RIGHT] + _ext[EXT_UP] + _ext[EXT_FWD] + _ext[EXT_BACK]
	return total


func get_dimensions() -> Vector3i:
	# Current cuboid dimensions in cells: (width x, height y, depth z). The
	# extend-lock zone compares this against its required_dims.
	return Vector3i(
		1 + _ext[EXT_LEFT] + _ext[EXT_RIGHT],
		1 + _ext[EXT_UP],
		1 + _ext[EXT_FWD] + _ext[EXT_BACK]
	)


func set_extend_locked(value: bool) -> void:
	_extend_locked = value


func is_extend_locked() -> bool:
	return _extend_locked


func is_moving() -> bool:
	return _tumbling or _dodging


func get_footprint_min() -> Vector2i:
	# Min-corner (smallest x, smallest z) cell of the cuboid footprint. Invariant to
	# how the extension is distributed (left vs right, fwd vs back), so it pins the
	# footprint's location regardless of how the shape was built.
	return Vector2i(grid_pos.x - _ext[EXT_LEFT], grid_pos.y - _ext[EXT_FWD])


func footprint_covers(cell: Vector2i) -> bool:
	var minx: int = grid_pos.x - _ext[EXT_LEFT]
	var minz: int = grid_pos.y - _ext[EXT_FWD]
	var w: int = 1 + _ext[EXT_LEFT] + _ext[EXT_RIGHT]
	var d: int = 1 + _ext[EXT_FWD] + _ext[EXT_BACK]
	return cell.x >= minx and cell.x < minx + w and cell.y >= minz and cell.y < minz + d


func is_dodging() -> bool:
	return _dodging


func get_dodge_cooldown_ratio() -> float:
	# 1.0 right after a dodge, ramps to 0.0 when ready again. The HUD bar reads this.
	return clampf(_dodge_cooldown_t / DODGE_COOLDOWN, 0.0, 1.0)


func is_dodge_available() -> bool:
	return _dodge_cooldown_t <= 0.0 and not _is_extended() and not suppress_dodge and not god_mode


func _reset_ground_overlays() -> void:
	# A reloaded scene shares the ground material resource, which still holds the
	# previous run's wave/footprint arrays. The per-frame pushes only cover live
	# entries, so empty lists would leave stale ripples and prints on the floor.
	# Zero them once on spawn for a clean start.
	clear_noise_waves()
	var zp := PackedVector2Array()
	zp.resize(MAX_FOOTPRINTS)
	var za := PackedFloat32Array()
	za.resize(MAX_FOOTPRINTS)
	_ground_material.set_shader_parameter("footprint_positions", zp)
	_ground_material.set_shader_parameter("footprint_alphas", za)


func clear_noise_waves() -> void:
	# Drop all in-flight noise waves and zero the shader arrays. Called on spawn
	# and by the level on a game-over state (the tree pauses there, so the player
	# stops processing and a live wave would otherwise freeze on the floor).
	_waves.clear()
	var zo := PackedVector2Array()
	zo.resize(MAX_WAVES)
	var zf := PackedFloat32Array()
	zf.resize(MAX_WAVES)
	_ground_material.set_shader_parameter("wave_origins", zo)
	_ground_material.set_shader_parameter("wave_half_extents", zo)
	_ground_material.set_shader_parameter("wave_radii", zf)
	_ground_material.set_shader_parameter("wave_alphas", zf)


func truncate_dodge_to(cell: Vector2i) -> void:
	# Cut a dodge short to land on the given cell. Scales remaining duration
	# to preserve the slide's base speed so the cube decelerates smoothly
	# instead of teleporting to the new target.
	if not _dodging:
		return
	var current_pos := position
	var target_pos := Vector3(cell.x, 0.5, cell.y)
	var remaining := (target_pos - current_pos).length()
	if remaining < 0.01:
		return
	var base_speed := float(DODGE_DISTANCE) / DODGE_DURATION
	_dodge_duration = remaining / base_speed
	_dodge_start_pos = current_pos
	_dodge_end_pos = target_pos
	_dodge_t = 0.0
	grid_pos = cell


func _update_mesh() -> void:
	# Mesh always lives in the parent's local frame with identity basis.
	# At rest, parent.basis == IDENTITY so the mesh is world-aligned.
	# During a tumble, parent.basis rotates so the mesh visibly tumbles with it.
	# DetectionArea's shape is resized and re-posed to match, so an enemy touching
	# any cell of the extended footprint triggers caught (the 1x1 shape used to
	# miss the extended portion).
	var size := Vector3(
		1.0 + _ext[EXT_LEFT] + _ext[EXT_RIGHT],
		1.0 + _ext[EXT_UP],
		1.0 + _ext[EXT_FWD] + _ext[EXT_BACK]
	)
	var offset := Vector3(
		(_ext[EXT_RIGHT] - _ext[EXT_LEFT]) * 0.5,
		_ext[EXT_UP] * 0.5,
		(_ext[EXT_BACK] - _ext[EXT_FWD]) * 0.5
	)
	# Only rebuild when the shape actually changes. Assigning BoxMesh.size rebuilds
	# the mesh every call (even to the same value), and this runs every frame; the
	# per-frame rebuild flickered now that faces carry distinct ink colours.
	if size == _box_mesh.size and offset == _mesh_instance.position:
		return
	_box_mesh.size = size
	_mesh_instance.transform = Transform3D(Basis.IDENTITY, offset)
	_detection_shape.size = size
	_detection_collider.transform = Transform3D(Basis.IDENTITY, offset)


func _begin_tumble(dir: Vector2i) -> void:
	_start_pos = position
	_start_basis = basis
	var ext_up_old: int = _ext[EXT_UP]
	var move: int = 0
	var pivot_x: float = position.x
	var pivot_z: float = position.z
	var new_ext: Array = _ext.duplicate()

	if dir.x == 1:
		var ext_dir: int = _ext[EXT_RIGHT]
		pivot_x = position.x + 0.5 + ext_dir
		_axis = Vector3(0, 0, 1)
		_angle = -PI / 2.0
		move = 1 + ext_dir + ext_up_old
		new_ext[EXT_LEFT] = ext_up_old
		new_ext[EXT_RIGHT] = 0
		new_ext[EXT_UP] = _ext[EXT_LEFT] + _ext[EXT_RIGHT]
	elif dir.x == -1:
		var ext_dir: int = _ext[EXT_LEFT]
		pivot_x = position.x - 0.5 - ext_dir
		_axis = Vector3(0, 0, 1)
		_angle = PI / 2.0
		move = 1 + ext_dir + ext_up_old
		new_ext[EXT_RIGHT] = ext_up_old
		new_ext[EXT_LEFT] = 0
		new_ext[EXT_UP] = _ext[EXT_LEFT] + _ext[EXT_RIGHT]
	elif dir.y == -1:
		var ext_dir: int = _ext[EXT_FWD]
		pivot_z = position.z - 0.5 - ext_dir
		_axis = Vector3(1, 0, 0)
		_angle = -PI / 2.0
		move = 1 + ext_dir + ext_up_old
		new_ext[EXT_BACK] = ext_up_old
		new_ext[EXT_FWD] = 0
		new_ext[EXT_UP] = _ext[EXT_FWD] + _ext[EXT_BACK]
	elif dir.y == 1:
		var ext_dir: int = _ext[EXT_BACK]
		pivot_z = position.z + 0.5 + ext_dir
		_axis = Vector3(1, 0, 0)
		_angle = PI / 2.0
		move = 1 + ext_dir + ext_up_old
		new_ext[EXT_FWD] = ext_up_old
		new_ext[EXT_BACK] = 0
		new_ext[EXT_UP] = _ext[EXT_FWD] + _ext[EXT_BACK]
	else:
		return

	if not _can_move_cuboid(dir, move):
		return

	# Floor isn't a tumble blocker any more: tumbles may land on void or on
	# a stable bridge config. The settle-time stability check (run in _process
	# after the animation finishes) is what decides between "ok landing" and
	# "tip and fall".

	_pivot = Vector3(pivot_x, 0.0, pivot_z)
	_pending_ext = new_ext
	_tumble_distance = move
	grid_pos += dir * move
	_t = 0.0
	_tumbling = true
	tumbled.emit()


func _begin_dodge(dir: Vector2i) -> void:
	var max_dist := 0
	for d in range(1, DODGE_DISTANCE + 1):
		if not _can_move(Vector3(dir.x * d, 0, dir.y * d)):
			break
		max_dist = d
	if max_dist == 0:
		return
	_dodge_start_pos = position
	_dodge_end_pos = Vector3(
		grid_pos.x + dir.x * max_dist,
		0.5,
		grid_pos.y + dir.y * max_dist
	)
	grid_pos += dir * max_dist
	_slide_last_cell = Vector2i(roundi(_dodge_start_pos.x), roundi(_dodge_start_pos.z))
	_dodge_t = 0.0
	_dodge_duration = DODGE_DURATION * float(max_dist) / float(DODGE_DISTANCE)
	# Peak heat (and therefore cooldown) scales with distance travelled: a dodge
	# cut short by a wall runs less hot and recovers faster, so 1-cell dodges are
	# cheap, quiet micro-steps in tight spaces.
	_dodge_heat_max = float(max_dist) / float(DODGE_DISTANCE)
	_dodging = true


func _check_fall_at_settle() -> void:
	if god_mode:
		return
	# Called after every settle event (tumble end, dodge end, collapse). The
	# shape is stable iff its geometric center is strictly inside the bounding
	# box of supported (floor) footprint cells. Anything else falls. Idempotent
	# so a second settle inside the same fall doesn't restart it.
	if _falling:
		return
	if not _is_stable_at(grid_pos, _ext):
		_begin_fall()


func _is_floor(cell: Vector2i) -> bool:
	# Null-safe is_floor: _level is absent when the cube runs standalone (editor).
	return _level != null and _level.is_floor(cell)


func _is_stable_at(test_grid_pos: Vector2i, test_ext: Array) -> bool:
	# Center-of-gravity model: the cuboid is stable iff its geometric center
	# (in world XZ) sits strictly inside the axis-aligned bounding box of the
	# floor cells under its footprint. Strict so a 1x2 with one cell over void
	# (centre exactly on the boundary) counts as a tip.
	#
	# Bounding box (not convex hull) is loose for L-shaped or diagonal support
	# patterns, but every common case (1xN bars, NxM rectangles with one corner
	# void) lands the same answer either way. Tighten to a proper hull if a
	# pathological case shows up.
	var center_x: float = float(test_grid_pos.x) + float(test_ext[EXT_RIGHT] - test_ext[EXT_LEFT]) * 0.5
	var center_z: float = float(test_grid_pos.y) + float(test_ext[EXT_BACK] - test_ext[EXT_FWD]) * 0.5
	var minx: int = test_grid_pos.x - test_ext[EXT_LEFT]
	var maxx: int = test_grid_pos.x + test_ext[EXT_RIGHT]
	var minz: int = test_grid_pos.y - test_ext[EXT_FWD]
	var maxz: int = test_grid_pos.y + test_ext[EXT_BACK]
	var sup_minx: int = 0
	var sup_maxx: int = 0
	var sup_minz: int = 0
	var sup_maxz: int = 0
	var found := false
	for x in range(minx, maxx + 1):
		for z in range(minz, maxz + 1):
			if not _is_floor(Vector2i(x, z)):
				continue
			if not found:
				sup_minx = x
				sup_maxx = x
				sup_minz = z
				sup_maxz = z
				found = true
			else:
				sup_minx = mini(sup_minx, x)
				sup_maxx = maxi(sup_maxx, x)
				sup_minz = mini(sup_minz, z)
				sup_maxz = maxi(sup_maxz, z)
	if not found:
		return false
	return (
		center_x > float(sup_minx) - 0.5
		and center_x < float(sup_maxx) + 0.5
		and center_z > float(sup_minz) - 0.5
		and center_z < float(sup_maxz) + 0.5
	)


func _begin_fall() -> void:
	# Engage the fall: clear in-progress animation flags so _process's falling
	# branch owns motion outright, and reset blend so the cube doesn't drop
	# while still tinted with cover color. _setup_tip picks between tipping
	# around a supported edge or a straight drop based on remaining support.
	_falling = true
	_fall_vel = 0.0
	_wedged = false
	_wedge_hold_t = 0.0
	_tumbling = false
	_dodging = false
	_bumping = false
	is_blending = false
	is_hiding = false
	_blend_phase = 0.0
	# Show a random fail "screen" while it falls/wedges (pushed by _push_cube_material below).
	_expression = randi() % EXPRESSION_COUNT
	_push_cube_material()
	_setup_tip()


func _tip_collides_at(angle: float) -> bool:
	# True if any of the cuboid's 8 corners, rotated to `angle` around the tip
	# pivot, would dip below floor surface (y < 0) at an xz on a floor cell.
	# Stops the tip when a tall cuboid would clip into floor on the far side
	# of the gap instead of swinging clean past it; the cube wedges there.
	# The cuboid is convex so corners bound its lowest reach in every rotation.
	var minx: float = float(grid_pos.x) - float(_ext[EXT_LEFT]) - 0.5
	var maxx: float = float(grid_pos.x) + float(_ext[EXT_RIGHT]) + 0.5
	var minz: float = float(grid_pos.y) - float(_ext[EXT_FWD]) - 0.5
	var maxz: float = float(grid_pos.y) + float(_ext[EXT_BACK]) + 0.5
	var ymax: float = 1.0 + float(_ext[EXT_UP])
	# Shrink the sampled box by WEDGE_INSET on every side before rounding. Two
	# jobs. (1) The cube's faces sit exactly on cell boundaries (the ±0.5 above),
	# and roundi() pushes a boundary corner onto the flanking cell; insetting xz
	# maps each corner to the cube's own column, so a corner descending cleanly
	# into a 1-wide gap stops false-firing against the floor beside it. (2)
	# Insetting y too makes the wedge fire only on real overlap, not a bare touch:
	# a tall pillar that just fits a snug hole lands its far corner on the far rim
	# at 90°; without the y inset that rim rounds onto the far floor and wedges
	# when it should tip in and drop.
	var xs := [minx + WEDGE_INSET, maxx - WEDGE_INSET]
	var ys := [WEDGE_INSET, ymax - WEDGE_INSET]
	var zs := [minz + WEDGE_INSET, maxz - WEDGE_INSET]
	for x in xs:
		for y in ys:
			for z in zs:
				var corner := Vector3(x, y, z)
				var rotated := (corner - _tip_pivot).rotated(_tip_axis, angle) + _tip_pivot
				if rotated.y >= 0.0:
					continue
				var cell := Vector2i(roundi(rotated.x), roundi(rotated.z))
				if _is_floor(cell):
					return true
	return false


func _setup_tip() -> void:
	# Decide whether the fall is a tip (any footprint cell still supported) or
	# a straight drop (none). For a tip, the pivot is the point on the support
	# bounding box closest to the centre of mass; the axis is perpendicular to
	# that overhang so positive rotation drops the unsupported side. When the
	# COG sits exactly on the support boundary (the knife-edge 1x2 case), pick
	# the tip direction from footprint-centre vs support-centre instead.
	_tipping = false
	var center_x: float = float(grid_pos.x) + float(_ext[EXT_RIGHT] - _ext[EXT_LEFT]) * 0.5
	var center_z: float = float(grid_pos.y) + float(_ext[EXT_BACK] - _ext[EXT_FWD]) * 0.5
	var minx: int = grid_pos.x - _ext[EXT_LEFT]
	var maxx: int = grid_pos.x + _ext[EXT_RIGHT]
	var minz: int = grid_pos.y - _ext[EXT_FWD]
	var maxz: int = grid_pos.y + _ext[EXT_BACK]
	var sup_minx: int = 0
	var sup_maxx: int = 0
	var sup_minz: int = 0
	var sup_maxz: int = 0
	var found := false
	for x in range(minx, maxx + 1):
		for z in range(minz, maxz + 1):
			if not _is_floor(Vector2i(x, z)):
				continue
			if not found:
				sup_minx = x
				sup_maxx = x
				sup_minz = z
				sup_maxz = z
				found = true
			else:
				sup_minx = mini(sup_minx, x)
				sup_maxx = maxi(sup_maxx, x)
				sup_minz = mini(sup_minz, z)
				sup_maxz = maxi(sup_maxz, z)
	if not found:
		return
	var pivot_x: float = clampf(center_x, float(sup_minx) - 0.5, float(sup_maxx) + 0.5)
	var pivot_z: float = clampf(center_z, float(sup_minz) - 0.5, float(sup_maxz) + 0.5)
	var dx: float = center_x - pivot_x
	var dz: float = center_z - pivot_z
	if absf(dx) < 0.001 and absf(dz) < 0.001:
		var foot_cx: float = float(minx + maxx) * 0.5
		var foot_cz: float = float(minz + maxz) * 0.5
		var sup_cx: float = float(sup_minx + sup_maxx) * 0.5
		var sup_cz: float = float(sup_minz + sup_maxz) * 0.5
		dx = foot_cx - sup_cx
		dz = foot_cz - sup_cz
	if absf(dx) < 0.001 and absf(dz) < 0.001:
		return
	_tipping = true
	_tip_pivot = Vector3(pivot_x, 0.0, pivot_z)
	_tip_axis = Vector3(dz, 0.0, -dx).normalized()
	_tip_angle = 0.0
	_tip_vel = TIP_INITIAL_VEL
	_tip_start_pos = position
	_tip_start_basis = basis


func _begin_blocked_bump(dir: Vector2i) -> void:
	# Won't-fit feedback: the extended shape tips toward dir and rocks back, like
	# bouncing off something solid, with a soft thud. No noise wave — this is pure
	# feedback, not a distraction (knock is the only deliberate noise, and it is
	# cube-only). Pivot is the leading bottom edge, so it reads as the start of a
	# tumble that couldn't complete.
	#
	# Scale the lean by the free space ahead so it never tips into the wall: the
	# top-leading corner reaches height * sin(angle) forward, so cap sin(angle) at
	# (gap / height). Flush against a wall (gap 0) leaves no room — just thud.
	var height: float = 1.0 + float(_ext[EXT_UP])
	var gap: float = float(_gap_ahead(dir))
	var mag: float = minf(BUMP_ANGLE, asin(clampf((gap - BUMP_CLEARANCE) / height, 0.0, 1.0)))
	if mag <= 0.001:
		_play_thud()
		return
	_start_pos = position
	_start_basis = basis
	var pivot_x: float = position.x
	var pivot_z: float = position.z
	if dir.x == 1:
		pivot_x = position.x + 0.5 + float(_ext[EXT_RIGHT])
		_bump_axis = Vector3(0, 0, 1)
		_bump_angle = -mag
	elif dir.x == -1:
		pivot_x = position.x - 0.5 - float(_ext[EXT_LEFT])
		_bump_axis = Vector3(0, 0, 1)
		_bump_angle = mag
	elif dir.y == -1:
		pivot_z = position.z - 0.5 - float(_ext[EXT_FWD])
		_bump_axis = Vector3(1, 0, 0)
		_bump_angle = -mag
	elif dir.y == 1:
		pivot_z = position.z + 0.5 + float(_ext[EXT_BACK])
		_bump_axis = Vector3(1, 0, 0)
		_bump_angle = mag
	else:
		return
	_bump_pivot = Vector3(pivot_x, 0.0, pivot_z)
	_bump_t = 0.0
	_bumping = true
	_play_thud()


func _gap_ahead(dir: Vector2i) -> int:
	# Cells clear of walls between the leading face and the nearest obstruction
	# along dir, taken as the minimum across the face's width (the binding
	# side). Capped at the cuboid height — past that the lean is maxed, so
	# more room is irrelevant. Void cells count as clear: the bump animation
	# only fires when wall-blocked, and the lean magnitude is about how far
	# the shape can tip before something solid stops it.
	var minx: int = grid_pos.x - _ext[EXT_LEFT]
	var maxx: int = grid_pos.x + _ext[EXT_RIGHT]
	var minz: int = grid_pos.y - _ext[EXT_FWD]
	var maxz: int = grid_pos.y + _ext[EXT_BACK]
	var cap: int = 1 + int(_ext[EXT_UP])
	var gap: int = cap
	if dir.x != 0:
		var lead_x: int = (maxx if dir.x > 0 else minx)
		for z in range(minz, maxz + 1):
			var d := 0
			while d < cap and _extend_cell_clear(Vector2i(lead_x + dir.x * (d + 1), z)):
				d += 1
			gap = mini(gap, d)
	else:
		var lead_z: int = (maxz if dir.y > 0 else minz)
		for x in range(minx, maxx + 1):
			var d := 0
			while d < cap and _extend_cell_clear(Vector2i(x, lead_z + dir.y * (d + 1))):
				d += 1
			gap = mini(gap, d)
	return gap


func _play_step(noise_level: float) -> void:
	var ext_sum: int = _ext[EXT_LEFT] + _ext[EXT_RIGHT] + _ext[EXT_UP] + _ext[EXT_FWD] + _ext[EXT_BACK]
	var size_factor := 1.0 + ext_sum * 0.15
	_step_player.volume_db = linear_to_db(STEP_GAIN * noise_level * size_factor)
	_step_player.pitch_scale = 1.0 - ext_sum * 0.08
	_step_player.play()
	var max_radius: float = (STEP_RADIUS_SPRINT if noise_level > 1.0 else STEP_RADIUS_NORMAL) + float(ext_sum)
	if _waves.size() >= MAX_WAVES:
		_waves.pop_front()
	# Wave originates from the footprint of the landed face
	var origin := Vector2(
		grid_pos.x + (_ext[EXT_RIGHT] - _ext[EXT_LEFT]) * 0.5,
		grid_pos.y + (_ext[EXT_BACK] - _ext[EXT_FWD]) * 0.5
	)
	var half_extent := Vector2(
		(_ext[EXT_LEFT] + _ext[EXT_RIGHT]) * 0.5,
		(_ext[EXT_FWD] + _ext[EXT_BACK]) * 0.5
	)
	_waves.append({
		"origin": origin,
		"half_extent": half_extent,
		"t": 0.0,
		"max_radius": max_radius
	})
	noise_emitted.emit(origin, max_radius, WAVE_DURATION)


func _emit_knock(dir: Vector2i) -> void:
	# Loud noise at the adjacent wall cell the cube rapped on, using the same
	# wave/noise plumbing the enemy hears. Cube-only (the caller gates on it), so
	# the origin is just grid_pos + dir and there is no extension size factor.
	_step_player.volume_db = 0.0
	_step_player.pitch_scale = 0.65
	_step_player.play()
	var origin := Vector2(grid_pos.x + dir.x, grid_pos.y + dir.y)
	if _waves.size() >= MAX_WAVES:
		_waves.pop_front()
	_waves.append({
		"origin": origin,
		"half_extent": Vector2.ZERO,
		"t": 0.0,
		"max_radius": KNOCK_RADIUS
	})
	noise_emitted.emit(origin, KNOCK_RADIUS, WAVE_DURATION)


func _play_thud() -> void:
	# Soft, non-alerting bump cue for a blocked extended move. Reuses the step
	# waveform, low and quiet; placeholder until the audio pass adds a real thud.
	_step_player.volume_db = linear_to_db(0.35)
	_step_player.pitch_scale = 0.5
	_step_player.play()


func _instant_focus() -> Vector3:
		# The "ideal" focus this frame, before smoothing. Y is pinned at the base
	# cell height so the camera doesn't bob when cuboid height changes.
	if _tumbling:
		var start_off := Vector3(
			(_ext[EXT_RIGHT] - _ext[EXT_LEFT]) * 0.5,
			0.0,
			(_ext[EXT_BACK] - _ext[EXT_FWD]) * 0.5
		)
		var end_off := Vector3(
			(_pending_ext[EXT_RIGHT] - _pending_ext[EXT_LEFT]) * 0.5,
			0.0,
			(_pending_ext[EXT_BACK] - _pending_ext[EXT_FWD]) * 0.5
		)
		var start_center := Vector3(_start_pos.x, 0.5, _start_pos.z) + start_off
		var end_center := Vector3(grid_pos.x, 0.5, grid_pos.y) + end_off
		return start_center.lerp(end_center, _t)
	var mesh_pos := _mesh_instance.global_position
	return Vector3(mesh_pos.x, 0.5, mesh_pos.z)


func get_camera_focus() -> Vector3:
	# Track the cuboid's visual centre. Snap during tumble/dodge so those
	# animations remain crisp; smooth at rest so extension presses don't pop.
	var instant := _instant_focus()
	if _tumbling or _dodging:
		_smoothed_focus = instant
	else:
		var dt := get_process_delta_time()
		var alpha := 1.0 - exp(-FOCUS_SMOOTH_RATE * dt)
		_smoothed_focus = _smoothed_focus.lerp(instant, alpha)
	return _smoothed_focus


func _pick_dir(move: Vector2) -> Vector2i:
	if absf(move.x) >= absf(move.y):
		return Vector2i(1 if move.x > 0.0 else -1, 0)
	return Vector2i(0, 1 if move.y > 0.0 else -1)


func _move_just_pressed() -> bool:
	return (Input.is_action_just_pressed("move_left")
		or Input.is_action_just_pressed("move_right")
		or Input.is_action_just_pressed("move_forward")
		or Input.is_action_just_pressed("move_back"))


func _capture_buffer() -> void:
	# Record the latest discrete shape press so it can fire when the current move
	# settles (consumed by _take_action). Movement and dodge are held inputs and
	# are read live, never buffered.
	for action in BUFFERABLE:
		if Input.is_action_just_pressed(action):
			_buf_action = action
			_buf_t = INPUT_BUFFER_TIME
			return


func _take_action(action: String) -> bool:
	# True (and consumes) if `action` is the buffered press. Fresh presses route
	# through the buffer too (captured the same frame), so this is the only read
	# site for these actions.
	if _buf_action == action and _buf_t > 0.0:
		_buf_action = ""
		return true
	return false


func _has_tall_wall(cell: Vector2i) -> bool:
	# A full-height wall occupies this cell (probed above the safety-edge top), as
	# opposed to a short safety edge or open void. Gates the knock so only real
	# walls can be rapped.
	return not _extend_cell_clear(cell, SAFETY_EDGE_PROBE_Y)


func _process(delta: float) -> void:
	_decay_footprints(delta)
	# Input buffer: a discrete shape press (collapse/extend) made mid-animation is
	# held so it fires when the move settles instead of being eaten by the early
	# returns below. The grace timer only counts down while NOT animating (an idle
	# frame consumes it immediately), so it survives a long tumble but still
	# expires if nothing acts on it.
	var mid_anim := _tumbling or _dodging or _bumping or _falling
	if not mid_anim and _buf_t > 0.0:
		_buf_t = maxf(_buf_t - delta, 0.0)
		if _buf_t <= 0.0:
			_buf_action = ""
	_capture_buffer()
	for i in range(_waves.size() - 1, -1, -1):
		_waves[i].t = minf(_waves[i].t + delta / WAVE_DURATION, 1.0)
		if _waves[i].t >= 1.0:
			_waves.remove_at(i)

	var origins := PackedVector2Array()
	var half_extents := PackedVector2Array()
	var radii := PackedFloat32Array()
	var alphas := PackedFloat32Array()
	origins.resize(MAX_WAVES)
	half_extents.resize(MAX_WAVES)
	radii.resize(MAX_WAVES)
	alphas.resize(MAX_WAVES)
	for i in _waves.size():
		origins[i] = _waves[i].origin
		half_extents[i] = _waves[i].half_extent
		radii[i] = _waves[i].max_radius * _waves[i].t
		alphas[i] = 1.0 - _waves[i].t
	_ground_material.set_shader_parameter("wave_origins", origins)
	_ground_material.set_shader_parameter("wave_half_extents", half_extents)
	_ground_material.set_shader_parameter("wave_radii", radii)
	_ground_material.set_shader_parameter("wave_alphas", alphas)
	_ground_material.set_shader_parameter("player_xz", Vector2(global_position.x, global_position.z))

	if _dodge_cooldown_t > 0.0:
		_dodge_cooldown_t = maxf(_dodge_cooldown_t - delta, 0.0)
		if _dodge_cooldown_t == 0.0:
			_dodge_flash = DODGE_FLASH_TIME   # just cooled to ready: fire the green blink
			_ready_player.play()              # soft positive "dodge ready" chime
	if _dodge_flash > 0.0:
		_dodge_flash = maxf(_dodge_flash - delta, 0.0)
	if _knock_cooldown_t > 0.0:
		_knock_cooldown_t = maxf(_knock_cooldown_t - delta, 0.0)

	# Falling: cuboid lost stability. Two phases. While _tipping, rotate the
	# cube around the supported edge with angular acceleration so the
	# unsupported side pivots into the hole; if a corner of the cuboid would
	# clip into floor on the far side of the gap, freeze the rotation (wedge)
	# and hold WEDGE_HOLD_TIME so the jam is visible, then emit fell. At
	# TIP_END_ANGLE the cube has cleared the edge; hand off to straight gravity,
	# inheriting the tangent's downward
	# component as initial _fall_vel. With no support to tip around (cube
	# tumbled alone onto void), skip the tip and drop straight. In the drop
	# branch, position.y crossing FALL_END_Y triggers the fell signal.
	if _falling:
		if _wedged:
			# Hang in the jammed pose with the tree running, then end the run so
			# the wedge is on screen before the results panel appears.
			_wedge_hold_t += delta
			if _wedge_hold_t >= WEDGE_HOLD_TIME:
				wedged.emit()   # jammed in a gap: its own fail, not a fall
				_falling = false
				_tipping = false
				_wedged = false
			return
		if _tipping:
			_tip_vel += TIP_ANGULAR_ACCEL * delta
			var new_angle := _tip_angle + _tip_vel * delta
			if new_angle >= TIP_END_ANGLE:
				# Reached vertical: the cube has cleared the near edge, so commit to
				# a straight drop. The wedge check is deliberately skipped at and past
				# TIP_END_ANGLE. A step can overshoot 90° by several degrees (the tip
				# is moving ~8°/frame by now), and past vertical the low corner swings
				# back under the near floor, which reads as a collision but is not a
				# wedge.
				_tip_angle = TIP_END_ANGLE
				var end_offset := (_tip_start_pos - _tip_pivot).rotated(_tip_axis, _tip_angle)
				var tangent := _tip_axis.cross(end_offset)
				_fall_vel = maxf(0.0, -tangent.y * _tip_vel)
				position = _tip_pivot + end_offset
				basis = Basis(_tip_axis, _tip_angle) * _tip_start_basis
				_tipping = false
			elif _tip_collides_at(new_angle):
				# Jammed before reaching vertical: freeze at the last clear angle and
				# hold before emitting fell.
				_wedged = true
				_wedge_hold_t = 0.0
				return
			else:
				_tip_angle = new_angle
				position = _tip_pivot + (_tip_start_pos - _tip_pivot).rotated(_tip_axis, _tip_angle)
				basis = Basis(_tip_axis, _tip_angle) * _tip_start_basis
		else:
			_fall_vel += FALL_GRAVITY * delta
			position.y -= _fall_vel * delta
		if position.y <= FALL_END_Y:
			fell.emit()
			_falling = false
			_tipping = false
		return

	# Blend phase: rises only when at rest, still, and in cover; forced toward 0
	# during animations so the cube visibly fades back as motion starts. Enter is
	# slow (the delay IS the fade), exit is fast so peeking out is detectable
	# almost instantly. is_blending (gameplay) flips only at full phase.
	var move := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var is_animating := _dodging or _tumbling or _bumping
	var wants_blend := not is_animating and move.length() <= 0.5 and _is_in_cover()
	is_hiding = wants_blend  # nav-block flag for enemies: kicks in immediately on entering cover at rest, before the visual fade completes
	if wants_blend and not _was_wanting_blend:
		_cover_color = _sample_cover_color()
	_was_wanting_blend = wants_blend
	var blend_target := 1.0 if wants_blend else 0.0
	var blend_rate := delta / (BLEND_ENTER_TIME if wants_blend else BLEND_EXIT_TIME)
	_blend_phase = move_toward(_blend_phase, blend_target, blend_rate)
	is_blending = _blend_phase >= 1.0
	_push_cube_material()

	if _dodging:
		_dodge_t = minf(_dodge_t + delta / _dodge_duration, 1.0)
		var t_eased := 1.0 - pow(1.0 - _dodge_t, 3.0)
		position = _dodge_start_pos.lerp(_dodge_end_pos, t_eased)
		var current_cell := Vector2i(roundi(position.x), roundi(position.z))
		if current_cell != _slide_last_cell:
			_slide_last_cell = current_cell
			_check_ink_contact()
			_check_water_contact()
			if not _ink_cells.has(current_cell) and _face_marks[_down_face_id()]:
				_deposit_streak_cell(current_cell)
		if _dodge_t >= 1.0:
			_dodging = false
			position = _dodge_end_pos
			# Cooldown is proportional to the heat built up (distance travelled).
			_dodge_cooldown_t = DODGE_COOLDOWN * _dodge_heat_max
			_check_fall_at_settle()
			if not _falling:
				_check_ink_contact()
				_check_water_contact()
				move_settled.emit()
		_update_mesh()
		return

	if _tumbling:
		var sprinting := Input.is_action_pressed("sprint") and not _is_extended()
		var per_cell := SPRINT_DURATION if sprinting else TUMBLE_DURATION
		var duration := per_cell * sqrt(float(_tumble_distance))
		_t = minf(_t + delta / duration, 1.0)
		var angle := _angle * _t
		position = _pivot + (_start_pos - _pivot).rotated(_axis, angle)
		basis = Basis(_axis, angle) * _start_basis
		if _t >= 1.0:
			_tumbling = false
			position = Vector3(grid_pos.x, 0.5, grid_pos.y)
			basis = Basis.IDENTITY
			_orient = _quantize_basis(Basis(_axis, _angle) * _orient)
			_ext = _pending_ext
			_check_fall_at_settle()
			if not _falling:
				_play_step(TUMBLE_DURATION / per_cell)
				_check_ink_contact_footprint()
				_check_water_contact_footprint()
				_maybe_deposit_footprint()
				move_settled.emit()
			# Re-push face colours AFTER orientation + settle-frame ink update; the
			# blend section ran earlier this frame with the OLD orientation, so without
			# this the cube shows pre-tumble colours for one frame (the blink as ink
			# crosses top/bottom).
			_push_cube_material()
		_update_mesh()
		return

	if _bumping:
		_bump_t = minf(_bump_t + delta / BUMP_DURATION, 1.0)
		var lean := sin(_bump_t * PI) * _bump_angle
		position = _bump_pivot + (_start_pos - _bump_pivot).rotated(_bump_axis, lean)
		basis = Basis(_bump_axis, lean) * _start_basis
		if _bump_t >= 1.0:
			_bumping = false
			position = Vector3(grid_pos.x, 0.5, grid_pos.y)
			basis = Basis.IDENTITY
		_update_mesh()
		return

	# Extend / collapse are discrete shape changes, read through the input buffer
	# (_take_action) so a press made mid-tumble applies on settle instead of being
	# dropped. Arrows grow width/depth, E grows up; collapse resets to a cube.
	if not _extend_locked:
		var ext := -1
		if _take_action("extend_left"):
			ext = EXT_LEFT
		elif _take_action("extend_right"):
			ext = EXT_RIGHT
		elif _take_action("extend_fwd"):
			ext = EXT_FWD
		elif _take_action("extend_back"):
			ext = EXT_BACK
		elif _take_action("extend_up"):
			ext = EXT_UP
		if ext != -1:
			_try_extend(ext)
			_update_mesh()
			return

	if _is_extended() and not _extend_locked and _take_action("collapse"):
		_reset_extensions()
		_update_mesh()
		# Collapse shifts grid_pos to the cuboid centre; if that lands on void
		# (the bridge case collapsing over its gap) the cube starts to fall.
		_check_fall_at_settle()
		return

	# Holding dodge primes it AND locks out tumbling, so you can line up a dodge
	# without stepping. A ready dodge fires on a direction; a cooling one just
	# holds still (the HUD bar shows why). Extension and god_mode (editor cursor)
	# disable dodge entirely.
	var dodge_held := (Input.is_action_pressed("dodge")
		and not _is_extended() and not suppress_dodge and not god_mode)
	var dodge_ready := dodge_held and _dodge_cooldown_t <= 0.0

	if dodge_ready and move.length() > 0.5:
		_begin_dodge(_pick_dir(move))
	elif not dodge_held and move.length() > 0.5:
		_begin_tumble(_pick_dir(move))

	# A directional tap that couldn't tumble. A compact cube raps an adjacent
	# FULL-HEIGHT wall (a loud knock to investigate); it does NOT knock on a short
	# safety edge or empty void. An extended shape bumps back with a soft thud.
	# The just-pressed edge stops a held direction from spamming either.
	if (not _tumbling and not _dodging and not dodge_held
			and move.length() > 0.5 and _move_just_pressed()):
		var kdir := _pick_dir(move)
		if _is_extended():
			_begin_blocked_bump(kdir)
		elif _knock_cooldown_t <= 0.0 and _has_tall_wall(grid_pos + kdir):
			_emit_knock(kdir)
			_knock_cooldown_t = KNOCK_COOLDOWN

	_update_mesh()


func _check_ink_contact() -> void:
	# Single cell at the render position, so it stays in sync with a fast dodge
	# slide (the Area3D overlap count lags the position lerp). The dodge path is
	# cube-only (dodge is locked while extended), so 1x1 is correct here.
	if _ink_cells.has(Vector2i(roundi(position.x), roundi(position.z))):
		_ink_face_contact()


func _check_ink_contact_footprint() -> void:
	# Tumble-landing check across the whole resting footprint, so an extended
	# cuboid inks its down face if ANY cell beneath it is an ink cell.
	var minx: int = grid_pos.x - _ext[EXT_LEFT]
	var maxx: int = grid_pos.x + _ext[EXT_RIGHT]
	var minz: int = grid_pos.y - _ext[EXT_FWD]
	var maxz: int = grid_pos.y + _ext[EXT_BACK]
	for cx in range(minx, maxx + 1):
		for cz in range(minz, maxz + 1):
			if _ink_cells.has(Vector2i(cx, cz)):
				_ink_face_contact()
				return


func _ink_face_contact() -> void:
	# Mark the current down face (binary, whole-face) and splash, once per face.
	var face: int = _down_face_id()
	if _face_marks[face]:
		return
	_face_marks[face] = true
	_splash_player.play()


func _check_water_contact() -> void:
	# Single cell at render position; for dodge (cube-only, locked while extended).
	# Slides cross cells faster than Area3D enter signals, so a dictionary lookup
	# is the responsive path.
	if _water_cells.has(Vector2i(roundi(position.x), roundi(position.z))):
		_try_cleanse()


func _check_water_contact_footprint() -> void:
	# Full-footprint check for tumble landings and extensions. Any covered water
	# cell cleanses marks once; subsequent covered cells find nothing to clear.
	var minx: int = grid_pos.x - _ext[EXT_LEFT]
	var maxx: int = grid_pos.x + _ext[EXT_RIGHT]
	var minz: int = grid_pos.y - _ext[EXT_FWD]
	var maxz: int = grid_pos.y + _ext[EXT_BACK]
	for cx in range(minx, maxx + 1):
		for cz in range(minz, maxz + 1):
			if _water_cells.has(Vector2i(cx, cz)):
				_try_cleanse()
				return


func _try_cleanse() -> void:
	if not _any_marked():
		return
	for i in _face_marks.size():
		_face_marks[i] = false
	_splash_player.play()


func _maybe_deposit_footprint() -> void:
	# Lay a print on every off-ink cell beneath the resting down face. For a cube
	# that's the single base cell; for an extended cuboid it's the whole footprint,
	# so a marked bar leaves a continuous trail the enemy can follow. Cells sitting
	# on ink are skipped (the puddle is the mark there). Per-cell ink test replaces
	# the old base-cell-only puddle-overlap gate so a cuboid straddling ink is
	# handled correctly.
	if not _face_marks[_down_face_id()]:
		return
	var minx: int = grid_pos.x - _ext[EXT_LEFT]
	var maxx: int = grid_pos.x + _ext[EXT_RIGHT]
	var minz: int = grid_pos.y - _ext[EXT_FWD]
	var maxz: int = grid_pos.y + _ext[EXT_BACK]
	var deposited := false
	for cx in range(minx, maxx + 1):
		for cz in range(minz, maxz + 1):
			if _ink_cells.has(Vector2i(cx, cz)):
				continue
			_add_footprint(Vector2(cx, cz))
			deposited = true
	if deposited:
		_update_footprint_uniforms()


func _deposit_streak_cell(cell: Vector2i) -> void:
	# One soft-tile footprint at the cell centre. Adjacent dodge cells merge
	# in the shader since each tile's soft edge reaches the cell boundary.
	# The caller gates this on the cell being off-ink.
	_add_footprint(Vector2(cell.x, cell.y))
	_update_footprint_uniforms()


func _add_footprint(pos: Vector2) -> void:
	if _footprints.size() >= MAX_FOOTPRINTS:
		_footprints.pop_front()
	_footprints.append({ "position": pos, "alpha": 1.0 })


func _decay_footprints(delta: float) -> void:
	# Prints fade with age (oldest reach zero first) and clear when spent. Drives
	# both the visual fade and the enemy trail, which only follows live prints.
	if _footprints.is_empty():
		return
	var fade := delta / FOOTPRINT_FADE_TIME
	for i in range(_footprints.size() - 1, -1, -1):
		_footprints[i].alpha -= fade
		if _footprints[i].alpha <= 0.0:
			_footprints.remove_at(i)
	_update_footprint_uniforms()


func _update_footprint_uniforms() -> void:
	var positions := PackedVector2Array()
	var alphas := PackedFloat32Array()
	positions.resize(MAX_FOOTPRINTS)
	alphas.resize(MAX_FOOTPRINTS)
	for i in _footprints.size():
		positions[i] = _footprints[i].position
		alphas[i] = _footprints[i].alpha
	_ground_material.set_shader_parameter("footprint_positions", positions)
	_ground_material.set_shader_parameter("footprint_alphas", alphas)


func _push_walls_to_shader() -> void:
	# One-time enumeration of static walls for the ground shader's LoS check.
	# Skips Perimeter* (arena edge — never blocks visibility inside the bounds).
	var mins := PackedVector2Array()
	var maxs := PackedVector2Array()
	mins.resize(MAX_WALLS)
	maxs.resize(MAX_WALLS)
	var count := 0
	for child in get_parent().get_children():
		if count >= MAX_WALLS:
			break
		if not (child is StaticBody3D and child.name.begins_with("Wall")):
			continue
		var mesh_node := child.get_node_or_null("MeshInstance3D") as MeshInstance3D
		if mesh_node == null:
			continue
		var box := mesh_node.mesh as BoxMesh
		if box == null:
			continue
		var half := Vector2(box.size.x * 0.5, box.size.z * 0.5)
		var pos := Vector2(child.position.x, child.position.z)
		mins[count] = pos - half
		maxs[count] = pos + half
		count += 1
	_ground_material.set_shader_parameter("wall_mins", mins)
	_ground_material.set_shader_parameter("wall_maxs", maxs)
	_ground_material.set_shader_parameter("wall_count", count)


func get_footprint_positions() -> PackedVector2Array:
	var out := PackedVector2Array()
	for fp in _footprints:
		out.append(fp.position)
	return out


func get_footprint_alphas() -> PackedFloat32Array:
	# Index-aligned with get_footprint_positions. Alpha doubles as freshness
	# (deposited at 1.0, uniform fade), which the enemy's trail-memory uses to
	# ignore prints older than ones it has already investigated.
	var out := PackedFloat32Array()
	for fp in _footprints:
		out.append(fp.alpha)
	return out


func consume_footprints_in_cell(cell: Vector2i) -> void:
	var changed := false
	for i in range(_footprints.size() - 1, -1, -1):
		var p: Vector2 = _footprints[i].position
		if Vector2i(roundi(p.x), roundi(p.y)) == cell:
			_footprints.remove_at(i)
			changed = true
	if changed:
		_update_footprint_uniforms()


func _down_face_id() -> int:
	# Use logical _orient (not visual basis) so face tracking persists across
	# tumbles even though the visual mesh snaps back to identity at rest.
	var local_down: Vector3 = _orient.inverse() * Vector3.DOWN
	return _dir_to_face_id(local_down)


func _dir_to_face_id(d: Vector3) -> int:
	if d.x > 0.5: return FACE_X_POS
	if d.x < -0.5: return FACE_X_NEG
	if d.y > 0.5: return FACE_Y_POS
	if d.y < -0.5: return FACE_Y_NEG
	if d.z > 0.5: return FACE_Z_POS
	return FACE_Z_NEG


func _quantize_basis(b: Basis) -> Basis:
	# Snap each rotated axis to its nearest cardinal direction so accumulated
	# float drift across many tumbles doesn't compound.
	return Basis(
		_snap_to_cardinal(b * Vector3.RIGHT),
		_snap_to_cardinal(b * Vector3.UP),
		_snap_to_cardinal(b * Vector3.BACK)
	)


func _snap_to_cardinal(v: Vector3) -> Vector3:
	var ax := absf(v.x)
	var ay := absf(v.y)
	var az := absf(v.z)
	if ax >= ay and ax >= az:
		return Vector3(signf(v.x), 0.0, 0.0)
	if ay >= az:
		return Vector3(0.0, signf(v.y), 0.0)
	return Vector3(0.0, 0.0, signf(v.z))


func _any_marked() -> bool:
	for m in _face_marks:
		if m:
			return true
	return false


func _base_color() -> Color:
	# Body colour ignoring blend and ink. Ink is now shown PER FACE by the cube
	# shader (not a whole-cube tint), so this is just the locked/normal body state;
	# the blend fade lerps it toward _cover_color by _blend_phase.
	if _extend_locked:
		return COLOR_LOCKED
	return COLOR_NORMAL


func _push_cube_material() -> void:
	# Drive the per-face cube shader: body/cover/blend plus which mesh faces are
	# inked. Pushed every visual frame (cheap) so blend and orientation stay live.
	_player_material.set_shader_parameter("base_color", _base_color())
	_player_material.set_shader_parameter("cover_color", _cover_color)
	_player_material.set_shader_parameter("blend_phase", _blend_phase)
	_player_material.set_shader_parameter("face_ink", _compute_face_ink())
	# Dodge cooldown shown as edge heat on the cube (replaces the HUD bar). Heat
	# BUILDS over the dodge (0 -> peak), then dissipates over the cooldown.
	var heat: float
	if _dodging:
		heat = _dodge_heat_max * _dodge_t
	else:
		heat = clampf(_dodge_cooldown_t / DODGE_COOLDOWN, 0.0, 1.0)
	_player_material.set_shader_parameter("cube_half", _box_mesh.size * 0.5)
	_player_material.set_shader_parameter("dodge_heat", heat)
	_player_material.set_shader_parameter("dodge_flash", _dodge_flash / DODGE_FLASH_TIME)
	_player_material.set_shader_parameter("expression", _expression)


func _compute_face_ink() -> PackedFloat32Array:
	# Map logical face marks to MESH-LOCAL faces via the current orientation, so an
	# inked face shows on whichever side it has rolled to. Index order matches the
	# shader and the FACE_* ids: +X, -X, +Y, -Y, +Z, -Z.
	var dirs := [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD]
	var inv := _orient.inverse()
	var out := PackedFloat32Array()
	out.resize(6)
	for i in 6:
		out[i] = 1.0 if _face_marks[_dir_to_face_id(inv * dirs[i])] else 0.0
	return out


static func _make_splash_sound() -> AudioStreamWAV:
	var rate := 44100
	var samples := 4096
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	var data := PackedByteArray()
	data.resize(samples * 2)
	for i in samples:
		var env := exp(-float(i) / 800.0)
		var freq: float = 200.0 - float(i) / float(samples) * 100.0
		var val := int(sin(float(i) * TAU * freq / float(rate)) * env * 32767.0)
		data[i * 2] = val & 0xFF
		data[i * 2 + 1] = (val >> 8) & 0xFF
	stream.data = data
	return stream


static func _make_step_sound() -> AudioStreamWAV:
	var rate := 44100
	var samples := 2048
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	var data := PackedByteArray()
	data.resize(samples * 2)
	for i in samples:
		var env := exp(-float(i) / 300.0)
		var val := int(sin(float(i) * TAU * 150.0 / rate) * env * 32767.0)
		data[i * 2] = val & 0xFF
		data[i * 2 + 1] = (val >> 8) & 0xFF
	stream.data = data
	return stream


static func _make_ready_sound() -> AudioStreamWAV:
	# Soft, short, rising blip: a gentle "dodge ready" confirmation. Quiet (low
	# amplitude), pitch glides up a fifth, with a soft attack and gentle release.
	var rate := 44100
	var samples := int(rate * 0.16)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	var data := PackedByteArray()
	data.resize(samples * 2)
	var phase := 0.0
	for i in samples:
		var u := float(i) / float(samples)
		var freq := lerpf(680.0, 1020.0, u)
		phase += TAU * freq / float(rate)
		var env := minf(u / 0.05, 1.0) * (1.0 - smoothstep(0.6, 1.0, u))
		var val := int(sin(phase) * env * 0.22 * 32767.0)
		data[i * 2] = val & 0xFF
		data[i * 2 + 1] = (val >> 8) & 0xFF
	stream.data = data
	return stream
