extends Node3D

# Holder for a lock-puzzle guide line (segments are child meshes). Its visibility
# tracks the player's extend-lock state so each line shows only while it is useful:
#   visible_when_locked = false -> lock->gate line: shown while the gate is SHUT
#       (not locked); hidden once you commit and the gate opens.
#   visible_when_locked = true  -> lock->unlock line: hidden until the gate is OPEN
#       (locked), then shows the route to the release.

@export var visible_when_locked := false

var _player: Player


func _ready() -> void:
	_player = get_node_or_null("../Player") as Player
	_update()


func _process(_delta: float) -> void:
	_update()


func _update() -> void:
	if _player != null:
		visible = _player.is_extend_locked() == visible_when_locked
