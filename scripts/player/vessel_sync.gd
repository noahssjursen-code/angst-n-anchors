class_name VesselSync
extends RefCounted

## Keeps the captain's owned fleet aligned with Postgres `/v1/vessels`.
## Commissioning appends rows; harbour master picks which hull to deploy.


static var _in_flight_registrations: Dictionary = {}
static var _failed_registrations: Dictionary = {}
static var _in_flight_pull: bool = false
static var _pending_pull_callbacks: Array = []


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


static func pull_captain_vessel(session: Node, on_complete: Callable = Callable()) -> void:
	if session == null or not _is_mp_session(session):
		if on_complete.is_valid():
			on_complete.call()
		return
	var captain_id := _captain_id(session)
	if captain_id.is_empty():
		if on_complete.is_valid():
			on_complete.call()
		return

	if _in_flight_pull:
		if on_complete.is_valid():
			_pending_pull_callbacks.append(on_complete)
		return

	_in_flight_pull = true
	if on_complete.is_valid():
		_pending_pull_callbacks.append(on_complete)

	_fetch_vessels(session, captain_id, func() -> void:
		_in_flight_pull = false
		var callbacks := _pending_pull_callbacks.duplicate()
		_pending_pull_callbacks.clear()
		for cb in callbacks:
			if cb.is_valid():
				cb.call()
	)


## Multiplayer NPCs should await this before reading owned_vessels.
static func refresh_for_ui(session: Node, on_complete: Callable = Callable()) -> void:
	pull_captain_vessel(session, on_complete)


static func push_fleet_state(session: Node, record: Dictionary) -> void:
	if session == null or not _is_mp_session(session):
		return
	var server_id := str(record.get("server_vessel_id", ""))
	if server_id.is_empty():
		push_warning(
			"VesselSync: fleet not pushed — vessel has no server_vessel_id (uid=%s). "
			% str(record.get("uid", ""))
		)
		return

	var av := AutonomousVesselRecord.from_owned_vessel(record)
	var fleet_body := JSON.stringify({
		"autonomous_active": av.active,
		"autonomous_active_at": av.active_at,
		"home_port_id": av.home_port_id,
		"visit_port_id": av.visit_port_id,
		"crew": av.crew,
		"expense_per_day": av.expense_per_day,
		"pending_earnings": av.pending_earnings,
		"last_collected_at": av.last_collected_at,
		"last_accrual_at": av.last_accrual_at,
		"sim_version": av.sim_version,
	})

	var req := HTTPRequest.new()
	session.add_child(req)
	var url := "%s/v1/vessels" % _http_base(session)
	var body := JSON.stringify({
		"id": server_id,
		"fleet_state_json": fleet_body,
	})
	req.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, _resp: PackedByteArray) -> void:
		req.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS or code != 200:
			push_warning("VesselSync: fleet push failed for %s (HTTP %d)" % [server_id, code])
	)
	req.request(url, PackedStringArray(["Content-Type: application/json"]), HTTPClient.METHOD_PUT, body)


## Ensures the vessel exists in Postgres, then pushes fleet route/state.
static func persist_fleet_state(session: Node, record: Dictionary) -> void:
	ensure_vessel_registered(session, record, func(updated: Dictionary) -> void:
		push_fleet_state(session, updated)
	)


## POST /v1/vessels for owned hulls that only exist in the local save.
static func ensure_vessel_registered(
	session: Node,
	record: Dictionary,
	on_complete: Callable = Callable(),
) -> void:
	if session == null or not _is_mp_session(session):
		if on_complete.is_valid():
			on_complete.call(record)
		return
	if not str(record.get("server_vessel_id", "")).is_empty():
		if on_complete.is_valid():
			on_complete.call(record)
		return

	var uid := str(record.get("uid", ""))
	if uid.is_empty():
		if on_complete.is_valid():
			on_complete.call(record)
		return

	if _in_flight_registrations.has(uid):
		if on_complete.is_valid():
			on_complete.call(record)
		return

	if _failed_registrations.has(uid):
		if on_complete.is_valid():
			on_complete.call(record)
		return

	var captain_id := _captain_id(session)
	var hull_id := str(record.get("hull_id", ""))
	var display := str(record.get("display", record.get("display_name", "Vessel")))
	var template_path := str(record.get("template_path", ""))
	if captain_id.is_empty() or hull_id.is_empty():
		push_warning("VesselSync: cannot register vessel — missing captain_id or hull_id")
		if on_complete.is_valid():
			on_complete.call(record)
		return

	_in_flight_registrations[uid] = true
	_post_vessel(session, captain_id, hull_id, display, template_path, uid, func(updated: Dictionary) -> void:
		_in_flight_registrations.erase(uid)
		if updated.is_empty() or str(updated.get("server_vessel_id", "")).is_empty():
			_failed_registrations[uid] = true
			push_warning("VesselSync: registration failed for local vessel uid=%s" % uid)
		else:
			_failed_registrations.erase(uid)
		if on_complete.is_valid():
			on_complete.call(updated)
	)


