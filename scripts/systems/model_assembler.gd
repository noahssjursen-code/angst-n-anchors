@tool
class_name ModelAssembler
extends Node3D

## Generic multi-part JSON model loader.
##
## This is intentionally not ship-specific. A model assembly is just a list of
## mesh parts with transforms, material colour, optional collision, and a free-form
## `role` string that higher-level systems may choose to interpret.
##
## Expected JSON:
## {
##   "name": "example_model",
##   "parts": [
##     {
##       "name": "body",
##       "mesh": "res://resources/data/meshes/body.json",
##       // or: "mesh": { "vertices": [...], "indices": [...] },
##       // or: "model": "res://resources/data/models/nested_model.json",
##       "role": "physics_body",
##       "position": [0, 0, 0],
##       "rotation_degrees": [0, 0, 0],
##       "scale": 1.0,
##       "color": [0.1, 0.1, 0.1],
##       "roughness": 0.9,
##       "metallic": 0.0,
##       "collision": "convex"
##     }
##   ]
## }

const PART_PREFIX := "ModelPart_"

@export_file("*.json") var model_data_path: String:
	set(v):
		if model_data_path == v:
			return
		model_data_path = v
		if is_node_ready():
			rebuild()

## Uniform scale applied to every part in the assembly. Individual part scale is
## multiplied by this value; neither path ever stretches X/Y/Z independently.
@export var absolute_scale: float = 1.0:
	set(v):
		if is_equal_approx(absolute_scale, v):
			return
		absolute_scale = v
		if is_node_ready():
			rebuild()

## Optional collision target for all generated mesh part colliders.
## If left empty, each MeshTransformer uses its own parent as the target when possible.
@export var collision_parent_path: NodePath:
	set(v):
		if collision_parent_path == v:
			return
		collision_parent_path = v
		if is_node_ready():
			rebuild()

var _part_nodes_by_name: Dictionary = {}
var _part_nodes_by_role: Dictionary = {}
var _part_specs_by_name: Dictionary = {}
var collision_mode_override: String = ""


func _ready() -> void:
	rebuild()


func rebuild() -> void:
	_clear_generated_parts()
	_part_nodes_by_name.clear()
	_part_nodes_by_role.clear()
	_part_specs_by_name.clear()

	if model_data_path.is_empty():
		return

	var data := _load_json(model_data_path)
	if data.is_empty():
		return
	if not data.has("parts") or typeof(data["parts"]) != TYPE_ARRAY:
		push_error("ModelAssembler: missing `parts` array in " + model_data_path)
		return

	for raw_part in data["parts"]:
		if typeof(raw_part) != TYPE_DICTIONARY:
			continue
		_build_part(raw_part)


func get_part(part_name: String) -> MeshTransformer:
	return _part_nodes_by_name.get(part_name, null) as MeshTransformer


func get_first_part_by_role(role: String) -> MeshTransformer:
	var parts: Array = _part_nodes_by_role.get(role, [])
	if parts.is_empty():
		return null
	return parts[0] as MeshTransformer


func get_parts_by_role(role: String) -> Array:
	return _part_nodes_by_role.get(role, []).duplicate()


func get_part_spec(part_name: String) -> Dictionary:
	return _part_specs_by_name.get(part_name, {}).duplicate()


func _build_part(part: Dictionary) -> void:
	var part_name := str(part.get("name", "part_" + str(_part_nodes_by_name.size())))
	if part.has("model"):
		_build_nested_model(part_name, part)
		return

	var mesh_value = part.get("mesh", "")
	if not _is_valid_mesh_value(mesh_value):
		push_warning("ModelAssembler: part `" + part_name + "` has invalid mesh data")
		return

	var node := MeshTransformer.new()
	node.name = PART_PREFIX + _safe_node_name(part_name)
	node.position = _vector3_from_array(part.get("position", []), Vector3.ZERO) * absolute_scale
	add_child(node)
	if Engine.is_editor_hint():
		node.owner = get_tree().edited_scene_root

	node.rebuild_suspended = true
	if typeof(mesh_value) == TYPE_DICTIONARY:
		node.mesh_data = mesh_value
	else:
		node.mesh_data_path = _resolve_mesh_path(str(mesh_value))
	node.absolute_scale = absolute_scale * float(part.get("scale", 1.0))
	node.mesh_rotation_degrees = _vector3_from_array(part.get("rotation_degrees", []), Vector3.ZERO)
	node.center_mesh = bool(part.get("center_mesh", false))
	node.mesh_color = _color_from_array(part.get("color", [0.5, 0.5, 0.5]), Color(0.5, 0.5, 0.5))
	node.mesh_roughness = float(part.get("roughness", 0.96))
	node.mesh_metallic = float(part.get("metallic", 0.0))
	node.create_collision = _part_collision_enabled(part)
	node.collision_parent_path = _collision_path_for_part(node)
	node.rebuild_suspended = false
	node.rebuild()

	_part_nodes_by_name[part_name] = node
	_part_specs_by_name[part_name] = part.duplicate()

	var role := str(part.get("role", ""))
	if not role.is_empty():
		if not _part_nodes_by_role.has(role):
			_part_nodes_by_role[role] = []
		_part_nodes_by_role[role].append(node)


