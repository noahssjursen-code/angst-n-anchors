extends SceneTree

const TestReport := preload("res://tests/support/test_report.gd")
const WORLD_RENDERER := preload("res://scripts/world/world_renderer.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var t := TestReport.new("ocean_wake_visual_capture")
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.current = true
	camera.position = Vector3(0.0, 24.0, 38.0)
	camera.look_at(Vector3(0.0, -1.5, -12.0))
	RenderingServer.viewport_set_measure_render_time(
		root.get_viewport().get_viewport_rid(), true
	)

	var renderer := WORLD_RENDERER.new()
	root.add_child(renderer)
	# Wait for FFT bind + wake field init under D3D12.
	for _i in range(20):
		await process_frame
	var field := renderer.get_node("OceanWakeField") as OceanWakeField
	if not t.check("renderer exposes an OceanWakeField", field != null):
		t.finish(self)
		return
	if renderer.has_method("_apply_ocean_shader"):
		renderer.call("_apply_ocean_shader", 1.0, 0.0, 0.0, 0.2, 0.0, 0.0)
	field.set_process(false)
	field.set_focus(Vector2.ZERO)
	for i in range(24):
		var phase := float(i) / 23.0
		var position := Vector2(
			sin(phase * PI) * 5.5,
			lerpf(12.0, -34.0, phase)
		)
		field.submit_emitter(
			"visual-test", position, Vector2(0.0, 1.0),
			3.5, 6.0, 0.9, 1.0, 100.0
		)
		field.call("_update_wake", 1.0 / 30.0)
	for _i in range(12):
		await process_frame
	var image := root.get_viewport().get_texture().get_image()
	var output_path := OS.get_user_data_dir().path_join("ocean_wake_visual.png")
	t.check("wake capture written", image.save_png(output_path) == OK)
	field.set_process(true)
	for i in range(45):
		field.submit_emitter(
			"visual-test",
			Vector2(0.0, -34.0 - float(i) * 0.12),
			Vector2(0.0, 1.0),
			3.5, 6.0, 0.9, 1.0, 100.0
		)
		await process_frame
	var gpu_frame_ms := RenderingServer.viewport_get_measured_render_time_gpu(
		root.get_viewport().get_viewport_rid()
	)
	print(
		"Ocean wake visual capture: %s (%.2f ms total GPU frame)"
		% [output_path, gpu_frame_ms]
	)
	renderer.queue_free()
	camera.queue_free()
	await process_frame
	t.finish(self)
