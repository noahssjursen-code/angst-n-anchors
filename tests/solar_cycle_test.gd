extends SceneTree


func _initialize() -> void:
	var dawn := SolarCycle.sample(SolarCycle.SUNRISE_HOUR / 24.0)
	var noon := SolarCycle.sample(SolarCycle.SOLAR_NOON_HOUR / 24.0)
	var evening := SolarCycle.sample(18.0 / 24.0)
	var sunset := SolarCycle.sample(SolarCycle.SUNSET_HOUR / 24.0)

	assert(absf(float(dawn["altitude_degrees"])) < 0.05)
	assert((dawn["sun_direction"] as Vector3).x > 0.0, "Sunrise must be east")
	assert(float(noon["altitude_degrees"]) > 51.0)
	assert((noon["sun_direction"] as Vector3).z > 0.6, "Solar noon must be south")
	assert(float(evening["daylight"]) > 0.95, "18:00 must not be night")
	assert(absf(float(sunset["altitude_degrees"])) < 0.05)
	assert((sunset["sun_direction"] as Vector3).x < 0.0, "Sunset must be west")

	var previous := SolarCycle.sample(0.0)
	for minute in range(10, 1441, 10):
		var current := SolarCycle.sample(float(minute % 1440) / 1440.0)
		var light_delta := absf(float(current["daylight"]) - float(previous["daylight"]))
		var direction_delta := (current["sun_direction"] as Vector3).angle_to(
			previous["sun_direction"] as Vector3
		)
		assert(light_delta < 0.08, "Daylight discontinuity at minute %d" % minute)
		assert(direction_delta < 0.08, "Sun-direction discontinuity at minute %d" % minute)
		previous = current

	print("SolarCycle tests: horizon, direction, long evening, and continuity passed")
	quit()
