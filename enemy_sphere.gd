extends Node3D

signal entered_pursuit

const GROUND_MATERIAL := preload("res://grid_ground_material.tres")

const COLOR_PATROL := Color(0.7, 0.7, 0.75)
const COLOR_SUSPICIOUS := Color(1.0, 0.85, 0.0)
const COLOR_INVESTIGATE := Color(1.0, 0.55, 0.0)
const COLOR_PURSUIT := Color(1.0, 0.2, 0.2)

const ARRIVE_THRESHOLD := 0.05
const INVESTIGATE_TIMEOUT := 12.0    # safety cap; a search normally ends when all tiles are checked
const SEARCH_DWELL := 0.6            # seconds paused at each checked tile so the 360 sweep can look
const SEARCH_MAX_CELLS := 5         # cap of tiles checked around a source
const SEARCH_ARRIVE := 0.35         # distance that counts as "at" a search tile
const PURSUIT_SPEED_MULT := 1.5
const SUSPICIOUS_SPEED_MULT := 0.5
const INVESTIGATE_SPEED_MULT := 1.0
const VIEW_RADIUS := 8.0
const VIEW_CONE_COS := 0.766  # cos(40°), so an 80° total cone
const FOOTPRINT_VIEW_RADIUS := 5.0
const FOOTPRINT_VIEW_CONE_COS := 0.866  # cos(30°), so a 60° total cone
const FOOTPRINT_RETARGET_DIST := 0.3
const TURN_RATE := 5.0  # rad/s — 180° in ~0.6s
const TURN_CRAWL_FRACTION := 0.5  # min fraction of speed kept through sharp turns (no dead stop)
const CORRIDOR_HYSTERESIS := 0.2  # corridor must stay clear this long before off-grid pursuit engages
const SQRT2 := 1.4142135623730951  # diagonal step cost for 8-connected A*

const NEIGHBORS_8: Array[Vector2i] = [
	Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
	Vector2i(-1, 0), Vector2i(1, 0),
	Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1),
]
const PATH_CELL_ARRIVE := 0.15
const PURSUIT_REPATH_INTERVAL := 0.3
const SILHOUETTE_ALPHA := 0.0
const VISIBILITY_LERP_RATE := 8.0
const PURSUIT_LOS_PADDING := 0.45

# Graduated detection (SPEC_graduated_detection.md). _detection in [0,1] is the
# enemy's visual certainty; thresholds drive the PATROL/SUSPICIOUS/PURSUIT ladder.
const DETECT_FILL_RATE := 2.0        # per second at full exposure factors
const DETECT_DRAIN_RATE := 0.4       # per second when not seeing
const DETECT_SUSPICIOUS := 0.25      # PATROL -> SUSPICIOUS
const DETECT_PURSUIT := 1.0          # -> PURSUIT (full bar)
const DETECT_PURSUIT_KEEP := 0.5     # stay in PURSUIT until drained below this
const DETECT_MIN_PROXIMITY := 0.15   # fill floor at cone edge
const DETECT_SIZE_WEIGHT := 0.15     # per extension unit
const DETECT_ALERT_FILL_MULT := 1.5  # faster fill when already alert
const DETECT_NOISE_SEED := 0.5       # heard noise seeds detection here, then drains
const DEBUG_DETECTION := true        # temporary on-screen _detection readout; remove with the focusing-cone task

# Focusing cone (reads _detection). The cone narrows, colour-ramps, and aims at
# the suspect as detection rises; INVESTIGATE opens to a 360 search sweep.
const CONE_FOCUS_COS := 0.97         # half-angle cos when fully locked (~14 deg)
const CONE_PATROL_ALPHA := 0.2       # cone opacity at detection 0
const CONE_LOCKED_ALPHA := 0.6       # cone opacity at detection 1
const CONE_SEARCH_ALPHA := 0.5       # rotating search cone opacity in INVESTIGATE (lock 0)
const CONE_SEARCH_HALF_COS := 0.7071 # cos(45°): a 90° rotating search cone in INVESTIGATE
const CONE_SEARCH_SWEEP_RATE := 3.0  # rad/s the INVESTIGATE cone rotates (emergency-beacon sweep)
const GLYPH_POP_SCALE := 1.6         # alert-glyph scale spike on a state change
const GLYPH_POP_TIME := 0.25         # seconds the glyph pop decays over

# State-encoded hum (occlusion-proof alert channel): pitch and volume rise along
# the alert ladder, indexed by State. Pitch also speeds the baked tremolo, so a
# higher alert reads as a more agitated hum even when the enemy is out of sight.
const HUM_PITCH: Array[float] = [1.0, 1.12, 1.22, 1.5]   # PATROL/SUSPICIOUS/INVESTIGATE/PURSUIT
const HUM_VOL: Array[float] = [-10.0, -9.0, -8.0, -6.0]
const HUM_LERP_RATE := 4.0           # how fast the hum eases between state targets

enum State { PATROL, SUSPICIOUS, INVESTIGATE, PURSUIT }

@export var waypoints: Array[Vector3] = [
	Vector3(8, 0.4, 0),
	Vector3(-8, 0.4, 0),
	Vector3(-8, 0.4, 1),
	Vector3(8, 0.4, 1),
]
@export var speed: float = 2.0

