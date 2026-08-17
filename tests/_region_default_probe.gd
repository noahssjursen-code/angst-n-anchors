extends Node

## Scratch probe (leading underscore — not a gate unit). LANE B, and it has to be:
## `ChartHarbourPlan` names `HarbourRegistry` bare, which reaches
## `harbour_authority_bridge.gd`'s bare `WorldGateway`, so under `--script` the file
## fails to COMPILE (CONVENTIONS §2).
##
##   xvfb-run -a --server-args="-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy \
##     res://tests/_region_default_probe.tscn
##
## ── THE QUESTIONS ──────────────────────────────────────────────────────────
##
## Q1  How far apart are the live chart's harbour and the stamped harbour today,
##     and does the count reproduce the last wave's 133 of 210 path for path?
##
## Q2  Which CANDIDATE MECHANISM closes it, measured through the real
##     `PortCatalog.register_port` rather than by poking `_ports`:
##       W14 — the fourteen arguments `world.gd:_setup_ports` passes today.
##       W15 — the same, plus `region`.
##       W17 — the same, plus `region`, `max_ship_class_name`, `commodity_exports`
##             (i.e. exactly what the OTHER producer, `port_plot.gd`, passes).
##       DEF — W14 with the whole placed `port_definition` written into the entry,
##             the shape an eighteenth parameter would take.
##
## Q3  THE SIBLING DEFAULTS. `region` was defaulted silently; what else among
##     `register_port`'s seventeen parameters does `world.gd` leave defaulted that
##     the placer/expander actually assigns, and does a player READ it?
##
## Whole structures are diffed — every polygon point, every meta dictionary, the
## bounds rect, the camera helpers. Never a `.size()` and never a sum (REALITY §4e:
## a conclusion was reversed this week by exactly those two).
##
## Six seeds x 35 ports, sizes 0-4. No port in this project is above size 4.
##
## ── Q4, ADDED 2026-08-17 AFTER THE FIRST RUN, AND IT IS THE REASON THE HEADLINE
##    NUMBER NEEDED RECONCILING ────────────────────────────────────────────────
##
## Run 1 of this file measured W14 divergence at **73 of 210** on the eighteen
## PLAYER_FACING_KEYS, with a path table IDENTICAL to the one on record
## (quay_polys 70, quay_meta 73, bounds 57, centre_world 57, suggested_span_m 46,
## berth counts 34, foundation/shore/dock-face 2). The number on record beside that
## same table is **133 of 210**. The tables agreeing while the counts differ says
## the two probes diffed different KEY SETS, not different worlds:
## `_chart_live_ceiling_probe._diff` walks the union of both digests' keys, and its
## digest carries five fields this one deliberately excludes — `data_features` and
## the four showcase-only attributes. So Q4 measures BOTH sets in one pass:
##
##   PLAYER_FACING_KEYS — what the chart draws, plus the PortData fields a panel
##                        reads off the same object.
##   ALL_KEYS           — the above plus `data_features`, the four showcase
##                        attributes, and the four expander RNG-stream fields
##                        (`has_lighthouse` / `has_fog_horn` / `has_fish_landing` /
##                        `population`), named individually rather than lumped into
##                        the features string, because they are the suspected cause:
##                        `expand_uncached` reads `definition.has_lighthouse or
##                        rng.randf() < 0.3`, which SHORT-CIRCUITS, so a rebuild
##                        whose definition lost those two booleans consumes the RNG
##                        stream at a different offset and every later draw off that
##                        `rng` shifts with it.
##
## ── THE ANSWER, run 2, six seeds x 35 ports, 840 draws, 840 forced cache misses,
##    0 unresolved ──────────────────────────────────────────────────────────────
##
## | registration | PLAYER_FACING_KEYS (18) | ALL_KEYS (27) |
## |---|---|---|
## | W14 — `world.gd` as of `f96ca38` | **73 of 210** | **139 of 210** |
## | W15 — plus `region` | **0 of 210** | 87 of 210 |
## | W17 — plus `max_ship_class_name`, `commodity_exports` | **0 of 210** | 87 of 210 |
## | DEF — plus the whole placed `port_definition` | **0 of 210** | **0 of 210** |
##
## **So the 133 on record was measuring the wider set, and neither probe was wrong.**
## `_chart_live_ceiling_probe`'s digest carried the eighteen keys here plus
## `data_features` and the four showcase attributes but NOT the four RNG-stream fields
## — add those four and the same measurement gives 139. The 6-port gap between 133 and
## 139 is ports whose only divergence is `population` or a facility boolean. The
## number for the harbour a player is SHOWN is **73 of 210**, and its path table is
## identical to the one published beside the 133.
##
## Two further results decided the mechanism, and both are the reason W17 and DEF were
## not adopted:
##
##   * W17 == W15 exactly, on both key sets. `resolve_port_data` reads neither
##     `max_ship_class_name` nor `commodity_exports`, so those two parameters cannot
##     move a harbour. They are wrong on the record for other readers (Q3) and are
##     registered in `chart_live_harbour_test`, not fixed here.
##   * DEF is the only variant that also closes the 87 — and all 87 are fields of a
##     `PortData` that is DISCARDED. `resolve_port_data`'s only production caller is
##     `ChartHarbourPlan.for_port`, which keeps the plan and drops the data. The cause
##     is the short-circuit in `expand_uncached`'s `definition.has_lighthouse or
##     rng.randf() < 0.3`: a rebuild whose definition lost those booleans consumes the
##     shared `rng` at a different offset, so `population` and the facility flags shift
##     with it. Real, and read by nobody.

