extends Node

var failures := PackedStringArray()


func _ready() -> void:
	var source := CharacterAppearance.default_appearance()
	source.body_id = "broad"
	source.hair_id = "side_part"
	source.facial_hair_id = "short_beard"
	source.top_id = "wool_sweater"
	source.outerwear_id = "rain_jacket_yellow"
	source.trousers_id = "bib_overalls"
	source.footwear_id = "sea_boots"
	source.headwear_id = "watch_cap"
	source.eyewear_id = "wire_glasses"
	source.face_accessory_id = "bent_pipe"
	source.neckwear_id = "wool_scarf"
	source.handwear_id = "leather_gloves"
	source.utility_id = "handheld_radio"
	source.uniform_id = "deck_crew"
	source.face_texture_profile_id = "face_surface_freckled"
	source.top_color = Color(0.7, 0.65, 0.5)
	source.headwear_color = Color(0.2, 0.25, 0.3)
	source.accent_color = Color(0.9, 0.3, 0.08)
	source.accessory_color = Color(0.25, 0.20, 0.14)
	source.company_primary_color = Color(0.08, 0.22, 0.34)
	source.company_secondary_color = Color(0.92, 0.40, 0.08)
	var restored := CharacterAppearance.from_json_string(source.to_json_string())
	_check(restored != null, "valid JSON restores")
	_check(restored != null and restored.to_dict() == source.to_dict(), "appearance roundtrip is lossless")
	var legacy := CharacterAppearance.from_dict({"hat_id":"flat_cap", "clothing_color":[0.1,0.2,0.3,1]})
	_check(legacy.headwear_id == "flat_cap", "legacy hat migrates into headwear")
	var invalid := CharacterAppearance.from_dict({"body_id":"impossible", "outerwear_id":"spacesuit"})
	_check(invalid.body_id == "average" and invalid.outerwear_id == "deck_jacket", "unknown catalog ids use safe defaults")
	if failures.is_empty():
		print("Character appearance test: all checks passed")
		get_tree().quit()
		return
	for failure in failures:
		push_error("Character appearance test: " + failure)
	get_tree().quit(1)


func _check(condition: bool, label: String) -> void:
	if not condition: failures.append(label)
