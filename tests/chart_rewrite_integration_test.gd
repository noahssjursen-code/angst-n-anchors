extends SceneTree

const SnapshotClass := preload("res://scripts/ui/chart/chart_data_snapshot.gd")
const BaseClass := preload("res://scripts/ui/chart/chart_base_raster.gd")
const RasterClass := preload("res://scripts/ui/chart/chart_raster_layer.gd")
const OverlayClass := preload("res://scripts/ui/map_overlay.gd")

var _picked := ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var registry := root.get_node_or_null("PortCatalog")
	var registry_ids: Array = registry.call("get_port_ids") if registry != null else []
	var snapshot = SnapshotClass.for_preview(90210, 20)
	assert(snapshot.is_valid())
	assert(snapshot.ports.size() == 20)
	assert(snapshot.layout_checksum == str(snapshot.layout.layout_checksum))
	if registry != null:
		assert((registry.call("get_port_ids") as Array) == registry_ids)
	## Onboarding and runtime must consume the same world identity and placed
	## port records. A preview may not silently fall back to the 40 km default.
	assert(is_equal_approx(float(snapshot.world_size_m), float(snapshot.layout.world_size_m)))
	var live_definitions := CoastalPortPlacer.place_ports(
		snapshot.layout,
		20,
		PackedStringArray(WorldPortNames.NAMES),
	)
	for index in range(live_definitions.size()):
		var preview_record := (snapshot.ports[index] as Dictionary).get(
			"port_definition", {},
		) as Dictionary
		assert(not preview_record.is_empty())
		assert(preview_record == (live_definitions[index] as PortDefinition).to_dict())
		assert(PortFishingService.is_eligible(
			PortDefinition.from_dict(preview_record), 90210,
		) == bool(
			(snapshot.ports[index] as Dictionary).get("has_fish_landing", false)
		))

	var base = BaseClass.new()
	base.prepare(snapshot.layout)
	assert(base.texture != null)
	assert(base.build_usec < 2000000)
	## Zoom tile path samples layout SDF only (no terrain meshes).
	base.prepare_visible(Rect2(-2500.0, -2500.0, 5000.0, 5000.0))
	assert(base.texture != null)
	assert(base.world_rect.size.x < float(snapshot.layout.world_size_m))

	var weather = RasterClass.new(RasterClass.Kind.WEATHER)
	var bounds := Rect2(-20000.0, -20000.0, 40000.0, 40000.0)
	weather.prepare(snapshot, bounds, 0.0)
	assert(weather.texture != null)
	assert(int(weather.debug_stats()["build_usec"]) < 750000)

	var overlay = OverlayClass.new()
	root.add_child(overlay)
	overlay.set_data_snapshot(snapshot)
	overlay.enter_home_port_pick_mode()
	overlay.layers.set_visible("weather", true)
	overlay.layers.set_visible("fishing", true)
	overlay.renderer.prepare_overlays(bounds, overlay.layers, 0.0)
	var readout: Array[String] = overlay.renderer.overlay_readout(Vector2.ZERO, overlay.layers, 0.0)
	assert(readout.any(func(row: String) -> bool: return row.begins_with("Wind")))
	assert(readout.any(func(row: String) -> bool: return row.begins_with("Fishing")))
	overlay.home_port_confirmed.connect(func(port_id: String) -> void: _picked = port_id)
	var first: Dictionary = snapshot.ports[0]
	var position := first["position"] as Vector3
	var chart := Rect2(0.0, 0.0, 1000.0, 1000.0)
	var context := {"chart_rect": chart, "world_bounds": bounds, "world_span": 40000.0}
	overlay.last_ctx = context
	var screen := chart.position + Vector2(
		(position.x - bounds.position.x) / bounds.size.x * chart.size.x,
		(position.z - bounds.position.y) / bounds.size.y * chart.size.y,
	)
	overlay.call("_click_chart", screen)
	assert(_picked == str(first["id"]))
	print(
		"Marine chart rewrite integration/performance tests passed (base=%d us weather=%d us)"
		% [base.build_usec, int(weather.debug_stats()["build_usec"])]
	)
	quit()
