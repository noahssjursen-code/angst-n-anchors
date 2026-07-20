class_name ShippingLaneTrafficSimulator
extends RefCounted

## Deterministic, data-only traffic authority exerciser.
##
## It deliberately does not instantiate BoatBody. It advances vessel records
## through the same directed edges, exclusive blocks, berth tokens, FIFO port
## queues, and authority snapshots intended for single-player or a server.

const REPORT_VERSION := 3
## Strategic authority does not need a physics tick. Half-second signal updates
## remain far below marine stopping distances and scale to persistent fleets.
const FIXED_STEP_S := 0.50
const DOCK_DWELL_S := 12.0
const DEADLOCK_WINDOW_S := 90.0
const COLLISION_DISTANCE_M := 6.0
const NEAR_AUTHORITY_RADIUS_M := 2400.0
const MID_AUTHORITY_RADIUS_M := 8000.0
const MID_AUTHORITY_STEP_S := 2.0
const REMOTE_AUTHORITY_STEP_S := 10.0
const EAGER_ROUTE_PLAN_LIMIT := 24
const BACKGROUND_ROUTE_PLANS_PER_STEP := 1
const BACKGROUND_ROUTE_PLAN_INTERVAL_S := 2.0
const STRATEGIC_PROMOTION_RADIUS_M := 9000.0
const OPEN_WATER_ARRIVAL_QUEUE_M := 1200.0
const OPEN_WATER_QUEUE_GAP_M := 18.0
## Free-sailing approaches stop outside the complete eight-ramp interchange,
## not merely one hull length from their own ON ramp. This leaves controlled
## OFF-ramp and feeder movements a clear authority envelope.
const OPEN_WATER_PORT_STANDOFF_M := 320.0
const TRAFFIC_CLEARANCE_CELL_M := 128.0
const OPEN_WATER_SCHEDULE := preload("res://scripts/traffic/shipping_open_water_schedule.gd")

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
var _open_water_schedule: RefCounted
var _planned_passage_cache: Dictionary = {}
var _sorted_vessel_ids := PackedStringArray()
var _exact_vessel_ids := PackedStringArray()
var _strategic_phase_buckets: Array[PackedStringArray] = []
var _interest_centers := PackedVector2Array()
var _authority_tick_index := 0
var _pending_plan_ids := PackedStringArray()
var _next_background_plan_s := 0.0
var _controlled_spatial_buckets: Dictionary = {}
var _open_water_obstacle_buckets: Dictionary = {}
var _open_water_arrival_ranks: Dictionary = {}
var _open_merge_owner_by_port: Dictionary = {} # port id -> vessel id
var _metrics := {
	"trips_completed": 0,
	"route_failures": 0,
	"reservation_denials": 0,
	"overtakes": 0,
	"queue_entries": 0,
	"berth_promotions": 0,
	"deadlocks": 0,
	"collisions": 0,
	"total_trip_seconds": 0.0,
	"total_distance_m": 0.0,
	"max_wait_seconds": 0.0,
	"max_port_queue": 0,
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
	_open_water_schedule = OPEN_WATER_SCHEDULE.new()
	_planned_passage_cache.clear()
	_sorted_vessel_ids = PackedStringArray()
	_exact_vessel_ids = PackedStringArray()
	_strategic_phase_buckets.clear()
	_interest_centers = PackedVector2Array()
	_authority_tick_index = 0
	_pending_plan_ids = PackedStringArray()
	_next_background_plan_s = 0.0
	_controlled_spatial_buckets.clear()
	_open_water_obstacle_buckets.clear()
	_open_water_arrival_ranks.clear()
	_open_merge_owner_by_port.clear()
	_metrics = {
		"trips_completed": 0,
		"route_failures": 0,
		"reservation_denials": 0,
		"overtakes": 0,
		"queue_entries": 0,
		"berth_promotions": 0,
		"deadlocks": 0,
		"collisions": 0,
		"total_trip_seconds": 0.0,
		"total_distance_m": 0.0,
		"max_wait_seconds": 0.0,
		"max_port_queue": 0,
	}
	if network == null or _token_ids.size() < 2:
		return
	var count := maxi(vessel_count, 1)
	var spawn_tokens := _hub_token_ids if _hub_token_ids.size() >= 2 else _token_ids
	for index in range(count):
		var source_id := spawn_tokens[index % spawn_tokens.size()]
		var destination_id := _pick_destination(source_id, index, 0)
		var vessel_id := "traffic-%03d" % (index + 1)
		var source := network.berth_tokens[source_id] as Dictionary
		var vessel := _make_vessel(vessel_id, index, source_id, destination_id)
		vessels[vessel_id] = vessel
		_plan_trip(vessel)
		if str(vessel.get("state", "")) == "route_failed":
			vessels[vessel_id] = vessel
			continue
		if index >= EAGER_ROUTE_PLAN_LIMIT:
			_stage_strategic_route(vessel)
			_pending_plan_ids.append(vessel_id)
		else:
			# Debug and restored fleets represent an already-running world. Staging
			# every exact contact underway avoids an artificial login-time burst in
			# which one ship per port simultaneously requests departure clearance.
			_activate_initial_vessel(vessel, true)
		vessels[vessel_id] = vessel
	_sorted_vessel_ids = ShippingLaneNetwork._sorted_ids(vessels)
	_rebuild_runtime_sets()


func _rebuild_runtime_sets() -> void:
	_exact_vessel_ids = PackedStringArray()
	_strategic_phase_buckets.clear()
	var strategic_ticks := maxi(1, roundi(REMOTE_AUTHORITY_STEP_S / FIXED_STEP_S))
	for unused in range(strategic_ticks):
		_strategic_phase_buckets.append(PackedStringArray())
	for vessel_id in _sorted_vessel_ids:
		var vessel := vessels.get(vessel_id, {}) as Dictionary
		if str(vessel.get("state", "")) == "scheduled_strategic":
			var phase := posmod(int(vessel.get("authority_phase_tick", 0)), strategic_ticks)
			_strategic_phase_buckets[phase].append(vessel_id)
			vessel["strategic_last_update_s"] = simulated_seconds
			vessels[vessel_id] = vessel
		else:
			_exact_vessel_ids.append(vessel_id)


func _activate_initial_vessel(vessel: Dictionary, force_underway: bool) -> void:
	var source_id := str(vessel.get("source_token_id", ""))
	var vessel_id := str(vessel.get("id", ""))
	var index := int(vessel.get("index", 0))
	# A strategic AIS contact already owns a real contract route and published
	# position. Promotion may add exact block authority, but it must never choose
	# a new route or snap the contact to an unrelated empty lane.
	var published_position := Vector2.INF
	if str(vessel.get("state", "")) == "scheduled_strategic":
		published_position = vessel.get("position", Vector2.INF) as Vector2
		if _place_initial_underway(vessel, published_position, true):
			_event(vessel_id, "promoted contract contact to exact local authority")
			return
		# Its present block or open-water slot is busy. Retain the published
		# strategic record and retry later instead of teleporting it.
		return
	if (vessel.get("route_steps", []) as Array).is_empty():
		_plan_trip(vessel)
	if str(vessel.get("state", "")) == "route_failed":
		return
	if force_underway:
		var placed := _place_initial_underway(vessel, published_position)
		var destination_attempt := 1
		while not placed and destination_attempt < _hub_token_ids.size():
			vessel["destination_token_id"] = _pick_destination(
				source_id, index, destination_attempt)
			_plan_trip(vessel)
			placed = str(vessel.get("state", "")) != "route_failed" \
				and _place_initial_underway(vessel, published_position)
			destination_attempt += 1
		if not placed:
			_fail_route(vessel, "no deterministic staging section for persistent vessel")
		return
	var source := network.berth_tokens[source_id] as Dictionary
	var source_claim := authority.request_berth(vessel_id,
		str(source.get("port_id", "")), PackedStringArray([source_id]))
	if str(source_claim.get("status", "")) != "assigned":
		_fail_route(vessel, "initial berth claim rejected")
		return
	vessel["departure_clearance_pending"] = true
	_try_departure_clearance(vessel)


func _stage_strategic_route(vessel: Dictionary) -> void:
	# Remote contacts are inexpensive, not fictitious. Every one is placed at a
	# deterministic voyage age on its real berth-to-berth route. This is the same
	# record a server can publish to clients and eliminates arbitrary western
	# spawns, wandering contacts and promotion-time route changes.
	var route := vessel.get("route_steps", []) as Array
	var candidates: Array[Dictionary] = []
	var local_candidates: Array[Dictionary] = []
	var total_travel_s := 0.0
	var local_travel_s := 0.0
	for step_index in range(route.size()):
		var step := route[step_index] as Dictionary
		var edge := _step_record(step)
		var step_kind := str(step.get("kind", ""))
		var edge_kind := str(edge.get("kind", ""))
		var length := maxf(float(edge.get("length_m", 0.0)), 1.0)
		var speed := maxf(float(edge.get("speed_limit_ms", 7.2)), 0.5)
		var travel_s := length / speed
		# A short contract between neighbouring harbours can legitimately remain
		# entirely inside their connected coastal access graph. Keep those edges
		# as a fallback rather than declaring a valid route failed merely because
		# it never reaches a regional/main lane.
		if edge_kind != "quay_maneuver":
			local_candidates.append({"step_index": step_index,
				"elapsed_before_s": local_travel_s, "travel_s": travel_s})
			local_travel_s += travel_s
		if step_kind != "open_water" and edge_kind not in [
				"main_lane", "regional_lane", "waterway_junction", "passing_lane"]:
			continue
		candidates.append({"step_index": step_index, "elapsed_before_s": total_travel_s,
			"travel_s": travel_s})
		total_travel_s += travel_s
	if candidates.is_empty():
		candidates = local_candidates
		total_travel_s = local_travel_s
	if candidates.is_empty():
		_fail_route(vessel, "contract route has no placeable travel section")
		return
	var phase := 0.04 + _deterministic_fraction(int(vessel.get("index", 0)), 43) * 0.92
	var desired_time := phase * total_travel_s
	var selected := candidates.back() as Dictionary
	for candidate_value in candidates:
		var candidate := candidate_value as Dictionary
		if desired_time <= float(candidate.get("elapsed_before_s", 0.0)) \
				+ float(candidate.get("travel_s", 0.0)):
			selected = candidate
			break
	var step_index := int(selected.get("step_index", 0))
	var selected_step := route[step_index] as Dictionary
	var selected_edge := _step_record(selected_step)
	var speed := maxf(float(selected_edge.get("speed_limit_ms", 7.2)), 0.5)
	var local_time := maxf(desired_time - float(selected.get("elapsed_before_s", 0.0)), 0.0)
	var progress := minf(local_time * speed,
		maxf(float(selected_edge.get("length_m", 0.0)), 0.0))
	vessel["route_index"] = step_index
	vessel["edge_progress_m"] = progress
	vessel["step_active"] = false
	vessel["current_block_id"] = ""
	vessel["trailing_blocks"] = []
	vessel["state"] = "scheduled_strategic"
	vessel["wait_seconds"] = 0.0
	vessel["schedule_age_s"] = desired_time
	vessel["trip_started_s"] = simulated_seconds - desired_time
	vessel["trip_distance_m"] = desired_time * speed
	_update_pose(vessel, selected_edge, progress)


func _process_pending_route_plans(maximum: int) -> void:
	if _interest_centers.is_empty():
		return
	for unused in range(mini(maximum, _pending_plan_ids.size())):
		var selected_index := _nearest_pending_plan_index()
		if selected_index < 0:
			return
		var vessel_id := _pending_plan_ids[selected_index]
		_pending_plan_ids.remove_at(selected_index)
		if not vessels.has(vessel_id):
			continue
		var vessel := vessels[vessel_id] as Dictionary
		_activate_initial_vessel(vessel, true)
		vessels[vessel_id] = vessel
		if str(vessel.get("state", "")) == "scheduled_strategic":
			# The published contact may currently share a controlled block with an
			# exact ship. Keep its cheap AIS movement and retry instead of snapping
			# it to an unrelated empty section.
			_pending_plan_ids.append(vessel_id)
		elif not _exact_vessel_ids.has(vessel_id):
			_exact_vessel_ids.append(vessel_id)


func _nearest_pending_plan_index() -> int:
	var best_index := -1
	var best_distance := STRATEGIC_PROMOTION_RADIUS_M * STRATEGIC_PROMOTION_RADIUS_M
	for index in range(_pending_plan_ids.size()):
		var vessel := vessels.get(_pending_plan_ids[index], {}) as Dictionary
		var point := vessel.get("position", Vector2.ZERO) as Vector2
		for center in _interest_centers:
			var distance := point.distance_squared_to(center)
			if distance < best_distance:
				best_distance = distance
				best_index = index
	return best_index


func _advance_strategic(vessel: Dictionary, delta: float) -> void:
	var remaining_s := maxf(delta, 0.0)
	var guard := 0
	while remaining_s > 0.001 and guard < 64:
		guard += 1
		var route := vessel.get("route_steps", []) as Array
		var route_index := int(vessel.get("route_index", 0))
		if route.is_empty() or route_index >= route.size():
			_complete_strategic_trip(vessel)
			if str(vessel.get("state", "")) == "route_failed":
				return
			continue
		var edge := _step_record(route[route_index] as Dictionary)
		if edge.is_empty():
			_fail_route(vessel, "strategic contract route references a missing edge")
			return
		var length := maxf(float(edge.get("length_m", 0.0)), 0.01)
		var speed := maxf(float(edge.get("speed_limit_ms", 7.2)), 0.5)
		var progress := clampf(float(vessel.get("edge_progress_m", 0.0)), 0.0, length)
		var available := maxf(length - progress, 0.0)
		var travelled := minf(remaining_s * speed, available)
		progress += travelled
		remaining_s -= travelled / speed
		vessel["trip_distance_m"] = float(vessel.get("trip_distance_m", 0.0)) + travelled
		vessel["edge_progress_m"] = progress
		_update_pose(vessel, edge, progress)
		if progress < length - 0.001:
			return
		vessel["route_index"] = route_index + 1
		vessel["edge_progress_m"] = 0.0


func _complete_strategic_trip(vessel: Dictionary) -> void:
	var trip_seconds := maxf(simulated_seconds
		- float(vessel.get("trip_started_s", simulated_seconds)), 0.0)
	vessel["deliveries"] = int(vessel.get("deliveries", 0)) + 1
	_metrics["trips_completed"] = int(_metrics.get("trips_completed", 0)) + 1
	_metrics["total_trip_seconds"] = float(_metrics.get("total_trip_seconds", 0.0)) \
		+ trip_seconds
	_metrics["total_distance_m"] = float(_metrics.get("total_distance_m", 0.0)) \
		+ float(vessel.get("trip_distance_m", 0.0))
	var source_id := str(vessel.get("destination_token_id", ""))
	vessel["source_token_id"] = source_id
	vessel["destination_token_id"] = _pick_destination(source_id,
		int(vessel.get("index", 0)), int(vessel.get("deliveries", 0)))
	vessel["destination_requested"] = false
	_plan_trip(vessel)
	if str(vessel.get("state", "")) != "route_failed":
		vessel["state"] = "scheduled_strategic"
		vessel["step_active"] = false
		vessel["current_block_id"] = ""


func _make_vessel(
		vessel_id: String,
		index: int,
		source_id: String,
		destination_id: String,
) -> Dictionary:
	var source := network.berth_tokens[source_id] as Dictionary
	var source_node := network.node(str(source.get("node_id", "")))
	return {
		"id": vessel_id,
		"index": index,
		# Current debug fleet alternates cargo/bulk fit-outs on the shared 28x10
		# coastal hull. Production records replace these with their registered
		# vessel dimensions before routing.
		"length_m": 28.0,
		"beam_m": 10.0,
		"draft_m": 3.0,
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
		"open_water_retry_s": -1.0,
		"open_merge_port_id": "",
		"open_merge_release_after_index": -1,
		"open_merge_waiting": false,
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
		"blocked_by": "",
		"blocked_at": "",
		"blocked_reason": "",
		"authority_elapsed_s": 0.0,
		"authority_phase_tick": posmod(index * 7 + scenario_seed, 20),
		"deliveries": 0,
	}


func _place_initial_underway(
		vessel: Dictionary,
		published_position := Vector2.INF,
		preserve_published_section := false,
) -> bool:
	var route := vessel.get("route_steps", []) as Array
	var candidates: Array[Dictionary] = []
	var total_travel_s := 0.0
	for step_index in range(route.size()):
		var step := route[step_index] as Dictionary
		var edge := _step_record(step)
		var step_kind := str(step.get("kind", ""))
		var edge_kind := str(edge.get("kind", ""))
		var from_node := network.node(str(edge.get("from_node_id", "")))
		var waterway_id := str(from_node.get("waterway_id", ""))
		# Persistent fleets are sampled from their deterministic voyage age. A
		# hybrid voyage may therefore begin on its open-water A* section; forcing
		# every such record onto the first controlled lane caused route failures
		# and artificial spawn queues at login. Port approaches remain excluded.
		if step_kind != "open_water" and edge_kind not in [
				"main_lane", "regional_lane", "waterway_junction", "passing_lane"]:
			continue
		if step_kind != "open_water" and waterway_id == "open_ocean_bus":
			continue
		var length := maxf(float(edge.get("length_m", 0.0)), 1.0)
		var speed := maxf(float(edge.get("speed_limit_ms", 7.2)), 0.5)
		var travel_s := length / speed
		candidates.append({
			"step_index": step_index,
			"travel_s": travel_s,
			"elapsed_before_s": total_travel_s,
		})
		if published_position.is_finite():
			var nearest := _nearest_polyline_progress(
				edge.get("points", PackedVector2Array()) as PackedVector2Array,
				published_position)
			candidates[-1]["published_progress_m"] = float(nearest.get(
				"progress_m", 0.0))
			candidates[-1]["published_distance_squared"] = float(nearest.get(
				"distance_squared", INF))
		total_travel_s += travel_s
	if candidates.is_empty():
		return false
	var vessel_index := int(vessel.get("index", 0))
	var phase := _deterministic_fraction(vessel_index, 17)
	var desired_time := phase * total_travel_s
	var preferred_index := 0
	if published_position.is_finite():
		var nearest_distance_squared := INF
		for index in range(candidates.size()):
			var distance_squared := float((candidates[index] as Dictionary).get(
				"published_distance_squared", INF))
			if distance_squared < nearest_distance_squared:
				nearest_distance_squared = distance_squared
				preferred_index = index
	else:
		for index in range(candidates.size()):
			var candidate := candidates[index] as Dictionary
			if desired_time <= float(candidate.get("elapsed_before_s", 0.0)) \
					+ float(candidate.get("travel_s", 0.0)):
				preferred_index = index
				break
	var attempts := 1 if preserve_published_section and published_position.is_finite() \
		else candidates.size()
	for offset in range(attempts):
		var candidate_index := posmod(preferred_index + offset, candidates.size())
		var candidate := candidates[candidate_index] as Dictionary
		var route_index := int(candidate.get("step_index", 0))
		var step := route[route_index] as Dictionary
		var edge := _step_record(step)
		var length := maxf(float(edge.get("length_m", 0.0)), 1.0)
		var speed := maxf(float(edge.get("speed_limit_ms", 7.2)), 0.5)
		var margin := minf(maxf(float(vessel.get("length_m", 28.0)), 24.0), length * 0.18)
		var usable := maxf(length - margin * 2.0, 1.0)
		var progress := margin + usable * _deterministic_fraction(vessel_index, 31 + offset)
		if offset == 0 and published_position.is_finite():
			progress = clampf(float(candidate.get("published_progress_m", progress)),
				margin, maxf(length - margin, margin))
		if str(step.get("kind", "")) == "open_water":
			var section_id := "%d:%d" % [
				int(vessel.get("trip_serial", 0)), route_index]
			var points := edge.get("points", PackedVector2Array()) as PackedVector2Array
			var link_id := "%s>%s" % [str(step.get("from_ramp_id", "")),
				str(step.get("to_ramp_id", ""))]
			var allocation: Dictionary = _open_water_schedule.request(
				str(vessel.get("id", "")), section_id, points,
				-progress / speed, speed, float(vessel.get("length_m", 40.0)), link_id)
			if not bool(allocation.get("ok", false)):
				continue
			var scheduled_progress := -float(allocation.get("start_s", 0.0)) * speed
			if scheduled_progress < margin or scheduled_progress > length - margin:
				_open_water_schedule.release(str(vessel.get("id", "")), section_id)
				continue
			progress = scheduled_progress
			vessel["current_block_id"] = ""
			vessel["open_water_section_id"] = section_id
			vessel["open_water_start_s"] = float(allocation.get("start_s", 0.0))
			vessel["state"] = "traveling_open_water"
		else:
			var blocks := edge.get("block_ids", PackedStringArray()) as PackedStringArray
			if blocks.is_empty():
				continue
			var block_id := blocks[0]
			if not authority.occupy(str(vessel.get("id", "")), block_id):
				continue
			vessel["current_block_id"] = block_id
			vessel["open_water_section_id"] = ""
			vessel["open_water_start_s"] = -1.0
			vessel["state"] = "traveling"
		vessel["route_index"] = route_index
		vessel["edge_progress_m"] = progress
		vessel["step_active"] = true
		var historical_age_s := float(candidate.get("elapsed_before_s", 0.0)) \
			+ progress / speed
		vessel["trip_started_s"] = -historical_age_s
		vessel["trip_distance_m"] = historical_age_s * speed
		vessel["schedule_age_s"] = historical_age_s
		_update_pose(vessel, edge, progress)
		return true
	return false


static func _nearest_polyline_progress(
		points: PackedVector2Array,
		query: Vector2,
) -> Dictionary:
	if points.is_empty():
		return {"progress_m": 0.0, "distance_squared": INF}
	if points.size() == 1:
		return {"progress_m": 0.0, "distance_squared": query.distance_squared_to(points[0])}
	var best_progress := 0.0
	var best_distance_squared := INF
	var accumulated := 0.0
	for index in range(points.size() - 1):
		var start := points[index]
		var finish := points[index + 1]
		var segment := finish - start
		var segment_length := segment.length()
		if segment_length <= 0.001:
			continue
		var fraction := clampf((query - start).dot(segment) /
			segment.length_squared(), 0.0, 1.0)
		var projected := start + segment * fraction
		var distance_squared := query.distance_squared_to(projected)
		if distance_squared < best_distance_squared:
			best_distance_squared = distance_squared
			best_progress = accumulated + segment_length * fraction
		accumulated += segment_length
	return {"progress_m": best_progress, "distance_squared": best_distance_squared}


func _deterministic_fraction(vessel_index: int, salt: int) -> float:
	# Integer-only hash: stable across clients and dedicated servers.
	var value := posmod(
		(vessel_index + 1) * 1103515245 + scenario_seed * 12345 + salt * 265443576,
		2147483647,
	)
	return float(value) / 2147483647.0


func advance(seconds: float) -> void:
	if network == null or vessels.is_empty() or seconds <= 0.0:
		return
	_accumulator += seconds
	while _accumulator >= FIXED_STEP_S:
		_accumulator -= FIXED_STEP_S
		_step(FIXED_STEP_S)


## A local single-player authority supplies one observer; a dedicated server
## supplies all connected-player interest centers. Results remain authoritative,
## but empty ocean contacts advance on AIS-like strategic cadences instead of
## burning a 2 Hz logic budget thousands of kilometres from every player.
func set_interest_centers(points: PackedVector2Array) -> void:
	_interest_centers = points.duplicate()


func vessel_records() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for vessel_id in _sorted_vessel_ids:
		result.append((vessels[vessel_id] as Dictionary).duplicate(true))
	return result


## Compact snapshot for rendering, chart contacts and network replication.
## Route geometry remains authority-side, so copying 1,000 contacts does not
## duplicate thousands of waypoint arrays every presentation tick.
func presentation_records() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for vessel_id in _sorted_vessel_ids:
		result.append(_presentation_record(vessels[vessel_id] as Dictionary))
	return result


func presentation_record(vessel_id: String) -> Dictionary:
	return _presentation_record(vessels.get(vessel_id, {}) as Dictionary)


static func _presentation_record(vessel: Dictionary) -> Dictionary:
	if vessel.is_empty():
		return {}
	return {
		"id": str(vessel.get("id", "")),
		"index": int(vessel.get("index", 0)),
		"position": vessel.get("position", Vector2.ZERO),
		"heading": vessel.get("heading", Vector2(0.0, -1.0)),
		"state": str(vessel.get("state", "unknown")),
		"route_mode": str(vessel.get("route_mode", "pending")),
		"open_water_sections": int(vessel.get("open_water_sections", 0)),
		"length_m": float(vessel.get("length_m", 40.0)),
		"beam_m": float(vessel.get("beam_m", 10.0)),
		"source_token_id": str(vessel.get("source_token_id", "")),
		"destination_token_id": str(vessel.get("destination_token_id", "")),
		"current_block_id": str(vessel.get("current_block_id", "")),
		"wait_seconds": float(vessel.get("wait_seconds", 0.0)),
		"deliveries": int(vessel.get("deliveries", 0)),
	}


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
		if state in ["waiting_berth", "waiting_port_approach"]:
			active_queue_count += 1
		if _is_unresolved_starvation(vessel):
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
		"pending_route_plans": _pending_plan_ids.size(),
		"open_water_schedule": _open_water_schedule.summary() \
			if _open_water_schedule != null else {},
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
		"Authority: reservation denials %d | overtakes %d | queue entries %d | berth promotions %d" % [
			int(data.get("reservation_denials", 0)), int(data.get("overtakes", 0)),
			int(data.get("queue_entries", 0)), int(data.get("berth_promotions", 0))],
		"Open water: %s" % JSON.stringify(data.get("open_water_schedule", {})),
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
		"open_merge_owners": _open_merge_owner_by_port.duplicate(true),
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
			"open_water_section_id": str(vessel.get("open_water_section_id", "")),
			"open_water_start_s": float(vessel.get("open_water_start_s", -1.0)),
			"open_merge_port_id": str(vessel.get("open_merge_port_id", "")),
			"open_merge_release_after_index": int(vessel.get(
				"open_merge_release_after_index", -1)),
			"open_merge_waiting": bool(vessel.get("open_merge_waiting", false)),
			"current_block_id": str(vessel.get("current_block_id", "")),
			"blocked_by": str(vessel.get("blocked_by", "")),
			"blocked_at": str(vessel.get("blocked_at", "")),
			"blocked_reason": str(vessel.get("blocked_reason", "")),
			"departure_blocked_by": str(vessel.get("departure_blocked_by", "")),
			"departure_blocked_at": str(vessel.get("departure_blocked_at", "")),
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
			"from_ramp_id": str(step.get("from_ramp_id", "")),
			"to_ramp_id": str(step.get("to_ramp_id", "")),
			"length_m": float(step.get("length_m", 0.0)),
		})
	return result


