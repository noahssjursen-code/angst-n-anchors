class_name ShippingLaneReservationService
extends RefCounted

## Atomic block reservation model, intentionally independent of vessel motion.
## Both a local single-player authority and a dedicated server can own one.

var _network: ShippingLaneNetwork
var _reserved_by_block: Dictionary = {} # block id -> vessel id
var _occupied_by_block: Dictionary = {} # block id -> vessel id
var _blocks_by_vessel: Dictionary = {} # vessel id -> Dictionary(block id -> true)


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


func clear() -> void:
	_reserved_by_block.clear()
	_occupied_by_block.clear()
	_blocks_by_vessel.clear()


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
	}


func apply_authority_snapshot(value: Dictionary) -> bool:
	if _network == null or str(value.get("network_checksum", "")) != _network.network_checksum:
		return false
	var reserved := value.get("reserved", {}) as Dictionary
	var occupied := value.get("occupied", {}) as Dictionary
	for block_id in reserved:
		if not _network.blocks.has(str(block_id)) or str(reserved[block_id]).is_empty():
			return false
	for block_id in occupied:
		if not _network.blocks.has(str(block_id)) or str(occupied[block_id]).is_empty():
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
	return true


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