const GENERATOR := preload("res://scripts/world/world_layout_generator.gd")
const PLACER := preload("res://scripts/world/coastal_port_placer.gd")
const PORT_COUNT := 35
const SEEDS := [424242, 20260817, 90210, 777, 20260816, 31337]

## The keys of the digest a player either sees drawn on the chart or reads off the
## same PortData. Same list as `chart_live_harbour_test`.
const PLAYER_FACING_KEYS: Array[String] = [
	"land_poly", "foundation_poly", "shore_poly", "dock_face_poly",
	"quay_polys", "quay_meta", "asphalt_polys", "asphalt_meta",
	"quay_poly_count", "asphalt_poly_count",
	"bounds", "centre_world", "suggested_span_m", "world_origin", "rotation_y",
	"data_size", "data_berth_count", "data_max_ship_class",
]

## The five keys `_chart_live_ceiling_probe`'s union-diff also walked, plus the four
## RNG-stream fields that feed `data_features`, named one by one. Declared as a
## literal so the superset cannot quietly change shape between runs (§4f shape 1).
const EXTRA_KEYS: Array[String] = [
	"data_features",
	"graph_site_max_size", "basin_max_size", "basin_site_max_size", "berth_notes",
	"data_population", "data_has_lighthouse", "data_has_fog_horn", "data_has_fish_landing",
]


