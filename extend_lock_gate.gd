extends StaticBody3D

# Extend-lock gate. Open (green, passable) while the player is extend-locked,
# closed (red, blocking) otherwise: you can only pass once you have committed to
# the required shape, and it shuts behind you when the lock releases. Driven by
# the player's lock state. Named "Gate" (not "Wall*") so it stays out of the
# enemy nav grid and the fog-of-war wall array.

const COLOR_CLOSED := Color(0.9, 0.2, 0.2, 0.5)
const COLOR_OPEN := Color(0.25, 0.9, 0.35, 0.3)

@onready var _shape: CollisionShape3D = $CollisionShape3D
@onready var _mesh: MeshInstance3D = $MeshInstance3D

var _player: Node3D
var _material: StandardMaterial3D
var _open := false


func _ready() -> void:
	_player = get_node("../Player")
	_material = (_mesh.get_surface_override_material(0) as StandardMaterial3D).duplicate()
	_mesh.set_surface_override_material(0, _material)
	_apply(false)


func _process(_delta: float) -> void:
	var want_open: bool = _player.is_extend_locked()
	if want_open != _open:
		_apply(want_open)


func _apply(open: bool) -> void:
	_open = open
	_shape.disabled = open
	_material.albedo_color = COLOR_OPEN if open else COLOR_CLOSED
