extends Node

## Independent acceptance checks for real exposed skerries, including the
## consumers which previously saw only the coarse mainland raster.
var _failures := PackedStringArray()


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	if OS.get_cmdline_user_args().has("--critic-route-probe"):
		var layout := WorldLayoutGenerator.generate(42)
		_test_routes_around_skerries(layout, layout.skerry_features())
		get_tree().quit(0 if _failures.is_empty() else 1)
		return
	if OS.get_cmdline_user_args().has("--critic-mesh-probe"):
		var layout := WorldLayoutGenerator.generate(42)
		for step in [25.0, 200.0]:
			_probe_mesh_area(layout, Vector2i(15, -5), step)
		get_tree().quit()
		return
	for seed_value in [42, 1212599375, 77127]:
		var start := Time.get_ticks_msec()
		var layout := WorldLayoutGenerator.generate(seed_value)
		if not layout.has_method("skerry_features"):
			_check(false, "WorldLayout exposes immutable skerry feature records")
			break
		var features: Array = layout.call("skerry_features")
		_test_field(layout, features)
		_test_navigation_raster(layout, features)
		_test_chart(layout, features)
		_test_routes_around_skerries(layout, features)
		_test_waterways(layout)
		_test_rendered_land(layout, features)
		print("SKERRY ACCEPTANCE seed=", seed_value, " features=", features.size(),
			" elapsed_ms=", Time.get_ticks_msec() - start)
		await get_tree().process_frame
	if _failures.is_empty():
		print("coastal_skerries_test: PASS")
	else:
		for failure in _failures: push_error(failure)
		print("coastal_skerries_test: FAIL (", _failures.size(), ")")
	get_tree().quit(0 if _failures.is_empty() else 1)


func _test_field(layout: WorldLayout, features: Array) -> void:
	_check(features.size() >= 30, "Coast has more than a token handful of exposed rocks")
	var sizes := [0, 0, 0]
	var coastal_cells: Dictionary = {}
	var groups: Dictionary = {}
	var original_land := 0
	var bad_centers := 0
	var checked_shore := 0
	var bad_shore := 0
	for feature: Dictionary in features:
		var center: Vector2 = feature.position
		var polygon: PackedVector2Array = feature.polygon
		var bounds := _bounds(polygon)
		var width := maxf(bounds.size.x, bounds.size.y)
		sizes[0 if width < 70.0 else (1 if width < 220.0 else 2)] += 1
		coastal_cells[Vector2i(floori(center.x / 3000.0), floori(center.y / 3000.0))] = true
		if feature.has("group"): groups[feature.group] = int(groups.get(feature.group, 0)) + 1
		if float(layout.call("sample_macro_signed_distance", center)) <= 0.0: original_land += 1
		if not layout.is_land(center) or layout.sample_water_depth(center) > 0.0 \
				or layout.sample_seabed_elevation(center) <= WaveSurface.WATER_LEVEL:
			bad_centers += 1
		for i in range(polygon.size()):
			var shore := polygon[i].lerp(polygon[(i + 1) % polygon.size()], 0.5)
			# Overlaps with another skerry or mainland can bury this edge; only
			# assess edges which remain actual boundaries of the union.
			if absf(layout.sample_signed_distance(shore)) > 0.05: continue
			checked_shore += 1
			if absf(layout.sample_seabed_elevation(shore) - WaveSurface.WATER_LEVEL) > 0.15:
				bad_shore += 1
	_check(original_land == 0, "New skerries occupy previously empty water")
	_check(bad_centers == 0, "Exposed rock centers agree across land, depth and terrain height")
	_check(coastal_cells.size() >= 8, "Skerry detail covers several separated coastal stretches")
	for i in range(sizes.size()):
		_check(sizes[i] >= 5, "Coast contains multiple exposed rocks in size band %d" % i)
	_check(checked_shore > 20 and bad_shore == 0, "Analytic coast and physical sea-level crossing agree")
	print("  field: size_bands=", sizes, " coastal_3km_cells=", coastal_cells.size(),
		" shore_edges=", checked_shore, " bad_centers=", bad_centers, " bad_edges=", bad_shore)
	var grouped := 0
	var largest_group := 0
	for size in groups.values():
		if int(size) >= 3: grouped += int(size)
		largest_group = maxi(largest_group, int(size))
	print("  clusters: groups=", groups.size(), " rocks_in_groups_of_3plus=", grouped,
		" largest_group=", largest_group)


