extends Node3D

# Floor button (pressure plate): a single-cell LATCHING link SOURCE -- the latching
# complement to the momentary extend-lock. It latches ON the first frame the cube's
# footprint covers its cell and stays on for the whole run (one-shot, no un-press; a
# level restart rebuilds it). Player-only -- enemies never trigger it. An extended
# cube spanning two adjacent buttons latches both in one move, so space required
# buttons apart when authoring.
#
# It opens gates through the SAME `opens` link kind locks use: a gate polls each
# opener's is_active() (button = latched, lock = am-I-the-active-lock) and opens per
# its own require_all flag. The button is NOT a wall (plain Node3D, not named Wall*),
# so it stays out of the nav grid and the cube walks over it freely.

const COLOR_OFF := Color(0.45, 0.5, 0.6)
const COLOR_ON := Color(0.3, 0.85, 0.4)
const PLATE_SIZE := 0.8
const TOP_OFF := 0.08          # plate top height above the floor when unpressed
const TOP_ON := 0.02           # sinks flush-ish when latched

# Link layer: this button's per-instance id is the opener token a gate matches against
# (injected by the loader from the level's object `id`). Empty = unlinked: it still
# latches but nothing reads it.
@export var link_id := ""

var _player: Player
var _latched := false
var _plate: MeshInstance3D
var _mat: StandardMaterial3D


func _ready() -> void:
	_player = get_node("../Player") as Player
	_build_plate()


func _cell() -> Vector2i:
	return Vector2i(roundi(global_position.x), roundi(global_position.z))


func is_active() -> bool:
	return _latched


func _process(_delta: float) -> void:
	if _latched:
		return
	# Latch only once the cube has LANDED on the cell, not the instant a tumble toward it
	# starts: grid_pos jumps to the destination at tumble start, so without this guard the
	# plate would fire mid-animation. (Same rest-only check the lock zone uses.)
	if _player.is_moving():
		return
	if _player.footprint_covers(_cell()):
		_latched = true
		_apply_visual()


func _build_plate() -> void:
	var box := BoxMesh.new()
	box.size = Vector3(PLATE_SIZE, TOP_OFF, PLATE_SIZE)
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = COLOR_OFF
	_mat.emission_enabled = true
	_mat.emission = COLOR_OFF
	_mat.emission_energy_multiplier = 0.25
	_plate = MeshInstance3D.new()
	_plate.mesh = box
	_plate.material_override = _mat
	_plate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_plate)
	_apply_visual()


func _apply_visual() -> void:
	var top := TOP_ON if _latched else TOP_OFF
	(_plate.mesh as BoxMesh).size = Vector3(PLATE_SIZE, top, PLATE_SIZE)
	_plate.position.y = (top * 0.5) - global_position.y   # rests on the floor surface (y=0)
	var c := COLOR_ON if _latched else COLOR_OFF
	_mat.albedo_color = c
	_mat.emission = c
	_mat.emission_energy_multiplier = 0.6 if _latched else 0.25
