extends SceneTree

## Opt-in production smoke test for the complete account -> captain ->
## authority -> UDP presence chain.
##
## Run with an isolated client slot that has already signed in:
##   godot --headless --path . --script tests/remote_realtime_join_smoke.gd -- \
##     --mp-client-slot=client-1
##
## The test reads the existing revocable account credential. It never prints or
## modifies that credential and closes both transports before exiting.

const JOIN_TIMEOUT_S := 10.0
const PRESENCE_TIMEOUT_S := 8.0
const MOVEMENT_TIMEOUT_S := 8.0
const REMOTE_PROFILE_TIMEOUT_S := 12.0

var _host: Node
var _authority_error := ""
var _avatar: CharacterBody3D


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_host = Node.new()
	_host.name = "RemoteRealtimeSmokeHost"
	root.add_child(_host)

	var config := root.get_node_or_null("ServerConfig")
	var gateway := root.get_node_or_null("WorldGateway")
	var network := root.get_node_or_null("NetworkManager")
	var player_session := root.get_node_or_null("PlayerSession")
	if config == null or gateway == null or network == null or player_session == null:
		_fail("required multiplayer autoloads are missing")
		return

	config.call("use_preset", "digital_ocean")
	var base_url := str(config.call("get_http_base_url"))
	var account_token := RemoteAccountCredentialStore.token_for(base_url)
	if account_token.is_empty():
		_fail("no cached account session for %s in slot %s" % [
			base_url,
			NetworkClientStorageScope.current_slot(),
		])
		return

	var roster := await _request_json(
		HTTPClient.METHOD_GET,
		base_url + "/v2/captains",
		PackedStringArray([
			"Accept: application/json",
			"Authorization: Account %s" % account_token,
		]),
	)
	if int(roster.get("status", 0)) != 200:
		_fail("captain roster request failed: HTTP %d" % int(roster.get("status", 0)))
		return
	var captains := (roster.get("body", {}) as Dictionary).get("captains", []) as Array
	if captains.is_empty():
		_fail("the cached account owns no captains")
		return
	var captain := captains[0] as Dictionary
	var captain_id := str(captain.get("id", "")).strip_edges()
	if captain_id.is_empty():
		_fail("server returned a captain without an id")
		return

	player_session.data.captain_id = captain_id
	player_session.data.account_id = str(
		RemoteAccountCredentialStore.account_for(base_url).get("id", "")
	)
	player_session.data.display_name = str(captain.get("display_name", "Smoke test captain"))
	var appearance_raw: Variant = JSON.parse_string(str(captain.get("appearance_json", "{}")))
	if appearance_raw is Dictionary:
		player_session.data.appearance = CharacterAppearance.from_dict(appearance_raw as Dictionary)

	_avatar = CharacterBody3D.new()
	_avatar.name = "RemoteRealtimeSmokeAvatar"
	_avatar.add_to_group("player")
	_avatar.position = _initial_position()
	_host.add_child(_avatar)

	gateway.authority_error.connect(func(code: String, message: String) -> void:
		_authority_error = "%s: %s" % [code, message]
	)
	gateway.call("begin_session", true)
	if not await _wait_until(func() -> bool: return bool(gateway.call("is_ready")), JOIN_TIMEOUT_S):
		_fail("authority join failed: %s" % (
			_authority_error if not _authority_error.is_empty() else "timeout"
		))
		return

	network.call("begin_multiplayer_session")
	if not bool(network.call("is_session_active")):
		_fail("UDP replication did not activate after authority acceptance")
		return

	var accepted := false
	var status_body: Dictionary = {}
	var deadline := Time.get_ticks_msec() + int(PRESENCE_TIMEOUT_S * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await create_timer(0.5, true, false, true).timeout
		var status := await _request_json(
			HTTPClient.METHOD_GET,
			base_url + "/v1/realtime-status",
			PackedStringArray(["Accept: application/json"]),
		)
		if int(status.get("status", 0)) != 200:
			continue
		status_body = status.get("body", {}) as Dictionary
		var world := status_body.get("realtime_world", {}) as Dictionary
		for player_variant in world.get("players", []) as Array:
			if str((player_variant as Dictionary).get("player_id", "")) == captain_id:
				accepted = true
				break
		if accepted:
			break

	if not accepted:
		network.call("end_multiplayer_session", false)
		gateway.call("stop_session")
		_fail("server accepted authority but never received this captain's UDP presence: %s" % JSON.stringify(status_body))
		return

	var target_position := _avatar.position + Vector3(37.0, 0.0, -19.0)
	_avatar.position = target_position
	var moved := false
	deadline = Time.get_ticks_msec() + int(MOVEMENT_TIMEOUT_S * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await create_timer(0.25, true, false, true).timeout
		var status := await _request_json(
			HTTPClient.METHOD_GET,
			base_url + "/v1/realtime-status",
			PackedStringArray(["Accept: application/json"]),
		)
		if int(status.get("status", 0)) != 200:
			continue
		status_body = status.get("body", {}) as Dictionary
		var world := status_body.get("realtime_world", {}) as Dictionary
		for entity_variant in world.get("entities", []) as Array:
			var entity := entity_variant as Dictionary
			if str(entity.get("id", "")) != captain_id:
				continue
			var position := entity.get("position", []) as Array
			if position.size() >= 3:
				var replicated := Vector3(
					float(position[0]),
					float(position[1]),
					float(position[2]),
				)
				if replicated.distance_to(target_position) < 0.1:
					moved = true
					break
		if moved:
			break

	var hold_seconds := _float_user_argument("--hold-seconds=", 0.0)
	if OS.get_cmdline_user_args().has("--expect-remote-profile"):
		var profile_result := await _verify_remote_profile(network, base_url, captain_id)
		if not bool(profile_result.get("ok", false)):
			network.call("end_multiplayer_session", false)
			gateway.call("stop_session")
			_fail("remote captain presentation failed: %s" % str(profile_result.get("message", "unknown failure")))
			return
	if hold_seconds > 0.0:
		await create_timer(hold_seconds, true, false, true).timeout

	network.call("end_multiplayer_session", false)
	await create_timer(0.25, true, false, true).timeout
	gateway.call("stop_session")
	if not moved:
		_fail("server received presence but not the captain's moved transform: %s" % JSON.stringify(status_body))
		return

	var transport := status_body.get("transport", {}) as Dictionary
	print(
		"Remote realtime smoke test passed: actor=%s datagrams=%d accepted=%d snapshots=%d entities=%d"
		% [
			captain_id,
			int(transport.get("datagrams_received", 0)),
			int(transport.get("updates_accepted", 0)),
			int(transport.get("snapshots_sent", 0)),
			int((status_body.get("realtime_world", {}) as Dictionary).get("entity_count", 0)),
		]
	)
	await _cleanup_and_quit(0)


func _verify_remote_profile(network: Node, base_url: String, local_captain_id: String) -> Dictionary:
	var expected_by_id: Dictionary = {}
	var deadline := Time.get_ticks_msec() + int(REMOTE_PROFILE_TIMEOUT_S * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await create_timer(0.1, true, false, true).timeout
		var drawing_service := network.get("drawing_service") as Node3D
		if drawing_service == null or not drawing_service.has_method("get_visible_entities"):
			continue
		var visible := drawing_service.call("get_visible_entities") as Dictionary
		for id_variant in visible.keys():
			var remote_id := str(id_variant)
			if remote_id == local_captain_id:
				continue
			var state := visible[id_variant] as Dictionary
			if str(state.get("type", "")) != "player":
				continue
			var remote_node := state.get("node", null) as Node3D
			if remote_node == null or not is_instance_valid(remote_node):
				continue
			if not expected_by_id.has(remote_id):
				var response := await _request_json(
					HTTPClient.METHOD_GET,
					base_url + "/v1/captains?id=%s" % remote_id.uri_encode(),
					PackedStringArray(["Accept: application/json"]),
				)
				if int(response.get("status", 0)) != 200:
					return {
						"ok": false,
						"message": "public captain lookup for %s returned HTTP %d" % [
							remote_id,
							int(response.get("status", 0)),
						],
					}
				expected_by_id[remote_id] = response.get("body", {}) as Dictionary
			var expected := expected_by_id[remote_id] as Dictionary
			var label := remote_node.get_node_or_null("PlayerNameLabel") as Label3D
			var body := remote_node.get_node_or_null("BodyMesh") as NpcBase
			if label == null or body == null:
				continue
			var expected_name := str(expected.get("display_name", "")).strip_edges()
			var expected_appearance_raw: Variant = JSON.parse_string(
				str(expected.get("appearance_json", "{}"))
			)
			if expected_appearance_raw is not Dictionary:
				return {"ok": false, "message": "public appearance for %s is invalid JSON" % remote_id}
			var expected_appearance := CharacterAppearance.from_dict(
				expected_appearance_raw as Dictionary
			)
			if label.text == expected_name \
					and body.appearance.to_json_string() == expected_appearance.to_json_string():
				print(
					"Remote captain presentation passed: actor=%s name=%s appearance=%s"
					% [
						remote_id,
						expected_name,
						expected_appearance.to_json_string().sha256_text().substr(0, 12),
					]
				)
				return {"ok": true}
	return {
		"ok": false,
		"message": "no remote player reached its server-authored name and appearance before timeout",
	}


func _wait_until(predicate: Callable, timeout_s: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout_s * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if bool(predicate.call()):
			return true
		await process_frame
	return bool(predicate.call())


func _request_json(method: HTTPClient.Method, url: String, headers: PackedStringArray) -> Dictionary:
	var request := HTTPRequest.new()
	request.timeout = 5.0
	_host.add_child(request)
	var error := request.request(url, headers, method)
	if error != OK:
		request.queue_free()
		return {"status": 0, "body": {}, "error": error_string(error)}
	var completed: Array = await request.request_completed
	request.queue_free()
	var body_bytes := completed[3] as PackedByteArray
	var parsed: Variant = JSON.parse_string(body_bytes.get_string_from_utf8())
	return {
		"result": int(completed[0]),
		"status": int(completed[1]),
		"body": parsed as Dictionary if parsed is Dictionary else {},
	}


func _initial_position() -> Vector3:
	var slot := NetworkClientStorageScope.current_slot()
	var offset := float(abs(slot.hash()) % 500)
	return Vector3(1000.0 + offset, 3.0, -2000.0 - offset)


func _float_user_argument(prefix: String, fallback: float) -> float:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with(prefix):
			return str(argument.trim_prefix(prefix)).to_float()
	return fallback


func _fail(message: String) -> void:
	var network := root.get_node_or_null("NetworkManager")
	if network != null:
		network.call("end_multiplayer_session", true)
	var gateway := root.get_node_or_null("WorldGateway")
	if gateway != null:
		gateway.call("stop_session")
	push_error("Remote realtime smoke test failed: %s" % message)
	call_deferred("_cleanup_and_quit", 1)


func _cleanup_and_quit(exit_code: int) -> void:
	if _host != null and is_instance_valid(_host):
		_host.queue_free()
	await process_frame
	await process_frame
	quit(exit_code)