func _test_navigation_raster(layout: WorldLayout, features: Array) -> void:
	var raster := layout.get_signed_distance_raster()
	var missed := 0
	var half := layout.half_extent_m
	var cell := layout.cell_size_m
	var resolution := layout.raster_resolution
	for feature: Dictionary in features:
		var center: Vector2 = feature.position
		var grid := Vector2i(roundi((center.x + half) / cell), roundi((center.y + half) / cell))
		if grid.x < 0 or grid.y < 0 or grid.x >= resolution or grid.y >= resolution: continue
		# A sub-cell skerry must reserve at least its nearest sea-grid node.
		if raster[grid.y * resolution + grid.x] >= WaterwayNavigation.ROUTE_SHORE_CLEARANCE_M:
			missed += 1
	_check(missed == 0, "Navigation occupancy includes skerries smaller than a macro cell")
	print("  navigation: unreserved_skerry_centers=", missed)


func _test_chart(layout: WorldLayout, features: Array) -> void:
	if features.is_empty(): return
	var smallest: Dictionary = features[0]
	for feature: Dictionary in features:
		if _bounds(feature.polygon).get_area() < _bounds(smallest.polygon).get_area(): smallest = feature
	var center: Vector2 = smallest.position
	var polygon: PackedVector2Array = smallest.polygon
	var index := ChartCoastlineIndex.new()
	index.prepare(layout)
	var segments := index.segments_in(_bounds(polygon).grow(1.0))
	var found_edge := false
	for segment in segments:
		if segment.size() == 2 and segment[0].distance_to(polygon[0]) < 0.01 \
				and segment[1].distance_to(polygon[1]) < 0.01:
			found_edge = true
	_check(found_edge, "Vector chart index includes sub-cell skerry coastline")
	var texture := ChartBaseRaster._bake_region(layout, Rect2(center-Vector2.ONE*128.0, Vector2.ONE*256.0), 128)
	var image := texture.get_image()
	var pixel := image.get_pixel(64, 64)
	_check(absf(pixel.r-ChartBaseRaster.LAND.r) < 0.005 or absf(pixel.r-ChartBaseRaster.COAST.r) < 0.005,
		"Detailed chart raster visibly includes the smallest exposed rock")


func _test_waterways(layout: WorldLayout) -> void:
	var newly_blocked := 0
	var probes := 0
	for way: Dictionary in layout.waterway_centerlines:
		var points: PackedVector2Array = way.points
		var widths: PackedFloat32Array = way.get("widths_m", PackedFloat32Array())
		for i in range(1, points.size()):
			var along := points[i] - points[i - 1]
			var normal := along.normalized().orthogonal()
			var steps := maxi(1, ceili(along.length() / 20.0))
			for step in range(steps + 1):
				var t := float(step) / float(steps)
				var center := points[i - 1].lerp(points[i], t)
				var width := float(way.width_m)
				if widths.size() == points.size(): width = lerpf(widths[i - 1], widths[i], t)
				for lateral in [-0.22, 0.0, 0.22]:
					var p: Vector2 = center + normal * width * float(lateral)
					if float(layout.call("sample_macro_signed_distance", p)) <= 0.0: continue
					probes += 1
					if layout.is_land(p): newly_blocked += 1
	_check(newly_blocked == 0, "Existing usable waterway corridors remain water")
	print("  waterways: probes=", probes, " newly_blocked=", newly_blocked)


