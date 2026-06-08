extends Node3D

# In-world level editor v2: the cursor IS the real player cube in god-mode (no fall,
# no-clip), so you drive and EXTEND it like in game. To place an extend-lock you just
# BE the shape: place captures the cube's dimensions at its cell. A palette of
# ObjectRegistry types is stamped at the cube's cell, building a JSON-format level.
#   Move / extend: your usual controls    Q / E: cycle type
#   Enter or Space: place    X or Backspace: erase    F5: finish / name
# FIRST PASS of v2. NEXT: menu-first selection, area-select bulk, tabbed assemblies,
# the paused-ghost play-mode toggle, real objects rendered inert. The previews here
# partly mirror level_loader; both want a shared LevelBuilder (no drift).

const REAL_SCENES := ["floor", "ink", "water"]

@onready var _player: Node3D = $Player
@onready var _info: Label = $UI/Info
@onready var _finish_panel: Control = $UI/FinishPanel
@onready var _name_edit: LineEdit = $UI/FinishPanel/VBox/NameEdit
@onready var _save_button: Button = $UI/FinishPanel/VBox/Buttons/SaveButton
@onready var _cancel_button: Button = $UI/FinishPanel/VBox/Buttons/CancelButton

var _palette: Array = []
var _sel := 0
var _finishing := false
var _level_name := "My Level"
var _base: Dictionary = {}       # Vector2i -> id
var _overlay: Dictionary = {}    # Vector2i -> id
var _objects: Dictionary = {}    # Vector2i -> { "id": String, "params": Dictionary }
var _vis: Dictionary = {}        # "layer:x,z" -> Node3D


func _ready() -> void:
	_player.god_mode = true
	_palette = ObjectRegistry.TYPES.keys()
	_save_button.pressed.connect(_do_save)
	_cancel_button.pressed.connect(_close_finish)
	_name_edit.text_submitted.connect(_on_name_submitted)
	_finish_panel.hide()
	_refresh()


func _process(_delta: float) -> void:
	_refresh()  # keep the readout live as the cube moves


func _unhandled_input(event: InputEvent) -> void:
	if _finishing:
		# the name panel owns input while open; Esc cancels it, not the editor
		if event.is_action_pressed("ui_cancel"):
			_close_finish()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel"):
		get_tree().change_scene_to_file("res://main_menu.tscn")
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_E:
				_cycle(1)
			KEY_Q:
				_cycle(-1)
			KEY_ENTER, KEY_SPACE:
				_place()
			KEY_X, KEY_BACKSPACE:
				_erase()
			KEY_F5:
				_open_finish()


func _cell() -> Vector2i:
	return _player.grid_pos


func _cycle(d: int) -> void:
	_sel = wrapi(_sel + d, 0, _palette.size())
	_refresh()


func _place() -> void:
	var id: String = _palette[_sel]
	match ObjectRegistry.TYPES[id]["kind"]:
		ObjectRegistry.Kind.BASE_TILE:
			_stamp_tile(_base, "base", id)
		ObjectRegistry.Kind.OVERLAY_TILE:
			_stamp_tile(_overlay, "overlay", id)
		ObjectRegistry.Kind.OBJECT:
			_stamp_object(id)
	_refresh()


func _stamp_tile(model: Dictionary, layer: String, id: String) -> void:
	var cell := _cell()
	var key := "%s:%d,%d" % [layer, cell.x, cell.y]
	_clear_vis(key)
	model[cell] = id
	var node := _make_visual(id, cell)
	if node != null:
		add_child(node)
		_vis[key] = node


func _stamp_object(id: String) -> void:
	# BE-the-shape: the lock captures the cube's current dimensions; others drop at
	# the cube's cell with default params.
	var cell := _cell()
	var params: Dictionary = {}
	if id == "extend_lock_zone":
		var dims: Vector3i = _player.get_dimensions()
		params = {"mode": "lock", "required_dims": [dims.x, dims.y, dims.z]}
	var key := "object:%d,%d" % [cell.x, cell.y]
	_clear_vis(key)
	_objects[cell] = {"id": id, "params": params}
	var node := _make_object_visual(id, params)
	node.position = Vector3(cell.x, _obj_y(id), cell.y)
	add_child(node)
	_vis[key] = node


