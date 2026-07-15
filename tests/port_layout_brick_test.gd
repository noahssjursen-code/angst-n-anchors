extends SceneTree

## Terrain-following foundation invariants. Trade berths live in berth_plan attrs.

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
	var foundation := graph.initial_attributes.get("foundation", {}) as Dictionary
	var spine := foundation.get("spine", []) as Array
	var segments := foundation.get("segments", []) as Array
	assert(coast.size() >= 3, "spine must follow the coast, not cut across it")
	assert(spine.size() >= 3)
	assert(not foundation.has("footprint_polygon"), "foundation is mesh-only")
	assert(not foundation.has("footprint_quads"), "foundation does not rebake terrain")
	assert(not foundation.has("land_edge"), "edge arrays are derived at stamp time")
	assert(float(foundation.get("dock_reach_m", 0.0)) > 8.0)
	assert(float(foundation.get("embed_depth_m", 0.0)) >= PortCoastTracer.FOUNDATION_EMBED_DEPTH_M * 0.5)
	assert(float(foundation.get("town_inland_m", 0.0)) >= PortCoastTracer.FOUNDATION_TOWN_INLAND_M * 0.99)
	assert(float(foundation.get("dock_reach_m", 0.0)) <= PortCoastTracer.FOUNDATION_DOCK_REACH_M * 1.1)

	var longest_segment := 0.0
	for raw_segment in segments:
		var segment := raw_segment as Dictionary
		longest_segment = maxf(longest_segment, float(segment.get("length_m", 0.0)))
	assert(
		longest_segment <= PortCoastTracer.MAX_SPINE_SEGMENT_M * 1.15,
		"no chord may span across the island",
	)

	var flattened := graph.flatten_zone_records(definition.world_position, definition.rotation_y)
	for raw_zone in flattened:
		var zone := raw_zone as Dictionary
		assert(not bool(zone.get("ribbon_fill", false)), "foundation must not emit terrain ribbon zones")
		assert(not bool(zone.get("inland_blend", false)), "foundation must not emit inland blend zones")

	print(
		"port_foundation_test OK: %d spine verts, %d segments, extruded mesh" % [
			spine.size(),
			segments.size(),
		]
	)
	quit(0)