func _step(delta: float) -> void:
	simulated_seconds += delta
	_authority_tick_index += 1
	if simulated_seconds + 0.001 >= _next_background_plan_s:
		_process_pending_route_plans(BACKGROUND_ROUTE_PLANS_PER_STEP)
		_next_background_plan_s = simulated_seconds + BACKGROUND_ROUTE_PLAN_INTERVAL_S
	_rebuild_controlled_spatial_buckets()
	_rebuild_open_water_obstacle_buckets()
	_rebuild_open_water_arrival_ranks()
	var progressed := false
	# Dormant world contacts live in 10-second AIS buckets. Only one phase is
	# touched per authority tick, so 1,000 or 10,000 remote records do not get
	# scanned at 2 Hz merely to discover that they are not due yet.
	if not _strategic_phase_buckets.is_empty():
		var due_phase := posmod(-_authority_tick_index, _strategic_phase_buckets.size())
		for vessel_id in _strategic_phase_buckets[due_phase]:
			var strategic := vessels.get(vessel_id, {}) as Dictionary
			if str(strategic.get("state", "")) != "scheduled_strategic":
				continue
			var last_update := float(strategic.get("strategic_last_update_s", 0.0))
			_advance_strategic(strategic, maxf(simulated_seconds - last_update, delta))
			strategic["strategic_last_update_s"] = simulated_seconds
			vessels[vessel_id] = strategic
	# Signal-controlled movements have right of way at an interchange. Process
	# them first so an open-water ship reads their same-tick position instead of
	# stepping into a ramp block that was entered later in id order.
	var controlled_order := PackedStringArray()
	var open_water_order := PackedStringArray()
	for vessel_id in _exact_vessel_ids:
		if _vessel_is_on_open_water_step(vessels[vessel_id] as Dictionary):
			open_water_order.append(vessel_id)
		else:
			controlled_order.append(vessel_id)
	var controlled_count := controlled_order.size()
	controlled_order.append_array(open_water_order)
	for order_index in range(controlled_order.size()):
		if order_index == controlled_count:
			# Include blocks entered by the controlled phase itself. Without this
			# refresh, a free-sailing ship earlier in id order can miss a ramp
			# movement that began during the same authority tick.
			_rebuild_controlled_spatial_buckets()
		var vessel_id := controlled_order[order_index]
		var vessel := vessels[vessel_id] as Dictionary
		var elapsed := float(vessel.get("authority_elapsed_s", 0.0)) + delta
		var cadence := _authority_cadence(vessel)
		var interval_ticks := maxi(1, roundi(cadence / FIXED_STEP_S))
		var phase_tick := int(vessel.get("authority_phase_tick", 0))
		if interval_ticks > 1 \
				and posmod(_authority_tick_index + phase_tick, interval_ticks) != 0:
			vessel["authority_elapsed_s"] = elapsed
			vessels[vessel_id] = vessel
			continue
		vessel["authority_elapsed_s"] = 0.0
		if _step_vessel(vessel, elapsed):
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
		_next_proximity_check_s = simulated_seconds + 5.0
		_check_proximity_collisions()


