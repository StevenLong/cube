extends Node3D

signal entered_pursuit

const GROUND_MATERIAL := preload("res://grid_ground_material.tres")

const COLOR_PATROL := Color(0.7, 0.7, 0.75)
const COLOR_SUSPICIOUS := Color(1.0, 0.85, 0.0)
const COLOR_INVESTIGATE := Color(1.0, 0.55, 0.0)
const COLOR_SEEK := Color(0.0, 0.85, 1.0)  # electric cyan: a guard acting on echo-pyramid intel (ties the behaviour to its cause)
const COLOR_PURSUIT := Color(1.0, 0.2, 0.2)

const ARRIVE_THRESHOLD := 0.05
const INVESTIGATE_TIMEOUT := 12.0    # safety cap; a search normally ends when all tiles are checked
const SEARCH_DWELL := 0.6            # seconds paused at each checked tile so the 360 sweep can look
const SEARCH_MAX_CELLS := 5         # cap of tiles checked around a source
const SEARCH_ARRIVE := 0.35         # distance that counts as "at" a search tile
const PURSUIT_SPEED_MULT := 1.5
const PURSUIT_SPEED := 4.5  # absolute floor on pursuit speed (units/sec). Walking is 1/TUMBLE_DURATION (about 3.3 u/s), so pursuit has to beat it or the player just strolls away; sprint (about 6.7 u/s) still outruns it. A fast guard keeps speed * PURSUIT_SPEED_MULT when that is higher.
const SEEK_SPEED_MULT := 1.3  # a fast guard keeps speed*this while seeking on pyramid intel (below pursuit's 1.5)
const SEEK_SPEED := 4.0  # absolute floor (u/s) on the pyramid-intel seek: above walking (~3.3), below pursuit (4.5)
const SEEK_ARRIVE_DIST := 0.6  # within this of the revealed cell counts as arrived -> hand off to INVESTIGATE
const SEEK_TIMEOUT := 8.0  # safety cap if the cell can't be reached; pings reset it, so it won't fire while you stay in the field
const PURSUIT_GRACE := 1.2  # seconds the chaser keeps tracking the player after LoS breaks (ducking a corner), so one corner is not a free escape
const SUSPICIOUS_SPEED_MULT := 0.5
const INVESTIGATE_SPEED_MULT := 1.0
const VIEW_RADIUS := 8.0
const VIEW_CONE_COS := 0.643  # cos(50°), so a 100° total cone. Widened from 40° (N12) so a fast pass across a guard's front spends longer in view and can't be blown straight through; a true behind/side pass is still out of cone.
const FOOTPRINT_VIEW_RADIUS := 5.0
const FOOTPRINT_VIEW_CONE_COS := 0.866  # cos(30°), so a 60° total cone
const FOOTPRINT_RETARGET_DIST := 0.3
const TURN_RATE := 5.0  # rad/s — 180° in ~0.6s
const TURN_CRAWL_FRACTION := 0.5  # min fraction of speed kept through sharp turns (no dead stop)
const SPEED_RAMP := 4.0  # u/s^2 the sphere accelerates toward its commanded speed, so a jump to pursuit speed builds up over ~0.6s instead of snapping on. Higher = snappier. TUNABLE.
const AIM_TURN_RATE := 11.0  # rad/s the vision cone eases toward its look target, kept separate from body turning (N2: nav must not steer vision). Raised from 6 (N12) so the cone tracks a fast, close mover instead of lagging onto their old position while they cross in clear sight.
const CORRIDOR_HYSTERESIS := 0.2  # corridor must stay clear this long before off-grid pursuit engages
const SQRT2 := 1.4142135623730951  # diagonal step cost for 8-connected A*

const NEIGHBORS_8: Array[Vector2i] = [
	Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
	Vector2i(-1, 0), Vector2i(1, 0),
	Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1),
]
const PATH_CELL_ARRIVE := 0.15
const PURSUIT_REPATH_INTERVAL := 0.3
const PATROL_REPATH_INTERVAL := 0.5  # patrol re-plans its route this often (not just on arrival), so a gate shutting across the path is noticed and re-routed / triggers confusion instead of walking into the face forever
const EJECT_TIME := 0.15             # a guard caught in a CLOSING gate slides out over this long, toward whichever side its position is nearer (past the cell midpoint = through, else back). Overlaps the 0.25s gate rise. TUNABLE (feel).
const CONFUSION_TIME := 1.5          # a PATROL sub-beat when the route is suddenly severed (gate shut, or player blended in a chokepoint): erratic look-around, no alert. TUNABLE.
const CONFUSION_GLANCE_INTERVAL := 0.4  # a confused guard snaps to a fresh glance direction this often (the erratic tell, vs the lighthouse's smooth sweep)
const LIGHTHOUSE_SWEEP_RATE := 1.1   # rad/s a node-less / fully-sealed guard rotates in place, scanning. Slow + steady (contrast: confusion is erratic). TUNABLE.
const LIGHTHOUSE_RECHECK_INTERVAL := 1.5  # a sealed guard re-tests waypoint reachability this often, so it resumes its patrol when a gate reopens
const SILHOUETTE_ALPHA := 0.0
const ENEMY_LOS_FADE := false  # base play: enemies always visible (perfect vision). Set true for the future "blinded" debuff to fade enemies behind walls.
const VISIBILITY_LERP_RATE := 8.0
const PURSUIT_LOS_PADDING := 0.45

