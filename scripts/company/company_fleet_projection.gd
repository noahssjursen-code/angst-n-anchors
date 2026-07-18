extends Node

## Reconstructs nearby vessels from fleet-authority timestamps. Player-owned,
## ambient, and eventually server-owned records all enter through the same
## projection, BoatBody, captain, autopilot, traffic, and port-operation path.

const INTEREST_RADIUS_M := 6500.0
const UPDATE_INTERVAL_S := 0.1
const MAX_PHYSICAL_NPC_VESSELS := 8
const ABSTRACT_TRAFFIC_INTERVAL_S := 0.5

var _ships: Dictionary = {} # vessel uid -> BoatBody
var _berths: Dictionary = {} # vessel uid -> { controller, berth_id }
var _physical_contracts: Dictionary = {} # vessel uid -> company freight id
var _last_status: Dictionary = {}
var _operation_interest: Dictionary = {}
var _restored_manifests: Dictionary = {}
var _authority_by_uid: Dictionary = {}
var _elapsed := 0.0
var _abstract_traffic_elapsed := 0.0
var _refreshing := false
var _published_authority_ids: Dictionary = {}
var _last_network_snapshot_bytes := 0
var _last_network_snapshot_ms := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_connect_authority_signals()
	call_deferred("_register_telemetry")


func _exit_tree() -> void:
	var telemetry := get_node_or_null("/root/Telemetry")
	if telemetry != null:
		telemetry.unregister_provider(&"fleet_projection", self)


func _register_telemetry() -> void:
	var telemetry := get_node_or_null("/root/Telemetry")
	if telemetry != null:
		telemetry.register_provider(
			&"fleet_projection", self, &"get_debug_stats", &"traffic")


func get_debug_stats() -> Dictionary:
	var quality_counts := {"full": 0, "medium": 0, "low": 0, "sleep": 0}
	var active_captains := 0
	for ship_raw in _ships.values():
		var ship := ship_raw as BoatBody
		if ship == null or not is_instance_valid(ship):
			continue
		var quality := ship.get_physics_quality_name().to_lower()
		quality_counts[quality] = int(quality_counts.get(quality, 0)) + 1
		if ship.get_node_or_null("AutonomousVesselCaptain") != null:
			active_captains += 1
	var authority_count := all_projection_records().size()
	return {
		"authority_vessels": authority_count,
		"physical_vessels": _ships.size(),
		"abstract_vessels": maxi(authority_count - _ships.size(), 0),
		"active_captains": active_captains,
		"physics_full": quality_counts.full,
		"physics_medium": quality_counts.medium,
		"physics_low": quality_counts.low,
		"physics_sleep": quality_counts.sleep,
		"physical_cap": MAX_PHYSICAL_NPC_VESSELS,
		"snapshot_bytes": _last_network_snapshot_bytes,
		"snapshot_build_ms": _last_network_snapshot_ms,
	}


func _process(delta: float) -> void:
	_elapsed += delta
	_abstract_traffic_elapsed += delta
	if _elapsed < UPDATE_INTERVAL_S:
		return
	_elapsed = 0.0
	_refresh()


func _on_company_changed(_snapshot: Dictionary) -> void:
	_refresh()


func authority_sources() -> Array[Node]:
	var out: Array[Node] = []
	for raw in get_tree().get_nodes_in_group("vessel_fleet_authority"):
		var authority := raw as Node
		if authority != null and authority.has_method("projection_records"):
			out.append(authority)
	return out


func all_projection_records() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for authority in authority_sources():
		for raw in authority.call("projection_records") as Array:
			var record := (raw as Dictionary).duplicate(true)
			record["_authority"] = authority
			out.append(record)
	return out


func leg_route_plan(vessel_uid: String) -> MarineRoutePlan:
	var authority := _authority_for(vessel_uid)
	if authority != null and authority.has_method("leg_route_plan"):
		return authority.call("leg_route_plan", vessel_uid) as MarineRoutePlan
	for source in authority_sources():
		for raw in source.call("projection_records") as Array:
			if str((raw as Dictionary).get("uid", "")) == vessel_uid:
				_authority_by_uid[vessel_uid] = source
				return source.call("leg_route_plan", vessel_uid) as MarineRoutePlan
	return MarineRoutePlan.new()


