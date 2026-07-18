class_name MaritimeTrafficService
extends Node

## Serializable world traffic authority. In singleplayer this autoload is the
## authority; an MP server can own the same state and replicate `snapshot()`.
## Clients apply snapshots and execute agreements through their local autopilots.

signal traffic_changed(snapshot: Dictionary)
signal agreement_issued(agreement: Dictionary)
signal vhf_message(message: Dictionary)
signal port_queue_changed(port_id: String, queue: Array)

const SCHEMA_VERSION := 2
const INTENT_TTL_MSEC := 8000
const AGREEMENT_TTL_MSEC := 12000
const CONFLICT_SCAN_INTERVAL_S := 0.5
const CPA_HORIZON_S := 120.0
const MIN_SEPARATION_M := 55.0
const CONFLICT_CELL_M := 700.0
const CONFLICT_NEIGHBOUR_CELLS := 2
const LANE_BLOCK_SIZE_M := 400.0
const LANE_LOOKAHEAD_M := [120.0, 520.0, 920.0]
const BLOCK_LEASE_MSEC := 30000

var _intents: Dictionary = {} # vessel_id -> JSON-safe row
var _agreements: Dictionary = {} # agreement_id -> JSON-safe row
var _blocks: Dictionary = {} # block_id -> {owner, direction, queue, ...}
var _port_queues: Dictionary = {} # port_id -> Array[ticket]
var _holding_zones: Dictionary = {} # port_id -> Array[[x,z]]
var _lane_claims: Dictionary = {} # vessel_id -> Array[block_id]
var _scan_elapsed := 0.0
var _revision := 0
var _request_sequence := 0


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
		"request_sequence": _request_sequence,
		"server_unix_msec": Time.get_unix_time_from_system() * 1000.0,
		"intents": _intents.duplicate(true),
		"agreements": _agreements.duplicate(true),
		"blocks": _blocks.duplicate(true),
		"port_queues": _port_queues.duplicate(true),
		"holding_zones": _holding_zones.duplicate(true),
		"lane_claims": _lane_claims.duplicate(true),
	}


