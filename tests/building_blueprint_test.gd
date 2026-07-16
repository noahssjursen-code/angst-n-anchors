extends SceneTree


func _initialize() -> void:
	var door_fp := BrickCatalog.footprint_of("block_door")
	assert(door_fp == Vector3i(2, 3, 1), "door footprint must be 2×3×1")
	assert(not BrickCatalog.has_tag("block", "ship_only"))
	assert(BrickCatalog.has_tag("helm", "ship_only"))
	assert(BrickCatalog.has("foundation"))
	assert(BrickCatalog.has("roof_flat"))
	assert(BrickCatalog.has("roof_slope_inv"))
	assert(BrickCatalog.ids_for_buildings().has("block"))
	assert(not BrickCatalog.ids_for_buildings().has("helm"))
	assert(not BrickCatalog.ids_for_buildings().has("trommel_small"))

	var layout := BuildingLayout.new()
	layout.blueprint_id = "roundtrip_house"
	layout.display_name = "Roundtrip House"
	layout.role = "decorative"
	layout.grid_size = Vector3i(8, 6, 8)
	var grid := layout.grid()
	assert(layout.place_footprint(Vector3i(1, 0, 1), "foundation", 0, grid))
	assert(layout.place_footprint(Vector3i(1, 1, 1), "block", 90, grid))
	assert(layout.place_footprint(Vector3i(3, 0, 1), "block_door", 0, grid))
	assert(layout.count() == 1 + 1 + 6, "door occupies six cells at 2×3×1")
	assert(layout.place_footprint(Vector3i(0, 0, 3), "block", 0, null, Color(0.7, 0.2, 0.15)))
	var painted := layout.get_brick(Vector3i(0, 0, 3))
	assert(painted.has("color"), "painted brick stores colour")
	assert(BuildingLayout.color_from_entry(painted, "block").is_equal_approx(Color(0.7, 0.2, 0.15)))
	assert(layout.place_footprint(Vector3i(0, 0, 4), "floor", 0))
	assert(layout.place_footprint(Vector3i(0, 0, 4), "block", 0))
	var stacked := layout.get_brick(Vector3i(0, 0, 4))
	assert(str(stacked.get("brick_id", "")) == "block")
	assert(stacked.has("surface"), "floor remains under content in the same cell")
	assert(str((stacked["surface"] as Dictionary).get("brick_id", "")) == "floor")
	assert(layout.erase_footprint_at(Vector3i(0, 0, 4)))
	var floor_left := layout.get_brick(Vector3i(0, 0, 4))
	assert(BuildingLayout.entry_is_surface_only(floor_left), "erase strips content first, keeps floor")
	assert(not layout.place_footprint(Vector3i(9, 0, 0), "block", 0, grid))
	var restored := BuildingLayout.from_dict(layout.to_dict())
	assert(restored.iter_primary_cells().size() == 5, "primary cells skip occupied fillers")
	assert(int(restored.get_brick(Vector3i(1, 1, 1)).get("yaw", 0)) == 90)
	assert(bool(BuildingRules.validate(restored).get("ok", false)))

	var fitout := BuildingFitout.build(restored)
	assert(fitout.get_meta("building_blueprint_id", "") == "roundtrip_house")
	## foundation, wall block, door, painted block, floor-only leftover, + collision
	assert(fitout.get_child_count() == 5 + 1, "primary visuals plus collision root")
	fitout.free()

	assert(BuildingBlueprintCatalog.by_id("harbourmaster_house") == null)
	# Filename stem is the public id.
	for blueprint_id in BuildingBlueprintCatalog.ids():
		var loaded := BuildingBlueprintCatalog.by_id(blueprint_id)
		assert(loaded != null)
		assert(loaded.blueprint_id == blueprint_id)

	quit()