## Register any local-only owned hulls, then push active fleet rows to the server.
static func backfill_unregistered_vessels(session: Node) -> void:
	if session == null or not _is_mp_session(session) or session.get("data") == null:
		return
	var data: PlayerData = session.data
	var pending: Array = []
	for entry_raw in data.owned_vessels:
		if typeof(entry_raw) != TYPE_DICTIONARY:
			continue
		var record := entry_raw as Dictionary
		if PlayerData.is_legacy_starter_vessel(record):
			continue
		if not str(record.get("server_vessel_id", "")).is_empty():
			continue
		var uid := str(record.get("uid", ""))
		if uid.is_empty() or _in_flight_registrations.has(uid) or _failed_registrations.has(uid):
			continue
		var hull_id := str(record.get("hull_id", ""))
		if hull_id.is_empty():
			var path := str(record.get("template_path", ""))
			hull_id = HullRegistry.resolve_id_from_template(path, hull_id)
		if hull_id.is_empty():
			continue
		pending.append(record.duplicate(true))

	if pending.is_empty():
		sync_all_active_fleet_to_server(session)
		return

	var remaining := pending.size()
	for record in pending:
		ensure_vessel_registered(session, record, func(_updated: Dictionary) -> void:
			remaining -= 1
			if remaining <= 0:
				sync_all_active_fleet_to_server(session)
				pull_captain_vessel(session)
		)


static func sync_all_active_fleet_to_server(session: Node) -> void:
	if session == null or not _is_mp_session(session) or session.get("data") == null:
		return
	for entry_raw in (session.data as PlayerData).owned_vessels:
		if typeof(entry_raw) != TYPE_DICTIONARY:
			continue
		var record := entry_raw as Dictionary
		if not bool(record.get("autonomous_active", false)):
			continue
		if str(record.get("server_vessel_id", "")).is_empty():
			continue
		push_fleet_state(session, record)


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
	on_complete: Callable = Callable(),
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
			if on_complete.is_valid():
				on_complete.call({})
			return
		var parsed: Variant = JSON.parse_string(resp_body.get_string_from_utf8())
		if typeof(parsed) != TYPE_DICTIONARY:
			if on_complete.is_valid():
				on_complete.call({})
			return
		var server_id := str((parsed as Dictionary).get("id", ""))
		if server_id.is_empty() or session.get("data") == null:
			if on_complete.is_valid():
				on_complete.call({})
			return
		var record: Dictionary = session.data.find_owned_vessel(uid)
		if record.is_empty():
			if on_complete.is_valid():
				on_complete.call({})
			return
		record["server_vessel_id"] = server_id
		session.data.upsert_owned_vessel(record)
		if str(session.data.active_vessel.get("uid", "")) == uid:
			session.data.set_active_vessel(record)
		if session.has_method("save_now"):
			session.call("save_now")
		print("[VesselSync] Registered vessel uid=%s server_id=%s" % [uid, server_id])
		if on_complete.is_valid():
			on_complete.call(record)
	)
	req.request(url, PackedStringArray(["Content-Type: application/json"]), HTTPClient.METHOD_POST, body)


