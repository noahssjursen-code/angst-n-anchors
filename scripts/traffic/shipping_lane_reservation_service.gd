class_name ShippingLaneReservationService
extends RefCounted

## Atomic block reservation model, intentionally independent of vessel motion.
## Both a local single-player authority and a dedicated server can own one.

var _network: ShippingLaneNetwork
var _reserved_by_block: Dictionary = {} # block id -> vessel id
var _occupied_by_block: Dictionary = {} # block id -> vessel id
var _blocks_by_vessel: Dictionary = {} # vessel id -> Dictionary(block id -> true)
var _berth_owner: Dictionary = {} # berth token id -> vessel id
var _berth_by_vessel: Dictionary = {} # vessel id -> berth token id
var _berth_queue_by_port: Dictionary = {} # port id -> Array[Dictionary]
var _queued_port_by_vessel: Dictionary = {} # vessel id -> port id
var _request_sequence := 0


func _init(network: ShippingLaneNetwork = null) -> void:
	_network = network


func configure(network: ShippingLaneNetwork) -> void:
	clear()
	_network = network


func try_reserve(vessel_id: String, requested: PackedStringArray) -> Dictionary:
	if _network == null or vessel_id.is_empty() or requested.is_empty():
		return {"ok": false, "reason": "invalid_request", "blocked_by": ""}
	for block_id in requested:
		if not _network.blocks.has(block_id):
			return {"ok": false, "reason": "unknown_block", "block_id": block_id, "blocked_by": ""}
		var queue_port_id := str((_network.blocks[block_id] as Dictionary).get("queue_port_id", ""))
		var queue_quay_id := str((_network.blocks[block_id] as Dictionary).get(
			"queue_physical_quay_id", ""))
		var queue_direction := int((_network.blocks[block_id] as Dictionary).get(
			"queue_direction_index", -1))
		var queue_index := int((_network.blocks[block_id] as Dictionary).get("queue_index", -1))
		if not queue_port_id.is_empty() \
				and not _vessel_may_enter_port_queue(
					vessel_id, queue_port_id, queue_quay_id, queue_direction, queue_index):
			return {"ok": false, "reason": "berth_or_queue_required",
				"block_id": block_id, "port_id": queue_port_id, "blocked_by": ""}
		var blocker := _blocking_owner(vessel_id, block_id)
		if not blocker.is_empty():
			return {"ok": false, "reason": "occupied", "block_id": block_id, "blocked_by": blocker}
	var owned := _blocks_by_vessel.get(vessel_id, {}) as Dictionary
	for block_id in requested:
		_reserved_by_block[block_id] = vessel_id
		owned[block_id] = true
	_blocks_by_vessel[vessel_id] = owned
	return {"ok": true, "reason": "", "blocks": requested.duplicate()}


func occupy(vessel_id: String, block_id: String) -> bool:
	if _network == null or vessel_id.is_empty() or not _network.blocks.has(block_id):
		return false
	var block := _network.blocks[block_id] as Dictionary
	var queue_port_id := str(block.get("queue_port_id", ""))
	if not queue_port_id.is_empty() and not _vessel_may_enter_port_queue(
			vessel_id,
			queue_port_id,
			str(block.get("queue_physical_quay_id", "")),
			int(block.get("queue_direction_index", -1)),
			int(block.get("queue_index", -1))):
		return false
	if not _blocking_owner(vessel_id, block_id).is_empty():
		return false
	_reserved_by_block[block_id] = vessel_id
	_occupied_by_block[block_id] = vessel_id
	var owned := _blocks_by_vessel.get(vessel_id, {}) as Dictionary
	owned[block_id] = true
	_blocks_by_vessel[vessel_id] = owned
	return true


func release_block(vessel_id: String, block_id: String) -> void:
	if str(_reserved_by_block.get(block_id, "")) == vessel_id:
		_reserved_by_block.erase(block_id)
	if str(_occupied_by_block.get(block_id, "")) == vessel_id:
		_occupied_by_block.erase(block_id)
	var owned := _blocks_by_vessel.get(vessel_id, {}) as Dictionary
	owned.erase(block_id)
	if owned.is_empty():
		_blocks_by_vessel.erase(vessel_id)
	else:
		_blocks_by_vessel[vessel_id] = owned


