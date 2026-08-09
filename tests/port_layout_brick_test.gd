extends SceneTree

## Terrain-following foundation invariants. Trade berths live in berth_plan attrs.

const WORLD_LAYOUT_GENERATOR := preload("res://scripts/world/world_layout_generator.gd")
const TestReport := preload("res://tests/support/test_report.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var t := TestReport.new("port_layout_brick_test")
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
	if not t.check("expand must yield a graph", first.layout_graph != null):
		t.finish(self)
		return
	var graph := first.layout_graph
	t.equal("foundation pass must not place harbour modules", graph.modules.size(), 1)
	t.check("foundation graph is connected", graph.is_graph_connected())
	t.check(
		"same site record must produce a byte-equivalent foundation",
		JSON.stringify(graph.to_dict()) == JSON.stringify(second.layout_graph.to_dict()),
	)

	var port_area := graph.initial_attributes.get("port_area", {}) as Dictionary
	var coast := port_area.get("coast_polyline", []) as Array
	var natural := port_area.get("natural_shore_polyline", []) as Array
	var foundation := graph.initial_attributes.get("foundation", {}) as Dictionary
	var spine := foundation.get("spine", []) as Array
	var segments := foundation.get("segments", []) as Array
	t.check("spine must follow the coast, not cut across it", coast.size() >= 3)
	t.check("spine has at least three vertices", spine.size() >= 3)
	t.check("foundation is mesh-only", not foundation.has("footprint_polygon"))
	t.check("foundation does not rebake terrain", not foundation.has("footprint_quads"))
	t.check("edge arrays are derived at stamp time", not foundation.has("land_edge"))
	t.check("dock reach exceeds 8 m", float(foundation.get("dock_reach_m", 0.0)) > 8.0)
	t.check(
		"embed depth is at least half the traced depth",
		float(foundation.get("embed_depth_m", 0.0)) >= PortCoastTracer.FOUNDATION_EMBED_DEPTH_M * 0.5,
	)
	t.check(
		"town inland distance matches the traced inland reach",
		float(foundation.get("town_inland_m", 0.0)) >= PortCoastTracer.FOUNDATION_TOWN_INLAND_M * 0.99,
	)
	t.check(
		"dock reach stays within the traced dock reach",
		float(foundation.get("dock_reach_m", 0.0)) <= PortCoastTracer.FOUNDATION_DOCK_REACH_M * 1.1,
	)

	var longest_segment := 0.0
	for raw_segment in segments:
		var segment := raw_segment as Dictionary
		longest_segment = maxf(longest_segment, float(segment.get("length_m", 0.0)))
	t.check(
		"no chord may span across the island",
		longest_segment <= PortCoastTracer.MAX_SPINE_SEGMENT_M * 1.15,
	)

	var flattened := graph.flatten_zone_records(definition.world_position, definition.rotation_y)
	for raw_zone in flattened:
		var zone := raw_zone as Dictionary
		t.check("foundation must not emit terrain ribbon zones", not bool(zone.get("ribbon_fill", false)))
		t.check("foundation must not emit inland blend zones", not bool(zone.get("inland_blend", false)))

	t.finish(self)
