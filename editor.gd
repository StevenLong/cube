extends Node3D
class_name LevelEditor

# In-world level editor v2: the cursor IS the real player cube in god-mode (no fall,
# no-clip), so you drive and EXTEND it like in game. To place an extend-lock you just
# BE the shape: place captures the cube's dimensions at its cell. MODAL: Tab opens a
# tool menu; pick a type to enter its placement mode, or "None" for free control.
#   Move / extend: your usual controls    Tab: tool menu
#   Enter/A: place (hold = rect)    B/X/Backspace: erase (hold = rect)    F5: finish    P: playtest
# Slices 1-4 done: modal tool menu, rectangle drag fill, controller place/erase,
# objects (patrol-path authoring, lock/unlock zone variants). Previews here partly
# mirror level_loader; both want a shared LevelBuilder.

const REAL_SCENES := ["floor", "ink", "water"]
# Puzzle-wizard stage sequences. The lock wizard places lock(s) -> gate(s) -> unlock(s);
# the button wizard is the same grouped-sequence flow minus the unlock stage (a latching
# button needs no re-seat). Both share the grouping, id minting, and _emit_group_links.
const WIZARD_STAGES := {
	"lock": ["lock", "gate", "unlock"],
	"button": ["button", "gate"],
}
const PLAYTEST_PATH := "user://_playtest.json"   # scratch level the Play action writes and the loader runs
const SESSION_PATH := "user://_editor_session.json"   # full editor snapshot: written on every exit (menu or playtest), restored by Continue and the playtest return

# Set by a launcher before changing to editor.tscn: the level file to open ("" =
# start blank), and whether it is a built-in (saving then makes a custom copy).
# open_session wins over open_path: restore the last exited editor state instead.
static var open_path: String = ""
static var open_readonly: bool = false
static var open_session: bool = false


static func has_session() -> bool:
	return FileAccess.file_exists(SESSION_PATH)

@onready var _player: Node3D = $Player
@onready var _info: Label = $UI/Info
@onready var _finish_panel: Control = $UI/FinishPanel
@onready var _name_edit: LineEdit = $UI/FinishPanel/VBox/NameEdit
@onready var _save_button: Button = $UI/FinishPanel/VBox/Buttons/SaveButton
@onready var _cancel_button: Button = $UI/FinishPanel/VBox/Buttons/CancelButton
@onready var _overwrite_confirm: ConfirmationDialog = $OverwriteConfirm
@onready var _tool_menu: Control = $UI/ToolMenu
@onready var _tool_list: VBoxContainer = $UI/ToolMenu/VBox/Scroll/ToolList
@onready var _grid_ref: MeshInstance3D = $GridRef
@onready var _command_menu: Control = $UI/CommandMenu
@onready var _cmd_resume: Button = $UI/CommandMenu/VBox/ResumeButton
@onready var _cmd_playtest: Button = $UI/CommandMenu/VBox/PlaytestButton
@onready var _cmd_save: Button = $UI/CommandMenu/VBox/SaveButton
@onready var _cmd_quit: Button = $UI/CommandMenu/VBox/QuitButton

var _tool := "none"              # active tool: "none" (free control) or an ObjectRegistry type id
var _command_open := false       # the Start/Esc command menu (resume/playtest/save/quit) is up
var _tool_mode := "lock"         # extend_lock_zone variant chosen in the menu (lock | unlock)
var _wizard_active := false      # a puzzle wizard is guiding placement (slice 4)
var _wizard_kind := "lock"       # which wizard: "lock" or "button" (see WIZARD_STAGES)
var _wizard_stage := "lock"      # current stage within that wizard's sequence
var _wizard_group := 0           # group id stamped onto objects placed in the current puzzle
var _next_group := 0             # monotonic source of fresh group ids (session-local; not serialized)
var _path_active := false        # a patrol path is being authored (A extends it)
var _path_cell := Vector2i.ZERO  # spawn cell of the path being authored (its _objects key)
var _menu_open := false
var _dragging := false           # place held: painting a rectangle (paint tools)
var _erase_dragging := false     # erase held: clearing a rectangle (any tool)
var _place_buffered := false     # a place press that landed mid-tumble, applied on settle (N7)
var _erase_buffered := false     # an erase press that landed mid-tumble, applied on settle (N7)
var _drag_min := Vector2i.ZERO   # footprint min/max snapshot at the press corner
var _drag_max := Vector2i.ZERO
var _preview: MeshInstance3D = null
var _finishing := false
var _level_name := "My Level"
var _current_readonly := false
var _current_path := ""           # the file currently being edited ("" = unsaved / new)
var _pending_save_name := ""
var _pending_save_path := ""
var _base: Dictionary = {}       # Vector2i -> id
var _overlay: Dictionary = {}    # Vector2i -> id
var _objects: Dictionary = {}    # Vector2i -> { "id": String, "params": Dictionary, "group"?: int }
var _loaded_links: Array = []    # links from the opened file; re-emitted on save (round-trip) so loaded relationships survive an edit
var _vis: Dictionary = {}        # "layer:x,z" -> Node3D
var _status := ""                # transient one-line message (saved, playtest hints)
var _status_t := 0.0
var _warn: Label = null          # Slice 6 lint panel: level-integrity warnings, top-right corner
var _warn_t := 0.0               # recompute throttle (the readout refreshes per frame; lint must not)


func _ready() -> void:
	_player.god_mode = true
	_player.allow_dodge_in_god_mode = true   # N4: keep dodge live in the editor (under the None tool) so the dev can judge dodge distance and move faster
	_build_tool_menu()
	_save_button.pressed.connect(_do_save)
	_cancel_button.pressed.connect(_close_finish)
	_name_edit.text_submitted.connect(_on_name_submitted)
	_overwrite_confirm.confirmed.connect(_confirm_overwrite)
	_cmd_resume.pressed.connect(_close_command)
	_cmd_playtest.pressed.connect(func() -> void: _close_command(); _enter_play())
	_cmd_save.pressed.connect(func() -> void: _close_command(); _quick_save())
	_cmd_quit.pressed.connect(_quit_to_menu)
	_finish_panel.hide()
	_command_menu.hide()
	_tool_menu.hide()
	_warn = Label.new()
	_warn.name = "Warnings"
	_warn.anchor_left = 1.0
	_warn.anchor_right = 1.0
	_warn.offset_left = -520.0
	_warn.offset_top = 12.0
	_warn.offset_right = -16.0
	_warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_warn.add_theme_color_override("font_color", Color(1.0, 0.5, 0.1))
	_warn.add_theme_font_size_override("font_size", 16)
	$UI.add_child(_warn)
	if open_session:
		open_session = false
		_load_session()
	elif open_path != "":
		_load_level(open_path, open_readonly)
		open_path = ""
	_refresh()


