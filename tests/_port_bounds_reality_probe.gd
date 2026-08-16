extends SceneTree

## SCRATCH PROBE — leading underscore, the gate must not score it.
##
##   xvfb-run -a --server-args="-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy \
##     --script res://tests/_port_bounds_reality_probe.gd
##
## Question: does `PortLayoutGraph.bounds()` contain the piers the game DRAWS,
## and if not, what do its two consumers do with the short number?
##
## The pier extents here are NOT read from `berth_plan.quay_stations[].tip`.
## They are read off the nodes `PortLayoutGraphVisualizer` actually stamps —
## `BerthTerminals/*/QuayPier/Deck`, a MeshInstance3D whose global transform and
## mesh AABB are the pier as it appears in the world. That is a second,
## independent derivation (REALITY.md §3b), and the probe also prints the
## station-dict tips beside it so the two can be compared.

const SEED := 424242
## berth_approach_lanes.gd:24
const LAND_PAD_M := IslandMeshBuilder.MARGIN + IslandMeshBuilder.AMPLITUDE


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	PortModuleCatalog.clear_cache()
	var world := Node3D.new()
	root.add_child(world)
	print("LAND_PAD_M=%.1f  PLOT_DEPTH_M=%.1f" % [LAND_PAD_M, PortSizing.PLOT_DEPTH_M])
	for size in range(PortSizing.MAX_SIZE + 1):
		await _measure(world, size)
	quit(0)


