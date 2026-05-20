class_name CharacterAppearance
extends RefCounted

## Serializable captain look — drives NpcBase tinting and hat overlays.
## Extend with more slots (coat, boots, …) as mesh parts arrive.

const HAT_NONE := ""
const HAT_FLAT_CAP := "flat_cap"
const HAT_PEAKED_CAP := "peaked_cap"

const HAT_PATHS: Dictionary = {
	HAT_FLAT_CAP:   "res://resources/data/meshes/characters/hat_flat_cap.json",
	HAT_PEAKED_CAP: "res://resources/data/meshes/characters/hat_peaked_cap.json",
}

var skin_color: Color = Color(0.72, 0.55, 0.40)
var clothing_color: Color = Color(0.18, 0.20, 0.30)
var trousers_color: Color = Color(0.18, 0.18, 0.20)
var hat_id: String = HAT_NONE


static func default_appearance() -> CharacterAppearance:
	return CharacterAppearance.new()


static func from_dict(d: Dictionary) -> CharacterAppearance:
	var a := CharacterAppearance.new()
	a.skin_color      = _color_from_variant(d.get("skin_color", a.skin_color))
	a.clothing_color  = _color_from_variant(d.get("clothing_color", a.clothing_color))
	a.trousers_color  = _color_from_variant(d.get("trousers_color", a.trousers_color))
	a.hat_id          = str(d.get("hat_id", HAT_NONE))
	if not HAT_PATHS.has(a.hat_id) and a.hat_id != HAT_NONE:
		a.hat_id = HAT_NONE
	return a


static func _color_from_variant(v: Variant) -> Color:
	if typeof(v) == TYPE_COLOR:
		return v as Color
	if typeof(v) == TYPE_ARRAY and (v as Array).size() >= 3:
		var arr := v as Array
		return Color(float(arr[0]), float(arr[1]), float(arr[2]), float(arr[3]) if arr.size() > 3 else 1.0)
	if typeof(v) == TYPE_STRING:
		return Color.from_string(v as String, Color.WHITE)
	return Color.WHITE


func to_dict() -> Dictionary:
	return {
		"skin_color":      [skin_color.r, skin_color.g, skin_color.b, skin_color.a],
		"clothing_color":  [clothing_color.r, clothing_color.g, clothing_color.b, clothing_color.a],
		"trousers_color":  [trousers_color.r, trousers_color.g, trousers_color.b, trousers_color.a],
		"hat_id":          hat_id,
	}


func duplicate() -> CharacterAppearance:
	var c := CharacterAppearance.new()
	c.skin_color     = skin_color
	c.clothing_color = clothing_color
	c.trousers_color = trousers_color
	c.hat_id         = hat_id
	return c


func apply_to_npc(npc: NpcBase) -> void:
	if npc == null:
		return
	npc.skin_color      = skin_color
	npc.clothing_color  = clothing_color
	npc.trousers_color  = trousers_color
	npc.remove_overlay("hat")
	if hat_id != HAT_NONE and HAT_PATHS.has(hat_id):
		npc.add_overlay("hat", str(HAT_PATHS[hat_id]))
