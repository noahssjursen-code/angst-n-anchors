extends Node

## Per-captain company authority. Physical workers and vessels are projections;
## this JSON-safe ledger is the durable simulation and future server seam.

signal company_changed(snapshot: Dictionary)
signal company_name_required
signal fleet_event(message: String)

const SCHEMA_VERSION := 1
const CRUISE_SPEED_MS := 7.2 # roughly 14 kn
const HARBOUR_SPEED_MS := 3.0
const CRAB_SPEED_MS := 1.4
const CRAB_ZONE_M := 24.0
const HARBOUR_ZONE_M := 300.0
const MIN_LEG_SECONDS := 120
const ABSTRACT_TURNAROUND_SECONDS := 120
const MAX_LEDGER_ROWS := 120

var _state: Dictionary = {}
var _session: Node
var _last_tick_unix := 0
var _projection_plan_cache: Dictionary = {}
var _route_templates_cache: Array[Dictionary] = []
var _route_templates_cache_key := ""
var _local_operations: Dictionary = {}
var _local_voyage_simulation: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("vessel_fleet_authority")
	_session = get_node_or_null("/root/PlayerSession")
	if _session != null:
		if not _session.data_loaded.is_connected(_on_data_loaded):
			_session.data_loaded.connect(_on_data_loaded)
		_on_data_loaded(_session.data)


func _process(_delta: float) -> void:
	if not is_company_authority():
		return
	if _state.is_empty() or str(_state.get("name", "")).is_empty():
		return
	var now := int(Time.get_unix_time_from_system())
	if now <= _last_tick_unix:
		return
	_last_tick_unix = now
	advance_to(now)


func snapshot() -> Dictionary:
	var out := _state.duplicate(true)
	var routes := _route_templates()
	out["marks"] = int(_session.get_marks()) if _session != null else 0
	out["owned_vessels"] = _owned_vessel_rows(routes)
	out["crew_candidates"] = _crew_candidates()
	out["route_templates"] = routes
	return out


func is_company_authority() -> bool:
	return multiplayer == null \
		or multiplayer.multiplayer_peer == null \
		or multiplayer.is_server()


## Durable company state replication seam. The server owns timestamps, payroll,
## cargo manifests, and assignments; clients derive presentation from this row.
func authority_snapshot() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"server_unix": int(Time.get_unix_time_from_system()),
		"company_state": _state.duplicate(true),
	}


func apply_authority_snapshot(payload: Dictionary) -> bool:
	if is_company_authority() and multiplayer != null and multiplayer.multiplayer_peer != null:
		return false
	var raw := payload.get("company_state", {}) as Dictionary
	if raw.is_empty():
		return false
	_state = _normalize(raw)
	_last_tick_unix = int(payload.get("server_unix", _state.get("last_simulated_unix", 0)))
	company_changed.emit(snapshot())
	return true


func projection_records() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for uid_raw in (_state.get("fleet", {}) as Dictionary).keys():
		var uid := str(uid_raw)
		var vessel := _owned_vessel(uid)
		var assignment := (_state["fleet"] as Dictionary).get(uid, {}) as Dictionary
		if vessel.is_empty() or assignment.is_empty():
			continue
		out.append({
			"uid": uid,
			"vessel": vessel,
			"assignment": assignment.duplicate(true),
			"projection": fleet_projection(uid),
		})
	return out


func set_company_name(value: String) -> bool:
	var clean := value.strip_edges()
	if clean.length() < 2:
		return false
	_state["name"] = clean.substr(0, 40)
	_publish(true)
	return true


func hire_employee(candidate_id: String) -> bool:
	var id := candidate_id.strip_edges()
	if id.is_empty() or employee(id) != {}:
		return false
	for candidate in _crew_candidates():
		if str(candidate.get("id", "")) != id:
			continue
		var employees := _state.get("employees", []) as Array
		var hired := (candidate as Dictionary).duplicate(true)
		hired["hired_at_unix"] = int(Time.get_unix_time_from_system())
		employees.append(hired)
		_state["employees"] = employees
		_add_ledger("hire", 0, "Hired %s" % str(candidate.get("name", "crew")))
		_publish(true)
		return true
	return false


func dismiss_employee(employee_id: String) -> bool:
	if _employee_assignment(employee_id) != "":
		return false
	var employees := _state.get("employees", []) as Array
	for index in range(employees.size()):
		if str((employees[index] as Dictionary).get("id", "")) == employee_id:
			var name := str((employees[index] as Dictionary).get("name", "crew"))
			employees.remove_at(index)
			_state["employees"] = employees
			_add_ledger("dismiss", 0, "Released %s" % name)
			_publish(true)
			return true
	return false


func employee(employee_id: String) -> Dictionary:
	for raw in _state.get("employees", []) as Array:
		var row := raw as Dictionary
		if str(row.get("id", "")) == employee_id:
			return row.duplicate(true)
	return {}


func vessel_assignment(vessel_uid: String) -> Dictionary:
	return ((_state.get("fleet", {}) as Dictionary).get(vessel_uid, {}) as Dictionary).duplicate(true)


func is_vessel_assigned(vessel_uid: String) -> bool:
	return not vessel_assignment(vessel_uid).is_empty()


func assign_and_start(vessel_uid: String, route_id: String) -> Dictionary:
	var vessel := _owned_vessel(vessel_uid)
	var route := _route_template(route_id)
	if vessel.is_empty() or route.is_empty():
		return {"ok": false, "reason": "Vessel or route unavailable"}
	if is_vessel_assigned(vessel_uid):
		return {"ok": false, "reason": "This vessel already has a company assignment"}
	var deployed_player_vessel := PlayerVessel.find_active_ship(get_tree())
	if (
		deployed_player_vessel != null
		and str(deployed_player_vessel.get_meta("vessel_uid", "")) == vessel_uid
	):
		return {"ok": false, "reason": "This vessel is currently deployed for you"}
	if not _vessel_can_run_route(vessel, route):
		return {"ok": false, "reason": "Vessel registration does not support this cargo route"}
	var required := _required_crew(vessel)
	var available: Array[String] = []
	for raw in _state.get("employees", []) as Array:
		var crew := raw as Dictionary
		var crew_id := str(crew.get("id", ""))
		if _employee_assignment(crew_id).is_empty():
			available.append(crew_id)
	if available.size() < required:
		return {"ok": false, "reason": "Requires %d available crew" % required}
	var crew_ids := PackedStringArray()
	for index in range(required):
		crew_ids.append(available[index])
	var fleet := _state.get("fleet", {}) as Dictionary
	var row := {
		"vessel_uid": vessel_uid,
		"route": route.duplicate(true),
		"crew_ids": crew_ids,
		"status": "preparing",
		"current_port_id": str(route.get("origin_port_id", "")),
		"leg_origin_port_id": "",
		"leg_destination_port_id": "",
		"leg_started_unix": 0,
		"leg_ends_unix": 0,
		"completed_legs": 0,
		"revenue_marks": 0,
		"wages_marks": 0,
		"first_departure_pending": true,
		"cargo_ready": false,
		"physical_contract_id": "",
		"arriving_contract_id": "",
		"cargo_manifest": {},
		"turnaround_ends_unix": int(Time.get_unix_time_from_system()) + ABSTRACT_TURNAROUND_SECONDS,
	}
	_prepare_next_leg(row)
	fleet[vessel_uid] = row
	_state["fleet"] = fleet
	_publish(true)
	return {"ok": true, "reason": "", "status": "preparing"}


