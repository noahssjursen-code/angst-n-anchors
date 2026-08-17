extends Node

## Scratch probe (leading underscore — not a gate unit). LANE B, and it has to
## be: `ChartHarbourPlan` names `HarbourRegistry` bare, which reaches
## `harbour_authority_bridge.gd`'s bare `WorldGateway`, so the whole file fails
## to COMPILE under `--script` (CONVENTIONS §2). Measured, not assumed — the
## lane-A attempt printed `Identifier not found: WorldGateway` and then
## `Failed to compile depended scripts` for `chart_harbour_plan.gd`.
##
##   xvfb-run -a --server-args="-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy \
##     res://tests/_chart_live_ceiling_probe.tscn
##
## THE ONE QUESTION: on the LIVE chart (`ChartDataSnapshot.from_live_tree` →
## `PortCatalog`), an unstamped port's silhouette is expanded from a definition
## whose `site_max_size` DEFAULTED to `PortSizing.MAX_SIZE` (8), because
## `register_port` has no such parameter. **Does that defaulted ceiling change
## anything a player sees?**
##
## Method — vary exactly ONE input through the real production function
## (REALITY §4e). `ChartHarbourPlan.resolve_port_data` reads
## `info.get("site_max_size", PortSizing.MAX_SIZE)` off the `PortCatalog` entry.
## Run A leaves the catalog exactly as `world.gd:_setup_ports` registers it (the
## key is absent → 8). Run B injects the world's own resolved ceiling into the
## same catalog entry and nothing else. Same function, same tree, same snapshot.
##
## Run C is the STAMPED harbour — `ChartHarbourPlan.from_port_data` on the
## world's own `PortData`, i.e. what the chart draws once the proximity loader
## has built the PortPlot. A/C is the total live-chart divergence, which is NOT
## the same question and is reported separately.
##
## Runs D and E decompose A/C, so the ceiling is not blamed for someone else's
## defect. D injects the world's `region` WORD as well as the ceiling (both are
## keys `resolve_port_data` reads and `register_port` never writes). E injects the
## whole placed `port_definition` record, which takes the branch the preview path
## takes — if E reproduces C exactly, the live chart's gap is "PortCatalog carries
## no definition", not "the ceiling defaults".
##
## Whole structures are diffed, never sizes or sums (a conclusion was reversed
## this week by a `.size()` comparison): every polygon point, every meta dict,
## the bounds rect, and the graph attributes.
##
## Six seeds x 35 ports, sizes 0-4. No port in this project is above size 4.
##
## ⚠ RUN B IS NOW INERT, AND THAT IS THE FIX LANDING — 2026-08-17. This probe was
## written against the code as found and measured, at 210 ports:
##
##   A vs B, BEFORE the fix   50 of 210 differ — `graph_site_max_size`,
##                            `basin_max_size`, `basin["site_max_size"]` and one
##                            `berth_plan.notes` string. ZERO drawn paths.
##   A vs B, AFTER the fix     0 of 210 differ — the read that consumed the
##                            injected key is deleted, so the injection does
##                            nothing at all.
##   A vs C, both times      133 of 210 differ, on a path table that is
##                            IDENTICAL before and after, which is the evidence
##                            that deleting the read changed no behaviour.
##
## So re-running this probe today cannot re-measure the ceiling's reach through the
## catalog: that door is closed. `chart_live_harbour_test` re-asks the same question
## through the branch that still reads a ceiling (a `port_definition` record), which
## is the counterfactual the deletion rests on.

