extends Node3D

const TUMBLE_DURATION := 0.3
const SPRINT_DURATION := 0.15
const DODGE_DISTANCE := 5
const DODGE_DURATION := 0.4
const DODGE_COOLDOWN := 1.5
const WAVE_DURATION := 0.4
const MAX_WAVES := 8
const FOCUS_SMOOTH_RATE := 25.0
const COLOR_NORMAL := Color(0.9, 0.9, 0.9)
const COLOR_BLENDING := Color(0.4, 0.4, 0.45)

const EXT_LEFT  := 0
const EXT_RIGHT := 1
const EXT_FWD   := 2
const EXT_BACK  := 3
const EXT_UP    := 4

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
var _ext := [0, 0, 0, 0, 0]
var _pending_ext := [0, 0, 0, 0, 0]
var _tumble_distance := 1
var _smoothed_focus := Vector3.ZERO
var _rb_extended_this_press := false
var is_blending := false
var _ground_material: ShaderMaterial
var _player_material: StandardMaterial3D
var _waves: Array = []
var _box_mesh: BoxMesh

@onready var _step_player: AudioStreamPlayer = $StepSound
@onready var _mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var _wall_rays: Array[RayCast3D] = [
	$WallRayN, $WallRayS, $WallRayE, $WallRayW
]


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().quit()

	if event.is_action_pressed("extend"):
		_rb_extended_this_press = false

	if event.is_action_released("extend"):
		if not _rb_extended_this_press:
			_reset_extensions()


func _ready() -> void:
	_step_player.stream = _make_step_sound()
	_ground_material = get_node("../Ground/MeshInstance3D").get_surface_override_material(0)
	_box_mesh = _mesh_instance.mesh.duplicate() as BoxMesh
	_mesh_instance.mesh = _box_mesh
	_player_material = (_mesh_instance.get_surface_override_material(0) as StandardMaterial3D).duplicate()
	_mesh_instance.set_surface_override_material(0, _player_material)
	_smoothed_focus = _mesh_instance.global_position


func _count_covered_sides() -> int:
	var count := 0
	for r in _wall_rays:
		if r.is_colliding():
			count += 1
	return count


func _axis_total(side: int) -> int:
	match side:
		EXT_LEFT, EXT_RIGHT: return _ext[EXT_LEFT] + _ext[EXT_RIGHT]
		EXT_FWD, EXT_BACK:   return _ext[EXT_FWD] + _ext[EXT_BACK]
		_:                   return _ext[EXT_UP]


func _try_extend(side: int) -> void:
	if _axis_total(side) < 2:
		_ext[side] += 1


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


func _update_mesh() -> void:
	# Mesh always lives in the parent's local frame with identity basis.
	# At rest, parent.basis == IDENTITY so the mesh is world-aligned.
	# During a tumble, parent.basis rotates so the mesh visibly tumbles with it.
	_box_mesh.size = Vector3(
		1.0 + _ext[EXT_LEFT] + _ext[EXT_RIGHT],
		1.0 + _ext[EXT_UP],
		1.0 + _ext[EXT_FWD] + _ext[EXT_BACK]
	)
	_mesh_instance.transform = Transform3D(
		Basis.IDENTITY,
		Vector3(
			(_ext[EXT_RIGHT] - _ext[EXT_LEFT]) * 0.5,
			_ext[EXT_UP] * 0.5,
			(_ext[EXT_BACK] - _ext[EXT_FWD]) * 0.5
		)
	)


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

	_pivot = Vector3(pivot_x, 0.0, pivot_z)
	_pending_ext = new_ext
	_tumble_distance = move
	grid_pos += dir * move
	_t = 0.0
	_tumbling = true


func _begin_dodge(dir: Vector2i) -> void:
	_dodge_start_pos = position
	_dodge_end_pos = Vector3(
		grid_pos.x + dir.x * DODGE_DISTANCE,
		0.5,
		grid_pos.y + dir.y * DODGE_DISTANCE
	)
	grid_pos += dir * DODGE_DISTANCE
	_dodge_t = 0.0
	_dodging = true


func _play_step(noise_level: float) -> void:
	var ext_sum: int = _ext[EXT_LEFT] + _ext[EXT_RIGHT] + _ext[EXT_UP] + _ext[EXT_FWD] + _ext[EXT_BACK]
	var size_factor := 1.0 + ext_sum * 0.15
	_step_player.volume_db = linear_to_db(noise_level * size_factor)
	_step_player.pitch_scale = 1.0 - ext_sum * 0.08
	_step_player.play()
	var max_radius: float = (8.0 if noise_level > 1.0 else 4.0) + ext_sum
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


func _process(delta: float) -> void:
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

	if _dodge_cooldown_t > 0.0:
		_dodge_cooldown_t = maxf(_dodge_cooldown_t - delta, 0.0)

	if _dodging:
		_dodge_t = minf(_dodge_t + delta / DODGE_DURATION, 1.0)
		var t_eased := 1.0 - pow(1.0 - _dodge_t, 3.0)
		position = _dodge_start_pos.lerp(_dodge_end_pos, t_eased)
		if _dodge_t >= 1.0:
			_dodging = false
			position = _dodge_end_pos
			_dodge_cooldown_t = DODGE_COOLDOWN
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
			_ext = _pending_ext
			_play_step(TUMBLE_DURATION / per_cell)
		_update_mesh()
		return

	if Input.is_action_pressed("extend"):
		if Input.is_action_just_pressed("move_left"):
			_rb_extended_this_press = true
			_try_extend(EXT_LEFT)
		elif Input.is_action_just_pressed("move_right"):
			_rb_extended_this_press = true
			_try_extend(EXT_RIGHT)
		elif Input.is_action_just_pressed("move_forward"):
			_rb_extended_this_press = true
			_try_extend(EXT_UP)
		if Input.is_action_just_pressed("extend_depth_fwd"):
			_rb_extended_this_press = true
			_try_extend(EXT_FWD)
		elif Input.is_action_just_pressed("extend_depth_back"):
			_rb_extended_this_press = true
			_try_extend(EXT_BACK)
		_update_mesh()
		return

	# Blend: while button held and 3+ sides covered, the player is undetectable
	# and movement is blocked (committing to the spot).
	is_blending = Input.is_action_pressed("blend") and _count_covered_sides() >= 3
	_player_material.albedo_color = COLOR_BLENDING if is_blending else COLOR_NORMAL

	if is_blending:
		_update_mesh()
		return

	var move := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dodge_primed := Input.is_action_pressed("dodge") and _dodge_cooldown_t <= 0.0 and not _is_extended()

	if dodge_primed and move.length() > 0.5:
		_begin_dodge(_pick_dir(move))
	elif not dodge_primed and move.length() > 0.5:
		_begin_tumble(_pick_dir(move))

	_update_mesh()


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