var _target_idx := 0
var _state: State = State.PATROL
var _state_timer := 0.0
var _detection := 0.0
var _last_seen_pos := Vector3.ZERO
var _last_visible_sample := Vector3.ZERO  # cell that passed _is_seeing_player this tick; sometimes the player's center, sometimes an exposed end of an extended bar
var _material: StandardMaterial3D
var _player: Player
var _pending_sounds: Array = []
var _ground_material: ShaderMaterial
var _nav_blocked: Dictionary = {}
var _path: Array[Vector2i] = []
var _path_idx: int = 0
var _search_cells: Array[Vector2i] = []
var _search_dwell: float = 0.0
var _pursuit_repath_timer: float = 0.0
var _corridor_open_timer: float = 0.0
var _visibility_alpha: float = 1.0
var _visibility_initialized: bool = false
var _debug_label: Label
var _debug_reveal: bool = false
var _ghost: MeshInstance3D
var _alert_glyph: Label3D
var _investigate_sweep_angle: float = 0.0
var _glyph_pop: float = 0.0
var _sting_player: AudioStreamPlayer3D
var _sting_alert: AudioStreamWAV
var _sting_spot: AudioStreamWAV
var _sting_standdown: AudioStreamWAV

@onready var _mesh: MeshInstance3D = $MeshInstance3D
@onready var _hum_player: AudioStreamPlayer3D = $HumSound
@onready var _level: Level = get_node("../Level")


func _ready() -> void:
	_material = (_mesh.get_surface_override_material(0) as StandardMaterial3D).duplicate()
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mesh.set_surface_override_material(0, _material)
	_player = get_node("../Player") as Player
	_player.noise_emitted.connect(_on_player_noise)
	_ground_material = GROUND_MATERIAL
	_hum_player.stream = _make_hum_sound()
	_hum_player.play()
	_setup_stings()
	_setup_alert_glyph()
	_setup_ghost()
	_build_nav_grid()
	if waypoints.size() > 0:
		_set_path_to(waypoints[_target_idx])
	if DEBUG_DETECTION:
		_setup_debug_label()


func _process(delta: float) -> void:
	_advance_pending_sounds(delta)
	var seeing := _is_seeing_player()
	if seeing:
		# Use the actually-visible cell, not the player's centre, so investigating
		# after losing sight heads toward where the exposed end was, not the (hidden)
		# base of an extended bar.
		_last_seen_pos = _last_visible_sample
	_update_detection(delta, seeing)

	var footprint_pos := Vector3.INF
	if not seeing and _state != State.PURSUIT:
		footprint_pos = _visible_footprint_pos()

	match _state:
		State.PATROL:
			_patrol(delta)
			if _detection >= DETECT_SUSPICIOUS:
				_enter_state(State.SUSPICIOUS)
			elif footprint_pos != Vector3.INF:
				_last_seen_pos = Vector3(footprint_pos.x, position.y, footprint_pos.z)
				_enter_state(State.INVESTIGATE)
		State.SUSPICIOUS:
			if _detection >= DETECT_PURSUIT:
				_enter_state(State.PURSUIT)
			elif _detection < DETECT_SUSPICIOUS:
				_enter_state(State.PATROL)
			elif footprint_pos != Vector3.INF:
				_last_seen_pos = Vector3(footprint_pos.x, position.y, footprint_pos.z)
				_enter_state(State.INVESTIGATE)
			else:
				_creep(delta)
		State.INVESTIGATE:
			if _detection >= DETECT_PURSUIT:
				_enter_state(State.PURSUIT)
			else:
				# Eat the print under our feet as we search, so cells we have already
				# checked can't lure us back the way we came.
				_player.consume_footprints_in_cell(Vector2i(roundi(position.x), roundi(position.z)))
				_state_timer += delta
				# A fresh print in view re-seeds the search on the trail (chase the player).
				if footprint_pos != Vector3.INF:
					var nv := Vector2(footprint_pos.x, footprint_pos.z)
					var cv := Vector2(_last_seen_pos.x, _last_seen_pos.z)
					if nv.distance_to(cv) > FOOTPRINT_RETARGET_DIST:
						_last_seen_pos = Vector3(footprint_pos.x, position.y, footprint_pos.z)
						_begin_search(_world_to_cell(_last_seen_pos))
						_state_timer = 0.0
				_investigate_search(delta)
				# Give up once every tile around the source is checked (or the safety cap).
				if _search_cells.is_empty() or _state_timer >= INVESTIGATE_TIMEOUT:
					_enter_state(State.PATROL)
		State.PURSUIT:
			_pursue(delta)
			if _detection < DETECT_PURSUIT_KEEP:
				_last_seen_pos = Vector3(_last_seen_pos.x, position.y, _last_seen_pos.z)
				_enter_state(State.INVESTIGATE)

	var target_alpha := 1.0 if (_debug_reveal or _visible_to_player()) else SILHOUETTE_ALPHA
	if not _visibility_initialized:
		_visibility_alpha = target_alpha
		_visibility_initialized = true
	else:
		_visibility_alpha = lerpf(_visibility_alpha, target_alpha, minf(delta * VISIBILITY_LERP_RATE, 1.0))
	var col := _state_color()
	col.a = _visibility_alpha
	_material.albedo_color = col
	_update_cone_uniforms(delta)
	_update_alert_glyph(delta)
	_update_hum(delta)
	_update_debug_label()
	_update_debug_reveal()
	_update_ghost(seeing)


