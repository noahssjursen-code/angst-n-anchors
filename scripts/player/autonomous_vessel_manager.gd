extends Node

## Autonomous fleet NPC hulls.
## Single-player: sim + render from local PlayerSession owned_vessels.
## Multiplayer: sim + render from server `/v1/autonomous_vessels` for every client.

const WorldReference := preload("res://scripts/world/world_reference.gd")
const BerthApproachLanesDebugDraw := preload("res://scripts/navigation/berth_approach_lanes_debug_draw.gd")
const REFRESH_INTERVAL_S := 2.0

var _controllers: Dictionary = {}  ## uid -> AutonomousNpcShip
var _server_records: Dictionary = {}  ## mp_* uid -> record (multiplayer only)
var _refresh_clock: float = 0.0
var _transit_debug_draw: AutonomousTransitDebugDraw
var _lane_debug_draw: BerthApproachLanesDebugDraw
var _fetch_in_flight: bool = false
var _context_port_id: String = ""
var _pending_fleet_push: Dictionary = {}  ## uid -> { record, at_ms }
const FLEET_PUSH_DEBOUNCE_MS := 2000


func _ready() -> void:
	var session := get_node_or_null("/root/PlayerSession")
	if session != null:
		if session.has_signal("data_loaded") and not session.data_loaded.is_connected(_on_session_data):
			session.data_loaded.connect(_on_session_data)
		if session.has_signal("vessels_synced") and not session.vessels_synced.is_connected(_on_session_data):
			session.vessels_synced.connect(_on_session_data)

	var gs := get_node_or_null("/root/GameState")
	if gs != null and gs.get("world") != null:
		var world_state := gs.world as WorldState
		if not world_state.nearest_port_changed.is_connected(_on_nearest_port_changed):
			world_state.nearest_port_changed.connect(_on_nearest_port_changed)
		_context_port_id = world_state.nearest_port_id

	call_deferred("refresh_all")
	call_deferred("_ensure_transit_debug_draw")
	call_deferred("_ensure_lane_debug_draw")


func _process(delta: float) -> void:
	_flush_pending_fleet_push()
	_refresh_clock += delta
	if _refresh_clock < REFRESH_INTERVAL_S:
		return
	_refresh_clock = 0.0
	_sync_controller_records()
	if _world_root() != null:
		refresh_all()


func apply_record_update(uid: String, record: Dictionary) -> void:
	if uid.is_empty() or record.is_empty():
		return

	var ctrl = _controllers.get(uid)
	if ctrl != null and is_instance_valid(ctrl):
		(ctrl as AutonomousNpcShip).sync_record(record)

	if _server_records.has(uid):
		_server_records[uid] = record.duplicate(true)
		_schedule_fleet_push(uid, record)
		return

	var data := _player_data()
	if data == null:
		return
	if data.find_owned_vessel(uid).is_empty():
		return
	data.upsert_owned_vessel(record)
	var session := get_node_or_null("/root/PlayerSession")
	if session != null and session.has_method("_request_save"):
		session.call("_request_save")


func _schedule_fleet_push(uid: String, record: Dictionary) -> void:
	_pending_fleet_push[uid] = {
		"record": record.duplicate(true),
		"at_ms": Time.get_ticks_msec(),
	}


func _flush_pending_fleet_push() -> void:
	if _pending_fleet_push.is_empty():
		return
	var now := Time.get_ticks_msec()
	var session := get_node_or_null("/root/PlayerSession")
	for uid in _pending_fleet_push.keys():
		var pending: Dictionary = _pending_fleet_push[uid]
		if now - int(pending.get("at_ms", 0)) < FLEET_PUSH_DEBOUNCE_MS:
			continue
		_pending_fleet_push.erase(uid)
		if session == null:
			continue
		VesselSync.push_fleet_state(session, pending.get("record", {}) as Dictionary)


func refresh_all() -> void:
	_ensure_transit_debug_draw()
	_ensure_lane_debug_draw()
	var session := get_node_or_null("/root/PlayerSession")
	if session == null:
		return
	if _fetch_in_flight:
		return

	var pos := _reference_position()
	if _is_mp_session():
		_fetch_in_flight = true
		AutonomousVesselLoader.request_nearby(
			session,
			pos,
			_nearest_port_id(),
			AutonomousVesselLoader.DEFAULT_PROXIMITY_M,
			_on_server_records,
		)
	else:
		_apply_record_list(AutonomousVesselLoader.load_near_player(session, pos), false)