# Graduated detection (SPEC_graduated_detection.md). _detection in [0,1] is the
# enemy's visual certainty; thresholds drive the PATROL/SUSPICIOUS/PURSUIT ladder.
const DETECT_FILL_RATE := 2.5        # per second at full exposure factors. Raised from 2.0 (N12) so a brief but clear look across the front escalates toward PURSUIT instead of stalling at SUSPICIOUS while the target slips past.
const DETECT_DRAIN_RATE := 0.4       # per second when not seeing
const DETECT_PURSUIT_DRAIN_RATE := 0.2  # slower bleed while already in PURSUIT: a brief LoS break mid-chase (a corner, a pillar) should not de-escalate the guard. Lower = stickier pursuit. TUNABLE.
const DETECT_SUSPICIOUS := 0.25      # PATROL -> SUSPICIOUS
const DETECT_PURSUIT := 1.0          # -> PURSUIT (full bar)
const DETECT_PURSUIT_KEEP := 0.35    # stay in PURSUIT until drained below this. With the slow pursuit drain above, ~3.3s of fully lost sight before dropping to INVESTIGATE (was ~1.25s). TUNABLE.
const DETECT_MIN_PROXIMITY := 0.15   # fill floor at cone edge
const DETECT_SIZE_WEIGHT := 0.15     # per extension unit
const DETECT_ALERT_FILL_MULT := 1.5  # faster fill when already alert
const DETECT_NOISE_SEED := 0.5       # heard noise seeds detection here, then drains
const NOISE_WALL_MUFFLE := 0.70      # heard-radius fraction left when a wall blocks the sound path. Raised from 0.45 (2026-07-01): a wall-blocked sound was hard-dropped past 45% of its radius, so a sound just around a corner never reached a guard right there (read as pure line-of-sight). FEEL KNOB -- if this still reads like LoS, escalate to grid-PATH propagation (sound rounds corners; see task-list note 1 option B).
const DEBUG_DETECTION := true        # temporary on-screen _detection readout; remove with the focusing-cone task

# Focusing cone (reads _detection). The cone narrows, colour-ramps, and aims at
# the suspect as detection rises; INVESTIGATE opens to a 360 search sweep.
const CONE_FOCUS_COS := 0.97         # half-angle cos when fully locked (~14 deg)
const CONE_PATROL_ALPHA := 0.2       # cone opacity at detection 0
const CONE_LOCKED_ALPHA := 0.6       # cone opacity at detection 1
const CONE_SEARCH_ALPHA := 0.5       # rotating search cone opacity in INVESTIGATE (lock 0)
const CONE_SEARCH_HALF_COS := 0.7071 # cos(45°): a 90° rotating search cone in INVESTIGATE
const CONE_SEARCH_SWEEP_RATE := 3.0  # rad/s the INVESTIGATE cone rotates (emergency-beacon sweep)
const CONE_MAX := 8                   # cone slots in grid_ground.gdshader: one per enemy (cone_index)
const GLYPH_POP_SCALE := 1.6         # alert-glyph scale spike on a state change
const GLYPH_POP_TIME := 0.25         # seconds the glyph pop decays over

# State-encoded hum (occlusion-proof alert channel): pitch and volume rise along
# the alert ladder, indexed by State. Pitch also speeds the baked tremolo, so a
# higher alert reads as a more agitated hum even when the enemy is out of sight.
const HUM_PITCH: Array[float] = [1.0, 1.12, 1.22, 1.5, 1.35]   # PATROL/SUSPICIOUS/INVESTIGATE/PURSUIT/SEEK (indexed by the State enum)
const HUM_VOL: Array[float] = [-10.0, -9.0, -8.0, -6.0, -7.0]   # PATROL/SUSPICIOUS/INVESTIGATE/PURSUIT/SEEK (indexed by the State enum)
const HUM_LERP_RATE := 4.0           # how fast the hum eases between state targets

enum State { PATROL, SUSPICIOUS, INVESTIGATE, PURSUIT, SEEK }

@export var waypoints: Array[Vector3] = [
	Vector3(8, 0.4, 0),
	Vector3(-8, 0.4, 0),
	Vector3(-8, 0.4, 1),
	Vector3(8, 0.4, 1),
]
@export var speed: float = 2.0
@export var cone_index: int = 0  # this enemy's slot in the shared ground-cone arrays; the loader assigns one per enemy

var _target_idx := 0
var _state: State = State.PATROL
var _state_timer := 0.0
var _detection := 0.0
var _last_seen_pos := Vector3.ZERO
var _last_visible_sample := Vector3.ZERO  # cell that passed _is_seeing_player this tick; sometimes the player's center, sometimes an exposed end of an extended bar
var _trail_alpha := 0.0  # freshness of the newest print already investigated; only FRESHER prints retarget. Decays at the print fade rate so it tracks that print's own alpha: same-trail older prints never re-trigger (kills the walk-the-trail-backwards ping-pong), new prints laid later do
var _seen_footprint_alpha := 0.0  # alpha of the print _visible_footprint_pos just returned
var _material: StandardMaterial3D
var _player: Player
var _pending_sounds: Array = []
var _ground_material: ShaderMaterial
var _nav_blocked: Dictionary = {}
var _vision_exclude: Array[RID] = []  # glass-wall RIDs the LoS rays ignore (see-through-but-solid)
var _path: Array[Vector2i] = []
var _path_idx: int = 0
var _search_cells: Array[Vector2i] = []
var _search_dwell: float = 0.0
var _pursuit_repath_timer: float = 0.0
var _corridor_open_timer: float = 0.0
var _pursuit_grace: float = 0.0  # countdown of post-LoS tracking in PURSUIT (see PURSUIT_GRACE)
var _gate_blocked_now: Dictionary = {}  # per-frame snapshot of cells shut gates block (rebuilt in _refresh_gate_blocked); read by _cell_blocked so A* routes around live gate state without rebuilding the static grid
var _patrol_repath_t: float = 0.0
var _eject_t: float = 0.0         # >0 while sliding out of a gate that shut on us
var _eject_from: Vector3 = Vector3.ZERO
var _eject_to: Vector3 = Vector3.ZERO
var _confused_t: float = 0.0      # >0 during the PATROL confusion beat (route just severed)
var _glance_t: float = 0.0        # countdown to the next confused glance snap
var _glance_dir: Vector2 = Vector2(0.0, 1.0)  # current confused-look target (xz)
var _lighthouse: bool = false     # scanning in place: no reachable waypoint (or node-less)
var _lighthouse_recheck_t: float = 0.0
var _speed_mult: float = 1.0  # eased toward the commanded speed mult (see _move_toward / SPEED_RAMP) so speed changes accelerate in instead of snapping
var _visibility_alpha: float = 1.0
var _visibility_initialized: bool = false
var _debug_label: Label
var _debug_reveal: bool = false
var _scan_line: MeshInstance3D
var _alert_glyph: Label3D
var _investigate_sweep_angle: float = 0.0
var _aim_dir: Vector2 = Vector2(0.0, 1.0)  # vision-cone direction (xz); decoupled from body facing so nav can't steer the cone
var _aim_initialized: bool = false
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
	add_to_group("guards")   # echo pyramids feed position to in-range guards (reveal_player_at)
	_ground_material = GROUND_MATERIAL
	_hum_player.stream = _make_hum_sound()
	_hum_player.play()
	_setup_stings()
	_setup_alert_glyph()
	_setup_scan_line()
	_build_nav_grid()
	# Glass walls are solid to bodies but transparent to vision: collect their RIDs
	# so the LoS rays below see straight through them (see _make_glass_rect, group "glass").
	for g in get_tree().get_nodes_in_group("glass"):
		if g is CollisionObject3D:
			_vision_exclude.append((g as CollisionObject3D).get_rid())
	if waypoints.size() > 0:
		_set_path_to(waypoints[_target_idx])
	if DEBUG_DETECTION:
		_setup_debug_label()


