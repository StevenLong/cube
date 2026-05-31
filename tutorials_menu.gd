extends Control


@onready var _t1_button: Button = $VBox/Tutorial1Button
@onready var _t2_button: Button = $VBox/Tutorial2Button
@onready var _back_button: Button = $VBox/BackButton


func _ready() -> void:
	_t1_button.pressed.connect(_load.bind("res://levels/tutorial_01_move.tscn"))
	_t2_button.pressed.connect(_load.bind("res://levels/tutorial_02_gaps.tscn"))
	_back_button.pressed.connect(_load.bind("res://main_menu.tscn"))
	_t1_button.grab_focus()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_load("res://main_menu.tscn")


func _load(path: String) -> void:
	get_tree().change_scene_to_file(path)
