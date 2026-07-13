extends SceneTree

const MAP_WEATHER_VIEW := preload("res://scripts/ui/map/map_weather_view.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var world_weather := root.get_node_or_null("WorldWeather")
	assert(world_weather != null)
	var ports: Array[Vector3] = []
	world_weather.call("initialize", 4451, ports)
	var view := MAP_WEATHER_VIEW.new()
	assert(MAP_WEATHER_VIEW.wind_to_screen_direction(Vector3(0.0, 0.0, 1.0)) == Vector2(0.0, -1.0))
	assert(MAP_WEATHER_VIEW.wind_to_screen_direction(Vector3(1.0, 0.0, 0.0)) == Vector2(1.0, 0.0))
	var ctx := {
		"wx_min": -8000.0, "wx_max": 8000.0,
		"wz_min": -5000.0, "wz_max": 5000.0,
		"cpx": 0.0, "cpy": 0.0, "cpw": 1200.0, "cph": 700.0,
	}
	var grid := view.call("_grid", ctx) as Dictionary
	view.call("_ensure_cache", 100.0, grid)
	var initial := view.get_debug_stats()
	assert(int(initial["cache_rebuilds"]) == 1)
	assert(int(initial["cache_cells"]) > 0)
	view.call("_ensure_cache", 100.02, grid)
	assert(int(view.get_debug_stats()["cache_rebuilds"]) == 1)
	view.call("_ensure_cache", 100.06, grid)
	assert(int(view.get_debug_stats()["cache_rebuilds"]) == 2)
	ctx["wx_min"] = -4000.0
	ctx["wx_max"] = 12000.0
	view.call("_ensure_cache", 100.06, view.call("_grid", ctx))
	assert(int(view.get_debug_stats()["cache_rebuilds"]) == 3)
	print("Chart weather cache tests: bounded invalidation passed")
	quit()
