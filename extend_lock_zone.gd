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
# UNLOCK: releases the lock by the SAME match (footprint min == this cell AND
#   dimensions == required_dims, at rest), shown while locked. Mirroring LOCK keeps
#   the release deliberate and placed: it can't fire while the cube is still over
#   the gate, which is what let a player trip it and then reverse back through.

enum Mode { LOCK, UNLOCK }

const COLOR_LOCK := Color(0.85, 0.5, 0.15, 0.55)
const COLOR_UNLOCK := Color(0.2, 0.8, 0.3, 0.55)
const GHOST_BLINK_RATE := 3.0    # rad/s of the ghost alpha pulse
const GHOST_ALPHA_MIN := 0.1
const GHOST_ALPHA_MAX := 0.4

@export var mode: Mode = Mode.LOCK
## width (x), height (y), depth (z), in cells. The exact cuboid required at this cell.
@export var required_dims: Vector3i = Vector3i(1, 1, 3)

var _player: Player
var _marker: MeshInstance3D
var _ghost: MeshInstance3D
var _ghost_mat: StandardMaterial3D
var _bp_color: Color
var _blink_t := 0.0


func _ready() -> void:
	monitoring = false  # location is grid-checked, not via area overlap
	_player = get_node("../Player") as Player
	_build_blueprint()


func _build_blueprint() -> void:
	# Footprint tiles on the ground plus a translucent ghost of the required cuboid,
	# generated from required_dims so they always match the check. Both modes show the
	# same telegraph (form it here / re-seat it here); only the colour differs.
	var w: int = required_dims.x
	var h: int = required_dims.y
	var d: int = required_dims.z
	_bp_color = COLOR_LOCK if mode == Mode.LOCK else COLOR_UNLOCK

	var plane := PlaneMesh.new()
	plane.size = Vector2(float(w) - 0.1, float(d) - 0.1)
	var pmat := StandardMaterial3D.new()
	pmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pmat.albedo_color = _bp_color
	_marker = MeshInstance3D.new()
	_marker.mesh = plane
	_marker.material_override = pmat
	_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_marker.position = Vector3((w - 1) * 0.5, 0.02 - global_position.y, (d - 1) * 0.5)
	add_child(_marker)

	var box := BoxMesh.new()
	box.size = Vector3(w, h, d)
	_ghost_mat = StandardMaterial3D.new()
	_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ghost_mat.albedo_color = Color(_bp_color.r, _bp_color.g, _bp_color.b, GHOST_ALPHA_MAX)
	_ghost = MeshInstance3D.new()
	_ghost.mesh = box
	_ghost.material_override = _ghost_mat
	_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost.position = Vector3((w - 1) * 0.5, h * 0.5 - global_position.y, (d - 1) * 0.5)
	add_child(_ghost)


func _cell() -> Vector2i:
	return Vector2i(roundi(global_position.x), roundi(global_position.z))


func _process(delta: float) -> void:
	_update_blueprint(delta)
	if _player.is_moving():
		return
	# Same exact match for both modes (shape and orientation seated at this exact
	# cell, at rest); they differ only in the lock state required and the one they
	# set. A precise UNLOCK, not a loose overlap, stays deliberate: it cannot fire
	# while the cube is still straddling the gate, so you can't trip it and reverse.
	var seated: bool = (_player.get_dimensions() == required_dims
		and _player.get_footprint_min() == _cell())
	if mode == Mode.LOCK:
		if seated and not _player.is_extend_locked():
			_player.set_extend_locked(true)
	elif seated and _player.is_extend_locked():
		_player.set_extend_locked(false)


func _update_blueprint(delta: float) -> void:
	# LOCK telegraphs where to FORM the shape (shown until armed). UNLOCK telegraphs
	# where to RE-SEAT it to release (shown while locked). Same pulse, mode colour.
	var show_bp: bool = (not _player.is_extend_locked()) if mode == Mode.LOCK else _player.is_extend_locked()
	_ghost.visible = show_bp
	_marker.visible = show_bp
	if show_bp:
		_blink_t += delta * GHOST_BLINK_RATE
		var a := lerpf(GHOST_ALPHA_MIN, GHOST_ALPHA_MAX, 0.5 + 0.5 * sin(_blink_t))
		_ghost_mat.albedo_color = Color(_bp_color.r, _bp_color.g, _bp_color.b, a)