func _update_detection(delta: float, seeing: bool) -> void:
	# Graduated visual certainty. Fills while the player is seen, scaled by how
	# close and how large they are (and faster when already alert); drains
	# otherwise. Hiding affects this only via _is_seeing_player (blend makes
	# seeing false), never as a direct term. See SPEC_graduated_detection.md.
	if seeing:
		var to_player := _player.global_position - global_position
		to_player.y = 0.0
		var dist := to_player.length()
		var proximity := clampf(1.0 - dist / VIEW_RADIUS, DETECT_MIN_PROXIMITY, 1.0)
		var size: float = 1.0 + _player.get_extension_sum() * DETECT_SIZE_WEIGHT
		var alert := DETECT_ALERT_FILL_MULT if _state != State.PATROL else 1.0
		_detection += DETECT_FILL_RATE * proximity * size * alert * delta
	else:
		_detection -= DETECT_DRAIN_RATE * delta
	_detection = clampf(_detection, 0.0, 1.0)


func _patrol(delta: float) -> void:
	if waypoints.size() < 2:
		return
	var target: Vector3 = waypoints[_target_idx]
	if (target - position).length() < ARRIVE_THRESHOLD:
		_target_idx = (_target_idx + 1) % waypoints.size()
		_set_path_to(waypoints[_target_idx])
		return
	_follow_path(delta, 1.0, target)


func _creep(delta: float) -> void:
	_follow_path(delta, SUSPICIOUS_SPEED_MULT, _last_seen_pos)


func _pursue(delta: float) -> void:
	# Hybrid locomotion: seek the suspect directly (off-grid, more threatening)
	# once a sphere-wide corridor has stayed clear for CORRIDOR_HYSTERESIS. That
	# debounces the per-frame ray check so the sphere does not jitter between
	# modes at a wall corner. Any block resets the timer and falls back to A*
	# immediately, the safe choice near walls.
	# Chase _last_seen_pos (the last visible cell), not the player's origin: for an
	# extended bar that is the exposed end currently in view, so the sphere closes on
	# what it can actually see instead of pathing toward the hidden base cell.
	var target := _last_seen_pos
	if _has_pursuit_corridor(target):
		_corridor_open_timer += delta
	else:
		_corridor_open_timer = 0.0
	if _corridor_open_timer >= CORRIDOR_HYSTERESIS:
		_path = []
		_path_idx = 0
		_pursuit_repath_timer = 0.0
		_move_toward(target, delta, PURSUIT_SPEED_MULT)
		return
	_pursuit_repath_timer -= delta
	if _pursuit_repath_timer <= 0.0:
		_set_path_to(target)
		_pursuit_repath_timer = PURSUIT_REPATH_INTERVAL
	_follow_path(delta, PURSUIT_SPEED_MULT, target)


func _has_pursuit_corridor(target: Vector3) -> bool:
	# Three parallel rays (center + two offset by sphere radius perpendicular
	# to travel direction). All must be clear so the sphere's body fits.
	var to := target
	var from := global_position
	var dir := Vector3(to.x - from.x, 0.0, to.z - from.z)
	if dir.length_squared() < 0.0001:
		return true
	var perp := Vector3(-dir.z, 0.0, dir.x).normalized() * PURSUIT_LOS_PADDING
	var offsets: Array[Vector3] = [Vector3.ZERO, perp, -perp]
	var space := get_world_3d().direct_space_state
	for offset in offsets:
		var query := PhysicsRayQueryParameters3D.create(from + offset, to + offset)
		query.collide_with_areas = false
		if not space.intersect_ray(query).is_empty():
			return false
	return true


func _move_toward(target_pos: Vector3, delta: float, speed_mult: float) -> void:
	var to_target := Vector3(target_pos.x - position.x, 0.0, target_pos.z - position.z)
	var distance := to_target.length()
	if distance < ARRIVE_THRESHOLD:
		return
	var horizontal_dir := to_target / distance
	var current_forward := -global_transform.basis.z
	current_forward.y = 0.0
	var angle_off := 0.0
	if current_forward.length_squared() > 0.0001:
		current_forward = current_forward.normalized()
		angle_off = current_forward.signed_angle_to(horizontal_dir, Vector3.UP)
		var rot_step := clampf(angle_off, -TURN_RATE * delta, TURN_RATE * delta)
		rotate(Vector3.UP, rot_step)
	# Move while turning: full speed when aligned, easing to a crawl (never a dead
	# stop) through sharp turns so the sphere arcs decisively instead of pivoting
	# in place at corners.
	var align := clampf(cos(angle_off), 0.0, 1.0)
	var speed_factor := lerpf(TURN_CRAWL_FRACTION, 1.0, align)
	var step := minf(speed * speed_mult * speed_factor * delta, distance)
	position += horizontal_dir * step


func _enter_state(new_state: State) -> void:
	var prev := _state
	var was_pursuit := prev == State.PURSUIT
	_state = new_state
	_state_timer = 0.0
	_glyph_pop = GLYPH_POP_TIME
	# Transition stings: occlusion-proof punctuation for the key beats. Spotted (!)
	# on entering pursuit, alerted (?) on the first escalation out of patrol, and an
	# all-clear when settling back to patrol. Lateral moves stay silent.
	if new_state == State.PURSUIT and not was_pursuit:
		_play_sting(_sting_spot)
	elif prev == State.PATROL and new_state != State.PATROL:
		_play_sting(_sting_alert)
	elif new_state == State.PATROL and prev != State.PATROL:
		_play_sting(_sting_standdown)
	if new_state == State.PATROL:
		_target_idx = _closest_waypoint_idx()
		_set_path_to(waypoints[_target_idx])
	if new_state == State.SUSPICIOUS:
		_set_path_to(_last_seen_pos)
	if new_state == State.INVESTIGATE:
		_begin_search(_world_to_cell(_last_seen_pos))
		# Start the search sweep aimed at the last-seen spot so the beam picks up
		# where the suspicious cone left it, then rotates away.
		var to_suspect := Vector2(_last_seen_pos.x - position.x, _last_seen_pos.z - position.z)
		if to_suspect.length() > 0.001:
			_investigate_sweep_angle = atan2(to_suspect.y, to_suspect.x)
	if new_state == State.PURSUIT:
		# _last_seen_pos is fresh here (pursuit is only reached by seeing the player,
		# which updates it the same frame), so seed the chase at the visible cell.
		_set_path_to(_last_seen_pos)
		_pursuit_repath_timer = PURSUIT_REPATH_INTERVAL
		_corridor_open_timer = 0.0
		_pending_sounds.clear()  # drop in-flight noise; pursuit ignores distractions
		if not was_pursuit:
			entered_pursuit.emit()


