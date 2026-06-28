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
const CATCH_FLASH_TIME := 0.35

var _player: Player
var _t := 0.0
var _sweeping := false
var _sweep_t := 0.0
var _detected_this_pulse := false
var _catch_flash := 0.0


func _ready() -> void:
	_player = get_node_or_null("../Player") as Player
	_build_pyramid_mesh()
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


func _process(delta: float) -> void:
	if _catch_flash > 0.0:
		_catch_flash = maxf(_catch_flash - delta, 0.0)

	var pulse_r := 0.0
	var charge_amt := 0.0
	if not _sweeping:
		_t += delta
		# Charge tell: brighten the zone over the last `charge` seconds before firing.
		if charge > 0.0 and _t > interval - charge:
			charge_amt = clampf((_t - (interval - charge)) / charge, 0.0, 1.0)
		if _t >= interval:
			_sweeping = true
			_sweep_t = 0.0
			_detected_this_pulse = false
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

	if _catch_flash > 0.0:
		charge_amt = 1.0   # whole zone flashes bright the moment it catches you
	_push_ground(minf(pulse_r, radius), charge_amt)


func _on_catch(player_pos: Vector3) -> void:
	# Feed the player's position to every guard currently inside the radius.
	_catch_flash = CATCH_FLASH_TIME
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
