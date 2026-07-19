class_name ShippingLaneTrafficSimulator
extends RefCounted

## Deterministic, data-only traffic authority exerciser.
##
## It deliberately does not instantiate BoatBody. It advances vessel records
## through the same directed edges, exclusive blocks, berth tokens, FIFO port
## queues, and authority snapshots intended for single-player or a server.

const REPORT_VERSION := 2
const FIXED_STEP_S := 0.20
const DOCK_DWELL_S := 12.0
const DEADLOCK_WINDOW_S := 90.0
const COLLISION_DISTANCE_M := 6.0

var network: ShippingLaneNetwork
var authority: ShippingLaneReservationService
var route_planner: HybridShippingRoutePlanner
var scenario_seed := 0
var simulated_seconds := 0.0
var vessels: Dictionary = {} # vessel id -> pure-data runtime record

var _token_ids := PackedStringArray()
var _hub_token_ids := PackedStringArray()
var _accumulator := 0.0
var _last_progress_s := 0.0
var _deadlock_latched := false
var _collision_pairs: Dictionary = {}
var _next_proximity_check_s := 0.0
var _events: Array[Dictionary] = []
var _safety_events: Array[Dictionary] = []
var _next_open_water_start_by_link: Dictionary = {}
var _metrics := {
	"trips_completed": 0,
	"route_failures": 0,
	"reservation_denials": 0,
	"queue_entries": 0,
	"berth_promotions": 0,
	"deadlocks": 0,
	"collisions": 0,
	"total_trip_seconds": 0.0,
	"total_distance_m": 0.0,
	"max_wait_seconds": 0.0,
	"max_port_queue": 0,
	"traffic_yields": 0,
}


func configure(value: ShippingLaneNetwork, vessel_count := 24, seed := 77127,
		world_layout: WorldLayout = null) -> void:
	network = value
	authority = ShippingLaneReservationService.new(network)
	route_planner = HybridShippingRoutePlanner.new()
	route_planner.configure(network, world_layout)
	scenario_seed = seed
	simulated_seconds = 0.0
	vessels.clear()
	_token_ids = PackedStringArray(network.sorted_berth_token_ids()) if network != null \
		else PackedStringArray()
	_hub_token_ids = _one_token_per_port()
	_accumulator = 0.0
	_last_progress_s = 0.0
	_deadlock_latched = false
	_collision_pairs.clear()
	_next_proximity_check_s = 0.0
	_events.clear()
	_safety_events.clear()
	_next_open_water_start_by_link.clear()
	_metrics = {
		"trips_completed": 0,
		"route_failures": 0,
		"reservation_denials": 0,
		"queue_entries": 0,
		"berth_promotions": 0,
		"deadlocks": 0,
		"collisions": 0,
		"total_trip_seconds": 0.0,
		"total_distance_m": 0.0,
		"max_wait_seconds": 0.0,
		"max_port_queue": 0,
		"traffic_yields": 0,
	}
	if network == null or _token_ids.size() < 2:
		return
	var count := mini(maxi(vessel_count, 1), _token_ids.size())
	for index in range(count):
		var source_id := _token_ids[index]
		var destination_id := _pick_destination(source_id, index, 0)
		var vessel_id := "traffic-%03d" % (index + 1)
		var source := network.berth_tokens[source_id] as Dictionary
		var source_node_id := str(source.get("node_id", ""))
		var source_node := network.node(source_node_id)
		var vessel := {
			"id": vessel_id,
			"index": index,
			"length_m": 42.0 + float(index % 4) * 8.0,
			"beam_m": 9.0 + float(index % 3) * 2.0,
			"draft_m": 3.0 + float(index % 2),
			"source_token_id": source_id,
			"destination_token_id": destination_id,
			"destination_requested": false,
			"route_edge_ids": PackedStringArray(),
			"route_steps": [],
			"route_mode": "",
			"open_water_sections": 0,
			"route_index": 0,
			"trip_serial": 0,
			"step_active": false,
			"open_water_section_id": "",
			"open_water_start_s": -1.0,
			"current_block_id": "",
			"trailing_blocks": [],
			"edge_progress_m": 0.0,
			"position": source_node.get("position", Vector2.ZERO),
			"heading": Vector2(0.0, -1.0),
			"state": "planning",
			"wait_seconds": 0.0,
			"trip_started_s": 0.0,
			"trip_distance_m": 0.0,
			"dwell_remaining_s": 0.0,
			"departure_clearance_pending": false,
			"deliveries": 0,
		}
		vessels[vessel_id] = vessel
		var source_claim := authority.request_berth(vessel_id,
			str(source.get("port_id", "")), PackedStringArray([source_id]))
		if str(source_claim.get("status", "")) != "assigned":
			_fail_route(vessel, "initial berth claim rejected")
			vessels[vessel_id] = vessel
			continue
		_plan_trip(vessel)
		vessel["departure_clearance_pending"] = true
		_try_departure_clearance(vessel)
		vessels[vessel_id] = vessel


