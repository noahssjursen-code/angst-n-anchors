class_name CharacterAppearance
extends RefCounted

## Shared, JSON-safe character appearance contract. NPCs and players use the
## same record so a server only needs to replicate data, never scene nodes.

const SCHEMA_VERSION := 6
const CHARACTER_CATALOG := preload("res://scripts/character/character_catalog.gd")
const HAT_NONE := ""

var skin_color := Color(0.72, 0.55, 0.40)
var clothing_color := Color(0.18, 0.20, 0.30)
var top_color := Color(0.86, 0.87, 0.81)
var trousers_color := Color(0.15, 0.23, 0.28)
var hair_color := Color(0.12, 0.075, 0.045)
var headwear_color := Color(0.16, 0.18, 0.20)
var footwear_color := Color(0.075, 0.065, 0.055)
var accent_color := Color(0.92, 0.48, 0.08)
var accessory_color := Color(0.20, 0.23, 0.25)
var company_primary_color := Color(0.10, 0.22, 0.32)
var company_secondary_color := Color(0.90, 0.45, 0.10)
var body_id := "mariner"
var hair_id := "crop"
var facial_hair_id := "none"
var top_id := "sweater"
var outerwear_id := ""
var trousers_id := "work"
var footwear_id := "boots"
## Authored morph weights. Visual proportions, not gameplay stats.
var build := 0.2
var belly := 0.0
var frame := 0.0
var age := 32.0
var headwear_id := "none"
var eyewear_id := "none"
var face_accessory_id := "none"
## Opaque appearance identifier retained for save compatibility. No assets installed.
var face_texture_profile_id := ""
var neckwear_id := "none"
var handwear_id := "none"
var utility_id := "none"
var uniform_id := "none"
## Legacy slot retained for save migration and the old NpcBase renderer.
var hat_id := HAT_NONE


static func default_appearance() -> CharacterAppearance:
	return CharacterAppearance.new()


static func from_dict(d: Dictionary) -> CharacterAppearance:
	var a := CharacterAppearance.new()
	a.build = clampf(float(d.get("build", a.build)), 0.0, 1.0)
	a.belly = clampf(float(d.get("belly", a.belly)), 0.0, 1.0)
	a.frame = clampf(float(d.get("frame", a.frame)), 0.0, 1.0)
	a.age = clampf(float(d.get("age", a.age)), 18.0, 80.0)
	a.skin_color = _color_from_variant(d.get("skin_color", a.skin_color), a.skin_color)
	a.clothing_color = _color_from_variant(d.get("clothing_color", a.clothing_color), a.clothing_color)
	a.top_color = _color_from_variant(d.get("top_color", d.get("clothing_color", a.top_color)), a.top_color)
	a.trousers_color = _color_from_variant(d.get("trousers_color", a.trousers_color), a.trousers_color)
	a.hair_color = _color_from_variant(d.get("hair_color", a.hair_color), a.hair_color)
	a.headwear_color = _color_from_variant(d.get("headwear_color", d.get("hair_color", a.headwear_color)), a.headwear_color)
	a.footwear_color = _color_from_variant(d.get("footwear_color", a.footwear_color), a.footwear_color)
	a.accent_color = _color_from_variant(d.get("accent_color", a.accent_color), a.accent_color)
	a.accessory_color = _color_from_variant(d.get("accessory_color", a.accessory_color), a.accessory_color)
	a.company_primary_color = _color_from_variant(d.get("company_primary_color", a.company_primary_color), a.company_primary_color)
	a.company_secondary_color = _color_from_variant(d.get("company_secondary_color", a.company_secondary_color), a.company_secondary_color)
	a.body_id = CHARACTER_CATALOG.normalized_id(&"body_presets", str(d.get("body_id", a.body_id)), a.body_id)
	a.hair_id = CHARACTER_CATALOG.normalized_id(&"hair", str(d.get("hair_id", a.hair_id)), a.hair_id)
	a.facial_hair_id = CHARACTER_CATALOG.normalized_id(&"facial_hair", str(d.get("facial_hair_id", a.facial_hair_id)), a.facial_hair_id)
	a.top_id = CHARACTER_CATALOG.normalized_id(&"tops", str(d.get("top_id", a.top_id)), a.top_id)
	a.outerwear_id = CHARACTER_CATALOG.normalized_id(&"outerwear", str(d.get("outerwear_id", a.outerwear_id)), a.outerwear_id)
	a.trousers_id = CHARACTER_CATALOG.normalized_id(&"trousers", str(d.get("trousers_id", a.trousers_id)), a.trousers_id)
	a.footwear_id = CHARACTER_CATALOG.normalized_id(&"footwear", str(d.get("footwear_id", a.footwear_id)), a.footwear_id)
	var migrated_headwear := str(d.get("headwear_id", d.get("hat_id", "none")))
	if migrated_headwear.is_empty():
		migrated_headwear = "none"
	a.headwear_id = CHARACTER_CATALOG.normalized_id(&"headwear", migrated_headwear, "none")
	a.eyewear_id = CHARACTER_CATALOG.normalized_id(&"eyewear", str(d.get("eyewear_id", a.eyewear_id)), "none")
	a.face_accessory_id = CHARACTER_CATALOG.normalized_id(&"face_accessories", str(d.get("face_accessory_id", a.face_accessory_id)), "none")
	a.face_texture_profile_id = CHARACTER_CATALOG.normalized_id(
		&"face_surfaces",
		str(d.get("face_texture_profile_id", a.face_texture_profile_id)).strip_edges(),
		""
	)
	a.neckwear_id = CHARACTER_CATALOG.normalized_id(&"neckwear", str(d.get("neckwear_id", a.neckwear_id)), "none")
	a.handwear_id = CHARACTER_CATALOG.normalized_id(&"handwear", str(d.get("handwear_id", a.handwear_id)), "none")
	a.utility_id = CHARACTER_CATALOG.normalized_id(&"utility_accessories", str(d.get("utility_id", a.utility_id)), "none")
	a.uniform_id = CHARACTER_CATALOG.normalized_id(&"uniform_templates", str(d.get("uniform_id", a.uniform_id)), "none")
	a.hat_id = str(d.get("hat_id", HAT_NONE))
	return a


