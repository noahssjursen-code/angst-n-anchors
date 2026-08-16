extends SceneTree

## No `## gate-requires:` marker: this file runs everywhere the gate runs.
##
## It carried `## gate-requires: rendering_device` and was skipped for it. That
## was wrong, and measurably so — with the skip lifted it passes here in ~31 s
## under xvfb + opengl3, on a box whose `RenderingServer.get_rendering_device()`
## is null. The marker was excluding a working test. (tools/gate.sh now re-runs
## whatever it skips and fails the gate on any skip that passes, so this cannot
## be reintroduced quietly — see "THE SKIP AUDIT" there.)
##
## The reasoning behind the old marker was half right and is kept, because it
## still describes what happens: WorldRenderer brings up the FFT water system
## and OceanWakeField, both compute pipelines, and without a RenderingDevice the
## FFT bind fails and `_update_wake` dereferences a null `rd`. So on a box like
## this one the PNG shows an ocean with no wake in it.
##
## That degrades the CAPTURE, not the CHECKS. Every claim asserted below — the
## OceanWakeField node exists, `_apply_ocean_shader` still takes the arguments
## this call passes, the frame is capturable and writable — holds with or
## without a RenderingDevice, and each has caught a real regression. A degraded
## capture is a reason to label the PNG, which `_run` now does; it is not a
## reason to delete three live assertions from the gate.
##
## ══ THIS RIG'S PNG CANNOT BE DIFFED. IT IS FOR LOOKING AT ONLY. ═════════════
##
## Measured 2026-08-16: two runs back to back, no code change, no gap —
## `ocean_wake_visual.png` moved **15.9% of its pixels with a worst channel
## delta of 244/255**; a pair further apart moved **88.3%**. Nothing is wrong.
## The subject is a moving sea.
##
## `WorldRenderer` sets the ocean materials' `wave_time` from
## `WaveSurface.get_sim_time()`, which is `Time.get_ticks_msec() * 0.001` — real
## milliseconds since the process started. Every frame this rig photographs is
## therefore a photograph of the wave field at a WALL-CLOCK phase, and two
## processes never reach the grab at the same millisecond.
##
## **This cannot be fixed without freezing the sea, and a frozen sea is not what
## this rig exists to show** — it exists so a person can look at whether a wake
## reads as a wake on moving water. So the rig states the limit instead of
## papering over it, and the statement is repeated on stdout on every run
## (`WAVE PHASE`) so nobody has to open this file to learn it.
##
## What that means for anyone comparing two of these PNGs: **a difference
## between them is evidence of nothing.** The claims below are the diffable
## part of this unit, and they are the only part.
##
## Every OTHER capture rig in `tests/` is byte-reproducible as of 2026-08-16 —
## this is the one exception, and it is the one whose subject is time.

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
	# solar, daylight, cloud, rain, sea_state, air_wind, storm, fog_t — noon, clear.
	# Recorded as a check rather than an `if`: the previous silent guard let the
	# call drift to six arguments against an eight-argument signature.
	if t.check("renderer exposes _apply_ocean_shader", renderer.has_method("_apply_ocean_shader")):
		renderer.call(
			"_apply_ocean_shader",
			SolarCycle.sample(0.5), 1.0, 0.0, 0.0, 0.2, 0.0, 0.0, 0.0
		)
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
	# Say which kind of PNG this is. Without a RenderingDevice the wake compute
	# never runs, and a reader who does not know that will read a wakeless ocean
	# as a wake regression.
	var wake_live := field.rd != null
	print(
		"Ocean wake visual capture: %s (%.2f ms total GPU frame) — wake compute %s"
		% [
			output_path,
			gpu_frame_ms,
			"live" if wake_live else "INERT (no RenderingDevice: ocean rendered without wake)",
		]
	)
	## Said out loud on every run, because the header is not where anyone stands
	## when they put two of these frames side by side. Measured 2026-08-16:
	## 15.9% of pixels between back-to-back runs, 88.3% between runs minutes
	## apart, worst channel delta 244/255 — all of it the sea moving.
	print(
		"WAVE PHASE %.3f s — THIS FRAME IS NOT REPRODUCIBLE AND MUST NOT BE DIFFED. "
		% (Time.get_ticks_msec() * 0.001)
		+ "wave_time comes from the wall clock, so two runs never photograph the "
		+ "same sea. Look at it; do not compare it."
	)
	renderer.queue_free()
	camera.queue_free()
	await process_frame
	t.finish(self)
