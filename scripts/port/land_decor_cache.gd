class_name LandDecorCache
extends RefCounted

## Pre-baked village house prototypes (merged mesh per material) for port land decor.

const VARIANT_COUNT := 8

static var _house_prototypes: Array[Node3D] = []
static var _initialized := false


static func clear() -> void:
	for proto in _house_prototypes:
		if proto != null and is_instance_valid(proto):
			proto.free()
	_house_prototypes.clear()
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


static func _bake_house(variant: int) -> Node3D:
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

	var root := Node3D.new()
	root.name = "HousePrototype"
	var bucket_index := 0
	for bucket in by_material.values():
		var mi := MeshInstance3D.new()
		## Named because the stamp now COPIES the name (`VisualFlatten.copy_visual`
		## does, this file's old `_stamp` did not). Left unnamed, the prototype's
		## auto-generated `@MeshInstance3D@17` was copied into every stamp and
		## sanitised by `Node.set_name` — `@` is not a legal name character — so
		## every house drew five children called `_MeshInstance3D_17`. Nothing reads
		## these names, but a debugger and a remote-scene tree do.
		mi.name = "HouseSurface_%d" % bucket_index
		bucket_index += 1
		mi.mesh = _merge_parts(bucket["parts"] as Array)
		mi.material_override = bucket["mat"]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	return root


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


## `VisualFlatten.stamp` — the one implementation the three prototype caches in
## this project share (REALITY.md §3b). This file used to carry its own
## mesh-only copy of it, the same pair that cost `BuildingCache` a `Label3D`,
## eight `OmniLight3D`, a metadata key and 72 of 717 meshes.
##
## **Measured before the port, and this cache lost NOTHING** — prototype census
## against stamped census, per class, all eight variants
## (`tests/_cache_survey.gd`): 5 `MeshInstance3D` in, 5 out, zero visuals nested
## under a visual. Nor could it have: `_bake_house`, in this same file, builds a
## flat row of `MeshInstance3D` by merging five primitives (four boxes and a
## prism) into one mesh per material. There is no producer under this that can
## change shape without changing this file.
##
## The port is therefore a merge, not a repair — and unlike buildings it is NOT
## free, because this stamps far more instances than a port has buildings:
## `PortLayoutGraphVisualizer` places a house per village cell and
## `ImpostorWarmup` bakes all eight variants at boot. Measured against a
## `git archive HEAD` baseline, same box, best of 3 × 500 stamps
## (`tests/_stamp_cost_probe.gd`):
##
##     LandDecorCache.house_instance   0.0358 -> 0.0435 ms/stamp   (+21.5%)
##     nodes per stamp                 5 -> 5                      (unchanged)
##
## +0.0077 ms per house. Attributed rather than guessed (REALITY.md §3g): with
## `copy_metadata` removed it measures 0.0408, so ~35% of the increase is one
## `get_meta_list()` call per mesh on nodes that carry no metadata, and the rest
## is the two extra field assignments (`gi_mode`, `name`) and the call through a
## shared static. Nothing here is a per-frame cost — a house is stamped once when
## its cell loads — so the trade taken is +0.008 ms per house for deleting a
## second copy of an algorithm that was measured wrong in the first.
static func _stamp(prototype: Node3D) -> Node3D:
	return VisualFlatten.stamp(prototype)