func release_vessel(vessel_id: String) -> void:
	var owned := _blocks_by_vessel.get(vessel_id, {}) as Dictionary
	for block_id_raw in owned.keys():
		release_block(vessel_id, str(block_id_raw))
	cancel_berth_request(vessel_id)
	release_berth(vessel_id)


func clear() -> void:
	_reserved_by_block.clear()
	_occupied_by_block.clear()
	_blocks_by_vessel.clear()
	_berth_owner.clear()
	_berth_by_vessel.clear()
	_berth_queue_by_port.clear()
	_queued_port_by_vessel.clear()
	_request_sequence = 0


func request_berth(
		vessel_id: String,
		port_id: String,
		allowed_token_ids: PackedStringArray = PackedStringArray(),
) -> Dictionary:
	if _network == null or vessel_id.is_empty() or port_id.is_empty():
		return {"status": "rejected", "reason": "invalid_request"}
	if _berth_by_vessel.has(vessel_id):
		var assigned_id := str(_berth_by_vessel[vessel_id])
		return {"status": "assigned", "berth_token_id": assigned_id,
			"port_id": str((_network.berth_tokens[assigned_id] as Dictionary).get("port_id", ""))}
	if _queued_port_by_vessel.has(vessel_id):
		var queued_port := str(_queued_port_by_vessel[vessel_id])
		var queued_request := _queue_request(queued_port, vessel_id)
		return {"status": "queued", "port_id": queued_port,
			"physical_quay_id": str(queued_request.get("physical_quay_id", "")),
			"queue_index": _queue_index(queued_port, vessel_id)}
	var available := _first_available_berth(port_id, allowed_token_ids)
	if not available.is_empty():
		_assign_berth(vessel_id, available)
		return {"status": "assigned", "port_id": port_id, "berth_token_id": available}
	var queue_quay_id := _choose_queue_quay(port_id, allowed_token_ids)
	if queue_quay_id.is_empty():
		return {"status": "rejected", "reason": "no_compatible_berth", "port_id": port_id}
	var request := {
		"vessel_id": vessel_id,
		"port_id": port_id,
		"allowed_token_ids": allowed_token_ids.duplicate(),
		"physical_quay_id": queue_quay_id,
		"sequence": _request_sequence,
	}
	_request_sequence += 1
	var queue := _berth_queue_by_port.get(port_id, []) as Array
	queue.append(request)
	_berth_queue_by_port[port_id] = queue
	_queued_port_by_vessel[vessel_id] = port_id
	return {"status": "queued", "port_id": port_id,
		"physical_quay_id": request["physical_quay_id"], "queue_index": queue.size() - 1}


func release_berth(vessel_id: String) -> Dictionary:
	if not _berth_by_vessel.has(vessel_id):
		return {}
	var token_id := str(_berth_by_vessel[vessel_id])
	var token := _network.berth_tokens.get(token_id, {}) as Dictionary
	var port_id := str(token.get("port_id", ""))
	_berth_by_vessel.erase(vessel_id)
	_berth_owner.erase(token_id)
	return _promote_queue(port_id, token_id)


func cancel_berth_request(vessel_id: String) -> void:
	if not _queued_port_by_vessel.has(vessel_id):
		return
	var port_id := str(_queued_port_by_vessel[vessel_id])
	var queue := _berth_queue_by_port.get(port_id, []) as Array
	for index in range(queue.size() - 1, -1, -1):
		if str((queue[index] as Dictionary).get("vessel_id", "")) == vessel_id:
			queue.remove_at(index)
	_queued_port_by_vessel.erase(vessel_id)
	if queue.is_empty():
		_berth_queue_by_port.erase(port_id)
	else:
		_berth_queue_by_port[port_id] = queue


func berth_assignment(vessel_id: String) -> Dictionary:
	var token_id := str(_berth_by_vessel.get(vessel_id, ""))
	return (_network.berth_tokens.get(token_id, {}) as Dictionary).duplicate(true) \
		if _network != null and not token_id.is_empty() else {}


func berth_owner(token_id: String) -> String:
	return str(_berth_owner.get(token_id, ""))


