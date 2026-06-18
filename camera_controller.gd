extends Camera3D

const DISTANCE := 12.0
const H_ANGLE := 0.0        # square-on to grid
const ELEV_MIN := 0.2        # ~11 degrees - almost side-on
const ELEV_MAX := 1.3        # ~74 degrees - almost top-down
const ELEV_DEFAULT := 0.7854 # 45 degrees down - the angle playtesting kept landing on
const TILT_SPEED := 1.2

# The chosen angle persists across restarts and levels for the whole app session,
# so a player who found their angle never re-adjusts after a reset.
static var saved_elevation := ELEV_DEFAULT

var _elevation := ELEV_DEFAULT
var _target: Node3D


func _ready() -> void:
	_target = get_node("../Player")
	_elevation = saved_elevation
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	# Don't let the camera tilt keys (R/F) bleed through the UI: while a menu or text
	# field holds keyboard focus, R/F belong to it (typing a level name, moving through
	# a menu), not the camera. A focused-but-hidden control (a just-closed panel) does
	# not count, so camera control resumes the instant the UI goes away. (N13)
	var focus_owner := get_viewport().gui_get_focus_owner()
	var ui_active := focus_owner != null and focus_owner.is_visible_in_tree()
	if not ui_active:
		var tilt := Input.get_axis("camera_tilt_down", "camera_tilt_up")
		_elevation = clampf(_elevation + tilt * TILT_SPEED * delta, ELEV_MIN, ELEV_MAX)
		saved_elevation = _elevation

	var h := DISTANCE * cos(_elevation)
	var v := DISTANCE * sin(_elevation)
	var focus: Vector3 = _target.get_camera_focus()
	position = focus + Vector3(h * sin(H_ANGLE), v, h * cos(H_ANGLE))
	look_at(focus, Vector3.UP)
