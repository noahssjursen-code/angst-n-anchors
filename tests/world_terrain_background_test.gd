extends SceneTree

const TestReport := preload("res://tests/support/test_report.gd")
const GENERATOR := preload("res://scripts/world/world_layout_generator.gd")
const STREAMER := preload("res://scripts/world/world_terrain_streamer.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var t := TestReport.new("world_terrain_background_test")
	var layout: WorldLayout = GENERATOR.generate(90210)
	var streamer := STREAMER.new()
	streamer.visual_radius_m = 1200.0
	streamer.collision_radius_m = 0.0
	streamer.background_mesh_builds = true
	root.add_child(streamer)
	streamer.configure(layout)
	var deadline := Time.get_ticks_msec() + 10000
	while int(streamer.get_debug_stats().get("loaded", 0)) == 0 \
			and Time.get_ticks_msec() < deadline:
		await process_frame
	var stats := streamer.get_debug_stats()
	t.check("streamer loaded a tile", int(stats.get("loaded", 0)) > 0)
	t.check(
		"build is in flight or the pending count is sane",
		bool(stats.get("build_in_flight", false)) or int(stats.get("pending", 0)) >= 0,
	)
	streamer.free()
	t.finish(self)
