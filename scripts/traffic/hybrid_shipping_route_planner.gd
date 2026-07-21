class_name HybridShippingRoutePlanner
extends RefCounted
## One deterministic route search across two movement domains. Controlled
## shipping-lane edges are always available. Open-water A* may only begin at an
## explicit leave portal and may only finish at an explicit join portal. Port
## service ramps are deliberately not part of this domain. The search can
## alternate between those domains any number of times.

const OPEN_WATER_SPEED_MS := 6.4
# Leaving a marked route still carries a manoeuvring/scheduling cost, but four
# minutes made even obvious cross-fjord passages lose to enormous motorway
# loops. One minute keeps lanes preferred for comparable journeys while
# allowing a legal OFF-to-ON water transfer to win when it removes real detour.
const OPEN_WATER_TRANSITION_PENALTY_S := 60.0
const MAX_RELEVANT_RAMPS := 32
const ON_RAMP_CANDIDATES_PER_OFF_RAMP := 8
const MIN_OPEN_WATER_LINK_M := 420.0
## Marked lanes are the default maritime route. Free-sailing A* is selected
## only when it removes a material detour. A route that is already reasonably
## direct stays in the marked system; an obviously circuitous motorway route
## gets a lower threshold so the ship can legally leave and rejoin instead of
## sailing to a remote network endpoint merely to reverse direction.
const OPEN_WATER_MIN_SAVING_S := 300.0
const OPEN_WATER_MIN_SAVING_RATIO := 0.18
const CIRCUITOUS_LANE_RATIO := 1.55
const CIRCUITOUS_MIN_SAVING_S := 75.0
const CIRCUITOUS_MIN_SAVING_RATIO := 0.04

var network: ShippingLaneNetwork
var layout: WorldLayout
var navigation: WaterwayNavigation

var _off_ramp_ids_by_node: Dictionary = {} # ramp node id -> PackedStringArray
var _on_ramp_ids := PackedStringArray()
var _water_link_cache: Dictionary = {} # directed ramp pair -> A* link record
var _plan_cache: Dictionary = {} # berth/dimensions -> immutable route result


func configure(value: ShippingLaneNetwork, world_layout: WorldLayout) -> void:
	network = value
	layout = world_layout
	navigation = WaterwayNavigation.new(world_layout) if world_layout != null else null
	_off_ramp_ids_by_node.clear()
	_on_ramp_ids.clear()
	_water_link_cache.clear()
	_plan_cache.clear()
	if network == null:
		return
	for ramp_id in network.sorted_open_water_portal_ids():
		var record := network.open_water_portals[ramp_id] as Dictionary
		if str(record.get("portal_kind", "")) == "join":
			_on_ramp_ids.append(ramp_id)
		else:
			# Open-water movement leaves from an outside access lane. Harbour
			# ramp mouths are deliberately not ocean waypoints.
			var node_id := str(record.get("lane_node_id", ""))
			var ids := _off_ramp_ids_by_node.get(node_id, PackedStringArray()) as PackedStringArray
			ids.append(ramp_id)
			ids.sort()
			_off_ramp_ids_by_node[node_id] = ids
	_on_ramp_ids.sort()


