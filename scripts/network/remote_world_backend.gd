class_name RemoteWorldBackend
extends WorldBackend

## Reliable remote authority transport. The long-poll implementation is hidden
## behind WorldBackend so it can be replaced by WebSocket without touching game
## systems or their command/event contracts.

var base_url := ""
var _session: Dictionary = {}
var _event_cursor := 0
var _poll_active := false
var _poll_in_flight := false
var _generation := 0
var _desired_interests := PackedStringArray(["global"])
var _interest_request_in_flight := false
var _interest_dirty := false
## Bumped every time the server confirms an interest change. Event polls issued
## under an older epoch must not fast-forward the cursor past events the server
## filtered out under the stale scopes — see _on_event_page.
var _interest_epoch := 0


func configure(url: String) -> void:
	base_url = url.trim_suffix("/")


func start_session(actor_id: String, display_name: String, world_checksum: String, account_token: String = "") -> void:
	_generation += 1
	_poll_active = false
	_session.clear()
	var body := {
		"contract_version": WorldContracts.VERSION,
		"actor_id": actor_id.strip_edges(),
		"display_name": display_name.strip_edges(),
		"world_checksum": world_checksum.strip_edges(),
	}
	_request_json(HTTPClient.METHOD_POST, "/v2/sessions", body, false, _on_session_response, 8.0, account_token)


func stop_session() -> void:
	_generation += 1
	_poll_active = false
	var closing_token := session_token()
	if not closing_token.is_empty():
		_request_detached_session_close(closing_token)
	_session.clear()
	session_ended.emit()


func session_token() -> String:
	return str(_session.get("session_token", ""))


## Interest scopes the server has confirmed for this session. Updated after
## every accepted interest sync, so callers can await scope activation before
## triggering actions whose events they must not miss.
func session_interests() -> Array:
	return (_session.get("interests", []) as Array).duplicate()


func is_ready() -> bool:
	return not session_token().is_empty()


func send_command(command: Dictionary) -> void:
	if not is_ready():
		command_finished.emit(WorldContracts.result_error(str(command.get("request_id", "")), "session_invalid", "Remote authority session is not ready."))
		return
	_request_json(HTTPClient.METHOD_POST, "/v2/commands", command, true, _on_command_response, 8.0)


func query_projections(kind: String = "", id: String = "") -> void:
	if not is_ready():
		return
	var query: Array[String] = []
	if not kind.is_empty():
		query.append("kind=%s" % kind.uri_encode())
	if not id.is_empty():
		query.append("id=%s" % id.uri_encode())
	var path := "/v2/projections"
	if not query.is_empty():
		path += "?" + "&".join(query)
	_request_json(HTTPClient.METHOD_GET, path, {}, true, _on_projection_response, 8.0)


func set_interests(scopes: PackedStringArray) -> void:
	_desired_interests = scopes.duplicate()
	if not _desired_interests.has("global"):
		_desired_interests.append("global")
	_desired_interests.sort()
	_interest_dirty = true
	_sync_interests()


func _on_session_response(response: Dictionary) -> void:
	if not bool(response.get("transport_ok", false)):
		transport_failed.emit("session_transport_failed", str(response.get("message", "Could not open authority session.")))
		return
	var payload := response.get("payload", {}) as Dictionary
	if int(payload.get("contract_version", 0)) != WorldContracts.VERSION:
		transport_failed.emit("contract_version_unsupported", "Client and server world contracts do not match.")
		return
	_session = payload.duplicate(true)
	_event_cursor = int(_session.get("event_cursor", 0))
	_poll_active = true
	session_started.emit(_session.duplicate(true))
	_interest_dirty = true
	_sync_interests()
	_poll_events_deferred(_generation)


func _sync_interests() -> void:
	if not is_ready() or _interest_request_in_flight or not _interest_dirty:
		return
	_interest_dirty = false
	_interest_request_in_flight = true
	_request_json(
		HTTPClient.METHOD_PUT,
		"/v2/sessions",
		{"contract_version": WorldContracts.VERSION, "scopes": Array(_desired_interests)},
		true,
		_on_interest_response,
		5.0,
	)


func _on_interest_response(response: Dictionary) -> void:
	_interest_request_in_flight = false
	if not bool(response.get("transport_ok", false)):
		transport_failed.emit("interest_transport_failed", str(response.get("message", "Could not update world interests.")))
	else:
		var payload := response.get("payload", {}) as Dictionary
		if not payload.is_empty():
			_session["interests"] = (payload.get("interests", []) as Array).duplicate()
		_interest_epoch += 1
		## A newly loaded scope may already contain durable state that predates
		## this session. Rehydrate it once after the server accepts the interest.
		query_projections()
	if _interest_dirty:
		_sync_interests()


func _on_command_response(response: Dictionary) -> void:
	var payload := response.get("payload", {}) as Dictionary
	if payload.is_empty():
		payload = WorldContracts.result_error("", "transport_failed", str(response.get("message", "Authority command failed.")))
	command_finished.emit(payload)


func _on_projection_response(response: Dictionary) -> void:
	if not bool(response.get("transport_ok", false)):
		transport_failed.emit("projection_transport_failed", str(response.get("message", "Projection query failed.")))
		return
	var payload := response.get("payload", {}) as Dictionary
	projections_received.emit((payload.get("projections", []) as Array).duplicate(true))


