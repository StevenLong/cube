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
#     "objects": [ { "type": <id>, "id": <str?>, "cell": [x, z], ...params } ],
#     "links":   [ { "from": <id>, "to": <id>, "kind": <str> } ],
#     "config":  { ... } }  # level rules         -- TODO build
#
# `id` (optional) is a per-instance key, distinct from `type` (the object kind).
# `links` are directed typed edges between those ids (kinds e.g. `opens` for
# lock->gate, `released_by` for lock->unlock). The loader parses and validates
# links here (dropping malformed/dangling edges with a warning); the kind is an
# opaque string so a new linkable type needs only a handler, not a parser change.
# Wiring the runtime coupling that reads these edges is a later slice. See memory
# project_link_layer_design.
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
const LINK_ALPHA := 0.5       # guide-line opacity: understated, reads as a hint not a bar
const LINK_EMISSION := 0.55   # guide-line glow strength (dimmed from the old full 1.0)
const JUMP_MAX := 5           # mirrors player.gd DODGE_DISTANCE: the cube can cross a straight
							  # cardinal gap of up to JUMP_MAX-1 void cells (dodge/bridge), so the
							  # guide router treats such a gap as a traversable edge, not a wall.
const JUMP_PENALTY := 100000  # extra cost a jump pays on top of its cells. Larger than any all-floor
							  # detour a real level can hold, so the guide stays on tiles wherever a
							  # floor path exists and only jumps when it must. Lower it to let a short
							  # jump win over a sufficiently long walk-around.
const DIRS_4: Array[Vector2i] = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]

@export var level_file: String = "res://levels/data/level_01.json"
static var requested_file: String = ""   # the active level's file. A launcher sets it; the loader keeps it (does NOT clear) so reload_current_scene (restart) replays the same file. Every painted_level launcher must set it, or a stale value leaks in.
static var return_to_editor: bool = false   # set by the editor's playtest; level.gd then returns to the editor on exit instead of the main menu
static var sequence: Array[String] = []   # ordered file paths of the set the active level belongs to; a menu launcher sets it so the complete screen can offer "Next". Empty (or last entry) = no Next button. Persists across reloads like requested_file.
static var sequence_noun: String = "Level"   # the button reads "Next <noun>"; the tutorials menu sets "Tutorial"

var _edge_mat: StandardMaterial3D
var _glass_mat: StandardMaterial3D
var _pitfall_mat: StandardMaterial3D
var _wall_idx := 0          # running Wall* counter; nav keys off unique Wall names
var _arrow_mesh_res: ArrayMesh   # shared flat arrowhead for jump markers, built once on first use


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
	# Pitfall floor: amber, visibly fragile/distinct from normal floor so it's plannable.
	_pitfall_mat = StandardMaterial3D.new()
	_pitfall_mat.albedo_color = Color(0.85, 0.45, 0.1)
	_pitfall_mat.emission_enabled = true
	_pitfall_mat.emission = Color(0.85, 0.45, 0.1)
	_pitfall_mat.emission_energy_multiplier = 0.35
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
	data["links"] = _parse_links(doc.get("links", []), data["objects"])
	# config is read by the format but not built yet.
	return data


func _parse_links(raw: Variant, objects: Array) -> Array[Dictionary]:
	# Parse the relationship layer: directed typed edges {from, to, kind} between
	# object `id`s. Generic by design -- `kind` is opaque, so a new linkable type
	# adds a kind plus a handler (later slices) without touching this plumbing.
	# Validates STRUCTURE (three non-empty string fields) and ENDPOINTS (from/to
	# each name a real object id); malformed or dangling edges are dropped with a
	# warning so the returned list is safe to resolve. Runtime coupling is NOT here.
	var out: Array[Dictionary] = []
	if typeof(raw) != TYPE_ARRAY:
		push_warning("level_loader: 'links' is not an array, ignored")
		return out
	var ids := _object_ids(objects)
	for edge in (raw as Array):
		if typeof(edge) != TYPE_DICTIONARY:
			push_warning("level_loader: link entry is not an object, skipped: %s" % [edge])
			continue
		var e: Dictionary = edge
		var from := String(e.get("from", ""))
		var to := String(e.get("to", ""))
		var kind := String(e.get("kind", ""))
		if from.is_empty() or to.is_empty() or kind.is_empty():
			push_warning("level_loader: link missing from/to/kind, skipped: %s" % [e])
			continue
		if not ids.has(from):
			push_warning("level_loader: link 'from' id '%s' matches no object, skipped" % from)
			continue
		if not ids.has(to):
			push_warning("level_loader: link 'to' id '%s' matches no object, skipped" % to)
			continue
		out.append({"from": from, "to": to, "kind": kind})
	return out


