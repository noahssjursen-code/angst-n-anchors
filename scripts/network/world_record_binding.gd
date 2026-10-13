class_name WorldRecordBinding
extends Node

## Bind any UI/renderer/system to an authoritative record, not scene-owned data.
signal updated(state: Dictionary, revision: int)
signal removed

var _gateway: Node
var _kind := ""
var _id := ""
var _scope := ""


func bind_record(kind: String, id: String, scope: String, gateway: Node = null) -> void:
	unbind()
	_gateway = gateway if gateway != null else WorldGateway
	_kind = kind
	_id = id
	_scope = scope
	_gateway.projection_changed.connect(_on_changed)
	_gateway.retain_interest(scope, self)
	_gateway.query_projections(kind, id)
	var current: Dictionary = _gateway.projection(kind, id)
	if not current.is_empty():
		_on_changed(kind, id, current)


func unbind() -> void:
	if is_instance_valid(_gateway):
		if _gateway.projection_changed.is_connected(_on_changed):
			_gateway.projection_changed.disconnect(_on_changed)
		_gateway.release_interest(_scope, self)
	_gateway = null


func _exit_tree() -> void:
	unbind()


func _on_changed(kind: String, id: String, projection: Dictionary) -> void:
	if kind != _kind or id != _id:
		return
	if projection.is_empty():
		removed.emit()
	else:
		updated.emit((projection.state as Dictionary).duplicate(true), int(projection.revision))
