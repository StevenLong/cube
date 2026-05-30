class_name FloorMissing
extends Node3D

# Config node that carves a rectangular hole in the floor. Applied after every
# FloorRect, so an outer rect minus a missing rect gives a slot or notch. Place
# explicit FloorTile nodes back inside a missing rect to fill arbitrary shapes.

@export var size: Vector2i = Vector2i(1, 1)


func cell_rect() -> Rect2i:
	var origin := Vector2i(roundi(position.x), roundi(position.z))
	return Rect2i(origin, size)
