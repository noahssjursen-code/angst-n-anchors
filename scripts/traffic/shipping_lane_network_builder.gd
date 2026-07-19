class_name ShippingLaneNetworkBuilder
extends RefCounted

## Deterministically converts WorldLayout waterways and seeded PortData quays
## into a Factorio-like directed lane/block/signal graph. No vessels are created.

const BLOCK_TARGET_M := 320.0
const CONNECTOR_BLOCK_M := 180.0
const LANE_SEPARATION_M := 34.0
const LANE_HALF_WIDTH_M := 24.0
const SHORE_CLEARANCE_M := 10.0
const PORT_HOLDING_COUNT := 4
const HOLDING_LATERAL_M := 78.0
const HOLDING_LONGITUDINAL_M := 105.0
const QUAY_CRAB_CLEARANCE_M := 48.0
const QUAY_TIP_CLEARANCE_M := 85.0

var _layout: WorldLayout
var _network: ShippingLaneNetwork
var _navigation: WaterwayNavigation
var _corridors: Dictionary = {} # waterway id -> directional node arrays


func build(layout: WorldLayout, ports: Array) -> ShippingLaneNetwork:
	_layout = layout
	_network = ShippingLaneNetwork.new()
	_corridors.clear()
	if layout == null:
		_network.validation_issues.append(_issue("error", "missing_layout", "World layout is missing"))
		return _network
	_network.layout_checksum = layout.layout_checksum
	_navigation = WaterwayNavigation.new(layout)
	_build_waterway_corridors()
	_build_open_ocean_bus()
	_connect_declared_waterways()
	var sorted_ports: Array = ports.duplicate()
	sorted_ports.sort_custom(func(a: Variant, b: Variant) -> bool:
		return str((a as PortData).port_id) < str((b as PortData).port_id))
	for raw in sorted_ports:
		var data := raw as PortData
		if data != null:
			_build_port(data)
	validate(_network, layout)
	_network.rebuild_checksum()
	return _network


func validate(network: ShippingLaneNetwork, layout: WorldLayout) -> Array[Dictionary]:
	if network == null:
		return [_issue("error", "missing_network", "Shipping lane network is missing")]
	var issues: Array[Dictionary] = network.validation_issues.duplicate(true)
	for edge_id in network.sorted_edge_ids():
		var edge := network.edges[edge_id] as Dictionary
		var points := edge.get("points", PackedVector2Array()) as PackedVector2Array
		if points.size() < 2 or float(edge.get("length_m", 0.0)) < 1.0:
			issues.append(_issue("error", "empty_edge", "Lane edge has no usable length", edge_id))
			continue
		if (edge.get("block_ids", PackedStringArray()) as PackedStringArray).is_empty():
			issues.append(_issue("error", "unblocked_edge", "Lane edge has no traffic block", edge_id,
				points[0]))
		var kind := str(edge.get("kind", ""))
		if layout != null and kind not in ["quay_maneuver", "holding_link"]:
			var minimum_clearance := SHORE_CLEARANCE_M if kind in ["main_lane", "regional_lane"] else 1.0
			for point in _sample_polyline(points, 60.0):
				# The western main bus deliberately meets the open-world boundary,
				# where the macro SDF clamps to zero rather than representing land.
				if absf(point.x) >= layout.half_extent_m - 520.0 \
						or absf(point.y) >= layout.half_extent_m - 520.0:
					continue
				var clearance := layout.sample_signed_distance(point)
				if clearance + 0.1 < minimum_clearance:
					issues.append(_issue("warning", "shore_clearance",
						"Lane enters shallow/land clearance (%.1f m)" % clearance, edge_id, point))
					break
	for block_id in network.sorted_block_ids():
		var block := network.blocks[block_id] as Dictionary
		if not network.edges.has(str(block.get("edge_id", ""))):
			issues.append(_issue("error", "orphan_block", "Block references a missing edge", block_id))
	for signal_id in ShippingLaneNetwork._sorted_ids(network.signals):
		var signal_record := network.signals[signal_id] as Dictionary
		var protected := signal_record.get("protected_blocks", PackedStringArray()) as PackedStringArray
		if protected.is_empty():
			issues.append(_issue("error", "empty_signal", "Signal protects no blocks", signal_id))
		for block_id in protected:
			if not network.blocks.has(block_id):
				issues.append(_issue("error", "unknown_signal_block",
					"Signal references an unknown block", signal_id))
	for node_id in network.sorted_node_ids():
		var node := network.nodes[node_id] as Dictionary
		if str(node.get("kind", "")) != "quay":
			continue
		if not network.can_reach_kind(node_id, PackedStringArray(["main_lane", "regional_lane"])):
			issues.append(_issue("error", "unreachable_quay",
				"Quay has no directed route to a shipping lane", node_id,
				node.get("position", Vector2.ZERO) as Vector2))
		var junction_id := str(node.get("junction_node_id", ""))
		if not network.nodes.has(junction_id):
			issues.append(_issue("error", "missing_quay_junction",
				"Quay has no dedicated clear-water junction", node_id,
				node.get("position", Vector2.ZERO) as Vector2))
			continue
		var quay_tip := node.get("quay_tip_position", node.get("position", Vector2.ZERO)) as Vector2
		var junction_record := network.nodes[junction_id] as Dictionary
		var junction_position := junction_record.get("position", quay_tip) as Vector2
		if quay_tip.distance_to(junction_position) < QUAY_TIP_CLEARANCE_M * 0.9:
			issues.append(_issue("error", "short_quay_junction",
				"Quay junction is not far enough beyond the physical quay tip", node_id,
				junction_position))
		var outbound := junction_record.get("outbound_vector", Vector2.ZERO) as Vector2
		var tip_to_junction := (junction_position - quay_tip).normalized()
		if outbound.length_squared() < 0.5 or tip_to_junction.dot(outbound.normalized()) < 0.995:
			issues.append(_issue("error", "misaligned_quay_junction",
				"Quay junction is not straight out from its physical tip", node_id,
				junction_position))
	for port_id_raw in network.port_gate_nodes.keys():
		var port_id := str(port_id_raw)
		var gates := network.port_gate_nodes[port_id_raw] as Array
		if gates.is_empty():
			issues.append(_issue("error", "missing_port_gates",
				"Port has no physical-quay traffic gates", port_id))
		for gate_id_value in gates:
			var gate_id := str(gate_id_value)
			if not network.nodes.has(gate_id):
				issues.append(_issue("error", "unknown_port_gate",
					"Port references an unknown quay gate", gate_id))
		var has_holding := false
		for slot in network.holding_slots.values():
			if str((slot as Dictionary).get("port_id", "")) == port_id:
				has_holding = true
				break
		if not has_holding:
			issues.append(_issue("error", "missing_holding", "Port has no holding slots", port_id))
	network.validation_issues = issues
	return issues