func _process(delta: float) -> void:
	if _status_t > 0.0:
		_status_t -= delta
		if _status_t <= 0.0:
			_status = ""
	_handle_place_drag()
	_handle_erase_drag()
	# Self-heal a stuck highlight: if no drag is active, no preview should exist.
	# Catches any path where a drag ended without freeing its preview box.
	if not _dragging and not _erase_dragging and _preview != null:
		_free_preview()
	# Infinite canvas: the void grid plane trails the cube, snapped to whole
	# cells so the world-space grid lines never visibly shift.
	_grid_ref.position.x = float(roundi(_player.position.x))
	_grid_ref.position.z = float(roundi(_player.position.z))
	_refresh()  # keep the readout live as the cube moves
	_warn_t -= delta
	if _warn_t <= 0.0:
		# ponytail: editor lint on a 0.5s timer, not on every edit; a 0.5s lag on a
		# warning is fine, and it dodges per-frame serialize/BFS. Dirty flag if it lags.
		_warn_t = 0.5
		_update_warnings()


func _unhandled_input(event: InputEvent) -> void:
	if _overwrite_confirm.visible:
		return   # the overwrite dialog owns input
	if _command_open:
		# the command menu owns input while open; Esc/Start closes it
		if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
			_close_command()
			get_viewport().set_input_as_handled()
		return
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
		# Start/Esc opens the command menu (resume / playtest / save / quit) so all
		# of those work on a controller, not just keyboard F5/P.
		_open_command()
		return
	if _wizard_active and event.is_action_pressed("editor_wizard_back"):
		# Checked before editor_menu: Shift+Tab also matches plain-Tab editor_menu, so
		# handling back here first (and returning) shadows that. L3 on the controller.
		_wizard_back()
		return
	if event.is_action_pressed("editor_menu"):
		if _wizard_active:
			_wizard_advance()   # in the wizard the menu button is "next stage", not the palette
		else:
			_open_menu()
		return
	if event.is_action_pressed("editor_none"):
		if _wizard_active:
			_wizard_exit()      # finish the puzzle and drop back to free control
		else:
			_select_tool("none")
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F5:
				_open_finish()
			KEY_P:
				_enter_play()
			KEY_T:
				_toggle_gate_combinator()   # flip ANY/ALL on the gate under the cursor


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


# --- Place drag: tap = one stamp, hold + tumble = fill the rectangle (paint tiles) ---

func _handle_place_drag() -> void:
	if _menu_open or _finishing or _command_open or _overwrite_confirm.visible or _tool == "none":
		if _dragging:
			_cancel_drag()
		_place_buffered = false
		return
	# A press that arrives mid-tumble is buffered, not dropped, then fires on landing
	# at the cell the cube settles on (N7). A press while settled fires immediately.
	# Beginning only on settle still means a single tap can't place at the tumble's
	# destination before the cube lands there; it just no longer needs a re-tap.
	if Input.is_action_just_pressed("place") and not _erase_dragging and _player.is_moving():
		_place_buffered = true
	var fire_fresh: bool = Input.is_action_just_pressed("place") and not _player.is_moving()
	var fire_buffered: bool = _place_buffered and not _player.is_moving() and not _dragging
	if (fire_fresh or fire_buffered) and not _erase_dragging:
		_place_buffered = false
		_begin_place()
		# A buffered press whose button was already released mid-tumble is a tap:
		# commit it now at the landed cell. If still held, it grows a drag as usual.
		if fire_buffered and not Input.is_action_pressed("place"):
			_end_place()
	if Input.is_action_just_released("place"):
		_end_place()
	elif _dragging:
		_update_place_preview()


# --- Erase drag (B / X / Backspace): tap = clear the footprint's top layer,
# hold + move = clear the rectangle. Tool-independent; while authoring a node
# path it instead undoes the newest node. ---

func _handle_erase_drag() -> void:
	if _menu_open or _finishing or _command_open or _overwrite_confirm.visible:
		if _erase_dragging:
			_erase_dragging = false
			_free_preview()
		_erase_buffered = false
		return
	# Authoring a path: erase undoes the newest node and is always immediate, even
	# while moving. Otherwise a press is buffered if it lands mid-tumble (N7).
	if Input.is_action_just_pressed("erase") and not _dragging and not _erase_dragging:
		if _path_active:
			_pop_path_node()
			_refresh()
			return
		if _player.is_moving():
			_erase_buffered = true
		else:
			_begin_erase()
	# Drain a buffered press on landing: begin the erase, and if the button was let
	# go mid-tumble (a tap) commit it now at the cell the cube settled on.
	if _erase_buffered and not _player.is_moving() and not _dragging and not _erase_dragging:
		_erase_buffered = false
		_begin_erase()
		if not Input.is_action_pressed("erase"):
			_erase_dragging = false
			_commit_erase_rect()
			_free_preview()
	if Input.is_action_just_released("erase") and _erase_dragging:
		_erase_dragging = false
		_commit_erase_rect()
		_free_preview()
	elif _erase_dragging:
		_update_place_preview()


func _begin_erase() -> void:
	_erase_dragging = true
	var d: Vector3i = _player.get_dimensions()
	_drag_min = _player.get_footprint_min()
	_drag_max = _drag_min + Vector2i(d.x - 1, d.z - 1)
	_create_preview(Color(1.0, 0.25, 0.2, 0.3))


func _commit_erase_rect() -> void:
	var r: Array = _drag_rect()
	for x in range(r[0], r[2] + 1):
		for z in range(r[1], r[3] + 1):
			_erase_cell(Vector2i(x, z))
	_refresh()


func _is_paint_tool() -> bool:
	return _tool != "none" and ObjectRegistry.TYPES[_tool].get("paint_mode", "single") == "paint"


func _begin_place() -> void:
	_dragging = true
	var d: Vector3i = _player.get_dimensions()
	_drag_min = _player.get_footprint_min()
	_drag_max = _drag_min + Vector2i(d.x - 1, d.z - 1)
	if _is_paint_tool():
		_create_preview()
	else:
		_place()   # single tile / object: one placement on press


