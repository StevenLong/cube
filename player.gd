class_name Player
extends Node3D

signal tumbled
signal move_settled
signal noise_emitted(origin: Vector2, max_radius: float, duration: float)
signal caught

const TUMBLE_DURATION := 0.3
const SPRINT_DURATION := 0.15
const DODGE_DISTANCE := 5
const DODGE_DURATION := 0.4
const DODGE_COOLDOWN := 1.5
const WAVE_DURATION := 0.4
const KNOCK_RADIUS := 10.0  # wall-knock noise radius (knock is a cube-only ability)
const KNOCK_COOLDOWN := 0.4  # min seconds between wall knocks
const BUMP_DURATION := 0.25  # won't-fit lean-and-rock-back for a blocked extended move
const BUMP_ANGLE := PI / 10.0  # peak lean (~18 deg) before rocking back, scaled down near a wall
const BUMP_CLEARANCE := 0.15  # air gap kept between the lean's leading corner and the wall
const MAX_WAVES := 8
const MAX_FOOTPRINTS := 64
const FOOTPRINT_FADE_TIME := 12.0  # seconds for a deposited print to fade out and clear
const MAX_WALLS := 16
const SLIDE_SUBSAMPLES := 4
const FOCUS_SMOOTH_RATE := 25.0
const COLOR_NORMAL := Color(0.9, 0.9, 0.9)
const COLOR_BLENDING := Color(0.4, 0.4, 0.45)
const COLOR_MARKED := Color(0.25, 0.35, 0.55)
const COLOR_LOCKED := Color(0.85, 0.5, 0.15)  # extend-locked: committed to a forced shape

const EXT_LEFT  := 0
const EXT_RIGHT := 1
const EXT_FWD   := 2
const EXT_BACK  := 3
const EXT_UP    := 4

# Face IDs map cube-local axis directions to indices 0-5.
# Used to track which physical face is in contact with ground/puddles.
const FACE_X_POS := 0
const FACE_X_NEG := 1
const FACE_Y_POS := 2
const FACE_Y_NEG := 3
const FACE_Z_POS := 4
const FACE_Z_NEG := 5

const LAYER_ENEMY := 4
const LAYER_PUDDLE := 16

var grid_pos := Vector2i(0, 0)
var _tumbling := false
var _t := 0.0
var _pivot := Vector3.ZERO
var _axis := Vector3.ZERO
var _angle := 0.0
var _start_pos := Vector3.ZERO
var _start_basis := Basis.IDENTITY
var _dodging := false
var _dodge_t := 0.0
var _dodge_start_pos := Vector3.ZERO
var _dodge_end_pos := Vector3.ZERO
var _dodge_cooldown_t := 0.0
var _knock_cooldown_t := 0.0
var _dodge_duration := DODGE_DURATION
var _slide_dir: Vector2i = Vector2i.ZERO
var _slide_last_cell: Vector2i = Vector2i.ZERO
var _ext := [0, 0, 0, 0, 0]
var _pending_ext := [0, 0, 0, 0, 0]
var _tumble_distance := 1
var _bumping := false
var _bump_t := 0.0
var _bump_pivot := Vector3.ZERO
var _bump_axis := Vector3.ZERO
var _bump_angle := 0.0
var _smoothed_focus := Vector3.ZERO
var _dodge_held_consumed := false  # a dodge press that collapsed an extension; suppresses dodge until released
var _extend_locked := false
var is_blending := false
var _ground_material: ShaderMaterial
var _player_material: StandardMaterial3D
var _waves: Array = []
var _footprints: Array = []
var _box_mesh: BoxMesh
var _face_marks: Array[bool] = [false, false, false, false, false, false]
var _water_overlap_count: int = 0
var _ink_cells: Dictionary = {}
var _orient: Basis = Basis.IDENTITY

@onready var _step_player: AudioStreamPlayer = $StepSound
@onready var _splash_player: AudioStreamPlayer = $SplashSound
@onready var _mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var _move_cast: ShapeCast3D = $MoveCast
@onready var _detection_area: Area3D = $DetectionArea


func _ready() -> void:
	_step_player.stream = _make_step_sound()
	_splash_player.stream = _make_splash_sound()
	_ground_material = get_node("../Ground/MeshInstance3D").get_surface_override_material(0)
	_push_walls_to_shader()
	_box_mesh = _mesh_instance.mesh.duplicate() as BoxMesh
	_mesh_instance.mesh = _box_mesh
	_player_material = (_mesh_instance.get_surface_override_material(0) as StandardMaterial3D).duplicate()
	_mesh_instance.set_surface_override_material(0, _player_material)
	_smoothed_focus = _mesh_instance.global_position
	_detection_area.area_entered.connect(_on_contact)
	for puddle in get_tree().get_nodes_in_group("ink_puddles"):
		puddle.area_entered.connect(_on_puddle_entered)
	for water in get_tree().get_nodes_in_group("water_puddles"):
		water.area_entered.connect(_on_water_entered)
		water.area_exited.connect(_on_water_exited)
	_build_ink_cells()


