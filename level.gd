class_name Level
extends Node

enum State { READY, PLAYING, COMPLETE, CAUGHT, FELL }

const PULSE_BASE := 1.5
const PULSE_AMPLITUDE := 1.0
const PULSE_RATE := 2.5
const RESTART_DELAY := 0.5

const FLOOR_TILE_SCENE := preload("res://FloorTile.tscn")

var state: State = State.READY
var moves: int = 0
var time_elapsed: float = 0.0
var spotted: bool = false

var _pulse_t: float = 0.0
var _complete_t: float = 0.0
var _pending_complete: bool = false
var _end_cell: Vector2i = Vector2i.ZERO
var _start_material: StandardMaterial3D
var _end_material: StandardMaterial3D
var _floor_cells: Dictionary = {}

@onready var _player: Node3D = get_node("../Player")
var _enemies: Array[Node] = []
@onready var _start_tile: MeshInstance3D = get_node("../StartTile")
@onready var _end_tile: MeshInstance3D = get_node("../EndTile")
@onready var _end_area: Area3D = get_node("../EndTile/Area3D")
@onready var _ready_label: Label = get_node("../UI/ReadyLabel")
@onready var _results_panel: Control = get_node("../UI/ResultsPanel")
@onready var _result_title: Label = get_node("../UI/ResultsPanel/VBox/Title")
@onready var _result_moves: Label = get_node("../UI/ResultsPanel/VBox/Moves")
@onready var _result_time: Label = get_node("../UI/ResultsPanel/VBox/Time")
@onready var _result_spotted: Label = get_node("../UI/ResultsPanel/VBox/Spotted")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Defer tile and edge spawning until after the scene finishes loading;
	# add_child() into the world root errors out with "Parent node is busy
	# setting up children" while scene instantiation is still in flight.
	_build_world.call_deferred()
	_start_material = (_start_tile.get_surface_override_material(0) as StandardMaterial3D).duplicate()
	_start_tile.set_surface_override_material(0, _start_material)
	_end_material = (_end_tile.get_surface_override_material(0) as StandardMaterial3D).duplicate()
	_end_tile.set_surface_override_material(0, _end_material)
	_end_cell = Vector2i(roundi(_end_tile.position.x), roundi(_end_tile.position.z))
	_player.tumbled.connect(_on_player_tumbled)
	_player.move_settled.connect(_on_player_move_settled)
	_player.caught.connect(_on_player_caught)
	_player.fell.connect(_on_player_fell)
	# Wire every enemy in the scene (any sibling exposing entered_pursuit) so the
	# Spotted readout reflects all guards, not just one. Backward compatible with
	# single-enemy scenes and the no-enemy tutorials.
	for child in get_parent().get_children():
		if child.has_signal("entered_pursuit"):
			_enemies.append(child)
			child.entered_pursuit.connect(_on_enemy_pursuit)
	if _enemies.is_empty():
		_result_spotted.hide()
	_end_area.area_entered.connect(_on_end_entered)
	_end_area.area_exited.connect(_on_end_exited)
	_enter_ready()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		get_tree().paused = false
		if LevelLoader.return_to_editor:
			# Came from the editor's playtest: go back to editing this level.
			LevelLoader.return_to_editor = false
			LevelEditor.open_path = LevelLoader.requested_file
			LevelEditor.open_readonly = false
			get_tree().change_scene_to_file("res://editor.tscn")
		else:
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
		State.COMPLETE, State.CAUGHT, State.FELL:
			_complete_t += delta
			if _complete_t >= RESTART_DELAY and _restart_pressed():
				get_tree().reload_current_scene()