func _closest_waypoint_idx() -> int:
	var best_idx := 0
	var best_dist := INF
	for i in waypoints.size():
		var d: float = (waypoints[i] - position).length_squared()
		if d < best_dist:
			best_dist = d
			best_idx = i
	return best_idx


func _state_color() -> Color:
	match _state:
		State.SUSPICIOUS: return COLOR_SUSPICIOUS
		State.INVESTIGATE: return COLOR_INVESTIGATE
		State.PURSUIT: return COLOR_PURSUIT
		_: return COLOR_PATROL


func get_detection_level() -> float:
	return _detection


func get_detection_state() -> int:
	return _state


func _setup_debug_label() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 128
	add_child(layer)
	_debug_label = Label.new()
	_debug_label.position = Vector2(24, 24)
	_debug_label.add_theme_font_size_override("font_size", 22)
	_debug_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_debug_label.add_theme_constant_override("outline_size", 4)
	layer.add_child(_debug_label)


func _update_debug_label() -> void:
	if _debug_label == null:
		return
	var suffix := "   [REVEAL]" if _debug_reveal else ""
	_debug_label.text = "%s  %.2f%s" % [_state_name(), _detection, suffix]
	_debug_label.add_theme_color_override("font_color", _state_color())


func _state_name() -> String:
	match _state:
		State.SUSPICIOUS: return "SUSPICIOUS"
		State.INVESTIGATE: return "INVESTIGATE"
		State.PURSUIT: return "PURSUIT"
		_: return "PATROL"


func _unhandled_input(event: InputEvent) -> void:
	# Debug reveal toggle (V): x-ray the enemy body + glyph so its motion can be
	# watched while occluded. The last-known ghost is a separate gameplay cue.
	if event.is_action_pressed("debug_reveal"):
		_debug_reveal = not _debug_reveal


func _setup_ghost() -> void:
	# Last-known-position readout: a translucent cube parked where the enemy last knew
	# the player to be. A gameplay cue (not debug), shown only while alerted and unable
	# to see the player right now — a live target needs no marker, so it reads as "the
	# search is happening here." top_level keeps it in world space; no_depth_test keeps
	# it readable when the spot is behind a wall, like the floor cone.
	_ghost = MeshInstance3D.new()
	_ghost.top_level = true
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE
	_ghost.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	mat.albedo_color = Color(1, 1, 1, 0.25)
	_ghost.material_override = mat
	_ghost.visible = false
	add_child(_ghost)


func _update_debug_reveal() -> void:
	# Debug x-ray only: draw the enemy body + glyph through walls while revealed.
	_material.no_depth_test = _debug_reveal
	if _alert_glyph != null:
		_alert_glyph.no_depth_test = _debug_reveal


func _update_ghost(seeing: bool) -> void:
	# Show the last-known marker only once the enemy has lost sight: alerted (not
	# patrol) and not currently seeing the player. Tint it by alert state so the cue
	# carries the threat level (yellow / orange / red).
	if _ghost == null:
		return
	var show_ghost := _state != State.PATROL and not seeing
	_ghost.visible = show_ghost
	if show_ghost:
		_ghost.position = Vector3(_last_seen_pos.x, 0.5, _last_seen_pos.z)
		var col := _state_color()
		col.a = 0.3
		(_ghost.material_override as StandardMaterial3D).albedo_color = col


func _on_player_noise(origin: Vector2, max_radius: float, duration: float) -> void:
	# Pursuit is locked on and ignores noise entirely, so don't even queue it: a knock
	# fired mid-chase must not be able to land as an investigate after pursuit drops.
	if _state == State.PURSUIT:
		return
	var enemy_xz := Vector2(position.x, position.z)
	var dist := enemy_xz.distance_to(origin)
	if dist > max_radius:
		return
	var delay := dist * duration / max_radius
	_pending_sounds.append({ "origin": origin, "delay": delay })


func _advance_pending_sounds(delta: float) -> void:
	for i in range(_pending_sounds.size() - 1, -1, -1):
		_pending_sounds[i].delay -= delta
		if _pending_sounds[i].delay <= 0.0:
			var origin: Vector2 = _pending_sounds[i].origin
			_pending_sounds.remove_at(i)
			_on_sound_heard(origin)


