extends Node3D

# Builds a playable level from a text grid (see levels/data/*.txt). The whole world
# is assembled DETACHED from a reusable template, positioned, then attached in one
# add_child so every node's _ready fires with the full tree present (Player<->Level
# resolve their sibling refs, the sphere nav grid sees the walls, the floor tiles are
# in-group before level.gd scans). This mirrors loading a hand-authored scene.
#
# Grid legend: '.' floor   '#' tall wall (cover)   '=' low rail (safe edge, see over)
#              ' ' void (fall)   'S' start   'E' end
# Enemy lines: "@ col,row col,row ... [speed=N]"  (first cell = spawn; cells 0-based)

const TEMPLATE := preload("res://level_template.tscn")
const FLOOR_TILE := preload("res://FloorTile.tscn")
const ENEMY := preload("res://enemy_sphere.tscn")

const WALL_TALL := 1.0
const RAIL_LOW := 0.5

@export var level_file: String = "res://levels/data/level_01.txt"

var _wall_mat: StandardMaterial3D
var _rail_mat: StandardMaterial3D


func _ready() -> void:
	_wall_mat = StandardMaterial3D.new()
	_wall_mat.albedo_color = Color(0.4, 0.4, 0.5)
	_rail_mat = StandardMaterial3D.new()
	_rail_mat.albedo_color = Color(0.35, 0.4, 0.55)
	# Deferred: add_child into the freshly-entering scene root errors mid-_ready.
	_load.call_deferred()


func _load() -> void:
	if not FileAccess.file_exists(level_file):
		push_error("level_loader: level file not found: %s" % level_file)
		return
	var data := _parse(FileAccess.get_file_as_string(level_file))
	var world: Node3D = TEMPLATE.instantiate()
	_populate(world, data)
	add_child(world)


func _parse(text: String) -> Dictionary:
	var floor_cells: Dictionary = {}    # Vector2i -> true
	var tall: Array[Vector2i] = []
	var rails: Array[Vector2i] = []
	var start := Vector2i.ZERO
	var end := Vector2i.ZERO
	var enemies: Array = []
	var row := 0
	for raw in text.split("\n"):
		var line := raw.rstrip("\r")     # tolerate CRLF from Windows editors
		if line.begins_with(";"):
			continue
		if line.begins_with("@"):
			enemies.append(_parse_enemy(line))
			continue
		if line.strip_edges().is_empty():
			continue
		for col in line.length():
			var cell := Vector2i(col, row)
			match line[col]:
				".":
					floor_cells[cell] = true
				"S":
					floor_cells[cell] = true
					start = cell
				"E":
					floor_cells[cell] = true
					end = cell
				"#":
					tall.append(cell)
				"=":
					rails.append(cell)
				_:
					pass             # space / unknown = void
		row += 1
	return {"floor": floor_cells, "tall": tall, "rails": rails, "start": start, "end": end, "enemies": enemies}


func _parse_enemy(line: String) -> Dictionary:
	var waypoints: Array[Vector3] = []
	var spawn := Vector2i.ZERO
	var speed := 1.8
	var first := true
	for tok in line.substr(1).split(" ", false):
		if tok.begins_with("speed="):
			speed = float(tok.substr(6))
			continue
		var parts := tok.split(",")
		if parts.size() != 2:
			continue
		var cell := Vector2i(int(parts[0]), int(parts[1]))
		if first:
			spawn = cell
			first = false
		waypoints.append(Vector3(cell.x, 0.4, cell.y))
	return {"spawn": spawn, "waypoints": waypoints, "speed": speed}


func _populate(world: Node3D, data: Dictionary) -> void:
	# Position the singletons BEFORE the subtree enters the tree, so Player syncs
	# grid_pos and Level reads _end_cell from the right cells at _ready.
	var start: Vector2i = data["start"]
	var end: Vector2i = data["end"]
	(world.get_node("Player") as Node3D).position = Vector3(start.x, 0.5, start.y)
	(world.get_node("StartTile") as Node3D).position = Vector3(start.x, 0.01, start.y)
	(world.get_node("EndTile") as Node3D).position = Vector3(end.x, 0.01, end.y)

	for cell in data["floor"]:
		var tile: Node3D = FLOOR_TILE.instantiate()
		tile.position = Vector3(cell.x, -1.0, cell.y)
		world.add_child(tile)

	var idx := 0
	for cell in data["tall"]:
		world.add_child(_make_wall(cell, WALL_TALL, idx, _wall_mat))
		idx += 1
	for cell in data["rails"]:
		world.add_child(_make_wall(cell, RAIL_LOW, idx, _rail_mat))
		idx += 1

	var e := 0
	for spec in data["enemies"]:
		var enemy: Node3D = ENEMY.instantiate()
		enemy.name = "Enemy%d" % e
		enemy.cone_index = e
		var spawn: Vector2i = spec["spawn"]
		enemy.position = Vector3(spawn.x, 0.4, spawn.y)
		var wps: Array[Vector3] = []
		wps.assign(spec["waypoints"])
		enemy.waypoints = wps
		enemy.speed = spec["speed"]
		world.add_child(enemy)
		e += 1


func _make_wall(cell: Vector2i, height: float, idx: int, mat: StandardMaterial3D) -> StaticBody3D:
	# Named Wall* and box-shaped so enemy_sphere._build_nav_grid blocks the cell.
	var body := StaticBody3D.new()
	body.name = "Wall%d" % idx
	body.position = Vector3(cell.x, height * 0.5, cell.y)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1, height, 1)
	mesh.mesh = box
	body.add_child(mesh)
	mesh.set_surface_override_material(0, mat)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1, height, 1)
	col.shape = shape
	body.add_child(col)
	return body