func _process(delta: float) -> void:
	_advance_pending_sounds(delta)
	_refresh_gate_blocked()   # snapshot shut-gate cells once; A* + the move backstop read it this frame
	_maybe_eject()            # start a slide-out if a gate just shut on our cell
	_trail_alpha = maxf(_trail_alpha - delta / Player.FOOTPRINT_FADE_TIME, 0.0)
	_update_aim(delta)
	var seeing := _is_seeing_player()
	if seeing:
		# Use the actually-visible cell, not the player's centre, so investigating
		# after losing sight heads toward where the exposed end was, not the (hidden)
		# base of an extended bar.
		_last_seen_pos = _last_visible_sample
	_update_detection(delta, seeing)

	var footprint_pos := Vector3.INF
	if not seeing and _state != State.PURSUIT and _state != State.SEEK:
		footprint_pos = _visible_footprint_pos()

	match _state:
		State.PATROL:
			_patrol(delta)
			if _detection >= DETECT_SUSPICIOUS:
				_enter_state(State.SUSPICIOUS)
			elif footprint_pos != Vector3.INF:
				_last_seen_pos = Vector3(footprint_pos.x, position.y, footprint_pos.z)
				_trail_alpha = _seen_footprint_alpha
				_enter_state(State.INVESTIGATE)
		State.SUSPICIOUS:
			if _detection >= DETECT_PURSUIT:
				_enter_state(State.PURSUIT)
			elif _detection < DETECT_SUSPICIOUS:
				_enter_state(State.PATROL)
			elif footprint_pos != Vector3.INF:
				_last_seen_pos = Vector3(footprint_pos.x, position.y, footprint_pos.z)
				_trail_alpha = _seen_footprint_alpha
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
						_trail_alpha = _seen_footprint_alpha
						_begin_search(_world_to_cell(_last_seen_pos))
						_state_timer = 0.0
				_investigate_search(delta)
				# Give up once every tile around the source is checked (or the safety cap).
				if _search_cells.is_empty() or _state_timer >= INVESTIGATE_TIMEOUT:
					_enter_state(State.PATROL)
		State.PURSUIT:
			# Keep tracking the player for a short grace after LoS breaks (e.g. ducking around
			# a corner right in front), so a single corner is not a free escape -- shaking the
			# guard takes real distance or several breaks. Re-seeing refreshes the grace.
			if seeing:
				_pursuit_grace = PURSUIT_GRACE
			elif _pursuit_grace > 0.0:
				_pursuit_grace = maxf(_pursuit_grace - delta, 0.0)
				_last_seen_pos = Vector3(_player.position.x, position.y, _player.position.z)
			_pursue(delta)
			if _detection < DETECT_PURSUIT_KEEP:
				_last_seen_pos = Vector3(_last_seen_pos.x, position.y, _last_seen_pos.z)
				_enter_state(State.INVESTIGATE)
		State.SEEK:
			# Charge the exact revealed cell on perfect pyramid intel. Escalate to a real
			# chase if the cone actually catches sight; otherwise drive there and, on arrival
			# (or the safety cap) with no fresh ping, hand off to the local search.
			if _detection >= DETECT_PURSUIT:
				_enter_state(State.PURSUIT)
			else:
				_seek(delta)
				_state_timer += delta
				var seek_d := Vector2(position.x, position.z).distance_to(
					Vector2(_last_seen_pos.x, _last_seen_pos.z))
				if seek_d < SEEK_ARRIVE_DIST or _state_timer >= SEEK_TIMEOUT:
					_enter_state(State.INVESTIGATE)

	# Ejection slide overrides whatever the state logic just did to position: a short
	# ease to the open side we were shoved toward, running under the gate's own rise.
	if _eject_t > 0.0:
		_eject_t = maxf(_eject_t - delta, 0.0)
		var u := 1.0 - _eject_t / EJECT_TIME
		u = 1.0 - (1.0 - u) * (1.0 - u)   # ease-out
		position = _eject_from.lerp(_eject_to, u)

	var target_alpha := 1.0 if (not ENEMY_LOS_FADE or _debug_reveal or _visible_to_player()) else SILHOUETTE_ALPHA
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
	_update_scan_line(seeing, footprint_pos)


func _update_aim(delta: float) -> void:
	# The vision cone's direction, kept SEPARATE from the body's movement facing (N2).
	# Welding the cone to travel direction caused an oscillation: a nav reroute around a
	# corner swung the cone off the suspect -> sight lost -> de-escalate -> reroute back
	# -> re-spot, forever. Now any alert state locks the cone onto the last-seen cell
	# while the body moves along its nav path; PATROL looks where it walks, drifting
	# toward a rising suspect (detection-weighted) as a telegraph. Uses last frame's
	# _last_seen_pos to avoid a circular dependency with _is_seeing_player.
	var body_fwd := -global_transform.basis.z
	body_fwd.y = 0.0
	var base := Vector2(body_fwd.x, body_fwd.z)
	base = base.normalized() if base.length() > 0.0001 else _aim_dir
	var look_target := base
	var to_suspect := Vector2(_last_seen_pos.x - position.x, _last_seen_pos.z - position.z)
	if _state != State.PATROL and to_suspect.length() > 0.05:
		look_target = to_suspect.normalized()
	elif _detection > 0.001 and to_suspect.length() > 0.05:
		var blended := base.lerp(to_suspect.normalized(), _detection)
		if blended.length() > 0.01:
			look_target = blended.normalized()
	if not _aim_initialized:
		_aim_dir = look_target
		_aim_initialized = true
		return
	var eased := _aim_dir.lerp(look_target, minf(delta * AIM_TURN_RATE, 1.0))
	_aim_dir = eased.normalized() if eased.length() > 0.001 else look_target


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
		# Pursuit holds on harder: drain slower while chasing so a momentary LoS break
		# (rounding a corner, a pillar) doesn't immediately bleed off the lock.
		var drain := DETECT_PURSUIT_DRAIN_RATE if _state == State.PURSUIT else DETECT_DRAIN_RATE
		_detection -= drain * delta
	_detection = clampf(_detection, 0.0, 1.0)


