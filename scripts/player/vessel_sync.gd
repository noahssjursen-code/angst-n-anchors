class_name VesselSync
extends RefCounted

## Keeps the captain's owned fleet aligned with Postgres `/v1/vessels`.
## Commissioning appends rows; harbour master picks which hull to deploy.


static var _in_flight_registrations: Dictionary = {}
static var _registration_callbacks: Dictionary = {}
static var _failed_registrations: Dictionary = {}
static var _in_flight_pull: bool = false
static var _pending_pull_callbacks: Array = []
static var _starter_repairs: Dictionary = {}


## Server commits payment and the fleet row atomically. Never register a locally
## purchased ship as a substitute for a failed or uncertain remote purchase.
static func purchase(session: Node, command: Dictionary) -> Dictionary:
	var base := _http_base(session)
	var captain := _captain_id(session)
	var request := HTTPRequest.new()
	request.timeout = 20.0
	session.add_child(request)
	var payload := command.duplicate(true)
	payload["captain_id"] = captain
	var error := request.request(base + "/v1/vessels/purchase", _captain_headers(session, true), HTTPClient.METHOD_POST, JSON.stringify(payload))
	if error != OK:
		request.queue_free()
		return CompanyContracts.result_error("transport", "Could not contact the shipwright. Retry this order.")
	var response: Array = await request.request_completed
	request.queue_free()
	if not _same_session(session, captain, base):
		return CompanyContracts.result_error("session_changed", "Captain changed while purchasing. Refresh that captain's fleet on reconnect.")
	var parsed: Variant = JSON.parse_string((response[3] as PackedByteArray).get_string_from_utf8())
	if int(response[0]) != HTTPRequest.RESULT_SUCCESS or int(response[1]) != 200 or not parsed is Dictionary:
		var message := "Purchase not confirmed. Retry this same order; it cannot charge twice."
		if parsed is Dictionary: message = str(parsed.get("error", message))
		return CompanyContracts.result_error("purchase_failed", message)
	var record := _merge_server_row(session.data, parsed.get("vessel", {}))
	if record.is_empty():
		return CompanyContracts.result_error("fleet_refresh", "Purchase saved on server, but this client cannot load its blueprint. Update the client and reconnect.")
	session.data.upsert_owned_vessel(record)
	if session.data.active_vessel.is_empty(): session.data.set_active_vessel(record)
	session.data.marks = int(parsed.balance_nok)
	var account: Dictionary = session.data.company.get("account", {}).duplicate(true)
	account["balance_marks"] = session.data.marks
	session.data.company["account"] = account
	session.data.company["tablet_received"] = true
	return CompanyContracts.result_ok({"vessel": record, "price_marks": int(parsed.price_nok), "balance_marks": session.data.marks})


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
	var blocked := live_refit_block_reason(session, record)
	if not blocked.is_empty():
		push_warning("VesselSync: " + blocked)
		if on_complete.is_valid(): on_complete.call({})
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
	var submitted := record.duplicate(true)
	var req := HTTPRequest.new()
	req.timeout = 12.0
	session.add_child(req)
	var captain := _captain_id(session)
	var base := _http_base(session)
	var body := JSON.stringify({
		"id": server_id,
		"brick_layout": layout,
	})
	var url := "%s/v1/vessels" % _http_base(session)
	req.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, resp_body: PackedByteArray) -> void:
		req.queue_free()
		if not _same_session(session, captain, base):
			if on_complete.is_valid(): on_complete.call({})
			return
		if result != HTTPRequest.RESULT_SUCCESS or code != 200:
			push_warning("VesselSync: failed to push brick_layout (HTTP %d)" % code)
			if on_complete.is_valid():
				on_complete.call({})
			return
		var parsed: Variant = JSON.parse_string(resp_body.get_string_from_utf8())
		if typeof(parsed) != TYPE_DICTIONARY or session.get("data") == null:
			if on_complete.is_valid():
				on_complete.call({})
			return
		var row := parsed as Dictionary
		if str(row.get("id", "")) != server_id or _decoded_layout(row.get("brick_layout", {})).is_empty():
			if on_complete.is_valid(): on_complete.call({})
			return
		var updated := submitted.duplicate(true)
		updated["layout_hash"] = str(row.get("layout_hash", ""))
		updated.merge(_construction_patch(row), true)
		updated["brick_layout"] = _decoded_layout(row.get("brick_layout", {}))
		apply_accepted_live_vessel(session, updated)
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
	if req.request(url, _captain_headers(session, true), HTTPClient.METHOD_PUT, body) != OK:
		req.queue_free()
		if on_complete.is_valid(): on_complete.call({})


