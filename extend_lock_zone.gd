extends Area3D

# Extend-lock zone (grid-exact), with a mode-specific telegraph.
#
# The check is integer-cell based, never physics overlap, so it cannot be satisfied
# one tile off, in the wrong orientation, or mid-tumble. It is satisfied whether the
# player formed the shape in place or arrived already in it, as long as size,
# orientation, and location all line up exactly.
#
# The zone's cell (its rounded x/z) is the footprint's MIN corner (smallest x,
# smallest z). The footprint then extends +x by width and +z by depth.
#
# LOCK: arms the lock when the player's footprint min == this cell AND dimensions
#   == required_dims, at rest. TELEGRAPH: a single marked tile with a floating
#   padlock icon until armed; standing on the tile swaps the icon for a ghost of
#   the cube EXPANDING to the required shape in place ("become this, here"). This
#   suits LOCK because you arrive as a 1x1 cube and have to form the shape.
# UNLOCK: releases the lock by the SAME match, while locked. TELEGRAPH: a
#   persistent ghost cuboid (plus footprint marker) showing where and in what
#   orientation to re-seat the (already-formed, frozen) shape. Dims matter because
#   TUMBLING a locked shape reorients it (a standing 1x3x1 becomes a lying 1x1x3),
#   so the ghost is a placement-and-orientation guide. Softlock guard lives in the
#   loader: any permutation of the lock's dims is reachable by tumbling, so it only
#   rewrites unlock dims that are NOT a permutation (truly unsatisfiable stale data).

enum Mode { LOCK, UNLOCK }

const COLOR_LOCK := Color(0.9, 0.55, 0.15)
const COLOR_UNLOCK := Color(0.3, 0.85, 0.4)
# LOCK telegraph
const ICON_SPIN := 1.2          # rad/s the padlock idles
const ICON_Y := 0.9             # height the icon floats above the tile
const GHOST_GROW_TIME := 1.2    # seconds for the expand demo to reach full size
const GHOST_HOLD_TIME := 0.5    # seconds held at full size before looping
const GHOST_ALPHA := 0.35
# UNLOCK telegraph (persistent blinking ghost)
const GHOST_BLINK_RATE := 3.0
const GHOST_ALPHA_MIN := 0.1
const GHOST_ALPHA_MAX := 0.4

@export var mode: Mode = Mode.LOCK
## width (x), height (y), depth (z), in cells. The exact cuboid required at this cell.
@export var required_dims: Vector3i = Vector3i(1, 1, 3)

# Link layer (injected by the loader from the level's `links`). A LOCK arms the player
# with its own `link_id`; an UNLOCK releases only when the active lock is one of the
# `release_lock_ids` it is paired to. Empty = unlinked (the default): a lone LOCK is a
# commit-to-a-shape puzzle, a lone UNLOCK simply never fires.
var link_id := ""
var release_lock_ids: Array[String] = []

var _player: Player
var _color: Color
var _marker: MeshInstance3D
var _marker_mat: StandardMaterial3D
var _icon: Node3D
var _ghost: MeshInstance3D
var _ghost_mat: StandardMaterial3D
var _ghost_phase := 0.0
var _blink_t := 0.0


func _ready() -> void:
	monitoring = false  # location is grid-checked, not via area overlap
	_player = get_node("../Player") as Player
	_color = COLOR_LOCK if mode == Mode.LOCK else COLOR_UNLOCK
	if mode == Mode.LOCK:
		_build_marker()
		_build_icon()
		_build_expand_ghost()
	else:
		_build_blueprint()


func _cell() -> Vector2i:
	return Vector2i(roundi(global_position.x), roundi(global_position.z))