func plan(source_node_id: String, destination_node_id: String,
		vessel: Dictionary = {}) -> Dictionary:
	if network == null or not network.nodes.has(source_node_id) \
			or not network.nodes.has(destination_node_id):
		return {}
	var cache_key := _plan_cache_key(source_node_id, destination_node_id, vessel)
	if _plan_cache.has(cache_key):
		return (_plan_cache[cache_key] as Dictionary).duplicate(true)
	if navigation == null or _off_ramp_ids_by_node.is_empty() or _on_ramp_ids.is_empty():
		var lane_plan := _lane_only_plan(source_node_id, destination_node_id, vessel)
		_plan_cache[cache_key] = lane_plan.duplicate(true)
		return lane_plan
	var source := network.node(source_node_id)
	var destination := network.node(destination_node_id)
	var source_port_id := str(source.get("port_id", ""))
	var destination_port_id := str(destination.get("port_id", ""))
	var source_point := source.get("position", Vector2.ZERO) as Vector2
	var destination_point := destination.get("position", Vector2.ZERO) as Vector2
	var relevant := _relevant_ramps(
		source_point, destination_point, source_port_id, destination_port_id)
	# Straight-line estimates are intentionally cheap, but a promising estimate
	# may cross land when expanded by WaterwayNavigation. Reject only that ramp
	# pair and rerun the graph search; abandoning the entire augmented search made
	# one invalid shortcut suppress every legal A* passage on the map.
	var rejected_water_links: Dictionary = {}
	var candidate: Dictionary = {}
	for unused in range(12):
		candidate = _augmented_plan(source_node_id, destination_node_id, vessel,
			source_port_id, destination_port_id, relevant, rejected_water_links)
		var invalid_link_key := str(candidate.get("invalid_link_key", ""))
		if invalid_link_key.is_empty():
			break
		rejected_water_links[invalid_link_key] = true
		candidate = {}
	var lane_candidate := _lane_only_plan(source_node_id, destination_node_id, vessel)
	var route_choice_reason := "marked_lane_shortest_path"
	var raw_augmented := candidate.duplicate(true)
	var direct_distance := maxf(source_point.distance_to(destination_point), 1.0)
	if not candidate.is_empty() \
			and int(candidate.get("open_water_sections", 0)) > 0 \
			and not lane_candidate.is_empty():
		var lane_seconds := float(lane_candidate.get("estimated_seconds", INF))
		var water_seconds := float(candidate.get("estimated_seconds", INF))
		var lane_detour_ratio := float(lane_candidate.get("distance_m", INF)) \
			/ direct_distance
		var required_saving := maxf(OPEN_WATER_MIN_SAVING_S,
			lane_seconds * OPEN_WATER_MIN_SAVING_RATIO)
		if lane_detour_ratio >= CIRCUITOUS_LANE_RATIO:
			required_saving = maxf(CIRCUITOUS_MIN_SAVING_S,
				lane_seconds * CIRCUITOUS_MIN_SAVING_RATIO)
		if lane_seconds - water_seconds < required_saving:
			candidate = lane_candidate
			route_choice_reason = "marked_lane_preferred"
		else:
			route_choice_reason = "material_network_detour"
	if OS.get_environment("AA_PROFILE_ROUTES") == "1":
		print("ROUTE PROFILE ", source_port_id, ">", destination_port_id,
			" candidate=", str(candidate.get("mode", "none")), "/",
			snappedf(float(candidate.get("estimated_seconds", INF)), 0.1),
			" open=", int(candidate.get("open_water_sections", 0)),
			" lane=", snappedf(float(lane_candidate.get("estimated_seconds", INF)), 0.1))
	# The augmented search includes every controlled edge. The explicit
	# lane-preference threshold above keeps modest detours on the marked route;
	# fall back to the lane candidate if all promising water links failed the
	# geographic validation pass.
	if candidate.is_empty():
		candidate = lane_candidate
		route_choice_reason = "lane_fallback"
	if not candidate.is_empty():
		var lane_seconds := float(lane_candidate.get("estimated_seconds", INF))
		var augmented_seconds := float(raw_augmented.get("estimated_seconds", INF))
		candidate["route_choice_reason"] = route_choice_reason
		candidate["direct_distance_m"] = direct_distance
		candidate["lane_only_distance_m"] = float(lane_candidate.get("distance_m", INF))
		candidate["lane_only_seconds"] = lane_seconds
		candidate["augmented_seconds"] = augmented_seconds
		candidate["open_water_saving_s"] = lane_seconds - augmented_seconds \
			if lane_seconds < INF and augmented_seconds < INF else 0.0
		candidate["open_water_saving_ratio"] = (lane_seconds - augmented_seconds) \
			/ maxf(lane_seconds, 1.0) if lane_seconds < INF and augmented_seconds < INF \
			else 0.0
	_plan_cache[cache_key] = candidate.duplicate(true)
	return candidate


func cached_water_link_count() -> int:
	return _water_link_cache.size()


func cached_plan_count() -> int:
	return _plan_cache.size()


