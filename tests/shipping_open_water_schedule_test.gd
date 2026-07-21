extends SceneTree

const VESSEL_COUNT := 50
const OPEN_WATER_SCHEDULE := preload("res://scripts/traffic/shipping_open_water_schedule.gd")


func _initialize() -> void:
	var started_usec := Time.get_ticks_usec()
	var schedule := OPEN_WATER_SCHEDULE.new()
	var failures := PackedStringArray()
	for index in range(VESSEL_COUNT):
		var lane_offset := float(index % 8) * 34.0 - 119.0
		var points := PackedVector2Array([
			Vector2(-10000.0, lane_offset), Vector2(10000.0, lane_offset)])
		if index % 5 == 0:
			points = PackedVector2Array([
				Vector2(lane_offset, -10000.0), Vector2(lane_offset, 10000.0)])
		var route_key := "vertical-%d" % (index % 8) if index % 5 == 0 \
			else "horizontal-%d" % (index % 8)
		var result := schedule.request("stress-%03d" % index, "crossing", points,
			float(index % 7) * 2.0, 7.2, 42.0 + float(index % 4) * 8.0, route_key)
		if not bool(result.get("ok", false)):
			failures.append("vessel %d was not scheduled" % index)
	var elapsed_ms := float(Time.get_ticks_usec() - started_usec) / 1000.0
	var summary := schedule.summary()
	print("Open-water schedule stress: %d vessels in %.2f ms | %s" % [
		VESSEL_COUNT, elapsed_ms, JSON.stringify(summary)])
	if int(summary.get("active_allocations", 0)) != VESSEL_COUNT:
		failures.append("not every vessel owns an allocation")
	if int(summary.get("delayed_requests", 0)) <= 0:
		failures.append("crossing scenario did not exercise delays")
	if elapsed_ms > 8000.0:
		failures.append("50-vessel scheduling exceeded 8000 ms")
	for failure in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)
