class_name ShippingLaneNetworkBuilder
extends RefCounted

## Deterministically converts WorldLayout waterways and seeded PortData quays
## into a Factorio-like directed lane/block/signal graph. No vessels are created.

const BLOCK_TARGET_M := 320.0
const CONNECTOR_BLOCK_M := 180.0
const QUEUE_BLOCK_TARGET_M := 140.0
const LANE_SEPARATION_M := 34.0
const LANE_HALF_WIDTH_M := 24.0
const SHORE_CLEARANCE_M := 10.0
const PASSING_ZONE_SEGMENTS := 3
const ACCESS_LANE_OFFSET_M := 51.0
const COASTAL_TRUNK_OFFSHORE_M := 620.0
const COASTAL_ROUTE_CLEARANCE_M := 72.0
const PORT_COLLECTOR_CLEARANCE_M := 190.0
const PORT_COLLECTOR_MIN_SPACING_M := 70.0
const QUAY_CRAB_CLEARANCE_M := 48.0
const QUAY_TIP_CLEARANCE_M := 85.0
const RAMP_STATION_OFFSET_BLOCKS := 3
const WATER_TRANSFER_OFFSET_BLOCKS := 6
const RAMP_MIN_PORT_CLEARANCE_M := 420.0
## An interchange mouth is a real manoeuvring point, not merely a graph node.
## Keep the four physical directional mouths far enough apart that a 40 m vessel plus
## its authority envelope cannot occupy an ON and OFF transition at once.
const RAMP_MIN_INTERCHANGE_CLEARANCE_M := 180.0
const RAMP_LATERAL_OFFSET_M := 72.0
const LOCAL_ROUTE_CLEARANCE_M := 4.0
const LOCAL_ROUTE_PADDING_M := 420.0
const LOCAL_ROUTE_MAX_AXIS_CELLS := 72
const LOCAL_ROUTE_MIN_CELL_M := 55.0
const PORT_BASIN_EXIT_STEP_M := 40.0
const PORT_BASIN_EXIT_MAX_M := 800.0
const CROSSING_HASH_CELL_M := 256.0
const CROSSING_CLEARANCE_M := 12.0
const CROSSING_MIN_SINE := 0.12

var _layout: WorldLayout
var _network: ShippingLaneNetwork
var _corridors: Dictionary = {} # waterway id -> directional node arrays
var _fallback_navigation: WaterwayNavigation
var build_profile: Dictionary = {}


func build(layout: WorldLayout, ports: Array) -> ShippingLaneNetwork:
	var build_started := Time.get_ticks_usec()
	build_profile = {"started_usec": build_started, "connector_route_ms": 0.0,
		"connector_conflict_ms": 0.0, "port_ms": {}, "feeder_paths": 0}
	_layout = layout
	_network = ShippingLaneNetwork.new()
	_corridors.clear()
	_fallback_navigation = null
	if layout == null:
		_network.validation_issues.append(_issue("error", "missing_layout", "World layout is missing"))
		return _network
	_network.layout_checksum = layout.layout_checksum
	_build_waterway_corridors()
	build_profile["waterways_ms"] = _elapsed_ms(build_started)
	_profile_checkpoint("waterways")
	_build_coastal_main_bus()
	build_profile["coastal_total_ms"] = _elapsed_ms(build_started)
	_profile_checkpoint("coastal bus")
	_connect_declared_waterways()
	build_profile["junction_total_ms"] = _elapsed_ms(build_started)
	_profile_checkpoint("waterway junctions")
	var sorted_ports: Array = ports.duplicate()
	sorted_ports.sort_custom(func(a: Variant, b: Variant) -> bool:
		return str((a as PortData).port_id) < str((b as PortData).port_id))
	for raw in sorted_ports:
		var data := raw as PortData
		if data != null:
			var port_started := Time.get_ticks_usec()
			_build_port(data)
			(build_profile["port_ms"] as Dictionary)[data.port_id] = _elapsed_ms(port_started)
			_profile_checkpoint("port %s" % data.port_id)
	var crossing_started := Time.get_ticks_usec()
	build_profile["geometric_conflicts"] = _add_geometric_crossing_conflicts()
	build_profile["geometric_conflict_ms"] = _elapsed_ms(crossing_started)
	_profile_checkpoint("geometric interlocks")
	validate(_network, layout)
	_profile_checkpoint("validation")
	_network.rebuild_checksum()
	build_profile["total_ms"] = _elapsed_ms(build_started)
	return _network


func _profile_checkpoint(label: String) -> void:
	if OS.get_environment("AA_PROFILE_LANES") == "1":
		print("LANE BUILD %-24s %8.1f ms" % [label, _elapsed_ms(
			int(build_profile.get("started_usec", Time.get_ticks_usec())))])


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
		if layout != null and kind != "quay_maneuver":
			var minimum_clearance := SHORE_CLEARANCE_M if kind in ["main_lane", "regional_lane"] else 1.0
			for point in _sample_polyline(points, 60.0):
				# Generated trunk centerlines may meet the open-world boundary, where
				# the macro SDF clamps to zero rather than representing land.
				if absf(point.x) >= layout.half_extent_m - 520.0 \
						or absf(point.y) >= layout.half_extent_m - 520.0:
					continue
				var clearance := layout.sample_signed_distance(point)
				# PortLayoutGenerator deliberately cuts a navigable harbour basin into
				# the immutable macro coastline. The macro SDF therefore remains land
				# for the short, authored seaward leg immediately outside a quay. Only
				# that local leg is exempt; the feeder after it must pass ordinary
				# water-clearance validation.
				if kind == "port_feeder" and _inside_constructed_port_basin(
						network, edge_id, point):
					continue
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
		var has_queue := false
		for slot in network.port_queue_slots.values():
			if str((slot as Dictionary).get("port_id", "")) == port_id:
				has_queue = true
				break
		if not has_queue:
			issues.append(_issue("error", "missing_port_queue",
				"Port has no inbound queue blocks", port_id))
	for slot_id in network.sorted_port_queue_slot_ids():
		var slot := network.port_queue_slots[slot_id] as Dictionary
		var block_id := str(slot.get("block_id", ""))
		if not network.blocks.has(block_id):
			issues.append(_issue("error", "unknown_queue_block",
				"Port queue slot references an unknown block", slot_id))
			continue
		var block := network.blocks[block_id] as Dictionary
		if str(block.get("queue_slot_id", "")) != slot_id:
			issues.append(_issue("error", "unmarked_queue_block",
				"Inbound queue block is missing its queue identity", slot_id))
	for token_id in network.sorted_berth_token_ids():
		var token := network.berth_tokens[token_id] as Dictionary
		if not network.nodes.has(str(token.get("node_id", ""))):
			issues.append(_issue("error", "unknown_berth_token_node",
				"Berth token references an unknown quay", token_id))
	for ramp_id in network.sorted_port_ramp_ids():
		var ramp := network.port_ramps[ramp_id] as Dictionary
		var lane_node := network.node(str(ramp.get("lane_node_id", "")))
		var ramp_node := network.node(str(ramp.get("ramp_node_id", "")))
		if str(lane_node.get("kind", "")) not in ["main_lane", "regional_lane"]:
			issues.append(_issue("error", "ramp_off_highway",
				"Ramp must attach to a regional or main shipping lane", ramp_id,
				ramp.get("position", Vector2.ZERO) as Vector2))
		if str(ramp_node.get("kind", "")) != "shipping_ramp":
			issues.append(_issue("error", "invalid_ramp_node",
				"Ramp transition must own a distinct shipping-ramp node", ramp_id,
				ramp.get("position", Vector2.ZERO) as Vector2))
		if str(lane_node.get("lane_role", "")) != "access" \
				or str(ramp.get("lane_role", "")) != "access":
			issues.append(_issue("error", "ramp_on_through_lane",
				"Port ramps must attach only to the outside access/overtaking lane",
				ramp_id, ramp.get("position", Vector2.ZERO) as Vector2))
		for gate_id_value in network.port_gate_nodes.get(str(ramp.get("port_id", "")), []) as Array:
			var gate_node := network.node(str(gate_id_value))
			if not gate_node.is_empty() and (gate_node.get("position", Vector2.ZERO) as Vector2) \
					.distance_to(ramp.get("position", Vector2.ZERO) as Vector2) \
					< RAMP_MIN_PORT_CLEARANCE_M:
				issues.append(_issue("error", "ramp_too_close",
					"On/off ramp is still inside the local quay approach envelope", ramp_id,
					ramp.get("position", Vector2.ZERO) as Vector2))
				break
	for portal_id in network.sorted_open_water_portal_ids():
		var portal := network.open_water_portals[portal_id] as Dictionary
		var lane_node := network.node(str(portal.get("lane_node_id", "")))
		if str(lane_node.get("kind", "")) not in ["main_lane", "regional_lane"]:
			issues.append(_issue("error", "portal_off_highway",
				"Open-water portal must attach to a regional or main shipping lane",
				portal_id, portal.get("position", Vector2.ZERO) as Vector2))
		if str(lane_node.get("lane_role", "")) != "access" \
				or str(portal.get("lane_role", "")) != "access":
			issues.append(_issue("error", "portal_on_through_lane",
				"Open-water portals must attach to the outside access lane",
				portal_id, portal.get("position", Vector2.ZERO) as Vector2))
		for gate_id_value in network.port_gate_nodes.get(
				str(portal.get("port_id", "")), []) as Array:
			var gate_node := network.node(str(gate_id_value))
			if not gate_node.is_empty() and (gate_node.get("position", Vector2.ZERO) as Vector2) \
					.distance_to(portal.get("position", Vector2.ZERO) as Vector2) \
					< RAMP_MIN_PORT_CLEARANCE_M:
				issues.append(_issue("error", "portal_too_close",
					"Open-water portal is inside the local quay approach envelope",
					portal_id, portal.get("position", Vector2.ZERO) as Vector2))
				break
	var ramp_ids := network.sorted_port_ramp_ids()
	for ramp_index in range(ramp_ids.size()):
		var ramp := network.port_ramps[ramp_ids[ramp_index]] as Dictionary
		for other_index in range(ramp_index + 1, ramp_ids.size()):
			var other := network.port_ramps[ramp_ids[other_index]] as Dictionary
			if str(ramp.get("port_id", "")) != str(other.get("port_id", "")):
				continue
			if (ramp.get("position", Vector2.ZERO) as Vector2).distance_to(
					other.get("position", Vector2.ZERO) as Vector2) < 30.0:
				issues.append(_issue("error", "overlapping_ramp_mouths",
					"Directional on/off ramps must occupy distinct physical water",
					"%s / %s" % [ramp_ids[ramp_index], ramp_ids[other_index]],
					ramp.get("position", Vector2.ZERO) as Vector2))
	for zone_id in network.sorted_passing_zone_ids():
		var zone := network.passing_zones[zone_id] as Dictionary
		for key in ["forward_blocks", "reverse_blocks"]:
			for block_id in zone.get(key, PackedStringArray()) as PackedStringArray:
				if not network.blocks.has(block_id):
					issues.append(_issue("error", "unknown_passing_block",
						"Passing zone references an unknown lane block", zone_id))
	# Validation is a public diagnostic API and callers commonly run it again on
	# an already-built network. Keep that idempotent: build-time issues are
	# retained, while the deterministic checks above must not accumulate a second
	# copy on every inspection/profile pass.
	var unique_issues: Array[Dictionary] = []
	var issue_keys: Dictionary = {}
	for issue in issues:
		var position := issue.get("position", Vector2.INF) as Vector2
		var issue_key := "%s|%s|%s|%.2f|%.2f" % [
			str(issue.get("severity", "")), str(issue.get("code", "")),
			str(issue.get("source_id", issue.get("source", ""))), position.x, position.y]
		if issue_keys.has(issue_key):
			continue
		issue_keys[issue_key] = true
		unique_issues.append(issue)
	network.validation_issues = unique_issues
	return unique_issues


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