func _build_waterway_corridors() -> void:
	for raw in _layout.waterway_centerlines:
		var waterway := raw as Dictionary
		var waterway_id := str(waterway.get("id", ""))
		var source := waterway.get("points", PackedVector2Array()) as PackedVector2Array
		if waterway_id.is_empty() or source.size() < 2:
			continue
		var centerline := _resample(source, BLOCK_TARGET_M)
		var width := float(waterway.get("width_m", 220.0))
		var kind := "main_lane" if str(waterway.get("kind", "")) == "trunk" else "regional_lane"
		_corridors[waterway_id] = _add_directional_corridor(
			"waterway:%s" % waterway_id, centerline, width, kind, waterway_id)


func _build_open_ocean_bus() -> void:
	var mouths: Array[Vector2] = []
	for raw in _layout.waterway_centerlines:
		var waterway := raw as Dictionary
		if str(waterway.get("kind", "")) != "trunk":
			continue
		var points := waterway.get("points", PackedVector2Array()) as PackedVector2Array
		if not points.is_empty():
			mouths.append(points[0])
	if mouths.size() < 2:
		return
	mouths.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.y < b.y)
	var bus_x := -_layout.half_extent_m + 420.0
	var bus := PackedVector2Array()
	bus.append(Vector2(bus_x, mouths[0].y - 650.0))
	for mouth in mouths:
		bus.append(Vector2(bus_x, mouth.y))
	bus.append(Vector2(bus_x, mouths[-1].y + 650.0))
	_corridors["open_ocean_bus"] = _add_directional_corridor(
		"waterway:open_ocean_bus", _resample(bus, BLOCK_TARGET_M), 900.0,
		"main_lane", "open_ocean_bus")
	for raw in _layout.waterway_centerlines:
		var waterway := raw as Dictionary
		if str(waterway.get("kind", "")) != "trunk":
			continue
		_connect_corridors(
			str(waterway.get("id", "")), "open_ocean_bus",
			(waterway.get("points", PackedVector2Array()) as PackedVector2Array)[0],
			"ocean_merge")


