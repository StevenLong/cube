extends Node3D

const TUMBLE_DURATION := 0.2

var grid_pos := Vector2i(0, 0)
var _tumbling := false
var _t := 0.0
var _pivot := Vector3.ZERO
var _axis := Vector3.ZERO
var _angle := 0.0
var _start_pos := Vector3.ZERO
var _start_basis := Basis.IDENTITY


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


func _process(delta: float) -> void:
	if _tumbling:
		_t = minf(_t + delta / TUMBLE_DURATION, 1.0)
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
		return

	var move := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if move.length() > 0.5:
		if absf(move.x) >= absf(move.y):
			_begin_tumble(Vector2i(1 if move.x > 0.0 else -1, 0))
		else:
			_begin_tumble(Vector2i(0, 1 if move.y > 0.0 else -1))
