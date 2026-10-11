extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_weighted_pairings()
	_test_determinism_and_continuity()
	_test_decoupled_dimensions()
	_test_rain_cloud_support()
	_test_lightning_events()
	_test_chart_and_route_parity()
	_test_weather_version_context()
	print("Weather composer contract: all checks passed")
	quit()


func _test_weighted_pairings() -> void:
	assert(not WeatherProfileCatalog.profile().is_empty())
	for x in range(-12, 13):
		for z in range(-8, 9):
			var ids := WeatherCellSampler.sample_component_ids(
				7219,
				Vector3((float(x) + 0.5) * 6000.0, 0.0, (float(z) + 0.5) * 6000.0),
				0.0,
			)
			var sky := str(ids.get("sky", ""))
			var rain := str(ids.get("precipitation", ""))
			var convection := str(ids.get("convection", "none"))
			var wind := str(ids.get("wind", ""))
			var fog := str(ids.get("fog", ""))
			if sky in ["clear", "light_cloud"]:
				assert(rain == "none", "fair sky must not select rain")
				assert(convection == "none")
			if convection != "none":
				assert(sky in ["broken", "overcast"])
				assert(rain in ["rain", "heavy_rain"])
			assert(not (wind == "gale" and fog == "dense"))


func _test_determinism_and_continuity() -> void:
	WeatherField.world_seed = 44331
	WeatherFrontField.initialize(44331)
	var p := Vector3(3111.0, 0.0, -7222.0)
	var a := WeatherComposer.sample(p, 124.75)
	var b := WeatherComposer.sample(p, 124.75)
	assert(a.component_ids == b.component_ids)
	assert(a.weather_cell_id == b.weather_cell_id)
	assert(is_equal_approx(a.sea_state, b.sea_state))
	assert(is_equal_approx(a.convection_index, b.convection_index))

	var near := WeatherComposer.sample(p + Vector3(1.0, 0.0, 1.0), 124.75)
	assert(absf(a.cloud_cover - near.cloud_cover) < 0.02)
	assert(absf(a.sea_state - near.sea_state) < 0.02)

	var before := WeatherComposer.sample(p, 18.0 - 0.0001)
	var after := WeatherComposer.sample(p, 18.0 + 0.0001)
	assert(absf(before.precipitation - after.precipitation) < 0.01)
	assert(absf(before.wind_force - after.wind_force) < 0.01)


func _test_decoupled_dimensions() -> void:
	var lighting := WeatherLightingState.new()
	lighting.sea_state = 1.0
	lighting.wind_force = 1.0
	lighting.precipitation = 0.0
	lighting.cloud_cover = 0.05
	lighting.convection_index = 0.0
	assert(is_zero_approx(lighting.thunder_intensity), "sea/wind must not create thunder")
	assert(is_zero_approx(lighting.storm_intensity), "dry swell must not darken the storm grade")

	var fog_mood := WeatherProfileCatalog.mood("foggy_calm")
	assert(str(fog_mood["precipitation"]) == "none")
	assert(str(fog_mood["fog"]) == "dense")
	var rain_mood := WeatherProfileCatalog.mood("rainy_medium_sea")
	assert(str(rain_mood["precipitation"]) == "heavy_rain")
	assert(str(rain_mood["fog"]) == "none")
	var dry_gale := WeatherProfileCatalog.mood("dry_gale")
	assert(str(dry_gale["wind"]) == "gale")
	assert(str(dry_gale["convection"]) == "none")
	lighting.free()

	# Harbour geography shelters waves only — not sky/rain/fog.
	LandField.initialize([{
		"center": Vector3.ZERO,
		"half_x": 250.0,
		"half_z": 500.0,
		"rotation_y": 0.0,
	}])
	WeatherField.world_seed = 7711
	WeatherFrontField.initialize(7711)
	var harbour_pos := Vector3(260.0, 0.0, 0.0)
	var open_pos := Vector3(6500.0, 0.0, 0.0)
	var hour := 240.0
	var base := WeatherField.sample(harbour_pos, hour)
	var harbour := WeatherComposer.sample(harbour_pos, hour)
	var open_water := WeatherComposer.sample(open_pos, hour)
	assert(harbour.exposure < 0.05)
	assert(harbour.significant_wave_height_m < 1.25)
	assert(open_water.significant_wave_height_m >= harbour.significant_wave_height_m)
	assert(absf(harbour.precipitation - base.precipitation) < 0.05)
	assert(absf(harbour.cloud_cover - base.cloud_cover) < 0.25)
	assert(absf(harbour.visibility - base.visibility) < 0.2)