func _vessel_is_on_open_water_step(vessel: Dictionary) -> bool:
	if not bool(vessel.get("step_active", false)):
		return false
	var route := vessel.get("route_steps", []) as Array
	var route_index := int(vessel.get("route_index", -1))
	return route_index >= 0 and route_index < route.size() \
		and str((route[route_index] as Dictionary).get("kind", "")) == "open_water"


func _authority_cadence(vessel: Dictionary) -> float:
	var state := str(vessel.get("state", ""))
	if state in ["docked", "departing", "waiting_departure_clearance"] \
			or state.begins_with("waiting"):
		return FIXED_STEP_S
	var block := network.block(str(vessel.get("current_block_id", "")))
	if str(block.get("kind", "")) in ["quay_maneuver", "port_approach",
			"port_connector", "port_merge", "port_feeder", "shipping_ramp"]:
		return FIXED_STEP_S
	if _interest_centers.is_empty():
		return REMOTE_AUTHORITY_STEP_S
	var position := vessel.get("position", Vector2.ZERO) as Vector2
	var nearest_squared := INF
	for center in _interest_centers:
		nearest_squared = minf(nearest_squared, position.distance_squared_to(center))
	if nearest_squared <= NEAR_AUTHORITY_RADIUS_M * NEAR_AUTHORITY_RADIUS_M:
		return FIXED_STEP_S
	if nearest_squared <= MID_AUTHORITY_RADIUS_M * MID_AUTHORITY_RADIUS_M:
		return MID_AUTHORITY_STEP_S
	return REMOTE_AUTHORITY_STEP_S


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
	if str((route[route_index] as Dictionary).get("kind", "")) == "open_water":
		# Join the destination authority before reaching its on-ramp. This gives
		# the arriving ship a deterministic FIFO identity while it is still at
		# sea, without reserving an empty berth for the whole crossing.
		if length - progress <= OPEN_WATER_ARRIVAL_QUEUE_M \
				and _open_step_targets_destination(vessel, route[route_index] as Dictionary):
			_ensure_destination_request(vessel)
		if length - progress <= OPEN_WATER_ARRIVAL_QUEUE_M \
				and not _ensure_open_merge_authority(vessel):
			var arrival_rank := _open_water_arrival_rank(vessel, route_index)
			var merge_margin := OPEN_WATER_PORT_STANDOFF_M + float(arrival_rank) * (
				float(vessel.get("length_m", 40.0)) + OPEN_WATER_QUEUE_GAP_M)
			var merge_hold_progress := maxf(0.0, length - merge_margin)
			# Never teleport a record backwards if a restored authoritative
			# snapshot already lies inside the approach envelope. New movement is
			# still stopped until the merge token becomes available.
			progress = old_progress if old_progress > merge_hold_progress \
				else minf(progress, merge_hold_progress)
		var proposed := (_sample_polyline(
			edge.get("points", PackedVector2Array()) as PackedVector2Array,
			progress).get("position", vessel.get("position", Vector2.ZERO)) as Vector2)
		if not _open_water_clear_to_advance(vessel, proposed):
			vessel["state"] = "waiting_traffic_clearance"
			_wait(vessel, delta)
			return false
	var held_for_next := false
	if route_index + 1 < route.size():
		var stopping_margin := minf(float(vessel.get("length_m", 40.0)) + 12.0,
			length * 0.8)
		if str((route[route_index] as Dictionary).get("kind", "")) == "open_water":
			# Every A* passage ends at a merge, even when the merge is only an
			# intermediate lane change. Hold outside the entire interchange until
			# the ON-ramp block is available; a one-hull stopping distance still
			# lets a controlled ship drive into the stationary open-water hull.
			stopping_margin = maxf(stopping_margin, OPEN_WATER_PORT_STANDOFF_M)
			var arrival_rank := _open_water_arrival_rank(vessel, route_index)
			if arrival_rank > 0:
				stopping_margin += float(arrival_rank) * (
					float(vessel.get("length_m", 40.0)) + OPEN_WATER_QUEUE_GAP_M)
				stopping_margin = minf(stopping_margin, length * 0.92)
		var hold_progress := maxf(0.0, length - stopping_margin)
		if progress >= hold_progress and not _pre_reserve_step(vessel, route_index + 1):
			progress = minf(progress, hold_progress)
			held_for_next = true
	var moved := progress - old_progress
	vessel["edge_progress_m"] = progress
	vessel["trip_distance_m"] = float(vessel.get("trip_distance_m", 0.0)) + moved
	_advance_trailing_blocks(vessel, moved)
	_update_pose(vessel, edge, progress)
	# The merge token protects the open mouth until the ship has traversed its
	# first complete downstream block. Once the bow reaches that block's end,
	# ordinary block occupancy and trailing-hull clearance protect the merge.
	# Waiting for the *next* edge to be entered kept the token forever whenever
	# that next edge was a busy berth gate.
	var merge_release_after := int(vessel.get("open_merge_release_after_index", -1))
	if merge_release_after >= 0 and route_index >= merge_release_after \
			and progress >= length - 0.001:
		_release_open_merge_authority(vessel)
	if held_for_next:
		var current_step := route[route_index] as Dictionary
		var next_step := route[route_index + 1] as Dictionary
		var next_edge := _step_record(next_step)
		var next_blocks := next_edge.get("block_ids", PackedStringArray()) as PackedStringArray
		var next_block := network.block(next_blocks[0]) if not next_blocks.is_empty() else {}
		if bool(vessel.get("open_merge_waiting", false)):
			vessel["state"] = "waiting_open_merge"
		elif _waiting_for_booked_open_slot(vessel) \
				or str(next_step.get("kind", "")) == "open_water":
			vessel["state"] = "waiting_open_water_slot"
		elif (str(current_step.get("kind", "")) == "open_water" \
				and _open_step_targets_destination(vessel, current_step)) \
				or bool(vessel.get("destination_requested", false)):
			vessel["state"] = "waiting_port_approach"
		else:
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