func _connect_declared_waterways() -> void:
	for raw in _layout.waterway_centerlines:
		var waterway := raw as Dictionary
		var child_id := str(waterway.get("id", ""))
		var points := waterway.get("points", PackedVector2Array()) as PackedVector2Array
		if points.is_empty():
			continue
		for parent_raw in waterway.get("connects_to", PackedStringArray()) as PackedStringArray:
			var parent_id := str(parent_raw)
			if parent_id == "open_ocean" or not _corridors.has(parent_id):
				continue
			_connect_corridors(child_id, parent_id, points[0], "waterway_junction")


func _connect_corridors(child_id: String, parent_id: String, near: Vector2, kind: String) -> void:
	if not _corridors.has(child_id) or not _corridors.has(parent_id):
		return
	var child := _corridors[child_id] as Dictionary
	var parent := _corridors[parent_id] as Dictionary
	var child_forward := child.get("forward", PackedStringArray()) as PackedStringArray
	var child_reverse := child.get("reverse", PackedStringArray()) as PackedStringArray
	var parent_forward := parent.get("forward", PackedStringArray()) as PackedStringArray
	var parent_reverse := parent.get("reverse", PackedStringArray()) as PackedStringArray
	if child_forward.is_empty() or child_reverse.is_empty() or parent_forward.is_empty() or parent_reverse.is_empty():
		return
	var parent_forward_id := _nearest_id(parent_forward, near)
	var parent_reverse_id := _nearest_id(parent_reverse, near)
	var junction_id := "junction:%s:%s" % [child_id, parent_id]
	var turn_blocks := PackedStringArray()
	turn_blocks.append(_add_junction_turn(junction_id + ":parent_in_child", parent_forward_id,
		child_forward[0], kind, junction_id))
	turn_blocks.append(_add_junction_turn(junction_id + ":parent_out_child", parent_reverse_id,
		child_forward[0], kind, junction_id))
	turn_blocks.append(_add_junction_turn(junction_id + ":child_parent_in", child_reverse[0],
		parent_forward_id, kind, junction_id))
	turn_blocks.append(_add_junction_turn(junction_id + ":child_parent_out", child_reverse[0],
		parent_reverse_id, kind, junction_id))
	for index in range(turn_blocks.size()):
		for other in range(index + 1, turn_blocks.size()):
			_network.add_block_conflict(turn_blocks[index], turn_blocks[other])


func _add_junction_turn(
		edge_id: String,
		from_id: String,
		to_id: String,
		kind: String,
		exclusive_group: String,
) -> String:
	var block_id := _add_single_edge(edge_id, from_id, to_id, kind, true)
	var block := _network.blocks.get(block_id, {}) as Dictionary
	block["exclusive_group"] = exclusive_group
	_network.blocks[block_id] = block
	_network.add_signal({"id": "signal:%s" % edge_id, "kind": "chain",
		"node_id": from_id, "protected_blocks": PackedStringArray([block_id])})
	return block_id


func _add_directional_corridor(
		prefix: String,
		centerline: PackedVector2Array,
		waterway_width_m: float,
		kind: String,
		waterway_id: String,
) -> Dictionary:
	var forward_points := _offset_path(centerline, 1.0, waterway_width_m)
	var reverse_points := _offset_path(centerline, -1.0, waterway_width_m)
	var forward_ids := PackedStringArray()
	var reverse_ids := PackedStringArray()
	for index in range(centerline.size()):
		var forward_id := "%s:in:%03d" % [prefix, index]
		var reverse_id := "%s:out:%03d" % [prefix, index]
		_network.add_node({"id": forward_id, "kind": kind, "position": forward_points[index],
			"waterway_id": waterway_id, "direction": "inbound"})
		_network.add_node({"id": reverse_id, "kind": kind, "position": reverse_points[index],
			"waterway_id": waterway_id, "direction": "outbound"})
		forward_ids.append(forward_id)
		reverse_ids.append(reverse_id)
	for index in range(centerline.size() - 1):
		var forward_edge := "%s:in:%03d" % [prefix, index]
		var reverse_edge := "%s:out:%03d" % [prefix, index]
		var forward_block := _add_edge_with_block(forward_edge, forward_ids[index], forward_ids[index + 1],
			PackedVector2Array([forward_points[index], forward_points[index + 1]]), kind, false,
			waterway_width_m)
		var reverse_block := _add_edge_with_block(reverse_edge, reverse_ids[index + 1], reverse_ids[index],
			PackedVector2Array([reverse_points[index + 1], reverse_points[index]]), kind, false,
			waterway_width_m)
		# Properly separated two-way waterways allow vessels to pass. Only a
		# genuinely narrow single-track reach shares one exclusive signal block.
		if waterway_width_m < 90.0:
			_network.add_block_conflict(forward_block, reverse_block)
	return {"forward": forward_ids, "reverse": reverse_ids}