func _end_place() -> void:
	if not _dragging:
		return
	_dragging = false
	if _is_paint_tool():
		_commit_rect()
	_free_preview()


func _cancel_drag() -> void:
	_dragging = false
	_free_preview()


func _drag_rect() -> Array:
	# [minx, minz, maxx, maxz] spanning the press footprint and the current one, so an
	# extended (or mid-drag resized) cube widens the rectangle by its own size.
	var d: Vector3i = _player.get_dimensions()
	var cmin: Vector2i = _player.get_footprint_min()
	var cmax: Vector2i = cmin + Vector2i(d.x - 1, d.z - 1)
	return [mini(_drag_min.x, cmin.x), mini(_drag_min.y, cmin.y), maxi(_drag_max.x, cmax.x), maxi(_drag_max.y, cmax.y)]


func _commit_rect() -> void:
	var r: Array = _drag_rect()
	var kind: int = ObjectRegistry.TYPES[_tool]["kind"]
	var model: Dictionary = _base if kind == ObjectRegistry.Kind.BASE_TILE else _overlay
	var layer: String = "base" if kind == ObjectRegistry.Kind.BASE_TILE else "overlay"
	for x in range(r[0], r[2] + 1):
		for z in range(r[1], r[3] + 1):
			_stamp_tile_cell(model, layer, _tool, Vector2i(x, z))
	_refresh()


func _create_preview(color: Color = Color(0.3, 0.8, 1.0, 0.25)) -> void:
	_free_preview()   # never orphan an existing preview (would leave a stuck highlight)
	_preview = MeshInstance3D.new()
	_preview.mesh = BoxMesh.new()
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = color
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_preview.set_surface_override_material(0, m)
	add_child(_preview)
	_update_place_preview()


func _update_place_preview() -> void:
	if _preview == null:
		return
	var r: Array = _drag_rect()
	var w: int = r[2] - r[0] + 1
	var d: int = r[3] - r[1] + 1
	(_preview.mesh as BoxMesh).size = Vector3(w, 0.2, d)
	_preview.position = Vector3((r[0] + r[2]) * 0.5, 0.1, (r[1] + r[3]) * 0.5)


func _free_preview() -> void:
	if _preview != null:
		_preview.queue_free()
		_preview = null


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
	# N6: ink/water needs ground under it or it floats over the void. Painting an
	# overlay on a cell with no base lays a floor there too. Existing base tiles
	# (including start/end and walls) are left alone.
	if layer == "overlay" and not _base.has(cell):
		_stamp_tile_cell(_base, "base", "floor", cell)


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
	# Path-mode objects (patrol routes, gate fences) build node by node; the zone
	# is BE-the-shape (mode from the menu variant); others drop at the cube's cell
	# with default params.
	if String(ObjectRegistry.TYPES[id].get("paint_mode", "single")) == "path":
		_extend_path(id)
		return
	var params: Dictionary = {}
	var at := _cell()
	if id == "extend_lock_zone":
		# Capture dims AND stamp at the footprint MIN corner, which is what the
		# zone's runtime check compares against (grid_pos is the base cell and
		# diverges when extended left/fwd, which offset the ghost from the cube).
		var dims: Vector3i = _player.get_dimensions()
		at = _player.get_footprint_min()
		params = {"mode": _tool_mode, "required_dims": [dims.x, dims.y, dims.z]}
		if _tool_mode == "unlock":
			var lock_dims: Vector3i = _find_lock_dims()
			if lock_dims != Vector3i.ZERO and not _dims_permutation(dims, lock_dims):
				_flash("Warning: shape unreachable from lock %s (loader will sync)" % lock_dims)
	_stamp_object_at(id, at, params)


func _find_lock_dims() -> Vector3i:
	for c in _objects:
		var e: Dictionary = _objects[c]
		if e["id"] == "extend_lock_zone" and String(e["params"].get("mode", "lock")) == "lock":
			var rd: Array = e["params"].get("required_dims", [])
			if rd.size() >= 3:
				return Vector3i(int(rd[0]), int(rd[1]), int(rd[2]))
	return Vector3i.ZERO


func _dims_permutation(a: Vector3i, b: Vector3i) -> bool:
	# A locked shape can tumble into any axis permutation of its dims, nothing else.
	var aa: Array = [a.x, a.y, a.z]
	var bb: Array = [b.x, b.y, b.z]
	aa.sort()
	bb.sort()
	return aa == bb


# --- Node-path authoring (paint_mode "path": patrol routes and gate fences) ---
# A starts a path at the cube's cell; each further A adds a node at the current
# cell; A on the LAST node cell finishes (tap-tap in place = single-node object:
# stationary guard, lone gate post). Erase pops the newest node while authoring
# (popping the first deletes the object). Switching tool also finishes. Patrol
# routes loop in game (enemy_sphere wraps its waypoint index).

func _extend_path(id: String) -> void:
	var cell := _cell()
	if not _path_active:
		_path_active = true
		_path_cell = cell
		_stamp_object_at(id, cell, _path_start_params(id, cell))
		_flash("%s path started: A = add node, A here again = finish" % _tool_label(id))
		return
	var entry: Dictionary = _objects[_path_cell]
	var nds: Array = entry["params"][_path_key(String(entry["id"]))]
	var last: Array = nds[nds.size() - 1]
	if cell == Vector2i(int(last[0]), int(last[1])):
		_end_path()
		return
	nds.append([cell.x, cell.y])
	_refresh_object_visual(_path_cell)
	_flash("Node %d" % nds.size())


func _path_key(id: String) -> String:
	return "waypoints" if id == "enemy_sphere" else "nodes"


func _path_start_params(id: String, cell: Vector2i) -> Dictionary:
	if id == "enemy_sphere":
		return {"waypoints": [[cell.x, cell.y]], "speed": float(ObjectRegistry.default_param("enemy_sphere", "speed"))}
	# Gate: height is the one shape axis that matters (extend up first for a
	# taller fence); width/depth are the fence's own node geometry. A gate placed in
	# the button wizard carries require_all (default false = ANY) so it shows an ANY/ALL
	# tag and T can toggle it; lock-wizard gates omit it (one opener, ANY/ALL is moot).
	var p: Dictionary = {"nodes": [[cell.x, cell.y]], "height": _player.get_dimensions().y}
	if _wizard_active and _wizard_kind == "button":
		p["require_all"] = false
	return p


