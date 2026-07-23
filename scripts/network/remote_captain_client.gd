class_name RemoteCaptainClient
extends RefCounted

## Account-authenticated multiplayer identity client. Accounts own captains;
## captains are playable personas, not login credentials.

signal account_changed(account: Dictionary)
signal auth_required
signal captains_listed(captains: Array)
signal captain_fetched(captain: Dictionary)
signal captain_fetch_failed(captain_id: String)
signal captain_created(captain: Dictionary)
signal captain_deleted(captain_id: String)
signal captain_updated(captain: Dictionary)
signal world_options_ready(options: Dictionary)
signal request_failed(action: String, message: String)

var _host: Node = null
var _base_url: String = ""
var _account: Dictionary = {}


func setup(host: Node, base_url: String) -> void:
	_host = host
	_base_url = base_url.trim_suffix("/")
	_account = RemoteAccountCredentialStore.account_for(_base_url)


func set_base_url(base_url: String) -> void:
	_base_url = base_url.trim_suffix("/")
	_account = RemoteAccountCredentialStore.account_for(_base_url)


func has_account_session() -> bool:
	return RemoteAccountCredentialStore.has_session(_base_url)


func current_account() -> Dictionary:
	return _account.duplicate(true)


func register_account(email: String, password: String) -> void:
	_authenticate("register", "/v2/accounts/register", email, password, 201)


func login(email: String, password: String) -> void:
	_authenticate("login", "/v2/accounts/login", email, password, 200)


func validate_session() -> void:
	if not has_account_session():
		_account.clear()
		auth_required.emit()
		return
	_request(HTTPClient.METHOD_GET, "/v2/accounts/me", "", func(code: int, body: Variant) -> void:
		if code == 401:
			_expire_session()
			return
		if code != 200 or body is not Dictionary:
			# A temporary outage must not erase a still-valid 30-day session. Keep
			# the token so the player can retry when the server is reachable again.
			request_failed.emit("account", _message_from(body, "The account server is unavailable."))
			return
		var account := (body as Dictionary).get("account", {}) as Dictionary
		if account.is_empty():
			_expire_session()
			return
		_account = account.duplicate(true)
		RemoteAccountCredentialStore.update_account(_base_url, _account)
		account_changed.emit(current_account())
		list_captains()
	, true)


func logout() -> void:
	if not has_account_session():
		_expire_session()
		return
	_request(HTTPClient.METHOD_DELETE, "/v2/accounts/session", "", func(_code: int, _body: Variant) -> void:
		# Local logout must succeed even if the server is unreachable. The
		# server-side token expires and can also be revoked on the next login.
		_expire_session()
	, true)


func list_captains() -> void:
	if not _require_session():
		return
	_request(HTTPClient.METHOD_GET, "/v2/captains", "", func(code: int, body: Variant) -> void:
		if code != 200 or body is not Dictionary:
			_handle_authenticated_failure(code, "list", body)
			return
		captains_listed.emit(((body as Dictionary).get("captains", []) as Array).duplicate(true))
	, true)


func fetch_captain(captain_id: String) -> void:
	var id := captain_id.strip_edges()
	if id.is_empty():
		request_failed.emit("fetch", "Captain id is required.")
		captain_fetch_failed.emit(captain_id)
		return
	# Remote-player presentation is intentionally public and read-only. The
	# authenticated /v2 endpoint only exposes captains owned by this account,
	# so using it here made every other player's name and outfit silently fall
	# back to the defaults.
	_request(HTTPClient.METHOD_GET, "/v1/captains?id=%s" % id.uri_encode(), "", func(code: int, body: Variant) -> void:
		if code != 200 or body is not Dictionary:
			captain_fetch_failed.emit(id)
			request_failed.emit("fetch", _message_from(body, "Could not load the captain's public presentation."))
			return
		var captain := body as Dictionary
		if str(captain.get("id", "")).strip_edges() != id:
			captain_fetch_failed.emit(id)
			request_failed.emit("fetch", "Captain presentation did not match the requested id.")
			return
		captain_fetched.emit(captain)
	)


func create_captain(display_name: String, appearance: CharacterAppearance) -> void:
	if not _require_session():
		return
	var app_dict: Dictionary = appearance.to_dict() if appearance != null else {}
	_post("/v2/captains", {
		"contract_version": WorldContracts.VERSION,
		"display_name": display_name,
		"appearance_json": JSON.stringify(app_dict),
	}, func(code: int, body: Variant) -> void:
		if code != 201 or body is not Dictionary:
			_handle_authenticated_failure(code, "create", body)
			return
		var captain := (body as Dictionary).get("captain", {}) as Dictionary
		if captain.is_empty():
			request_failed.emit("create", "Server returned an invalid captain.")
			return
		captain_created.emit(captain)
	)


func update_captain(captain_id: String, display_name: String, appearance: CharacterAppearance) -> void:
	if not _require_session():
		return
	_put("/v2/captains", {
		"contract_version": WorldContracts.VERSION,
		"id": captain_id.strip_edges(),
		"display_name": display_name.strip_edges(),
		"appearance_json": JSON.stringify(appearance.to_dict() if appearance != null else {}),
	}, func(code: int, body: Variant) -> void:
		if code != 200 or body is not Dictionary:
			_handle_authenticated_failure(code, "update", body)
			return
		captain_updated.emit((body as Dictionary).get("captain", {}) as Dictionary)
	)