class StubWorld:
	extends Node
	var layout: WorldLayout
	var seed_value := 0

	func get_world_layout() -> WorldLayout:
		return layout

	func get_shipping_lane_network():
		return null

	func get_world_traffic_service():
		return null

	func get_world_context() -> Dictionary:
		return {
			"seed": seed_value,
			"generation_version": 0,
			"layout_checksum": str(layout.layout_checksum) if layout != null else "",
			"world_size_m": layout.world_size_m if layout != null else 40000.0,
			"world_preset": "standard",
		}


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var catalog := get_node_or_null("/root/PortCatalog")
	if catalog == null:
		print("NO PortCatalog AUTOLOAD — probe cannot run")
		get_tree().quit(1)
		return

	var total := 0
	var forced_misses := 0
	var unresolved := 0
	var differ: Dictionary = {"w14": 0, "w15": 0, "w17": 0, "def": 0}
	var paths: Dictionary = {"w14": {}, "w15": {}, "w17": {}, "def": {}}
	## Q4 — the same four variants against the SUPERSET key set.
	var differ_all: Dictionary = {"w14": 0, "w15": 0, "w17": 0, "def": 0}
	var paths_all: Dictionary = {"w14": {}, "w15": {}, "w17": {}, "def": {}}
	var all_keys: Array[String] = PLAYER_FACING_KEYS.duplicate() as Array[String]
	for key in EXTRA_KEYS:
		all_keys.append(key)
	var first_divergent: Dictionary = {}
	## Q3 — the sibling defaults.
	var region_wrong := 0
	var class_wrong := 0
	var exports_wrong := 0
	var regions_seen: Dictionary = {}
	var classes_seen: Dictionary = {}
	var export_slot_counts: Dictionary = {}
	var class_examples: Array[String] = []
	var export_examples: Array[String] = []
	var sizes_seen: Dictionary = {}

	for world_seed in SEEDS:
		var seed_int := int(world_seed)
		var layout: WorldLayout = GENERATOR.generate(seed_int)
		var defs: Array = PLACER.place_ports(
			layout, PORT_COUNT, PackedStringArray(WorldPortNames.NAMES))

		catalog.call("clear")
		PortDataCache.clear()
		LandField.initialize(layout)
		FishingField.initialize(seed_int)
		WeatherField.world_seed = seed_int
		WeatherFrontField.initialize(seed_int)

		var records: Array = []
		for raw in defs:
			var placed := raw as PortDefinition
			var source := placed.to_dict()
			var world_def := PortDefinition.from_dict(source)
			var world_data := PortExpander.expand(world_def, seed_int, layout)
			_register(catalog, world_data, "w14")
			records.append({"source": source, "data": world_data})

		var stub := StubWorld.new()
		stub.name = "ProbeWorld"
		stub.layout = layout
		stub.seed_value = seed_int
		stub.add_to_group("world")
		get_tree().root.add_child(stub)
		var snapshot := ChartDataSnapshot.from_live_tree(get_tree())
		if snapshot.ports.size() != defs.size():
			print("SNAPSHOT SIZE MISMATCH %d vs %d" % [snapshot.ports.size(), defs.size()])

		for rec_raw in records:
			var rec: Dictionary = rec_raw
			var data := rec["data"] as PortData
			var pid := data.port_id
			total += 1
			sizes_seen[int(data.size)] = int(sizes_seen.get(int(data.size), 0)) + 1

			## ── Q3, measured off the catalog entry the world actually writes ──
			var truth := data.to_chart_dict()
			var real_region := str(truth.get("region", ""))
			var real_class := str(truth.get("max_ship_class_name", ""))
			var real_exports: Array = []
			if data.trade_profile != null:
				real_exports = data.trade_profile.export_slots.duplicate()
			regions_seen[real_region] = int(regions_seen.get(real_region, 0)) + 1
			classes_seen[real_class] = int(classes_seen.get(real_class, 0)) + 1
			export_slot_counts[real_exports.size()] = \
					int(export_slot_counts.get(real_exports.size(), 0)) + 1
			var live: Dictionary = catalog.call("get_port_info", pid)
			if str(live.get("region", "")) != real_region:
				region_wrong += 1
			if str(live.get("max_ship_class_name", "")) != real_class:
				class_wrong += 1
				if class_examples.size() < 3:
					class_examples.append("%s: catalog=%s real=%s" % [
						pid, str(live.get("max_ship_class_name", "")), real_class])
			if JSON.stringify(_strings(live.get("commodity_exports", []) as Array)) \
					!= JSON.stringify(_strings(real_exports)):
				exports_wrong += 1
				if export_examples.size() < 3:
					export_examples.append("%s: catalog=%s real=%s" % [
						pid,
						str(_strings(live.get("commodity_exports", []) as Array)),
						str(_strings(real_exports))])

			## ── Q1 / Q2 — the STAMP, then each candidate through register_port ──
			var c := _digest(ChartHarbourPlan.from_port_data(data), data)
			for variant in ["w14", "w15", "w17", "def"]:
				var v := _draw_variant(catalog, snapshot, data, rec["source"] as Dictionary, variant)
				forced_misses += int(v.get("forced_misses", 0))
				if not bool(v.get("resolved", false)):
					unresolved += 1
					continue
				var d_all := _diff(v, c, all_keys)
				if not d_all.is_empty():
					differ_all[variant] = int(differ_all[variant]) + 1
					var bucket_all: Dictionary = paths_all[variant]
					for key_all in d_all:
						bucket_all[key_all] = int(bucket_all.get(key_all, 0)) + 1
				var d := _diff(v, c, PLAYER_FACING_KEYS)
				if not d.is_empty():
					differ[variant] = int(differ[variant]) + 1
					var bucket: Dictionary = paths[variant]
					for key in d:
						bucket[key] = int(bucket.get(key, 0)) + 1
					if variant == "w14" and first_divergent.is_empty():
						first_divergent = {
							"port": "%d/%s" % [seed_int, pid],
							"paths": d.keys(),
							"live": v, "stamp": c,
						}
			## Leave the catalog as the world writes it.
			_register(catalog, data, "w14")

		get_tree().root.remove_child(stub)
		stub.free()
		print("seed %d done — cumulative W14 divergence %d of %d"
			% [seed_int, int(differ["w14"]), total])

	print("")
	print("=== _region_default_probe ===")
	print("ports measured: %d (%d seeds x %d), unresolved: %d, forced cache misses: %d of %d draws"
		% [total, SEEDS.size(), PORT_COUNT, unresolved, forced_misses, total * 4])
	print("resolved sizes seen: %s" % str(sizes_seen))
	print("")
	print("--- Q1/Q2: the live chart's harbour against the STAMPED harbour ---")
	print("    key set: the %d PLAYER_FACING_KEYS (drawn, or read off the same PortData)"
		% PLAYER_FACING_KEYS.size())
	for variant in ["w14", "w15", "w17", "def"]:
		print("%s: DIFFER at %d of %d ports · paths %s"
			% [variant.to_upper(), int(differ[variant]), total, str(paths[variant])])
	print("")
	print("--- Q4: the SAME four variants against the SUPERSET the 133 was measured on ---")
	print("    key set: those %d plus %s" % [PLAYER_FACING_KEYS.size(), str(EXTRA_KEYS)])
	for variant in ["w14", "w15", "w17", "def"]:
		print("%s: DIFFER at %d of %d ports · paths %s"
			% [variant.to_upper(), int(differ_all[variant]), total, str(paths_all[variant])])
	if not first_divergent.is_empty():
		print("")
		print("first W14 divergence: %s paths=%s"
			% [str(first_divergent["port"]), str(first_divergent["paths"])])
		for p in (first_divergent["paths"] as Array):
			print("   %s LIVE  = %s" % [str(p),
				str((first_divergent["live"] as Dictionary)[p]).substr(0, 200)])
			print("   %s STAMP = %s" % [str(p),
				str((first_divergent["stamp"] as Dictionary)[p]).substr(0, 200)])
	print("")
	print("--- Q3: the sibling defaults on the entry world.gd writes ---")
	print("region words the placer assigns: %s" % str(regions_seen))
	print("   catalog `region` WRONG at %d of %d" % [region_wrong, total])
	print("max ship classes the expander assigns: %s" % str(classes_seen))
	print("   catalog `max_ship_class_name` WRONG at %d of %d" % [class_wrong, total])
	for line in class_examples:
		print("      %s" % line)
	print("export-slot counts the trade profile assigns: %s" % str(export_slot_counts))
	print("   catalog `commodity_exports` WRONG at %d of %d" % [exports_wrong, total])
	for line in export_examples:
		print("      %s" % line)
	get_tree().quit(0)


