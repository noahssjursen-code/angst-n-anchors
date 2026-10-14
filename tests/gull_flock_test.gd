extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var a := GullFlockSimulation.new()
	var b := GullFlockSimulation.new()
	a.configure(32, 761, 3.0, 1.0, 0.8)
	b.configure(32, 761, 3.0, 1.0, 0.8)
	assert(a.snapshot() == b.snapshot(), "Seeded identity / placement must repeat")
	for i in 600:
		a.advance(1.0 / 30.0)
	for i in 1200:
		b.advance(1.0 / 60.0)
	assert(a.snapshot() == b.snapshot(), "Frame rate must not change the fixed-step simulation")
	for i in a.positions.size():
		assert(a.positions[i].is_finite() and a.velocities[i].is_finite())
		assert(a.positions[i].y >= 3.0)
		assert(a.positions[i].length() < 100.0, "Flock escaped its local habitat")
		assert(a.velocities[i].length() <= a.profiles[i].cruise_speed_mps * 1.301)
	a.set_goal(0, Vector3(15, 8, 4))
	var wire: Dictionary = JSON.parse_string(JSON.stringify(a.snapshot()))
	assert(b.restore(wire), "JSON snapshots must reconstruct the flock")
	for i in 120:
		a.advance(1.0 / 30.0)
		b.advance(1.0 / 30.0)
	for i in a.positions.size():
		assert(a.positions[i].distance_to(b.positions[i]) < 0.005, "Restored flock diverged")
	assert(b.snapshot().birds[0].behaviour == "seeking")
	var before := b.snapshot()
	assert(not b.restore({"version": 1, "birds": [{"position": [0, 0]}]}))
	assert(b.snapshot() == before, "Rejected snapshots must leave the flock untouched")
	assert(GullProfile.from_record({"size_scale": 100}).size_scale == 1.25)
	assert(GullProfile.from_record({"age_years": 0}).age_years == 0.5)
	var bird := CoastalGull.new()
	root.add_child(bird)
	assert(bird.find_child("LeftWing", true, false) != null)
	var model := bird.get_child(0) as Node3D
	var juvenile := GullProfile.from_record({"age_years": 0.5, "size_scale": 0.8})
	bird.apply_profile(juvenile)
	assert(model.scale.is_equal_approx(Vector3.ONE * 0.8))
	var body := model.find_child("CoastalGullMesh", true, false) as MeshInstance3D
	assert(is_zero_approx(float(body.get_instance_shader_parameter("maturity"))))
	bird.pose(1.0, 0.0, true)
	assert(not (bird.find_child("LeftWing", true, false) as Node3D).visible)
	assert((bird.find_child("FoldedWings", true, false) as Node3D).visible)
	bird.queue_free()
	print("PASS gulls: repeatable profiles, frame-rate independence, bounded flight, JSON restore, goals, safe rejection, appearance and poses")
	quit()
