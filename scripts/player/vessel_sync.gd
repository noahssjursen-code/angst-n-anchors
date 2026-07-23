class_name VesselSync
extends RefCounted

## Keeps the captain's owned fleet aligned with Postgres `/v1/vessels`.
## Commissioning appends rows; harbour master picks which hull to deploy.


static var _in_flight_registrations: Dictionary = {}
static var _failed_registrations: Dictionary = {}
static var _in_flight_pull: bool = false
static var _pending_pull_callbacks: Array = []
static var _starter_repairs: Dictionary = {}


static func publish_commission(
	session: Node,
	entry: Dictionary,
	template_path: String,
	uid: String,
	vessel_name: String = "",
) -> void:
	if session == null or not _is_mp_session(session):
		return
	var captain_id := _captain_id(session)
	if captain_id.is_empty():
		return

	var hull_id := str(entry.get("hull_id", entry.get("id", "")))
	var display := vessel_name.strip_edges()
	if display.is_empty():
		display = str(entry.get("display", "Vessel"))
	if hull_id.is_empty() or uid.is_empty():
		return

	var record: Dictionary = {}
	if session.get("data") != null:
		record = session.data.find_owned_vessel(uid)
	if record.is_empty():
		record = {
			"uid": uid,
			"hull_id": hull_id,
			"name": display,
			"display": display,
			"shaft_power_kw": float(entry.get("shaft_power_kw", 1.0)),
			"template_path": template_path,
			"scene_path": template_path,
		}
	else:
		record["hull_id"] = hull_id
		record["name"] = display
		record["shaft_power_kw"] = float(entry.get("shaft_power_kw", 1.0))
		record["template_path"] = template_path
		record["scene_path"] = template_path
	ensure_vessel_registered(session, record)


## Push deck fit-out after shipwright refit (or backfill).
static func push_brick_layout(session: Node, record: Dictionary, on_complete: Callable = Callable()) -> void:
	if session == null or not _is_mp_session(session):
		if on_complete.is_valid():
			on_complete.call(record)
		return
	var server_id := str(record.get("server_vessel_id", ""))
	if server_id.is_empty():
		ensure_vessel_registered(session, record, func(updated: Dictionary) -> void:
			if updated.is_empty() or str(updated.get("server_vessel_id", "")).is_empty():
				if on_complete.is_valid():
					on_complete.call(updated)
				return
			push_brick_layout(session, updated, on_complete)
		)
		return

	var layout := VesselSpawn.brick_layout_of(record)
	var req := HTTPRequest.new()
	session.add_child(req)
	var body := JSON.stringify({
		"id": server_id,
		"brick_layout": layout,
	})
	var url := "%s/v1/vessels" % _http_base(session)
	req.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, resp_body: PackedByteArray) -> void:
		req.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS or code != 200:
			push_warning("VesselSync: failed to push brick_layout (HTTP %d)" % code)
			if on_complete.is_valid():
				on_complete.call(record)
			return
		var parsed: Variant = JSON.parse_string(resp_body.get_string_from_utf8())
		if typeof(parsed) != TYPE_DICTIONARY or session.get("data") == null:
			if on_complete.is_valid():
				on_complete.call(record)
			return
		var row := parsed as Dictionary
		var updated := record.duplicate(true)
		updated["layout_hash"] = str(row.get("layout_hash", ""))
		var layout_raw: Variant = row.get("brick_layout", layout)
		if typeof(layout_raw) == TYPE_DICTIONARY and (
			_layout_has_configuration(layout_raw as Dictionary)
			or not _layout_has_configuration(VesselSpawn.brick_layout_of(updated))
		):
			updated["brick_layout"] = layout_raw
		session.data.upsert_owned_vessel(updated)
		if str(session.data.active_vessel.get("uid", "")) == str(updated.get("uid", "")):
			session.data.set_active_vessel(updated)
		if session.has_method("save_now"):
			session.call("save_now")
		_force_ship_meta_resync()
		print("[VesselSync] Pushed brick_layout server_id=%s hash=%s" % [
			server_id, str(updated.get("layout_hash", ""))
		])
		if on_complete.is_valid():
			on_complete.call(updated)
	)
	req.request(url, _captain_headers(session, true), HTTPClient.METHOD_PUT, body)