const GENERATOR := preload("res://scripts/world/world_layout_generator.gd")
const PLACER := preload("res://scripts/world/coastal_port_placer.gd")
const PORT_COUNT := 35
const SEEDS := [424242, 20260817, 90210, 777, 20260816, 31337]


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
	var ceiling_defaulted := 0
	var ceiling_would_differ := 0
	var plan_differs_ab := 0
	var plan_differs_ac := 0
	var attr_differs_ab: Dictionary = {}
	var path_differs_ab: Dictionary = {}
	var path_differs_ac: Dictionary = {}
	var size_differs_ab := 0
	var size_differs_ac := 0
	var span_differs_ab := 0
	var quay_count_differs_ab := 0
	var sizes_seen: Dictionary = {}
	var ceilings_seen: Dictionary = {}
	var unresolved := 0
	var worst_ab: Dictionary = {}
	var worst_ac: Dictionary = {}
	var plan_differs_dc := 0
	var plan_differs_ec := 0
	var path_differs_dc: Dictionary = {}
	var path_differs_ec: Dictionary = {}
	var plan_differs_fc := 0
	var path_differs_fc: Dictionary = {}
	var regions_seen: Dictionary = {}

	for world_seed in SEEDS:
		var seed_int := int(world_seed)
		var layout: WorldLayout = GENERATOR.generate(seed_int)
		var defs: Array = PLACER.place_ports(
			layout, PORT_COUNT, PackedStringArray(WorldPortNames.NAMES))

		## ── the world, exactly as world.gd:_setup_ports does it ──────────────
		catalog.call("clear")
		PortDataCache.clear()
		LandField.initialize(layout)
		FishingField.initialize(seed_int)
		WeatherField.world_seed = seed_int
		WeatherFrontField.initialize(seed_int)

		var world_records: Array = []
		for raw in defs:
			var placed := raw as PortDefinition
			var source := placed.to_dict()
			var world_def := PortDefinition.from_dict(source)
			var world_data := PortExpander.expand(world_def, seed_int, layout)
			catalog.call(
				"register_port",
				world_data.port_id, world_data.display_name, world_data.world_position,
				Vector3(INF, INF, INF),
				world_data.commodity_export, world_data.commodity_imports,
				world_data.island_width,
				world_data.plot_depth,
				world_data.layout_seed,
				world_data.population, world_data.features, world_data.rotation_y,
				world_data.berth_count, world_data.size,
			)
			world_records.append({
				"source": source,
				"placed_ceiling": placed.site_max_size,
				"resolved_ceiling": world_def.site_max_size,
				"resolved_size": world_def.size,
				"data": world_data,
			})

		## ── the live chart snapshot, from the live tree ──────────────────────
		var stub := StubWorld.new()
		stub.name = "ProbeWorld"
		stub.layout = layout
		stub.seed_value = seed_int
		stub.add_to_group("world")
		get_tree().root.add_child(stub)
		var snapshot := ChartDataSnapshot.from_live_tree(get_tree())
		if snapshot.ports.size() != defs.size():
			print("SNAPSHOT SIZE MISMATCH %d vs %d" % [snapshot.ports.size(), defs.size()])

		for i in range(world_records.size()):
			var rec: Dictionary = world_records[i]
			var pid := str((rec["source"] as Dictionary).get("port_id", ""))
			total += 1
			sizes_seen[int(rec["resolved_size"])] = int(sizes_seen.get(int(rec["resolved_size"]), 0)) + 1
			ceilings_seen[int(rec["resolved_ceiling"])] = \
					int(ceilings_seen.get(int(rec["resolved_ceiling"]), 0)) + 1

			var info: Dictionary = catalog.call("get_port_info", pid)
			if not info.has("site_max_size"):
				ceiling_defaulted += 1
			if int(rec["resolved_ceiling"]) != PortSizing.MAX_SIZE:
				ceiling_would_differ += 1

			var region_word := _region_word(int((rec["source"] as Dictionary).get("region_kind", 0)))
			regions_seen[region_word] = int(regions_seen.get(region_word, 0)) + 1
			## RUN A — the catalog as the world registers it. Ceiling defaults.
			var a := _draw_live(pid, snapshot, {}, catalog)
			## RUN B — same call, the resolved ceiling injected. One input varied.
			var b := _draw_live(pid, snapshot,
				{"site_max_size": int(rec["resolved_ceiling"])}, catalog)
			## RUN D — ceiling AND the world's region word.
			var d := _draw_live(pid, snapshot, {
				"site_max_size": int(rec["resolved_ceiling"]),
				"region": region_word,
			}, catalog)
			## RUN F — the region word ALONE, ceiling still defaulted.
			var f := _draw_live(pid, snapshot, {"region": region_word}, catalog)
			## RUN E — the whole placed definition record.
			var e := _draw_live(pid, snapshot,
				{"port_definition": rec["source"]}, catalog)
			## RUN C — the stamped harbour: the world's own PortData.
			var c := _digest(
				ChartHarbourPlan.from_port_data(rec["data"] as PortData),
				rec["data"] as PortData,
			)
			var dc := _diff(d, c)
			if not dc.is_empty():
				plan_differs_dc += 1
				for path3 in dc:
					path_differs_dc[path3] = int(path_differs_dc.get(path3, 0)) + 1
			var fc := _diff(f, c)
			if not fc.is_empty():
				plan_differs_fc += 1
				for path5 in fc:
					path_differs_fc[path5] = int(path_differs_fc.get(path5, 0)) + 1
			var ec := _diff(e, c)
			if not ec.is_empty():
				plan_differs_ec += 1
				for path4 in ec:
					path_differs_ec[path4] = int(path_differs_ec.get(path4, 0)) + 1
			if not bool(a.get("resolved", false)) or not bool(b.get("resolved", false)):
				unresolved += 1
				continue

			var ab := _diff(a, b)
			var ac := _diff(a, c)
			if not ab.is_empty():
				plan_differs_ab += 1
				for path in ab:
					path_differs_ab[path] = int(path_differs_ab.get(path, 0)) + 1
				if worst_ab.is_empty():
					worst_ab = {
						"port": "%d/%s" % [seed_int, pid],
						"paths": ab.keys(),
						"ceiling_a": PortSizing.MAX_SIZE,
						"ceiling_b": int(rec["resolved_ceiling"]),
						"a": a, "b": b,
					}
			if not ac.is_empty():
				plan_differs_ac += 1
				for path2 in ac:
					path_differs_ac[path2] = int(path_differs_ac.get(path2, 0)) + 1
				if worst_ac.is_empty():
					worst_ac = {"port": "%d/%s" % [seed_int, pid], "paths": ac.keys()}
			if int(a["data_size"]) != int(b["data_size"]):
				size_differs_ab += 1
			if int(a["data_size"]) != int(c["data_size"]):
				size_differs_ac += 1
			if not is_equal_approx(float(a["suggested_span_m"]), float(b["suggested_span_m"])):
				span_differs_ab += 1
			if int(a["quay_poly_count"]) != int(b["quay_poly_count"]):
				quay_count_differs_ab += 1
			for key in ["graph_site_max_size", "basin_max_size", "basin_site_max_size", "berth_notes"]:
				if str(a[key]) != str(b[key]):
					attr_differs_ab[key] = int(attr_differs_ab.get(key, 0)) + 1

		print("seed %d: A/B ceiling moved the graph attribute at %d ports so far (cumulative)"
			% [seed_int, int(path_differs_ab.get("graph_site_max_size", 0))])
		get_tree().root.remove_child(stub)
		stub.free()

	print("=== _chart_live_ceiling_probe ===")
	print("ports measured: %d (six seeds x %d), unresolved: %d" % [total, PORT_COUNT, unresolved])
	print("resolved sizes seen: %s" % str(sizes_seen))
	print("resolved geography ceilings seen: %s" % str(ceilings_seen))
	print("catalog entries WITHOUT site_max_size (so the chart defaults to %d): %d of %d"
		% [PortSizing.MAX_SIZE, ceiling_defaulted, total])
	print("ports whose resolved ceiling is NOT %d (i.e. the default is wrong): %d of %d"
		% [PortSizing.MAX_SIZE, ceiling_would_differ, total])
	print("--- A vs B: the defaulted ceiling against the resolved one, one input varied ---")
	print("drawn plans that DIFFER: %d of %d" % [plan_differs_ab, total])
	print("paths that moved: %s" % str(path_differs_ab))
	print("resolved size differs: %d · quay polygon count differs: %d · suggested span differs: %d"
		% [size_differs_ab, quay_count_differs_ab, span_differs_ab])
	print("graph attributes that moved: %s" % str(attr_differs_ab))
	if not worst_ab.is_empty():
		print("first A/B divergence: %s ceiling %s->%s paths=%s" % [
			str(worst_ab["port"]), str(worst_ab["ceiling_a"]), str(worst_ab["ceiling_b"]),
			str(worst_ab["paths"])])
		for p in (worst_ab["paths"] as Array):
			print("   %s: A=%s" % [str(p), str((worst_ab["a"] as Dictionary)[p]).substr(0, 240)])
			print("   %s: B=%s" % [str(p), str((worst_ab["b"] as Dictionary)[p]).substr(0, 240)])
	print("--- A vs C: the live unstamped chart against the STAMPED harbour (different question) ---")
	print("drawn plans that DIFFER: %d of %d" % [plan_differs_ac, total])
	print("resolved size differs: %d" % size_differs_ac)
	print("paths that moved: %s" % str(path_differs_ac))
	if not worst_ac.is_empty():
		print("first A/C divergence: %s paths=%s" % [str(worst_ac["port"]), str(worst_ac["paths"])])
	print("--- decomposition: what actually closes the A/C gap ---")
	print("region words the placer assigned: %s" % str(regions_seen))
	print("D (ceiling + region injected) vs C: DIFFER at %d of %d · paths %s"
		% [plan_differs_dc, total, str(path_differs_dc)])
	print("F (region word ALONE, ceiling still defaulted) vs C: DIFFER at %d of %d · paths %s"
		% [plan_differs_fc, total, str(path_differs_fc)])
	print("E (whole placed port_definition injected) vs C: DIFFER at %d of %d · paths %s"
		% [plan_differs_ec, total, str(path_differs_ec)])
	get_tree().quit(0)


