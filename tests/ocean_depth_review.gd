extends "res://tests/ocean_transmission_review.gd"

func review() -> void:
	assert(ShipyardPlaytestMode.active())
	get_tree().create_timer(90).timeout.connect(func(): get_tree().quit(1))
	output = "C:/Users/noahs/Pictures/machinescreenshots/ocean-depth-" + str(Time.get_unix_time_from_system()).replace(".", "-")
	DirAccess.make_dir_recursive_absolute(output)
	WorldWeather.set_blend_to_lighting_paused(true)
	WorldClock.snap_time_of_day(.5)
	WeatherLighting.time_of_day = .5
	WeatherLighting.cloud_cover = .3
	WeatherLighting.precipitation = 0
	WeatherLighting.visibility = 1
	WeatherLighting.sea_state = .55
	WeatherLighting.wind_force = .6
	camera = Camera3D.new()
	add_child(camera)
	camera.current = true
	camera.far = 12000
	camera.position = Vector3(10, 2, 8)
	renderer = WorldRenderer.new()
	add_child(renderer)
	await get_tree().create_timer(8).timeout
	renderer._fft_system.set_process(false)
	renderer.set_process(false)
	var fixed: Shader = renderer._ocean_shader_material.shader
	var previous := Shader.new()
	previous.code = fixed.code.replace(", depth_draw_always", "")
	for heading in [0, 90, 180, 270]:
		camera.rotation_degrees = Vector3(-2, heading, 0)
		renderer._ocean_shader_material.shader = previous
		await capture("before-" + str(heading))
		renderer._ocean_shader_material.shader = fixed
		await capture("after-" + str(heading))
	print("OCEAN DEPTH REVIEW COMPLETE ", output)
	get_tree().quit()
