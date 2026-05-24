class_name VesselSync
extends RefCounted

## Keeps the captain's owned fleet aligned with Postgres `/v1/vessels`.
## Commissioning appends rows; harbour master picks which hull to deploy.


static func publish_commission(session: Node, entry: Dictionary, template_path: String, uid: String) -> void:
	if session == null or not _is_mp_session(session):
		return
	var captain_id := _captain_id(session)
	if captain_id.is_empty():
		return

	var hull_id := str(entry.get("id", ""))
	var display := str(entry.get("display", "Vessel"))
	if hull_id.is_empty():
		return

	_post_vessel(session, captain_id, hull_id, display, template_path, uid)


static func pull_captain_vessel(session: Node) -> void:
	if session == null or not _is_mp_session(session):
		return
	var captain_id := _captain_id(session)
	if captain_id.is_empty():
		return
	_fetch_vessels(session, captain_id)


static func _is_mp_session(session: Node) -> bool:
	var config := session.get_node_or_null("/root/ServerConfig") as Node
	return config != null and bool(config.get("is_multiplayer_mode"))


static func _http_base(session: Node) -> String:
	var config := session.get_node_or_null("/root/ServerConfig") as Node
	if config == null:
		return ""
	return str(config.call("get_http_base_url"))


static func _captain_id(session: Node) -> String:
	if session.get("data") == null:
		return ""
	return str(session.data.captain_id)


static func _post_vessel(
	session: Node,
	captain_id: String,
	hull_id: String,
	display: String,
	template_path: String,
	uid: String,
) -> void:
	var req := HTTPRequest.new()
	session.add_child(req)
	var body := JSON.stringify({
		"captain_id": captain_id,
		"hull_id": hull_id,
		"display_name": display,
		"template_path": template_path,
	})
	var url := "%s/v1/vessels" % _http_base(session)
	req.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, resp_body: PackedByteArray) -> void:
		req.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS or code != 200:
			push_warning("VesselSync: failed to register vessel (HTTP %d)" % code)
			return
		var parsed: Variant = JSON.parse_string(resp_body.get_string_from_utf8())
		if typeof(parsed) != TYPE_DICTIONARY:
			return
		var server_id := str((parsed as Dictionary).get("id", ""))
		if server_id.is_empty() or session.get("data") == null:
			return
		var record: Dictionary = session.data.find_owned_vessel(uid)
		if record.is_empty():
			return
		record["server_vessel_id"] = server_id
		session.data.upsert_owned_vessel(record)
		if str(session.data.active_vessel.get("uid", "")) == uid:
			session.data.set_active_vessel(record)
		if session.has_method("save_now"):
			session.call("save_now")
	)
	req.request(url, PackedStringArray(["Content-Type: application/json"]), HTTPClient.METHOD_POST, body)


static func _fetch_vessels(session: Node, captain_id: String) -> void:
	var req := HTTPRequest.new()
	session.add_child(req)
	var url := "%s/v1/vessels?captain_id=%s" % [_http_base(session), captain_id.uri_encode()]
	req.request_completed.connect(func(result: int, response_code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
		req.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
			return
		var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
		if typeof(parsed) != TYPE_ARRAY:
			return
		_apply_server_vessels(session, parsed as Array)
	)
	req.request(url)


static func _apply_server_vessels(session: Node, rows: Array) -> void:
	if session.get("data") == null:
		return

	var data: PlayerData = session.data
	var merged: Array = []
	var seen_uids: Dictionary = {}

	for row_raw in rows:
		if typeof(row_raw) != TYPE_DICTIONARY:
			continue
		var record := _merge_server_row(data, row_raw as Dictionary)
		if record.is_empty():
			continue
		var uid := str(record.get("uid", ""))
		if uid.is_empty() or seen_uids.has(uid):
			continue
		seen_uids[uid] = true
		merged.append(record)

	for entry_raw in data.owned_vessels:
		if typeof(entry_raw) != TYPE_DICTIONARY:
			continue
		var entry := entry_raw as Dictionary
		var uid := str(entry.get("uid", ""))
		if uid.is_empty() or seen_uids.has(uid):
			continue
		if PlayerData.is_legacy_starter_vessel(entry):
			continue
		var path := str(entry.get("template_path", ""))
		if path.is_empty() or not FileAccess.file_exists(path):
			continue
		seen_uids[uid] = true
		merged.append(entry.duplicate())

	if merged.is_empty():
		return

	var active_uid := str(data.active_vessel.get("uid", ""))
	data.owned_vessels = merged
	var still_active := false
	for entry_raw in merged:
		var entry := entry_raw as Dictionary
		if str(entry.get("uid", "")) == active_uid:
			data.set_active_vessel(entry)
			still_active = true
			break
	if not still_active:
		data.set_active_vessel(merged[merged.size() - 1] as Dictionary)
	data.repair_save_consistency()
	if session.has_method("save_now"):
		session.call("save_now")
	if session.has_method("notify_vessels_synced"):
		session.call("notify_vessels_synced")


static func _merge_server_row(data: PlayerData, row: Dictionary) -> Dictionary:
	var server_id := str(row.get("id", ""))
	var hull_id := str(row.get("hull_id", ""))
	var display := str(row.get("display_name", "Vessel"))
	if hull_id.is_empty():
		return {}

	var existing := data.find_owned_by_server_id(server_id)
	if not existing.is_empty():
		existing["display"] = display
		existing["hull_id"] = hull_id
		var path := str(existing.get("template_path", ""))
		if path.is_empty() or not FileAccess.file_exists(path):
			var rebuilt := _ensure_local_template(hull_id, display)
			if rebuilt.is_empty():
				return {}
			existing["uid"] = rebuilt["uid"]
			existing["template_path"] = rebuilt["template_path"]
		return existing

	var local := _ensure_local_template(hull_id, display)
	if local.is_empty():
		return {}
	return {
		"uid":              local["uid"],
		"hull_id":          hull_id,
		"display":          display,
		"template_path":    local["template_path"],
		"server_vessel_id": server_id,
	}


static func _ensure_local_template(hull_id: String, display: String) -> Dictionary:
	var entry := HullRegistry.get_by_id(hull_id)
	if entry.is_empty():
		return {}
	DirAccess.make_dir_recursive_absolute("user://shipwright_orders")
	var uid := "%s_%d" % [hull_id, Time.get_unix_time_from_system()]
	var path := "user://shipwright_orders/" + uid + ".json"
	var template := StarterVessel.build_template(entry)
	template["display_name"] = display
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return {}
	f.store_string(JSON.stringify(template))
	f.close()
	return {"uid": uid, "template_path": path}
