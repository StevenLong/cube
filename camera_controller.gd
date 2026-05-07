extends Camera3D

const OFFSET := Vector3(0.0, 8.0, 8.0)

var _target: Node3D


func _ready() -> void:
	_target = get_node("../Player")


func _process(_delta: float) -> void:
	position = _target.position + OFFSET
	look_at(_target.position, Vector3.UP)