func _patrol(delta: float) -> void:
	# Sub-modes kept OFF the State enum (so the [_state]-indexed hum/colour arrays don't grow --
	# that was the SEEK crash): CONFUSED = a brief erratic "huh, a wall?" glance after the route
	# is suddenly severed; LIGHTHOUSE = scan in place when nothing is reachable (or there are no
	# nodes). Both stay PATROL-tier, so the escalation check in the caller still spots the player.
	if _confused_t > 0.0:
		_confused_glance(delta)
		_confused_t -= delta
		if _confused_t <= 0.0:
			_resettle_patrol()
		return
	if _lighthouse:
		_lighthouse_scan(delta)
		_lighthouse_recheck_t -= delta
		if _lighthouse_recheck_t <= 0.0:
			_lighthouse_recheck_t = LIGHTHOUSE_RECHECK_INTERVAL
			var wp := _first_reachable_waypoint()
			if wp >= 0:   # a gate reopened -> resume the real patrol
				_lighthouse = false
				_target_idx = wp
				_set_path_to(waypoints[_target_idx])
				_patrol_repath_t = PATROL_REPATH_INTERVAL
		return
	if waypoints.size() < 2:
		_enter_lighthouse()   # node-less: scan in place instead of sitting dead
		return
	var target: Vector3 = waypoints[_target_idx]
	if (target - position).length() < ARRIVE_THRESHOLD:
		_target_idx = (_target_idx + 1) % waypoints.size()
		_set_path_to(waypoints[_target_idx])
		_patrol_repath_t = PATROL_REPATH_INTERVAL
		if _path.is_empty():
			_enter_confusion()   # the next leg is sealed
		return
	# Re-plan periodically, not only on arrival: a gate shutting ACROSS the current leg leaves a
	# stale path that would walk us into the gate face forever (we'd never arrive). An empty
	# re-plan means the leg was just severed -> confusion. A reroute (start/goal-snap found a
	# detour) keeps a non-empty path, so we just quietly go around -- confusion is severance-only.
	_patrol_repath_t -= delta
	if _patrol_repath_t <= 0.0:
		_set_path_to(target)
		_patrol_repath_t = PATROL_REPATH_INTERVAL
		if _path.is_empty():
			_enter_confusion()
			return
	_follow_path(delta, 1.0, target)


func _enter_confusion() -> void:
	_confused_t = CONFUSION_TIME
	_glance_t = 0.0   # snap a fresh glance on the first frame
	_path = []
	_path_idx = 0


func _confused_glance(delta: float) -> void:
	# Erratic look-around: snap to a fresh direction every CONFUSION_GLANCE_INTERVAL and turn the
	# body toward it (the cone follows via _update_aim). Quick + jittery reads as "huh?", distinct
	# from the lighthouse's smooth sweep. Stationary for now; small wander is a feel-check add.
	_glance_t -= delta
	if _glance_t <= 0.0:
		_glance_t = CONFUSION_GLANCE_INTERVAL
		var ang := randf() * TAU
		_glance_dir = Vector2(cos(ang), sin(ang))
	_turn_body_toward(_glance_dir, delta)


func _lighthouse_scan(delta: float) -> void:
	rotate(Vector3.UP, LIGHTHOUSE_SWEEP_RATE * delta)   # slow steady spin; the vision cone follows via _update_aim


func _enter_lighthouse() -> void:
	_lighthouse = true
	_lighthouse_recheck_t = LIGHTHOUSE_RECHECK_INTERVAL
	_path = []
	_path_idx = 0


func _resettle_patrol() -> void:
	# Confusion over: patrol whatever is still reachable (keeping patrol order), else lighthouse.
	var wp := _first_reachable_waypoint()
	if wp >= 0:
		_target_idx = wp
		_set_path_to(waypoints[_target_idx])
		_patrol_repath_t = PATROL_REPATH_INTERVAL
	else:
		_enter_lighthouse()


func _first_reachable_waypoint() -> int:
	# First reachable waypoint scanning forward from the current target (so a corralled guard
	# keeps its patrol order), or -1 if none can be reached right now. _find_path start-snaps,
	# so this works even while we sit on a blocked cell.
	if waypoints.size() < 2:
		return -1
	var start := _world_to_cell(position)
	for i in waypoints.size():
		var idx: int = (_target_idx + i) % waypoints.size()
		if _find_path(start, _world_to_cell(waypoints[idx])).size() > 0:
			return idx
	return -1


func _turn_body_toward(dir: Vector2, delta: float) -> void:
	if dir.length_squared() < 0.0001:
		return
	var want := Vector3(dir.x, 0.0, dir.y).normalized()
	var fwd := -global_transform.basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 0.0001:
		return
	fwd = fwd.normalized()
	var off := fwd.signed_angle_to(want, Vector3.UP)
	rotate(Vector3.UP, clampf(off, -TURN_RATE * delta, TURN_RATE * delta))


func _creep(delta: float) -> void:
	_follow_path(delta, SUSPICIOUS_SPEED_MULT, _last_seen_pos)


func _pursue(delta: float) -> void:
	# Chase _last_seen_pos (the last visible cell), not the player's origin: for an
	# extended bar that is the exposed end currently in view, so the sphere closes on
	# what it can actually see instead of pathing toward the hidden base cell.
	# Pursuit speed has an absolute floor (PURSUIT_SPEED) so a walking player can't
	# stroll away from any guard, whatever its patrol speed; a fast guard keeps the
	# higher speed * PURSUIT_SPEED_MULT. Expressed as the mult _move_toward expects.
	var pmult := maxf(PURSUIT_SPEED_MULT, PURSUIT_SPEED / maxf(speed, 0.01))
	_chase(_last_seen_pos, delta, pmult)