func stop_after_current_leg(vessel_uid: String) -> bool:
	var fleet := _state.get("fleet", {}) as Dictionary
	if not fleet.has(vessel_uid):
		return false
	var row := fleet[vessel_uid] as Dictionary
	if str(row.get("status", "")) == "underway":
		row["stop_after_leg"] = true
	else:
		row["status"] = "inactive"
	fleet[vessel_uid] = row
	_state["fleet"] = fleet
	_publish(true)
	return true


func resume_vessel(vessel_uid: String) -> Dictionary:
	var fleet := _state.get("fleet", {}) as Dictionary
	var row := fleet.get(vessel_uid, {}) as Dictionary
	if row.is_empty():
		return {"ok": false, "reason": "Fleet assignment missing"}
	if str(row.get("status", "")) == "underway":
		return {"ok": true, "reason": ""}
	row["stop_after_leg"] = false
	if bool(row.get("cargo_ready", false)):
		fleet[vessel_uid] = row
		_state["fleet"] = fleet
		return _start_next_leg(vessel_uid, int(Time.get_unix_time_from_system()))
	row["status"] = "preparing"
	_prepare_next_leg(row)
	row["turnaround_ends_unix"] = int(Time.get_unix_time_from_system()) + ABSTRACT_TURNAROUND_SECONDS
	fleet[vessel_uid] = row
	_state["fleet"] = fleet
	_publish(true)
	return {"ok": true, "reason": "", "status": str(row.get("status", "preparing"))}


func set_local_operations_active(vessel_uid: String, active: bool) -> void:
	if active:
		_local_operations[vessel_uid] = true
	else:
		_local_operations.erase(vessel_uid)


func set_local_voyage_simulation(vessel_uid: String, active: bool) -> void:
	if active:
		_local_voyage_simulation[vessel_uid] = true
	else:
		_local_voyage_simulation.erase(vessel_uid)


func complete_local_voyage(
		vessel_uid: String,
		berth_id: String,
		berth_yaw: float,
		berth_position: Vector3,
) -> bool:
	var fleet := _state.get("fleet", {}) as Dictionary
	var row := fleet.get(vessel_uid, {}) as Dictionary
	if row.is_empty() or str(row.get("status", "")) != "underway":
		return false
	_local_voyage_simulation.erase(vessel_uid)
	row["leg_destination_berth_id"] = berth_id.strip_edges()
	fleet[vessel_uid] = row
	_state["fleet"] = fleet
	_complete_leg(vessel_uid, int(Time.get_unix_time_from_system()))
	var arrived := (_state.get("fleet", {}) as Dictionary).get(vessel_uid, {}) as Dictionary
	arrived["current_berth_yaw"] = berth_yaw
	arrived["current_berth_position_xz"] = [berth_position.x, berth_position.z]
	fleet = _state.get("fleet", {}) as Dictionary
	fleet[vessel_uid] = arrived
	_state["fleet"] = fleet
	_publish(true)
	return true


func suspend_local_voyage(
		vessel_uid: String,
		route_progress_m: float,
		route_distance_m: float,
) -> void:
	_local_voyage_simulation.erase(vessel_uid)
	var fleet := _state.get("fleet", {}) as Dictionary
	var row := fleet.get(vessel_uid, {}) as Dictionary
	if row.is_empty() or str(row.get("status", "")) != "underway":
		return
	var total := maxf(route_distance_m, 1.0)
	var progress := clampf(route_progress_m, 0.0, total)
	var now := int(Time.get_unix_time_from_system())
	var elapsed := _voyage_elapsed_at_distance(total, progress)
	var duration := _voyage_duration_s(total)
	row["leg_started_unix"] = now - int(round(elapsed))
	row["departure_ready_unix"] = row["leg_started_unix"]
	row["leg_ends_unix"] = now + maxi(int(ceil(duration - elapsed)), 1)
	row["leg_distance_m"] = total
	fleet[vessel_uid] = row
	_state["fleet"] = fleet
	_publish(true)


func set_physical_contract(vessel_uid: String, contract_id: String) -> bool:
	var fleet := _state.get("fleet", {}) as Dictionary
	var row := fleet.get(vessel_uid, {}) as Dictionary
	if row.is_empty():
		return false
	row["physical_contract_id"] = contract_id.strip_edges()
	fleet[vessel_uid] = row
	_state["fleet"] = fleet
	_publish(true)
	return true


func set_current_berth(
		vessel_uid: String,
		berth_id: String,
		berth_yaw: float = INF,
		berth_position: Vector3 = Vector3(INF, INF, INF),
) -> bool:
	var fleet := _state.get("fleet", {}) as Dictionary
	var row := fleet.get(vessel_uid, {}) as Dictionary
	var clean := berth_id.strip_edges()
	if row.is_empty() or clean.is_empty() or str(row.get("status", "")) == "underway":
		return false
	var yaw_known := is_finite(berth_yaw)
	var position_known := berth_position.is_finite()
	if str(row.get("current_berth_id", "")) == clean \
			and str(row.get("leg_origin_berth_id", "")) == clean \
			and (not yaw_known or is_equal_approx(float(row.get("current_berth_yaw", INF)), berth_yaw)) \
			and (not position_known or (row.get("current_berth_position_xz", []) as Array).size() >= 2):
		return true
	row["current_berth_id"] = clean
	if yaw_known:
		row["current_berth_yaw"] = berth_yaw
	if position_known:
		row["current_berth_position_xz"] = [berth_position.x, berth_position.z]
	_prepare_next_leg(row)
	fleet[vessel_uid] = row
	_state["fleet"] = fleet
	_publish(true)
	return true