func _on_sound_heard(origin: Vector2) -> void:
	# A noise is a located clue, so go investigate the source (this is what makes
	# knocking a usable lure). Pursuit ignores noise — already locked on.
	if _state == State.PURSUIT:
		return
	_detection = maxf(_detection, DETECT_NOISE_SEED)
	var heard_pos := Vector3(origin.x, position.y, origin.y)
	if _state == State.INVESTIGATE:
		# Only redirect (and refresh the dwell) for a meaningfully different source.
		# Spamming knocks at the same spot must not keep resetting _state_timer — that
		# stunlocked the sphere in INVESTIGATE forever and churned its path. Same-spot
		# repeats are ignored so the current search runs out to its timeout.
		var moved := Vector2(heard_pos.x, heard_pos.z).distance_to(Vector2(_last_seen_pos.x, _last_seen_pos.z))
		if moved > FOOTPRINT_RETARGET_DIST:
			_last_seen_pos = heard_pos
			_begin_search(_world_to_cell(_last_seen_pos))
			_state_timer = 0.0
	else:
		_last_seen_pos = heard_pos
		_enter_state(State.INVESTIGATE)


func _is_seeing_player() -> bool:
	# Cone + LoS check across the player's whole footprint, not just its centre,
	# so an extended bar's end poking out of cover is detectable even when the
	# base cell's ray is occluded by a wall. INVESTIGATE drops the cone filter
	# (active 360° scan). First sample cell that passes all gates wins.
	if _player.is_blending:
		return false
	var cone_active := _state != State.INVESTIGATE
	var forward := Vector3.ZERO
	if cone_active:
		forward = -global_transform.basis.z
		forward.y = 0.0
		var fl := forward.length()
		if fl < 0.0001:
			return false
		forward /= fl
	var space := get_world_3d().direct_space_state
	var fmin: Vector2i = _player.get_footprint_min()
	var dims: Vector3i = _player.get_dimensions()
	var sample_y := _player.global_position.y
	for dx in range(dims.x):
		for dz in range(dims.z):
			var sample := Vector3(fmin.x + dx, sample_y, fmin.y + dz)
			var to_sample := sample - global_position
			to_sample.y = 0.0
			var dist := to_sample.length()
			if dist < 0.01 or dist > VIEW_RADIUS:
				continue
			if cone_active and (to_sample / dist).dot(forward) < VIEW_CONE_COS:
				continue
			var query := PhysicsRayQueryParameters3D.create(global_position, sample)
			query.collide_with_areas = false
			if space.intersect_ray(query).is_empty():
				_last_visible_sample = sample
				return true
	return false


func _visible_footprint_pos() -> Vector3:
	# Returns the freshest in-view footprint with unobstructed LoS, so the search
	# heads up the trail toward the player instead of back down it. get_footprint_
	# positions is oldest -> newest, so we walk it newest-first and take the first
	# hit. INVESTIGATE scans 360° around the sphere; other states use the cone.
	var positions: PackedVector2Array = _player.get_footprint_positions()
	if positions.is_empty():
		return Vector3.INF
	var skip_cone := _state == State.INVESTIGATE
	var forward := Vector3.ZERO
	if not skip_cone:
		forward = -global_transform.basis.z
		forward.y = 0.0
		var fl := forward.length()
		if fl < 0.0001:
			return Vector3.INF
		forward /= fl
	var origin := global_position
	var space := get_world_3d().direct_space_state
	for i in range(positions.size() - 1, -1, -1):
		var p := positions[i]
		var fp_world := Vector3(p.x, 0.05, p.y)
		var delta_xz := Vector3(fp_world.x - origin.x, 0.0, fp_world.z - origin.z)
		var dist := delta_xz.length()
		if dist < 0.01 or dist > FOOTPRINT_VIEW_RADIUS:
			continue
		if not skip_cone:
			var dir := delta_xz / dist
			if dir.dot(forward) < FOOTPRINT_VIEW_CONE_COS:
				continue
		var query := PhysicsRayQueryParameters3D.create(origin, fp_world)
		query.collide_with_areas = false
		if space.intersect_ray(query).is_empty():
			return fp_world
	return Vector3.INF


func _begin_search(center: Vector2i) -> void:
	# Build the ring of tiles to check around the noise / last-seen cell and head for
	# the first. This is what turns "look at the source from one side" into a
	# search-and-clear that comes around a knocked wall to the far side.
	_search_cells = _build_search_cells(center)
	_search_dwell = 0.0
	if not _search_cells.is_empty():
		_set_path_to(_cell_to_world(_search_cells[0]))


func _build_search_cells(center: Vector2i) -> Array[Vector2i]:
	# The source cell (if standable) plus its orthogonal neighbours: the tiles around
	# the sound, on every side, so a knocked wall gets checked from the far side too.
	# Keep only cells we can actually reach, ordered nearest-first, capped.
	var start := _world_to_cell(position)
	var candidates: Array[Vector2i] = []
	if not _cell_blocked(center):
		candidates.append(center)
	for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var c: Vector2i = center + d
		if not _cell_blocked(c):
			candidates.append(c)
	var reachable: Array[Vector2i] = []
	for c: Vector2i in candidates:
		if _find_path(start, c).size() > 0:
			reachable.append(c)
	reachable.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return (a - start).length_squared() < (b - start).length_squared())
	if reachable.size() > SEARCH_MAX_CELLS:
		reachable.resize(SEARCH_MAX_CELLS)
	return reachable


func _investigate_search(delta: float) -> void:
	# Walk to the current search tile; on arrival pause so the 360 sweep can clear it,
	# then advance. Emptying the list ends the search (handled by the caller).
	if _search_cells.is_empty():
		return
	var target := _cell_to_world(_search_cells[0])
	var to_target := Vector2(target.x - position.x, target.z - position.z)
	if to_target.length() <= SEARCH_ARRIVE:
		_search_dwell += delta
		if _search_dwell >= SEARCH_DWELL:
			_search_cells.remove_at(0)
			_search_dwell = 0.0
			if not _search_cells.is_empty():
				_set_path_to(_cell_to_world(_search_cells[0]))
	else:
		_follow_path(delta, INVESTIGATE_SPEED_MULT, target)


