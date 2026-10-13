class_name FishingCatchReplication
extends Node

## Catch commands outlive the held rod. Only server projections fill MP crates.
signal catch_finished(lot_id: String, ok: bool, message: String)
signal landing_finished(operation_id: String, result: Dictionary)
var _landings: Dictionary = {}
var gateway: Node
var _queue: Array[Dictionary] = []
var _interests: Dictionary = {}
var _applied: Dictionary = {}
var _elapsed := 0.0
var _retry_at := 0

static func owns_ship(boat: BoatBody) -> bool:
	if not is_instance_valid(boat) or PlayerSession.data == null or bool(boat.get_meta("remote_replica", false)): return false
	var record := PlayerSession.data.find_owned_vessel(str(boat.get_meta("vessel_uid", "")))
	return not record.is_empty() and not str(record.get("server_vessel_id", "")).is_empty() and str(record.server_vessel_id) == str(boat.get_meta("server_vessel_id", ""))

func setup(world_gateway: Node) -> void:
	gateway = world_gateway
	gateway.command_completed.connect(_on_result)
	gateway.session_closed.connect(_clear)

func submit(vessel_id: String, hold_id: String, lot: Dictionary, fish: Dictionary) -> void:
	_queue.append({"body":{"vessel_id":vessel_id,"hold_id":hold_id,"lot":lot.duplicate(true)},
		"request":gateway.next_request_id("fishing-catch"),"fish":fish.duplicate(true)})
	if _queue.size() == 1: _retry_at = 0

func pending_mass(vessel_id: String, hold_id: String) -> float:
	var mass := 0.0
	for entry in _queue:
		if entry.body.vessel_id == vessel_id and entry.body.hold_id == hold_id:
			mass += float(entry.body.lot.mass_kg)
	return mass

func land(vessel_id:String,operation_id:String,lot_ids:Array[String])->void:
	if _landings.has(operation_id):return
	_landings[operation_id]={"body":{"vessel_id":vessel_id,"operation_id":operation_id,"lot_ids":lot_ids.duplicate()},"request":gateway.next_request_id("fish-landing"),"retry_at":Time.get_ticks_msec()+500}

func _process(delta: float) -> void:
	if gateway == null or not gateway.is_remote() or not gateway.is_ready(): return
	for entry:Dictionary in _landings.values():
		if Time.get_ticks_msec()>=int(entry.retry_at):
			entry.retry_at=Time.get_ticks_msec()+10000
			gateway.send_command("fishing.catch.land",entry.body,entry.request)
	if not _queue.is_empty() and Time.get_ticks_msec() >= _retry_at:
		_retry_at = Time.get_ticks_msec() + 10000
		# Same receipt on timeout: the response may have been lost after commit.
		gateway.send_command("fishing.catch.store", _queue[0].body, _queue[0].request)
	_elapsed += delta
	if _elapsed < .2: return
	_elapsed = 0
	var wanted := {}
	for node in get_tree().get_nodes_in_group("network_catch_hold"):
		var hold := node as CatchHoldComponent
		var boat := hold._boat
		if not is_instance_valid(boat): continue
		var vessel_id := str(boat.get_meta("server_vessel_id", ""))
		if vessel_id.is_empty(): continue
		var scope := "vessel:" + vessel_id
		wanted[scope] = true
		var id := vessel_id + "/" + hold.hold_id
		if not _interests.has(scope):
			_interests[scope] = true
			gateway.retain_interest(scope, self)
			gateway.query_projections("fishing_hold")
		var projection: Dictionary = gateway.projection("fishing_hold", id)
		var revision := int(projection.get("revision", 0))
		var key := str(hold.get_instance_id())
		if _applied.get(key, -1) == revision: continue
		_applied[key] = revision
		var state: Dictionary = projection.get("state", {"hold_id":hold.hold_id,"capacity_kg":hold.capacity_kg,"lots":[],"owner_actor_id":""})
		hold.apply_state(state)
	for scope in _interests.keys():
		if not wanted.has(scope):
			gateway.release_interest(scope, self)
			_interests.erase(scope)

func _on_result(request: String, result: Dictionary) -> void:
	for id in _landings.keys():
		if _landings[id].request!=request:continue
		if str(result.get("error_code",result.get("code","")))=="transport_failed":return
		_landings.erase(id)
		if bool(result.get("ok",false)):
			gateway.query_projections("fishing_hold")
			gateway.refresh_captain_balance()
		landing_finished.emit(id,result)
		return
	if _queue.is_empty() or request != _queue[0].request: return
	if str(result.get("error_code", result.get("code", ""))) == "transport_failed": return
	var entry: Dictionary = _queue.pop_front()
	_retry_at = 0
	var ok := bool(result.get("ok", false))
	if ok:
		var accepted: Dictionary = result.get("data", {}).get("hold", {})
		# The event usually arrives first. Query also covers a missed subscription.
		gateway.query_projections("fishing_hold", str(entry.body.vessel_id) + "/" + str(entry.body.hold_id))
		if not accepted.is_empty():
			for node in get_tree().get_nodes_in_group("network_catch_hold"):
				var hold := node as CatchHoldComponent
				if is_instance_valid(hold._boat) and str(hold._boat.get_meta("server_vessel_id", "")) == str(entry.body.vessel_id) and hold.hold_id == str(entry.body.hold_id):
					hold.apply_state(accepted)
		if FishingField.habitat != null:
			FishingField.habitat.take_one(entry.fish.school_id, str(entry.fish.get("fish_id", "")))
	catch_finished.emit(str(entry.body.lot.lot_id), ok, "Stored in the deck crate" if ok else str(result.get("message", "Server could not store catch")))

func _clear() -> void:
	_landings.clear()
	for entry in _queue:
		catch_finished.emit(str(entry.body.lot.lot_id), false, "Connection closed; check the crate after reconnecting")
	_queue.clear()
	for scope in _interests: gateway.release_interest(scope, self)
	_interests.clear()
	_applied.clear()
