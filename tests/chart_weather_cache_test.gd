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
	## Resolution is chosen per view span by `_weather_lod`, so a fixed
	## `COLS * ROWS` is only the answer at the closest tier. The two checks that
	## used to sit here asserted 768 against a 16 km view that legitimately
	## rasterises at 24x18 = 432 — a restated constant, not a property. What the
	## layer actually promises is a monotone ladder that tops out at the declared
	## grid, and a build that samples every cell of whichever tier it picked.
	var weather = RasterClass.new(RasterClass.Kind.WEATHER)
	var full_grid := RasterClass.COLS * RasterClass.ROWS
	var near_view := Rect2(-5000.0, -5000.0, 10000.0, 10000.0)
	t.check("weather layer prepares", weather.prepare(snapshot, near_view, 100.0))
	var first := weather.debug_stats()
	t.equal("first prepare rebuilds the cache once", int(first["cache_rebuilds"]), 1)
	t.equal("the closest view rasterises at the full declared grid", int(first["cache_cells"]), full_grid)
	t.equal("every cell of that grid was sampled", int(first["samples"]), int(first["cache_cells"]))

	var mid_cells := _cells_for_view(snapshot, Rect2(-8000.0, -5000.0, 16000.0, 10000.0))
	var far_cells := _cells_for_view(snapshot, Rect2(-20000.0, -20000.0, 40000.0, 40000.0))
	t.check(
		"a 16 km view rasterises coarser than the closest tier (%d < %d)" % [mid_cells, full_grid],
		mid_cells < full_grid,
	)
	t.check(
		"a 40 km view rasterises coarser still (%d < %d)" % [far_cells, mid_cells],
		far_cells < mid_cells,
	)
	t.check("the coarsest tier still has cells to draw (%d)" % far_cells, far_cells > 0)

	## Clock expiry, stated against the declared max age rather than against the
	## 0.02 h / 0.06 h literals that were chosen when WEATHER_MAX_AGE_H was 0.05.
	## Nine samples half a bucket apart: the whole-bucket steps must rebuild and
	## the half-bucket steps must not, whatever the constant is.
	var age := RasterClass.WEATHER_MAX_AGE_H
	var drift = RasterClass.new(RasterClass.Kind.WEATHER)
	t.check("the drift layer prepares", drift.prepare(snapshot, near_view, 1250.0 * age))
	var whole_step_rebuilds := 0
	var half_step_reuses := 0
	for step in range(1, 9):
		var rebuilt: bool = drift.prepare(snapshot, near_view, (1250.0 + 0.5 * float(step)) * age)
		if step % 2 == 0:
			if rebuilt:
				whole_step_rebuilds += 1
		elif not rebuilt:
			half_step_reuses += 1
	t.equal("every whole max-age step expires the cache", whole_step_rebuilds, 4)
	t.equal("every half max-age step reuses it", half_step_reuses, 4)
	t.equal(
		"rebuild count advanced once per expiry",
		int(drift.debug_stats()["cache_rebuilds"]),
		5,
	)

	## The fishing layer's own bounds are irrelevant to it — it always covers the
	## whole macro map — which is what the next three checks say.
	var bounds := Rect2(-8000.0, -5000.0, 16000.0, 10000.0)
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


## Cells a fresh weather layer rasterises for one view. Fresh, so the LOD is
## chosen from the view alone and not inherited from a previous prepare.
func _cells_for_view(snapshot, view: Rect2) -> int:
	var layer = RasterClass.new(RasterClass.Kind.WEATHER)
	layer.prepare(snapshot, view, 0.0)
	return int(layer.debug_stats()["cache_cells"])
