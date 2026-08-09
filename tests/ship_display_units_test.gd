extends SceneTree

const TestReport := preload("res://tests/support/test_report.gd")


func _initialize() -> void:
	var t := TestReport.new("ship_display_units_test")
	var hull := HullRegistry.get_by_id("hull_28x10")
	t.check("hull loa_m is 28", is_equal_approx(float(hull.get("loa_m", 0.0)), 28.0))
	t.check("hull beam_m is 10", is_equal_approx(float(hull.get("beam_m", 0.0)), 10.0))
	t.check(
		"28x10 formats as display dimensions",
		ShipClass.format_display_dimensions(28.0, 10.0) == "14.0 × 5.0 m",
	)
	var grid := HullRegistry.make_grid("hull_28x10")
	t.check("display conversion must not shrink deck length", grid.length == 28)
	t.check("display conversion must not shrink deck width", grid.width == 10)
	var req := HarbourDeploy.ship_requirements({"hull_id": "hull_28x10"})
	t.check("loa_world_m is 28", is_equal_approx(float(req.get("loa_world_m", 0.0)), 28.0))
	t.check("loa_display_m is 14", is_equal_approx(float(req.get("loa_display_m", 0.0)), 14.0))
	t.check(
		"vessel name is converted to display units",
		VesselSpawn.vessel_name_of({"name": "28x10 Cargo"}) == "14x5 Cargo",
	)
	t.finish(self)