func _end_path() -> void:
	if not _path_active:
		return
	_path_active = false
	var entry: Dictionary = _objects[_path_cell]
	var nds: Array = entry["params"][_path_key(String(entry["id"]))]
	_flash("Path finished (%d node%s)" % [nds.size(), "" if nds.size() == 1 else "s"])


func _pop_path_node() -> void:
	var entry: Dictionary = _objects[_path_cell]
	var nds: Array = entry["params"][_path_key(String(entry["id"]))]
	nds.pop_back()
	if nds.is_empty():
		_path_active = false
		_clear_vis("object:%d,%d" % [_path_cell.x, _path_cell.y])
		_objects.erase(_path_cell)
		_flash("Path removed")
		return
	_refresh_object_visual(_path_cell)
	_flash("Node removed (%d left)" % nds.size())


func _refresh_object_visual(cell: Vector2i) -> void:
	var entry: Dictionary = _objects[cell]
	_stamp_object_at(String(entry["id"]), cell, entry["params"])


func _stamp_object_at(id: String, cell: Vector2i, params: Dictionary) -> void:
	var key := "object:%d,%d" % [cell.x, cell.y]
	_clear_vis(key)
	var entry: Dictionary = {"id": id, "params": params}
	# Group tag (slice 4): preserve it across path re-stamps (gate node add/pop);
	# otherwise a fresh lock/gate/unlock placed while the wizard guides placement
	# joins the active puzzle, so _serialize can mint ids + emit its links.
	if _objects.has(cell) and (_objects[cell] as Dictionary).has("group"):
		entry["group"] = _objects[cell]["group"]
	elif _wizard_active and (id == "extend_lock_zone" or id == "extend_lock_gate" or id == "floor_button"):
		entry["group"] = _wizard_group
	_objects[cell] = entry
	var node := _make_object_visual(id, params)
	node.position = Vector3(cell.x, _obj_y(id), cell.y)
	add_child(node)
	_vis[key] = node


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
	if id == "enemy_sphere":
		return _make_patrol_visual(params)
	if id == "extend_lock_zone":
		var d: Array = params.get("required_dims", [1, 1, 3])
		var locked := String(params.get("mode", "lock")) == "lock"
		var col := Color(0.85, 0.5, 0.15, 0.45) if locked else Color(0.3, 0.85, 0.4, 0.45)
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(d[0], d[1], d[2])
		mi.mesh = box
		mi.set_surface_override_material(0, _ghost_mat(col))
		# Centre the cuboid over the footprint (min corner at the cube's cell).
		mi.position = Vector3((d[0] - 1) * 0.5, d[1] * 0.5 - _obj_y(id), (d[2] - 1) * 0.5)
		var holder := Node3D.new()
		holder.add_child(mi)
		return holder
	if id == "extend_lock_gate":
		return _make_gate_visual(params)
	if id == "enemy_pyramid":
		return _make_pyramid_visual(params)
	return _preview_mesh(id)


func _make_pyramid_visual(params: Dictionary) -> Node3D:
	# Hovering pyramid marker + a flat coverage disc so the author sees the radius.
	var holder := Node3D.new()
	var r: float = float(params.get("radius", ObjectRegistry.default_param("enemy_pyramid", "radius")))
	var pyr := _preview_mesh("enemy_pyramid")
	pyr.position = Vector3(0, 2.0, 0)
	holder.add_child(pyr)
	var disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = r
	cyl.bottom_radius = r
	cyl.height = 0.02
	cyl.radial_segments = 40
	disc.mesh = cyl
	disc.position = Vector3(0, 0.02, 0)
	disc.set_surface_override_material(0, _ghost_mat(Color(0.4, 0.7, 1.0, 0.12)))
	holder.add_child(disc)
	return holder


func _make_gate_visual(params: Dictionary) -> Node3D:
	# Ghost fence mirroring the game build: a thin post per node, a thin panel
	# between consecutive nodes, `height` tall, relative to the first node.
	var holder := Node3D.new()
	var nds: Array = params.get("nodes", [])
	var h: float = float(params.get("height", 3))
	if nds.is_empty():
		return holder
	var origin := Vector2(float(nds[0][0]), float(nds[0][1]))
	for i in nds.size():
		var n := Vector2(float(nds[i][0]), float(nds[i][1])) - origin
		var post := MeshInstance3D.new()
		post.mesh = _box(Vector3(0.4, h, 0.4))
		post.set_surface_override_material(0, _ghost_mat(Color(0.9, 0.2, 0.2, 0.5)))
		post.position = Vector3(n.x, h * 0.5, n.y)
		holder.add_child(post)
		if i < nds.size() - 1:
			var nxt := Vector2(float(nds[i + 1][0]), float(nds[i + 1][1])) - origin
			var seg := MeshInstance3D.new()
			seg.mesh = _box(Vector3(0.2, h, n.distance_to(nxt)))
			seg.set_surface_override_material(0, _ghost_mat(Color(0.9, 0.2, 0.2, 0.35)))
			var mid := (n + nxt) * 0.5
			seg.position = Vector3(mid.x, h * 0.5, mid.y)
			seg.rotation.y = atan2(nxt.x - n.x, nxt.y - n.y)
			holder.add_child(seg)
	# Button-puzzle gates carry require_all: float an ANY/ALL tag over the first post so
	# the combinator reads at a glance. Lock gates omit the flag and show no tag.
	if params.has("require_all"):
		var tag := Label3D.new()
		tag.text = "ALL" if bool(params["require_all"]) else "ANY"
		tag.font_size = 64
		tag.pixel_size = 0.012
		tag.modulate = Color(1.0, 0.9, 0.35)
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.no_depth_test = true
		tag.position = Vector3(0, h + 0.5, 0)
		holder.add_child(tag)
	return holder


