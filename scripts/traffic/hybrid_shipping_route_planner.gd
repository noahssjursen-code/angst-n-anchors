class_name HybridShippingRoutePlanner
extends RefCounted

## Plans one deterministic passage across two movement domains:
## signal-controlled lane edges and free-water A* links between legal breakoffs.
## Breakoffs are the only places a vessel may leave or rejoin controlled traffic.

const OPEN_WATER_SPEED_MS := 6.4
const OPEN_WATER_TRANSITION_PENALTY_S := 75.0
const NEARBY_BREAKOFF_LINKS := 3

var network: ShippingLaneNetwork
var layout: WorldLayout
var navigation: WaterwayNavigation

var _breakoff_ids_by_node: Dictionary = {} # lane node -> PackedStringArray
var _water_link_cache: Dictionary = {} # directed breakoff pair -> link record


func configure(value: ShippingLaneNetwork, world_layout: WorldLayout) -> void:
	network = value
	layout = world_layout
	navigation = WaterwayNavigation.new(world_layout) if world_layout != null else null
	_breakoff_ids_by_node.clear()
	_water_link_cache.clear()
	if network == null:
		return
	for breakoff_id in network.sorted_port_breakoff_ids():
		var record := network.port_breakoffs[breakoff_id] as Dictionary
		var node_id := str(record.get("lane_node_id", ""))
		var ids := _breakoff_ids_by_node.get(node_id, PackedStringArray()) as PackedStringArray
		ids.append(breakoff_id)
		ids.sort()
		_breakoff_ids_by_node[node_id] = ids


func plan(source_node_id: String, destination_node_id: String,
		vessel: Dictionary = {}) -> Dictionary:
	if network == null or not network.nodes.has(source_node_id) \
			or not network.nodes.has(destination_node_id):
		return {}
	var best := _lane_only_plan(source_node_id, destination_node_id, vessel)
	if navigation == null:
		return best
	var source_node := network.node(source_node_id)
	var destination_node := network.node(destination_node_id)
	var source_port_id := str(source_node.get("port_id", ""))
	var destination_port_id := str(destination_node.get("port_id", ""))
	var source_physical := str(source_node.get("physical_quay_id", ""))
	var destination_physical := str(destination_node.get("physical_quay_id", ""))
	var source_breakoffs := network.breakoffs_for_port(source_port_id, source_physical)
	var destination_breakoffs := network.breakoffs_for_port(
		destination_port_id, destination_physical)
	if source_breakoffs.is_empty() or destination_breakoffs.is_empty():
		return best

	# Rank cheaply first. Only the best few candidates invoke the water A*.
	var descriptors: Array[Dictionary] = []
	for source_breakoff in source_breakoffs:
		var source_id := str(source_breakoff.get("id", ""))
		var source_lane := str(source_breakoff.get("lane_node_id", ""))
		var depart := _controlled_steps(source_node_id, source_lane, vessel)
		if depart.is_empty():
			continue
		for destination_breakoff in destination_breakoffs:
			var destination_id := str(destination_breakoff.get("id", ""))
			var destination_lane := str(destination_breakoff.get("lane_node_id", ""))
			var arrive := _controlled_steps(destination_lane, destination_node_id, vessel)
			if arrive.is_empty():
				continue
			var source_point := source_breakoff.get("position", Vector2.ZERO) as Vector2
			var destination_point := destination_breakoff.get("position", Vector2.ZERO) as Vector2
			descriptors.append({
				"estimate": _steps_cost(depart) + source_point.distance_to(destination_point) \
					/ OPEN_WATER_SPEED_MS + OPEN_WATER_TRANSITION_PENALTY_S \
					+ _steps_cost(arrive),
				"prefix": depart,
				"water_from": source_id,
				"water_to": destination_id,
				"suffix": arrive,
			})

			var intermediate := _best_intermediate_breakoff(
				source_point, destination_point, source_port_id, destination_port_id)
			if intermediate.is_empty():
				continue
			var intermediate_id := str(intermediate.get("id", ""))
			var intermediate_lane := str(intermediate.get("lane_node_id", ""))
			var intermediate_point := intermediate.get("position", Vector2.ZERO) as Vector2
			var lane_after := _controlled_steps(intermediate_lane, destination_lane, vessel)
			if not lane_after.is_empty():
				var suffix_after := lane_after.duplicate(true)
				suffix_after.append_array(arrive)
				descriptors.append({
					"estimate": _steps_cost(depart) \
						+ source_point.distance_to(intermediate_point) / OPEN_WATER_SPEED_MS \
						+ OPEN_WATER_TRANSITION_PENALTY_S + _steps_cost(suffix_after),
					"prefix": depart,
					"water_from": source_id,
					"water_to": intermediate_id,
					"suffix": suffix_after,
				})
			var lane_before := _controlled_steps(source_lane, intermediate_lane, vessel)
			if not lane_before.is_empty():
				var prefix_before := depart.duplicate(true)
				prefix_before.append_array(lane_before)
				descriptors.append({
					"estimate": _steps_cost(prefix_before) \
						+ intermediate_point.distance_to(destination_point) / OPEN_WATER_SPEED_MS \
						+ OPEN_WATER_TRANSITION_PENALTY_S + _steps_cost(arrive),
					"prefix": prefix_before,
					"water_from": intermediate_id,
					"water_to": destination_id,
					"suffix": arrive,
				})

	descriptors.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if not is_equal_approx(float(a.estimate), float(b.estimate)):
			return float(a.estimate) < float(b.estimate)
		return "%s>%s" % [a.water_from, a.water_to] \
			< "%s>%s" % [b.water_from, b.water_to]
	)
	for index in range(mini(3, descriptors.size())):
		var descriptor := descriptors[index]
		var water := _water_link(str(descriptor.water_from), str(descriptor.water_to))
		if water.is_empty():
			continue
		var steps := (descriptor.prefix as Array).duplicate(true)
		steps.append(water)
		steps.append_array(descriptor.suffix as Array)
		var candidate := _build_result(steps,
			_steps_cost(steps) + OPEN_WATER_TRANSITION_PENALTY_S)
		if best.is_empty() or float(candidate.estimated_seconds) \
				< float(best.get("estimated_seconds", INF)):
			best = candidate
	return best


