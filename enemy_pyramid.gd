extends Node3D

# Echo Pyramid: a stationary floating sonar pylon (design grill 2026-06-27). It
# defeats cover. On a fixed beat it fires a detection front that expands from its
# centre to `radius`; the player is caught the instant the front reaches their cell
# while inside the radius. A catch feeds the player's exact position to every guard
# CURRENTLY inside the radius (sets _last_seen_pos + kicks it to INVESTIGATE, bypassing
# LoS/walls) -- so a guard in the field can't be shaken by cover. No standalone fail,
# no global alert, no links: a lone pyramid with no guard in its field is inert.
# Pure range/timing (shape ignored). All tunable per-instance.
#
# The danger zone + expanding front are drawn by the ground shader on the FLOOR TILES
# (per-slot pyr_* uniforms), so they never overhang the void and read like the player's
# step wave. Each pyramid owns one slot (pyr_index, assigned by the loader).

const GROUND_MATERIAL := preload("res://grid_ground_material.tres")
const PYR_MAX := 4   # pyr_* slots in grid_ground.gdshader

@export var radius: float = 5.0       # danger-zone / detection-front max radius (units)
@export var interval: float = 3.0     # seconds between pulse launches
@export var charge: float = 1.0       # tell duration before a fire (zone brightens)
@export var front_speed: float = 10.0 # u/s the detection front travels: THE dodge-drama knob
@export var pyr_index: int = 0        # this pyramid's slot in the shared ground-shader arrays

const FLOAT_Y := 3.0                   # how high the pyramid mesh hovers above its cell
const CHARGE_RISE := 1.5               # extra lift while charging; falls back under gravity on emit (the wind-up tell)
const APEX_Y := FLOAT_Y - 0.4          # cone tip height above the cell; the emit beam runs from here to the floor
const CATCH_FLASH_TIME := 0.35
const BEAM_FLASH_TIME := 0.3           # how long the emit shaft stays lit at sweep start
const DROP_GRAVITY := 32.0             # mesh fall acceleration after firing (u/s^2)
const DROP_BOUNCE_DAMP := 0.35         # fraction of landing speed kept on each bounce
const DROP_BOUNCE_MIN := 1.2           # landing speed below which it stops bouncing and settles

var _player: Player
var _t := 0.0
var _sweeping := false
var _sweep_t := 0.0
var _detected_this_pulse := false
var _catch_flash := 0.0
var _beam_flash := 0.0
var _mesh_y := FLOAT_Y     # current pyramid lift: rises with the charge, gravity-drops with a bounce on emit
var _drop_v := 0.0
var _dropping := false
var _pyr_mesh: MeshInstance3D
var _beam: MeshInstance3D
var _beam_mat: StandardMaterial3D
var _sweep_player: AudioStreamPlayer3D   # sonar ping at sweep start
var _catch_player: AudioStreamPlayer3D   # distinct low alarm on a catch


func _ready() -> void:
	_player = get_node_or_null("../Player") as Player
	_build_pyramid_mesh()
	_build_beam()
	_build_audio()
	# Stale slots from a prior level are wiped by the loader (_clear_pyramid_overlays).


func _build_pyramid_mesh() -> void:
	# Hovering 4-sided pyramid, apex down (scanning the floor). The danger disc and
	# front are the shader's job now, not a mesh.
	var pyr := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.55
	cone.height = 0.8
	cone.radial_segments = 4
	pyr.mesh = cone
	pyr.position = Vector3(0, FLOAT_Y, 0)
	pyr.rotation_degrees = Vector3(180, 45, 0)
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.4, 0.7, 1.0)
	pmat.emission_enabled = true
	pmat.emission = Color(0.4, 0.7, 1.0)
	pmat.emission_energy_multiplier = 0.5
	pyr.set_surface_override_material(0, pmat)
	add_child(pyr)
	_pyr_mesh = pyr


