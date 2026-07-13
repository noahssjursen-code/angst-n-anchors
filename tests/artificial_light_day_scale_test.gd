extends SceneTree

## Daylight artificial-light scales must preserve night and crush noon wash.

var _failures := PackedStringArray()


func _initialize() -> void:
	var weather := load("res://scripts/weather/weather_lighting.gd").new()
	root.add_child(weather)

	weather.time_of_day = 0.0
	weather.visibility = 1.0
	_check_close(weather.daylight_factor(), 0.0, "midnight daylight")
	_check_close(weather.artificial_light_scale(), 1.0, "midnight light scale")
	_check_close(weather.artificial_volumetric_scale(), 1.0, "midnight vol scale")

	weather.time_of_day = 0.5
	_check(weather.daylight_factor() > 0.95, "noon daylight near 1")
	_check(weather.artificial_light_scale() < 0.08, "noon light scale tiny")
	_check(weather.artificial_volumetric_scale() < 0.02, "noon clear vol scale ~0")

	weather.visibility = 0.4
	_check(
		weather.artificial_volumetric_scale() > 0.1
		and weather.artificial_volumetric_scale() < 0.35,
		"noon fog keeps some vol scatter"
	)

	weather.queue_free()
	_finish()


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)


func _check_close(actual: float, expected: float, label: String) -> void:
	_check(absf(actual - expected) < 0.001, "%s (%f != %f)" % [label, actual, expected])


func _finish() -> void:
	if _failures.is_empty():
		print("ArtificialLightDayScale tests: all deterministic checks passed")
		quit()
		return
	for failure in _failures:
		push_error("ArtificialLightDayScale test: " + failure)
	quit(1)