func _build_ink_cells() -> void:
	# Record every cell an ink puddle covers, so ink contact reads off the current
	# position rather than the Area3D overlap count (which lags the render-frame
	# position lerp during a dodge and would swallow the first tiles of the trail).
	# Reads each puddle's BoxShape3D footprint, so multi-cell puddles and clusters
	# of adjacent puddles both work. Assumes axis-aligned boxes, like the walls.
	_ink_cells.clear()
	for puddle in get_tree().get_nodes_in_group("ink_puddles"):
		var area := puddle as Area3D
		if area == null:
			continue
		var center := area.global_position
		var box: BoxShape3D = null
		for child in area.get_children():
			if child is CollisionShape3D:
				center = child.global_position
				box = child.shape as BoxShape3D
				break
		if box == null:
			_ink_cells[Vector2i(roundi(center.x), roundi(center.z))] = true
			continue
		var half := box.size * 0.5
		for cx in range(ceili(center.x - half.x), floori(center.x + half.x) + 1):
			for cz in range(ceili(center.z - half.z), floori(center.z + half.z) + 1):
				_ink_cells[Vector2i(cx, cz)] = true


func _on_contact(area: Area3D) -> void:
	if (area.collision_layer & LAYER_ENEMY) != 0:
		caught.emit()


func _on_puddle_entered(area: Area3D) -> void:
	# A dodge can slide onto an ink cell between cell-transition checks; recheck on
	# overlap so the entering face still inks. Off-dodge tumbles ink on landing.
	if area == _detection_area and _dodging:
		_check_ink_contact()


func _on_water_entered(area: Area3D) -> void:
	if area == _detection_area:
		_water_overlap_count += 1
		_check_water_cleanse()


func _on_water_exited(area: Area3D) -> void:
	if area == _detection_area:
		_water_overlap_count -= 1


func _can_move(delta_world: Vector3) -> bool:
	_move_cast.target_position = delta_world
	_move_cast.force_shapecast_update()
	return not _move_cast.is_colliding()


func _can_move_cuboid(dir: Vector2i, dist: int) -> bool:
	# Tumble collision for an extended cuboid: sweep the base box along dir by dist
	# at every cell offset perpendicular to the roll, covering the cuboid's full
	# perpendicular width (a tumble preserves that width; the along-roll extent is
	# already covered by dist). Without this only the base cell is checked and the
	# extended cells clip through walls.
	var perp: Vector3
	var lo: int
	var hi: int
	if dir.x != 0:
		perp = Vector3(0.0, 0.0, 1.0)
		lo = -int(_ext[EXT_FWD])
		hi = int(_ext[EXT_BACK])
	else:
		perp = Vector3(1.0, 0.0, 0.0)
		lo = -int(_ext[EXT_LEFT])
		hi = int(_ext[EXT_RIGHT])
	var delta_world := Vector3(dir.x * dist, 0.0, dir.y * dist)
	var clear := true
	for j in range(lo, hi + 1):
		_move_cast.position = perp * float(j)
		_move_cast.target_position = delta_world
		_move_cast.force_shapecast_update()
		if _move_cast.is_colliding():
			clear = false
			break
	_move_cast.position = Vector3.ZERO
	return clear


func _is_in_cover() -> bool:
	# Blend gate: hidden when one pair of opposite footprint sides is fully walled
	# (every adjacent cell on that side is a wall). That is exactly "looks like part
	# of a flat wall": from the two open directions the cube's face lines up coplanar
	# with the flanking walls; from the walled directions it is buried. One pair is
	# enough, so an entrance-plug (two opposite sides walled, two open ends) counts.
	var minx: int = grid_pos.x - _ext[EXT_LEFT]
	var maxx: int = grid_pos.x + _ext[EXT_RIGHT]
	var minz: int = grid_pos.y - _ext[EXT_FWD]
	var maxz: int = grid_pos.y + _ext[EXT_BACK]
	if _column_walled(minx - 1, minz, maxz) and _column_walled(maxx + 1, minz, maxz):
		return true
	return _row_walled(minz - 1, minx, maxx) and _row_walled(maxz + 1, minx, maxx)


func _column_walled(x: int, z0: int, z1: int) -> bool:
	for z in range(z0, z1 + 1):
		if _extend_cell_clear(Vector2i(x, z)):
			return false
	return true


func _row_walled(z: int, x0: int, x1: int) -> bool:
	for x in range(x0, x1 + 1):
		if _extend_cell_clear(Vector2i(x, z)):
			return false
	return true


func _axis_total(side: int) -> int:
	match side:
		EXT_LEFT, EXT_RIGHT: return _ext[EXT_LEFT] + _ext[EXT_RIGHT]
		EXT_FWD, EXT_BACK:   return _ext[EXT_FWD] + _ext[EXT_BACK]
		_:                   return _ext[EXT_UP]


func _try_extend(side: int) -> void:
	if _axis_total(side) >= 2:
		return
	if not _extend_side_clear(side):
		return
	_ext[side] += 1


