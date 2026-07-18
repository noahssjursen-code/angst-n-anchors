class_name MaritimeTrafficService
extends Node

## Serializable world traffic authority. In singleplayer this autoload is the
## authority; an MP server can own the same state and replicate `snapshot()`.
## Clients apply snapshots and execute agreements through their local autopilots.

signal traffic_changed(snapshot: Dictionary)
signal agreement_issued(agreement: Dictionary)
signal vhf_message(message: Dictionary)
signal port_queue_changed(port_id: String, queue: Array)

const SCHEMA_VERSION := 1
const INTENT_TTL_MSEC := 8000
const AGREEMENT_TTL_MSEC := 12000
const CONFLICT_SCAN_INTERVAL_S := 0.5
const CPA_HORIZON_S := 120.0
const MIN_SEPARATION_M := 55.0

var _intents: Dictionary = {} # vessel_id -> JSON-safe row
var _agreements: Dictionary = {} # agreement_id -> JSON-safe row
var _blocks: Dictionary = {} # block_id -> {owner, direction, queue, ...}
var _port_queues: Dictionary = {} # port_id -> Array[ticket]
var _holding_zones: Dictionary = {} # port_id -> Array[[x,z]]
var _scan_elapsed := 0.0
var _revision := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	if not is_world_authority():
		return
	_scan_elapsed += delta
	if _scan_elapsed < CONFLICT_SCAN_INTERVAL_S:
		return
	_scan_elapsed = 0.0
	var changed := _cleanup_expired()
	changed = _resolve_conflicts() or changed
	if changed:
		_publish()


func is_world_authority() -> bool:
	return multiplayer == null \
		or multiplayer.multiplayer_peer == null \
		or multiplayer.is_server()


func snapshot() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"revision": _revision,
		"server_unix_msec": Time.get_unix_time_from_system() * 1000.0,
		"intents": _intents.duplicate(true),
		"agreements": _agreements.duplicate(true),
		"blocks": _blocks.duplicate(true),
		"port_queues": _port_queues.duplicate(true),
		"holding_zones": _holding_zones.duplicate(true),
	}


func apply_authority_snapshot(data: Dictionary) -> bool:
	if is_world_authority() and multiplayer != null and multiplayer.multiplayer_peer != null:
		return false
	var incoming_revision := int(data.get("revision", -1))
	if incoming_revision < _revision:
		return false
	_revision = incoming_revision
	_intents = (data.get("intents", {}) as Dictionary).duplicate(true)
	_agreements = (data.get("agreements", {}) as Dictionary).duplicate(true)
	_blocks = (data.get("blocks", {}) as Dictionary).duplicate(true)
	_port_queues = (data.get("port_queues", {}) as Dictionary).duplicate(true)
	_holding_zones = (data.get("holding_zones", {}) as Dictionary).duplicate(true)
	traffic_changed.emit(snapshot())
	return true


func publish_intent(raw: Dictionary) -> bool:
	if not is_world_authority():
		return false
	var vessel_id := str(raw.get("vessel_id", "")).strip_edges()
	if vessel_id.is_empty():
		return false
	var position := _vector2_value(raw.get("position_xz", raw.get("position", [])))
	var velocity := _vector2_value(raw.get("velocity_xz", raw.get("velocity", [])))
	if not position.is_finite() or not velocity.is_finite():
		return false
	var row := {
		"vessel_id": vessel_id,
		"owner_id": str(raw.get("owner_id", "")),
		"kind": str(raw.get("kind", "npc")),
		"position_xz": [position.x, position.y],
		"velocity_xz": [velocity.x, velocity.y],
		"heading_deg": float(raw.get("heading_deg", 0.0)),
		"length_m": maxf(float(raw.get("length_m", 15.0)), 1.0),
		"beam_m": maxf(float(raw.get("beam_m", 5.0)), 1.0),
		"route_id": str(raw.get("route_id", "")),
		"route_progress_m": maxf(float(raw.get("route_progress_m", 0.0)), 0.0),
		"phase": str(raw.get("phase", "passage")),
		"priority": int(raw.get("priority", 0)),
		"updated_msec": Time.get_ticks_msec(),
	}
	_intents[vessel_id] = row
	return true


func withdraw_vessel(vessel_id: String) -> void:
	if not is_world_authority():
		return
	var clean := vessel_id.strip_edges()
	_intents.erase(clean)
	for agreement_id in _agreements.keys():
		var agreement := _agreements[agreement_id] as Dictionary
		if (agreement.get("vessel_ids", []) as Array).has(clean):
			_agreements.erase(agreement_id)
	for block_id in _blocks.keys():
		release_block(str(block_id), clean)
	for port_id in _port_queues.keys():
		cancel_port_arrival(str(port_id), clean)
	_publish()


