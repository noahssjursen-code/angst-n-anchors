class_name VesselLoadout
extends RefCounted

## Owned-vessel `attachments[]` helpers. Empty socket = nothing mounted.


static func entry(socket: String, attachment: String) -> Dictionary:
	return {"socket": socket, "attachment": attachment}


static func default_for(vessel_id: String = "workboat") -> Array:
	var id := HullRegistry.resolve_network_hull_id(vessel_id)
	match id:
		_:
			return workboat_default()


static func workboat_default() -> Array:
	## Full-capability starter: cabin, cargo, fishing, cleats, nav lights.
	return [
		entry("cabin", "cabin_workboat_basic"),
		entry("cargo_main", "cargo_deck_grid"),
		entry("fishing_stern", "trawl_system"),
		entry("mooring_port_fwd", "mooring_cleat"),
		entry("mooring_stbd_fwd", "mooring_cleat"),
		entry("mooring_port_aft", "mooring_cleat"),
		entry("mooring_stbd_aft", "mooring_cleat"),
		entry("nav_port", "nav_light_port"),
		entry("nav_stbd", "nav_light_starboard"),
		entry("nav_bow", "nav_light_bow"),
		entry("nav_stern", "nav_light_stern"),
	]


static func normalize(record: Dictionary) -> Dictionary:
	## Ensure a ledger row has a valid attachments array (fills defaults once).
	var out := record.duplicate(true)
	var hull_id := str(out.get("hull_id", "workboat"))
	var raw: Variant = out.get("attachments", null)
	if raw == null or typeof(raw) != TYPE_ARRAY or (raw as Array).is_empty():
		out["attachments"] = default_for(hull_id)
	else:
		out["attachments"] = _sanitize_list(raw as Array)
	return out


static func attachments_of(record: Dictionary) -> Array:
	return normalize(record).get("attachments", []) as Array


static func has_attachment(record: Dictionary, attachment_id: String) -> bool:
	var want := attachment_id.strip_edges()
	for raw in attachments_of(record):
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		if str((raw as Dictionary).get("attachment", "")) == want:
			return true
	return false


static func has_kind(record: Dictionary, kind: String) -> bool:
	var want := kind.strip_edges()
	for raw in attachments_of(record):
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var aid := str((raw as Dictionary).get("attachment", ""))
		if AttachmentCatalog.kind_of(aid) == want:
			return true
	return false


static func validate_against_sockets(attachments: Array, sockets: Array[AttachmentSocket]) -> Array[String]:
	## Returns human-readable errors; empty = ok.
	var errors: Array[String] = []
	var by_id: Dictionary = {}
	for socket in sockets:
		by_id[socket.socket_id] = socket
	var used: Dictionary = {}
	for raw in attachments:
		if typeof(raw) != TYPE_DICTIONARY:
			errors.append("Invalid attachment row")
			continue
		var entry := raw as Dictionary
		var sid := str(entry.get("socket", "")).strip_edges()
		var aid := str(entry.get("attachment", "")).strip_edges()
		if sid.is_empty() or aid.is_empty():
			errors.append("Empty socket or attachment id")
			continue
		if used.has(sid):
			errors.append("Socket `%s` already occupied" % sid)
			continue
		used[sid] = true
		if not by_id.has(sid):
			errors.append("Unknown socket `%s`" % sid)
			continue
		if not AttachmentCatalog.has(aid):
			errors.append("Unknown attachment `%s`" % aid)
			continue
		var socket: AttachmentSocket = by_id[sid]
		var want_kind := AttachmentCatalog.kind_of(aid)
		if socket.kind != "generic" and not want_kind.is_empty() and socket.kind != want_kind:
			errors.append("Socket `%s` rejects %s (%s)" % [sid, aid, want_kind])
	return errors


static func _sanitize_list(raw: Array) -> Array:
	var out: Array = []
	var seen: Dictionary = {}
	for item in raw:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var d := item as Dictionary
		var sid := str(d.get("socket", "")).strip_edges()
		var aid := str(d.get("attachment", "")).strip_edges()
		if sid.is_empty() or aid.is_empty():
			continue
		if seen.has(sid):
			continue
		if not AttachmentCatalog.has(aid):
			continue
		seen[sid] = true
		out.append(entry(sid, aid))
	return out
