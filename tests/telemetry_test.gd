extends SceneTree

const TELEMETRY := preload("res://scripts/state/telemetry.gd")


class Provider extends RefCounted:
	func get_debug_stats() -> Dictionary:
		return {"work_ms": 12.5, "items": 7}


func _initialize() -> void:
	var service := TELEMETRY.new()
	service.publish_metric(&"test.frame_ms", 10.0, {"category": "test", "unit": "ms"})
	service.publish_metric(&"test.frame_ms", 22.0)
	service.publish_metric(&"test.frame_ms", 15.0)
	assert(is_equal_approx(float(service.metric_value(&"test.frame_ms", false)), 15.0))
	assert(is_equal_approx(float(service.metric_value(&"test.frame_ms", true)), 22.0))
	service.publish_metric(&"test.fps", 60, {"peak_mode": "min"})
	service.publish_metric(&"test.fps", 42)
	service.publish_metric(&"test.fps", 55)
	assert(int(service.metric_value(&"test.fps", true)) == 42)
	service.publish_metric(&"test.warmup_fps", 1, {"peak_mode": "min", "track_peak": false})
	service.publish_metric(&"test.warmup_fps", 60, {"peak_mode": "min"})
	assert(int(service.metric_value(&"test.warmup_fps", true)) == 60)
	service.publish_metric(&"test.age", INF)
	service.publish_metric(&"test.age", 12.0)
	assert(is_equal_approx(float(service.metric_value(&"test.age", true)), 12.0))

	var provider := Provider.new()
	service.register_provider(&"test.provider", provider, &"get_debug_stats", &"test")
	service._poll_providers()
	assert(is_equal_approx(float(service.metric_value(&"test.provider.work_ms")), 12.5))
	service.set_context_flag(&"test.flag", true, &"test")
	service.record_action(&"clicked", {"target": "button"})
	var action := service.begin_action(&"timed")
	service.end_action(action, {"result": "ok"})
	var report := service.generate_report(false)
	assert(report.contains("test.provider.work_ms"))
	assert(report.contains("test.flag"))
	assert(report.contains("action.clicked"))
	service.worst_spike_snapshot = {"worst_ms": 30.0, "process_ms": 30.0}
	service.spike_count = 1
	var peak_report := service.generate_report(true)
	assert(peak_report.contains("WORST COHERENT SPIKE"))
	assert(peak_report.contains("worst_ms"))
	service.reset_peaks()
	assert(is_equal_approx(float(service.metric_value(&"test.frame_ms", true)), 15.0))
	service.free()
	print("telemetry_test: PASS")
	quit(0)
