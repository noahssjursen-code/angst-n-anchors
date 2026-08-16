extends SceneTree

## SCRATCH PROBE — leading underscore, the gate must not score it.
##
##   xvfb-run -a --server-args="-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy \
##     --script res://tests/_port_label_screen_probe.gd
##
## `port_plot.gd:129` puts the floating port name at `bounds().get_center() +
## 12 m up`. How far off is that ON SCREEN? The camera framing is derived from
## the DRAWN pier decks and the traced coast — never from `bounds()` — so the
## same frame is used whether `bounds()` is fixed or reverted, and the two runs
## are comparable. Run once on the fixed file, once with the berth-plan walk
## removed, and diff the pixel numbers.

const SEED := 424242
const SHOT := Vector2i(1280, 720)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	PortModuleCatalog.clear_cache()
	var viewport := SubViewport.new()
	viewport.size = SHOT
	viewport.own_world_3d = true
	root.add_child(viewport)
	var world := Node3D.new()
	viewport.add_child(world)
	var camera := Camera3D.new()
	camera.current = true
	camera.fov = 48.0
	world.add_child(camera)

	print("size | label world (x,z) | label px (x,y) | frame centre px | offset px | offset %% of 1280")
	for size in range(PortSizing.MAX_SIZE + 1):
		await _one(world, camera, size)
	quit(0)


func _one(world: Node3D, camera: Camera3D, size: int) -> void:
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

	var visualizer := PortLayoutGraphVisualizer.new()
	world.add_child(visualizer)
	visualizer.configure(graph)
	await process_frame

	## Framing from what is DRAWN, plus the traced coast — the port a player sees.
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var decks: Array = []
	var terminals := visualizer.find_child("BerthTerminals", true, false)
	if terminals != null:
		_collect(terminals, decks)
	for deck in decks:
		for raw in deck["corners"]:
			var c := raw as Vector2
			lo.x = minf(lo.x, c.x)
			lo.y = minf(lo.y, c.y)
			hi.x = maxf(hi.x, c.x)
			hi.y = maxf(hi.y, c.y)
	var foundation := graph.initial_attributes.get("foundation", {}) as Dictionary
	for key in ["coast_polyline", "dock_face_polyline"]:
		for raw_point in foundation.get(key, []) as Array:
			var arr := raw_point as Array
			if arr == null or arr.size() < 2:
				continue
			var p := Vector2(float(arr[0]), float(arr[1]))
			lo.x = minf(lo.x, p.x)
			lo.y = minf(lo.y, p.y)
			hi.x = maxf(hi.x, p.x)
			hi.y = maxf(hi.y, p.y)
	var centre := (lo + hi) * 0.5
	var span := maxf(maxf(hi.x - lo.x, hi.y - lo.y) * 1.25, 160.0)
	var focus := Vector3(centre.x, 0.0, centre.y)
	## Straight overhead: an orthographic-ish plan view, so screen offset is a
	## clean function of world offset and nothing depends on a viewing angle.
	camera.position = focus + Vector3(0.0, span * 1.15, 0.001)
	camera.look_at(focus, Vector3(0.0, 0.0, -1.0))
	await process_frame

	## Exactly what port_plot.gd:129 computes.
	var label_world := graph.bounds().get_center() + Vector3(0.0, 12.0, 0.0)
	var label_px := camera.unproject_position(label_world)
	var frame_px := camera.unproject_position(focus)
	var offset := label_px.distance_to(frame_px)
	print("size %d | (%8.2f,%8.2f) | (%7.1f,%7.1f) | (%7.1f,%7.1f) | %7.1f px | %5.1f%%  [span %.0f m, %.3f m/px]"
		% [size, label_world.x, label_world.z, label_px.x, label_px.y,
			frame_px.x, frame_px.y, offset, 100.0 * offset / 1280.0,
			span, span / 1280.0])

	visualizer.queue_free()
	await process_frame


func _collect(node: Node, out: Array) -> void:
	if node is MeshInstance3D and node.name == "Deck" \
			and node.get_parent() != null and node.get_parent().name == "QuayPier":
		var mi := node as MeshInstance3D
		var box := mi.get_aabb()
		var xf := mi.global_transform
		var half := Vector3(box.size.x, 0.0, box.size.z) * 0.5
		var centre_local := box.get_center()
		var corners: Array = []
		for raw in [
			Vector3(-half.x, 0.0, -half.z), Vector3(half.x, 0.0, -half.z),
			Vector3(half.x, 0.0, half.z), Vector3(-half.x, 0.0, half.z),
		]:
			var w := xf * (centre_local + (raw as Vector3))
			corners.append(Vector2(w.x, w.z))
		out.append({"corners": corners})
	for child in node.get_children():
		_collect(child, out)