func _augmented_plan(source_node_id: String, destination_node_id: String,
		vessel: Dictionary, source_port_id: String, destination_port_id: String,
		relevant: Dictionary, rejected_water_links: Dictionary = {}) -> Dictionary:
	var frontier: Array[Dictionary] = []
	ShippingLaneNetwork._heap_push(frontier, {"node_id": source_node_id, "cost": 0.0})
	var distance := {source_node_id: 0.0}
	var previous_node: Dictionary = {}
	var previous_step: Dictionary = {}
	while not frontier.is_empty():
		var entry := ShippingLaneNetwork._heap_pop(frontier)
		var current := str(entry.get("node_id", ""))
		var current_cost := float(entry.get("cost", INF))
		if current_cost > float(distance.get(current, INF)) + 0.0001:
			continue
		if current == destination_node_id:
			break
		for edge in network.outgoing_edges(current):
			if not network.edge_supports(edge, vessel):
				continue
			var edge_kind := str(edge.get("kind", ""))
			if edge_kind == "port_feeder":
				var edge_port := _edge_port_id(edge)
				if edge_port not in [source_port_id, destination_port_id]:
					continue
			var next_id := str(edge.get("to_node_id", ""))
			var edge_cost := float(edge.get("length_m", 0.0)) \
				/ maxf(float(edge.get("speed_limit_ms", 7.2)), 0.1) \
				+ float(edge.get("routing_penalty_s", 0.0))
			_relax(frontier, distance, previous_node, previous_step,
				current, next_id, current_cost + edge_cost,
				{"kind": "controlled", "edge_id": str(edge.get("id", ""))})
		for off_ramp_id in _off_ramp_ids_by_node.get(current, PackedStringArray()) \
				as PackedStringArray:
			if not bool(relevant.get(off_ramp_id, false)):
				continue
			for on_ramp_id in _candidate_on_ramps(
					off_ramp_id, destination_port_id, relevant):
				var water_link_key := "%s>%s" % [off_ramp_id, on_ramp_id]
				if rejected_water_links.has(water_link_key):
					continue
				var off_ramp := network.open_water_portals[off_ramp_id] as Dictionary
				var on_ramp := network.open_water_portals[on_ramp_id] as Dictionary
				var next_id := str(on_ramp.get("lane_node_id", ""))
				var off_point := _portal_water_position(off_ramp)
				var on_point := _portal_water_position(on_ramp)
				var length_m := off_point.distance_to(on_point)
				if length_m < MIN_OPEN_WATER_LINK_M:
					continue
				var water_cost := length_m / OPEN_WATER_SPEED_MS \
					+ OPEN_WATER_TRANSITION_PENALTY_S
				_relax(frontier, distance, previous_node, previous_step,
					current, next_id, current_cost + water_cost, {
						"kind": "open_water_estimate",
						"from_portal_id": off_ramp_id,
						"to_portal_id": on_ramp_id,
					})
	if not distance.has(destination_node_id):
		return {}
	var reverse_steps: Array[Dictionary] = []
	var cursor := destination_node_id
	while cursor != source_node_id:
		if not previous_node.has(cursor) or not previous_step.has(cursor):
			return {}
		reverse_steps.append((previous_step[cursor] as Dictionary).duplicate(true))
		cursor = str(previous_node[cursor])
	reverse_steps.reverse()
	var steps: Array[Dictionary] = []
	for raw_step in reverse_steps:
		var step := raw_step as Dictionary
		if str(step.get("kind", "")) != "open_water_estimate":
			steps.append(step)
			continue
		var link := _water_link(str(step.get("from_portal_id", "")),
			str(step.get("to_portal_id", "")))
		if link.is_empty():
			return {"invalid_link_key": "%s>%s" % [
				str(step.get("from_portal_id", "")), str(step.get("to_portal_id", ""))]}
		steps.append(link)
	return _build_result(steps)


func _relax(frontier: Array[Dictionary], distance: Dictionary,
		previous_node: Dictionary, previous_step: Dictionary, from_id: String,
		to_id: String, candidate: float, step: Dictionary) -> void:
	if to_id.is_empty() or candidate >= float(distance.get(to_id, INF)):
		return
	distance[to_id] = candidate
	previous_node[to_id] = from_id
	previous_step[to_id] = step
	ShippingLaneNetwork._heap_push(frontier, {"node_id": to_id, "cost": candidate})


