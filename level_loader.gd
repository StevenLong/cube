extends Node3D
class_name LevelLoader

# Builds a playable level from a JSON file (see levels/data/*.json and
# SPEC_object_anatomy.md). The world is assembled DETACHED from a reusable
# template, positioned, then attached in one add_child so every node's _ready
# fires with the full tree present (Player<->Level resolve sibling refs, the
# sphere nav grid sees the walls, floor tiles are in-group before level.gd scans).
#
# Format (v1):
#   { "version": 1,
#     "meta":    { "name": ..., "size": [w, h] },
#     "base":    ["...grid rows..."],   # base tiles, one glyph per cell
#     "overlay": ["...grid rows..."],   # surface tiles (ink/water)
#     "objects": [ { "type": <id>, "cell": [x, z], ...params } ],
#     "links":   [ ... ],   # relationship edges  -- TODO build
#     "config":  { ... } }  # level rules         -- TODO build
#
# Tile glyphs, object types, their scenes and default params all live in
# ObjectRegistry (the single source of truth). safety_edge is an invisible blocker
# shown only as a red line on its floor-facing sides; it owns that render (level.gd
# no longer auto-draws strips). Objects dispatch on "type" to a builder; unknown
# types warn and skip so a level with a not-yet-supported object still loads.

# load()ed lazily rather than preload()ed to avoid a cyclic dependency: the template
# embeds level.gd, which now references LevelLoader (for the playtest return flag).
const TEMPLATE_PATH := "res://level_template.tscn"

const WALL_TALL := 1.0
const FLOOR_DEPTH := 2.0  # floor tiles are 2u-deep boxes with tops at y=0; walls share that bottom
const WALL_MATERIAL := preload("res://wall_material.tres")  # static grid look: thin top lines, floor-style sides, no dynamic overlays
const SAFE_EDGE_HEIGHT := 0.4   # low invisible blocker; the red line is its only visual
const SAFE_EDGE_Y := 0.02       # red line height above floor top
const SAFE_EDGE_PERP := 0.04    # thickness across the edge
const SAFE_EDGE_VERT := 0.02    # vertical thickness (reads as paint, not a bar)
const SAFE_EDGE_ENERGY := 0.6
const DIRS_4: Array[Vector2i] = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]

@export var level_file: String = "res://levels/data/level_01.json"
static var requested_file: String = ""   # the active level's file. A launcher sets it; the loader keeps it (does NOT clear) so reload_current_scene (restart) replays the same file. Every painted_level launcher must set it, or a stale value leaks in.
static var return_to_editor: bool = false   # set by the editor's playtest; level.gd then returns to the editor on exit instead of the main menu

var _edge_mat: StandardMaterial3D
var _wall_idx := 0          # running Wall* counter; nav keys off unique Wall names


func _ready() -> void:
	_edge_mat = StandardMaterial3D.new()
	_edge_mat.albedo_color = Color(0.9, 0.15, 0.15)
	_edge_mat.emission_enabled = true
	_edge_mat.emission = Color(0.9, 0.15, 0.15)
	_edge_mat.emission_energy_multiplier = SAFE_EDGE_ENERGY
	_edge_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Deferred: add_child into the freshly-entering scene root errors mid-_ready.
	_load.call_deferred()


func _load() -> void:
	if requested_file != "":
		level_file = requested_file
	if not FileAccess.file_exists(level_file):
		push_error("level_loader: level file not found: %s" % level_file)
		return
	var data: Dictionary = _parse(FileAccess.get_file_as_string(level_file))
	if data.is_empty():
		return
	var world: Node3D = (load(TEMPLATE_PATH) as PackedScene).instantiate()
	_populate(world, data)
	add_child(world)


func _parse(text: String) -> Dictionary:
	var json: Variant = JSON.parse_string(text)
	if typeof(json) != TYPE_DICTIONARY:
		push_error("level_loader: %s is not a JSON object" % level_file)
		return {}
	var doc: Dictionary = json
	var version := int(doc.get("version", 0))
	if version != 1:
		push_error("level_loader: %s has unsupported version %d (expected 1)" % [level_file, version])
		return {}
	var data: Dictionary = _parse_base(doc.get("base", []))
	data["overlay"] = _parse_overlay(doc.get("overlay", []))
	data["objects"] = doc.get("objects", [])
	# links and config are read by the format but not built yet.
	return data


