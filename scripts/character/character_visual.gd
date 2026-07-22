@tool
class_name CharacterVisual
extends Node3D

## Shared block-built neutral character renderer. This checkpoint intentionally
## contains no wardrobe catalogue or clothing assembly. The replacement outfit
## system will be designed against this approved body rather than inheriting the
## discarded character-creator assets.

const BODY_COLOR := Color("344653")

var appearance: CharacterAppearance = CharacterAppearance.default_appearance()
var _body_root: Node3D
var _rig: ModelAssembler


func _ready() -> void:
	rebuild()


func apply_appearance(value: CharacterAppearance) -> void:
	appearance = value.duplicate() if value != null else CharacterAppearance.default_appearance()
	if is_node_ready():
		rebuild()


func set_decorated(value: bool) -> void:
	# Compatibility seam for callers that predate the body-only checkpoint.
	# Decoration is deliberately unavailable until the new slot contract lands.
	pass


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


func _apply_base_colors() -> void:
	_tint_role(_rig, "body_upper", BODY_COLOR)
	_tint_role(_rig, "body_lower", BODY_COLOR)
	_tint_role(_rig, "skin", appearance.skin_color)
	_tint_role(_rig, "skin_shadow", appearance.skin_color.darkened(0.06))
	_tint_role(_rig, "nose", appearance.skin_color.darkened(0.08))
	_tint_role(_rig, "face_ink", Color("14191c"))
	_tint_role(_rig, "mouth", Color("493338"))
	_tint_role(_rig, "footwear", BODY_COLOR.darkened(0.30))


func _tint_role(assembler: ModelAssembler, role: String, color: Color) -> void:
	if assembler == null:
		return
	for part in assembler.get_parts_by_role(role):
		if part is MeshTransformer:
			(part as MeshTransformer).mesh_color = color
