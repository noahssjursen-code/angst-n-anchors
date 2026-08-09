extends SceneTree

const TestReport := preload("res://tests/support/test_report.gd")

var _t: RefCounted


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	# The pairing sweep records thousands of checks; only failures are printed.
	_t = TestReport.new("weather_composer_contract_test", false)
	_test_weighted_pairings()
	_test_determinism_and_continuity()
	_test_decoupled_dimensions()
	_test_lightning_events()
	_test_chart_and_route_parity()
	_test_weather_version_context()
	_t.finish(self)


func _test_weighted_pairings() -> void:
	_t.check("weather profile catalog is populated", not WeatherProfileCatalog.profile().is_empty())
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
			if sky == "clear":
				_t.check("cell %d,%d: clear sky excludes heavy rain" % [x, z], rain != "heavy_rain")
				_t.check("cell %d,%d: clear sky excludes convection" % [x, z], convection == "none")
			if convection != "none":
				_t.check("cell %d,%d: convection needs a broken or overcast sky" % [x, z], sky in ["broken", "overcast"])
				_t.check("cell %d,%d: convection needs rain" % [x, z], rain in ["rain", "heavy_rain"])
			_t.check("cell %d,%d: gale never pairs with dense fog" % [x, z], not (wind == "gale" and fog == "dense"))


func _test_determinism_and_continuity() -> void:
	WeatherField.world_seed = 44331
	WeatherFrontField.initialize(44331)
	var p := Vector3(3111.0, 0.0, -7222.0)
	var a := WeatherComposer.sample(p, 124.75)
	var b := WeatherComposer.sample(p, 124.75)
	_t.check("repeat sample keeps component ids", a.component_ids == b.component_ids)
	_t.check("repeat sample keeps the weather cell id", a.weather_cell_id == b.weather_cell_id)
	_t.check("repeat sample keeps the sea state", is_equal_approx(a.sea_state, b.sea_state))
	_t.check("repeat sample keeps the convection index", is_equal_approx(a.convection_index, b.convection_index))

	var near := WeatherComposer.sample(p + Vector3(1.0, 0.0, 1.0), 124.75)
	_t.check("cloud cover is continuous over a metre", absf(a.cloud_cover - near.cloud_cover) < 0.02)
	_t.check("sea state is continuous over a metre", absf(a.sea_state - near.sea_state) < 0.02)

	var before := WeatherComposer.sample(p, 18.0 - 0.0001)
	var after := WeatherComposer.sample(p, 18.0 + 0.0001)
	_t.check("precipitation is continuous across hour 18", absf(before.precipitation - after.precipitation) < 0.01)
	_t.check("wind force is continuous across hour 18", absf(before.wind_force - after.wind_force) < 0.01)


func _test_decoupled_dimensions() -> void:
	var lighting := WeatherLightingState.new()
	lighting.sea_state = 1.0
	lighting.wind_force = 1.0
	lighting.precipitation = 0.0
	lighting.cloud_cover = 0.05
	lighting.convection_index = 0.0
	_t.check("sea/wind must not create thunder", is_zero_approx(lighting.thunder_intensity))
	_t.check("dry swell must not darken the storm grade", is_zero_approx(lighting.storm_intensity))

	var fog_mood := WeatherProfileCatalog.mood("foggy_calm")
	_t.check("foggy_calm brings no precipitation", str(fog_mood["precipitation"]) == "none")
	_t.check("foggy_calm brings dense fog", str(fog_mood["fog"]) == "dense")
	var rain_mood := WeatherProfileCatalog.mood("rainy_medium_sea")
	_t.check("rainy_medium_sea brings heavy rain", str(rain_mood["precipitation"]) == "heavy_rain")
	_t.check("rainy_medium_sea brings no fog", str(rain_mood["fog"]) == "none")
	var dry_gale := WeatherProfileCatalog.mood("dry_gale")
	_t.check("dry_gale blows a gale", str(dry_gale["wind"]) == "gale")
	_t.check("dry_gale carries no convection", str(dry_gale["convection"]) == "none")
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
	_t.check("harbour is sheltered from exposure", harbour.exposure < 0.05)
	_t.check("harbour keeps a low significant wave height", harbour.significant_wave_height_m < 1.25)
	_t.check(
		"open water is never calmer than the harbour",
		open_water.significant_wave_height_m >= harbour.significant_wave_height_m,
	)
	_t.check("shelter leaves precipitation alone", absf(harbour.precipitation - base.precipitation) < 0.05)
	_t.check("shelter leaves cloud cover alone", absf(harbour.cloud_cover - base.cloud_cover) < 0.25)
	_t.check("shelter leaves visibility alone", absf(harbour.visibility - base.visibility) < 0.2)


func _test_lightning_events() -> void:
	var event_a := WeatherEventClock.lightning_for_window(91, "4:2:-1", 812, 1.0)
	var event_b := WeatherEventClock.lightning_for_window(91, "4:2:-1", 812, 1.0)
	_t.check("lightning window is deterministic", event_a == event_b)
	_t.check(
		"no convection means no lightning",
		not bool(WeatherEventClock.lightning_for_window(91, "4:2:-1", 812, 0.0)["occurs"]),
	)


func _test_chart_and_route_parity() -> void:
	var world_weather := root.get_node_or_null("WorldWeather")
	if not _t.check("WorldWeather is available", world_weather != null):
		return
	var ports: Array[Vector3] = []
	world_weather.call("initialize", 8891, ports)
	var p := Vector3(2200.0, 0.0, -4300.0)
	var hour := 61.25
	var canonical := world_weather.call("sample_at", p, hour) as WeatherSample
	var raster := ChartRasterLayer.new(ChartRasterLayer.Kind.WEATHER)
	var chart := raster.sample_at(Vector2(p.x, p.z), hour)
	_t.check("chart layer matches the canonical sea state", is_equal_approx(float(chart["sea_state"]), canonical.sea_state))
	_t.check(
		"chart layer matches the canonical precipitation",
		is_equal_approx(float(chart["precipitation"]), canonical.precipitation),
	)
	_t.check("chart layer matches the canonical component ids", chart["component_ids"] == canonical.component_ids)

	var route := PackedVector3Array([p, p + Vector3(1500.0, 0.0, 0.0)])
	var forecast: Array = world_weather.call("sample_route", route, 500.0, hour)
	if not _t.check("route forecast has four samples", forecast.size() == 4):
		return
	var first := forecast[0]["weather"] as WeatherSample
	_t.check("route forecast starts at the canonical cloud cover", is_equal_approx(first.cloud_cover, canonical.cloud_cover))


func _test_weather_version_context() -> void:
	var current := {
		"seed": 42,
		"generation_version": 1,
		"weather_generation_version": 3,
		"layout_checksum": "same",
	}
	var old_weather := current.duplicate()
	old_weather["weather_generation_version"] = 0
	_t.check("a stale weather generation version does not match", not WorldGenerationContext.matches(old_weather, current))
	var legacy := current.duplicate()
	legacy.erase("weather_generation_version")
	_t.check("a legacy context without a weather version still matches", WorldGenerationContext.matches(legacy, current))
