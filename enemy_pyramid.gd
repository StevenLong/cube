extends Node3D

# Echo Pyramid: a stationary floating sonar pylon (design grill 2026-06-27). It
# defeats cover. On a fixed beat it fires a detection front that expands from its
# centre to `radius`; the player is caught the instant the front reaches their cell
# while inside the radius. A catch feeds the player's exact position to every guard
# CURRENTLY inside the radius (sets _last_seen_pos + kicks it to INVESTIGATE, bypassing
# LoS/walls) -- so a guard in the field can't be shaken by cover. No standalone fail,
# no global alert, no links: a lone pyramid with no guard in its field is inert.
# Pure range/timing (shape ignored). All tunable per-instance.

@export var radius: float = 5.0       # danger-zone / detection-front max radius (units)
@export var interval: float = 3.0     # seconds between pulse launches
@export var charge: float = 1.0       # tell duration before a fire (ring brightens)
@export var front_speed: float = 10.0 # u/s the detection front travels: THE dodge-drama knob

const FLOAT_Y := 3.0                   # how high the pyramid mesh hovers above its cell
const CATCH_FLASH_TIME := 0.35
const ZONE_COLOR := Color(0.4, 0.7, 1.0)    # echo blue
const CATCH_COLOR := Color(1.0, 0.35, 0.2)  # flash when it catches you
const ZONE_ALPHA_DIM := 0.05
const ZONE_ALPHA_CHARGE := 0.22

var _player: Player
var _t := 0.0
var _sweeping := false
var _sweep_t := 0.0
var _detected_this_pulse := false
var _catch_flash := 0.0
var _zone_mat: StandardMaterial3D
var _front: MeshInstance3D
var _front_mesh: TorusMesh
var _front_mat: StandardMaterial3D


func _ready() -> void:
	_player = get_node_or_null("../Player") as Player
	_build_visuals()


func _build_visuals() -> void:
	# Hovering 4-sided pyramid, apex down (scanning the floor).
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
	pmat.albedo_color = ZONE_COLOR
	pmat.emission_enabled = true
	pmat.emission = ZONE_COLOR
	pmat.emission_energy_multiplier = 0.5
	pyr.set_surface_override_material(0, pmat)
	add_child(pyr)

	# Always-visible dim danger disc at floor level (the zone you must read).
	var zone := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = radius
	disc.bottom_radius = radius
	disc.height = 0.02
	disc.radial_segments = 48
	zone.mesh = disc
	zone.position = Vector3(0, 0.02, 0)
	_zone_mat = StandardMaterial3D.new()
	_zone_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_zone_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_zone_mat.albedo_color = Color(ZONE_COLOR, ZONE_ALPHA_DIM)
	zone.set_surface_override_material(0, _zone_mat)
	add_child(zone)

	# The expanding bright front (a flat ring), hidden until a pulse fires.
	_front = MeshInstance3D.new()
	_front_mesh = TorusMesh.new()
	_front_mesh.rings = 4
	_front_mesh.ring_segments = 48
	_front.mesh = _front_mesh
	_front.position = Vector3(0, 0.04, 0)
	_front_mat = StandardMaterial3D.new()
	_front_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_front_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_front_mat.albedo_color = Color(ZONE_COLOR, 0.8)
	_front.set_surface_override_material(0, _front_mat)
	_front.visible = false
	add_child(_front)


func _process(delta: float) -> void:
	if _catch_flash > 0.0:
		_catch_flash = maxf(_catch_flash - delta, 0.0)

	if not _sweeping:
		_t += delta
		# Charge tell: brighten the zone over the last `charge` seconds before firing.
		var amt := 0.0
		if charge > 0.0 and _t > interval - charge:
			amt = clampf((_t - (interval - charge)) / charge, 0.0, 1.0)
		_zone_mat.albedo_color = Color(_zone_rgb(), lerpf(ZONE_ALPHA_DIM, ZONE_ALPHA_CHARGE, amt))
		if _t >= interval:
			_sweeping = true
			_sweep_t = 0.0
			_detected_this_pulse = false
			_front.visible = true
	else:
		_sweep_t += delta
		var fr := front_speed * _sweep_t
		_update_front(fr)
		if not _detected_this_pulse and _player != null:
			var center := Vector2(position.x, position.z)
			var pc := Vector2(_player.position.x, _player.position.z)
			var d := pc.distance_to(center)
			# Caught the instant the front reaches the player's distance, inside range.
			if d <= radius and fr >= d:
				_detected_this_pulse = true
				_on_catch(_player.position)
		if fr >= radius:
			_sweeping = false
			_t = 0.0
			_front.visible = false
			_zone_mat.albedo_color = Color(_zone_rgb(), ZONE_ALPHA_DIM)


func _zone_rgb() -> Color:
	return CATCH_COLOR if _catch_flash > 0.0 else ZONE_COLOR


func _update_front(fr: float) -> void:
	var outer := minf(fr, radius)
	_front_mesh.outer_radius = maxf(outer, 0.001)
	_front_mesh.inner_radius = maxf(outer - 0.25, 0.0)
	_front_mat.albedo_color = Color(_zone_rgb(), 0.8)


func _on_catch(player_pos: Vector3) -> void:
	# Feed the player's position to every guard currently inside the radius.
	_catch_flash = CATCH_FLASH_TIME
	var center := Vector2(position.x, position.z)
	for g in get_tree().get_nodes_in_group("guards"):
		if not g.has_method("reveal_player_at"):
			continue
		var gc := Vector2((g as Node3D).position.x, (g as Node3D).position.z)
		if gc.distance_to(center) <= radius:
			g.reveal_player_at(player_pos)