func _seek(delta: float) -> void:
	# Aggressive directed seek on perfect pyramid intel: the same hybrid locomotion as
	# pursuit but at the lower SEEK floor, charging the exact revealed cell.
	var smult := maxf(SEEK_SPEED_MULT, SEEK_SPEED / maxf(speed, 0.01))
	_chase(_last_seen_pos, delta, smult)


func _chase(target: Vector3, delta: float, mult: float) -> void:
	# Hybrid locomotion shared by PURSUIT and SEEK: go off-grid straight at the target once
	# a sphere-wide corridor has stayed clear for CORRIDOR_HYSTERESIS (debounces the per-frame
	# ray check so it does not jitter at a corner); otherwise A* repath. Any block resets the
	# timer and falls back to A* immediately, the safe choice near walls.
	if _has_pursuit_corridor(target):
		_corridor_open_timer += delta
	else:
		_corridor_open_timer = 0.0
	if _corridor_open_timer >= CORRIDOR_HYSTERESIS:
		_path = []
		_path_idx = 0
		_pursuit_repath_timer = 0.0
		_move_toward(target, delta, mult)
		return
	_pursuit_repath_timer -= delta
	if _pursuit_repath_timer <= 0.0:
		_set_path_to(target)
		_pursuit_repath_timer = PURSUIT_REPATH_INTERVAL
	_follow_path(delta, mult, target)


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
	# Walls clear is not enough: the straight line must also run over floor the
	# whole way, or off-grid pursuit cuts across a void gap the A* grid would
	# have routed around.
	return _line_on_floor(from, to)


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
	# Ease the commanded multiplier toward its target at a fixed acceleration so the
	# jump to pursuit speed builds up instead of snapping on. Ramp in velocity space
	# (divide by speed) so the build-up time is consistent whatever the base speed.
	_speed_mult = move_toward(_speed_mult, speed_mult, SPEED_RAMP / maxf(speed, 0.01) * delta)
	var step := minf(speed * _speed_mult * speed_factor * delta, distance)
	# Backstop for every locomotion path: never step onto a non-floor cell. The
	# corridor/clear-walk checks gate the big moves; this catches the rest (and
	# stalls the sphere at a gap edge instead of letting it float across).
	var next_pos := position + horizontal_dir * step
	var next_cell := Vector2i(roundi(next_pos.x), roundi(next_pos.z))
	if not _level.is_floor(next_cell) or _gate_blocked_now.has(next_cell):
		# Stall at a gap edge OR a gate face instead of clipping across it during the
		# ~0.3s repath window (the corridor/A* checks gate the big moves; this the rest).
		return
	position = next_pos


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
		_lighthouse = false
		_confused_t = 0.0
		if waypoints.size() >= 2:
			_target_idx = _closest_waypoint_idx()
			_set_path_to(waypoints[_target_idx])
			_patrol_repath_t = PATROL_REPATH_INTERVAL
		else:
			_enter_lighthouse()   # node-less guard returns to scanning, not to an empty-waypoint crash
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
	if new_state == State.SEEK:
		# Seed the path to the revealed cell; the shared chase locomotion takes over per frame.
		_set_path_to(_last_seen_pos)
		_pursuit_repath_timer = PURSUIT_REPATH_INTERVAL
		_corridor_open_timer = 0.0
		_pending_sounds.clear()  # perfect intel: ignore noise distractions like pursuit does


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
		State.SEEK: return COLOR_SEEK
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
		State.SEEK: return "SEEK"
		State.PURSUIT: return "PURSUIT"
		_: return "PATROL"


func _unhandled_input(event: InputEvent) -> void:
	# Debug reveal toggle (V): x-ray the enemy body + glyph so its motion can be
	# watched while occluded. The last-known ghost is a separate gameplay cue.
	if event.is_action_pressed("debug_reveal"):
		_debug_reveal = not _debug_reveal


func _setup_scan_line() -> void:
	# Active line-of-sight readout (N10): a thin emissive beam the enemy draws to
	# whatever it directly sees right now (the player, or a footprint it has eyes on).
	# Replaces the last-known ghost marker: instead of "the search is here" it shows
	# "I can see you THERE, right now." Tinted by alert state so it carries the threat
	# level. top_level keeps it in world space so both endpoints are set directly.
	_scan_line = MeshInstance3D.new()
	_scan_line.top_level = true
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.02
	mesh.bottom_radius = 0.02
	mesh.height = 1.0
	mesh.radial_segments = 6
	mesh.rings = 0
	_scan_line.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	_scan_line.material_override = mat
	_scan_line.visible = false
	add_child(_scan_line)


func _update_debug_reveal() -> void:
	# Debug x-ray only: draw the enemy body + glyph through walls while revealed.
	_material.no_depth_test = _debug_reveal
	if _alert_glyph != null:
		_alert_glyph.no_depth_test = _debug_reveal


func _update_scan_line(seeing: bool, footprint_pos: Vector3) -> void:
	# Draw the beam only while the enemy has direct sight of its focus: the player
	# when seen, otherwise a footprint currently in view. No sight -> no line (the
	# search cone carries the lost-sight case now that the ghost is gone).
	if _scan_line == null:
		return
	var target := Vector3.INF
	if seeing:
		target = _last_visible_sample
	elif footprint_pos != Vector3.INF:
		target = Vector3(footprint_pos.x, 0.5, footprint_pos.z)
	if target == Vector3.INF:
		_scan_line.visible = false
		return
	var a := global_position
	var dir := target - a
	var length := dir.length()
	if length < 0.01:
		_scan_line.visible = false
		return
	_scan_line.visible = true
	# Orient the unit cylinder (its local Y is its length) along the sightline and
	# scale that axis to the distance, so the beam spans enemy -> target exactly.
	var beam_basis := Basis(Quaternion(Vector3.UP, dir / length)) * Basis.from_scale(Vector3(1.0, length, 1.0))
	_scan_line.global_transform = Transform3D(beam_basis, a + dir * 0.5)
	var col := _state_color()
	var mat := _scan_line.material_override as StandardMaterial3D
	mat.albedo_color = col
	mat.emission = col