func port_berth_queue(port_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for request_value in _berth_queue_by_port.get(port_id, []) as Array:
		result.append((request_value as Dictionary).duplicate(true))
	return result


func queue_slots_for_vessel(vessel_id: String, direction_index := -1) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var port_id := str(_queued_port_by_vessel.get(vessel_id, ""))
	var physical_quay_id := ""
	if not port_id.is_empty():
		for request_value in _berth_queue_by_port.get(port_id, []) as Array:
			var request := request_value as Dictionary
			if str(request.get("vessel_id", "")) == vessel_id:
				physical_quay_id = str(request.get("physical_quay_id", ""))
				break
	else:
		var token_id := str(_berth_by_vessel.get(vessel_id, ""))
		var token := _network.berth_tokens.get(token_id, {}) as Dictionary
		port_id = str(token.get("port_id", ""))
		physical_quay_id = str(token.get("physical_quay_id", ""))
	for slot_id in _network.sorted_port_queue_slot_ids():
		var slot := _network.port_queue_slots[slot_id] as Dictionary
		if str(slot.get("port_id", "")) != port_id \
				or str(slot.get("physical_quay_id", "")) != physical_quay_id:
			continue
		if direction_index >= 0 and int(slot.get("direction_index", -1)) != direction_index:
			continue
		result.append(slot.duplicate(true))
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_direction := int(a.get("direction_index", 0))
		var b_direction := int(b.get("direction_index", 0))
		if a_direction != b_direction:
			return a_direction < b_direction
		return int(a.get("queue_index", 0)) < int(b.get("queue_index", 0))
	)
	return result


func assigned_queue_slot(vessel_id: String, direction_index: int) -> Dictionary:
	var slots := queue_slots_for_vessel(vessel_id, direction_index)
	var rank := _queue_branch_index(vessel_id)
	if rank < 0 or rank >= slots.size():
		# Queue capacity has backed up to the upstream highway signal. The vessel
		# must remain in its current block until a connector slot becomes free.
		return {}
	return slots[rank].duplicate(true)


func try_reserve_passing(vessel_id: String, zone_id: String, travel_direction: String) -> Dictionary:
	if _network == null or not _network.passing_zones.has(zone_id):
		return {"ok": false, "reason": "unknown_passing_zone"}
	if travel_direction != "forward" and travel_direction != "reverse":
		return {"ok": false, "reason": "invalid_travel_direction"}
	var zone := _network.passing_zones[zone_id] as Dictionary
	# A forward-moving ship borrows the opposing reverse lane and vice versa.
	var key := "reverse_blocks" if travel_direction == "forward" else "forward_blocks"
	var borrowed := zone.get(key, PackedStringArray()) as PackedStringArray
	var result := try_reserve(vessel_id, borrowed)
	result["passing_zone_id"] = zone_id
	result["borrowed_direction"] = "reverse" if travel_direction == "forward" else "forward"
	return result


func owner_of(block_id: String) -> String:
	return str(_occupied_by_block.get(block_id, _reserved_by_block.get(block_id, "")))


func signal_state(signal_id: String) -> String:
	if _network == null:
		return "invalid"
	var signal_record := _network.signals.get(signal_id, {}) as Dictionary
	if signal_record.is_empty():
		return "invalid"
	for block_id in signal_record.get("protected_blocks", PackedStringArray()) as PackedStringArray:
		if _occupied_by_block.has(block_id):
			return "red"
		if _reserved_by_block.has(block_id):
			return "yellow"
	return "green"


func block_state(block_id: String) -> String:
	if _network == null or not _network.blocks.has(block_id):
		return "invalid"
	if _occupied_by_block.has(block_id):
		return "red"
	if _reserved_by_block.has(block_id):
		return "yellow"
	return "green"


func snapshot() -> Dictionary:
	return {
		"network_checksum": _network.network_checksum if _network != null else "",
		"reserved": _reserved_by_block.duplicate(),
		"occupied": _occupied_by_block.duplicate(),
		"berth_owner": _berth_owner.duplicate(),
		"berth_queues": _berth_queue_by_port.duplicate(true),
		"request_sequence": _request_sequence,
	}


