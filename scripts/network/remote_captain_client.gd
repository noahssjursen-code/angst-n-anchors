class_name RemoteCaptainClient
extends RefCounted

## Thin HTTP client for /v1/captains and /v1/world-options.
## One host Node owns transient HTTPRequest children.

signal captains_listed(captains: Array)
signal captain_created(captain: Dictionary)
signal captain_deleted(captain_id: String)
signal captain_updated(captain: Dictionary)
signal world_options_ready(options: Dictionary)
signal request_failed(action: String, message: String)

var _host: Node = null
var _base_url: String = ""


func setup(host: Node, base_url: String) -> void:
	_host = host
	_base_url = base_url.rstrip("/")


func set_base_url(base_url: String) -> void:
	_base_url = base_url.rstrip("/")


func list_captains() -> void:
	_http_get("/v1/captains", func(code: int, body: Variant) -> void:
		if code != 200 or typeof(body) != TYPE_ARRAY:
			request_failed.emit("list", "Failed to load captains.")
			return
		captains_listed.emit(body as Array)
	)


func create_captain(display_name: String, appearance: CharacterAppearance) -> void:
	var app_dict: Dictionary = appearance.to_dict() if appearance != null else {}
	_post("/v1/captains", {
		"display_name": display_name,
		"appearance_json": JSON.stringify(app_dict),
	}, func(code: int, body: Variant) -> void:
		if code != 200 or typeof(body) != TYPE_DICTIONARY:
			request_failed.emit("create", "Failed to create captain.")
			return
		captain_created.emit(body as Dictionary)
	)


func delete_captain(captain_id: String) -> void:
	var id := captain_id.strip_edges()
	_request(HTTPClient.METHOD_DELETE, "/v1/captains?id=%s" % id, "", func(code: int, _body: Variant) -> void:
		if code != 200:
			request_failed.emit("delete", "Failed to delete captain.")
			return
		captain_deleted.emit(id)
	)


func update_marks(captain_id: String, marks: int) -> void:
	_put("/v1/captains", {
		"id": captain_id,
		"marks": marks,
	}, func(code: int, body: Variant) -> void:
		if code != 200 or typeof(body) != TYPE_DICTIONARY:
			request_failed.emit("update", "Failed to update captain.")
			return
		captain_updated.emit(body as Dictionary)
	)


func fetch_world_options() -> void:
	_http_get("/v1/world-options", func(code: int, body: Variant) -> void:
		if code != 200 or typeof(body) != TYPE_DICTIONARY:
			request_failed.emit("world_options", "Failed to load world options.")
			return
		world_options_ready.emit(body as Dictionary)
	)


func parse_appearance(raw: Variant) -> CharacterAppearance:
	if typeof(raw) == TYPE_DICTIONARY:
		return CharacterAppearance.from_dict(raw as Dictionary)
	if typeof(raw) == TYPE_STRING:
		var text := str(raw)
		if text.is_empty():
			return CharacterAppearance.default_appearance()
		var parsed: Variant = JSON.parse_string(text)
		if typeof(parsed) == TYPE_DICTIONARY:
			return CharacterAppearance.from_dict(parsed as Dictionary)
	return CharacterAppearance.default_appearance()


func _http_get(path: String, on_done: Callable) -> void:
	_request(HTTPClient.METHOD_GET, path, "", on_done)


func _post(path: String, body: Dictionary, on_done: Callable) -> void:
	_request(HTTPClient.METHOD_POST, path, JSON.stringify(body), on_done, true)


func _put(path: String, body: Dictionary, on_done: Callable) -> void:
	_request(HTTPClient.METHOD_PUT, path, JSON.stringify(body), on_done, true)


func _request(
	method: int,
	path: String,
	body: String,
	on_done: Callable,
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
		var parsed: Variant = null
		if not text.is_empty():
			parsed = JSON.parse_string(text)
		on_done.call(response_code, parsed)
	)
	var headers := PackedStringArray()
	if json_body:
		headers.append("Content-Type: application/json")
	var err := req.request("%s%s" % [_base_url, path], headers, method, body)
	if err != OK:
		req.queue_free()
		on_done.call(-1, null)