func advance(seconds: float) -> void:
	if network == null or vessels.is_empty() or seconds <= 0.0:
		return
	_accumulator += seconds
	while _accumulator >= FIXED_STEP_S:
		_accumulator -= FIXED_STEP_S
		_step(FIXED_STEP_S)


func vessel_records() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for vessel_id in ShippingLaneNetwork._sorted_ids(vessels):
		result.append((vessels[vessel_id] as Dictionary).duplicate(true))
	return result


func summary() -> Dictionary:
	var states: Dictionary = {}
	var passage_modes: Dictionary = {}
	var active_queue_count := 0
	var starved_vessels := 0
	for vessel_value in vessels.values():
		var vessel := vessel_value as Dictionary
		var state := str(vessel.get("state", "unknown"))
		states[state] = int(states.get(state, 0)) + 1
		var passage_mode := str(vessel.get("route_mode", "unknown"))
		passage_modes[passage_mode] = int(passage_modes.get(passage_mode, 0)) + 1
		if state == "waiting_berth":
			active_queue_count += 1
		if float(vessel.get("wait_seconds", 0.0)) >= DEADLOCK_WINDOW_S:
			starved_vessels += 1
	var completed := int(_metrics.get("trips_completed", 0))
	var result := _metrics.duplicate(true)
	result.merge({
		"report_version": REPORT_VERSION,
		"scenario_seed": scenario_seed,
		"network_checksum": network.network_checksum if network != null else "",
		"simulated_seconds": simulated_seconds,
		"vessel_count": vessels.size(),
		"states": states,
		"passage_modes": passage_modes,
		"active_port_queue": active_queue_count,
		"starved_vessels": starved_vessels,
		"average_trip_seconds": float(_metrics.get("total_trip_seconds", 0.0)) \
			/ float(completed) if completed > 0 else 0.0,
		"average_trip_distance_m": float(_metrics.get("total_distance_m", 0.0)) \
			/ float(completed) if completed > 0 else 0.0,
	}, true)
	if _has_safety_failure(result):
		result["status"] = "FAIL"
	elif completed <= 0:
		result["status"] = "WARMUP"
	else:
		result["status"] = "PASS"
	return result


