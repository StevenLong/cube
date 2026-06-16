extends StaticBody3D

# Extend-lock gate: the doorway cells are FLOOR TILES that rise into a soft-red
# blocking wall while the gate is shut, and sink flush into the floor (walkable)
# while it is open. Open (passable) while the player is extend-locked, shut
# otherwise: you can only pass once you have committed to the required shape, and
# it rises behind you when the lock releases. This replaces the old bright ghost
# fence with world-geometry that reads as "the floor here is blocking you."
#
# One StaticBody3D owns one box per covered cell; they all rise/lower together.
# Named "Gate" (not "Wall*") so it stays out of the enemy nav grid and the
# fog-of-war wall array; its colliders still block the cube and enemy sight while
# raised. Authored as node(s) like a patrol path; the cells between nodes fill in.

const RAISE_TIME := 0.25            # seconds for the rise/sink animation
const RAISED_TOP := 1.0             # tile top y when shut (a 1u wall above the floor)
const LOWERED_TOP := -0.1           # tile top y when open (tucked just under the floor surface)
const BOX_H := 1.9                  # spans floor depth: raised covers 0..1, lowered tucks to floor bottom (no protrusion below the level)
const WALL_MATERIAL := preload("res://wall_material.tres")
const RED_LINE := Color(1.0, 0.25, 0.25)   # red grid lines = "this floor is blocking you"
const RED_TOP := Color(0.18, 0.05, 0.06)
const RED_SIDE := Color(0.12, 0.03, 0.04)

@export var nodes: Array[Vector2i] = []   # absolute cells; first = this node's cell
@export var height: int = 3               # kept for format compat; tiles raise to RAISED_TOP

var _player: Player
var _material: ShaderMaterial
var _open := false
var _raise_t := 1.0                       # 1 = fully raised (shut), 0 = fully lowered (open)
var _covered: Array[Vector2i] = []        # cells the gate occupies (hold-open + tiles)
var _meshes: Array[MeshInstance3D] = []
var _shapes: Array[CollisionShape3D] = []


func _ready() -> void:
	_player = get_node("../Player") as Player
	if nodes.is_empty():
		nodes = [Vector2i(roundi(global_position.x), roundi(global_position.z))]
	# Same grid look as floor/walls (so it reads as world geometry, not a flat
	# black box) but with red lines, marking the cells as blocking.
	_material = WALL_MATERIAL.duplicate()
	_material.set_shader_parameter("grid_line_color", RED_LINE)
	_material.set_shader_parameter("top_color", RED_TOP)
	_material.set_shader_parameter("side_color", RED_SIDE)
	_compute_covered()
	var origin: Vector2i = nodes[0]
	for cell in _covered:
		_add_tile(Vector3(float(cell.x - origin.x), 0.0, float(cell.y - origin.y)))
	_raise_t = 1.0
	_apply_visual()


func _compute_covered() -> void:
	# Node cells plus the cells each segment between consecutive nodes passes
	# through (half-cell sampling), so a multi-node gate fills its whole span.
	var cov: Dictionary = {}
	for i in nodes.size():
		cov[nodes[i]] = true
		if i < nodes.size() - 1:
			var a := Vector2(float(nodes[i].x), float(nodes[i].y))
			var b := Vector2(float(nodes[i + 1].x), float(nodes[i + 1].y))
			var steps := maxi(1, ceili(a.distance_to(b) * 2.0))
			for s in range(steps + 1):
				var p := a.lerp(b, float(s) / float(steps))
				cov[Vector2i(roundi(p.x), roundi(p.y))] = true
	for c in cov:
		_covered.append(c)


func _add_tile(local_pos: Vector3) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.0, BOX_H, 1.0)
	mesh.mesh = box
	mesh.material_override = _material   # shared: one glow/visibility write drives every tile
	mesh.position = Vector3(local_pos.x, 0.0, local_pos.z)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)
	_meshes.append(mesh)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.0, BOX_H, 1.0)
	col.shape = shape
	col.position = Vector3(local_pos.x, 0.0, local_pos.z)
	add_child(col)
	_shapes.append(col)


func _process(delta: float) -> void:
	var want_open: bool = _player.is_extend_locked()
	# Never rise on the player: the unlock zone can release the lock while the cube
	# still overlaps the doorway. Hold open while the footprint covers any gate cell
	# and only rise once it has moved clear.
	if not want_open and _covers_player():
		want_open = true
	_open = want_open
	var target := 0.0 if _open else 1.0
	if _raise_t != target:
		_raise_t = move_toward(_raise_t, target, delta / RAISE_TIME)
		_apply_visual()


func _covers_player() -> bool:
	for cell in _covered:
		if _player.footprint_covers(cell):
			return true
	return false


func _apply_visual() -> void:
	# Lerp the tile boxes between lowered (tucked under the floor, hidden) and
	# raised (a 1u red grid wall). No glow fade needed: a lowered tile is occluded
	# by the floor tile above it.
	var top := lerpf(LOWERED_TOP, RAISED_TOP, _raise_t)
	var center_y := top - BOX_H * 0.5
	var lowered := _raise_t <= 0.01   # fully sunk: hide so it doesn't z-fight inside the deep floor column
	for m in _meshes:
		m.position.y = center_y
		m.visible = not lowered
	for c in _shapes:
		c.position.y = center_y
		c.disabled = _raise_t < 0.5   # passable once mostly lowered
