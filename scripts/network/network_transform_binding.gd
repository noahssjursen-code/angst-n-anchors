class_name NetworkTransformBinding
extends Node

## Reusable owner-side binding for high-frequency, loss-tolerant transforms.
##
## This component deliberately does not carry gameplay facts. Doors, cargo,
## jobs, payments, and machine state belong in WorldGateway projections. Use
## this only for presentation transforms whose next packet supersedes the last.

enum RotationMode {
	YAW,
	FULL,
}

@export var entity_id := ""
@export var entity_type := "dynamic"
@export var rotation_mode := RotationMode.YAW
@export_multiline var metadata := ""
@export var auto_activate := true

var _host: Node3D = null
var _active := false


func _ready() -> void:
	_host = get_parent() as Node3D
	if auto_activate:
		activate()


func _exit_tree() -> void:
	deactivate()


func configure(id: String, type: String = "dynamic", mode: int = RotationMode.YAW) -> void:
	var was_active := _active
	deactivate()
	entity_id = id.strip_edges()
	entity_type = type.strip_edges()
	rotation_mode = mode
	if was_active or auto_activate:
		activate()


func activate() -> void:
	if _active:
		return
	if _host == null:
		_host = get_parent() as Node3D
	if _host == null or entity_id.strip_edges().is_empty():
		return
	_active = true
	NetworkManager.register_sender(
		_host,
		entity_id,
		entity_type,
		6 if rotation_mode == RotationMode.FULL else 4,
		_build_payload,
		_build_metadata,
	)


func deactivate() -> void:
	if not _active:
		return
	_active = false
	NetworkManager.unregister_sender(entity_id)


func force_sync() -> void:
	if _active:
		NetworkManager.force_sender_sync(entity_id)


func _build_payload() -> Array:
	if _host != null and _host.has_method("network_transform_payload"):
		var custom: Variant = _host.call("network_transform_payload")
		if custom is Array:
			return custom as Array
	if _host == null:
		return []
	var position := _host.global_position
	if rotation_mode == RotationMode.FULL:
		var rotation := _host.global_rotation
		return [position.x, position.y, position.z, rotation.x, rotation.y, rotation.z]
	return [position.x, position.y, position.z, _host.global_rotation.y]


func _build_metadata() -> String:
	if _host != null and _host.has_method("network_transform_metadata"):
		return str(_host.call("network_transform_metadata"))
	return metadata