func _extend_side_clear(side: int) -> bool:
	# An extension may not grow into a wall. EXT_UP grows into the air (no ground
	# cells), so it is always clear; otherwise check every new footprint cell the
	# extension would add along that side.
	if side == EXT_UP:
		return true
	var minx: int = grid_pos.x - _ext[EXT_LEFT]
	var maxx: int = grid_pos.x + _ext[EXT_RIGHT]
	var minz: int = grid_pos.y - _ext[EXT_FWD]
	var maxz: int = grid_pos.y + _ext[EXT_BACK]
	match side:
		EXT_LEFT:
			for z in range(minz, maxz + 1):
				if not _extend_cell_clear(Vector2i(minx - 1, z)):
					return false
		EXT_RIGHT:
			for z in range(minz, maxz + 1):
				if not _extend_cell_clear(Vector2i(maxx + 1, z)):
					return false
		EXT_FWD:
			for x in range(minx, maxx + 1):
				if not _extend_cell_clear(Vector2i(x, minz - 1)):
					return false
		EXT_BACK:
			for x in range(minx, maxx + 1):
				if not _extend_cell_clear(Vector2i(x, maxz + 1)):
					return false
	return true


func _extend_cell_clear(cell: Vector2i) -> bool:
	# True if the cell has no wall to grow into. Queries live physics (layer 1), so
	# it respects the perimeter and the gate's current open/closed collision state.
	var space := get_world_3d().direct_space_state
	var params := PhysicsPointQueryParameters3D.new()
	params.position = Vector3(cell.x, 0.5, cell.y)
	params.collision_mask = 1
	params.collide_with_areas = false
	return space.intersect_point(params).is_empty()


func _reset_extensions() -> void:
	# Move grid_pos to the cuboid's centre so the visual collapses in place
	# instead of snapping to the original base corner.
	var shift_x: int = roundi((_ext[EXT_RIGHT] - _ext[EXT_LEFT]) / 2.0)
	var shift_z: int = roundi((_ext[EXT_BACK] - _ext[EXT_FWD]) / 2.0)
	grid_pos += Vector2i(shift_x, shift_z)
	position = Vector3(grid_pos.x, 0.5, grid_pos.y)
	_ext = [0, 0, 0, 0, 0]
	# Sync mesh immediately — _reset is called from _input, which runs before
	# camera _process. Without this the camera would read a stale mesh offset.
	_update_mesh()


func _is_extended() -> bool:
	for v in _ext:
		if v > 0:
			return true
	return false


func get_extension_sum() -> int:
	# Total extension units across all axes. Drives the detection size factor and
	# mirrors the noise size factor in _play_step.
	var total: int = _ext[EXT_LEFT] + _ext[EXT_RIGHT] + _ext[EXT_UP] + _ext[EXT_FWD] + _ext[EXT_BACK]
	return total


func get_dimensions() -> Vector3i:
	# Current cuboid dimensions in cells: (width x, height y, depth z). The
	# extend-lock zone compares this against its required_dims.
	return Vector3i(
		1 + _ext[EXT_LEFT] + _ext[EXT_RIGHT],
		1 + _ext[EXT_UP],
		1 + _ext[EXT_FWD] + _ext[EXT_BACK]
	)


func set_extend_locked(value: bool) -> void:
	_extend_locked = value


func is_extend_locked() -> bool:
	return _extend_locked


func is_moving() -> bool:
	return _tumbling or _dodging


func get_footprint_min() -> Vector2i:
	# Min-corner (smallest x, smallest z) cell of the cuboid footprint. Invariant to
	# how the extension is distributed (left vs right, fwd vs back), so it pins the
	# footprint's location regardless of how the shape was built.
	return Vector2i(grid_pos.x - _ext[EXT_LEFT], grid_pos.y - _ext[EXT_FWD])


func footprint_covers(cell: Vector2i) -> bool:
	var minx: int = grid_pos.x - _ext[EXT_LEFT]
	var minz: int = grid_pos.y - _ext[EXT_FWD]
	var w: int = 1 + _ext[EXT_LEFT] + _ext[EXT_RIGHT]
	var d: int = 1 + _ext[EXT_FWD] + _ext[EXT_BACK]
	return cell.x >= minx and cell.x < minx + w and cell.y >= minz and cell.y < minz + d


func is_dodging() -> bool:
	return _dodging


func truncate_dodge_to(cell: Vector2i) -> void:
	# Cut a dodge short to land on the given cell. Scales remaining duration
	# to preserve the slide's base speed so the cube decelerates smoothly
	# instead of teleporting to the new target.
	if not _dodging:
		return
	var current_pos := position
	var target_pos := Vector3(cell.x, 0.5, cell.y)
	var remaining := (target_pos - current_pos).length()
	if remaining < 0.01:
		return
	var base_speed := float(DODGE_DISTANCE) / DODGE_DURATION
	_dodge_duration = remaining / base_speed
	_dodge_start_pos = current_pos
	_dodge_end_pos = target_pos
	_dodge_t = 0.0
	grid_pos = cell


func _update_mesh() -> void:
	# Mesh always lives in the parent's local frame with identity basis.
	# At rest, parent.basis == IDENTITY so the mesh is world-aligned.
	# During a tumble, parent.basis rotates so the mesh visibly tumbles with it.
	_box_mesh.size = Vector3(
		1.0 + _ext[EXT_LEFT] + _ext[EXT_RIGHT],
		1.0 + _ext[EXT_UP],
		1.0 + _ext[EXT_FWD] + _ext[EXT_BACK]
	)
	_mesh_instance.transform = Transform3D(
		Basis.IDENTITY,
		Vector3(
			(_ext[EXT_RIGHT] - _ext[EXT_LEFT]) * 0.5,
			_ext[EXT_UP] * 0.5,
			(_ext[EXT_BACK] - _ext[EXT_FWD]) * 0.5
		)
	)