func apply_authority_snapshot(value: Dictionary) -> bool:
	if _network == null or str(value.get("network_checksum", "")) != _network.network_checksum:
		return false
	var reserved := value.get("reserved", {}) as Dictionary
	var occupied := value.get("occupied", {}) as Dictionary
	var berth_owner := value.get("berth_owner", {}) as Dictionary
	var berth_queues := value.get("berth_queues", {}) as Dictionary
	for block_id in reserved:
		if not _network.blocks.has(str(block_id)) or str(reserved[block_id]).is_empty():
			return false
	for block_id in occupied:
		if not _network.blocks.has(str(block_id)) or str(occupied[block_id]).is_empty():
			return false
	for token_id in berth_owner:
		if not _network.berth_tokens.has(str(token_id)) or str(berth_owner[token_id]).is_empty():
			return false
	for port_id in berth_queues:
		for request_value in berth_queues[port_id] as Array:
			var request := request_value as Dictionary
			if str(request.get("vessel_id", "")).is_empty() \
					or str(request.get("port_id", "")) != str(port_id):
				return false
	clear()
	for block_id_raw in reserved:
		var block_id := str(block_id_raw)
		var vessel_id := str(reserved[block_id_raw])
		_reserved_by_block[block_id] = vessel_id
		_track(vessel_id, block_id)
	for block_id_raw in occupied:
		var block_id := str(block_id_raw)
		var vessel_id := str(occupied[block_id_raw])
		_occupied_by_block[block_id] = vessel_id
		_track(vessel_id, block_id)
	for token_id_raw in berth_owner:
		var token_id := str(token_id_raw)
		var vessel_id := str(berth_owner[token_id_raw])
		_berth_owner[token_id] = vessel_id
		_berth_by_vessel[vessel_id] = token_id
	for port_id_raw in berth_queues:
		var port_id := str(port_id_raw)
		var queue: Array = []
		for request_value in berth_queues[port_id_raw] as Array:
			var request := (request_value as Dictionary).duplicate(true)
			request["allowed_token_ids"] = PackedStringArray(
				request.get("allowed_token_ids", []))
			queue.append(request)
		_berth_queue_by_port[port_id] = queue
		for request_value in queue:
			_queued_port_by_vessel[str((request_value as Dictionary).get("vessel_id", ""))] = port_id
	_request_sequence = int(value.get("request_sequence", 0))
	return true


func _vessel_may_enter_port_queue(
		vessel_id: String,
		port_id: String,
		physical_quay_id: String,
		direction_index: int,
		queue_index: int,
) -> bool:
	if str(_queued_port_by_vessel.get(vessel_id, "")) == port_id:
		# A connector is an interlocked movement corridor, not a parking queue.
		# Unassigned arrivals wait on ordinary upstream lane blocks. That creates
		# a natural Factorio-style tail which can later expose passing lanes,
		# while always leaving the quay-to-lane corridor free for departures.
		return false
	var token_id := str(_berth_by_vessel.get(vessel_id, ""))
	if token_id.is_empty():
		return false
	var token := _network.berth_tokens.get(token_id, {}) as Dictionary
	return str(token.get("port_id", "")) == port_id \
		and str(token.get("physical_quay_id", "")) == physical_quay_id


func _queue_request(port_id: String, vessel_id: String) -> Dictionary:
	for request_value in _berth_queue_by_port.get(port_id, []) as Array:
		var request := request_value as Dictionary
		if str(request.get("vessel_id", "")) == vessel_id:
			return request
	return {}


func _choose_queue_quay(port_id: String, allowed: PackedStringArray) -> String:
	var candidates := PackedStringArray()
	for token_id in _network.sorted_berth_token_ids():
		var token := _network.berth_tokens[token_id] as Dictionary
		if str(token.get("port_id", "")) != port_id:
			continue
		if not allowed.is_empty() and not allowed.has(token_id):
			continue
		var physical_quay_id := str(token.get("physical_quay_id", ""))
		if not candidates.has(physical_quay_id):
			candidates.append(physical_quay_id)
	var best := ""
	var best_count := 1 << 30
	for physical_quay_id in candidates:
		var count := 0
		for request_value in _berth_queue_by_port.get(port_id, []) as Array:
			if str((request_value as Dictionary).get("physical_quay_id", "")) == physical_quay_id:
				count += 1
		if count < best_count:
			best_count = count
			best = physical_quay_id
	return best