func _parse_base(rows: Array) -> Dictionary:
	# Bucket cells by base-tile id; glyphs come from the registry so they live in
	# one place. floor/start/end imply a floor cell; tall_wall and safety_edge are
	# code-built (see _populate).
	var glyph_id := ObjectRegistry.glyph_to_id(ObjectRegistry.Kind.BASE_TILE)
	var floor_cells: Dictionary = {}
	var tall: Array[Vector2i] = []
	var edges: Array[Vector2i] = []
	var start := Vector2i.ZERO
	var end := Vector2i.ZERO
	for z in rows.size():
		var line: String = rows[z]
		for x in line.length():
			var cell := Vector2i(x, z)
			match String(glyph_id.get(line[x], "")):
				"floor":
					floor_cells[cell] = true
				"start":
					floor_cells[cell] = true
					start = cell
				"end":
					floor_cells[cell] = true
					end = cell
				"tall_wall":
					tall.append(cell)
				"safety_edge":
					edges.append(cell)
				_:
					pass             # void / unknown
	return {"floor": floor_cells, "tall": tall, "edges": edges, "start": start, "end": end}


func _parse_overlay(rows: Array) -> Dictionary:
	# Surface tiles painted on top of base terrain; glyphs from the registry.
	var glyph_id := ObjectRegistry.glyph_to_id(ObjectRegistry.Kind.OVERLAY_TILE)
	var ink: Array[Vector2i] = []
	var water: Array[Vector2i] = []
	for z in rows.size():
		var line: String = rows[z]
		for x in line.length():
			match String(glyph_id.get(line[x], "")):
				"ink":
					ink.append(Vector2i(x, z))
				"water":
					water.append(Vector2i(x, z))
				_:
					pass
	return {"ink": ink, "water": water}


func _populate(world: Node3D, data: Dictionary) -> void:
	# Position the singletons BEFORE the subtree enters the tree, so Player syncs
	# grid_pos and Level reads _end_cell from the right cells at _ready.
	var start: Vector2i = data["start"]
	var end: Vector2i = data["end"]
	(world.get_node("Player") as Node3D).position = Vector3(start.x, 0.5, start.y)
	(world.get_node("StartTile") as Node3D).position = Vector3(start.x, 0.01, start.y)
	(world.get_node("EndTile") as Node3D).position = Vector3(end.x, 0.01, end.y)

	var floor_scene: PackedScene = ObjectRegistry.scene_for("floor")
	for cell in data["floor"]:
		var tile: Node3D = floor_scene.instantiate()
		tile.position = Vector3(cell.x, -1.0, cell.y)
		world.add_child(tile)

	_wall_idx = 0
	# Contiguous wall cells merge into one Wall* body each: the ground shader's
	# occlusion list caps at MAX_WALLS=16 BODIES (player.gd), so per-cell walls
	# silently stop occluding in any real maze. Nav and the shader both read
	# multi-cell boxes correctly already.
	for rect in _merge_rects(data["tall"]):
		world.add_child(_make_wall_rect(rect, WALL_TALL, WALL_MATERIAL))
	for cell in data["edges"]:
		_build_safety_edge(world, cell, data["floor"])

	_build_objects(world, data["objects"])
	_build_overlay(world, data.get("overlay", {}))


func _build_safety_edge(world: Node3D, cell: Vector2i, floor_cells: Dictionary) -> void:
	# Formalized safety_edge: an invisible low blocker (cube + nav) plus a thin red
	# line on every side that faces floor (the edge it guards). No visible body and
	# deliberately NO tile: it marks an impasse at a boundary without walling up
	# the visuals; the red line on the floor's edge is the whole readout.
	world.add_child(_make_wall(cell, SAFE_EDGE_HEIGHT, null))
	for d in DIRS_4:
		if floor_cells.has(cell + d):
			world.add_child(_make_edge_strip(cell, d))