func _begin_tumble(dir: Vector2i) -> void:
	_start_pos = position
	_start_basis = basis
	var ext_up_old: int = _ext[EXT_UP]
	var move: int = 0
	var pivot_x: float = position.x
	var pivot_z: float = position.z
	var new_ext: Array = _ext.duplicate()

	if dir.x == 1:
		var ext_dir: int = _ext[EXT_RIGHT]
		pivot_x = position.x + 0.5 + ext_dir
		_axis = Vector3(0, 0, 1)
		_angle = -PI / 2.0
		move = 1 + ext_dir + ext_up_old
		new_ext[EXT_LEFT] = ext_up_old
		new_ext[EXT_RIGHT] = 0
		new_ext[EXT_UP] = _ext[EXT_LEFT] + _ext[EXT_RIGHT]
	elif dir.x == -1:
		var ext_dir: int = _ext[EXT_LEFT]
		pivot_x = position.x - 0.5 - ext_dir
		_axis = Vector3(0, 0, 1)
		_angle = PI / 2.0
		move = 1 + ext_dir + ext_up_old
		new_ext[EXT_RIGHT] = ext_up_old
		new_ext[EXT_LEFT] = 0
		new_ext[EXT_UP] = _ext[EXT_LEFT] + _ext[EXT_RIGHT]
	elif dir.y == -1:
		var ext_dir: int = _ext[EXT_FWD]
		pivot_z = position.z - 0.5 - ext_dir
		_axis = Vector3(1, 0, 0)
		_angle = -PI / 2.0
		move = 1 + ext_dir + ext_up_old
		new_ext[EXT_BACK] = ext_up_old
		new_ext[EXT_FWD] = 0
		new_ext[EXT_UP] = _ext[EXT_FWD] + _ext[EXT_BACK]
	elif dir.y == 1:
		var ext_dir: int = _ext[EXT_BACK]
		pivot_z = position.z + 0.5 + ext_dir
		_axis = Vector3(1, 0, 0)
		_angle = PI / 2.0
		move = 1 + ext_dir + ext_up_old
		new_ext[EXT_FWD] = ext_up_old
		new_ext[EXT_BACK] = 0
		new_ext[EXT_UP] = _ext[EXT_FWD] + _ext[EXT_BACK]
	else:
		return

	if not _can_move_cuboid(dir, move):
		return

	_pivot = Vector3(pivot_x, 0.0, pivot_z)
	_pending_ext = new_ext
	_tumble_distance = move
	grid_pos += dir * move
	_t = 0.0
	_tumbling = true
	tumbled.emit()


func _begin_dodge(dir: Vector2i) -> void:
	var max_dist := 0
	for d in range(1, DODGE_DISTANCE + 1):
		if not _can_move(Vector3(dir.x * d, 0, dir.y * d)):
			break
		max_dist = d
	if max_dist == 0:
		return
	_dodge_start_pos = position
	_dodge_end_pos = Vector3(
		grid_pos.x + dir.x * max_dist,
		0.5,
		grid_pos.y + dir.y * max_dist
	)
	grid_pos += dir * max_dist
	_slide_dir = dir
	_slide_last_cell = Vector2i(roundi(_dodge_start_pos.x), roundi(_dodge_start_pos.z))
	_dodge_t = 0.0
	_dodge_duration = DODGE_DURATION * float(max_dist) / float(DODGE_DISTANCE)
	_dodging = true


func _begin_blocked_bump(dir: Vector2i) -> void:
	# Won't-fit feedback: the extended shape tips toward dir and rocks back, like
	# bouncing off something solid, with a soft thud. No noise wave — this is pure
	# feedback, not a distraction (knock is the only deliberate noise, and it is
	# cube-only). Pivot is the leading bottom edge, so it reads as the start of a
	# tumble that couldn't complete.
	#
	# Scale the lean by the free space ahead so it never tips into the wall: the
	# top-leading corner reaches height * sin(angle) forward, so cap sin(angle) at
	# (gap / height). Flush against a wall (gap 0) leaves no room — just thud.
	var height: float = 1.0 + float(_ext[EXT_UP])
	var gap: float = float(_gap_ahead(dir))
	var mag: float = minf(BUMP_ANGLE, asin(clampf((gap - BUMP_CLEARANCE) / height, 0.0, 1.0)))
	if mag <= 0.001:
		_play_thud()
		return
	_start_pos = position
	_start_basis = basis
	var pivot_x: float = position.x
	var pivot_z: float = position.z
	if dir.x == 1:
		pivot_x = position.x + 0.5 + float(_ext[EXT_RIGHT])
		_bump_axis = Vector3(0, 0, 1)
		_bump_angle = -mag
	elif dir.x == -1:
		pivot_x = position.x - 0.5 - float(_ext[EXT_LEFT])
		_bump_axis = Vector3(0, 0, 1)
		_bump_angle = mag
	elif dir.y == -1:
		pivot_z = position.z - 0.5 - float(_ext[EXT_FWD])
		_bump_axis = Vector3(1, 0, 0)
		_bump_angle = -mag
	elif dir.y == 1:
		pivot_z = position.z + 0.5 + float(_ext[EXT_BACK])
		_bump_axis = Vector3(1, 0, 0)
		_bump_angle = mag
	else:
		return
	_bump_pivot = Vector3(pivot_x, 0.0, pivot_z)
	_bump_t = 0.0
	_bumping = true
	_play_thud()