func set_cargo_manifest(vessel_uid: String, manifest: Dictionary) -> bool:
	var fleet := _state.get("fleet", {}) as Dictionary
	var row := fleet.get(vessel_uid, {}) as Dictionary
	if row.is_empty():
		return false
	row["cargo_manifest"] = manifest.duplicate(true)
	fleet[vessel_uid] = row
	_state["fleet"] = fleet
	_publish(true)
	return true


func set_leg_dock_endpoints(
		vessel_uid: String,
		origin_xz: Vector2,
		destination_xz: Vector2,
) -> bool:
	var fleet := _state.get("fleet", {}) as Dictionary
	var row := fleet.get(vessel_uid, {}) as Dictionary
	if row.is_empty() or str(row.get("status", "")) != "underway":
		return false
	var changed := false
	if origin_xz.is_finite():
		var origin_value := [origin_xz.x, origin_xz.y]
		if row.get("leg_origin_position_xz", []) != origin_value:
			row["leg_origin_position_xz"] = origin_value
			changed = true
	if destination_xz.is_finite():
		var destination_value := [destination_xz.x, destination_xz.y]
		if row.get("leg_destination_position_xz", []) != destination_value:
			row["leg_destination_position_xz"] = destination_value
			changed = true
	if not changed:
		return true
	_projection_plan_cache.clear()
	fleet[vessel_uid] = row
	_state["fleet"] = fleet
	_publish(true)
	return true


func confirm_arrival_unloaded(vessel_uid: String) -> bool:
	var fleet := _state.get("fleet", {}) as Dictionary
	var row := fleet.get(vessel_uid, {}) as Dictionary
	if row.is_empty():
		return false
	row["arriving_contract_id"] = ""
	row["arriving_commodity_id"] = ""
	row["cargo_manifest"] = {}
	_settle_arrival_revenue(row, vessel_uid)
	if bool(row.get("stop_after_leg", false)):
		row["status"] = "inactive"
	fleet[vessel_uid] = row
	_state["fleet"] = fleet
	_publish(true)
	return true


func mark_cargo_ready(vessel_uid: String, ready: bool = true) -> bool:
	var fleet := _state.get("fleet", {}) as Dictionary
	var row := fleet.get(vessel_uid, {}) as Dictionary
	if row.is_empty():
		return false
	row["cargo_ready"] = ready
	fleet[vessel_uid] = row
	_state["fleet"] = fleet
	_publish(true)
	return true


func depart_prepared_vessel(vessel_uid: String) -> Dictionary:
	var row := (_state.get("fleet", {}) as Dictionary).get(vessel_uid, {}) as Dictionary
	if row.is_empty() or str(row.get("status", "")) not in ["preparing", "turnaround", "unpaid"]:
		return {"ok": false, "reason": "Vessel is not preparing to depart"}
	if not bool(row.get("cargo_ready", false)):
		return {"ok": false, "reason": "Cargo operations are not complete"}
	return _start_next_leg(vessel_uid, int(Time.get_unix_time_from_system()))


func recall_deployed_vessel(vessel_uid: String) -> bool:
	var ship := PlayerVessel.find_active_ship(get_tree())
	if ship == null or str(ship.get_meta("vessel_uid", "")) != vessel_uid:
		return false
	if ship.get_moored_berth_id().is_empty():
		return false
	PlayerVessel.despawn_all_ships(get_tree())
	if _session != null and _session.has_method("save_now"):
		_session.call("save_now")
	_publish(false)
	return true


func end_assignment(vessel_uid: String) -> bool:
	var fleet := _state.get("fleet", {}) as Dictionary
	var row := fleet.get(vessel_uid, {}) as Dictionary
	if row.is_empty() or str(row.get("status", "")) == "underway":
		return false
	var freight := get_node_or_null("/root/FreightService")
	if freight != null:
		for key in ["physical_contract_id", "arriving_contract_id"]:
			var contract_id := str(row.get(key, ""))
			if not contract_id.is_empty():
				freight.cancel_company_contract(contract_id)
	fleet.erase(vessel_uid)
	_state["fleet"] = fleet
	_add_ledger("route_ended", 0, "%s service assignment ended" % _vessel_name(vessel_uid))
	_publish(true)
	return true


func advance_to(now_unix: int) -> void:
	if _state.is_empty():
		return
	var previous := int(_state.get("last_simulated_unix", now_unix))
	if now_unix <= previous:
		return
	_apply_live_traffic_delays(now_unix - previous)
	var changed := false
	# Settle globally by event time. This makes shared-payroll outcomes stable
	# regardless of dictionary insertion order or how long the game was closed.
	while true:
		var next_uid := ""
		var next_ends := 0
		var next_kind := ""
		var fleet := _state.get("fleet", {}) as Dictionary
		var vessel_uids := PackedStringArray()
		for uid_raw in fleet.keys():
			vessel_uids.append(str(uid_raw))
		vessel_uids.sort()
		for vessel_uid in vessel_uids:
			var row := fleet.get(vessel_uid, {}) as Dictionary
			var status := str(row.get("status", ""))
			var ends := 0
			var kind := ""
			if status == "underway" and not _local_voyage_simulation.has(vessel_uid):
				ends = int(row.get("leg_ends_unix", 0))
				kind = "arrival"
			elif status in ["preparing", "turnaround"] and not _local_operations.has(vessel_uid):
				ends = int(row.get("turnaround_ends_unix", 0))
				kind = "departure"
			else:
				continue
			if ends <= 0 or ends > now_unix:
				continue
			if next_uid.is_empty() or ends < next_ends:
				next_uid = vessel_uid
				next_ends = ends
				next_kind = kind
		if next_uid.is_empty():
			break
		if next_kind == "arrival":
			_complete_leg(next_uid, next_ends)
		else:
			_abstract_turnaround_and_depart(next_uid, next_ends)
		changed = true
	_state["last_simulated_unix"] = now_unix
	if changed:
		_publish(true)


func _apply_live_traffic_delays(delta_s: int) -> void:
	## Offline timestamps establish the initial deterministic point. Once the
	## world is live, traffic authority may pause an abstract vessel just like a
	## physical captain; shifting its leg clock preserves that delayed progress.
	if delta_s <= 0:
		return
	var traffic := get_node_or_null("/root/MaritimeTraffic")
	if traffic == null:
		return
	var traffic_snapshot: Dictionary = traffic.snapshot()
	var intents := traffic_snapshot.get("intents", {}) as Dictionary
	var blocks := traffic_snapshot.get("blocks", {}) as Dictionary
	var fleet := _state.get("fleet", {}) as Dictionary
	for uid_raw in fleet.keys():
		var uid := str(uid_raw)
		if _local_voyage_simulation.has(uid):
			continue
		var row := fleet[uid] as Dictionary
		if str(row.get("status", "")) != "underway":
			continue
		var intent := intents.get(uid, {}) as Dictionary
		var held := str(intent.get("phase", "")) in ["holding", "waiting_approach"]
		if not held:
			for block_raw in blocks.values():
				for queued_raw in (block_raw as Dictionary).get("queue", []) as Array:
					if str((queued_raw as Dictionary).get("vessel_id", "")) == uid:
						held = true
						break
				if held:
					break
		if not held:
			continue
		for key in ["leg_started_unix", "departure_ready_unix", "leg_ends_unix"]:
			if row.has(key):
				row[key] = int(row[key]) + delta_s
		row["traffic_delay_seconds"] = int(row.get("traffic_delay_seconds", 0)) + delta_s
		fleet[uid] = row
	_state["fleet"] = fleet


