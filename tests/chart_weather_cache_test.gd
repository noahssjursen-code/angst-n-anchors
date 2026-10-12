extends SceneTree

const SnapshotClass := preload("res://scripts/ui/chart/chart_data_snapshot.gd")
const RasterClass := preload("res://scripts/ui/chart/chart_raster_layer.gd")


func _initialize() -> void:
	var snapshot = SnapshotClass.for_preview(4451, 12)
	assert(snapshot.is_valid())
	var weather = RasterClass.new(RasterClass.Kind.WEATHER)
	var bounds := Rect2(-8000.0, -5000.0, 16000.0, 10000.0)
	assert(weather.prepare(snapshot, bounds, 100.0))
	var first := weather.debug_stats()
	assert(int(first["cache_rebuilds"]) == 1)
	assert(int(first["cache_cells"]) > 0)
	assert(int(first["samples"]) == int(first["cache_cells"]))
	assert(not weather.prepare(snapshot, bounds, 100.0))
	assert(int(weather.debug_stats()["cache_rebuilds"]) == 1)
	assert(weather.prepare(snapshot, bounds, 100.2))
	assert(int(weather.debug_stats()["cache_rebuilds"]) == 2)

	var layers := ChartLayerManager.new()
	layers.set_overlay_preferences(true, true)
	assert(not layers.is_visible("fishing"))
	print("Marine chart raster cache tests passed")
	quit()
