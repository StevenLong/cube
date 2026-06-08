extends Control


const LEVEL1 := "res://levels/data/level_01.json"
const USER_DIR := "user://levels"

@onready var _vbox: VBoxContainer = $VBox
@onready var _level1_button: Button = $VBox/Level1Button
@onready var _back_button: Button = $VBox/BackButton


func _ready() -> void:
	_level1_button.pressed.connect(_play.bind(LEVEL1))
	_build_user_levels()
	_back_button.pressed.connect(_load.bind("res://main_menu.tscn"))
	_level1_button.grab_focus()


# One button per user-made level (user://levels/*.json), labelled by its meta.name,
# inserted just above Back. Built in code so the list tracks whatever the editor saved.
func _build_user_levels() -> void:
	for path in _user_level_files():
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(0, 48)
		btn.add_theme_font_size_override("font_size", 22)
		btn.text = _level_name_of(path)
		btn.pressed.connect(_play.bind(path))
		_vbox.add_child(btn)
		_vbox.move_child(btn, _back_button.get_index())   # keep Back last


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


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_load("res://main_menu.tscn")


func _load(path: String) -> void:
	get_tree().change_scene_to_file(path)