func _restart_pressed() -> bool:
	return (Input.is_action_just_pressed("dodge")
		or Input.is_action_just_pressed("extend_up")
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
	_result_title.text = "Level Complete"
	_result_moves.text = "Moves: %d" % moves
	_result_time.text = "Time: %.1fs" % time_elapsed
	_result_spotted.text = "Spotted: %s" % ("Yes" if spotted else "No")
	if not _enemies.is_empty():
		_result_spotted.show()
	_results_panel.show()


func _enter_caught() -> void:
	state = State.CAUGHT
	_complete_t = 0.0
	get_tree().paused = true
	_result_title.text = "Caught"
	_result_moves.text = "Moves: %d" % moves
	_result_time.text = "Time: %.1fs" % time_elapsed
	_result_spotted.hide()
	_results_panel.show()


func _enter_fell() -> void:
	state = State.FELL
	_complete_t = 0.0
	get_tree().paused = true
	_result_title.text = "Fell"
	_result_moves.text = "Moves: %d" % moves
	_result_time.text = "Time: %.1fs" % time_elapsed
	_result_spotted.hide()
	_results_panel.show()


func _on_player_tumbled() -> void:
	if state == State.PLAYING:
		moves += 1


func _on_enemy_pursuit() -> void:
	spotted = true


func _on_player_caught() -> void:
	if state == State.PLAYING:
		_enter_caught()


func _on_player_fell() -> void:
	if state == State.PLAYING:
		_enter_fell()


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
	# Pending covers the cube/dodge path (EndTile Area3D overlaps the 1x1 base cell).
	# The footprint check adds the extended case: a cuboid whose base cell is off the
	# end tile but whose footprint covers it still completes, matching extend-lock
	# UNLOCK semantics (covers, not fully on).
	if state != State.PLAYING:
		return
	if _pending_complete or _player.footprint_covers(_end_cell):
		_enter_complete()


func is_floor(cell: Vector2i) -> bool:
	return _floor_cells.has(cell)


func get_floor_bounds() -> Rect2i:
	# Tight rect around every floor cell, or empty if there is no floor. Used for
	# debug and any system that needs a quick reach estimate.
	if _floor_cells.is_empty():
		return Rect2i()
	var first: Vector2i = _floor_cells.keys()[0]
	var minx: int = first.x
	var maxx: int = first.x
	var minz: int = first.y
	var maxz: int = first.y
	for cell in _floor_cells.keys():
		var c: Vector2i = cell
		minx = mini(minx, c.x)
		maxx = maxi(maxx, c.x)
		minz = mini(minz, c.y)
		maxz = maxi(maxz, c.y)
	return Rect2i(minx, minz, maxx - minx + 1, maxz - minz + 1)


func _build_world() -> void:
	# Deferred from _ready: if the scene was torn down (or swapped) before this
	# runs, the node is out of the tree and get_tree() is null. Bail rather than
	# crash; a vanishing scene has nothing to build. Safety-edge red lines are now
	# owned by the safety_edge object (level_loader), not auto-derived here.
	if not is_inside_tree():
		return
	_build_floor()


func _build_floor() -> void:
	# Resolve floor cells from FloorRect/FloorMissing config nodes and any
	# pre-placed FloorTile instances, then spawn missing tiles. Pre-placed tiles
	# override FloorMissing (you can fill back into a carved hole). Tiles are
	# snap-positioned so the top sits at y=0 even if a designer dragged off-grid.
	_floor_cells.clear()
	var root: Node = get_parent()

	for child in root.get_children():
		if child is FloorRect:
			var r: Rect2i = (child as FloorRect).cell_rect()
			for x in range(r.position.x, r.position.x + r.size.x):
				for z in range(r.position.y, r.position.y + r.size.y):
					_floor_cells[Vector2i(x, z)] = true

	for child in root.get_children():
		if child is FloorMissing:
			var r: Rect2i = (child as FloorMissing).cell_rect()
			for x in range(r.position.x, r.position.x + r.size.x):
				for z in range(r.position.y, r.position.y + r.size.y):
					_floor_cells.erase(Vector2i(x, z))

	var pre_placed: Dictionary = {}
	for tile in get_tree().get_nodes_in_group("floor_tiles"):
		var t: Node3D = tile
		var cell := Vector2i(roundi(t.position.x), roundi(t.position.z))
		t.position = Vector3(cell.x, -1.0, cell.y)
		_floor_cells[cell] = true
		pre_placed[cell] = true

	for cell in _floor_cells.keys():
		if pre_placed.has(cell):
			continue
		var tile: Node3D = FLOOR_TILE_SCENE.instantiate()
		tile.position = Vector3(cell.x, -1.0, cell.y)
		root.add_child(tile)