func _build_beam() -> void:
	# A thin bright shaft from the cone tip down to the floor, flashed for an instant
	# at sweep start so the exact emit moment is unmistakable (cf. the wall edge beams).
	_beam = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.05
	cyl.bottom_radius = 0.05
	cyl.height = APEX_Y
	_beam.mesh = cyl
	_beam.position = Vector3(0, APEX_Y * 0.5, 0)
	_beam_mat = StandardMaterial3D.new()
	_beam_mat.albedo_color = Color(0.6, 0.9, 1.0)
	_beam_mat.emission_enabled = true
	_beam_mat.emission = Color(0.6, 0.9, 1.0)
	_beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beam.set_surface_override_material(0, _beam_mat)
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.visible = false
	add_child(_beam)


func _build_audio() -> void:
	# Two procedural one-shots on their own 3D players (no audio assets to ship).
	_sweep_player = AudioStreamPlayer3D.new()
	_sweep_player.unit_size = 6.0
	_sweep_player.max_distance = 25.0
	_sweep_player.stream = _make_ping(1650.0, 1000.0, 0.8, 0.6, 1.6, 6.0)   # sonar: high "boing" + long ring
	add_child(_sweep_player)
	_catch_player = AudioStreamPlayer3D.new()
	_catch_player.unit_size = 6.0
	_catch_player.max_distance = 25.0
	_catch_player.stream = _make_ping(900.0, 280.0, 0.28, 0.95, 6.0, 3.0)   # catch sting: sharp, short, punchy
	add_child(_catch_player)


func _process(delta: float) -> void:
	if _catch_flash > 0.0:
		_catch_flash = maxf(_catch_flash - delta, 0.0)
	if _beam_flash > 0.0:
		_beam_flash = maxf(_beam_flash - delta, 0.0)

	var pulse_r := 0.0
	var charge_amt := 0.0
	var rise := 0.0   # 0..1 charge wind-up; drives the mesh lift (and the zone brighten)
	if not _sweeping:
		_t += delta
		# Charge tell: brighten the zone + lift the pyramid over the last `charge` seconds.
		if charge > 0.0 and _t > interval - charge:
			rise = clampf((_t - (interval - charge)) / charge, 0.0, 1.0)
		charge_amt = rise
		if _t >= interval:
			_sweeping = true
			_sweep_t = 0.0
			_detected_this_pulse = false
			_on_sweep_start()
	else:
		_sweep_t += delta
		pulse_r = front_speed * _sweep_t
		if not _detected_this_pulse and _player != null:
			var center := Vector2(position.x, position.z)
			var pc := Vector2(_player.position.x, _player.position.z)
			var d := pc.distance_to(center)
			# Caught the instant the front reaches the player's distance, inside range.
			if d <= radius and pulse_r >= d:
				_detected_this_pulse = true
				_on_catch(_player.position)
		if pulse_r >= radius:
			_sweeping = false
			_t = 0.0
			pulse_r = 0.0

	# Mesh lift: rises with the charge, then falls back under gravity with a small damped
	# bounce when it fires (instead of teleporting down).
	if _dropping:
		_drop_v += DROP_GRAVITY * delta
		_mesh_y -= _drop_v * delta
		if _mesh_y <= FLOAT_Y:
			_mesh_y = FLOAT_Y
			if _drop_v > DROP_BOUNCE_MIN:
				_drop_v = -_drop_v * DROP_BOUNCE_DAMP   # bounce back up
			else:
				_drop_v = 0.0
				_dropping = false
	else:
		_mesh_y = FLOAT_Y + CHARGE_RISE * rise
	_pyr_mesh.position.y = _mesh_y
	var beam_ratio := _beam_flash / BEAM_FLASH_TIME
	_beam.visible = beam_ratio > 0.0
	if _beam.visible:
		_beam_mat.emission_energy_multiplier = 4.0 * beam_ratio

	if _catch_flash > 0.0:
		charge_amt = 1.0   # whole zone flashes bright the moment it catches you
	_push_ground(minf(pulse_r, radius), charge_amt)