func _build_coastal_main_bus() -> void:
	# The generated fjord trunks start at the western map boundary. Select the
	# last open-water point before each trunk enters its fjord, then join those
	# gates into the useful north/south mainland route vessels actually need.
	var gates: Array[Dictionary] = []
	for raw in _layout.waterway_centerlines:
		var waterway := raw as Dictionary
		if str(waterway.get("kind", "")) != "trunk":
			continue
		var points := waterway.get("points", PackedVector2Array()) as PackedVector2Array
		if points.size() < 2:
			continue
		# The first generated trunk sample is the empty western world boundary.
		# Region classification changes to FJORD almost immediately, so using the
		# first region transition built the former north/south bus at x=-16 km.
		# A stable two-thirds station is the actual mainland-coast interchange: it
		# is outside the local harbour approaches but well inside the useful world.
		var gate_index := clampi(roundi(float(points.size() - 1) * 0.66), 1,
			points.size() - 2)
		var gate := points[gate_index]
		# Keep the coastal trunk physically outside the fjord route instead of
		# laying both corridor centerlines on top of one another at the merge.
		var coastal_position := gate + Vector2(-COASTAL_TRUNK_OFFSHORE_M, 0.0)
		if _layout.sample_signed_distance(coastal_position) < SHORE_CLEARANCE_M:
			coastal_position = gate + (points[maxi(0, gate_index - 1)] - gate).normalized() \
				* COASTAL_TRUNK_OFFSHORE_M
		gates.append({
			"waterway_id": str(waterway.get("id", "")),
			"position": coastal_position,
			"merge_position": gate,
		})
	if gates.size() < 2:
		return
	gates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return (a.position as Vector2).y < (b.position as Vector2).y)
	var centerline := PackedVector2Array([(gates[0] as Dictionary).position as Vector2])
	for index in range(1, gates.size()):
		var target := (gates[index] as Dictionary).position as Vector2
		var segment := _safe_connector_points(
			centerline[-1], target, COASTAL_ROUTE_CLEARANCE_M)
		if segment.size() < 2:
			segment = PackedVector2Array([centerline[-1], target])
		for point_index in range(1, segment.size()):
			if centerline[-1].distance_squared_to(segment[point_index]) > 1.0:
				centerline.append(segment[point_index])
	centerline = _resample(centerline, BLOCK_TARGET_M)
	_corridors["coastal_main_bus"] = _add_directional_corridor(
		"waterway:coastal_main_bus", centerline, 700.0,
		"main_lane", "coastal_main_bus")
	for gate in gates:
		_connect_corridors(str(gate.waterway_id), "coastal_main_bus",
			gate.merge_position as Vector2, "coastal_merge")


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
	var child_forward_id := _nearest_id(child_forward, near)
	var child_reverse_id := _nearest_id(child_reverse, near)
	var junction_id := "junction:%s:%s" % [child_id, parent_id]
	var turn_blocks := PackedStringArray()
	# A generated corridor may continue on either side of its junction station.
	# Connect both directed carriageways in both domains; assuming the child
	# always lies "after" the merge stranded ports located before that station.
	for parent_pair in [
		{"name": "parent_in", "id": parent_forward_id},
		{"name": "parent_out", "id": parent_reverse_id},
	]:
		for child_pair in [
			{"name": "child_in", "id": child_forward_id},
			{"name": "child_out", "id": child_reverse_id},
		]:
			turn_blocks.append(_add_junction_turn(
				"%s:%s_%s" % [junction_id, parent_pair.name, child_pair.name],
				str(parent_pair.id), str(child_pair.id), kind, junction_id))
	for child_pair in [
		{"name": "child_in", "id": child_forward_id},
		{"name": "child_out", "id": child_reverse_id},
	]:
		for parent_pair in [
			{"name": "parent_in", "id": parent_forward_id},
			{"name": "parent_out", "id": parent_reverse_id},
		]:
			turn_blocks.append(_add_junction_turn(
				"%s:%s_%s" % [junction_id, child_pair.name, parent_pair.name],
				str(child_pair.id), str(parent_pair.id), kind, junction_id))
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
	# Four permanent carriageways. The inner pair is protected through traffic;
	# the outer pair is the continuous access/overtaking pair used by every port
	# ramp. They are graph lanes, not temporary visual bypasses.
	var forward_points := _offset_path_distance(centerline, 1.0,
		LANE_SEPARATION_M * 0.5)
	var reverse_points := _offset_path_distance(centerline, -1.0,
		LANE_SEPARATION_M * 0.5)
	var forward_access_points := _offset_path_distance(centerline, 1.0,
		ACCESS_LANE_OFFSET_M)
	var reverse_access_points := _offset_path_distance(centerline, -1.0,
		ACCESS_LANE_OFFSET_M)
	var forward_ids := PackedStringArray()
	var reverse_ids := PackedStringArray()
	var forward_access_ids := PackedStringArray()
	var reverse_access_ids := PackedStringArray()
	var forward_blocks := PackedStringArray()
	var reverse_blocks := PackedStringArray()
	var forward_access_blocks := PackedStringArray()
	var reverse_access_blocks := PackedStringArray()
	for index in range(centerline.size()):
		var forward_id := "%s:in:%03d" % [prefix, index]
		var reverse_id := "%s:out:%03d" % [prefix, index]
		var forward_access_id := "%s:in_access:%03d" % [prefix, index]
		var reverse_access_id := "%s:out_access:%03d" % [prefix, index]
		_network.add_node({"id": forward_id, "kind": kind, "position": forward_points[index],
			"waterway_id": waterway_id, "direction": "inbound", "lane_role": "through"})
		_network.add_node({"id": reverse_id, "kind": kind, "position": reverse_points[index],
			"waterway_id": waterway_id, "direction": "outbound", "lane_role": "through"})
		_network.add_node({"id": forward_access_id, "kind": kind,
			"position": forward_access_points[index], "waterway_id": waterway_id,
			"direction": "inbound", "lane_role": "access"})
		_network.add_node({"id": reverse_access_id, "kind": kind,
			"position": reverse_access_points[index], "waterway_id": waterway_id,
			"direction": "outbound", "lane_role": "access"})
		forward_ids.append(forward_id)
		reverse_ids.append(reverse_id)
		forward_access_ids.append(forward_access_id)
		reverse_access_ids.append(reverse_access_id)
	for index in range(centerline.size() - 1):
		var forward_edge := "%s:in:%03d" % [prefix, index]
		var reverse_edge := "%s:out:%03d" % [prefix, index]
		var forward_block := _add_edge_with_block(forward_edge, forward_ids[index], forward_ids[index + 1],
			PackedVector2Array([forward_points[index], forward_points[index + 1]]), kind, false,
			waterway_width_m)
		var reverse_block := _add_edge_with_block(reverse_edge, reverse_ids[index + 1], reverse_ids[index],
			PackedVector2Array([reverse_points[index + 1], reverse_points[index]]), kind, false,
			waterway_width_m)
		var forward_access_edge := "%s:in_access:%03d" % [prefix, index]
		var reverse_access_edge := "%s:out_access:%03d" % [prefix, index]
		var forward_access_block := _add_edge_with_block(forward_access_edge,
			forward_access_ids[index], forward_access_ids[index + 1],
			PackedVector2Array([forward_access_points[index], forward_access_points[index + 1]]),
			"passing_lane", false, waterway_width_m)
		var reverse_access_block := _add_edge_with_block(reverse_access_edge,
			reverse_access_ids[index + 1], reverse_access_ids[index],
			PackedVector2Array([reverse_access_points[index + 1], reverse_access_points[index]]),
			"passing_lane", false, waterway_width_m)
		_annotate_lane_edge(forward_edge, "through", "forward", waterway_id, 0.0)
		_annotate_lane_edge(reverse_edge, "through", "reverse", waterway_id, 0.0)
		_annotate_lane_edge(forward_access_edge, "access", "forward", waterway_id, 8.0)
		_annotate_lane_edge(reverse_access_edge, "access", "reverse", waterway_id, 8.0)
		# Properly separated two-way waterways allow vessels to pass. Only a
		# genuinely narrow single-track reach shares one exclusive signal block.
		if waterway_width_m < 90.0:
			_network.add_block_conflict(forward_block, reverse_block)
		forward_blocks.append(forward_block)
		reverse_blocks.append(reverse_block)
		forward_access_blocks.append(forward_access_block)
		reverse_access_blocks.append(reverse_access_block)
	_build_passing_zones(waterway_id, centerline,
		forward_ids, reverse_ids, forward_access_ids, reverse_access_ids,
		forward_blocks, reverse_blocks, forward_access_blocks, reverse_access_blocks)
	return {
		"forward": forward_ids,
		"reverse": reverse_ids,
		"forward_access": forward_access_ids,
		"reverse_access": reverse_access_ids,
		"forward_blocks": forward_blocks,
		"reverse_blocks": reverse_blocks,
		"forward_access_blocks": forward_access_blocks,
		"reverse_access_blocks": reverse_access_blocks,
		"centerline": centerline,
	}


