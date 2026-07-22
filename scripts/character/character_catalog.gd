class_name CharacterCatalog
extends RefCounted

const PATH := "res://resources/data/characters/catalog.json"

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		_data = JsonUtil.load(PATH)
	return _data


static func options(slot: StringName) -> Array:
	var value: Variant = data().get(String(slot), [])
	return value if typeof(value) == TYPE_ARRAY else []


static func ids(slot: StringName) -> PackedStringArray:
	var result := PackedStringArray()
	for option in options(slot):
		if typeof(option) == TYPE_DICTIONARY:
			result.append(str(option.get("id", "")))
	return result


static func is_valid(slot: StringName, id: String) -> bool:
	return id in ids(slot)


static func normalized_id(slot: StringName, id: String, fallback: String) -> String:
	return id if is_valid(slot, id) else fallback


static func option(slot: StringName, id: String) -> Dictionary:
	for entry in options(slot):
		if typeof(entry) == TYPE_DICTIONARY and str(entry.get("id", "")) == id:
			return (entry as Dictionary).duplicate(true)
	return {}


static func outfit_presets() -> Array:
	var value: Variant = data().get("outfit_presets", [])
	return value if typeof(value) == TYPE_ARRAY else []


static func outfit_preset(id: String) -> Dictionary:
	for entry in outfit_presets():
		if typeof(entry) == TYPE_DICTIONARY and str(entry.get("id", "")) == id:
			return (entry as Dictionary).duplicate(true)
	return {}


static func appearance_preset(id: String) -> CharacterAppearance:
	var preset := outfit_preset(id)
	return CharacterAppearance.from_dict(preset) if not preset.is_empty() else CharacterAppearance.default_appearance()


static func wardrobe_parts(slot: StringName, id: String) -> PackedStringArray:
	var result := PackedStringArray()
	for part in option(slot, id).get("parts", []):
		result.append(str(part))
	return result


static func all_wardrobe_parts(slot: StringName) -> PackedStringArray:
	var result := PackedStringArray()
	for entry in options(slot):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		for part in entry.get("parts", []):
			var part_name := str(part)
			if not part_name in result:
				result.append(part_name)
	return result


static func wardrobe_model_path(slot: StringName, id: String) -> String:
	var entry := option(slot, id)
	if entry.is_empty() or (entry.get("parts", []) as Array).is_empty():
		return ""
	return "res://resources/data/models/characters/wardrobe/%s/%s.json" % [String(slot), id]


## Stable inventory metadata for a future server/Steam inventory seam. The
## appearance record stores only the equipped id; ownership is deliberately
## validated elsewhere so a client cannot grant itself cosmetics through JSON.
static func cosmetic_metadata(slot: StringName, id: String) -> Dictionary:
	var entry := option(slot, id)
	if entry.is_empty() or id == "none":
		return {}
	return {
		"inventory_key": str(entry.get("inventory_key", "character.%s.%s" % [String(slot), id])),
		"collection": str(entry.get("collection", "core_workwear")),
		"rarity": str(entry.get("rarity", "standard")),
		"trade_policy": str(entry.get("trade_policy", "game_owned")),
	}
