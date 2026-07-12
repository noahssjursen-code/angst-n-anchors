class_name AttachmentMount
extends RefCounted

## Mounts a loadout onto a vessel's AttachmentSocket markers.


static func apply(boat: BoatBody, attachments: Array) -> void:
	if boat == null:
		return
	clear(boat)
	for raw in attachments:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var entry := raw as Dictionary
		var socket_id := str(entry.get("socket", "")).strip_edges()
		var attachment_id := str(entry.get("attachment", "")).strip_edges()
		if socket_id.is_empty() or attachment_id.is_empty():
			continue
		var socket := find_socket(boat, socket_id)
		if socket == null:
			push_warning("AttachmentMount: no socket `%s` on %s" % [socket_id, boat.name])
			continue
		var want_kind := AttachmentCatalog.kind_of(attachment_id)
		if not want_kind.is_empty() and socket.kind != "generic" and socket.kind != want_kind:
			push_warning(
				"AttachmentMount: kind mismatch — socket `%s` wants %s, got %s (%s)"
				% [socket_id, socket.kind, want_kind, attachment_id]
			)
			continue
		var att := AttachmentCatalog.create(attachment_id)
		if att == null:
			continue
		att.name = attachment_id
		att.mount(boat, socket)
	boat.set_meta("loadout_applied", true)
	# ShipLighting gathers lights once in _ready; refresh after late mounts.
	var lighting := boat.get_node_or_null("ShipLighting") as ShipLighting
	if lighting != null and lighting.has_method("_gather_lights"):
		lighting.call_deferred("_gather_lights")


static func clear(boat: BoatBody) -> void:
	if boat == null:
		return
	for socket in list_sockets(boat):
		socket.clear_mount()
	if boat.has_meta("loadout_applied"):
		boat.remove_meta("loadout_applied")


static func find_socket(boat: BoatBody, socket_id: String) -> AttachmentSocket:
	var want := socket_id.strip_edges()
	for socket in list_sockets(boat):
		if socket.socket_id == want:
			return socket
	return null


static func list_sockets(boat: BoatBody) -> Array[AttachmentSocket]:
	var out: Array[AttachmentSocket] = []
	if boat == null:
		return out
	_collect_sockets(boat, out)
	return out


static func _collect_sockets(node: Node, out: Array[AttachmentSocket]) -> void:
	if node is AttachmentSocket:
		out.append(node as AttachmentSocket)
	for child in node.get_children():
		_collect_sockets(child, out)


static func has_kind(boat: BoatBody, kind: String) -> bool:
	for socket in list_sockets(boat):
		if not socket.is_occupied():
			continue
		if socket.mounted_attachment.kind() == kind:
			return true
	return false
