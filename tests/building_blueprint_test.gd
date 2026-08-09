extends SceneTree

const TestReport := preload("res://tests/support/test_report.gd")


func _initialize() -> void:
	var t := TestReport.new("building_blueprint_test")
	_run(t)
	t.finish(self)


func _run(t: TestReport) -> void:
	var door_fp := BrickCatalog.footprint_of("block_door")
	t.check("door footprint must be 2×3×1", door_fp == Vector3i(2, 3, 1))
	t.check("block is not ship-only", not BrickCatalog.has_tag("block", "ship_only"))
	t.check("helm is ship-only", BrickCatalog.has_tag("helm", "ship_only"))
	t.check("foundation is catalogued", BrickCatalog.has("foundation"))
	t.check("roof_flat is catalogued", BrickCatalog.has("roof_flat"))
	t.check("roof_slope_inv is catalogued", BrickCatalog.has("roof_slope_inv"))
	t.check("building bricks include block", BrickCatalog.ids_for_buildings().has("block"))
	t.check("building bricks exclude helm", not BrickCatalog.ids_for_buildings().has("helm"))
	t.check(
		"building bricks exclude trommel_small",
		not BrickCatalog.ids_for_buildings().has("trommel_small"),
	)

	var layout := BuildingLayout.new()
	layout.blueprint_id = "roundtrip_house"
	layout.display_name = "Roundtrip House"
	layout.role = "decorative"
	layout.grid_size = Vector3i(8, 6, 8)
	var grid := layout.grid()
	t.check("foundation places at (1,0,1)", layout.place_footprint(Vector3i(1, 0, 1), "foundation", 0, grid))
	t.check("block places yawed at (1,1,1)", layout.place_footprint(Vector3i(1, 1, 1), "block", 90, grid))
	t.check("door places at (3,0,1)", layout.place_footprint(Vector3i(3, 0, 1), "block_door", 0, grid))
	t.check("door occupies six cells at 2×3×1", layout.count() == 1 + 1 + 6)
	t.check(
		"painted block places at (0,0,3)",
		layout.place_footprint(Vector3i(0, 0, 3), "block", 0, null, Color(0.7, 0.2, 0.15)),
	)
	var painted := layout.get_brick(Vector3i(0, 0, 3))
	t.check("painted brick stores colour", painted.has("color"))
	t.check(
		"painted brick keeps the requested colour",
		BuildingLayout.color_from_entry(painted, "block").is_equal_approx(Color(0.7, 0.2, 0.15)),
	)
	t.check("floor places at (0,0,4)", layout.place_footprint(Vector3i(0, 0, 4), "floor", 0))
	t.check("block stacks over the floor at (0,0,4)", layout.place_footprint(Vector3i(0, 0, 4), "block", 0))
	var stacked := layout.get_brick(Vector3i(0, 0, 4))
	t.check("the stacked cell reports block as its content", str(stacked.get("brick_id", "")) == "block")
	if not t.check("floor remains under content in the same cell", stacked.has("surface")):
		return
	t.check(
		"the retained surface is the floor",
		str((stacked["surface"] as Dictionary).get("brick_id", "")) == "floor",
	)
	t.check("erasing the stacked cell reports a removal", layout.erase_footprint_at(Vector3i(0, 0, 4)))
	var floor_left := layout.get_brick(Vector3i(0, 0, 4))
	t.check("erase strips content first, keeps floor", BuildingLayout.entry_is_surface_only(floor_left))
	t.check(
		"placement outside the grid is rejected",
		not layout.place_footprint(Vector3i(9, 0, 0), "block", 0, grid),
	)
	var restored := BuildingLayout.from_dict(layout.to_dict())
	t.check("primary cells skip occupied fillers", restored.iter_primary_cells().size() == 5)
	t.check("yaw survives the dict round-trip", int(restored.get_brick(Vector3i(1, 1, 1)).get("yaw", 0)) == 90)
	t.check("the restored layout validates", bool(BuildingRules.validate(restored).get("ok", false)))

	var fitout := BuildingFitout.build(restored)
	t.check("fitout carries the blueprint id", fitout.get_meta("building_blueprint_id", "") == "roundtrip_house")
	## foundation, wall block, door, painted block, floor-only leftover, + collision
	t.check("primary visuals plus collision root", fitout.get_child_count() == 5 + 1)
	fitout.free()

	t.check(
		"harbourmaster_house is not a catalogued blueprint",
		BuildingBlueprintCatalog.by_id("harbourmaster_house") == null,
	)
	# Filename stem is the public id.
	for blueprint_id in BuildingBlueprintCatalog.ids():
		var loaded := BuildingBlueprintCatalog.by_id(blueprint_id)
		if not t.check("blueprint %s loads" % blueprint_id, loaded != null):
			continue
		t.check("blueprint %s reports its own id" % blueprint_id, loaded.blueprint_id == blueprint_id)
