class_name Level
extends Node

enum State { READY, PLAYING, COMPLETE, CAUGHT, FELL, WEDGED }

const PULSE_BASE := 1.5
const PULSE_AMPLITUDE := 1.0
const PULSE_RATE := 2.5
const RESTART_DELAY := 0.5

const FLOOR_TILE_SCENE := preload("res://FloorTile.tscn")

# Any first gameplay input releases READY, not just movement: extending into a
# shape or priming a dodge are as valid an opening move as a tumble. Event-driven
# (see _input) so the starting press itself still applies the same frame.
const START_ACTIONS: Array[String] = [
	"move_left", "move_right", "move_forward", "move_back",
	"extend_left", "extend_right", "extend_fwd", "extend_back", "extend_up",
	"collapse", "dodge", "sprint",
]

var state: State = State.READY
var moves: int = 0
var time_elapsed: float = 0.0
var spotted: bool = false

var _pulse_t: float = 0.0
var _complete_t: float = 0.0
var _pause_open: bool = false
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
@onready var _result_restart: Button = get_node_or_null("../UI/ResultsPanel/VBox/RestartButton")
@onready var _result_back_button: Button = get_node_or_null("../UI/ResultsPanel/VBox/BackToEditorButton")
@onready var _result_quit: Button = get_node_or_null("../UI/ResultsPanel/VBox/QuitButton")
# Optional HUD nodes: present in level_template, absent in older hand-authored
# scenes (sandbox/tutorials), so resolve them null-safely and guard every use.
@onready var _pause_panel: Control = get_node_or_null("../UI/PausePanel")
@onready var _resume_button: Button = get_node_or_null("../UI/PausePanel/VBox/ResumeButton")
@onready var _restart_button: Button = get_node_or_null("../UI/PausePanel/VBox/RestartButton")
@onready var _pause_back_button: Button = get_node_or_null("../UI/PausePanel/VBox/BackToEditorButton")
@onready var _quit_button: Button = get_node_or_null("../UI/PausePanel/VBox/QuitButton")


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
	# The start tile is just visual noise once you've spawned; hide it. The goal
	# instead gets a tall light beacon so it reads from across a large level.
	_start_tile.visible = false
	_build_end_beacon()
	_player.tumbled.connect(_on_player_tumbled)
	_player.move_settled.connect(_on_player_move_settled)
	_player.caught.connect(_on_player_caught)
	_player.fell.connect(_on_player_fell)
	_player.wedged.connect(_on_player_wedged)
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
	# Back to Editor appears only during an editor playtest; in a normal level it
	# stays hidden (and the focus chain skips it).
	var in_playtest := LevelLoader.return_to_editor
	if _pause_panel != null:
		_resume_button.pressed.connect(_toggle_pause)
		_restart_button.pressed.connect(_restart)
		_quit_button.pressed.connect(_exit_to_menu)
		_pause_back_button.pressed.connect(_back_to_editor)
		_pause_back_button.visible = in_playtest
		_pause_panel.hide()
	if _result_restart != null:
		_result_restart.pressed.connect(_restart)
		_result_quit.pressed.connect(_exit_to_menu)
		_result_back_button.pressed.connect(_back_to_editor)
		_result_back_button.visible = in_playtest
	_enter_ready()


func _input(event: InputEvent) -> void:
	if state == State.READY and not _pause_open:
		for action in START_ACTIONS:
			if event.is_action_pressed(action):
				_enter_playing()
				break
	if event.is_action_pressed("pause"):
		# Mid-run: open the pause menu. Otherwise (ready screen, results screen, or
		# any scene without a pause panel) fall straight back to the menu.
		if _pause_panel != null and (state == State.PLAYING or _pause_open):
			_toggle_pause()
		else:
			_exit_to_menu()


func _toggle_pause() -> void:
	_pause_open = not _pause_open
	get_tree().paused = _pause_open
	_pause_panel.visible = _pause_open
	if _pause_open:
		_resume_button.grab_focus()


func _restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func _exit_to_menu() -> void:
	# Always to the main menu, including from an editor playtest. The editor
	# auto-saved its session on launch, so Editor > Continue resumes editing; this
	# keeps "Quit to Menu" meaning the same thing everywhere.
	get_tree().paused = false
	LevelLoader.return_to_editor = false
	get_tree().change_scene_to_file("res://main_menu.tscn")


func _back_to_editor() -> void:
	# Playtest-only: jump straight back to the editor with the session restored
	# (saved when the playtest launched).
	get_tree().paused = false
	LevelLoader.return_to_editor = false
	LevelEditor.open_session = true
	get_tree().change_scene_to_file("res://editor.tscn")


func _process(delta: float) -> void:
	_pulse_t += delta
	var pulse: float = PULSE_BASE + sin(_pulse_t * PULSE_RATE) * PULSE_AMPLITUDE
	_start_material.emission_energy_multiplier = pulse
	_end_material.emission_energy_multiplier = pulse

	match state:
		State.READY:
			pass   # released by any START_ACTIONS press in _input
		State.PLAYING:
			time_elapsed += delta
		State.COMPLETE, State.CAUGHT, State.FELL, State.WEDGED:
			pass   # results panel buttons (Restart / Quit) drive what happens next


func _build_end_beacon() -> void:
	# Vertical light pillar over the goal so it stands out from afar and from the
	# (now hidden) start. Translucent, unshaded, no collision; childed to the end
	# tile so it tracks the goal cell.
	var beam := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.22, 5.0, 0.22)
	beam.mesh = box
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.75, 0.2, 0.35)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.75, 0.2)
	mat.emission_energy_multiplier = 2.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam.material_override = mat
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.position = Vector3(0.0, 2.5, 0.0)
	_end_tile.add_child(beam)


func _show_results() -> void:
	_results_panel.show()
	if _result_restart != null:
		_result_restart.grab_focus()


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
	_player.clear_noise_waves()  # the tree pauses here; clear so no wave freezes on the floor
	get_tree().paused = true
	_result_title.text = "Level Complete"
	_result_moves.text = "Moves: %d" % moves
	_result_time.text = "Time: %.1fs" % time_elapsed
	_result_spotted.text = "Spotted: %s" % ("Yes" if spotted else "No")
	if not _enemies.is_empty():
		_result_spotted.show()
	_show_results()


func _enter_caught() -> void:
	state = State.CAUGHT
	_complete_t = 0.0
	_player.clear_noise_waves()
	get_tree().paused = true
	_result_title.text = "Caught"
	_result_moves.text = "Moves: %d" % moves
	_result_time.text = "Time: %.1fs" % time_elapsed
	_result_spotted.hide()
	_show_results()


func _enter_fell() -> void:
	state = State.FELL
	_complete_t = 0.0
	_player.clear_noise_waves()
	get_tree().paused = true
	_result_title.text = "Fell"
	_result_moves.text = "Moves: %d" % moves
	_result_time.text = "Time: %.1fs" % time_elapsed
	_result_spotted.hide()
	_show_results()


func _enter_wedged() -> void:
	state = State.WEDGED
	_complete_t = 0.0
	_player.clear_noise_waves()
	get_tree().paused = true
	_result_title.text = "Wedged"
	_result_moves.text = "Moves: %d" % moves
	_result_time.text = "Time: %.1fs" % time_elapsed
	_result_spotted.hide()
	_show_results()


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


func _on_player_wedged() -> void:
	if state == State.PLAYING:
		_enter_wedged()


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