func _build_passing_zones(
		waterway_id: String,
		centerline: PackedVector2Array,
		forward_ids: PackedStringArray,
		reverse_ids: PackedStringArray,
		forward_access_ids: PackedStringArray,
		reverse_access_ids: PackedStringArray,
		forward_blocks: PackedStringArray,
		reverse_blocks: PackedStringArray,
		forward_access_blocks: PackedStringArray,
		reverse_access_blocks: PackedStringArray,
) -> void:
	var segment_count := mini(forward_blocks.size(), reverse_blocks.size())
	var zone_number := 0
	var start := 0
	while start < segment_count:
		var finish := mini(start + PASSING_ZONE_SEGMENTS, segment_count)
		var zone_forward := PackedStringArray()
		var zone_reverse := PackedStringArray()
		for index in range(start, finish):
			zone_forward.append(forward_blocks[index])
			zone_reverse.append(reverse_blocks[index])
		var zone_id := "passing:%s:%02d" % [waterway_id, zone_number]
		for block_id in zone_forward:
			var block := _network.blocks[block_id] as Dictionary
			block["passing_zone_id"] = zone_id
			_network.blocks[block_id] = block
		for block_id in zone_reverse:
			var block := _network.blocks[block_id] as Dictionary
			block["passing_zone_id"] = zone_id
			_network.blocks[block_id] = block
		var zone_forward_access := PackedStringArray()
		var zone_reverse_access := PackedStringArray()
		for index in range(start, finish):
			zone_forward_access.append(forward_access_blocks[index])
			zone_reverse_access.append(reverse_access_blocks[index])
			var forward_access_block := _network.block(forward_access_blocks[index])
			forward_access_block["passing_zone_id"] = zone_id
			forward_access_block["passing_direction"] = "forward"
			_network.blocks[forward_access_blocks[index]] = forward_access_block
			var reverse_access_block := _network.block(reverse_access_blocks[index])
			reverse_access_block["passing_zone_id"] = zone_id
			reverse_access_block["passing_direction"] = "reverse"
			_network.blocks[reverse_access_blocks[index]] = reverse_access_block
		var forward_entry := _add_lane_change(zone_id, "forward", "entry",
			forward_ids[start], forward_access_ids[start])
		var forward_exit := _add_lane_change(zone_id, "forward", "exit",
			forward_access_ids[finish], forward_ids[finish])
		var reverse_entry := _add_lane_change(zone_id, "reverse", "entry",
			reverse_ids[finish], reverse_access_ids[finish])
		var reverse_exit := _add_lane_change(zone_id, "reverse", "exit",
			reverse_access_ids[start], reverse_ids[start])
		var midpoint_index := mini(
			start + PASSING_ZONE_SEGMENTS / 2, centerline.size() - 1)
		_network.add_passing_zone({
			"id": zone_id,
			"waterway_id": waterway_id,
			"position": centerline[midpoint_index],
			"forward_blocks": zone_forward,
			"reverse_blocks": zone_reverse,
			"forward_access_blocks": zone_forward_access,
			"reverse_access_blocks": zone_reverse_access,
			"forward_bypass_edge_ids": _edge_ids_for_blocks(zone_forward_access),
			"reverse_bypass_edge_ids": _edge_ids_for_blocks(zone_reverse_access),
			"forward_entry_edge_id": forward_entry,
			"forward_exit_edge_id": forward_exit,
			"reverse_entry_edge_id": reverse_entry,
			"reverse_exit_edge_id": reverse_exit,
			"activation": "on_demand",
		})
		zone_number += 1
		start = finish


func _add_lane_change(zone_id: String, direction: String, role: String,
		from_id: String, to_id: String) -> String:
	var edge_id := "%s:%s:%s" % [zone_id, direction, role]
	_add_single_edge(edge_id, from_id, to_id, "lane_change", true)
	var edge := _network.edge(edge_id)
	edge["passing_zone_id"] = zone_id
	edge["passing_direction"] = direction
	edge["lane_role"] = "lane_change"
	edge["routing_penalty_s"] = 18.0
	_network.edges[edge_id] = edge
	return edge_id


