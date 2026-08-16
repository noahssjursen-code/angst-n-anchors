extends SceneTree

## SCRATCH PROBE — ASK WHAT THE FIXTURES DO NOT CONTAIN.
##
## `port_berth_plan_test` expands nine synthetic ports with NO WorldLayout, so
## `soft_cap` is false, `basin.max_arm_m` is INF, and the arm-shortening /
## spacing-compression branch in `port_berth_plan.gd` — the ONLY branch that can
## push two piers together — is never taken. The check that says "no two decks
## overlap" has therefore never seen the code that could make them overlap.
## Measure the terrain-traced path before deciding whether the test should carry it.

const WORLD_LAYOUT_GENERATOR := preload("res://scripts/world/world_layout_generator.gd")
const SEED := 424242


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	PortModuleCatalog.clear_cache()
	var layout: Variant = WORLD_LAYOUT_GENERATOR.generate(SEED)
	for size in range(PortSizing.MAX_SIZE + 1):
		var d := PortDefinition.new()
		d.port_id = "terrain-%d" % size
		d.display_name = "TERRAIN %d" % size
		d.size = size
		d.region_kind = PortDefinition.RegionKind.MAINLAND
		d.site_seed = SEED ^ (size * 9973)
		d.port_generation_version = PortDefinition.CURRENT_PORT_GENERATION_VERSION
		d.world_position = Vector3(12000.0, 0.0, -8000.0)
		d.rotation_y = 0.4
		d.has_explicit_rotation = true
		var graph := PortExpander.expand(d, SEED, layout).layout_graph
		var plan := graph.initial_attributes.get("berth_plan", {}) as Dictionary
		var basin := plan.get("basin", {}) as Dictionary
		var stations: Array = plan.get("quay_stations", []) as Array
		var rects: Array = []
		for raw in stations:
			var s := raw as Dictionary
			rects.append({
				"id": str(s.get("id", "")),
				"o": _v(s.get("origin", [])),
				"t": _v(s.get("tip", [])),
				"w": float(s.get("width_m", 0.0)),
				"len": float(s.get("length_m", 0.0)),
			})
		var overlaps := 0
		var worst := 0.0
		var drift := 0.0
		for i in range(rects.size()):
			drift = maxf(drift, absf((rects[i]["o"] as Vector2).distance_to(rects[i]["t"] as Vector2)
				- float(rects[i]["len"])))
			for j in range(i + 1, rects.size()):
				var pen := _overlap_m(rects[i], rects[j])
				if pen > 0.0:
					overlaps += 1
					worst = maxf(worst, pen)
					print("    OVERLAP %s x %s by %.3f m" % [rects[i]["id"], rects[j]["id"], pen])
		print("size=%d stations=%d max_arm_m=%s probe_failed=%s | overlaps=%d worst=%.3f m | tip-length drift=%.5f m | primary=%.2f longest=%.2f"
			% [size, rects.size(), str(basin.get("max_arm_m", "?")), str(basin.get("probe_failed", "?")),
				overlaps, worst, drift,
				float(graph.primary_quay_pose().get("length_m", 0.0)), _longest(rects)])
	quit(0)


func _longest(rects: Array) -> float:
	var best := 0.0
	for r in rects:
		best = maxf(best, float(r["len"]))
	return best


func _v(raw: Variant) -> Vector2:
	var arr := raw as Array
	if arr == null or arr.size() < 2:
		return Vector2.ZERO
	return Vector2(float(arr[0]), float(arr[1]))


func _corners(rect: Dictionary) -> Array:
	var o := rect["o"] as Vector2
	var t := rect["t"] as Vector2
	var axis := t - o
	if axis.length() < 0.0001:
		axis = Vector2(0.0, 1.0)
	axis = axis.normalized()
	var across := Vector2(-axis.y, axis.x) * (float(rect["w"]) * 0.5)
	return [o - across, o + across, t + across, t - across]


func _overlap_m(a: Dictionary, b: Dictionary) -> float:
	var ca := _corners(a)
	var cb := _corners(b)
	var least := INF
	for quad in [ca, cb]:
		for i in range(4):
			var p1 := quad[i] as Vector2
			var p2 := quad[(i + 1) % 4] as Vector2
			var normal := Vector2(-(p2.y - p1.y), p2.x - p1.x)
			if normal.length() < 0.0001:
				continue
			normal = normal.normalized()
			var a_lo := INF
			var a_hi := -INF
			for c in ca:
				var p := normal.dot(c as Vector2)
				a_lo = minf(a_lo, p)
				a_hi = maxf(a_hi, p)
			var b_lo := INF
			var b_hi := -INF
			for c2 in cb:
				var p2v := normal.dot(c2 as Vector2)
				b_lo = minf(b_lo, p2v)
				b_hi = maxf(b_hi, p2v)
			var gap := minf(a_hi, b_hi) - maxf(a_lo, b_lo)
			if gap <= 0.0:
				return 0.0
			least = minf(least, gap)
	return 0.0 if least == INF else least
