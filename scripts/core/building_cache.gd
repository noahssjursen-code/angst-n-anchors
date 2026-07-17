class_name BuildingCache
extends RefCounted

## Bakes voxel blueprint visuals once and stamps shared-mesh copies.
## Collision is a single box per instance derived from the layout grid bounds.

static var _visual_prototypes: Dictionary = {}  ## blueprint_id -> Node3D
static var _footprint_cache: Dictionary = {}  ## blueprint_id -> {size, center}


static func clear() -> void:
	for key in _visual_prototypes.keys():
		var proto: Node3D = _visual_prototypes[key] as Node3D
		if proto != null and is_instance_valid(proto):
			proto.free()
	_visual_prototypes.clear()
	_footprint_cache.clear()


static func instance(
		layout: BuildingLayout,
		collision_enabled: bool = true,
) -> Node3D:
	if layout == null:
		return Node3D.new()
	var blueprint_id := layout.blueprint_id.strip_edges()
	if blueprint_id.is_empty():
		return BuildingFitout.build(layout, collision_enabled)

	var root := Node3D.new()
	root.name = BuildingFitout.ROOT_NAME
	root.set_meta("building_blueprint_id", blueprint_id)

	var visual := _stamp_visual(blueprint_id, layout)
	visual.name = "Visual"
	root.add_child(visual)

	var lighting := BuildingLighting.new()
	lighting.name = "BuildingLighting"
	root.add_child(lighting)

	if collision_enabled:
		var body := StaticBody3D.new()
		body.name = "Collision"
		root.add_child(body)
		_add_footprint_collision(body, blueprint_id, layout)

	return root


static func _stamp_visual(blueprint_id: String, layout: BuildingLayout) -> Node3D:
	if not _visual_prototypes.has(blueprint_id):
		_bake_prototype(blueprint_id, layout)
	var proto: Node3D = _visual_prototypes[blueprint_id] as Node3D
	return _stamp_node(proto)


static func _bake_prototype(blueprint_id: String, layout: BuildingLayout) -> void:
	var baked := BuildingFitout.build(layout, false)
	var root := Node3D.new()
	root.name = "BuildingPrototype"
	_flatten_visuals(baked, root, Transform3D.IDENTITY)
	baked.free()
	_visual_prototypes[blueprint_id] = root
	_footprint_cache[blueprint_id] = _measure_footprint(layout)


static func _flatten_visuals(src: Node, dst_root: Node3D, parent_xform: Transform3D) -> void:
	for child in src.get_children():
		if child.name == "BuildingLighting":
			continue
		if not (child is Node3D):
			continue
		var node_3d := child as Node3D
		var xform := parent_xform * node_3d.transform
		if child is MeshInstance3D:
			var src_mi := child as MeshInstance3D
			var mi := MeshInstance3D.new()
			mi.name = src_mi.name
			mi.mesh = src_mi.mesh
			mi.material_override = src_mi.material_override
			mi.cast_shadow = src_mi.cast_shadow
			mi.gi_mode = src_mi.gi_mode
			mi.transform = xform
			dst_root.add_child(mi)
		else:
			_flatten_visuals(child, dst_root, xform)


static func _stamp_node(prototype: Node3D) -> Node3D:
	var root := Node3D.new()
	for child in prototype.get_children():
		if child is MeshInstance3D:
			var src := child as MeshInstance3D
			var mi := MeshInstance3D.new()
			mi.name = src.name
			mi.mesh = src.mesh
			mi.material_override = src.material_override
			mi.cast_shadow = src.cast_shadow
			mi.gi_mode = src.gi_mode
			mi.transform = src.transform
			root.add_child(mi)
	return root


static func _measure_footprint(layout: BuildingLayout) -> Dictionary:
	var grid := layout.grid()
	var min_cell := Vector3i(999999, 999999, 999999)
	var max_cell := Vector3i(-999999, -999999, -999999)
	var found := false
	for item in layout.iter_primary_cells():
		if BuildingLayout.entry_is_surface_only(item):
			continue
		found = true
		var cell := item["cell"] as Vector3i
		min_cell = Vector3i(mini(min_cell.x, cell.x), mini(min_cell.y, cell.y), mini(min_cell.z, cell.z))
		max_cell = Vector3i(maxi(max_cell.x, cell.x), maxi(max_cell.y, cell.y), maxi(max_cell.z, cell.z))
	if not found:
		return {"size": Vector3(8.0, 6.0, 8.0), "center": Vector3.ZERO}
	var min_p := grid.cell_center_local(min_cell)
	var max_p := grid.cell_center_local(max_cell)
	var size := max_p - min_p + Vector3.ONE
	return {"size": size, "center": (min_p + max_p) * 0.5}


static func _add_footprint_collision(body: StaticBody3D, blueprint_id: String, layout: BuildingLayout) -> void:
	if not _footprint_cache.has(blueprint_id):
		_footprint_cache[blueprint_id] = _measure_footprint(layout)
	var fp: Dictionary = _footprint_cache[blueprint_id]
	var size: Vector3 = fp.get("size", Vector3(8.0, 6.0, 8.0))
	var center: Vector3 = fp.get("center", Vector3.ZERO)
	var col := CollisionShape3D.new()
	col.name = "Footprint"
	var shape := BoxShape3D.new()
	shape.size = Vector3(maxf(size.x, 1.0), maxf(size.y, 2.5), maxf(size.z, 1.0))
	col.shape = shape
	col.position = center + Vector3(0.0, shape.size.y * 0.5 - 0.5, 0.0)
	body.add_child(col)