func _gap_ahead(dir: Vector2i) -> int:
	# Clear cells between the leading face and the nearest obstruction along dir, taken
	# as the minimum across the face's width (the binding side). Capped at the cuboid
	# height — past that the lean is already maxed, so more room is irrelevant.
	var minx: int = grid_pos.x - _ext[EXT_LEFT]
	var maxx: int = grid_pos.x + _ext[EXT_RIGHT]
	var minz: int = grid_pos.y - _ext[EXT_FWD]
	var maxz: int = grid_pos.y + _ext[EXT_BACK]
	var cap: int = 1 + int(_ext[EXT_UP])
	var gap: int = cap
	if dir.x != 0:
		var lead_x: int = (maxx if dir.x > 0 else minx)
		for z in range(minz, maxz + 1):
			var d := 0
			while d < cap and _extend_cell_clear(Vector2i(lead_x + dir.x * (d + 1), z)):
				d += 1
			gap = mini(gap, d)
	else:
		var lead_z: int = (maxz if dir.y > 0 else minz)
		for x in range(minx, maxx + 1):
			var d := 0
			while d < cap and _extend_cell_clear(Vector2i(x, lead_z + dir.y * (d + 1))):
				d += 1
			gap = mini(gap, d)
	return gap


func _play_step(noise_level: float) -> void:
	var ext_sum: int = _ext[EXT_LEFT] + _ext[EXT_RIGHT] + _ext[EXT_UP] + _ext[EXT_FWD] + _ext[EXT_BACK]
	var size_factor := 1.0 + ext_sum * 0.15
	_step_player.volume_db = linear_to_db(noise_level * size_factor)
	_step_player.pitch_scale = 1.0 - ext_sum * 0.08
	_step_player.play()
	var max_radius: float = (8.0 if noise_level > 1.0 else 4.0) + ext_sum
	if _waves.size() >= MAX_WAVES:
		_waves.pop_front()
	# Wave originates from the footprint of the landed face
	var origin := Vector2(
		grid_pos.x + (_ext[EXT_RIGHT] - _ext[EXT_LEFT]) * 0.5,
		grid_pos.y + (_ext[EXT_BACK] - _ext[EXT_FWD]) * 0.5
	)
	var half_extent := Vector2(
		(_ext[EXT_LEFT] + _ext[EXT_RIGHT]) * 0.5,
		(_ext[EXT_FWD] + _ext[EXT_BACK]) * 0.5
	)
	_waves.append({
		"origin": origin,
		"half_extent": half_extent,
		"t": 0.0,
		"max_radius": max_radius
	})
	noise_emitted.emit(origin, max_radius, WAVE_DURATION)


func _emit_knock(dir: Vector2i) -> void:
	# Loud noise at the adjacent wall cell the cube rapped on, using the same
	# wave/noise plumbing the enemy hears. Cube-only (the caller gates on it), so
	# the origin is just grid_pos + dir and there is no extension size factor.
	_step_player.volume_db = 0.0
	_step_player.pitch_scale = 0.65
	_step_player.play()
	var origin := Vector2(grid_pos.x + dir.x, grid_pos.y + dir.y)
	if _waves.size() >= MAX_WAVES:
		_waves.pop_front()
	_waves.append({
		"origin": origin,
		"half_extent": Vector2.ZERO,
		"t": 0.0,
		"max_radius": KNOCK_RADIUS
	})
	noise_emitted.emit(origin, KNOCK_RADIUS, WAVE_DURATION)


func _play_thud() -> void:
	# Soft, non-alerting bump cue for a blocked extended move. Reuses the step
	# waveform, low and quiet; placeholder until the audio pass adds a real thud.
	_step_player.volume_db = linear_to_db(0.35)
	_step_player.pitch_scale = 0.5
	_step_player.play()


func _instant_focus() -> Vector3:
		# The "ideal" focus this frame, before smoothing. Y is pinned at the base
	# cell height so the camera doesn't bob when cuboid height changes.
	if _tumbling:
		var start_off := Vector3(
			(_ext[EXT_RIGHT] - _ext[EXT_LEFT]) * 0.5,
			0.0,
			(_ext[EXT_BACK] - _ext[EXT_FWD]) * 0.5
		)
		var end_off := Vector3(
			(_pending_ext[EXT_RIGHT] - _pending_ext[EXT_LEFT]) * 0.5,
			0.0,
			(_pending_ext[EXT_BACK] - _pending_ext[EXT_FWD]) * 0.5
		)
		var start_center := Vector3(_start_pos.x, 0.5, _start_pos.z) + start_off
		var end_center := Vector3(grid_pos.x, 0.5, grid_pos.y) + end_off
		return start_center.lerp(end_center, _t)
	var mesh_pos := _mesh_instance.global_position
	return Vector3(mesh_pos.x, 0.5, mesh_pos.z)


func get_camera_focus() -> Vector3:
	# Track the cuboid's visual centre. Snap during tumble/dodge so those
	# animations remain crisp; smooth at rest so extension presses don't pop.
	var instant := _instant_focus()
	if _tumbling or _dodging:
		_smoothed_focus = instant
	else:
		var dt := get_process_delta_time()
		var alpha := 1.0 - exp(-FOCUS_SMOOTH_RATE * dt)
		_smoothed_focus = _smoothed_focus.lerp(instant, alpha)
	return _smoothed_focus


