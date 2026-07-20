class_name ShippingLaneNetwork
extends RefCounted

## Immutable-after-build traffic infrastructure. This is the shared geographic
## truth for a future local single-player authority and dedicated MP authority.
## It deliberately contains no BoatBody, autopilot, company, or vessel state.

const FORMAT_VERSION := 5

var layout_checksum := ""
var network_checksum := ""
var nodes: Dictionary = {}       # node_id -> record
var edges: Dictionary = {}       # edge_id -> directed record
var blocks: Dictionary = {}      # block_id -> exclusive corridor record
var signals: Dictionary = {}     # signal_id -> record
var port_queue_slots: Dictionary = {} # queue slot id -> inbound connector block record
var berth_tokens: Dictionary = {} # berth token id -> one reservable quay station
var passing_zones: Dictionary = {} # passing zone id -> deterministic opposing-lane block set
var port_gate_nodes: Dictionary = {} # port_id -> Array[String] of physical-quay gates
var port_ramps: Dictionary = {} # ramp id -> explicit directed lane/open-water transition
var validation_issues: Array[Dictionary] = []
var _outgoing_edge_ids: Dictionary = {} # node_id -> PackedStringArray


func add_node(record: Dictionary) -> bool:
	var node_id := str(record.get("id", ""))
	var position := record.get("position", Vector2(INF, INF)) as Vector2
	if node_id.is_empty() or not position.is_finite() or nodes.has(node_id):
		return false
	var stored := record.duplicate(true)
	stored["id"] = node_id
	stored["position"] = position
	nodes[node_id] = stored
	return true


func add_edge(record: Dictionary) -> bool:
	var edge_id := str(record.get("id", ""))
	var from_id := str(record.get("from_node_id", ""))
	var to_id := str(record.get("to_node_id", ""))
	var points := _points(record.get("points", PackedVector2Array()))
	if edge_id.is_empty() or edges.has(edge_id) or not nodes.has(from_id) \
			or not nodes.has(to_id) or points.size() < 2:
		return false
	var stored := record.duplicate(true)
	stored["id"] = edge_id
	stored["from_node_id"] = from_id
	stored["to_node_id"] = to_id
	stored["points"] = points
	stored["length_m"] = _polyline_length(points)
	stored["block_ids"] = PackedStringArray(stored.get("block_ids", PackedStringArray()))
	edges[edge_id] = stored
	var outgoing := _outgoing_edge_ids.get(from_id, PackedStringArray()) as PackedStringArray
	outgoing.append(edge_id)
	outgoing.sort()
	_outgoing_edge_ids[from_id] = outgoing
	return true


func add_block(record: Dictionary) -> bool:
	var block_id := str(record.get("id", ""))
	var edge_id := str(record.get("edge_id", ""))
	if block_id.is_empty() or blocks.has(block_id) or not edges.has(edge_id):
		return false
	var stored := record.duplicate(true)
	stored["id"] = block_id
	stored["edge_id"] = edge_id
	stored["conflicts"] = PackedStringArray(stored.get("conflicts", PackedStringArray()))
	blocks[block_id] = stored
	var edge := edges[edge_id] as Dictionary
	var ids := edge.get("block_ids", PackedStringArray()) as PackedStringArray
	if not ids.has(block_id):
		ids.append(block_id)
	edge["block_ids"] = ids
	edges[edge_id] = edge
	return true


func add_signal(record: Dictionary) -> bool:
	var signal_id := str(record.get("id", ""))
	var node_id := str(record.get("node_id", ""))
	if signal_id.is_empty() or signals.has(signal_id) or not nodes.has(node_id):
		return false
	var stored := record.duplicate(true)
	stored["id"] = signal_id
	stored["node_id"] = node_id
	stored["protected_blocks"] = PackedStringArray(
		stored.get("protected_blocks", PackedStringArray()))
	signals[signal_id] = stored
	return true


