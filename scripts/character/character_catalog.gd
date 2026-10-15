class_name CharacterCatalog
extends RefCounted

## Only Blender-authored assets are registered here. Unknown legacy IDs are inert.
const SLOTS := {
	"body_presets": {"crew_base": "Base character"},
	"hair": {"none": "None"},
	"tops": {"none": "None"},
	"outerwear": {"none": "None"},
	"trousers": {"none": "None"},
	"footwear": {"none": "None"},
	"headwear": {"none": "None"},
	"facial_hair": {"none": "None"},
	"eyewear": {"none": "None"},
	"face_accessories": {"none": "None"},
	"utility_accessories": {"none": "None"},
}

static func data() -> Dictionary:
	return SLOTS.duplicate(true)
static func options(slot: StringName) -> Array:
	var result: Array = []
	for id in SLOTS.get(str(slot), {}): result.append(option(slot, id))
	return result
static func ids(slot: StringName) -> PackedStringArray:
	return PackedStringArray(SLOTS.get(str(slot), {}).keys())
static func is_valid(slot: StringName, id: String) -> bool:
	return SLOTS.get(str(slot), {}).has(id)
static func normalized_id(_slot: StringName, id: String, fallback: String) -> String:
	return id if not id.is_empty() else fallback
static func option(slot: StringName, id: String) -> Dictionary:
	return {"id": id, "label": SLOTS[str(slot)][id]} if is_valid(slot,id) else {}
static func outfit_presets() -> Array:
	return []
static func outfit_preset(_id: String) -> Dictionary:
	return {}
static func appearance_preset(_id: String) -> CharacterAppearance:
	return CharacterAppearance.default_appearance()
static func wardrobe_parts(_slot: StringName, _id: String) -> PackedStringArray:
	return PackedStringArray()
static func all_wardrobe_parts(_slot: StringName) -> PackedStringArray:
	return PackedStringArray()
static func wardrobe_model_path(_slot: StringName, _id: String) -> String:
	return ""
static func cosmetic_metadata(slot: StringName, id: String) -> Dictionary:
	return option(slot,id)
