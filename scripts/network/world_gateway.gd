extends Node

## Public multiplayer seam for gameplay systems.
##
## Commands express intent. Events are authoritative facts. Projections are
## queryable current state. High-frequency transforms remain in NetworkManager.

signal session_ready(remote: bool, session: Dictionary)
signal session_closed
signal command_completed(request_id: String, result: Dictionary)
signal world_event(event: Dictionary)
signal projection_changed(kind: String, id: String, projection: Dictionary)
signal authority_error(code: String, message: String)

const LocalBackendClass = preload("res://scripts/network/local_world_backend.gd")
const RemoteBackendClass = preload("res://scripts/network/remote_world_backend.gd")

var _backend: WorldBackend = null
var _remote := false
## Optional connection override for gateway instances that are not the process
## autoload — test harness virtual clients and future dedicated workers. When
## set, remote sessions use these instead of ServerConfig and the process-global
## credential store, letting several fully independent gateways coexist.
var _override_base_url := ""
var _override_account_token := ""
var _store := WorldProjectionStore.new()
var _subscriptions: Dictionary = {} ## event type -> [{owner, callback}]
var _request_counter := 0
var _session: Dictionary = {}
## scope -> {"owners": {instance_id: true}, "anonymous": int}. Keeping the
## caller identity prevents repeated streaming/setup callbacks from leaking an
## interest forever or releasing another system's interest accidentally.
var _interest_references: Dictionary = {
	"global": {"owners": {"gateway": true}, "anonymous": 0},
}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_store.changed.connect(_on_projection_changed)


func begin_session(multiplayer: bool) -> void:
	var actor := str(LocalPlayerView.get_network_player_id()).strip_edges()
	var display_name := str(LocalPlayerView.get_display_name()).strip_edges()
	var world_context := LocalPlayerView.get_world_context() as Dictionary
	begin_session_with_identity(multiplayer, actor, display_name, str(world_context.get("layout_checksum", "")))


## Explicit identity entry point used by isolated showcases, headless tests, and
## future dedicated-server workers. Normal gameplay should use begin_session().
func begin_session_with_identity(
		multiplayer: bool,
		actor: String,
		display_name: String = "",
		world_checksum: String = "",
) -> void:
	if ShipyardPlaytestMode.active():
		return
	stop_session()
	var normalized_actor := actor.strip_edges()
	if normalized_actor.is_empty():
		var message := "Selected captain identity is not ready."
		push_error("[WorldGateway] Refusing to open a world session without a captain identity.")
		authority_error.emit("captain_identity_missing", message)
		return
	_remote = multiplayer
	_backend = RemoteBackendClass.new() if multiplayer else LocalBackendClass.new()
	_backend.name = "RemoteWorldBackend" if multiplayer else "LocalWorldBackend"
	add_child(_backend)
	_backend.session_started.connect(_on_session_started)
	_backend.session_ended.connect(_on_session_ended)
	_backend.command_finished.connect(_on_command_finished)
	_backend.event_received.connect(_on_world_event)
	_backend.projections_received.connect(_on_projections_received)
	_backend.transport_failed.connect(_on_transport_failed)
	var base_url := _override_base_url if not _override_base_url.is_empty() else ServerConfig.get_http_base_url()
	if multiplayer:
		(_backend as RemoteWorldBackend).configure(base_url)
	var account_token := ""
	if multiplayer:
		account_token = _override_account_token
		if account_token.is_empty():
			account_token = RemoteAccountCredentialStore.token_for(base_url)
		if account_token.is_empty():
			push_error("[WorldGateway] No account credential is available for %s." % base_url)
			authority_error.emit("account_session_missing", "Sign in to this server before joining shared waters.")
			_backend.queue_free()
			_backend = null
			_remote = false
			return
		print(
			"[WorldGateway] Opening authority session actor=%s server=%s"
			% [normalized_actor, base_url]
		)
	_backend.start_session(normalized_actor, display_name.strip_edges(), world_checksum.strip_edges(), account_token)


func stop_session() -> void:
	if _backend != null and is_instance_valid(_backend):
		_backend.stop_session()
		_backend.queue_free()
	_backend = null
	_session.clear()
	_store.clear()
	_remote = false