func _cell_to_world(cell: Vector2i) -> Vector3:
	return Vector3(cell.x, position.y, cell.y)


func _update_cone_uniforms(delta: float) -> void:
	var forward := -global_transform.basis.z
	forward.y = 0.0
	var fl := forward.length()
	var dir_2d := Vector2(1.0, 0.0)
	if fl > 0.0001:
		dir_2d = Vector2(forward.x / fl, forward.z / fl)
	_ground_material.set_shader_parameter("cone_origin", Vector2(position.x, position.z))
	_ground_material.set_shader_parameter("cone_radius", VIEW_RADIUS)

	if _state == State.INVESTIGATE:
		_update_search_cone(delta)
		return

	# Visual ladder: the cone is the detection fill. As _detection rises it
	# narrows toward a tight beam, ramps grey -> yellow -> red, and aims at the
	# suspect so the narrowing beam keeps the target lit (and marks last-known).
	var aim := dir_2d
	var to_suspect := Vector2(_last_seen_pos.x - position.x, _last_seen_pos.z - position.z)
	if _detection > 0.001 and to_suspect.length() > 0.05:
		var blended := dir_2d.lerp(to_suspect.normalized(), _detection)
		if blended.length() > 0.01:
			aim = blended.normalized()
	var half_cos := lerpf(VIEW_CONE_COS, CONE_FOCUS_COS, _detection)
	var col := _detection_color(_detection)
	var alpha := lerpf(CONE_PATROL_ALPHA, CONE_LOCKED_ALPHA, _detection)
	_ground_material.set_shader_parameter("cone_dir", aim)
	_ground_material.set_shader_parameter("cone_half_angle_cos", half_cos)
	_ground_material.set_shader_parameter("cone_color", _color_to_vec3(col))
	# Independent of _visibility_alpha: the floor cone stays readable when the enemy
	# body is occluded. The shader's per-pixel LoS still hides cone on unseen ground.
	_ground_material.set_shader_parameter("cone_alpha", alpha)


func _update_search_cone(delta: float) -> void:
	# Active search: a 90° cone sweeps the floor like a rotating beacon. As
	# certainty (lock) climbs back toward pursuit the sweep slows and stops, the
	# cone narrows toward the focus beam, slides orange -> red, and homes on the
	# suspect. At lock 1 this matches the PURSUIT branch exactly, so the handoff
	# is a continuous focus rather than a snap.
	var lock := clampf((_detection - DETECT_SUSPICIOUS) / (DETECT_PURSUIT - DETECT_SUSPICIOUS), 0.0, 1.0)
	_investigate_sweep_angle += CONE_SEARCH_SWEEP_RATE * (1.0 - lock) * delta
	var sweep_dir := Vector2(cos(_investigate_sweep_angle), sin(_investigate_sweep_angle))
	var aim := sweep_dir
	var to_suspect := Vector2(_last_seen_pos.x - position.x, _last_seen_pos.z - position.z)
	if to_suspect.length() > 0.05:
		var blended := sweep_dir.lerp(to_suspect.normalized(), lock)
		if blended.length() > 0.01:
			aim = blended.normalized()
	var half_cos := lerpf(CONE_SEARCH_HALF_COS, CONE_FOCUS_COS, lock)
	var col := COLOR_INVESTIGATE.lerp(COLOR_PURSUIT, lock)
	var alpha := lerpf(CONE_SEARCH_ALPHA, CONE_LOCKED_ALPHA, lock)
	_ground_material.set_shader_parameter("cone_dir", aim)
	_ground_material.set_shader_parameter("cone_half_angle_cos", half_cos)
	_ground_material.set_shader_parameter("cone_color", _color_to_vec3(col))
	# Independent of _visibility_alpha (see _update_cone_uniforms): the search cone
	# stays visible on seen ground even when the enemy itself is behind a wall.
	_ground_material.set_shader_parameter("cone_alpha", alpha)


func _detection_color(d: float) -> Color:
	if d < 0.5:
		return COLOR_PATROL.lerp(COLOR_SUSPICIOUS, d / 0.5)
	return COLOR_SUSPICIOUS.lerp(COLOR_PURSUIT, (d - 0.5) / 0.5)


func _color_to_vec3(c: Color) -> Vector3:
	return Vector3(c.r, c.g, c.b)


func _setup_stings() -> void:
	# One-shot transition stings on their own 3D player (so they layer over the
	# looping hum). Procedurally generated so there are no audio assets to ship.
	_sting_player = AudioStreamPlayer3D.new()
	_sting_player.unit_size = 6.0
	_sting_player.max_distance = 20.0
	add_child(_sting_player)
	_sting_alert = _make_sting(520.0, 760.0, 0.16, 0.6)       # "?" curious, rising
	_sting_spot = _make_sting(1000.0, 820.0, 0.13, 0.95)      # "!" alarm, sharp and loud
	_sting_standdown = _make_sting(520.0, 320.0, 0.22, 0.45)  # all-clear, falling and soft


func _play_sting(stream: AudioStreamWAV) -> void:
	_sting_player.stream = stream
	_sting_player.play()