func _complete_leg(vessel_uid: String, at_unix: int) -> void:
	var fleet := _state.get("fleet", {}) as Dictionary
	var row := fleet.get(vessel_uid, {}) as Dictionary
	if row.is_empty():
		return
	var route := row.get("route", {}) as Dictionary
	var payout := maxi(int(route.get("pay_marks", 0)), 0)
	row["current_port_id"] = str(row.get("leg_destination_port_id", ""))
	row["current_berth_id"] = str(row.get("leg_destination_berth_id", ""))
	row.erase("current_berth_yaw")
	row["first_departure_pending"] = false
	row["arrival_pending_settlement"] = true
	row["pending_revenue_marks"] = payout
	row["arriving_contract_id"] = str(row.get("physical_contract_id", ""))
	row["arriving_commodity_id"] = str(row.get("commodity_id", ""))
	row["physical_contract_id"] = ""
	row["cargo_ready"] = false
	row["status"] = "turnaround"
	row["turnaround_ends_unix"] = at_unix + ABSTRACT_TURNAROUND_SECONDS
	_prepare_next_leg(row)
	fleet[vessel_uid] = row
	_state["fleet"] = fleet


func _abstract_turnaround_and_depart(vessel_uid: String, at_unix: int) -> void:
	var fleet := _state.get("fleet", {}) as Dictionary
	var row := fleet.get(vessel_uid, {}) as Dictionary
	if row.is_empty() or str(row.get("status", "")) not in ["preparing", "turnaround"]:
		return
	var contract_id := str(row.get("physical_contract_id", ""))
	var freight := get_node_or_null("/root/FreightService")
	if freight != null and not contract_id.is_empty():
		freight.cancel_company_contract(contract_id)
	row["arriving_contract_id"] = ""
	row["arriving_commodity_id"] = ""
	row["cargo_manifest"] = {}
	row["physical_contract_id"] = ""
	_settle_arrival_revenue(row, vessel_uid)
	if bool(row.get("stop_after_leg", false)):
		row["status"] = "inactive"
		fleet[vessel_uid] = row
		_state["fleet"] = fleet
		return
	_ensure_abstract_cargo(row, vessel_uid)
	row["cargo_ready"] = true
	fleet[vessel_uid] = row
	_state["fleet"] = fleet
	_start_next_leg(vessel_uid, at_unix, false)


func _settle_arrival_revenue(row: Dictionary, vessel_uid: String) -> void:
	if not bool(row.get("arrival_pending_settlement", false)):
		return
	var payout := maxi(int(row.get("pending_revenue_marks", 0)), 0)
	if payout > 0 and _session != null:
		_session.earn_marks(payout)
	row["completed_legs"] = int(row.get("completed_legs", 0)) + 1
	row["revenue_marks"] = int(row.get("revenue_marks", 0)) + payout
	row["arrival_pending_settlement"] = false
	row["pending_revenue_marks"] = 0
	_add_ledger("freight_income", payout, "%s completed a freight leg" % _vessel_name(vessel_uid))


func _ensure_abstract_cargo(row: Dictionary, vessel_uid: String) -> void:
	if not (row.get("cargo_manifest", {}) as Dictionary).is_empty():
		return
	var vessel := _owned_vessel(vessel_uid)
	var layout := BrickLayout.from_dict(vessel.get("brick_layout", {}) as Dictionary)
	var commodity_id := str(row.get("commodity_id", "provisions"))
	var handling := CommodityCatalog.commodity_handling_mode(commodity_id)
	var contract_id := "company-freight:%s:%d" % [vessel_uid, int(row.get("completed_legs", 0))]
	if handling == "bulk":
		var hold_states: Array[Dictionary] = []
		var hold_index := 0
		for raw in layout.iter_bulk_holds():
			var hold := raw as Dictionary
			var mn := BrickLayout.zone_min(hold)
			var mx := BrickLayout.zone_max(hold)
			var width_m := float(mx.x - mn.x + 1) * DeckGrid.CELL_M
			var length_m := float(mx.z - mn.z + 1) * DeckGrid.CELL_M
			var entry := BrickCatalog.get_entry(str(hold.get("brick_id", "bulk_hold_6x12")))
			var depth_m := float(entry.get("hold_depth_m", 2.5))
			var capacity := BulkCargoRules.hold_capacity_tonnes(
				width_m, length_m, depth_m, commodity_id)
			hold_states.append({
				"hold_id": "hold_%d" % hold_index,
				"commodity_id": commodity_id,
				"capacity_tonnes_t": capacity,
				"filled_tonnes_t": capacity,
			})
			hold_index += 1
		row["physical_contract_id"] = "company-bulk:%s:%d" % [
			vessel_uid, int(row.get("completed_legs", 0))]
		row["cargo_manifest"] = {
			"kind": "bulk",
			"contract_id": row["physical_contract_id"],
			"commodity_id": commodity_id,
			"holds": hold_states,
		}
		return
	var capacity_units := 0
	var footprint := ContainerUnit.DEFAULT_FOOTPRINT
	for raw in layout.iter_container_pads():
		var pad := raw as Dictionary
		var mn := BrickLayout.zone_min(pad)
		var mx := BrickLayout.zone_max(pad)
		capacity_units += ((mx.x - mn.x + 1) / footprint.x) * ((mx.z - mn.z + 1) / footprint.y)
	var quantity := mini(capacity_units, 8 + posmod(contract_id.hash(), 5))
	if quantity <= 0:
		return
	var route := row.get("route", {}) as Dictionary
	var contract := {
		"id": contract_id,
		"status": "loaded",
		"origin_port_id": str(row.get("leg_origin_port_id", "")),
		"destination_port_id": str(row.get("leg_destination_port_id", "")),
		"commodity_id": commodity_id,
		"handling_mode": handling,
		"quantity": quantity,
		"quantity_unit": "units",
		"pay_marks": int(route.get("pay_marks", 0)),
		"vessel_uid": vessel_uid,
		"berth_id": str(row.get("leg_origin_berth_id", "")),
		"loaded_quantity": quantity,
		"issued_quantity": quantity,
		"delivered_quantity": 0,
		"company_managed": true,
	}
	contract["consignment"] = CargoConsignment.from_contract(contract).to_dict()
	var units: Array[Dictionary] = []
	for index in range(quantity):
		var unit := ContainerUnit.create("%s:unit:%d" % [contract_id, index], commodity_id)
		unit.origin_port_id = str(contract["origin_port_id"])
		unit.destination_port_id = str(contract["destination_port_id"])
		unit.freight_contract_id = contract_id
		unit.consignment_id = str((contract["consignment"] as Dictionary).get("consignment_id", ""))
		unit.delivery_value_marks = int(round(float(contract["pay_marks"]) / float(quantity)))
		unit.paint_variant = posmod(contract_id.hash() + index, ContainerPaintMaterial.FREIGHT_PALETTE.size())
		units.append(unit.to_dict())
	row["physical_contract_id"] = contract_id
	row["cargo_manifest"] = {"kind": "units", "contract": contract, "units": units}