func _build_port(data: PortData) -> void:
	var port_id := data.port_id
	var seaward := _rotate(Vector2(0.0, -1.0), data.rotation_y).normalized()
	var berths := _port_berths(data)
	var junction_records: Dictionary = {}
	for berth in berths:
		var berth_id := str(berth.get("id", ""))
		var physical_quay_id := str(berth.get("physical_quay_id", berth_id))
		var berth_position := berth.get("position", Vector2.ZERO) as Vector2
		var water := (berth.get("water", seaward) as Vector2).normalized()
		if water.length_squared() < 0.5:
			water = seaward
		var quay_node := "port:%s:quay:%s" % [port_id, berth_id]
		var clearance_node := "%s:clear" % quay_node
		var junction_node := "port:%s:quay_junction:%s" % [port_id, physical_quay_id]
		var clearance_position := berth_position + water.normalized() * QUAY_CRAB_CLEARANCE_M
		var approach_position := berth.get("approach_position", clearance_position) as Vector2
		var junction_position := berth.get("junction_position", approach_position) as Vector2
		var quay_tip_position := berth.get("quay_tip_position", junction_position) as Vector2
		var quay_outbound := berth.get("quay_outbound", seaward) as Vector2
		if not junction_records.has(physical_quay_id):
			_network.add_node({
				"id": junction_node,
				"kind": "quay_junction",
				"position": junction_position,
				"port_id": port_id,
				"physical_quay_id": physical_quay_id,
				"quay_tip_position": quay_tip_position,
				"outbound_vector": quay_outbound,
				"direction": "port_gate",
			})
			junction_records[physical_quay_id] = {
				"id": junction_node,
				"position": junction_position,
				"outbound_vector": quay_outbound,
				"physical_quay_id": physical_quay_id,
			}
		_network.add_node({"id": quay_node, "kind": "quay", "position": berth_position,
			"port_id": port_id, "berth_id": berth_id, "physical_quay_id": physical_quay_id,
			"junction_node_id": junction_node, "quay_tip_position": quay_tip_position,
			"direction": "station"})
		_network.add_node({"id": clearance_node, "kind": "quay_clearance", "position": clearance_position,
			"port_id": port_id, "berth_id": berth_id, "direction": "maneuver"})
		var maneuver_path := _add_bidirectional_segmented_path(
			"port:%s:%s:maneuver" % [port_id, berth_id], quay_node, clearance_node,
			PackedVector2Array([berth_position, clearance_position]), "quay_maneuver", true)
		var approach_path := _add_bidirectional_segmented_path(
			"port:%s:%s:approach" % [port_id, berth_id], clearance_node, junction_node,
			PackedVector2Array([clearance_position, approach_position, junction_position]),
			"port_approach", true)
		var all_berth_blocks := _path_blocks(maneuver_path)
		all_berth_blocks.append_array(_path_blocks(approach_path))
		_set_block_group(all_berth_blocks, "quay_maneuver:%s:%s" % [port_id, physical_quay_id])
		var departure_blocks := maneuver_path.get("forward", PackedStringArray()) as PackedStringArray
		departure_blocks.append_array(approach_path.get("forward", PackedStringArray()) as PackedStringArray)
		var arrival_blocks := approach_path.get("reverse", PackedStringArray()) as PackedStringArray
		arrival_blocks.append_array(maneuver_path.get("reverse", PackedStringArray()) as PackedStringArray)
		_network.add_signal({
			"id": "signal:%s:depart" % quay_node,
			"kind": "chain",
			"node_id": quay_node,
			"port_id": port_id,
			"protected_blocks": departure_blocks,
		})
		_network.add_signal({
			"id": "signal:%s:arrive" % quay_node,
			"kind": "chain",
			"node_id": junction_node,
			"port_id": port_id,
			"protected_blocks": arrival_blocks,
		})
	var gate_ids: Array[String] = []
	for physical_quay_id in ShippingLaneNetwork._sorted_ids(junction_records):
		gate_ids.append(str((junction_records[physical_quay_id] as Dictionary).get("id", "")))
	_network.port_gate_nodes[port_id] = gate_ids
	_connect_port_gates_to_lane(data, junction_records)
	_build_holding_slots(data, junction_records, seaward)


