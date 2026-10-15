extends Node

const PlotIndex := preload("res://scripts/port/coastal_plot_index.gd")
var _failures: Array[String] = []
var _checks := 0


func _ready() -> void:
	_test_grid_and_expansion()
	_test_distinct_shores()
	_test_small_island_and_corner()
	_test_identity_and_queries()
	_test_production_geography()
	print("COASTAL_PLOT_INDEX checks=%d failures=%s" % [_checks, JSON.stringify(_failures)])
	get_tree().quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)
		push_error(label)


func _fixture(contours: Array[PackedVector2Array], checksum: String = "fixture") -> CoastalPlotIndex:
	var index := PlotIndex.new()
	index._build(contours, {"seed": 7, "generation_version": 12,
		"layout_checksum": checksum, "world_size_m": 2000.0}, Rect2(-1000, -1000, 2000, 2000), 200.0)
	return index


func _test_grid_and_expansion() -> void:
	# Two segments meeting at a plot boundary must form one contiguous coastline.
	var index := _fixture([
		PackedVector2Array([Vector2(-350, 50), Vector2(0, 50)]),
		PackedVector2Array([Vector2(0, 50), Vector2(350, 50)]),
	])
	_check(index.count() == 4, "shore split into four 200 metre squares")
	var west := index.plot_at(Vector2(-50, 50))
	var east := index.plot_at(Vector2(50, 50))
	_check(west.grid == [-1, 0], "negative coordinates use floor, not truncation")
	_check(index.neighbour_ids(west.id).has(east.id), "boundary endpoint joins adjacent coast parcels")
	_check(index.neighbour_ids(east.id).has(west.id), "coast adjacency is bidirectional")
	var owned: Array[String] = [west.id, east.id]
	var frontier := index.expansion_frontier(owned)
	_check(frontier.size() == 2, "coast expansion returns both outer parcels")
	_check(not frontier.has(west.id) and not frontier.has(east.id), "expansion excludes supplied parcels")
	_check(index.expansion_frontier(["unknown"]).is_empty(), "unknown identities cannot start expansion")
	_check(is_equal_approx(float(west.shore_length_m), 200.0), "shore length is clipped to parcel")
	_check(west.shore_section_count == 1 and not west.boundary_review_required, "simple shore has one section")


func _test_distinct_shores() -> void:
	# Geometric grid neighbours on opposite banks are not coastline neighbours.
	var index := _fixture([
		PackedVector2Array([Vector2(-350, 50), Vector2(350, 50)]),
		PackedVector2Array([Vector2(-350, 250), Vector2(350, 250)]),
	])
	var south := index.plot_at(Vector2(50, 50))
	var north := index.plot_at(Vector2(50, 250))
	_check(index.count() == 8, "both shorelines produce parcels")
	_check(not index.neighbour_ids(south.id).has(north.id), "nearby opposite shore cannot become expansion neighbour")
	var narrow := _fixture([
		PackedVector2Array([Vector2(-350, 40), Vector2(350, 40)]),
		PackedVector2Array([Vector2(-350, 140), Vector2(350, 140)]),
	])
	var mixed := narrow.plot_at(Vector2(50, 50))
	_check(mixed.shore_section_count == 2, "multiple coasts inside one grid square are detected")
	_check(mixed.boundary_review_required, "narrow water parcels explicitly require ownership boundary review")


func _test_small_island_and_corner() -> void:
	# The island fits entirely inside a parcel; corner-only land sampling misses it.
	var tiny := _fixture([PackedVector2Array([
		Vector2(10, 10), Vector2(40, 10), Vector2(40, 40), Vector2(10, 40), Vector2(10, 10),
	])])
	_check(tiny.count() == 1, "small closed island inside one square is included")
	var island := tiny.plot_at(Vector2(25, 25))
	_check(is_equal_approx(float(island.shore_length_m), 120.0), "small island shore perimeter retained")
	_check(island.shore_section_count == 1, "closed contour forms one connected shoreline")
	var diagonal := _fixture([PackedVector2Array([Vector2(50, 50), Vector2(350, 350)])])
	_check(diagonal.count() == 2, "corner crossing does not create zero length side parcels")
	var a := diagonal.plot_at(Vector2(50, 50))
	var b := diagonal.plot_at(Vector2(350, 350))
	_check(diagonal.neighbour_ids(a.id).has(b.id), "shore through a corner remains connected")
	var end_on_grid := _fixture([PackedVector2Array([Vector2(50, 50), Vector2(200, 50)])])
	_check(end_on_grid.count() == 1, "endpoint at boundary does not allocate an empty parcel")
	var clipped := _fixture([PackedVector2Array([Vector2(-1500, 50), Vector2(1500, 50)])])
	_check(clipped.count() == 10, "contours extending beyond map are clipped before parcel creation")


