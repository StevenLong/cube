extends Node3D

const TUMBLE_DURATION := 0.3
const SPRINT_DURATION := 0.15
const DODGE_DISTANCE := 5
const DODGE_DURATION := 0.4
const DODGE_COOLDOWN := 1.5
const WAVE_DURATION := 0.4
const MAX_WAVES := 8

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
var _ground_material: ShaderMaterial
var _waves: Array = []

@onready var _step_player: AudioStreamPlayer = $StepSound


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().quit()


func _ready() -> void:
	_step_player.stream = _make_step_sound()
	_ground_material = get_node("../Ground/MeshInstance3D").get_surface_override_material(0)


func _begin_tumble(dir: Vector2i) -> void:
	_start_pos = position
	_start_basis = basis
	if dir.x == 1:
		_pivot = Vector3(position.x + 0.5, 0.0, position.z)
		_axis = Vector3(0, 0, 1)
		_angle = -PI / 2.0
	elif dir.x == -1:
		_pivot = Vector3(position.x - 0.5, 0.0, position.z)
		_axis = Vector3(0, 0, 1)
		_angle = PI / 2.0
	elif dir.y == 1:
		_pivot = Vector3(position.x, 0.0, position.z + 0.5)
		_axis = Vector3(1, 0, 0)
		_angle = PI / 2.0
	elif dir.y == -1:
		_pivot = Vector3(position.x, 0.0, position.z - 0.5)
		_axis = Vector3(1, 0, 0)
		_angle = -PI / 2.0
	grid_pos += dir
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
	_step_player.volume_db = linear_to_db(noise_level)
	_step_player.play()
	var max_radius := 8.0 if noise_level > 1.0 else 4.0
	if _waves.size() >= MAX_WAVES:
		_waves.pop_front()
	_waves.append({"origin": Vector2(grid_pos.x, grid_pos.y), "t": 0.0, "max_radius": max_radius})


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
	var radii := PackedFloat32Array()
	var alphas := PackedFloat32Array()
	origins.resize(MAX_WAVES)
	radii.resize(MAX_WAVES)
	alphas.resize(MAX_WAVES)
	for i in _waves.size():
		origins[i] = _waves[i].origin
		radii[i] = _waves[i].max_radius * _waves[i].t
		alphas[i] = 1.0 - _waves[i].t
	_ground_material.set_shader_parameter("wave_origins", origins)
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
		return

	if _tumbling:
		var duration := SPRINT_DURATION if Input.is_action_pressed("sprint") else TUMBLE_DURATION
		_t = minf(_t + delta / duration, 1.0)
		var angle := _angle * _t
		position = _pivot + (_start_pos - _pivot).rotated(_axis, angle)
		basis = Basis(_axis, angle) * _start_basis
		if _t >= 1.0:
			_tumbling = false
			position = Vector3(grid_pos.x, 0.5, grid_pos.y)
			basis = Basis(
				basis.x.snapped(Vector3.ONE),
				basis.y.snapped(Vector3.ONE),
				basis.z.snapped(Vector3.ONE)
			)
			_play_step(TUMBLE_DURATION / duration)
		return

	var move := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dodge_primed := Input.is_action_pressed("dodge") and _dodge_cooldown_t <= 0.0

	if dodge_primed and move.length() > 0.5:
		_begin_dodge(_pick_dir(move))
	elif not dodge_primed and move.length() > 0.5:
		_begin_tumble(_pick_dir(move))


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