func _process(delta: float) -> void:
	if mode == Mode.LOCK:
		_update_lock_telegraph(delta)
	else:
		_update_unlock_blueprint(delta)
	if _player.is_moving():
		return
	# Same exact match for both modes (shape, orientation, and location seated at
	# this cell, at rest); they differ only in the lock state required and the one
	# they set. See header for why UNLOCK keeps the dims check (tumble reorients).
	var seated: bool = (_player.get_dimensions() == required_dims
		and _player.get_footprint_min() == _cell())
	if mode == Mode.LOCK:
		if seated and not _player.is_extend_locked():
			_player.set_active_lock(link_id)
	elif seated and release_lock_ids.has(_player.active_lock_id()):
		_player.clear_active_lock()


# --- LOCK telegraph: marked tile + padlock icon, swapped for an expand ghost on land ---

func _build_marker() -> void:
	# Uniform tint over the WHOLE required footprint (not a single corner tile), so
	# the lock area reads as one cohesive zone and matches the unlock's footprint marker.
	var w: int = required_dims.x
	var d: int = required_dims.z
	var plane := PlaneMesh.new()
	plane.size = Vector2(float(w) - 0.1, float(d) - 0.1)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(_color.r, _color.g, _color.b, 0.4)
	mat.emission_enabled = true
	mat.emission = _color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_marker_mat = mat   # kept so the disabled state can dim it (see _set_marker_dim)
	_marker = MeshInstance3D.new()
	_marker.mesh = plane
	_marker.material_override = mat
	_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_marker.position = Vector3((w - 1) * 0.5, 0.02 - global_position.y, (d - 1) * 0.5)
	add_child(_marker)


func _build_icon() -> void:
	# Placeholder padlock from primitives (box body + torus shackle), floating and
	# slowly spinning, centred over the footprint. Replaced by the real icon set later.
	var w: int = required_dims.x
	var d: int = required_dims.z
	_icon = Node3D.new()
	_icon.position = Vector3((w - 1) * 0.5, ICON_Y - global_position.y, (d - 1) * 0.5)
	add_child(_icon)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = _color
	mat.emission_enabled = true
	mat.emission = _color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var body := MeshInstance3D.new()
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(0.34, 0.28, 0.16)
	body.mesh = body_mesh
	body.material_override = mat
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_icon.add_child(body)
	var shackle := MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 0.07
	ring.outer_radius = 0.13
	shackle.mesh = ring
	shackle.material_override = mat
	shackle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shackle.rotation.x = PI / 2.0   # stand the ring up, like a shackle
	shackle.position = Vector3(0.0, 0.2, 0.0)
	_icon.add_child(shackle)


func _build_expand_ghost() -> void:
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	_ghost_mat = StandardMaterial3D.new()
	_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ghost_mat.albedo_color = Color(_color.r, _color.g, _color.b, GHOST_ALPHA)
	_ghost_mat.emission_enabled = true
	_ghost_mat.emission = _color
	_ghost = MeshInstance3D.new()
	_ghost.mesh = box
	_ghost.material_override = _ghost_mat
	_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost.visible = false
	add_child(_ghost)


func _update_lock_telegraph(delta: float) -> void:
	# A lock is actionable only while NO lock is engaged (the player holds one active lock
	# at a time). Once any lock is armed, every lock drops to a quiet DISABLED state -- dim
	# tile, no padlock icon, no expand ghost -- so attention is free for the live unlock and
	# its guide line. (Previously this HID every lock outright, which erased the cue for the
	# shape you'd just formed and blanked the other puzzles' locks too.)
	var available := not _player.is_extend_locked()
	if not available:
		_marker.visible = true
		_set_marker_dim(true)
		_icon.visible = false
		_ghost.visible = false
		_ghost_phase = 0.0
		return
	_set_marker_dim(false)
	var on_tile: bool = not _player.is_moving() and _player_on_footprint()
	_marker.visible = true
	_icon.visible = not on_tile
	_ghost.visible = on_tile
	if _icon.visible:
		_icon.rotate_y(ICON_SPIN * delta)
	if on_tile:
		_advance_expand_ghost(delta)
	else:
		_ghost_phase = 0.0


