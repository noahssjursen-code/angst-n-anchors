extends SceneTree

## Scratch probe (leading underscore — not a gate unit). Lane A.
## Which published fields diverge between `chart_summary` and the world's
## `expand`, at exactly the seed and port count `chart_rewrite_integration_test`
## uses (90210, 20), plus the cache-reuse count the new check will assert.

const SnapshotClass := preload("res://scripts/ui/chart/chart_data_snapshot.gd")


func _initialize() -> void:
	PortDataCache.clear()
	var snapshot = SnapshotClass.for_preview(90210, 20)
	var after_preview: int = PortDataCache._cache.size()
	var definitions := CoastalPortPlacer.place_ports(
		snapshot.layout, 20, PackedStringArray(WorldPortNames.NAMES))
	var diverge: Dictionary = {}
	var example: Dictionary = {}
	var keys_seen: Dictionary = {}
	for index in definitions.size():
		var summary: Dictionary = snapshot.ports[index]
		var world := PortExpander.expand(
			definitions[index] as PortDefinition, 90210, snapshot.layout)
		var chart := world.to_chart_dict()
		for key in chart:
			if not summary.has(key):
				continue
			keys_seen[key] = true
			if str(summary[key]) != str(chart[key]):
				diverge[key] = int(diverge.get(key, 0)) + 1
				if not example.has(key):
					example[key] = "summary=%s world=%s" % [
						str(summary[key]).substr(0, 90), str(chart[key]).substr(0, 90)]
	var after_world: int = PortDataCache._cache.size()
	print("=== cache entries: after preview %d, after 20 world expansions %d (delta %d)" % [
		after_preview, after_world, after_world - after_preview])
	print("=== published keys compared: %s" % str(keys_seen.keys()))
	print("=== summary-only keys: %s" % str(
		snapshot.ports[0].keys().filter(func(k): return not keys_seen.has(k))))
	for key in diverge:
		print("   DIVERGES %2d/20  %-20s %s" % [int(diverge[key]), str(key), str(example[key])])

	## Contrast: is the layout-less harbour a different harbour at every port?
	var coast_differs := 0
	var pads_differ := 0
	for index in definitions.size():
		var d: PortDefinition = definitions[index]
		var with_l := PortExpander.expand_uncached(
			PortDefinition.from_dict(d.to_dict()), 90210, snapshot.layout)
		var without := PortExpander.expand_uncached(
			PortDefinition.from_dict(d.to_dict()), 90210, null)
		if str(_coast(with_l)) != str(_coast(without)):
			coast_differs += 1
		if _pads(with_l) != _pads(without):
			pads_differ += 1
	print("=== layout vs no layout: coast polyline differs at %d/20, pad count at %d/20" % [
		coast_differs, pads_differ])
	quit(0)


func _coast(data: PortData) -> Array:
	var area := data.layout_graph.initial_attributes.get("port_area", {}) as Dictionary
	return area.get("coast_polyline", []) as Array


func _pads(data: PortData) -> int:
	var land := data.layout_graph.initial_attributes.get("land_plan", {}) as Dictionary
	return int((land.get("apron_pads", {}) as Dictionary).get("pad_count", -1))