func _object_ids(objects: Array) -> Dictionary:
	# Set of the non-empty per-instance ids present in the object list, warning on
	# duplicates (a link to a repeated id would resolve ambiguously). Objects with
	# no id are simply unlinkable, which is the default (optionality = not linked).
	var ids: Dictionary = {}
	for obj in objects:
		if typeof(obj) != TYPE_DICTIONARY:
			continue
		var oid := String((obj as Dictionary).get("id", ""))
		if oid.is_empty():
			continue
		if ids.has(oid):
			push_warning("level_loader: duplicate object id '%s'; links to it are ambiguous" % oid)
			continue
		ids[oid] = true
	return ids


func _parse_base(rows: Array) -> Dictionary:
	# Bucket cells by base-tile id; glyphs come from the registry so they live in
	# one place. floor/start/end imply a floor cell; tall_wall and safety_edge are
	# code-built (see _populate).
	var glyph_id := ObjectRegistry.glyph_to_id(ObjectRegistry.Kind.BASE_TILE)
	var floor_cells: Dictionary = {}
	var tall: Array[Vector2i] = []
	var edges: Array[Vector2i] = []
	var glass: Array[Vector2i] = []
	var pitfall: Array[Vector2i] = []
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
				"pitfall":
					# Walkable floor until the player vacates it; level.gd tags the
					# tile so it can break at runtime.
					floor_cells[cell] = true
					pitfall.append(cell)
				_:
					pass             # void / unknown
	return {"floor": floor_cells, "tall": tall, "edges": edges, "glass": glass, "pitfall": pitfall, "start": start, "end": end}


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

	# N6 safety net: an overlay (ink/water) implies a floor beneath it, so old data
	# (saved before the editor auto-stamped floor) can't leave a surface tile floating
	# over the void. New saves already carry the floor; this just backstops the rest.
	var overlay: Dictionary = data.get("overlay", {})
	for cell in overlay.get("ink", []):
		data["floor"][cell] = true
	for cell in overlay.get("water", []):
		data["floor"][cell] = true

	var floor_scene: PackedScene = ObjectRegistry.scene_for("floor")
	var pitfall_set := {}
	for cell in data["pitfall"]:
		pitfall_set[cell] = true
	for cell in data["floor"]:
		if pitfall_set.has(cell):
			continue   # pitfall cells get their own (breakable) tile below
		var tile: Node3D = floor_scene.instantiate()
		tile.position = Vector3(cell.x, -1.0, cell.y)
		world.add_child(tile)
	# Pitfall tiles: a normal floor tile (so it counts as floor and is in group
	# "floor_tiles"), recoloured and tagged so level.gd can break it on vacate.
	for cell in data["pitfall"]:
		var tile: Node3D = floor_scene.instantiate()
		tile.position = Vector3(cell.x, -1.0, cell.y)
		tile.add_to_group("pitfall_tiles")
		var mi: MeshInstance3D = tile.get_node_or_null("MeshInstance3D")
		if mi != null:
			mi.set_surface_override_material(0, _pitfall_mat)
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
	# Softlock guard: a locked shape can tumble into any PERMUTATION of a lock's dims,
	# but never into other dims, so an unlock requiring a shape no lock can produce is
	# unsatisfiable stale data and gets rewritten to a real lock shape. Crucially this
	# checks EVERY lock, not just the first: a level can chain several lock/unlock pairs
	# of different shapes (locked into A, unlock A, then lock into B, unlock B, ...) on
	# the single global lock state, and each unlock keeps its own shape as long as some
	# lock can produce it. Pairing a specific unlock to a specific lock (and catching a
	# mis-sequenced softlock) still needs the link layer (N5/N14).
	if not lock_zones.is_empty():
		for u in unlock_zones:
			var reachable := false
			for l in lock_zones:
				if _same_dims_set(u.required_dims, l.required_dims):
					reachable = true
					break
			if not reachable:
				push_warning("level_loader: unlock dims %s match no lock, synced to %s" % [u.required_dims, lock_zones[0].required_dims])
				u.required_dims = lock_zones[0].required_dims
	_wire_lock_links(lock_zones, unlock_zones, gates, data.get("links", []))
	_build_lock_links(world, lock_zones, unlock_zones, gates, data.get("links", []), _walkable_cells(data), _blocked_cells(data))