func _test_identity_and_queries() -> void:
	var contours: Array[PackedVector2Array] = [
		PackedVector2Array([Vector2(-350, 50), Vector2(0, 50)]),
		PackedVector2Array([Vector2(0, 50), Vector2(350, 50)]),
	]
	var first := _fixture(contours)
	contours.reverse()
	var reversed := _fixture(contours)
	_check(first.plot_ids() == reversed.plot_ids(), "IDs and ordering independent of contour visitation")
	_check(JSON.stringify(first.plots_in_rect(first.world_bounds)) == JSON.stringify(reversed.plots_in_rect(reversed.world_bounds)),
		"derived records deterministic after contour reorder")
	var other_world := _fixture(contours, "different-world")
	_check(first.plot_ids()[0] != other_world.plot_ids()[0], "different world checksum cannot alias parcel IDs")
	_check(first.get_plot(other_world.plot_ids()[0]).is_empty(), "foreign world parcel lookup rejected")
	var wider := PlotIndex.new()
	wider._build(contours, first.world_identity, first.world_bounds, 250.0)
	_check(first.plot_ids()[0] != wider.plot_ids()[0], "changing parcel size cannot reuse old ID")
	var visible := first.plots_in_rect(Rect2(0, 0, 200, 200))
	_check(visible.size() == 1 and visible[0].grid == [0, 0], "visible lookup uses half open square bounds")
	_check(first.plots_in_rect(Rect2(400, 400, 200, 200)).is_empty(), "inland or open water square is absent")
	_check(first.plots_in_rect(Rect2(1100, 1100, 100, 100)).is_empty(), "outside map rect is empty")
	_check(first.plots_in_rect(first.world_bounds, 2).size() == 2, "bounded lookup limit respected")
	_check(first.all_bounds().size() == first.count(), "native batching geometry covers all parcels")
	_check(first.plot_bounds(visible[0].id) == Rect2(0, 0, 200, 200), "native bounds use metre coordinates")
	var serialized: Variant = JSON.parse_string(JSON.stringify(visible[0]))
	_check(serialized is Dictionary and serialized.id == visible[0].id and serialized.grid == [0.0, 0.0], "record round trips through plain JSON")
	visible[0]["grid"][0] = 999
	_check(first.plot_at(Vector2(50, 50)).grid == [0, 0], "consumer cannot mutate cached records")
	_check(not first.plot_at(Vector2(50, 50)).has("owner") and not first.plot_at(Vector2(50, 50)).has("price"),
		"derived geography does not manufacture ownership or sale authority")


func _test_production_geography() -> void:
	var layout := WorldLayoutGenerator.generate(42017, WorldLayoutGenerator.DEFAULT_CONFIG_PATH, 15000.0)
	var index := PlotIndex.for_layout(layout)
	_check(index.count() > 100, "production world produces shoreline parcels")
	_check(PlotIndex.for_layout(layout) == index, "same world reuses derived index")
	var macros := layout.macro_coastline_contours()
	var macro_found := 0
	for contour in macros:
		var at := (contour[0] + contour[1]) * 0.5
		if not index.world_bounds.has_point(at):
			continue
		if not index.plot_at(at).is_empty():
			macro_found += 1
	_check(macro_found > 100 and macro_found == macros.size(), "all true macro shoreline segment midpoints are indexed")
	var features := layout.skerry_features()
	_check(not features.is_empty(), "production fixture includes skerries")
	var skerries_found := 0
	for feature in features:
		var polygon: PackedVector2Array = feature.polygon
		var at := (polygon[0] + polygon[1]) * 0.5
		if not index.plot_at(at).is_empty():
			skerries_found += 1
	_check(skerries_found == features.size(), "exposed skerries are included, not only coarse macro coast")
	var unknown: Array[String] = ["invalid"]
	_check(index.expansion_frontier(unknown).is_empty(), "future expansion preserves world identity")
	var before := Time.get_ticks_usec()
	for i in 1000:
		index.plots_in_rect(Rect2(Vector2(-3000 + i % 100 * 20, -1200), Vector2(1000, 1000)))
	print("COASTAL_PLOT_INDEX production plots=%d skerries=%d build_ms=%.2f query_1000_ms=%.2f" % [
		index.count(), features.size(), index.build_usec / 1000.0, (Time.get_ticks_usec() - before) / 1000.0])
