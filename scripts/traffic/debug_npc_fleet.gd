class_name DebugNpcFleet
extends Node

## Session-only world authority used to inject realistic NPC assignment rows.
## CompanyFleetProjection consumes these through the same authority interface as
## CompanyService, so owned and ambient NPCs share one physical simulation path.

signal company_changed(snapshot: Dictionary)

const DEFAULT_COUNT := 5
const MAX_COUNT := 64
const ABSTRACT_CRUISE_SPEED_MS := 7.2
const ABSTRACT_STEP_S := 0.25
var _fleet: Dictionary = {}
var _local_simulation: Dictionary = {}
var _abstract_elapsed_s := 0.0
var _route_plan_cache: Dictionary = {}
var _route_plan_requests := 0
var _route_plan_cache_hits := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("vessel_fleet_authority")
	call_deferred("_register_telemetry")


func _exit_tree() -> void:
	var telemetry := get_node_or_null("/root/Telemetry")
	if telemetry != null:
		telemetry.unregister_provider(&"debug_npc_fleet", self)


func _register_telemetry() -> void:
	var telemetry := get_node_or_null("/root/Telemetry")
	if telemetry != null:
		telemetry.register_provider(
			&"debug_npc_fleet", self, &"get_debug_stats", &"traffic")


func get_debug_stats() -> Dictionary:
	var underway := 0
	var general := 0
	var bulk := 0
	for record_raw in _fleet.values():
		var assignment := (record_raw as Dictionary).get("assignment", {}) as Dictionary
		if str(assignment.get("status", "")) == "underway":
			underway += 1
		if str((assignment.get("route", {}) as Dictionary).get("handling_mode", "")) == "bulk":
			bulk += 1
		else:
			general += 1
	return {
		"authority_vessels": _fleet.size(),
		"locally_simulated": _local_simulation.size(),
		"abstract_simulated": maxi(_fleet.size() - _local_simulation.size(), 0),
		"underway": underway,
		"general_cargo": general,
		"bulk": bulk,
		"route_cache_entries": _route_plan_cache.size(),
		"route_plan_requests": _route_plan_requests,
		"route_plan_cache_hits": _route_plan_cache_hits,
	}


func _process(delta: float) -> void:
	if not _fleet.is_empty() and _is_main_menu():
		clear_fleet()
		return
	_abstract_elapsed_s += delta
	if _abstract_elapsed_s < ABSTRACT_STEP_S:
		return
	var step := _abstract_elapsed_s
	_abstract_elapsed_s = 0.0
	var changed := false
	var traffic := get_node_or_null("/root/MaritimeTraffic")
	var traffic_snapshot: Dictionary = traffic.snapshot() if traffic != null else {}
	for uid_raw in _fleet.keys():
		var uid := str(uid_raw)
		if _local_simulation.has(uid):
			continue
		var record := _fleet[uid] as Dictionary
		var row := record.get("assignment", {}) as Dictionary
		var plan := record.get("plan") as MarineRoutePlan
		if str(row.get("status", "")) != "underway" or plan == null or not plan.is_valid():
			continue
		var limit := maxf(plan.total_distance_m() - 45.0, 0.0)
		var speed_factor := _authority_speed_factor(uid, traffic_snapshot)
		var progress := minf(
			float(row.get("route_progress_m", 0.0)) \
				+ ABSTRACT_CRUISE_SPEED_MS * speed_factor * step,
			limit,
		)
		if not is_equal_approx(progress, float(row.get("route_progress_m", 0.0))):
			row["route_progress_m"] = progress
			record["assignment"] = row
			changed = true
	if changed:
		company_changed.emit(snapshot())


func _authority_speed_factor(uid: String, traffic_snapshot: Dictionary) -> float:
	if traffic_snapshot.is_empty():
		return 1.0
	var intent := (traffic_snapshot.get("intents", {}) as Dictionary).get(uid, {}) as Dictionary
	if str(intent.get("phase", "")) in ["holding", "waiting_approach"]:
		return 0.0
	for block_raw in (traffic_snapshot.get("blocks", {}) as Dictionary).values():
		for queued_raw in (block_raw as Dictionary).get("queue", []) as Array:
			if str((queued_raw as Dictionary).get("vessel_id", "")) == uid:
				return 0.0
	var traffic := get_node_or_null("/root/MaritimeTraffic")
	var agreement: Dictionary = traffic.agreement_for(uid) if traffic != null else {}
	if agreement.is_empty():
		return 1.0
	return clampf(float((agreement.get("instruction", {}) as Dictionary).get(
		"speed_limit", 1.0)), 0.0, 1.0)


