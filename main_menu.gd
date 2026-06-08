extends Control


@onready var _tutorials_button: Button = $VBox/TutorialsButton
@onready var _levels_button: Button = $VBox/LevelsButton
@onready var _sandbox_button: Button = $VBox/SandboxButton
@onready var _editor_button: Button = $VBox/EditorButton
@onready var _quit_button: Button = $VBox/QuitButton


func _ready() -> void:
	_tutorials_button.pressed.connect(_load.bind("res://tutorials_menu.tscn"))
	_levels_button.pressed.connect(_load.bind("res://levels_menu.tscn"))
	_sandbox_button.pressed.connect(_load.bind("res://main.tscn"))
	_editor_button.pressed.connect(_open_editor)
	_quit_button.pressed.connect(_quit)
	_tutorials_button.grab_focus()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_quit()


func _load(path: String) -> void:
	get_tree().change_scene_to_file(path)


func _open_editor() -> void:
	LevelEditor.open_path = ""   # blank canvas
	_load("res://editor.tscn")


func _quit() -> void:
	get_tree().quit()
