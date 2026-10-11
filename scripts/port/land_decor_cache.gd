class_name LandDecorCache
extends RefCounted

## Pre-baked village house prototypes (merged mesh per material) for port land decor.

const VARIANT_COUNT := 8

# Resource-only descriptors: off-tree Nodes are not reference-counted and leak
# their rendering instances when a static cache outlives the world.
static var _house_prototypes: Array[Array] = []
static var _initialized := false
static var _distance_meshes: Dictionary = {}


static func clear() -> void:
	_house_prototypes.clear()
	_distance_meshes.clear()
	_initialized = false


static func house_instance(index: int, u: float, v: float) -> Node3D:
	_ensure_baked()
	var variant := variant_index(index, u, v)
	return _stamp(_house_prototypes[variant])


static func variant_index(index: int, u: float, v: float) -> int:
	return int(index + int(u * 4.0) + int(v * 4.0)) % VARIANT_COUNT


static func _ensure_baked() -> void:
	if _initialized:
		return
	_initialized = true
	for variant in range(VARIANT_COUNT):
		_house_prototypes.append(_bake_house(variant))


static func _mesh_from_primitive(primitive: PrimitiveMesh) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.create_from(primitive, 0)
	return st.commit()


static func _bake_house(variant: int) -> Array[Dictionary]:
	var tint := fmod(float(variant) * 0.17 + float(variant) * 0.11, 1.0)
	var wall := Color(0.72, 0.28, 0.22).lerp(Color(0.55, 0.42, 0.32), tint)
	var roof_col := Color(0.28, 0.22, 0.20).lerp(Color(0.38, 0.18, 0.14), 1.0 - tint)
	var w := lerpf(7.2, 9.0, fmod(tint * 3.1, 1.0))
	var d := lerpf(6.0, 7.6, fmod(tint * 5.7, 1.0))
	var wall_h := lerpf(3.4, 4.2, fmod(tint * 2.3, 1.0))
	var roof_h := lerpf(2.2, 2.8, fmod(tint * 4.1, 1.0))

	var parts: Array[Dictionary] = [
		{"mesh": _mesh_from_primitive(_box_mesh(Vector3(w, wall_h, d))), "mat": MeshBuilder.make_material(wall, 0.92), "xform": Transform3D(Basis.IDENTITY, Vector3(0.0, wall_h * 0.5, 0.0))},
		{"mesh": _mesh_from_primitive(_prism_mesh(Vector3(w * 1.08, roof_h, d * 1.04))), "mat": MeshBuilder.make_material(roof_col, 0.88), "xform": Transform3D(Basis.IDENTITY, Vector3(0.0, wall_h + roof_h * 0.5, 0.0))},
		{"mesh": _mesh_from_primitive(_box_mesh(Vector3(w * 0.22, wall_h * 0.55, 0.35))), "mat": MeshBuilder.make_material(Color(0.22, 0.16, 0.12), 0.9, 0.05), "xform": Transform3D(Basis.IDENTITY, Vector3(0.0, wall_h * 0.28, d * 0.5))},
		{"mesh": _mesh_from_primitive(_box_mesh(Vector3(w * 0.18, wall_h * 0.28, 0.25))), "mat": MeshBuilder.make_material(Color(0.55, 0.72, 0.82), 0.35, 0.1), "xform": Transform3D(Basis.IDENTITY, Vector3(w * 0.28, wall_h * 0.55, d * 0.5))},
		{"mesh": _mesh_from_primitive(_box_mesh(Vector3(0.7, roof_h * 0.85, 0.7))), "mat": MeshBuilder.make_material(Color(0.35, 0.28, 0.26), 0.95), "xform": Transform3D(Basis.IDENTITY, Vector3(-w * 0.28, wall_h + roof_h * 0.55, -d * 0.15))},
	]

	var by_material: Dictionary = {}
	for part in parts:
		var mat: Material = part["mat"]
		var key := str(mat.get_instance_id())
		if not by_material.has(key):
			by_material[key] = {"mat": mat, "parts": [] as Array}
		(by_material[key]["parts"] as Array).append(part)

	var meshes: Array[Dictionary] = []
	for bucket in by_material.values():
		meshes.append({"mesh": _merge_parts(bucket["parts"] as Array), "material": bucket["mat"]})
	return meshes


static func _merge_parts(parts: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for part in parts:
		var mesh: Mesh = part["mesh"]
		var xform: Transform3D = part["xform"]
		var arrays := mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if indices.is_empty():
			for i in range(0, verts.size(), 3):
				st.add_vertex(xform * verts[i])
				st.add_vertex(xform * verts[i + 1])
				st.add_vertex(xform * verts[i + 2])
		else:
			for idx in indices:
				st.add_vertex(xform * verts[idx])
	st.generate_normals()
	return st.commit()


static func _box_mesh(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh


static func _prism_mesh(size: Vector3) -> PrismMesh:
	var mesh := PrismMesh.new()
	mesh.size = size
	return mesh


static func _stamp(prototype: Array) -> Node3D:
	var root := Node3D.new()
	for part: Dictionary in prototype:
		var mi := MeshInstance3D.new()
		mi.mesh = part["mesh"]
		mi.material_override = part["material"]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	return root


## Preserve the existing pitched roof/chimney silhouette in one shared draw.
## This is a presentation reduction of the existing house, not new geometry.
static func house_distance_mesh(variant: int) -> ArrayMesh:
	_ensure_baked()
	variant=posmod(variant,VARIANT_COUNT)
	if _distance_meshes.has(variant): return _distance_meshes[variant]
	var surface:=SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for part:Dictionary in _house_prototypes[variant]:
		var mesh:Mesh=part.mesh
		var material:StandardMaterial3D=part.material
		var arrays:=mesh.surface_get_arrays(0)
		var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var normals:PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
		for i in vertices.size():
			surface.set_color(material.albedo_color)
			surface.set_normal(normals[i])
			surface.add_vertex(vertices[i])
	var result:=surface.commit()
	var paint:=StandardMaterial3D.new()
	paint.vertex_color_use_as_albedo=true
	paint.vertex_color_is_srgb=true
	paint.roughness=.95
	result.surface_set_material(0,paint)
	_distance_meshes[variant]=result
	return result