func add_port_queue_slot(record: Dictionary) -> bool:
	var slot_id := str(record.get("id", ""))
	var block_id := str(record.get("block_id", ""))
	if slot_id.is_empty() or port_queue_slots.has(slot_id) or not blocks.has(block_id):
		return false
	var stored := record.duplicate(true)
	stored["id"] = slot_id
	stored["block_id"] = block_id
	port_queue_slots[slot_id] = stored
	return true


func add_berth_token(record: Dictionary) -> bool:
	var token_id := str(record.get("id", ""))
	var node_id := str(record.get("node_id", ""))
	if token_id.is_empty() or berth_tokens.has(token_id) or not nodes.has(node_id):
		return false
	var stored := record.duplicate(true)
	stored["id"] = token_id
	stored["node_id"] = node_id
	berth_tokens[token_id] = stored
	return true


func add_passing_zone(record: Dictionary) -> bool:
	var zone_id := str(record.get("id", ""))
	if zone_id.is_empty() or passing_zones.has(zone_id):
		return false
	var forward_blocks := PackedStringArray(record.get("forward_blocks", PackedStringArray()))
	var reverse_blocks := PackedStringArray(record.get("reverse_blocks", PackedStringArray()))
	if forward_blocks.is_empty() or reverse_blocks.is_empty():
		return false
	for block_id in forward_blocks:
		if not blocks.has(block_id):
			return false
	for block_id in reverse_blocks:
		if not blocks.has(block_id):
			return false
	var stored := record.duplicate(true)
	stored["id"] = zone_id
	stored["forward_blocks"] = forward_blocks
	stored["reverse_blocks"] = reverse_blocks
	stored["forward_access_blocks"] = PackedStringArray(
		stored.get("forward_access_blocks", PackedStringArray()))
	stored["reverse_access_blocks"] = PackedStringArray(
		stored.get("reverse_access_blocks", PackedStringArray()))
	stored["forward_bypass_edge_ids"] = PackedStringArray(
		stored.get("forward_bypass_edge_ids", PackedStringArray()))
	stored["reverse_bypass_edge_ids"] = PackedStringArray(
		stored.get("reverse_bypass_edge_ids", PackedStringArray()))
	passing_zones[zone_id] = stored
	return true


func add_port_ramp(record: Dictionary) -> bool:
	var ramp_id := str(record.get("id", ""))
	var lane_node_id := str(record.get("lane_node_id", ""))
	var ramp_node_id := str(record.get("ramp_node_id", ""))
	var ramp_kind := str(record.get("ramp_kind", ""))
	if ramp_id.is_empty() or port_ramps.has(ramp_id) \
			or not nodes.has(lane_node_id) or not nodes.has(ramp_node_id) \
			or ramp_kind not in ["on_ramp", "off_ramp"]:
		return false
	var stored := record.duplicate(true)
	stored["id"] = ramp_id
	stored["lane_node_id"] = lane_node_id
	stored["ramp_node_id"] = ramp_node_id
	stored["ramp_kind"] = ramp_kind
	stored["position"] = (nodes[ramp_node_id] as Dictionary).get("position", Vector2.ZERO)
	stored["transition_edge_ids"] = PackedStringArray(
		stored.get("transition_edge_ids", PackedStringArray()))
	stored["port_feeder_edge_ids"] = PackedStringArray(
		stored.get("port_feeder_edge_ids", PackedStringArray()))
	stored["crossing_block_ids"] = PackedStringArray(
		stored.get("crossing_block_ids", PackedStringArray()))
	port_ramps[ramp_id] = stored
	return true


func add_block_conflict(a_id: String, b_id: String) -> void:
	if a_id == b_id or not blocks.has(a_id) or not blocks.has(b_id):
		return
	_add_unique_conflict(a_id, b_id)
	_add_unique_conflict(b_id, a_id)


func node(node_id: String) -> Dictionary:
	return nodes.get(node_id, {}) as Dictionary


func edge(edge_id: String) -> Dictionary:
	return edges.get(edge_id, {}) as Dictionary


