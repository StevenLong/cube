extends Node3D

const COLOR_IDLE := Color(0.7, 0.7, 0.75)
const COLOR_DETECT := Color(1.0, 0.2, 0.2)
const ARRIVE_THRESHOLD := 0.05

@export var waypoints: Array[Vector3] = [
	Vector3(5, 0.4, 0),
	Vector3(-5, 0.4, 0),
]
@export var speed: float = 2.0

var _target_idx := 0
var _material: StandardMaterial3D

@onready var _ray: RayCast3D = $RayCast3D
@onready var _mesh: MeshInstance3D = $MeshInstance3D


func _ready() -> void:
	_material = (_mesh.get_surface_override_material(0) as StandardMaterial3D).duplicate()
	_mesh.set_surface_override_material(0, _material)


func _process(delta: float) -> void:
	if waypoints.size() >= 2:
		var target: Vector3 = waypoints[_target_idx]
		var to_target := target - position
		var distance := to_target.length()
		if distance < ARRIVE_THRESHOLD:
			_target_idx = (_target_idx + 1) % waypoints.size()
		else:
			var step := minf(speed * delta, distance)
			position += to_target / distance * step
			look_at(target, Vector3.UP)

	_material.albedo_color = COLOR_DETECT if _ray.is_colliding() else COLOR_IDLE
