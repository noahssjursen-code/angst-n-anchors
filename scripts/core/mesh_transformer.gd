@tool
class_name MeshTransformer
extends Node3D

## Component that takes a mesh JSON and transforms it into a 3D model with collision.
## Handles normalization, scaling, and runtime construction.

@export_file("*.json") var mesh_data_path: String:
	set(v):
		if mesh_data_path == v:
			return
		mesh_data_path = v
		if is_node_ready():
			rebuild()

var mesh_data: Dictionary = {}:
	set(v):
		mesh_data = v.duplicate(true)
		if is_node_ready():
			rebuild()

@export var mesh_color: Color = Color(0.5, 0.5, 0.5):
	set(v):
		if mesh_color == v:
			return
		mesh_color = v
		if is_node_ready():
			rebuild()

@export var mesh_roughness: float = 0.96:
	set(v):
		if is_equal_approx(mesh_roughness, v):
			return
		mesh_roughness = v
		if is_node_ready():
			rebuild()

@export var mesh_metallic: float = 0.0:
	set(v):
		if is_equal_approx(mesh_metallic, v):
			return
		mesh_metallic = v
		if is_node_ready():
			rebuild()

## Single uniform scale factor for the mesh. No independent X/Y/Z stretching.
@export var absolute_scale: float = 1.0:
	set(v):
		if is_equal_approx(absolute_scale, v):
			return
		absolute_scale = v
		if is_node_ready():
			rebuild()

@export var mesh_rotation_degrees: Vector3 = Vector3.ZERO:
	set(v):
		if mesh_rotation_degrees == v:
			return
		mesh_rotation_degrees = v
		if is_node_ready():
			rebuild()

@export var create_collision: bool = true:
	set(v):
		if create_collision == v:
			return
		create_collision = v
		if is_node_ready():
			rebuild()

## `convex` — hull of all vertices (wrong for hollow shells). `concave` — triangle
## mesh; only use on **static** bodies (see Jolt / Godot notes on dynamic + concave).
## Concave builds default to **double-sided** triangles unless `collision_double_sided` is off.
var collision_mode: String = "convex"

## For concave collisions: duplicate each triangle with opposite winding so thin shells
## block movement from either side (Jolt trimesh is effectively one-sided per triangle).
var collision_double_sided: bool = true

## Optional target for generated CollisionShape3D nodes. Use this when the
## transformer is nested under a generic assembler but colliders must be direct
## children of a PhysicsBody3D/Area3D.
@export var collision_parent_path: NodePath:
	set(v):
		if collision_parent_path == v:
			return
		collision_parent_path = v
		if is_node_ready():
			rebuild()

## Standalone meshes are centered by default. Multi-part assemblies should disable
## this so all parts keep their shared authored coordinate space.
@export var center_mesh: bool = true:
	set(v):
		if center_mesh == v:
			return
		center_mesh = v
		if is_node_ready():
			rebuild()

## When true, collision triangles swap v1/v2 relative to authored indices (concave /
## walk proxies). Mostly redundant when `collision_double_sided` is true.
@export var invert_collision_face_winding: bool = false:
	set(v):
		if invert_collision_face_winding == v:
			return
		invert_collision_face_winding = v


var actual_size: Vector3 = Vector3.ZERO
var actual_center: Vector3 = Vector3.ZERO
var actual_min: Vector3 = Vector3.ZERO
var actual_max: Vector3 = Vector3.ZERO
var rebuild_suspended: bool = false

var _current_data: Dictionary = {}


func _ready() -> void:
	rebuild()


func rebuild() -> void:
	if rebuild_suspended:
		return

	# Clear existing generated nodes
	# We also need to clear shapes from the collision target, if any.
	var collision_parent := _get_collision_parent()
	if collision_parent != null:
		for child in collision_parent.get_children():
			var is_legacy_collider := child.name == "Generated_MeshCollider"
			if child.name.begins_with(_generated_prefix()) or is_legacy_collider:
				collision_parent.remove_child(child)
				child.free()

	for child in get_children():
		remove_child(child)
		child.free()
	
	if not mesh_data.is_empty():
		_current_data = mesh_data.duplicate(true)
	elif not mesh_data_path.is_empty():
		_current_data = _load_json(mesh_data_path)
	else:
		return

	if _current_data.is_empty():
		push_error("MeshTransformer: current_data is empty for path: " + mesh_data_path)
		return
	if not _current_data.has("vertices") or not _current_data.has("indices"):
		push_error("MeshTransformer: mesh data must contain `vertices` and `indices` (path: " + mesh_data_path + ", keys: " + str(_current_data.keys()) + ")")
		return

	var params := _get_normalization_params(_current_data["vertices"])
	
	_build_mesh(params)
	if create_collision:
		if collision_mode == "concave":
			_build_collision_concave(params)
		else:
			_build_collision_convex(params)


