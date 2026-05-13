extends Node

enum State { READY, PLAYING, COMPLETE }

const PULSE_BASE := 1.5
const PULSE_AMPLITUDE := 1.0
const PULSE_RATE := 2.5
const RESTART_DELAY := 0.5

var state: State = State.READY
var moves: int = 0
var time_elapsed: float = 0.0
var spotted: bool = false

var _pulse_t: float = 0.0
var _complete_t: float = 0.0
var _pending_complete: bool = false
var _start_material: StandardMaterial3D
var _end_material: StandardMaterial3D

@onready var _player: Node3D = get_node("../Player")
@onready var _enemy: Node3D = get_node_or_null("../Enemy")
@onready var _start_tile: MeshInstance3D = get_node("../StartTile")
@onready var _end_tile: MeshInstance3D = get_node("../EndTile")
@onready var _end_area: Area3D = get_node("../EndTile/Area3D")
@onready var _ready_label: Label = get_node("../UI/ReadyLabel")
@onready var _results_panel: Control = get_node("../UI/ResultsPanel")
@onready var _result_moves: Label = get_node("../UI/ResultsPanel/VBox/Moves")
@onready var _result_time: Label = get_node("../UI/ResultsPanel/VBox/Time")
@onready var _result_spotted: Label = get_node("../UI/ResultsPanel/VBox/Spotted")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_start_material = (_start_tile.get_surface_override_material(0) as StandardMaterial3D).duplicate()
	_start_tile.set_surface_override_material(0, _start_material)
	_end_material = (_end_tile.get_surface_override_material(0) as StandardMaterial3D).duplicate()
	_end_tile.set_surface_override_material(0, _end_material)
	_player.tumbled.connect(_on_player_tumbled)
	_player.move_settled.connect(_on_player_move_settled)
	if _enemy != null:
		_enemy.entered_pursuit.connect(_on_enemy_pursuit)
	else:
		_result_spotted.hide()
	_end_area.area_entered.connect(_on_end_entered)
	_end_area.area_exited.connect(_on_end_exited)
	_enter_ready()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().paused = false
		get_tree().change_scene_to_file("res://main_menu.tscn")


func _process(delta: float) -> void:
	_pulse_t += delta
	var pulse: float = PULSE_BASE + sin(_pulse_t * PULSE_RATE) * PULSE_AMPLITUDE
	_start_material.emission_energy_multiplier = pulse
	_end_material.emission_energy_multiplier = pulse

	match state:
		State.READY:
			var move := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
			if move.length() > 0.5:
				_enter_playing()
		State.PLAYING:
			time_elapsed += delta
		State.COMPLETE:
			_complete_t += delta
			if _complete_t >= RESTART_DELAY and _restart_pressed():
				get_tree().reload_current_scene()


func _restart_pressed() -> bool:
	return (Input.is_action_just_pressed("dodge")
		or Input.is_action_just_pressed("extend")
		or Input.is_action_just_pressed("move_left")
		or Input.is_action_just_pressed("move_right")
		or Input.is_action_just_pressed("move_forward")
		or Input.is_action_just_pressed("move_back"))


func _enter_ready() -> void:
	state = State.READY
	get_tree().paused = true
	_ready_label.show()
	_results_panel.hide()


func _enter_playing() -> void:
	state = State.PLAYING
	get_tree().paused = false
	_ready_label.hide()


func _enter_complete() -> void:
	state = State.COMPLETE
	_complete_t = 0.0
	get_tree().paused = true
	_result_moves.text = "Moves: %d" % moves
	_result_time.text = "Time: %.1fs" % time_elapsed
	_result_spotted.text = "Spotted: %s" % ("Yes" if spotted else "No")
	_results_panel.show()


func _on_player_tumbled() -> void:
	if state == State.PLAYING:
		moves += 1


func _on_enemy_pursuit() -> void:
	spotted = true


func _on_end_entered(_area: Area3D) -> void:
	if state != State.PLAYING:
		return
	_pending_complete = true
	if _player.is_dodging():
		var cell := Vector2i(roundi(_end_tile.position.x), roundi(_end_tile.position.z))
		_player.truncate_dodge_to(cell)


func _on_end_exited(_area: Area3D) -> void:
	# A slide that passes through the end counts as completion (per design),
	# so don't clear pending while the player is mid-dodge. Tumbles still
	# require landing — sweep-over without landing clears as before.
	if _player.is_dodging():
		return
	_pending_complete = false


func _on_player_move_settled() -> void:
	if state == State.PLAYING and _pending_complete:
		_enter_complete()
