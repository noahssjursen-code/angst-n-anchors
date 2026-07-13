extends SceneTree


func _initialize() -> void:
	var centered := BowThrusterComponent.crab_force_split(-10.0, 10.0, 0.0)
	assert(is_equal_approx(centered.x, 0.5))
	assert(is_equal_approx(centered.y, 0.5))

	var aft_com := 2.0
	var split := BowThrusterComponent.crab_force_split(-10.0, 10.0, aft_com)
	assert(split.x < split.y)
	assert(is_equal_approx(split.x + split.y, 1.0))
	var yaw_moment := (-10.0 - aft_com) * split.x + (10.0 - aft_com) * split.y
	assert(absf(yaw_moment) < 0.0001)

	var invalid := BowThrusterComponent.crab_force_split(2.0, 4.0, 0.0)
	assert(invalid == Vector2(0.5, 0.5))

	print("BowThrusterComponent tests passed")
	quit()