func _start_next_leg(vessel_uid: String, at_unix: int, publish_change: bool = true) -> Dictionary:
	var fleet := _state.get("fleet", {}) as Dictionary
	var row := fleet.get(vessel_uid, {}) as Dictionary
	if row.is_empty():
		return {"ok": false, "reason": "Fleet assignment missing"}
	if not bool(row.get("cargo_ready", false)):
		return {"ok": false, "reason": "Cargo is not ready"}
	var route := row.get("route", {}) as Dictionary
	var leg_distance := _planned_leg_distance_m(row)
	var duration := maxi(int(ceil(_voyage_duration_s(leg_distance))), MIN_LEG_SECONDS)
	var wage_cost := _leg_wage(row, duration)
	if _session == null or not _session.spend_marks(wage_cost):
		row["status"] = "unpaid"
		row["stop_reason"] = "Insufficient marks for next crew payroll"
		fleet[vessel_uid] = row
		_state["fleet"] = fleet
		fleet_event.emit("%s is held at berth: payroll unavailable" % _vessel_name(vessel_uid))
		if publish_change:
			_publish(true)
		return {"ok": false, "reason": str(row["stop_reason"])}
	var current := str(row.get("current_port_id", route.get("origin_port_id", "")))
	var a := str(route.get("origin_port_id", ""))
	var b := str(route.get("destination_port_id", ""))
	var destination := b if current == a else a
	row["status"] = "underway"
	row["leg_origin_port_id"] = current
	row["leg_destination_port_id"] = destination
	row["leg_started_unix"] = at_unix
	row["departure_ready_unix"] = at_unix
	row["leg_ends_unix"] = at_unix + duration
	row["leg_distance_m"] = leg_distance
	row["commodity_id"] = str(route.get(
		"outbound_commodity_id" if current == a else "return_commodity_id", "provisions"))
	row["wages_marks"] = int(row.get("wages_marks", 0)) + wage_cost
	row["cargo_ready"] = false
	row.erase("stop_reason")
	fleet[vessel_uid] = row
	_state["fleet"] = fleet
	_add_ledger("crew_wages", -wage_cost, "%s crew paid for next leg" % _vessel_name(vessel_uid))
	if publish_change:
		_publish(true)
	return {"ok": true, "reason": "", "wage_cost": wage_cost}


func _prepare_next_leg(row: Dictionary) -> void:
	var route := row.get("route", {}) as Dictionary
	var current := str(row.get("current_port_id", route.get("origin_port_id", "")))
	var a := str(route.get("origin_port_id", ""))
	var b := str(route.get("destination_port_id", ""))
	row["leg_origin_port_id"] = current
	row["leg_destination_port_id"] = b if current == a else a
	row["leg_origin_berth_id"] = str(row.get("current_berth_id", ""))
	row["leg_origin_berth_yaw"] = float(row.get("current_berth_yaw", INF))
	row["leg_origin_position_xz"] = (row.get("current_berth_position_xz", []) as Array).duplicate()
	row.erase("leg_destination_position_xz")
	row["commodity_id"] = str(route.get(
		"outbound_commodity_id" if current == a else "return_commodity_id", "provisions"))
	row["leg_destination_berth_id"] = BerthApproachLanes.best_target_id(
		str(row.get("leg_destination_port_id", "")),
		CommodityCatalog.commodity_terminal_family(str(row.get("commodity_id", ""))),
		str(row.get("commodity_id", "")),
	)


func _planned_leg_distance_m(row: Dictionary) -> float:
	var route := row.get("route", {}) as Dictionary
	var fallback := maxf(float(route.get("distance_m", 0.0)), CRUISE_SPEED_MS * MIN_LEG_SECONDS)
	var catalog := get_node_or_null("/root/PortCatalog")
	if catalog == null or not is_inside_tree():
		return fallback
	var origin_id := str(row.get("leg_origin_port_id", ""))
	var destination_id := str(row.get("leg_destination_port_id", ""))
	var origin := catalog.get_port_position(origin_id) as Vector3
	var destination := catalog.get_port_position(destination_id) as Vector3
	var world := get_tree().get_first_node_in_group("world")
	var layout := world.call("get_world_layout") as WorldLayout if world != null else null
	if layout == null:
		return fallback
	var plan := _cached_leg_plan(
		layout, origin, destination, origin_id,
		str(row.get("leg_origin_berth_id", "")), destination_id,
		str(row.get("leg_destination_berth_id", "")),
		_xz_from_row(row, "leg_origin_position_xz"),
		_xz_from_row(row, "leg_destination_position_xz"),
	)
	return plan.total_distance_m() if plan.is_valid() else fallback


func _voyage_profile(distance_m: float) -> Dictionary:
	var total := maxf(distance_m, 0.0)
	var crab_each := minf(CRAB_ZONE_M, total * 0.12)
	var harbour_each := minf(HARBOUR_ZONE_M, maxf(total * 0.5 - crab_each, 0.0))
	var passage := maxf(total - 2.0 * (crab_each + harbour_each), 0.0)
	return {
		"crab_each": crab_each,
		"harbour_each": harbour_each,
		"passage": passage,
	}


func _voyage_duration_s(distance_m: float) -> float:
	var profile := _voyage_profile(distance_m)
	return (
		2.0 * float(profile["crab_each"]) / CRAB_SPEED_MS
		+ 2.0 * float(profile["harbour_each"]) / HARBOUR_SPEED_MS
		+ float(profile["passage"]) / CRUISE_SPEED_MS
	)