func generate_report() -> String:
	var data := summary()
	var lines := PackedStringArray([
		"ANGST 'N ANCHORS TRAFFIC LAB REPORT",
		"Status: %s | Report v%d | Scenario seed: %d" % [
			str(data.get("status", "FAIL")), REPORT_VERSION, scenario_seed],
		"Network: %s" % str(data.get("network_checksum", "")),
		"Simulated: %.1f s | Vessels: %d | Trips: %d" % [
			float(data.get("simulated_seconds", 0.0)), int(data.get("vessel_count", 0)),
			int(data.get("trips_completed", 0))],
		"States: %s" % JSON.stringify(data.get("states", {})),
		"Passages: %s | cached water links %d" % [
			JSON.stringify(data.get("passage_modes", {})),
			route_planner.cached_water_link_count() if route_planner != null else 0],
		"Queues: active %d | maximum %d | max wait %.1f s" % [
			int(data.get("active_port_queue", 0)), int(data.get("max_port_queue", 0)),
			float(data.get("max_wait_seconds", 0.0))],
		"Safety: collisions %d | global deadlocks %d | starved vessels %d | route failures %d" % [
			int(data.get("collisions", 0)), int(data.get("deadlocks", 0)),
			int(data.get("starved_vessels", 0)),
			int(data.get("route_failures", 0))],
		"Authority: reservation denials %d | queue entries %d | berth promotions %d" % [
			int(data.get("reservation_denials", 0)), int(data.get("queue_entries", 0)),
			int(data.get("berth_promotions", 0))],
		"Average completed trip: %.1f s / %.0f m" % [
			float(data.get("average_trip_seconds", 0.0)),
			float(data.get("average_trip_distance_m", 0.0))],
		"",
		"RECENT EVENTS",
	])
	if _events.is_empty():
		lines.append("(none)")
	else:
		for event in _events:
			lines.append("%8.1f  %-16s  %s" % [float(event.get("time_s", 0.0)),
				str(event.get("vessel_id", "system")), str(event.get("message", ""))])
	lines.append("")
	lines.append("SAFETY EVENTS")
	if _safety_events.is_empty():
		lines.append("(none)")
	else:
		for event in _safety_events:
			var point := event.get("position", Vector2.ZERO) as Vector2
			lines.append("%8.1f  %-16s  %-16s  (%7.0f,%7.0f)  %s/%s  %s" % [
				float(event.get("time_s", 0.0)), str(event.get("vessel_id", "")),
				str(event.get("other_vessel_id", "")), point.x, point.y,
				str(event.get("state", "")), str(event.get("other_state", "")),
				str(event.get("kind", ""))])
	lines.append("")
	lines.append("VESSEL SNAPSHOT")
	for vessel in vessel_records():
		var position := vessel.get("position", Vector2.ZERO) as Vector2
		lines.append("%s | %-15s | (%7.0f,%7.0f) | trips %d | wait %.1f | block %s" % [
			str(vessel.get("id", "")), str(vessel.get("state", "")), position.x, position.y,
			int(vessel.get("deliveries", 0)), float(vessel.get("wait_seconds", 0.0)),
			str(vessel.get("current_block_id", ""))])
	lines.append("")
	lines.append("MACHINE DATA")
	lines.append(JSON.stringify({
		"summary": data,
		"authority": authority.snapshot() if authority != null else {},
		"vessels": _vessel_wire_snapshot(),
		"recent_events": _events.duplicate(true),
		"safety_events": _safety_events.duplicate(true),
	}, "  "))
	return "\n".join(lines)


func _vessel_wire_snapshot() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for vessel in vessel_records():
		var point := vessel.get("position", Vector2.ZERO) as Vector2
		var heading := vessel.get("heading", Vector2(0.0, -1.0)) as Vector2
		result.append({
			"id": str(vessel.get("id", "")),
			"state": str(vessel.get("state", "")),
			"position": [point.x, point.y],
			"heading": [heading.x, heading.y],
			"source_token_id": str(vessel.get("source_token_id", "")),
			"destination_token_id": str(vessel.get("destination_token_id", "")),
			"route_index": int(vessel.get("route_index", 0)),
			"route_mode": str(vessel.get("route_mode", "")),
			"open_water_sections": int(vessel.get("open_water_sections", 0)),
			"open_water_links": _open_water_link_snapshot(vessel),
			"current_block_id": str(vessel.get("current_block_id", "")),
			"trailing_blocks": (vessel.get("trailing_blocks", []) as Array).duplicate(true),
			"wait_seconds": float(vessel.get("wait_seconds", 0.0)),
			"deliveries": int(vessel.get("deliveries", 0)),
		})
	return result