func _pick_dir(move: Vector2) -> Vector2i:
	if absf(move.x) >= absf(move.y):
		return Vector2i(1 if move.x > 0.0 else -1, 0)
	return Vector2i(0, 1 if move.y > 0.0 else -1)


func _move_just_pressed() -> bool:
	return (Input.is_action_just_pressed("move_left")
		or Input.is_action_just_pressed("move_right")
		or Input.is_action_just_pressed("move_forward")
		or Input.is_action_just_pressed("move_back"))


func _process(delta: float) -> void:
	_decay_footprints(delta)
	for i in range(_waves.size() - 1, -1, -1):
		_waves[i].t = minf(_waves[i].t + delta / WAVE_DURATION, 1.0)
		if _waves[i].t >= 1.0:
			_waves.remove_at(i)

	var origins := PackedVector2Array()
	var half_extents := PackedVector2Array()
	var radii := PackedFloat32Array()
	var alphas := PackedFloat32Array()
	origins.resize(MAX_WAVES)
	half_extents.resize(MAX_WAVES)
	radii.resize(MAX_WAVES)
	alphas.resize(MAX_WAVES)
	for i in _waves.size():
		origins[i] = _waves[i].origin
		half_extents[i] = _waves[i].half_extent
		radii[i] = _waves[i].max_radius * _waves[i].t
		alphas[i] = 1.0 - _waves[i].t
	_ground_material.set_shader_parameter("wave_origins", origins)
	_ground_material.set_shader_parameter("wave_half_extents", half_extents)
	_ground_material.set_shader_parameter("wave_radii", radii)
	_ground_material.set_shader_parameter("wave_alphas", alphas)
	_ground_material.set_shader_parameter("player_xz", Vector2(global_position.x, global_position.z))

	if _dodge_cooldown_t > 0.0:
		_dodge_cooldown_t = maxf(_dodge_cooldown_t - delta, 0.0)
	if _knock_cooldown_t > 0.0:
		_knock_cooldown_t = maxf(_knock_cooldown_t - delta, 0.0)

	if _dodging:
		_dodge_t = minf(_dodge_t + delta / _dodge_duration, 1.0)
		var t_eased := 1.0 - pow(1.0 - _dodge_t, 3.0)
		position = _dodge_start_pos.lerp(_dodge_end_pos, t_eased)
		var current_cell := Vector2i(roundi(position.x), roundi(position.z))
		if current_cell != _slide_last_cell:
			_slide_last_cell = current_cell
			_check_ink_contact()
			if not _ink_cells.has(current_cell) and _face_marks[_down_face_id()]:
				_deposit_streak_cell(current_cell)
		if _dodge_t >= 1.0:
			_dodging = false
			position = _dodge_end_pos
			_dodge_cooldown_t = DODGE_COOLDOWN
			_check_ink_contact()
			move_settled.emit()
		_update_mesh()
		return

	if _tumbling:
		var sprinting := Input.is_action_pressed("sprint") and not _is_extended()
		var per_cell := SPRINT_DURATION if sprinting else TUMBLE_DURATION
		var duration := per_cell * sqrt(float(_tumble_distance))
		_t = minf(_t + delta / duration, 1.0)
		var angle := _angle * _t
		position = _pivot + (_start_pos - _pivot).rotated(_axis, angle)
		basis = Basis(_axis, angle) * _start_basis
		if _t >= 1.0:
			_tumbling = false
			position = Vector3(grid_pos.x, 0.5, grid_pos.y)
			basis = Basis.IDENTITY
			_orient = _quantize_basis(Basis(_axis, _angle) * _orient)
			_ext = _pending_ext
			_play_step(TUMBLE_DURATION / per_cell)
			_check_ink_contact_footprint()
			_maybe_deposit_footprint()
			move_settled.emit()
		_update_mesh()
		return

	if _bumping:
		_bump_t = minf(_bump_t + delta / BUMP_DURATION, 1.0)
		var lean := sin(_bump_t * PI) * _bump_angle
		position = _bump_pivot + (_start_pos - _bump_pivot).rotated(_bump_axis, lean)
		basis = Basis(_bump_axis, lean) * _start_basis
		if _bump_t >= 1.0:
			_bumping = false
			position = Vector3(grid_pos.x, 0.5, grid_pos.y)
			basis = Basis.IDENTITY
		_update_mesh()
		return

	# Auto-blend: standing still wedged between two opposite walls makes you
	# undetectable, no button. Evaluated every at-rest frame (moves returned above) so
	# it stays fresh even while extending — pressing a direction or growing out of
	# cover drops it.
	var move := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	is_blending = move.length() <= 0.5 and _is_in_cover()
	_player_material.albedo_color = _current_color()

	if Input.is_action_pressed("extend") and not _extend_locked:
		if Input.is_action_just_pressed("move_left"):
			_try_extend(EXT_LEFT)
		elif Input.is_action_just_pressed("move_right"):
			_try_extend(EXT_RIGHT)
		elif Input.is_action_just_pressed("move_forward"):
			_try_extend(EXT_UP)
		if Input.is_action_just_pressed("extend_depth_fwd"):
			_try_extend(EXT_FWD)
		elif Input.is_action_just_pressed("extend_depth_back"):
			_try_extend(EXT_BACK)
		_update_mesh()
		return

	# Collapse lives on the dodge button (idle while extended), not the extend
	# button, so collapsing mid-move can't accidentally re-extend. The dodge press
	# that collapses is consumed until released, so it can't also fire a dodge the
	# instant you become a cube again.
	if not Input.is_action_pressed("dodge"):
		_dodge_held_consumed = false
	if _is_extended() and not _extend_locked and Input.is_action_just_pressed("dodge"):
		_reset_extensions()
		_dodge_held_consumed = true
		_update_mesh()
		return

	var dodge_primed := Input.is_action_pressed("dodge") and _dodge_cooldown_t <= 0.0 and not _is_extended() and not _dodge_held_consumed

	if dodge_primed and move.length() > 0.5:
		_begin_dodge(_pick_dir(move))
	elif not dodge_primed and move.length() > 0.5:
		_begin_tumble(_pick_dir(move))

	# A directional tap that couldn't tumble (no move started). A cube raps the
	# adjacent wall: a loud knock enemies investigate. An extended shape can't fit
	# and bounces back with a soft thud (won't-fit feedback), never knocking — knock
	# is cube-only, like sprint and dodge. The just-pressed edge stops a held
	# direction into a wall from spamming either; you re-press.
	if (not _tumbling and not _dodging and not dodge_primed
			and move.length() > 0.5 and _move_just_pressed()):
		if _is_extended():
			_begin_blocked_bump(_pick_dir(move))
		elif _knock_cooldown_t <= 0.0:
			_emit_knock(_pick_dir(move))
			_knock_cooldown_t = KNOCK_COOLDOWN

	_update_mesh()


