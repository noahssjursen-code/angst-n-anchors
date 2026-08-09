extends SceneTree

const SnapshotClass := preload("res://scripts/ui/chart/chart_data_snapshot.gd")
const RasterClass := preload("res://scripts/ui/chart/chart_raster_layer.gd")
const TestReport := preload("res://tests/support/test_report.gd")


func _initialize() -> void:
	var t := TestReport.new("chart_weather_cache_test")
	var snapshot = SnapshotClass.for_preview(4451, 12)
	if not t.check("preview snapshot is valid", snapshot.is_valid()):
		t.finish(self)
		return
	var weather = RasterClass.new(RasterClass.Kind.WEATHER)
	var bounds := Rect2(-8000.0, -5000.0, 16000.0, 10000.0)
	t.check("weather layer prepares", weather.prepare(snapshot, bounds, 100.0))
	var first := weather.debug_stats()
	t.equal("first prepare rebuilds the cache once", int(first["cache_rebuilds"]), 1)
	t.equal("weather cache fills the grid", int(first["cache_cells"]), RasterClass.COLS * RasterClass.ROWS)
	t.equal("weather cache samples every cell", int(first["samples"]), RasterClass.COLS * RasterClass.ROWS)
	t.check("a hair of clock drift does not rebuild", not weather.prepare(snapshot, bounds, 100.02))
	t.equal("rebuild count holds after the no-op prepare", int(weather.debug_stats()["cache_rebuilds"]), 1)
	t.check("crossing the drift threshold rebuilds", weather.prepare(snapshot, bounds, 100.06))
	t.equal("rebuild count advances after the drift", int(weather.debug_stats()["cache_rebuilds"]), 2)

	var fishing = RasterClass.new(RasterClass.Kind.FISHING)
	t.check("fishing layer prepares", fishing.prepare(snapshot, bounds, 100.0))
	var fishing_texture = fishing.texture
	t.check("fishing layer ignores clock drift", not fishing.prepare(snapshot, bounds, 500.0))
	t.check(
		"fishing layer ignores a bounds change",
		not fishing.prepare(snapshot, Rect2(-1000.0, -1000.0, 2000.0, 2000.0), 500.0),
	)
	t.check("fishing texture is reused", fishing.texture == fishing_texture)
	t.equal("fishing cache rebuilds only once", int(fishing.debug_stats()["cache_rebuilds"]), 1)
	t.equal(
		"fishing cache fills its own grid",
		int(fishing.debug_stats()["cache_cells"]),
		RasterClass.FISHING_RESOLUTION ** 2,
	)
	t.finish(self)
