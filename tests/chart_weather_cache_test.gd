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
	assert(int(first["cache_cells"]) == RasterClass.COLS * RasterClass.ROWS)
	assert(int(first["samples"]) == RasterClass.COLS * RasterClass.ROWS)
	assert(not weather.prepare(snapshot, bounds, 100.02))
	assert(int(weather.debug_stats()["cache_rebuilds"]) == 1)
	assert(weather.prepare(snapshot, bounds, 100.06))
	assert(int(weather.debug_stats()["cache_rebuilds"]) == 2)

	var fishing = RasterClass.new(RasterClass.Kind.FISHING)
	assert(fishing.prepare(snapshot, bounds, 100.0))
	var fishing_texture = fishing.texture
	assert(not fishing.prepare(snapshot, bounds, 500.0))
	assert(not fishing.prepare(snapshot, Rect2(-1000.0, -1000.0, 2000.0, 2000.0), 500.0))
	assert(fishing.texture == fishing_texture)
	assert(int(fishing.debug_stats()["cache_rebuilds"]) == 1)
	assert(int(fishing.debug_stats()["cache_cells"]) == RasterClass.FISHING_RESOLUTION ** 2)
	print("Marine chart raster cache tests passed")
	quit()