static func fetch_vessel_layout(session: Node, server_vessel_id: String, on_complete: Callable) -> void:
	## Remote clients: GET /v1/vessels?id=<uuid> → { brick_layout, layout_hash, … }.
	fetch_vessel_record(session, server_vessel_id, func(row: Dictionary) -> void:
		if on_complete.is_valid():
			on_complete.call(_decoded_layout(row.get("brick_layout", {})), str(row.get("layout_hash", "")))
	)


## Fetch the accepted server row for owner deployment as well as observers.
## An empty response means failure; callers must not silently deploy a local draft.
static func fetch_vessel_record(session: Node, server_vessel_id: String, on_complete: Callable) -> HTTPRequest:
	if server_vessel_id.is_empty():
		if on_complete.is_valid(): on_complete.call({})
		return null
	return _fetch_public_record(session, "/v1/vessels?id=" + server_vessel_id.uri_encode(), func(row: Dictionary) -> void:
		if not on_complete.is_valid(): return
		if str(row.get("id", "")) != server_vessel_id:
			on_complete.call({})
			return
		var construction_id := str(row.get("construction_id", ""))
		if construction_id.is_empty():
			# Explicit compatibility for records saved before immutable builds.
			row["brick_layout"] = _decoded_layout(row.get("brick_layout", {}))
			on_complete.call(row)
			return
		fetch_vessel_construction(session, construction_id, func(construction: Dictionary) -> void:
			if not on_complete.is_valid(): return
			if not construction_matches(construction_id, construction):
				on_complete.call({})
				return
			var layout: Dictionary = construction.layout
			if str(row.get("hull_id", "")) != str(layout.get("hull", "")):
				on_complete.call({})
				return
			row["brick_layout"] = layout.duplicate(true)
			row["catalog_hash"] = construction.catalog_hash
			on_complete.call(row)
		)
	)


## Immutable accepted construction, independent of the current mutable vessel row.
static func fetch_vessel_construction(session: Node, construction_id: String, on_complete: Callable) -> HTTPRequest:
	if construction_id.is_empty():
		if on_complete.is_valid(): on_complete.call({})
		return null
	return _fetch_public_record(session, "/v2/constructions?id=" + construction_id.uri_encode(), on_complete)


static func construction_matches(construction_id: String, construction: Dictionary) -> bool:
	if construction_id.is_empty() or str(construction.get("id", "")) != construction_id:
		return false
	if int(construction.get("schema_version", 0)) != 1:
		return false
	if str(construction.get("catalog_hash", "")) != FileAccess.get_sha256(AuthorityVesselAssembly.CATALOG):
		return false
	var raw: Variant = construction.get("layout")
	return raw is Dictionary and ImportedVesselLayout.valid(raw, str(raw.get("hull", "")))


static func _fetch_public_record(session: Node, endpoint: String, on_complete: Callable) -> HTTPRequest:
	if not on_complete.is_valid(): return null
	if session == null or not is_instance_valid(session) or _http_base(session).is_empty():
		on_complete.call({})
		return null
	var req := HTTPRequest.new()
	req.timeout = 12.0
	req.body_size_limit = 8 * 1024 * 1024
	session.add_child(req)
	req.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
		req.queue_free()
		if not on_complete.is_valid(): return
		if result != HTTPRequest.RESULT_SUCCESS or code != 200:
			on_complete.call({})
			return
		var decoded: Variant = JSON.parse_string(body.get_string_from_utf8())
		on_complete.call(decoded if decoded is Dictionary else {})
	)
	var error := req.request(_http_base(session) + endpoint)
	if error != OK:
		req.queue_free()
		on_complete.call({})
		return null
	return req


static func _decoded_layout(raw: Variant) -> Dictionary:
	if raw is Dictionary: return (raw as Dictionary).duplicate(true)
	if raw is String:
		var decoded: Variant = JSON.parse_string(raw)
		if decoded is Dictionary: return decoded
	return {}


## Construction references travel with the owned record, never inside the layout.
static func _construction_patch(row: Dictionary) -> Dictionary:
	var patch := {}
	for field in ["construction_id", "catalog_hash"]:
		if row.has(field): patch[field] = str(row[field])
	return patch