func get_collision_points_in(target: Node3D) -> Array[Vector3]:
	if target == null:
		return []
	if not _ensure_current_data():
		return []

	var params := _get_normalization_params(_current_data["vertices"])
	var vertices: Array = _current_data["vertices"]
	var points: Array[Vector3] = []
	var rotation_basis := Basis.from_euler(Vector3(
		deg_to_rad(mesh_rotation_degrees.x),
		deg_to_rad(mesh_rotation_degrees.y),
		deg_to_rad(mesh_rotation_degrees.z)
	))
	var scale_vec: Vector3 = params["scale"]
	var offset: Vector3 = params["offset"]

	for i in range(0, vertices.size(), 3):
		var local := Vector3(vertices[i], vertices[i + 1], vertices[i + 2])
		local = rotation_basis * ((local + offset) * scale_vec)
		points.append(target.to_local(to_global(local)))

	return points


func get_collision_faces_in(target: Node3D) -> Array[Vector3]:
	if target == null:
		return []
	if not _ensure_current_data():
		return []

	var params := _get_normalization_params(_current_data["vertices"])
	var vertices: Array = _current_data["vertices"]
	var indices: Array = _current_data["indices"]
	var faces: Array[Vector3] = []
	var rotation_basis := Basis.from_euler(Vector3(
		deg_to_rad(mesh_rotation_degrees.x),
		deg_to_rad(mesh_rotation_degrees.y),
		deg_to_rad(mesh_rotation_degrees.z)
	))
	var scale_vec: Vector3 = params["scale"]
	var offset: Vector3 = params["offset"]

	for i in range(0, indices.size(), 3):
		var triangle := [0, 1, 2]
		if invert_collision_face_winding:
			triangle = [0, 2, 1]
		for j in triangle:
			var vertex_index := int(indices[i + j]) * 3
			if vertex_index + 2 >= vertices.size():
				continue
			var local := Vector3(
				vertices[vertex_index],
				vertices[vertex_index + 1],
				vertices[vertex_index + 2]
			)
			local = rotation_basis * ((local + offset) * scale_vec)
			faces.append(target.to_local(to_global(local)))

	return faces


func _ensure_current_data() -> bool:
	if _current_data.has("vertices") and _current_data.has("indices"):
		return true
	if not mesh_data.is_empty():
		_current_data = mesh_data.duplicate(true)
	elif not mesh_data_path.is_empty():
		_current_data = _load_json(mesh_data_path)
	else:
		return false
	return _current_data.has("vertices") and _current_data.has("indices")


## Thin wrapper around JsonUtil.load() — kept as an instance method so existing
## callers (line 144, 233) work unchanged.
func _load_json(path: String) -> Dictionary:
	return JsonUtil.load(path)


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

	var center := (max_v + min_v) * 0.5

	var scale_vec := Vector3(absolute_scale, absolute_scale, absolute_scale)
	var offset := -center if center_mesh else Vector3.ZERO
	_update_actual_bounds(vertices, offset, scale_vec)

	return {
		"scale": scale_vec,
		"offset": offset,
	}


