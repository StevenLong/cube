extends Control

# Levels menu: one row per level (a Play button labelled by name, an Edit button,
# and a Delete button for custom levels only). Built-ins (shipped levels, and later
# tutorials) are never deletable; opening one in the editor is read-only, so saving
# there writes a new custom copy and never touches the shipped file.

const BUILTINS := [
	{"name": "Crossing", "path": "res://levels/data/level_01.json"},
]
const USER_DIR := "user://levels"

@onready var _rows: VBoxContainer = $VBox/Scroll/Rows
@onready var _back_button: Button = $VBox/BackButton
@onready var _confirm: ConfirmationDialog = $ConfirmDelete

var _pending_delete := ""
var _first_button: Button = null


func _ready() -> void:
	_confirm.confirmed.connect(_do_delete)
	_build_list()
	_back_button.pressed.connect(_load.bind("res://main_menu.tscn"))
	if _first_button != null:
		_first_button.grab_focus()
	else:
		_back_button.grab_focus()


func _build_list() -> void:
	for b in BUILTINS:
		_add_row(b["name"], b["path"], false)
	for path in _user_level_files():
		_add_row(_level_name_of(path), path, true)


func _add_row(level_name: String, path: String, deletable: bool) -> void:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 48)
	row.add_theme_constant_override("separation", 8)

	var play := Button.new()
	play.custom_minimum_size = Vector2(0, 48)
	play.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	play.add_theme_font_size_override("font_size", 22)
	play.text = level_name
	play.pressed.connect(_play.bind(path))
	row.add_child(play)
	if _first_button == null:
		_first_button = play

	var edit := Button.new()
	edit.custom_minimum_size = Vector2(80, 48)
	edit.add_theme_font_size_override("font_size", 18)
	edit.text = "Edit"
	edit.pressed.connect(_edit.bind(path, not deletable))
	row.add_child(edit)

	if deletable:
		var del := Button.new()
		del.custom_minimum_size = Vector2(80, 48)
		del.add_theme_font_size_override("font_size", 18)
		del.text = "Delete"
		del.pressed.connect(_ask_delete.bind(path, level_name))
		row.add_child(del)

	_rows.add_child(row)


func _user_level_files() -> Array:
	var out: Array = []
	var d := DirAccess.open(USER_DIR)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".json"):
			out.append(USER_DIR + "/" + f)
	out.sort()
	return out


func _level_name_of(path: String) -> String:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if data is Dictionary and data.get("meta") is Dictionary and data["meta"].has("name"):
		return str(data["meta"]["name"])
	return path.get_file().get_basename()


func _play(level_file: String) -> void:
	LevelLoader.requested_file = level_file
	_load("res://painted_level.tscn")


func _edit(path: String, readonly: bool) -> void:
	LevelEditor.open_path = path
	LevelEditor.open_readonly = readonly
	_load("res://editor.tscn")


func _ask_delete(path: String, level_name: String) -> void:
	_pending_delete = path
	_confirm.dialog_text = "Delete \"%s\"? This cannot be undone." % level_name
	_confirm.popup_centered()


func _do_delete() -> void:
	if _pending_delete == "":
		return
	var d := DirAccess.open(USER_DIR)
	if d != null:
		d.remove(_pending_delete.get_file())
	_pending_delete = ""
	_load("res://levels_menu.tscn")   # rebuild the list


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not _confirm.visible:
		_load("res://main_menu.tscn")


func _load(path: String) -> void:
	get_tree().change_scene_to_file(path)