func _make_edge_strip(cell: Vector2i, dir: Vector2i) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	if dir.x != 0:
		box.size = Vector3(SAFE_EDGE_PERP, SAFE_EDGE_VERT, 1.0)
	else:
		box.size = Vector3(1.0, SAFE_EDGE_VERT, SAFE_EDGE_PERP)
	mi.mesh = box
	mi.position = Vector3(cell.x + dir.x * 0.5, SAFE_EDGE_Y, cell.y + dir.y * 0.5)
	mi.material_override = _edge_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _build_objects(world: Node3D, objects: Array) -> void:
	# Dispatch each typed instance to its builder. New object types register here.
	var enemy_idx := 0
	var zone_idx := 0
	var gate_idx := 0
	var lock_zones: Array = []
	var unlock_zones: Array = []
	for obj in objects:
		if typeof(obj) != TYPE_DICTIONARY:
			continue
		var spec: Dictionary = obj
		var cell := _cell(spec.get("cell", [0, 0]))
		match String(spec.get("type", "")):
			"enemy_sphere":
				world.add_child(_build_enemy(spec, enemy_idx))
				enemy_idx += 1
			"extend_lock_zone":
				var zone: Node3D = _build_lock_zone(spec, cell, zone_idx)
				world.add_child(zone)
				(lock_zones if zone.mode == 0 else unlock_zones).append(zone)
				zone_idx += 1
			"extend_lock_gate":
				world.add_child(_build_gate(spec, cell, gate_idx))
				gate_idx += 1
			_:
				push_warning("level_loader: unknown object type '%s', skipped" % spec.get("type", ""))
	# Softlock guard: a locked shape can tumble into any PERMUTATION of the lock's
	# dims, but never into other dims. An unlock requiring a non-permutation is
	# unsatisfiable stale data, so rewrite it to the lock's dims; a deliberate
	# different-orientation unlock (a valid permutation) is left alone. One global
	# lock per level until the link layer exists, so the first lock decides.
	if not lock_zones.is_empty():
		for u in unlock_zones:
			if not _same_dims_set(u.required_dims, lock_zones[0].required_dims):
				push_warning("level_loader: unlock dims %s unreachable from lock %s, synced" % [u.required_dims, lock_zones[0].required_dims])
				u.required_dims = lock_zones[0].required_dims


func _same_dims_set(a: Vector3i, b: Vector3i) -> bool:
	var aa: Array = [a.x, a.y, a.z]
	var bb: Array = [b.x, b.y, b.z]
	aa.sort()
	bb.sort()
	return aa == bb


func _build_enemy(spec: Dictionary, idx: int) -> Node3D:
	var enemy: Node3D = ObjectRegistry.scene_for("enemy_sphere").instantiate()
	enemy.name = "Enemy%d" % idx
	enemy.cone_index = idx
	var cell := _cell(spec.get("cell", [0, 0]))
	enemy.position = Vector3(cell.x, 0.4, cell.y)
	var wps: Array[Vector3] = []
	for wp in spec.get("waypoints", []):
		var c := _cell(wp)
		wps.append(Vector3(c.x, 0.4, c.y))
	if wps.is_empty():
		wps.append(Vector3(cell.x, 0.4, cell.y))
	enemy.waypoints = wps
	enemy.speed = float(spec.get("speed", ObjectRegistry.default_param("enemy_sphere", "speed")))
	return enemy


func _build_lock_zone(spec: Dictionary, cell: Vector2i, idx: int) -> Node3D:
	var zone: Node3D = ObjectRegistry.scene_for("extend_lock_zone").instantiate()
	zone.name = "LockZone%d" % idx
	zone.position = Vector3(cell.x, 0.5, cell.y)
	zone.mode = 1 if String(spec.get("mode", ObjectRegistry.default_param("extend_lock_zone", "mode"))) == "unlock" else 0
	zone.required_dims = _vec3i(spec.get("required_dims", ObjectRegistry.default_param("extend_lock_zone", "required_dims")))
	return zone


func _build_gate(spec: Dictionary, cell: Vector2i, idx: int) -> Node3D:
	# Node-fence gate: posts at each node cell, thin panels between consecutive
	# nodes, `height` tall. The script builds the pieces; node sits at floor level
	# at the first node's cell. Legacy gates (no nodes) become a single post.
	var gate: Node3D = ObjectRegistry.scene_for("extend_lock_gate").instantiate()
	gate.name = "Gate%d" % idx
	gate.position = Vector3(cell.x, 0.0, cell.y)
	var nds: Array[Vector2i] = []
	for n in spec.get("nodes", [[cell.x, cell.y]]):
		nds.append(_cell(n))
	gate.nodes = nds
	gate.height = int(spec.get("height", ObjectRegistry.default_param("extend_lock_gate", "height")))
	return gate


