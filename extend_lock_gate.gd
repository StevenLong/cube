extends StaticBody3D

# Extend-lock gate: a fence of thin posts (one per node cell) and panels between
# consecutive nodes, `height` units tall. Open (green, passable) while the player
# is extend-locked, closed (red, blocking) otherwise: you can only pass once you
# have committed to the required shape, and it shuts behind you when the lock
# releases. Nodes are authored like patrol nodes; diagonal runs are fine, the
# panel is just rotated. Named "Gate" (not "Wall*") so it stays out of the enemy
# nav grid and the fog-of-war wall array.

const COLOR_CLOSED := Color(0.9, 0.2, 0.2, 0.5)
const COLOR_OPEN := Color(0.25, 0.9, 0.35, 0.3)
const POST_SIZE := 0.4
const PANEL_THICKNESS := 0.2

@export var nodes: Array[Vector2i] = []   # absolute cells; first = this node's cell
@export var height: int = 3

var _player: Player
var _material: StandardMaterial3D
var _open := false
var _covered: Array[Vector2i] = []          # cells any piece touches (hold-open check)
var _shapes: Array[CollisionShape3D] = []


func _ready() -> void:
	_player = get_node("../Player") as Player
	_material = StandardMaterial3D.new()
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if nodes.is_empty():
		nodes = [Vector2i(roundi(global_position.x), roundi(global_position.z))]
	_build()
	_apply(false)


func _build() -> void:
	var origin: Vector2i = nodes[0]
	var covered: Dictionary = {}
	var h := float(height)
	for i in nodes.size():
		var rel := Vector2(float(nodes[i].x - origin.x), float(nodes[i].y - origin.y))
		_add_piece(Vector3(POST_SIZE, h, POST_SIZE), Vector3(rel.x, h * 0.5, rel.y), 0.0)
		covered[nodes[i]] = true
		if i < nodes.size() - 1:
			var nrel := Vector2(float(nodes[i + 1].x - origin.x), float(nodes[i + 1].y - origin.y))
			var seg_len := rel.distance_to(nrel)
			var mid := (rel + nrel) * 0.5
			_add_piece(Vector3(PANEL_THICKNESS, h, seg_len), Vector3(mid.x, h * 0.5, mid.y), atan2(nrel.x - rel.x, nrel.y - rel.y))
			# Cells the panel passes through, sampled at half-cell steps, so the
			# hold-open check covers the whole fence, not just the node cells.
			var steps := maxi(1, ceili(seg_len * 2.0))
			for s in range(steps + 1):
				var p := rel.lerp(nrel, float(s) / float(steps))
				covered[Vector2i(roundi(p.x) + origin.x, roundi(p.y) + origin.y)] = true
	for c in covered:
		_covered.append(c)


func _add_piece(piece_size: Vector3, pos: Vector3, rot_y: float) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = piece_size
	mesh.mesh = box
	mesh.material_override = _material   # shared: one color write flips the whole fence
	mesh.position = pos
	mesh.rotation.y = rot_y
	add_child(mesh)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = piece_size
	col.shape = shape
	col.position = pos
	col.rotation.y = rot_y
	add_child(col)
	_shapes.append(col)


func _process(_delta: float) -> void:
	var want_open: bool = _player.is_extend_locked()
	# Never shut on the player: the unlock zone can release the lock while the cube
	# still overlaps the fence line. Hold open while the footprint covers any
	# covered cell and only shut once it has moved clear.
	if not want_open and _covers_player():
		want_open = true
	if want_open != _open:
		_apply(want_open)


func _covers_player() -> bool:
	for cell in _covered:
		if _player.footprint_covers(cell):
			return true
	return false


func _apply(open: bool) -> void:
	_open = open
	for col in _shapes:
		col.disabled = open
	_material.albedo_color = COLOR_OPEN if open else COLOR_CLOSED