func network_fleet_snapshot() -> Dictionary:
	var started_usec := Time.get_ticks_usec()
	var vessels: Array[Dictionary] = []
	var server_time := int(Time.get_unix_time_from_system() * 1000.0)
	for record in all_projection_records():
		var uid := str(record.get("uid", ""))
		var wire := VesselAuthoritySnapshot.from_projection_record(
			record, leg_route_plan(uid), _ships.get(uid) as Node3D, server_time)
		if VesselAuthoritySnapshot.is_valid(wire):
			vessels.append(wire)
	var result := {
		"schema_version": 1,
		"server_unix_msec": server_time,
		"vessels": vessels,
	}
	_last_network_snapshot_bytes = JSON.stringify(result).to_utf8_buffer().size()
	_last_network_snapshot_ms = float(Time.get_ticks_usec() - started_usec) / 1000.0
	return result


func _connect_authority_signals() -> void:
	for authority in authority_sources():
		if authority.has_signal("company_changed"):
			var callback := Callable(self, "_on_company_changed")
			if not authority.is_connected("company_changed", callback):
				authority.connect("company_changed", callback)


func _authority_for(uid: String) -> Node:
	var authority := _authority_by_uid.get(uid) as Node
	return authority if authority != null and is_instance_valid(authority) else null


func _call_authority(uid: String, method: String, args: Array = []) -> Variant:
	var authority := _authority_for(uid)
	if authority == null or not authority.has_method(method):
		return null
	return authority.callv(method, args)


func _refresh() -> void:
	if _refreshing:
		return
	_refreshing = true
	var view := get_node_or_null("/root/LocalPlayerView")
	if view == null or _is_main_menu():
		_clear_all()
		_refreshing = false
		return
	var observer := _observer_position()
	if not observer.is_finite():
		_clear_all()
		_refreshing = false
		return
	var wanted: Dictionary = {}
	var operation_interest: Dictionary = {}
	_connect_authority_signals()
	var records := all_projection_records()
	records.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _physical_priority(a, observer) < _physical_priority(b, observer))
	var physical_count := 0
	for raw in records:
		var record := raw as Dictionary
		var authority := record.get("_authority") as Node
		var vessel := record.get("vessel", {}) as Dictionary
		var uid := str(record.get("uid", ""))
		var assignment := record.get("assignment", {}) as Dictionary
		var status := str(assignment.get("status", ""))
		if uid.is_empty() or assignment.is_empty() or status not in ["underway", "preparing", "turnaround", "unpaid", "inactive", "berthed"]:
			continue
		_authority_by_uid[uid] = authority
		_last_status[uid] = status
		var projection := record.get("projection", {}) as Dictionary
		var existing_ship := _ships.get(uid) as BoatBody
		var position := existing_ship.global_position if existing_ship != null \
				and is_instance_valid(existing_ship) \
			else projection.get("position", Vector3(INF, INF, INF)) as Vector3
		if not position.is_finite() or position.distance_to(observer) > INTEREST_RADIUS_M:
			continue
		if physical_count >= MAX_PHYSICAL_NPC_VESSELS:
			continue
		physical_count += 1
		var waiting_at_berth := status != "underway"
		if status in ["preparing", "turnaround"]:
			operation_interest[uid] = true
			_call_authority(uid, "set_local_operations_active", [uid, true])
		if waiting_at_berth and not _berths.has(uid):
			var harbour := HarbourRegistry.controller(str(projection.get("origin_port_id", "")))
			if harbour == null or _pick_cargo_berth(harbour, vessel, assignment) == null:
				# A vessel already visible on its arrival lane waits where it is
				# instead of blinking out while every compatible quay is occupied.
				var waiting_ship := _ships.get(uid) as BoatBody
				if waiting_ship != null and is_instance_valid(waiting_ship):
					wanted[uid] = true
				continue
		wanted[uid] = true
		var ship := _ships.get(uid) as BoatBody
		if ship == null or not is_instance_valid(ship):
			ship = _spawn(vessel, uid)
		if ship == null:
			continue
		_project(ship, uid, vessel, assignment, projection, authority)
	for uid_raw in _ships.keys():
		var uid := str(uid_raw)
		if not wanted.has(uid):
			_despawn(uid)
	for uid_raw in _operation_interest.keys():
		var uid := str(uid_raw)
		if not operation_interest.has(uid):
			_call_authority(uid, "set_local_operations_active", [uid, false])
	_operation_interest = operation_interest
	_apply_shared_npc_physics_budget()
	if _abstract_traffic_elapsed >= ABSTRACT_TRAFFIC_INTERVAL_S:
		_abstract_traffic_elapsed = 0.0
		_publish_authority_traffic(records)
	_refreshing = false


