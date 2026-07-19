extends SceneTree

## Headless regression for the high-volume NPC presentation path.

var _failed := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var general := _prebuilt("28_10_m", "proxy-general")
	var bulk := _prebuilt("bulk_small", "proxy-bulk")
	_assert(not general.is_empty(), "general prebuilt is available")
	_assert(not bulk.is_empty(), "bulk prebuilt is available")
	var general_mesh := VesselProxyRenderer.shared_visual_mesh(general)
	var same_mesh := VesselProxyRenderer.shared_visual_mesh(general)
	var bulk_mesh := VesselProxyRenderer.shared_visual_mesh(bulk)
	_assert(general_mesh != null, "general proxy mesh builds")
	_assert(bulk_mesh != null, "bulk proxy mesh builds")
	_assert(general_mesh == same_mesh, "identical layouts reuse one mesh resource")
	_assert(general_mesh.get_surface_count() <= 8, "proxy surface budget is bounded")
	_assert(bulk_mesh.get_surface_count() <= 8, "bulk proxy surface budget is bounded")
	_assert(_mesh_vertex_count(general_mesh) > 1000,
		"proxy preserves authored brick geometry instead of box placeholders")

	var renderer := VesselProxyRenderer.new()
	root.add_child(renderer)
	var wanted: Dictionary = {}
	for index in range(50):
		var uid := "proxy-%02d" % index
		wanted[uid] = true
		var vessel := general if index % 2 == 0 else bulk
		renderer.set_projection(uid, vessel, {}, {
			"position": Vector3(float(index % 10) * 35.0, 0.0, float(index / 10) * 45.0),
			"heading_xz": Vector2(0.0, -1.0),
		})
	renderer.retain_only(wanted)
	await process_frame
	await process_frame
	var stats := renderer.get_debug_stats()
	_assert(int(stats.get("visual_proxies", 0)) == 50, "fifty proxy poses are retained")
	_assert(int(stats.get("proxy_batches", 99)) == 2, "fifty ships collapse to two shared batches")
	_assert(int(stats.get("proxy_transform_writes", 0)) == 50, "each pose updates exactly once")
	var retained_half: Dictionary = {}
	for index in range(25):
		retained_half["proxy-%02d" % index] = true
	renderer.retain_only(retained_half)
	await process_frame
	_assert(renderer.proxy_count() == 25, "interest demotion releases stale proxy poses")
	renderer.clear()
	await process_frame
	_assert(renderer.proxy_count() == 0, "scene transition cleanup releases every proxy")
	if _failed:
		quit(1)
	else:
		print("VesselProxyRendererTest: PASS")
		quit(0)


func _prebuilt(prebuilt_id: String, uid: String) -> Dictionary:
	for entry in PrebuiltVesselCatalog.catalog_entries(false):
		if str(entry.get("prebuilt_id", "")) != prebuilt_id:
			continue
		return VesselSpawn.normalize_record({
			"uid": uid,
			"hull_id": entry.get("hull_id", "hull_28x10"),
			"name": entry.get("prebuilt_name", "Test Vessel"),
			"shaft_power_kw": entry.get("shaft_power_kw", 1871.0),
			"registration_id": entry.get("registration_id", "cargo_vessel"),
			"proxy_visual_id": prebuilt_id,
			"brick_layout": entry.get("prebuilt_layout", {}) as Dictionary,
		})
	return {}


func _mesh_vertex_count(mesh: ArrayMesh) -> int:
	var total := 0
	for surface in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(surface)
		total += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	return total


func _assert(ok: bool, message: String) -> void:
	if ok:
		return
	push_error("VesselProxyRendererTest: " + message)
	_failed = true