func apply_authority_snapshot(data: Dictionary) -> bool:
	if is_world_authority() and multiplayer != null and multiplayer.multiplayer_peer != null:
		return false
	var incoming_revision := int(data.get("revision", -1))
	if incoming_revision < _revision:
		return false
	_revision = incoming_revision
	_request_sequence = maxi(int(data.get("request_sequence", 0)), _request_sequence)
	_intents = (data.get("intents", {}) as Dictionary).duplicate(true)
	_agreements = (data.get("agreements", {}) as Dictionary).duplicate(true)
	_blocks = (data.get("blocks", {}) as Dictionary).duplicate(true)
	_port_queues = (data.get("port_queues", {}) as Dictionary).duplicate(true)
	_holding_zones = (data.get("holding_zones", {}) as Dictionary).duplicate(true)
	_lane_claims = (data.get("lane_claims", {}) as Dictionary).duplicate(true)
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
		"updated_unix_msec": _now_unix_msec(),
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
	release_lane_window(clean)
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
		"resource_key": _port_resource_key(family, preferred_berth_id),
		"requested_unix_msec": _now_unix_msec() if found < 0 \
			else int((queue[found] as Dictionary).get("requested_unix_msec", _now_unix_msec())),
		"request_sequence": _next_request_sequence() if found < 0 \
			else int((queue[found] as Dictionary).get("request_sequence", 0)),
	}
	if found >= 0:
		queue[found] = ticket
	else:
		queue.append(ticket)
	_sort_port_queue(queue)
	_port_queues[pid] = queue
	var queue_index := _resource_queue_index(queue, vid, str(ticket["resource_key"]))
	var zones := _holding_zones.get(pid, []) as Array
	var holding_rank := maxi(_queue_index(queue, vid), 0)
	var holding: Variant = zones[holding_rank % zones.size()] if not zones.is_empty() else []
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
		capacity: int = 1,
) -> bool:
	if not is_world_authority():
		return false
	var bid := block_id.strip_edges()
	var vid := vessel_id.strip_edges()
	if bid.is_empty() or vid.is_empty():
		return false
	var block := _normalized_block(bid, _blocks.get(bid, {}) as Dictionary, capacity)
	var owners := block.get("owner_vessel_ids", []) as Array
	var requested_direction := signi(direction)
	if requested_direction == 0:
		requested_direction = 1
	if owners.has(vid):
		var leases := block.get("owner_lease_unix_msec", {}) as Dictionary
		leases[vid] = _now_unix_msec() + BLOCK_LEASE_MSEC
		block["owner_lease_unix_msec"] = leases
		_blocks[bid] = block
		return true
	var queue := (block.get("queue", []) as Array).duplicate(true)
	var opposing_waits := _queue_has_opposing_direction(queue, int(block.get("direction", 0)))
	var can_join := owners.is_empty() or (
		int(block.get("direction", 0)) == requested_direction
		and owners.size() < int(block.get("capacity", 1))
		and not opposing_waits
	)
	if can_join:
		if owners.is_empty():
			block["direction"] = requested_direction
		owners.append(vid)
		var leases := block.get("owner_lease_unix_msec", {}) as Dictionary
		leases[vid] = _now_unix_msec() + BLOCK_LEASE_MSEC
		block["owner_vessel_ids"] = owners
		block["owner_vessel_id"] = str(owners[0])
		block["owner_lease_unix_msec"] = leases
		_blocks[bid] = block
		_publish()
		return true
	var queued_now := false
	if _queue_index(queue, vid) < 0:
		queue.append({
			"vessel_id": vid,
			"direction": signi(direction),
			"priority": priority,
			"requested_unix_msec": _now_unix_msec(),
			"request_sequence": _next_request_sequence(),
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
	var block := _normalized_block(bid, _blocks.get(bid, {}) as Dictionary, 1)
	if block.is_empty():
		return false
	var queue: Array = (block.get("queue", []) as Array).filter(func(row: Dictionary) -> bool:
		return str(row.get("vessel_id", "")) != vid)
	var owners := (block.get("owner_vessel_ids", []) as Array).duplicate()
	if not owners.has(vid):
		block["queue"] = queue
		_blocks[bid] = block
		return false
	owners.erase(vid)
	var leases := block.get("owner_lease_unix_msec", {}) as Dictionary
	leases.erase(vid)
	block["owner_vessel_ids"] = owners
	block["owner_lease_unix_msec"] = leases
	if not owners.is_empty():
		block["owner_vessel_id"] = str(owners[0])
		block["queue"] = queue
		_blocks[bid] = block
		_publish()
		return true
	if queue.is_empty():
		_blocks.erase(bid)
		_publish()
		return true
	var next_direction := int((queue[0] as Dictionary).get("direction", 1))
	owners = []
	leases = {}
	var capacity_value := int(block.get("capacity", 1))
	while not queue.is_empty() and owners.size() < capacity_value:
		var next := queue[0] as Dictionary
		if int(next.get("direction", 0)) != next_direction:
			break
		queue.pop_front()
		var next_id := str(next.get("vessel_id", ""))
		owners.append(next_id)
		leases[next_id] = _now_unix_msec() + BLOCK_LEASE_MSEC
	block["owner_vessel_ids"] = owners
	block["owner_vessel_id"] = str(owners[0])
	block["direction"] = next_direction
	block["owner_lease_unix_msec"] = leases
	block["queue"] = queue
	_blocks[bid] = block
	_publish()
	return true


func block_snapshot(block_id: String) -> Dictionary:
	return (_blocks.get(block_id.strip_edges(), {}) as Dictionary).duplicate(true)


func lane_block_spec(position_xz: Vector2, direction_xz: Vector2) -> Dictionary:
	var cell := Vector2i(
		floori(position_xz.x / LANE_BLOCK_SIZE_M),
		floori(position_xz.y / LANE_BLOCK_SIZE_M),
	)
	var direction := 1
	if absf(direction_xz.x) >= absf(direction_xz.y):
		direction = 1 if direction_xz.x >= 0.0 else -1
	else:
		direction = 1 if direction_xz.y >= 0.0 else -1
	var clearance := LandField.distance_to_land(Vector3(position_xz.x, 0.0, position_xz.y))
	var capacity := 1 if clearance < 90.0 else (2 if clearance < 180.0 else 4)
	return {
		"block_id": "lane:%d:%d" % [cell.x, cell.y],
		"direction": direction,
		"capacity": capacity,
		"clearance_m": clearance,
		"center_xz": [
			(float(cell.x) + 0.5) * LANE_BLOCK_SIZE_M,
			(float(cell.y) + 0.5) * LANE_BLOCK_SIZE_M,
		],
	}


func lane_window_for_route(route: MarineRoutePlan, progress_m: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if route == null or not route.is_valid():
		return out
	var seen: Dictionary = {}
	for offset in LANE_LOOKAHEAD_M:
		var distance := minf(progress_m + float(offset), route.total_distance_m())
		var point := route.point_at_distance(distance)
		var direction := route.direction_at_distance(distance, 80.0)
		var spec := lane_block_spec(point, direction)
		var block_id := str(spec.get("block_id", ""))
		if block_id.is_empty() or seen.has(block_id):
			continue
		seen[block_id] = true
		out.append(spec)
	return out


func request_lane_window(vessel_id: String, specs: Array[Dictionary], priority: int = 0) -> Dictionary:
	if not is_world_authority():
		return {}
	var vid := vessel_id.strip_edges()
	if vid.is_empty():
		return {}
	var wanted := PackedStringArray()
	var acquired := PackedStringArray()
	var blocked_by := ""
	for spec in specs:
		var block_id := str(spec.get("block_id", ""))
		if block_id.is_empty():
			continue
		wanted.append(block_id)
		if request_block(block_id, vid, int(spec.get("direction", 1)), priority,
				int(spec.get("capacity", 1))):
			_decorate_lane_block(block_id, spec)
			acquired.append(block_id)
		else:
			_decorate_lane_block(block_id, spec)
			blocked_by = block_id
			break
	var previous := _string_array(_lane_claims.get(vid, []))
	for block_id in previous:
		if block_id not in acquired:
			release_block(block_id, vid)
	_lane_claims[vid] = Array(acquired)
	return {
		"granted": blocked_by.is_empty(),
		"blocked_by": blocked_by,
		"held_blocks": Array(acquired),
		"requested_blocks": Array(wanted),
	}


func release_lane_window(vessel_id: String) -> void:
	var vid := vessel_id.strip_edges()
	for block_id in _string_array(_lane_claims.get(vid, [])):
		release_block(block_id, vid)
	_lane_claims.erase(vid)


func _decorate_lane_block(block_id: String, spec: Dictionary) -> void:
	var block := _blocks.get(block_id, {}) as Dictionary
	if block.is_empty():
		return
	block["kind"] = "shipping_lane"
	block["center_xz"] = (spec.get("center_xz", []) as Array).duplicate()
	block["clearance_m"] = float(spec.get("clearance_m", 0.0))
	_blocks[block_id] = block


func _resolve_conflicts() -> bool:
	var changed := false
	var active_pairs: Dictionary = {}
	for pair in _spatial_conflict_pairs():
			var aid := str(pair[0])
			var bid := str(pair[1])
			var a := _intents.get(aid, {}) as Dictionary
			var b := _intents.get(bid, {}) as Dictionary
			var conflict := _conflict_between(a, b)
			if conflict.is_empty():
				continue
			var agreement_id := _agreement_id(aid, bid)
			active_pairs[agreement_id] = true
			var existing := _agreements.get(agreement_id, {}) as Dictionary
			conflict["agreement_id"] = agreement_id
			conflict["issued_unix_msec"] = int(existing.get("issued_unix_msec", _now_unix_msec()))
			conflict["expires_unix_msec"] = _now_unix_msec() + AGREEMENT_TTL_MSEC
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


func _spatial_conflict_pairs() -> Array[Array]:
	var buckets: Dictionary = {}
	for vessel_id_raw in _intents.keys():
		var vessel_id := str(vessel_id_raw)
		var position := _vector2_value((_intents[vessel_id] as Dictionary).get("position_xz", []))
		if not position.is_finite():
			continue
		var cell := Vector2i(floori(position.x / CONFLICT_CELL_M), floori(position.y / CONFLICT_CELL_M))
		var key := "%d:%d" % [cell.x, cell.y]
		var bucket := buckets.get(key, []) as Array
		bucket.append(vessel_id)
		buckets[key] = bucket
	var pairs: Array[Array] = []
	var seen: Dictionary = {}
	for key_raw in buckets.keys():
		var parts := str(key_raw).split(":")
		var origin := Vector2i(int(parts[0]), int(parts[1]))
		for dx in range(-CONFLICT_NEIGHBOUR_CELLS, CONFLICT_NEIGHBOUR_CELLS + 1):
			for dz in range(-CONFLICT_NEIGHBOUR_CELLS, CONFLICT_NEIGHBOUR_CELLS + 1):
				var other_key := "%d:%d" % [origin.x + dx, origin.y + dz]
				if not buckets.has(other_key):
					continue
				for a_raw in buckets[key_raw] as Array:
					for b_raw in buckets[other_key] as Array:
						var a := str(a_raw)
						var b := str(b_raw)
						if a == b:
							continue
						var pair_id := _agreement_id(a, b)
						if seen.has(pair_id):
							continue
						seen[pair_id] = true
						pairs.append([a, b] if a < b else [b, a])
	return pairs


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
	var now := _now_unix_msec()
	var changed := false
	for vessel_id in _intents.keys():
		if now - int((_intents[vessel_id] as Dictionary).get("updated_unix_msec", 0)) > INTENT_TTL_MSEC:
			_intents.erase(vessel_id)
			changed = true
	for agreement_id in _agreements.keys():
		if int((_agreements[agreement_id] as Dictionary).get("expires_unix_msec", 0)) <= now:
			_agreements.erase(agreement_id)
			changed = true
	for block_id in _blocks.keys():
		var block := _blocks[block_id] as Dictionary
		var leases := block.get("owner_lease_unix_msec", {}) as Dictionary
		for owner_raw in (block.get("owner_vessel_ids", []) as Array).duplicate():
			var owner := str(owner_raw)
			if int(leases.get(owner, 0)) <= now:
				release_block(str(block_id), owner)
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
	var ra := int(a.get("requested_unix_msec", a.get("requested_msec", 0)))
	var rb := int(b.get("requested_unix_msec", b.get("requested_msec", 0)))
	if ra != rb:
		return ra < rb
	var sa := int(a.get("request_sequence", 0))
	var sb := int(b.get("request_sequence", 0))
	if sa != sb:
		return sa < sb
	return str(a.get("vessel_id", "")) < str(b.get("vessel_id", ""))


func _queue_index(queue: Array, vessel_id: String) -> int:
	for index in range(queue.size()):
		if str((queue[index] as Dictionary).get("vessel_id", "")) == vessel_id:
			return index
	return -1


func _resource_queue_index(queue: Array, vessel_id: String, resource_key: String) -> int:
	var index := 0
	for raw in queue:
		var row := raw as Dictionary
		if str(row.get("resource_key", "")) != resource_key:
			continue
		if str(row.get("vessel_id", "")) == vessel_id:
			return index
		index += 1
	return -1


func _port_resource_key(family: String, preferred_berth_id: String) -> String:
	var berth := preferred_berth_id.strip_edges()
	return "berth:%s" % berth if not berth.is_empty() else "family:%s" % family.strip_edges()


func _normalized_block(block_id: String, raw: Dictionary, capacity: int) -> Dictionary:
	var block := raw.duplicate(true)
	block["block_id"] = block_id
	block["capacity"] = maxi(int(block.get("capacity", capacity)), maxi(capacity, 1))
	var owners := block.get("owner_vessel_ids", []) as Array
	if owners.is_empty():
		var legacy_owner := str(block.get("owner_vessel_id", ""))
		if not legacy_owner.is_empty():
			owners.append(legacy_owner)
	block["owner_vessel_ids"] = owners
	block["owner_vessel_id"] = str(owners[0]) if not owners.is_empty() else ""
	block["owner_lease_unix_msec"] = block.get("owner_lease_unix_msec", {})
	block["queue"] = block.get("queue", [])
	return block


func _queue_has_opposing_direction(queue: Array, direction: int) -> bool:
	for raw in queue:
		if int((raw as Dictionary).get("direction", 0)) != direction:
			return true
	return false


func _string_array(value: Variant) -> PackedStringArray:
	var out := PackedStringArray()
	if value is Array or value is PackedStringArray:
		for raw in value:
			out.append(str(raw))
	return out


func _now_unix_msec() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0)


func _next_request_sequence() -> int:
	_request_sequence += 1
	return _request_sequence


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
