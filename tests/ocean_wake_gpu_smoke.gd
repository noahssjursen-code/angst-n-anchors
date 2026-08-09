extends SceneTree

const TestReport := preload("res://tests/support/test_report.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var t := TestReport.new("ocean_wake_gpu_smoke")
	var field := OceanWakeField.new()
	root.add_child(field)
	await process_frame
	if not t.check("Wake GPU smoke requires RenderingDevice", field.rd != null):
		t.finish(self)
		return
	field.set_process(false)
	field.set_focus(Vector2.ZERO)
	for i in range(8):
		field.submit_emitter(
			"gpu-test",
			Vector2(0.0, float(i) * -2.0),
			Vector2.DOWN,
			4.0,
			6.0,
			0.9,
			1.0,
			100.0
		)
		field.call("_update_wake", 1.0 / 30.0)
	field.rd.sync()
	await process_frame
	await process_frame
	field.call("_collect_gpu_profile")

	var data := field.rd.texture_get_data(
		field._textures[field._current_index], 0
	)
	var image := Image.create_from_data(
		OceanWakeField.RESOLUTION,
		OceanWakeField.RESOLUTION,
		false,
		Image.FORMAT_RGH,
		data
	)
	var center := OceanWakeField.RESOLUTION / 2
	var strongest := 0.0
	for y in range(center - 16, center + 8):
		for x in range(center - 6, center + 7):
			var pixel := image.get_pixel(x, y)
			strongest = maxf(strongest, maxf(pixel.r, pixel.g))
	t.check("GPU emitter injection did not reach wake field", strongest > 0.08)

	var stats := field.get_debug_stats()
	print(
		"Ocean wake GPU smoke: peak %.2f, %.3f ms CPU submit"
		% [
			strongest,
			float(stats["cpu_update_ms"]),
		]
	)
	field.queue_free()
	await process_frame
	t.finish(self)