func _voyage_distance_at_elapsed(distance_m: float, elapsed_s: float) -> float:
	var profile := _voyage_profile(distance_m)
	var remaining := maxf(elapsed_s, 0.0)
	var travelled := 0.0
	var segments := [
		[float(profile["crab_each"]), CRAB_SPEED_MS],
		[float(profile["harbour_each"]), HARBOUR_SPEED_MS],
		[float(profile["passage"]), CRUISE_SPEED_MS],
		[float(profile["harbour_each"]), HARBOUR_SPEED_MS],
		[float(profile["crab_each"]), CRAB_SPEED_MS],
	]
	for segment in segments:
		var segment_distance := float(segment[0])
		var speed := float(segment[1])
		var segment_time := segment_distance / speed if speed > 0.0 else 0.0
		if remaining >= segment_time:
			travelled += segment_distance
			remaining -= segment_time
			continue
		travelled += remaining * speed
		break
	return minf(travelled, maxf(distance_m, 0.0))


func _voyage_elapsed_at_distance(distance_m: float, travelled_m: float) -> float:
	var profile := _voyage_profile(distance_m)
	var remaining := clampf(travelled_m, 0.0, maxf(distance_m, 0.0))
	var elapsed := 0.0
	var segments := [
		[float(profile["crab_each"]), CRAB_SPEED_MS],
		[float(profile["harbour_each"]), HARBOUR_SPEED_MS],
		[float(profile["passage"]), CRUISE_SPEED_MS],
		[float(profile["harbour_each"]), HARBOUR_SPEED_MS],
		[float(profile["crab_each"]), CRAB_SPEED_MS],
	]
	for segment in segments:
		var segment_distance := float(segment[0])
		var speed := float(segment[1])
		var consumed := minf(remaining, segment_distance)
		elapsed += consumed / speed if speed > 0.0 else 0.0
		remaining -= consumed
		if remaining <= 0.001:
			break
	return elapsed


func _cached_leg_plan(
		layout: WorldLayout,
		origin: Vector3,
		destination: Vector3,
		origin_id: String,
		origin_berth_id: String,
		destination_id: String,
		destination_berth_id: String,
		origin_exact_xz: Vector2 = Vector2(INF, INF),
		destination_exact_xz: Vector2 = Vector2(INF, INF),
) -> MarineRoutePlan:
	if layout == null:
		return MarineRoutePlan.new()
	var origin_lane := BerthApproachLanes.get_target_lane(
		origin_id, origin_berth_id, BerthApproachLanes.LaneKind.SPINE)
	var destination_lane := BerthApproachLanes.get_target_lane(
		destination_id, destination_berth_id, BerthApproachLanes.LaneKind.SPINE)
	var cache_key := "%s|%s/%s:%s:%s>%s/%s:%s:%s" % [
		str(layout.layout_checksum), origin_id, origin_berth_id,
		_lane_cache_token(origin_lane), _xz_cache_token(origin_exact_xz),
		destination_id, destination_berth_id, _lane_cache_token(destination_lane),
		_xz_cache_token(destination_exact_xz),
	]
	var plan := _projection_plan_cache.get(cache_key) as MarineRoutePlan
	if plan == null:
		plan = MarineRoutePlanner.new(layout).plan_berth_to_berth(
			Vector2(origin.x, origin.z), Vector2(destination.x, destination.z),
			origin_id, origin_berth_id, destination_id, destination_berth_id,
			origin_exact_xz, destination_exact_xz,
		)
		_projection_plan_cache[cache_key] = plan
	return plan


func _lane_cache_token(lane: Array) -> String:
	if lane.is_empty():
		return "0"
	var first := lane[0] as Vector3
	var last := lane[-1] as Vector3
	return "%d@%.2f,%.2f>%.2f,%.2f" % [
		lane.size(), first.x, first.z, last.x, last.z,
	]


func _leg_wage(row: Dictionary, duration_s: int) -> int:
	var total := 0.0
	for crew_id in row.get("crew_ids", PackedStringArray()) as PackedStringArray:
		total += float(employee(crew_id).get("wage_per_hour", 20)) * float(duration_s) / 3600.0
	return maxi(int(ceil(total)), 1)


func _on_data_loaded(data: PlayerData) -> void:
	_local_operations.clear()
	_local_voyage_simulation.clear()
	if data == null:
		_state = {}
		return
	_state = _normalize(data.company_state)
	_projection_plan_cache.clear()
	_route_templates_cache.clear()
	_route_templates_cache_key = ""
	data.company_state = _state
	var now := int(Time.get_unix_time_from_system())
	_last_tick_unix = now
	advance_to(now)
	if str(data.account_id).is_empty() and str(data.captain_id).is_empty():
		return
	if str(_state.get("name", "")).is_empty():
		company_name_required.emit()
	_publish(false)


func _normalize(raw: Dictionary) -> Dictionary:
	var now := int(Time.get_unix_time_from_system())
	var out := raw.duplicate(true) if not raw.is_empty() else {}
	out["schema_version"] = SCHEMA_VERSION
	out["name"] = str(out.get("name", ""))
	out["employees"] = (out.get("employees", []) as Array).duplicate(true)
	var fleet := (out.get("fleet", {}) as Dictionary).duplicate(true)
	var employee_ids: Dictionary = {}
	for employee_raw in out["employees"] as Array:
		var employee_row := employee_raw as Dictionary
		var employee_id := str(employee_row.get("id", "")).strip_edges()
		if not employee_id.is_empty():
			employee_ids[employee_id] = true
	for uid_raw in fleet.keys():
		var uid := str(uid_raw)
		var row := fleet.get(uid, {}) as Dictionary
		if row.is_empty() or (row.get("route", {}) as Dictionary).is_empty():
			fleet.erase(uid)
			continue
		var crew_ids := PackedStringArray()
		for crew_raw in row.get("crew_ids", []):
			var crew_id := str(crew_raw).strip_edges()
			if employee_ids.has(crew_id) and crew_id not in crew_ids:
				crew_ids.append(crew_id)
		row["crew_ids"] = crew_ids
		var status := str(row.get("status", ""))
		if status == "berthed":
			row["status"] = "preparing"
		elif status not in ["preparing", "underway", "turnaround", "inactive", "unpaid"]:
			row["status"] = "inactive"
		row["cargo_ready"] = bool(row.get("cargo_ready", false))
		row["physical_contract_id"] = str(row.get("physical_contract_id", ""))
		row["arriving_contract_id"] = str(row.get("arriving_contract_id", ""))
		row["arriving_commodity_id"] = str(row.get("arriving_commodity_id", ""))
		row["cargo_manifest"] = (row.get("cargo_manifest", {}) as Dictionary).duplicate(true)
		if str(row.get("status", "")) != "underway":
			_prepare_next_leg(row)
		if str(row.get("status", "")) in ["preparing", "turnaround"]:
			row["turnaround_ends_unix"] = int(row.get(
				"turnaround_ends_unix", now + ABSTRACT_TURNAROUND_SECONDS))
			if int(row["turnaround_ends_unix"]) <= 0:
				row["turnaround_ends_unix"] = now + ABSTRACT_TURNAROUND_SECONDS
		fleet[uid] = row
	out["fleet"] = fleet
	out["ledger"] = (out.get("ledger", []) as Array).duplicate(true)
	out["last_simulated_unix"] = int(out.get("last_simulated_unix", now))
	return out