## Points this gateway instance at a specific server and account credential.
## Call before begin_session_with_identity. The process autoload never needs
## this; it exists so tests and workers can run isolated gateway instances.
func set_connection_override(base_url: String, account_token: String) -> void:
	_override_base_url = base_url.strip_edges().trim_suffix("/")
	_override_account_token = account_token.strip_edges()


func is_ready() -> bool:
	return _backend != null and is_instance_valid(_backend) and _backend.is_ready()


## Interest scopes the server has confirmed for the current session. Callers
## that must not miss scoped events should await their scope appearing here
## before acting (the backend replays missed windows losslessly, but state
## derived from projections is only guaranteed after confirmation).
func confirmed_interests() -> Array:
	if not is_ready():
		return []
	if _backend is RemoteWorldBackend:
		return (_backend as RemoteWorldBackend).session_interests()
	return Array(active_interests())


func is_remote() -> bool:
	return _remote


func session_token() -> String:
	return _backend.session_token() if is_ready() else ""


func actor_id() -> String:
	return str(_session.get("actor_id", ""))


func send_command(name: String, body: Dictionary, request_id: String = "", expected_revision: int = -1) -> String:
	if request_id.strip_edges().is_empty():
		request_id = next_request_id(name)
	var command := WorldContracts.command(request_id, name, body, expected_revision)
	if not is_ready():
		var result := WorldContracts.result_error(request_id, "session_invalid", "World authority session is not ready.")
		command_completed.emit(request_id, result)
		return request_id
	_backend.send_command(command)
	return request_id


func query_projections(kind: String = "", id: String = "") -> void:
	if is_ready():
		_backend.query_projections(kind, id)


func retain_interest(scope: String, owner: Object = null) -> void:
	var normalized := scope.strip_edges()
	if normalized.is_empty() or normalized == "global":
		return
	var entry := _interest_entry(normalized)
	if owner != null and is_instance_valid(owner):
		var owners := entry.get("owners", {}) as Dictionary
		owners[str(owner.get_instance_id())] = true
		entry["owners"] = owners
	else:
		entry["anonymous"] = int(entry.get("anonymous", 0)) + 1
	_interest_references[normalized] = entry
	_sync_interests()


func release_interest(scope: String, owner: Object = null) -> void:
	var normalized := scope.strip_edges()
	if normalized.is_empty() or normalized == "global" or not _interest_references.has(normalized):
		return
	var entry := _interest_entry(normalized)
	if owner != null:
		var owners := entry.get("owners", {}) as Dictionary
		owners.erase(str(owner.get_instance_id()))
		entry["owners"] = owners
	else:
		entry["anonymous"] = maxi(0, int(entry.get("anonymous", 0)) - 1)
	if _interest_entry_empty(entry):
		_interest_references.erase(normalized)
	else:
		_interest_references[normalized] = entry
	_sync_interests()


func active_interests() -> PackedStringArray:
	var out := PackedStringArray()
	for scope_variant in _interest_references.keys():
		out.append(str(scope_variant))
	out.sort()
	return out


func _sync_interests() -> void:
	if _backend != null and is_instance_valid(_backend):
		_backend.set_interests(active_interests())


func projection(kind: String, id: String) -> Dictionary:
	return _store.get_projection(kind, id)


func projections(kind: String = "") -> Array:
	return _store.all(kind)


func subscribe(event_type: String, owner: Object, callback: Callable) -> void:
	if not is_instance_valid(owner) or not callback.is_valid():
		return
	var type := event_type.strip_edges()
	var listeners := _subscriptions.get(type, []) as Array
	for listener_variant in listeners:
		var listener := listener_variant as Dictionary
		if listener.get("owner") == owner and listener.get("callback") == callback:
			return
	listeners.append({"owner": owner, "callback": callback})
	_subscriptions[type] = listeners


