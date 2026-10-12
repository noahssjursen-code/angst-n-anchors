extends Node

var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	for seed_value in [42, 1212599375, 77127]:
		var layout := WorldLayoutGenerator.generate(seed_value)
		var deepest := 0.0
		var shallowest := INF
		var water_samples := 0
		for z in range(-19000, 19000, 500):
			for x in range(-19000, 19000, 500):
				var at := Vector2(x, z)
				var height := layout.sample_seabed_elevation(at)
				check(is_finite(height), "Finite terrain")
				if layout.is_land(at):
					continue
				water_samples += 1
				var depth := layout.sample_water_depth(at)
				deepest = maxf(deepest, depth)
				shallowest = minf(shallowest, depth)
				check(depth > 0.0, "No accidental new land")
				check(is_equal_approx(height, WorldTerrainStreamer.sample_render_terrain_height(layout, at)), "Depth and rendered datum agree")
				check(is_equal_approx(depth, layout.sample_water_depth(at)), "Stable sampling")
				check(is_equal_approx(layout.sample_water_depth(at, WaveSurface.WATER_LEVEL + 2), depth + 2), "Water-level offset")
		check(water_samples > 100 and deepest > 150 and shallowest < 20, "Shelf/basin range")
		print("SEABED seed=", seed_value, " depth=", shallowest, "..", deepest)
		var shelves := 0
		for feature in layout.skerry_features():
			var polygon: PackedVector2Array = feature.polygon
			if polygon.size() < 2:
				continue
			for edge in range(0, polygon.size(), maxi(1, polygon.size() / 4)):
				var a: Vector2 = polygon[edge]
				var b: Vector2 = polygon[(edge + 1) % polygon.size()]
				var mid := (a + b) * 0.5
				var outward := (b - a).orthogonal().normalized()
				if outward.length_squared() < 0.5:
					continue
				if layout.is_land(mid + outward * 40.0):
					outward = -outward
				if layout.is_land(mid + outward * 40.0) or layout.is_land(mid + outward * 80.0):
					continue
				var near := layout.sample_water_depth(mid + outward * 40.0)
				var mid_depth := layout.sample_water_depth(mid + outward * 80.0)
				check(near >= 8.0 and near <= 42.0, "Small-island foot stays near crab depth at 40 m, got %s" % near)
				check(mid_depth < near + 40.0, "Small-island foot does not drop tens of metres in the next 40 m")
				shelves += 1
				break
			if shelves >= 6:
				break
		check(shelves >= 3, "Sampled small-island shelves")
		# Adjacent mesh edges share exact positions at the same LOD.
		var left := WorldTerrainStreamer.build_chunk_mesh_data(layout, Vector2i(-10, 0), 100.0)
		var right := WorldTerrainStreamer.build_chunk_mesh_data(layout, Vector2i(-9, 0), 100.0)
		check(left.indices.size() >= 600, "Open ocean has a complete floor")
		for row in range(11):
			check(left.vertices[row * 11 + 10] == right.vertices[row * 11], "Chunk boundary continuity")
	var layers := ChartLayerManager.new()
	layers.apply_preset(ChartLayerManager.Preset.FISHING)
	layers.set_visible("fishing", true)
	check(not layers.is_visible("fishing"), "Legacy settings cannot expose fish")
	var snapshot := ChartDataSnapshot.for_preview(1212599375, 35)
	var renderer := ChartLayerRenderer.new()
	renderer.set_snapshot(snapshot)
	var sample_at := Vector2(-10000, 0)
	var rows := renderer.overlay_readout(sample_at, layers, 0)
	check(rows.any(func(row: String): return row.begins_with("Chart depth")), "Chart exposes depth")
	check(not rows.any(func(row: String): return row.begins_with("Fishing")), "Chart cannot reveal fish")
	check(renderer.base.texture != null, "Depth chart raster built")
	var weather := ChartRasterLayer.new()
	var bounds := Rect2(-8000, -5000, 16000, 10000)
	check(weather.prepare(snapshot, bounds, 100), "Weather raster still builds")
	check(not weather.prepare(snapshot, bounds, 100), "Weather raster still caches")
	print("SEABED RESULT failures=", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