func _annotate_lane_edge(edge_id: String, lane_role: String, direction: String,
		waterway_id: String, penalty_s: float) -> void:
	var edge := _network.edge(edge_id)
	edge["lane_role"] = lane_role
	edge["direction"] = "inbound" if direction == "forward" else "outbound"
	edge["travel_direction"] = direction
	edge["waterway_id"] = waterway_id
	edge["routing_penalty_s"] = penalty_s
	_network.edges[edge_id] = edge


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
		_network.add_berth_token({
			"id": "berth:%s:%s" % [port_id, berth_id],
			"port_id": port_id,
			"berth_id": berth_id,
			"physical_quay_id": physical_quay_id,
			"node_id": quay_node,
		})
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
	var forward_access_ids := corridor.get("forward_access", PackedStringArray()) as PackedStringArray
	var reverse_access_ids := corridor.get("reverse_access", PackedStringArray()) as PackedStringArray
	if forward_access_ids.is_empty() or reverse_access_ids.is_empty():
		_network.validation_issues.append(_issue("error", "missing_access_lanes",
			"Port cannot attach without continuous outside access lanes", data.port_id, centroid))
		return
	var ordered_gates := _ordered_quay_gates(gates, forward_ids, centroid)
	var available_count := mini(forward_ids.size(), reverse_ids.size())
	if available_count < 2:
		_network.validation_issues.append(_issue("error", "short_highway",
			"Port cannot place directional ramps on a one-node lane", data.port_id, centroid))
		return
	var base_index := clampi(_nearest_index(forward_ids, centroid), 0, available_count - 1)
	var station_indices := {
		"before": clampi(base_index - RAMP_STATION_OFFSET_BLOCKS, 1, available_count - 2),
		"after": clampi(base_index + RAMP_STATION_OFFSET_BLOCKS, 1, available_count - 2),
	}
	# A branch-end harbour may not have six blocks of motorway on both sides of
	# its projection. Resolve each carriageway independently and fall back to two
	# clear, distinct ocean stations on the available side instead of pinning a
	# nominal "before" transfer inside the harbour.
	var transfer_station_indices := {
		0: _water_transfer_station_pair(forward_access_ids, base_index, gates),
		1: _water_transfer_station_pair(reverse_access_ids, base_index, gates),
	}
	var collector := _build_port_collector(data, gates, ordered_gates, forward_ids, centroid)
	var collector_ids := collector.get("collector_node_ids", PackedStringArray()) \
		as PackedStringArray
	if collector_ids.is_empty():
		return
	var local_paths: Array[Dictionary] = []
	var used_ramp_positions := PackedVector2Array()
	var movements: Array[Dictionary] = [
		{"station": "before", "direction_index": 0, "ramp_kind": "off_ramp"},
		{"station": "after", "direction_index": 0, "ramp_kind": "on_ramp"},
		{"station": "after", "direction_index": 1, "ramp_kind": "off_ramp"},
		{"station": "before", "direction_index": 1, "ramp_kind": "on_ramp"},
	]
	for movement in movements:
		var station := str(movement.station)
		var station_index := int(station_indices[station])
		var direction_index := int(movement.direction_index)
		var ramp_kind := str(movement.ramp_kind)
		var direction_name := "forward" if direction_index == 0 else "reverse"
		var lane_ids := forward_access_ids if direction_index == 0 else reverse_access_ids
		var lane_node_id := lane_ids[station_index]
		var lane_position := (_network.node(lane_node_id).get("position", centroid) as Vector2)
		var station_tangent := _lane_tangent(forward_ids, station_index)
		# The harbour has one collector/junction per physical quay. Ramps attach
		# to the appropriate end of that collector spine; they never converge on
		# a synthetic middle throat. This keeps neighbouring quay manoeuvres
		# independent until they intentionally merge at an access lane.
		var entry_node_id := collector_ids[0] if station == "before" \
			else collector_ids[-1]
		var entry_position := (_network.node(entry_node_id).get(
			"position", centroid) as Vector2)
		var portward := (entry_position - lane_position).normalized()
		if portward.length_squared() < 0.5:
			portward = Vector2(-station_tangent.y, station_tangent.x)
		var longitudinal_slot := -48.0 if ramp_kind == "off_ramp" else 48.0
		var ramp_position := lane_position + portward * 86.0 \
			+ station_tangent * longitudinal_slot
		ramp_position = _clear_ramp_position(ramp_position, gates, centroid,
			station_tangent, used_ramp_positions)
		used_ramp_positions.append(ramp_position)
		var ramp_id := "ramp:%s:%s:%s:%s" % [data.port_id, station,
			direction_name, ramp_kind]
		var ramp_node_id := "%s:node" % ramp_id
		_network.add_node({
			"id": ramp_node_id, "kind": "shipping_ramp", "position": ramp_position,
			"port_id": data.port_id, "station": station, "ramp_kind": ramp_kind,
			"direction_index": direction_index, "waterway_id": waterway_id,
			"lane_role": "access",
		})
		var lane_to_ramp := _safe_connector_points(lane_position, ramp_position)
		var transition_points := lane_to_ramp if ramp_kind == "off_ramp" \
			else _reversed_points(lane_to_ramp)
		var transition_blocks := _add_directed_segmented_path(
			"%s:transition" % ramp_id,
			lane_node_id if ramp_kind == "off_ramp" else ramp_node_id,
			ramp_node_id if ramp_kind == "off_ramp" else lane_node_id,
			transition_points, "shipping_ramp", true, QUEUE_BLOCK_TARGET_M)
		var crossing_blocks := _interlock_ramp_crossing(
			data.port_id, transition_blocks, corridor, station_index)
		if ramp_kind == "off_ramp":
			for transition_block_id in transition_blocks:
				var transition_block := _network.block(transition_block_id)
				transition_block["destination_port_entry"] = data.port_id
				_network.blocks[transition_block_id] = transition_block
		var portward_points := _safe_connector_points(ramp_position, entry_position)
		var feeder_points := portward_points if ramp_kind == "off_ramp" \
			else _reversed_points(portward_points)
		var feeder_blocks := _add_directed_segmented_path(
			"%s:feeder" % ramp_id,
			ramp_node_id if ramp_kind == "off_ramp" else entry_node_id,
			entry_node_id if ramp_kind == "off_ramp" else ramp_node_id,
			feeder_points, "port_feeder", true, QUEUE_BLOCK_TARGET_M)
		var feeder_path := {"forward": feeder_blocks, "reverse": PackedStringArray()}
		for existing_path in local_paths:
			_add_connector_cross_conflicts(existing_path, feeder_path)
		local_paths.append(feeder_path)
		build_profile["feeder_paths"] = int(build_profile.get("feeder_paths", 0)) + 1
		var protected := transition_blocks.duplicate()
		protected.append_array(crossing_blocks)
		protected.append_array(feeder_blocks)
		_network.add_signal({
			"id": "signal:%s" % ramp_id,
			"kind": "chain" if not crossing_blocks.is_empty() else "regular",
			"node_id": lane_node_id if ramp_kind == "off_ramp" else entry_node_id,
			"port_id": data.port_id,
			"protected_blocks": protected,
		})
		_network.add_port_ramp({
			"id": ramp_id, "port_id": data.port_id, "station": station,
			"ramp_kind": ramp_kind, "direction_index": direction_index,
			"direction": direction_name, "waterway_id": waterway_id,
			"position": ramp_position, "lane_node_id": lane_node_id,
			"ramp_node_id": ramp_node_id, "lane_role": "access",
			"port_entry_node_id": entry_node_id,
			"transition_edge_ids": _edge_ids_for_blocks(transition_blocks),
			"port_feeder_edge_ids": _edge_ids_for_blocks(feeder_blocks),
			"crossing_block_ids": crossing_blocks,
			"serves_port": true,
		})
	# A service ramp and an open-water portal are different concepts. The
	# former leads portward into the collector; the latter breaks away from (or
	# rejoins) the outside lane without touching the harbour. Supplying the four
	# complementary transfer points gives each travel direction an ON and OFF on
	# both sides of the port, so a ship can leave its quay, merge, then immediately
	# choose a legal A* crossing instead of sailing to the end of the world.
	var water_portals: Array[Dictionary] = [
		{"station": "before", "direction_index": 0, "portal_kind": "join"},
		{"station": "after", "direction_index": 0, "portal_kind": "leave"},
		{"station": "after", "direction_index": 1, "portal_kind": "join"},
		{"station": "before", "direction_index": 1, "portal_kind": "leave"},
	]
	for portal in water_portals:
		var station := str(portal.station)
		var direction_index := int(portal.direction_index)
		var portal_kind := str(portal.portal_kind)
		var direction_name := "forward" if direction_index == 0 else "reverse"
		var lane_ids := forward_access_ids if direction_index == 0 else reverse_access_ids
		var direction_stations := transfer_station_indices[direction_index] as Dictionary
		var lane_node_id := lane_ids[int(direction_stations[station])]
		var lane_position := _network.node(lane_node_id).get("position", centroid) as Vector2
		var portal_id := "portal:%s:%s:%s:%s" % [data.port_id,
			station, direction_name, portal_kind]
		_network.add_open_water_portal({
			"id": portal_id, "port_id": data.port_id, "station": station,
			"portal_kind": portal_kind, "direction_index": direction_index,
			"direction": direction_name, "waterway_id": waterway_id,
			"position": lane_position, "lane_node_id": lane_node_id,
			"lane_role": "access",
		})


func _build_port_collector(data: PortData, gates: Dictionary, ordered_gates: Array,
		corridor_ids: PackedStringArray, centroid: Vector2) -> Dictionary:
	if ordered_gates.is_empty() or corridor_ids.is_empty():
		return {}
	var nearest_index := _nearest_index(corridor_ids, centroid)
	var lane_position := (_network.node(corridor_ids[nearest_index]).get(
		"position", centroid) as Vector2)
	var portward_axis := (lane_position - centroid).normalized()
	if portward_axis.length_squared() < 0.5:
		portward_axis = (ordered_gates[0] as Dictionary).get(
			"outbound_vector", Vector2(0.0, -1.0)) as Vector2
	portward_axis = portward_axis.normalized()
	var tangent := _lane_tangent(corridor_ids, nearest_index)
	var furthest_projection := 0.0
	for gate_value in ordered_gates:
		var gate := gate_value as Dictionary
		furthest_projection = maxf(furthest_projection,
			((gate.get("position", centroid) as Vector2) - centroid).dot(portward_axis))
	var collector_base := centroid + portward_axis * (
		furthest_projection + PORT_COLLECTOR_CLEARANCE_M)
	var collector_ids := PackedStringArray()
	var previous_projection := -INF
	for gate_index in range(ordered_gates.size()):
		var gate := ordered_gates[gate_index] as Dictionary
		var gate_id := str(gate.get("id", ""))
		var projection := ((gate.get("position", centroid) as Vector2) - centroid).dot(tangent)
		if previous_projection > -INF:
			projection = maxf(projection, previous_projection + PORT_COLLECTOR_MIN_SPACING_M)
		previous_projection = projection
		var collector_position := collector_base + tangent * projection
		var collector_id := "port:%s:collector:%02d" % [data.port_id, gate_index]
		_network.add_node({"id": collector_id, "kind": "port_collector",
			"position": collector_position, "port_id": data.port_id,
			"physical_quay_id": str(gate.get("physical_quay_id", "")),
			"direction": "collector"})
		collector_ids.append(collector_id)
		var gate_to_collector := _safe_port_feeder_points(gate, collector_position)
		var branch := _add_bidirectional_segmented_path(
			"port:%s:collector_branch:%02d" % [data.port_id, gate_index],
			gate_id, collector_id, gate_to_collector, "port_feeder", true,
			QUEUE_BLOCK_TARGET_M)
		var arrival := branch.get("reverse", PackedStringArray()) as PackedStringArray
		_register_inbound_queue(data.port_id, gate, 0, collector_id,
			"collector", arrival)
		_network.add_signal({"id": "signal:%s:collector_arrive" % gate_id,
			"kind": "chain", "node_id": collector_id, "port_id": data.port_id,
			"protected_blocks": arrival})
	for index in range(collector_ids.size() - 1):
		var from_id := collector_ids[index]
		var to_id := collector_ids[index + 1]
		var from_position := (_network.node(from_id).get("position", centroid) as Vector2)
		var to_position := (_network.node(to_id).get("position", centroid) as Vector2)
		_add_bidirectional_segmented_path(
			"port:%s:collector_spine:%02d" % [data.port_id, index],
			from_id, to_id, _safe_connector_points(from_position, to_position),
			"port_collector", true, QUEUE_BLOCK_TARGET_M)
	return {"collector_node_ids": collector_ids}


