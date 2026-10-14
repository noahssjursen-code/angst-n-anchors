extends Node

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	assert(_check_long_rest_and_disturbance())
	var approach := GullWaterBehaviour.new()
	approach.land(Vector3(0, 14, 0), Vector3(0, -1, -18), Vector3(0, -1.5, -14), 2.0, 18.0)
	while approach.stage == GullWaterBehaviour.Stage.LANDING:
		approach.advance(GullFlockSimulation.STEP)
		assert(approach.velocity.dot(Vector3.FORWARD) >= -0.001, "Approach must not overshoot and fly backwards")
	for stage in [GullWaterBehaviour.Stage.RESTING, GullWaterBehaviour.Stage.TAKING_OFF]:
		approach.rest_at(Vector3(3, -1.5, 7), Vector3.FORWARD, 2.0)
		if stage == GullWaterBehaviour.Stage.TAKING_OFF:
			approach.take_off()
		approach.advance(0.7)
		var copy := GullWaterBehaviour.from_record(JSON.parse_string(JSON.stringify(approach.to_record())))
		assert(copy != null)
		for tick in 180:
			approach.advance(GullFlockSimulation.STEP)
			copy.advance(GullFlockSimulation.STEP)
			assert(approach.stage == copy.stage)
			assert(approach.position.distance_to(copy.position) < 0.001)
	var sim := GullFlockSimulation.new()
	sim.configure(3, 42, 4.0, 1.0, 0.0)
	var water_target := Vector3(0, WaveSurface.WATER_LEVEL, 0)
	assert(sim.request_water_rest(0, water_target, 3.0))
	assert(not sim.request_water_rest(0, water_target), "Do not restart an active landing")
	var seen: Dictionary = {}
	var restored := GullFlockSimulation.new()
	for i in 600:
		sim.advance(GullFlockSimulation.STEP)
		var motion := sim.water_behaviours[0]
		seen[motion.stage] = true
		assert(motion.position.is_finite())
		if motion.stage == GullWaterBehaviour.Stage.RESTING:
			assert(is_equal_approx(sim.positions[0].y, WaveSurface.WATER_LEVEL))
		if i == 60:
			var wire: Dictionary = JSON.parse_string(JSON.stringify(sim.snapshot()))
			assert(restored.restore(wire))
		elif i > 60:
			restored.advance(GullFlockSimulation.STEP)
			assert(sim.positions[0].distance_to(restored.positions[0]) < 0.005)
	assert(seen.has(GullWaterBehaviour.Stage.LANDING))
	assert(seen.has(GullWaterBehaviour.Stage.RESTING))
	assert(seen.has(GullWaterBehaviour.Stage.TAKING_OFF))
	assert(seen.has(GullWaterBehaviour.Stage.FLYING))
	assert(sim.positions[0].y >= 3.0, "Takeoff must rejoin airborne flock")
	var before := restored.snapshot()
	var broken := before.duplicate(true)
	broken.birds[0].water_behaviour = {"stage": 400}
	assert(not restored.restore(broken))
	assert(restored.snapshot() == before)
	var flock := GullFlock.new()
	flock.bird_count = 1
	add_child(flock)
	flock.position = Vector3(100, 10, 20)
	var local_water := flock.to_local(Vector3(101, WaveSurface.WATER_LEVEL, 21))
	flock.simulation.water_behaviours[0].rest_at(local_water, Vector3.FORWARD)
	flock.simulation.water_behaviours[0].elapsed = 2.0
	flock.simulation.positions[0] = local_water
	flock.simulation.previous_positions[0] = local_water
	flock.simulation.velocities[0] = Vector3.FORWARD * 0.1
	flock.water_sample_provider = func(_x: float, _z: float) -> WaterSample:
		var sample := WaterSample.flat()
		sample.height = 3.25
		sample.normal = Vector3(0.2, 1, 0.1).normalized()
		return sample
	flock._refresh(0.0)
	var bird := flock.get_child(0) as CoastalGull
	assert(absf(bird.global_position.y - (3.25 + 0.012 * bird.profile.size_scale)) < 0.001, "Floating must follow sampled water height in world coordinates")
	assert(bird.global_basis.y.dot(Vector3(0.2, 1, 0.1).normalized()) > 0.999)
	assert(not (bird.find_child("Legs", true, false) as Node3D).visible)
	assert((bird.find_child("FoldedWings", true, false) as Node3D).visible)
	var body := bird.find_child("CoastalGullMesh", true, false) as MeshInstance3D
	for shape in ["WaterRest", "NeckLift", "LookLeft", "LookRight"]:
		assert(body.find_blend_shape_by_name(shape) >= 0, "The actual Blender asset must include head poses")
	var motion := flock.simulation.water_behaviours[0]
	for step in 1200:
		motion.elapsed = float(step) * 0.1
		bird.pose_water(0.0, motion)
		assert(is_equal_approx(body.get_blend_shape_value(body.find_blend_shape_by_name("WaterRest")), 1.0), "Head must remain upright throughout rest, including quiet intervals")
		assert(is_equal_approx(body.get_blend_shape_value(body.find_blend_shape_by_name("NeckLift")), float(motion.rest_activity().neck_lift)))
		assert(not (bird.find_child("Legs", true, false) as Node3D).visible, "Stretching must not trigger a flight pose")
	bird.pose(0.0)
	assert(is_zero_approx(body.get_blend_shape_value(body.find_blend_shape_by_name("WaterRest"))))
	assert(is_zero_approx(body.get_blend_shape_value(body.find_blend_shape_by_name("NeckLift"))))
	flock.queue_free()
	print("PASS gull water: long rests, varied idles, vessel disturbances, JSON continuation, wave following and imported head poses")
	get_tree().quit()

