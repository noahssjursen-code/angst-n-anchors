extends Node

## Autoload — register as "AuthSession".
## Holds the logged-in user's email/password session for the multiplayer server.
##
## The token is a stateless HMAC string signed by the Go server (see
## internal/auth/auth.go). We persist it to disk so login survives restarts.
## All HTTP calls into account-scoped endpoints (/v1/captains, /v1/vessels, …)
## must send `auth_headers()`.

signal authenticated()
signal logged_out()

const CONFIG_PATH := "user://auth_session.cfg"

var auth_token: String = ""
var user_id: String = ""
var email: String = ""
var is_admin: bool = false


func _ready() -> void:
	_load_from_disk()


func is_authenticated() -> bool:
	return not auth_token.is_empty() and not user_id.is_empty()


func auth_headers(content_type: String = "application/json") -> PackedStringArray:
	var headers := PackedStringArray()
	if not content_type.is_empty():
		headers.append("Content-Type: " + content_type)
	if not auth_token.is_empty():
		headers.append("Authorization: Bearer " + auth_token)
	return headers


## Calls POST /v1/auth/login. on_complete(success: bool, error: String) is invoked once.
func login(email_in: String, password: String, on_complete: Callable = Callable()) -> void:
	_post_credentials("login", email_in, password, on_complete)


## Calls POST /v1/auth/register. Same callback shape as login().
func register(email_in: String, password: String, on_complete: Callable = Callable()) -> void:
	_post_credentials("register", email_in, password, on_complete)


func logout() -> void:
	auth_token = ""
	user_id = ""
	email = ""
	is_admin = false
	_save_to_disk()
	logged_out.emit()


func _post_credentials(endpoint: String, email_in: String, password: String, on_complete: Callable) -> void:
	var base := _http_base()
	if base.is_empty():
		_finish(on_complete, false, "no server selected")
		return
	var url := "%s/v1/auth/%s" % [base, endpoint]
	var body := JSON.stringify({"email": email_in, "password": password})

	var req := HTTPRequest.new()
	add_child(req)
	req.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, resp: PackedByteArray) -> void:
		req.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS:
			_finish(on_complete, false, "network error (%d)" % result)
			return
		var parsed: Variant = JSON.parse_string(resp.get_string_from_utf8())
		if code != 200:
			var msg := "HTTP %d" % code
			if typeof(parsed) == TYPE_DICTIONARY:
				msg = str((parsed as Dictionary).get("error", msg))
			_finish(on_complete, false, msg)
			return
		if typeof(parsed) != TYPE_DICTIONARY:
			_finish(on_complete, false, "malformed response")
			return
		var d := parsed as Dictionary
		auth_token = str(d.get("token", ""))
		user_id = str(d.get("user_id", ""))
		email = str(d.get("email", email_in))
		is_admin = bool(d.get("is_admin", false))
		if auth_token.is_empty() or user_id.is_empty():
			_finish(on_complete, false, "missing token in response")
			return
		_save_to_disk()
		authenticated.emit()
		_finish(on_complete, true, "")
	)
	var headers := PackedStringArray(["Content-Type: application/json"])
	req.request(url, headers, HTTPClient.METHOD_POST, body)


## Fetches /v1/auth/me. on_complete(success: bool, captains: Array) is invoked.
## On 401, the local session is cleared automatically.
func fetch_me(on_complete: Callable = Callable()) -> void:
	if not is_authenticated():
		if on_complete.is_valid():
			on_complete.call(false, [])
		return
	var base := _http_base()
	if base.is_empty():
		if on_complete.is_valid():
			on_complete.call(false, [])
		return

	var url := "%s/v1/auth/me" % base
	var req := HTTPRequest.new()
	add_child(req)
	req.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, resp: PackedByteArray) -> void:
		req.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS or code == 401:
			if code == 401:
				logout()
			if on_complete.is_valid():
				on_complete.call(false, [])
			return
		if code != 200:
			if on_complete.is_valid():
				on_complete.call(false, [])
			return
		var parsed: Variant = JSON.parse_string(resp.get_string_from_utf8())
		if typeof(parsed) != TYPE_DICTIONARY:
			if on_complete.is_valid():
				on_complete.call(false, [])
			return
		var d := parsed as Dictionary
		email = str(d.get("email", email))
		is_admin = bool(d.get("is_admin", is_admin))
		var caps_raw: Variant = d.get("captains", [])
		var caps: Array = caps_raw if typeof(caps_raw) == TYPE_ARRAY else []
		if on_complete.is_valid():
			on_complete.call(true, caps)
	)
	req.request(url, auth_headers(""))


func _finish(cb: Callable, ok: bool, msg: String) -> void:
	if cb.is_valid():
		cb.call(ok, msg)


func _http_base() -> String:
	var config := get_node_or_null("/root/ServerConfig") as Node
	if config == null:
		return ""
	return str(config.call("get_http_base_url"))


func _save_to_disk() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("auth", "token", auth_token)
	cfg.set_value("auth", "user_id", user_id)
	cfg.set_value("auth", "email", email)
	cfg.set_value("auth", "is_admin", is_admin)
	cfg.save(CONFIG_PATH)


func _load_from_disk() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return
	auth_token = str(cfg.get_value("auth", "token", ""))
	user_id = str(cfg.get_value("auth", "user_id", ""))
	email = str(cfg.get_value("auth", "email", ""))
	is_admin = bool(cfg.get_value("auth", "is_admin", false))
