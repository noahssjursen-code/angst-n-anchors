extends SceneTree

const TestReport := preload("res://tests/support/test_report.gd")
const TELEMETRY := preload("res://scripts/state/telemetry.gd")


class Provider extends RefCounted:
	func get_debug_stats() -> Dictionary:
		return {"work_ms": 12.5, "items": 7}


func _initialize() -> void:
	var t := TestReport.new("telemetry_test")
	var service := TELEMETRY.new()
	service.publish_metric(&"test.frame_ms", 10.0, {"category": "test", "unit": "ms"})
	service.publish_metric(&"test.frame_ms", 22.0)
	service.publish_metric(&"test.frame_ms", 15.0)
	t.check(
		"latest frame_ms is the last published sample",
		is_equal_approx(float(service.metric_value(&"test.frame_ms", false)), 15.0),
	)
	t.check(
		"peak frame_ms tracks the maximum sample",
		is_equal_approx(float(service.metric_value(&"test.frame_ms", true)), 22.0),
	)
	service.publish_metric(&"test.fps", 60, {"peak_mode": "min"})
	service.publish_metric(&"test.fps", 42)
	service.publish_metric(&"test.fps", 55)
	t.equal("peak_mode min tracks the minimum sample", int(service.metric_value(&"test.fps", true)), 42)
	service.publish_metric(&"test.warmup_fps", 1, {"peak_mode": "min", "track_peak": false})
	service.publish_metric(&"test.warmup_fps", 60, {"peak_mode": "min"})
	t.equal(
		"track_peak false excludes the warmup sample from the peak",
		int(service.metric_value(&"test.warmup_fps", true)),
		60,
	)
	service.publish_metric(&"test.age", INF)
	service.publish_metric(&"test.age", 12.0)
	t.check(
		"non-finite samples never become the peak",
		is_equal_approx(float(service.metric_value(&"test.age", true)), 12.0),
	)

	var provider := Provider.new()
	service.register_provider(&"test.provider", provider, &"get_debug_stats", &"test")
	service._poll_providers()
	t.check(
		"polled provider stats publish as namespaced metrics",
		is_equal_approx(float(service.metric_value(&"test.provider.work_ms")), 12.5),
	)
	service.set_context_flag(&"test.flag", true, &"test")
	service.record_action(&"clicked", {"target": "button"})
	var action := service.begin_action(&"timed")
	service.end_action(action, {"result": "ok"})
	var report := service.generate_report(false)
	t.check("report lists provider metrics", report.contains("test.provider.work_ms"))
	t.check("report lists context flags", report.contains("test.flag"))
	t.check("report lists recorded actions", report.contains("action.clicked"))
	service.worst_spike_snapshot = {"worst_ms": 30.0, "process_ms": 30.0}
	service.spike_count = 1
	var peak_report := service.generate_report(true)
	t.check("peak report includes the worst coherent spike", peak_report.contains("WORST COHERENT SPIKE"))
	t.check("peak report includes the spike snapshot fields", peak_report.contains("worst_ms"))
	service.reset_peaks()
	t.check(
		"reset_peaks rebases the peak onto the latest sample",
		is_equal_approx(float(service.metric_value(&"test.frame_ms", true)), 15.0),
	)
	service.free()
	t.finish(self)