func agreement_for(vessel_id: String) -> Dictionary:
	var clean := vessel_id.strip_edges()
	for raw in _agreements.values():
		var agreement := raw as Dictionary
		var instructions := agreement.get("instructions", {}) as Dictionary
		if instructions.has(clean):
			var out := agreement.duplicate(true)
			out["instruction"] = (instructions[clean] as Dictionary).duplicate(true)
			return out
	return {}


func register_holding_zones(port_id: String, points: Array) -> void:
	if not is_world_authority():
		return
	var clean_port_id := port_id.strip_edges()
	if _holding_zones.has(clean_port_id) \
			and not (_holding_zones.get(clean_port_id, []) as Array).is_empty():
		return
	var normalized: Array = []
	for raw in points:
		var point := _vector2_value(raw)
		if point.is_finite():
			normalized.append([point.x, point.y])
	_holding_zones[clean_port_id] = normalized


func request_port_arrival(
		port_id: String,
		vessel_id: String,
		family: String,
		preferred_berth_id: String,
		eta_unix: int = 0,
		priority: int = 0,
) -> Dictionary:
	if not is_world_authority():
		return {}
	var pid := port_id.strip_edges()
	var vid := vessel_id.strip_edges()
	if pid.is_empty() or vid.is_empty():
		return {}
	var queue := (_port_queues.get(pid, []) as Array).duplicate(true)
	var old_queue_json := JSON.stringify(queue)
	var found := -1
	for index in range(queue.size()):
		if str((queue[index] as Dictionary).get("vessel_id", "")) == vid:
			found = index
			break
	var ticket := {
		"ticket_id": "arrival:%s:%s" % [pid, vid],
		"port_id": pid,
		"vessel_id": vid,
		"family": family.strip_edges(),
		"preferred_berth_id": preferred_berth_id.strip_edges(),
		"eta_unix": int((queue[found] as Dictionary).get("eta_unix", eta_unix)) if found >= 0 \
			else (eta_unix if eta_unix > 0 else int(Time.get_unix_time_from_system())),
		"priority": priority,
		"requested_msec": Time.get_ticks_msec() if found < 0 \
			else int((queue[found] as Dictionary).get("requested_msec", Time.get_ticks_msec())),
	}
	if found >= 0:
		queue[found] = ticket
	else:
		queue.append(ticket)
	_sort_port_queue(queue)
	_port_queues[pid] = queue
	var queue_index := _queue_index(queue, vid)
	var zones := _holding_zones.get(pid, []) as Array
	var holding: Variant = zones[queue_index % zones.size()] if not zones.is_empty() else []
	var result := ticket.duplicate(true)
	result["queue_position"] = queue_index + 1
	result["cleared_for_approach"] = queue_index == 0
	result["holding_position_xz"] = holding
	if JSON.stringify(queue) != old_queue_json:
		port_queue_changed.emit(pid, queue.duplicate(true))
		_publish()
	return result


func complete_port_arrival(port_id: String, vessel_id: String) -> void:
	if not is_world_authority():
		return
	cancel_port_arrival(port_id, vessel_id)


func cancel_port_arrival(port_id: String, vessel_id: String) -> void:
	if not is_world_authority():
		return
	var pid := port_id.strip_edges()
	var vid := vessel_id.strip_edges()
	var queue := (_port_queues.get(pid, []) as Array).duplicate(true)
	var filtered: Array = queue.filter(func(row: Dictionary) -> bool:
		return str(row.get("vessel_id", "")) != vid)
	if filtered.size() == queue.size():
		return
	if filtered.is_empty():
		_port_queues.erase(pid)
	else:
		_port_queues[pid] = filtered
	port_queue_changed.emit(pid, filtered.duplicate(true))
	_publish()