func _open_water_arrival_rank(vessel: Dictionary, route_index: int) -> int:
	return int(_open_water_arrival_ranks.get(str(vessel.get("id", "")), 0))


func _open_step_targets_destination(vessel: Dictionary, step: Dictionary) -> bool:
	if str(step.get("kind", "")) != "open_water" or network == null:
		return false
	var destination_token := network.berth_tokens.get(
		str(vessel.get("destination_token_id", "")), {}) as Dictionary
	var ramp := network.port_ramps.get(str(step.get("to_ramp_id", "")), {}) as Dictionary
	return not destination_token.is_empty() and not ramp.is_empty() \
		and str(destination_token.get("port_id", "")) == str(ramp.get("port_id", ""))


func _current_open_step_targets_destination(vessel: Dictionary) -> bool:
	var route := vessel.get("route_steps", []) as Array
	var route_index := int(vessel.get("route_index", -1))
	return route_index >= 0 and route_index < route.size() \
		and _open_step_targets_destination(vessel, route[route_index] as Dictionary)


func _is_unresolved_starvation(vessel: Dictionary) -> bool:
	if float(vessel.get("wait_seconds", 0.0)) < DEADLOCK_WINDOW_S:
		return false
	return not _wait_has_explicit_authority_cause(vessel, {})