func _publish(save: bool) -> void:
	if _session != null and _session.data != null:
		_session.data.company_state = _state
		if save:
			_session.call("_request_save")
	company_changed.emit(snapshot())


func _add_ledger(kind: String, amount: int, memo: String) -> void:
	var ledger := _state.get("ledger", []) as Array
	ledger.push_front({
		"timestamp_unix": int(Time.get_unix_time_from_system()),
		"kind": kind,
		"amount": amount,
		"memo": memo,
	})
	if ledger.size() > MAX_LEDGER_ROWS:
		ledger.resize(MAX_LEDGER_ROWS)
	_state["ledger"] = ledger


func _owned_vessel(record_uid: String) -> Dictionary:
	if _session == null or _session.data == null:
		return {}
	return _session.data.find_owned_vessel(record_uid)


func _owned_vessel_rows(routes: Array[Dictionary] = []) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _session == null or _session.data == null:
		return out
	if routes.is_empty():
		routes = _route_templates()
	var fleet := _state.get("fleet", {}) as Dictionary
	var deployed := PlayerVessel.find_active_ship(get_tree())
	var deployed_uid := str(deployed.get_meta("vessel_uid", "")) if deployed != null else ""
	var deployed_berth := deployed.get_moored_berth_id() if deployed != null else ""
	for raw in _session.data.owned_vessels:
		var vessel := raw as Dictionary
		var copy := vessel.duplicate(true)
		copy["required_crew"] = _required_crew(vessel)
		var supported_routes := PackedStringArray()
		for route in routes:
			if _vessel_can_run_route(vessel, route):
				supported_routes.append(str(route.get("id", "")))
		copy["supported_route_ids"] = supported_routes
		var uid := str(vessel.get("uid", ""))
		copy["deployed_for_player"] = uid == deployed_uid
		copy["deployed_at_berth"] = uid == deployed_uid and not deployed_berth.is_empty()
		var assignment := (fleet.get(uid, {}) as Dictionary).duplicate(true)
		if not assignment.is_empty():
			assignment["projection"] = fleet_projection(uid)
		copy["company_assignment"] = assignment
		out.append(copy)
	return out


func fleet_projection(vessel_uid: String, now_unix: float = -1.0) -> Dictionary:
	var row := (_state.get("fleet", {}) as Dictionary).get(vessel_uid, {}) as Dictionary
	if row.is_empty():
		return {}
	if now_unix < 0.0:
		now_unix = Time.get_unix_time_from_system()
	var underway := str(row.get("status", "")) == "underway"
	var current_port_id := str(row.get("current_port_id", ""))
	var origin_id := str(row.get("leg_origin_port_id", current_port_id)) if underway else current_port_id
	var destination_id := str(row.get("leg_destination_port_id", origin_id)) if underway else origin_id
	var origin_berth_id := str(row.get("leg_origin_berth_id", row.get("current_berth_id", "")))
	var destination_berth_id := str(row.get("leg_destination_berth_id", origin_berth_id)) if underway \
		else str(row.get("current_berth_id", origin_berth_id))
	var catalog := get_node_or_null("/root/PortCatalog")
	if catalog == null:
		return {}
	var origin := catalog.get_port_position(origin_id) as Vector3
	var destination := catalog.get_port_position(destination_id) as Vector3
	var started := float(row.get("departure_ready_unix", row.get("leg_started_unix", now_unix)))
	var ends := float(row.get("leg_ends_unix", started))
	var progress := 0.0
	if underway and ends > started:
		var saved_distance := maxf(float(row.get("leg_distance_m", 0.0)), 1.0)
		progress = _voyage_distance_at_elapsed(saved_distance, now_unix - started) / saved_distance
	elif origin_id == destination_id:
		progress = 1.0
	var position := origin.lerp(destination, progress)
	var heading := Vector2(destination.x - origin.x, destination.z - origin.z).normalized()
	if not underway and not destination_berth_id.is_empty():
		var berth_position := BerthApproachLanes.target_world_position(origin_id, destination_berth_id)
		if berth_position != Vector3.ZERO:
			position = berth_position
	var world := get_tree().get_first_node_in_group("world")
	var layout := world.call("get_world_layout") as WorldLayout if world != null else null
	var route_progress_m := 0.0
	var route_distance_m := 0.0
	if layout != null and underway:
		var plan := _cached_leg_plan(
			layout, origin, destination, origin_id, origin_berth_id,
			destination_id, destination_berth_id,
			_xz_from_row(row, "leg_origin_position_xz"),
			_xz_from_row(row, "leg_destination_position_xz"),
		)
		if plan.is_valid():
			var distance := _voyage_distance_at_elapsed(plan.total_distance_m(), now_unix - started)
			route_progress_m = distance
			route_distance_m = plan.total_distance_m()
			progress = distance / maxf(plan.total_distance_m(), 1.0)
			var point := plan.point_at_distance(distance)
			var ahead := plan.point_at_distance(minf(distance + 20.0, plan.total_distance_m()))
			position = Vector3(point.x, WaveSurface.WATER_LEVEL, point.y)
			heading = (ahead - point).normalized()
			var profile := _voyage_profile(plan.total_distance_m())
			var origin_yaw := float(row.get("leg_origin_berth_yaw", INF))
			if is_finite(origin_yaw) and distance <= float(profile["crab_each"]):
				heading = Vector2(-sin(origin_yaw), -cos(origin_yaw))
	return {
		"position": position,
		"heading_xz": heading,
		"progress": progress,
		"route_progress_m": route_progress_m,
		"route_distance_m": route_distance_m,
		"eta_seconds": maxi(int(ceil(ends - now_unix)), 0) if underway else 0,
		"awaiting_departure": underway and now_unix < started,
		"berthed": not underway,
		"origin_port_id": origin_id,
		"destination_port_id": destination_id,
	}