func _connect_port_gates_to_lane(data: PortData, gates: Dictionary) -> void:
	if gates.is_empty():
		return
	var centroid := Vector2.ZERO
	for gate_value in gates.values():
		centroid += (gate_value as Dictionary).get("position", Vector2.ZERO) as Vector2
	centroid /= float(gates.size())
	var highway_id := _network.nearest_node(centroid,
		PackedStringArray(["main_lane", "regional_lane"]))
	if highway_id.is_empty():
		_network.validation_issues.append(_issue("error", "missing_highway",
			"Port quay junctions cannot find a shipping lane", data.port_id, centroid))
		return
	var highway_record := _network.nodes[highway_id] as Dictionary
	var waterway_id := str(highway_record.get("waterway_id", ""))
	var corridor := _corridors.get(waterway_id, {}) as Dictionary
	var forward_ids := corridor.get("forward", PackedStringArray()) as PackedStringArray
	var reverse_ids := corridor.get("reverse", PackedStringArray()) as PackedStringArray
	if forward_ids.is_empty() or reverse_ids.is_empty():
		forward_ids = PackedStringArray([highway_id])
		reverse_ids = PackedStringArray([highway_id])
	var ordered_gates := _ordered_quay_gates(gates, forward_ids, centroid)
	var base_index := _nearest_index(forward_ids, centroid)
	var available_count := mini(forward_ids.size(), reverse_ids.size())
	var first_index := clampi(
		base_index - ordered_gates.size() / 2,
		0,
		maxi(available_count - ordered_gates.size(), 0),
	)
	for gate_index in range(ordered_gates.size()):
		var gate := ordered_gates[gate_index] as Dictionary
		var gate_id := str(gate.get("id", ""))
		var gate_position := gate.get("position", Vector2.ZERO) as Vector2
		var lane_index := mini(first_index + gate_index, available_count - 1)
		var targets := PackedStringArray([forward_ids[lane_index], reverse_ids[lane_index]])
		for direction_index in range(targets.size()):
			var target_id := targets[direction_index]
			if target_id.is_empty() or targets.find(target_id) < direction_index:
				continue
			var highway_position := (_network.nodes[target_id] as Dictionary).get(
				"position", gate_position) as Vector2
			var points := _safe_connector_points(gate_position, highway_position)
			var prefix := "port:%s:%s:connector:%d" % [
				data.port_id, str(gate.get("physical_quay_id", gate_index)), direction_index,
			]
			var connector_path := _add_bidirectional_segmented_path(
				prefix, gate_id, target_id, points, "port_connector", true, CONNECTOR_BLOCK_M)
			_network.add_signal({"id": "signal:%s:depart" % prefix,
				"kind": "chain", "node_id": gate_id, "port_id": data.port_id,
				"protected_blocks": connector_path.get("forward", PackedStringArray())})
			_network.add_signal({"id": "signal:%s:arrive" % prefix,
				"kind": "chain", "node_id": target_id, "port_id": data.port_id,
				"protected_blocks": connector_path.get("reverse", PackedStringArray())})


func _build_holding_slots(
		data: PortData,
		gates: Dictionary,
		seaward: Vector2,
) -> PackedStringArray:
	var all_blocks := PackedStringArray()
	var ordered_gates: Array = []
	for gate_id in ShippingLaneNetwork._sorted_ids(gates):
		ordered_gates.append(gates[gate_id])
	if ordered_gates.is_empty():
		return all_blocks
	for index in range(PORT_HOLDING_COUNT):
		var gate := ordered_gates[index % ordered_gates.size()] as Dictionary
		var gate_id := str(gate.get("id", ""))
		var gate_position := gate.get("position", Vector2.ZERO) as Vector2
		var outbound := (gate.get("outbound_vector", seaward) as Vector2).normalized()
		var lateral := Vector2(-outbound.y, outbound.x)
		var row := index / ordered_gates.size()
		var side := -1.0 if row % 2 == 0 else 1.0
		var position := gate_position + outbound * (HOLDING_LONGITUDINAL_M * float(row + 1)) \
			+ lateral * HOLDING_LATERAL_M * 0.45 * side
		var node_id := "port:%s:holding:%02d" % [data.port_id, index]
		_network.add_node({"id": node_id, "kind": "holding", "position": position,
			"port_id": data.port_id, "holding_index": index})
		var slot_id := "holding:%s:%02d" % [data.port_id, index]
		_network.add_holding_slot({"id": slot_id, "node_id": node_id,
			"port_id": data.port_id, "position": position, "queue_index": index})
		var path := _add_bidirectional_segmented_path(slot_id, gate_id, node_id,
			PackedVector2Array([gate_position, position]), "holding_link", true)
		all_blocks.append_array(_path_blocks(path))
		_network.add_signal({"id": "signal:%s:enter" % slot_id, "kind": "chain",
			"node_id": gate_id, "port_id": data.port_id,
			"protected_blocks": path.get("forward", PackedStringArray())})
		_network.add_signal({"id": "signal:%s:exit" % slot_id, "kind": "chain",
			"node_id": node_id, "port_id": data.port_id,
			"protected_blocks": path.get("reverse", PackedStringArray())})
	return all_blocks


