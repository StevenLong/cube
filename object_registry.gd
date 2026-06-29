class_name ObjectRegistry

# Single source of truth for every paintable type (see SPEC_object_anatomy.md).
# The level loader reads it (glyph -> id, id -> scene) and the editor will read it
# (palette, paint mode, default params). Adding a type is an entry here, plus, for
# the few code-built base tiles, a build case in level_loader.
#
# Entry fields:
#   name        display name (editor palette)
#   kind        BASE_TILE | OVERLAY_TILE | OBJECT  (placement / storage layer)
#   glyph       grid char for tiles; "" for objects (they live in the object list)
#   paint_mode  paint | single | region | path     (which editor tool)
#   scene       PackedScene to instantiate; absent for code-built base tiles
#   params      default per-instance params (objects)

enum Kind { BASE_TILE, OVERLAY_TILE, OBJECT }

const TYPES := {
	"floor": {
		"name": "Floor", "kind": Kind.BASE_TILE, "glyph": ".", "paint_mode": "paint",
		"scene": preload("res://FloorTile.tscn"),
	},
	"tall_wall": {
		"name": "Tall Wall", "kind": Kind.BASE_TILE, "glyph": "#", "paint_mode": "paint",
	},
	"safety_edge": {
		"name": "Safety Edge", "kind": Kind.BASE_TILE, "glyph": "=", "paint_mode": "paint",
	},
	"glass_wall": {
		"name": "Glass Wall", "kind": Kind.BASE_TILE, "glyph": "g", "paint_mode": "paint",
	},
	"pitfall": {
		"name": "Pitfall", "kind": Kind.BASE_TILE, "glyph": "p", "paint_mode": "paint",
	},
	"void": {
		"name": "Void", "kind": Kind.BASE_TILE, "glyph": " ", "paint_mode": "paint",
	},
	"start": {
		"name": "Start", "kind": Kind.BASE_TILE, "glyph": "S", "paint_mode": "single",
	},
	"end": {
		"name": "End", "kind": Kind.BASE_TILE, "glyph": "E", "paint_mode": "single",
	},
	"ink": {
		"name": "Ink", "kind": Kind.OVERLAY_TILE, "glyph": "i", "paint_mode": "paint",
		"scene": preload("res://ink_overlay.tscn"),
	},
	"water": {
		"name": "Water", "kind": Kind.OVERLAY_TILE, "glyph": "w", "paint_mode": "paint",
		"scene": preload("res://water_overlay.tscn"),
	},
	"enemy_sphere": {
		"name": "Patrol Guard", "kind": Kind.OBJECT, "glyph": "", "paint_mode": "path",
		"scene": preload("res://enemy_sphere.tscn"),
		"params": {"speed": 1.8},
	},
	"enemy_pyramid": {
		"name": "Echo Pyramid", "kind": Kind.OBJECT, "glyph": "", "paint_mode": "single",
		"scene": preload("res://enemy_pyramid.tscn"),
		"params": {"radius": 5.0, "interval": 3.0},
	},
	"extend_lock_zone": {
		"name": "Lock Zone", "kind": Kind.OBJECT, "glyph": "", "paint_mode": "single",
		"scene": preload("res://extend_lock_zone.tscn"),
		"params": {"mode": "lock", "required_dims": [1, 1, 3]},
	},
	"extend_lock_gate": {
		"name": "Gate", "kind": Kind.OBJECT, "glyph": "", "paint_mode": "path",
		"scene": preload("res://extend_lock_gate.tscn"),
		"params": {"height": 3},
	},
	"floor_button": {
		"name": "Floor Button", "kind": Kind.OBJECT, "glyph": "", "paint_mode": "single",
		"scene": preload("res://floor_button.tscn"),
		"params": {},
	},
}


static func glyph_to_id(kind: Kind) -> Dictionary:
	# { glyph -> type id } for one tile layer; used by the loader's parser and the
	# editor's serializer so glyphs live only here.
	var out: Dictionary = {}
	for id in TYPES:
		var t: Dictionary = TYPES[id]
		if t["kind"] == kind and String(t.get("glyph", "")) != "":
			out[t["glyph"]] = id
	return out


static func ids_of_kind(kind: Kind) -> Array:
	# Type ids of one kind, in declaration order (editor palette groups).
	var out: Array = []
	for id in TYPES:
		if TYPES[id]["kind"] == kind:
			out.append(id)
	return out


static func scene_for(id: String) -> PackedScene:
	var t: Dictionary = TYPES.get(id, {})
	return t.get("scene", null)


static func default_param(id: String, key: String) -> Variant:
	# A type's default value for one param, so the loader and editor never
	# re-hardcode it. The registry is the only place a default lives.
	return TYPES.get(id, {}).get("params", {}).get(key, null)