func _update_hum(delta: float) -> void:
	# Ease pitch and volume toward the current state's target so the hum tracks the
	# alert ladder smoothly. Audio is not occluded, so this reads through walls.
	var t := minf(delta * HUM_LERP_RATE, 1.0)
	_hum_player.pitch_scale = lerpf(_hum_player.pitch_scale, HUM_PITCH[_state], t)
	_hum_player.volume_db = lerpf(_hum_player.volume_db, HUM_VOL[_state], t)


func _setup_alert_glyph() -> void:
	# Billboarded ? / ! above the sphere. Hidden on patrol; reads alert state from
	# any angle. Fades with _visibility_alpha so it never leaks the enemy's
	# position when the player has no line of sight (matches the mesh).
	_alert_glyph = Label3D.new()
	_alert_glyph.text = ""
	_alert_glyph.position = Vector3(0.0, 0.95, 0.0)
	_alert_glyph.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_alert_glyph.pixel_size = 0.01
	_alert_glyph.font_size = 64
	_alert_glyph.outline_size = 12
	_alert_glyph.outline_modulate = Color.BLACK
	_alert_glyph.visible = false
	add_child(_alert_glyph)


func _update_alert_glyph(delta: float) -> void:
	if _alert_glyph == null:
		return
	_glyph_pop = maxf(_glyph_pop - delta, 0.0)
	var glyph := ""
	var col := COLOR_PATROL
	match _state:
		State.SUSPICIOUS:
			glyph = "?"
			col = COLOR_SUSPICIOUS
		State.INVESTIGATE:
			glyph = "?"
			col = COLOR_INVESTIGATE
		State.PURSUIT:
			glyph = "!"
			col = COLOR_PURSUIT
	if glyph == "":
		_alert_glyph.visible = false
		return
	_alert_glyph.visible = true
	_alert_glyph.text = glyph
	col.a = _visibility_alpha
	_alert_glyph.modulate = col
	_alert_glyph.outline_modulate = Color(0.0, 0.0, 0.0, _visibility_alpha)
	# Scale spike on state change: starts at GLYPH_POP_SCALE and eases back to 1.
	var s := 1.0 + (GLYPH_POP_SCALE - 1.0) * (_glyph_pop / GLYPH_POP_TIME)
	_alert_glyph.scale = Vector3(s, s, s)


func _build_nav_grid() -> void:
	# Static walls only — interior Wall* nodes. Mark every grid cell the wall's box
	# footprint covers (not just its centre cell), so multi-cell walls block fully.
	# Perimeter walls don't match the "Wall*" prefix and would land on non-floor
	# cells anyway, so they fall through the is_floor gate in _cell_blocked.
	_nav_blocked.clear()
	for child in get_parent().get_children():
		if not (child is StaticBody3D and child.name.begins_with("Wall")):
			continue
		var body := child as StaticBody3D
		var fp := _wall_footprint(body)
		var x0 := roundi(body.position.x - fp.x * 0.5 + 0.5)
		var x1 := roundi(body.position.x + fp.x * 0.5 - 0.5)
		var z0 := roundi(body.position.z - fp.y * 0.5 + 0.5)
		var z1 := roundi(body.position.z + fp.y * 0.5 - 0.5)
		for x in range(x0, x1 + 1):
			for z in range(z0, z1 + 1):
				_nav_blocked[Vector2i(x, z)] = true


func _wall_footprint(body: StaticBody3D) -> Vector2:
	# XZ extent of the wall's BoxShape3D collider, or 1x1 if none found. Returns
	# (x_size, z_size); single-cell walls give (1, 1) and behave as before.
	for c in body.get_children():
		if c is CollisionShape3D and (c as CollisionShape3D).shape is BoxShape3D:
			var s := ((c as CollisionShape3D).shape as BoxShape3D).size
			return Vector2(s.x, s.z)
	return Vector2.ONE


func _cell_blocked(cell: Vector2i) -> bool:
	# Floor is the new bounds source: non-floor = off the level = unreachable.
	# Interior walls still contribute via _nav_blocked. NAV_MIN/MAX is gone now
	# that floor data carries the play-area shape.
	if not _level.is_floor(cell):
		return true
	if _nav_blocked.has(cell):
		return true
	# A hiding player counts as a wall to pathfinding: they "look like part of
	# the wall," so the enemy plans around the footprint instead of barging in.
	# Gated on is_hiding (still + in cover) not is_blending (full phase), so the
	# nav block engages the moment the player settles into cover, before the visual
	# fade completes; the 0.4s ramp window would otherwise let the enemy walk in.
	# _find_path already snaps a blocked goal to the nearest open neighbour, so
	# investigating a noise at the player's cell ends at the cell next to them.
	if _player.is_hiding and _player.footprint_covers(cell):
		return true
	return false


func _world_to_cell(p: Vector3) -> Vector2i:
	return Vector2i(roundi(p.x), roundi(p.z))


func _set_path_to(target: Vector3) -> void:
	var start_cell := _world_to_cell(position)
	var goal_cell := _world_to_cell(target)
	_path = _find_path(start_cell, goal_cell)
	_path_idx = 0
	if _path.size() > 0 and _path[0] == start_cell:
		_path_idx = 1