func _interlock_ramp_crossing(port_id: String, transition_blocks: PackedStringArray,
		corridor: Dictionary, station_index: int) -> PackedStringArray:
	var conflict_ids := PackedStringArray()
	var lane_sets: Array[PackedStringArray] = [
		corridor.get("forward_blocks", PackedStringArray()) as PackedStringArray,
		corridor.get("reverse_blocks", PackedStringArray()) as PackedStringArray,
		corridor.get("forward_access_blocks", PackedStringArray()) as PackedStringArray,
		corridor.get("reverse_access_blocks", PackedStringArray()) as PackedStringArray,
	]
	for transition_block_id in transition_blocks:
		var transition_edge := _network.edge(str(_network.block(
			transition_block_id).get("edge_id", "")))
		var transition_points := transition_edge.get("points", PackedVector2Array()) \
			as PackedVector2Array
		if transition_points.size() < 2:
			continue
		for lane_blocks in lane_sets:
			for index in range(maxi(0, station_index - 2),
					mini(lane_blocks.size(), station_index + 2)):
				var lane_block_id := lane_blocks[index]
				var lane_edge := _network.edge(str(_network.block(lane_block_id).get(
					"edge_id", "")))
				var lane_points := lane_edge.get("points", PackedVector2Array()) \
					as PackedVector2Array
				if lane_points.size() < 2 or _segment_clearance(
						transition_points[0], transition_points[-1],
						lane_points[0], lane_points[-1]) > CROSSING_CLEARANCE_M:
					continue
				_network.add_block_conflict(transition_block_id, lane_block_id)
				if not conflict_ids.has(lane_block_id):
					conflict_ids.append(lane_block_id)
		var block := _network.block(transition_block_id)
		if conflict_ids.size() > 1:
			block["crossing_group"] = "port_crossing:%s" % port_id
			block["atomic_crossing"] = true
		_network.blocks[transition_block_id] = block
	conflict_ids.sort()
	return conflict_ids


func _add_connector_cross_conflicts(a_path: Dictionary, b_path: Dictionary) -> void:
	# A quay may connect to both directional highway lanes. Those branches fan
	# through the same manoeuvring water, so geometrically crossing block pairs
	# must be interlocked even though they belong to different paths.
	var a_blocks := _path_blocks(a_path)
	var b_blocks := _path_blocks(b_path)
	for a_block_id in a_blocks:
		var a_block := _network.blocks.get(a_block_id, {}) as Dictionary
		var a_edge := _network.edges.get(str(a_block.get("edge_id", "")), {}) as Dictionary
		var a_points := a_edge.get("points", PackedVector2Array()) as PackedVector2Array
		if a_points.size() < 2:
			continue
		for b_block_id in b_blocks:
			var b_block := _network.blocks.get(b_block_id, {}) as Dictionary
			var b_edge := _network.edges.get(str(b_block.get("edge_id", "")), {}) as Dictionary
			var b_points := b_edge.get("points", PackedVector2Array()) as PackedVector2Array
			if b_points.size() < 2:
				continue
			if _segment_clearance(a_points[0], a_points[-1], b_points[0], b_points[-1]) <= 20.0:
				_network.add_block_conflict(a_block_id, b_block_id)


func _add_geometric_crossing_conflicts() -> int:
	# Connector A* is allowed to choose any clear water. A harbour feeder can
	# therefore cross a trunk, ramp, or another port connector without sharing a
	# graph node. Such a crossing must still behave as one interlocked rail
	# junction. A spatial hash keeps this post-build audit close to linear for a
	# production graph with thousands of blocks.
	var buckets: Dictionary = {}
	var segments: Dictionary = {}
	for block_id in _network.sorted_block_ids():
		var block := _network.block(block_id)
		var edge := _network.edge(str(block.get("edge_id", "")))
		var points := edge.get("points", PackedVector2Array()) as PackedVector2Array
		if points.size() < 2:
			continue
		var start := points[0]
		var finish := points[-1]
		if start.distance_squared_to(finish) < 1.0:
			continue
		segments[block_id] = {"start": start, "finish": finish,
			"edge_id": str(block.get("edge_id", "")),
			"family": _segmented_edge_family(str(block.get("edge_id", ""))),
			"kind": str(block.get("kind", ""))}
		var lower := Vector2(minf(start.x, finish.x), minf(start.y, finish.y)) \
			- Vector2.ONE * CROSSING_CLEARANCE_M
		var upper := Vector2(maxf(start.x, finish.x), maxf(start.y, finish.y)) \
			+ Vector2.ONE * CROSSING_CLEARANCE_M
		var lower_cell := Vector2i(floori(lower.x / CROSSING_HASH_CELL_M),
			floori(lower.y / CROSSING_HASH_CELL_M))
		var upper_cell := Vector2i(floori(upper.x / CROSSING_HASH_CELL_M),
			floori(upper.y / CROSSING_HASH_CELL_M))
		for cell_x in range(lower_cell.x, upper_cell.x + 1):
			for cell_y in range(lower_cell.y, upper_cell.y + 1):
				var cell := Vector2i(cell_x, cell_y)
				var values := buckets.get(cell, PackedStringArray()) as PackedStringArray
				values.append(block_id)
				buckets[cell] = values
	var checked: Dictionary = {}
	var added := 0
	for bucket_value in buckets.values():
		var block_ids := bucket_value as PackedStringArray
		for a_index in range(block_ids.size()):
			var a_id := block_ids[a_index]
			var a := segments.get(a_id, {}) as Dictionary
			var a_start := a.get("start", Vector2.ZERO) as Vector2
			var a_finish := a.get("finish", Vector2.ZERO) as Vector2
			var a_direction := (a_finish - a_start).normalized()
			for b_index in range(a_index + 1, block_ids.size()):
				var b_id := block_ids[b_index]
				if a_id == b_id:
					continue
				var pair_id := "%s|%s" % [a_id, b_id] if a_id < b_id \
					else "%s|%s" % [b_id, a_id]
				if checked.has(pair_id):
					continue
				checked[pair_id] = true
				var b := segments.get(b_id, {}) as Dictionary
				var b_start := b.get("start", Vector2.ZERO) as Vector2
				var b_finish := b.get("finish", Vector2.ZERO) as Vector2
				var a_kind := str(a.get("kind", ""))
				var b_kind := str(b.get("kind", ""))
				var a_is_feeder := a_kind == "port_feeder"
				var b_is_feeder := b_kind == "port_feeder"
				var a_is_trunk := a_kind in ["main_lane", "regional_lane", "passing_lane"]
				var b_is_trunk := b_kind in ["main_lane", "regional_lane", "passing_lane"]
				var a_is_ramp := a_kind == "shipping_ramp"
				var b_is_ramp := b_kind == "shipping_ramp"
				var a_is_interchange := a_is_trunk or a_kind == "shipping_ramp"
				var b_is_interchange := b_is_trunk or b_kind == "shipping_ramp"
				# Existing graph junctions and the local feeder fan own their normal
				# interlocks. This audit also covers a ramp crossing the opposite
				# directional carriageway on its way to its own lane node; sharing a
				# graph endpoint with one lane does not protect that other crossing.
				# Treating every shared connector endpoint as a crossing serializes
				# whole ports and can deadlock an outbound ship behind its own queue.
				if not ((a_is_feeder and b_is_interchange) \
						or (b_is_feeder and a_is_interchange) \
						or (a_is_ramp and b_is_trunk) \
						or (b_is_ramp and a_is_trunk) \
						or (a_is_ramp and b_is_ramp)):
					continue
				if str(a.get("family", "")) == str(b.get("family", "")):
					# Consecutive blocks in one lane are intentionally simultaneous:
					# that is what gives a queue physical capacity. Their shared bend
					# is not an intersection between independent movements.
					continue
				var b_direction := (b_finish - b_start).normalized()
				# Parallel lane pairs are intentionally independent. Only a real
				# crossing or merge angle becomes a shared authority region.
				if absf(a_direction.cross(b_direction)) < CROSSING_MIN_SINE:
					continue
				if _segment_clearance(a_start, a_finish, b_start, b_finish) \
						> CROSSING_CLEARANCE_M:
					continue
				var conflicts := (_network.block(a_id).get(
					"conflicts", PackedStringArray()) as PackedStringArray)
				if not conflicts.has(b_id):
					_network.add_block_conflict(a_id, b_id)
					var feeder := a if a_is_feeder else b
					var crossing_id := b_id if a_is_feeder else a_id
					var crossing_is_trunk := b_is_trunk if a_is_feeder else a_is_trunk
					var feeder_port_id := _port_id_from_feeder_edge(
						str(feeder.get("edge_id", "")))
					if not feeder_port_id.is_empty() and crossing_is_trunk:
						# Destination traffic must not stop on the physical crossing
						# and pin the vessel at the berth. The ON-ramp chain checks this
						# gate before entry; through traffic remains unaffected and may
						# use the downstream merge at this interchange.
						var trunk_block := _network.block(crossing_id)
						trunk_block["destination_port_entry"] = feeder_port_id
						_network.blocks[crossing_id] = trunk_block
					added += 1
	return added


