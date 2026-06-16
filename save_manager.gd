class_name SaveManager
extends RefCounted

# Persistent progression: per-level completion + best time + perfect-stealth flag.
# Static API matching the LevelLoader / LevelEditor singleton pattern (no autoload).
# Levels are keyed by their resource path (the same string LevelLoader.requested_file
# holds). The file is user://save.json, loaded lazily on first access and kept in
# memory; every write flushes the whole document to disk (it is tiny).
#
# A level record is: { "completed": bool, "best_time": float, "perfect": bool }.

const SAVE_PATH := "user://save.json"
const VERSION := 1

static var _data: Dictionary = {}      # { "version": int, "levels": { path: record } }
static var _loaded := false


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_data = {"version": VERSION, "levels": {}}
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if parsed is Dictionary:
		_data = _migrate(parsed)


static func _migrate(raw: Dictionary) -> Dictionary:
	# Coerce every record into the known shape and drop anything unrecognised, so a
	# malformed or future-versioned file can never crash a load. When the schema
	# changes, branch on raw.get("version") here and upgrade in place.
	var out: Dictionary = {"version": VERSION, "levels": {}}
	if raw.get("levels") is Dictionary:
		for key in raw["levels"]:
			var r: Variant = raw["levels"][key]
			if r is Dictionary:
				out["levels"][str(key)] = {
					"completed": bool(r.get("completed", false)),
					"best_time": float(r.get("best_time", 0.0)),
					"perfect": bool(r.get("perfect", false)),
				}
	return out


static func _write() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("SaveManager: could not open %s for writing" % SAVE_PATH)
		return
	f.store_string(JSON.stringify(_data, "\t"))
	f.close()


# --- Public API ---

static func get_record(level_path: String) -> Dictionary:
	# A defensive copy; an unplayed level gets the empty defaults.
	_ensure_loaded()
	var levels: Dictionary = _data["levels"]
	if levels.has(level_path):
		return (levels[level_path] as Dictionary).duplicate()
	return {"completed": false, "best_time": 0.0, "perfect": false}


static func is_completed(level_path: String) -> bool:
	return get_record(level_path)["completed"]


static func record_result(level_path: String, time: float, perfect: bool) -> void:
	# Mark complete; keep the faster time; perfect is sticky (once earned, stays).
	_ensure_loaded()
	var levels: Dictionary = _data["levels"]
	var rec: Dictionary = levels.get(level_path, {"completed": false, "best_time": 0.0, "perfect": false})
	if not rec["completed"] or time < rec["best_time"]:
		rec["best_time"] = time
	rec["completed"] = true
	rec["perfect"] = bool(rec["perfect"]) or perfect
	levels[level_path] = rec
	_write()