static func _open_water_link_snapshot(vessel: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for raw_step in vessel.get("route_steps", []) as Array:
		var step := raw_step as Dictionary
		if str(step.get("kind", "")) != "open_water":
			continue
		result.append({
			"from_breakoff_id": str(step.get("from_breakoff_id", "")),
			"to_breakoff_id": str(step.get("to_breakoff_id", "")),
			"length_m": float(step.get("length_m", 0.0)),
		})
	return result


func _step(delta: float) -> void:
	simulated_seconds += delta
	var progressed := false
	for vessel_id in ShippingLaneNetwork._sorted_ids(vessels):
		var vessel := vessels[vessel_id] as Dictionary
		if _step_vessel(vessel, delta):
			progressed = true
		vessels[vessel_id] = vessel
	if progressed:
		_last_progress_s = simulated_seconds
		_deadlock_latched = false
	elif simulated_seconds - _last_progress_s >= DEADLOCK_WINDOW_S and not _deadlock_latched:
		_deadlock_latched = true
		_metrics["deadlocks"] = int(_metrics.get("deadlocks", 0)) + 1
		_event("", "no vessel progressed for %.0f seconds" % DEADLOCK_WINDOW_S)
	_update_queue_peak()
	if simulated_seconds >= _next_proximity_check_s:
		_next_proximity_check_s = simulated_seconds + 1.0
		_check_proximity_collisions()


func _step_vessel(vessel: Dictionary, delta: float) -> bool:
	if str(vessel.get("state", "")) == "route_failed":
		return false
	if str(vessel.get("state", "")) == "waiting_departure_clearance":
		if _try_departure_clearance(vessel):
			return true
		_wait(vessel, delta)
		return false
	if str(vessel.get("state", "")) == "docked":
		vessel["dwell_remaining_s"] = float(vessel.get("dwell_remaining_s", 0.0)) - delta
		if float(vessel["dwell_remaining_s"]) <= 0.0:
			_depart_again(vessel)
			return str(vessel.get("state", "")) != "waiting_departure_clearance"
		return false
	var route := vessel.get("route_steps", []) as Array
	var route_index := int(vessel.get("route_index", 0))
	if route.is_empty() or route_index >= route.size():
		_fail_route(vessel, "route exhausted before arrival")
		return false
	if not bool(vessel.get("step_active", false)):
		if not _enter_step(vessel, route_index):
			_wait(vessel, delta)
			return false
	var edge := _step_record(route[route_index] as Dictionary)
	var speed := maxf(float(edge.get("speed_limit_ms", 7.2)), 0.5)
	var length := maxf(float(edge.get("length_m", 0.0)), 0.01)
	var old_progress := float(vessel.get("edge_progress_m", 0.0))
	var progress := minf(old_progress + speed * delta, length)
	var held_for_next := false
	if route_index + 1 < route.size():
		var stopping_margin := minf(float(vessel.get("length_m", 40.0)) + 12.0,
			length * 0.8)
		var hold_progress := maxf(0.0, length - stopping_margin)
		if progress >= hold_progress and not _pre_reserve_step(vessel, route_index + 1):
			progress = minf(progress, hold_progress)
			held_for_next = true
	var moved := progress - old_progress
	vessel["edge_progress_m"] = progress
	vessel["trip_distance_m"] = float(vessel.get("trip_distance_m", 0.0)) + moved
	_advance_trailing_blocks(vessel, moved)
	_update_pose(vessel, edge, progress)
	if held_for_next:
		var next_step := route[route_index + 1] as Dictionary
		var next_edge := _step_record(next_step)
		var next_blocks := next_edge.get("block_ids", PackedStringArray()) as PackedStringArray
		var next_block := network.block(next_blocks[0]) if not next_blocks.is_empty() else {}
		vessel["state"] = "waiting_berth" \
			if not str(next_block.get("queue_port_id", "")).is_empty() \
			else "waiting_signal"
		_wait(vessel, delta)
		return moved > 0.001
	if progress < length - 0.001:
		vessel["state"] = "traveling_open_water" \
			if str((route[route_index] as Dictionary).get("kind", "")) == "open_water" \
			else "traveling"
		vessel["wait_seconds"] = 0.0
		return true
	if route_index + 1 >= route.size():
		_arrive(vessel)
		return true
	if _enter_step(vessel, route_index + 1):
		return true
	_wait(vessel, delta)
	return false


func _pre_reserve_step(vessel: Dictionary, edge_index: int) -> bool:
	var route := vessel.get("route_steps", []) as Array
	if edge_index < 0 or edge_index >= route.size():
		return false
	var step := route[edge_index] as Dictionary
	if str(step.get("kind", "")) == "open_water":
		return true
	var edge := network.edge(str(step.get("edge_id", "")))
	var block_ids := edge.get("block_ids", PackedStringArray()) as PackedStringArray
	if block_ids.is_empty():
		return false
	var block_id := block_ids[0]
	var block := network.block(block_id)
	if not str(block.get("queue_port_id", "")).is_empty():
		_ensure_destination_request(vessel)
		if authority.berth_assignment(str(vessel.get("id", ""))).is_empty():
			return false
	var reservation := authority.try_reserve(str(vessel.get("id", "")),
		PackedStringArray([block_id]))
	if not bool(reservation.get("ok", false)):
		_metrics["reservation_denials"] = int(_metrics.get("reservation_denials", 0)) + 1
		return false
	return true


func _enter_step(vessel: Dictionary, edge_index: int) -> bool:
	var route := vessel.get("route_steps", []) as Array
	if edge_index < 0 or edge_index >= route.size():
		return false
	var step := route[edge_index] as Dictionary
	if str(step.get("kind", "")) == "open_water":
		var section_id := "%d:%d" % [int(vessel.get("trip_serial", 0)), edge_index]
		if str(vessel.get("open_water_section_id", "")) != section_id:
			var link_id := "%s>%s" % [str(step.get("from_breakoff_id", "")),
				str(step.get("to_breakoff_id", ""))]
			var speed := maxf(float(step.get("speed_limit_ms", 7.2)), 0.5)
			var start_s := maxf(simulated_seconds,
				float(_next_open_water_start_by_link.get(link_id, simulated_seconds)))
			var headway_s := (float(vessel.get("length_m", 40.0)) + 36.0) / speed
			_next_open_water_start_by_link[link_id] = start_s + headway_s
			vessel["open_water_section_id"] = section_id
			vessel["open_water_start_s"] = start_s
		if simulated_seconds + 0.001 < float(vessel.get("open_water_start_s", simulated_seconds)):
			vessel["state"] = "waiting_open_water_slot"
			return false
		var previous_open := str(vessel.get("current_block_id", ""))
		if not previous_open.is_empty():
			var trailing_open := vessel.get("trailing_blocks", []) as Array
			trailing_open.append({"block_id": previous_open,
				"clearance_remaining_m": float(vessel.get("length_m", 40.0))})
			vessel["trailing_blocks"] = trailing_open
		vessel["current_block_id"] = ""
		vessel["route_index"] = edge_index
		vessel["edge_progress_m"] = 0.0
		vessel["step_active"] = true
		vessel["state"] = "traveling_open_water"
		vessel["wait_seconds"] = 0.0
		_update_pose(vessel, _step_record(step), 0.0)
		return true
	var edge := network.edge(str(step.get("edge_id", "")))
	var block_ids := edge.get("block_ids", PackedStringArray()) as PackedStringArray
	if block_ids.is_empty():
		_fail_route(vessel, "edge has no authority block")
		return false
	var block_id := block_ids[0]
	var block := network.block(block_id)
	if not str(block.get("queue_port_id", "")).is_empty():
		_ensure_destination_request(vessel)
	# Leaving the front queue position requires an actual berth assignment.
	var current_block := network.block(str(vessel.get("current_block_id", "")))
	if not str(current_block.get("queue_port_id", "")).is_empty() \
			and str(block.get("queue_port_id", "")).is_empty() \
			and authority.berth_assignment(str(vessel.get("id", ""))).is_empty():
		vessel["state"] = "waiting_berth"
		return false
	var reservation := authority.try_reserve(str(vessel.get("id", "")),
		PackedStringArray([block_id]))
	if not bool(reservation.get("ok", false)):
		_metrics["reservation_denials"] = int(_metrics.get("reservation_denials", 0)) + 1
		vessel["state"] = "waiting_berth" \
			if not str(block.get("queue_port_id", "")).is_empty() else "waiting_signal"
		return false
	if not authority.occupy(str(vessel.get("id", "")), block_id):
		authority.release_block(str(vessel.get("id", "")), block_id)
		return false
	vessel["open_water_section_id"] = ""
	vessel["open_water_start_s"] = -1.0
	var previous := str(vessel.get("current_block_id", ""))
	if not previous.is_empty() and previous != block_id:
		var trailing := vessel.get("trailing_blocks", []) as Array
		trailing.append({"block_id": previous,
			"clearance_remaining_m": float(vessel.get("length_m", 40.0))})
		vessel["trailing_blocks"] = trailing
	vessel["current_block_id"] = block_id
	vessel["route_index"] = edge_index
	vessel["edge_progress_m"] = 0.0
	vessel["step_active"] = true
	vessel["state"] = "traveling"
	vessel["wait_seconds"] = 0.0
	_update_pose(vessel, edge, 0.0)
	return true


func _ensure_destination_request(vessel: Dictionary) -> void:
	if bool(vessel.get("destination_requested", false)):
		return
	var vessel_id := str(vessel.get("id", ""))
	var token_id := str(vessel.get("destination_token_id", ""))
	var token := network.berth_tokens.get(token_id, {}) as Dictionary
	var result := authority.request_berth(vessel_id, str(token.get("port_id", "")),
		PackedStringArray([token_id]))
	vessel["destination_requested"] = true
	if str(result.get("status", "")) == "queued":
		_metrics["queue_entries"] = int(_metrics.get("queue_entries", 0)) + 1
		_event(vessel_id, "joined berth queue for %s" % str(token.get("port_id", "")))
	elif str(result.get("status", "")) == "rejected":
		_fail_route(vessel, "destination berth request rejected")


func _arrive(vessel: Dictionary) -> void:
	var vessel_id := str(vessel.get("id", ""))
	var assignment := authority.berth_assignment(vessel_id)
	if assignment.is_empty():
		_fail_route(vessel, "reached quay without berth authority")
		return
	var current_block_id := str(vessel.get("current_block_id", ""))
	if not current_block_id.is_empty():
		authority.release_block(vessel_id, current_block_id)
	for trailing_value in vessel.get("trailing_blocks", []) as Array:
		authority.release_block(vessel_id, str((trailing_value as Dictionary).get("block_id", "")))
	vessel["current_block_id"] = ""
	vessel["trailing_blocks"] = []
	vessel["step_active"] = false
	vessel["state"] = "docked"
	vessel["dwell_remaining_s"] = DOCK_DWELL_S
	vessel["departure_clearance_pending"] = false
	vessel["wait_seconds"] = 0.0
	vessel["deliveries"] = int(vessel.get("deliveries", 0)) + 1
	var trip_seconds := simulated_seconds - float(vessel.get("trip_started_s", simulated_seconds))
	_metrics["trips_completed"] = int(_metrics.get("trips_completed", 0)) + 1
	_metrics["total_trip_seconds"] = float(_metrics.get("total_trip_seconds", 0.0)) + trip_seconds
	_metrics["total_distance_m"] = float(_metrics.get("total_distance_m", 0.0)) \
		+ float(vessel.get("trip_distance_m", 0.0))
	_event(vessel_id, "berthed after %.0f seconds" % trip_seconds)


func _depart_again(vessel: Dictionary) -> void:
	var vessel_id := str(vessel.get("id", ""))
	var source_id := str(vessel.get("destination_token_id", ""))
	var next_delivery := int(vessel.get("deliveries", 0))
	vessel["source_token_id"] = source_id
	vessel["destination_token_id"] = _pick_destination(
		source_id, int(vessel.get("index", 0)), next_delivery)
	vessel["destination_requested"] = false
	_plan_trip(vessel)
	if str(vessel.get("state", "")) == "route_failed":
		return
	vessel["departure_clearance_pending"] = true
	_try_departure_clearance(vessel)


func _try_departure_clearance(vessel: Dictionary) -> bool:
	if not bool(vessel.get("departure_clearance_pending", false)):
		return true
	var vessel_id := str(vessel.get("id", ""))
	var blocks := _departure_clearance_blocks(vessel)
	if blocks.is_empty():
		_fail_route(vessel, "departure route has no controlled harbour corridor")
		return false
	var result := authority.try_reserve(vessel_id, blocks)
	if not bool(result.get("ok", false)):
		_metrics["reservation_denials"] = int(_metrics.get("reservation_denials", 0)) + 1
		vessel["state"] = "waiting_departure_clearance"
		vessel["departure_blocked_by"] = str(result.get("blocked_by", ""))
		vessel["departure_blocked_at"] = str(result.get("block_id", ""))
		return false
	var promoted := authority.release_berth(vessel_id)
	if not promoted.is_empty():
		_metrics["berth_promotions"] = int(_metrics.get("berth_promotions", 0)) + 1
		_event(str(promoted.get("vessel_id", "")), "promoted after outbound corridor cleared")
	vessel["departure_clearance_pending"] = false
	vessel["departure_blocked_by"] = ""
	vessel["departure_blocked_at"] = ""
	vessel["state"] = "departing"
	vessel["wait_seconds"] = 0.0
	return true


func _departure_clearance_blocks(vessel: Dictionary) -> PackedStringArray:
	var result := PackedStringArray()
	var saw_harbour_edge := false
	for raw_step in vessel.get("route_steps", []) as Array:
		var step := raw_step as Dictionary
		if str(step.get("kind", "")) == "open_water":
			break
		var edge := network.edge(str(step.get("edge_id", "")))
		var edge_kind := str(edge.get("kind", ""))
		var is_harbour := edge_kind in ["quay_maneuver", "port_approach", "port_connector", "port_merge"]
		if is_harbour:
			saw_harbour_edge = true
		elif saw_harbour_edge:
			# Own the first highway block too, so the stern can clear the connector
			# before an inbound vessel is promoted into the opposing movement.
			for block_id in edge.get("block_ids", PackedStringArray()) as PackedStringArray:
				if not result.has(block_id):
					result.append(block_id)
			break
		elif not result.is_empty():
			break
		for block_id in edge.get("block_ids", PackedStringArray()) as PackedStringArray:
			if not result.has(block_id):
				result.append(block_id)
	return result


func _plan_trip(vessel: Dictionary) -> void:
	var source := network.berth_tokens.get(str(vessel.get("source_token_id", "")), {}) as Dictionary
	var destination := network.berth_tokens.get(
		str(vessel.get("destination_token_id", "")), {}) as Dictionary
	var vessel_limits := {
		"length_m": vessel.get("length_m", 0.0),
		"beam_m": vessel.get("beam_m", 0.0),
		"draft_m": vessel.get("draft_m", 0.0),
	}
	var passage := route_planner.plan(str(source.get("node_id", "")),
		str(destination.get("node_id", "")), vessel_limits)
	var route := passage.get("steps", []) as Array
	if route.is_empty():
		_fail_route(vessel, "no route between selected berths")
		return
	vessel["route_steps"] = route
	vessel["route_edge_ids"] = passage.get("controlled_edge_ids", PackedStringArray())
	vessel["route_mode"] = str(passage.get("mode", "all_lane"))
	vessel["open_water_sections"] = int(passage.get("open_water_sections", 0))
	vessel["route_index"] = 0
	vessel["trip_serial"] = int(vessel.get("trip_serial", 0)) + 1
	vessel["edge_progress_m"] = 0.0
	vessel["current_block_id"] = ""
	vessel["trailing_blocks"] = []
	vessel["step_active"] = false
	vessel["state"] = "departing"
	vessel["wait_seconds"] = 0.0
	vessel["trip_started_s"] = simulated_seconds
	vessel["trip_distance_m"] = 0.0
	var source_node := network.node(str(source.get("node_id", "")))
	vessel["position"] = source_node.get("position", Vector2.ZERO)
	_event(str(vessel.get("id", "")), "departing for %s via %s (%d open-water sections)" % [
		str(destination.get("port_id", "")), str(vessel.get("route_mode", "")),
		int(vessel.get("open_water_sections", 0))])


func _pick_destination(source_token_id: String, vessel_index: int, trip_index: int) -> String:
	var source := network.berth_tokens.get(source_token_id, {}) as Dictionary
	var source_port := str(source.get("port_id", ""))
	var pool := _hub_token_ids if _hub_token_ids.size() >= 2 else _token_ids
	for offset in range(pool.size()):
		var index := posmod(vessel_index * 3 + trip_index * 5 + offset + 1, pool.size())
		var candidate := pool[index]
		var token := network.berth_tokens[candidate] as Dictionary
		if candidate != source_token_id and str(token.get("port_id", "")) != source_port:
			return candidate
	return _token_ids[posmod(vessel_index + trip_index + 1, _token_ids.size())]


func _one_token_per_port() -> PackedStringArray:
	var result := PackedStringArray()
	var seen: Dictionary = {}
	for token_id in _token_ids:
		var token := network.berth_tokens[token_id] as Dictionary
		var port_id := str(token.get("port_id", ""))
		if seen.has(port_id):
			continue
		seen[port_id] = true
		result.append(token_id)
	return result


func _wait(vessel: Dictionary, delta: float) -> void:
	var wait := float(vessel.get("wait_seconds", 0.0)) + delta
	vessel["wait_seconds"] = wait
	_metrics["max_wait_seconds"] = maxf(float(_metrics.get("max_wait_seconds", 0.0)), wait)


func _advance_trailing_blocks(vessel: Dictionary, moved_m: float) -> void:
	if moved_m <= 0.0:
		return
	var vessel_id := str(vessel.get("id", ""))
	var trailing := vessel.get("trailing_blocks", []) as Array
	var retained: Array = []
	for trailing_value in trailing:
		var record := trailing_value as Dictionary
		record["clearance_remaining_m"] = float(record.get("clearance_remaining_m", 0.0)) - moved_m
		if float(record["clearance_remaining_m"]) <= 0.0:
			authority.release_block(vessel_id, str(record.get("block_id", "")))
		else:
			retained.append(record)
	vessel["trailing_blocks"] = retained


func _update_pose(vessel: Dictionary, edge: Dictionary, distance_m: float) -> void:
	var points := edge.get("points", PackedVector2Array()) as PackedVector2Array
	var sample := _sample_polyline(points, distance_m)
	vessel["position"] = sample.get("position", Vector2.ZERO)
	vessel["heading"] = sample.get("heading", Vector2(0.0, -1.0))


func _step_record(step: Dictionary) -> Dictionary:
	if str(step.get("kind", "")) == "open_water":
		return step
	return network.edge(str(step.get("edge_id", "")))


static func _sample_polyline(points: PackedVector2Array, distance_m: float) -> Dictionary:
	if points.size() < 2:
		return {"position": points[0] if not points.is_empty() else Vector2.ZERO,
			"heading": Vector2(0.0, -1.0)}
	var remaining := maxf(distance_m, 0.0)
	for index in range(points.size() - 1):
		var delta := points[index + 1] - points[index]
		var length := delta.length()
		if remaining <= length or index == points.size() - 2:
			var direction := delta.normalized() if length > 0.001 else Vector2(0.0, -1.0)
			return {"position": points[index] + direction * minf(remaining, length),
				"heading": direction}
		remaining -= length
	return {"position": points[-1], "heading": (points[-1] - points[-2]).normalized()}


func _update_queue_peak() -> void:
	var maximum := 0
	for port_id in network.port_gate_nodes.keys():
		maximum = maxi(maximum, authority.port_berth_queue(str(port_id)).size())
	_metrics["max_port_queue"] = maxi(int(_metrics.get("max_port_queue", 0)), maximum)


func _check_proximity_collisions() -> void:
	var ids := ShippingLaneNetwork._sorted_ids(vessels)
	for a_index in range(ids.size()):
		var a := vessels[ids[a_index]] as Dictionary
		if str(a.get("state", "")) in ["docked", "route_failed"]:
			continue
		for b_index in range(a_index + 1, ids.size()):
			var b := vessels[ids[b_index]] as Dictionary
			if str(b.get("state", "")) in ["docked", "route_failed"]:
				continue
			if (a.get("position", Vector2.ZERO) as Vector2).distance_to(
					b.get("position", Vector2.ZERO) as Vector2) >= COLLISION_DISTANCE_M:
				continue
			var pair_id := "%s|%s" % [ids[a_index], ids[b_index]]
			if _collision_pairs.has(pair_id):
				continue
			_collision_pairs[pair_id] = true
			_metrics["collisions"] = int(_metrics.get("collisions", 0)) + 1
			_safety_events.append({
				"kind": "proximity_collision",
				"time_s": simulated_seconds,
				"vessel_id": ids[a_index],
				"other_vessel_id": ids[b_index],
				"position": a.get("position", Vector2.ZERO),
				"other_position": b.get("position", Vector2.ZERO),
				"state": str(a.get("state", "")),
				"other_state": str(b.get("state", "")),
				"block_id": str(a.get("current_block_id", "")),
				"other_block_id": str(b.get("current_block_id", "")),
				"route_mode": str(a.get("route_mode", "")),
				"other_route_mode": str(b.get("route_mode", "")),
			})
			_event(ids[a_index], "proximity collision with %s at %s / %s" % [
				ids[b_index], str(a.get("current_block_id", "")),
				str(b.get("current_block_id", ""))])


func _fail_route(vessel: Dictionary, reason: String) -> void:
	if str(vessel.get("state", "")) == "route_failed":
		return
	vessel["state"] = "route_failed"
	_metrics["route_failures"] = int(_metrics.get("route_failures", 0)) + 1
	_event(str(vessel.get("id", "")), reason)


func _event(vessel_id: String, message: String) -> void:
	_events.append({"time_s": simulated_seconds, "vessel_id": vessel_id, "message": message})
	while _events.size() > 24:
		_events.pop_front()


static func _has_safety_failure(data: Dictionary) -> bool:
	return int(data.get("collisions", 0)) > 0 \
		or int(data.get("deadlocks", 0)) > 0 \
		or int(data.get("starved_vessels", 0)) > 0 \
		or int(data.get("route_failures", 0)) > 0