func _measure(world: Node3D, size: int) -> void:
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
	var data := PortExpander.expand(d, SEED)
	var graph := data.layout_graph

	var visualizer := PortLayoutGraphVisualizer.new()
	world.add_child(visualizer)
	visualizer.configure(graph)
	await process_frame

	## ── DRAWN pier decks, straight off the stamped nodes ────────────────────
	var decks: Array = []
	var terminals := visualizer.find_child("BerthTerminals", true, false)
	if terminals != null:
		_collect_decks(terminals, decks)
	var drawn_lo := Vector2(INF, INF)
	var drawn_hi := Vector2(-INF, -INF)
	for deck in decks:
		for corner in deck["corners"]:
			var p := corner as Vector2
			drawn_lo.x = minf(drawn_lo.x, p.x)
			drawn_lo.y = minf(drawn_lo.y, p.y)
			drawn_hi.x = maxf(drawn_hi.x, p.x)
			drawn_hi.y = maxf(drawn_hi.y, p.y)

	print("\n=== size %d : %d drawn pier decks ===" % [size, decks.size()])
	var stations: Array = (graph.initial_attributes.get("berth_plan", {}) as Dictionary) \
			.get("quay_stations", []) as Array
	for deck in decks:
		print("    DRAWN %-22s centre=(%8.2f,%8.2f) len=%7.2f wid=%6.2f  tipA=(%8.2f,%8.2f) tipB=(%8.2f,%8.2f)"
			% [str(deck["name"]), deck["centre"].x, deck["centre"].y,
				deck["length"], deck["width"],
				deck["tip_a"].x, deck["tip_a"].y, deck["tip_b"].x, deck["tip_b"].y])
	for raw in stations:
		var s := raw as Dictionary
		print("    PLAN  %-22s origin=(%8.2f,%8.2f) tip=(%8.2f,%8.2f) len=%7.2f wid=%6.2f"
			% [str(s.get("id", "")), _v(s.get("origin", [])).x, _v(s.get("origin", [])).y,
				_v(s.get("tip", [])).x, _v(s.get("tip", [])).y,
				float(s.get("length_m", 0.0)), float(s.get("width_m", 0.0))])

	## ── bounds() vs drawn ───────────────────────────────────────────────────
	var b := graph.bounds()
	var b_lo := Vector2(b.position.x, b.position.z)
	var b_hi := Vector2(b.position.x + b.size.x, b.position.z + b.size.z)
	var outside := 0
	var worst := 0.0
	var worst_where := ""
	for deck in decks:
		for corner in deck["corners"]:
			var c := corner as Vector2
			var dx := maxf(maxf(b_lo.x - c.x, c.x - b_hi.x), 0.0)
			var dz := maxf(maxf(b_lo.y - c.y, c.y - b_hi.y), 0.0)
			var out := maxf(dx, dz)
			if out > 0.0:
				outside += 1
				if out > worst:
					worst = out
					worst_where = str(deck["name"])
	print("    bounds()  x[%8.2f..%8.2f] z[%8.2f..%8.2f]  size=(%.2f x %.2f)"
		% [b_lo.x, b_hi.x, b_lo.y, b_hi.y, b.size.x, b.size.z])
	print("    drawn     x[%8.2f..%8.2f] z[%8.2f..%8.2f]  size=(%.2f x %.2f)"
		% [drawn_lo.x, drawn_hi.x, drawn_lo.y, drawn_hi.y,
			drawn_hi.x - drawn_lo.x, drawn_hi.y - drawn_lo.y])
	print("    DRAWN CORNERS OUTSIDE bounds() = %d of %d   worst overhang = %.2f m  (%s)"
		% [outside, decks.size() * 4, worst, worst_where])
	print("    per-axis shortfall: -x=%.2f +x=%.2f -z=%.2f +z=%.2f"
		% [maxf(b_lo.x - drawn_lo.x, 0.0), maxf(drawn_hi.x - b_hi.x, 0.0),
			maxf(b_lo.y - drawn_lo.y, 0.0), maxf(drawn_hi.y - b_hi.y, 0.0)])

	## ── consumer 1: port_expander plot sizing ────────────────────────────────
	var iw := maxf(b.size.x + 36.0, PortSizing.island_width_m(size))
	var pd := maxf(b.size.z + 36.0, PortSizing.PLOT_DEPTH_M)
	## Same formula against a bounds() that DID contain the drawn piers.
	var fixed_lo := Vector2(minf(b_lo.x, drawn_lo.x), minf(b_lo.y, drawn_lo.y))
	var fixed_hi := Vector2(maxf(b_hi.x, drawn_hi.x), maxf(b_hi.y, drawn_hi.y))
	var iw_fixed := maxf(fixed_hi.x - fixed_lo.x + 36.0, PortSizing.island_width_m(size))
	var pd_fixed := maxf(fixed_hi.y - fixed_lo.y + 36.0, PortSizing.PLOT_DEPTH_M)
	print("    island_width  now=%8.2f   with piers=%8.2f   short by %8.2f m"
		% [iw, iw_fixed, iw_fixed - iw])
	print("    plot_depth    now=%8.2f   with piers=%8.2f   short by %8.2f m"
		% [pd, pd_fixed, pd_fixed - pd])

	## ── consumer 1b: the island keep-out box those two numbers build ────────
	## berth_approach_lanes centres the box on data.world_position (0,0,0 here)
	## and asks for half_x/half_z. Are the DRAWN piers inside it?
	var half_x := iw * 0.5 + LAND_PAD_M
	var half_z := pd * 0.5 + LAND_PAD_M
	var pier_out_x := maxf(maxf(-half_x - drawn_lo.x, drawn_hi.x - half_x), 0.0)
	var pier_out_z := maxf(maxf(-half_z - drawn_lo.y, drawn_hi.y - half_z), 0.0)
	print("    keep-out box  half_x=%.2f half_z=%.2f  -> pier outside by x=%.2f z=%.2f m"
		% [half_x, half_z, pier_out_x, pier_out_z])
	## Approach waypoints, port-local, from berth_approach_lanes.
	var spine := Vector2(0.0, -half_z - 70.0)
	var flank_p := [
		Vector2(half_x + 55.0, -half_z + 15.0),
		Vector2(half_x + 55.0, 50.0),
		Vector2(half_x + 55.0, half_z + 85.0),
	]
	var flank_s := [
		Vector2(-half_x - 55.0, -half_z + 15.0),
		Vector2(-half_x - 55.0, 50.0),
		Vector2(-half_x - 55.0, half_z + 85.0),
	]
	var hits := 0
	var worst_pen := 0.0
	for node_set in [[spine], flank_p, flank_s]:
		for raw_node in node_set:
			var node := raw_node as Vector2
			for deck in decks:
				var pen := _point_penetration(node, deck["corners"] as Array)
				if pen > 0.0:
					hits += 1
					worst_pen = maxf(worst_pen, pen)
					print("    LANE NODE (%8.2f,%8.2f) IS INSIDE DRAWN PIER %s by %.2f m"
						% [node.x, node.y, str(deck["name"]), pen])
	## And how close does the outermost node come to a pier tip?
	var min_clear := INF
	for node_set2 in [[spine], flank_p, flank_s]:
		for raw_node2 in node_set2:
			var node2 := raw_node2 as Vector2
			for deck in decks:
				min_clear = minf(min_clear, _point_distance(node2, deck["corners"] as Array))
	print("    lane nodes inside a drawn pier = %d ; nearest lane node to any pier = %.2f m"
		% [hits, min_clear])

	## ── consumer 2: the floating name label ─────────────────────────────────
	var label_c := b.get_center()
	var drawn_centre := (drawn_lo + drawn_hi) * 0.5
	var true_lo := fixed_lo
	var true_hi := fixed_hi
	var true_centre := (true_lo + true_hi) * 0.5
	var span := maxf(true_hi.x - true_lo.x, true_hi.y - true_lo.y)
	print("    label at bounds centre=(%8.2f,%8.2f) ; centre incl. piers=(%8.2f,%8.2f) ; off by %.2f m (%.1f%% of the %.0f m span)"
		% [label_c.x, label_c.z, true_centre.x, true_centre.y,
			Vector2(label_c.x, label_c.z).distance_to(true_centre),
			100.0 * Vector2(label_c.x, label_c.z).distance_to(true_centre) / maxf(span, 0.001),
			span])
	print("    (drawn-pier centre alone = (%8.2f,%8.2f))" % [drawn_centre.x, drawn_centre.y])

	visualizer.queue_free()
	await process_frame