static func fetch_vessel_layout(session: Node, server_vessel_id: String, on_complete: Callable) -> void:
	## Remote clients: GET /v1/vessels?id=<uuid> → { brick_layout, layout_hash, … }.
	if session == null or server_vessel_id.is_empty() or not on_complete.is_valid():
		return
	var base := _http_base(session)
	if base.is_empty():
		on_complete.call({}, "")
		return
	var req := HTTPRequest.new()
	session.add_child(req)
	var url := "%s/v1/vessels?id=%s" % [base, server_vessel_id.uri_encode()]
	req.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, resp_body: PackedByteArray) -> void:
		req.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS or code != 200:
			on_complete.call({}, "")
			return
		var parsed: Variant = JSON.parse_string(resp_body.get_string_from_utf8())
		if typeof(parsed) != TYPE_DICTIONARY:
			on_complete.call({}, "")
			return
		var row := parsed as Dictionary
		var layout_raw: Variant = row.get("brick_layout", {})
		var layout: Dictionary = {}
		if typeof(layout_raw) == TYPE_DICTIONARY:
			layout = layout_raw as Dictionary
		elif typeof(layout_raw) == TYPE_STRING:
			var nested: Variant = JSON.parse_string(str(layout_raw))
			if typeof(nested) == TYPE_DICTIONARY:
				layout = nested as Dictionary
		on_complete.call(layout, str(row.get("layout_hash", "")))
	)
	req.request(url)


static func _force_ship_meta_resync() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var nm := tree.root.get_node_or_null("/root/NetworkManager")
	if nm != null and nm.has_method("force_local_ship_meta_resync"):
		nm.call("force_local_ship_meta_resync")


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
	if session == null or not _is_mp_session(session):
		if on_complete.is_valid():
			on_complete.call()
		return
	pull_captain_vessel(session, on_complete)


## Autonomous fleet sync removed — kept as no-ops so old MP call sites compile.
static func push_fleet_state(_session: Node, _record: Dictionary) -> void:
	pass


