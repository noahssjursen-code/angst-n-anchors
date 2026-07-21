extends RefCounted

## Deterministic spatial/time authority for free-sailing ocean links.
##
## Each route is reduced to the coarse ocean cells it crosses and a relative
## entry/exit interval for each cell. Conflicts jump directly to the first safe
## start time rather than polling every simulation tick or brute-forcing time
## buckets. The state is pure data and suitable for local or server authority.

const CELL_SIZE_M := 120.0
const SAMPLE_STEP_M := 60.0
const START_QUANTUM_S := 5.0
## Persistent fleets may reserve long crossings hours ahead. A one-hour cap
## turned a valid busy-ocean queue into repeated expensive "saturated" probes;
## one authority day keeps the allocation deterministic without polling.
const MAX_START_DELAY_S := 86400.0
const MIN_CLEARANCE_M := 36.0
const MAX_RESCHEDULE_PASSES := 128

var _occupancy_by_cell: Dictionary = {} # cell id -> Array[interval]
var _allocations: Dictionary = {} # vessel|section -> internal record
var _passage_cache: Dictionary = {} # stable off-ramp -> on-ramp link -> relative cell passages
var _next_start_by_route_key: Dictionary = {} # convoy headway for identical direction/path
var _requests := 0
var _delayed_requests := 0
var _maximum_delay_s := 0.0


func request(
		vessel_id: String,
		section_id: String,
		points: PackedVector2Array,
		requested_start_s: float,
		speed_ms: float,
		vessel_length_m: float,
		route_key := "",
) -> Dictionary:
	var allocation_id := "%s|%s" % [vessel_id, section_id]
	if _allocations.has(allocation_id):
		return _public_record(_allocations[allocation_id] as Dictionary)
	if vessel_id.is_empty() or section_id.is_empty() or points.size() < 2:
		return {"ok": false, "reason": "invalid_open_water_request"}
	_requests += 1
	var speed := maxf(speed_ms, 0.5)
	var clearance_s := (maxf(vessel_length_m, 0.0) + MIN_CLEARANCE_M) / speed
	var cache_key := route_key
	var passages := _passage_cache.get(cache_key, []) as Array \
		if not cache_key.is_empty() else []
	if passages.is_empty():
		passages = _relative_cell_passages(points, speed)
		if not cache_key.is_empty():
			_passage_cache[cache_key] = passages
	var start_s := ceilf(requested_start_s / START_QUANTUM_S) * START_QUANTUM_S
	if not route_key.is_empty():
		start_s = maxf(start_s, float(_next_start_by_route_key.get(route_key, start_s)))
	var latest_s := start_s + MAX_START_DELAY_S
	var scheduled := false
	for _pass_index in range(MAX_RESCHEDULE_PASSES):
		var next_start_s := _first_safe_start(
			passages, start_s, clearance_s, allocation_id, route_key)
		if next_start_s <= start_s + 0.001:
			scheduled = true
			break
		start_s = ceilf(next_start_s / START_QUANTUM_S) * START_QUANTUM_S
		if start_s > latest_s:
			break
	if not scheduled:
		return {"ok": false, "reason": "open_water_schedule_saturated"}
	var reservations: Array[Dictionary] = []
	for passage in passages:
		var cell_id := str(passage.get("cell_id", ""))
		var interval := {
			"allocation_id": allocation_id,
			"route_key": route_key,
			"direction": passage.get("direction", Vector2.ZERO),
			"start_s": start_s + float(passage.get("entry_s", 0.0)) - clearance_s,
			"end_s": start_s + float(passage.get("exit_s", 0.0)) + clearance_s,
		}
		var occupants := _occupancy_by_cell.get(cell_id, []) as Array
		occupants.append(interval)
		_occupancy_by_cell[cell_id] = occupants
		reservations.append({"cell_id": cell_id, "interval": interval})
	var delay_s := start_s - requested_start_s
	var record := {
		"ok": true,
		"allocation_id": allocation_id,
		"vessel_id": vessel_id,
		"section_id": section_id,
		"requested_start_s": requested_start_s,
		"start_s": start_s,
		"delay_s": delay_s,
		"slot_count": reservations.size(),
		"reservations": reservations,
	}
	_allocations[allocation_id] = record
	if not route_key.is_empty():
		_next_start_by_route_key[route_key] = start_s + clearance_s
	if delay_s > 0.001:
		_delayed_requests += 1
		_maximum_delay_s = maxf(_maximum_delay_s, delay_s)
	return _public_record(record)


func release(vessel_id: String, section_id: String) -> void:
	var allocation_id := "%s|%s" % [vessel_id, section_id]
	var record := _allocations.get(allocation_id, {}) as Dictionary
	for reservation_value in record.get("reservations", []) as Array:
		var reservation := reservation_value as Dictionary
		var cell_id := str(reservation.get("cell_id", ""))
		var retained: Array = []
		for interval_value in _occupancy_by_cell.get(cell_id, []) as Array:
			var interval := interval_value as Dictionary
			if str(interval.get("allocation_id", "")) != allocation_id:
				retained.append(interval)
		if retained.is_empty():
			_occupancy_by_cell.erase(cell_id)
		else:
			_occupancy_by_cell[cell_id] = retained
	_allocations.erase(allocation_id)


