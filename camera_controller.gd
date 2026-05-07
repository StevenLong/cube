extends Camera3D

const DISTANCE := 12.0
const H_ANGLE := 0.0        # square-on to grid
const ELEV_MIN := 0.2        # ~11 degrees - almost side-on
const ELEV_MAX := 1.3        # ~74 degrees - almost top-down
const TILT_SPEED := 1.2

var _elevation := 0.6155     # ~35 degrees - true isometric default
var _target: Node3D


func _ready() -> void:
	_target = get_node("../Player")


func _process(delta: float) -> void:
	var tilt := Input.get_axis("camera_tilt_down", "camera_tilt_up")
	_elevation = clampf(_elevation + tilt * TILT_SPEED * delta, ELEV_MIN, ELEV_MAX)

	var h := DISTANCE * cos(_elevation)
	var v := DISTANCE * sin(_elevation)
	position = _target.position + Vector3(h * sin(H_ANGLE), v, h * cos(H_ANGLE))
	look_at(_target.position, Vector3.UP)
