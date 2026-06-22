extends Node3D

# Holder for a lock-puzzle guide line (segments are child meshes). Its visibility
# tracks the lock state so each line shows only while it is useful:
#   visible_when_locked = false -> lock->gate line: shown while the gate is SHUT
#       (that lock not armed); hidden once you commit and the gate opens.
#   visible_when_locked = true  -> lock->unlock line: hidden until the gate is OPEN
#       (that lock armed), then shows the route to the release.
# lock_id pins the line to ONE lock so a multi-lock level shows each puzzle on its own.
# lock_id == "" is the legacy/backfill mode (track the global "any lock armed" flag);
# it goes away once every level carries real links (after slice 5).

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
	var armed: bool = _player.is_extend_locked() if lock_id == "" else _player.active_lock_id() == lock_id
	visible = armed == visible_when_locked
