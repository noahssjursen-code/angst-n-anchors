extends Node3D

## Distant presentation of the actual commissioned build. Authority, collision,
## cargo and attachment nodes remain live; only render instances are substituted.
const FAR_M := 500.0
const NEAR_M := 400.0
const MIN_DETAIL_M := 0.8
var distant := false
var source_surfaces := 0
var proxy_surfaces := 0
var _sources: Array[MeshInstance3D] = []
var _proxy: MeshInstance3D
var _signature := ""
var _building := false
var _generation := 0

func refresh(distance_m: float, force_near: bool = false) -> void:
	if force_near or distance_m < NEAR_M:
		if _building:
			_generation += 1
			_building = false
			_signature = ""
		_restore()
		return
	if _building: return
	if not distant and distance_m <= FAR_M: return
	var sources: Array[MeshInstance3D] = []
	var ids: Array[int] = []
	for raw in get_parent().find_children("*", "MeshInstance3D", true, false):
		var mesh := raw as MeshInstance3D
		if is_ancestor_of(mesh) or mesh.mesh == null: continue
		# visibility ranges leave the logical visibility untouched, including
		# doors, lights and newly arriving manifest cargo while in the far band.
		if not mesh.is_visible_in_tree(): continue
		sources.append(mesh)
		ids.append(mesh.get_instance_id())
	var signature := str(ids) + str(get_parent().get_meta("layout_hash", ""))
	if signature != _signature:
		_restore()
		_building = true
		_generation += 1
		var generation := _generation
		await _build(sources, generation)
		if generation != _generation: return
		_building = false
		_signature = signature
	if _proxy == null: return
	_sources = sources
	for mesh in _sources:
		if not is_instance_valid(mesh): continue
		if not mesh.has_meta("remote_lod_range"):
			mesh.set_meta("remote_lod_range", [mesh.visibility_range_begin, mesh.visibility_range_end])
		# A tiny positive range suppresses rendering, without hiding new children
		# or altering visibility owned by equipment / cargo presentation.
		mesh.visibility_range_begin = 0.0
		mesh.visibility_range_end = 0.01
	_proxy.visible = true
	distant = true

func _restore() -> void:
	for mesh in _sources:
		if not is_instance_valid(mesh) or not mesh.has_meta("remote_lod_range"): continue
		var saved: Array = mesh.get_meta("remote_lod_range")
		mesh.visibility_range_begin = float(saved[0])
		mesh.visibility_range_end = float(saved[1])
		mesh.remove_meta("remote_lod_range")
	if is_instance_valid(_proxy): _proxy.visible = false
	distant = false

func _build(sources: Array[MeshInstance3D], generation: int) -> void:
	if is_instance_valid(_proxy): _proxy.free()
	_proxy = null
	var groups: Dictionary = {}
	var deadline := Time.get_ticks_usec() + 2000
	source_surfaces = 0
	for source in sources:
		if Time.get_ticks_usec() >= deadline:
			await get_tree().process_frame
			if generation != _generation: return
			deadline = Time.get_ticks_usec() + 2000
		if not is_instance_valid(source): continue
		source_surfaces += source.mesh.get_surface_count()
		if not source.mesh is ArrayMesh and not source.mesh is PrimitiveMesh: continue
		if source.skin != null or source.get_meta("walk_detail_visual", false): continue
		var transform := global_transform.affine_inverse() * source.global_transform
		var extent := (transform * source.get_aabb()).size
		# Omit small fittings/interior machinery, retain the authored hull,
		# cabin, rails and cargo silhouettes. No generic replacement hull.
		if maxf(extent.x, maxf(extent.y, extent.z)) < MIN_DETAIL_M: continue
		for surface in source.mesh.get_surface_count():
			if source.mesh is ArrayMesh and source.mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES: continue
			var material := source.get_active_material(surface)
			var key := _material_key(material)
			if not groups.has(key):
				var tool := SurfaceTool.new()
				tool.begin(Mesh.PRIMITIVE_TRIANGLES)
				tool.set_material(material)
				groups[key] = tool
			(groups[key] as SurfaceTool).append_from(source.mesh, surface, transform)
	var combined := ArrayMesh.new()
	for tool: SurfaceTool in groups.values():
		tool.commit(combined)
		if Time.get_ticks_usec() >= deadline:
			await get_tree().process_frame
			if generation != _generation: return
			deadline = Time.get_ticks_usec() + 2000
	proxy_surfaces = combined.get_surface_count()
	if proxy_surfaces == 0: return
	_proxy = MeshInstance3D.new()
	_proxy.name = "DistantConstruction"
	_proxy.mesh = combined
	_proxy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_proxy)

static func _material_key(material: Material) -> String:
	if material == null: return "none"
	if not material is StandardMaterial3D: return str(material.get_instance_id())
	# Painted modular parts duplicate materials. Merge equivalent finishes while
	# retaining every stored optical/texture property, not just diffuse colour.
	var values: Array = []
	for property in material.get_property_list():
		var key := str(property.name)
		if int(property.usage) & PROPERTY_USAGE_STORAGE == 0 or key.begins_with("resource_"): continue
		var value: Variant = material.get(key)
		values.append(value.get_instance_id() if value is Resource else value)
	return str(values)