func _build_overlay(world: Node3D, overlay: Dictionary) -> void:
	# Surface-overlay tiles (ink/water) painted on top of floor. Each is a per-cell
	# puddle whose Area3D group + footprint the player reads (_collect_puddle_cells).
	for cell in overlay.get("ink", []):
		world.add_child(_make_overlay(ObjectRegistry.scene_for("ink"), cell))
	for cell in overlay.get("water", []):
		world.add_child(_make_overlay(ObjectRegistry.scene_for("water"), cell))


func _make_overlay(prefab: PackedScene, cell: Vector2i) -> Node3D:
	var p: Node3D = prefab.instantiate()
	p.position = Vector3(cell.x, 0.01, cell.y)
	return p


func _vec3i(value: Variant) -> Vector3i:
	if typeof(value) == TYPE_ARRAY and (value as Array).size() >= 3:
		var arr: Array = value
		return Vector3i(int(arr[0]), int(arr[1]), int(arr[2]))
	return Vector3i(1, 1, 3)


func _cell(value: Variant) -> Vector2i:
	# An [x, z] pair from JSON (numbers parse back as floats).
	if typeof(value) == TYPE_ARRAY and (value as Array).size() >= 2:
		var arr: Array = value
		return Vector2i(int(arr[0]), int(arr[1]))
	return Vector2i.ZERO


func _make_wall(cell: Vector2i, height: float, mat: Material) -> StaticBody3D:
	# Single-cell wall body (used per-cell by safety edges).
	return _make_wall_rect(Rect2i(cell.x, cell.y, 1, 1), height, mat)


func _make_wall_rect(rect: Rect2i, height: float, mat: Material) -> StaticBody3D:
	# Named Wall* and box-shaped so enemy_sphere._build_nav_grid blocks every
	# covered cell (it reads the collider's box footprint) and the ground shader
	# gets one AABB for the whole run. mat == null builds an INVISIBLE blocker
	# (the safety_edge body). Visible walls wear the grid material and extend
	# DOWN to the floor tiles' bottom, so a wall reads as a risen floor tile and
	# there is no void gap beneath it.
	var body := StaticBody3D.new()
	body.name = "Wall%d" % _wall_idx
	_wall_idx += 1
	var top_y := height
	var bottom_y := -FLOOR_DEPTH if mat != null else 0.0
	var size := Vector3(rect.size.x, top_y - bottom_y, rect.size.y)
	body.position = Vector3(
		rect.position.x + (rect.size.x - 1) * 0.5,
		(top_y + bottom_y) * 0.5,
		rect.position.y + (rect.size.y - 1) * 0.5
	)
	if mat != null:
		var mesh := MeshInstance3D.new()
		# Explicit name: player._push_walls_to_shader looks up "MeshInstance3D",
		# and runtime add_child auto-names ("@MeshInstance3D@N") broke that
		# silently, painted levels have been pushing ZERO wall AABBs to the
		# ground shader since the data-driven pivot.
		mesh.name = "MeshInstance3D"
		var box := BoxMesh.new()
		box.size = size
		mesh.mesh = box
		mesh.set_surface_override_material(0, mat)
		body.add_child(mesh)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	return body


func _merge_rects(cells: Array[Vector2i]) -> Array[Rect2i]:
	# Greedy rectangle cover: the top-left-most unused cell starts a rect, which
	# grows right as far as cells exist, then down while every cell of the next
	# row exists. Not optimal in pathological layouts, but collapses straight
	# runs and solid blocks (the common wall shapes) to one body each.
	var remaining: Dictionary = {}
	for c in cells:
		remaining[c] = true
	var ordered: Array = cells.duplicate()
	ordered.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y or (a.y == b.y and a.x < b.x))
	var rects: Array[Rect2i] = []
	for c in ordered:
		var cell: Vector2i = c
		if not remaining.has(cell):
			continue
		var w := 1
		while remaining.has(Vector2i(cell.x + w, cell.y)):
			w += 1
		var h := 1
		var grow := true
		while grow:
			for x in range(cell.x, cell.x + w):
				if not remaining.has(Vector2i(x, cell.y + h)):
					grow = false
					break
			if grow:
				h += 1
		for x in range(cell.x, cell.x + w):
			for z in range(cell.y, cell.y + h):
				remaining.erase(Vector2i(x, z))
		rects.append(Rect2i(cell.x, cell.y, w, h))
	return rects