## Register exactly as one of the candidate call sites would. `w14` is
## `world.gd:_setup_ports` as found; `w17` is `port_plot.gd:_register_with_catalog`'s
## argument list, which is the full signature.
func _register(catalog: Node, data: PortData, variant: String) -> void:
	var chart := data.to_chart_dict()
	if variant == "w14":
		catalog.call(
			"register_port",
			data.port_id, data.display_name, data.world_position,
			Vector3(INF, INF, INF),
			data.commodity_export, data.commodity_imports,
			data.island_width, data.plot_depth, data.layout_seed,
			data.population, data.features, data.rotation_y,
			data.berth_count, data.size,
		)
		return
	if variant == "w15":
		catalog.call(
			"register_port",
			data.port_id, data.display_name, data.world_position,
			Vector3(INF, INF, INF),
			data.commodity_export, data.commodity_imports,
			data.island_width, data.plot_depth, data.layout_seed,
			data.population, data.features, data.rotation_y,
			data.berth_count, data.size,
			str(chart.get("region", "")),
		)
		return
	catalog.call(
		"register_port",
		data.port_id, data.display_name, data.world_position,
		Vector3(INF, INF, INF),
		data.commodity_export, data.commodity_imports,
		data.island_width, data.plot_depth, data.layout_seed,
		data.population, data.features, data.rotation_y,
		data.berth_count, data.size,
		str(chart.get("region", "")),
		str(chart.get("max_ship_class_name", "")),
		data.trade_profile.export_slots if data.trade_profile != null else [],
	)