func _on_player_noise(origin: Vector2, max_radius: float, duration: float) -> void:
	# Pursuit/seek are locked on and ignore noise entirely, so don't even queue it: a knock
	# fired mid-chase must not be able to land as an investigate after the lock drops.
	if _state == State.PURSUIT or _state == State.SEEK:
		return
	var enemy_xz := Vector2(position.x, position.z)
	var dist := enemy_xz.distance_to(origin)
	if dist > max_radius:
		return
	# Walls muffle: a blocked sound path cuts the heard radius hard, so a loud
	# step on the far side of a wall no longer reads as a precise beacon. A
	# knock's origin sits INSIDE the knocked wall and rays ignore the shape they
	# start in, so a knock still carries through its own wall (the lure works)
	# but is muffled by any further wall.
	if not _noise_path_clear(origin) and dist > max_radius * NOISE_WALL_MUFFLE:
		return
	var delay := dist * duration / max_radius
	_pending_sounds.append({ "origin": origin, "delay": delay })


func _noise_path_clear(origin: Vector2) -> bool:
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		Vector3(origin.x, 0.5, origin.y),
		Vector3(global_position.x, 0.5, global_position.z)
	)
	query.collision_mask = 1
	query.collide_with_areas = false
	return space.intersect_ray(query).is_empty()


func _advance_pending_sounds(delta: float) -> void:
	for i in range(_pending_sounds.size() - 1, -1, -1):
		_pending_sounds[i].delay -= delta
		if _pending_sounds[i].delay <= 0.0:
			var origin: Vector2 = _pending_sounds[i].origin
			_pending_sounds.remove_at(i)
			_on_sound_heard(origin)


func _on_sound_heard(origin: Vector2) -> void:
	# A noise is a located clue, so go investigate the source (this is what makes
	# knocking a usable lure). Pursuit/seek ignore noise — already locked on better intel.
	if _state == State.PURSUIT or _state == State.SEEK:
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


func reveal_player_at(pos: Vector3) -> void:
	# An echo pyramid hands this guard the player's exact position with no LoS/wall gating
	# (perfect intel = the pyramid defeats cover): aggressively SEEK the exact cell. A guard
	# already in PURSUIT keeps its own tighter lock. Each ping refreshes the live target and
	# resets the give-up timer, so cover only helps once you LEAVE the field (pings stop, the
	# guard reaches the stale cell and drops to a local INVESTIGATE).
	_last_seen_pos = Vector3(pos.x, position.y, pos.z)
	if _state == State.PURSUIT:
		# Already chasing: act on the fresh intel at once -- refresh the lock and repath to the
		# new cell instead of playing out the stale pursue/de-escalate cycle.
		_detection = maxf(_detection, DETECT_PURSUIT)
		_pursuit_grace = PURSUIT_GRACE
		_set_path_to(_last_seen_pos)
		_pursuit_repath_timer = PURSUIT_REPATH_INTERVAL
		return
	if _state == State.SEEK:
		_state_timer = 0.0
		_set_path_to(_last_seen_pos)
	else:
		_enter_state(State.SEEK)


func _is_seeing_player() -> bool:
	# Cone + LoS check across the player's whole footprint AND height, not just
	# its centre: an extended bar's end poking out of cover is detectable when
	# the base cell's ray is occluded, and a TALL cube poking above a 1u wall is
	# seen over it (tall = exposed, the symmetric half of periscope; this is also
	# what lets the enemy see over a safety_edge). One sample per unit cell of
	# the cuboid: column gates (range, cone) run once per column, then a ray per
	# height. INVESTIGATE drops the cone filter (active 360° scan). First sample
	# that passes all gates wins.
	# Blending normally defeats vision outright. The exception: a guard already in
	# PURSUIT watched the cube drop into cover, so blending right in front of an active
	# pursuer is not an escape. We fall through to the cone + LoS test below, which still
	# returns false if the cube is actually out of sight (occluded, or outside the cone /
	# range) — so blending behind cover mid-pursuit, or in any lower alert state, still works.
	if _player.is_blending and _state != State.PURSUIT:
		return false
	var cone_active := _state != State.INVESTIGATE
	var forward := Vector3.ZERO
	if cone_active:
		# Cone direction is _aim_dir (decoupled from body facing, see _update_aim), so a
		# nav reroute does not pull the detection cone off the suspect.
		forward = Vector3(_aim_dir.x, 0.0, _aim_dir.y)
	var space := get_world_3d().direct_space_state
	# During a dodge the cube is a 1x1 sliding between cells; track its VISUAL
	# position, not grid_pos (which snapped to the landing cell when the dodge
	# began). Without this the enemy "sees" the destination from frame one, so a
	# dodge toward cover dropped detection like a smoke bomb while the cube was
	# still out in the open. Now a dodge only escapes when the geometry actually
	# breaks line of sight.
	var fmin: Vector2i
	var dims: Vector3i
	if _player.is_dodging():
		fmin = Vector2i(roundi(_player.global_position.x), roundi(_player.global_position.z))
		dims = Vector3i.ONE
	else:
		fmin = _player.get_footprint_min()
		dims = _player.get_dimensions()
	for dx in range(dims.x):
		for dz in range(dims.z):
			var to_sample := Vector3(fmin.x + dx, 0.0, fmin.y + dz) - global_position
			to_sample.y = 0.0
			var dist := to_sample.length()
			if dist < 0.01 or dist > VIEW_RADIUS:
				continue
			if cone_active and (to_sample / dist).dot(forward) < VIEW_CONE_COS:
				continue
			for dy in range(dims.y):
				var sample := Vector3(fmin.x + dx, 0.5 + dy, fmin.y + dz)
				var query := PhysicsRayQueryParameters3D.create(global_position, sample)
				query.collide_with_areas = false
				query.exclude = _vision_exclude   # glass is see-through
				if space.intersect_ray(query).is_empty():
					_last_visible_sample = sample
					return true
	return false