func _check_ink_contact() -> void:
	# Single cell at the render position, so it stays in sync with a fast dodge
	# slide (the Area3D overlap count lags the position lerp). The dodge path is
	# cube-only (dodge is locked while extended), so 1x1 is correct here.
	if _ink_cells.has(Vector2i(roundi(position.x), roundi(position.z))):
		_ink_face_contact()


func _check_ink_contact_footprint() -> void:
	# Tumble-landing check across the whole resting footprint, so an extended
	# cuboid inks its down face if ANY cell beneath it is an ink cell.
	var minx: int = grid_pos.x - _ext[EXT_LEFT]
	var maxx: int = grid_pos.x + _ext[EXT_RIGHT]
	var minz: int = grid_pos.y - _ext[EXT_FWD]
	var maxz: int = grid_pos.y + _ext[EXT_BACK]
	for cx in range(minx, maxx + 1):
		for cz in range(minz, maxz + 1):
			if _ink_cells.has(Vector2i(cx, cz)):
				_ink_face_contact()
				return


func _ink_face_contact() -> void:
	# Mark the current down face (binary, whole-face) and splash, once per face.
	var face: int = _down_face_id()
	if _face_marks[face]:
		return
	_face_marks[face] = true
	_splash_player.play()


func _check_water_cleanse() -> void:
	if _water_overlap_count <= 0:
		return
	if not _any_marked():
		return
	for i in _face_marks.size():
		_face_marks[i] = false
	_splash_player.play()


func _maybe_deposit_footprint() -> void:
	# Lay a print on every off-ink cell beneath the resting down face. For a cube
	# that's the single base cell; for an extended cuboid it's the whole footprint,
	# so a marked bar leaves a continuous trail the enemy can follow. Cells sitting
	# on ink are skipped (the puddle is the mark there). Per-cell ink test replaces
	# the old base-cell-only puddle-overlap gate so a cuboid straddling ink is
	# handled correctly.
	if not _face_marks[_down_face_id()]:
		return
	var minx: int = grid_pos.x - _ext[EXT_LEFT]
	var maxx: int = grid_pos.x + _ext[EXT_RIGHT]
	var minz: int = grid_pos.y - _ext[EXT_FWD]
	var maxz: int = grid_pos.y + _ext[EXT_BACK]
	var deposited := false
	for cx in range(minx, maxx + 1):
		for cz in range(minz, maxz + 1):
			if _ink_cells.has(Vector2i(cx, cz)):
				continue
			_add_footprint(Vector2(cx, cz))
			deposited = true
	if deposited:
		_update_footprint_uniforms()


func _deposit_streak_cell(cell: Vector2i) -> void:
	# Spread SLIDE_SUBSAMPLES footprints across this cell along the slide
	# direction so adjacent cells merge into a continuous streak instead of
	# discrete blobs. The caller gates this on the cell being off-ink.
	var dir := Vector2(_slide_dir.x, _slide_dir.y)
	for i in SLIDE_SUBSAMPLES:
		var t: float = -0.375 + i * 0.25
		var pos := Vector2(cell.x, cell.y) + dir * t
		_add_footprint(pos)
	_update_footprint_uniforms()


func _add_footprint(pos: Vector2) -> void:
	if _footprints.size() >= MAX_FOOTPRINTS:
		_footprints.pop_front()
	_footprints.append({ "position": pos, "alpha": 1.0 })