func is_active() -> bool:
	return not _fleet.is_empty()


func vessel_count() -> int:
	return _fleet.size()


func spawn_server_join_fleet(count: int = DEFAULT_COUNT) -> bool:
	clear_fleet()
	var world := get_tree().get_first_node_in_group("world")
	var layout := world.call("get_world_layout") as WorldLayout if world != null \
		and world.has_method("get_world_layout") else null
	var catalog := get_node_or_null("/root/PortCatalog")
	if layout == null or catalog == null:
		return false
	var observer := _observer_xz()
	var candidates := _contract_candidates(catalog, observer)
	_ensure_bulk_candidates(candidates, catalog, observer)
	if candidates.is_empty():
		push_warning("Debug NPC fleet: no valid world cargo routes are available")
		return false
	var desired := clampi(count, 1, MAX_COUNT)
	var selected := _select_mixed_contracts(candidates, desired)
	for index in range(selected.size()):
		var planned := _resolve_planned_contract(selected[index], candidates, layout)
		if planned.is_empty():
			continue
		var contract := (planned.get("contract", {}) as Dictionary).duplicate(true)
		var plan := planned.get("plan") as MarineRoutePlan
		var uid := "debug-traffic-%02d" % (index + 1)
		# The route may intentionally be shared to exercise traffic negotiation,
		# but cargo authority is always per vessel.
		contract["id"] = "%s:vessel:%s" % [contract.get("id", "route"), uid]
		var vessel := _prebuilt_record(
			"bulk_small" if str(contract.get("handling_mode", "")) == "bulk" else "28_10_m",
			uid,
			index,
		)
		if vessel.is_empty() or plan == null or not plan.is_valid():
			continue
		var progress := _join_progress(plan, observer, index)
		_fleet[uid] = {
			"vessel": vessel,
			"assignment": _assignment(contract, progress, plan, uid),
			"plan": plan,
		}
	company_changed.emit(snapshot())
	return not _fleet.is_empty()


func clear_fleet() -> void:
	_fleet.clear()
	_local_simulation.clear()
	_route_plan_cache.clear()
	_route_plan_requests = 0
	_route_plan_cache_hits = 0
	company_changed.emit(snapshot())


func snapshot() -> Dictionary:
	return {"debug": true, "fleet_count": _fleet.size()}


func projection_records() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for uid_raw in _fleet.keys():
		var uid := str(uid_raw)
		var record := _fleet[uid] as Dictionary
		var assignment := record.get("assignment", {}) as Dictionary
		out.append({
			"uid": uid,
			"vessel": (record.get("vessel", {}) as Dictionary).duplicate(true),
			"assignment": assignment.duplicate(true),
			"projection": _projection(record),
		})
	return out


func _resolve_planned_contract(
		preferred: Dictionary,
		candidates: Array[Dictionary],
		layout: WorldLayout,
) -> Dictionary:
	var handling := str(preferred.get("handling_mode", ""))
	var choices: Array[Dictionary] = [preferred]
	for candidate in candidates:
		if str(candidate.get("handling_mode", "")) == handling \
				and str(candidate.get("id", "")) != str(preferred.get("id", "")):
			choices.append(candidate)
	var attempts := 0
	for candidate in choices:
		var plan := _plan_contract(candidate, layout)
		attempts += 1
		if plan != null and plan.is_valid():
			return {"contract": candidate, "plan": plan}
		if attempts >= 12:
			break
	return {}


func leg_route_plan(vessel_uid: String) -> MarineRoutePlan:
	var record := _fleet.get(vessel_uid, {}) as Dictionary
	return record.get("plan") as MarineRoutePlan if not record.is_empty() \
		else MarineRoutePlan.new()


func set_local_voyage_simulation(vessel_uid: String, active: bool) -> void:
	if active:
		_local_simulation[vessel_uid] = true
	else:
		_local_simulation.erase(vessel_uid)


func set_local_operations_active(_vessel_uid: String, _active: bool) -> void:
	pass


func suspend_local_voyage(vessel_uid: String, progress_m: float, _distance_m: float) -> void:
	var record := _fleet.get(vessel_uid, {}) as Dictionary
	if record.is_empty():
		return
	(record["assignment"] as Dictionary)["route_progress_m"] = progress_m
	_local_simulation.erase(vessel_uid)
	company_changed.emit(snapshot())