func _region_word(region_kind: int) -> String:
	match region_kind:
		int(PortDefinition.RegionKind.MAINLAND):
			return "mainland"
		int(PortDefinition.RegionKind.FJORD):
			return "fjord"
		int(PortDefinition.RegionKind.ARCHIPELAGO):
			return "archipelago"
	return "coastal"


## Drive the real `ChartHarbourPlan.resolve_port_data` against the live catalog.
## `inject_ceiling` >= 0 writes `site_max_size` into the catalog entry first;
## -1 leaves the entry exactly as `register_port` built it.
func _draw_live(
		port_id: String,
		snapshot: ChartDataSnapshot,
		inject: Dictionary,
		catalog: Node,
) -> Dictionary:
	var ports: Dictionary = catalog.get("_ports")
	var entry := ports[port_id] as Dictionary
	for key in ["site_max_size", "port_definition"]:
		if inject.has(key):
			entry[key] = inject[key]
		else:
			entry.erase(key)
	## `register_port` always writes `region`, defaulted to "coastal", so this one
	## is overwritten rather than erased.
	entry["region"] = str(inject.get("region", "coastal"))
	## Cleared so BOTH runs really enter `expand_uncached`. A cache hit would
	## hand back an expansion the other run paid for and the comparison would be
	## between one PortData and itself.
	PortDataCache.clear()
	ChartHarbourPlan.clear_cache()
	var data := ChartHarbourPlan.resolve_port_data(port_id, get_tree(), snapshot)
	if data == null:
		return {"resolved": false}
	return _digest(ChartHarbourPlan.from_port_data(data), data)


## Whole structure — every point, every meta dict, the bounds rect, the graph
## attributes the ceiling is published into, and the two camera helpers.
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


func _diff(a: Dictionary, b: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var keys: Dictionary = {}
	for k in a:
		keys[k] = true
	for k in b:
		keys[k] = true
	for key in keys:
		var av: Variant = a.get(key, "<absent>")
		var bv: Variant = b.get(key, "<absent>")
		if typeof(av) == TYPE_ARRAY or typeof(bv) == TYPE_ARRAY:
			if JSON.stringify(av) != JSON.stringify(bv):
				out[str(key)] = true
		elif str(av) != str(bv):
			out[str(key)] = true
	return out