func _build_nested_model(part_name: String, part: Dictionary) -> void:
	var model_path := _resolve_model_path(str(part.get("model", "")))
	if model_path.is_empty():
		push_warning("ModelAssembler: nested model `" + part_name + "` has no model path")
		return

	var node := ModelAssembler.new()
	node.name = PART_PREFIX + _safe_node_name(part_name)
	node.position = _vector3_from_array(part.get("position", []), Vector3.ZERO) * absolute_scale
	node.rotation_degrees = _vector3_from_array(part.get("rotation_degrees", []), Vector3.ZERO)
	add_child(node)
	if Engine.is_editor_hint():
		node.owner = get_tree().edited_scene_root

	node.collision_parent_path = _collision_path_for_part(node)
	node.collision_mode_override = _nested_collision_override(part)
	node.absolute_scale = absolute_scale * float(part.get("scale", 1.0))
	node.model_data_path = model_path

	_part_nodes_by_name[part_name] = node
	_part_specs_by_name[part_name] = part.duplicate()

	var role := str(part.get("role", ""))
	if not role.is_empty():
		if not _part_nodes_by_role.has(role):
			_part_nodes_by_role[role] = []
		_part_nodes_by_role[role].append(node)


func _clear_generated_parts() -> void:
	for child in get_children():
		if child.name.begins_with(PART_PREFIX):
			remove_child(child)
			child.free()


func _part_collision_enabled(part: Dictionary) -> bool:
	if collision_mode_override == "none":
		return false
	return str(part.get("collision", "none")) != "none"


func _nested_collision_override(part: Dictionary) -> String:
	if collision_mode_override == "none":
		return "none"
	var mode := str(part.get("collision", ""))
	if mode == "none":
		return "none"
	return ""


func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("ModelAssembler: file not found: " + path)
		return {}

	var file := FileAccess.open(path, FileAccess.READ)
	var json_string := file.get_as_text()
	file.close()

	var json := JSON.new()
	var error := json.parse(json_string)
	if error != OK:
		push_error("ModelAssembler: JSON parse error in " + path)
		return {}

	var data = json.get_data()
	if typeof(data) != TYPE_DICTIONARY:
		push_error("ModelAssembler: root must be an object in " + path)
		return {}
	return data


func _resolve_mesh_path(mesh_path: String) -> String:
	if mesh_path.is_empty():
		return ""
	if mesh_path.begins_with("res://") or mesh_path.begins_with("user://"):
		return mesh_path

	var base_dir := model_data_path.get_base_dir()
	var local_path := base_dir.path_join(mesh_path)
	if FileAccess.file_exists(local_path):
		return local_path

	var mesh_data_path := "res://resources/data/meshes".path_join(mesh_path)
	if FileAccess.file_exists(mesh_data_path):
		return mesh_data_path

	return local_path


func _resolve_model_path(model_path: String) -> String:
	if model_path.is_empty():
		return ""
	if model_path.begins_with("res://") or model_path.begins_with("user://"):
		return model_path

	var base_dir := model_data_path.get_base_dir()
	var local_path := base_dir.path_join(model_path)
	if FileAccess.file_exists(local_path):
		return local_path

	var mesh_data_path := "res://resources/data/meshes".path_join(model_path)
	if FileAccess.file_exists(mesh_data_path):
		return mesh_data_path

	var model_data_path_candidate := "res://resources/data/models".path_join(model_path)
	if FileAccess.file_exists(model_data_path_candidate):
		return model_data_path_candidate

	return local_path


func _is_valid_mesh_value(value) -> bool:
	if typeof(value) == TYPE_STRING:
		return not str(value).is_empty()
	if typeof(value) == TYPE_DICTIONARY:
		return value.has("vertices") and value.has("indices")
	return false


func _vector3_from_array(value, fallback: Vector3) -> Vector3:
	if typeof(value) != TYPE_ARRAY or value.size() < 3:
		return fallback
	return Vector3(float(value[0]), float(value[1]), float(value[2]))


func _color_from_array(value, fallback: Color) -> Color:
	if typeof(value) != TYPE_ARRAY or value.size() < 3:
		return fallback
	var alpha := 1.0
	if value.size() > 3:
		alpha = float(value[3])
	return Color(float(value[0]), float(value[1]), float(value[2]), alpha)


func _collision_path_for_part(part_node: Node) -> NodePath:
	if collision_parent_path.is_empty():
		return NodePath("")
	var target := get_node_or_null(collision_parent_path)
	if target == null:
		return NodePath("")
	return part_node.get_path_to(target)


func _safe_node_name(value: String) -> String:
	return value.replace(" ", "_").replace("@", "_").replace(":", "_").replace("/", "_")
