class_name FloorRect
extends Node3D

# Config node that adds a rectangular block of floor cells. The node's XZ
# position is the min-corner cell (snap to integer for predictable results);
# size is the cell footprint in cells. Level scans these at startup and spawns
# a FloorTile per cell. Place multiple FloorRects to compose shapes; carve gaps
# with FloorMissing.

@export var size: Vector2i = Vector2i(27, 27)


func cell_rect() -> Rect2i:
	var origin := Vector2i(roundi(position.x), roundi(position.z))
	return Rect2i(origin, size)
