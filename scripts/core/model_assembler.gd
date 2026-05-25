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
##       "mesh": "res://resources/data/meshes/ships/hull.json",
##       // or: "mesh": { "vertices": [...], "indices": [...] },
##       // or: "model": "res://resources/data/models/ships/nested_model.json",
##       "role": "physics_body",
##       "parent": "other_part_name",  // optional: attach under a previously-built
##                                       // sibling part so position / rotation
##                                       // inherit from that node (articulated rigs).
##                                       // Default: attach to assembler root.
##       "position": [0, 0, 0],
##       "rotation_degrees": [0, 0, 0],
##       "scale": 1.0,
##       "color": [0.1, 0.1, 0.1],
##       "roughness": 0.9,
##       "metallic": 0.0,
##       "invert_collision_face_winding": false,
##       "collision_double_sided": true, // concave only: default true (thin walls solid both sides)
##       "collision": "convex"      // optional: "none" | "convex" | "concave"
##                                    // concave = triangle mesh; static bodies only
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

## When false, collision-enabled parts still contribute points through
## `get_collision_points_in`, but do not spawn separate CollisionShape3D nodes.
@export var build_part_colliders: bool = true:
	set(v):
		if build_part_colliders == v:
			return
		build_part_colliders = v
		if is_node_ready():
			rebuild()

var _part_nodes_by_name: Dictionary = {}
var _part_nodes_by_role: Dictionary = {}
var _part_specs_by_name: Dictionary = {}
var _collidable_parts_by_name: Dictionary = {}
var collision_mode_override: String = ""


func _ready() -> void:
	rebuild()


func rebuild() -> void:
	_clear_generated_parts()
	_part_nodes_by_name.clear()
	_part_nodes_by_role.clear()
	_part_specs_by_name.clear()
	_collidable_parts_by_name.clear()

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
	var node: Variant = _part_nodes_by_name.get(part_name, null)
	if node == null or not is_instance_valid(node):
		return null
	return node as MeshTransformer


func get_first_part_by_role(role: String) -> MeshTransformer:
	var parts: Array = _part_nodes_by_role.get(role, [])
	if parts.is_empty():
		return null
	return parts[0] as MeshTransformer


## Roles are declared on MeshTransformer leaf parts; `model` nests another assembler in between.
## Boat hull bounds and tooling that need mesh metrics must recurse (see `boat_body`).
func get_first_mesh_part_by_role(role: String) -> MeshTransformer:
	var direct_at_level: Variant = _part_nodes_by_role.get(role, [])
	if typeof(direct_at_level) == TYPE_ARRAY:
		for entry in direct_at_level:
			if entry is MeshTransformer:
				return entry as MeshTransformer
	for pk in _part_nodes_by_name.keys():
		var child: Node = _part_nodes_by_name[pk]
		if child is ModelAssembler:
			var inner := (child as ModelAssembler).get_first_mesh_part_by_role(role)
			if inner != null:
				return inner
	return null


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
	# Optional `parent: "<part_name>"` lets a part attach to a previously-built
	# sibling instead of the assembler root. Lets us build articulated rigs
	# (hand follows arm, tool follows hand) without a Skeleton3D — just nested
	# Node3Ds. Parent must appear before child in the JSON; if unknown, falls
	# back to the assembler root with a warning.
	var parent_node := _resolve_part_parent(part, part_name)
	parent_node.add_child(node)
	if Engine.is_editor_hint() and is_inside_tree():
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
	node.invert_collision_face_winding = bool(part.get("invert_collision_face_winding", false))
	var is_collidable := _part_collision_enabled(part)
	var col_key := str(part.get("collision", "none")).to_lower()
	node.collision_mode = "concave" if col_key == "concave" else "convex"
	node.collision_double_sided = bool(part.get("collision_double_sided", true))
	node.create_collision = is_collidable and build_part_colliders
	node.collision_parent_path = _collision_path_for_part(node)
	node.rebuild_suspended = false
	node.rebuild()

	_part_nodes_by_name[part_name] = node
	_part_specs_by_name[part_name] = part.duplicate()
	_collidable_parts_by_name[part_name] = is_collidable

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
	var parent_node := _resolve_part_parent(part, part_name)
	parent_node.add_child(node)
	if Engine.is_editor_hint() and is_inside_tree():
		node.owner = get_tree().edited_scene_root

	node.collision_parent_path = _collision_path_for_part(node)
	node.collision_mode_override = _nested_collision_override(part)
	node.build_part_colliders = build_part_colliders
	node.absolute_scale = absolute_scale * float(part.get("scale", 1.0))
	node.model_data_path = model_path

	_part_nodes_by_name[part_name] = node
	_part_specs_by_name[part_name] = part.duplicate()
	_collidable_parts_by_name[part_name] = _nested_collision_override(part) != "none"

	var role := str(part.get("role", ""))
	if not role.is_empty():
		if not _part_nodes_by_role.has(role):
			_part_nodes_by_role[role] = []
		_part_nodes_by_role[role].append(node)


func get_collision_points_in(target: Node3D) -> Array[Vector3]:
	var points: Array[Vector3] = []
	if target == null:
		return points

	for part_name in _part_nodes_by_name.keys():
		if not bool(_collidable_parts_by_name.get(part_name, false)):
			continue
		var node := _part_nodes_by_name[part_name] as Node
		if node == null:
			continue
		if node.has_method("get_collision_points_in"):
			points.append_array(node.call("get_collision_points_in", target))

	return points


func get_collision_faces_in(target: Node3D) -> Array[Vector3]:
	var faces: Array[Vector3] = []
	if target == null:
		return faces

	for part_name in _part_nodes_by_name.keys():
		if not bool(_collidable_parts_by_name.get(part_name, false)):
			continue
		var node := _part_nodes_by_name[part_name] as Node
		if node == null:
			continue
		if node.has_method("get_collision_faces_in"):
			faces.append_array(node.call("get_collision_faces_in", target))

	return faces


## Resolves the Node a freshly-built part should attach to. Default is the
## assembler root. If the part declares `parent: "<other_part_name>"`, look
## that previously-built part up and use it instead — produces a Node3D
## hierarchy without needing a Skeleton3D.
func _resolve_part_parent(part: Dictionary, part_name: String) -> Node:
	if not part.has("parent"):
		return self
	var parent_key := str(part.get("parent", "")).strip_edges()
	if parent_key.is_empty():
		return self
	var parent_node := _part_nodes_by_name.get(parent_key, null) as Node
	if parent_node == null:
		push_warning("ModelAssembler: part `%s` references unknown parent `%s` — attaching to root" % [part_name, parent_key])
		return self
	return parent_node


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


## Thin wrapper around JsonUtil.load() — kept as an instance method so existing
## callers work unchanged.
func _load_json(path: String) -> Dictionary:
	return JsonUtil.load(path)


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
