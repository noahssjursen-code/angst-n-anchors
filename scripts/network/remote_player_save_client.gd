class_name RemotePlayerSaveClient
extends RefCounted

## Revisioned multiplayer captain-document client.
##
## This transports PlayerData-compatible JSON but does not make it authoritative:
## server-owned identity, marks, vessels, and world projections replace matching
## document fields when PlayerSession hydrates. Saves are serialized so autosave
## and event-driven writes cannot race each other.

signal loaded(state: Dictionary, format_version: int, found: bool)
signal saved(revision: int)
signal save_conflict(current_revision: int)
signal request_failed(message: String)
signal authentication_required

var _host: Node = null
var _base_url := ""
var _captain_id := ""
var _account_id := ""
var _revision: int = 0
var _ready_to_save := false
var _loading := false
var _save_in_flight := false
var _pending_save: Dictionary = {}
var _outbox: Dictionary = {}


func setup(host: Node, base_url: String, captain_id: String, new_document: bool = false) -> void:
	_host = host
	_base_url = base_url.strip_edges().trim_suffix("/")
	_captain_id = captain_id.strip_edges()
	_account_id = str(RemoteAccountCredentialStore.account_for(_base_url).get("id", "")).strip_edges()
	_revision = 0
	_ready_to_save = new_document
	_loading = false
	_save_in_flight = false
	_pending_save.clear()
	_outbox = RemoteSaveOutbox.load_entry(_base_url, _account_id, _captain_id)


func is_ready() -> bool:
	return _ready_to_save and not _captain_id.is_empty()


func load_document() -> void:
	if _loading or _captain_id.is_empty():
		return
	_loading = true
	_request(
		HTTPClient.METHOD_GET,
		"/v2/captain-state?captain_id=%s" % _captain_id.uri_encode(),
		"",
		func(code: int, body: Variant) -> void:
			_loading = false
			if code == 404:
				_finish_document_load({}, 0, false)
				return
			if code == 401:
				_ready_to_save = false
				authentication_required.emit()
				return
			if code != 200 or body is not Dictionary:
				request_failed.emit(_message_from(body, "Captain progress could not be loaded."))
				return
			var document_raw: Variant = (body as Dictionary).get("document", {})
			if document_raw is not Dictionary:
				request_failed.emit("Server returned an invalid captain progress document.")
				return
			var document := document_raw as Dictionary
			var state_raw: Variant = document.get("state", {})
			if state_raw is not Dictionary:
				request_failed.emit("Captain progress state is not a JSON object.")
				return
			_finish_document_load(
				(state_raw as Dictionary).duplicate(true),
				int(document.get("format_version", 0)),
				true,
				maxi(int(document.get("revision", 0)), 0),
			)
	)


func queue_save(state: Dictionary, format_version: int) -> bool:
	if _captain_id.is_empty() or _account_id.is_empty() or state.is_empty() or format_version < 1:
		return false
	_pending_save = {
		"state": state.duplicate(true),
		"format_version": format_version,
	}
	if _outbox.is_empty():
		_outbox = {
			"base_revision": _revision,
			"sent_state": {},
		}
	_outbox["latest_state"] = state.duplicate(true)
	_outbox["format_version"] = format_version
	if not _persist_outbox():
		_pending_save.clear()
		return false
	_send_pending_save()
	return true


func _send_pending_save() -> void:
	if not _ready_to_save or _save_in_flight or _pending_save.is_empty():
		return
	var pending := _pending_save
	_pending_save = {}
	_save_in_flight = true
	_outbox["sent_state"] = (pending.get("state", {}) as Dictionary).duplicate(true)
	_outbox["sent_format_version"] = int(pending.get("format_version", PlayerSaveStore.SAVE_VERSION))
	if not _persist_outbox():
		_save_in_flight = false
		_restore_failed_save(pending)
		request_failed.emit("Captain progress could not be staged safely for upload.")
		return
	var body := {
		"contract_version": WorldContracts.VERSION,
		"captain_id": _captain_id,
		"expected_revision": _revision,
		"format_version": int(pending.get("format_version", PlayerSaveStore.SAVE_VERSION)),
		"state": pending.get("state", {}) as Dictionary,
	}
	_request(HTTPClient.METHOD_PUT, "/v2/captain-state", JSON.stringify(body), func(code: int, response: Variant) -> void:
		_save_in_flight = false
		if code == 401:
			_ready_to_save = false
			_restore_failed_save(pending)
			authentication_required.emit()
			return
		if code == 409:
			_ready_to_save = false
			_restore_failed_save(pending)
			var current := int((response as Dictionary).get("current_revision", 0)) if response is Dictionary else 0
			save_conflict.emit(current)
			return
		if code != 200 or response is not Dictionary:
			_restore_failed_save(pending)
			request_failed.emit(_message_from(response, "Captain progress could not be saved."))
			return
		var document_raw: Variant = (response as Dictionary).get("document", {})
		if document_raw is not Dictionary:
			_restore_failed_save(pending)
			request_failed.emit("Server returned an invalid save receipt.")
			return
		_revision = maxi(int((document_raw as Dictionary).get("revision", _revision)), _revision)
		if _pending_save.is_empty():
			RemoteSaveOutbox.remove_entry(_base_url, _account_id, _captain_id)
			_outbox.clear()
		else:
			_outbox["base_revision"] = _revision
			_outbox["sent_state"] = {}
			_outbox["latest_state"] = (_pending_save.get("state", {}) as Dictionary).duplicate(true)
			_outbox["format_version"] = int(_pending_save.get("format_version", PlayerSaveStore.SAVE_VERSION))
			_persist_outbox()
		saved.emit(_revision)
		_send_pending_save()
	, true)