static func _segmented_edge_family(edge_id: String) -> String:
	var separator := edge_id.rfind(":")
	if separator < 0:
		return edge_id
	var suffix := edge_id.substr(separator + 1)
	return edge_id.substr(0, separator) if suffix.is_valid_int() else edge_id


static func _port_id_from_feeder_edge(edge_id: String) -> String:
	var pieces := edge_id.split(":")
	return str(pieces[1]) if pieces.size() >= 3 and pieces[0] == "ramp" else ""


func _edge_ids_for_blocks(block_ids: PackedStringArray) -> PackedStringArray:
	var result := PackedStringArray()
	for block_id in block_ids:
		var block := _network.blocks.get(block_id, {}) as Dictionary
		var edge_id := str(block.get("edge_id", ""))
		if not edge_id.is_empty():
			result.append(edge_id)
	return result


static func _segment_clearance(a0: Vector2, a1: Vector2, b0: Vector2, b1: Vector2) -> float:
	if Geometry2D.segment_intersects_segment(a0, a1, b0, b1) != null:
		return 0.0
	return minf(
		minf(_point_segment_distance(a0, b0, b1), _point_segment_distance(a1, b0, b1)),
		minf(_point_segment_distance(b0, a0, a1), _point_segment_distance(b1, a0, a1)),
	)


static func _point_segment_distance(point: Vector2, a: Vector2, b: Vector2) -> float:
	var delta := b - a
	if delta.length_squared() < 0.0001:
		return point.distance_to(a)
	var t := clampf((point - a).dot(delta) / delta.length_squared(), 0.0, 1.0)
	return point.distance_to(a + delta * t)


func _register_inbound_queue(
		port_id: String,
		gate: Dictionary,
		direction_index: int,
		entry_node_id: String,
		station: String,
		inbound: PackedStringArray,
) -> void:
	var physical_quay_id := str(gate.get("physical_quay_id", ""))
	# Blocks are stored in travel order from the off-ramp toward the quay.
	# Queue index zero is the front position closest to the assigned berth.
	for queue_index in range(inbound.size()):
		var block_id := inbound[inbound.size() - 1 - queue_index]
		var block := _network.blocks.get(block_id, {}) as Dictionary
		var edge := _network.edges.get(str(block.get("edge_id", "")), {}) as Dictionary
		var points := edge.get("points", PackedVector2Array()) as PackedVector2Array
		var position := points[0].lerp(points[-1], 0.5) if points.size() >= 2 else Vector2.ZERO
		var slot_id := "queue:%s:%s:%s:%d:%02d" % [
			port_id, physical_quay_id, station, direction_index, queue_index,
		]
		block["queue_slot_id"] = slot_id
		block["queue_port_id"] = port_id
		block["queue_physical_quay_id"] = physical_quay_id
		block["queue_direction_index"] = direction_index
		block["queue_station"] = station
		block["queue_index"] = queue_index
		_network.blocks[block_id] = block
		_network.add_port_queue_slot({
			"id": slot_id,
			"port_id": port_id,
			"physical_quay_id": physical_quay_id,
			"gate_node_id": str(gate.get("id", "")),
			"entry_node_id": entry_node_id,
			"station": station,
			"direction_index": direction_index,
			"queue_index": queue_index,
			"block_id": block_id,
			"position": position,
		})
		_network.add_signal({
			"id": "signal:%s" % slot_id,
			"kind": "regular",
			"node_id": str(edge.get("from_node_id", "")),
			"port_id": port_id,
			"protected_blocks": PackedStringArray([block_id]),
		})




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


func _water_transfer_station_pair(lane_ids: PackedStringArray, base_index: int,
		gates: Dictionary) -> Dictionary:
	var before := _best_water_transfer_index(lane_ids, base_index, -1, gates, -1)
	var after := _best_water_transfer_index(lane_ids, base_index, 1, gates, before)
	if before == after:
		before = _best_water_transfer_index(lane_ids, base_index, -1, gates, after)
	return {"before": before, "after": after}


func _best_water_transfer_index(lane_ids: PackedStringArray, base_index: int,
		preferred_sign: int, gates: Dictionary, excluded_index: int) -> int:
	var first_index := 1
	var last_index := lane_ids.size() - 2
	if last_index < first_index:
		return clampi(base_index, 0, maxi(lane_ids.size() - 1, 0))
	var target := clampi(base_index + preferred_sign * WATER_TRANSFER_OFFSET_BLOCKS,
		first_index, last_index)
	var preferred: Array[Dictionary] = []
	var fallback: Array[Dictionary] = []
	var best_index := target
	var best_clearance := -INF
	for index in range(first_index, last_index + 1):
		if index == excluded_index:
			continue
		var node_position := _network.node(lane_ids[index]).get(
			"position", Vector2.ZERO) as Vector2
		var clearance := INF
		for gate_value in gates.values():
			var gate_position := (gate_value as Dictionary).get(
				"position", Vector2.ZERO) as Vector2
			clearance = minf(clearance, node_position.distance_to(gate_position))
		if clearance > best_clearance:
			best_clearance = clearance
			best_index = index
		if clearance < RAMP_MIN_PORT_CLEARANCE_M:
			continue
		var candidate := {"index": index, "distance": absi(index - target)}
		var signed_delta := (index - base_index) * preferred_sign
		if signed_delta >= WATER_TRANSFER_OFFSET_BLOCKS:
			preferred.append(candidate)
		else:
			fallback.append(candidate)
	var compare := func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.distance) != int(b.distance):
			return int(a.distance) < int(b.distance)
		return int(a.index) < int(b.index)
	preferred.sort_custom(compare)
	fallback.sort_custom(compare)
	if not preferred.is_empty():
		return int(preferred[0].index)
	if not fallback.is_empty():
		return int(fallback[0].index)
	return best_index


func _lane_tangent(ids: PackedStringArray, index: int) -> Vector2:
	var before_id := ids[maxi(index - 1, 0)]
	var after_id := ids[mini(index + 1, ids.size() - 1)]
	var before := (_network.nodes[before_id] as Dictionary).get("position", Vector2.ZERO) as Vector2
	var after := (_network.nodes[after_id] as Dictionary).get("position", before) as Vector2
	var tangent := (after - before).normalized()
	return tangent if tangent.length_squared() > 0.5 else Vector2(1.0, 0.0)


func _safe_ramp_position(lane_position: Vector2, port_centroid: Vector2,
		tangent: Vector2, direction_index: int, ramp_kind: String,
		serves_port: bool) -> Vector2:
	var away := (lane_position - port_centroid).normalized()
	var normal := Vector2(-tangent.y, tangent.x)
	if away.length_squared() < 0.5:
		away = normal
	# Give the deterministic clearance search distinct starting bearings. The
	# search below enforces the actual vessel-scale separation between mouths.
	var slot_m := -60.0 if direction_index == 0 and ramp_kind == "off_ramp" \
		else 20.0 if direction_index == 0 \
		else 60.0 if ramp_kind == "off_ramp" \
		else -20.0
	var longitudinal := tangent * slot_m
	var side := -1.0 if serves_port else 1.0
	var candidates := PackedVector2Array([
		lane_position + away * RAMP_LATERAL_OFFSET_M * side + longitudinal,
		lane_position + normal * RAMP_LATERAL_OFFSET_M * side + longitudinal,
		lane_position - normal * RAMP_LATERAL_OFFSET_M * side + longitudinal,
	])
	var best := candidates[0]
	var best_clearance := _layout.sample_signed_distance(best)
	for candidate in candidates:
		var clearance := _layout.sample_signed_distance(candidate)
		if clearance > best_clearance:
			best = candidate
			best_clearance = clearance
	return best


