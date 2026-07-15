class_name PortLayoutGenerator
extends RefCounted

const CoastTracer := preload("res://scripts/port/port_coast_tracer.gd")
const BerthPlan := preload("res://scripts/port/port_berth_plan.gd")

## Terrain-traced port layout (current authority):
##   1) square port area + coast trace
##   2) fit harbour spine / asphalt dock face on the shoreline
##   3) measure basin water envelope
##   4) build berth_plan (asphalt pads + dedicated quay arms)
##
## The graph currently holds a single foundation anchor. Trade berths live in
## initial_attributes["berth_plan"] and are stamped by the visualizer.


static func generate(
		definition: PortDefinition,
		profile: PortTradeProfile,
		site_seed: int,
		attributes: Dictionary = {},
) -> PortLayoutGraph:
	var graph := PortLayoutGraph.new()
	graph.port_id = definition.port_id
	graph.site_id = definition.site_id
	graph.site_seed = site_seed
	graph.generation_version = definition.port_generation_version
	graph.initial_attributes = attributes.duplicate(true)
	graph.initial_attributes.erase("world_layout")
	var size := PortSizing.normalized_size(definition.size)
	definition.size = size
	graph.initial_attributes["size"] = size
	graph.initial_attributes["region_kind"] = int(definition.region_kind)
	PortTradeProfile.resync_for_size(profile, size)
	graph.initial_attributes["exports"] = profile.export_slots.duplicate()
	graph.initial_attributes["imports"] = profile.import_slots.duplicate()

	var layout := attributes.get("world_layout") as WorldLayout
	var half_width := CoastTracer.port_area_half_width_m(size)
	var half_depth := CoastTracer.trace_half_depth_m(size)
	var traced_coast := _trace_coast(
		layout,
		definition,
		site_seed,
		half_width,
		half_depth,
	)
	var fit := CoastTracer.fit_port_shoreline(
		layout,
		definition.world_position,
		definition.rotation_y,
		traced_coast,
		size,
		site_seed,
		0.0,
		str(attributes.get("length_profile_override", "")),
	)
	var coast_path: PackedVector2Array = fit.get("harbour_coast", PackedVector2Array()) as PackedVector2Array
	var natural_shore: PackedVector2Array = fit.get("natural_shore", PackedVector2Array()) as PackedVector2Array
	graph.initial_attributes["port_area"] = {
		"half_width_m": CoastTracer.port_area_half_width_m(size),
		"half_depth_m": CoastTracer.port_area_half_depth_m(size),
		"trace_half_width_m": half_width,
		"trace_half_depth_m": half_depth,
		"half_extent_m": maxf(
			CoastTracer.port_area_half_width_m(size),
			CoastTracer.port_area_half_depth_m(size),
		),
		"coast_polyline": _polyline_to_array(coast_path),
		"natural_shore_polyline": _polyline_to_array(natural_shore),
		"terrain_coast_polyline": _polyline_to_array(traced_coast),
		"harbour_style": str(fit.get("style", "")),
		"length_profile": str(fit.get("length_profile", "")),
		"span_coast_polyline": _polyline_to_array(fit.get("span_coast", PackedVector2Array()) as PackedVector2Array),
	}
	var center := coast_path[int(float(coast_path.size()) * 0.5)] if not coast_path.is_empty() else Vector2.ZERO
	graph.add_root("coast_vertex", "root", Vector3(center.x, 0.0, center.y), 0.0, {"role": "foundation_anchor"})
	var foundation: Dictionary = fit.get("foundation", {}) as Dictionary
	foundation["dock_reach_m"] = fit.get("dock_reach_m", foundation.get("dock_reach_m", 0.0))
	foundation["shore_length_m"] = fit.get("shore_length_m", 0.0)
	foundation["length_profile"] = fit.get("length_profile", foundation.get("length_profile", ""))
	foundation["design_hull_loa_m"] = fit.get("design_hull_loa_m", PortSizing.design_hull_loa_m(size))
	foundation["basin"] = BerthPlan.measure_basin(layout, definition, foundation)
	var basin: Dictionary = foundation["basin"]
	## Basin only soft-clamps pier length. Do not rewrite site_max_size here —
	## that ceiling is mini(geo, trade) from PortExpander.
	graph.initial_attributes["foundation"] = foundation
	graph.initial_attributes["basin"] = basin
	graph.initial_attributes["basin_max_size"] = int(basin.get("site_max_size", definition.site_max_size))
	graph.initial_attributes["site_max_size"] = definition.site_max_size
	graph.initial_attributes["exports"] = profile.export_slots.duplicate()
	graph.initial_attributes["imports"] = profile.import_slots.duplicate()
	graph.initial_attributes["berth_plan"] = BerthPlan.build(
		profile,
		size,
		foundation,
		site_seed,
		layout,
		definition,
	)
	return graph


static func _trace_coast(
		layout: WorldLayout,
		definition: PortDefinition,
		site_seed: int,
		half_width: float,
		half_depth: float,
) -> PackedVector2Array:
	if layout != null:
		var traced := CoastTracer.trace_in_port_area(
			layout,
			definition.world_position,
			definition.rotation_y,
			half_width,
			half_depth,
		)
		if traced.size() >= 2:
			return traced
	return CoastTracer.synthetic_coast(site_seed, half_width, half_depth)


static func _polyline_to_array(path: PackedVector2Array) -> Array:
	var out: Array = []
	for point in path:
		out.append([point.x, point.y])
	return out
