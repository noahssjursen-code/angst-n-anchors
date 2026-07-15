extends SceneTree

## Terrain-following foundation invariants. Harbours have no terminals yet.

const WORLD_LAYOUT_GENERATOR := preload("res://scripts/world/world_layout_generator.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var layout := WORLD_LAYOUT_GENERATOR.generate(424242)
	var definition := PortDefinition.new()
	definition.port_id = "foundation-test"
	definition.display_name = "Foundation Test"
	definition.size = 4
	definition.region_kind = PortDefinition.RegionKind.MAINLAND
	definition.site_seed = 424242
	definition.port_generation_version = PortDefinition.CURRENT_PORT_GENERATION_VERSION
	definition.world_position = Vector3(12000.0, 0.0, -8000.0)
	definition.rotation_y = 0.4
	definition.has_explicit_rotation = true

	var first := PortExpander.expand(definition, 424242, layout)
	var second := PortExpander.expand(definition, 424242, layout)
	assert(first.layout_graph != null, "expand must yield a graph")
	var graph := first.layout_graph
	assert(graph.modules.size() == 1, "foundation pass must not place harbour modules")
	assert(graph.is_graph_connected())
	assert(
		JSON.stringify(graph.to_dict()) == JSON.stringify(second.layout_graph.to_dict()),
		"same site record must produce a byte-equivalent foundation",
	)

	var port_area := graph.initial_attributes.get("port_area", {}) as Dictionary
	var coast := port_area.get("coast_polyline", []) as Array
	var natural := port_area.get("natural_shore_polyline", []) as Array
	var terrain_coast := port_area.get("terrain_coast_polyline", []) as Array
	var foundation := graph.initial_attributes.get("foundation", {}) as Dictionary
	var land_edge := foundation.get("land_edge", []) as Array
	var water_edge := foundation.get("water_edge", []) as Array
	var segments := foundation.get("segments", []) as Array
	var reclaim_zones := foundation.get("reclaim_zones", []) as Array
	assert(coast.size() >= 2, "must trace a shoreline inside the port area")
	assert(natural.size() >= 2, "must keep the natural mainland edge")
	assert(terrain_coast.size() >= 2, "must keep the natural traced shoreline")
	assert(str(port_area.get("harbour_style", "")) == "grown_dock", "harbour must grow dock from mainland")
	assert(land_edge.size() == coast.size() and water_edge.size() == coast.size())
	assert(segments.size() == coast.size() - 1, "foundation ribbon covers every coast segment")
	assert(float(foundation.get("dock_reach_m", 0.0)) > 8.0)
	assert(is_equal_approx(float(foundation.get("surface_y_m", 0.0)), PortCoastTracer.FOUNDATION_SURFACE_Y_M))
	assert(not graph.initial_attributes.has("dock_recipe"), "quays stay disabled")
	assert(reclaim_zones.size() >= 1, "harbour must reclaim seaward dock growth")
	assert(not foundation.has("carve_zones"), "carving is disabled")

	var longest := 0.0
	for raw_segment in segments:
		var segment := raw_segment as Dictionary
		longest = maxf(longest, float(segment.get("length_m", 0.0)))
	assert(longest >= PortCoastTracer.normalized_min_segment_m(4) * 0.85, "pavement spans should normalize")

	for instance_id in graph.module_ids():
		var placed := graph.modules[instance_id] as PortPlacedModule
		var module_definition := graph.module_definition(placed.module_id)
		assert(module_definition != null and module_definition.kind == "coast")

	var flattened := graph.flatten_zone_records(definition.world_position, definition.rotation_y)
	assert(flattened.size() == segments.size() + reclaim_zones.size(), "terrain uses pavement pads and reclaim zones")
	var reclaim_count := 0
	var carve_count := 0
	for raw_zone in flattened:
		var zone := raw_zone as Dictionary
		if bool(zone.get("reclaim", false)):
			reclaim_count += 1
		if bool(zone.get("carve", false)):
			carve_count += 1
	assert(reclaim_count == reclaim_zones.size())
	assert(carve_count == 0)

	var restored := PortLayoutGraph.from_dict(graph.to_dict())
	assert(restored != null and restored.is_graph_connected())
	print(
		"port_foundation_test OK: %s, %d pavement segments, %d reclaim zones" % [
			str(port_area.get("harbour_style", "")),
			segments.size(),
			reclaim_zones.size(),
		]
	)
	quit(0)
