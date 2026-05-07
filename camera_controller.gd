extends Camera3D

const ORBIT_SPEED := 2.5  # radians per second at full stick
const DISTANCE := 8.0
const HEIGHT := 8.0

var _orbit_angle := 0.0
var _target: Node3D


func _ready() -> void:
	_target = get_node("../Player")


func _process(delta: float) -> void:
	var input := Input.get_axis("camera_orbit_ccw", "camera_orbit_cw")
	_orbit_angle += input * ORBIT_SPEED * delta

	position = _target.position + Vector3(
		sin(_orbit_angle) * DISTANCE,
		HEIGHT,
		cos(_orbit_angle) * DISTANCE
	)
	look_at(_target.position, Vector3.UP)
