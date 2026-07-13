extends SceneTree

const WORLD_RENDERER := preload("res://scripts/world/world_renderer.gd")
var _gpu_capture_available := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	WeatherField.world_seed = 7241
	WeatherFrontField.initialize(7241)
	LandField.initialize([{
		"center": Vector3.ZERO,
		"half_x": 300.0,
		"half_z": 650.0,
		"rotation_y": 0.0,
	}])
	var camera: Camera3D
	var renderer: Node
	_gpu_capture_available = RenderingServer.get_rendering_device() != null
	if _gpu_capture_available:
		camera = Camera3D.new()
		root.add_child(camera)
		camera.current = true
		camera.position = Vector3(0.0, 22.0, 42.0)
		camera.look_at(Vector3(0.0, -1.0, -16.0))
		renderer = WORLD_RENDERER.new()
		root.add_child(renderer)
		for _i in range(20):
			await process_frame

	var output_dir := OS.get_user_data_dir().path_join("weather_validation")
	DirAccess.make_dir_recursive_absolute(output_dir)
	var ordinary_time := 210.0
	await _capture(
		output_dir, "01_harbour_calm.png",
		WeatherComposer.sample(Vector3(310.0, 0.0, 0.0), ordinary_time), 0.52
	)
	await _capture(
		output_dir, "02_coastal_passage.png",
		WeatherComposer.sample(Vector3(1800.0, 0.0, 0.0), ordinary_time), 0.52
	)
	await _capture(
		output_dir, "03_open_ocean.png",
		WeatherComposer.sample(Vector3(6500.0, 0.0, 0.0), ordinary_time), 0.52
	)

	var severe := _strongest_front_sample()
	await _capture(output_dir, "04_approaching_front.png", severe["edge"], 0.47)
	await _capture(output_dir, "05_gale_core.png", severe["core"], 0.43)
	var fog := (severe["core"] as WeatherSample)
	var fog_state := fog.to_weather_state()
	fog_state.visibility = 0.18
	fog_state.precipitation = maxf(fog_state.precipitation, 0.62)
	await _capture_state(output_dir, "06_fog_and_rain.png", fog_state, 0.42)
	await _capture(output_dir, "07_gale_night.png", severe["core"], 0.02)

	print("Weather visual captures: %s" % output_dir)
	if renderer != null:
		renderer.queue_free()
	if camera != null:
		camera.queue_free()
	await process_frame
	quit()


func _strongest_front_sample() -> Dictionary:
	var best_front: WeatherFront
	var best_time := 0.0
	var best := -1.0
	for hour in range(0, 97):
		for front in WeatherFrontField.active_fronts(float(hour)):
			var activity := front.activity_at(float(hour))
			if activity > best:
				best = activity
				best_front = front
				best_time = float(hour)
	assert(best_front != null)
	var center := best_front.center_at(best_time, WeatherFrontField.WORLD_HALF_EXTENT_M)
	var direction := best_front.velocity_m_per_game_hour.normalized()
	var edge := center - direction * best_front.radius_m * 0.78
	return {
		"core": WeatherComposer.sample(Vector3(center.x, 0.0, center.y), best_time),
		"edge": WeatherComposer.sample(Vector3(edge.x, 0.0, edge.y), best_time),
	}


func _capture(output_dir: String, filename: String, sample: WeatherSample, time_of_day: float) -> void:
	await _capture_state(output_dir, filename, sample.to_weather_state(), time_of_day)


func _capture_state(output_dir: String, filename: String, state: WeatherState, time_of_day: float) -> void:
	var clock := root.get_node_or_null("WorldClock")
	var lighting := root.get_node_or_null("WeatherLighting")
	assert(clock != null and lighting != null)
	clock.call("snap_time_of_day", time_of_day)
	lighting.call("apply_weather_state", state)
	for _i in range(8):
		await process_frame
	var image: Image
	if _gpu_capture_available:
		var viewport_texture := root.get_viewport().get_texture()
		if viewport_texture != null:
			image = viewport_texture.get_image()
	if image == null or image.is_empty():
		image = _diagnostic_image(state, time_of_day)
	assert(image.save_png(output_dir.path_join(filename)) == OK)


func _diagnostic_image(state: WeatherState, time_of_day: float) -> Image:
	# Headless CI fallback. It preserves each scenario as a deterministic visual
	# regression card even when no GPU viewport is available.
	var image := Image.create(960, 540, false, Image.FORMAT_RGBA8)
	var daylight := smoothstep(-0.18, 0.55, -cos(time_of_day * TAU))
	var storm := clampf(state.precipitation * 0.75 + state.front_intensity * 0.35, 0.0, 1.0)
	var sky := Color(0.035, 0.055, 0.11).lerp(Color(0.42, 0.64, 0.86), daylight)
	sky = sky.lerp(Color(0.16, 0.19, 0.24), maxf(state.cloud_cover, storm))
	var sea := Color(0.015, 0.04, 0.08).lerp(Color(0.04, 0.20, 0.28), daylight * 0.65)
	sea = sea.lerp(Color(0.02, 0.055, 0.075), state.sea_state)
	var fog := Color(0.58, 0.64, 0.68)
	sky = sky.lerp(fog, (1.0 - state.visibility) * 0.72)
	sea = sea.lerp(fog, (1.0 - state.visibility) * 0.48)
	image.fill(sky)
	image.fill_rect(Rect2i(0, 255, 960, 285), sea)
	var crest_count := 2 + int(state.sea_state * 11.0)
	for i in range(crest_count):
		var y := 290 + i * 20
		var crest := Color(0.45, 0.74, 0.76, 0.18 + state.sea_state * 0.45)
		image.fill_rect(Rect2i(0, y, 960, maxi(1, int(state.sea_state * 4.0))), crest)
	var rain_lines := int(state.precipitation * 80.0)
	for i in range(rain_lines):
		var x := (i * 137 + 53) % 960
		var y := (i * 89 + 31) % 500
		image.fill_rect(Rect2i(x, y, 1, 24), Color(0.62, 0.76, 0.88, 0.58))
	return image
