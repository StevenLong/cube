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
const FLOOR_DEPTH := 60.0  # visual depth of floor/wall columns; must exceed the shader fade_end and match FloorTile.tscn's mesh depth.
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
var _glass_mat: StandardMaterial3D
var _wall_idx := 0          # running Wall* counter; nav keys off unique Wall names


func _ready() -> void:
	_edge_mat = StandardMaterial3D.new()
	_edge_mat.albedo_color = Color(0.9, 0.15, 0.15)
	_edge_mat.emission_enabled = true
	_edge_mat.emission = Color(0.9, 0.15, 0.15)
	_edge_mat.emission_energy_multiplier = SAFE_EDGE_ENERGY
	_edge_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glass_mat = StandardMaterial3D.new()
	_glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glass_mat.albedo_color = Color(0.4, 0.8, 1.0, 0.18)
	_glass_mat.emission_enabled = true
	_glass_mat.emission = Color(0.4, 0.8, 1.0)
	_glass_mat.emission_energy_multiplier = 0.2
	_glass_mat.cull_mode = BaseMaterial3D.CULL_DISABLED  # both faces of the pane visible
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
	var glass: Array[Vector2i] = []
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
				"glass_wall":
					glass.append(cell)
				_:
					pass             # void / unknown
	return {"floor": floor_cells, "tall": tall, "edges": edges, "glass": glass, "start": start, "end": end}


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

	# Gate cells and lock/unlock footprints must be walkable floor: the player walks
	# a lowered gate, and forms/re-seats the shape across a zone's whole footprint.
	# Merge those cells into the floor set so each gets a tile (and is reachable by
	# nav / the guide-path BFS), not just the authored base cells.
	_add_object_floor(data)

	# A glass pane is a 1u-tall wall (not a sunk column), so it can't hide the void
	# beneath it: give every glass cell a floor tile, like gate/zone footprints.
	for cell in data["glass"]:
		data["floor"][cell] = true

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
	for rect in _merge_rects(data["glass"]):
		world.add_child(_make_glass_rect(rect))
	for cell in data["edges"]:
		_build_safety_edge(world, cell, data["floor"])

	_build_objects(world, data)
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


func _build_objects(world: Node3D, data: Dictionary) -> void:
	# Dispatch each typed instance to its builder. New object types register here.
	var objects: Array = data.get("objects", [])
	var enemy_idx := 0
	var zone_idx := 0
	var gate_idx := 0
	var lock_zones: Array = []
	var unlock_zones: Array = []
	var gates: Array = []
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
				var gate: Node3D = _build_gate(spec, cell, gate_idx)
				world.add_child(gate)
				gates.append(gate)
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
	_build_lock_links(world, lock_zones, unlock_zones, gates, _walkable_cells(data))


func _add_object_floor(data: Dictionary) -> void:
	# Gate spans and lock/unlock footprints become floor, so a lowered gate leaves
	# walkable ground and a zone's whole required footprint has floor to form on.
	var floor_cells: Dictionary = data["floor"]
	for obj in data.get("objects", []):
		if typeof(obj) != TYPE_DICTIONARY:
			continue
		match String(obj.get("type", "")):
			"extend_lock_gate":
				var nds: Array = obj.get("nodes", [obj.get("cell", [0, 0])])
				for i in nds.size():
					var a := _cell(nds[i])
					floor_cells[a] = true
					if i < nds.size() - 1:
						var b := _cell(nds[i + 1])
						var av := Vector2(a.x, a.y)
						var bv := Vector2(b.x, b.y)
						var steps := maxi(1, ceili(av.distance_to(bv) * 2.0))
						for s in range(steps + 1):
							var p := av.lerp(bv, float(s) / float(steps))
							floor_cells[Vector2i(roundi(p.x), roundi(p.y))] = true
			"extend_lock_zone":
				var cell := _cell(obj.get("cell", [0, 0]))
				var dims := _vec3i(obj.get("required_dims", ObjectRegistry.default_param("extend_lock_zone", "required_dims")))
				for i in range(dims.x):       # width = x
					for j in range(dims.z):   # depth = z
						floor_cells[cell + Vector2i(i, j)] = true


func _walkable_cells(data: Dictionary) -> Dictionary:
	# Floor cells the guide path may run along: floor minus full-height walls minus
	# safety edges. Gate cells stay walkable (the path runs through the doorway).
	var out: Dictionary = {}
	for cell in data.get("floor", {}):
		out[cell] = true
	for cell in data.get("tall", []):
		out.erase(cell)
	for cell in data.get("glass", []):
		out.erase(cell)
	for cell in data.get("edges", []):
		out.erase(cell)
	return out


func _build_lock_links(world: Node3D, locks: Array, unlocks: Array, gates: Array, walkable: Dictionary) -> void:
	# Guide lines so the lock puzzle reads at a glance, routed ALONG THE GRID (not
	# crow-flies): an orange path from the lock to the gate it opens (always shown),
	# and a green path from the lock to its unlock zone (shown only once the gate is
	# open, i.e. while extend-locked). One global lock per level for now, so the
	# first lock is the anchor (the link layer will make this per-instance later).
	if locks.is_empty():
		return
	var lock_cell := _zone_center_cell(locks[0])
	for gate in gates:
		# lock->gate: shown while the gate is shut, hidden once it opens.
		var holder := _new_link_holder(false)
		_draw_grid_path(holder, lock_cell, _gate_center_cell(gate), walkable, Color(0.9, 0.55, 0.15), 0.07)
		world.add_child(holder)
	for u in unlocks:
		# lock->unlock: hidden until the gate opens (player locked), then shown.
		var holder := _new_link_holder(true)
		_draw_grid_path(holder, lock_cell, _zone_center_cell(u), walkable, Color(0.25, 0.85, 0.4), 0.04)
		world.add_child(holder)


