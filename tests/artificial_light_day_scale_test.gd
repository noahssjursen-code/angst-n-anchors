extends SceneTree

## Daylight artificial-light scales must preserve night and crush noon wash.

var _failures := PackedStringArray()


func _initialize() -> void:
	var weather: Node = load("res://scripts/weather/weather_lighting.gd").new()
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

	weather.visibility = 1.0
	weather.time_of_day = 18.0 / 24.0
	_check(weather.daylight_factor() > 0.95, "18:00 remains full daylight")
	_check(weather.artificial_light_scale() < 0.1, "18:00 artificial lights stay dim")
	weather.time_of_day = 21.0 / 24.0
	_check(weather.daylight_factor() > 0.7, "21:00 preserves long evening light")
	weather.time_of_day = 23.0 / 24.0
	_check(weather.daylight_factor() < 0.1, "23:00 reaches night")
	_check(weather.artificial_light_scale() > 0.85, "23:00 artificial lights are active")

	var fixture := Node3D.new()
	var controller := BuildingLighting.new()
	var building_light := OmniLight3D.new()
	building_light.set_meta("building_light_base_energy", 4.0)
	building_light.set_meta("building_light_base_volumetric", 0.5)
	var lens := MeshInstance3D.new()
	var lens_material := StandardMaterial3D.new()
	lens_material.emission_enabled = true
	lens_material.emission_energy_multiplier = 2.4
	lens.material_override = lens_material
	lens.set_meta("building_lens_base_emission", 2.4)
	fixture.add_child(controller)
	fixture.add_child(building_light)
	fixture.add_child(lens)
	controller.call("_apply_node", fixture, 0.05, 0.2)
	_check_close(building_light.light_energy, 0.2, "building noon light scale")
	_check_close(building_light.light_volumetric_fog_energy, 0.1, "building noon vol scale")
	_check_close(lens_material.emission_energy_multiplier, 0.12, "building noon lens scale")
	fixture.free()

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