func _test_routes_around_skerries(layout: WorldLayout, features: Array) -> void:
	var navigation := WaterwayNavigation.new(layout)
	var checked := 0
	var failures := 0
	var slowest_us := 0
	for feature: Dictionary in features:
		if checked >= 12: break
		var bounds := _bounds(feature.polygon)
		if maxf(bounds.size.x, bounds.size.y) > 100.0: continue
		var center: Vector2 = feature.position
		var reach := maxf(bounds.size.x, bounds.size.y) + 140.0
		var from := center - Vector2(reach, 0.0)
		var to := center + Vector2(reach, 0.0)
		if layout.sample_signed_distance(from) < 80.0 or layout.sample_signed_distance(to) < 80.0: continue
		var started_us := Time.get_ticks_usec()
		var route := navigation.route_points(from, to)
		slowest_us = maxi(slowest_us, Time.get_ticks_usec()-started_us)
		checked += 1
		if route.size() < 2:
			failures += 1
			print("  ROUTE FAILURE missing center=", center, " from=", from, " to=", to)
			continue
		var crosses_land := false
		var first_land := Vector2.INF
		for i in range(1, route.size()):
			var probes := maxi(1, ceili(route[i-1].distance_to(route[i]) / 3.0))
			for probe in range(probes + 1):
				var point := route[i-1].lerp(route[i], float(probe)/float(probes))
				if layout.is_land(point):
					crosses_land = true
					if not is_finite(first_land.x): first_land = point
		if crosses_land:
			failures += 1
			print("  ROUTE FAILURE crossing center=", center, " from=", from, " to=", to,
				" land=", first_land, " waypoints=", route)
	_check(checked >= 3 and failures == 0, "Actual routes between open water on opposite sides avoid small exposed skerries")
	print("  routes: tested=", checked, " crossing_or_missing=", failures,
		" slowest_ms=", float(slowest_us)/1000.0)


func _test_rendered_land(layout: WorldLayout, features: Array) -> void:
	if features.is_empty(): return
	var selected: Array[Dictionary] = []
	var smallest: Dictionary = features[0]
	var widest: Dictionary = features[0]
	var border: Dictionary = features[0]
	var border_distance := INF
	for feature: Dictionary in features:
		var bounds := _bounds(feature.polygon)
		if bounds.get_area() < _bounds(smallest.polygon).get_area(): smallest = feature
		if bounds.get_area() > _bounds(widest.polygon).get_area(): widest = feature
		var center: Vector2 = feature.position
		var edge := minf(minf(fposmod(center.x, 1000.0), 1000.0-fposmod(center.x, 1000.0)),
			minf(fposmod(center.y, 1000.0), 1000.0-fposmod(center.y, 1000.0)))
		if edge < border_distance:
			border_distance = edge
			border = feature
	selected.assign([smallest, widest, border])
	_test_lod_boundary(layout, border)
	for feature: Dictionary in selected:
		var center: Vector2 = feature.position
		var polygon: PackedVector2Array = feature.polygon
		var points := PackedVector2Array([center])
		for i in range(0, polygon.size(), 2):
			points.append(center.lerp(polygon[i], 0.5))
			points.append(center.lerp(polygon[i], 0.8))
		for step in [25.0, 200.0]:
			var meshes: Dictionary = {}
			var dry := 0
			var wet := 0
			var crest_height := NAN
			for point: Vector2 in points:
				if not layout.is_land(point): continue
				var coord := WorldTerrainStreamer.world_to_chunk(point)
				if not meshes.has(coord):
					meshes[coord] = WorldTerrainStreamer.build_chunk_mesh_data(layout, coord, step, [], 0.0)
				var height := _mesh_height(meshes[coord], point)
				if point == center: crest_height = height
				if is_finite(height) and height > WaveSurface.WATER_LEVEL: dry += 1
				else: wet += 1
			_check(is_finite(crest_height) and crest_height > WaveSurface.WATER_LEVEL,
				"Skerry remains visible at %.0f m terrain LOD (%.1f, %.1f)" % [step, center.x, center.y])
			_check(dry > wet * 3, "Most analytic land footprint survives actual %.0f m mesh" % step)
			for mesh: Dictionary in meshes.values():
				var area := _mesh_area(mesh)
				if absf(area-1000000.0) >= 3.0:
					print("  AREA FAILURE coord=", mesh.coord, " step=", step, " area=", area)
				_check(absf(area - 1000000.0) < 3.0, "Detailed island mesh tiles chunk without holes or overlaps")
			print("  mesh: step=", step, " center=", center, " dry=", dry, " wet=", wet,
				" chunks=", meshes.size(), " crest=", crest_height)