func complete_local_voyage(
		vessel_uid: String,
		berth_id: String,
		berth_yaw: float,
		berth_position: Vector3,
) -> bool:
	var record := _fleet.get(vessel_uid, {}) as Dictionary
	if record.is_empty():
		return false
	var row := record.get("assignment", {}) as Dictionary
	row["status"] = "turnaround"
	row["current_port_id"] = row.get("leg_destination_port_id", "")
	row["current_berth_id"] = berth_id
	row["current_berth_yaw"] = berth_yaw
	row["current_berth_position_xz"] = [berth_position.x, berth_position.z]
	row["arrival_pending_settlement"] = true
	row["arriving_contract_id"] = str(row.get("physical_contract_id", ""))
	row["arriving_commodity_id"] = str(row.get("commodity_id", ""))
	row["physical_contract_id"] = ""
	row["cargo_ready"] = false
	_prepare_reverse_leg(row)
	record["assignment"] = row
	_local_simulation.erase(vessel_uid)
	company_changed.emit(snapshot())
	return true


func set_current_berth(
		vessel_uid: String,
		berth_id: String,
		berth_yaw: float = INF,
		berth_position: Vector3 = Vector3(INF, INF, INF),
) -> bool:
	var record := _fleet.get(vessel_uid, {}) as Dictionary
	if record.is_empty():
		return false
	var row := record.get("assignment", {}) as Dictionary
	row["current_berth_id"] = berth_id
	if is_finite(berth_yaw):
		row["current_berth_yaw"] = berth_yaw
	if berth_position.is_finite():
		row["current_berth_position_xz"] = [berth_position.x, berth_position.z]
	record["assignment"] = row
	return true


func set_leg_dock_endpoints(vessel_uid: String, origin_xz: Vector2, destination_xz: Vector2) -> bool:
	var record := _fleet.get(vessel_uid, {}) as Dictionary
	if record.is_empty():
		return false
	var row := record.get("assignment", {}) as Dictionary
	if origin_xz.is_finite():
		row["leg_origin_position_xz"] = [origin_xz.x, origin_xz.y]
	if destination_xz.is_finite():
		row["leg_destination_position_xz"] = [destination_xz.x, destination_xz.y]
	record["assignment"] = row
	return true


func _prepare_reverse_leg(row: Dictionary) -> void:
	var old_origin_port := str(row.get("leg_origin_port_id", ""))
	var old_origin_berth := str(row.get("leg_origin_berth_id", ""))
	row["leg_origin_port_id"] = row.get("leg_destination_port_id", "")
	row["leg_origin_berth_id"] = row.get("leg_destination_berth_id", "")
	row["leg_destination_port_id"] = old_origin_port
	row["leg_destination_berth_id"] = old_origin_berth
	row["current_port_id"] = row.get("leg_origin_port_id", "")
	row["commodity_id"] = row.get("return_commodity_id", row.get("commodity_id", "provisions"))
	row["status"] = "turnaround"
	row["route_progress_m"] = 0.0
	row["route"] = {
		"origin_port_id": row.get("leg_origin_port_id", ""),
		"destination_port_id": row.get("leg_destination_port_id", ""),
		"commodity_id": row.get("commodity_id", "provisions"),
	}


func set_physical_contract(vessel_uid: String, contract_id: String) -> bool:
	return _set_assignment_value(vessel_uid, "physical_contract_id", contract_id.strip_edges())


func set_cargo_manifest(vessel_uid: String, manifest: Dictionary) -> bool:
	return _set_assignment_value(vessel_uid, "cargo_manifest", manifest.duplicate(true))


func mark_cargo_ready(vessel_uid: String, ready: bool = true) -> bool:
	return _set_assignment_value(vessel_uid, "cargo_ready", ready)


func confirm_arrival_unloaded(vessel_uid: String) -> bool:
	var record := _fleet.get(vessel_uid, {}) as Dictionary
	if record.is_empty():
		return false
	var row := record.get("assignment", {}) as Dictionary
	row["arriving_contract_id"] = ""
	row["arriving_commodity_id"] = ""
	row["arrival_pending_settlement"] = false
	row["cargo_manifest"] = {}
	record["assignment"] = row
	company_changed.emit(snapshot())
	return true


