extends Control

# Tutorials menu: data-driven, one Play button per tutorial in order. Tutorials are
# shipped data levels (res://levels/data/tut_*.json) launched through the same loader
# path as the levels menu. Register a tutorial in TUTORIALS once it is promoted into
# the repo; the displayed number is its position here, so reordering is automatic.
# "Old Tutorials" opens the pre-pipeline .tscn tutorials, kept for reference only.

const TUTORIALS := [
	{"name": "Movement", "path": "res://levels/data/tut_01_movement.json"},
	{"name": "Sphere", "path": "res://levels/data/tut_02_sphere.json"},
	{"name": "Extension", "path": "res://levels/data/tut_03_extension.json"},
	{"name": "Blend", "path": "res://levels/data/tut_04_blend.json"},
	{"name": "Ink", "path": "res://levels/data/tut_05_ink.json"},
	{"name": "Dodge", "path": "res://levels/data/tut_06_dodge.json"},
	{"name": "Convergence", "path": "res://levels/data/tut_07_convergence.json"},
]

@onready var _rows: VBoxContainer = $VBox/Scroll/Rows
@onready var _old_button: Button = $VBox/OldTutorialsButton
@onready var _back_button: Button = $VBox/BackButton

var _first_button: Button = null


func _ready() -> void:
	_build_list()
	_old_button.pressed.connect(_load.bind("res://old_tutorials_menu.tscn"))
	_back_button.pressed.connect(_load.bind("res://main_menu.tscn"))
	if _first_button != null:
		_first_button.grab_focus()
	else:
		_old_button.grab_focus()


func _build_list() -> void:
	if TUTORIALS.is_empty():
		var empty := Label.new()
		empty.text = "No tutorials yet."
		empty.add_theme_font_size_override("font_size", 18)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
		_rows.add_child(empty)
		return
	for i in TUTORIALS.size():
		var t: Dictionary = TUTORIALS[i]
		var b := Button.new()
		b.custom_minimum_size = Vector2(0, 48)
		b.add_theme_font_size_override("font_size", 22)
		b.text = "%d: %s" % [i + 1, t["name"]]
		b.pressed.connect(_play.bind(t["path"]))
		_rows.add_child(b)
		if _first_button == null:
			_first_button = b


func _play(level_file: String) -> void:
	LevelLoader.requested_file = level_file
	_load("res://painted_level.tscn")


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_load("res://main_menu.tscn")


func _load(path: String) -> void:
	get_tree().change_scene_to_file(path)