func _poll_events_deferred(generation: int) -> void:
	if generation != _generation or not _poll_active:
		return
	call_deferred("_poll_events", generation)


func _poll_events(generation: int) -> void:
	if generation != _generation or not _poll_active or _poll_in_flight or not is_ready():
		return
	_poll_in_flight = true
	if OS.has_environment("MP_BACKEND_DEBUG"):
		print("[backend %s] poll after=%d epoch=%d" % [get_parent().name if get_parent() != null else "?", _event_cursor, _interest_epoch])
	var epoch := _interest_epoch
	var path := "/v2/events?after=%d&limit=128&wait_ms=1500" % _event_cursor
	_request_json(
		HTTPClient.METHOD_GET,
		path,
		{},
		true,
		func(response: Dictionary): _on_event_page(response, generation, epoch),
		4.0,
	)


func _on_event_page(response: Dictionary, generation: int, epoch: int = -1) -> void:
	_poll_in_flight = false
	if generation != _generation or not _poll_active:
		return
	if OS.has_environment("MP_BACKEND_DEBUG"):
		print("[backend %s] page ok=%s status=%d events=%d next=%s stale_epoch=%s" % [
			get_parent().name if get_parent() != null else "?",
			response.get("transport_ok"), int(response.get("status", 0)),
			((response.get("payload", {}) as Dictionary).get("events", []) as Array).size(),
			str((response.get("payload", {}) as Dictionary).get("next_cursor", "?")),
			epoch != _interest_epoch,
		])
	if bool(response.get("transport_ok", false)):
		var payload := response.get("payload", {}) as Dictionary
		for event_variant in payload.get("events", []) as Array:
			var event := event_variant as Dictionary
			var cursor := int(event.get("cursor", 0))
			if cursor <= _event_cursor:
				continue
			_event_cursor = cursor
			event_received.emit(event.duplicate(true))
		## A poll issued before the latest confirmed interest change scanned the
		## log under stale scopes: events it filtered out may be visible under
		## the new scopes. Advancing only past *delivered* events (above) and
		## skipping the fast-forward makes the next poll rescan that window —
		## events are cursor-replayable, so nothing is lost and nothing repeats.
		if epoch == _interest_epoch:
			_event_cursor = maxi(_event_cursor, int(payload.get("next_cursor", _event_cursor)))
		_poll_events_deferred(generation)
		return
	if int(response.get("status", 0)) == 401:
		transport_failed.emit("session_invalid", "Remote authority session expired.")
		_poll_active = false
		return
	var tree := get_tree()
	if tree == null:
		return
	await tree.create_timer(0.75, true, false, true).timeout
	_poll_events_deferred(generation)


func _request_json(
		method: HTTPClient.Method,
		path: String,
		body: Dictionary,
		authenticated: bool,
		callback: Callable,
	timeout_s: float,
	account_token: String = "",
) -> void:
	if base_url.is_empty():
		if callback.is_valid():
			callback.call({"transport_ok": false, "status": 0, "message": "Server URL is empty.", "payload": {}})
		return
	var request := HTTPRequest.new()
	request.timeout = timeout_s
	add_child(request)
	request.request_completed.connect(_on_http_completed.bind(request, callback), CONNECT_ONE_SHOT)
	var headers := PackedStringArray(["Accept: application/json", "Content-Type: application/json"])
	if authenticated:
		headers.append("Authorization: Bearer %s" % session_token())
	elif not account_token.is_empty():
		headers.append("Authorization: Account %s" % account_token)
	var encoded := JSON.stringify(body) if method != HTTPClient.METHOD_GET and method != HTTPClient.METHOD_DELETE else ""
	var error := request.request(base_url + path, headers, method, encoded)
	if error != OK:
		request.queue_free()
		if callback.is_valid():
			callback.call({"transport_ok": false, "status": 0, "message": error_string(error), "payload": {}})


## Session shutdown must outlive this backend. WorldGateway deliberately frees
## the backend immediately after stop_session(), so parenting this DELETE below
## the backend used to cancel it and leak the authority session until expiry.
func _request_detached_session_close(closing_token: String) -> void:
	var tree := get_tree()
	if tree == null or base_url.is_empty():
		return
	var request := HTTPRequest.new()
	request.name = "AuthoritySessionClose"
	request.timeout = 4.0
	tree.root.add_child(request)
	request.request_completed.connect(request.queue_free.unbind(4), CONNECT_ONE_SHOT)
	var headers := PackedStringArray([
		"Accept: application/json",
		"Authorization: Bearer %s" % closing_token,
	])
	var error := request.request(
		base_url + "/v2/sessions",
		headers,
		HTTPClient.METHOD_DELETE,
	)
	if error != OK:
		request.queue_free()


func _on_http_completed(
		result: int,
		response_code: int,
		_headers: PackedStringArray,
		body: PackedByteArray,
		request: HTTPRequest,
		callback: Callable,
) -> void:
	if is_instance_valid(request):
		request.queue_free()
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8()) if not body.is_empty() else {}
	var payload := parsed as Dictionary if parsed is Dictionary else {}
	var ok := result == HTTPRequest.RESULT_SUCCESS and response_code >= 200 and response_code < 300
	var message := str(payload.get("error", ""))
	if message.is_empty() and not ok:
		message = "HTTP %d (transport %d)" % [response_code, result]
	if callback.is_valid():
		callback.call({"transport_ok": ok, "status": response_code, "message": message, "payload": payload})