func _physical_priority(record: Dictionary, observer: Vector3) -> float:
	var uid := str(record.get("uid", ""))
	var assignment := record.get("assignment", {}) as Dictionary
	var projection := record.get("projection", {}) as Dictionary
	var position := projection.get("position", Vector3(INF, INF, INF)) as Vector3
	var score := position.distance_to(observer) if position.is_finite() else INF
	if _ships.has(uid):
		score -= 250.0
	if str(assignment.get("status", "")) != "underway":
		score -= 5000.0
	else:
		var plan := leg_route_plan(uid)
		if plan != null and plan.is_valid():
			var remaining := plan.total_distance_m() - float(
				projection.get("route_progress_m", assignment.get("route_progress_m", 0.0)))
			if remaining < 1200.0:
				score -= 3500.0
	return score


func _publish_authority_traffic(records: Array[Dictionary]) -> void:
	var traffic := get_node_or_null("/root/MaritimeTraffic")
	if traffic == null or not traffic.is_world_authority():
		return
	var current: Dictionary = {}
	for record in records:
		var uid := str(record.get("uid", ""))
		var assignment := record.get("assignment", {}) as Dictionary
		var projection := record.get("projection", {}) as Dictionary
		if uid.is_empty() or str(assignment.get("status", "")) != "underway":
			continue
		var position := projection.get("position", Vector3(INF, INF, INF)) as Vector3
		var heading := projection.get("heading_xz", Vector2.ZERO) as Vector2
		if not position.is_finite() or heading.length_squared() < 0.1:
			continue
		current[uid] = true
		var vessel := record.get("vessel", {}) as Dictionary
		var speed_ms := float(assignment.get("cruise_speed_ms", 7.2))
		var plan := leg_route_plan(uid)
		var progress_m := float(projection.get("route_progress_m", 0.0))
		var remaining_m := plan.total_distance_m() - progress_m if plan != null \
				and plan.is_valid() else INF
		var phase := "passage"
		var velocity := heading * speed_ms
		if not _ships.has(uid) and remaining_m < 1500.0:
			var family := CommodityCatalog.commodity_terminal_family(
				str(assignment.get("commodity_id", "")))
			var ticket: Dictionary = traffic.request_port_arrival(
				str(assignment.get("leg_destination_port_id", "")),
				uid,
				family,
				str(assignment.get("leg_destination_berth_id", "")),
				int(Time.get_unix_time_from_system() + remaining_m / maxf(speed_ms, 0.1)),
			)
			if not bool(ticket.get("cleared_for_approach", false)):
				phase = "holding"
				velocity = Vector2.ZERO
			else:
				phase = "waiting_approach"
			traffic.release_lane_window(uid)
		traffic.publish_intent({
			"vessel_id": uid,
			"owner_id": str(vessel.get("owner_id", "")),
			"kind": "npc",
			"position_xz": [position.x, position.z],
			"velocity_xz": [velocity.x, velocity.y],
			"heading_deg": NavigationAxes.heading_deg_horizontal(heading),
			"length_m": float(vessel.get("display_length_m", 28.0)),
			"beam_m": float(vessel.get("display_beam_m", 10.0)),
			"route_id": plan.route_id if plan != null else "",
			"route_progress_m": progress_m,
			"phase": phase,
		})
		if not _ships.has(uid) and phase == "passage":
			traffic.request_lane_window(uid, traffic.lane_window_for_route(
				plan, progress_m))
	for uid_raw in _published_authority_ids.keys():
		var uid := str(uid_raw)
		if not current.has(uid):
			traffic.withdraw_vessel(uid)
	_published_authority_ids = current


func _spawn(record: Dictionary, uid: String) -> BoatBody:
	var ship := VesselSpawn.instantiate_from_record(record)
	if ship == null:
		return null
	ship.name = "CompanyVessel_%s" % uid.validate_node_name()
	ship.set_meta("company_vessel_uid", uid)
	ship.set_meta("network_ship_id", "company:%s" % uid)
	ship.set_meta("authority_projection", true)
	ship.visible = false
	ship.freeze = true
	# These hulls move every authority tick. Kinematic freeze keeps Jolt from
	# repeatedly removing/re-adding a moving "static" body to its broadphase.
	ship.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	var scene := get_tree().current_scene
	if scene == null:
		ship.queue_free()
		return null
	scene.add_child(ship)
	# BoatBody._ready() applies its default FULL quality and unfreezes the body.
	# Reassert projection authority after _ready so gravity/Jolt cannot fight the
	# deterministic pose while all force-producing components are disabled.
	ship.freeze = true
	ship.sleeping = true
	# The projection is moved from authority timestamps. Disable buoyancy,
	# controllers, audio, and gameplay polling while keeping its visuals alive.
	ship.process_mode = Node.PROCESS_MODE_DISABLED
	_ships[uid] = ship
	return ship