func _follow_path(delta: float, speed_mult: float, final_target: Vector3) -> void:
	while _path_idx < _path.size():
		var cell: Vector2i = _path[_path_idx]
		var cell_world := Vector3(cell.x, position.y, cell.y)
		var to_cell := Vector2(cell_world.x - position.x, cell_world.z - position.z)
		if to_cell.length() < PATH_CELL_ARRIVE:
			_path_idx += 1
			continue
		_move_toward(cell_world, delta, speed_mult)
		return
	# Path exhausted (or empty) — close the last sub-cell to the actual target, but
	# only if that target cell is open AND nothing is between us and it. The straight
	# _move_toward ignores collision, so without the clear-line check the sphere would
	# clip through a wall to a target on the far side (e.g. a knock origin).
	if not _cell_blocked(_world_to_cell(final_target)) and _clear_walk_to(final_target):
		_move_toward(final_target, delta, speed_mult)


func _clear_walk_to(target: Vector3) -> bool:
	# True if a straight horizontal line from the sphere to target hits no wall, so a
	# direct (collision-less) _move_toward there won't pass through geometry.
	var space := get_world_3d().direct_space_state
	var to := Vector3(target.x, global_position.y, target.z)
	var query := PhysicsRayQueryParameters3D.create(global_position, to)
	query.collision_mask = 1
	query.collide_with_areas = false
	return space.intersect_ray(query).is_empty()


func _find_path(start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	# Goal-blocked fallback: snap to closest open 8-neighbour of the goal so the
	# sphere walks to a cell adjacent to a footprint sitting on a wall edge.
	if _cell_blocked(goal):
		var best_n := Vector2i.ZERO
		var best_dist := INF
		var found := false
		for d in NEIGHBORS_8:
			var n: Vector2i = goal + d
			if _cell_blocked(n):
				continue
			var dist := float((start - n).length_squared())
			if dist < best_dist:
				best_dist = dist
				best_n = n
				found = true
		if not found:
			return []
		goal = best_n
	if _cell_blocked(start):
		return []
	if start == goal:
		var single: Array[Vector2i] = [start]
		return single
	var came_from: Dictionary = {}
	var g_score: Dictionary = {start: 0.0}
	var open: Dictionary = {start: _octile(start, goal)}
	while not open.is_empty():
		var current := _pop_lowest(open)
		if current == goal:
			return _reconstruct_path(came_from, current)
		var current_g: float = g_score[current]
		for step in NEIGHBORS_8:
			var n: Vector2i = current + step
			if _cell_blocked(n):
				continue
			# No diagonal corner cutting: both shared orthogonal cells must be
			# open so the sphere body cannot clip a wall corner.
			if step.x != 0 and step.y != 0:
				if _cell_blocked(Vector2i(current.x + step.x, current.y)) or _cell_blocked(Vector2i(current.x, current.y + step.y)):
					continue
			var move_cost := SQRT2 if (step.x != 0 and step.y != 0) else 1.0
			var tentative_g := current_g + move_cost
			if not g_score.has(n) or tentative_g < g_score[n]:
				came_from[n] = current
				g_score[n] = tentative_g
				open[n] = tentative_g + _octile(n, goal)
	return []


func _pop_lowest(open: Dictionary) -> Vector2i:
	var best: Vector2i = Vector2i.ZERO
	var best_f := INF
	for k in open.keys():
		var key: Vector2i = k
		var f: float = open[key]
		if f < best_f:
			best_f = f
			best = key
	open.erase(best)
	return best


func _octile(a: Vector2i, b: Vector2i) -> float:
	# 8-connected admissible heuristic: straight steps cost 1, diagonals SQRT2.
	var dx := float(absi(a.x - b.x))
	var dy := float(absi(a.y - b.y))
	return (dx + dy) + (SQRT2 - 2.0) * minf(dx, dy)


func _reconstruct_path(came_from: Dictionary, current: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = [current]
	while came_from.has(current):
		var prev: Vector2i = came_from[current]
		current = prev
		path.push_front(current)
	return path


func _visible_to_player() -> bool:
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(_player.global_position, global_position)
	query.collide_with_areas = false
	return space.intersect_ray(query).is_empty()


static func _make_hum_sound() -> AudioStreamWAV:
	# 147Hz fundamental + 294Hz octave + 3Hz amplitude tremolo. 14700 samples
	# (1/3s) holds an integer number of cycles for all three components, so the
	# loop seam is silent.
	var rate := 44100
	var samples := 14700
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = samples
	var data := PackedByteArray()
	data.resize(samples * 2)
	for i in samples:
		var t := float(i) * TAU / float(rate)
		var carrier := sin(t * 147.0) * 0.7 + sin(t * 294.0) * 0.3
		var tremolo := 1.0 + 0.3 * sin(t * 3.0)
		var val := int(carrier * tremolo * 24000.0)
		data[i * 2] = val & 0xFF
		data[i * 2 + 1] = (val >> 8) & 0xFF
	stream.data = data
	return stream


static func _make_sting(f0: float, f1: float, dur: float, peak: float) -> AudioStreamWAV:
	# Short non-looping tone that glides f0 -> f1 with a fast attack and an
	# exponential decay. peak (0..1) sets loudness. Used for the ? / ! / all-clear
	# transition stings.
	var rate := 44100
	var samples := int(rate * dur)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	var data := PackedByteArray()
	data.resize(samples * 2)
	var phase := 0.0
	for i in samples:
		var u := float(i) / float(samples)
		var freq := lerpf(f0, f1, u)
		phase += TAU * freq / float(rate)
		var env := minf(u / 0.04, 1.0) * exp(-3.5 * u)
		var val := int(sin(phase) * env * peak * 30000.0)
		data[i * 2] = val & 0xFF
		data[i * 2 + 1] = (val >> 8) & 0xFF
	stream.data = data
	return stream