func _lane_only_plan(source_node_id: String, destination_node_id: String,
		vessel: Dictionary) -> Dictionary:
	var edge_ids := network.route_edge_ids(source_node_id, destination_node_id, vessel)
	if edge_ids.is_empty():
		return {}
	var steps: Array[Dictionary] = []
	for edge_id in edge_ids:
		steps.append({"kind": "controlled", "edge_id": edge_id})
	return _build_result(steps)


func _build_result(steps: Array[Dictionary]) -> Dictionary:
	var controlled_count := 0
	var open_count := 0
	var distance_m := 0.0
	var estimated_seconds := 0.0
	var edge_ids := PackedStringArray()
	var transitions: Array[Dictionary] = []
	for step in steps:
		if str(step.get("kind", "")) == "open_water":
			open_count += 1
			var length_m := float(step.get("length_m", 0.0))
			distance_m += length_m
			estimated_seconds += length_m / OPEN_WATER_SPEED_MS \
				+ OPEN_WATER_TRANSITION_PENALTY_S
			transitions.append({
				"from_portal_id": str(step.get("from_portal_id", "")),
				"to_portal_id": str(step.get("to_portal_id", "")),
			})
		else:
			controlled_count += 1
			var edge_id := str(step.get("edge_id", ""))
			var edge := network.edge(edge_id)
			edge_ids.append(edge_id)
			var length_m := float(edge.get("length_m", 0.0))
			distance_m += length_m
			estimated_seconds += length_m \
				/ maxf(float(edge.get("speed_limit_ms", 7.2)), 0.1) \
				+ float(edge.get("routing_penalty_s", 0.0))
	var mode := "all_lane"
	if open_count > 0:
		mode = "hybrid" if controlled_count > 0 else "open_water"
	return {
		"mode": mode,
		"steps": steps,
		"controlled_edge_ids": edge_ids,
		"open_water_sections": open_count,
		"portal_transitions": transitions,
		"estimated_seconds": estimated_seconds,
		"distance_m": distance_m,
	}


func _relevant_ramps(from: Vector2, to: Vector2, source_port_id: String,
		destination_port_id: String) -> Dictionary:
	var ranked: Array[Dictionary] = []
	var direct_distance := maxf(from.distance_to(to), 1.0)
	for ramp_id in network.sorted_open_water_portal_ids():
		var ramp := network.open_water_portals[ramp_id] as Dictionary
		# Portals are a separate authority concept, so service ramps cannot
		# accidentally consume the open-water candidate budget.
		var point := _portal_water_position(ramp)
		var port_id := str(ramp.get("port_id", ""))
		var segment_distance := _point_segment_distance(point, from, to)
		var projection := clampf((point - from).dot(to - from) / direct_distance / direct_distance,
			0.0, 1.0)
		var score := segment_distance + absf(projection - 0.5) * direct_distance * 0.08
		if port_id in [source_port_id, destination_port_id]:
			score -= direct_distance * 2.0
		ranked.append({"id": ramp_id, "score": score})
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if not is_equal_approx(float(a.score), float(b.score)):
			return float(a.score) < float(b.score)
		return str(a.id) < str(b.id))
	var result: Dictionary = {}
	for index in range(mini(MAX_RELEVANT_RAMPS, ranked.size())):
		result[str((ranked[index] as Dictionary).id)] = true
	for ramp_id in network.sorted_open_water_portal_ids():
		var ramp := network.open_water_portals[ramp_id] as Dictionary
		var port_id := str(ramp.get("port_id", ""))
		if port_id in [source_port_id, destination_port_id]:
			result[ramp_id] = true
	return result


