class_name WorldStateBinding
extends Node

## Reusable reliable-state component for doors, switches, machines, lights,
## businesses, and other low-frequency world entities. The host owns visuals;
## this component owns authority commands, replay, and revision ordering.

signal authoritative_state_changed(state: Dictionary, action: String, event: Dictionary)
signal command_rejected(code: String, message: String)

@export var entity_id := ""
@export var entity_kind := "world_entity"
@export var query_on_ready := true

var _revision := -1
var _state: Dictionary = {}
var _active := false
var _pending_requests: Dictionary = {}
var _retained_scope := ""


func _ready() -> void:
	activate()


func _exit_tree() -> void:
	deactivate()


func configure(id: String, kind: String = "world_entity") -> void:
	_release_scope()
	entity_id = id.strip_edges()
	entity_kind = kind.strip_edges()
	if entity_kind.is_empty():
		entity_kind = "world_entity"
	if _active:
		_retain_scope()
		_reconcile()


func activate() -> void:
	if _active:
		return
	_active = true
	_retain_scope()
	WorldGateway.subscribe(WorldContracts.EVENT_INTERACTION_CHANGED, self, _on_world_event)
	if not WorldGateway.projection_changed.is_connected(_on_projection_changed):
		WorldGateway.projection_changed.connect(_on_projection_changed)
	if not WorldGateway.command_completed.is_connected(_on_command_completed):
		WorldGateway.command_completed.connect(_on_command_completed)
	if not WorldGateway.session_ready.is_connected(_on_session_ready):
		WorldGateway.session_ready.connect(_on_session_ready)
	_reconcile()


func deactivate() -> void:
	if not _active:
		return
	_active = false
	_release_scope()
	WorldGateway.unsubscribe_owner(self)
	if WorldGateway.projection_changed.is_connected(_on_projection_changed):
		WorldGateway.projection_changed.disconnect(_on_projection_changed)
	if WorldGateway.command_completed.is_connected(_on_command_completed):
		WorldGateway.command_completed.disconnect(_on_command_completed)
	if WorldGateway.session_ready.is_connected(_on_session_ready):
		WorldGateway.session_ready.disconnect(_on_session_ready)


func request(action: String, state: Dictionary = {}, optimistic_revision: bool = true) -> String:
	var normalized_action := action.strip_edges()
	if entity_id.strip_edges().is_empty() or normalized_action.is_empty():
		command_rejected.emit("binding_invalid", "A world state binding requires an entity id and action.")
		return ""
	var request_id := WorldGateway.next_request_id("interaction-%s" % entity_id)
	_pending_requests[request_id] = true
	var expected := _revision if optimistic_revision else -1
	WorldGateway.send_command(
		WorldContracts.COMMAND_INTERACTION_SET,
		{
			"entity_id": entity_id,
			"kind": entity_kind,
			"action": normalized_action,
			"state": state.duplicate(true),
		},
		request_id,
		expected,
	)
	return request_id


func state() -> Dictionary:
	return _state.duplicate(true)


func revision() -> int:
	return _revision


func _on_session_ready(_remote: bool, _session: Dictionary) -> void:
	_reconcile()


func _reconcile() -> void:
	if entity_id.strip_edges().is_empty():
		return
	var projection := WorldGateway.projection("interaction", entity_id)
	if not projection.is_empty():
		_apply_projection(projection, {})
	elif query_on_ready and WorldGateway.is_ready():
		WorldGateway.query_projections("interaction", entity_id)


func _on_projection_changed(kind: String, id: String, projection: Dictionary) -> void:
	if kind == "interaction" and id == entity_id:
		_apply_projection(projection, {})


func _on_world_event(event: Dictionary) -> void:
	var body := event.get("body", {}) as Dictionary
	if str(body.get("entity_id", "")) != entity_id:
		return
	var projection := event.get("projection", {}) as Dictionary
	if not projection.is_empty():
		_apply_projection(projection, event)


func _apply_projection(projection: Dictionary, event: Dictionary) -> void:
	var incoming_revision := int(projection.get("revision", 0))
	if incoming_revision < _revision:
		return
	_revision = incoming_revision
	var envelope := projection.get("state", {}) as Dictionary
	_state = (envelope.get("state", {}) as Dictionary).duplicate(true)
	authoritative_state_changed.emit(
		_state.duplicate(true),
		str(envelope.get("action", "")),
		event.duplicate(true),
	)


func _on_command_completed(request_id: String, result: Dictionary) -> void:
	if not _pending_requests.has(request_id):
		return
	_pending_requests.erase(request_id)
	if not bool(result.get("ok", false)):
		command_rejected.emit(str(result.get("code", "command_rejected")), str(result.get("message", "Command rejected.")))


func _retain_scope() -> void:
	if not _retained_scope.is_empty() or entity_id.strip_edges().is_empty():
		return
	_retained_scope = "entity:%s" % entity_id.strip_edges()
	WorldGateway.retain_interest(_retained_scope, self)


func _release_scope() -> void:
	if _retained_scope.is_empty():
		return
	WorldGateway.release_interest(_retained_scope, self)
	_retained_scope = ""
