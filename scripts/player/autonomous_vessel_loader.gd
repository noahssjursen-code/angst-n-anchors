class_name AutonomousVesselLoader
extends RefCounted

## Client-side fetch + proximity filter for autonomous NPC ships.
## Wire-up to MP happens later — today this normalises local active fleet records.

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


## Future: GET /v1/autonomous_vessels?x=&z=&radius=
static func request_nearby_from_server(
	session: Node,
	player_world_pos: Vector3,
	radius_m: float = DEFAULT_PROXIMITY_M,
	on_complete: Callable = Callable(),
) -> void:
	if session == null:
		if on_complete.is_valid():
			on_complete.call([])
		return
	var config := session.get_node_or_null("/root/ServerConfig")
	if config == null or not bool(config.get("is_multiplayer_mode")):
		var local := load_near_player(session, player_world_pos, radius_m)
		if on_complete.is_valid():
			on_complete.call(local)
		return

	var req := HTTPRequest.new()
	session.add_child(req)
	var base_url := str(config.call("get_http_base_url"))
	var url := "%s/v1/autonomous_vessels?x=%f&z=%f&radius=%f" % [
		base_url,
		player_world_pos.x,
		player_world_pos.z,
		radius_m,
	]
	req.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
		req.queue_free()
		var out: Array = []
		if result == HTTPRequest.RESULT_SUCCESS and code == 200:
			var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
			if typeof(parsed) == TYPE_ARRAY:
				for row_raw in parsed as Array:
					if typeof(row_raw) == TYPE_DICTIONARY:
						out.append(AutonomousVesselRecord.from_sync_dict(row_raw as Dictionary))
		if on_complete.is_valid():
			on_complete.call(out)
	)
	req.request(url)