func _make_patrol_visual(params: Dictionary) -> Node3D:
	# Spawn sphere at the holder origin, a flat marker on every later waypoint, and
	# a thin floor strip between consecutive ones. All offsets are relative to the
	# spawn (waypoint 0), which is where _stamp_object_at positions the holder.
	var holder := Node3D.new()
	holder.add_child(_preview_mesh("enemy_sphere"))
	var wps: Array = params.get("waypoints", [])
	if wps.is_empty():
		return holder
	var origin := Vector2(float(wps[0][0]), float(wps[0][1]))
	for i in wps.size():
		var w := Vector2(float(wps[i][0]), float(wps[i][1])) - origin
		if i > 0:
			var marker := MeshInstance3D.new()
			marker.mesh = _box(Vector3(0.3, 0.06, 0.3))
			marker.set_surface_override_material(0, _ghost_mat(Color(0.7, 0.7, 0.75, 0.6)))
			marker.position = Vector3(w.x, -0.35, w.y)   # world ~0.05 under the 0.4 holder
			holder.add_child(marker)
		if i < wps.size() - 1:
			var nxt := Vector2(float(wps[i + 1][0]), float(wps[i + 1][1])) - origin
			holder.add_child(_make_path_segment(w, nxt))
	return holder


func _make_path_segment(a: Vector2, b: Vector2) -> MeshInstance3D:
	# Thin strip at floor level from waypoint a to b (spawn-relative XZ), rotated so
	# the box's long (z) axis runs along the segment.
	var mi := MeshInstance3D.new()
	var seg_len := a.distance_to(b)
	mi.mesh = _box(Vector3(0.08, 0.02, seg_len))
	mi.set_surface_override_material(0, _ghost_mat(Color(0.7, 0.7, 0.75, 0.35)))
	var mid := (a + b) * 0.5
	mi.position = Vector3(mid.x, -0.37, mid.y)
	mi.rotation.y = atan2(b.x - a.x, b.y - a.y)
	return mi


func _obj_y(id: String) -> float:
	match id:
		"floor":
			return -1.0
		"ink", "water":
			return 0.01
		"enemy_sphere":
			return 0.4
		"extend_lock_gate":
			return 0.0   # floor-level holder; the sized ghost centres itself
		"pitfall":
			return 0.05  # flat tile sits just above the floor plane
		"enemy_pyramid":
			return 0.0   # holder anchors on the cell; pyramid + disc offset themselves
		"floor_button":
			return 0.04  # flat plate rests just above the floor plane
		_:
			return 0.5