## A refit rebuilds installed storage components. Until their authoritative
## inventory migration is complete, refuse to discard occupied live storage.
static func live_refit_block_reason(session: Node, record: Dictionary) -> String:
	var ship := _matching_live_owned_ship(session, record)
	if ship == null: return ""
	var layout := VesselSpawn.brick_layout_of(record)
	if ship is ImportedDraftVessel and ship.draft == layout: return ""
	for pad in ship.get_cargo_pads():
		if not pad.get_containers().is_empty(): return "Unload the vessel's containers before changing its construction."
	for hold in ship.get_bulk_holds():
		if not hold.state.is_empty(): return "Unload the vessel's bulk cargo before changing its construction."
	for hold in ship.get_catch_holds():
		if not hold.state.is_empty(): return "Land the vessel's catch before changing its construction."
	var controller := ship.get_node_or_null("BoatController") as BoatController
	if controller != null and controller._active:
		return "Leave the helm before changing the vessel's construction."
	return ""


## Owner and observer must show the same accepted build. Match persistent
## vessel identity instead of rebuilding whichever boat happens to be active.
static func apply_accepted_live_vessel(session: Node, record: Dictionary) -> bool:
	var ship := _matching_live_owned_ship(session, record)
	if ship == null: return true
	var blocked := live_refit_block_reason(session, record)
	if not blocked.is_empty():
		push_warning("VesselSync: accepted refit awaits a safe redeployment: " + blocked)
		return false
	var layout := VesselSpawn.brick_layout_of(record)
	if ship is ImportedDraftVessel:
		if not ImportedVesselLayout.valid(layout, str(ship.draft.get("hull", ""))): return false
	if ship.has_method("apply_brick_layout"):
		ship.call("apply_brick_layout", layout)
	VesselSpawn.apply_propulsion_override(ship, record)
	VesselSpawn.apply_identity(ship, record)
	var manager := session.get_node_or_null("/root/NetworkManager")
	if manager != null and manager.has_method("refresh_ship_fitout"):
		manager.call("refresh_ship_fitout", ship)
	_force_ship_meta_resync()
	return true


static func _matching_live_owned_ship(session: Node, record: Dictionary) -> BoatBody:
	if session == null or not is_instance_valid(session) or not session.is_inside_tree(): return null
	var vid := str(record.get("server_vessel_id", ""))
	var uid := str(record.get("uid", ""))
	for raw: Node in session.get_tree().get_nodes_in_group(PlayerVessel.GROUP):
		var ship := raw as BoatBody
		if ship == null or bool(ship.get_meta("remote_replica", false)): continue
		var ship_vid := str(ship.get_meta("server_vessel_id", ""))
		if not ship_vid.is_empty():
			if ship_vid == vid: return ship
		elif not uid.is_empty() and str(ship.get_meta("vessel_uid", "")) == uid:
			# First registration may give an already-present local hull its id.
			return ship
	return null


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
			on_complete.call({})
		return
	var key := _registration_key(session, uid)
	if _in_flight_registrations.has(key):
		if on_complete.is_valid(): _registration_callbacks[key].append(on_complete)
		return

	var captain_id := _captain_id(session)
	var hull_id := str(record.get("hull_id", ""))
	var display := VesselSpawn.vessel_name_of(record)
	var template_path := str(record.get("template_path", ""))
	if captain_id.is_empty() or hull_id.is_empty():
		push_warning("VesselSync: cannot register vessel — missing captain_id or hull_id")
		if on_complete.is_valid():
			on_complete.call({})
		return

	_in_flight_registrations[key] = true
	_registration_callbacks[key] = [on_complete] if on_complete.is_valid() else []
	var layout := VesselSpawn.brick_layout_of(record)
	var registration_finished := func(updated: Dictionary) -> void:
		_in_flight_registrations.erase(key)
		if updated.is_empty() or str(updated.get("server_vessel_id", "")).is_empty():
			_failed_registrations[key] = true
			push_warning("VesselSync: registration failed for local vessel uid=%s" % uid)
		else:
			_failed_registrations.erase(key)
		var callbacks: Array = _registration_callbacks.get(key, [])
		_registration_callbacks.erase(key)
		for callback: Callable in callbacks:
			if callback.is_valid(): callback.call(updated.duplicate(true))
	_post_vessel(
		session, captain_id, hull_id, display, template_path, uid,
		str(record.get("registration_id", "review_required")),
		float(record.get("shaft_power_kw", 1.0)), layout,
		registration_finished,
		record,
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
		var key := _registration_key(session, uid)
		if uid.is_empty() or _in_flight_registrations.has(key) or _failed_registrations.has(key):
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


static func _registration_key(session: Node, uid: String) -> String:
	return _http_base(session) + "|" + _captain_id(session) + "|" + uid


static func _same_session(session: Node, captain: String, base: String) -> bool:
	return is_instance_valid(session) and _captain_id(session) == captain and _http_base(session) == base and _is_mp_session(session)


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
	source_record: Dictionary = {},
) -> void:
	var submitted := source_record.duplicate(true)
	var req := HTTPRequest.new()
	req.timeout = 12.0
	session.add_child(req)
	var base := _http_base(session)
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
		if not _same_session(session, captain_id, base):
			if on_complete.is_valid(): on_complete.call({})
			return
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
		var record: Dictionary = submitted.duplicate(true)
		if record.is_empty(): record = session.data.find_owned_vessel(uid)
		if record.is_empty() or _decoded_layout(row.get("brick_layout", {})).is_empty():
			if on_complete.is_valid():
				on_complete.call({})
			return
		record["server_vessel_id"] = server_id
		record["layout_hash"] = str(row.get("layout_hash", ""))
		record.merge(_construction_patch(row), true)
		record["brick_layout"] = _decoded_layout(row.get("brick_layout", {}))
		apply_accepted_live_vessel(session, record)
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
	if req.request(url, _captain_headers(session, true), HTTPClient.METHOD_POST, body) != OK:
		req.queue_free()
		if on_complete.is_valid(): on_complete.call({})


