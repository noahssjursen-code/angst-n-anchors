extends SceneTree

const TestReport := preload("res://tests/support/test_report.gd")


func _initialize() -> void:
	var t := TestReport.new("ocean_wake_smoke")
	_test_strength_and_direction(t)
	_test_mapping_decay_and_teleport(t)
	_test_origin_hysteresis(t)
	_test_registry_priority_and_staleness(t)
	_test_visual_only_contract(t)
	t.finish(self)


func _test_strength_and_direction(t: TestReport) -> void:
	var dry := OceanWakeField.calculate_strength(
		200000.0, 250000.0, 0.0, -1.0, -1.0
	)
	t.check("Dry propeller must not stamp a wake", dry == Vector2.ZERO)
	var bollard := OceanWakeField.calculate_strength(
		232000.0, 256000.0, 0.0, -1.0, 1.0
	)
	t.check("bollard wash is strong and wider than it is deep", bollard.x > 0.45 and bollard.y >= bollard.x)
	# Slightly high propeller markers must still produce wash.
	var high_prop := OceanWakeField.calculate_strength(
		232000.0, 256000.0, 0.0, -1.0, -0.2
	)
	t.check("High propeller marker killed all wake", high_prop.y > 0.15)
	var ahead := OceanWakeField.calculate_trailing_axis(Vector2.DOWN, -1.0)
	var astern := OceanWakeField.calculate_trailing_axis(Vector2.DOWN, 1.0)
	t.equal("ahead trails along the heading", ahead, Vector2.DOWN)
	t.equal("astern trails against the heading", astern, Vector2.UP)


func _test_mapping_decay_and_teleport(t: TestReport) -> void:
	var uv := OceanWakeField.world_to_uv(
		Vector2(512.0, 512.0), Vector2.ZERO, 1024.0
	)
	t.check("field centre maps to the middle of the texture", uv.distance_to(Vector2(0.5, 0.5)) < 0.0001)
	t.check("a short hop is not a teleport", not OceanWakeField.is_teleport_segment(
		Vector2.ZERO, Vector2(20.0, 0.0), 5.0
	))
	t.check("a long jump is a teleport", OceanWakeField.is_teleport_segment(
		Vector2.ZERO, Vector2(120.0, 0.0), 5.0
	))
	var decayed := OceanWakeField.decayed_channel(1.0, 1.0, 18.0)
	t.check("a full channel decays without vanishing", decayed > 0.0 and decayed < 1.0)


func _test_origin_hysteresis(t: TestReport) -> void:
	var origin_a := OceanWakeField.compute_locked_origin(
		Vector2.ZERO, Vector2.ZERO, false
	)
	var origin_b := OceanWakeField.compute_locked_origin(
		Vector2(12.0, -8.0), origin_a, true
	)
	t.check("Wake origin remapped too eagerly", origin_b == origin_a)
	var origin_c := OceanWakeField.compute_locked_origin(
		Vector2(220.0, 0.0), origin_a, true
	)
	t.check("Wake origin never remapped", origin_c != origin_a)


func _test_registry_priority_and_staleness(t: TestReport) -> void:
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
	t.equal("registry caps at MAX_EMITTERS", int(stats["active_emitters"]), OceanWakeField.MAX_EMITTERS)
	t.check("local strength reflects the submitted wash", float(stats["local_strength"]) >= 0.6)

	field.submit_emitter(
		"teleport", Vector2.ZERO, Vector2.DOWN, 3.0, 4.0, 1.0, 1.0, 110.0
	)
	field.submit_emitter(
		"teleport", Vector2(150.0, 0.0), Vector2.DOWN, 3.0, 4.0, 1.0, 1.0, 110.0
	)
	field.set_focus(Vector2(150.0, 0.0))
	var packed: PackedByteArray = field.call("_pack_emitters")
	t.check("Teleport stamp was not rejected", is_equal_approx(packed.decode_float(52), 1.0))
	field.free()


func _test_visual_only_contract(t: TestReport) -> void:
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
	t.check("wake does not move the wave height", is_equal_approx(before.height, after.height))
	t.check("wake does not move the wave velocity", before.velocity == after.velocity)
	field.free()
