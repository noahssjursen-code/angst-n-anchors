extends SceneTree

## SCRATCH PROBE. Why does `apron_decor` produce fewer than 3 props on the port
## `port_trade_profile_test` uses? Re-walks `PortLandPlan._build_apron_decor`'s
## own loop with the same seed, counting which rule rejected each arc sample.
##
##   xvfb-run -a --server-args="-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy \
##     --script res://tests/_apron_decor_why_probe.gd

const CoastTracer := preload("res://scripts/port/port_coast_tracer.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	PortModuleCatalog.clear_cache()
	## Exactly what port_trade_profile_test expands.
	_report("trade_profile_test port", 2, 991122, 424242)
	## A sweep, so the answer is not one seed's accident.
	var zero := 0
	var under3 := 0
	var total := 0
	for size in range(PortSizing.MAX_SIZE + 1):
		for k in range(12):
			var n := _decor_count(size, 700000 + k * 5171, 424242)
			total += 1
			if n == 0:
				zero += 1
			if n < 3:
				under3 += 1
	print("")
	print("SWEEP %d ports: %d produce ZERO props, %d produce fewer than 3"
		% [total, zero, under3])
	quit(0)


func _decor_count(size: int, site_seed: int, world_seed: int) -> int:
	PortDataCache.clear()
	var definition := PortDefinition.new()
	definition.port_id = "sweep"
	definition.display_name = "SWEEP"
	definition.size = size
	definition.region_kind = PortDefinition.RegionKind.MAINLAND
	definition.site_seed = site_seed
	definition.port_generation_version = PortDefinition.CURRENT_PORT_GENERATION_VERSION
	var data := PortExpander.expand(definition, world_seed)
	var land := data.layout_graph.initial_attributes.get("land_plan", {}) as Dictionary
	return int((land.get("apron_decor", {}) as Dictionary).get("point_count", 0))


func _report(label: String, size: int, site_seed: int, world_seed: int) -> void:
	PortDataCache.clear()
	var definition := PortDefinition.new()
	definition.port_id = "port-home"
	definition.display_name = "Haugsvik"
	definition.size = size
	definition.region_kind = PortDefinition.RegionKind.MAINLAND
	definition.site_seed = site_seed
	definition.port_generation_version = PortDefinition.CURRENT_PORT_GENERATION_VERSION
	var data := PortExpander.expand(definition, world_seed)
	var graph := data.layout_graph
	var foundation := graph.initial_attributes.get("foundation", {}) as Dictionary
	var berth := graph.initial_attributes.get("berth_plan", {}) as Dictionary
	var land := graph.initial_attributes.get("land_plan", {}) as Dictionary
	var decor := land.get("apron_decor", {}) as Dictionary

	var dock_face := _polyline_of(foundation.get("dock_face_polyline", []) as Array)
	if dock_face.size() < 2:
		dock_face = _polyline_of(foundation.get("spine", []) as Array)
	var arc_lengths := CoastTracer.path_arc_lengths(dock_face)
	var total_arc := float(arc_lengths[arc_lengths.size() - 1]) if not arc_lengths.is_empty() else 0.0
	var blocked: Array = PortLandPlan._apron_blocked_arcs(berth)

	print("=== %s (size %d, site_seed %d)" % [label, size, site_seed])
	print("  dock face %.1f m over %d vertices" % [total_arc, dock_face.size()])
	print("  asphalt_stations=%d quay_stations=%d"
		% [
			(berth.get("asphalt_stations", []) as Array).size(),
			(berth.get("quay_stations", []) as Array).size(),
		])
	var blocked_m := 0.0
	for raw in blocked:
		var iv: Dictionary = raw
		var lo := maxf(float(iv["lo"]), 0.0)
		var hi := minf(float(iv["hi"]), total_arc)
		blocked_m += maxf(hi - lo, 0.0)
		print("    blocked arc [%.1f, %.1f]" % [float(iv["lo"]), float(iv["hi"])])
	print("  blocked %.1f m of %.1f m (%.1f%%)"
		% [blocked_m, total_arc, 100.0 * blocked_m / maxf(total_arc, 0.001)])
	for raw in berth.get("quay_stations", []) as Array:
		var st: Dictionary = raw
		var o: Array = st.get("origin", [0.0, 0.0]) as Array
		print("    quay %-30s origin=(%.1f, %.1f) width=%.1f -> keep-out r=%.1f m"
			% [
				str(st.get("id", "?")),
				float(o[0]),
				float(o[1]),
				float(st.get("width_m", 0.0)),
				float(st.get("width_m", 24.0)) * 0.5 + PortLandPlan.APRON_QUAY_RADIUS_CLEAR_M,
			])

	## Re-walk the loop, counting rejections by cause.
	var rng := RandomNumberGenerator.new()
	rng.seed = int(site_seed) ^ 0xA70A40A1
	var placed: Array[Vector2] = []
	var rej_blocked := 0
	var rej_quay := 0
	var rej_spacing := 0
	var kept := 0
	var arc := PortLandPlan.APRON_DECOR_EDGE_PAD_M + rng.randf_range(0.0, 6.0)
	var town_inland := float(foundation.get("town_inland_m", CoastTracer.FOUNDATION_TOWN_INLAND_M))
	var inland_max := maxf(
		town_inland * PortLandPlan.APRON_DECOR_INLAND_MAX_FRAC,
		PortLandPlan.APRON_DECOR_INLAND_MIN_M + 10.0,
	)
	var first_kept := -1.0
	var last_kept := -1.0
	while arc < total_arc - PortLandPlan.APRON_DECOR_EDGE_PAD_M:
		if PortLandPlan._arc_in_blocked(blocked, arc):
			rej_blocked += 1
			arc += PortLandPlan.APRON_DECOR_STEP_M * 0.45
			continue
		var sample := CoastTracer.point_at_arc_s(dock_face, arc_lengths, arc)
		var face_pos: Vector2 = sample.get("position", Vector2.ZERO)
		if PortLandPlan._near_quay_station(face_pos, berth):
			rej_quay += 1
			arc += PortLandPlan.APRON_DECOR_STEP_M
			continue
		var kind := PortLandPlan._pick_apron_kind(rng, data.trade_profile)
		var inland_dist := lerpf(PortLandPlan.APRON_DECOR_INLAND_MIN_M, inland_max, rng.randf())
		match kind:
			PortLandPlan.APRON_KIND_LAMP:
				inland_dist = town_inland * 0.30 + rng.randf_range(-3.0, 3.0)
			PortLandPlan.APRON_KIND_HATCH:
				inland_dist = town_inland * 0.24 + rng.randf_range(-2.0, 2.0)
			PortLandPlan.APRON_KIND_SIGN:
				inland_dist = town_inland * 0.38 + rng.randf_range(-4.0, 4.0)
		inland_dist = clampf(inland_dist, PortLandPlan.APRON_DECOR_INLAND_MIN_M, inland_max)
		var local_pos := face_pos + CoastTracer.PORT_LOCAL_INLAND_DIR * inland_dist
		var too_close := false
		for other in placed:
			if local_pos.distance_to(other) < PortLandPlan.APRON_DECOR_MIN_SPACING_M:
				too_close = true
				break
		if too_close:
			rej_spacing += 1
			arc += PortLandPlan.APRON_DECOR_STEP_M * 0.55
			continue
		var _family := PortLandPlan._pick_apron_family(rng, data.trade_profile)
		kept += 1
		if first_kept < 0.0:
			first_kept = arc
		last_kept = arc
		placed.append(local_pos)
		arc += PortLandPlan.APRON_DECOR_STEP_M + rng.randf_range(-4.0, 4.0)

	print("  loop: kept=%d  rejected: blocked-arc=%d  near-quay=%d  min-spacing=%d"
		% [kept, rej_blocked, rej_quay, rej_spacing])
	print("  kept props span arc %.1f m .. %.1f m of %.1f m" % [first_kept, last_kept, total_arc])
	print("  PLAN REPORTS point_count = %d  (check wants >= 3)"
		% int(decor.get("point_count", 0)))
	for raw in decor.get("points", []) as Array:
		var p: Dictionary = raw
		print("    prop %-12s local=%s" % [str(p.get("kind", "")), str(p.get("local", []))])


func _polyline_of(raw: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for entry in raw:
		var arr := entry as Array
		if arr != null and arr.size() >= 2:
			out.append(Vector2(float(arr[0]), float(arr[1])))
	return out
