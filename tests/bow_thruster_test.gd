extends SceneTree

const TestReport := preload("res://tests/support/test_report.gd")


func _initialize() -> void:
	var t := TestReport.new("bow_thruster_test")
	var centered := BowThrusterComponent.crab_force_split(-10.0, 10.0, 0.0)
	t.check("centred CoM splits bow share evenly", is_equal_approx(centered.x, 0.5))
	t.check("centred CoM splits stern share evenly", is_equal_approx(centered.y, 0.5))

	var aft_com := 2.0
	var split := BowThrusterComponent.crab_force_split(-10.0, 10.0, aft_com)
	t.check("aft CoM shifts share to the stern thruster", split.x < split.y)
	t.check("shares sum to 1", is_equal_approx(split.x + split.y, 1.0))
	var yaw_moment := (-10.0 - aft_com) * split.x + (10.0 - aft_com) * split.y
	t.check("split cancels yaw moment", absf(yaw_moment) < 0.0001)

	var invalid := BowThrusterComponent.crab_force_split(2.0, 4.0, 0.0)
	t.check("invalid geometry falls back to an even split", invalid == Vector2(0.5, 0.5))

	t.finish(self)
