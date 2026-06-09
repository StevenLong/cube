extends Node3D
class_name LevelEditor

# In-world level editor v2: the cursor IS the real player cube in god-mode (no fall,
# no-clip), so you drive and EXTEND it like in game. To place an extend-lock you just
# BE the shape: place captures the cube's dimensions at its cell. MODAL: Tab opens a
# tool menu; pick a type to enter its placement mode, or "None" for free control.
#   Move / extend: your usual controls    Tab: tool menu
#   Enter: place    X or Backspace: erase    F5: finish    P: playtest
# SLICE 1 of menu-first (modal). NEXT: rectangle drag (hold place + move), A = place
# with dodge suppressed, a Back-to-None shortcut, object path/param modes. Previews
# here partly mirror level_loader; both want a shared LevelBuilder.

const REAL_SCENES := ["floor", "ink", "water"]
const PLAYTEST_PATH := "user://_playtest.json"   # scratch level the Play action writes and the loader runs

# Set by a launcher before changing to editor.tscn: the level file to open ("" =
# start blank), and whether it is a built-in (saving then makes a custom copy).
static var open_path: String = ""
static var open_readonly: bool = false

@onready var _player: Node3D = $Player
@onready var _info: Label = $UI/Info
@onready var _finish_panel: Control = $UI/FinishPanel
@onready var _name_edit: LineEdit = $UI/FinishPanel/VBox/NameEdit
@onready var _save_button: Button = $UI/FinishPanel/VBox/Buttons/SaveButton
@onready var _cancel_button: Button = $UI/FinishPanel/VBox/Buttons/CancelButton
@onready var _overwrite_confirm: ConfirmationDialog = $OverwriteConfirm
@onready var _tool_menu: Control = $UI/ToolMenu
@onready var _tool_list: VBoxContainer = $UI/ToolMenu/VBox/Scroll/ToolList

var _tool := "none"              # active tool: "none" (free control) or an ObjectRegistry type id
var _menu_open := false
var _finishing := false
var _level_name := "My Level"
var _current_readonly := false
var _current_path := ""           # the file currently being edited ("" = unsaved / new)
var _pending_save_name := ""
var _pending_save_path := ""
var _base: Dictionary = {}       # Vector2i -> id
var _overlay: Dictionary = {}    # Vector2i -> id
var _objects: Dictionary = {}    # Vector2i -> { "id": String, "params": Dictionary }
var _vis: Dictionary = {}        # "layer:x,z" -> Node3D
var _status := ""                # transient one-line message (saved, playtest hints)
var _status_t := 0.0


func _ready() -> void:
	_player.god_mode = true
	_build_tool_menu()
	_save_button.pressed.connect(_do_save)
	_cancel_button.pressed.connect(_close_finish)
	_name_edit.text_submitted.connect(_on_name_submitted)
	_overwrite_confirm.confirmed.connect(_confirm_overwrite)
	_finish_panel.hide()
	_tool_menu.hide()
	if open_path != "":
		_load_level(open_path, open_readonly)
		open_path = ""
	_refresh()


func _process(delta: float) -> void:
	if _status_t > 0.0:
		_status_t -= delta
		if _status_t <= 0.0:
			_status = ""
	_refresh()  # keep the readout live as the cube moves


func _unhandled_input(event: InputEvent) -> void:
	if _overwrite_confirm.visible:
		return   # the overwrite dialog owns input
	if _menu_open:
		# the tool menu owns input while open; Esc/B closes it
		if event.is_action_pressed("ui_cancel"):
			_close_menu()
			get_viewport().set_input_as_handled()
		return
	if _finishing:
		# the name panel owns input while open; Esc cancels it, not the editor
		if event.is_action_pressed("ui_cancel"):
			_close_finish()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("pause"):
		get_tree().change_scene_to_file("res://main_menu.tscn")
		return
	if event.is_action_pressed("editor_menu"):
		_open_menu()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ENTER:
				_place()
			KEY_X, KEY_BACKSPACE:
				_erase()
			KEY_F5:
				_open_finish()
			KEY_P:
				_enter_play()


func _cell() -> Vector2i:
	return _player.grid_pos