func _project(
		ship: BoatBody,
		uid: String,
		record: Dictionary,
		assignment: Dictionary,
		projection: Dictionary,
		authority: Node,
) -> void:
	_restore_cargo_manifest(ship, uid, assignment)
	var at_berth := str(assignment.get("status", "")) != "underway"
	if at_berth:
		if _ensure_berthed(ship, uid, record, assignment, str(projection.get("origin_port_id", ""))):
			ship.visible = true
			_drive_port_operations(ship, uid, assignment)
			return
		# Do not put an awaiting vessel on top of the harbour anchor if every
		# compatible quay is occupied. It appears when a berth becomes free.
		_despawn(uid)
		return
	if ship.has_meta("company_physics_started"):
		return
	var departed_from_visible_berth := _berths.has(uid)
	if departed_from_visible_berth:
		_berths.erase(uid)
	_sync_exact_leg_endpoints(uid, ship, assignment)
	if _begin_physical_voyage(ship, uid, assignment, projection, departed_from_visible_berth, authority):
		ship.visible = true


func _begin_physical_voyage(
		ship: BoatBody,
		uid: String,
		assignment: Dictionary,
		projection: Dictionary,
		depart_from_berth: bool,
		authority: Node,
) -> bool:
	if authority == null:
		return false
	var autopilot := ship.get_node_or_null("VesselAutopilot") as VesselAutopilot
	if autopilot == null:
		autopilot = VesselAutopilot.new()
		autopilot.name = "VesselAutopilot"
		ship.add_child(autopilot)
	var captain := ship.get_node_or_null("AutonomousVesselCaptain") as AutonomousVesselCaptain
	if captain == null:
		captain = AutonomousVesselCaptain.new()
		captain.name = "AutonomousVesselCaptain"
		ship.add_child(captain)
	if not captain.voyage_completed.is_connected(_on_voyage_completed):
		captain.voyage_completed.connect(_on_voyage_completed.bind(uid, captain))
	if not captain.voyage_failed.is_connected(_on_voyage_failed):
		captain.voyage_failed.connect(_on_voyage_failed.bind(uid))
	_enable_boat_physics(ship)
	var family := CommodityCatalog.commodity_terminal_family(
		str(assignment.get("commodity_id", "")))
	var started := false
	if depart_from_berth:
		started = captain.assign_voyage(
			str(assignment.get("physical_contract_id", "")),
			str(assignment.get("leg_origin_port_id", "")),
			str(assignment.get("leg_origin_berth_id", "")),
			str(assignment.get("leg_destination_port_id", "")),
			family,
			str(assignment.get("leg_destination_berth_id", "")),
		)
	else:
		var plan := authority.call("leg_route_plan", uid) as MarineRoutePlan
		if plan == null or not plan.is_valid():
			return false
		var position := projection.get("position", Vector3.ZERO) as Vector3
		var heading := projection.get("heading_xz", Vector2(0.0, -1.0)) as Vector2
		ship.global_position = position
		if heading.length_squared() > 0.1:
			ship.rotation.y = atan2(-heading.x, -heading.y)
		ship.place_at_waterline(WaveSurface.get_height_at(position.x, position.z))
		started = captain.resume_voyage(
			str(assignment.get("physical_contract_id", "")),
			str(assignment.get("leg_origin_port_id", "")),
			str(assignment.get("leg_origin_berth_id", "")),
			str(assignment.get("leg_destination_port_id", "")),
			str(assignment.get("leg_destination_berth_id", "")),
			plan,
			float(projection.get("route_progress_m", 0.0)),
			family,
		)
	if not started:
		ship.freeze = true
		ship.process_mode = Node.PROCESS_MODE_DISABLED
		return false
	ship.set_meta("company_physics_started", true)
	if authority.has_method("set_local_voyage_simulation"):
		authority.call("set_local_voyage_simulation", uid, true)
	return true


func _enable_boat_physics(ship: BoatBody) -> void:
	var player_controller := ship.get_node_or_null("BoatController")
	if player_controller != null:
		player_controller.process_mode = Node.PROCESS_MODE_DISABLED
	ship.process_mode = Node.PROCESS_MODE_INHERIT
	# NPC precision follows manoeuvre state, not how many ships happen to be near
	# the local player. This is deterministic and applies equally to every fleet
	# authority while avoiding full strip-buoyancy work for open-water passage.
	ship.automatic_physics_lod = false
	ship.set_physics_quality(BoatBody.PhysicsQuality.MEDIUM)
	ship.freeze = false
	ship.sleeping = false