func _wait_has_explicit_authority_cause(vessel: Dictionary, visited: Dictionary) -> bool:
	var vessel_id := str(vessel.get("id", ""))
	if visited.has(vessel_id):
		return false
	visited[vessel_id] = true
	var state := str(vessel.get("state", ""))
	# These waits all expose a deterministic future condition: a booked water
	# slot, a berth FIFO rank, a port merge token, or a hull physically ahead.
	# They remain visible in state/max-wait telemetry; they are not silently
	# counted as healthy movement, but neither are they unresolved starvation.
	if state in ["waiting_open_water_slot", "waiting_berth", "waiting_port_approach",
			"waiting_open_merge"]:
		return true
	if state in ["traveling", "traveling_open_water", "departing"]:
		return true
	if _waiting_for_booked_open_slot(vessel):
		return true
	if state == "waiting_traffic_clearance" \
			and (_current_open_step_targets_destination(vessel) \
				or bool(vessel.get("open_merge_waiting", false))):
		return true
	if state == "waiting_traffic_clearance":
		var clearance_blocker := vessels.get(
			str(vessel.get("blocked_by", "")), {}) as Dictionary
		return not clearance_blocker.is_empty() \
			and _wait_has_explicit_authority_cause(clearance_blocker, visited)
	if state == "waiting_signal":
		var blocker := vessels.get(str(vessel.get("blocked_by", "")), {}) as Dictionary
		return not blocker.is_empty() \
			and _wait_has_explicit_authority_cause(blocker, visited)
	if state == "waiting_departure_clearance":
		var departure_blocker := vessels.get(
			str(vessel.get("departure_blocked_by", "")), {}) as Dictionary
		return not departure_blocker.is_empty() \
			and _wait_has_explicit_authority_cause(departure_blocker, visited)
	return false


func _rebuild_open_water_arrival_ranks() -> void:
	_open_water_arrival_ranks.clear()
	var groups: Dictionary = {}
	for vessel_id in _exact_vessel_ids:
		var vessel := vessels.get(vessel_id, {}) as Dictionary
		if not bool(vessel.get("step_active", false)):
			continue
		var route := vessel.get("route_steps", []) as Array
		var route_index := int(vessel.get("route_index", -1))
		if route_index < 0 or route_index >= route.size():
			continue
		var step := route[route_index] as Dictionary
		if str(step.get("kind", "")) != "open_water":
			continue
		var to_ramp_id := str(step.get("to_ramp_id", ""))
		if to_ramp_id.is_empty():
			continue
		var edge := _step_record(step)
		var remaining := maxf(float(edge.get("length_m", 0.0))
			- float(vessel.get("edge_progress_m", 0.0)), 0.0)
		if remaining > OPEN_WATER_ARRIVAL_QUEUE_M:
			continue
		# Every ramp mouth at a port shares the same final manoeuvring water.
		# Rank them as one interchange, not as independent endpoint queues.
		var ramp := network.port_ramps.get(to_ramp_id, {}) as Dictionary
		var group_id := "port:%s" % str(ramp.get("port_id", to_ramp_id))
		var eligible := true
		if _open_step_targets_destination(vessel, step):
			# A ship without an assigned berth remains in the lane-side FIFO; it
			# must not monopolize the open-water merge token while through traffic
			# has a clear downstream ramp.
			eligible = not authority.berth_assignment(str(vessel_id)).is_empty()
		var group := groups.get(group_id, []) as Array
		group.append({"id": str(vessel_id), "remaining_m": remaining,
			"eligible": eligible})
		groups[group_id] = group
	for group_value in groups.values():
		var group := group_value as Array
		group.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if bool(a.get("eligible", true)) != bool(b.get("eligible", true)):
				return bool(a.get("eligible", true))
			var a_remaining := float(a.get("remaining_m", 0.0))
			var b_remaining := float(b.get("remaining_m", 0.0))
			if not is_equal_approx(a_remaining, b_remaining):
				return a_remaining < b_remaining
			return str(a.get("id", "")) < str(b.get("id", "")))
		for rank in range(group.size()):
			_open_water_arrival_ranks[str((group[rank] as Dictionary).get("id", ""))] = rank


func _open_water_clear_to_advance(vessel: Dictionary, proposed: Vector2) -> bool:
	# Open-water transfers yield to signal-controlled traffic and to any
	# free-sailing vessel which has stopped at a controlled merge. The temporal
	# scheduler separates moving open-water passages, but a ship delayed beyond
	# its booked arrival window becomes a real obstacle that later passages must
	# see. This swept test covers both cases without promoting either ship to a
	# per-frame physics body.
	# It is deterministic, data-only, and runs only for a vessel on its coarse
	# authority tick (not once per rendered frame).
	var vessel_id := str(vessel.get("id", ""))
	var owns_merge := _owns_next_controlled_entry(vessel)
	var start := vessel.get("position", proposed) as Vector2
	var padding := maxf(16.0, float(vessel.get("beam_m", 10.0)) + 8.0)
	var lower := Vector2(minf(start.x, proposed.x), minf(start.y, proposed.y)) \
		- Vector2.ONE * padding
	var upper := Vector2(maxf(start.x, proposed.x), maxf(start.y, proposed.y)) \
		+ Vector2.ONE * padding
	var lower_cell := Vector2i(floori(lower.x / TRAFFIC_CLEARANCE_CELL_M),
		floori(lower.y / TRAFFIC_CLEARANCE_CELL_M))
	var upper_cell := Vector2i(floori(upper.x / TRAFFIC_CLEARANCE_CELL_M),
		floori(upper.y / TRAFFIC_CLEARANCE_CELL_M))
	var candidates := PackedStringArray()
	var seen: Dictionary = {}
	for cell_x in range(lower_cell.x, upper_cell.x + 1):
		for cell_y in range(lower_cell.y, upper_cell.y + 1):
			var cell := Vector2i(cell_x, cell_y)
			for bucket_value in [
					_controlled_spatial_buckets.get(cell, PackedStringArray()),
					_open_water_obstacle_buckets.get(cell, PackedStringArray()),
			]:
				for candidate_id in bucket_value as PackedStringArray:
					if not seen.has(candidate_id):
						seen[candidate_id] = true
						candidates.append(candidate_id)
	for other_id in candidates:
		if other_id == vessel_id:
			continue
		var other := vessels.get(other_id, {}) as Dictionary
		if str(other.get("state", "")) in ["docked", "route_failed", "scheduled_strategic"]:
			continue
		var other_is_controlled := not str(other.get("current_block_id", "")).is_empty()
		var clearance := maxf(8.0,
			(float(vessel.get("beam_m", 10.0)) + float(other.get("beam_m", 10.0)))
			* 0.5 + 3.0)
		var other_position := other.get("position", Vector2.ZERO) as Vector2
		if _point_segment_distance(other_position, start, proposed) >= clearance:
			continue
		if other_is_controlled:
			# The graph-authorized movement has right of way at a ramp or at a
			# connector crossing. Once this open-water vessel atomically owns its
			# ON-ramp chain, however, the controlled side is already held at red.
			# Yielding to that stopped hull as well creates a two-sided deadlock.
			if not owns_merge:
				vessel["blocked_by"] = other_id
				vessel["blocked_reason"] = "open_water_yields_to_controlled"
				return false
			continue
		var movement := proposed - start
		var movement_direction := movement.normalized() \
			if movement.length_squared() > 0.001 else Vector2.ZERO
		var other_heading := other.get("heading", Vector2.ZERO) as Vector2
		if not movement_direction.is_zero_approx() and not other_heading.is_zero_approx() \
				and movement_direction.dot(other_heading) >= 0.7:
			# In a convoy only the ship physically ahead constrains this ship.
			# The leader must not stop because a follower is within the swept
			# AABB behind its stern.
			if (other_position - start).dot(movement_direction) > 0.0:
				vessel["blocked_by"] = other_id
				vessel["blocked_reason"] = "open_water_convoy_headway"
				return false
			continue
		# Temporal scheduling normally prevents crossing encounters. If one
		# ship has been delayed beyond its slot, a stable id tie-break gives
		# exactly one of them right of way instead of making both wait forever.
		if other_id < vessel_id:
			vessel["blocked_by"] = other_id
			vessel["blocked_reason"] = "open_water_crossing_priority"
			return false
	_clear_blocker(vessel)
	return true


func _owns_next_controlled_entry(vessel: Dictionary) -> bool:
	var route := vessel.get("route_steps", []) as Array
	var route_index := int(vessel.get("route_index", -1))
	if route_index < 0 or route_index + 1 >= route.size():
		return false
	var next_step := route[route_index + 1] as Dictionary
	if str(next_step.get("kind", "")) != "controlled":
		return false
	var edge := network.edge(str(next_step.get("edge_id", "")))
	var blocks := edge.get("block_ids", PackedStringArray()) as PackedStringArray
	return not blocks.is_empty() \
		and authority.owner_of(blocks[0]) == str(vessel.get("id", ""))