func _decay_footprints(delta: float) -> void:
	# Prints fade with age (oldest reach zero first) and clear when spent. Drives
	# both the visual fade and the enemy trail, which only follows live prints.
	if _footprints.is_empty():
		return
	var fade := delta / FOOTPRINT_FADE_TIME
	for i in range(_footprints.size() - 1, -1, -1):
		_footprints[i].alpha -= fade
		if _footprints[i].alpha <= 0.0:
			_footprints.remove_at(i)
	_update_footprint_uniforms()


func _update_footprint_uniforms() -> void:
	var positions := PackedVector2Array()
	var alphas := PackedFloat32Array()
	positions.resize(MAX_FOOTPRINTS)
	alphas.resize(MAX_FOOTPRINTS)
	for i in _footprints.size():
		positions[i] = _footprints[i].position
		alphas[i] = _footprints[i].alpha
	_ground_material.set_shader_parameter("footprint_positions", positions)
	_ground_material.set_shader_parameter("footprint_alphas", alphas)


func _push_walls_to_shader() -> void:
	# One-time enumeration of static walls for the ground shader's LoS check.
	# Skips Perimeter* (arena edge — never blocks visibility inside the bounds).
	var mins := PackedVector2Array()
	var maxs := PackedVector2Array()
	mins.resize(MAX_WALLS)
	maxs.resize(MAX_WALLS)
	var count := 0
	for child in get_parent().get_children():
		if count >= MAX_WALLS:
			break
		if not (child is StaticBody3D and child.name.begins_with("Wall")):
			continue
		var mesh_node := child.get_node_or_null("MeshInstance3D") as MeshInstance3D
		if mesh_node == null:
			continue
		var box := mesh_node.mesh as BoxMesh
		if box == null:
			continue
		var half := Vector2(box.size.x * 0.5, box.size.z * 0.5)
		var pos := Vector2(child.position.x, child.position.z)
		mins[count] = pos - half
		maxs[count] = pos + half
		count += 1
	_ground_material.set_shader_parameter("wall_mins", mins)
	_ground_material.set_shader_parameter("wall_maxs", maxs)
	_ground_material.set_shader_parameter("wall_count", count)


func get_footprint_positions() -> PackedVector2Array:
	var out := PackedVector2Array()
	for fp in _footprints:
		out.append(fp.position)
	return out


func consume_footprints_in_cell(cell: Vector2i) -> void:
	var changed := false
	for i in range(_footprints.size() - 1, -1, -1):
		var p: Vector2 = _footprints[i].position
		if Vector2i(roundi(p.x), roundi(p.y)) == cell:
			_footprints.remove_at(i)
			changed = true
	if changed:
		_update_footprint_uniforms()


func _down_face_id() -> int:
	# Use logical _orient (not visual basis) so face tracking persists across
	# tumbles even though the visual mesh snaps back to identity at rest.
	var local_down: Vector3 = _orient.inverse() * Vector3.DOWN
	return _dir_to_face_id(local_down)


func _dir_to_face_id(d: Vector3) -> int:
	if d.x > 0.5: return FACE_X_POS
	if d.x < -0.5: return FACE_X_NEG
	if d.y > 0.5: return FACE_Y_POS
	if d.y < -0.5: return FACE_Y_NEG
	if d.z > 0.5: return FACE_Z_POS
	return FACE_Z_NEG


func _quantize_basis(b: Basis) -> Basis:
	# Snap each rotated axis to its nearest cardinal direction so accumulated
	# float drift across many tumbles doesn't compound.
	return Basis(
		_snap_to_cardinal(b * Vector3.RIGHT),
		_snap_to_cardinal(b * Vector3.UP),
		_snap_to_cardinal(b * Vector3.BACK)
	)


func _snap_to_cardinal(v: Vector3) -> Vector3:
	var ax := absf(v.x)
	var ay := absf(v.y)
	var az := absf(v.z)
	if ax >= ay and ax >= az:
		return Vector3(signf(v.x), 0.0, 0.0)
	if ay >= az:
		return Vector3(0.0, signf(v.y), 0.0)
	return Vector3(0.0, 0.0, signf(v.z))


func _any_marked() -> bool:
	for m in _face_marks:
		if m:
			return true
	return false


func _current_color() -> Color:
	if is_blending:
		return COLOR_BLENDING
	if _extend_locked:
		return COLOR_LOCKED
	if _any_marked():
		return COLOR_MARKED
	return COLOR_NORMAL


static func _make_splash_sound() -> AudioStreamWAV:
	var rate := 44100
	var samples := 4096
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	var data := PackedByteArray()
	data.resize(samples * 2)
	for i in samples:
		var env := exp(-float(i) / 800.0)
		var freq: float = 200.0 - float(i) / float(samples) * 100.0
		var val := int(sin(float(i) * TAU * freq / float(rate)) * env * 32767.0)
		data[i * 2] = val & 0xFF
		data[i * 2 + 1] = (val >> 8) & 0xFF
	stream.data = data
	return stream


static func _make_step_sound() -> AudioStreamWAV:
	var rate := 44100
	var samples := 2048
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	var data := PackedByteArray()
	data.resize(samples * 2)
	for i in samples:
		var env := exp(-float(i) / 300.0)
		var val := int(sin(float(i) * TAU * 150.0 / rate) * env * 32767.0)
		data[i * 2] = val & 0xFF
		data[i * 2 + 1] = (val >> 8) & 0xFF
	stream.data = data
	return stream