func _check_long_rest_and_disturbance() -> bool:
	var a := GullWaterBehaviour.new()
	a.idle_seed = 761
	a.rest_at(Vector3(0, -1.5, 0), Vector3.FORWARD)
	var b := GullWaterBehaviour.from_record(JSON.parse_string(JSON.stringify(a.to_record())))
	var actions: Dictionary = {}
	var quiet := 0
	for i in 1800:
		a.advance(0.1)
		b.advance(0.1)
		assert(a.stage == GullWaterBehaviour.Stage.RESTING, "Do not take off after a few seconds")
		assert(a.rest_activity() == b.rest_activity(), "Idle schedule must reproduce from data and time")
		var pose := a.rest_activity()
		actions[pose.name] = true
		if pose.name == "Resting": quiet += 1
	assert(actions.size() == 4, "Quiet, wing stretch, neck lift and looking around")
	assert(quiet > 1200, "Most resting time must be quiet")
	assert(a.position.distance_to(a.target) < 0.5, "Resting bird must not paddle out of its patch")
	assert(not a.react_to_vessel(Vector3(100, 0, 0), Vector3(-3, 0, 0), 3.0))
	assert(not a.react_to_vessel(Vector3(20, 0, 0), Vector3(8, 0, 0), 3.0), "Distant departing ship should not scare it")
	assert(a.react_to_vessel(Vector3(20, 0, 0), Vector3(-8, 0, 0), 3.0), "Oncoming vessel must interrupt the rest")
	assert(a.stage == GullWaterBehaviour.Stage.TAKING_OFF and a.startled)
	assert(absf(a.heading.dot(Vector3.LEFT)) < 0.2, "Escape sideways from the vessel path")
	assert(not a.react_to_vessel(Vector3(0, 0, 0), Vector3.ZERO), "One disturbance must not repeatedly restart takeoff")
	b = GullWaterBehaviour.from_record(JSON.parse_string(JSON.stringify(a.to_record())))
	for i in 150:
		a.advance(GullFlockSimulation.STEP)
		b.advance(GullFlockSimulation.STEP)
		assert(a.stage == b.stage and a.position.distance_to(b.position) < 0.001)
	assert(a.stage == GullWaterBehaviour.Stage.FLYING)
	a.rest_at(Vector3.ZERO, Vector3.FORWARD, 2.0, true)
	a.advance(300.0)
	assert(a.stage == GullWaterBehaviour.Stage.RESTING, "Indefinite rest holds until disturbed")
	assert(a.react_to_vessel(Vector3(1, 0, 0), Vector3.ZERO))
	# A threat during the approach cancels the landing without snapping onto water.
	a.land(Vector3(0, 10, 0), Vector3(0, 0, -7), Vector3(0, -1.5, -14), 240, 7)
	assert(a.react_to_vessel(Vector3(1, 0, 0), Vector3.ZERO))
	assert(is_zero_approx(a.water_weight()))
	return true
