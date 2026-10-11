class_name CharacterCatalog
extends RefCounted

## Only Blender-authored assets are registered here. Unknown legacy IDs are inert.
const SLOTS := {
	"body_presets": {"mariner": "Mariner"},
	"hair": {"none": "Bald", "crop": "Short crop"},
	"tops": {"none": "None", "sweater": "Work sweater"},
	"outerwear": {"none": "None", "vest": "Work vest"},
	"trousers": {"none": "Base layer", "work": "Work trousers"},
	"footwear": {"none": "Barefoot", "boots": "Deck boots"},
	"headwear": {"none": "None", "cap": "Sailor cap", "hardhat": "Hard hat"},
	"facial_hair": {"none": "None", "moustache": "Moustache"},
	"eyewear": {"none": "None", "glasses": "Glasses"},
	"face_accessories": {"none": "None", "pipe": "Pipe"},
	"utility_accessories": {"none": "None", "belt": "Belt and pouch"},
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
	return [{"id":"sailor","label":"Sailor"},{"id":"dock_worker","label":"Deck crew"},{"id":"harbour_master","label":"Harbour master"}]
static func outfit_preset(id: String) -> Dictionary:
	for preset in outfit_presets():
		if preset.id == id: return preset
	return {}
static func appearance_preset(id: String) -> CharacterAppearance:
	var result := CharacterAppearance.default_appearance()
	if id == "sailor":
		result.headwear_id = "cap"
		result.facial_hair_id = "moustache"
		result.face_accessory_id = "pipe"
		result.age = 45
	if id in ["dock_worker", "harbour_mechanic"]:
		result.outerwear_id = "vest"
		result.utility_id = "belt"
		result.headwear_id = "hardhat"
		result.eyewear_id = "glasses"
		result.accent_color = Color(.95,.76,.055)
		result.top_color = Color(.18,.27,.32)
	if id == "harbour_master":
		result.age = 58
		result.belly = .3
		result.top_color = Color(.12,.18,.24)
	return result
static func wardrobe_parts(_slot: StringName, _id: String) -> PackedStringArray:
	return PackedStringArray()
static func all_wardrobe_parts(_slot: StringName) -> PackedStringArray:
	return PackedStringArray()
static func wardrobe_model_path(slot: StringName, id: String) -> String:
	return "res://resources/models/characters/mariner.glb" if is_valid(slot,id) and id != "none" else ""
static func cosmetic_metadata(slot: StringName, id: String) -> Dictionary:
	return option(slot,id)
