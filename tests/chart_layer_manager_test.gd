extends SceneTree

const ChartCameraClass = preload("res://scripts/ui/chart/chart_camera.gd")
const ChartLayerManagerClass = preload("res://scripts/ui/chart/chart_layer_manager.gd")

var _failures := PackedStringArray()


func _initialize() -> void:
	var layers := ChartLayerManagerClass.new()
	_check(layers.preset == ChartLayerManagerClass.Preset.COASTAL, "default preset is Coastal")
	_check(not layers.is_visible("weather"), "default has no pressure wash")
	_check(layers.is_visible("traffic"), "Coastal shows AIS traffic")
	_check(not layers.is_visible("approaches"), "Coastal hides berth approaches")

	var stable_key := layers.cache_key()
	_check(stable_key == layers.cache_key(), "unchanged layer cache key is stable")
	var revision := layers.revision
	layers.set_visible("weather", true)
	_check(layers.cache_key() != stable_key, "layer toggle invalidates cache key")
	_check(layers.revision == revision + 1, "layer toggle advances revision once")
	layers.set_visible("weather", true)
	_check(layers.revision == revision + 1, "no-op toggle preserves cache revision")

	layers.apply_preset(ChartLayerManagerClass.Preset.HARBOUR)
	_check(layers.is_visible("approaches"), "Harbour shows berth approaches")
	_check(not layers.is_visible("weather"), "Harbour remains uncluttered")
	layers.apply_preset(ChartLayerManagerClass.Preset.PASSAGE)
	_check(not layers.is_visible("annotations"), "Passage suppresses port labels")
	_check(layers.is_visible("nav_vectors"), "Passage keeps navigation vectors")
	layers.apply_preset(ChartLayerManagerClass.Preset.WEATHER)
	_check(layers.is_visible("weather"), "Weather preset shows weather")
	_check(not layers.is_visible("traffic"), "Weather preset declutters traffic")

	var camera := ChartCameraClass.new()
	camera.home(Vector3(100.0, 0.0, -200.0), [])
	var bounds := camera.world_bounds(Vector2(800.0, 400.0))
	_check(bounds.has_point(Vector2(100.0, -200.0)), "home keeps ship in camera bounds")
	_finish()


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)


func _finish() -> void:
	if _failures.is_empty():
		print("ChartLayerManager tests: all deterministic checks passed")
		quit()
		return
	for failure in _failures:
		push_error("ChartLayerManager test: " + failure)
	quit(1)