func _update_actual_bounds(vertices: Array, offset: Vector3, scale_vec: Vector3) -> void:
	var min_v := Vector3(INF, INF, INF)
	var max_v := Vector3(-INF, -INF, -INF)
	var rotation_basis := Basis.from_euler(Vector3(
		deg_to_rad(mesh_rotation_degrees.x),
		deg_to_rad(mesh_rotation_degrees.y),
		deg_to_rad(mesh_rotation_degrees.z)
	))

	for i in range(0, vertices.size(), 3):
		var local := Vector3(vertices[i], vertices[i + 1], vertices[i + 2])
		local = rotation_basis * ((local + offset) * scale_vec)
		min_v.x = minf(min_v.x, local.x)
		min_v.y = minf(min_v.y, local.y)
		min_v.z = minf(min_v.z, local.z)
		max_v.x = maxf(max_v.x, local.x)
		max_v.y = maxf(max_v.y, local.y)
		max_v.z = maxf(max_v.z, local.z)

	actual_min = min_v
	actual_max = max_v
	actual_size = max_v - min_v
	actual_center = (max_v + min_v) * 0.5


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
		mesh_roughness, 
		mesh_metallic
	)
	
	mi.scale = params["scale"]
	mi.rotation_degrees = mesh_rotation_degrees
	mi.name = _generated_prefix() + "Mesh"
	add_child(mi)
	if Engine.is_editor_hint() and get_tree() != null:
		mi.owner = get_tree().edited_scene_root


func _collision_col_child() -> CollisionShape3D:
	var col := CollisionShape3D.new()
	col.name = _generated_prefix() + "Collider"
	col.rotation_degrees = mesh_rotation_degrees
	var collision_parent := _get_collision_parent()
	if collision_parent != null:
		collision_parent.add_child(col)
		col.global_position = global_position
		if Engine.is_editor_hint() and get_tree() != null:
			col.owner = get_tree().edited_scene_root
	else:
		add_child(col)
		if Engine.is_editor_hint() and get_tree() != null:
			col.owner = get_tree().edited_scene_root
	return col


func _build_collision_convex(params: Dictionary) -> void:
	if not _current_data.has("vertices") or not _current_data.has("indices"):
		return

	var vertices: Array = _current_data["vertices"]
	var s: Vector3 = params["scale"]
	var offset: Vector3 = params["offset"]

	var col := _collision_col_child()

	# Godot (and Jolt) silently disable ConcavePolygonShape3D on dynamic RigidBodies,
	# which is why you fall straight through. Dynamic bodies MUST use Convex shapes.
	var shape := ConvexPolygonShape3D.new()
	var points: Array[Vector3] = []

	for i in range(0, vertices.size(), 3):
		points.append(Vector3(
			(vertices[i] + offset.x) * s.x,
			(vertices[i + 1] + offset.y) * s.y,
			(vertices[i + 2] + offset.z) * s.z
		))

	shape.points = points
	col.shape = shape


func _build_collision_concave(params: Dictionary) -> void:
	if not _current_data.has("vertices") or not _current_data.has("indices"):
		return

	var vertices: Array = _current_data["vertices"]
	var indices: Array = _current_data["indices"]
	var s: Vector3 = params["scale"]
	var offset: Vector3 = params["offset"]

	var faces: Array[Vector3] = []
	for ii in range(0, indices.size(), 3):
		var triangle := [0, 1, 2]
		if invert_collision_face_winding:
			triangle = [0, 2, 1]
		var okay := true
		var triple: Array[Vector3] = []
		for ti in triangle:
			var vertex_index := int(indices[ii + ti]) * 3
			if vertex_index + 2 >= vertices.size():
				okay = false
				break
			triple.append(Vector3(
				(vertices[vertex_index] + offset.x) * s.x,
				(vertices[vertex_index + 1] + offset.y) * s.y,
				(vertices[vertex_index + 2] + offset.z) * s.z
			))
		if okay and triple.size() == 3:
			faces.append_array(triple)
			if collision_double_sided:
				faces.push_back(triple[0])
				faces.push_back(triple[2])
				faces.push_back(triple[1])

	if faces.size() < 9:
		push_warning(
			"MeshTransformer: concave collision fallback to convex (%s triangles)" %
			str(name)
		)
		_build_collision_convex(params)
		return

	var col := _collision_col_child()
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	col.shape = shape


func _get_collision_parent() -> CollisionObject3D:
	if not collision_parent_path.is_empty():
		return get_node_or_null(collision_parent_path) as CollisionObject3D
	return get_parent() as CollisionObject3D


func _generated_prefix() -> String:
	return "Generated_" + name.replace(" ", "_").replace("@", "_").replace(":", "_") + "_"