func block(block_id: String) -> Dictionary:
	return blocks.get(block_id, {}) as Dictionary


func sorted_node_ids() -> Array[String]:
	return _sorted_ids(nodes)


func sorted_edge_ids() -> Array[String]:
	return _sorted_ids(edges)


func sorted_block_ids() -> Array[String]:
	return _sorted_ids(blocks)


func sorted_signal_ids() -> Array[String]:
	return _sorted_ids(signals)


func sorted_port_queue_slot_ids() -> Array[String]:
	return _sorted_ids(port_queue_slots)


func sorted_berth_token_ids() -> Array[String]:
	return _sorted_ids(berth_tokens)


func sorted_passing_zone_ids() -> Array[String]:
	return _sorted_ids(passing_zones)


func sorted_port_ramp_ids() -> Array[String]:
	return _sorted_ids(port_ramps)


func ramps_for_port(port_id: String, ramp_kind := "", station := "") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for ramp_id in sorted_port_ramp_ids():
		var record := port_ramps[ramp_id] as Dictionary
		if str(record.get("port_id", "")) != port_id:
			continue
		if not ramp_kind.is_empty() and str(record.get("ramp_kind", "")) != ramp_kind:
			continue
		if not station.is_empty() and str(record.get("station", "")) != station:
			continue
		result.append(record)
	return result


func ramp_ids_for_node(node_id: String, ramp_kind := "") -> PackedStringArray:
	var result := PackedStringArray()
	for ramp_id in sorted_port_ramp_ids():
		var record := port_ramps[ramp_id] as Dictionary
		if str(record.get("ramp_node_id", "")) != node_id:
			continue
		if not ramp_kind.is_empty() and str(record.get("ramp_kind", "")) != ramp_kind:
			continue
		result.append(ramp_id)
	return result


func nearest_node(position: Vector2, allowed_kinds: PackedStringArray = PackedStringArray()) -> String:
	var best_id := ""
	var best_distance_sq := INF
	for node_id in sorted_node_ids():
		var record := nodes[node_id] as Dictionary
		if not allowed_kinds.is_empty() and not allowed_kinds.has(str(record.get("kind", ""))):
			continue
		var distance_sq := position.distance_squared_to(record.get("position", Vector2.ZERO) as Vector2)
		if distance_sq < best_distance_sq:
			best_distance_sq = distance_sq
			best_id = node_id
	return best_id