func _rebuild_controlled_spatial_buckets() -> void:
	_controlled_spatial_buckets.clear()
	for vessel_id in _exact_vessel_ids:
		var vessel := vessels.get(vessel_id, {}) as Dictionary
		if str(vessel.get("state", "")) in ["docked", "route_failed", "scheduled_strategic"] \
				or str(vessel.get("current_block_id", "")).is_empty():
			continue
		var point := vessel.get("position", Vector2.ZERO) as Vector2
		var cell := Vector2i(floori(point.x / TRAFFIC_CLEARANCE_CELL_M),
			floori(point.y / TRAFFIC_CLEARANCE_CELL_M))
		var bucket := _controlled_spatial_buckets.get(cell, PackedStringArray()) \
			as PackedStringArray
		bucket.append(vessel_id)
		_controlled_spatial_buckets[cell] = bucket


func _rebuild_open_water_obstacle_buckets() -> void:
	_open_water_obstacle_buckets.clear()
	for vessel_id in _exact_vessel_ids:
		var vessel := vessels.get(vessel_id, {}) as Dictionary
		if str(vessel.get("state", "")) in ["docked", "route_failed", "scheduled_strategic"] \
				or not str(vessel.get("current_block_id", "")).is_empty() \
				or not bool(vessel.get("step_active", false)):
			continue
		var route := vessel.get("route_steps", []) as Array
		var route_index := int(vessel.get("route_index", -1))
		if route_index < 0 or route_index >= route.size() \
				or str((route[route_index] as Dictionary).get("kind", "")) != "open_water":
			continue
		var point := vessel.get("position", Vector2.ZERO) as Vector2
		var cell := Vector2i(floori(point.x / TRAFFIC_CLEARANCE_CELL_M),
			floori(point.y / TRAFFIC_CLEARANCE_CELL_M))
		var bucket := _open_water_obstacle_buckets.get(cell, PackedStringArray()) \
			as PackedStringArray
		bucket.append(vessel_id)
		_open_water_obstacle_buckets[cell] = bucket


static func _point_segment_distance(point: Vector2, start: Vector2, finish: Vector2) -> float:
	var segment := finish - start
	var length_squared := segment.length_squared()
	if length_squared <= 0.0001:
		return point.distance_to(start)
	var ratio := clampf((point - start).dot(segment) / length_squared, 0.0, 1.0)
	return point.distance_to(start + segment * ratio)


func _pre_reserve_step(vessel: Dictionary, edge_index: int) -> bool:
	var route := vessel.get("route_steps", []) as Array
	if edge_index < 0 or edge_index >= route.size():
		return false
	var step := route[edge_index] as Dictionary
	if str(step.get("kind", "")) == "open_water":
		var current_index := int(vessel.get("route_index", -1))
		var travel_to_slot_s := 0.0
		if current_index >= 0 and current_index < route.size():
			var current_edge := _step_record(route[current_index] as Dictionary)
			var current_speed := maxf(float(current_edge.get("speed_limit_ms", 7.2)), 0.5)
			travel_to_slot_s = maxf(float(current_edge.get("length_m", 0.0))
				- float(vessel.get("edge_progress_m", 0.0)), 0.0) / current_speed
		return _ensure_open_water_allocation(vessel, edge_index, travel_to_slot_s)
	if _vessel_is_on_open_water_step(vessel) and not _ensure_open_merge_authority(vessel):
		return false
	var edge := network.edge(str(step.get("edge_id", "")))
	if not _ensure_open_slot_after_ramp(vessel, edge_index, edge):
		return false
	var block_ids := edge.get("block_ids", PackedStringArray()) as PackedStringArray
	if block_ids.is_empty():
		return false
	var block_id := block_ids[0]
	var block := network.block(block_id)
	if _block_begins_destination_port_entry(vessel, block):
		_ensure_destination_request(vessel)
		if authority.berth_assignment(str(vessel.get("id", ""))).is_empty():
			vessel["state"] = "waiting_berth"
			return false
	if not str(block.get("queue_port_id", "")).is_empty():
		_ensure_destination_request(vessel)
		if authority.berth_assignment(str(vessel.get("id", ""))).is_empty():
			return false
	var requested_blocks := _transition_chain_blocks(route, edge_index, edge)
	if requested_blocks.is_empty():
		requested_blocks.append(block_id)
	if _chain_has_denied_destination_entry(vessel, requested_blocks):
		return false
	var reservation := authority.try_reserve(str(vessel.get("id", "")), requested_blocks)
	if not bool(reservation.get("ok", false)):
		_record_blocker(vessel, reservation)
		_metrics["reservation_denials"] = int(_metrics.get("reservation_denials", 0)) + 1
		if _try_activate_passing(vessel, edge_index, block_id, reservation):
			return true
		return false
	_clear_blocker(vessel)
	return true


func _try_activate_passing(vessel: Dictionary, edge_index: int, blocked_block_id: String,
		reservation: Dictionary) -> bool:
	var blocker_id := str(reservation.get("blocked_by", ""))
	if blocker_id.is_empty() or not vessels.has(blocker_id):
		return false
	var blocker := vessels[blocker_id] as Dictionary
	# The outer lane is an access/overtaking lane, not a second high-speed route
	# chosen whenever ordinary traffic happens to be one block ahead. Activate it
	# only around a vessel that has stopped for a port queue; otherwise constant
	# weaving can gridlock both lanes in dense traffic.
	if str(blocker.get("state", "")) not in [
			"waiting_berth", "waiting_port_approach", "waiting_open_merge"]:
		return false
	# Do not jump the FIFO for the same destination.
	if str(blocker.get("destination_token_id", "")) \
			== str(vessel.get("destination_token_id", "")):
		return false
	var blocked := network.block(blocked_block_id)
	var zone_id := str(blocked.get("passing_zone_id", ""))
	if zone_id.is_empty() or not network.passing_zones.has(zone_id):
		return false
	var zone := network.passing_zones[zone_id] as Dictionary
	var direction := "forward" if (zone.get("forward_blocks", PackedStringArray()) \
		as PackedStringArray).has(blocked_block_id) else "reverse"
	var base_blocks := zone.get("%s_blocks" % direction, PackedStringArray()) as PackedStringArray
	if not base_blocks.has(blocked_block_id):
		return false
	var bypass_edge_ids := zone.get("%s_bypass_edge_ids" % direction,
		PackedStringArray()) as PackedStringArray
	var entry_edge_id := str(zone.get("%s_entry_edge_id" % direction, ""))
	var exit_edge_id := str(zone.get("%s_exit_edge_id" % direction, ""))
	if bypass_edge_ids.is_empty() or entry_edge_id.is_empty() or exit_edge_id.is_empty():
		return false
	var bypass_blocks := PackedStringArray()
	for transition_edge_id in [entry_edge_id]:
		bypass_blocks.append_array(network.edge(transition_edge_id).get(
			"block_ids", PackedStringArray()) as PackedStringArray)
	for bypass_edge_id in bypass_edge_ids:
		bypass_blocks.append_array(network.edge(bypass_edge_id).get(
			"block_ids", PackedStringArray()) as PackedStringArray)
	bypass_blocks.append_array(network.edge(exit_edge_id).get(
		"block_ids", PackedStringArray()) as PackedStringArray)
	var bypass_reservation := authority.try_reserve(str(vessel.get("id", "")), bypass_blocks)
	if not bool(bypass_reservation.get("ok", false)):
		return false
	var route := vessel.get("route_steps", []) as Array
	var remove_count := 0
	while edge_index + remove_count < route.size():
		var step := route[edge_index + remove_count] as Dictionary
		if str(step.get("kind", "")) != "controlled":
			break
		var step_edge := network.edge(str(step.get("edge_id", "")))
		var step_blocks := step_edge.get("block_ids", PackedStringArray()) as PackedStringArray
		if step_blocks.is_empty() or not base_blocks.has(step_blocks[0]):
			break
		remove_count += 1
	if remove_count <= 0:
		for reserved_block_id in bypass_blocks:
			authority.release_block(str(vessel.get("id", "")), reserved_block_id)
		return false
	for unused in range(remove_count):
		route.remove_at(edge_index)
	var replacement: Array[Dictionary] = [{"kind": "controlled", "edge_id": entry_edge_id}]
	for bypass_edge_id in bypass_edge_ids:
		replacement.append({"kind": "controlled", "edge_id": bypass_edge_id})
	replacement.append({"kind": "controlled", "edge_id": exit_edge_id})
	for replacement_index in range(replacement.size() - 1, -1, -1):
		route.insert(edge_index, replacement[replacement_index])
	vessel["route_steps"] = route
	_metrics["overtakes"] = int(_metrics.get("overtakes", 0)) + 1
	_event(str(vessel.get("id", "")), "reserved %s to pass %s" % [zone_id, blocker_id])
	return true


