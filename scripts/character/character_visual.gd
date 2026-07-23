@tool
class_name CharacterVisual
extends Node3D

## Shared block-built character renderer. The approved body remains the rig;
## wardrobe pieces are fitted JSON shells attached to its animated anchors.

const BODY_COLOR := Color("344653")
const TEXTURE_MATERIAL_CATALOG := preload("res://scripts/core/texture_material_catalog.gd")

var appearance: CharacterAppearance = CharacterAppearance.default_appearance()
var _body_root: Node3D
var _rig: ModelAssembler
var _decorated := true
var _garments: Array[CharacterGarment] = []


func _ready() -> void:
	rebuild()


func apply_appearance(value: CharacterAppearance) -> void:
	appearance = value.duplicate() if value != null else CharacterAppearance.default_appearance()
	if is_node_ready():
		rebuild()


func set_decorated(value: bool) -> void:
	if _decorated == value:
		return
	_decorated = value
	if is_node_ready():
		rebuild()


func rebuild() -> void:
	_clear_body()
	_body_root = Node3D.new()
	_body_root.name = "BodyRoot"
	add_child(_body_root)

	_rig = ModelAssembler.new()
	_rig.name = "BaseBody"
	_rig.model_data_path = AssetPaths.NPC_CHARACTER_STUDY_MODEL
	_rig.build_part_colliders = false
	_body_root.add_child(_rig)

	_apply_base_colors()
	if _decorated:
		_build_wardrobe()


func get_part(part_name: String) -> Node3D:
	if _rig != null:
		var base_part := _rig.get_part(part_name)
		if base_part != null:
			return base_part
	return null


func get_base_assembler() -> ModelAssembler:
	return _rig


func get_all_assemblers() -> Array[ModelAssembler]:
	var out: Array[ModelAssembler] = []
	if _rig != null:
		out.append(_rig)
	return out


func get_hand_anchor(side: String) -> Node3D:
	return get_part("hand_%s" % side)


func _clear_body() -> void:
	if _body_root != null and is_instance_valid(_body_root):
		remove_child(_body_root)
		_body_root.free()
	_body_root = null
	_rig = null
	_garments.clear()


func _build_wardrobe() -> void:
	for slot in [
		&"trousers", &"footwear", &"tops", &"outerwear", &"hair",
		&"facial_hair", &"headwear", &"eyewear", &"face_accessories",
		&"neckwear", &"handwear", &"utility_accessories",
	]:
		var item_id := _appearance_id_for_slot(slot)
		if item_id.is_empty() or item_id == "none":
			continue
		var model_path := CharacterCatalog.wardrobe_model_path(slot, item_id)
		if model_path.is_empty() or not FileAccess.file_exists(model_path):
			continue
		var garment := CharacterGarment.new()
		garment.name = "Wardrobe_%s_%s" % [String(slot), item_id]
		_body_root.add_child(garment)
		if garment.attach(self, model_path, _palette_for_slot(slot)):
			_garments.append(garment)
		else:
			garment.queue_free()


func _appearance_id_for_slot(slot: StringName) -> String:
	match slot:
		&"hair": return appearance.hair_id
		&"facial_hair": return appearance.facial_hair_id
		&"tops": return appearance.top_id
		&"outerwear": return appearance.outerwear_id
		&"trousers": return appearance.trousers_id
		&"footwear": return appearance.footwear_id
		&"headwear": return appearance.headwear_id
		&"eyewear": return appearance.eyewear_id
		&"face_accessories": return appearance.face_accessory_id
		&"neckwear": return appearance.neckwear_id
		&"handwear": return appearance.handwear_id
		&"utility_accessories": return appearance.utility_id
	return "none"


