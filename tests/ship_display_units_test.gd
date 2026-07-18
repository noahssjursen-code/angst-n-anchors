extends SceneTree


func _initialize() -> void:
	var hull := HullRegistry.get_by_id("hull_28x10")
	assert(is_equal_approx(float(hull.get("loa_m", 0.0)), 28.0))
	assert(is_equal_approx(float(hull.get("beam_m", 0.0)), 10.0))
	assert(ShipClass.format_display_dimensions(28.0, 10.0) == "14.0 × 5.0 m")
	var grid := HullRegistry.make_grid("hull_28x10")
	assert(grid.length == 28, "display conversion must not shrink deck length")
	assert(grid.width == 10, "display conversion must not shrink deck width")
	var req := HarbourDeploy.ship_requirements({"hull_id": "hull_28x10"})
	assert(is_equal_approx(float(req.get("loa_world_m", 0.0)), 28.0))
	assert(is_equal_approx(float(req.get("loa_display_m", 0.0)), 14.0))
	assert(VesselSpawn.vessel_name_of({"name": "28x10 Cargo"}) == "14x5 Cargo")
	print("ship_display_units_test: PASS")
	quit()
