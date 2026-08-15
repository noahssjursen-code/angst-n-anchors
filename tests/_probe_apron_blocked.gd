extends SceneTree

## Scratch probe (not a test). Why does the apron sprinkle zero service props
## for the port_trade_profile_test fixture?

const LandPlan := preload("res://scripts/port/port_land_plan.gd")
const CoastTracer := preload("res://scripts/port/port_coast_tracer.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var definition := PortDefinition.new()
	definition.port_id = "port-home"
	definition.display_name = "Haugsvik"
	definition.size = 2
	definition.region_kind = PortDefinition.RegionKind.MAINLAND
	definition.port_generation_version = PortDefinition.CURRENT_PORT_GENERATION_VERSION
	definition.site_seed = 991122
	var data := PortExpander.expand(definition, 424242)
	var attrs: Dictionary = data.layout_graph.initial_attributes
	var land: Dictionary = attrs.get("land_plan", {}) as Dictionary
	if land.is_empty():
		print("land_plan missing; keys = %s" % [attrs.keys()])
		quit()
		return

	var foundation: Dictionary = attrs.get("foundation", {}) as Dictionary
	var berth_plan: Dictionary = attrs.get("berth_plan", {}) as Dictionary
	var dock_face: Array = foundation.get("dock_face_polyline", []) as Array
	print("resolved size = %d" % data.size)
	print("dock_face points = %d" % dock_face.size())
	var poly := PackedVector2Array()
	for raw in dock_face:
		var pair: Array = raw
		poly.append(Vector2(float(pair[0]), float(pair[1])))
	var arcs: PackedFloat32Array = CoastTracer.path_arc_lengths(poly)
	var total := float(arcs[arcs.size() - 1]) if not arcs.is_empty() else 0.0
	print("total dock-face arc = %.2f m" % total)
	print("APRON_DECOR_EDGE_PAD_M = %.2f  STEP = %.2f  MIN_SPACING = %.2f" % [
		LandPlan.APRON_DECOR_EDGE_PAD_M,
		LandPlan.APRON_DECOR_STEP_M,
		LandPlan.APRON_DECOR_MIN_SPACING_M,
	])
	print("APRON_STATION_ARC_CLEAR_M = %.2f  APRON_QUAY_RADIUS_CLEAR_M = %.2f" % [
		LandPlan.APRON_STATION_ARC_CLEAR_M,
		LandPlan.APRON_QUAY_RADIUS_CLEAR_M,
	])
	print("asphalt_quay_loading_clearance_m(%d) = %.2f" % [
		data.size, PortSizing.asphalt_quay_loading_clearance_m(data.size),
	])
	print("quay_deck_width_m(%d) = %.2f" % [data.size, PortSizing.quay_deck_width_m(data.size)])

	var quay: Array = berth_plan.get("quay_stations", []) as Array
	var asphalt: Array = berth_plan.get("asphalt_stations", []) as Array
	print("quay_stations = %d  asphalt_stations = %d" % [quay.size(), asphalt.size()])
	var blocked: Array = _blocked_arcs(poly, arcs, berth_plan, data.size)
	print("merged blocked intervals (%d):" % blocked.size())
	var covered := 0.0
	for raw in blocked:
		var iv: Dictionary = raw
		var lo := float(iv["lo"])
		var hi := float(iv["hi"])
		covered += maxf(0.0, minf(hi, total) - maxf(lo, 0.0))
		print("   [%9.2f , %9.2f]  width %.2f" % [lo, hi, hi - lo])
	print("blocked coverage of the [0, %.2f] face = %.2f m (%.1f%%)" % [
		total, covered, 100.0 * covered / maxf(total, 0.001),
	])

	## Which of the two gates rejects each candidate arc?
	var blocked_hits := 0
	var near_hits := 0
	var free := 0
	var arc := LandPlan.APRON_DECOR_EDGE_PAD_M
	while arc < total - LandPlan.APRON_DECOR_EDGE_PAD_M:
		var in_blocked := _in_blocked(blocked, arc)
		if in_blocked:
			blocked_hits += 1
		else:
			var sample: Dictionary = CoastTracer.point_at_arc_s(poly, arcs, arc)
			var face_pos: Vector2 = sample.get("position", Vector2.ZERO)
			if _near_quay(face_pos, berth_plan):
				near_hits += 1
			else:
				free += 1
		arc += 5.0
	print("5 m sweep of the face: blocked=%d near_quay=%d FREE=%d" % [
		blocked_hits, near_hits, free,
	])

	var apron: Dictionary = land.get("apron_decor", {}) as Dictionary
	print("apron_decor point_count = %d" % int(apron.get("point_count", 0)))

	## What the loading clearance is FOR, per its own producer.
	for s in range(0, 5):
		print("  size %d: loading_clear=%.2f quay_w=%.2f" % [
			s, PortSizing.asphalt_quay_loading_clearance_m(s),
			PortSizing.quay_deck_width_m(s),
		])
	quit()


## Mirrors PortLandPlan._apron_blocked_arcs / _arc_in_blocked / _near_quay_station.
## Private statics are not reachable through call(), so the probe restates them.
func _blocked_arcs(
		poly: PackedVector2Array,
		arcs: PackedFloat32Array,
		berth_plan: Dictionary,
		size: int,
) -> Array:
	var out: Array = []
	var loading_clear := PortSizing.asphalt_quay_loading_clearance_m(size)
	for raw in berth_plan.get("quay_stations", []) as Array:
		var station: Dictionary = raw
		var origin_arr: Array = station.get("origin", [0.0, 0.0]) as Array
		var origin := Vector2(float(origin_arr[0]), float(origin_arr[1]))
		var root_arc := _nearest_arc(poly, arcs, origin)
		var half_w := float(station.get("width_m", PortSizing.quay_deck_width_m(size))) * 0.5
		out.append({
			"lo": root_arc - half_w - loading_clear,
			"hi": root_arc + half_w + loading_clear,
			"src": "quay half_w=%.2f clear=%.2f root=%.2f" % [half_w, loading_clear, root_arc],
		})
	for raw in berth_plan.get("asphalt_stations", []) as Array:
		var station: Dictionary = raw
		var arc_m := float(station.get("arc_m", 0.0))
		var half_len := float(station.get("length_m", 0.0)) * 0.5
		out.append({
			"lo": arc_m - half_len - LandPlan.APRON_STATION_ARC_CLEAR_M,
			"hi": arc_m + half_len + LandPlan.APRON_STATION_ARC_CLEAR_M,
			"src": "asphalt half_len=%.2f arc=%.2f" % [half_len, arc_m],
		})
	for raw in out:
		var iv: Dictionary = raw
		print("   raw %s -> [%.2f, %.2f]" % [iv["src"], iv["lo"], iv["hi"]])
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["lo"]) < float(b["lo"])
	)
	var merged: Array = []
	for raw in out:
		var nxt: Dictionary = raw
		if merged.is_empty():
			merged.append(nxt.duplicate())
			continue
		var cur: Dictionary = merged[merged.size() - 1]
		if float(nxt["lo"]) <= float(cur["hi"]) + 1.0:
			cur["hi"] = maxf(float(cur["hi"]), float(nxt["hi"]))
			merged[merged.size() - 1] = cur
		else:
			merged.append(nxt.duplicate())
	return merged


