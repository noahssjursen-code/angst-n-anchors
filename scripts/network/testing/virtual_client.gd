class_name MpVirtualClient
extends Node

## One fully independent multiplayer client identity for automated testing.
## Hosts the REAL service stack the game uses — a private WorldGateway instance
## (commands, events, projections, interests) over RemoteWorldBackend — plus a
## raw WireProtocol UDP socket for the transform plane. Account/captain/vessel
## HTTP is issued directly because those wrappers are bound to process-global
## credential storage, which cannot host several accounts in one process.

const WorldGatewayScript = preload("res://scripts/network/world_gateway.gd")
const WireProtocolClass = preload("res://scripts/network/wire_protocol.gd")

signal event_recorded(event: Dictionary)

var label := "client"
var base_url := ""
var udp_host := ""
var udp_port := 7777

var account: Dictionary = {}
var account_token := ""
var captain: Dictionary = {}
var vessels: Dictionary = {} ## client_uid -> server vessel row

var gateway: Node = null ## private WorldGateway instance
var session: Dictionary = {}
var session_failed_code := ""
var session_failed_message := ""

var recorded_events: Array[Dictionary] = []
var command_results: Dictionary = {} ## request_id -> result

## entity id -> {"entity": Dictionary, "first_seen_ms": int, "last_seen_ms": int}
var snapshot_entities: Dictionary = {}
var snapshot_count := 0
var rx_packets := 0
var rx_bytes := 0
var observer_pos := Vector3.ZERO

var _udp: PacketPeerUDP = null
var _udp_seq := 0
var _outbound: Dictionary = {} ## entity id -> {"type","format","payload","meta","tombstone_sends_left"}
var _send_accum := 0.0
var _send_interval := 0.1


func setup(client_label: String, http_base_url: String, game_udp_host: String, game_udp_port: int) -> void:
	label = client_label
	base_url = http_base_url.trim_suffix("/")
	udp_host = game_udp_host
	udp_port = game_udp_port


func captain_id() -> String:
	return str(captain.get("id", ""))


func vessel_id(client_uid: String) -> String:
	return str((vessels.get(client_uid, {}) as Dictionary).get("id", ""))


func mark() -> int:
	return Time.get_ticks_msec()


func is_session_ready() -> bool:
	return gateway != null and gateway.is_ready()


func session_token() -> String:
	return gateway.session_token() if gateway != null else ""


# ── Direct HTTP (account plane) ──────────────────────────────────────────────

## auth: "" (none) | "account" | "bearer"
func _http(method: int, path: String, body: Variant, auth: String) -> Dictionary:
	var request := HTTPRequest.new()
	request.timeout = 12.0
	add_child(request)
	var headers := PackedStringArray(["Accept: application/json"])
	match auth:
		"account":
			headers.append("Authorization: Account %s" % account_token)
		"bearer":
			headers.append("Authorization: Bearer %s" % session_token())
	var body_text := ""
	if method != HTTPClient.METHOD_GET and method != HTTPClient.METHOD_DELETE:
		headers.append("Content-Type: application/json")
		body_text = JSON.stringify(body if body != null else {})
	var err := request.request(base_url + path, headers, method, body_text)
	if err != OK:
		request.queue_free()
		return {"ok": false, "status": 0, "payload": {}, "message": "http_request_error_%d" % err}
	var completed: Array = await request.request_completed
	request.queue_free()
	var result := int(completed[0])
	var status := int(completed[1])
	var raw := completed[3] as PackedByteArray
	var payload: Variant = {}
	if raw.size() > 0:
		var parsed: Variant = JSON.parse_string(raw.get_string_from_utf8())
		if parsed != null:
			payload = parsed
	var ok := result == HTTPRequest.RESULT_SUCCESS and status >= 200 and status < 300
	var message := ""
	if not ok:
		if payload is Dictionary:
			message = str((payload as Dictionary).get("error", (payload as Dictionary).get("message", "")))
		if message.is_empty():
			message = "transport result %d, status %d" % [result, status]
	return {"ok": ok, "status": status, "payload": payload, "message": message}


func login_or_register(email: String, password: String) -> Dictionary:
	var body := {"email": email, "password": password}
	var res := await _http(HTTPClient.METHOD_POST, "/v2/accounts/login", body, "")
	if not res["ok"]:
		res = await _http(HTTPClient.METHOD_POST, "/v2/accounts/register", body, "")
	if not res["ok"]:
		return {"ok": false, "message": "login and register both failed: %s" % res["message"]}
	var payload := res["payload"] as Dictionary
	account = (payload.get("account", {}) as Dictionary).duplicate(true)
	account_token = str(payload.get("access_token", ""))
	if account_token.is_empty():
		return {"ok": false, "message": "no access_token in auth response"}
	return {"ok": true}