func _place() -> void:
	if _tool == "none":
		return
	match ObjectRegistry.TYPES[_tool]["kind"]:
		ObjectRegistry.Kind.BASE_TILE:
			_stamp_tile(_base, "base", _tool)
		ObjectRegistry.Kind.OVERLAY_TILE:
			_stamp_tile(_overlay, "overlay", _tool)
		ObjectRegistry.Kind.OBJECT:
			_stamp_object(_tool)
	_refresh()


func _stamp_tile(model: Dictionary, layer: String, id: String) -> void:
	# Paint-mode tiles use the cube as a footprint-shaped stamp: the whole extended
	# base paints at once. Single-mode tiles (start/end) drop one cell at the cursor.
	var cells: Array = _footprint_cells() if ObjectRegistry.TYPES[id].get("paint_mode", "single") == "paint" else [_cell()]
	for cell: Vector2i in cells:
		_stamp_tile_cell(model, layer, id, cell)


func _stamp_tile_cell(model: Dictionary, layer: String, id: String, cell: Vector2i) -> void:
	var key := "%s:%d,%d" % [layer, cell.x, cell.y]
	_clear_vis(key)
	model[cell] = id
	var node := _make_visual(id, cell)
	if node != null:
		add_child(node)
		_vis[key] = node


func _footprint_cells() -> Array:
	# The cells the cube's base currently covers: one when compact, the whole
	# extended footprint otherwise. Reuses the player's own footprint math.
	var min_c: Vector2i = _player.get_footprint_min()
	var dims: Vector3i = _player.get_dimensions()
	var cells: Array = []
	for x in range(min_c.x, min_c.x + dims.x):
		for z in range(min_c.y, min_c.y + dims.z):
			cells.append(Vector2i(x, z))
	return cells


func _stamp_object(id: String) -> void:
	# BE-the-shape: the lock captures the cube's current dimensions; others drop at
	# the cube's cell with default params.
	var params: Dictionary = {}
	if id == "extend_lock_zone":
		var dims: Vector3i = _player.get_dimensions()
		params = {"mode": "lock", "required_dims": [dims.x, dims.y, dims.z]}
	_stamp_object_at(id, _cell(), params)


func _stamp_object_at(id: String, cell: Vector2i, params: Dictionary) -> void:
	var key := "object:%d,%d" % [cell.x, cell.y]
	_clear_vis(key)
	_objects[cell] = {"id": id, "params": params}
	var node := _make_object_visual(id, params)
	node.position = Vector3(cell.x, _obj_y(id), cell.y)
	add_child(node)
	_vis[key] = node


func _erase() -> void:
	# Erase mirrors the stamp: clears the cube's whole footprint (one cell when compact).
	for cell: Vector2i in _footprint_cells():
		_erase_cell(cell)
	_refresh()


func _erase_cell(cell: Vector2i) -> void:
	# Clear the topmost occupied layer at one cell (object over overlay over base).
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
			return


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
	var c := _cell()
	var shape: Vector3i = _player.get_dimensions()
	var tag := "  (built-in copy: saving makes a new custom level)" if _current_readonly else ""
	var status_line := ("\n" + _status) if _status != "" else ""
	_info.text = "Editing: %s%s\nCell (%d, %d)   Cube %dx%dx%d   Tool: %s\nWASD move, arrows/E/Q shape; Tab menu; Enter place; X erase; F5 finish; P playtest\n%d tiles   %d overlay   %d objects%s" % [
		_level_name, tag, c.x, c.y, shape.x, shape.y, shape.z, _tool_label(_tool), _base.size(), _overlay.size(), _objects.size(), status_line
	]


# --- Tool menu (Tab): pick the active placement tool, or "None" for free control ---

func _build_tool_menu() -> void:
	_add_tool_button("none", "None (free control)")
	for id in ObjectRegistry.TYPES:
		_add_tool_button(id, String(ObjectRegistry.TYPES[id]["name"]))


func _add_tool_button(id: String, label: String) -> void:
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 34)
	b.add_theme_font_size_override("font_size", 18)
	b.text = label
	b.pressed.connect(_select_tool.bind(id))
	_tool_list.add_child(b)