func depart_prepared_vessel(vessel_uid: String) -> Dictionary:
	var record := _fleet.get(vessel_uid, {}) as Dictionary
	if record.is_empty():
		return {"ok": false, "reason": "Fleet assignment missing"}
	var row := record.get("assignment", {}) as Dictionary
	if str(row.get("status", "")) not in ["preparing", "turnaround"]:
		return {"ok": false, "reason": "Vessel is not preparing to depart"}
	if not bool(row.get("cargo_ready", false)):
		return {"ok": false, "reason": "Cargo is not ready"}
	var world := get_tree().get_first_node_in_group("world")
	var layout := world.call("get_world_layout") as WorldLayout if world != null else null
	var plan := _plan_assignment(row, layout)
	if plan == null or not plan.is_valid():
		return {"ok": false, "reason": "Route planning failed"}
	row["status"] = "underway"
	row["route_progress_m"] = 0.0
	row["leg_distance_m"] = plan.total_distance_m()
	record["assignment"] = row
	record["plan"] = plan
	company_changed.emit(snapshot())
	return {"ok": true, "reason": "", "status": "underway"}


func _set_assignment_value(vessel_uid: String, key: String, value: Variant) -> bool:
	var record := _fleet.get(vessel_uid, {}) as Dictionary
	if record.is_empty():
		return false
	var row := record.get("assignment", {}) as Dictionary
	row[key] = value
	record["assignment"] = row
	company_changed.emit(snapshot())
	return true


func _projection(record: Dictionary) -> Dictionary:
	var row := record.get("assignment", {}) as Dictionary
	var plan := record.get("plan") as MarineRoutePlan
	var underway := str(row.get("status", "")) == "underway"
	var progress := float(row.get("route_progress_m", 0.0))
	if underway and plan != null and plan.is_valid():
		var point := plan.point_at_distance(progress)
		var heading := plan.direction_at_distance(progress, 30.0)
		return {
			"position": Vector3(point.x, WaveSurface.WATER_LEVEL, point.y),
			"heading_xz": heading,
			"route_progress_m": progress,
			"route_distance_m": plan.total_distance_m(),
			"origin_port_id": row.get("leg_origin_port_id", ""),
			"destination_port_id": row.get("leg_destination_port_id", ""),
			"berthed": false,
		}
	var raw := row.get("current_berth_position_xz", []) as Array
	var position := Vector3.ZERO
	if raw.size() >= 2:
		position = Vector3(float(raw[0]), WaveSurface.WATER_LEVEL, float(raw[1]))
	else:
		position = BerthApproachLanes.target_world_position(
			str(row.get("current_port_id", "")), str(row.get("current_berth_id", "")))
	return {"position": position, "origin_port_id": row.get("current_port_id", ""),
		"destination_port_id": row.get("current_port_id", ""), "berthed": true}


func _assignment(
		contract: Dictionary,
		progress: float,
		plan: MarineRoutePlan,
		vessel_uid: String = "",
) -> Dictionary:
	return {
		"status": "underway",
		"route": contract.duplicate(true),
		"commodity_id": contract.get("commodity_id", "provisions"),
		"return_commodity_id": contract.get("return_commodity_id", contract.get("commodity_id", "provisions")),
		"leg_origin_port_id": contract.get("origin_port_id", ""),
		"leg_origin_berth_id": contract.get("origin_berth_id", ""),
		"leg_destination_port_id": contract.get("destination_port_id", ""),
		"leg_destination_berth_id": contract.get("destination_berth_id", ""),
		"current_port_id": contract.get("origin_port_id", ""),
		"current_berth_id": contract.get("origin_berth_id", ""),
		"route_progress_m": progress,
		"leg_distance_m": plan.total_distance_m(),
		"physical_contract_id": _contract_id(contract),
		"arriving_contract_id": "",
		"arriving_commodity_id": "",
		"arrival_pending_settlement": false,
		"cargo_ready": true,
		"cargo_manifest": _cargo_manifest(contract, vessel_uid),
	}


func _contract_id(contract: Dictionary) -> String:
	return "debug-contract:%s" % contract.get("id", "route")


