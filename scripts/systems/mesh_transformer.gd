@tool
class_name MeshTransformer
extends Node3D

## Component that takes a mesh JSON and transforms it into a 3D model with collision.
## Handles normalization, scaling, and runtime construction.

@export_file("*.json") var mesh_data_path: String:
	set(v):
		mesh_data_path = v
		if is_node_ready():
			rebuild()

@export var mesh_color: Color = Color(0.5, 0.5, 0.5):
	set(v):
		mesh_color = v
		if is_node_ready():
			rebuild()

## Single uniform scale factor for the mesh. No independent X/Y/Z stretching.
@export var absolute_scale: float = 1.0:
	set(v):
		absolute_scale = v
		if is_node_ready():
			rebuild()

@export var mesh_rotation_degrees: Vector3 = Vector3.ZERO:
	set(v):
		mesh_rotation_degrees = v
		if is_node_ready():
			rebuild()

@export var create_collision: bool = true:
	set(v):
		create_collision = v
		if is_node_ready():
			rebuild()


var actual_size: Vector3 = Vector3.ZERO

var _current_data: Dictionary = {}


func _ready() -> void:
	rebuild()


func rebuild() -> void:
	# Clear existing generated nodes
	# We also need to clear shapes from the parent if it's a RigidBody
	var parent = get_parent()
	if parent is RigidBody3D:
		for child in parent.get_children():
			if child.name.begins_with("Generated_"):
				parent.remove_child(child)
				child.free()

	for child in get_children():
		remove_child(child)
		child.free()
	
	if mesh_data_path.is_empty():
		return

	_current_data = _load_json(mesh_data_path)
	if _current_data.is_empty():
		return

	var params := _get_normalization_params(_current_data["vertices"])
	
	_build_mesh(params)
	if create_collision:
		_build_collision(params)


func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	
	var file := FileAccess.open(path, FileAccess.READ)
	var json_string := file.get_as_text()
	file.close()
	
	var json := JSON.new()
	var error := json.parse(json_string)
	if error != OK:
		push_error("MeshTransformer: JSON Parse Error in " + path)
		return {}
	
	var data = json.get_data()
	if typeof(data) != TYPE_DICTIONARY:
		return {}
		
	return data


func _get_normalization_params(vertices: Array) -> Dictionary:
	var min_v := Vector3(INF, INF, INF)
	var max_v := Vector3(-INF, -INF, -INF)

	for i in range(0, vertices.size(), 3):
		var v := Vector3(vertices[i], vertices[i+1], vertices[i+2])
		min_v.x = minf(min_v.x, v.x)
		min_v.y = minf(min_v.y, v.y)
		min_v.z = minf(min_v.z, v.z)
		max_v.x = maxf(max_v.x, v.x)
		max_v.y = maxf(max_v.y, v.y)
		max_v.z = maxf(max_v.z, v.z)

	var native_size := max_v - min_v
	var center := (max_v + min_v) * 0.5

	var scale_vec := Vector3(absolute_scale, absolute_scale, absolute_scale)
	actual_size = native_size * absolute_scale

	return {
		"scale": scale_vec,
		"offset": -center,
	}


func _build_mesh(params: Dictionary) -> void:
	if not _current_data.has("vertices") or not _current_data.has("indices"):
		return

	var vertices: Array = _current_data["vertices"].duplicate()
	var offset: Vector3 = params["offset"]
	for i in range(0, vertices.size(), 3):
		vertices[i] += offset.x
		vertices[i+1] += offset.y
		vertices[i+2] += offset.z

	var mi := MeshBuilder.from_data(
		vertices, 
		_current_data["indices"], 
		mesh_color, 
		0.8, 
		0.1
	)
	
	mi.scale = params["scale"]
	mi.rotation_degrees = mesh_rotation_degrees
	mi.name = "Generated_Mesh"
	add_child(mi)
	if Engine.is_editor_hint():
		mi.owner = get_tree().edited_scene_root


func _build_collision(params: Dictionary) -> void:
	if not _current_data.has("vertices") or not _current_data.has("indices"):
		return

	var vertices: Array = _current_data["vertices"]
	var s: Vector3 = params["scale"]
	var offset: Vector3 = params["offset"]

	var col := CollisionShape3D.new()
	col.name = "Generated_MeshCollider"
	
	# Godot (and Jolt) silently disable ConcavePolygonShape3D on dynamic RigidBodies,
	# which is why you fall straight through. Dynamic bodies MUST use Convex shapes.
	# Since your new JSON is a "flat deck" hull, a Convex hull will wrap it perfectly
	# without creating the "invisible ground" issue you had with the old recessed-hold ship.
	var shape := ConvexPolygonShape3D.new()
	var points: Array[Vector3] = []
	
	for i in range(0, vertices.size(), 3):
		points.append(Vector3(
			(vertices[i] + offset.x) * s.x, 
			(vertices[i+1] + offset.y) * s.y, 
			(vertices[i+2] + offset.z) * s.z
		))
	
	shape.points = points
	col.shape = shape
	col.rotation_degrees = mesh_rotation_degrees
	
	# CRITICAL: CollisionShape3D MUST be a direct child of the RigidBody3D
	var parent = get_parent()
	if parent is RigidBody3D:
		parent.add_child(col)
		if Engine.is_editor_hint():
			col.owner = get_tree().edited_scene_root
	else:
		add_child(col)
		if Engine.is_editor_hint():
			col.owner = get_tree().edited_scene_root