func _preview_mesh(id: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mat := StandardMaterial3D.new()
	match id:
		"tall_wall":
			# Match the in-game look (risen tile, static wall shader) so authoring previews true.
			mi.mesh = _box(Vector3(1, 1, 1))
			mi.set_surface_override_material(0, preload("res://wall_material.tres"))
			return mi
		"safety_edge":
			mi.mesh = _box(Vector3(1, 0.1, 1))
			mat.albedo_color = Color(0.9, 0.15, 0.15)
			mat.emission_enabled = true
			mat.emission = Color(0.9, 0.15, 0.15)
		"glass_wall":
			# Transparent cyan pane: matches the in-game glass look (see _make_glass_rect).
			mi.mesh = _box(Vector3(1, 1, 1))
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.albedo_color = Color(0.4, 0.8, 1.0, 0.25)
			mat.emission_enabled = true
			mat.emission = Color(0.4, 0.8, 1.0)
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		"pitfall":
			# Flat amber tile: matches the in-game fragile-floor look (_pitfall_mat).
			mi.mesh = _box(Vector3(1, 0.1, 1))
			mat.albedo_color = Color(0.85, 0.45, 0.1)
			mat.emission_enabled = true
			mat.emission = Color(0.85, 0.45, 0.1)
		"enemy_sphere":
			mi.mesh = _sphere(0.4)
			mat.albedo_color = Color(0.7, 0.7, 0.75)
		"enemy_pyramid":
			var cone := CylinderMesh.new()
			cone.top_radius = 0.0
			cone.bottom_radius = 0.55
			cone.height = 0.8
			cone.radial_segments = 4
			mi.mesh = cone
			mi.rotation_degrees = Vector3(180, 45, 0)
			mat.albedo_color = Color(0.4, 0.7, 1.0)
			mat.emission_enabled = true
			mat.emission = Color(0.4, 0.7, 1.0)
		"extend_lock_gate":
			mi.mesh = _box(Vector3(0.4, 3, 1))
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.albedo_color = Color(0.9, 0.2, 0.2, 0.5)
		"floor_button":
			# Flat plate matching the in-game button (floor_button.gd unpressed look).
			mi.mesh = _box(Vector3(0.8, 0.08, 0.8))
			mat.albedo_color = Color(0.45, 0.5, 0.6)
			mat.emission_enabled = true
			mat.emission = Color(0.45, 0.5, 0.6)
			mat.emission_energy_multiplier = 0.25
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
	var path_line := "\nPATH: A = add node, A on last node = finish, X/B = undo" if _path_active else ""
	var wizard_line := ""
	if _wizard_active:
		var counts: String
		if _wizard_kind == "button":
			counts = "%dB %dG" % [
				_wizard_role_cells(_wizard_group, "button").size(),
				_wizard_role_cells(_wizard_group, "gate").size()]
		else:
			counts = "%dL %dG %dU" % [
				_wizard_role_cells(_wizard_group, "lock").size(),
				_wizard_role_cells(_wizard_group, "gate").size(),
				_wizard_role_cells(_wizard_group, "unlock").size()]
		var toggle_hint := "; T ANY/ALL" if (_wizard_kind == "button" and _wizard_stage == "gate") else ""
		wizard_line = "\n%s %d  [%s stage]  %s   Tab next, Shift+Tab back, ` done; X/B erase%s" % [
			_wizard_noun().to_upper(), _wizard_group, _wizard_stage, counts, toggle_hint]
	_info.text = "Editing: %s%s\nCell (%d, %d)   Cube %dx%dx%d   Tool: %s\nWASD move, arrows/E/Q shape; Tab menu; Enter place (hold = fill); X/B erase (hold = fill); ` none; F5 finish; P playtest\n%d tiles   %d overlay   %d objects%s%s%s" % [
		_level_name, tag, c.x, c.y, shape.x, shape.y, shape.z, _tool_label(_tool), _base.size(), _overlay.size(), _objects.size(), wizard_line, path_line, status_line
	]


# --- Slice 6: editor lint panel. Surfaces level-integrity problems the explicit-links
# runtime would otherwise let ship silently (orphan gate/unlock, dead start/end, an
# unlock whose shape the lock can't tumble into, an end you can't reach). ---

func _update_warnings() -> void:
	var w := _compute_warnings()
	if w.is_empty():
		_warn.text = ""
		return
	_warn.text = "⚠ %d issue%s\n%s" % [w.size(), "" if w.size() == 1 else "s", "\n".join(w)]


func _compute_warnings() -> Array:
	var w: Array = []
	var has_start := "start" in _base.values()
	var has_end := "end" in _base.values()
	if not has_start:
		w.append("No start tile")
	if not has_end:
		w.append("No end tile")

	# Link orphans + dims mismatch off the SAME serialized links the save would emit
	# (this also mints ids onto grouped objects, idempotently, exactly as save does).
	var data := _serialize()
	var opened: Dictionary = {}     # gate id -> has an opener lock
	var released: Dictionary = {}   # unlock id -> has a releasing lock
	var lock_of: Dictionary = {}    # unlock id -> its lock id (for the shape check)
	for raw in data.get("links", []):
		var e: Dictionary = raw
		match String(e.get("kind", "")):
			"opens":
				opened[String(e.get("to", ""))] = true
			"released_by":
				released[String(e.get("to", ""))] = true
				lock_of[String(e.get("to", ""))] = String(e.get("from", ""))

	var by_id: Dictionary = {}      # link id -> object entry (for the lock-dims lookup)
	for c in _objects:
		var oid := String((_objects[c]["params"] as Dictionary).get("id", ""))
		if oid != "":
			by_id[oid] = _objects[c]

	for c in _objects:
		var ent: Dictionary = _objects[c]
		var oid := String((ent["params"] as Dictionary).get("id", ""))
		var who: String = oid if oid != "" else "at (%d,%d)" % [c.x, c.y]
		if ent["id"] == "extend_lock_gate":
			if oid == "" or not opened.has(oid):
				w.append("Gate %s has no opener (lock or button)" % who)
		elif ent["id"] == "extend_lock_zone" and String(ent["params"].get("mode", "lock")) == "unlock":
			if oid == "" or not released.has(oid):
				w.append("Unlock %s has no lock" % who)
			elif by_id.has(lock_of.get(oid, "")):
				var ud := _required_dims(ent)
				var ld := _required_dims(by_id[lock_of[oid]])
				if ud != Vector3i.ZERO and ld != Vector3i.ZERO and not _dims_permutation(ud, ld):
					w.append("Unlock %s shape %s not reachable from lock %s" % [oid, ud, ld])

	# End reachable from start, via the real traversal router (floor steps + void jumps).
	if has_start and has_end:
		var ll := LevelLoader.new()
		var parsed: Dictionary = ll._parse_base(data["base"])
		var route: Dictionary = ll._route(parsed["start"], parsed["end"], ll._walkable_cells(parsed), ll._blocked_cells(parsed))
		ll.free()
		if not route["connected"]:
			w.append("End unreachable from start")
	return w


func _required_dims(ent: Dictionary) -> Vector3i:
	var rd: Array = (ent["params"] as Dictionary).get("required_dims", [])
	return Vector3i(int(rd[0]), int(rd[1]), int(rd[2])) if rd.size() >= 3 else Vector3i.ZERO


# --- Tool menu (Tab): pick the active placement tool, or "None" for free control ---

func _build_tool_menu() -> void:
	_add_tool_button("none", "None (free control)")
	_add_wizard_button()
	for id in ObjectRegistry.TYPES:
		if id == "extend_lock_zone":
			# One type, two placement variants: mode is a param, not a separate type
			# (the file format stays type extend_lock_zone + mode, per the SPEC).
			_add_tool_button(id, "Lock Zone", "lock")
			_add_tool_button(id, "Unlock Zone", "unlock")
		else:
			_add_tool_button(id, String(ObjectRegistry.TYPES[id]["name"]))
	# Wrap focus: Down past the last entry loops to the first and vice versa, so
	# controller navigation never dead-ends at the bottom of the list.
	var n := _tool_list.get_child_count()
	if n > 1:
		var first := _tool_list.get_child(0) as Control
		var last := _tool_list.get_child(n - 1) as Control
		first.focus_neighbor_top = first.get_path_to(last)
		first.focus_previous = first.get_path_to(last)
		last.focus_neighbor_bottom = last.get_path_to(first)
		last.focus_next = last.get_path_to(first)


func _add_tool_button(id: String, label: String, variant: String = "lock") -> void:
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 34)
	b.add_theme_font_size_override("font_size", 18)
	b.text = label
	b.pressed.connect(_select_tool.bind(id, variant))
	_tool_list.add_child(b)


func _add_wizard_button() -> void:
	# The puzzle wizards are not registry types; each drives placement across its stages
	# and auto-wires the links (slice 4). Lock = lock/gate/unlock; Button = button/gate.
	_add_wizard_entry("Lock Puzzle (wizard)", "lock")
	_add_wizard_entry("Button Puzzle (wizard)", "button")


func _add_wizard_entry(label: String, kind: String) -> void:
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 34)
	b.add_theme_font_size_override("font_size", 18)
	b.text = label
	b.pressed.connect(_start_wizard.bind(kind))
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


# --- Command menu (Start/Esc): resume / playtest / save / quit, all reachable on
# a controller. Freezes the cube while open, like the tool menu (the tree is not
# paused; the editor cursor is the player). ---

func _open_command() -> void:
	_command_open = true
	_player.process_mode = Node.PROCESS_MODE_DISABLED
	_command_menu.show()
	_cmd_resume.grab_focus()


func _close_command() -> void:
	_command_open = false
	_player.process_mode = Node.PROCESS_MODE_INHERIT
	_command_menu.hide()


func _quick_save() -> void:
	# Controller-friendly save: overwrite the current file silently once it has a
	# name. A brand-new level still needs the name panel (keyboard) the first time.
	if _current_path == "":
		_open_finish()
		return
	_write_level(_current_path, _level_name)
	_current_readonly = false
	_flash("Saved \"%s\"" % _level_name)


func _quit_to_menu() -> void:
	_save_session()   # leaving never loses work; Continue restores this
	get_tree().change_scene_to_file("res://main_menu.tscn")


func _select_tool(id: String, variant: String = "lock") -> void:
	_end_path()   # switching tool commits any patrol path in progress
	_tool = id
	_tool_mode = variant
	_player.suppress_dodge = id != "none"   # placement mode: A places instead of dodging
	_close_menu()
	_flash("Tool: %s" % _tool_label(id))