func _test_rain_cloud_support() -> void:
	# Presentation must stay coherent through arrival/departure of a rain cell,
	# including manual invalid combinations and repeated smoothing.
	var lighting := WeatherLightingState.new()
	var clear := WeatherState.new()
	clear.cloud_cover = 0.08
	clear.precipitation = 0.8
	lighting.apply_weather_state(clear)
	assert(is_zero_approx(lighting.rain_amount))
	var wet := WeatherState.new()
	wet.cloud_cover = 0.9
	wet.precipitation = 0.8
	for iteration in 90:
		lighting.blend_towards(wet if iteration < 45 else clear, 0.08)
		assert(lighting.precipitation <= clampf((lighting.cloud_cover - 0.4) / 0.5, 0.0, 1.0) + 0.00001)
	lighting.free()
	WeatherField.world_seed = 44331
	WeatherFrontField.initialize(44331)
	var dry_samples := 0
	var wet_samples := 0
	for hour in [0.0, 7.0, 13.9, 14.1, 31.0]:
		for x in range(-10, 11):
			for z in range(-10, 11):
				var sample := WeatherComposer.sample_chart(Vector3(x * 1733.0, 0.0, z * 2117.0), hour)
				assert(sample.precipitation <= clampf((sample.cloud_cover - 0.4) / 0.5, 0.0, 1.0) + 0.00001)
				if sample.cloud_cover < 0.4:
					assert(is_zero_approx(sample.precipitation))
				if sample.precipitation > 0.45:
					wet_samples += 1
				if sample.precipitation < 0.01:
					dry_samples += 1
	assert(wet_samples > 0 and dry_samples > 0, "coherence must retain both rain and dry weather")
	print("Rain support sweep: 2205 samples, %s wet / %s dry" % [wet_samples, dry_samples])


func _test_lightning_events() -> void:
	var event_a := WeatherEventClock.lightning_for_window(91, "4:2:-1", 812, 1.0)
	var event_b := WeatherEventClock.lightning_for_window(91, "4:2:-1", 812, 1.0)
	assert(event_a == event_b)
	assert(not bool(WeatherEventClock.lightning_for_window(91, "4:2:-1", 812, 0.0)["occurs"]))


func _test_chart_and_route_parity() -> void:
	var world_weather := root.get_node_or_null("WorldWeather")
	assert(world_weather != null)
	var ports: Array[Vector3] = []
	world_weather.call("initialize", 8891, ports)
	var p := Vector3(2200.0, 0.0, -4300.0)
	var hour := 61.25
	var canonical := world_weather.call("sample_at", p, hour) as WeatherSample
	var raster := ChartRasterLayer.new(ChartRasterLayer.Kind.WEATHER)
	var chart := raster.sample_at(Vector2(p.x, p.z), hour)
	assert(is_equal_approx(float(chart["sea_state"]), canonical.sea_state))
	assert(is_equal_approx(float(chart["precipitation"]), canonical.precipitation))
	assert(chart["component_ids"] == canonical.component_ids)

	var route := PackedVector3Array([p, p + Vector3(1500.0, 0.0, 0.0)])
	var forecast: Array = world_weather.call("sample_route", route, 500.0, hour)
	assert(forecast.size() == 4)
	var first := forecast[0]["weather"] as WeatherSample
	assert(is_equal_approx(first.cloud_cover, canonical.cloud_cover))


func _test_weather_version_context() -> void:
	var current := {
		"seed": 42,
		"generation_version": 1,
		"weather_generation_version": 3,
		"layout_checksum": "same",
	}
	var old_weather := current.duplicate()
	old_weather["weather_generation_version"] = 0
	assert(not WorldGenerationContext.matches(old_weather, current))
	var legacy := current.duplicate()
	legacy.erase("weather_generation_version")
	assert(WorldGenerationContext.matches(legacy, current))
