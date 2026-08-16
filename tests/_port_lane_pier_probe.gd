extends SceneTree

## SCRATCH PROBE — leading underscore, the gate must not score it.
##
##   xvfb-run -a --server-args="-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy \
##     --script res://tests/_port_lane_pier_probe.gd
##
## Consumer severity for the short `PortLayoutGraph.bounds()`.
## `port_expander` sizes `plot_depth` off it; `berth_approach_lanes` turns that
## into the island keep-out half-extent every approach lane is routed around.
## So: bake the REAL lanes through `BerthApproachLanes.bake_from_port_data`,
## then ask how much lane polyline lies inside a pier the visualizer DRAWS —
## once with the shipped `plot_depth`, once with `plot_depth` recomputed from a
## bounds that contains the piers. The difference is what the defect costs.

const SEED := 424242


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	PortModuleCatalog.clear_cache()
	LandField.initialize([])
	var world := Node3D.new()
	root.add_child(world)
	print("land_field_initialized=%s" % str(LandField.is_initialized()))
	print("size | plot_depth | lanes | segs_in_pier | worst_chord_m | max_depth_in_pier_m")
	for size in range(PortSizing.MAX_SIZE + 1):
		await _one(world, size)
	quit(0)


func _one(world: Node3D, size: int) -> void:
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
	## Port sits at the world origin with zero yaw, so port-local == world XZ
	## and the drawn visualizer nodes are directly comparable to lane points.
	data.world_position = Vector3.ZERO
	data.rotation_y = 0.0

	var graph := data.layout_graph
	var visualizer := PortLayoutGraphVisualizer.new()
	world.add_child(visualizer)
	visualizer.configure(graph)
	await process_frame
	var decks: Array = []
	var terminals := visualizer.find_child("BerthTerminals", true, false)
	if terminals != null:
		_collect_decks(terminals, decks)

	## Corrected plot_depth: the same expander formula over a bounds that also
	## covers every drawn deck corner.
	var b := graph.bounds()
	var lo := Vector2(b.position.x, b.position.z)
	var hi := Vector2(b.position.x + b.size.x, b.position.z + b.size.z)
	for deck in decks:
		for raw in deck["corners"]:
			var c := raw as Vector2
			lo.x = minf(lo.x, c.x)
			lo.y = minf(lo.y, c.y)
			hi.x = maxf(hi.x, c.x)
			hi.y = maxf(hi.y, c.y)
	var shipped_depth := data.plot_depth
	var fixed_depth := maxf(hi.y - lo.y + 36.0, PortSizing.PLOT_DEPTH_M)
	var shipped_width := data.island_width
	var fixed_width := maxf(hi.x - lo.x + 36.0, PortSizing.island_width_m(size))

	var shipped := _bake_and_score(data, decks, shipped_width, shipped_depth, "SHIPPED")
	var fixed := _bake_and_score(data, decks, fixed_width, fixed_depth, "FIXED  ")
	print("size %d  plot_depth %7.1f -> %7.1f | island_width %7.1f -> %7.1f"
		% [size, shipped_depth, fixed_depth, shipped_width, fixed_width])
	print("    SHIPPED lanes=%d segments_crossing_pier=%d worst_chord=%7.2f m deepest=%6.2f m"
		% [shipped["lanes"], shipped["hits"], shipped["chord"], shipped["depth"]])
	print("    FIXED   lanes=%d segments_crossing_pier=%d worst_chord=%7.2f m deepest=%6.2f m"
		% [fixed["lanes"], fixed["hits"], fixed["chord"], fixed["depth"]])

	visualizer.queue_free()
	await process_frame


func _bake_and_score(
		data: PortData,
		decks: Array,
		width: float,
		depth: float,
		_label: String,
) -> Dictionary:
	data.island_width = width
	data.plot_depth = depth
	_reset_lanes()
	BerthApproachLanes.bake_from_port_data(data)
	var polylines := BerthApproachLanes.collect_debug_polylines()
	var hits := 0
	var worst_chord := 0.0
	var deepest := 0.0
	var lanes := 0
	for raw in polylines:
		var entry := raw as Dictionary
		var pts: Array = entry.get("points", []) as Array
		lanes += 1
		for i in range(pts.size() - 1):
			var a3 := pts[i] as Vector3
			var b3 := pts[i + 1] as Vector3
			var a := Vector2(a3.x, a3.z)
			var b := Vector2(b3.x, b3.z)
			for deck in decks:
				var chord := _chord_inside(a, b, deck["corners"] as Array)
				if chord > 0.01:
					hits += 1
					worst_chord = maxf(worst_chord, chord)
			for raw_pt in [a, b]:
				for deck2 in decks:
					deepest = maxf(deepest, _penetration(raw_pt as Vector2, deck2["corners"] as Array))
	return {"lanes": lanes, "hits": hits, "chord": worst_chord, "depth": deepest}


func _reset_lanes() -> void:
	## No public reset; the statics are the only handle and bake_from_port_data
	## refuses a port that is already live-baked.
	BerthApproachLanes.bake_all_ports([], 0)


func _collect_decks(node: Node, out: Array) -> void:
	if node is MeshInstance3D and node.name == "Deck" \
			and node.get_parent() != null and node.get_parent().name == "QuayPier":
		var mi := node as MeshInstance3D
		var aabb := mi.get_aabb()
		var xf := mi.global_transform
		var half := Vector3(aabb.size.x, 0.0, aabb.size.z) * 0.5
		var centre_local := aabb.get_center()
		var corners: Array = []
		for local_raw in [
			Vector3(-half.x, 0.0, -half.z),
			Vector3(half.x, 0.0, -half.z),
			Vector3(half.x, 0.0, half.z),
			Vector3(-half.x, 0.0, half.z),
		]:
			var w := xf * (centre_local + (local_raw as Vector3))
			corners.append(Vector2(w.x, w.z))
		out.append({"name": str(mi.get_parent().get_parent().name), "corners": corners})
	for child in node.get_children():
		_collect_decks(child, out)


## Length of segment a→b that lies inside the convex quad (0 when disjoint).
func _chord_inside(a: Vector2, b: Vector2, quad: Array) -> float:
	var t0 := 0.0
	var t1 := 1.0
	var dir := b - a
	for i in range(quad.size()):
		var p := quad[i] as Vector2
		var q := quad[(i + 1) % quad.size()] as Vector2
		var edge := q - p
		var normal := Vector2(-edge.y, edge.x)
		var denom := normal.dot(dir)
		var dist := normal.dot(a - p)
		if absf(denom) < 0.000001:
			if dist > 0.0:
				return 0.0
			continue
		var t := -dist / denom
		if denom > 0.0:
			t1 = minf(t1, t)
		else:
			t0 = maxf(t0, t)
		if t0 > t1:
			return 0.0
	return maxf(t1 - t0, 0.0) * dir.length()


func _penetration(point: Vector2, quad: Array) -> float:
	var least := INF
	for i in range(quad.size()):
		var a := quad[i] as Vector2
		var b := quad[(i + 1) % quad.size()] as Vector2
		var edge := b - a
		var normal := Vector2(-edge.y, edge.x).normalized()
		var dv := normal.dot(point - a)
		if dv > 0.0:
			return 0.0
		least = minf(least, -dv)
	return least