func _tool_label(id: String) -> String:
	if id == "none":
		return "None"
	if id == "extend_lock_zone" and _tool_mode == "unlock":
		return "Unlock Zone"
	return String(ObjectRegistry.TYPES[id]["name"])


# --- Lock-puzzle wizard (slice 4): a grouped-sequence flow that places a puzzle's
# lock(s) -> gate(s) -> unlock(s), tags each object with the puzzle's group, and lets
# _serialize mint ids + emit all-to-all links within the group (every lock opens every
# gate, every lock is released_by every unlock). Tab = next stage (and, past unlock,
# finish this puzzle and start the next one); ` (editor_none) = finish and exit.
# Placement itself is the existing zone/gate tooling, untouched. ---

func _start_wizard(kind: String) -> void:
	_close_menu()
	_wizard_active = true
	_wizard_kind = kind
	_wizard_group = _next_group
	_next_group += 1
	_wizard_set_stage(WIZARD_STAGES[kind][0])
	_flash(_wizard_prompt())


func _wizard_set_stage(stage: String) -> void:
	_end_path()   # commit any in-progress gate fence before changing tools
	_wizard_stage = stage
	match stage:
		"lock":
			_tool = "extend_lock_zone"
			_tool_mode = "lock"
		"button":
			_tool = "floor_button"
			_tool_mode = "lock"   # mode is irrelevant for buttons (single-cell stamp)
		"gate":
			_tool = "extend_lock_gate"
			_tool_mode = "lock"   # mode is irrelevant for gates (path tool)
		"unlock":
			_tool = "extend_lock_zone"
			_tool_mode = "unlock"
	_player.suppress_dodge = true   # placement mode: A places, not dodge


func _wizard_advance() -> void:
	var stages: Array = WIZARD_STAGES[_wizard_kind]
	var i := stages.find(_wizard_stage)
	# The first stage needs at least one source (a lock/button) before advancing, so a
	# group always has something to wire its gates to.
	if i == 0 and _wizard_role_cells(_wizard_group, stages[0]).is_empty():
		_flash("Place at least one %s before advancing" % stages[0])
		return
	if i < stages.size() - 1:
		_wizard_set_stage(stages[i + 1])
	else:
		# Past the last stage: close this puzzle and open a fresh independent one.
		_wizard_group = _next_group
		_next_group += 1
		_wizard_set_stage(stages[0])
	_flash(_wizard_prompt())


func _wizard_back() -> void:
	# Step back a stage within the SAME puzzle to add more of an earlier role. Safe
	# because wiring is all-to-all per group and order-independent. Stops at the first
	# stage (no crossing into the previous puzzle).
	var stages: Array = WIZARD_STAGES[_wizard_kind]
	var i := stages.find(_wizard_stage)
	if i <= 0:
		_flash("Already at the first stage (%s)" % stages[0])
		return
	_wizard_set_stage(stages[i - 1])
	_flash(_wizard_prompt())


func _wizard_noun() -> String:
	return "Button Puzzle" if _wizard_kind == "button" else "Lock Puzzle"


func _wizard_prompt() -> String:
	var what: String = {
		"lock": "place lock zone(s)",
		"button": "place button(s)",
		"gate": "place gate(s)" + ("  [T = gate ANY/ALL]" if _wizard_kind == "button" else ""),
		"unlock": "place unlock zone(s)",
	}[_wizard_stage]
	return "%s %d: %s.  Tab = next/finish, Shift+Tab = back, ` = done" % [_wizard_noun(), _wizard_group, what]


func _wizard_exit() -> void:
	_wizard_active = false
	_select_tool("none")   # ends any path, restores dodge, drops to free control
	_flash("Lock puzzle wizard finished")


func _wizard_role_cells(group: int, role: String) -> Array:
	# Cells of _objects in this group filling the given lock role (lock | gate | unlock).
	var out: Array = []
	for c in _objects:
		var e: Dictionary = _objects[c]
		if int(e.get("group", -1)) == group and _lock_role(e) == role:
			out.append(c)
	return out


func _lock_role(entry: Dictionary) -> String:
	# The puzzle role of an object entry, or "" if it is not a puzzle component.
	var id := String(entry["id"])
	if id == "extend_lock_gate":
		return "gate"
	if id == "floor_button":
		return "button"
	if id == "extend_lock_zone":
		return "unlock" if String((entry["params"] as Dictionary).get("mode", "lock")) == "unlock" else "lock"
	return ""


func _toggle_gate_combinator() -> void:
	# Flip a gate's ANY/ALL combinator (require_all). Targets the gate whose fence covers
	# the cursor cell; only button-puzzle gates carry the flag (lock gates have one opener,
	# so ANY/ALL is moot and the flag is absent on them).
	var cell := _cell()
	for c in _objects:
		var e: Dictionary = _objects[c]
		if String(e["id"]) != "extend_lock_gate":
			continue
		var params: Dictionary = e["params"]
		if not params.has("require_all"):
			continue
		if not _gate_covered_cells(params.get("nodes", [])).has(cell):
			continue
		params["require_all"] = not bool(params["require_all"])
		_refresh_object_visual(c)
		_flash("Gate: %s" % ("ALL (every button)" if params["require_all"] else "ANY (any button)"))
		return
	_flash("Stand on a button-puzzle gate to toggle ANY/ALL")


func _gate_covered_cells(nds: Array) -> Dictionary:
	# Cells a gate fence occupies: each node cell plus the half-cell-sampled run between
	# consecutive nodes (mirrors the loader's _compute_covered), as a set for membership.
	var cov: Dictionary = {}
	for i in nds.size():
		var a := Vector2(float(nds[i][0]), float(nds[i][1]))
		cov[Vector2i(roundi(a.x), roundi(a.y))] = true
		if i < nds.size() - 1:
			var b := Vector2(float(nds[i + 1][0]), float(nds[i + 1][1]))
			var steps := maxi(1, ceili(a.distance_to(b) * 2.0))
			for s in range(steps + 1):
				var p := a.lerp(b, float(s) / float(steps))
				cov[Vector2i(roundi(p.x), roundi(p.y))] = true
	return cov


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
	# Autosave the session: "Back to Editor" (and Editor > Continue) restore it.
	# return_to_editor flags the playtest context so the in-level menus show the
	# Back to Editor button; "Quit to Menu" still goes to the main menu.
	_save_session()
	LevelLoader.requested_file = PLAYTEST_PATH
	LevelLoader.return_to_editor = true
	get_tree().change_scene_to_file("res://painted_level.tscn")


