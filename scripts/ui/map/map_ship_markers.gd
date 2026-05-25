class_name MapShipMarkers
extends RefCounted

## Builds sea-chart ship markers from session sim, scene nodes, and MP `/v1/entities`.

const POLL_SEC := 12.0
const LOCAL_PLAYER_DEDUPE_M := 100.0
const MARKER_DEDUPE_M := 35.0

enum Kind { AUTONOMOUS, OWN_REMOTE, OTHER }


static func color_for(kind: Kind) -> Color:
	match kind:
		Kind.AUTONOMOUS:
			return Color(0.35, 0.82, 0.92, 0.95)
		Kind.OWN_REMOTE:
			return Color(0.96, 0.66, 0.12, 0.92)
		_:
			return Color(0.72, 0.78, 0.90, 0.88)


static func collect_own_autonomous(session: Node) -> Array:
	var out: Array = []
	if session == null:
		return out
	for rec_raw in AutonomousVesselRecord.collect_active_from_session(session):
		var rec := rec_raw as AutonomousVesselRecord
		if rec == null:
			continue
		var spawn := AutonomousVesselLoader.spawn_dict_from_local(rec)
		var sample := AutonomousVesselSim.sample(spawn)
		if not bool(sample.get("valid", false)):
			continue
		var pos: Vector3 = sample.get("position", Vector3.ZERO)
		var yaw := float(sample.get("yaw", 0.0))
		out.append(_make_marker(pos, sim_yaw_to_bow_hz(yaw), Kind.AUTONOMOUS, rec.display_name))
	return out


static func append_scene_autonomous(tree: SceneTree, session: Node, out: Array) -> void:
	if tree == null:
		return
	for node in tree.get_nodes_in_group(AutonomousNpcShip.GROUP):
		var ctrl := node as AutonomousNpcShip
		if ctrl == null:
			continue
		var body := ctrl.get_body()
		if body == null or not is_instance_valid(body):
			continue
		var record := ctrl.get_live_record()
		if record.is_empty() or not bool(record.get("autonomous_active", false)):
			continue
		if _is_local_autonomous_vessel(session, ctrl.vessel_uid, ctrl.server_vessel_id, record):
			continue
		var pos := body.global_position
		var bow := NavigationAxes.vessel_bow_horizontal(body)
		var label := str(record.get("display", record.get("display_name", "Vessel")))
		_append_unique(out, _make_marker(pos, bow, Kind.AUTONOMOUS, label))


static func append_server_autonomous_markers(
	body: PackedByteArray,
	session: Node,
	out: Array,
) -> void:
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) != TYPE_ARRAY:
		return
	var captain := _local_captain_id(session)
	for row_raw in parsed as Array:
		if typeof(row_raw) != TYPE_DICTIONARY:
			continue
		var rec := AutonomousVesselRecord.from_sync_dict(row_raw as Dictionary)
		if not rec.active:
			continue
		if not captain.is_empty() and rec.owner_id == captain:
			continue
		rec.hydrate_ports()
		var spawn := AutonomousVesselLoader.spawn_dict_from_server(rec)
		var sample := AutonomousVesselSim.sample(spawn)
		if not bool(sample.get("valid", false)):
			continue
		var pos: Vector3 = sample.get("position", Vector3.ZERO)
		var yaw := float(sample.get("yaw", 0.0))
		_append_unique(
			out,
			_make_marker(pos, sim_yaw_to_bow_hz(yaw), Kind.AUTONOMOUS, rec.display_name),
		)


static func append_entity_markers(
	body: PackedByteArray,
	session: Node,
	tree: SceneTree,
	out: Array,
) -> void:
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var entities: Variant = (parsed as Dictionary).get("entities", [])
	if typeof(entities) != TYPE_ARRAY:
		return
	for ent_raw in entities as Array:
		if typeof(ent_raw) != TYPE_DICTIONARY:
			continue
		var ent := ent_raw as Dictionary
		var type_name := str(ent.get("type", ""))
		if not type_name.begins_with("ship"):
			continue
		var pos := Vector3(
			float(ent.get("x", 0.0)),
			float(ent.get("y", 0.0)),
			float(ent.get("z", 0.0)),
		)
		if near_local_player(pos, tree, LOCAL_PLAYER_DEDUPE_M):
			continue
		var payload: Array = []
		var payload_raw: Variant = ent.get("payload", [])
		if typeof(payload_raw) == TYPE_ARRAY:
			payload = payload_raw
		var bow := bow_hz_from_entity_payload(payload)
		var owner_id := str(ent.get("owner_id", ""))
		var kind := Kind.OTHER
		if _is_local_owner(owner_id, session):
			kind = Kind.OWN_REMOTE
		_append_unique(out, _make_marker(pos, bow, kind, ""))