func _apply_shared_npc_physics_budget() -> void:
	for raw in _ships.values():
		var ship := raw as BoatBody
		if ship == null or not is_instance_valid(ship):
			continue
		var captain := ship.get_node_or_null("AutonomousVesselCaptain") as AutonomousVesselCaptain
		if captain == null:
			ship.set_physics_quality(BoatBody.PhysicsQuality.MEDIUM)
			continue
		match captain.phase:
			AutonomousVesselCaptain.Phase.IDLE, AutonomousVesselCaptain.Phase.MOORED:
				ship.set_physics_quality(BoatBody.PhysicsQuality.SLEEP)
			AutonomousVesselCaptain.Phase.PASSAGE, \
			AutonomousVesselCaptain.Phase.WAITING_APPROACH, \
			AutonomousVesselCaptain.Phase.HOLDING:
				ship.set_physics_quality(BoatBody.PhysicsQuality.LOW)
			AutonomousVesselCaptain.Phase.DEPARTURE, \
			AutonomousVesselCaptain.Phase.APPROACH:
				ship.set_physics_quality(BoatBody.PhysicsQuality.MEDIUM)
			_:
				# Casting off, crabbing, alignment and securing need the exact
				# hull/water response used by the player vessel.
				ship.set_physics_quality(BoatBody.PhysicsQuality.FULL)


func _on_voyage_completed(
		_contract_id: String,
		uid: String,
		captain: AutonomousVesselCaptain,
) -> void:
	var ship := _ships.get(uid) as BoatBody
	var authority := _authority_for(uid)
	if ship == null or authority == null or captain == null:
		return
	var controller := HarbourRegistry.controller(captain.destination_port_id)
	if controller != null:
		_berths[uid] = {
			"controller": controller,
			"berth_id": captain.destination_berth_id,
		}
	ship.remove_meta("company_physics_started")
	authority.call("complete_local_voyage",
		uid, captain.destination_berth_id, ship.rotation.y, ship.global_position)


func _on_voyage_failed(reason: String, uid: String) -> void:
	push_warning("Company vessel %s autonomous voyage failed: %s" % [uid, reason])
	call_deferred("_despawn", uid)


func _ensure_berthed(
		ship: BoatBody,
		uid: String,
		record: Dictionary,
		assignment: Dictionary,
	port_id: String,
) -> bool:
	if _berths.has(uid):
		var existing_mooring := ship.find_child("MooringComponent", true, false) as MooringComponent
		if existing_mooring != null and existing_mooring.is_moored:
			return true
		_release_berth(uid, ship)
	var harbour := HarbourRegistry.controller(port_id)
	if harbour == null:
		return false
	var slot := _pick_cargo_berth(harbour, record, assignment)
	if slot == null:
		return false
	ship.dock_at_berth(slot)
	if not harbour.plug_ship(slot.berth_id, ship):
		return false
	_berths[uid] = {"controller": harbour, "berth_id": slot.berth_id}
	var mooring := ship.find_child("MooringComponent", true, false) as MooringComponent
	if mooring != null:
		mooring.moor_to_nearest_of(slot.bollards())
	if mooring == null or not mooring.is_moored:
		harbour.unplug_ship(ship)
		_berths.erase(uid)
		return false
	_enable_boat_physics(ship)
	_call_authority(uid, "set_current_berth",
		[uid, slot.berth_id, ship.rotation.y, ship.global_position])
	return true


func _drive_port_operations(ship: BoatBody, uid: String, assignment: Dictionary) -> void:
	var service := _authority_for(uid)
	var berth_row := _berths.get(uid, {}) as Dictionary
	var harbour := berth_row.get("controller") as HarbourController
	var berth_id := str(berth_row.get("berth_id", ""))
	if service == null or harbour == null or berth_id.is_empty():
		return
	service.set_local_operations_active(uid, true)
	var arriving_contract_id := str(assignment.get("arriving_contract_id", ""))
	var departing_contract_id := str(assignment.get("physical_contract_id", ""))
	var operation_commodity := str(assignment.get(
		"arriving_commodity_id" if not arriving_contract_id.is_empty() else "commodity_id", ""))
	var handling := CommodityCatalog.commodity_handling_mode(operation_commodity)
	if not arriving_contract_id.is_empty():
		_physical_contracts[uid] = arriving_contract_id
	elif not departing_contract_id.is_empty():
		_physical_contracts[uid] = departing_contract_id
	if arriving_contract_id.is_empty() and bool(assignment.get("arrival_pending_settlement", false)):
		service.confirm_arrival_unloaded(uid)
		return
	if handling == "bulk":
		if not _finish_bulk_arrival(ship, uid, harbour, berth_id, arriving_contract_id):
			return
		if str(assignment.get("status", "")) in ["inactive", "unpaid"]:
			service.set_local_operations_active(uid, false)
			return
		_prepare_bulk_departure(ship, uid, harbour, berth_id, assignment)
		return
	if not _finish_unit_arrival(ship, uid, harbour, berth_id, arriving_contract_id):
		return
	if str(assignment.get("status", "")) in ["inactive", "unpaid"]:
		service.set_local_operations_active(uid, false)
		return
	_prepare_unit_departure(ship, uid, harbour, berth_id, assignment)