func _visible_footprint_pos() -> Vector3:
	# Returns the freshest in-view footprint with unobstructed LoS, so the search
	# heads up the trail toward the player instead of back down it. get_footprint_
	# positions is oldest -> newest, so we walk it newest-first and take the first hit.
	# Pickup is cone-gated in EVERY state (N16): the guard must be LOOKING toward a print
	# to notice it, so it follows the trail by sweeping its gaze onto prints instead of
	# snapping to the freshest one anywhere in range. PATROL/SUSPICIOUS use the forward
	# detection aim with the narrow footprint cone; INVESTIGATE uses its rotating search
	# beam (the same beam the floor beacon shows, via _search_beam_dir) with the wider
	# search cone, so the beam visibly crossing the trail is what triggers the pickup.
	var positions: PackedVector2Array = _player.get_footprint_positions()
	if positions.is_empty():
		return Vector3.INF
	var alphas: PackedFloat32Array = _player.get_footprint_alphas()
	var forward: Vector3
	var cone_cos: float
	if _state == State.INVESTIGATE:
		var beam := _search_beam_dir()
		forward = Vector3(beam.x, 0.0, beam.y)
		cone_cos = CONE_SEARCH_HALF_COS
	else:
		forward = Vector3(_aim_dir.x, 0.0, _aim_dir.y)   # same decoupled aim as the body cone
		cone_cos = FOOTPRINT_VIEW_CONE_COS
	var origin := global_position
	var space := get_world_3d().direct_space_state
	for i in range(positions.size() - 1, -1, -1):
		# Trail memory: skip prints no fresher than the newest one already
		# investigated. _trail_alpha decays in lockstep with print fade, so the
		# cleared trail stays cleared while later prints still qualify.
		if alphas[i] <= _trail_alpha:
			continue
		# N8: never react to a print on a cell the player currently occupies. A fresh
		# print under a hidden cube otherwise pins the search onto the exact hiding spot
		# and re-triggers alerts until it fades; the trail just behind them still leads here.
		if _player.footprint_covers(Vector2i(roundi(positions[i].x), roundi(positions[i].y))):
			continue
		var p := positions[i]
		var fp_world := Vector3(p.x, 0.05, p.y)
		var delta_xz := Vector3(fp_world.x - origin.x, 0.0, fp_world.z - origin.z)
		var dist := delta_xz.length()
		if dist < 0.01 or dist > FOOTPRINT_VIEW_RADIUS:
			continue
		var dir := delta_xz / dist
		if dir.dot(forward) < cone_cos:
			continue
		var query := PhysicsRayQueryParameters3D.create(origin, fp_world)
		query.collide_with_areas = false
		query.exclude = _vision_exclude   # glass is see-through
		if space.intersect_ray(query).is_empty():
			_seen_footprint_alpha = alphas[i]
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
	var origin := Vector2(position.x, position.z)
	if _state == State.INVESTIGATE:
		_update_search_cone(delta, origin)
		return

	# Visual ladder: the cone is the detection fill. As _detection rises it narrows
	# toward a tight beam and ramps grey -> yellow -> red. It points along _aim_dir, the
	# SAME direction the detection test uses (see _update_aim), so what you see is what it
	# can detect, and the cone tracks the suspect during alert instead of the body's path.
	var half_cos := lerpf(VIEW_CONE_COS, CONE_FOCUS_COS, _detection)
	var col := _detection_color(_detection)
	var alpha := lerpf(CONE_PATROL_ALPHA, CONE_LOCKED_ALPHA, _detection)
	# Independent of _visibility_alpha: the floor cone stays readable when the enemy
	# body is occluded. The shader's per-pixel LoS still hides cone on unseen ground.
	_write_cone(origin, _aim_dir, VIEW_RADIUS, half_cos, _color_to_vec3(col), alpha)


func _update_search_cone(delta: float, origin: Vector2) -> void:
	# Active search: a 90° cone sweeps the floor like a rotating beacon. As
	# certainty (lock) climbs back toward pursuit the sweep slows and stops, the
	# cone narrows toward the focus beam, slides orange -> red, and homes on the
	# suspect. At lock 1 this matches the PURSUIT branch exactly, so the handoff
	# is a continuous focus rather than a snap.
	var lock := clampf((_detection - DETECT_SUSPICIOUS) / (DETECT_PURSUIT - DETECT_SUSPICIOUS), 0.0, 1.0)
	_investigate_sweep_angle += CONE_SEARCH_SWEEP_RATE * (1.0 - lock) * delta
	var aim := _search_beam_dir()
	var half_cos := lerpf(CONE_SEARCH_HALF_COS, CONE_FOCUS_COS, lock)
	var col := COLOR_INVESTIGATE.lerp(COLOR_PURSUIT, lock)
	var alpha := lerpf(CONE_SEARCH_ALPHA, CONE_LOCKED_ALPHA, lock)
	# Independent of _visibility_alpha (see _update_cone_uniforms): the search cone
	# stays visible on seen ground even when the enemy itself is behind a wall.
	_write_cone(origin, aim, VIEW_RADIUS, half_cos, _color_to_vec3(col), alpha)


func _search_beam_dir() -> Vector2:
	# Direction of the INVESTIGATE rotating search beam: the swept angle, homing toward
	# the suspect as lock (re-acquisition certainty) rises. Shared by the visible floor
	# cone (_update_search_cone) and footprint pickup (_visible_footprint_pos) so the beam
	# you SEE is exactly what can notice a print (N16). Reads the current sweep angle;
	# _update_search_cone owns advancing it.
	var sweep := Vector2(cos(_investigate_sweep_angle), sin(_investigate_sweep_angle))
	var lock := clampf((_detection - DETECT_SUSPICIOUS) / (DETECT_PURSUIT - DETECT_SUSPICIOUS), 0.0, 1.0)
	var to_suspect := Vector2(_last_seen_pos.x - position.x, _last_seen_pos.z - position.z)
	if to_suspect.length() > 0.05:
		var blended := sweep.lerp(to_suspect.normalized(), lock)
		if blended.length() > 0.01:
			return blended.normalized()
	return sweep


func _write_cone(origin: Vector2, dir: Vector2, radius: float, half_cos: float, col: Vector3, alpha: float) -> void:
	# Each enemy owns one slot (cone_index) in the shared ground material, so many
	# cones coexist instead of stomping a single set of uniforms. We touch only our
	# own slot; _process runs sequentially, so this read-modify-write is race-free.
	if cone_index < 0 or cone_index >= CONE_MAX:
		return
	var origins: PackedVector2Array = _ground_material.get_shader_parameter("cone_origins")
	var dirs: PackedVector2Array = _ground_material.get_shader_parameter("cone_dirs")
	var radii: PackedFloat32Array = _ground_material.get_shader_parameter("cone_radii")
	var halves: PackedFloat32Array = _ground_material.get_shader_parameter("cone_half_angle_cos")
	var colors: PackedVector3Array = _ground_material.get_shader_parameter("cone_colors")
	var alphas: PackedFloat32Array = _ground_material.get_shader_parameter("cone_alphas")
	origins[cone_index] = origin
	dirs[cone_index] = dir
	radii[cone_index] = radius
	halves[cone_index] = half_cos
	colors[cone_index] = col
	alphas[cone_index] = alpha
	_ground_material.set_shader_parameter("cone_origins", origins)
	_ground_material.set_shader_parameter("cone_dirs", dirs)
	_ground_material.set_shader_parameter("cone_radii", radii)
	_ground_material.set_shader_parameter("cone_half_angle_cos", halves)
	_ground_material.set_shader_parameter("cone_colors", colors)
	_ground_material.set_shader_parameter("cone_alphas", alphas)