func _clear_ramp_position(
		seed: Vector2,
		gates: Dictionary,
		port_centroid: Vector2,
		tangent: Vector2,
		used: PackedVector2Array,
) -> Vector2:
	# The authored quay junction is not the motorway ramp. Push each mouth into
	# clear water until it is outside every local manoeuvre envelope, while also
	# preserving a distinct physical point for all four service ramps. Offshore
	# transfer records stay on their shipping-lane nodes and do not use this path.
	var away := (seed - port_centroid).normalized()
	if away.length_squared() < 0.5:
		away = Vector2(-tangent.y, tangent.x)
	var gate_points := PackedVector2Array()
	for gate_value in gates.values():
		gate_points.append((gate_value as Dictionary).get("position", port_centroid) as Vector2)
	var best := seed
	var best_score := -INF
	for ring in range(18):
		var radial := seed + away * float(ring) * 80.0
		for lateral_index in [0, 1, -1, 2, -2]:
			var candidate := radial + tangent * float(lateral_index) * 55.0
			var water_clearance := _layout.sample_signed_distance(candidate)
			var gate_clearance := INF
			for gate_point in gate_points:
				gate_clearance = minf(gate_clearance, candidate.distance_to(gate_point))
			var ramp_clearance := INF
			for used_point in used:
				ramp_clearance = minf(ramp_clearance, candidate.distance_to(used_point))
			var score := minf(water_clearance - LOCAL_ROUTE_CLEARANCE_M,
				gate_clearance - RAMP_MIN_PORT_CLEARANCE_M)
			if not used.is_empty():
				score = minf(score, ramp_clearance - RAMP_MIN_INTERCHANGE_CLEARANCE_M)
			if score > best_score:
				best_score = score
				best = candidate
			if water_clearance >= LOCAL_ROUTE_CLEARANCE_M \
					and gate_clearance >= RAMP_MIN_PORT_CLEARANCE_M \
					and (used.is_empty() \
						or ramp_clearance >= RAMP_MIN_INTERCHANGE_CLEARANCE_M):
				return candidate
	# A fjord wall can sit directly along the simple seaward ray. Search a
	# deterministic fan around the same port/lane bearing before conceding; this
	# keeps compact or end-of-corridor harbours from placing ramps on terrain.
	var base_radius := maxf(seed.distance_to(port_centroid), RAMP_MIN_PORT_CLEARANCE_M)
	var angle_steps := PackedInt32Array([0, 1, -1, 2, -2, 3, -3, 4, -4,
		5, -5, 6, -6, 8, -8, 10, -10, 12, -12])
	for ring in range(32):
		var radius := base_radius + float(ring) * 80.0
		for angle_step in angle_steps:
			var direction := away.rotated(float(angle_step) * PI / 24.0)
			var candidate := port_centroid + direction * radius
			var water_clearance := _layout.sample_signed_distance(candidate)
			var gate_clearance := INF
			for gate_point in gate_points:
				gate_clearance = minf(gate_clearance, candidate.distance_to(gate_point))
			var ramp_clearance := INF
			for used_point in used:
				ramp_clearance = minf(ramp_clearance, candidate.distance_to(used_point))
			var score := minf(water_clearance - LOCAL_ROUTE_CLEARANCE_M,
				gate_clearance - RAMP_MIN_PORT_CLEARANCE_M)
			if not used.is_empty():
				score = minf(score, ramp_clearance - RAMP_MIN_INTERCHANGE_CLEARANCE_M)
			if score > best_score:
				best_score = score
				best = candidate
			if water_clearance >= LOCAL_ROUTE_CLEARANCE_M \
					and gate_clearance >= RAMP_MIN_PORT_CLEARANCE_M \
					and (used.is_empty() \
						or ramp_clearance >= RAMP_MIN_INTERCHANGE_CLEARANCE_M):
				return candidate
	return best


func _safe_connector_points(from: Vector2, to: Vector2,
		clearance_m := LOCAL_ROUTE_CLEARANCE_M) -> PackedVector2Array:
	if _connector_has_water_line(from, to, clearance_m):
		return PackedVector2Array([from, to])
	for padding_m in [LOCAL_ROUTE_PADDING_M, 1200.0, 2800.0, 5600.0]:
		var routed := _bounded_water_route(from, to, padding_m, clearance_m)
		routed = _repair_connector_waypoints(routed, clearance_m)
		if routed.size() >= 2 and _connector_route_is_clear(routed, clearance_m):
			return routed
	# Difficult concave fjords can require leaving every reasonable endpoint
	# bounding box. Pay for the shared whole-world raster only on that rare path;
	# the ordinary per-port build remains bounded and fast.
	if _fallback_navigation == null:
		_fallback_navigation = WaterwayNavigation.new(_layout)
	var global_route := _fallback_navigation.route_points(from, to)
	global_route = _repair_connector_waypoints(global_route, clearance_m)
	if global_route.size() >= 2 and _connector_route_is_clear(global_route, clearance_m):
		return global_route
	# Keep the graph connected for diagnostics, but validation will report this
	# explicit last resort. Normal seeded ports must succeed in one of the
	# bounded searches above rather than silently drawing a chord through land.
	return PackedVector2Array([from, to])


func _safe_port_feeder_points(gate: Dictionary, ramp_position: Vector2) -> PackedVector2Array:
	var gate_position := gate.get("position", Vector2.ZERO) as Vector2
	var outward := gate.get("outbound_vector", Vector2.ZERO) as Vector2
	if outward.length_squared() < 0.5:
		outward = (ramp_position - gate_position).normalized()
	else:
		outward = outward.normalized()
	var basin_exit := gate_position
	var best_clearance := _layout.sample_signed_distance(gate_position)
	for distance_m in range(int(PORT_BASIN_EXIT_STEP_M),
			int(PORT_BASIN_EXIT_MAX_M + PORT_BASIN_EXIT_STEP_M),
			int(PORT_BASIN_EXIT_STEP_M)):
		var candidate := gate_position + outward * float(distance_m)
		var clearance := _layout.sample_signed_distance(candidate)
		if clearance > best_clearance:
			best_clearance = clearance
			basin_exit = candidate
		# Require a second clear probe so a thin zero crossing is not mistaken
		# for the actual mouth of the generated harbour basin.
		if clearance >= LOCAL_ROUTE_CLEARANCE_M and _layout.sample_signed_distance(
				candidate + outward * PORT_BASIN_EXIT_STEP_M) >= LOCAL_ROUTE_CLEARANCE_M:
			basin_exit = candidate
			break
	var ocean_leg := _safe_connector_points(basin_exit, ramp_position)
	var result := PackedVector2Array([gate_position])
	if result[-1].distance_squared_to(basin_exit) > 1.0:
		result.append(basin_exit)
	for index in range(1, ocean_leg.size()):
		if result[-1].distance_squared_to(ocean_leg[index]) > 1.0:
			result.append(ocean_leg[index])
	return result


func _inside_constructed_port_basin(network: ShippingLaneNetwork, edge_id: String,
		point: Vector2) -> bool:
	var pieces := edge_id.split(":")
	if pieces.size() < 2 or pieces[0] not in ["port", "ramp"]:
		return false
	var port_id := str(pieces[1])
	for gate_id_value in network.port_gate_nodes.get(port_id, []) as Array:
		var gate := network.node(str(gate_id_value))
		if gate.is_empty():
			continue
		var gate_position := gate.get("position", point) as Vector2
		var outward := gate.get("outbound_vector", Vector2.ZERO) as Vector2
		if outward.length_squared() < 0.5:
			continue
		var delta := point - gate_position
		var forward_m := delta.dot(outward.normalized())
		var lateral_m := absf(delta.cross(outward.normalized()))
		if forward_m >= -30.0 and forward_m <= PORT_BASIN_EXIT_MAX_M \
				and lateral_m <= 55.0:
			return true
	return false


