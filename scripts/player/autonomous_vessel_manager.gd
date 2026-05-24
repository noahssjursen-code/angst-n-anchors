extends Node

## Spawns and drives autonomous NPC hulls from owned_vessel records (local only).

const REFRESH_INTERVAL_S := 2.0

var _controllers: Dictionary = {}  ## uid -> AutonomousNpcShip
var _refresh_clock: float = 0.0
var _transit_debug_draw: AutonomousTransitDebugDraw


func _ready() -> void:
	var session := get_node_or_null("/root/PlayerSession")
	if session != null:
		if session.has_signal("data_loaded") and not session.data_loaded.is_connected(_on_session_data):
			session.data_loaded.connect(_on_session_data)
		if session.has_signal("vessels_synced") and not session.vessels_synced.is_connected(_on_session_data):
			session.vessels_synced.connect(_on_session_data)
	call_deferred("refresh_all")
	call_deferred("_ensure_transit_debug_draw")


func _process(delta: float) -> void:
	_refresh_clock += delta
	if _refresh_clock < REFRESH_INTERVAL_S:
		return
	_refresh_clock = 0.0
	_sync_controller_records()
	if _world_root() != null:
		refresh_all()


func refresh_all() -> void:
	_ensure_transit_debug_draw()
	var data := _player_data()
	if data == null:
		return
	var keep: Dictionary = {}
	for entry_raw in data.owned_vessels:
		if typeof(entry_raw) != TYPE_DICTIONARY:
			continue
		var record: Dictionary = entry_raw as Dictionary
		var uid := str(record.get("uid", ""))
		if uid.is_empty():
			continue
		if not bool(record.get("autonomous_active", false)):
			continue
		if _should_skip_record(record):
			continue
		keep[uid] = true
		_ensure_spawn(record)

	for uid in _controllers.keys():
		if not keep.has(uid):
			_despawn_uid(str(uid))


func refresh_vessel(uid: String) -> void:
	var data := _player_data()
	if data == null or uid.is_empty():
		return
	var record: Dictionary = data.find_owned_vessel(uid)
	if record.is_empty() or not bool(record.get("autonomous_active", false)) or _should_skip_record(record):
		_despawn_uid(uid)
		return
	_ensure_spawn(record)


func _on_session_data(_data: Variant = null) -> void:
	call_deferred("refresh_all")


func _sync_controller_records() -> void:
	_purge_stale_controllers()
	var data := _player_data()
	if data == null:
		return
	for uid in _controllers.keys():
		var ctrl = _controllers.get(uid)
		if ctrl == null or not is_instance_valid(ctrl):
			_controllers.erase(uid)
			continue
		var record: Dictionary = data.find_owned_vessel(str(uid))
		if record.is_empty():
			continue
		(ctrl as AutonomousNpcShip).sync_record(record)


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

	var path := str(record.get("template_path", ""))
	if path.is_empty() or not FileAccess.file_exists(path):
		push_warning("AutonomousVesselManager: missing template for %s" % uid)
		return

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
	var uid := str(record.get("uid", ""))
	var active_uid := str(data.active_vessel.get("uid", ""))
	if uid.is_empty() or uid != active_uid:
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


func _player_data() -> PlayerData:
	var session := get_node_or_null("/root/PlayerSession")
	if session == null or session.get("data") == null:
		return null
	return session.data as PlayerData