func _enter_step(vessel: Dictionary, edge_index: int) -> bool:
	var route := vessel.get("route_steps", []) as Array
	if edge_index < 0 or edge_index >= route.size():
		return false
	var step := route[edge_index] as Dictionary
	if str(step.get("kind", "")) == "open_water":
		if not _ensure_open_water_allocation(vessel, edge_index):
			return false
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
	if _vessel_is_on_open_water_step(vessel) and not _ensure_open_merge_authority(vessel):
		return false
	if not _ensure_open_slot_after_ramp(vessel, edge_index, edge):
		return false
	var block_ids := edge.get("block_ids", PackedStringArray()) as PackedStringArray
	if block_ids.is_empty():
		_fail_route(vessel, "edge has no authority block")
		return false
	var block_id := block_ids[0]
	var block := network.block(block_id)
	if _block_begins_destination_port_entry(vessel, block):
		_ensure_destination_request(vessel)
		if authority.berth_assignment(str(vessel.get("id", ""))).is_empty():
			vessel["state"] = "waiting_berth"
			return false
	if not str(block.get("queue_port_id", "")).is_empty():
		_ensure_destination_request(vessel)
	# Leaving the front queue position requires an actual berth assignment.
	var current_block := network.block(str(vessel.get("current_block_id", "")))
	if not str(current_block.get("queue_port_id", "")).is_empty() \
			and str(block.get("queue_port_id", "")).is_empty() \
			and authority.berth_assignment(str(vessel.get("id", ""))).is_empty():
		vessel["state"] = "waiting_berth"
		return false
	var requested_blocks := _transition_chain_blocks(route, edge_index, edge)
	if requested_blocks.is_empty():
		requested_blocks.append(block_id)
	if _chain_has_denied_destination_entry(vessel, requested_blocks):
		return false
	var reservation := authority.try_reserve(str(vessel.get("id", "")), requested_blocks)
	if not bool(reservation.get("ok", false)):
		_record_blocker(vessel, reservation)
		_metrics["reservation_denials"] = int(_metrics.get("reservation_denials", 0)) + 1
		vessel["state"] = "waiting_berth" \
			if not str(block.get("queue_port_id", "")).is_empty() else "waiting_signal"
		return false
	_clear_blocker(vessel)
	if not authority.occupy(str(vessel.get("id", "")), block_id):
		authority.release_block(str(vessel.get("id", "")), block_id)
		return false
	# Keep the interchange token through the first complete downstream block,
	# not merely through the segmented ON ramp. The merge lies at that trunk
	# block's entrance; releasing there lets the next open-water hull arrive
	# while this vessel is still physically crossing the approach.
	var merge_release_after := int(vessel.get("open_merge_release_after_index", -1))
	if merge_release_after >= 0 and edge_index > merge_release_after:
		_release_open_merge_authority(vessel)
	# A pre-booked A* slot belongs to the complete OFF-ramp chain. Releasing it
	# when the first segmented ramp block is entered forces the same vessel to
	# request a new (usually much later) slot while physically parked in the
	# interchange. The allocation is released when the open-water passage ends
	# and the vessel enters its destination ON ramp.
	if not str(edge.get("id", "")).contains(":off_ramp:transition:"):
		_release_open_water_allocation(vessel)
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


func _transition_chain_blocks(
		route: Array, edge_index: int, edge: Dictionary,
) -> PackedStringArray:
	# Ramp transitions are chain-signal territory: once the bow enters, the ship
	# must be able to clear every segmented block. Reserving only the first block
	# allowed a vessel to park halfway through an OFF ramp and pin both its A*
	# slot and the occupied berth's departure corridor.
	var edge_id := str(edge.get("id", ""))
	var marker := ":transition:"
	var marker_index := edge_id.find(marker)
	if marker_index < 0 or not edge_id.begins_with("ramp:"):
		return PackedStringArray()
	var transition_prefix := edge_id.left(marker_index + marker.length())
	var result := PackedStringArray()
	var cursor := edge_index
	while cursor < route.size():
		var step := route[cursor] as Dictionary
		if str(step.get("kind", "")) != "controlled":
			break
		var candidate := network.edge(str(step.get("edge_id", "")))
		if not str(candidate.get("id", "")).begins_with(transition_prefix):
			break
		for candidate_block_id in candidate.get(
				"block_ids", PackedStringArray()) as PackedStringArray:
			if not result.has(candidate_block_id):
				result.append(candidate_block_id)
		cursor += 1
	# An ON ramp is a chain signal through its merge. Claim the first downstream
	# trunk block as well, so no hull enters the ramp only to stop at its nose.
	# Destination gates on that block are evaluated before this reservation;
	# through traffic may use it normally.
	if edge_id.contains(":on_ramp:transition:") and cursor < route.size():
		var downstream_step := route[cursor] as Dictionary
		if str(downstream_step.get("kind", "")) == "controlled":
			var downstream_edge := network.edge(str(downstream_step.get("edge_id", "")))
			for downstream_block_id in downstream_edge.get(
					"block_ids", PackedStringArray()) as PackedStringArray:
				if not result.has(downstream_block_id):
					result.append(downstream_block_id)
	return result


func _chain_has_denied_destination_entry(
		vessel: Dictionary, block_ids: PackedStringArray,
) -> bool:
	for block_id in block_ids:
		if not _block_begins_destination_port_entry(vessel, network.block(block_id)):
			continue
		_ensure_destination_request(vessel)
		if authority.berth_assignment(str(vessel.get("id", ""))).is_empty():
			vessel["state"] = "waiting_berth"
			_release_open_merge_authority(vessel)
			return true
	return false


func _ensure_open_merge_authority(vessel: Dictionary) -> bool:
	var port_id := _current_open_merge_port_id(vessel)
	if port_id.is_empty():
		vessel["open_merge_waiting"] = false
		return true
	if _current_open_step_targets_destination(vessel) \
			and authority.berth_assignment(str(vessel.get("id", ""))).is_empty():
		vessel["open_merge_waiting"] = true
		return false
	var vessel_id := str(vessel.get("id", ""))
	var owner := str(_open_merge_owner_by_port.get(port_id, ""))
	if owner == vessel_id:
		vessel["open_merge_waiting"] = false
		return true
	if not owner.is_empty():
		vessel["open_merge_waiting"] = true
		return false
	if _open_water_arrival_rank(vessel, int(vessel.get("route_index", -1))) > 0:
		vessel["open_merge_waiting"] = true
		return false
	_open_merge_owner_by_port[port_id] = vessel_id
	vessel["open_merge_port_id"] = port_id
	vessel["open_merge_release_after_index"] = _open_merge_release_index(vessel)
	vessel["open_merge_waiting"] = false
	return true


func _release_open_merge_authority(vessel: Dictionary) -> void:
	var vessel_id := str(vessel.get("id", ""))
	for port_id_raw in _open_merge_owner_by_port.keys():
		var port_id := str(port_id_raw)
		if str(_open_merge_owner_by_port.get(port_id, "")) == vessel_id:
			_open_merge_owner_by_port.erase(port_id)
	vessel["open_merge_port_id"] = ""
	vessel["open_merge_release_after_index"] = -1
	vessel["open_merge_waiting"] = false


func _current_open_merge_port_id(vessel: Dictionary) -> String:
	var route := vessel.get("route_steps", []) as Array
	var route_index := int(vessel.get("route_index", -1))
	if route_index < 0 or route_index >= route.size():
		return ""
	var step := route[route_index] as Dictionary
	if str(step.get("kind", "")) != "open_water":
		return ""
	return str((network.port_ramps.get(str(step.get("to_ramp_id", "")), {}) \
		as Dictionary).get("port_id", ""))


func _open_merge_release_index(vessel: Dictionary) -> int:
	var route := vessel.get("route_steps", []) as Array
	var cursor := int(vessel.get("route_index", -1)) + 1
	while cursor < route.size():
		var step := route[cursor] as Dictionary
		if str(step.get("kind", "")) != "controlled":
			return cursor
		var edge := network.edge(str(step.get("edge_id", "")))
		if str(edge.get("kind", "")) != "shipping_ramp":
			return cursor
		cursor += 1
	return maxi(cursor - 1, int(vessel.get("route_index", 0)))


func _block_begins_destination_port_entry(vessel: Dictionary, block: Dictionary) -> bool:
	var entry_port_id := str(block.get("destination_port_entry", ""))
	if entry_port_id.is_empty():
		return false
	var destination := network.berth_tokens.get(
		str(vessel.get("destination_token_id", "")), {}) as Dictionary
	return str(destination.get("port_id", "")) == entry_port_id


func _ensure_open_slot_after_ramp(
		vessel: Dictionary, edge_index: int, edge: Dictionary,
) -> bool:
	# An OFF ramp is a chain signal for the following free-sailing crossing.
	# Booking only after reaching its end leaves the ship parked across the ramp
	# for the full schedule delay. Reserve the water slot before entering so it
	# waits in the ordinary lane, where unrelated traffic can use the bypass.
	var edge_id := str(edge.get("id", ""))
	var marker := ":off_ramp:transition"
	var marker_index := edge_id.find(marker)
	if marker_index < 0:
		return true
	var route := vessel.get("route_steps", []) as Array
	# A long ramp is split into several authority edges. Looking only one edge
	# ahead let a ship enter the first segment and then wait across the whole
	# interchange for an A* slot. Scan the complete ramp chain and book before
	# its first block instead.
	var transition_prefix := edge_id.left(marker_index + marker.length()) + ":"
	var open_index := edge_index
	var travel_s := 0.0
	while open_index < route.size():
		var candidate_step := route[open_index] as Dictionary
		if str(candidate_step.get("kind", "")) != "controlled":
			break
		var candidate_edge := network.edge(str(candidate_step.get("edge_id", "")))
		if not str(candidate_edge.get("id", "")).begins_with(transition_prefix):
			break
		var speed := maxf(float(candidate_edge.get("speed_limit_ms", 5.2)), 0.5)
		travel_s += float(candidate_edge.get("length_m", 0.0)) / speed
		open_index += 1
	if open_index >= route.size() \
			or str((route[open_index] as Dictionary).get("kind", "")) != "open_water":
		return true
	return _ensure_open_water_allocation(vessel, open_index, travel_s)