static func _fetch_vessels(session: Node, captain_id: String, on_complete: Callable = Callable()) -> void:
	var req := HTTPRequest.new()
	req.timeout = 12.0
	session.add_child(req)
	var base := _http_base(session)
	var url := "%s/v1/vessels?captain_id=%s" % [_http_base(session), captain_id.uri_encode()]
	req.request_completed.connect(func(result: int, response_code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
		req.queue_free()
		if not _same_session(session, captain_id, base):
			if on_complete.is_valid(): on_complete.call()
			return
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
	if req.request(url, _captain_headers(session)) != OK:
		req.queue_free()
		if on_complete.is_valid(): on_complete.call()


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
	var backfill := _collect_unregistered_local(data.owned_vessels, session)
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
			if not str(entry.get("construction_id", "")).is_empty():
				apply_accepted_live_vessel(session, entry)
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


static func _collect_unregistered_local(owned: Array, session: Node = null) -> Array:
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
		var key := _registration_key(session, uid) if session != null else uid
		if uid.is_empty() or _in_flight_registrations.has(key) or _failed_registrations.has(key):
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
	if not str(row.get("construction_id", "")).is_empty() and layout_patch.is_empty():
		# An incompatible build must not combine new identity/hull fields with
		# an old local layout. Deployment will report the catalog mismatch.
		return existing
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
			var rebuilt := _ensure_local_template(hull_id, hull_display, server_id)
			if rebuilt.is_empty():
				return {}
			if str(existing.get("uid", "")).is_empty(): existing["uid"] = rebuilt["uid"]
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
	# New imported records carry an accepted immutable version. The fleet
	# ledger follows server truth; unfinished editor drafts live separately.
	# Keep the old preservation policy only for pre-construction legacy rows.
	if not str(row.get("construction_id", "")).is_empty():
		if not construction_matches(str(row.construction_id), {
			"schema_version": 1, "id": row.construction_id,
			"catalog_hash": row.get("catalog_hash", ""), "layout": layout,
		}):
			return {}
		patch["brick_layout"] = layout
		patch["layout_hash"] = hash
		patch.merge(_construction_patch(row), true)
		return patch
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
		patch.merge(_construction_patch(row), true)
	elif not layout.is_empty() and layout == VesselSpawn.brick_layout_of(existing):
		# Confirm a previously accepted local copy without associating the new
		# server identity with a different, unsaved local draft.
		patch.merge(_construction_patch(row), true)
		if not hash.is_empty(): patch["layout_hash"] = hash
	return patch


static func _layout_has_configuration(layout: Dictionary) -> bool:
	if ImportedVesselLayout.is_imported(layout) and layout.get("parts") is Array and not layout.parts.is_empty(): return true
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
