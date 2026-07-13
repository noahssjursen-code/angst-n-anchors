extends SceneTree

const WEATHER_STATE := preload("res://scripts/weather/weather_state.gd")
const WEATHER_SAMPLE := preload("res://scripts/weather/weather_sample.gd")
const SEASON_SCRIPT := preload("res://scripts/weather/season.gd")
const WEATHER_FIELD := preload("res://scripts/weather/weather_field.gd")
const LAND_FIELD := preload("res://scripts/weather/land_field.gd")
const WEATHER_FRONT := preload("res://scripts/weather/weather_front.gd")
const FRONT_FIELD := preload("res://scripts/weather/weather_front_field.gd")
const COMPOSER := preload("res://scripts/weather/weather_composer.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_determinism()
	_test_coastal_exposure()
	_test_front_continuity()
	_test_offshore_gale_access()
	_profile_sampling()
	print("Weather system smoke: all assertions passed")
	quit()


func _test_determinism() -> void:
	WEATHER_FIELD.world_seed = 8162
	FRONT_FIELD.initialize(8162)
	var p := Vector3(4321.0, 0.0, -2345.0)
	var a: WeatherSample = COMPOSER.sample(p, 412.75)
	var b: WeatherSample = COMPOSER.sample(p, 412.75)
	assert(is_equal_approx(a.pressure, b.pressure))
	assert(a.wind_velocity_ms.is_equal_approx(b.wind_velocity_ms))
	assert(is_equal_approx(a.front_intensity, b.front_intensity))
	assert(a.zone_label == b.zone_label)


func _test_coastal_exposure() -> void:
	LAND_FIELD.initialize([{
		"center": Vector3.ZERO,
		"half_x": 250.0,
		"half_z": 500.0,
		"rotation_y": 0.0,
	}])
	var shore := LAND_FIELD.shore_shelter(Vector3(260.0, 0.0, 0.0))
	var coastal := LAND_FIELD.shore_shelter(Vector3(1250.0, 0.0, 0.0))
	var offshore := LAND_FIELD.shore_shelter(Vector3(3800.0, 0.0, 0.0))
	assert(shore < 0.01)
	assert(coastal > shore and coastal < 0.5)
	assert(offshore > 0.99)
	var calm := COMPOSER.sample(Vector3(260.0, 0.0, 0.0), 123.0)
	assert(calm.exposure < 0.02)
	assert(calm.significant_wave_height_m < 1.0)


func _test_front_continuity() -> void:
	var front := WEATHER_FRONT.new()
	front.origin_xz = Vector2(1000.0, -2000.0)
	front.velocity_m_per_game_hour = Vector2(70.0, 25.0)
	front.phase_offset = 0.2
	var before := front.center_at(31.999, FRONT_FIELD.WORLD_HALF_EXTENT_M)
	var after := front.center_at(32.001, FRONT_FIELD.WORLD_HALF_EXTENT_M)
	assert(before.distance_to(after) < 1.0)
	assert(absf(front.activity_at(31.999) - front.activity_at(32.001)) < 0.01)


func _test_offshore_gale_access() -> void:
	WEATHER_FIELD.world_seed = 991
	FRONT_FIELD.initialize(991)
	var best_front: WeatherFront
	var best_time := 0.0
	var best_activity := -1.0
	for hour in range(0, 97):
		for front in FRONT_FIELD.active_fronts(float(hour)):
			var activity := front.activity_at(float(hour))
			if activity > best_activity:
				best_activity = activity
				best_front = front
				best_time = float(hour)
	assert(best_front != null and best_activity > 0.45)
	var center := best_front.center_at(best_time, FRONT_FIELD.WORLD_HALF_EXTENT_M)
	var gale := COMPOSER.sample(Vector3(center.x, 0.0, center.y), best_time)
	assert(gale.front_intensity > 0.4)
	assert(gale.wind_speed_ms > 10.0)
	assert(gale.significant_wave_height_m > 2.0)


func _profile_sampling() -> void:
	var started := Time.get_ticks_usec()
	for i in range(2000):
		var x := float((i * 7919) % 40000) - 20000.0
		var z := float((i * 3571) % 40000) - 20000.0
		COMPOSER.sample(Vector3(x, 0.0, z), 300.0 + float(i % 48) * 0.25)
	var elapsed := Time.get_ticks_usec() - started
	print("Weather sampling profile: %.2f µs/sample uncached" % (float(elapsed) / 2000.0))
