class_name TextureMaterialCatalog
extends RefCounted

## Registry for reusable textured-JSON appearances. Models reference a stable
## profile id; paths and default palettes live here instead of being repeated
## across every garment, face, vessel, or prop model.

const DATA_PATH := "res://resources/data/materials/textured_materials.json"


static func resolve(profile_id: String, overrides: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {}
	if not profile_id.is_empty():
		var catalog := JsonUtil.load(DATA_PATH)
		var profiles := catalog.get("profiles", {}) as Dictionary
		if profiles.has(profile_id) and typeof(profiles[profile_id]) == TYPE_DICTIONARY:
			result = (profiles[profile_id] as Dictionary).duplicate(true)
		else:
			push_warning("TextureMaterialCatalog: unknown profile `%s`" % profile_id)
	for key in overrides:
		result[key] = overrides[key]
	return result


static func color_value(value: Variant, fallback: Color = Color.WHITE) -> Color:
	if typeof(value) == TYPE_COLOR:
		return value
	if typeof(value) == TYPE_STRING:
		var text := str(value).strip_edges()
		if not text.is_empty():
			return Color.from_string(text, fallback)
	if typeof(value) == TYPE_ARRAY and value.size() >= 3:
		return Color(
			float(value[0]),
			float(value[1]),
			float(value[2]),
			float(value[3]) if value.size() > 3 else 1.0,
		)
	return fallback