func _on_sweep_start() -> void:
	# The exact moment the detection front launches: drop the mesh, flash the beam, ping.
	_dropping = true
	_drop_v = 0.0
	_beam_flash = BEAM_FLASH_TIME
	_sweep_player.play()


func _on_catch(player_pos: Vector3) -> void:
	# Feed the player's position to every guard currently inside the radius.
	_catch_flash = CATCH_FLASH_TIME
	_catch_player.play()   # distinct low alarm: you were caught
	# Overheat + Exposed: a catch must STICK -- bar dodge/blend so you can't just
	# re-blend and vanish. Pyramid-specific; the player owns the timer.
	_player.apply_catch_overheat()
	var center := Vector2(position.x, position.z)
	for g in get_tree().get_nodes_in_group("guards"):
		if not g.has_method("reveal_player_at"):
			continue
		var gc := Vector2((g as Node3D).position.x, (g as Node3D).position.z)
		if gc.distance_to(center) <= radius:
			g.reveal_player_at(player_pos)


func _push_ground(pulse_r: float, charge_amt: float) -> void:
	# Write this pyramid's slot in the shared ground-shader arrays (read-modify-write,
	# like the enemy vision cones). Single-threaded, so slots never clobber each other.
	if pyr_index < 0 or pyr_index >= PYR_MAX:
		return
	var origins := _slot_v2("pyr_origins")
	var zone := _slot_f("pyr_zone_radii")
	var pulse := _slot_f("pyr_pulse_radii")
	var charge_a := _slot_f("pyr_charge")
	origins[pyr_index] = Vector2(position.x, position.z)
	zone[pyr_index] = radius
	pulse[pyr_index] = pulse_r
	charge_a[pyr_index] = charge_amt
	GROUND_MATERIAL.set_shader_parameter("pyr_origins", origins)
	GROUND_MATERIAL.set_shader_parameter("pyr_zone_radii", zone)
	GROUND_MATERIAL.set_shader_parameter("pyr_pulse_radii", pulse)
	GROUND_MATERIAL.set_shader_parameter("pyr_charge", charge_a)


func _slot_v2(param: String) -> PackedVector2Array:
	var a = GROUND_MATERIAL.get_shader_parameter(param)
	if a == null or (a as PackedVector2Array).size() < PYR_MAX:
		var z := PackedVector2Array()
		z.resize(PYR_MAX)
		return z
	return a


func _slot_f(param: String) -> PackedFloat32Array:
	var a = GROUND_MATERIAL.get_shader_parameter(param)
	if a == null or (a as PackedFloat32Array).size() < PYR_MAX:
		var z := PackedFloat32Array()
		z.resize(PYR_MAX)
		return z
	return a


static func _make_ping(f0: float, f1: float, dur: float, peak: float, decay := 2.5, glide_k := 0.0) -> AudioStreamWAV:
	# One-shot tone gliding f0 -> f1 with a fast attack + exponential decay. glide_k > 0
	# bends the pitch fast-then-settle (a springy "boing"); 0 = linear glide. decay sets
	# the ring length (lower = longer tail). Procedural, no audio asset to ship.
	var rate := 44100
	var samples := int(rate * dur)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	var data := PackedByteArray()
	data.resize(samples * 2)
	var phase := 0.0
	var glide_norm := (1.0 - exp(-glide_k)) if glide_k > 0.0 else 1.0
	for i in samples:
		var u := float(i) / float(samples)
		var fu := u if glide_k <= 0.0 else (1.0 - exp(-glide_k * u)) / glide_norm
		var freq := lerpf(f0, f1, fu)
		phase += TAU * freq / float(rate)
		var env := minf(u / 0.005, 1.0) * exp(-decay * u)
		var val := int(sin(phase) * env * peak * 30000.0)
		data[i * 2] = val & 0xFF
		data[i * 2 + 1] = (val >> 8) & 0xFF
	stream.data = data
	return stream