func _wire_lock_links(locks: Array, unlocks: Array, gates: Array, links: Array) -> void:
	# Decentralised partner injection (slice 2): hand each object the lock ids it must
	# react to, then the objects self-update against the player's single active lock id
	# (a gate opens while its opener is active; an unlock releases its paired lock). The
	# coupling is EXPLICIT-LINKS-ONLY: an object with nothing injected reacts to nothing.
	# A level with no lock edges wires nothing (a lone lock is a commit-to-a-shape puzzle).
	if locks.is_empty():
		return
	var gate_by_id := _by_link_id(gates)
	var unlock_by_id := _by_link_id(unlocks)
	for edge in links:
		var e: Dictionary = edge
		match String(e["kind"]):
			"opens":
				if gate_by_id.has(e["to"]):
					gate_by_id[e["to"]].opener_ids.append(String(e["from"]))
				else:
					push_warning("level_loader: 'opens' target '%s' is not a gate, skipped" % e["to"])
			"released_by":
				if unlock_by_id.has(e["to"]):
					unlock_by_id[e["to"]].release_lock_ids.append(String(e["from"]))
				else:
					push_warning("level_loader: 'released_by' target '%s' is not an unlock zone, skipped" % e["to"])
			_:
				pass   # no handler for this kind yet; the plumbing stays generic
	for l in locks:
		if l.link_id == "":
			push_warning("level_loader: a lock has no id, so it cannot arm (no link references it)")


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


func _blocked_cells(data: Dictionary) -> Dictionary:
	# Cells a jump cannot cross: full-height walls, glass panes, and safety edges are all
	# physical bodies that stop a dodge/bridge. The jump router treats a gap as crossable
	# only when every cell in the span is pure void (neither floor nor one of these).
	var out: Dictionary = {}
	for cell in data.get("tall", []):
		out[cell] = true
	for cell in data.get("glass", []):
		out[cell] = true
	for cell in data.get("edges", []):
		out[cell] = true
	return out


func _build_lock_links(world: Node3D, locks: Array, unlocks: Array, gates: Array, links: Array, walkable: Dictionary, blocked: Dictionary) -> void:
	# Guide lines so the lock puzzle reads at a glance, routed ALONG THE GRID (not
	# crow-flies): an orange path lock->gate (shown while the gate is shut) and a green
	# path lock->unlock (shown once that lock is armed). Each line is drawn per edge and
	# tagged with its lock id, so a multi-lock level reads each puzzle on its own. A level
	# with no lock edges draws no guide lines.
	if locks.is_empty():
		return
	var lock_by_id := _by_link_id(locks)
	var gate_by_id := _by_link_id(gates)
	var unlock_by_id := _by_link_id(unlocks)
	for edge in links:
		var e: Dictionary = edge
		var lock_id := String(e["from"])
		var lock = lock_by_id.get(lock_id)
		if lock == null:
			continue   # 'from' is not a lock: nothing to anchor a line on (already warned at parse)
		var lock_cell := _zone_center_cell(lock)
		match String(e["kind"]):
			"opens":
				var g = gate_by_id.get(String(e["to"]))
				if g != null:
					var holder := _new_link_holder(false, lock_id)
					_draw_grid_path(holder, lock_cell, _gate_center_cell(g), walkable, blocked, Color(0.9, 0.55, 0.15), 0.07)
					world.add_child(holder)
			"released_by":
				var u = unlock_by_id.get(String(e["to"]))
				if u != null:
					var holder := _new_link_holder(true, lock_id)
					_draw_grid_path(holder, lock_cell, _zone_center_cell(u), walkable, blocked, Color(0.25, 0.85, 0.4), 0.04)
					world.add_child(holder)
			_:
				pass   # no guide line for unknown kinds yet


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