func _record_blocker(vessel: Dictionary, reservation: Dictionary) -> void:
	vessel["blocked_by"] = str(reservation.get("blocked_by", ""))
	vessel["blocked_at"] = str(reservation.get("block_id", ""))
	vessel["blocked_reason"] = str(reservation.get("reason", ""))


func _clear_blocker(vessel: Dictionary) -> void:
	vessel["blocked_by"] = ""
	vessel["blocked_at"] = ""
	vessel["blocked_reason"] = ""


func _ensure_open_water_allocation(
		vessel: Dictionary, edge_index: int, travel_to_slot_s := 0.0,
) -> bool:
	var section_id := "%d:%d" % [int(vessel.get("trip_serial", 0)), edge_index]
	if str(vessel.get("open_water_section_id", "")) == section_id:
		var ready := simulated_seconds + maxf(travel_to_slot_s, 0.0) + FIXED_STEP_S \
			>= float(vessel.get("open_water_start_s", simulated_seconds))
		if not ready:
			vessel["state"] = "waiting_open_water_slot"
		return ready
	var route := vessel.get("route_steps", []) as Array
	if edge_index < 0 or edge_index >= route.size():
		return false
	var step := route[edge_index] as Dictionary
	var edge := _step_record(step)
	var points := edge.get("points", PackedVector2Array()) as PackedVector2Array
	var link_id := "%s>%s" % [str(step.get("from_ramp_id", "")),
		str(step.get("to_ramp_id", ""))]
	if simulated_seconds + 0.001 < float(vessel.get("open_water_retry_s", -1.0)):
		return false
	var allocation: Dictionary = _open_water_schedule.request(
		str(vessel.get("id", "")), section_id, points,
		simulated_seconds + maxf(travel_to_slot_s, 0.0),
		maxf(float(edge.get("speed_limit_ms", 7.2)), 0.5),
		float(vessel.get("length_m", 40.0)), link_id)
	if not bool(allocation.get("ok", false)):
		vessel["state"] = "waiting_open_water_slot"
		# A saturated spatial schedule is transient. Retrying its full conflict
		# search twice per second can dominate a large authority, so the record
		# remains parked and probes at an AIS-like interval instead.
		vessel["open_water_retry_s"] = simulated_seconds + REMOTE_AUTHORITY_STEP_S
		return false
	vessel["open_water_retry_s"] = -1.0
	vessel["open_water_section_id"] = section_id
	vessel["open_water_start_s"] = float(allocation.get("start_s", simulated_seconds))
	if simulated_seconds + maxf(travel_to_slot_s, 0.0) + FIXED_STEP_S \
			< float(vessel.get("open_water_start_s", simulated_seconds)):
		vessel["state"] = "waiting_open_water_slot"
		return false
	return true


func _waiting_for_booked_open_slot(vessel: Dictionary) -> bool:
	return not str(vessel.get("open_water_section_id", "")).is_empty() \
		and float(vessel.get("open_water_start_s", -1.0)) > simulated_seconds + FIXED_STEP_S


func _release_open_water_allocation(vessel: Dictionary) -> void:
	var section_id := str(vessel.get("open_water_section_id", ""))
	if not section_id.is_empty() and _open_water_schedule != null:
		_open_water_schedule.release(str(vessel.get("id", "")), section_id)
	vessel["open_water_section_id"] = ""
	vessel["open_water_start_s"] = -1.0
	vessel["open_water_retry_s"] = -1.0

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
	_release_open_merge_authority(vessel)
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
		var is_harbour := edge_kind in ["quay_maneuver", "port_approach", "port_connector",
			"port_merge", "port_feeder", "shipping_ramp"]
		if is_harbour:
			saw_harbour_edge = true
		elif saw_harbour_edge:
			# The local harbour corridor is enough to release the berth safely.
			# Reserving the first motorway block as part of this atomic request can
			# pin a ship at the quay behind an unrelated lane queue. Once clear of
			# the quay it joins ordinary block/passing-lane authority at the ramp.
			break
		elif not result.is_empty():
			break
		for block_id in edge.get("block_ids", PackedStringArray()) as PackedStringArray:
			if not result.has(block_id):
				result.append(block_id)
	return result


func _plan_trip(vessel: Dictionary) -> void:
	_release_open_merge_authority(vessel)
	_release_open_water_allocation(vessel)
	var source := network.berth_tokens.get(str(vessel.get("source_token_id", "")), {}) as Dictionary
	var destination := network.berth_tokens.get(
		str(vessel.get("destination_token_id", "")), {}) as Dictionary
	var vessel_limits := {
		"length_m": vessel.get("length_m", 0.0),
		"beam_m": vessel.get("beam_m", 0.0),
		"draft_m": vessel.get("draft_m", 0.0),
	}
	var cache_key := "%s>%s:%.0f:%.0f:%.0f" % [
		str(vessel.get("source_token_id", "")),
		str(vessel.get("destination_token_id", "")),
		float(vessel_limits.length_m), float(vessel_limits.beam_m),
		float(vessel_limits.draft_m),
	]
	var passage := _planned_passage_cache.get(cache_key, {}) as Dictionary
	if passage.is_empty():
		passage = route_planner.plan(str(source.get("node_id", "")),
			str(destination.get("node_id", "")), vessel_limits)
		_planned_passage_cache[cache_key] = passage
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
	var source_index := pool.find(source_token_id)
	# Two deterministic service cohorts per source exercise both coastal and
	# cross-water passages without creating hundreds of unique startup searches.
	# Each cohort is a cyclic permutation of the port list, so traffic demand is
	# balanced: no debug run sends half its fleet to one unfortunate berth.
	var cohort := posmod(vessel_index / maxi(pool.size(), 1), 2)
	var service_wave := trip_index / 2
	var jump := 1 + posmod(cohort * 3 + service_wave * 5,
		maxi(pool.size() - 1, 1))
	for offset in range(pool.size()):
		var index := posmod(source_index + jump + offset, pool.size())
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
	var ids := _exact_vessel_ids
	var cell_size := COLLISION_DISTANCE_M
	var buckets: Dictionary = {}
	for vessel_id in ids:
		var vessel := vessels[vessel_id] as Dictionary
		if str(vessel.get("state", "")) in ["docked", "route_failed", "scheduled_strategic"]:
			continue
		var point := vessel.get("position", Vector2.ZERO) as Vector2
		var cell := Vector2i(floori(point.x / cell_size), floori(point.y / cell_size))
		var bucket := buckets.get(cell, PackedStringArray()) as PackedStringArray
		bucket.append(vessel_id)
		buckets[cell] = bucket
	for vessel_id in ids:
		var a := vessels[vessel_id] as Dictionary
		if str(a.get("state", "")) in ["docked", "route_failed", "scheduled_strategic"]:
			continue
		var a_point := a.get("position", Vector2.ZERO) as Vector2
		var a_cell := Vector2i(floori(a_point.x / cell_size), floori(a_point.y / cell_size))
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				for other_id in buckets.get(a_cell + Vector2i(dx, dy), PackedStringArray()):
					if other_id <= vessel_id:
						continue
					var b := vessels[other_id] as Dictionary
					if a_point.distance_to(b.get("position", Vector2.ZERO) as Vector2) \
							>= COLLISION_DISTANCE_M:
						continue
					_register_proximity_collision(vessel_id, other_id, a, b)


func _register_proximity_collision(
		a_id: String, b_id: String, a: Dictionary, b: Dictionary,
) -> void:
	var pair_id := "%s|%s" % [a_id, b_id]
	if _collision_pairs.has(pair_id):
		return
	_collision_pairs[pair_id] = true
	_metrics["collisions"] = int(_metrics.get("collisions", 0)) + 1
	_safety_events.append({
		"kind": "proximity_collision",
		"time_s": simulated_seconds,
		"vessel_id": a_id,
		"other_vessel_id": b_id,
		"position": a.get("position", Vector2.ZERO),
		"other_position": b.get("position", Vector2.ZERO),
		"state": str(a.get("state", "")),
		"other_state": str(b.get("state", "")),
		"block_id": str(a.get("current_block_id", "")),
		"other_block_id": str(b.get("current_block_id", "")),
		"route_mode": str(a.get("route_mode", "")),
		"other_route_mode": str(b.get("route_mode", "")),
	})
	_event(a_id, "proximity collision with %s at %s / %s" % [
		b_id, str(a.get("current_block_id", "")),
		str(b.get("current_block_id", ""))])


func _fail_route(vessel: Dictionary, reason: String) -> void:
	if str(vessel.get("state", "")) == "route_failed":
		return
	_release_open_merge_authority(vessel)
	_release_open_water_allocation(vessel)
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