func _cargo_manifest(contract: Dictionary, vessel_uid: String = "") -> Dictionary:
	if str(contract.get("handling_mode", "")) == "bulk":
		var commodity := str(contract.get("commodity_id", "iron_ore"))
		return {"kind": "bulk", "commodity_id": commodity, "holds": [{
			"hold_id": "", "commodity_id": commodity,
			"capacity_tonnes_t": 420.0, "filled_tonnes_t": 275.0,
		}]}
	var units: Array[Dictionary] = []
	var commodity := str(contract.get("commodity_id", "provisions"))
	var contract_id := _contract_id(contract)
	var contract_record := {
		"id": contract_id,
		"status": "loaded",
		"origin_port_id": contract.get("origin_port_id", ""),
		"destination_port_id": contract.get("destination_port_id", ""),
		"commodity_id": commodity,
		"handling_mode": "general",
		"quantity": 6,
		"quantity_unit": "units",
		"pay_marks": 3000,
		"vessel_uid": vessel_uid,
		"loaded_quantity": 6,
		"issued_quantity": 6,
		"delivered_quantity": 0,
	}
	contract_record["consignment"] = CargoConsignment.from_contract(contract_record).to_dict()
	for index in range(6):
		var unit := ContainerUnit.create(
			"debug-%s-%d" % [contract.get("id", "route"), index], commodity)
		unit.origin_port_id = str(contract.get("origin_port_id", ""))
		unit.destination_port_id = str(contract.get("destination_port_id", ""))
		unit.freight_contract_id = contract_id
		unit.consignment_id = str(
			(contract_record["consignment"] as Dictionary).get("consignment_id", ""))
		unit.delivery_value_marks = 500 + index * 75
		units.append(unit.to_dict())
	contract_record["quantity"] = units.size()
	return {"kind": "units", "contract": contract_record, "units": units}


func _contract_candidates(catalog: Node, observer: Vector2) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var ids: Array[String] = catalog.get_port_ids()
	for origin_id in ids:
		var origin := catalog.get_port_info(origin_id) as Dictionary
		for destination_id in ids:
			if destination_id == origin_id:
				continue
			var destination := catalog.get_port_info(destination_id) as Dictionary
			for raw_commodity in origin.get("commodity_exports", []) as Array:
				var commodity := str(raw_commodity)
				if commodity not in (destination.get("commodity_imports", []) as Array):
					continue
				var handling := CommodityCatalog.commodity_handling_mode(commodity)
				if handling not in ["general", "bulk"]:
					continue
				var family := CommodityCatalog.commodity_terminal_family(commodity)
				var origin_berth := BerthApproachLanes.best_target_id(origin_id, family, commodity)
				var destination_berth := BerthApproachLanes.best_target_id(destination_id, family, commodity)
				if origin_berth.is_empty() or destination_berth.is_empty():
					continue
				var op := origin.get("position", Vector3.ZERO) as Vector3
				var dp := destination.get("position", Vector3.ZERO) as Vector3
				var midpoint := Vector2(op.x + dp.x, op.z + dp.z) * 0.5
				out.append({"id": "debug:%s:%s:%s" % [origin_id, destination_id, commodity],
					"origin_port_id": origin_id, "origin_berth_id": origin_berth,
					"destination_port_id": destination_id, "destination_berth_id": destination_berth,
					"commodity_id": commodity, "return_commodity_id": _return_commodity(destination, origin, handling),
					"handling_mode": handling, "family": family,
					"score": observer.distance_to(midpoint)})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("score", INF)) < float(b.get("score", INF)))
	return out


func _select_mixed_contracts(candidates: Array[Dictionary], count: int) -> Array[Dictionary]:
	var general: Array[Dictionary] = []
	var bulk: Array[Dictionary] = []
	for row in candidates:
		(bulk if str(row.get("handling_mode", "")) == "bulk" else general).append(row)
	var out: Array[Dictionary] = []
	for index in range(count):
		var pool := bulk if index % 2 == 1 and not bulk.is_empty() else general
		if pool.is_empty():
			pool = bulk
		if pool.is_empty():
			break
		out.append(pool[index % pool.size()])
	return out


func _ensure_bulk_candidates(candidates: Array[Dictionary], catalog: Node, observer: Vector2) -> void:
	for row in candidates:
		if str(row.get("handling_mode", "")) == "bulk":
			return
	for commodity in ["iron_ore", "coal", "grain"]:
		var family := CommodityCatalog.commodity_terminal_family(commodity)
		var endpoints: Array[Dictionary] = []
		for port_id in catalog.get_port_ids():
			var berth_id := BerthApproachLanes.best_target_id(port_id, family, commodity)
			if berth_id.is_empty():
				continue
			var position := catalog.get_port_position(port_id) as Vector3
			endpoints.append({"port_id": port_id, "berth_id": berth_id, "position": position})
		if endpoints.size() < 2:
			continue
		for index in range(endpoints.size() - 1):
			var a := endpoints[index]
			var b := endpoints[index + 1]
			var ap := a.get("position", Vector3.ZERO) as Vector3
			var bp := b.get("position", Vector3.ZERO) as Vector3
			candidates.append({"id": "debug-bulk:%s:%s:%s" % [a.get("port_id"), b.get("port_id"), commodity],
				"origin_port_id": a.get("port_id", ""), "origin_berth_id": a.get("berth_id", ""),
				"destination_port_id": b.get("port_id", ""), "destination_berth_id": b.get("berth_id", ""),
				"commodity_id": commodity, "return_commodity_id": commodity,
				"handling_mode": "bulk", "family": family,
				"score": observer.distance_to(Vector2(ap.x + bp.x, ap.z + bp.z) * 0.5)})
		return