func _new_link_holder(visible_when_locked: bool, lock_id: String) -> Node3D:
	var h := Node3D.new()
	h.set_script(load("res://guide_line.gd"))
	h.set("visible_when_locked", visible_when_locked)
	h.set("lock_id", lock_id)
	return h


func _by_link_id(nodes: Array) -> Dictionary:
	# Map each node's injected link_id -> node (skipping the unidentified). Shared by the
	# partner injection and the per-lock guide-line drawing.
	var m: Dictionary = {}
	for n in nodes:
		if n.link_id != "":
			m[n.link_id] = n
	return m


func _draw_grid_path(holder: Node3D, start: Vector2i, goal: Vector2i, walkable: Dictionary, blocked: Dictionary, color: Color, y: float) -> void:
	# Snap each end to the nearest floor cell first: a zone footprint centre or a gate's
	# bounding-box centre can land on a void (e.g. an L-gate's inner corner), which would
	# otherwise make the BFS bail and beeline. Then route along the cube's REAL traversal:
	# a solid line for each floor STEP, and at each JUMP (a dodge/bridge across void) no
	# line over the gap -- just an arrow on the take-off cell pointing to where the line
	# resumes. If the goal stays unreachable even with jumps, the line simply stops at the
	# nearest reachable cell (a level bug, surfaced by the gap, never marked over the void).
	var s := _nearest_walkable(start, walkable)
	var g := _nearest_walkable(goal, walkable)
	var route := _route(s, g, walkable, blocked)
	var path: Array = route["path"]
	for i in range(path.size() - 1):
		var a: Vector2i = path[i]
		var b: Vector2i = path[i + 1]
		if absi(a.x - b.x) + absi(a.y - b.y) == 1:
			holder.add_child(_make_link_segment(Vector2(a.x, a.y), Vector2(b.x, b.y), color, y))
		else:
			holder.add_child(_make_link_arrow(a, b, color, y))


func _nearest_walkable(cell: Vector2i, walkable: Dictionary) -> Vector2i:
	# Closest floor cell to `cell` (itself if already floor), searched in widening rings.
	if walkable.has(cell):
		return cell
	for radius in range(1, 8):
		var best := cell
		var best_d := 1 << 30
		var found := false
		for dx in range(-radius, radius + 1):
			for dz in range(-radius, radius + 1):
				var c := cell + Vector2i(dx, dz)
				if walkable.has(c):
					var dd: int = absi(dx) + absi(dz)
					if dd < best_d:
						best_d = dd
						best = c
						found = true
		if found:
			return best
	return cell


func _route(start: Vector2i, goal: Vector2i, walkable: Dictionary, blocked: Dictionary) -> Dictionary:
	# Weighted shortest path over the cube's traversal graph: 4-connected floor steps PLUS
	# jump edges (see _neighbors). A walk step costs its 1 cell; a jump ALSO pays JUMP_PENALTY,
	# so a floor route always beats a jump when one exists and gaps are crossed with the fewest,
	# shortest jumps otherwise. Returns {path, connected}: the full route to goal when reachable,
	# else the path to the reachable cell CLOSEST to goal, so the line stops at the gap nearest
	# the target. Consecutive path cells more than 1 apart are a jump, drawn as an arrow.
	if not walkable.has(start):
		return {"path": [], "connected": false}
	if start == goal:
		return {"path": [start] as Array[Vector2i], "connected": true}
	var came: Dictionary = {}
	var cost: Dictionary = {start: 0}
	var done: Dictionary = {}
	var frontier: Array[Vector2i] = [start]
	var found := false
	while not frontier.is_empty():
		# Pop the lowest-cost frontier cell (levels are small, so a linear scan is plenty).
		var bi := 0
		for i in range(1, frontier.size()):
			if int(cost[frontier[i]]) < int(cost[frontier[bi]]):
				bi = i
		var cur: Vector2i = frontier[bi]
		frontier.remove_at(bi)
		if cur == goal:
			found = true
			break
		done[cur] = true
		for n in _neighbors(cur, walkable, blocked):
			if done.has(n):
				continue
			var step: int = absi(n.x - cur.x) + absi(n.y - cur.y)   # cells moved (1 = walk, >1 = jump)
			var nc: int = int(cost[cur]) + step + (JUMP_PENALTY if step > 1 else 0)
			if not cost.has(n) or nc < int(cost[n]):
				cost[n] = nc
				came[n] = cur
				if not frontier.has(n):
					frontier.append(n)
	var target := goal
	if not found:
		var best := start
		var best_d: int = absi(start.x - goal.x) + absi(start.y - goal.y)
		for c in cost:
			var cc: Vector2i = c
			var dd: int = absi(cc.x - goal.x) + absi(cc.y - goal.y)
			if dd < best_d:
				best_d = dd
				best = cc
		target = best
	var path: Array[Vector2i] = [target]
	var c2 := target
	while c2 != start:
		c2 = came[c2]
		path.push_front(c2)
	return {"path": path, "connected": found}