static func _fetch_vessels(session: Node, captain_id: String, on_complete: Callable = Callable()) -> void:
	var req := HTTPRequest.new()
	session.add_child(req)
	var url := "%s/v1/vessels?captain_id=%s" % [_http_base(session), captain_id.uri_encode()]
	req.request_completed.connect(func(result: int, response_code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
		req.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
			if on_complete.is_valid():
				on_complete.call()
			return
		var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
		if typeof(parsed) != TYPE_ARRAY:
			if on_complete.is_valid():
				on_complete.call()
			return
		_apply_server_vessels(session, parsed as Array, on_complete)
	)
	req.request(url)


static func _apply_server_vessels(session: Node, rows: Array, on_complete: Callable = Callable()) -> void:
	if session.get("data") == null:
		if on_complete.is_valid():
			on_complete.call()
		return

	var data: PlayerData = session.data
	var pending_local := _collect_unregistered_local(data.owned_vessels)
	var merged: Array = []
	var seen_server_ids: Dictionary = {}

	for row_raw in rows:
		if typeof(row_raw) != TYPE_DICTIONARY:
			continue
		var record := _merge_server_row(data, row_raw as Dictionary)
		if record.is_empty():
			continue
		var server_id := str(record.get("server_vessel_id", ""))
		if server_id.is_empty() or seen_server_ids.has(server_id):
			continue
		seen_server_ids[server_id] = true
		merged.append(record)

	var active_uid := str(data.active_vessel.get("uid", ""))
	var active_server_id := str(data.active_vessel.get("server_vessel_id", ""))
	data.owned_vessels = merged

	var still_active := false
	for entry_raw in merged:
		var entry := entry_raw as Dictionary
		var uid := str(entry.get("uid", ""))
		var sid := str(entry.get("server_vessel_id", ""))
		if uid == active_uid or (not active_server_id.is_empty() and sid == active_server_id):
			data.set_active_vessel(entry)
			still_active = true
			break
	if not still_active and not merged.is_empty():
		data.set_active_vessel(merged[merged.size() - 1] as Dictionary)
	elif not still_active:
		data.active_vessel = {}

	data.repair_save_consistency()
	if session.has_method("save_now"):
		session.call("save_now")
	if session.has_method("notify_vessels_synced"):
		session.call("notify_vessels_synced")
	if on_complete.is_valid():
		on_complete.call()
	if not pending_local.is_empty():
		_backfill_vessel_records(session, pending_local)


static func _collect_unregistered_local(owned: Array) -> Array:
	var out: Array = []
	for entry_raw in owned:
		if typeof(entry_raw) != TYPE_DICTIONARY:
			continue
		var record := entry_raw as Dictionary
		if PlayerData.is_legacy_starter_vessel(record):
			continue
		if not str(record.get("server_vessel_id", "")).is_empty():
			continue
		var uid := str(record.get("uid", ""))
		if uid.is_empty() or _in_flight_registrations.has(uid) or _failed_registrations.has(uid):
			continue
		var hull_id := str(record.get("hull_id", ""))
		if hull_id.is_empty():
			hull_id = HullRegistry.resolve_id_from_template(str(record.get("template_path", "")), hull_id)
		if hull_id.is_empty():
			continue
		out.append(record.duplicate(true))
	return out


static func _backfill_vessel_records(session: Node, records: Array) -> void:
	if session == null or records.is_empty():
		return
	var remaining := records.size()
	for record in records:
		ensure_vessel_registered(session, record, func(_updated: Dictionary) -> void:
			remaining -= 1
			if remaining <= 0:
				pull_captain_vessel(session)
		)


static func _merge_server_row(data: PlayerData, row: Dictionary) -> Dictionary:
	var server_id := str(row.get("id", ""))
	var hull_id := str(row.get("hull_id", ""))
	var display := str(row.get("display_name", "Vessel"))
	if hull_id.is_empty():
		return {}

	var fleet_patch := _fleet_patch_from_row(row)

	var existing := data.find_owned_by_server_id(server_id)
	if not existing.is_empty():
		existing = PlayerData.merge_vessel_record(existing, {
			"display": display,
			"hull_id": hull_id,
		})
		existing = PlayerData.merge_vessel_record(existing, fleet_patch)
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
	var record := {
		"uid":              local["uid"],
		"hull_id":          hull_id,
		"display":          display,
		"template_path":    local["template_path"],
		"server_vessel_id": server_id,
	}
	return PlayerData.merge_vessel_record(record, fleet_patch)


static func _fleet_patch_from_row(row: Dictionary) -> Dictionary:
	var raw := str(row.get("fleet_state_json", ""))
	if raw.is_empty() or raw == "{}":
		return {}
	var parsed: Variant = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var fleet := parsed as Dictionary
	return {
		"autonomous_active": bool(fleet.get("autonomous_active", false)),
		"autonomous_active_at": int(fleet.get("autonomous_active_at", 0)),
		"home_port_id": str(fleet.get("home_port_id", "")),
		"visit_port_id": str(fleet.get("visit_port_id", "")),
		"crew": fleet.get("crew", []),
		"expense_per_day": int(fleet.get("expense_per_day", 0)),
		"pending_earnings": int(fleet.get("pending_earnings", 0)),
		"last_collected_at": int(fleet.get("last_collected_at", 0)),
		"last_accrual_at": int(fleet.get("last_accrual_at", 0)),
		"sim_version": int(fleet.get("sim_version", AutonomousVesselRecord.SIM_VERSION)),
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