func _return_commodity(origin: Dictionary, destination: Dictionary, handling: String) -> String:
	for raw in origin.get("commodity_exports", []) as Array:
		var commodity := str(raw)
		if commodity in (destination.get("commodity_imports", []) as Array) \
				and CommodityCatalog.commodity_handling_mode(commodity) == handling:
			return commodity
	return "provisions" if handling == "general" else "iron_ore"


func _plan_contract(contract: Dictionary, layout: WorldLayout) -> MarineRoutePlan:
	_route_plan_requests += 1
	var key := "%s|%s|%s|%s|%s" % [
		str(layout.layout_checksum),
		str(contract.get("origin_port_id", "")),
		str(contract.get("origin_berth_id", "")),
		str(contract.get("destination_port_id", "")),
		str(contract.get("destination_berth_id", "")),
	]
	var cached := _route_plan_cache.get(key) as MarineRoutePlan
	if cached != null and cached.is_valid():
		_route_plan_cache_hits += 1
		return cached
	var catalog := get_node("/root/PortCatalog")
	var origin := catalog.get_port_position(str(contract.get("origin_port_id", ""))) as Vector3
	var destination := catalog.get_port_position(str(contract.get("destination_port_id", ""))) as Vector3
	var plan := MarineRoutePlanner.new(layout).plan_berth_to_berth(Vector2(origin.x, origin.z),
		Vector2(destination.x, destination.z), str(contract.get("origin_port_id", "")),
		str(contract.get("origin_berth_id", "")), str(contract.get("destination_port_id", "")),
		str(contract.get("destination_berth_id", "")))
	if plan != null and plan.is_valid():
		_route_plan_cache[key] = plan
	return plan


func _plan_assignment(row: Dictionary, layout: WorldLayout) -> MarineRoutePlan:
	return _plan_contract({"origin_port_id": row.get("leg_origin_port_id", ""),
		"origin_berth_id": row.get("leg_origin_berth_id", ""),
		"destination_port_id": row.get("leg_destination_port_id", ""),
		"destination_berth_id": row.get("leg_destination_berth_id", "")}, layout)


func _join_progress(plan: MarineRoutePlan, observer: Vector2, index: int) -> float:
	var lower := maxf(plan.departure_handoff_m + 40.0, plan.total_distance_m() * 0.08)
	var upper := minf(plan.arrival_handoff_m - 100.0, plan.total_distance_m() * 0.92)
	if upper <= lower:
		lower = plan.total_distance_m() * 0.15
		upper = plan.total_distance_m() * 0.82
	return clampf(plan.nearest_progress_m(observer) + (float(index) - 2.0) * 140.0, lower, upper)


func _prebuilt_record(prebuilt_id: String, uid: String, index: int) -> Dictionary:
	for entry in PrebuiltVesselCatalog.catalog_entries(false):
		if str(entry.get("prebuilt_id", "")) == prebuilt_id:
			return VesselSpawn.normalize_record({"uid": uid, "hull_id": entry.get("hull_id", "hull_28x10"),
				"name": "Traffic %02d · %s" % [index + 1, entry.get("prebuilt_name", "Freighter")],
				"shaft_power_kw": entry.get("shaft_power_kw", 1871.0),
				"registration_id": entry.get("registration_id", "cargo_vessel"),
				"brick_layout": (entry.get("prebuilt_layout", {}) as Dictionary).duplicate(true)})
	return {}


func _observer_xz() -> Vector2:
	var view := get_node_or_null("/root/LocalPlayerView")
	var ship := view.get_active_ship() as Node3D if view != null else null
	if ship != null:
		return Vector2(ship.global_position.x, ship.global_position.z)
	var camera := get_viewport().get_camera_3d()
	return Vector2(camera.global_position.x, camera.global_position.z) if camera != null else Vector2.ZERO


func _is_main_menu() -> bool:
	var scene := get_tree().current_scene
	return scene == null or String(scene.scene_file_path).ends_with("main_menu.tscn")