func port_queue(port_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for raw in _port_queues.get(port_id.strip_edges(), []) as Array:
		out.append((raw as Dictionary).duplicate(true))
	return out


func request_block(
		block_id: String,
		vessel_id: String,
		direction: int,
		priority: int = 0,
) -> bool:
	if not is_world_authority():
		return false
	var bid := block_id.strip_edges()
	var vid := vessel_id.strip_edges()
	if bid.is_empty() or vid.is_empty():
		return false
	var block := (_blocks.get(bid, {}) as Dictionary).duplicate(true)
	var owner := str(block.get("owner_vessel_id", ""))
	if owner.is_empty() or owner == vid:
		block["block_id"] = bid
		block["owner_vessel_id"] = vid
		block["direction"] = signi(direction)
		block["lease_expires_msec"] = Time.get_ticks_msec() + 60000
		block["queue"] = block.get("queue", [])
		_blocks[bid] = block
		if owner.is_empty():
			_publish()
		return true
	var queue := (block.get("queue", []) as Array).duplicate(true)
	var queued_now := false
	if _queue_index(queue, vid) < 0:
		queue.append({
			"vessel_id": vid,
			"direction": signi(direction),
			"priority": priority,
			"requested_msec": Time.get_ticks_msec(),
		})
		queue.sort_custom(_traffic_request_before)
		queued_now = true
	block["queue"] = queue
	_blocks[bid] = block
	if queued_now:
		_publish()
	return false


func release_block(block_id: String, vessel_id: String) -> bool:
	if not is_world_authority():
		return false
	var bid := block_id.strip_edges()
	var vid := vessel_id.strip_edges()
	var block := (_blocks.get(bid, {}) as Dictionary).duplicate(true)
	if block.is_empty():
		return false
	var queue: Array = (block.get("queue", []) as Array).filter(func(row: Dictionary) -> bool:
		return str(row.get("vessel_id", "")) != vid)
	if str(block.get("owner_vessel_id", "")) != vid:
		block["queue"] = queue
		_blocks[bid] = block
		return false
	if queue.is_empty():
		_blocks.erase(bid)
		_publish()
		return true
	var next := queue.pop_front() as Dictionary
	block["owner_vessel_id"] = str(next.get("vessel_id", ""))
	block["direction"] = int(next.get("direction", 0))
	block["lease_expires_msec"] = Time.get_ticks_msec() + 60000
	block["queue"] = queue
	_blocks[bid] = block
	_publish()
	return true


func block_snapshot(block_id: String) -> Dictionary:
	return (_blocks.get(block_id.strip_edges(), {}) as Dictionary).duplicate(true)


func _resolve_conflicts() -> bool:
	var changed := false
	var ids := PackedStringArray()
	for vessel_id in _intents.keys():
		ids.append(str(vessel_id))
	ids.sort()
	var active_pairs: Dictionary = {}
	for a_index in range(ids.size()):
		for b_index in range(a_index + 1, ids.size()):
			var a := _intents.get(ids[a_index], {}) as Dictionary
			var b := _intents.get(ids[b_index], {}) as Dictionary
			var conflict := _conflict_between(a, b)
			if conflict.is_empty():
				continue
			var agreement_id := _agreement_id(ids[a_index], ids[b_index])
			active_pairs[agreement_id] = true
			var existing := _agreements.get(agreement_id, {}) as Dictionary
			conflict["agreement_id"] = agreement_id
			conflict["issued_msec"] = int(existing.get("issued_msec", Time.get_ticks_msec()))
			conflict["expires_msec"] = Time.get_ticks_msec() + AGREEMENT_TTL_MSEC
			_agreements[agreement_id] = conflict
			if existing.is_empty():
				agreement_issued.emit(conflict.duplicate(true))
				vhf_message.emit(_vhf_for_agreement(conflict))
				changed = true
			elif existing.get("instructions", {}) != conflict.get("instructions", {}) \
					or str(existing.get("situation", "")) != str(conflict.get("situation", "")):
				changed = true
	for agreement_id in _agreements.keys():
		if not active_pairs.has(agreement_id):
			_agreements.erase(agreement_id)
			changed = true
	return changed


func _conflict_between(a: Dictionary, b: Dictionary) -> Dictionary:
	if str(a.get("phase", "")) in ["idle", "moored", "failed", "securing"] \
			or str(b.get("phase", "")) in ["idle", "moored", "failed", "securing"]:
		return {}
	var pa := _vector2_value(a.get("position_xz", []))
	var pb := _vector2_value(b.get("position_xz", []))
	var va := _vector2_value(a.get("velocity_xz", []))
	var vb := _vector2_value(b.get("velocity_xz", []))
	var relative_position := pb - pa
	var relative_velocity := vb - va
	var speed_sq := relative_velocity.length_squared()
	var tcpa := 0.0 if speed_sq <= 0.01 \
		else clampf(-relative_position.dot(relative_velocity) / speed_sq, 0.0, CPA_HORIZON_S)
	var separation := (relative_position + relative_velocity * tcpa).length()
	var safety := maxf(
		MIN_SEPARATION_M,
		(float(a.get("length_m", 15.0)) + float(b.get("length_m", 15.0))) * 0.65,
	)
	if tcpa <= 0.5 or separation >= safety:
		return {}
	var fa := _forward_from_heading(float(a.get("heading_deg", 0.0)))
	var fb := _forward_from_heading(float(b.get("heading_deg", 0.0)))
	var situation := "head_on" if fa.dot(fb) < -0.7 else "crossing"
	var aid := str(a.get("vessel_id", ""))
	var bid := str(b.get("vessel_id", ""))
	var instructions := {}
	if situation == "head_on":
		instructions[aid] = {"action": "alter_starboard", "heading_offset_deg": 18.0, "speed_limit": 0.72}
		instructions[bid] = {"action": "alter_starboard", "heading_offset_deg": 18.0, "speed_limit": 0.72}
	else:
		var give_way := _crossing_give_way(a, b, relative_position)
		var stand_on := bid if give_way == aid else aid
		instructions[give_way] = {"action": "give_way_starboard", "heading_offset_deg": 22.0, "speed_limit": 0.45}
		instructions[stand_on] = {"action": "stand_on", "heading_offset_deg": 0.0, "speed_limit": 0.85}
	return {
		"vessel_ids": [aid, bid],
		"situation": situation,
		"tcpa_seconds": tcpa,
		"predicted_separation_m": separation,
		"minimum_separation_m": safety,
		"instructions": instructions,
	}


func _crossing_give_way(a: Dictionary, b: Dictionary, a_to_b: Vector2) -> String:
	var aid := str(a.get("vessel_id", ""))
	var bid := str(b.get("vessel_id", ""))
	var fa := _forward_from_heading(float(a.get("heading_deg", 0.0)))
	var starboard_a := Vector2(-fa.y, fa.x)
	if a_to_b.normalized().dot(starboard_a) > 0.05:
		return aid
	var priority_a := int(a.get("priority", 0))
	var priority_b := int(b.get("priority", 0))
	if priority_a != priority_b:
		return aid if priority_a < priority_b else bid
	return aid if aid > bid else bid


func _cleanup_expired() -> bool:
	var now := Time.get_ticks_msec()
	var changed := false
	for vessel_id in _intents.keys():
		if now - int((_intents[vessel_id] as Dictionary).get("updated_msec", 0)) > INTENT_TTL_MSEC:
			_intents.erase(vessel_id)
			changed = true
	for agreement_id in _agreements.keys():
		if int((_agreements[agreement_id] as Dictionary).get("expires_msec", 0)) <= now:
			_agreements.erase(agreement_id)
			changed = true
	for block_id in _blocks.keys():
		var block := _blocks[block_id] as Dictionary
		if int(block.get("lease_expires_msec", 0)) <= now:
			release_block(str(block_id), str(block.get("owner_vessel_id", "")))
			changed = true
	return changed


func _vhf_for_agreement(agreement: Dictionary) -> Dictionary:
	var vessels := agreement.get("vessel_ids", []) as Array
	var situation := str(agreement.get("situation", "traffic"))
	var text := "%s and %s: head-on traffic. Both alter starboard and reduce speed." % [
		str(vessels[0]) if vessels.size() > 0 else "Vessel",
		str(vessels[1]) if vessels.size() > 1 else "traffic",
	]
	if situation == "crossing":
		var give_way := "traffic"
		var stand_on := "traffic"
		var instructions := agreement.get("instructions", {}) as Dictionary
		for vessel_id in instructions.keys():
			var action := str((instructions[vessel_id] as Dictionary).get("action", ""))
			if action.begins_with("give_way"):
				give_way = str(vessel_id)
			elif action == "stand_on":
				stand_on = str(vessel_id)
		text = "%s, give way to starboard. %s, stand on and maintain reduced speed." % [
			give_way, stand_on]
	return {
		"channel": 16,
		"kind": "traffic_agreement",
		"agreement_id": str(agreement.get("agreement_id", "")),
		"vessel_ids": vessels.duplicate(),
		"text": text,
	}


func _sort_port_queue(queue: Array) -> void:
	queue.sort_custom(_traffic_request_before)


func _traffic_request_before(a: Dictionary, b: Dictionary) -> bool:
	var pa := int(a.get("priority", 0))
	var pb := int(b.get("priority", 0))
	if pa != pb:
		return pa > pb
	var ea := int(a.get("eta_unix", 0))
	var eb := int(b.get("eta_unix", 0))
	if ea != eb:
		return ea < eb
	var ra := int(a.get("requested_msec", 0))
	var rb := int(b.get("requested_msec", 0))
	if ra != rb:
		return ra < rb
	return str(a.get("vessel_id", "")) < str(b.get("vessel_id", ""))


func _queue_index(queue: Array, vessel_id: String) -> int:
	for index in range(queue.size()):
		if str((queue[index] as Dictionary).get("vessel_id", "")) == vessel_id:
			return index
	return -1


func _agreement_id(a: String, b: String) -> String:
	return "traffic:%s:%s" % ([a, b] if a < b else [b, a])


func _forward_from_heading(heading_deg: float) -> Vector2:
	var radians := deg_to_rad(heading_deg)
	return Vector2(sin(radians), -cos(radians)).normalized()


func _vector2_value(value: Variant) -> Vector2:
	if value is Vector2:
		return value
	if value is Vector3:
		return Vector2(value.x, value.z)
	if value is Array and (value as Array).size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return Vector2(INF, INF)


func _publish() -> void:
	_revision += 1
	traffic_changed.emit(snapshot())