func _save_session() -> void:
	# Snapshot the whole editor state (level data plus which file it belongs to)
	# so leaving the editor, for the menu or a playtest, never loses work.
	var data := _serialize()
	if not data.has("meta"):
		data["meta"] = {}
	data["meta"]["name"] = _level_name
	data["session"] = {"current_path": _current_path, "readonly": _current_readonly}
	var f := FileAccess.open(SESSION_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(data, "  "))
	f.close()


func _load_session() -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(SESSION_PATH))
	if not (data is Dictionary):
		return
	_load_data(data)
	_level_name = str((data.get("meta", {}) as Dictionary).get("name", "My Level"))
	var sess: Dictionary = data.get("session", {})
	_current_path = str(sess.get("current_path", ""))
	_current_readonly = bool(sess.get("readonly", false))


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
	var links := _build_links()   # mints ids onto grouped objects (writes into params) BEFORE the object loop reads them
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
		for pkey in ["waypoints", "nodes"]:
			if o.has(pkey):
				# Node lists are stored in editor space; shift them by the same
				# min-corner offset as cells (into a NEW array, the live params
				# stay editor-space).
				var shifted: Array = []
				for wp in o[pkey]:
					shifted.append([int(wp[0]) - minx, int(wp[1]) - minz])
				o[pkey] = shifted
		objs.append(o)
	return {
		"version": 1,
		"meta": {"size": [maxx - minx + 1, maxz - minz + 1]},
		"base": _grid_rows(_base, minx, minz, maxx, maxz),
		"overlay": _grid_rows(_overlay, minx, minz, maxx, maxz),
		"objects": objs,
		"links": links,
		"config": {},
	}


# --- Link layer (slice 4): turn wizard group tags into the serialized `links` edge
# list, and round-trip the links the file was loaded with. ---

func _build_links() -> Array:
	# Final link list = loaded links whose endpoints still exist (pruning edges to
	# deleted objects), UNION the all-to-all links emitted from each wizard group.
	_mint_link_ids()
	var current_ids: Dictionary = {}
	for c in _objects:
		var oid := String((_objects[c]["params"] as Dictionary).get("id", ""))
		if oid != "":
			current_ids[oid] = true
	var out: Array = []
	var seen: Dictionary = {}
	for raw in _loaded_links:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var e: Dictionary = raw
		var from := String(e.get("from", ""))
		var to := String(e.get("to", ""))
		var kind := String(e.get("kind", ""))
		if from.is_empty() or to.is_empty() or kind.is_empty():
			continue
		if not current_ids.has(from) or not current_ids.has(to):
			continue   # endpoint deleted: prune the dangling edge
		var key := "%s|%s|%s" % [from, to, kind]
		if seen.has(key):
			continue
		seen[key] = true
		out.append({"from": from, "to": to, "kind": kind})
	for e in _emit_group_links():
		var key := "%s|%s|%s" % [e["from"], e["to"], e["kind"]]
		if seen.has(key):
			continue
		seen[key] = true
		out.append(e)
	return out


func _mint_link_ids() -> void:
	# Give every grouped (wizard-authored) lock/gate/unlock a stable, unique id, scanned
	# against all ids already present (loaded ids + earlier mints). Idempotent: an object
	# that already has an id keeps it, so re-saving never renames.
	var used: Dictionary = {}
	for c in _objects:
		var oid := String((_objects[c]["params"] as Dictionary).get("id", ""))
		if oid != "":
			used[oid] = true
	var counters: Dictionary = {"lock": 0, "button": 0, "gate": 0, "unlock": 0}
	for c in _objects:
		var e: Dictionary = _objects[c]
		if not e.has("group"):
			continue
		var params: Dictionary = e["params"]
		if String(params.get("id", "")) != "":
			continue
		var role := _lock_role(e)
		if role == "":
			continue
		var nid := ""
		while true:
			counters[role] += 1
			nid = "%s%d" % [role, counters[role]]
			if not used.has(nid):
				break
		used[nid] = true
		params["id"] = nid


func _emit_group_links() -> Array:
	# All-to-all OR within each group: every lock AND every button opens every gate, and
	# every lock is released_by every unlock. Groups are independent puzzles. Both locks
	# and buttons emit the same `opens` kind, so the gate's opener-poll treats them alike.
	var groups: Dictionary = {}   # group -> { "lock":[ids], "button":[ids], "gate":[ids], "unlock":[ids] }
	for c in _objects:
		var e: Dictionary = _objects[c]
		if not e.has("group"):
			continue
		var role := _lock_role(e)
		var oid := String((e["params"] as Dictionary).get("id", ""))
		if role == "" or oid == "":
			continue
		var g := int(e["group"])
		if not groups.has(g):
			groups[g] = {"lock": [], "button": [], "gate": [], "unlock": []}
		(groups[g][role] as Array).append(oid)
	var out: Array = []
	for g in groups:
		var rec: Dictionary = groups[g]
		for gt in rec["gate"]:
			for src in (rec["lock"] + rec["button"]):
				out.append({"from": src, "to": gt, "kind": "opens"})
		for lk in rec["lock"]:
			for ul in rec["unlock"]:
				out.append({"from": lk, "to": ul, "kind": "released_by"})
	return out


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
	_load_data(data)
	var base_name := str((data.get("meta", {}) as Dictionary).get("name", "My Level"))
	_level_name = (base_name + " (copy)") if readonly else base_name
	_current_readonly = readonly
	_current_path = path


func _load_data(data: Dictionary) -> void:
	_clear_all()
	# Stash the file's links so a save re-emits them (object ids already round-trip via
	# params); without this, re-saving a linked level would silently drop its relationships.
	_loaded_links = (data.get("links", []) as Array).duplicate(true)
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


func _load_grid(rows: Array, glyphs: Dictionary, model: Dictionary, layer: String) -> void:
	for z in range(rows.size()):
		var row := String(rows[z])
		for x in range(row.length()):
			var g := row[x]
			if g != " " and glyphs.has(g):
				_stamp_tile_cell(model, layer, glyphs[g], Vector2i(x, z))


func _clear_all() -> void:
	_path_active = false
	_wizard_active = false
	_loaded_links = []
	for key in _vis:
		_vis[key].queue_free()
	_vis.clear()
	_base.clear()
	_overlay.clear()
	_objects.clear()