func refresh_vessel(_uid: String = "") -> void:
	if _is_mp_session():
		call_deferred("refresh_all")
		return
	var data := _player_data()
	if data == null or _uid.is_empty():
		return
	var record: Dictionary = data.find_owned_vessel(_uid)
	if record.is_empty() or not bool(record.get("autonomous_active", false)) or _should_skip_record(record):
		_despawn_uid(_uid)
		return
	_ensure_spawn(record)


func _on_session_data(_data: Variant = null) -> void:
	call_deferred("refresh_all")


func _on_nearest_port_changed(port_id: String) -> void:
	if port_id == _context_port_id:
		return
	_context_port_id = port_id
	call_deferred("refresh_all")


func _on_server_records(records: Array) -> void:
	_fetch_in_flight = false
	_apply_record_list(records, true)


func _apply_record_list(records: Array, from_server: bool) -> void:
	var keep: Dictionary = {}
	for rec_raw in records:
		var record: Dictionary
		if rec_raw is AutonomousVesselRecord:
			var rec := rec_raw as AutonomousVesselRecord
			record = (
				AutonomousVesselLoader.spawn_dict_from_server(rec)
				if from_server
				else AutonomousVesselLoader.spawn_dict_from_local(rec)
			)
		elif typeof(rec_raw) == TYPE_DICTIONARY:
			record = rec_raw as Dictionary
		else:
			continue
		var uid := str(record.get("uid", ""))
		if uid.is_empty():
			continue
		if not bool(record.get("autonomous_active", false)):
			continue
		if _should_skip_record(record):
			continue
		if from_server:
			_server_records[uid] = record.duplicate(true)
		keep[uid] = true
		_ensure_spawn(record)

	if from_server:
		for uid in _server_records.keys():
			if not keep.has(uid):
				_server_records.erase(uid)

	# Do not despawn NPCs that are still sim-near the local player — port queries
	# are per-context and can flicker when freecam or streaming changes.
	var ref := _reference_position()
	var ref_xz := Vector2(ref.x, ref.z)
	for uid in _controllers.keys():
		if keep.has(uid):
			continue
		var rec: Dictionary = _record_for_uid(str(uid))
		if rec.is_empty():
			_despawn_uid(str(uid))
			continue
		var av := AutonomousVesselRecord.from_owned_vessel(rec)
		av.hydrate_ports(get_node_or_null("/root/ContractRegistry"))
		if av.is_relevant_near(ref_xz, AutonomousVesselLoader.DEFAULT_PROXIMITY_M):
			keep[uid] = true
			continue
		_despawn_uid(str(uid))


func _sync_controller_records() -> void:
	_purge_stale_controllers()
	for uid in _controllers.keys():
		var ctrl = _controllers.get(uid)
		if ctrl == null or not is_instance_valid(ctrl):
			_controllers.erase(uid)
			continue
		var uid_str := str(uid)
		var record: Dictionary = _record_for_uid(uid_str)
		if record.is_empty():
			continue
		var live: Dictionary = (ctrl as AutonomousNpcShip).get_live_record()
		if not live.is_empty():
			var pending := maxi(
				int(live.get("pending_earnings", 0)),
				int(record.get("pending_earnings", 0)),
			)
			if pending != int(record.get("pending_earnings", 0)):
				record = record.duplicate(true)
				record["pending_earnings"] = pending
				if _server_records.has(uid_str):
					_server_records[uid_str] = record.duplicate(true)
		(ctrl as AutonomousNpcShip).sync_record(record)


func _record_for_uid(uid: String) -> Dictionary:
	if _is_mp_session():
		return _server_records.get(uid, {})
	var data := _player_data()
	if data == null:
		return {}
	return data.find_owned_vessel(uid)


func _purge_stale_controllers() -> void:
	for uid in _controllers.keys():
		var ctrl = _controllers.get(uid)
		if ctrl == null or not is_instance_valid(ctrl):
			_controllers.erase(uid)


func _ensure_spawn(record: Dictionary) -> void:
	var uid := str(record.get("uid", ""))
	if uid.is_empty():
		return
	var existing = _controllers.get(uid)
	if existing != null:
		if not is_instance_valid(existing):
			_controllers.erase(uid)
		else:
			(existing as AutonomousNpcShip).sync_record(record)
			return

	var path := AutonomousVesselLoader.resolve_template_path(record)
	if path.is_empty():
		push_warning("AutonomousVesselManager: missing template for %s" % uid)
		return
	record["template_path"] = path

	var ship := ShipBuilder.build(path)
	if ship == null:
		return

	ship.name = "AutonomousNPC_%s" % uid
	ship.freeze = true
	_disable_player_control(ship)

	var world := _world_root()
	if world == null:
		ship.queue_free()
		return
	world.add_child(ship)

	var ctrl := AutonomousNpcShip.new()
	ctrl.name = "AutonomousNpcShip"
	ship.add_child(ctrl)
	ctrl.setup(ship, record)
	ctrl.call_deferred("snap_to_sample")

	_controllers[uid] = ctrl