func _erase() -> void:
	var cell := _cell()
	for layer in ["object", "overlay", "base"]:
		var key := "%s:%d,%d" % [layer, cell.x, cell.y]
		if _vis.has(key):
			_clear_vis(key)
			match layer:
				"object":
					_objects.erase(cell)
				"overlay":
					_overlay.erase(cell)
				"base":
					_base.erase(cell)
			break
	_refresh()


func _clear_vis(key: String) -> void:
	if _vis.has(key):
		_vis[key].queue_free()
		_vis.erase(key)


func _make_visual(id: String, cell: Vector2i) -> Node3D:
	if id in REAL_SCENES:
		var n: Node3D = ObjectRegistry.scene_for(id).instantiate()
		n.position = Vector3(cell.x, (-1.0 if id == "floor" else 0.01), cell.y)
		return n
	if id == "void":
		return null
	var mi := _preview_mesh(id)
	mi.position = Vector3(cell.x, _obj_y(id), cell.y)
	return mi


func _make_object_visual(id: String, params: Dictionary) -> Node3D:
	if id == "extend_lock_zone":
		var d: Array = params.get("required_dims", [1, 1, 3])
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(d[0], d[1], d[2])
		mi.mesh = box
		mi.set_surface_override_material(0, _ghost_mat(Color(0.85, 0.5, 0.15, 0.45)))
		# Centre the cuboid over the footprint (min corner at the cube's cell).
		mi.position = Vector3((d[0] - 1) * 0.5, d[1] * 0.5 - _obj_y(id), (d[2] - 1) * 0.5)
		var holder := Node3D.new()
		holder.add_child(mi)
		return holder
	return _preview_mesh(id)


func _obj_y(id: String) -> float:
	match id:
		"floor":
			return -1.0
		"ink", "water":
			return 0.01
		"enemy_sphere":
			return 0.4
		"extend_lock_gate":
			return 1.5
		_:
			return 0.5