func cached_water_link_count() -> int:
	return _water_link_cache.size()


func _lane_only_plan(source_node_id: String, destination_node_id: String,
		vessel: Dictionary) -> Dictionary:
	var edge_ids := network.route_edge_ids(source_node_id, destination_node_id, vessel)
	if edge_ids.is_empty():
		return {}
	var steps: Array[Dictionary] = []
	var cost := 0.0
	for edge_id in edge_ids:
		var edge := network.edge(edge_id)
		steps.append({"kind": "controlled", "edge_id": edge_id})
		cost += float(edge.get("length_m", 0.0)) \
			/ maxf(float(edge.get("speed_limit_ms", 7.2)), 0.1)
	return _build_result(steps, cost)


func _controlled_steps(from_node_id: String, to_node_id: String,
		vessel: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for edge_id in network.route_edge_ids(from_node_id, to_node_id, vessel):
		result.append({"kind": "controlled", "edge_id": edge_id})
	return result


func _steps_cost(steps: Array) -> float:
	var result := 0.0
	for value in steps:
		var step := value as Dictionary
		if str(step.get("kind", "")) == "open_water":
			result += float(step.get("length_m", 0.0)) / OPEN_WATER_SPEED_MS
		else:
			var edge := network.edge(str(step.get("edge_id", "")))
			result += float(edge.get("length_m", 0.0)) \
				/ maxf(float(edge.get("speed_limit_ms", 7.2)), 0.1)
			result += float(edge.get("routing_penalty_s", 0.0))
	return result


func _best_intermediate_breakoff(from: Vector2, to: Vector2, source_port_id: String,
		destination_port_id: String) -> Dictionary:
	var midpoint := from.lerp(to, 0.5)
	var best: Dictionary = {}
	var best_score := INF
	for breakoff_id in network.sorted_port_breakoff_ids():
		var record := network.port_breakoffs[breakoff_id] as Dictionary
		var port_id := str(record.get("port_id", ""))
		if port_id in [source_port_id, destination_port_id]:
			continue
		var point := record.get("position", Vector2.ZERO) as Vector2
		var score := point.distance_squared_to(midpoint)
		if score < best_score:
			best_score = score
			best = record
	return best


func _build_result(steps: Array[Dictionary], cost_s: float) -> Dictionary:
	var controlled_count := 0
	var open_count := 0
	var distance_m := 0.0
	var edge_ids := PackedStringArray()
	for step in steps:
		if str(step.get("kind", "")) == "open_water":
			open_count += 1
			distance_m += float(step.get("length_m", 0.0))
		else:
			controlled_count += 1
			var edge_id := str(step.get("edge_id", ""))
			edge_ids.append(edge_id)
			distance_m += float(network.edge(edge_id).get("length_m", 0.0))
	var mode := "all_lane"
	if open_count > 0:
		mode = "hybrid" if controlled_count > 0 else "open_water"
	return {
		"mode": mode,
		"steps": steps,
		"controlled_edge_ids": edge_ids,
		"open_water_sections": open_count,
		"estimated_seconds": cost_s,
		"distance_m": distance_m,
	}


func _water_link(from_breakoff_id: String, to_breakoff_id: String) -> Dictionary:
	var key := "%s>%s" % [from_breakoff_id, to_breakoff_id]
	if _water_link_cache.has(key):
		return _water_link_cache[key] as Dictionary
	var from_record := network.port_breakoffs.get(from_breakoff_id, {}) as Dictionary
	var to_record := network.port_breakoffs.get(to_breakoff_id, {}) as Dictionary
	if from_record.is_empty() or to_record.is_empty():
		_water_link_cache[key] = {}
		return {}
	var points := navigation.route_points(
		from_record.get("position", Vector2.ZERO) as Vector2,
		to_record.get("position", Vector2.ZERO) as Vector2,
	)
	if points.size() < 2:
		_water_link_cache[key] = {}
		return {}
	var link := {
		"kind": "open_water",
		"from_breakoff_id": from_breakoff_id,
		"to_breakoff_id": to_breakoff_id,
		"points": points,
		"length_m": ShippingLaneNetwork._polyline_length(points),
		"speed_limit_ms": OPEN_WATER_SPEED_MS,
	}
	_water_link_cache[key] = link
	return link