func unsubscribe_owner(owner: Object) -> void:
	if not is_instance_valid(owner):
		return
	for type in _subscriptions.keys():
		var kept: Array = []
		for listener_variant in _subscriptions[type] as Array:
			var listener := listener_variant as Dictionary
			# A freed Object still occupies its Variant slot. Casting it throws
			# before is_instance_valid can run, so validate the raw value first.
			var candidate: Variant = listener.get("owner")
			var callback: Callable = listener.get("callback") as Callable
			if is_instance_valid(candidate) and candidate != owner and callback.is_valid():
				kept.append(listener)
		if kept.is_empty():
			_subscriptions.erase(type)
		else:
			_subscriptions[type] = kept
	_release_owner_interests(owner)


func _interest_entry(scope: String) -> Dictionary:
	var existing: Variant = _interest_references.get(scope, null)
	if existing is Dictionary:
		return existing as Dictionary
	return {"owners": {}, "anonymous": 0}


func _interest_entry_empty(entry: Dictionary) -> bool:
	return (entry.get("owners", {}) as Dictionary).is_empty() and int(entry.get("anonymous", 0)) <= 0


func _release_owner_interests(owner: Object) -> void:
	var owner_key := str(owner.get_instance_id())
	var changed := false
	for scope_variant in _interest_references.keys().duplicate():
		var scope := str(scope_variant)
		if scope == "global":
			continue
		var entry := _interest_entry(scope)
		var owners := entry.get("owners", {}) as Dictionary
		if not owners.erase(owner_key):
			continue
		changed = true
		entry["owners"] = owners
		if _interest_entry_empty(entry):
			_interest_references.erase(scope)
		else:
			_interest_references[scope] = entry
	if changed:
		_sync_interests()


func next_request_id(request_scope: String = "command") -> String:
	_request_counter += 1
	var request_actor := actor_id()
	if request_actor.is_empty():
		request_actor = str(LocalPlayerView.get_network_player_id())
	return "%s:%s:%d:%d" % [
		request_scope.replace(".", "-"),
		request_actor,
		Time.get_ticks_usec(),
		_request_counter,
	]


func _on_session_started(session: Dictionary) -> void:
	_session = session.duplicate(true)
	var session_id := str(session.get("session_id", ""))
	print(
		"[WorldGateway] Authority session accepted actor=%s session=%s remote=%s"
		% [str(session.get("actor_id", "")), session_id, str(_remote)]
	)
	_sync_interests()
	session_ready.emit(_remote, session)
	_backend.query_projections()


func _on_session_ended() -> void:
	_session.clear()
	session_closed.emit()


func _on_command_finished(result: Dictionary) -> void:
	command_completed.emit(str(result.get("request_id", "")), result.duplicate(true))


func _on_world_event(event: Dictionary) -> void:
	var projection_variant: Variant = event.get("projection", null)
	if projection_variant is Dictionary:
		_store.apply(projection_variant as Dictionary)
	world_event.emit(event.duplicate(true))
	_dispatch(str(event.get("type", "")), event)
	_dispatch("*", event)


func _on_projections_received(incoming: Array) -> void:
	for projection_variant in incoming:
		if projection_variant is Dictionary:
			_store.apply(projection_variant as Dictionary)


func _dispatch(type: String, event: Dictionary) -> void:
	var listeners := (_subscriptions.get(type, []) as Array).duplicate()
	for listener_variant in listeners:
		var listener := listener_variant as Dictionary
		# Callbacks may unsubscribe or free later listeners while this snapshot
		# is being delivered. Consult the current list before each invocation.
		var current := _subscriptions.get(type, []) as Array
		if not current.has(listener):
			continue
		var owner: Variant = listener.get("owner")
		var callback: Callable = listener.get("callback") as Callable
		if not is_instance_valid(owner) or not callback.is_valid():
			current.erase(listener)
			if current.is_empty():
				_subscriptions.erase(type)
			continue
		callback.call(event.duplicate(true))


func _on_projection_changed(kind: String, id: String, projection_value: Dictionary) -> void:
	projection_changed.emit(kind, id, projection_value)


func _on_transport_failed(code: String, message: String) -> void:
	push_error("[WorldGateway] Authority transport failed (%s): %s" % [code, message])
	authority_error.emit(code, message)