func _first_available_berth(port_id: String, allowed: PackedStringArray) -> String:
	for token_id in _network.sorted_berth_token_ids():
		var token := _network.berth_tokens[token_id] as Dictionary
		if str(token.get("port_id", "")) != port_id or _berth_owner.has(token_id):
			continue
		if not allowed.is_empty() and not allowed.has(token_id):
			continue
		return token_id
	return ""


func _assign_berth(vessel_id: String, token_id: String) -> void:
	_berth_owner[token_id] = vessel_id
	_berth_by_vessel[vessel_id] = token_id
	_queued_port_by_vessel.erase(vessel_id)


func _promote_queue(port_id: String, freed_token_id: String) -> Dictionary:
	var freed_token := _network.berth_tokens.get(freed_token_id, {}) as Dictionary
	var freed_quay_id := str(freed_token.get("physical_quay_id", ""))
	var queue := _berth_queue_by_port.get(port_id, []) as Array
	for index in range(queue.size()):
		var request := queue[index] as Dictionary
		var allowed := request.get("allowed_token_ids", PackedStringArray()) as PackedStringArray
		if not allowed.is_empty() and not allowed.has(freed_token_id):
			continue
		if str(request.get("physical_quay_id", "")) != freed_quay_id:
			continue
		var vessel_id := str(request.get("vessel_id", ""))
		queue.remove_at(index)
		if queue.is_empty():
			_berth_queue_by_port.erase(port_id)
		else:
			_berth_queue_by_port[port_id] = queue
		_assign_berth(vessel_id, freed_token_id)
		return {"status": "assigned", "vessel_id": vessel_id,
			"port_id": port_id, "berth_token_id": freed_token_id}
	return {}


func _queue_index(port_id: String, vessel_id: String) -> int:
	var queue := _berth_queue_by_port.get(port_id, []) as Array
	for index in range(queue.size()):
		if str((queue[index] as Dictionary).get("vessel_id", "")) == vessel_id:
			return index
	return -1


func _queue_branch_index(vessel_id: String) -> int:
	var port_id := str(_queued_port_by_vessel.get(vessel_id, ""))
	if port_id.is_empty():
		return -1
	var queue := _berth_queue_by_port.get(port_id, []) as Array
	var physical_quay_id := ""
	for request_value in queue:
		var request := request_value as Dictionary
		if str(request.get("vessel_id", "")) == vessel_id:
			physical_quay_id = str(request.get("physical_quay_id", ""))
			break
	if physical_quay_id.is_empty():
		return -1
	var rank := 0
	for request_value in queue:
		var request := request_value as Dictionary
		if str(request.get("physical_quay_id", "")) != physical_quay_id:
			continue
		if str(request.get("vessel_id", "")) == vessel_id:
			return rank
		rank += 1
	return -1


func _track(vessel_id: String, block_id: String) -> void:
	var owned := _blocks_by_vessel.get(vessel_id, {}) as Dictionary
	owned[block_id] = true
	_blocks_by_vessel[vessel_id] = owned


func _blocking_owner(vessel_id: String, block_id: String) -> String:
	var owner := owner_of(block_id)
	if not owner.is_empty() and owner != vessel_id:
		return owner
	var record := _network.blocks.get(block_id, {}) as Dictionary
	var exclusive_group := str(record.get("exclusive_group", ""))
	if not exclusive_group.is_empty():
		for active_id_raw in _reserved_by_block.keys():
			var active_id := str(active_id_raw)
			if active_id == block_id:
				continue
			var active_record := _network.blocks.get(active_id, {}) as Dictionary
			if str(active_record.get("exclusive_group", "")) != exclusive_group:
				continue
			owner = owner_of(active_id)
			if not owner.is_empty() and owner != vessel_id:
				return owner
	for conflict_id in record.get("conflicts", PackedStringArray()) as PackedStringArray:
		owner = owner_of(conflict_id)
		if not owner.is_empty() and owner != vessel_id:
			return owner
	return ""