func _finish_unit_arrival(
		ship: BoatBody,
		uid: String,
		harbour: HarbourController,
		berth_id: String,
		contract_id: String,
) -> bool:
	if contract_id.is_empty():
		return true
	var freight := get_node_or_null("/root/FreightService")
	if freight == null or freight.company_contract(contract_id).is_empty():
		_call_authority(uid, "confirm_arrival_unloaded", [uid])
		# The settlement can also transition a stop-after-leg vessel to inactive.
		# Re-read authority on the next projection tick before loading anything.
		return false
	if not _has_active_job(harbour, berth_id, ship):
		harbour.request_unload(berth_id)
	return false


func _prepare_unit_departure(
		ship: BoatBody,
		uid: String,
		harbour: HarbourController,
		berth_id: String,
		assignment: Dictionary,
) -> void:
	var freight := get_node_or_null("/root/FreightService")
	var service := _authority_for(uid)
	if freight == null or service == null:
		return
	var contract_id := str(assignment.get("physical_contract_id", ""))
	var contract: Dictionary = freight.company_contract(contract_id) if not contract_id.is_empty() else {}
	if not contract_id.is_empty():
		_physical_contracts[uid] = contract_id
	if contract.is_empty():
		var free_units := _free_unit_capacity(ship)
		if free_units <= 0:
			return
		contract_id = "company-freight:%s:%d" % [uid, int(assignment.get("completed_legs", 0))]
		var quantity := mini(free_units, 8 + posmod(contract_id.hash(), 5))
		contract = {
			"id": contract_id,
			"status": "accepted",
			"origin_port_id": str(assignment.get("leg_origin_port_id", "")),
			"destination_port_id": str(assignment.get("leg_destination_port_id", "")),
			"commodity_id": str(assignment.get("commodity_id", "provisions")),
			"handling_mode": CommodityCatalog.commodity_handling_mode(str(assignment.get("commodity_id", "provisions"))),
			"quantity": quantity,
			"quantity_unit": "units",
			"pay_marks": int((assignment.get("route", {}) as Dictionary).get("pay_marks", 0)),
			"vessel_uid": uid,
			"berth_id": berth_id,
		}
		if not freight.register_company_contract(contract):
			return
		service.set_physical_contract(uid, contract_id)
		_physical_contracts[uid] = contract_id
		freight.stage_berth(harbour.port_id(), berth_id)
		contract = freight.company_contract(contract_id)
	var required := float(contract.get("quantity", 0.0))
	if required > 0.0 and float(contract.get("loaded_quantity", 0.0)) >= required:
		var manifest := _capture_unit_manifest(ship, contract)
		var onboard := (manifest.get("units", []) as Array).size()
		if onboard < int(round(required)):
			freight.reconcile_company_loaded_units(contract_id, onboard)
			freight.stage_berth(harbour.port_id(), berth_id)
			if not _has_active_job(harbour, berth_id, ship):
				harbour.request_load(berth_id, str(contract.get("commodity_id", "")))
			return
		service.set_cargo_manifest(uid, manifest)
		service.mark_cargo_ready(uid, true)
		var result := service.depart_prepared_vessel(uid) as Dictionary
		if bool(result.get("ok", false)):
			service.set_local_operations_active(uid, false)
		return
	if not _has_active_job(harbour, berth_id, ship):
		# A yard can hold fewer boxes than the ship. Refill freed yard slots
		# between crane batches until the full consignment is aboard.
		freight.stage_berth(harbour.port_id(), berth_id)
		harbour.request_load(berth_id, str(contract.get("commodity_id", "")))


