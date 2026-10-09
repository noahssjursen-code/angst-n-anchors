extends WorldLightingShowcase

## Shared runtime sky/rain at human eye height, with deterministic comparisons.
func _ready() -> void:
	super._ready()
	WorldClock.set_process(false)
	get_node("ReviewHUD").hide()
	_camera.position = Vector3(3.0, 4.1, 35.0)
	_camera.look_at(Vector3(-12.0, 9.0, -40.0))
	_camera.fov = 65.0
	_capture_running = true
	call_deferred("_review")


func _review() -> void:
	var directory := "C:/Users/noahs/Pictures/machinescreenshots/rain-%s-%s" % [
		int(Time.get_unix_time_from_system()), Time.get_ticks_msec()]
	DirAccess.make_dir_recursive_absolute(directory)
	var results: Array[Dictionary] = []
	for spec in [
		["clear-invalid-rain", 0.5, 0.08, 0.65, 0.12],
		["fair-cloud-invalid-rain", 0.5, 0.30, 0.65, 0.12],
		["overcast-dry", 0.5, 0.88, 0.0, 0.12],
		["drizzle", 0.5, 0.86, 0.38, 0.12],
		["rain", 0.5, 0.86, 0.72, 0.28],
		["wind-driven-rain", 0.5, 0.98, 0.95, 0.70],
		["night-rain", 0.0, 0.90, 0.75, 0.28],
	]:
		var state := WeatherState.new()
		state.cloud_cover = spec[2]
		state.precipitation = spec[3]
		state.wind_force = spec[4]
		state.wind_speed_ms = state.wind_force * 22.0
		state.wind_direction = Vector3(-0.72, 0.0, 0.69).normalized()
		state.visibility = 0.94
		state.sea_state = 0.12
		WeatherLighting.time_of_day = spec[1]
		WeatherLighting.apply_weather_state(state)
		# Stable volume offset and repeatable particle simulation at every state.
		get_node("WorldRenderer")._sky_shader_material.set_shader_parameter("sky_time", 120.0)
		var particles := get_node("RainField/RainParticles") as GPUParticles3D
		particles.use_fixed_seed = true
		particles.seed = 781
		particles.restart()
		# restart() starts emission even if the weather is dry.
		get_node("RainField")._apply_weather()
		assert(particles.emitting == (WeatherLighting.rain_amount > 0.01))
		await get_tree().create_timer(2.5).timeout
		var samples: Array[float] = []
		var last_frame := Time.get_ticks_usec()
		for frame in 120:
			await get_tree().process_frame
			var now := Time.get_ticks_usec()
			samples.append((now - last_frame) / 1000.0)
			last_frame = now
		samples.sort()
		await RenderingServer.frame_post_draw
		var path := directory.path_join(spec[0] + ".png")
		assert(get_viewport().get_texture().get_image().save_png(path) == OK)
		results.append({"view": spec[0], "cloud": WeatherLighting.cloud_cover,
			"precipitation": WeatherLighting.precipitation, "rain_amount": WeatherLighting.rain_amount,
			"emitting": particles.emitting, "frame_median_ms": samples[60], "frame_p95_ms": samples[114],
			"particle_budget": particles.amount,
			"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)})
		print("RAIN_CAPTURE ", path)
	FileAccess.open(directory.path_join("report.json"), FileAccess.WRITE).store_string(JSON.stringify(results, "\t"))
	print("RAIN_REVIEW ", directory)
	get_tree().quit()
