class_name LodProfiles
extends RefCounted

## Single distance table for LodService. JSON is the source of truth.

const PATH := "res://resources/data/world/lod_profiles.json"
const DEFAULT_ID := &"default"

static var _profiles: Dictionary = {}
static var _loaded := false


static func reload() -> void:
	_profiles.clear()
	_loaded = false
	_ensure_loaded()


static func profile_ids() -> PackedStringArray:
	_ensure_loaded()
	var out := PackedStringArray()
	for key in _profiles.keys():
		out.append(str(key))
	out.sort()
	return out


static func get_profile(profile_id: StringName = DEFAULT_ID) -> Dictionary:
	_ensure_loaded()
	var id := StringName(str(profile_id).strip_edges())
	if id == StringName() or not _profiles.has(id):
		id = DEFAULT_ID
	var raw: Dictionary = _profiles.get(id, _profiles.get(DEFAULT_ID, {})) as Dictionary
	return {
		"id": id,
		"detailed_m": maxf(float(raw.get("detailed_m", 280.0)), 1.0),
		"impostor_m": maxf(float(raw.get("impostor_m", 2200.0)), 1.0),
		"hysteresis_m": maxf(float(raw.get("hysteresis_m", 120.0)), 0.0),
	}


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_profiles = {
		DEFAULT_ID: {
			"detailed_m": 280.0,
			"impostor_m": 2200.0,
			"hysteresis_m": 120.0,
		},
	}
	if not FileAccess.file_exists(PATH):
		push_warning("LodProfiles: missing %s — using built-in default" % PATH)
		return
	var file := FileAccess.open(PATH, FileAccess.READ)
	if file == null:
		push_warning("LodProfiles: failed to open %s" % PATH)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("LodProfiles: invalid JSON root in %s" % PATH)
		return
	var root := parsed as Dictionary
	for key in root.keys():
		var entry: Variant = root[key]
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var d := entry as Dictionary
		_profiles[StringName(str(key))] = {
			"detailed_m": float(d.get("detailed_m", 280.0)),
			"impostor_m": float(d.get("impostor_m", 2200.0)),
			"hysteresis_m": float(d.get("hysteresis_m", 120.0)),
		}