func _ordered_quay_gates(gates: Dictionary, corridor_ids: PackedStringArray,
		centroid: Vector2) -> Array:
	var ordered: Array = gates.values()
	if corridor_ids.is_empty():
		return ordered
	var base := _nearest_index(corridor_ids, centroid)
	var before_id := corridor_ids[maxi(base - 1, 0)]
	var after_id := corridor_ids[mini(base + 1, corridor_ids.size() - 1)]
	var before := (_network.nodes[before_id] as Dictionary).get("position", centroid) as Vector2
	var after := (_network.nodes[after_id] as Dictionary).get("position", centroid) as Vector2
	var tangent := (after - before).normalized()
	if tangent.length_squared() < 0.5:
		tangent = Vector2(1.0, 0.0)
	ordered.sort_custom(func(a: Variant, b: Variant) -> bool:
		var a_record := a as Dictionary
		var b_record := b as Dictionary
		var a_projection := (a_record.get("position", centroid) as Vector2).dot(tangent)
		var b_projection := (b_record.get("position", centroid) as Vector2).dot(tangent)
		if not is_equal_approx(a_projection, b_projection):
			return a_projection < b_projection
		return str(a_record.get("physical_quay_id", "")) \
			< str(b_record.get("physical_quay_id", ""))
	)
	return ordered


func _nearest_index(ids: PackedStringArray, position: Vector2) -> int:
	var best_index := 0
	var best_distance := INF
	for index in range(ids.size()):
		var point := (_network.nodes[ids[index]] as Dictionary).get(
			"position", position) as Vector2
		var distance := point.distance_squared_to(position)
		if distance < best_distance:
			best_distance = distance
			best_index = index
	return best_index


func _safe_connector_points(from: Vector2, to: Vector2) -> PackedVector2Array:
	var straight := true
	for index in range(1, 12):
		var point := from.lerp(to, float(index) / 12.0)
		if _layout.sample_signed_distance(point) < 2.0:
			straight = false
			break
	if straight:
		return PackedVector2Array([from, to])
	var routed := _navigation.route_points(from, to)
	return routed if routed.size() >= 2 else PackedVector2Array([from, to])


func _set_block_group(block_ids: PackedStringArray, group_id: String) -> void:
	for block_id in block_ids:
		var block := _network.blocks.get(block_id, {}) as Dictionary
		block["exclusive_group"] = group_id
		_network.blocks[block_id] = block


