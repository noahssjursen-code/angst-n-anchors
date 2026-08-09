extends SceneTree

const TestReport := preload("res://tests/support/test_report.gd")


func _initialize() -> void:
	var t := TestReport.new("solar_cycle_test")
	var dawn := SolarCycle.sample(SolarCycle.SUNRISE_HOUR / 24.0)
	var noon := SolarCycle.sample(SolarCycle.SOLAR_NOON_HOUR / 24.0)
	var evening := SolarCycle.sample(18.0 / 24.0)
	var sunset := SolarCycle.sample(SolarCycle.SUNSET_HOUR / 24.0)

	t.check("Sunrise sits on the horizon", absf(float(dawn["altitude_degrees"])) < 0.05)
	t.check("Sunrise must be east", (dawn["sun_direction"] as Vector3).x > 0.0)
	t.check("Solar noon clears 51 degrees altitude", float(noon["altitude_degrees"]) > 51.0)
	t.check("Solar noon must be south", (noon["sun_direction"] as Vector3).z > 0.6)
	t.check("18:00 must not be night", float(evening["daylight"]) > 0.95)
	t.check("Sunset sits on the horizon", absf(float(sunset["altitude_degrees"])) < 0.05)
	t.check("Sunset must be west", (sunset["sun_direction"] as Vector3).x < 0.0)

	var previous := SolarCycle.sample(0.0)
	for minute in range(10, 1441, 10):
		var current := SolarCycle.sample(float(minute % 1440) / 1440.0)
		var light_delta := absf(float(current["daylight"]) - float(previous["daylight"]))
		var direction_delta := (current["sun_direction"] as Vector3).angle_to(
			previous["sun_direction"] as Vector3
		)
		t.check("Daylight discontinuity at minute %d" % minute, light_delta < 0.08)
		t.check("Sun-direction discontinuity at minute %d" % minute, direction_delta < 0.08)
		previous = current

	t.finish(self)