static func from_json_string(json: String) -> CharacterAppearance:
	var parsed: Variant = JSON.parse_string(json)
	return from_dict(parsed as Dictionary) if typeof(parsed) == TYPE_DICTIONARY else null


static func _color_from_variant(value: Variant, fallback: Color = Color.WHITE) -> Color:
	if typeof(value) == TYPE_COLOR:
		return value as Color
	if typeof(value) == TYPE_ARRAY and (value as Array).size() >= 3:
		var arr := value as Array
		return Color(float(arr[0]), float(arr[1]), float(arr[2]), float(arr[3]) if arr.size() > 3 else 1.0)
	if typeof(value) == TYPE_STRING:
		return Color.from_string(value as String, fallback)
	return fallback


func to_dict() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"build": build,
		"belly": belly,
		"frame": frame,
		"age": age,
		"body_id": body_id,
		"hair_id": hair_id,
		"facial_hair_id": facial_hair_id,
		"top_id": top_id,
		"outerwear_id": outerwear_id,
		"trousers_id": trousers_id,
		"footwear_id": footwear_id,
		"headwear_id": headwear_id,
		"eyewear_id": eyewear_id,
		"face_accessory_id": face_accessory_id,
		"face_texture_profile_id": face_texture_profile_id,
		"neckwear_id": neckwear_id,
		"handwear_id": handwear_id,
		"utility_id": utility_id,
		"uniform_id": uniform_id,
		"hat_id": hat_id,
		"skin_color": _color_array(skin_color),
		"clothing_color": _color_array(clothing_color),
		"top_color": _color_array(top_color),
		"trousers_color": _color_array(trousers_color),
		"hair_color": _color_array(hair_color),
		"headwear_color": _color_array(headwear_color),
		"footwear_color": _color_array(footwear_color),
		"accent_color": _color_array(accent_color),
		"accessory_color": _color_array(accessory_color),
		"company_primary_color": _color_array(company_primary_color),
		"company_secondary_color": _color_array(company_secondary_color),
	}


func to_json_string() -> String:
	return JSON.stringify(to_dict(), "  ")


func to_meta_string(display_name: String = "", captain_id: String = "") -> String:
	var encoded_appearance := Marshalls.raw_to_base64(to_json_string().to_utf8_buffer())
	var parts := PackedStringArray([
		"skin=%s" % skin_color.to_html(false), "coat=%s" % clothing_color.to_html(false),
		"pants=%s" % trousers_color.to_html(false), "hat=%s" % hat_id,
		"appearance=%s" % encoded_appearance,
	])
	if not display_name.is_empty(): parts.append("name=%s" % display_name)
	if not captain_id.is_empty(): parts.append("cid=%s" % captain_id)
	return ";".join(parts)


func duplicate() -> CharacterAppearance:
	return CharacterAppearance.from_dict(to_dict())


func apply_to_npc(npc: NpcBase) -> void:
	if npc != null:
		npc.apply_appearance(self)


static func _color_array(color: Color) -> Array:
	return [color.r, color.g, color.b, color.a]
