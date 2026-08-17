extends SceneTree

## Scratch probe (leading underscore — not a gate unit). Lane A.
##
## THE ONE QUESTION: can `PortExpander.chart_summary` stop re-deriving the trade
## profile, the size ladder and the RNG draws and simply ASK the expander?
##
## `chart_summary` already calls `realized_fish_landing` (deleted after this probe
## ran, when the collapse left it with no callers; `summary_expansion` now), which
## runs a FULL
## `expand` (cached) and throws away everything but one boolean. So the collapse
## is not "spend a full expansion instead of a cheap summary" — the full
## expansion is ALREADY PAID. This probe measures three things:
##
##   1. COST. Wall time of `chart_summary` per port as it stands, and how much of
##      that is the expansion it already runs. If the summary's own re-derivation
##      is a rounding error beside the expand it already pays for, the cost
##      argument for keeping a second derivation is gone.
##   2. CACHE. Whether the expansion `chart_summary` runs is the same cache entry
##      the chart's own `ChartHarbourPlan.resolve_port_data` uses — i.e. whether
##      reading the fields off it costs zero new expansions.
##   3. PRODUCIBILITY, field by field. For every key `chart_summary` publishes,
##      whether the world's `PortData` (or its layout graph) already carries the
##      same value. A field the expander CANNOT produce at preview time is a real
##      reason not to collapse, and it would show up here as a mismatch.
##
## Six seeds x 35 ports, sizes 0-4 (no port in this project is above size 4).

const GENERATOR := preload("res://scripts/world/world_layout_generator.gd")
const PLACER := preload("res://scripts/world/coastal_port_placer.gd")
const PORT_COUNT := 35
const SEEDS := [424242, 20260817, 90210, 777, 20260816, 31337]
const LAYOUT_NOTE := "Terrain-traced Port Layout"


