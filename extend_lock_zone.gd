extends Area3D

# Extend-lock zone (grid-exact) with a ghost-blueprint telegraph.
#
# The check is integer-cell based, never physics overlap, so it cannot be satisfied
# one tile off, in the wrong orientation, or mid-tumble. It is satisfied whether the
# player formed the shape in place or arrived already in it, as long as size,
# orientation, and location all line up exactly.
#
# The zone's cell (its rounded x/z) is the footprint's MIN corner (smallest x,
# smallest z). The footprint then extends +x by width and +z by depth.
#
# LOCK: arms the lock when the player's footprint min == this cell AND dimensions
#   == required_dims, at rest. Shows a blinking translucent ghost of the required
#   cuboid plus its footprint tiles, hidden once the lock is armed.
# UNLOCK: releases the lock when the locked cuboid covers this cell.

enum Mode { LOCK, UNLOCK }

const COLOR_LOCK := Color(0.85, 0.5, 0.15, 0.55)
const COLOR_UNLOCK := Color(0.2, 0.8, 0.3, 0.55)
const GHOST_BLINK_RATE := 3.0    # rad/s of the ghost alpha pulse
const GHOST_ALPHA_MIN := 0.1
const GHOST_ALPHA_MAX := 0.4

@export var mode: Mode = Mode.LOCK
## width (x), height (y), depth (z), in cells. LOCK mode only.
@export var required_dims: Vector3i = Vector3i(1, 1, 3)

var _player: Player
var _marker: MeshInstance3D
var _ghost: MeshInstance3D
var _ghost_mat: StandardMaterial3D
var _blink_t := 0.0


func _ready() -> void:
	monitoring = false  # location is grid-checked, not via area overlap
	_player = get_node("../Player") as Player
	_build_blueprint()


func _build_blueprint() -> void:
	# Footprint tiles on the ground (both modes), and for LOCK a translucent ghost
	# of the required cuboid where it must be formed. Generated from required_dims so
	# they always match the check.
	var w: int = required_dims.x if mode == Mode.LOCK else 1
	var d: int = required_dims.z if mode == Mode.LOCK else 1
	var col := COLOR_LOCK if mode == Mode.LOCK else COLOR_UNLOCK

	var plane := PlaneMesh.new()
	plane.size = Vector2(float(w) - 0.1, float(d) - 0.1)
	var pmat := StandardMaterial3D.new()
	pmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pmat.albedo_color = col
	_marker = MeshInstance3D.new()
	_marker.mesh = plane
	_marker.material_override = pmat
	_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_marker.position = Vector3((w - 1) * 0.5, 0.02 - global_position.y, (d - 1) * 0.5)
	add_child(_marker)

	if mode != Mode.LOCK:
		return

	var h: int = required_dims.y
	var box := BoxMesh.new()
	box.size = Vector3(w, h, d)
	_ghost_mat = StandardMaterial3D.new()
	_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ghost_mat.albedo_color = Color(col.r, col.g, col.b, GHOST_ALPHA_MAX)
	_ghost = MeshInstance3D.new()
	_ghost.mesh = box
	_ghost.material_override = _ghost_mat
	_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost.position = Vector3((w - 1) * 0.5, h * 0.5 - global_position.y, (d - 1) * 0.5)
	add_child(_ghost)


func _cell() -> Vector2i:
	return Vector2i(roundi(global_position.x), roundi(global_position.z))


func _process(delta: float) -> void:
	if mode == Mode.LOCK:
		_update_blueprint(delta)
	if _player.is_moving():
		return
	if mode == Mode.LOCK:
		var matched: bool = (not _player.is_extend_locked()
			and _player.get_dimensions() == required_dims
			and _player.get_footprint_min() == _cell())
		if matched:
			_player.set_extend_locked(true)
	elif _player.is_extend_locked() and _player.footprint_covers(_cell()):
		_player.set_extend_locked(false)


func _update_blueprint(delta: float) -> void:
	# Show the ghost + tiles until the lock is armed (you have filled the shape),
	# pulsing the ghost's alpha so it reads as a blueprint to match.
	var show_bp: bool = not _player.is_extend_locked()
	_ghost.visible = show_bp
	_marker.visible = show_bp
	if show_bp:
		_blink_t += delta * GHOST_BLINK_RATE
		var a := lerpf(GHOST_ALPHA_MIN, GHOST_ALPHA_MAX, 0.5 + 0.5 * sin(_blink_t))
		_ghost_mat.albedo_color = Color(COLOR_LOCK.r, COLOR_LOCK.g, COLOR_LOCK.b, a)
