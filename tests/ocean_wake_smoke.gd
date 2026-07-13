extends SceneTree


func _initialize() -> void:
	_test_strength_and_direction()
	_test_mapping_decay_and_teleport()
	_test_origin_hysteresis()
	_test_registry_priority_and_staleness()
	_test_visual_only_contract()
	print("Ocean wake smoke: persistent field contracts passed")
	quit()


func _test_strength_and_direction() -> void:
	var dry := OceanWakeField.calculate_strength(
		200000.0, 250000.0, 0.0, -1.0, -1.0
	)
	assert(dry == Vector2.ZERO, "Dry propeller must not stamp a wake")
	var bollard := OceanWakeField.calculate_strength(
		232000.0, 256000.0, 0.0, -1.0, 1.0
	)
	assert(bollard.x > 0.45 and bollard.y >= bollard.x)
	# Slightly high propeller markers must still produce wash.
	var high_prop := OceanWakeField.calculate_strength(
		232000.0, 256000.0, 0.0, -1.0, -0.2
	)
	assert(high_prop.y > 0.15, "High propeller marker killed all wake")
	var ahead := OceanWakeField.calculate_trailing_axis(Vector2.DOWN, -1.0)
	var astern := OceanWakeField.calculate_trailing_axis(Vector2.DOWN, 1.0)
	assert(ahead == Vector2.DOWN)
	assert(astern == Vector2.UP)


func _test_mapping_decay_and_teleport() -> void:
	var uv := OceanWakeField.world_to_uv(
		Vector2(512.0, 512.0), Vector2.ZERO, 1024.0
	)
	assert(uv.distance_to(Vector2(0.5, 0.5)) < 0.0001)
	assert(not OceanWakeField.is_teleport_segment(
		Vector2.ZERO, Vector2(20.0, 0.0), 5.0
	))
	assert(OceanWakeField.is_teleport_segment(
		Vector2.ZERO, Vector2(120.0, 0.0), 5.0
	))
	var decayed := OceanWakeField.decayed_channel(1.0, 1.0, 18.0)
	assert(decayed > 0.0 and decayed < 1.0)


func _test_origin_hysteresis() -> void:
	var origin_a := OceanWakeField.compute_locked_origin(
		Vector2.ZERO, Vector2.ZERO, false
	)
	var origin_b := OceanWakeField.compute_locked_origin(
		Vector2(12.0, -8.0), origin_a, true
	)
	assert(origin_b == origin_a, "Wake origin remapped too eagerly")
	var origin_c := OceanWakeField.compute_locked_origin(
		Vector2(220.0, 0.0), origin_a, true
	)
	assert(origin_c != origin_a, "Wake origin never remapped")


func _test_registry_priority_and_staleness() -> void:
	var field := OceanWakeField.new()
	field.set_focus(Vector2.ZERO)
	for i in range(10):
		field.submit_emitter(
			"test:%d" % i,
			Vector2(float(i), 0.0),
			Vector2.DOWN,
			3.0,
			5.0,
			0.5,
			0.6,
			100.0 if i == 9 else float(i)
		)
	field.call("_pack_emitters")
	var stats := field.get_debug_stats()
	assert(int(stats["active_emitters"]) == OceanWakeField.MAX_EMITTERS)
	assert(float(stats["local_strength"]) >= 0.6)

	field.submit_emitter(
		"teleport", Vector2.ZERO, Vector2.DOWN, 3.0, 4.0, 1.0, 1.0, 110.0
	)
	field.submit_emitter(
		"teleport", Vector2(150.0, 0.0), Vector2.DOWN, 3.0, 4.0, 1.0, 1.0, 110.0
	)
	field.set_focus(Vector2(150.0, 0.0))
	var packed: PackedByteArray = field.call("_pack_emitters")
	assert(is_equal_approx(packed.decode_float(52), 1.0), "Teleport stamp was not rejected")
	field.free()


func _test_visual_only_contract() -> void:
	WaveSurface.fft_system = null
	WaveSurface.clear_sample_cache()
	var before := WaveSurface.sample_at(12.0, 34.0)
	var field := OceanWakeField.new()
	field.submit_emitter(
		"visual-only", Vector2(12.0, 34.0), Vector2.DOWN,
		4.0, 5.0, 1.0, 1.0, 100.0
	)
	WaveSurface.clear_sample_cache()
	var after := WaveSurface.sample_at(12.0, 34.0)
	assert(is_equal_approx(before.height, after.height))
	assert(before.velocity == after.velocity)
	field.free()