## Re-register the port through the REAL `register_port` with the variant's
## argument list, then drive the REAL `ChartHarbourPlan.resolve_port_data`.
## Unregistered first because `register_port` MERGES with the previous entry when
## an argument is empty — leaving the old entry in place would carry a region word
## forward into the variant that is supposed to be missing it.
func _draw_variant(
		catalog: Node,
		snapshot: ChartDataSnapshot,
		data: PortData,
		source: Dictionary,
		variant: String,
) -> Dictionary:
	var pid := data.port_id
	catalog.call("unregister_port", pid)
	_register(catalog, data, "w14" if variant == "def" else variant)
	if variant == "def":
		var ports: Dictionary = catalog.get("_ports")
		(ports[pid] as Dictionary)["port_definition"] = source
	## Cleared so this draw MUST enter `expand_uncached`: `PortDataCache` would
	## otherwise hand one variant the expansion another variant paid for and the
	## comparison becomes one object against itself.
	PortDataCache.clear()
	ChartHarbourPlan.clear_cache()
	var out_data := ChartHarbourPlan.resolve_port_data(pid, get_tree(), snapshot)
	if out_data == null:
		return {"resolved": false, "forced_misses": 0}
	var out := _digest(ChartHarbourPlan.from_port_data(out_data), out_data)
	out["forced_misses"] = 1 if PortDataCache._cache.size() > 0 else 0
	return out


func _digest(plan: ChartHarbourPlan, data: PortData) -> Dictionary:
	var attrs: Dictionary = {}
	if data.layout_graph != null:
		attrs = data.layout_graph.initial_attributes
	var berth_plan := attrs.get("berth_plan", {}) as Dictionary
	var basin := berth_plan.get("basin", {}) as Dictionary
	return {
		"resolved": true,
		"data_size": int(data.size),
		"data_berth_count": int(data.berth_count),
		"data_max_ship_class": int(data.max_ship_class),
		"data_features": str(data.features),
		"data_population": int(data.population),
		"data_has_lighthouse": bool(data.has_lighthouse),
		"data_has_fog_horn": bool(data.has_fog_horn),
		"data_has_fish_landing": bool(data.has_fish_landing),
		"graph_site_max_size": int(attrs.get("site_max_size", -1)),
		"basin_max_size": int(attrs.get("basin_max_size", -1)),
		"basin_site_max_size": int(basin.get("site_max_size", -1)),
		"berth_notes": str(berth_plan.get("notes", [])),
		"quay_poly_count": plan.quay_polys.size(),
		"asphalt_poly_count": plan.asphalt_polys.size(),
		"land_poly": _pts(plan.land_poly),
		"foundation_poly": _pts(plan.foundation_poly),
		"shore_poly": _pts(plan.shore_poly),
		"dock_face_poly": _pts(plan.dock_face_poly),
		"quay_polys": _poly_list(plan.quay_polys),
		"quay_meta": str(plan.quay_meta),
		"asphalt_polys": _poly_list(plan.asphalt_polys),
		"asphalt_meta": str(plan.asphalt_meta),
		"bounds": [plan.bounds.position.x, plan.bounds.position.y,
			plan.bounds.size.x, plan.bounds.size.y],
		"centre_world": [plan.centre_world().x, plan.centre_world().y],
		"suggested_span_m": plan.suggested_span_m(),
		"world_origin": [plan.world_origin.x, plan.world_origin.y, plan.world_origin.z],
		"rotation_y": plan.rotation_y,
	}


func _pts(poly: PackedVector2Array) -> Array:
	var out: Array = []
	for p in poly:
		out.append([p.x, p.y])
	return out


func _poly_list(polys: Array) -> Array:
	var out: Array = []
	for poly in polys:
		out.append(_pts(poly as PackedVector2Array))
	return out


func _strings(values: Array) -> Array:
	var out: Array = []
	for v in values:
		out.append(str(v))
	return out


## FAILS LOUD on a key missing from either digest rather than skipping it.
func _diff(a: Dictionary, b: Dictionary, keys: Array[String]) -> Dictionary:
	var out: Dictionary = {}
	for key in keys:
		if not a.has(key) or not b.has(key):
			out["MISSING:" + key] = true
			continue
		var av: Variant = a[key]
		var bv: Variant = b[key]
		if typeof(av) == TYPE_ARRAY or typeof(bv) == TYPE_ARRAY:
			if JSON.stringify(av) != JSON.stringify(bv):
				out[str(key)] = true
		elif str(av) != str(bv):
			out[str(key)] = true
	return out
