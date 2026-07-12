@tool
class_name VesselAttachment
extends Node3D

## Base contract for anything mounted at an AttachmentSocket.

var _boat: BoatBody = null
var _socket: AttachmentSocket = null


func attachment_id() -> String:
	return ""


func kind() -> String:
	return "generic"


func mount(boat: BoatBody, socket: AttachmentSocket) -> void:
	_boat = boat
	_socket = socket
	if get_parent() != socket:
		if get_parent() != null:
			get_parent().remove_child(self)
		socket.add_child(self)
	position = Vector3.ZERO
	rotation = Vector3.ZERO
	socket.mounted_attachment = self
	_on_mounted()


func unmount() -> void:
	_on_unmounted()
	if _socket != null and is_instance_valid(_socket) and _socket.mounted_attachment == self:
		_socket.mounted_attachment = null
	_socket = null
	_boat = null
	if get_parent() != null:
		get_parent().remove_child(self)
	queue_free()


func _on_mounted() -> void:
	pass


func _on_unmounted() -> void:
	pass