func _port_berths(data: PortData) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if data.layout_graph == null:
		return result
	var plan := data.layout_graph.initial_attributes.get("berth_plan", {}) as Dictionary
	for raw in plan.get("asphalt_stations", []) as Array:
		var station := raw as Dictionary
		var origin := _array_xz(station.get("origin", [0.0, 0.0]))
		var water := _array_xz(station.get("direction", [0.0, -1.0])).normalized()
		var depth := float(station.get("depth_m", 36.0))
		var station_id := str(station.get("id", "asphalt"))
		var berth_local := origin + water * (depth * 0.5 + 10.0)
		var tip_local := origin + water * depth
		var junction_local := tip_local + water * QUAY_TIP_CLEARANCE_M
		result.append({
			"id": station_id,
			"physical_quay_id": station_id,
			"position": _local_to_world(berth_local, data),
			"water": _rotate(water, data.rotation_y),
			"approach_position": _local_to_world(junction_local, data),
			"junction_position": _local_to_world(junction_local, data),
			"quay_tip_position": _local_to_world(tip_local, data),
			"quay_outbound": _rotate(water, data.rotation_y),
		})
	for raw in plan.get("quay_stations", []) as Array:
		var station := raw as Dictionary
		var origin := _array_xz(station.get("origin", [0.0, 0.0]))
		var tip := _array_xz(station.get("tip", [origin.x, origin.y]))
		var seaward := _array_xz(station.get("direction", [0.0, -1.0])).normalized()
		var right := Vector2(seaward.y, -seaward.x)
		var mid := origin.lerp(tip, 0.5)
		var station_id := str(station.get("id", "quay"))
		var width := float(station.get("width_m", 24.0))
		var junction_local := tip + seaward * QUAY_TIP_CLEARANCE_M
		if str(station.get("layout", "single")) == "twin_joined":
			var sides := station.get("sides", []) as Array
			for side_index in range(mini(sides.size(), 2)):
				var side := sides[side_index] as Dictionary
				var sign := float(side.get("berth_side", -1.0 if side_index == 0 else 1.0))
				var water := right * sign
				var face_offset := width * 0.5 + 10.0
				result.append({
					"id": "%s/side_%d" % [station_id, side_index],
					"physical_quay_id": station_id,
					"position": _local_to_world(mid + water * face_offset, data),
					"water": _rotate(water, data.rotation_y),
					"approach_position": _local_to_world(
						tip + water * (face_offset + QUAY_CRAB_CLEARANCE_M), data),
					"junction_position": _local_to_world(junction_local, data),
					"quay_tip_position": _local_to_world(tip, data),
					"quay_outbound": _rotate(seaward, data.rotation_y),
				})
		else:
			var sign := float(station.get("berth_side", 1.0))
			var water := right * sign
			var face_offset := width * 0.5 + 10.0
			result.append({
				"id": station_id,
				"physical_quay_id": station_id,
				"position": _local_to_world(mid + water * face_offset, data),
				"water": _rotate(water, data.rotation_y),
				"approach_position": _local_to_world(
					tip + water * (face_offset + QUAY_CRAB_CLEARANCE_M), data),
				"junction_position": _local_to_world(junction_local, data),
				"quay_tip_position": _local_to_world(tip, data),
				"quay_outbound": _rotate(seaward, data.rotation_y),
			})
	return result


func _add_bidirectional_segmented_path(
		prefix: String,
		from_id: String,
		to_id: String,
		points: PackedVector2Array,
		kind: String,
		chain_region: bool,
	block_target_m: float = CONNECTOR_BLOCK_M,
) -> Dictionary:
	var sampled := _resample(points, block_target_m)
	if sampled.size() < 2:
		return {"forward": PackedStringArray(), "reverse": PackedStringArray()}
	var node_ids := PackedStringArray([from_id])
	for index in range(1, sampled.size() - 1):
		var node_id := "%s:node:%03d" % [prefix, index]
		_network.add_node({"id": node_id, "kind": kind, "position": sampled[index]})
		node_ids.append(node_id)
	node_ids.append(to_id)
	var forward := PackedStringArray()
	var reverse := PackedStringArray()
	for index in range(sampled.size() - 1):
		var forward_block := _add_edge_with_block("%s:fwd:%03d" % [prefix, index],
			node_ids[index], node_ids[index + 1],
			PackedVector2Array([sampled[index], sampled[index + 1]]), kind, chain_region)
		var reverse_block := _add_edge_with_block("%s:rev:%03d" % [prefix, index],
			node_ids[index + 1], node_ids[index],
			PackedVector2Array([sampled[index + 1], sampled[index]]), kind, chain_region)
		_network.add_block_conflict(forward_block, reverse_block)
		forward.append(forward_block)
		# Keep reverse route order usable from `to_id` back to `from_id`.
		reverse.insert(0, reverse_block)
	return {"forward": forward, "reverse": reverse}


static func _path_blocks(path: Dictionary) -> PackedStringArray:
	var result := PackedStringArray()
	result.append_array(path.get("forward", PackedStringArray()) as PackedStringArray)
	result.append_array(path.get("reverse", PackedStringArray()) as PackedStringArray)
	return result


func _add_single_edge(edge_id: String, from_id: String, to_id: String, kind: String,
		chain_region: bool) -> String:
	if not _network.nodes.has(from_id) or not _network.nodes.has(to_id):
		return ""
	var from := (_network.nodes[from_id] as Dictionary).get("position", Vector2.ZERO) as Vector2
	var to := (_network.nodes[to_id] as Dictionary).get("position", Vector2.ZERO) as Vector2
	return _add_edge_with_block(edge_id, from_id, to_id, PackedVector2Array([from, to]),
		kind, chain_region)


