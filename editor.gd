extends Node3D

# In-world level editor: the cube is a god-mode CURSOR (no falling, floats over the
# void). A palette of ObjectRegistry types is stamped at the cursor's cell, building
# a JSON-format level (SPEC_object_anatomy.md).
#   Move: your move keys / dpad (one cell per press)   Q / E: cycle type
#   Enter or Space: place   X or Backspace: erase   F5: save
# FIRST PASS: single-cell placement only. NEXT: area-select bulk (switch the cursor
# to a resizable selection on bulk start), play-mode toggle, load, the menu hook.
# NOTE: object previews and the tile y-offsets here partly mirror level_loader; both
# want a shared LevelBuilder so the edit view matches the game exactly (no drift).
# Scripted game objects (enemy/lock/gate) need a Player sibling, so in edit mode they
# render as lightweight previews; the inert tile scenes are instantiated for real.

const SAVE_PATH := "res://levels/data/editor_test.json"
const REAL_SCENES := ["floor", "ink", "water"]   # scriptless, safe to instantiate here

@onready var _cursor: Node3D = $Cursor
@onready var _camera: Camera3D = $Camera3D
@onready var _info: Label = $UI/Info

var _cell := Vector2i.ZERO
var _target := Vector3(0, 0.5, 0)
var _palette: Array = []
var _sel := 0
var _base: Dictionary = {}       # Vector2i -> id
var _overlay: Dictionary = {}    # Vector2i -> id
var _objects: Dictionary = {}    # Vector2i -> id  (one object per cell, first pass)
var _vis: Dictionary = {}        # "layer:x,z" -> Node3D


func _ready() -> void:
	_palette = ObjectRegistry.TYPES.keys()
	_refresh()


func _process(delta: float) -> void:
	_cursor.position = _cursor.position.lerp(_target, minf(delta * 14.0, 1.0))
	var focus: Vector3 = _cursor.position
	_camera.position = focus + Vector3(0, 9, 9)
	_camera.look_at(focus, Vector3.UP)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("move_left"):
		_move(Vector2i(-1, 0))
	elif event.is_action_pressed("move_right"):
		_move(Vector2i(1, 0))
	elif event.is_action_pressed("move_forward"):
		_move(Vector2i(0, -1))
	elif event.is_action_pressed("move_back"):
		_move(Vector2i(0, 1))
	elif event is InputEventKey and event.pressed and not event.echo:
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
				_save()


func _move(dir: Vector2i) -> void:
	_cell += dir
	_target = Vector3(_cell.x, 0.5, _cell.y)
	_refresh()


func _cycle(d: int) -> void:
	_sel = wrapi(_sel + d, 0, _palette.size())
	_refresh()


func _place() -> void:
	var id: String = _palette[_sel]
	match ObjectRegistry.TYPES[id]["kind"]:
		ObjectRegistry.Kind.BASE_TILE:
			_stamp(_base, "base", id)
		ObjectRegistry.Kind.OVERLAY_TILE:
			_stamp(_overlay, "overlay", id)
		ObjectRegistry.Kind.OBJECT:
			_stamp(_objects, "object", id)
	_refresh()


func _stamp(model: Dictionary, layer: String, id: String) -> void:
	var key := "%s:%d,%d" % [layer, _cell.x, _cell.y]
	if _vis.has(key):
		_vis[key].queue_free()
		_vis.erase(key)
	model[_cell] = id
	var node := _make_visual(id)
	if node != null:
		add_child(node)
		_vis[key] = node


func _erase() -> void:
	for layer in ["object", "overlay", "base"]:
		var key := "%s:%d,%d" % [layer, _cell.x, _cell.y]
		if _vis.has(key):
			_vis[key].queue_free()
			_vis.erase(key)
			match layer:
				"object":
					_objects.erase(_cell)
				"overlay":
					_overlay.erase(_cell)
				"base":
					_base.erase(_cell)
			break
	_refresh()


func _make_visual(id: String) -> Node3D:
	if id in REAL_SCENES:
		var n: Node3D = ObjectRegistry.scene_for(id).instantiate()
		n.position = Vector3(_cell.x, (-1.0 if id == "floor" else 0.01), _cell.y)
		return n
	if id == "void":
		return null
	return _preview_mesh(id)


func _preview_mesh(id: String) -> Node3D:
	var mi := MeshInstance3D.new()
	var mat := StandardMaterial3D.new()
	var y := 0.5
	match id:
		"tall_wall":
			mi.mesh = _box(Vector3(1, 1, 1))
			mat.albedo_color = Color(0.4, 0.4, 0.5)
		"safety_edge":
			mi.mesh = _box(Vector3(1, 0.1, 1))
			y = 0.05
			mat.albedo_color = Color(0.9, 0.15, 0.15)
			mat.emission_enabled = true
			mat.emission = Color(0.9, 0.15, 0.15)
		"enemy_sphere":
			mi.mesh = _sphere(0.4)
			y = 0.4
			mat.albedo_color = Color(0.7, 0.7, 0.75)
		"extend_lock_gate":
			mi.mesh = _box(Vector3(0.4, 3, 1))
			y = 1.5
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.albedo_color = Color(0.9, 0.2, 0.2, 0.5)
		"extend_lock_zone":
			mi.mesh = _box(Vector3(0.9, 0.9, 0.9))
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.albedo_color = Color(0.85, 0.5, 0.15, 0.5)
		"start":
			mi.mesh = _plane()
			y = 0.02
			mat.albedo_color = Color(0.2, 0.7, 1)
			mat.emission_enabled = true
			mat.emission = Color(0.2, 0.7, 1)
		"end":
			mi.mesh = _plane()
			y = 0.02
			mat.albedo_color = Color(1, 0.75, 0.2)
			mat.emission_enabled = true
			mat.emission = Color(1, 0.75, 0.2)
		_:
			mi.mesh = _box(Vector3(0.6, 0.6, 0.6))
			mat.albedo_color = Color(0.6, 0.6, 0.6)
	mi.set_surface_override_material(0, mat)
	mi.position = Vector3(_cell.x, y, _cell.y)
	return mi


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
	_info.text = "Cell (%d, %d)    Selected: %s  [%s]\nMove: your move keys    Q/E: cycle    Enter: place    X: erase    F5: save\n%d tiles   %d overlay   %d objects" % [
		_cell.x, _cell.y, tname, id, _base.size(), _overlay.size(), _objects.size()
	]


func _save() -> void:
	var data := _serialize()
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_error("editor: cannot write %s" % SAVE_PATH)
		return
	f.store_string(JSON.stringify(data, "  "))
	f.close()
	_info.text = "Saved to %s" % SAVE_PATH


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
		objs.append({"type": _objects[cell], "cell": [cell.x - minx, cell.y - minz]})
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
