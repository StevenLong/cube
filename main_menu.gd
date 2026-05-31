extends Control


@onready var _tutorials_button: Button = $VBox/TutorialsButton
@onready var _sandbox_button: Button = $VBox/SandboxButton
@onready var _quit_button: Button = $VBox/QuitButton


func _ready() -> void:
	_tutorials_button.pressed.connect(_load.bind("res://tutorials_menu.tscn"))
	_sandbox_button.pressed.connect(_load.bind("res://main.tscn"))
	_quit_button.pressed.connect(_quit)
	_tutorials_button.grab_focus()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_quit()


func _load(path: String) -> void:
	get_tree().change_scene_to_file(path)


func _quit() -> void:
	get_tree().quit()
