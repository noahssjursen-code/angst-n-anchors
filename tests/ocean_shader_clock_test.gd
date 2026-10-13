extends "res://tests/ocean_transmission_review.gd"

func review() -> void:
	assert(ShipyardPlaytestMode.active())
	get_tree().create_timer(60).timeout.connect(func(): get_tree().quit(1))
	output = "C:/Users/noahs/Pictures/machinescreenshots/ocean-clock-%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(output)
	WorldWeather.set_blend_to_lighting_paused(true)
	WorldClock.snap_time_of_day(.5)
	WeatherLighting.time_of_day = .5
	WeatherLighting.cloud_cover = .5
	WeatherLighting.sea_state = .7
	WeatherLighting.wind_force = .7
	camera = Camera3D.new()
	add_child(camera)
	camera.current = true
	camera.position = Vector3(0, 15, 0)
	camera.look_at(Vector3(10, -2, -30))
	renderer = WorldRenderer.new()
	add_child(renderer)
	await get_tree().create_timer(6).timeout
	renderer._fft_system.set_process(false)
	renderer.set_process(false)
	var materials: Array[ShaderMaterial] = [renderer._ocean_shader_material, renderer._ocean_mid_material, renderer._ocean_far_material, renderer._ocean_horizon_material]
	for variant in ["unix-unbounded", "unix-bounded", "wrap-before", "wrap-after"]:
		var t := 1791907200.0
		if variant == "unix-bounded": t = fposmod(t, 4096.0)
		if variant == "wrap-before": t = 4096.0 - 0.001
		if variant == "wrap-after": t = 0.001
		for material in materials: material.set_shader_parameter("wave_time", t)
		await capture(variant)
	print("OCEAN SHADER CLOCK REVIEW ", output)
	get_tree().quit()
