extends Control


@onready var _level1_button: Button = $VBox/Level1Button
@onready var _back_button: Button = $VBox/BackButton


func _ready() -> void:
	_level1_button.pressed.connect(_load.bind("res://painted_level.tscn"))
	_back_button.pressed.connect(_load.bind("res://main_menu.tscn"))
	_level1_button.grab_focus()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_load("res://main_menu.tscn")


func _load(path: String) -> void:
	get_tree().change_scene_to_file(path)