func ensure_captain(display_name: String) -> Dictionary:
	var res := await _http(HTTPClient.METHOD_GET, "/v2/captains", null, "account")
	if res["ok"]:
		for entry in (res["payload"] as Dictionary).get("captains", []) as Array:
			var row := entry as Dictionary
			if str(row.get("display_name", "")) == display_name:
				captain = row.duplicate(true)
				return {"ok": true}
	var body := {"contract_version": 1, "display_name": display_name, "appearance_json": "{}"}
	res = await _http(HTTPClient.METHOD_POST, "/v2/captains", body, "account")
	if not res["ok"]:
		return {"ok": false, "message": "captain create failed: %s" % res["message"]}
	captain = ((res["payload"] as Dictionary).get("captain", {}) as Dictionary).duplicate(true)
	if captain_id().is_empty():
		return {"ok": false, "message": "captain response missing id"}
	return {"ok": true}


func ensure_vessel(client_uid: String, display_name: String, hull_id := "hull_90x24") -> Dictionary:
	var res := await _http(
		HTTPClient.METHOD_GET, "/v1/vessels?captain_id=%s" % captain_id().uri_encode(), null, "account"
	)
	if res["ok"] and res["payload"] is Array:
		for entry in res["payload"] as Array:
			var row := entry as Dictionary
			if str(row.get("client_uid", "")) == client_uid:
				vessels[client_uid] = row.duplicate(true)
				return {"ok": true}
	var body := {
		"captain_id": captain_id(),
		"client_uid": client_uid,
		"hull_id": hull_id,
		"registration_id": "general_vessel",
		"shaft_power_kw": 1200.0,
		"display_name": display_name,
	}
	res = await _http(HTTPClient.METHOD_POST, "/v1/vessels", body, "account")
	if not res["ok"]:
		return {"ok": false, "message": "vessel create failed: %s" % res["message"]}
	var created := res["payload"] as Dictionary
	if created.has("vessel"):
		created = created.get("vessel", {}) as Dictionary
	if str(created.get("id", "")).is_empty():
		return {"ok": false, "message": "vessel response missing id"}
	vessels[client_uid] = created.duplicate(true)
	return {"ok": true}


# ── Reliable authority plane (real WorldGateway service stack) ───────────────

func open_world_session(world_checksum := "mp-test-harness", timeout_s := 12.0) -> Dictionary:
	if gateway == null:
		gateway = WorldGatewayScript.new()
		gateway.name = "Gateway"
		add_child(gateway)
		gateway.set_connection_override(base_url, account_token)
		gateway.session_ready.connect(func(_remote: bool, s: Dictionary) -> void: session = s.duplicate(true))
		gateway.authority_error.connect(func(code: String, message: String) -> void:
			session_failed_code = code
			session_failed_message = message
		)
		gateway.command_completed.connect(func(request_id: String, result: Dictionary) -> void:
			command_results[request_id] = result.duplicate(true)
		)
		gateway.world_event.connect(_on_event_received)
	else:
		gateway.set_connection_override(base_url, account_token)
	session = {}
	session_failed_code = ""
	session_failed_message = ""
	gateway.begin_session_with_identity(true, captain_id(), label, world_checksum)
	var deadline := Time.get_ticks_msec() + int(timeout_s * 1000.0)
	while session.is_empty() and session_failed_code.is_empty() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if not session.is_empty():
		return {"ok": true}
	return {"ok": false, "message": "%s: %s" % [session_failed_code, session_failed_message]}


## Simulates a drop + reconnect: closes the session and opens a fresh one on
## the same gateway. Retained interest scopes survive on the gateway and are
## re-synced automatically; callers should still await ensure_interests before
## depending on scoped events.
func reopen_session(timeout_s := 12.0) -> Dictionary:
	if gateway != null:
		gateway.stop_session()
	return await open_world_session("mp-test-harness", timeout_s)


func _on_event_received(event: Dictionary) -> void:
	var copy := event.duplicate(true)
	copy["_received_at_ms"] = Time.get_ticks_msec()
	recorded_events.append(copy)
	event_recorded.emit(copy)


## Retains interest scopes on the gateway and waits until the server confirms
## them, so actions triggered afterwards can never race the scope activation.
func ensure_interests(scopes: Array, timeout_s := 8.0) -> Dictionary:
	for scope in scopes:
		gateway.retain_interest(str(scope), self)
	var deadline := Time.get_ticks_msec() + int(timeout_s * 1000.0)
	while Time.get_ticks_msec() < deadline:
		var active: Array = gateway.confirmed_interests()
		var all_present := true
		for scope in scopes:
			if not active.has(str(scope)):
				all_present = false
				break
		if all_present:
			return {"ok": true}
		await get_tree().create_timer(0.2).timeout
	return {"ok": false, "message": "interest scopes not confirmed within %.1fs" % timeout_s}