func _finish_bulk_arrival(
		ship: BoatBody,
		uid: String,
		harbour: HarbourController,
		berth_id: String,
		arriving_contract_id: String,
) -> bool:
	if arriving_contract_id.is_empty():
		return true
	if _bulk_is_empty(ship):
		_call_authority(uid, "confirm_arrival_unloaded", [uid])
		return false
	if not _has_active_job(harbour, berth_id, ship):
		harbour.request_unload(berth_id)
	return false


func _prepare_bulk_departure(
		ship: BoatBody,
		uid: String,
		harbour: HarbourController,
		berth_id: String,
		assignment: Dictionary,
) -> void:
	var service := _authority_for(uid)
	if service == null:
		return
	var cargo_token := str(assignment.get("physical_contract_id", ""))
	if cargo_token.is_empty():
		cargo_token = "company-bulk:%s:%d" % [uid, int(assignment.get("completed_legs", 0))]
		service.set_physical_contract(uid, cargo_token)
		_physical_contracts[uid] = cargo_token
	if not _bulk_is_empty(ship) and not _has_active_job(harbour, berth_id, ship):
		service.set_cargo_manifest(uid, _capture_bulk_manifest(ship, cargo_token, assignment))
		service.mark_cargo_ready(uid, true)
		var result := service.depart_prepared_vessel(uid) as Dictionary
		if bool(result.get("ok", false)):
			service.set_local_operations_active(uid, false)
		return
	if not _has_active_job(harbour, berth_id, ship):
		harbour.request_load(berth_id, str(assignment.get("commodity_id", "")))


func _has_active_job(harbour: HarbourController, berth_id: String, ship: BoatBody) -> bool:
	for equip_id in harbour.equipment_ids_on_berth(berth_id):
		var equipment := harbour.get_equipment(equip_id)
		if equipment != null and equipment.is_job_active() and equipment.served_ship() == ship:
			return true
	return false


func _free_unit_capacity(ship: BoatBody) -> int:
	var total := 0
	for pad in ship.get_cargo_pads():
		total += pad.get_free_slot_count()
	return total


func _bulk_is_empty(ship: BoatBody) -> bool:
	for hold in ship.get_bulk_holds():
		if not hold.get_state().is_empty():
			return false
	return true


func _pick_cargo_berth(
		harbour: HarbourController,
		record: Dictionary,
		assignment: Dictionary,
) -> QuayBerthSlot:
	var family := CommodityCatalog.commodity_terminal_family(
		str(assignment.get("commodity_id", "provisions")))
	var free_slots := HarbourDeploy.free_slots_for(harbour, record)
	var preferred_id := str(assignment.get("current_berth_id", ""))
	for raw in free_slots:
		var preferred := raw as QuayBerthSlot
		if preferred != null and preferred.berth_id == preferred_id and str(preferred.family) == family:
			return preferred
	for raw in free_slots:
		var slot := raw as QuayBerthSlot
		if slot != null and str(slot.family) == family:
			return slot
	return null


func _release_berth(uid: String, ship: BoatBody) -> void:
	if not _berths.has(uid):
		return
	var row := _berths[uid] as Dictionary
	var harbour := row.get("controller") as HarbourController
	if harbour != null and is_instance_valid(harbour):
		harbour.unplug_ship(ship)
	var mooring := ship.find_child("MooringComponent", true, false) as MooringComponent
	if mooring != null and mooring.is_moored:
		mooring.release_mooring()
	_berths.erase(uid)


func _despawn(uid: String) -> void:
	var ship := _ships.get(uid) as BoatBody
	if ship != null and is_instance_valid(ship):
		var status := str(_last_status.get(uid, ""))
		var contract_id := str(_physical_contracts.get(uid, ""))
		var authority := _authority_for(uid)
		if status == "underway" and authority != null:
			var autopilot := ship.get_node_or_null("VesselAutopilot") as VesselAutopilot
			if autopilot != null and autopilot.route != null:
				if authority.has_method("suspend_local_voyage"):
					authority.call("suspend_local_voyage",
						uid, autopilot.progress_m, autopilot.route.total_distance_m())
		# Unplugging stops the crane and returns staged yard cargo first. This
		# avoids deleting a box while an auto-operator still holds its node.
		_release_berth(uid, ship)
		if status in ["underway", "preparing", "turnaround"]:
			var freight := get_node_or_null("/root/FreightService")
			if freight != null and not contract_id.is_empty():
				freight.cancel_company_contract(contract_id)
			if status != "underway":
				_call_authority(uid, "set_physical_contract", [uid, ""])
		ship.queue_free()
	_call_authority(uid, "set_local_operations_active", [uid, false])
	_ships.erase(uid)
	_berths.erase(uid)
	_last_status.erase(uid)
	_physical_contracts.erase(uid)
	_restored_manifests.erase(uid)
	_operation_interest.erase(uid)
	_authority_by_uid.erase(uid)