func _preview_mesh(id: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mat := StandardMaterial3D.new()
	match id:
		"tall_wall":
			mi.mesh = _box(Vector3(1, 1, 1))
			mat.albedo_color = Color(0.4, 0.4, 0.5)
		"safety_edge":
			mi.mesh = _box(Vector3(1, 0.1, 1))
			mat.albedo_color = Color(0.9, 0.15, 0.15)
			mat.emission_enabled = true
			mat.emission = Color(0.9, 0.15, 0.15)
		"enemy_sphere":
			mi.mesh = _sphere(0.4)
			mat.albedo_color = Color(0.7, 0.7, 0.75)
		"extend_lock_gate":
			mi.mesh = _box(Vector3(0.4, 3, 1))
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.albedo_color = Color(0.9, 0.2, 0.2, 0.5)
		"start":
			mi.mesh = _plane()
			mat.albedo_color = Color(0.2, 0.7, 1)
			mat.emission_enabled = true
			mat.emission = Color(0.2, 0.7, 1)
		"end":
			mi.mesh = _plane()
			mat.albedo_color = Color(1, 0.75, 0.2)
			mat.emission_enabled = true
			mat.emission = Color(1, 0.75, 0.2)
		_:
			mi.mesh = _box(Vector3(0.6, 0.6, 0.6))
			mat.albedo_color = Color(0.6, 0.6, 0.6)
	mi.set_surface_override_material(0, mat)
	return mi


func _ghost_mat(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = col
	return m


func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func _sphere(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	return s


func _plane() -> PlaneMesh:
	var p := PlaneMesh.new()
	p.size = Vector2(0.95, 0.95)
	return p


func _refresh() -> void:
	var id: String = _palette[_sel]
	var tname: String = ObjectRegistry.TYPES[id]["name"]
	var c := _cell()
	var shape: Vector3i = _player.get_dimensions()
	_info.text = "Cell (%d, %d)   Cube %dx%dx%d   Selected: %s [%s]\nMove/extend the cube; Q/E cycle; Enter place; X erase; F5 finish/name\n%d tiles   %d overlay   %d objects" % [
		c.x, c.y, shape.x, shape.y, shape.z, tname, id, _base.size(), _overlay.size(), _objects.size()
	]


# --- Finish / name panel: freeze the cube, name the level, write user://levels/<slug>.json ---

func _open_finish() -> void:
	_finishing = true
	_player.process_mode = Node.PROCESS_MODE_DISABLED   # freeze the cube while typing
	_name_edit.text = _level_name
	_finish_panel.show()
	_name_edit.grab_focus()
	_name_edit.select_all()


func _close_finish() -> void:
	_finishing = false
	_player.process_mode = Node.PROCESS_MODE_INHERIT
	_finish_panel.hide()


func _on_name_submitted(_text: String) -> void:
	_do_save()


func _do_save() -> void:
	var nm := _name_edit.text.strip_edges()
	if nm.is_empty():
		nm = "My Level"
	_level_name = nm
	var path := "user://levels/%s.json" % _slugify(nm)
	_write_level(path, nm)
	_close_finish()
	_info.text = "Saved \"%s\"  ->  %s" % [nm, path]


func _write_level(path: String, level_name: String) -> void:
	var data := _serialize()
	if not data.has("meta"):
		data["meta"] = {}
	data["meta"]["name"] = level_name
	DirAccess.make_dir_recursive_absolute("user://levels")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("editor: cannot write %s" % path)
		return
	f.store_string(JSON.stringify(data, "  "))
	f.close()


func _slugify(s: String) -> String:
	var out := ""
	for c in s.to_lower():
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9"):
			out += c
		elif c == " " or c == "-" or c == "_":
			out += "_"
	while out.contains("__"):
		out = out.replace("__", "_")
	out = out.lstrip("_").rstrip("_")
	if out.is_empty():
		out = "level"
	return out


func _serialize() -> Dictionary:
	var cells: Array = _base.keys() + _overlay.keys() + _objects.keys()
	if cells.is_empty():
		return {"version": 1, "base": [], "overlay": [], "objects": []}
	var minx := 1 << 30
	var minz := 1 << 30
	var maxx := -(1 << 30)
	var maxz := -(1 << 30)
	for c in cells:
		var cell: Vector2i = c
		minx = mini(minx, cell.x)
		maxx = maxi(maxx, cell.x)
		minz = mini(minz, cell.y)
		maxz = maxi(maxz, cell.y)
	var objs: Array = []
	for c in _objects:
		var cell: Vector2i = c
		var entry: Dictionary = _objects[cell]
		var o: Dictionary = {"type": entry["id"], "cell": [cell.x - minx, cell.y - minz]}
		for k in entry["params"]:
			o[k] = entry["params"][k]
		objs.append(o)
	return {
		"version": 1,
		"meta": {"size": [maxx - minx + 1, maxz - minz + 1]},
		"base": _grid_rows(_base, minx, minz, maxx, maxz),
		"overlay": _grid_rows(_overlay, minx, minz, maxx, maxz),
		"objects": objs,
		"links": [],
		"config": {},
	}


func _grid_rows(model: Dictionary, minx: int, minz: int, maxx: int, maxz: int) -> Array:
	var rows: Array = []
	for z in range(minz, maxz + 1):
		var line := ""
		for x in range(minx, maxx + 1):
			var cell := Vector2i(x, z)
			if model.has(cell):
				line += String(ObjectRegistry.TYPES[model[cell]].get("glyph", " "))
			else:
				line += " "
		rows.append(line)
	return rows