static func persist_fleet_state(_session: Node, _record: Dictionary) -> void:
	pass


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
	var display := VesselSpawn.vessel_name_of(record)
	var template_path := str(record.get("template_path", ""))
	if captain_id.is_empty() or hull_id.is_empty():
		push_warning("VesselSync: cannot register vessel — missing captain_id or hull_id")
		if on_complete.is_valid():
			on_complete.call(record)
		return

	_in_flight_registrations[uid] = true
	var layout := VesselSpawn.brick_layout_of(record)
	var registration_finished := func(updated: Dictionary) -> void:
		_in_flight_registrations.erase(uid)
		if updated.is_empty() or str(updated.get("server_vessel_id", "")).is_empty():
			_failed_registrations[uid] = true
			push_warning("VesselSync: registration failed for local vessel uid=%s" % uid)
		else:
			_failed_registrations.erase(uid)
		if on_complete.is_valid():
			on_complete.call(updated)
	_post_vessel(
		session, captain_id, hull_id, display, template_path, uid,
		str(record.get("registration_id", "review_required")),
		float(record.get("shaft_power_kw", 1.0)), layout,
		registration_finished,
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
		return

	var remaining := pending.size()
	for record in pending:
		ensure_vessel_registered(session, record, func(_updated: Dictionary) -> void:
			remaining -= 1
			if remaining <= 0:
				pull_captain_vessel(session)
		)


static func sync_all_active_fleet_to_server(_session: Node) -> void:
	pass


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


static func _captain_headers(session: Node, include_json: bool = false) -> PackedStringArray:
	var headers := PackedStringArray()
	if include_json:
		headers.append("Content-Type: application/json")
	var token := RemoteAccountCredentialStore.token_for(_http_base(session))
	if not token.is_empty():
		headers.append("Authorization: Account %s" % token)
	return headers


static func _post_vessel(
	session: Node,
	captain_id: String,
	hull_id: String,
	display: String,
	template_path: String,
	uid: String,
	registration_id: String,
	shaft_power_kw: float,
	brick_layout: Dictionary = {},
	on_complete: Callable = Callable(),
) -> void:
	var req := HTTPRequest.new()
	session.add_child(req)
	var body := JSON.stringify({
		"captain_id": captain_id,
		"client_uid": uid,
		"hull_id": hull_id,
		"registration_id": registration_id,
		"shaft_power_kw": shaft_power_kw,
		"display_name": display,
		"template_path": template_path,
		"brick_layout": brick_layout if not brick_layout.is_empty() else {"hull_id": hull_id, "cells": {}},
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
		var row := parsed as Dictionary
		var server_id := str(row.get("id", ""))
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
		record["layout_hash"] = str(row.get("layout_hash", ""))
		var layout_raw: Variant = row.get("brick_layout", null)
		if typeof(layout_raw) == TYPE_DICTIONARY and (
			_layout_has_configuration(layout_raw as Dictionary)
			or not _layout_has_configuration(VesselSpawn.brick_layout_of(record))
		):
			record["brick_layout"] = layout_raw
		session.data.upsert_owned_vessel(record)
		if str(session.data.active_vessel.get("uid", "")) == uid:
			session.data.set_active_vessel(record)
		if session.has_method("save_now"):
			session.call("save_now")
		_force_ship_meta_resync()
		print("[VesselSync] Registered vessel uid=%s server_id=%s hash=%s" % [
			uid, server_id, str(record.get("layout_hash", ""))
		])
		if on_complete.is_valid():
			on_complete.call(record)
	)
	req.request(url, _captain_headers(session, true), HTTPClient.METHOD_POST, body)


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
	req.request(url, _captain_headers(session))


static func _apply_server_vessels(session: Node, rows: Array, on_complete: Callable = Callable()) -> void:
	if session == null or not _is_mp_session(session):
		if on_complete.is_valid():
			on_complete.call()
		return
	if session.get("data") == null:
		if on_complete.is_valid():
			on_complete.call()
		return

	var data: PlayerData = session.data
	## A pull is an update, never a delete operation. Preserve every local ledger
	## row not represented by the response, including server-linked vessels.
	## Server deletion/tombstones require an explicit user-facing flow.
	var local_records := _collect_preserved_local_vessels(data.owned_vessels)
	var backfill := _collect_unregistered_local(data.owned_vessels)
	var merged: Array = []
	var seen_server_ids: Dictionary = {}
	var seen_uids: Dictionary = {}

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
		var uid := str(record.get("uid", ""))
		if not uid.is_empty():
			seen_uids[uid] = true
		merged.append(record)

	for local_raw in local_records:
		if typeof(local_raw) != TYPE_DICTIONARY:
			continue
		var local := local_raw as Dictionary
		var uid := str(local.get("uid", ""))
		var server_id := str(local.get("server_vessel_id", ""))
		if uid.is_empty() or seen_uids.has(uid) \
				or (not server_id.is_empty() and seen_server_ids.has(server_id)):
			continue
		seen_uids[uid] = true
		merged.append(local)

	var active_uid := str(data.active_vessel.get("uid", ""))
	var active_server_id := str(data.active_vessel.get("server_vessel_id", ""))
	data.owned_vessels = merged
	# Captains created by the old multiplayer flow have a valid server identity
	# but no company/starter grant. Repair that state once, using the exact same
	# certified prebuilt contract as normal onboarding. The deterministic UID and
	# server uniqueness constraint make this safe if two clients select the same
	# captain at nearly the same time.
	if rows.is_empty() and merged.is_empty():
		var captain_id := _captain_id(session)
		if not captain_id.is_empty() and not _starter_repairs.has(captain_id):
			_starter_repairs[captain_id] = true
			var starter := CompanyService.build_starter_vessel_record(
				"general_cargo", "starter-%s" % captain_id,
			)
			if not starter.is_empty():
				data.upsert_owned_vessel(starter)
				data.set_active_vessel(starter)
				merged.append(starter)
				data.owned_vessels = merged
				ensure_vessel_registered(session, starter, func(_updated: Dictionary) -> void:
					_starter_repairs.erase(captain_id)
				)

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
	if not backfill.is_empty():
		_backfill_vessel_records(session, backfill)


## Local save is the durability layer. Pull responses can update matching rows,
## but omission from a response is not proof that the player meant to delete one.
static func _collect_preserved_local_vessels(owned: Array) -> Array:
	var out: Array = []
	for entry_raw in owned:
		if typeof(entry_raw) != TYPE_DICTIONARY:
			continue
		var record := entry_raw as Dictionary
		if PlayerData.is_legacy_starter_vessel(record):
			continue
		var uid := str(record.get("uid", ""))
		if uid.is_empty():
			continue
		out.append(record.duplicate(true))
	return out


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
		## Skip in-flight / hard-failed for POST retry only — preservation uses
		## _collect_local_only_vessels and does not consult these flags.
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
	var registration_id := str(row.get("registration_id", "review_required"))
	var shaft_power_kw := float(row.get("shaft_power_kw", 1.0))
	if hull_id.is_empty():
		return {}

	var existing: Dictionary = data.find_owned_by_server_id(server_id)
	var fleet_patch := _fleet_patch_from_row(row)
	var layout_patch := _layout_patch_from_row(row, existing)
	var hull_entry := HullRegistry.get_by_id(hull_id)
	var hull_display := str(hull_entry.get("display", display))

	if not existing.is_empty():
		existing = PlayerData.merge_vessel_record(existing, {
			"name": display,
			"display": hull_display,
			"hull_id": hull_id,
			"registration_id": registration_id,
			"shaft_power_kw": shaft_power_kw,
		})
		existing = PlayerData.merge_vessel_record(existing, fleet_patch)
		existing = PlayerData.merge_vessel_record(existing, layout_patch)
		var path := str(existing.get("template_path", ""))
		if path.is_empty() or not ResourceLoader.exists(path):
			var rebuilt := _ensure_local_template(hull_id, hull_display)
			if rebuilt.is_empty():
				return {}
			existing["uid"] = rebuilt["uid"]
			existing["template_path"] = rebuilt["template_path"]
			existing["scene_path"] = rebuilt.get("scene_path", rebuilt["template_path"])
		return existing

	var client_uid := str(row.get("client_uid", ""))
	var local := _ensure_local_template(hull_id, hull_display, client_uid if not client_uid.is_empty() else server_id)
	if local.is_empty():
		return {}
	var record := {
		"uid":              local["uid"],
		"hull_id":          hull_id,
		"name":             display,
		"display":          hull_display,
		"registration_id": registration_id,
		"shaft_power_kw":   shaft_power_kw,
		"template_path":    local["template_path"],
		"server_vessel_id": server_id,
	}
	record = PlayerData.merge_vessel_record(record, fleet_patch)
	return PlayerData.merge_vessel_record(record, layout_patch)


static func _layout_patch_from_row(row: Dictionary, existing: Dictionary = {}) -> Dictionary:
	var patch: Dictionary = {}
	var hash := str(row.get("layout_hash", ""))
	var layout_raw: Variant = row.get("brick_layout", null)
	var layout: Dictionary = {}
	if typeof(layout_raw) == TYPE_DICTIONARY:
		layout = layout_raw as Dictionary
	elif typeof(layout_raw) == TYPE_STRING:
		var nested: Variant = JSON.parse_string(str(layout_raw))
		if typeof(nested) == TYPE_DICTIONARY:
			layout = nested as Dictionary
	## Never replace a configured local deck during a pull. A local refit may
	## have reached disk before its HTTP push completed; stale server JSON must
	## not erase ten minutes of work. Server layout hydrates only a bare record.
	var local_is_configured := _layout_has_configuration(
		VesselSpawn.brick_layout_of(existing)
	)
	if not layout.is_empty() and (
		layout.has("cells") or layout.has("bulk_holds") or layout.has("container_pads") or layout.has("hull_id")
	) and not local_is_configured:
		patch["brick_layout"] = layout
		if not hash.is_empty():
			patch["layout_hash"] = hash
	return patch


static func _layout_has_configuration(layout: Dictionary) -> bool:
	var cells_raw: Variant = layout.get("cells", {})
	if typeof(cells_raw) == TYPE_DICTIONARY and not (cells_raw as Dictionary).is_empty():
		return true
	var holds_raw: Variant = layout.get("bulk_holds", [])
	return typeof(holds_raw) == TYPE_ARRAY and not (holds_raw as Array).is_empty()


static func _fleet_patch_from_row(_row: Dictionary) -> Dictionary:
	# Autonomous fleet fields ignored after NPC-ship wipe.
	return {}


static func _ensure_local_template(
	hull_id: String,
	display: String,
	server_vessel_id: String = "",
) -> Dictionary:
	var entry := HullRegistry.get_by_id(hull_id)
	if entry.is_empty():
		return {}
	var uid := (
		"server_%s" % server_vessel_id
		if not server_vessel_id.is_empty()
		else VesselSpawn.new_vessel_uid(hull_id)
	)
	var scene_path := str(entry.get("scene_path", VesselSpawn.TRAWLER_SMALL_SCENE))
	return {
		"uid": uid,
		"template_path": scene_path,
		"scene_path": scene_path,
		"display": display,
		"hull_id": str(entry.get("id", "fishing_trawler_small")),
	}