func _palette_for_slot(slot: StringName) -> Dictionary:
	var primary := appearance.accessory_color
	var secondary := appearance.accent_color
	match slot:
		&"hair", &"facial_hair":
			primary = appearance.hair_color
			secondary = appearance.hair_color.darkened(0.22)
		&"tops":
			primary = appearance.top_color
			# The reference sweater is a cream-and-charcoal micro-knit. It should
			# not inherit a bright company accent and turn into a novelty jumper.
			if appearance.top_id == "wool_sweater":
				secondary = Color("191d20")
			elif appearance.top_id == "plain_wool_sweater":
				secondary = appearance.top_color.darkened(0.28)
			else:
				secondary = appearance.accent_color
		&"outerwear":
			primary = appearance.clothing_color
			# Tailored wool uses tonal construction detail. A company accent is
			# appropriate on safety gear and oilskins, but it made suit lapels and
			# peacoat collars read like costume trim.
			if appearance.outerwear_id in ["shore_suit_jacket", "wool_peacoat"]:
				secondary = appearance.clothing_color.darkened(0.18)
			elif appearance.outerwear_id in ["rain_jacket_yellow", "rain_jacket_orange"]:
				# Oilskin construction details are tonal. Preset accents belong on
				# company markings and accessories, not the whole storm closure.
				secondary = appearance.clothing_color.darkened(0.12)
			else:
				secondary = appearance.accent_color
		&"trousers":
			primary = appearance.trousers_color
			if appearance.trousers_id == "rain_trousers":
				secondary = appearance.trousers_color.darkened(0.12)
			else:
				secondary = appearance.accent_color
		&"footwear":
			primary = appearance.footwear_color
			secondary = appearance.footwear_color.darkened(0.25)
		&"headwear":
			primary = appearance.headwear_color
			if appearance.headwear_id == "souwester":
				secondary = appearance.headwear_color.darkened(0.10)
			else:
				secondary = appearance.accent_color
		&"eyewear":
			primary = appearance.accessory_color
			secondary = appearance.accessory_color.darkened(0.18)
		&"handwear":
			primary = appearance.accessory_color
			secondary = appearance.accessory_color.darkened(0.12)
	return {
		"primary_color": primary,
		"secondary_color": secondary,
	}


func _apply_base_colors() -> void:
	_tint_role(_rig, "body_upper", BODY_COLOR)
	_tint_role(_rig, "body_lower", BODY_COLOR)
	_tint_role(_rig, "skin", appearance.skin_color)
	_tint_role(_rig, "skin_shadow", appearance.skin_color.darkened(0.06))
	_tint_role(_rig, "nose", appearance.skin_color.darkened(0.08))
	_tint_role(_rig, "face_ink", Color("14191c"))
	_tint_role(_rig, "mouth", Color("493338"))
	_tint_role(_rig, "footwear", BODY_COLOR.darkened(0.30))
	_apply_face_surface()


func _apply_face_surface() -> void:
	if appearance.face_texture_profile_id == "none":
		return
	var head := get_part("head") as MeshTransformer
	if head == null:
		return
	var profile := TEXTURE_MATERIAL_CATALOG.resolve(appearance.face_texture_profile_id)
	if profile.is_empty():
		return
	# The mask supplies the skin palette. Keeping the solid part tint here would
	# multiply the skin colour by itself and darken textured faces.
	head.mesh_color = Color.WHITE
	head.mesh_texture_path = str(profile.get("texture", ""))
	head.mesh_texture_mask_path = str(profile.get("texture_mask", ""))
	head.mesh_primary_color = appearance.skin_color
	head.mesh_secondary_color = appearance.skin_color.darkened(0.08)
	head.mesh_roughness = float(profile.get("roughness", head.mesh_roughness))
	head.mesh_metallic = float(profile.get("metallic", head.mesh_metallic))


func _tint_role(assembler: ModelAssembler, role: String, color: Color) -> void:
	if assembler == null:
		return
	for part in assembler.get_parts_by_role(role):
		if part is MeshTransformer:
			(part as MeshTransformer).mesh_color = color
