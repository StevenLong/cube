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

@export var visible_when_locked := false
var lock_id := ""

var _player: Player


func _ready() -> void:
	_player = get_node_or_null("../Player") as Player
	_update()


func _process(_delta: float) -> void:
	_update()


func _update() -> void:
	if _player == null:
		return
	if visible_when_locked:
		# lock->unlock route: only while THIS puzzle is the engaged one.
		visible = _player.active_lock_id() == lock_id
	else:
		# lock->gate route: only while nothing is engaged (one active lock at a time), so a
		# different puzzle's line does not draw attention while the player is committed.
		visible = not _player.is_extend_locked()