func _clear_all() -> void:
	for uid in _ships.keys():
		_despawn(str(uid))
	for uid in _operation_interest.keys():
		_call_authority(str(uid), "set_local_operations_active", [str(uid), false])
	_operation_interest.clear()
	_authority_by_uid.clear()


func _observer_position() -> Vector3:
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		return camera.global_position
	var view := get_node_or_null("/root/LocalPlayerView")
	var ship: Node3D = view.get_active_ship() as Node3D if view != null else null
	return ship.global_position if ship is Node3D else Vector3(INF, INF, INF)


func _capture_unit_manifest(ship: BoatBody, contract: Dictionary) -> Dictionary:
	var units: Array[Dictionary] = []
	var contract_id := str(contract.get("id", ""))
	var consignment := contract.get("consignment", {}) as Dictionary
	for pad in ship.get_cargo_pads():
		for unit in pad.get_containers():
			var authority_match := (
				unit.origin_port_id == str(contract.get("origin_port_id", ""))
				and unit.destination_port_id == str(contract.get("destination_port_id", ""))
				and unit.commodity_id == str(contract.get("commodity_id", ""))
			)
			if unit.freight_contract_id != contract_id and not authority_match:
				continue
			unit.freight_contract_id = contract_id
			unit.consignment_id = str(consignment.get("consignment_id", ""))
			units.append(unit.to_dict())
	var persisted_contract := contract.duplicate(true)
	persisted_contract["issued_quantity"] = units.size()
	persisted_contract["loaded_quantity"] = units.size()
	return {"kind": "units", "contract": persisted_contract, "units": units}


func _capture_bulk_manifest(
		ship: BoatBody,
		contract_id: String,
		assignment: Dictionary,
) -> Dictionary:
	var holds: Array[Dictionary] = []
	for hold in ship.get_bulk_holds():
		holds.append(hold.get_state().to_dict())
	return {
		"kind": "bulk",
		"contract_id": contract_id,
		"commodity_id": str(assignment.get("commodity_id", "")),
		"holds": holds,
	}


func _restore_cargo_manifest(ship: BoatBody, uid: String, assignment: Dictionary) -> void:
	if _restored_manifests.has(uid):
		return
	_restored_manifests[uid] = true
	var manifest := assignment.get("cargo_manifest", {}) as Dictionary
	if manifest.is_empty():
		return
	if str(manifest.get("kind", "")) == "bulk":
		var states := manifest.get("holds", []) as Array
		var holds := ship.get_bulk_holds()
		for index in range(mini(states.size(), holds.size())):
			holds[index].apply_state(states[index] as Dictionary)
		return
	var contract := manifest.get("contract", {}) as Dictionary
	var contract_id := str(contract.get("id", ""))
	var freight := get_node_or_null("/root/FreightService")
	if freight != null and not contract_id.is_empty():
		freight.register_company_contract(contract)
		_physical_contracts[uid] = contract_id
	var pads := ship.get_cargo_pads()
	var pad_index := 0
	for raw in manifest.get("units", []) as Array:
		var unit := ContainerUnit.from_dict(raw as Dictionary)
		while pad_index < pads.size() and pads[pad_index].add_container(unit) < 0:
			pad_index += 1
		if pad_index >= pads.size():
			break


func _sync_exact_leg_endpoints(uid: String, ship: BoatBody, assignment: Dictionary) -> void:
	var authority := _authority_for(uid)
	if authority == null:
		return
	var origin := Vector2(INF, INF)
	var origin_raw := assignment.get("leg_origin_position_xz", []) as Array
	if origin_raw.size() >= 2:
		origin = Vector2(float(origin_raw[0]), float(origin_raw[1]))
	var destination := Vector2(INF, INF)
	var controller := HarbourRegistry.controller(str(assignment.get("leg_destination_port_id", "")))
	if controller != null:
		var slot := controller.berth(str(assignment.get("leg_destination_berth_id", "")))
		if slot != null:
			var dock := slot.global_transform * slot.ship_dock_local(ship.get_half_beam_m())
			destination = Vector2(dock.origin.x, dock.origin.z)
	if authority.has_method("set_leg_dock_endpoints"):
		authority.call("set_leg_dock_endpoints", uid, origin, destination)


func _is_main_menu() -> bool:
	var scene := get_tree().current_scene
	return scene == null or String(scene.scene_file_path).ends_with("main_menu.tscn")