func _open_menu() -> void:
	_menu_open = true
	_player.process_mode = Node.PROCESS_MODE_DISABLED   # freeze the cube while choosing
	_tool_menu.show()
	if _tool_list.get_child_count() > 0:
		(_tool_list.get_child(0) as Control).grab_focus()


func _close_menu() -> void:
	_menu_open = false
	_player.process_mode = Node.PROCESS_MODE_INHERIT
	_tool_menu.hide()


func _select_tool(id: String) -> void:
	_tool = id
	_close_menu()
	_flash("Tool: %s" % _tool_label(id))


func _tool_label(id: String) -> String:
	return "None" if id == "none" else String(ObjectRegistry.TYPES[id]["name"])


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
	var path := "user://levels/%s.json" % _slugify(nm)
	# Guard against clobbering a DIFFERENT level. Re-saving the file you opened
	# (same path) is expected and skips the prompt.
	if path != _current_path and FileAccess.file_exists(path):
		_pending_save_name = nm
		_pending_save_path = path
		_overwrite_confirm.dialog_text = "A level named \"%s\" already exists. Overwrite it?" % nm
		_overwrite_confirm.popup_centered()
		return
	_write_and_finish(path, nm)


func _confirm_overwrite() -> void:
	_write_and_finish(_pending_save_path, _pending_save_name)


func _write_and_finish(path: String, nm: String) -> void:
	_level_name = nm
	_write_level(path, nm)
	_current_path = path
	_current_readonly = false   # now editing the saved custom file
	_close_finish()
	_flash("Saved \"%s\"" % nm)


func _flash(msg: String) -> void:
	_status = msg
	_status_t = 3.0


func _enter_play() -> void:
	# Scene-swap playtest: serialize the current level to a scratch file and launch
	# the real game pipeline (painted_level + level_loader). Esc there returns here.
	if not ("start" in _base.values()):
		_flash("Place a Start tile before playtesting")
		return
	if not ("end" in _base.values()):
		_flash("Place an End tile before playtesting")
		return
	var data := _serialize()
	if not data.has("meta"):
		data["meta"] = {}
	data["meta"]["name"] = _level_name
	var f := FileAccess.open(PLAYTEST_PATH, FileAccess.WRITE)
	if f == null:
		_flash("Could not start playtest")
		return
	f.store_string(JSON.stringify(data, "  "))
	f.close()
	LevelLoader.requested_file = PLAYTEST_PATH
	LevelLoader.return_to_editor = true
	get_tree().change_scene_to_file("res://painted_level.tscn")


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


# --- Load an existing level back into the editor (inverse of _serialize) ---

func _load_level(path: String, readonly: bool) -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (data is Dictionary):
		push_error("editor: cannot parse level %s" % path)
		return
	_clear_all()
	_load_grid(data.get("base", []), ObjectRegistry.glyph_to_id(ObjectRegistry.Kind.BASE_TILE), _base, "base")
	_load_grid(data.get("overlay", []), ObjectRegistry.glyph_to_id(ObjectRegistry.Kind.OVERLAY_TILE), _overlay, "overlay")
	for o in data.get("objects", []):
		if o is Dictionary and o.has("type") and o.has("cell"):
			var c: Array = o["cell"]
			var params: Dictionary = {}
			for k in o:
				if k != "type" and k != "cell":
					params[k] = o[k]
			_stamp_object_at(String(o["type"]), Vector2i(int(c[0]), int(c[1])), params)
	var base_name := str((data.get("meta", {}) as Dictionary).get("name", "My Level"))
	_level_name = (base_name + " (copy)") if readonly else base_name
	_current_readonly = readonly
	_current_path = path


func _load_grid(rows: Array, glyphs: Dictionary, model: Dictionary, layer: String) -> void:
	for z in range(rows.size()):
		var row := String(rows[z])
		for x in range(row.length()):
			var g := row[x]
			if g != " " and glyphs.has(g):
				_stamp_tile_cell(model, layer, glyphs[g], Vector2i(x, z))


func _clear_all() -> void:
	for key in _vis:
		_vis[key].queue_free()
	_vis.clear()
	_base.clear()
	_overlay.clear()
	_objects.clear()
