@tool
class_name AttachmentSocket
extends Marker3D

## Thin mount point on a vessel. Authored in vessel metres; boat faces already correct.

@export var socket_id: String = ""
@export_enum("cabin", "cargo", "fishing", "crane", "light", "mooring", "generic") var kind: String = "generic"

var mounted_attachment: VesselAttachment = null


func is_occupied() -> bool:
	return mounted_attachment != null and is_instance_valid(mounted_attachment)


func clear_mount() -> void:
	if mounted_attachment != null and is_instance_valid(mounted_attachment):
		mounted_attachment.unmount()
	mounted_attachment = null
