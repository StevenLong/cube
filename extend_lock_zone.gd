extends Area3D

# Extend-lock zone (grid-exact).
#
# The check is integer-cell based, never physics overlap, so it cannot be satisfied
# one tile off, in the wrong orientation, or mid-tumble. It is satisfied whether the
# player formed the shape in place or arrived already in it, as long as size,
# orientation, and location all line up exactly.
#
# The zone's cell (its rounded x/z) is the footprint's MIN corner (smallest x,
# smallest z). The footprint then extends +x by width and +z by depth.
#
# LOCK: arms the lock when the player's footprint min == this cell AND the player's
#   dimensions == required_dims, while the player is at rest.
# UNLOCK: releases the lock when the locked cuboid covers this cell.

enum Mode { LOCK, UNLOCK }

const COLOR_LOCK := Color(0.85, 0.5, 0.15, 0.55)
const COLOR_UNLOCK := Color(0.2, 0.8, 0.3, 0.55)

@export var mode: Mode = Mode.LOCK
## width (x), height (y), depth (z), in cells. LOCK mode only.
@export var required_dims: Vector3i = Vector3i(1, 1, 3)

var _player: Node3D


func _ready() -> void:
	monitoring = false  # location is grid-checked, not via area overlap
	_player = get_node("../Player")
	_build_marker()


func _build_marker() -> void:
	# Translucent footprint over the exact required tiles. LOCK shows the w x d
	# footprint to fill (this cell is its min corner); UNLOCK shows the single tile
	# to reach. Generated from required_dims so it always matches the check.
	var w: int = required_dims.x if mode == Mode.LOCK else 1
	var d: int = required_dims.z if mode == Mode.LOCK else 1
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(float(w) - 0.1, float(d) - 0.1)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = COLOR_LOCK if mode == Mode.LOCK else COLOR_UNLOCK
	var marker := MeshInstance3D.new()
	marker.mesh = mesh
	marker.material_override = mat
	marker.position = Vector3((w - 1) * 0.5, 0.02 - global_position.y, (d - 1) * 0.5)
	add_child(marker)


func _cell() -> Vector2i:
	return Vector2i(roundi(global_position.x), roundi(global_position.z))


func _process(_delta: float) -> void:
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
