extends SceneTree

const WEATHER_STATE := preload("res://scripts/weather/weather_state.gd")
const WEATHER_SAMPLE := preload("res://scripts/weather/weather_sample.gd")
const SEASON_SCRIPT := preload("res://scripts/weather/season.gd")
const WEATHER_FIELD := preload("res://scripts/weather/weather_field.gd")
const LAND_FIELD := preload("res://scripts/weather/land_field.gd")
const WEATHER_FRONT := preload("res://scripts/weather/weather_front.gd")
const FRONT_FIELD := preload("res://scripts/weather/weather_front_field.gd")
const COMPOSER := preload("res://scripts/weather/weather_composer.gd")
const TestReport := preload("res://tests/support/test_report.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var t := TestReport.new("weather_system_smoke")
	_test_determinism(t)
	_test_coastal_exposure(t)
	_test_front_continuity(t)
	_test_offshore_gale_access(t)
	_profile_sampling()
	t.finish(self)


func _test_determinism(t: TestReport) -> void:
	WEATHER_FIELD.world_seed = 8162
	FRONT_FIELD.initialize(8162)
	var p := Vector3(4321.0, 0.0, -2345.0)
	var a: WeatherSample = COMPOSER.sample(p, 412.75)
	var b: WeatherSample = COMPOSER.sample(p, 412.75)
	t.check("pressure resamples identically", is_equal_approx(a.pressure, b.pressure))
	t.check("wind velocity resamples identically", a.wind_velocity_ms.is_equal_approx(b.wind_velocity_ms))
	t.check("front intensity resamples identically", is_equal_approx(a.front_intensity, b.front_intensity))
	t.equal("zone label resamples identically", a.zone_label, b.zone_label)


func _test_coastal_exposure(t: TestReport) -> void:
	LAND_FIELD.initialize([{
		"center": Vector3.ZERO,
		"half_x": 250.0,
		"half_z": 500.0,
		"rotation_y": 0.0,
	}])
	var shore := LAND_FIELD.shore_shelter(Vector3(260.0, 0.0, 0.0))
	var coastal := LAND_FIELD.shore_shelter(Vector3(1250.0, 0.0, 0.0))
	var offshore := LAND_FIELD.shore_shelter(Vector3(3800.0, 0.0, 0.0))
	t.check("shore is fully sheltered", shore < 0.01)
	t.check("coastal water is partly sheltered", coastal > shore and coastal < 0.5)
	t.check("offshore water is unsheltered", offshore > 0.99)
	var calm := COMPOSER.sample(Vector3(260.0, 0.0, 0.0), 123.0)
	t.check("sheltered sample has near-zero exposure", calm.exposure < 0.02)
	t.check("sheltered sample stays under a metre of swell", calm.significant_wave_height_m < 1.0)


func _test_front_continuity(t: TestReport) -> void:
	var front := WEATHER_FRONT.new()
	front.origin_xz = Vector2(1000.0, -2000.0)
	front.velocity_m_per_game_hour = Vector2(70.0, 25.0)
	front.phase_offset = 0.2
	var before := front.center_at(31.999, FRONT_FIELD.WORLD_HALF_EXTENT_M)
	var after := front.center_at(32.001, FRONT_FIELD.WORLD_HALF_EXTENT_M)
	t.check("front centre is continuous across the hour boundary", before.distance_to(after) < 1.0)
	t.check(
		"front activity is continuous across the hour boundary",
		absf(front.activity_at(31.999) - front.activity_at(32.001)) < 0.01,
	)


func _test_offshore_gale_access(t: TestReport) -> void:
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
	if not t.check("a strong front is reachable within four days", best_front != null and best_activity > 0.45):
		return
	var center := best_front.center_at(best_time, FRONT_FIELD.WORLD_HALF_EXTENT_M)
	var gale := COMPOSER.sample(Vector3(center.x, 0.0, center.y), best_time)
	t.check("gale sample carries front intensity", gale.front_intensity > 0.4)
	t.check("gale sample blows over 10 m/s", gale.wind_speed_ms > 10.0)
	t.check("gale sample raises over 2 m of swell", gale.significant_wave_height_m > 2.0)


func _profile_sampling() -> void:
	var started := Time.get_ticks_usec()
	for i in range(2000):
		var x := float((i * 7919) % 40000) - 20000.0
		var z := float((i * 3571) % 40000) - 20000.0
		COMPOSER.sample(Vector3(x, 0.0, z), 300.0 + float(i % 48) * 0.25)
	var elapsed := Time.get_ticks_usec() - started
	print("Weather sampling profile: %.2f µs/sample uncached" % (float(elapsed) / 2000.0))