func outgoing_edges(node_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for edge_id in _outgoing_edge_ids.get(node_id, PackedStringArray()) as PackedStringArray:
		if edges.has(edge_id):
			out.append(edges[edge_id] as Dictionary)
	return out


func can_reach_kind(from_node_id: String, target_kinds: PackedStringArray) -> bool:
	if not nodes.has(from_node_id):
		return false
	var pending: Array[String] = [from_node_id]
	var seen := {from_node_id: true}
	while not pending.is_empty():
		var current: String = pending.pop_front()
		if target_kinds.has(str((nodes[current] as Dictionary).get("kind", ""))):
			return true
		for connection in outgoing_edges(current):
			var next_id := str(connection.get("to_node_id", ""))
			if next_id.is_empty() or seen.has(next_id):
				continue
			seen[next_id] = true
			pending.append(next_id)
	return false


func route_edge_ids(
		from_node_id: String,
		to_node_id: String,
		vessel: Dictionary = {},
) -> PackedStringArray:
	if not nodes.has(from_node_id) or not nodes.has(to_node_id):
		return PackedStringArray()
	var frontier: Array[Dictionary] = []
	_heap_push(frontier, {"node_id": from_node_id, "cost": 0.0})
	var distance := {from_node_id: 0.0}
	var previous_node: Dictionary = {}
	var previous_edge: Dictionary = {}
	while not frontier.is_empty():
		var entry := _heap_pop(frontier)
		var current := str(entry.get("node_id", ""))
		var current_cost := float(entry.get("cost", INF))
		if current_cost > float(distance.get(current, INF)) + 0.0001:
			continue
		if current == to_node_id:
			break
		for connection in outgoing_edges(current):
			if not _edge_supports(connection, vessel):
				continue
			var next_id := str(connection.get("to_node_id", ""))
			var speed := maxf(float(connection.get("speed_limit_ms", 7.2)), 0.1)
			var cost := float(connection.get("length_m", 0.0)) / speed \
				+ float(connection.get("routing_penalty_s", 0.0))
			var candidate := float(distance.get(current, INF)) + cost
			if candidate >= float(distance.get(next_id, INF)):
				continue
			distance[next_id] = candidate
			previous_node[next_id] = current
			previous_edge[next_id] = str(connection.get("id", ""))
			_heap_push(frontier, {"node_id": next_id, "cost": candidate})
	if not distance.has(to_node_id):
		return PackedStringArray()
	var reversed := PackedStringArray()
	var cursor := to_node_id
	while cursor != from_node_id:
		if not previous_node.has(cursor):
			return PackedStringArray()
		reversed.append(str(previous_edge[cursor]))
		cursor = str(previous_node[cursor])
	var result := PackedStringArray()
	for index in range(reversed.size() - 1, -1, -1):
		result.append(reversed[index])
	return result


static func _heap_push(heap: Array[Dictionary], entry: Dictionary) -> void:
	heap.append(entry)
	var index := heap.size() - 1
	while index > 0:
		var parent := (index - 1) / 2
		if not _heap_entry_less(heap[index], heap[parent]):
			break
		var swap := heap[parent]
		heap[parent] = heap[index]
		heap[index] = swap
		index = parent


static func _heap_pop(heap: Array[Dictionary]) -> Dictionary:
	var result := heap[0]
	var tail := heap.pop_back() as Dictionary
	if heap.is_empty():
		return result
	heap[0] = tail
	var index := 0
	while true:
		var left := index * 2 + 1
		if left >= heap.size():
			break
		var right := left + 1
		var smallest := left
		if right < heap.size() and _heap_entry_less(heap[right], heap[left]):
			smallest = right
		if not _heap_entry_less(heap[smallest], heap[index]):
			break
		var swap := heap[index]
		heap[index] = heap[smallest]
		heap[smallest] = swap
		index = smallest
	return result


static func _heap_entry_less(a: Dictionary, b: Dictionary) -> bool:
	var a_cost := float(a.get("cost", INF))
	var b_cost := float(b.get("cost", INF))
	if not is_equal_approx(a_cost, b_cost):
		return a_cost < b_cost
	return str(a.get("node_id", "")) < str(b.get("node_id", ""))


func rebuild_checksum() -> String:
	# Appending to one growing String is quadratic for production-size worlds.
	# Accumulate immutable fragments and join once so a 35-port authority graph
	# hashes in linear time without changing its deterministic wire identity.
	var identity_parts := PackedStringArray(["%d|%s" % [FORMAT_VERSION, layout_checksum]])
	for node_id in sorted_node_ids():
		var record := nodes[node_id] as Dictionary
		var point := record.get("position", Vector2.ZERO) as Vector2
		identity_parts.append("|N:%s:%s:%d,%d:%s:%s:%s" % [
			node_id, str(record.get("kind", "")), roundi(point.x), roundi(point.y),
			record.get("port_id", ""), record.get("berth_id", ""),
			record.get("waterway_id", "")])
	for edge_id in sorted_edge_ids():
		var record := edges[edge_id] as Dictionary
		identity_parts.append("|E:%s:%s:%s:%s:%.3f:%.3f:%.3f:%.3f:%.3f" % [
			edge_id, record.get("from_node_id", ""), record.get("to_node_id", ""),
			record.get("kind", ""), float(record.get("lane_width_m", 0.0)),
			float(record.get("speed_limit_ms", 0.0)), float(record.get("max_draft_m", 0.0)),
			float(record.get("max_beam_m", 0.0)), float(record.get("max_length_m", 0.0))])
		for point in record.get("points", PackedVector2Array()) as PackedVector2Array:
			identity_parts.append(":%d,%d" % [roundi(point.x), roundi(point.y)])
	for block_id in sorted_block_ids():
		var record := blocks[block_id] as Dictionary
		identity_parts.append("|B:%s:%s:%s" % [block_id, record.get("edge_id", ""),
			record.get("exclusive_group", "")])
		for conflict_id in record.get("conflicts", PackedStringArray()) as PackedStringArray:
			identity_parts.append(":%s" % conflict_id)
	for signal_id in _sorted_ids(signals):
		var record := signals[signal_id] as Dictionary
		identity_parts.append("|S:%s:%s:%s" % [signal_id, record.get("kind", ""),
			record.get("node_id", "")])
		for block_id in record.get("protected_blocks", PackedStringArray()) as PackedStringArray:
			identity_parts.append(":%s" % block_id)
	for slot_id in _sorted_ids(port_queue_slots):
		var record := port_queue_slots[slot_id] as Dictionary
		var point := record.get("position", Vector2.ZERO) as Vector2
		identity_parts.append("|Q:%s:%s:%s:%d:%d,%d" % [slot_id, record.get("port_id", ""),
			record.get("block_id", ""), int(record.get("queue_index", -1)),
			roundi(point.x), roundi(point.y)])
	for token_id in _sorted_ids(berth_tokens):
		var record := berth_tokens[token_id] as Dictionary
		identity_parts.append("|T:%s:%s:%s:%s" % [token_id, record.get("port_id", ""),
			record.get("node_id", ""), record.get("physical_quay_id", "")])
	for zone_id in _sorted_ids(passing_zones):
		var record := passing_zones[zone_id] as Dictionary
		identity_parts.append("|Z:%s:%s" % [zone_id, record.get("waterway_id", "")])
		for block_id in record.get("forward_blocks", PackedStringArray()) as PackedStringArray:
			identity_parts.append(":F:%s" % block_id)
		for block_id in record.get("reverse_blocks", PackedStringArray()) as PackedStringArray:
			identity_parts.append(":R:%s" % block_id)
		for block_id in record.get("forward_access_blocks", PackedStringArray()) as PackedStringArray:
			identity_parts.append(":AF:%s" % block_id)
		for block_id in record.get("reverse_access_blocks", PackedStringArray()) as PackedStringArray:
			identity_parts.append(":AR:%s" % block_id)
	for port_id in _sorted_ids(port_gate_nodes):
		identity_parts.append("|P:%s" % port_id)
		for gate_id in port_gate_nodes[port_id] as Array:
			identity_parts.append(":%s" % str(gate_id))
	for ramp_id in sorted_port_ramp_ids():
		var record := port_ramps[ramp_id] as Dictionary
		var point := record.get("position", Vector2.ZERO) as Vector2
		identity_parts.append("|R:%s:%s:%s:%s:%s:%s:%d,%d" % [ramp_id,
			record.get("port_id", ""), record.get("ramp_kind", ""),
			record.get("station", ""), record.get("lane_node_id", ""),
			record.get("ramp_node_id", ""), roundi(point.x), roundi(point.y)])
		for edge_id in record.get("transition_edge_ids", PackedStringArray()) as PackedStringArray:
			identity_parts.append(":T:%s" % edge_id)
		for edge_id in record.get("port_feeder_edge_ids", PackedStringArray()) as PackedStringArray:
			identity_parts.append(":F:%s" % edge_id)
		for block_id in record.get("crossing_block_ids", PackedStringArray()) as PackedStringArray:
			identity_parts.append(":C:%s" % block_id)
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update("".join(identity_parts).to_utf8_buffer())
	network_checksum = context.finish().hex_encode()
	return network_checksum


func to_snapshot() -> Dictionary:
	var wire_nodes: Dictionary = {}
	for node_id in sorted_node_ids():
		var record := (nodes[node_id] as Dictionary).duplicate(true)
		record["position"] = _vector_to_wire(record.get("position", Vector2.ZERO) as Vector2)
		wire_nodes[node_id] = record
	var wire_edges: Dictionary = {}
	for edge_id in sorted_edge_ids():
		var record := (edges[edge_id] as Dictionary).duplicate(true)
		var wire_points: Array = []
		for point in record.get("points", PackedVector2Array()) as PackedVector2Array:
			wire_points.append(_vector_to_wire(point))
		record["points"] = wire_points
		record["block_ids"] = _strings_to_wire(
			record.get("block_ids", PackedStringArray()) as PackedStringArray)
		wire_edges[edge_id] = record
	var wire_blocks: Dictionary = {}
	for block_id in sorted_block_ids():
		var record := (blocks[block_id] as Dictionary).duplicate(true)
		record["conflicts"] = _strings_to_wire(
			record.get("conflicts", PackedStringArray()) as PackedStringArray)
		wire_blocks[block_id] = record
	var wire_signals: Dictionary = {}
	for signal_id in sorted_signal_ids():
		var record := (signals[signal_id] as Dictionary).duplicate(true)
		record["protected_blocks"] = _strings_to_wire(
			record.get("protected_blocks", PackedStringArray()) as PackedStringArray)
		wire_signals[signal_id] = record
	var wire_queue_slots: Dictionary = {}
	for slot_id in sorted_port_queue_slot_ids():
		var record := (port_queue_slots[slot_id] as Dictionary).duplicate(true)
		record["position"] = _vector_to_wire(record.get("position", Vector2.ZERO) as Vector2)
		wire_queue_slots[slot_id] = record
	var wire_passing_zones: Dictionary = {}
	for zone_id in sorted_passing_zone_ids():
		var record := (passing_zones[zone_id] as Dictionary).duplicate(true)
		record["position"] = _vector_to_wire(record.get("position", Vector2.ZERO) as Vector2)
		record["forward_blocks"] = _strings_to_wire(
			record.get("forward_blocks", PackedStringArray()) as PackedStringArray)
		record["reverse_blocks"] = _strings_to_wire(
			record.get("reverse_blocks", PackedStringArray()) as PackedStringArray)
		record["forward_access_blocks"] = _strings_to_wire(
			record.get("forward_access_blocks", PackedStringArray()) as PackedStringArray)
		record["reverse_access_blocks"] = _strings_to_wire(
			record.get("reverse_access_blocks", PackedStringArray()) as PackedStringArray)
		record["forward_bypass_edge_ids"] = _strings_to_wire(
			record.get("forward_bypass_edge_ids", PackedStringArray()) as PackedStringArray)
		record["reverse_bypass_edge_ids"] = _strings_to_wire(
			record.get("reverse_bypass_edge_ids", PackedStringArray()) as PackedStringArray)
		wire_passing_zones[zone_id] = record
	var wire_port_gates: Dictionary = {}
	for port_id in _sorted_ids(port_gate_nodes):
		wire_port_gates[port_id] = (port_gate_nodes[port_id] as Array).duplicate()
	var wire_ramps: Dictionary = {}
	for ramp_id in sorted_port_ramp_ids():
		var record := (port_ramps[ramp_id] as Dictionary).duplicate(true)
		record["position"] = _vector_to_wire(record.get("position", Vector2.ZERO) as Vector2)
		record["transition_edge_ids"] = _strings_to_wire(
			record.get("transition_edge_ids", PackedStringArray()) as PackedStringArray)
		record["port_feeder_edge_ids"] = _strings_to_wire(
			record.get("port_feeder_edge_ids", PackedStringArray()) as PackedStringArray)
		record["crossing_block_ids"] = _strings_to_wire(
			record.get("crossing_block_ids", PackedStringArray()) as PackedStringArray)
		wire_ramps[ramp_id] = record
	return {
		"format_version": FORMAT_VERSION,
		"layout_checksum": layout_checksum,
		"network_checksum": network_checksum,
		"nodes": wire_nodes,
		"edges": wire_edges,
		"blocks": wire_blocks,
		"signals": wire_signals,
		"port_queue_slots": wire_queue_slots,
		"berth_tokens": berth_tokens.duplicate(true),
		"passing_zones": wire_passing_zones,
		"port_gate_nodes": wire_port_gates,
		"port_ramps": wire_ramps,
	}


static func from_snapshot(snapshot: Dictionary) -> ShippingLaneNetwork:
	var restored := ShippingLaneNetwork.new()
	if int(snapshot.get("format_version", -1)) != FORMAT_VERSION:
		restored.validation_issues.append({"severity": "error", "code": "format_mismatch",
			"message": "Shipping lane snapshot format is incompatible"})
		return restored
	restored.layout_checksum = str(snapshot.get("layout_checksum", ""))
	for node_id in _sorted_ids(snapshot.get("nodes", {}) as Dictionary):
		var record := ((snapshot.get("nodes", {}) as Dictionary)[node_id] as Dictionary).duplicate(true)
		record["position"] = _vector_from_wire(record.get("position", []))
		restored.add_node(record)
	for edge_id in _sorted_ids(snapshot.get("edges", {}) as Dictionary):
		var record := ((snapshot.get("edges", {}) as Dictionary)[edge_id] as Dictionary).duplicate(true)
		var points := PackedVector2Array()
		for raw_point in record.get("points", []) as Array:
			points.append(_vector_from_wire(raw_point))
		record["points"] = points
		record["block_ids"] = PackedStringArray(record.get("block_ids", []))
		restored.add_edge(record)
	for block_id in _sorted_ids(snapshot.get("blocks", {}) as Dictionary):
		var record := ((snapshot.get("blocks", {}) as Dictionary)[block_id] as Dictionary).duplicate(true)
		record["conflicts"] = PackedStringArray(record.get("conflicts", []))
		restored.add_block(record)
	for signal_id in _sorted_ids(snapshot.get("signals", {}) as Dictionary):
		var record := ((snapshot.get("signals", {}) as Dictionary)[signal_id] as Dictionary).duplicate(true)
		record["protected_blocks"] = PackedStringArray(record.get("protected_blocks", []))
		restored.add_signal(record)
	for slot_id in _sorted_ids(snapshot.get("port_queue_slots", {}) as Dictionary):
		var record := ((snapshot.get("port_queue_slots", {}) as Dictionary)[slot_id] as Dictionary).duplicate(true)
		record["position"] = _vector_from_wire(record.get("position", []))
		restored.add_port_queue_slot(record)
	for token_id in _sorted_ids(snapshot.get("berth_tokens", {}) as Dictionary):
		var record := ((snapshot.get("berth_tokens", {}) as Dictionary)[token_id] as Dictionary).duplicate(true)
		restored.add_berth_token(record)
	for zone_id in _sorted_ids(snapshot.get("passing_zones", {}) as Dictionary):
		var record := ((snapshot.get("passing_zones", {}) as Dictionary)[zone_id] as Dictionary).duplicate(true)
		record["position"] = _vector_from_wire(record.get("position", []))
		record["forward_blocks"] = PackedStringArray(record.get("forward_blocks", []))
		record["reverse_blocks"] = PackedStringArray(record.get("reverse_blocks", []))
		record["forward_access_blocks"] = PackedStringArray(
			record.get("forward_access_blocks", []))
		record["reverse_access_blocks"] = PackedStringArray(
			record.get("reverse_access_blocks", []))
		record["forward_bypass_edge_ids"] = PackedStringArray(
			record.get("forward_bypass_edge_ids", []))
		record["reverse_bypass_edge_ids"] = PackedStringArray(
			record.get("reverse_bypass_edge_ids", []))
		restored.add_passing_zone(record)
	for port_id in _sorted_ids(snapshot.get("port_gate_nodes", {}) as Dictionary):
		restored.port_gate_nodes[port_id] = Array(
			(snapshot.get("port_gate_nodes", {}) as Dictionary)[port_id],
		).duplicate()
	for ramp_id in _sorted_ids(snapshot.get("port_ramps", {}) as Dictionary):
		var record := ((snapshot.get("port_ramps", {}) as Dictionary)[ramp_id] \
			as Dictionary).duplicate(true)
		record["position"] = _vector_from_wire(record.get("position", []))
		record["transition_edge_ids"] = PackedStringArray(record.get("transition_edge_ids", []))
		record["port_feeder_edge_ids"] = PackedStringArray(record.get("port_feeder_edge_ids", []))
		record["crossing_block_ids"] = PackedStringArray(record.get("crossing_block_ids", []))
		restored.add_port_ramp(record)
	var expected := str(snapshot.get("network_checksum", ""))
	restored.rebuild_checksum()
	if not expected.is_empty() and expected != restored.network_checksum:
		restored.validation_issues.append({"severity": "error", "code": "checksum_mismatch",
			"message": "Shipping lane snapshot checksum does not match its contents"})
	return restored


static func _vector_to_wire(point: Vector2) -> Array[float]:
	return [point.x, point.y]


static func _vector_from_wire(raw: Variant) -> Vector2:
	if raw is Vector2:
		return raw
	if raw is Array and (raw as Array).size() >= 2:
		return Vector2(float(raw[0]), float(raw[1]))
	return Vector2(INF, INF)


static func _strings_to_wire(values: PackedStringArray) -> Array[String]:
	var out: Array[String] = []
	for value in values:
		out.append(value)
	return out


func summary() -> Dictionary:
	var errors := 0
	var warnings := 0
	for issue in validation_issues:
		if str(issue.get("severity", "warning")) == "error":
			errors += 1
		else:
			warnings += 1
	return {
		"format_version": FORMAT_VERSION,
		"layout_checksum": layout_checksum,
		"network_checksum": network_checksum,
		"nodes": nodes.size(),
		"edges": edges.size(),
		"blocks": blocks.size(),
		"signals": signals.size(),
		"port_queue_slots": port_queue_slots.size(),
		"berth_tokens": berth_tokens.size(),
		"passing_zones": passing_zones.size(),
		"port_ramps": port_ramps.size(),
		"ports": port_gate_nodes.size(),
		"errors": errors,
		"warnings": warnings,
	}


func _add_unique_conflict(owner_id: String, other_id: String) -> void:
	var record := blocks[owner_id] as Dictionary
	var conflicts := record.get("conflicts", PackedStringArray()) as PackedStringArray
	if not conflicts.has(other_id):
		conflicts.append(other_id)
		conflicts.sort()
	record["conflicts"] = conflicts
	blocks[owner_id] = record


static func _edge_supports(record: Dictionary, vessel: Dictionary) -> bool:
	if vessel.is_empty():
		return true
	var draft := float(vessel.get("draft_m", 0.0))
	var beam := float(vessel.get("beam_m", 0.0))
	var length := float(vessel.get("length_m", 0.0))
	return draft <= float(record.get("max_draft_m", INF)) \
		and beam <= float(record.get("max_beam_m", INF)) \
		and length <= float(record.get("max_length_m", INF))


func edge_supports(record: Dictionary, vessel: Dictionary) -> bool:
	return _edge_supports(record, vessel)


static func _sorted_ids(source: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for raw in source.keys():
		out.append(str(raw))
	out.sort()
	return out


static func _points(raw: Variant) -> PackedVector2Array:
	if raw is PackedVector2Array:
		return (raw as PackedVector2Array).duplicate()
	var out := PackedVector2Array()
	if raw is Array:
		for value in raw as Array:
			if value is Vector2:
				out.append(value)
			elif value is Vector3:
				out.append(Vector2(value.x, value.z))
	return out


static func _polyline_length(points: PackedVector2Array) -> float:
	var total := 0.0
	for index in range(1, points.size()):
		total += points[index - 1].distance_to(points[index])
	return total