func _zone_center_cell(zone: Node3D) -> Vector2i:
	# Centre of a lock/unlock footprint, so guide lines connect centrally rather
	# than at the min corner (integer-floored, so it stays a valid grid cell).
	var c := Vector2i(roundi(zone.position.x), roundi(zone.position.z))
	var dims: Vector3i = zone.required_dims
	@warning_ignore("integer_division")
	return c + Vector2i((dims.x - 1) / 2, (dims.z - 1) / 2)


func _gate_center_cell(gate: Node3D) -> Vector2i:
	# Centre of a gate's node span (its bounding box), for central guide-line ends.
	var nds: Array = gate.nodes
	if nds.is_empty():
		return Vector2i(roundi(gate.position.x), roundi(gate.position.z))
	var minc: Vector2i = nds[0]
	var maxc: Vector2i = nds[0]
	for n in nds:
		var v: Vector2i = n
		minc.x = mini(minc.x, v.x)
		minc.y = mini(minc.y, v.y)
		maxc.x = maxi(maxc.x, v.x)
		maxc.y = maxi(maxc.y, v.y)
	@warning_ignore("integer_division")
	return Vector2i((minc.x + maxc.x) / 2, (minc.y + maxc.y) / 2)


func _new_link_holder(visible_when_locked: bool) -> Node3D:
	var h := Node3D.new()
	h.set_script(load("res://guide_line.gd"))
	h.set("visible_when_locked", visible_when_locked)
	return h


func _draw_grid_path(holder: Node3D, start: Vector2i, goal: Vector2i, walkable: Dictionary, color: Color, y: float) -> void:
	var path := _grid_path(start, goal, walkable)
	if path.size() < 2:
		# No grid route (e.g. the target is off-floor): fall back to a straight line
		# so the relationship is still shown.
		holder.add_child(_make_link_segment(Vector2(start.x, start.y), Vector2(goal.x, goal.y), color, y))
		return
	for i in range(path.size() - 1):
		holder.add_child(_make_link_segment(Vector2(path[i].x, path[i].y), Vector2(path[i + 1].x, path[i + 1].y), color, y))


func _grid_path(start: Vector2i, goal: Vector2i, walkable: Dictionary) -> Array[Vector2i]:
	# 4-connected BFS over walkable cells. Returns start..goal inclusive, or [] if
	# either endpoint is off-floor or no orthogonal route exists.
	if not walkable.has(start) or not walkable.has(goal):
		return []
	if start == goal:
		return [start]
	var came: Dictionary = {}
	var visited: Dictionary = {start: true}
	var frontier: Array[Vector2i] = [start]
	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	while not frontier.is_empty():
		var cur: Vector2i = frontier.pop_front()
		if cur == goal:
			break
		for d in dirs:
			var n: Vector2i = cur + d
			if walkable.has(n) and not visited.has(n):
				visited[n] = true
				came[n] = cur
				frontier.append(n)
	if not came.has(goal):
		return []
	var path: Array[Vector2i] = [goal]
	var c := goal
	while c != start:
		c = came[c]
		path.push_front(c)
	return path


func _make_link_segment(a: Vector2, b: Vector2, color: Color, y: float) -> MeshInstance3D:
	# A thin emissive strip on the floor from a -> b (cell centres), rotated so the
	# box's long (z) axis runs along the segment. Visual guide only, no collision.
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.08, 0.02, maxf(a.distance_to(b), 0.01))
	mi.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mid := (a + b) * 0.5
	mi.position = Vector3(mid.x, y, mid.y)
	mi.rotation.y = atan2(b.x - a.x, b.y - a.y)
	return mi


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


func _make_glass_rect(rect: Rect2i) -> StaticBody3D:
	# A glass wall: a normal layer-1 solid named Wall* — so it blocks the player's
	# tumble and the sphere's body, and nav routes around it exactly like any wall —
	# but tagged into group "glass" so enemy_sphere adds it to the EXCLUDE list of its
	# vision rays. Guards therefore see and detect straight through it (the point: a
	# risk-free window onto patrol behaviour) while it stays physically solid.
	# It is 1u tall on its own floor tile (see _populate), not a sunk column, since a
	# clear pane can't mask a void. The mesh is deliberately NOT named "MeshInstance3D"
	# so player._push_walls_to_shader skips it and the floor cone reads through the glass.
	var body := StaticBody3D.new()
	body.name = "Wall%d" % _wall_idx
	_wall_idx += 1
	body.add_to_group("glass")
	var size := Vector3(rect.size.x, WALL_TALL, rect.size.y)
	body.position = Vector3(
		rect.position.x + (rect.size.x - 1) * 0.5,
		WALL_TALL * 0.5,
		rect.position.y + (rect.size.y - 1) * 0.5
	)
	var mesh := MeshInstance3D.new()
	mesh.name = "GlassPane"
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.set_surface_override_material(0, _glass_mat)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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
