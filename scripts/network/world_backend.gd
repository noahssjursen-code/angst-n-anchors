class_name WorldBackend
extends Node

## Transport-neutral authority backend. WorldGateway is the only public caller.

signal session_started(session: Dictionary)
signal session_ended
signal command_finished(result: Dictionary)
signal event_received(event: Dictionary)
signal projections_received(projections: Array)
signal transport_failed(code: String, message: String)


func start_session(_actor_id: String, _display_name: String, _world_checksum: String, _captain_token: String = "") -> void:
	push_error("WorldBackend.start_session must be implemented")


func stop_session() -> void:
	session_ended.emit()


func send_command(_command: Dictionary) -> void:
	push_error("WorldBackend.send_command must be implemented")


func query_projections(_kind: String = "", _id: String = "") -> void:
	push_error("WorldBackend.query_projections must be implemented")


func set_interests(_scopes: PackedStringArray) -> void:
	pass


func session_token() -> String:
	return ""


func is_ready() -> bool:
	return false
