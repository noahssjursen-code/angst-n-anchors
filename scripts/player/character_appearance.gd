class_name CharacterAppearance
extends RefCounted

## Serializable captain look — drives NpcBase tinting and hat overlays.
## Extend with more slots (coat, boots, …) as mesh parts arrive.

const HAT_NONE := ""
const HAT_FLAT_CAP := "flat_cap"
const HAT_PEAKED_CAP := "peaked_cap"

const HAT_PATHS: Dictionary = {
	HAT_FLAT_CAP:   AssetPaths.HAT_FLAT_CAP,
	HAT_PEAKED_CAP: AssetPaths.HAT_PEAKED_CAP,
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


func to_meta_string(display_name: String = "", captain_id: String = "") -> String:
	var parts: PackedStringArray = [
		"skin=%s" % skin_color.to_html(false),
		"coat=%s" % clothing_color.to_html(false),
		"pants=%s" % trousers_color.to_html(false),
		"hat=%s" % hat_id,
	]
	if not display_name.is_empty():
		parts.append("name=%s" % display_name)
	if not captain_id.is_empty():
		parts.append("cid=%s" % captain_id)
	return ";".join(parts)


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
	npc.set_colors(skin_color, clothing_color, trousers_color)
	if hat_id == HAT_NONE:
		npc.remove_overlay("hat")
	elif HAT_PATHS.has(hat_id):
		var hat_path: String = str(HAT_PATHS[hat_id])
		var existing := npc.get_node_or_null("Overlay_hat") as ModelAssembler
		if existing == null or existing.model_data_path != hat_path:
			npc.add_overlay("hat", hat_path)
