class_name CharacterGarment
extends Node

const TEXTURE_MATERIAL_CATALOG := preload("res://scripts/core/texture_material_catalog.gd")

## Attaches a data-authored garment to named joints on CharacterVisual. Each
## mesh remains a normal MeshTransformer, so clothing follows the same JSON,
## material cache, and procedural animation path as the underlying body.

const GENERATED_PREFIX := "GarmentPart_"

var model_data_path := ""
var _visual: CharacterVisual
var _parts: Array[MeshTransformer] = []
var _appearance_overrides: Dictionary = {}


func attach(visual: CharacterVisual, data_path: String, appearance_overrides: Dictionary = {}) -> bool:
	clear()
	_visual = visual
	model_data_path = data_path
	_appearance_overrides = appearance_overrides.duplicate(true)
	if _visual == null or model_data_path.is_empty():
		return false
	var data := JsonUtil.load(model_data_path)
	if data.is_empty() or typeof(data.get("parts", null)) != TYPE_ARRAY:
		push_error("CharacterGarment: invalid model `%s`" % model_data_path)
		return false
	for raw_part in data.parts:
		if typeof(raw_part) != TYPE_DICTIONARY:
			continue
		_build_part(raw_part as Dictionary)
	return not _parts.is_empty()


func clear() -> void:
	for child in _parts:
		if child == null or not is_instance_valid(child):
			continue
		var parent := child.get_parent()
		if parent != null:
			parent.remove_child(child)
		child.free()
	_parts.clear()


func _build_part(spec: Dictionary) -> void:
	var anchor_name := str(spec.get("anchor", ""))
	var anchor := _visual.get_part(anchor_name)
	if anchor == null:
		push_warning("CharacterGarment: unknown body anchor `%s`" % anchor_name)
		return
	var mesh_data = spec.get("mesh", {})
	if typeof(mesh_data) != TYPE_DICTIONARY:
		return
	var part := MeshTransformer.new()
	part.name = GENERATED_PREFIX + _safe_name(str(spec.get("name", anchor_name)))
	part.rebuild_suspended = true
	part.create_collision = false
	part.center_mesh = false
	part.mesh_geometry_cache_id = "%s::part:%s" % [model_data_path, str(spec.get("name", anchor_name))]
	part.mesh_data = mesh_data
	var appearance := _texture_appearance(spec)
	part.mesh_color = TEXTURE_MATERIAL_CATALOG.color_value(appearance.get("color", Color.WHITE))
	part.mesh_roughness = float(appearance.get("roughness", 0.92))
	part.mesh_metallic = float(appearance.get("metallic", 0.0))
	part.mesh_texture_path = _resolve_asset_path(str(appearance.get("texture", "")))
	part.mesh_texture_mask_path = _resolve_asset_path(str(appearance.get("texture_mask", "")))
	part.mesh_primary_color = TEXTURE_MATERIAL_CATALOG.color_value(appearance.get("primary_color", Color.WHITE))
	part.mesh_secondary_color = TEXTURE_MATERIAL_CATALOG.color_value(appearance.get("secondary_color", Color.WHITE))
	part.position = _vector3_from_array(spec.get("position", []))
	part.rotation_degrees = _vector3_from_array(spec.get("rotation_degrees", []))
	part.rebuild_suspended = false
	anchor.add_child(part)
	part.rebuild()
	_parts.append(part)


func _texture_appearance(spec: Dictionary) -> Dictionary:
	var result: Dictionary = TEXTURE_MATERIAL_CATALOG.resolve(str(spec.get("texture_profile", "")))
	for key in ["texture", "texture_mask", "primary_color", "secondary_color", "color", "roughness", "metallic"]:
		if spec.has(key):
			result[key] = spec[key]
	var primary := TEXTURE_MATERIAL_CATALOG.color_value(
		_appearance_overrides.get("primary_color", result.get("primary_color", Color.WHITE)))
	var secondary := TEXTURE_MATERIAL_CATALOG.color_value(
		_appearance_overrides.get("secondary_color", result.get("secondary_color", primary.darkened(0.18))))
	var channel := str(spec.get("palette_channel", "primary"))
	if channel == "secondary":
		var swap := primary
		primary = secondary
		secondary = swap
	elif channel == "dark":
		primary = primary.darkened(0.24)
		secondary = secondary.darkened(0.24)
	elif channel == "light":
		primary = primary.lightened(0.20)
		secondary = secondary.lightened(0.20)
	result["primary_color"] = primary
	result["secondary_color"] = secondary
	var textured := not str(result.get("texture", "")).is_empty() and not str(result.get("texture_mask", "")).is_empty()
	if not textured and channel != "fixed":
		result["color"] = primary
	for key in ["roughness", "metallic"]:
		if _appearance_overrides.has(key):
			result[key] = _appearance_overrides[key]
	return result


func _resolve_asset_path(path: String) -> String:
	if path.is_empty() or path.begins_with("res://") or path.begins_with("user://"):
		return path
	return model_data_path.get_base_dir().path_join(path)


func _vector3_from_array(value: Variant) -> Vector3:
	if typeof(value) != TYPE_ARRAY or value.size() < 3:
		return Vector3.ZERO
	return Vector3(float(value[0]), float(value[1]), float(value[2]))


func _safe_name(value: String) -> String:
	return value.replace(" ", "_").replace("/", "_").replace(":", "_")