func delete_captain(captain_id: String) -> void:
	var id := captain_id.strip_edges()
	if not _require_session():
		return
	_request(HTTPClient.METHOD_DELETE, "/v2/captains?id=%s" % id.uri_encode(), "", func(code: int, body: Variant) -> void:
		if code != 200:
			_handle_authenticated_failure(code, "delete", body)
			return
		captain_deleted.emit(id)
	, true)


func fetch_world_options() -> void:
	_request(HTTPClient.METHOD_GET, "/v1/world-options", "", func(code: int, body: Variant) -> void:
		if code != 200 or body is not Dictionary:
			request_failed.emit("world_options", _message_from(body, "Failed to load world options."))
			return
		world_options_ready.emit(body as Dictionary)
	)


func parse_appearance(raw: Variant) -> CharacterAppearance:
	if raw is Dictionary:
		return CharacterAppearance.from_dict(raw as Dictionary)
	if raw is String:
		var text := str(raw)
		if not text.is_empty():
			var parsed: Variant = JSON.parse_string(text)
			if parsed is Dictionary:
				return CharacterAppearance.from_dict(parsed as Dictionary)
	return CharacterAppearance.default_appearance()


func _authenticate(action: String, path: String, email: String, password: String, expected_code: int) -> void:
	var normalized_email := email.strip_edges()
	if normalized_email.is_empty() or password.is_empty():
		request_failed.emit(action, "Email and password are required.")
		return
	_request(HTTPClient.METHOD_POST, path, JSON.stringify({"email": normalized_email, "password": password}), func(code: int, body: Variant) -> void:
		if code != expected_code or body is not Dictionary:
			request_failed.emit(action, _authentication_error_message(code, body))
			return
		var payload := body as Dictionary
		var account := payload.get("account", {}) as Dictionary
		var token := str(payload.get("access_token", ""))
		if account.is_empty() or not RemoteAccountCredentialStore.set_session(_base_url, token, account):
			request_failed.emit(action, "Signed in, but the account session could not be saved on this device.")
			return
		_account = account.duplicate(true)
		account_changed.emit(current_account())
		list_captains()
	, false, true)


func _post(path: String, body: Dictionary, on_done: Callable) -> void:
	_request(HTTPClient.METHOD_POST, path, JSON.stringify(body), on_done, true, true)


func _put(path: String, body: Dictionary, on_done: Callable) -> void:
	_request(HTTPClient.METHOD_PUT, path, JSON.stringify(body), on_done, true, true)


func _request(
	method: int,
	path: String,
	body: String,
	on_done: Callable,
	authenticated: bool = false,
	json_body: bool = false,
) -> void:
	if _host == null or not is_instance_valid(_host):
		request_failed.emit("request", "HTTP host missing.")
		return
	if _base_url.is_empty():
		request_failed.emit("request", "Server URL missing.")
		return
	var req := HTTPRequest.new()
	_host.add_child(req)
	req.timeout = 8.0
	req.request_completed.connect(func(result: int, response_code: int, _headers: PackedStringArray, response_body: PackedByteArray) -> void:
		req.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS:
			on_done.call(-1, null)
			return
		var text := response_body.get_string_from_utf8()
		var parsed: Variant = JSON.parse_string(text) if not text.is_empty() else {}
		on_done.call(response_code, parsed)
	)
	var headers := PackedStringArray(["Accept: application/json"])
	if json_body:
		headers.append("Content-Type: application/json")
	if authenticated:
		var token := RemoteAccountCredentialStore.token_for(_base_url)
		if token.is_empty():
			_expire_session()
			req.queue_free()
			return
		headers.append("Authorization: Account %s" % token)
	var err := req.request("%s%s" % [_base_url, path], headers, method, body)
	if err != OK:
		req.queue_free()
		on_done.call(-1, null)


func _require_session() -> bool:
	if has_account_session():
		return true
	_expire_session()
	return false


func _handle_authenticated_failure(code: int, action: String, body: Variant) -> void:
	if code == 401:
		_expire_session()
		return
	request_failed.emit(action, _message_from(body, "Server request failed."))


func _expire_session() -> void:
	RemoteAccountCredentialStore.clear_session(_base_url)
	_account.clear()
	captains_listed.emit([])
	account_changed.emit({})
	auth_required.emit()


static func _message_from(body: Variant, fallback: String) -> String:
	if body is Dictionary:
		var message := str((body as Dictionary).get("error", "")).strip_edges()
		if not message.is_empty():
			return message
	return fallback


static func _authentication_error_message(code: int, body: Variant) -> String:
	var server_message := _message_from(body, "")
	if not server_message.is_empty():
		return server_message
	match code:
		-1:
			return "Could not reach the account server."
		404:
			return "This server does not support account login yet. The server must be updated."
		429:
			return "Too many login attempts. Wait a moment and try again."
		500, 502, 503, 504:
			return "The account service is temporarily unavailable."
		_:
			return "Email or password was not accepted."