func _restore_failed_save(failed: Dictionary) -> void:
	# A newer queued state always wins; otherwise retain the failed state for the
	# next autosave attempt without inventing a second revision.
	if _pending_save.is_empty():
		_pending_save = failed


func _finish_document_load(
	server_state: Dictionary,
	format_version: int,
	found: bool,
	server_revision: int = 0,
) -> void:
	_revision = maxi(server_revision, 0)
	_ready_to_save = true
	var effective_state := server_state.duplicate(true)
	var effective_format := format_version
	if not _outbox.is_empty():
		var base_revision := maxi(int(_outbox.get("base_revision", 0)), 0)
		var latest_raw: Variant = _outbox.get("latest_state", {})
		var sent_raw: Variant = _outbox.get("sent_state", {})
		var latest := (latest_raw as Dictionary).duplicate(true) if latest_raw is Dictionary else {}
		var sent := (sent_raw as Dictionary).duplicate(true) if sent_raw is Dictionary else {}
		if _revision == base_revision:
			_pending_save = {
				"state": latest,
				"format_version": int(_outbox.get("format_version", PlayerSaveStore.SAVE_VERSION)),
			}
			effective_state = latest
			effective_format = int(_outbox.get("format_version", format_version))
		elif _revision == base_revision + 1 and not sent.is_empty() and PlayerData.json_equivalent(server_state, sent):
			if PlayerData.json_equivalent(latest, sent):
				RemoteSaveOutbox.remove_entry(_base_url, _account_id, _captain_id)
				_outbox.clear()
			else:
				_outbox["base_revision"] = _revision
				_outbox["sent_state"] = {}
				_persist_outbox()
				_pending_save = {
					"state": latest,
					"format_version": int(_outbox.get("format_version", PlayerSaveStore.SAVE_VERSION)),
				}
				effective_state = latest
				effective_format = int(_outbox.get("format_version", format_version))
		else:
			_ready_to_save = false
			save_conflict.emit(_revision)
			return
	loaded.emit(effective_state, effective_format, found or not effective_state.is_empty())
	_send_pending_save()


func _persist_outbox() -> bool:
	return RemoteSaveOutbox.save_entry(_base_url, _account_id, _captain_id, _outbox)


func _request(method: int, path: String, body: String, on_done: Callable, json_body: bool = false) -> void:
	if _host == null or not is_instance_valid(_host) or _base_url.is_empty():
		on_done.call(-1, null)
		return
	var token := RemoteAccountCredentialStore.token_for(_base_url)
	if token.is_empty():
		on_done.call(401, {})
		return
	var request := HTTPRequest.new()
	_host.add_child(request)
	request.timeout = 10.0
	request.request_completed.connect(func(result: int, response_code: int, _headers: PackedStringArray, bytes: PackedByteArray) -> void:
		request.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS:
			on_done.call(-1, null)
			return
		var text := bytes.get_string_from_utf8()
		var parsed: Variant = JSON.parse_string(text) if not text.is_empty() else {}
		on_done.call(response_code, parsed)
	)
	var headers := PackedStringArray(["Accept: application/json", "Authorization: Account %s" % token])
	if json_body:
		headers.append("Content-Type: application/json")
	var error := request.request("%s%s" % [_base_url, path], headers, method, body)
	if error != OK:
		request.queue_free()
		on_done.call(-1, null)


static func _message_from(body: Variant, fallback: String) -> String:
	if body is Dictionary:
		var message := str((body as Dictionary).get("error", "")).strip_edges()
		if not message.is_empty():
			return message
	return fallback
