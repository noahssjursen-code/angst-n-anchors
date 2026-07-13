extends SceneTree

const WORLD_RENDERER := preload("res://scripts/world/world_renderer.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
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
	assert(int(stats.get("active_rings", 0)) == 9)
	assert(int(stats.get("vertices", 0)) == 107145)
	assert(renderer.get_node_or_null("OceanClipmap") != null)
	assert(renderer.get_node("OceanClipmap").get_child_count() == 9)
	assert(is_equal_approx(renderer.get_node("OceanClipmap").position.x, 17.25))
	assert(is_equal_approx(renderer.get_node("OceanClipmap").position.z, -31.5))

	var fft := renderer.get_node("FFTWaterSystem")
	var fft_stats: Dictionary = fft.get_debug_stats()
	assert(int(fft_stats["resolution"]) == 512)
	assert(int(fft_stats["cascades"]) == 4)
	assert(int(fft_stats["sim_hz"]) == 60)

	for height in [4.0, 40.0, 200.0]:
		camera.position = Vector3(523.1, height, -917.8)
		await process_frame
		assert(is_equal_approx(renderer.get_node("OceanClipmap").position.x, 522.75))
		assert(is_equal_approx(renderer.get_node("OceanClipmap").position.z, -918.0))

	for _frame in range(90):
		await process_frame
	var gpu_ms := RenderingServer.viewport_get_measured_render_time_gpu(
		root.get_viewport().get_viewport_rid()
	)
	print("WorldRenderer clipmap smoke: 9 surfaces, 512²×4 FFT @ 60Hz, %.2f ms GPU frame" % gpu_ms)
	quit()
