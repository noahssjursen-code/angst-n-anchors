extends SceneTree

const TestReport := preload("res://tests/support/test_report.gd")
const GENERATOR := preload("res://scripts/world/world_layout_generator.gd")
const STREAMER := preload("res://scripts/world/world_terrain_streamer.gd")
const VISUAL_RADIUS_M := 1200.0
const FOCUS_SCAN_STEP_M := 500.0
const CONVERGE_TIMEOUT_MS := 90000


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var t := TestReport.new("world_terrain_background_test")
	var layout: WorldLayout = GENERATOR.generate(90210)
	# Origin is open water on this seed, and an all-water radius makes every
	# geometry comparison below a comparison of zeros. Stream over land.
	var focus := _land_focus(layout)
	if not t.check("found a land focus to stream over", layout.is_land(Vector2(focus.x, focus.z))):
		t.finish(self)
		return
	# `background_mesh_builds` is a scheduling switch, not a geometry switch: the
	# worker-pool path must resolve the same chunk set with the same meshes the
	# synchronous path produces, and its queue must actually drain.
	var threaded := await _stream(layout, focus, true)
	var direct := await _stream(layout, focus, false)
	var threaded_stats := threaded["stats"] as Dictionary
	var direct_stats := direct["stats"] as Dictionary

	t.check(
		"background build queue drains (pending %d after %d frames)"
		% [int(threaded_stats.get("pending", 0)), int(threaded["frames"])],
		bool(threaded["converged"]),
	)
	t.check("synchronous build queue drains", bool(direct["converged"]))
	t.check("a build was observed in flight on the worker pool", bool(threaded["saw_in_flight"]))
	t.check("synchronous streamer never reports a task in flight", not bool(direct["saw_in_flight"]))
	t.check(
		"background builds are timed (avg %.3f ms)"
		% float(threaded_stats.get("average_build_ms", 0.0)),
		float(threaded_stats.get("average_build_ms", 0.0)) > 0.0,
	)
	# Non-vacuity guards: without these the parity checks below pass on an
	# all-water radius that streams nothing at all.
	t.check(
		"background streamed real terrain (%d vertices, %d visual chunks)"
		% [int(threaded_stats.get("vertices", 0)), int(threaded_stats.get("visual_chunks", 0))],
		int(threaded_stats.get("vertices", 0)) > 0
		and int(threaded_stats.get("triangles", 0)) > 0
		and int(threaded_stats.get("visual_chunks", 0)) > 0,
	)
	t.check(
		"background resolved more than one chunk (%d)" % int(threaded_stats.get("loaded", 0)),
		int(threaded_stats.get("loaded", 0)) > 1,
	)

	for key in ["loaded", "vertices", "triangles", "visual_chunks", "empty_water_chunks",
			"retained_cpu_bytes", "memory_estimate_bytes"]:
		t.equal(
			"background and synchronous builds agree on %s" % key,
			int(threaded_stats.get(key, -1)),
			int(direct_stats.get(key, -2)),
		)
	t.finish(self)


## Nearest chunk-grid point to the origin that the layout calls land, so the
## streamed radius is guaranteed to contain buildable terrain.
func _land_focus(layout: WorldLayout) -> Vector3:
	var best := Vector3.ZERO
	var best_distance := INF
	var steps := int(minf(layout.half_extent_m, 20000.0) / FOCUS_SCAN_STEP_M)
	for iz in range(-steps, steps + 1):
		for ix in range(-steps, steps + 1):
			var point := Vector2(float(ix) * FOCUS_SCAN_STEP_M, float(iz) * FOCUS_SCAN_STEP_M)
			if not layout.is_land(point):
				continue
			var distance := point.length()
			if distance < best_distance:
				best_distance = distance
				best = Vector3(point.x, 0.0, point.y)
	return best


## Streams one radius to convergence — `loaded > 0` with nothing left pending —
## and reports what was seen on the way there.
func _stream(layout: WorldLayout, focus: Vector3, background: bool) -> Dictionary:
	var streamer := STREAMER.new()
	streamer.visual_radius_m = VISUAL_RADIUS_M
	streamer.collision_radius_m = 0.0
	streamer.background_mesh_builds = background
	root.add_child(streamer)
	streamer.configure(layout)
	streamer.begin_boot_priority(focus)
	var deadline := Time.get_ticks_msec() + CONVERGE_TIMEOUT_MS
	var saw_in_flight := false
	var frames := 0
	var stats := streamer.get_debug_stats()
	while Time.get_ticks_msec() < deadline:
		await process_frame
		frames += 1
		stats = streamer.get_debug_stats()
		saw_in_flight = saw_in_flight or bool(stats.get("build_in_flight", false))
		if int(stats.get("loaded", 0)) > 0 and int(stats.get("pending", 0)) == 0:
			break
	streamer.free()
	return {
		"stats": stats,
		"saw_in_flight": saw_in_flight,
		"frames": frames,
		"converged": int(stats.get("loaded", 0)) > 0 and int(stats.get("pending", 0)) == 0,
	}
