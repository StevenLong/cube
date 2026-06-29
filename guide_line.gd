extends Node3D

# Holder for a lock-puzzle guide line (segments are child meshes). Its visibility
# tracks the lock state so each line shows only while it is useful:
#   visible_when_locked = false -> lock->gate line: shown only while NOTHING is engaged
#       (any puzzle is startable); hidden the moment you commit to any lock, so a
#       different puzzle's line does not beckon while you are locked elsewhere.
#   visible_when_locked = true  -> lock->unlock line: shown only while THIS puzzle's lock
#       is the active one, pointing the way to its release.
# lock_id pins the line to ONE lock so a multi-lock level shows each puzzle on its own
# (always set: the loader only draws a line per authored edge).
#
# A BUTTON->gate line uses `opener` instead: it tracks the button object directly and
# stays visible, but GRAYS OUT once that button latches (is_active()) -- the connection
# still reads, just spent. This bypasses the lock-state branches below. Buttons are
# one-shot, so the line only ever dims once and never restores.

@export var visible_when_locked := false
var lock_id := ""
var opener: Object = null   # set for a button->gate line: gray out once this opener is active

var _player: Player
var _opener_dimmed := false


func _ready() -> void:
	_player = get_node_or_null("../Player") as Player
	_update()


func _process(_delta: float) -> void:
	_update()


func _update() -> void:
	if opener != null:
		# button->gate route: stay visible, gray out once the button latches (one-shot,
		# so dim a single time and we're done).
		if not _opener_dimmed and opener.is_active():
			_opener_dimmed = true
			_gray_out()
		return
	if _player == null:
		return
	if visible_when_locked:
		# lock->unlock route: only while THIS puzzle is the engaged one.
		visible = _player.active_lock_id() == lock_id
	else:
		# lock->gate route: only while nothing is engaged (one active lock at a time), so a
		# different puzzle's line does not draw attention while the player is committed.
		visible = not _player.is_extend_locked()


func _gray_out() -> void:
	# Spent-button look: desaturate every segment/arrow to a dim grey but keep it drawn.
	for c in get_children():
		var mi := c as MeshInstance3D
		if mi == null:
			continue
		var m := mi.material_override as StandardMaterial3D
		if m == null:
			continue
		m.albedo_color = Color(0.5, 0.5, 0.55, 0.3)
		m.emission = Color(0.5, 0.5, 0.55)
		m.emission_energy_multiplier = 0.12
