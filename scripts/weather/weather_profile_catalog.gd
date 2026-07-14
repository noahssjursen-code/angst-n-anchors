class_name WeatherProfileCatalog
extends RefCounted

const DEFAULT_PROFILE_PATH := "res://resources/data/weather/norway_maritime.json"

static var _profile: Dictionary = {}


static func profile() -> Dictionary:
	if not _profile.is_empty():
		return _profile
	var file := FileAccess.open(DEFAULT_PROFILE_PATH, FileAccess.READ)
	if file == null:
		push_error("WeatherProfileCatalog: cannot open %s" % DEFAULT_PROFILE_PATH)
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("WeatherProfileCatalog: invalid profile JSON")
		return {}
	_profile = parsed as Dictionary
	return _profile


static func generation_version() -> int:
	return int(profile().get("version", 1))


static func dimensions() -> PackedStringArray:
	var result := PackedStringArray()
	var data: Dictionary = profile().get("dimensions", {})
	for key in data.keys():
		result.append(str(key))
	return result


static func bands(dimension: String) -> Array:
	var data: Dictionary = profile().get("dimensions", {})
	var entries = data.get(dimension, [])
	return entries as Array if entries is Array else []


static func band(dimension: String, band_id: String) -> Dictionary:
	for raw in bands(dimension):
		var entry := raw as Dictionary
		if str(entry.get("id", "")) == band_id:
			return entry
	return {}


static func moods() -> Array:
	var entries = profile().get("moods", [])
	return entries as Array if entries is Array else []


static func mood(mood_id: String) -> Dictionary:
	for raw in moods():
		var entry := raw as Dictionary
		if str(entry.get("id", "")) == mood_id:
			return entry
	return {}


static func compatibility(
		left_dimension: String,
		left_id: String,
		right_dimension: String,
		right_id: String,
) -> float:
	var all_rules: Dictionary = profile().get("compatibility", {})
	var dimensions_key := "%s|%s" % [left_dimension, right_dimension]
	var value_key := "%s|%s" % [left_id, right_id]
	if all_rules.has(dimensions_key):
		return float((all_rules[dimensions_key] as Dictionary).get(value_key, 1.0))
	dimensions_key = "%s|%s" % [right_dimension, left_dimension]
	value_key = "%s|%s" % [right_id, left_id]
	if all_rules.has(dimensions_key):
		return float((all_rules[dimensions_key] as Dictionary).get(value_key, 1.0))
	return 1.0


static func value_for_band(dimension: String, band_id: String, unit_value: float = 0.5) -> float:
	var entry := band(dimension, band_id)
	var range_value = entry.get("range", [0.0, 0.0])
	if not range_value is Array or (range_value as Array).size() < 2:
		return 0.0
	var values := range_value as Array
	return lerpf(float(values[0]), float(values[1]), clampf(unit_value, 0.0, 1.0))


static func label_for_band(dimension: String, band_id: String) -> String:
	return str(band(dimension, band_id).get("label", band_id.capitalize()))


static func clear_cache() -> void:
	_profile.clear()