## Every `QuayPier/Deck` MeshInstance3D under the berth terminals, in world XZ.
func _collect_decks(node: Node, out: Array) -> void:
	if node is MeshInstance3D and node.name == "Deck" \
			and node.get_parent() != null and node.get_parent().name == "QuayPier":
		var mi := node as MeshInstance3D
		var aabb := mi.get_aabb()
		var xf := mi.global_transform
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		var corners: Array = []
		for i in range(8):
			var p := xf * aabb.get_endpoint(i)
			var q := Vector2(p.x, p.z)
			lo.x = minf(lo.x, q.x)
			lo.y = minf(lo.y, q.y)
			hi.x = maxf(hi.x, q.x)
			hi.y = maxf(hi.y, q.y)
		## The four XZ corners of the oriented slab (y ignored).
		var half := Vector3(aabb.size.x, 0.0, aabb.size.z) * 0.5
		var centre_local := aabb.get_center()
		for local_raw in [
			Vector3(-half.x, 0.0, -half.z),
			Vector3(half.x, 0.0, -half.z),
			Vector3(half.x, 0.0, half.z),
			Vector3(-half.x, 0.0, half.z),
		]:
			var w := xf * (centre_local + (local_raw as Vector3))
			corners.append(Vector2(w.x, w.z))
		var centre_world := xf * centre_local
		var axis := (xf.basis * Vector3(0.0, 0.0, 1.0)).normalized()
		var half_len := aabb.size.z * 0.5
		out.append({
			"name": str(mi.get_parent().get_parent().name),
			"corners": corners,
			"centre": Vector2(centre_world.x, centre_world.z),
			"length": aabb.size.z,
			"width": aabb.size.x,
			"tip_a": Vector2(centre_world.x, centre_world.z)
					+ Vector2(axis.x, axis.z) * half_len,
			"tip_b": Vector2(centre_world.x, centre_world.z)
					- Vector2(axis.x, axis.z) * half_len,
		})
	for child in node.get_children():
		_collect_decks(child, out)


func _v(raw: Variant) -> Vector2:
	var arr := raw as Array
	if arr == null or arr.size() < 2:
		return Vector2.ZERO
	return Vector2(float(arr[0]), float(arr[1]))


## Depth of `point` inside a convex quad, 0 when outside.
func _point_penetration(point: Vector2, quad: Array) -> float:
	var least := INF
	for i in range(quad.size()):
		var a := quad[i] as Vector2
		var b := quad[(i + 1) % quad.size()] as Vector2
		var edge := b - a
		var normal := Vector2(-edge.y, edge.x).normalized()
		var d := normal.dot(point - a)
		if d > 0.0:
			return 0.0
		least = minf(least, -d)
	return least


## Distance from `point` to the quad boundary (0 when inside).
func _point_distance(point: Vector2, quad: Array) -> float:
	if _point_penetration(point, quad) > 0.0:
		return 0.0
	var best := INF
	for i in range(quad.size()):
		var a := quad[i] as Vector2
		var b := quad[(i + 1) % quad.size()] as Vector2
		var ab := b - a
		var t := clampf((point - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		best = minf(best, point.distance_to(a + ab * t))
	return best