func _exit_tree() -> void:
	# Leaving the scene: zero our cone slot so a later scene with fewer enemies does
	# not inherit a stale cone in the shared ground material (radii[i] <= 0 disables
	# the slot in the shader).
	if _ground_material == null or cone_index < 0 or cone_index >= CONE_MAX:
		return
	var radii: PackedFloat32Array = _ground_material.get_shader_parameter("cone_radii")
	if cone_index < radii.size():
		radii[cone_index] = 0.0
		_ground_material.set_shader_parameter("cone_radii", radii)


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
		State.SEEK:
			glyph = "!"
			col = COLOR_SEEK
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
	if _gate_blocked_now.has(cell):   # a shut gate blocks its whole span, live (see _refresh_gate_blocked)
		return true
	# A hiding player counts as a wall to pathfinding: they "look like part of
	# the wall," so the enemy plans around the footprint instead of barging in.
	# Gated on is_hiding (still + in cover) not is_blending (full phase), so the
	# nav block engages the moment the player settles into cover, before the visual
	# fade completes; the 0.4s ramp window would otherwise let the enemy walk in.
	# _find_path already snaps a blocked goal to the nearest open neighbour, so
	# investigating a noise at the player's cell ends at the cell next to them.
	# EXCEPT in PURSUIT: an active pursuer watched the cube dive into cover (the same
	# reason vision sees through blend mid-pursuit, _is_seeing_player), so it must be
	# able to path onto the hide cell and make contact instead of parking next to it
	# forever (N15). Drop out of PURSUIT and the block re-engages, so the hide spot
	# protects again the instant the guard loses the lock.
	if _state != State.PURSUIT and _player.is_hiding and _player.footprint_covers(cell):
		return true
	return false


func _world_to_cell(p: Vector3) -> Vector2i:
	return Vector2i(roundi(p.x), roundi(p.z))


func _refresh_gate_blocked() -> void:
	# Once-per-frame snapshot of every cell a currently-shut gate blocks. _cell_blocked and
	# the _move_toward backstop read this, so A* routes around live gate state without touching
	# the static _nav_blocked grid. ponytail: O(gates * cells) per guard per frame -- fine for
	# a handful of gates; cache-on-gate-state-change only if a level ever runs many big gates.
	_gate_blocked_now.clear()
	for g in get_tree().get_nodes_in_group("gates"):
		for c in g.blocked_cells():
			_gate_blocked_now[c] = true


func _maybe_eject() -> void:
	# A gate that shut on our cell shoves us out to the nearer open side. "Nearest open cell to
	# our ACTUAL sub-cell position" gives the fairness rule for free: past the gate midpoint we
	# are closer to the far side (ejected through), before it the near side (ejected back).
	if _eject_t > 0.0:
		return
	var here := _world_to_cell(position)
	if not _gate_blocked_now.has(here):
		return
	var dest := _nearest_open_cell(position)
	if dest == here:   # no open neighbour -> stay put, the start-snap repath will get us out
		return
	_eject_from = position
	_eject_to = Vector3(dest.x, position.y, dest.y)
	_eject_t = EJECT_TIME


func _nearest_open_cell(from: Vector3) -> Vector2i:
	# Nearest 8-neighbour cell that is open (floor, not gate/wall blocked, not a hide cell) to
	# the actual position `from`, so the shove picks the side we are physically closest to.
	# Returns the (blocked) current cell if none is open -- callers treat that as "no eject".
	var here := _world_to_cell(from)
	var best := here
	var best_d := INF
	for d in NEIGHBORS_8:
		var c: Vector2i = here + d
		if _cell_blocked(c):
			continue
		var dx := float(c.x) - from.x
		var dz := float(c.y) - from.z
		var dist := dx * dx + dz * dz
		if dist < best_d:
			best_d = dist
			best = c
	return best


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
	# True if a straight horizontal line from the sphere to target hits no wall AND
	# stays over floor, so a direct (collision-less) _move_toward there won't pass
	# through geometry or float across a void gap.
	var space := get_world_3d().direct_space_state
	var to := Vector3(target.x, global_position.y, target.z)
	var query := PhysicsRayQueryParameters3D.create(global_position, to)
	query.collision_mask = 1
	query.collide_with_areas = false
	if not space.intersect_ray(query).is_empty():
		return false
	return _line_on_floor(global_position, to)


func _line_on_floor(from: Vector3, to: Vector3) -> bool:
	# Every cell under the segment must be floor, sampled at half-cell steps.
	# Rays only catch walls; a missing floor tile blocks nothing physically, so
	# the off-grid movement paths have to check it explicitly.
	var delta := Vector3(to.x - from.x, 0.0, to.z - from.z)
	var dist := delta.length()
	var steps := maxi(1, ceili(dist * 2.0))
	for i in range(steps + 1):
		var p := from + delta * (float(i) / float(steps))
		if not _level.is_floor(Vector2i(roundi(p.x), roundi(p.z))):
			return false
	return true


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
		# Symmetric to the goal snap above: a guard sitting on a cell that just became blocked
		# (a gate shut on it, a player blended onto it) plans from its nearest open neighbour
		# toward the goal instead of returning [] and freezing. The guard then walks out onto it.
		var best_s := Vector2i.ZERO
		var best_sd := INF
		var found_s := false
		for d in NEIGHBORS_8:
			var n: Vector2i = start + d
			if _cell_blocked(n):
				continue
			var dist := float((goal - n).length_squared())
			if dist < best_sd:
				best_sd = dist
				best_s = n
				found_s = true
		if not found_s:
			return []
		start = best_s
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
	query.exclude = _vision_exclude   # glass is see-through
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