func leg_route_plan(vessel_uid: String) -> MarineRoutePlan:
	var row := (_state.get("fleet", {}) as Dictionary).get(vessel_uid, {}) as Dictionary
	if row.is_empty():
		return MarineRoutePlan.new()
	var catalog := get_node_or_null("/root/PortCatalog")
	var world := get_tree().get_first_node_in_group("world") if is_inside_tree() else null
	var layout := world.call("get_world_layout") as WorldLayout if world != null else null
	if catalog == null or layout == null:
		return MarineRoutePlan.new()
	var origin_id := str(row.get("leg_origin_port_id", ""))
	var destination_id := str(row.get("leg_destination_port_id", ""))
	return _cached_leg_plan(
		layout,
		catalog.get_port_position(origin_id) as Vector3,
		catalog.get_port_position(destination_id) as Vector3,
		origin_id,
		str(row.get("leg_origin_berth_id", "")),
		destination_id,
		str(row.get("leg_destination_berth_id", "")),
		_xz_from_row(row, "leg_origin_position_xz"),
		_xz_from_row(row, "leg_destination_position_xz"),
	)


func _xz_from_row(row: Dictionary, key: String) -> Vector2:
	var raw := row.get(key, []) as Array
	if raw.size() < 2:
		return Vector2(INF, INF)
	return Vector2(float(raw[0]), float(raw[1]))


func _xz_cache_token(value: Vector2) -> String:
	if not value.is_finite():
		return "auto"
	return "%d,%d" % [roundi(value.x), roundi(value.y)]


func _required_crew(vessel: Dictionary) -> int:
	var hull := HullRegistry.get_by_id(str(vessel.get("hull_id", "")))
	return ShipClass.crew_slots(int(hull.get("ship_class", ShipClass.Type.COASTAL_TRADER)))


func _employee_assignment(employee_id: String) -> String:
	for vessel_uid in (_state.get("fleet", {}) as Dictionary).keys():
		var row := (_state["fleet"] as Dictionary).get(vessel_uid, {}) as Dictionary
		if (row.get("crew_ids", PackedStringArray()) as PackedStringArray).has(employee_id):
			return str(vessel_uid)
	return ""


func _crew_candidates() -> Array[Dictionary]:
	var owner := "captain"
	if _session != null and _session.data != null:
		owner = str(_session.data.account_id if not _session.data.account_id.is_empty() else _session.data.captain_id)
	var first := ["Astrid", "Elias", "Ingrid", "Marius", "Sigrid", "Tobias", "Runa", "Henrik", "Liv", "Oskar"]
	var last := ["Berg", "Dahl", "Eide", "Haugen", "Moen", "Nilsen", "Solberg", "Vik", "Lunde", "Aasen"]
	var existing: Dictionary = {}
	for raw in _state.get("employees", []) as Array:
		existing[str((raw as Dictionary).get("id", ""))] = true
	var out: Array[Dictionary] = []
	for index in range(48):
		var seed := owner.hash() + index * 7919
		var id := "crew:%08x:%d" % [owner.hash() & 0xffffffff, index]
		if existing.has(id):
			continue
		out.append({
			"id": id,
			"name": "%s %s" % [first[posmod(seed, first.size())], last[posmod(int(seed / 17), last.size())]],
			"role": "Deck crew" if index % 3 else "Mate",
			"wage_per_hour": 18 + posmod(int(seed / 31), 17),
			"hired_at_unix": 0,
		})
	return out


func _route_templates() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var catalog := get_node_or_null("/root/PortCatalog")
	if catalog == null or _session == null or _session.data == null:
		return out
	var origin_id: String = str(_session.data.home_port_id)
	var origin := catalog.get_port_info(origin_id) as Dictionary
	if origin.is_empty():
		return out
	var world := get_tree().get_first_node_in_group("world")
	var layout := world.call("get_world_layout") as WorldLayout if world != null else null
	var cache_key := "%s|%s|%d" % [
		origin_id, str(layout.layout_checksum) if layout != null else "no-layout",
		catalog.get_port_ids().size(),
	]
	if cache_key == _route_templates_cache_key and not _route_templates_cache.is_empty():
		return _route_templates_cache
	for destination_id in catalog.get_port_ids():
		if destination_id == origin_id:
			continue
		var destination := catalog.get_port_info(destination_id) as Dictionary
		var distance := (destination.get("position", Vector3.ZERO) as Vector3).distance_to(
			origin.get("position", Vector3.ZERO) as Vector3)
		if distance < 500.0:
			continue
		var outbound_commodity := _route_commodity(origin, destination)
		var return_commodity := _route_commodity(destination, origin)
		if outbound_commodity.is_empty() or return_commodity.is_empty():
			continue
		var duration := maxi(int(distance / CRUISE_SPEED_MS), MIN_LEG_SECONDS)
		out.append({
			"id": "company-route:%s:%s" % [origin_id, destination_id],
			"origin_port_id": origin_id,
			"destination_port_id": str(destination_id),
			"origin_name": str(origin.get("display_name", origin_id)),
			"destination_name": str(destination.get("display_name", destination_id)),
			"outbound_commodity_id": outbound_commodity,
			"return_commodity_id": return_commodity,
			"distance_m": distance,
			"duration_seconds": duration,
			"pay_marks": maxi(80, int(round(distance / 1000.0 * 42.0))),
		})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("distance_m", INF)) < float(b.get("distance_m", INF)))
	if out.size() > 36:
		out.resize(36)
	_route_templates_cache = out
	_route_templates_cache_key = cache_key
	return out


func _route_template(route_id: String) -> Dictionary:
	for route in _route_templates():
		if str(route.get("id", "")) == route_id:
			return route
	return {}


func _route_commodity(origin: Dictionary, destination: Dictionary) -> String:
	var imports := destination.get("commodity_imports", []) as Array
	for raw in origin.get("commodity_exports", []) as Array:
		var commodity_id := str(raw)
		if imports.has(commodity_id) and CommodityCatalog.commodity_handling_mode(commodity_id) in ["general", "container", "bulk"]:
			return commodity_id
	return ""


func _vessel_can_run_route(vessel: Dictionary, route: Dictionary) -> bool:
	var supported := HarbourDeploy.terminal_families_for_registration(
		str(vessel.get("registration_id", "")))
	if supported.is_empty():
		return false
	for key in ["outbound_commodity_id", "return_commodity_id"]:
		var family := CommodityCatalog.commodity_terminal_family(str(route.get(key, "")))
		if family not in supported:
			return false
	return true


func _vessel_name(uid: String) -> String:
	var vessel := _owned_vessel(uid)
	return str(vessel.get("display", vessel.get("name", "Vessel")))