func _candidate_on_ramps(off_ramp_id: String, destination_port_id: String,
		relevant: Dictionary) -> PackedStringArray:
	var off_ramp := network.open_water_portals[off_ramp_id] as Dictionary
	var off_point := _portal_water_position(off_ramp)
	var destination_ramps: Array[Dictionary] = []
	for ramp in network.portals_for_port(destination_port_id, "join"):
		destination_ramps.append(ramp)
	var destination_point := off_point
	if not destination_ramps.is_empty():
		destination_point = _portal_water_position(destination_ramps[0] as Dictionary)
	var ranked: Array[Dictionary] = []
	for on_ramp_id in _on_ramp_ids:
		if not bool(relevant.get(on_ramp_id, false)):
			continue
		var on_ramp := network.open_water_portals[on_ramp_id] as Dictionary
		if str(on_ramp.get("port_id", "")) == str(off_ramp.get("port_id", "")):
			continue
		# At the destination, open water joins the transfer ON ramp upstream
		# of the port queue. At an intermediate interchange it may also use the
		# serving ON ramp downstream of the port. This through-traffic merge
		# cannot be clogged by vessels waiting to enter that port.
		var point := _portal_water_position(on_ramp)
		var score := off_point.distance_to(point) + point.distance_to(destination_point) * 0.35
		if str(on_ramp.get("port_id", "")) == destination_port_id:
			score -= 1000000.0
		ranked.append({"id": on_ramp_id, "score": score})
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if not is_equal_approx(float(a.score), float(b.score)):
			return float(a.score) < float(b.score)
		return str(a.id) < str(b.id))
	var result := PackedStringArray()
	for index in range(mini(ON_RAMP_CANDIDATES_PER_OFF_RAMP, ranked.size())):
		result.append(str((ranked[index] as Dictionary).id))
	return result


func _water_link(from_ramp_id: String, to_ramp_id: String) -> Dictionary:
	var key := "%s>%s" % [from_ramp_id, to_ramp_id]
	if _water_link_cache.has(key):
		return (_water_link_cache[key] as Dictionary).duplicate(true)
	var from_record := network.open_water_portals.get(from_ramp_id, {}) as Dictionary
	var to_record := network.open_water_portals.get(to_ramp_id, {}) as Dictionary
	if from_record.is_empty() or to_record.is_empty():
		_water_link_cache[key] = {}
		return {}
	var points := navigation.route_points(
		_portal_water_position(from_record), _portal_water_position(to_record))
	if points.size() < 2:
		if OS.get_environment("AA_PROFILE_ROUTES") == "1":
			print("ROUTE LINK FAILED ", key, " from=", from_record.get("position"),
				" to=", to_record.get("position"), " clearances=",
				layout.sample_signed_distance(_portal_water_position(from_record)), "/",
				layout.sample_signed_distance(_portal_water_position(to_record)))
		_water_link_cache[key] = {}
		return {}
	var link := {
		"kind": "open_water",
		"from_portal_id": from_ramp_id,
		"to_portal_id": to_ramp_id,
		"points": points,
		"length_m": ShippingLaneNetwork._polyline_length(points),
		"speed_limit_ms": OPEN_WATER_SPEED_MS,
	}
	_water_link_cache[key] = link
	return link.duplicate(true)


func _portal_water_position(ramp: Dictionary) -> Vector2:
	if network == null:
		return ramp.get("position", Vector2.ZERO) as Vector2
	var lane_node := network.node(str(ramp.get("lane_node_id", "")))
	return lane_node.get("position", ramp.get("position", Vector2.ZERO)) as Vector2


func _edge_port_id(edge: Dictionary) -> String:
	var from := network.node(str(edge.get("from_node_id", "")))
	var to := network.node(str(edge.get("to_node_id", "")))
	var port_id := str(from.get("port_id", ""))
	if port_id.is_empty():
		port_id = str(to.get("port_id", ""))
	if not port_id.is_empty():
		return port_id
	# Segmented feeder interior nodes are deliberately dumb graph points. Their
	# deterministic edge id still carries the owning ramp or collector identity.
	var edge_id := str(edge.get("id", ""))
	if edge_id.begins_with("ramp:") or edge_id.begins_with("port:"):
		var parts := edge_id.split(":", false)
		if parts.size() >= 2:
			return str(parts[1])
	return ""


static func _point_segment_distance(point: Vector2, a: Vector2, b: Vector2) -> float:
	var delta := b - a
	if delta.length_squared() < 0.0001:
		return point.distance_to(a)
	var ratio := clampf((point - a).dot(delta) / delta.length_squared(), 0.0, 1.0)
	return point.distance_to(a + delta * ratio)


static func _plan_cache_key(source_node_id: String, destination_node_id: String,
		vessel: Dictionary) -> String:
	return "%s>%s:%.1f:%.1f:%.1f" % [source_node_id, destination_node_id,
		float(vessel.get("length_m", 0.0)), float(vessel.get("beam_m", 0.0)),
		float(vessel.get("draft_m", 0.0))]