func _set_marker_dim(dim: bool) -> void:
	# Disabled look: a quiet grey, unlit tile so an engaged/idle lock still reads spatially
	# without competing for attention. Active look: the lock's colour, emissive.
	if dim:
		_marker_mat.albedo_color = Color(0.55, 0.55, 0.6, 0.12)
		_marker_mat.emission_enabled = false
	else:
		_marker_mat.albedo_color = Color(_color.r, _color.g, _color.b, 0.4)
		_marker_mat.emission_enabled = true


func _player_on_footprint() -> bool:
	# True if the player overlaps any cell of the required footprint, so the expand
	# demo shows whenever they are standing in the lock area, not only on the corner.
	var c := _cell()
	for i in range(required_dims.x):
		for j in range(required_dims.z):
			if _player.footprint_covers(c + Vector2i(i, j)):
				return true
	return false


func _advance_expand_ghost(delta: float) -> void:
	# Loop the cuboid growing from 1x1x1 to required_dims (brief hold at full size).
	# It grows CENTRED on the footprint (XZ) and up from the floor (Y), ending exactly
	# filling the required footprint, so it reads as "fill this area" not "from a corner".
	_ghost_phase = fmod(_ghost_phase + delta, GHOST_GROW_TIME + GHOST_HOLD_TIME)
	var t := clampf(_ghost_phase / GHOST_GROW_TIME, 0.0, 1.0)
	var w := lerpf(1.0, float(required_dims.x), t)
	var h := lerpf(1.0, float(required_dims.y), t)
	var d := lerpf(1.0, float(required_dims.z), t)
	(_ghost.mesh as BoxMesh).size = Vector3(w, h, d)
	var cx := (float(required_dims.x) - 1.0) * 0.5   # fixed footprint centre offset
	var cz := (float(required_dims.z) - 1.0) * 0.5
	_ghost.position = Vector3(cx, h * 0.5 - global_position.y, cz)


# --- UNLOCK telegraph: persistent ghost cuboid + footprint marker (placement guide) ---

func _build_blueprint() -> void:
	var w: int = required_dims.x
	var h: int = required_dims.y
	var d: int = required_dims.z
	var plane := PlaneMesh.new()
	plane.size = Vector2(float(w) - 0.1, float(d) - 0.1)
	var pmat := StandardMaterial3D.new()
	pmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pmat.albedo_color = Color(_color.r, _color.g, _color.b, 0.55)
	_marker = MeshInstance3D.new()
	_marker.mesh = plane
	_marker.material_override = pmat
	_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_marker.position = Vector3((w - 1) * 0.5, 0.02 - global_position.y, (d - 1) * 0.5)
	_marker.visible = false   # hidden until the gate opens (player extend-locked)
	add_child(_marker)

	var box := BoxMesh.new()
	box.size = Vector3(w, h, d)
	_ghost_mat = StandardMaterial3D.new()
	_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ghost_mat.albedo_color = Color(_color.r, _color.g, _color.b, GHOST_ALPHA_MAX)
	_ghost = MeshInstance3D.new()
	_ghost.mesh = box
	_ghost.material_override = _ghost_mat
	_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost.position = Vector3((w - 1) * 0.5, h * 0.5 - global_position.y, (d - 1) * 0.5)
	_ghost.visible = false   # hidden until the gate opens (player extend-locked)
	add_child(_ghost)


func _update_unlock_blueprint(delta: float) -> void:
	# Shown only while the lock THIS zone releases is the active one, so in a multi-lock
	# level an unlock blinks for its own puzzle, not whenever any lock is armed.
	var show_bp := release_lock_ids.has(_player.active_lock_id())
	_ghost.visible = show_bp
	_marker.visible = show_bp
	if show_bp:
		_blink_t += delta * GHOST_BLINK_RATE
		var a := lerpf(GHOST_ALPHA_MIN, GHOST_ALPHA_MAX, 0.5 + 0.5 * sin(_blink_t))
		_ghost_mat.albedo_color = Color(_color.r, _color.g, _color.b, a)