func _test_lod_boundary(layout: WorldLayout, feature: Dictionary) -> void:
	var center: Vector2 = feature.position
	var bounds := _bounds(feature.polygon)
	var edge_x := roundf(center.x / 1000.0) * 1000.0
	var edge_y := roundf(center.y / 1000.0) * 1000.0
	var vertical := absf(edge_x-center.x) < absf(edge_y-center.y)
	var origin := Vector2(edge_x, center.y) if vertical else Vector2(center.x, edge_y)
	var across := Vector2.RIGHT if vertical else Vector2.DOWN
	var along := across.orthogonal()
	var left := WorldTerrainStreamer.build_chunk_mesh_data(layout,
		WorldTerrainStreamer.world_to_chunk(origin-across), 25.0, [], 0.0)
	var right := WorldTerrainStreamer.build_chunk_mesh_data(layout,
		WorldTerrainStreamer.world_to_chunk(origin+across), 200.0, [], 0.0)
	var reach := maxf(bounds.size.x, bounds.size.y)
	var checked := 0
	var greatest_gap := 0.0
	for i in range(-ceili(reach / 2.0), ceili(reach / 2.0) + 1):
		var point := origin + along * float(i) * 2.0
		if not layout.is_land(point): continue
		var a := _mesh_height(left, point)
		var b := _mesh_height(right, point)
		if not is_finite(a) or not is_finite(b): continue
		checked += 1
		greatest_gap = maxf(greatest_gap, absf(a-b))
	_check(checked > 0, "Border regression covers exposed island crossing a chunk seam")
	_check(greatest_gap < 1.5, "Coarse/fine chunk border retains the same exposed island surface")
	print("  lod_boundary: samples=", checked, " worst_height_gap=", greatest_gap)


func _bounds(polygon: PackedVector2Array) -> Rect2:
	var result := Rect2(polygon[0], Vector2.ZERO)
	for point in polygon: result = result.expand(point)
	return result


func _mesh_height(mesh: Dictionary, point: Vector2) -> float:
	var vertices: PackedVector3Array = mesh.vertices
	var indices: PackedInt32Array = mesh.indices
	for i in range(0, indices.size(), 3):
		var va := vertices[indices[i]]
		var vb := vertices[indices[i + 1]]
		var vc := vertices[indices[i + 2]]
		var a := Vector2(va.x, va.z)
		var b := Vector2(vb.x, vb.z)
		var c := Vector2(vc.x, vc.z)
		var denominator := (b-a).cross(c-a)
		if absf(denominator) < 0.00001: continue
		var wb := (point-a).cross(c-a) / denominator
		var wc := (b-a).cross(point-a) / denominator
		var wa := 1.0-wb-wc
		if minf(wa, minf(wb, wc)) >= -0.00001:
			return va.y*wa+vb.y*wb+vc.y*wc
	return NAN


func _mesh_area(mesh: Dictionary) -> float:
	var area := 0.0
	var vertices: PackedVector3Array = mesh.vertices
	var indices: PackedInt32Array = mesh.indices
	for i in range(0, indices.size(), 3):
		var a := vertices[indices[i]]
		var b := vertices[indices[i + 1]]
		var c := vertices[indices[i + 2]]
		area += absf(Vector2(b.x-a.x,b.z-a.z).cross(Vector2(c.x-a.x,c.z-a.z)))*0.5
	return area


func _probe_mesh_area(layout: WorldLayout, coord: Vector2i, step: float) -> void:
	var mesh := WorldTerrainStreamer.build_chunk_mesh_data(layout, coord, step, [], 0.0)
	var cells: Dictionary = {}
	var vertices: PackedVector3Array = mesh.vertices
	var indices: PackedInt32Array = mesh.indices
	var origin := WorldTerrainStreamer.chunk_origin(coord)
	for i in range(0, indices.size(), 3):
		var a := vertices[indices[i]]
		var b := vertices[indices[i+1]]
		var c := vertices[indices[i+2]]
		var center := (Vector2(a.x,a.z)+Vector2(b.x,b.z)+Vector2(c.x,c.z))/3.0
		var cell := Vector2i(floori((center.x-origin.x)/step), floori((center.y-origin.y)/step))
		var area := absf(Vector2(b.x-a.x,b.z-a.z).cross(Vector2(c.x-a.x,c.z-a.z)))*0.5
		cells[cell] = float(cells.get(cell, 0.0)) + area
	print("PROBE coord=", coord, " step=", step, " area=", _mesh_area(mesh), " cells=", cells.size())
	var shown := 0
	for key in cells:
		if absf(float(cells[key])-step*step) > 0.05 and shown < 20:
			print("  bad cell=",key," area=",cells[key]," expected=",step*step)
			shown += 1


func _check(condition: bool, message: String) -> void:
	if not condition and _failures.size() < 60:
		_failures.append(message)