func _neighbors(cur: Vector2i, walkable: Dictionary, blocked: Dictionary) -> Array[Vector2i]:
	# Traversal edges out of `cur` for the guide BFS: each adjacent floor cell (an ordinary
	# walk step), plus jump edges -- a straight cardinal hop of 2..JUMP_MAX cells that clears
	# a run of PURE VOID (every span cell neither floor nor a blocker) and lands on floor.
	# This mirrors a dodge/bridge: void is passable, but a wall or safety edge in the span
	# stops the crossing, and the landing must be solid ground.
	var out: Array[Vector2i] = []
	for d in DIRS_4:
		if walkable.has(cur + d):
			out.append(cur + d)   # contiguous floor: walk (a jump would only overshoot it)
			continue
		for k in range(2, JUMP_MAX + 1):
			var inter := cur + d * (k - 1)   # cell just short of this jump's landing
			if walkable.has(inter) or blocked.has(inter):
				break                        # span broken by floor or a blocker: stop scanning
			var land := cur + d * k
			if walkable.has(land):
				out.append(land)             # pure-void span cleared, lands on floor
	return out


func _make_link_segment(a: Vector2, b: Vector2, color: Color, y: float) -> MeshInstance3D:
	# A thin emissive strip on the floor from a -> b (cell centres), rotated so the
	# box's long (z) axis runs along the segment. Visual guide only, no collision.
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.08, 0.02, maxf(a.distance_to(b), 0.01))
	mi.mesh = box
	mi.material_override = _link_material(color)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mid := (a + b) * 0.5
	mi.position = Vector3(mid.x, y, mid.y)
	mi.rotation.y = atan2(b.x - a.x, b.y - a.y)
	return mi


func _make_link_arrow(from_cell: Vector2i, to_cell: Vector2i, color: Color, y: float) -> MeshInstance3D:
	# Marks a JUMP across void: the guide line breaks at the gap and resumes on the far
	# side, with this flat arrowhead on the take-off cell (just shy of the void) pointing
	# the way. Shows the crossing without ever drawing a mark over the void itself.
	var dir := Vector2(to_cell.x - from_cell.x, to_cell.y - from_cell.y).normalized()
	var mi := MeshInstance3D.new()
	mi.mesh = _arrow_mesh()
	var mat := _link_material(color)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED   # flat single-sided tri stays visible from above
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Offset 0.30 + tip length 0.18 keeps the whole head inside the cell edge (0.5): the
	# arrow sits near the gap but never paints over the void it points across.
	mi.position = Vector3(from_cell.x + dir.x * 0.30, y, from_cell.y + dir.y * 0.30)
	mi.rotation.y = atan2(dir.x, dir.y)
	return mi


func _arrow_mesh() -> ArrayMesh:
	# A small flat triangle in local XZ pointing +Z (forward), shared by every jump arrow.
	if _arrow_mesh_res != null:
		return _arrow_mesh_res
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(0.0, 0.0, 0.18),     # tip
		Vector3(-0.13, 0.0, -0.10),  # back-left
		Vector3(0.13, 0.0, -0.10),   # back-right
	])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_arrow_mesh_res = mesh
	return mesh


func _link_material(color: Color) -> StandardMaterial3D:
	# Shared guide-line look: half-translucent with a dimmed glow so guides read as quiet
	# hints, not bright bars competing with the level. LINK_ALPHA/LINK_EMISSION tune it.
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(color.r, color.g, color.b, LINK_ALPHA)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = LINK_EMISSION
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat


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
	zone.link_id = String(spec.get("id", ""))
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
	gate.link_id = String(spec.get("id", ""))
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
