extends Control


@onready var _vbox: Control = $VBox
@onready var _tutorials_button: Button = $VBox/TutorialsButton
@onready var _levels_button: Button = $VBox/LevelsButton
@onready var _sandbox_button: Button = $VBox/SandboxButton
@onready var _editor_button: Button = $VBox/EditorButton
@onready var _quit_button: Button = $VBox/QuitButton
@onready var _editor_menu: Control = $EditorMenu
@onready var _continue_button: Button = $EditorMenu/ContinueButton
@onready var _new_button: Button = $EditorMenu/NewButton
@onready var _edit_levels_button: Button = $EditorMenu/EditLevelsButton
@onready var _editor_back_button: Button = $EditorMenu/BackButton


func _ready() -> void:
	_tutorials_button.pressed.connect(_load.bind("res://tutorials_menu.tscn"))
	_levels_button.pressed.connect(_load.bind("res://levels_menu.tscn"))
	_sandbox_button.pressed.connect(_load.bind("res://main.tscn"))
	_editor_button.pressed.connect(_open_editor_menu)
	_quit_button.pressed.connect(_quit)
	_continue_button.pressed.connect(_continue_editor)
	_new_button.pressed.connect(_new_editor)
	_edit_levels_button.pressed.connect(_load.bind("res://levels_menu.tscn"))
	_editor_back_button.pressed.connect(_close_editor_menu)
	_tutorials_button.grab_focus()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _editor_menu.visible:
			_close_editor_menu()
		else:
			_quit()


func _load(path: String) -> void:
	get_tree().change_scene_to_file(path)


func _open_editor_menu() -> void:
	# Editor submenu: Continue (restore the auto-saved session), New, or pick a
	# level to edit (the levels menu has per-level Edit buttons).
	_continue_button.disabled = not LevelEditor.has_session()
	_vbox.hide()
	_editor_menu.show()
	if _continue_button.disabled:
		_new_button.grab_focus()
	else:
		_continue_button.grab_focus()


func _close_editor_menu() -> void:
	_editor_menu.hide()
	_vbox.show()
	_editor_button.grab_focus()


func _continue_editor() -> void:
	LevelEditor.open_session = true
	_load("res://editor.tscn")


func _new_editor() -> void:
	LevelEditor.open_path = ""   # blank canvas
	LevelEditor.open_session = false
	_load("res://editor.tscn")


func _quit() -> void:
	get_tree().quit()