func release_vessel(vessel_id: String) -> void:
	var prefix := "%s|" % vessel_id
	for allocation_id_raw in _allocations.keys().duplicate():
		var allocation_id := str(allocation_id_raw)
		if allocation_id.begins_with(prefix):
			release(vessel_id, allocation_id.trim_prefix(prefix))


func summary() -> Dictionary:
	return {
		"active_allocations": _allocations.size(),
		"occupied_cells": _occupancy_by_cell.size(),
		"requests": _requests,
		"delayed_requests": _delayed_requests,
		"maximum_delay_s": _maximum_delay_s,
		"cached_passages": _passage_cache.size(),
	}


func snapshot() -> Dictionary:
	var records: Array[Dictionary] = []
	var ids := PackedStringArray()
	for allocation_id in _allocations.keys():
		ids.append(str(allocation_id))
	ids.sort()
	for allocation_id in ids:
		records.append(_public_record(_allocations[allocation_id] as Dictionary))
	return {"summary": summary(), "allocations": records}


func _first_safe_start(
		passages: Array[Dictionary], candidate_s: float, clearance_s: float,
		allocation_id: String, route_key: String,
) -> float:
	var required_start_s := candidate_s
	for passage in passages:
		var relative_entry := float(passage.get("entry_s", 0.0))
		var proposed_start := candidate_s + relative_entry - clearance_s
		var proposed_end := candidate_s + float(passage.get("exit_s", 0.0)) + clearance_s
		for interval_value in _occupancy_by_cell.get(str(passage.get("cell_id", "")), []) as Array:
			var interval := interval_value as Dictionary
			if str(interval.get("allocation_id", "")) == allocation_id:
				continue
			# Same path and direction is a convoy, not a crossing movement. Its
			# launch headway is enforced by `_next_start_by_route_key`.
			if not route_key.is_empty() and str(interval.get("route_key", "")) == route_key:
				continue
			# Different links may converge from separate off-ramps. Even when their
			# final headings match they are not one established convoy, so shared
			# cells remain authority-controlled. Only an identical route key may
			# use the explicit convoy-headway rule above.
			var occupied_start := float(interval.get("start_s", 0.0))
			var occupied_end := float(interval.get("end_s", 0.0))
			if proposed_end <= occupied_start or proposed_start >= occupied_end:
				continue
			required_start_s = maxf(required_start_s,
				occupied_end - relative_entry + clearance_s)
	return required_start_s


static func _relative_cell_passages(
		points: PackedVector2Array, speed_ms: float,
) -> Array[Dictionary]:
	var by_cell: Dictionary = {}
	var cumulative_distance := 0.0
	for point_index in range(points.size() - 1):
		var start := points[point_index]
		var finish := points[point_index + 1]
		var segment := finish - start
		var segment_length := segment.length()
		if segment_length <= 0.001:
			continue
		var sample_count := maxi(1, ceili(segment_length / SAMPLE_STEP_M))
		var direction := segment / segment_length
		for sample_index in range(sample_count + 1):
			var ratio := float(sample_index) / float(sample_count)
			_add_relative_passage(by_cell, start.lerp(finish, ratio),
				(cumulative_distance + segment_length * ratio) / speed_ms, direction)
		cumulative_distance += segment_length
	var result: Array[Dictionary] = []
	for value in by_cell.values():
		var passage := value as Dictionary
		var direction_sum := passage.get("direction_sum", Vector2.ZERO) as Vector2
		passage["direction"] = direction_sum.normalized() \
			if not direction_sum.is_zero_approx() else Vector2.ZERO
		passage.erase("direction_sum")
		result.append(passage)
	return result


static func _add_relative_passage(
		by_cell: Dictionary, point: Vector2, time_s: float, direction: Vector2,
) -> void:
	# Two offset grids catch close trajectories even when one straddles a
	# spatial cell boundary.
	for grid_index in range(2):
		var shift := CELL_SIZE_M * 0.5 * float(grid_index)
		var cell_x := floori((point.x + shift) / CELL_SIZE_M)
		var cell_y := floori((point.y + shift) / CELL_SIZE_M)
		var cell_id := "%d:%d:%d" % [grid_index, cell_x, cell_y]
		var passage := by_cell.get(cell_id, {
			"cell_id": cell_id,
			"entry_s": time_s,
			"exit_s": time_s,
			"direction_sum": Vector2.ZERO,
		}) as Dictionary
		passage["entry_s"] = minf(float(passage.get("entry_s", time_s)), time_s)
		passage["exit_s"] = maxf(float(passage.get("exit_s", time_s)), time_s)
		passage["direction_sum"] = (passage.get("direction_sum", Vector2.ZERO) as Vector2) \
			+ direction
		by_cell[cell_id] = passage


static func _public_record(record: Dictionary) -> Dictionary:
	return {
		"ok": bool(record.get("ok", false)),
		"allocation_id": str(record.get("allocation_id", "")),
		"vessel_id": str(record.get("vessel_id", "")),
		"section_id": str(record.get("section_id", "")),
		"requested_start_s": float(record.get("requested_start_s", 0.0)),
		"start_s": float(record.get("start_s", 0.0)),
		"delay_s": float(record.get("delay_s", 0.0)),
		"slot_count": int(record.get("slot_count", 0)),
	}
