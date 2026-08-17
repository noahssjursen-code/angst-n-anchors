extends SceneTree

## Scratch probe (leading underscore — not a gate unit). Lane A.
##
## ONE QUESTION, RAISED BY A MUTATION THAT PASSED FIRST TIME. Dropping the
## `world_layout` argument from `ChartDataSnapshot.for_preview`'s
## `PortExpander.chart_summary` call changed NOTHING: `port_feature_promise_test`
## stayed PASS (32) with identical witness ports and identical counts. Either the
## layout does not reach the fish-landing answer, or nothing measured looks where
## it does. `PortExpander.realized_fish_landing`'s header says an expansion without
## a layout "answers a different question", and that sentence is a claim.
##
## So: expand every port of two worlds BOTH ways and diff the fields.

const GENERATOR := preload("res://scripts/world/world_layout_generator.gd")
const PLACER := preload("res://scripts/world/coastal_port_placer.gd")
const PORT_COUNT := 35
const SEEDS := [424242, 20260817]


func _initialize() -> void:
	var total := 0
	var moved: Dictionary = {}
	for world_seed in SEEDS:
		var layout: WorldLayout = GENERATOR.generate(int(world_seed))
		var ports: Array[PortDefinition] = PLACER.place_ports(
			layout, PORT_COUNT, PackedStringArray(WorldPortNames.NAMES))
		LandField.initialize(layout)
		FishingField.initialize(int(world_seed))
		for port in ports:
			total += 1
			var with_layout := _expand(port, int(world_seed), layout)
			var without := _expand(port, int(world_seed), null)
			for key in with_layout:
				if str(with_layout[key]) != str(without[key]):
					if not moved.has(key):
						moved[key] = [0, port.port_id, with_layout[key], without[key]]
					var row: Array = moved[key]
					row[0] = int(row[0]) + 1
	print("%d ports expanded twice (with layout / without) over seeds %s" % [total, str(SEEDS)])
	for key in ["has_fish_landing", "size", "berth_count", "quay_families",
			"dock_length", "island_width", "commodity_imports",
			"basin_seaward_clear_m", "basin_probe_failed", "basin_max_arm_m",
			"coast_polyline_points", "quay_length_m", "harbour_style"]:
		if moved.has(key):
			var row: Array = moved[key]
			print("   %-20s MOVED at %2d/%d ports   e.g. %s: with=%s without=%s" % [
				key, int(row[0]), total, str(row[1]), str(row[2]), str(row[3]),
			])
		else:
			print("   %-20s identical at all %d ports" % [key, total])
	quit(0)


func _expand(definition: PortDefinition, world_seed: int, layout: WorldLayout) -> Dictionary:
	PortDataCache.clear()
	var data := PortExpander.expand_uncached(
		PortDefinition.from_dict(definition.to_dict()), world_seed, layout)
	var families: Array[String] = []
	for raw in (data.layout_graph.initial_attributes.get("berth_plan", {}) as Dictionary) \
			.get("quay_stations", []) as Array:
		families.append(str((raw as Dictionary).get("family", "")))
	families.sort()
	var attrs := data.layout_graph.initial_attributes
	var plan := attrs.get("berth_plan", {}) as Dictionary
	var basin := plan.get("basin", {}) as Dictionary
	var quay_len := 0.0
	for raw in plan.get("quay_stations", []) as Array:
		quay_len += float((raw as Dictionary).get("length_m", 0.0))
	return {
		"basin_seaward_clear_m": "%.1f" % float(basin.get("seaward_clear_m", -1.0)),
		"basin_probe_failed": bool(basin.get("probe_failed", false)),
		"basin_max_arm_m": "%.1f" % float(basin.get("max_arm_m", -1.0)),
		"coast_polyline_points": (attrs.get("port_area", {}) as Dictionary) \
			.get("coast_polyline", []).size(),
		"quay_length_m": "%.1f" % quay_len,
		"harbour_style": str((attrs.get("port_area", {}) as Dictionary).get("harbour_style", "")),
		"has_fish_landing": data.has_fish_landing,
		"size": data.size,
		"berth_count": data.berth_count,
		"quay_families": str(families),
		"dock_length": "%.1f" % data.dock_length,
		"island_width": "%.1f" % data.island_width,
		"commodity_imports": str(data.commodity_imports),
	}
