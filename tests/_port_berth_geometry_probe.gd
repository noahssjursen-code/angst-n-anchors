extends SceneTree

## SCRATCH PROBE — measure before asserting. The properties I am considering
## turning into a gate test, over every size, so I find out which of them are
## true before a check claims they are.
##
##   xvfb-run -a --server-args="-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy \
##     --script res://tests/_port_berth_geometry_probe.gd

const SEED := 424242


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	PortModuleCatalog.clear_cache()
	for size in range(PortSizing.MAX_SIZE + 1):
		var d := PortDefinition.new()
		d.port_id = "capture-%d" % size
		d.display_name = "SIZE %d" % size
		d.size = size
		d.region_kind = PortDefinition.RegionKind.MAINLAND
		d.site_seed = SEED ^ (size * 9973)
		d.has_lighthouse = size >= 2
		d.has_fog_horn = size >= 1
		d.port_generation_version = PortDefinition.CURRENT_PORT_GENERATION_VERSION
		d.ground_mode = PortDefinition.GroundMode.LOCAL_ISLAND
		var graph := PortExpander.expand(d, SEED).layout_graph
		var plan := graph.initial_attributes.get("berth_plan", {}) as Dictionary
		var stations: Array = plan.get("quay_stations", []) as Array
		print("--- size %d: %d stations, quay_count=%s"
			% [size, stations.size(), str(plan.get("quay_count", "?"))])
		var longest := 0.0
		var rects: Array = []
		for raw in stations:
			var s := raw as Dictionary
			var origin := _v(s.get("origin", []))
			var tip := _v(s.get("tip", []))
			var length_m := float(s.get("length_m", 0.0))
			var width_m := float(s.get("width_m", 0.0))
			var span := origin.distance_to(tip)
			longest = maxf(longest, length_m)
			rects.append({"o": origin, "t": tip, "w": width_m, "id": str(s.get("id", ""))})
			print("    %-28s length_m=%8.3f  |tip-origin|=%8.3f  delta=%9.5f  width=%6.2f  berths=%s"
				% [str(s.get("id", "")), length_m, span, span - length_m, width_m,
					str(s.get("berth_faces", "?"))])
		var pose := graph.primary_quay_pose()
		print("    primary_quay_pose.length_m=%.3f   longest station=%.3f   equal=%s"
			% [float(pose.get("length_m", 0.0)), longest,
				str(is_equal_approx(float(pose.get("length_m", 0.0)), longest))])
		## Do the drawn decks overlap? SAT on the two oriented rectangles.
		var overlaps := 0
		for i in range(rects.size()):
			for j in range(i + 1, rects.size()):
				var pen := _overlap_m(rects[i], rects[j])
				if pen > 0.0:
					overlaps += 1
					print("    OVERLAP %s x %s by %.3f m"
						% [rects[i]["id"], rects[j]["id"], pen])
		print("    overlapping deck pairs=%d of %d" % [overlaps, rects.size() * (rects.size() - 1) / 2])
		var b := graph.bounds()
		var outside := 0
		var worst_out := 0.0
		for rect in rects:
			for corner in _corners(rect):
				var c := corner as Vector2
				var dx := maxf(maxf(b.position.x - c.x, c.x - (b.position.x + b.size.x)), 0.0)
				var dz := maxf(maxf(b.position.z - c.y, c.y - (b.position.z + b.size.z)), 0.0)
				if dx > 0.0 or dz > 0.0:
					outside += 1
					worst_out = maxf(worst_out, maxf(dx, dz))
		print("    graph.bounds() x[%.0f..%.0f] z[%.0f..%.0f]  pier corners outside=%d worst=%.1f m  open_slots=%d"
			% [b.position.x, b.position.x + b.size.x, b.position.z, b.position.z + b.size.z,
				outside, worst_out, graph.open_slots().size()])
	quit(0)


func _v(raw: Variant) -> Vector2:
	var arr := raw as Array
	if arr == null or arr.size() < 2:
		return Vector2.ZERO
	return Vector2(float(arr[0]), float(arr[1]))


## Corners of a pier deck: the origin→tip run, `width_m` across.
func _corners(rect: Dictionary) -> Array:
	var o: Vector2 = rect["o"]
	var t: Vector2 = rect["t"]
	var axis := (t - o)
	if axis.length() < 0.0001:
		axis = Vector2(0.0, 1.0)
	axis = axis.normalized()
	var across := Vector2(-axis.y, axis.x) * (float(rect["w"]) * 0.5)
	return [o - across, o + across, t + across, t - across]


## Separating-axis penetration depth in metres; 0 when the decks are disjoint.
func _overlap_m(a: Dictionary, b: Dictionary) -> float:
	var ca := _corners(a)
	var cb := _corners(b)
	var least := INF
	for quad in [ca, cb]:
		for i in range(4):
			var p1: Vector2 = quad[i]
			var p2: Vector2 = quad[(i + 1) % 4]
			var normal := Vector2(-(p2.y - p1.y), p2.x - p1.x).normalized()
			var a_lo := INF
			var a_hi := -INF
			for corner in ca:
				var proj: float = normal.dot(corner as Vector2)
				a_lo = minf(a_lo, proj)
				a_hi = maxf(a_hi, proj)
			var b_lo := INF
			var b_hi := -INF
			for corner2 in cb:
				var proj2: float = normal.dot(corner2 as Vector2)
				b_lo = minf(b_lo, proj2)
				b_hi = maxf(b_hi, proj2)
			var gap := minf(a_hi, b_hi) - maxf(a_lo, b_lo)
			if gap <= 0.0:
				return 0.0
			least = minf(least, gap)
	return least