static func dedupe_markers(markers: Array) -> Array:
	var out: Array = []
	for marker_raw in markers:
		if typeof(marker_raw) != TYPE_DICTIONARY:
			continue
		_append_unique(out, marker_raw as Dictionary)
	return out


static func near_local_player(pos: Vector3, tree: SceneTree, radius_m: float) -> bool:
	if tree == null:
		return false
	for node in tree.get_nodes_in_group("player_boat"):
		var body := node as Node3D
		if body == null or not is_instance_valid(body):
			continue
		var lp := body.global_position
		if Vector2(pos.x, pos.z).distance_to(Vector2(lp.x, lp.z)) <= radius_m:
			return true
	return false


static func sim_yaw_to_bow_hz(yaw: float) -> Vector2:
	var dir := Vector3(-sin(yaw), 0.0, -cos(yaw))
	if dir.length_squared() < 1e-10:
		return Vector2(0.0, -1.0)
	dir = dir.normalized()
	return Vector2(dir.x, dir.z)


static func bow_hz_from_entity_payload(payload: Array) -> Vector2:
	if payload.size() >= 6:
		var ry := float(payload[4])
		if is_finite(ry):
			return sim_yaw_to_bow_hz(ry)
	return Vector2(0.0, -1.0)


static func _make_marker(pos: Vector3, bow_hz: Vector2, kind: Kind, label: String) -> Dictionary:
	var bow := bow_hz
	if bow.length_squared() < 1e-10:
		bow = Vector2(0.0, -1.0)
	else:
		bow = bow.normalized()
	return {
		"pos": pos,
		"bow_hz": bow,
		"kind": kind,
		"label": label,
	}


static func _append_unique(out: Array, marker: Dictionary) -> void:
	var pos: Vector3 = marker.get("pos", Vector3.ZERO)
	for existing_raw in out:
		if typeof(existing_raw) != TYPE_DICTIONARY:
			continue
		var existing := existing_raw as Dictionary
		var other: Vector3 = existing.get("pos", Vector3.ZERO)
		if Vector2(pos.x, pos.z).distance_to(Vector2(other.x, other.z)) <= MARKER_DEDUPE_M:
			return
	out.append(marker)


static func _is_local_autonomous_vessel(
	session: Node,
	vessel_uid: String,
	server_vessel_id: String,
	record: Dictionary,
) -> bool:
	var record_owner := str(record.get("owner_id", ""))
	var captain := _local_captain_id(session)
	if not record_owner.is_empty() and not captain.is_empty() and record_owner == captain:
		return true
	if session == null:
		return false
	for rec_raw in AutonomousVesselRecord.collect_active_from_session(session):
		var rec := rec_raw as AutonomousVesselRecord
		if rec == null:
			continue
		if not server_vessel_id.is_empty() and rec.id == server_vessel_id:
			return true
		if not vessel_uid.is_empty() and rec.id == vessel_uid:
			return true
	return false


static func _local_captain_id(session: Node) -> String:
	if session == null or session.get("data") == null:
		return ""
	return str(session.data.captain_id)


static func _is_local_owner(owner_id: String, session: Node) -> bool:
	if owner_id.is_empty():
		return false
	var captain := _local_captain_id(session)
	if not captain.is_empty() and owner_id == captain:
		return true
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return false
	var nm := tree.root.get_node_or_null("/root/NetworkManager")
	if nm != null and nm.has_method("get_local_player_id"):
		var local_id := str(nm.call("get_local_player_id"))
		if local_id.is_empty():
			return false
		if owner_id == local_id:
			return true
		var idx := local_id.rfind("_")
		if idx > 0:
			var suffix := local_id.substr(idx + 1)
			if suffix.is_valid_int() and owner_id == local_id.substr(0, idx):
				return true
	return false