func _add_edge_with_block(
		edge_id: String,
		from_id: String,
		to_id: String,
		points: PackedVector2Array,
		kind: String,
		chain_region: bool,
		waterway_width_m: float = 120.0,
) -> String:
	var speed := 4.0 if kind in ["quay_maneuver", "port_approach", "port_merge", "holding_link"] else 7.2
	var close_quarters := kind in ["quay_maneuver", "port_approach", "port_merge", "holding_link", "port_connector"]
	var width := 34.0 if close_quarters else minf(maxf(waterway_width_m * 0.14, 30.0), 34.0)
	_network.add_edge({
		"id": edge_id,
		"from_node_id": from_id,
		"to_node_id": to_id,
		"points": points,
		"kind": kind,
		"lane_width_m": width,
		"speed_limit_ms": speed,
		"max_draft_m": maxf(waterway_width_m * 0.08, 8.0),
		"max_beam_m": maxf(width * 0.82, 14.0),
		"max_length_m": 220.0,
		"chain_region": chain_region,
	})
	var block_id := "block:%s" % edge_id
	_network.add_block({"id": block_id, "edge_id": edge_id,
		"length_m": ShippingLaneNetwork._polyline_length(points), "kind": kind,
		"chain_region": chain_region})
	if not chain_region and kind not in ["holding_link", "waterway_junction", "ocean_merge"]:
		_network.add_signal({"id": "signal:%s" % edge_id, "kind": "regular",
			"node_id": from_id, "protected_blocks": PackedStringArray([block_id])})
	return block_id


func _offset_path(points: PackedVector2Array, side: float, waterway_width_m: float) -> PackedVector2Array:
	var result := PackedVector2Array()
	var desired := minf(LANE_SEPARATION_M * 0.5, waterway_width_m * 0.10)
	for index in range(points.size()):
		var before := points[maxi(index - 1, 0)]
		var after := points[mini(index + 1, points.size() - 1)]
		var tangent := (after - before).normalized()
		if tangent.length_squared() < 0.001:
			tangent = Vector2(1.0, 0.0)
		var normal := Vector2(-tangent.y, tangent.x)
		var available := maxf(_layout.sample_signed_distance(points[index]) - SHORE_CLEARANCE_M, 0.0)
		var offset := minf(desired, available * 0.45)
		result.append(points[index] + normal * offset * side)
	return result


func _nearest_id(ids: PackedStringArray, position: Vector2) -> String:
	var best := ""
	var best_distance := INF
	for node_id in ids:
		var point := (_network.nodes[node_id] as Dictionary).get("position", Vector2.ZERO) as Vector2
		var distance := point.distance_squared_to(position)
		if distance < best_distance:
			best_distance = distance
			best = node_id
	return best


static func _resample(points: PackedVector2Array, target_m: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	if points.is_empty():
		return out
	out.append(points[0])
	for index in range(points.size() - 1):
		var a := points[index]
		var b := points[index + 1]
		var steps := maxi(1, ceili(a.distance_to(b) / maxf(target_m, 1.0)))
		for step in range(1, steps + 1):
			var point := a.lerp(b, float(step) / float(steps))
			if out[-1].distance_squared_to(point) > 1.0:
				out.append(point)
	return out


static func _sample_polyline(points: PackedVector2Array, spacing_m: float) -> PackedVector2Array:
	return _resample(points, spacing_m)


static func _rotate(direction: Vector2, yaw: float) -> Vector2:
	return direction.rotated(-yaw)


static func _local_to_world(local: Vector2, data: PortData) -> Vector2:
	return Vector2(data.world_position.x, data.world_position.z) + _rotate(local, data.rotation_y)


static func _array_xz(raw: Variant) -> Vector2:
	if raw is Vector2:
		return raw as Vector2
	if raw is Vector3:
		return Vector2(raw.x, raw.z)
	if raw is Array and (raw as Array).size() >= 2:
		return Vector2(float(raw[0]), float(raw[1]))
	return Vector2.ZERO


static func _issue(severity: String, code: String, message: String,
		source_id: String = "", position: Vector2 = Vector2(INF, INF)) -> Dictionary:
	return {"severity": severity, "code": code, "message": message,
		"source_id": source_id, "position": position}
