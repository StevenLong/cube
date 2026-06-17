extends Control

# The pre-pipeline tutorials: three hand-authored .tscn scenes from before the
# data-driven loader. Kept for reference only (controls and results screens are
# stale); reachable from the Tutorials menu. Safe to delete, along with the three
# levels/tutorial_*.tscn scenes, once their content is rebuilt as data levels.


@onready var _t1_button: Button = $VBox/Tutorial1Button
@onready var _t2_button: Button = $VBox/Tutorial2Button
@onready var _t3_button: Button = $VBox/Tutorial3Button
@onready var _back_button: Button = $VBox/BackButton


func _ready() -> void:
	_t1_button.pressed.connect(_load.bind("res://levels/tutorial_01_move.tscn"))
	_t2_button.pressed.connect(_load.bind("res://levels/tutorial_02_gaps.tscn"))
	_t3_button.pressed.connect(_load.bind("res://levels/tutorial_03_bridge.tscn"))
	_back_button.pressed.connect(_load.bind("res://tutorials_menu.tscn"))
	_t1_button.grab_focus()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_load("res://tutorials_menu.tscn")


func _load(path: String) -> void:
	get_tree().change_scene_to_file(path)