func _despawn_uid(uid: String) -> void:
	_server_records.erase(uid)
	var ctrl = _controllers.get(uid)
	_controllers.erase(uid)
	if ctrl == null or not is_instance_valid(ctrl):
		return
	(ctrl as AutonomousNpcShip).release_berth()
	var body := (ctrl as AutonomousNpcShip).get_body()
	if body != null and is_instance_valid(body):
		PlayerVessel.unregister_ship_from_docks(body)
		body.queue_free()


func _should_skip_record(record: Dictionary) -> bool:
	var data := _player_data()
	if data == null:
		return false
	var active := data.active_vessel
	var active_uid := str(active.get("uid", ""))
	var active_server_id := str(active.get("server_vessel_id", ""))
	var record_uid := str(record.get("uid", ""))
	var record_server_id := str(record.get("server_vessel_id", ""))

	var is_player_hull := false
	if not active_server_id.is_empty() and active_server_id == record_server_id:
		is_player_hull = true
	elif not active_uid.is_empty() and active_uid == record_uid:
		is_player_hull = true
	elif not active_server_id.is_empty() and record_uid == "mp_%s" % active_server_id:
		is_player_hull = true

	if not is_player_hull:
		return false
	var tree := get_tree()
	if tree == null:
		return false
	return PlayerVessel.find_active_ship(tree) != null


func _disable_player_control(ship: BoatBody) -> void:
	var controller := ship.find_child("BoatController", true, false) as BoatController
	if controller != null:
		controller.set_process(false)
		controller.set_physics_process(false)
	var chair := ship.find_child("CaptainsChair", true, false)
	if chair != null:
		chair.set_process(false)
		chair.set_physics_process(false)


func _world_root() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	for node in tree.get_nodes_in_group("world"):
		if node is Node3D:
			return node as Node3D
	if tree.current_scene != null:
		return tree.current_scene
	return tree.root


func _ensure_transit_debug_draw() -> void:
	var world := _world_root()
	if world == null:
		return
	if _transit_debug_draw != null and is_instance_valid(_transit_debug_draw):
		if _transit_debug_draw.get_parent() != world:
			_transit_debug_draw.reparent(world)
		return
	_transit_debug_draw = AutonomousTransitDebugDraw.new()
	_transit_debug_draw.name = "AutonomousTransitDebugDraw"
	world.add_child(_transit_debug_draw)


func _ensure_lane_debug_draw() -> void:
	var world := _world_root()
	if world == null:
		return
	if _lane_debug_draw != null and is_instance_valid(_lane_debug_draw):
		if _lane_debug_draw.get_parent() != world:
			_lane_debug_draw.reparent(world)
		return
	_lane_debug_draw = BerthApproachLanesDebugDraw.new()
	_lane_debug_draw.name = "BerthApproachLanesDebugDraw"
	_lane_debug_draw.top_level = true
	world.add_child(_lane_debug_draw)


func refresh_lane_debug() -> void:
	_ensure_lane_debug_draw()
	var hud := get_node_or_null("/root/DebugHud")
	var open := bool(hud.call("is_open")) if hud != null else false
	if _lane_debug_draw != null and is_instance_valid(_lane_debug_draw):
		_lane_debug_draw.sync_visibility(open)
		_lane_debug_draw.refresh_now()


func _player_data() -> PlayerData:
	var session := get_node_or_null("/root/PlayerSession")
	if session == null or session.get("data") == null:
		return null
	return session.data as PlayerData


func _is_mp_session() -> bool:
	var config := get_node_or_null("/root/ServerConfig")
	return config != null and bool(config.get("is_multiplayer_mode"))


func _nearest_port_id() -> String:
	var gs := get_node_or_null("/root/GameState")
	if gs != null and gs.get("world") != null:
		return str((gs.world as WorldState).nearest_port_id)
	return ""


func _reference_position() -> Vector3:
	var tree := get_tree()
	if tree == null:
		return Vector3.ZERO
	return WorldReference.gameplay_position(tree)
