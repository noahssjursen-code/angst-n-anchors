class_name AutonomousVesselLoader
extends RefCounted

## Client-side fetch + proximity filter for autonomous NPC ships.
## Multiplayer: server / DB rows only. Single-player: local PlayerSession records.

const DEFAULT_PROXIMITY_M := 8000.0

signal vessels_loaded(records: Array)


static func load_near_player(
	session: Node,
	player_world_pos: Vector3,
	radius_m: float = DEFAULT_PROXIMITY_M,
	registry: Node = null,
) -> Array:
	var records := AutonomousVesselRecord.collect_active_from_session(session)
	return AutonomousVesselRecord.filter_nearby(
		records,
		Vector2(player_world_pos.x, player_world_pos.z),
		radius_m,
		registry,
	)


static func request_nearby(
	session: Node,
	player_world_pos: Vector3,
	port_id: String = "",
	radius_m: float = DEFAULT_PROXIMITY_M,
	on_complete: Callable = Callable(),
) -> void:
	if session == null:
		if on_complete.is_valid():
			on_complete.call([])
		return

	var registry := session.get_node_or_null("/root/ContractRegistry")
	var config := session.get_node_or_null("/root/ServerConfig")
	if config == null or not bool(config.get("is_multiplayer_mode")):
		var local := load_near_player(session, player_world_pos, radius_m, registry)
		if on_complete.is_valid():
			on_complete.call(local)
		return

	var query_port_id := resolve_query_port_id(player_world_pos, port_id, registry)
	if query_port_id.is_empty():
		if on_complete.is_valid():
			on_complete.call([])
		return

	var req := HTTPRequest.new()
	session.add_child(req)
	var base_url := str(config.call("get_http_base_url"))
	var url := "%s/v1/autonomous_vessels?port_id=%s" % [base_url, query_port_id.uri_encode()]
	req.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
		req.queue_free()
		var rows: Array = []
		if result == HTTPRequest.RESULT_SUCCESS and code == 200:
			var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
			if typeof(parsed) == TYPE_ARRAY:
				for row_raw in parsed as Array:
					if typeof(row_raw) == TYPE_DICTIONARY:
						rows.append(AutonomousVesselRecord.from_sync_dict(row_raw as Dictionary))
		var filtered := _filter_server_records(rows, player_world_pos, radius_m, registry)
		if filtered.is_empty() and rows.size() > 0:
			push_warning(
				"AutonomousVesselLoader: server returned %d vessels but none are active for port %s"
				% [rows.size(), query_port_id]
			)
		elif rows.is_empty():
			print("[AutonomousVesselLoader] No autonomous vessels at port %s" % query_port_id)
		else:
			print("[AutonomousVesselLoader] Loaded %d autonomous vessel(s) for port %s" % [filtered.size(), query_port_id])
		if on_complete.is_valid():
			on_complete.call(filtered)
	)
	var auth := session.get_node_or_null("/root/AuthSession")
	var headers := auth.call("auth_headers", "") if auth != null else PackedStringArray()
	req.request(url, headers)


static func resolve_query_port_id(
	player_world_pos: Vector3,
	context_port_id: String,
	registry: Node,
) -> String:
	if not context_port_id.is_empty():
		return context_port_id
	if registry == null or not registry.has_method("nearest_port_id"):
		return ""
	var xz := Vector2(player_world_pos.x, player_world_pos.z)
	return str(registry.call("nearest_port_id", xz, INF))


## MP spawn dict — uid always keyed by server vessel id so every client matches.
static func spawn_dict_from_server(rec: AutonomousVesselRecord) -> Dictionary:
	var base := rec.merge_into_owned_vessel({})
	base["hull_id"] = rec.hull_id
	base["display"] = rec.display_name
	base["template_path"] = rec.template_path
	if rec.id.is_empty():
		return base
	base["server_vessel_id"] = rec.id
	base["uid"] = "mp_%s" % rec.id
	return base


## SP spawn dict — local owned-vessel uid and save fields.
static func spawn_dict_from_local(rec: AutonomousVesselRecord) -> Dictionary:
	var base: Dictionary
	if not rec.id.is_empty():
		var local := _find_local_owned(rec.id).duplicate(true)
		if local.is_empty():
			base = rec.merge_into_owned_vessel({})
		else:
			base = PlayerData.merge_vessel_record(local, rec.to_owned_vessel_patch())
	else:
		base = rec.merge_into_owned_vessel({})

	base["hull_id"] = rec.hull_id
	base["display"] = rec.display_name
	base["template_path"] = rec.template_path
	if not rec.id.is_empty():
		base["server_vessel_id"] = rec.id
	if str(base.get("uid", "")).is_empty() and not rec.id.is_empty():
		base["uid"] = rec.id
	return base


static func _find_local_owned(server_or_uid: String) -> Dictionary:
	if server_or_uid.is_empty():
		return {}
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return {}
	var session: Node = tree.root.get_node_or_null("/root/PlayerSession")
	if session == null or session.get("data") == null:
		return {}
	var data: PlayerData = session.data as PlayerData
	var by_server := data.find_owned_by_server_id(server_or_uid)
	if not by_server.is_empty():
		return by_server
	return data.find_owned_vessel(server_or_uid)


static func resolve_template_path(record: Dictionary) -> String:
	var path := str(record.get("template_path", ""))
	if not path.is_empty() and FileAccess.file_exists(path):
		return path
	var hull_id := str(record.get("hull_id", ""))
	if hull_id.is_empty():
		path = str(record.get("template_path", ""))
		if not path.is_empty():
			hull_id = HullRegistry.resolve_id_from_template(path, hull_id)
	if hull_id.is_empty():
		return ""
	var display := str(record.get("display", record.get("display_name", "Vessel")))
	DirAccess.make_dir_recursive_absolute("user://mp_hull_templates")
	var cache_path := "user://mp_hull_templates/%s.json" % hull_id
	if FileAccess.file_exists(cache_path):
		return cache_path
	var entry := HullRegistry.get_by_id(hull_id)
	if entry.is_empty():
		return ""
	var template := StarterVessel.build_template(entry)
	template["display_name"] = display
	var f := FileAccess.open(cache_path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(JSON.stringify(template))
	f.close()
	return cache_path


static func resolve_deployable_record(record: Dictionary) -> Dictionary:
	if record.is_empty():
		return {}
	var path := resolve_template_path(record)
	if path.is_empty():
		return {}
	var out := record.duplicate(true)
	out["template_path"] = path
	return out


static func _filter_server_records(
	rows: Array,
	player_world_pos: Vector3,
	radius_m: float,
	registry: Node,
) -> Array:
	var out: Array = []
	for rec_raw in rows:
		if not rec_raw is AutonomousVesselRecord:
			continue
		var rec := rec_raw as AutonomousVesselRecord
		rec.hydrate_ports(registry)
		if not rec.active:
			continue
		# Server already filtered by port + autonomous_active; keep all active rows.
		out.append(rec)
	return out