func send_world_command(command_name: String, body: Dictionary, request_id := "") -> String:
	return gateway.send_command(command_name, body, request_id)


func await_command_result(request_id: String, timeout_s := 8.0) -> Dictionary:
	var deadline := Time.get_ticks_msec() + int(timeout_s * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if command_results.has(request_id):
			return command_results[request_id] as Dictionary
		await get_tree().process_frame
	return {"ok": false, "code": "await_timeout", "message": "no result within %.1fs" % timeout_s, "request_id": request_id}


func await_command(command_name: String, body: Dictionary, timeout_s := 8.0, request_id := "") -> Dictionary:
	var rid := send_world_command(command_name, body, request_id)
	return await await_command_result(rid, timeout_s)


func events_of_type(event_type: String, since_ms := -1, predicate := Callable()) -> Array[Dictionary]:
	var matches: Array[Dictionary] = []
	for event in recorded_events:
		if str(event.get("type", "")) != event_type:
			continue
		if since_ms >= 0 and int(event.get("_received_at_ms", 0)) < since_ms:
			continue
		if predicate.is_valid() and not bool(predicate.call(event)):
			continue
		matches.append(event)
	return matches


func await_event(event_type: String, predicate := Callable(), timeout_s := 8.0, since_ms := -1) -> Dictionary:
	var deadline := Time.get_ticks_msec() + int(timeout_s * 1000.0)
	while Time.get_ticks_msec() < deadline:
		var matches := events_of_type(event_type, since_ms, predicate)
		if not matches.is_empty():
			return matches[0]
		await get_tree().process_frame
	return {}


func await_projection(kind: String, id: String, predicate := Callable(), timeout_s := 8.0) -> Dictionary:
	var deadline := Time.get_ticks_msec() + int(timeout_s * 1000.0)
	while Time.get_ticks_msec() < deadline:
		var projection: Dictionary = gateway.projection(kind, id)
		if not projection.is_empty():
			if not predicate.is_valid() or bool(predicate.call(projection)):
				return projection
		gateway.query_projections(kind, id)
		await get_tree().create_timer(0.4).timeout
	return {}


## Creates a WorldStateBinding wired to THIS client's gateway — the exact
## service class game assets attach. The caller owns assertions on its signals.
func make_state_binding(entity_id: String, kind := "world_entity") -> WorldStateBinding:
	var binding := WorldStateBinding.new()
	binding.entity_id = entity_id
	binding.entity_kind = kind
	binding.set_gateway(gateway)
	add_child(binding)
	return binding


# ── Loss-tolerant realtime plane (raw UDP via WireProtocol) ──────────────────

func udp_start() -> Dictionary:
	_udp = PacketPeerUDP.new()
	var err := _udp.connect_to_host(udp_host, udp_port)
	if err != OK:
		return {"ok": false, "message": "udp connect error %d" % err}
	return {"ok": true}


func set_avatar(pos: Vector3, yaw := 0.0) -> void:
	observer_pos = pos
	_outbound[captain_id()] = {
		"type": "player",
		"format": 4,
		"payload": [pos.x, pos.y, pos.z, yaw],
		"meta": "name=%s" % label,
	}


func set_ship_entity(entity_id: String, hull_id: String, pos: Vector3, meta: String) -> void:
	_outbound[entity_id] = {
		"type": "ship_%s" % hull_id,
		"format": 6,
		"payload": [pos.x, pos.y, pos.z, 0.0, 0.0, 0.0],
		"meta": meta,
	}


## Replaces the entity's outbound meta with the server removal signal and keeps
## repeating it for a few sends (UDP is lossy), then stops sending the entity.
func tombstone_entity(entity_id: String, repeats := 5) -> void:
	if not _outbound.has(entity_id):
		return
	var entry := _outbound[entity_id] as Dictionary
	entry["meta"] = "state=despawned"
	entry["tombstone_sends_left"] = repeats


## Simulates the current buggy client behavior: stop sending with no tombstone.
func drop_entity_silently(entity_id: String) -> void:
	_outbound.erase(entity_id)


func has_seen_entity(entity_id: String) -> bool:
	return snapshot_entities.has(entity_id)


func entity_last_seen_ms(entity_id: String) -> int:
	if not snapshot_entities.has(entity_id):
		return -1
	return int((snapshot_entities[entity_id] as Dictionary).get("last_seen_ms", -1))


func await_snapshot_entity(entity_id: String, timeout_s := 10.0, predicate := Callable()) -> Dictionary:
	var deadline := Time.get_ticks_msec() + int(timeout_s * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if snapshot_entities.has(entity_id):
			var entity := (snapshot_entities[entity_id] as Dictionary).get("entity", {}) as Dictionary
			if not predicate.is_valid() or bool(predicate.call(entity)):
				return entity
		await get_tree().process_frame
	return {}


## Waits until the entity has been absent from inbound snapshots for
## `absent_for_ms`. Returns how long after `from_ms` the entity was last seen.
func await_entity_absent(entity_id: String, absent_for_ms := 3000, timeout_s := 30.0, from_ms := -1) -> Dictionary:
	var start := Time.get_ticks_msec() if from_ms < 0 else from_ms
	var deadline := Time.get_ticks_msec() + int(timeout_s * 1000.0)
	while Time.get_ticks_msec() < deadline:
		var last_seen := entity_last_seen_ms(entity_id)
		if last_seen < 0 or Time.get_ticks_msec() - last_seen >= absent_for_ms:
			var lingered_s := 0.0
			if last_seen > start:
				lingered_s = float(last_seen - start) / 1000.0
			return {"ok": true, "lingered_s": lingered_s}
		await get_tree().process_frame
	return {"ok": false, "lingered_s": float(timeout_s)}


func send_logout(times := 3) -> void:
	if _udp == null or session_token().is_empty():
		return
	var packet := WireProtocolClass.encode_logout(captain_id(), session_token())
	for i in times:
		_udp.put_packet(packet)
		await get_tree().create_timer(0.1).timeout


func close_session() -> void:
	_outbound.clear()
	if _udp != null:
		_udp.close()
		_udp = null
	if gateway != null:
		gateway.stop_session()


func _process(delta: float) -> void:
	_pump_inbound()
	if _udp == null or session_token().is_empty():
		return
	_send_accum += delta
	if _send_accum < _send_interval:
		return
	_send_accum = 0.0
	_send_update()


func _send_update() -> void:
	var entities: Array = []
	var finished_tombstones: Array[String] = []
	for entity_id in _outbound.keys():
		var entry := _outbound[entity_id] as Dictionary
		entities.append({
			"id": entity_id,
			"type": entry["type"],
			"format": entry["format"],
			"payload": entry["payload"],
			"meta": entry["meta"],
		})
		if entry.has("tombstone_sends_left"):
			entry["tombstone_sends_left"] = int(entry["tombstone_sends_left"]) - 1
			if int(entry["tombstone_sends_left"]) <= 0:
				finished_tombstones.append(str(entity_id))
	for entity_id in finished_tombstones:
		_outbound.erase(entity_id)
	if entities.is_empty():
		_udp_seq += 1
		_udp.put_packet(WireProtocolClass.encode_client_update(
			_udp_seq, captain_id(), session_token(), observer_pos, []
		))
		return
	## Byte-aware batching, mirroring NetworkManager: the server silently drops
	## datagrams over MAX_PACKET_BYTES, so batches split on encoded size, not
	## just entity count.
	var batch: Array = []
	for entity in entities:
		var candidate := batch.duplicate()
		candidate.append(entity)
		var probe := WireProtocolClass.encode_client_update(
			_udp_seq + 1, captain_id(), session_token(), observer_pos, candidate
		)
		var overflows := candidate.size() > WireProtocolClass.MAX_ENTITIES_PER_UPDATE \
			or probe.size() > WireProtocolClass.MAX_PACKET_BYTES
		if overflows and not batch.is_empty():
			_udp_seq += 1
			_udp.put_packet(WireProtocolClass.encode_client_update(
				_udp_seq, captain_id(), session_token(), observer_pos, batch
			))
			batch = [entity]
		else:
			batch = candidate
	if not batch.is_empty():
		_udp_seq += 1
		_udp.put_packet(WireProtocolClass.encode_client_update(
			_udp_seq, captain_id(), session_token(), observer_pos, batch
		))


func _pump_inbound() -> void:
	if _udp == null:
		return
	while _udp.get_available_packet_count() > 0:
		var packet := _udp.get_packet()
		rx_packets += 1
		rx_bytes += packet.size()
		if packet.size() < 2 or int(packet[1]) != WireProtocolClass.UDP_MSG_TYPE_SNAPSHOT:
			continue
		var snapshot := WireProtocolClass.decode_snapshot(packet)
		if snapshot.is_empty():
			continue
		snapshot_count += 1
		var now := Time.get_ticks_msec()
		for entity_variant in snapshot.get("entities", []) as Array:
			var entity := entity_variant as Dictionary
			var entity_id := str(entity.get("id", ""))
			var first_seen := now
			if snapshot_entities.has(entity_id):
				first_seen = int((snapshot_entities[entity_id] as Dictionary).get("first_seen_ms", now))
			snapshot_entities[entity_id] = {
				"entity": entity,
				"first_seen_ms": first_seen,
				"last_seen_ms": now,
			}