func _initialize() -> void:
	var total := 0
	var sizes: Dictionary = {}
	var mismatch: Dictionary = {}
	var example: Dictionary = {}
	var summary_usec := 0
	var cold_expand_usec := 0
	var warm_summary_usec := 0
	var cache_growth_from_summary := 0
	var cache_growth_from_chart_redraw := 0

	for world_seed in SEEDS:
		var layout: WorldLayout = GENERATOR.generate(int(world_seed))
		var ports: Array[PortDefinition] = PLACER.place_ports(
			layout, PORT_COUNT, PackedStringArray(WorldPortNames.NAMES))
		LandField.initialize(layout)
		FishingField.initialize(int(world_seed))
		WeatherField.world_seed = int(world_seed)
		for port in ports:
			total += 1
			var tag := "%d/%s" % [int(world_seed), port.port_id]

			## ── cost, cold: chart_summary from an empty cache ────────────────
			PortDataCache.clear()
			var t0 := Time.get_ticks_usec()
			var summary := PortExpander.chart_summary(
				PortDefinition.from_dict(port.to_dict()), int(world_seed), layout)
			summary_usec += Time.get_ticks_usec() - t0
			cache_growth_from_summary += PortDataCache._cache.size()

			## the expansion alone, same inputs, also cold
			PortDataCache.clear()
			var t1 := Time.get_ticks_usec()
			var data := PortExpander.expand(
				PortDefinition.from_dict(port.to_dict()), int(world_seed), layout)
			cold_expand_usec += Time.get_ticks_usec() - t1
			## ── cost, warm: what a collapsed summary would pay on a cache hit
			var t2 := Time.get_ticks_usec()
			var _again := PortExpander.chart_summary(
				PortDefinition.from_dict(port.to_dict()), int(world_seed), layout)
			warm_summary_usec += Time.get_ticks_usec() - t2

			## ── cache: does drawing the harbour cost a new expansion? ────────
			var before := PortDataCache._cache.size()
			var chart_def := PortDefinition.from_dict(
				summary.get("port_definition", {}) as Dictionary)
			var _redraw := PortExpander.expand(chart_def, int(world_seed), layout)
			cache_growth_from_chart_redraw += PortDataCache._cache.size() - before

			sizes["size %d" % int(data.size)] = int(sizes.get("size %d" % int(data.size), 0)) + 1

			## ── producibility, field by field ────────────────────────────────
			var graph_attrs: Dictionary = data.layout_graph.initial_attributes
			var world_of: Dictionary = {
				"id": data.port_id,
				"display_name": data.display_name,
				"position": data.world_position,
				"rotation_y": data.rotation_y,
				"layout_seed": data.layout_seed,
				"site_max_size": int(graph_attrs.get("site_max_size", -1)),
				"size": data.size,
				"commodity_export": data.commodity_export,
				"commodity_imports": data.commodity_imports,
				"export_slots": data.trade_profile.export_slots,
				"max_ship_class": int(data.max_ship_class),
				"max_ship_class_name": str(ShipClass.DISPLAY_NAME.get(data.max_ship_class, "Vessel")),
				"has_lighthouse": data.has_lighthouse,
				"has_fog_horn": data.has_fog_horn,
				"has_fish_landing": data.has_fish_landing,
				"region": (data.to_chart_dict() as Dictionary).get("region", ""),
			}
			for key in world_of:
				_cmp(mismatch, example, str(key), tag,
					str(summary.get(key, "<missing>")), str(world_of[key]))
			## features: is the world's list exactly the note plus the panel's?
			var panel_features: Array = summary.get("features", []) as Array
			var world_features: Array = data.features
			var stripped: Array = []
			for raw in world_features:
				if str(raw) != LAYOUT_NOTE:
					stripped.append(str(raw))
			_cmp(mismatch, example, "features(note stripped)", tag,
				str(panel_features), str(stripped))
			_cmp(mismatch, example, "features(note is first and once)", tag,
				"true",
				str(world_features.size() == stripped.size() + 1
					and str(world_features[0]) == LAYOUT_NOTE))
			## the two owner-decision fields, recorded not resolved
			_cmp(mismatch, example, "population(OWNER)", tag,
				str(summary.get("population", -1)), str(data.population))
			_cmp(mismatch, example, "berth_count(OWNER)", tag,
				str(summary.get("berth_count", -1)), str(data.berth_count))
			## the definition chart_summary promises to leave untouched
			_cmp(mismatch, example, "port_definition untouched", tag,
				str(summary.get("port_definition", {})), str(port.to_dict()))

	print("")
	print("=== %d ports over %d seeds   %s" % [total, SEEDS.size(), str(sizes)])
	print("=== COST per port, cold cache:")
	print("      chart_summary as it stands      %7.2f ms" % (float(summary_usec) / total / 1000.0))
	print("      the expand() inside it, alone   %7.2f ms" % (float(cold_expand_usec) / total / 1000.0))
	print("      chart_summary on a WARM cache   %7.2f ms" % (float(warm_summary_usec) / total / 1000.0))
	print("      => the summary's own re-derivation is the difference between the")
	print("         first two; a collapsed summary pays the third on a warm cache.")
	print("=== CACHE: cache entries after one cold chart_summary: %.2f per port" % (
		float(cache_growth_from_summary) / total))
	print("      new entries when the chart then draws that harbour: %d over %d ports" % [
		cache_growth_from_chart_redraw, total])
	print("=== PRODUCIBILITY — fields where the world's PortData does NOT already")
	print("    carry the summary's value (0 means the expander can produce it):")
	var keys := mismatch.keys()
	keys.sort()
	for key in keys:
		print("      %3d/%d  %-32s %s" % [
			int(mismatch[key]), total, str(key), str(example[key])])
	if mismatch.is_empty():
		print("      (none — every published field is already in the expander's output)")
	quit(0)


func _cmp(mismatch: Dictionary, example: Dictionary, key: String, tag: String,
		a: String, b: String) -> void:
	if a == b:
		return
	mismatch[key] = int(mismatch.get(key, 0)) + 1
	if not example.has(key):
		example[key] = "%s summary=%s world=%s" % [tag, _clip(a), _clip(b)]


func _clip(s: String) -> String:
	return s if s.length() <= 90 else s.substr(0, 87) + "..."
