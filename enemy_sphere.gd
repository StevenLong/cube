extends Node3D

const COLOR_PATROL := Color(0.7, 0.7, 0.75)
const COLOR_SUSPICIOUS := Color(1.0, 0.85, 0.0)
const COLOR_PURSUIT := Color(1.0, 0.2, 0.2)

const ARRIVE_THRESHOLD := 0.05
const CONFIRM_DURATION := 0.5
const SUSPICIOUS_TIMEOUT := 2.0
const PURSUIT_LOSE_TIMEOUT := 1.5
const PURSUIT_SPEED_MULT := 1.5
const SUSPICIOUS_SPEED_MULT := 0.5

enum State { PATROL, SUSPICIOUS, PURSUIT }

@export var waypoints: Array[Vector3] = [
	Vector3(5, 0.4, 0),
	Vector3(-5, 0.4, 0),
]
@export var speed: float = 2.0

var _target_idx := 0
var _state: State = State.PATROL
var _state_timer := 0.0
var _confirm_timer := 0.0
var _last_seen_pos := Vector3.ZERO
var _material: StandardMaterial3D
var _player: Node3D
var _player_area: Area3D

@onready var _ray: RayCast3D = $RayCast3D
@onready var _mesh: MeshInstance3D = $MeshInstance3D


func _ready() -> void:
	_material = (_mesh.get_surface_override_material(0) as StandardMaterial3D).duplicate()
	_mesh.set_surface_override_material(0, _material)
	_player = get_node("../Player")
	_player_area = get_node("../Player/DetectionArea")


func _process(delta: float) -> void:
	var seeing := _ray.is_colliding() and _ray.get_collider() == _player_area
	if seeing:
		_last_seen_pos = _player.position

	match _state:
		State.PATROL:
			_patrol(delta)
			if seeing:
				_enter_state(State.SUSPICIOUS)
		State.SUSPICIOUS:
			_state_timer += delta
			if seeing:
				_confirm_timer += delta
				if _confirm_timer >= CONFIRM_DURATION:
					_enter_state(State.PURSUIT)
			else:
				_confirm_timer = 0.0
			if _state == State.SUSPICIOUS and _state_timer >= SUSPICIOUS_TIMEOUT:
				_enter_state(State.PATROL)
			_creep(delta)
		State.PURSUIT:
			_pursue(delta)
			if seeing:
				_state_timer = 0.0
			else:
				_state_timer += delta
				if _state_timer >= PURSUIT_LOSE_TIMEOUT:
					_enter_state(State.SUSPICIOUS)

	_material.albedo_color = _state_color()


func _patrol(delta: float) -> void:
	if waypoints.size() < 2:
		return
	var target: Vector3 = waypoints[_target_idx]
	var to_target := target - position
	var distance := to_target.length()
	if distance < ARRIVE_THRESHOLD:
		_target_idx = (_target_idx + 1) % waypoints.size()
	else:
		var step := minf(speed * delta, distance)
		position += to_target / distance * step
		look_at(target, Vector3.UP)


func _creep(delta: float) -> void:
	var to_target := _last_seen_pos - position
	var distance := to_target.length()
	if distance > ARRIVE_THRESHOLD:
		var step := minf(speed * SUSPICIOUS_SPEED_MULT * delta, distance)
		position += to_target / distance * step
		look_at(_last_seen_pos, Vector3.UP)


func _pursue(delta: float) -> void:
	var to_player := _player.position - position
	var distance := to_player.length()
	if distance > ARRIVE_THRESHOLD:
		var step := minf(speed * PURSUIT_SPEED_MULT * delta, distance)
		position += to_player / distance * step
		look_at(_player.position, Vector3.UP)


func _enter_state(new_state: State) -> void:
	_state = new_state
	_state_timer = 0.0
	_confirm_timer = 0.0
	if new_state == State.PATROL:
		_target_idx = _closest_waypoint_idx()


func _closest_waypoint_idx() -> int:
	var best_idx := 0
	var best_dist := INF
	for i in waypoints.size():
		var d: float = (waypoints[i] - position).length_squared()
		if d < best_dist:
			best_dist = d
			best_idx = i
	return best_idx


func _state_color() -> Color:
	match _state:
		State.SUSPICIOUS: return COLOR_SUSPICIOUS
		State.PURSUIT: return COLOR_PURSUIT
		_: return COLOR_PATROL
