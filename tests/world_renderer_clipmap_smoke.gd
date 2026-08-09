extends SceneTree

const WORLD_RENDERER := preload("res://scripts/world/world_renderer.gd")
const TestReport := preload("res://tests/support/test_report.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var t := TestReport.new("world_renderer_clipmap_smoke")
	await _check_all(t)
	t.finish(self)


func _check_all(t: TestReport) -> void:
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.current = true
	camera.position = Vector3(17.2, 8.0, -31.4)
	camera.rotation_degrees.x = -18.0
	RenderingServer.viewport_set_measure_render_time(root.get_viewport().get_viewport_rid(), true)

	var renderer := WORLD_RENDERER.new()
	root.add_child(renderer)
	await process_frame
	await process_frame

	var stats: Dictionary = renderer.get_ocean_debug_stats()
	t.check("nine clipmap rings are active", int(stats.get("active_rings", 0)) == 9)
	t.check("clipmap reports 107145 vertices", int(stats.get("vertices", 0)) == 107145)
	if not t.check("OceanClipmap node exists", renderer.get_node_or_null("OceanClipmap") != null):
		return
	t.check("OceanClipmap holds nine ring children", renderer.get_node("OceanClipmap").get_child_count() == 9)
	t.check("clipmap x snaps to 17.25", is_equal_approx(renderer.get_node("OceanClipmap").position.x, 17.25))
	t.check("clipmap z snaps to -31.5", is_equal_approx(renderer.get_node("OceanClipmap").position.z, -31.5))
	var lighting: Dictionary = renderer.get_lighting_debug_state()
	t.check("tonemapper is ACES", int(lighting["tonemap_mode"]) == Environment.TONE_MAPPER_ACES)
	t.check("tonemap white stays at or under 3.0", float(lighting["tonemap_white"]) <= 3.0)
	t.check("SSAO is enabled", bool(lighting["ssao_enabled"]))
	t.check("glow is enabled", bool(lighting["glow_enabled"]))
	t.check("ambient energy is at least 0.04", float(lighting["ambient_energy"]) >= 0.04)
	var weather := root.get_node_or_null("WeatherLighting")
	if weather != null:
		weather.set("visibility", 0.96)
		await process_frame
		lighting = renderer.get_lighting_debug_state()
		t.check("volumetric fog stays off at 0.96 visibility", not bool(lighting["volumetric_fog_enabled"]))
		weather.set("visibility", 0.88)
		await process_frame
		lighting = renderer.get_lighting_debug_state()
		t.check("volumetric fog stays off at 0.88 visibility", not bool(lighting["volumetric_fog_enabled"]))
		weather.set("visibility", 0.50)
		await process_frame
		lighting = renderer.get_lighting_debug_state()
		t.check("volumetric fog switches on at 0.50 visibility", bool(lighting["volumetric_fog_enabled"]))
		t.check("volumetric fog density stays under 0.01", float(lighting["volumetric_fog_density"]) < 0.01)
		weather.set("visibility", 1.0)
		await process_frame

	# Camera crossing the wave surface must drive the underwater split in both
	# directions; the ocean itself remains double-sided for the submerged view.
	var above_water_far := camera.far
	camera.position.y = WaveSurface.WATER_LEVEL + 1.0
	await process_frame
	lighting = renderer.get_lighting_debug_state()
	t.check(
		"a camera above the surface reads a positive signed distance",
		float(lighting["camera_water_signed_distance"]) > 0.0,
	)
	camera.position.y = WaveSurface.WATER_LEVEL - 1.0
	await process_frame
	lighting = renderer.get_lighting_debug_state()
	t.check(
		"a submerged camera reads a negative signed distance",
		float(lighting["camera_water_signed_distance"]) < 0.0,
	)
	t.check("underwater fog density is at least 0.03", float(lighting["fog_density"]) >= 0.03)
	t.check("volumetric fog stays off underwater", not bool(lighting["volumetric_fog_enabled"]))
	t.check("underwater camera far clips to 140 m or less", float(lighting["camera_far"]) <= 140.0)
	camera.position.y = 8.0
	await process_frame
	t.check("camera far is restored on surfacing", is_equal_approx(camera.far, above_water_far))

	var fft := renderer.get_node("FFTWaterSystem")
	var fft_stats: Dictionary = fft.get_debug_stats()
	t.check("FFT resolution is 512", int(fft_stats["resolution"]) == 512)
	t.check("FFT runs four cascades", int(fft_stats["cascades"]) == 4)
	t.check("FFT simulates at 60 Hz", int(fft_stats["sim_hz"]) == 60)

	for height in [4.0, 40.0, 200.0]:
		camera.position = Vector3(523.1, height, -917.8)
		await process_frame
		t.check(
			"clipmap x snaps to 522.75 at height %s" % height,
			is_equal_approx(renderer.get_node("OceanClipmap").position.x, 522.75),
		)
		t.check(
			"clipmap z snaps to -918.0 at height %s" % height,
			is_equal_approx(renderer.get_node("OceanClipmap").position.z, -918.0),
		)

	for _frame in range(90):
		await process_frame
	var gpu_ms := RenderingServer.viewport_get_measured_render_time_gpu(
		root.get_viewport().get_viewport_rid()
	)
	print("WorldRenderer clipmap smoke: 9 surfaces, 512²×4 FFT @ 60Hz, %.2f ms GPU frame" % gpu_ms)