func _in_blocked(blocked: Array, arc_s: float) -> bool:
	for raw in blocked:
		var iv: Dictionary = raw
		if arc_s >= float(iv["lo"]) - 0.5 and arc_s <= float(iv["hi"]) + 0.5:
			return true
	return false


func _near_quay(face_pos: Vector2, berth_plan: Dictionary) -> bool:
	for raw in berth_plan.get("quay_stations", []) as Array:
		var station: Dictionary = raw
		var origin_arr: Array = station.get("origin", [0.0, 0.0]) as Array
		var origin := Vector2(float(origin_arr[0]), float(origin_arr[1]))
		var radius := float(station.get("width_m", 24.0)) * 0.5 + LandPlan.APRON_QUAY_RADIUS_CLEAR_M
		if face_pos.distance_to(origin) < radius:
			return true
	return false


func _nearest_arc(poly: PackedVector2Array, arcs: PackedFloat32Array, point: Vector2) -> float:
	var best := 0.0
	var best_d := INF
	for i in range(poly.size() - 1):
		var a := poly[i]
		var b := poly[i + 1]
		var ab := b - a
		var len_sq := ab.length_squared()
		var t := 0.0 if len_sq <= 0.0 else clampf((point - a).dot(ab) / len_sq, 0.0, 1.0)
		var proj := a + ab * t
		var d := point.distance_to(proj)
		if d < best_d:
			best_d = d
			best = float(arcs[i]) + ab.length() * t
	return best