static func _reversed_points(points: PackedVector2Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for index in range(points.size() - 1, -1, -1):
		result.append(points[index])
	return result


## Port feeders and the coastal bus only need to solve the water immediately
## surrounding their two endpoints. Running the 257x257 whole-world sea grid
## once per quay made deterministic network construction scale with the number
## of berths. This bounded grid has a fixed maximum axis size, so adding ports
## cannot turn graph construction into minutes of global A* work.
func _bounded_water_route(from: Vector2, to: Vector2, padding_m: float,
		clearance_m := LOCAL_ROUTE_CLEARANCE_M) -> PackedVector2Array:
	var lower := Vector2(minf(from.x, to.x), minf(from.y, to.y)) \
		- Vector2.ONE * padding_m
	var upper := Vector2(maxf(from.x, to.x), maxf(from.y, to.y)) \
		+ Vector2.ONE * padding_m
	var extent := upper - lower
	var cell_m := maxf(LOCAL_ROUTE_MIN_CELL_M,
		maxf(extent.x, extent.y) / float(LOCAL_ROUTE_MAX_AXIS_CELLS - 1))
	var columns := maxi(3, ceili(extent.x / cell_m) + 1)
	var rows := maxi(3, ceili(extent.y / cell_m) + 1)
	var grid := AStarGrid2D.new()
	grid.region = Rect2i(0, 0, columns, rows)
	grid.cell_size = Vector2.ONE
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.update()
	for row in range(rows):
		for column in range(columns):
			var sample := lower + Vector2(float(column), float(row)) * cell_m
			if _layout.sample_signed_distance(sample) < clearance_m:
				grid.set_point_solid(Vector2i(column, row), true)
	var from_guess := Vector2i(
		clampi(roundi((from.x - lower.x) / cell_m), 0, columns - 1),
		clampi(roundi((from.y - lower.y) / cell_m), 0, rows - 1))
	var to_guess := Vector2i(
		clampi(roundi((to.x - lower.x) / cell_m), 0, columns - 1),
		clampi(roundi((to.y - lower.y) / cell_m), 0, rows - 1))
	var start_id := _nearest_open_local_grid_id(grid, from_guess, columns, rows)
	var finish_id := _nearest_open_local_grid_id(grid, to_guess, columns, rows)
	if start_id.x < 0 or finish_id.x < 0:
		return PackedVector2Array()
	var ids: Array[Vector2i] = grid.get_id_path(start_id, finish_id)
	if ids.is_empty():
		return PackedVector2Array()
	var raw := PackedVector2Array([from])
	for id in ids:
		var point := lower + Vector2(float(id.x), float(id.y)) * cell_m
		if raw[-1].distance_squared_to(point) > 1.0:
			raw.append(point)
	if raw[-1].distance_squared_to(to) > 1.0:
		raw.append(to)
	return _smooth_connector_route(raw, clearance_m)


func _nearest_open_local_grid_id(grid: AStarGrid2D, origin: Vector2i,
		columns: int, rows: int) -> Vector2i:
	if not grid.is_point_solid(origin):
		return origin
	var maximum_radius := maxi(columns, rows)
	for radius in range(1, maximum_radius):
		for y in range(maxi(0, origin.y - radius), mini(rows, origin.y + radius + 1)):
			for x in range(maxi(0, origin.x - radius), mini(columns, origin.x + radius + 1)):
				if abs(x - origin.x) != radius and abs(y - origin.y) != radius:
					continue
				var candidate := Vector2i(x, y)
				if not grid.is_point_solid(candidate):
					return candidate
	return Vector2i(-1, -1)


func _smooth_connector_route(route: PackedVector2Array,
		clearance_m := LOCAL_ROUTE_CLEARANCE_M) -> PackedVector2Array:
	if route.size() <= 2:
		return route
	var result := PackedVector2Array([route[0]])
	var current := 0
	while current < route.size() - 1:
		var furthest := -1
		for candidate in range(route.size() - 1, current, -1):
			if _connector_has_water_line(route[current], route[candidate], clearance_m):
				furthest = candidate
				break
		# AStarGrid2D validates cell centres. A coarse cell can still straddle a
		# narrow headland, especially where the endpoint connects to its nearest
		# open cell. Never preserve that unsafe adjacent hop just to keep a route.
		if furthest < 0:
			return PackedVector2Array()
		result.append(route[furthest])
		current = furthest
	return result


func _connector_route_is_clear(route: PackedVector2Array,
		clearance_m := LOCAL_ROUTE_CLEARANCE_M) -> bool:
	for index in range(1, route.size() - 1):
		if _layout.sample_signed_distance(route[index]) < clearance_m:
			return false
	for index in range(route.size() - 1):
		if not _connector_has_water_line(route[index], route[index + 1], clearance_m):
			return false
	return true


func _repair_connector_waypoints(route: PackedVector2Array,
		clearance_m := LOCAL_ROUTE_CLEARANCE_M) -> PackedVector2Array:
	if route.size() < 3:
		return route
	var result := route.duplicate()
	for index in range(1, result.size() - 1):
		if _layout.sample_signed_distance(result[index]) >= clearance_m:
			continue
		var original := result[index]
		var replacement := Vector2.INF
		for radius_m in range(20, 241, 20):
			for angle_index in range(16):
				var candidate := original + Vector2.RIGHT.rotated(
					float(angle_index) * TAU / 16.0) * float(radius_m)
				if _layout.sample_signed_distance(candidate) < clearance_m:
					continue
				if _connector_has_water_line(result[index - 1], candidate, clearance_m) \
						and _connector_has_water_line(candidate, result[index + 1], clearance_m):
					replacement = candidate
					break
			if replacement != Vector2.INF:
				break
		if replacement != Vector2.INF:
			result[index] = replacement
	# Resampling changes the probe phase: a 140 m edge can graze a very small
	# cape even when the original long segment's 45 m probes were clear. Repair
	# only these short generated edges with a dense test, keeping global routing
	# fast while making the final graph itself the validated geometry.
	for _repair_index in range(16):
		var changed := false
		for segment_index in range(result.size() - 1):
			var unsafe := _first_dense_unsafe_point(
				result[segment_index], result[segment_index + 1], clearance_m)
			if unsafe == Vector2.INF:
				continue
			var delta := result[segment_index + 1] - result[segment_index]
			var normal := Vector2(-delta.y, delta.x).normalized()
			var detour := Vector2.INF
			for radius_m in range(10, 211, 10):
				for side in [1.0, -1.0]:
					var candidate: Vector2 = unsafe + normal * float(side) * float(radius_m)
					if _layout.sample_signed_distance(candidate) < clearance_m:
						continue
					if _first_dense_unsafe_point(result[segment_index], candidate,
							clearance_m) == Vector2.INF \
							and _first_dense_unsafe_point(candidate,
								result[segment_index + 1], clearance_m) == Vector2.INF:
						detour = candidate
						break
				if detour != Vector2.INF:
					break
			if detour == Vector2.INF:
				return result
			result.insert(segment_index + 1, detour)
			changed = true
			break
		if not changed:
			break
	return result


func _first_dense_unsafe_point(a: Vector2, b: Vector2,
		clearance_m := 1.0) -> Vector2:
	var probes := maxi(2, ceili(a.distance_to(b) / 4.0))
	for index in range(probes + 1):
		var point := a.lerp(b, float(index) / float(probes))
		if _layout.sample_signed_distance(point) < clearance_m:
			return point
	return Vector2.INF


func _connector_has_water_line(a: Vector2, b: Vector2,
		clearance_m := LOCAL_ROUTE_CLEARANCE_M) -> bool:
	var probes := maxi(2, ceili(a.distance_to(b) / 45.0))
	for index in range(probes + 1):
		var point := a.lerp(b, float(index) / float(probes))
		if _layout.sample_signed_distance(point) < clearance_m:
			return false
	return true


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
		var station_id := str(station.get("id", "asphalt"))
		## Asphalt station origins are waterfront edges; their physical pads
		## extend inland and must not push traffic anchors through the apron.
		var berth_local := origin + water * 10.0
		var tip_local := origin
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


func _add_directed_segmented_path(
		prefix: String,
		from_id: String,
		to_id: String,
		points: PackedVector2Array,
		kind: String,
		chain_region: bool,
		block_target_m: float = CONNECTOR_BLOCK_M,
) -> PackedStringArray:
	var sampled := _resample(points, block_target_m)
	var blocks_out := PackedStringArray()
	if sampled.size() < 2:
		return blocks_out
	var node_ids := PackedStringArray([from_id])
	for index in range(1, sampled.size() - 1):
		var node_id := "%s:node:%03d" % [prefix, index]
		_network.add_node({"id": node_id, "kind": kind, "position": sampled[index]})
		node_ids.append(node_id)
	node_ids.append(to_id)
	for index in range(sampled.size() - 1):
		blocks_out.append(_add_edge_with_block(
			"%s:%03d" % [prefix, index], node_ids[index], node_ids[index + 1],
			PackedVector2Array([sampled[index], sampled[index + 1]]), kind, chain_region))
	return blocks_out
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
	var speed := 4.0 if kind in ["quay_maneuver", "port_approach", "port_merge", "port_feeder"] \
		else 5.2 if kind == "shipping_ramp" else 7.2
	var close_quarters := kind in ["quay_maneuver", "port_approach", "port_merge",
		"port_connector", "port_feeder", "shipping_ramp"]
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
	if not chain_region and kind not in ["waterway_junction", "ocean_merge"]:
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


func _offset_path_distance(points: PackedVector2Array, side: float,
		desired_distance_m: float) -> PackedVector2Array:
	var result := PackedVector2Array()
	for index in range(points.size()):
		var before := points[maxi(index - 1, 0)]
		var after := points[mini(index + 1, points.size() - 1)]
		var tangent := (after - before).normalized()
		if tangent.length_squared() < 0.001:
			tangent = Vector2(1.0, 0.0)
		var normal := Vector2(-tangent.y, tangent.x)
		var available := maxf(_layout.sample_signed_distance(points[index]) - SHORE_CLEARANCE_M, 0.0)
		# Keep the four graph lanes distinct at macro-SDF seams. Port terrain is
		# flattened later and the generated centerline remains authoritative there;
		# collapsing offsets to zero creates zero-length merge edges and disconnects
		# the access carriageway exactly at those seams.
		var offset := minf(desired_distance_m,
			maxf(desired_distance_m * 0.35, available * 0.72))
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


static func _elapsed_ms(started_usec: int) -> float:
	return float(Time.get_ticks_usec() - started_usec) / 1000.0
