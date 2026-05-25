class_name AutonomousVesselRecord
extends RefCounted

## Canonical lean snapshot for player-owned autonomous / NPC-simulated vessels.
##
## **Persist & sync by port id** — never treat XZ as authoritative in saves.
## Call `hydrate_ports()` after ContractRegistry knows the world so `home_pos` /
## `visit_pos` are filled for proximity checks and route preview.
##
## Owned-vessel ledger fields (PlayerData.owned_vessels) map 1:1 onto this record.
## MP wire format uses `to_sync_dict()` / `from_sync_dict()` — still lean.

const SIM_VERSION := 1
const NO_VISIT := ""

var id: String = ""
var owner_id: String = ""
var hull_id: String = ""
var display_name: String = ""
var template_path: String = ""

var active: bool = false
var active_at: int = 0

var home_port_id: String = ""
var visit_port_id: String = NO_VISIT

var crew: Array = []
var expense_per_day: int = 0

var pending_earnings: int = 0
var last_collected_at: int = 0
var last_accrual_at: int = 0

var sim_version: int = SIM_VERSION

## Hydrated from ContractRegistry — not written back to saves as source of truth.
var home_pos: Vector3 = Vector3.ZERO
var visit_pos: Vector3 = Vector3.ZERO
var _ports_hydrated: bool = false


static func from_owned_vessel(record: Dictionary, owner_id: String = "") -> AutonomousVesselRecord:
	var out := AutonomousVesselRecord.new()
	out.id = _vessel_id(record)
	out.owner_id = owner_id if not owner_id.is_empty() else str(record.get("owner_id", ""))
	out.hull_id = str(record.get("hull_id", ""))
	out.display_name = str(record.get("display", record.get("display_name", "Vessel")))
	out.template_path = str(record.get("template_path", ""))

	out.active = bool(record.get("autonomous_active", record.get("active", false)))
	out.active_at = int(record.get("autonomous_active_at", record.get("active_at", 0)))

	out.home_port_id = str(record.get("home_port_id", ""))
	var visit_raw: Variant = record.get("visit_port_id", record.get("destination_port_id", NO_VISIT))
	out.visit_port_id = "" if visit_raw == null else str(visit_raw)

	out.crew = _copy_crew(record.get("crew", []))
	out.expense_per_day = int(record.get("expense_per_day", 0))
	if out.expense_per_day <= 0 and not out.crew.is_empty():
		out.expense_per_day = VesselCrew.total_daily_wages(out.crew)

	out.sim_version = int(record.get("sim_version", SIM_VERSION))
	out.pending_earnings = int(record.get("pending_earnings", 0))
	out.last_collected_at = int(record.get("last_collected_at", 0))
	out.last_accrual_at = int(record.get("last_accrual_at", 0))
	return out


static func from_sync_dict(row: Dictionary) -> AutonomousVesselRecord:
	var out := from_owned_vessel(row, str(row.get("owner_id", row.get("captain_id", ""))))
	out.id = str(row.get("id", row.get("vessel_id", out.id)))

	if row.has("home_x") and row.has("home_z"):
		out.home_pos = Vector3(float(row["home_x"]), 0.0, float(row["home_z"]))
	if row.has("dest_x") and row.has("dest_z"):
		out.visit_pos = Vector3(float(row["dest_x"]), 0.0, float(row["dest_z"]))
		out._ports_hydrated = true
	return out


func to_owned_vessel_patch() -> Dictionary:
	recompute_expense()
	return {
		"autonomous_active": active,
		"autonomous_active_at": active_at if active else 0,
		"home_port_id": home_port_id,
		"visit_port_id": visit_port_id,
		"crew": _copy_crew(crew),
		"expense_per_day": expense_per_day,
		"sim_version": sim_version,
		"pending_earnings": pending_earnings,
		"last_collected_at": last_collected_at,
		"last_accrual_at": last_accrual_at,
	}


func merge_into_owned_vessel(record: Dictionary) -> Dictionary:
	var merged := record.duplicate(true)
	for key in to_owned_vessel_patch():
		merged[key] = to_owned_vessel_patch()[key]
	return merged


func to_sync_dict(include_positions: bool = true) -> Dictionary:
	var row := {
		"id": id,
		"owner_id": owner_id,
		"hull_id": hull_id,
		"display_name": display_name,
		"template_path": template_path,
		"active": active,
		"active_at": active_at,
		"home_port_id": home_port_id,
		"visit_port_id": visit_port_id if not visit_port_id.is_empty() else null,
		"crew": _copy_crew(crew),
		"expense_per_day": expense_per_day,
		"sim_version": sim_version,
		"pending_earnings": pending_earnings,
		"last_collected_at": last_collected_at,
		"last_accrual_at": last_accrual_at,
		"vessel_role": vessel_role(),
	}
	if include_positions and _ports_hydrated:
		row["home_x"] = home_pos.x
		row["home_z"] = home_pos.z
		if has_visit_port():
			row["dest_x"] = visit_pos.x
			row["dest_z"] = visit_pos.z
	return row


func hydrate_ports(registry: Node = null) -> void:
	var reg := registry if registry != null else _registry()
	if reg == null:
		return
	home_pos = _port_position(reg, home_port_id)
	if has_visit_port():
		visit_pos = _port_position(reg, visit_port_id)
	else:
		visit_pos = Vector3(INF, INF, INF)
	_ports_hydrated = home_port_id.is_empty() or home_pos != Vector3(INF, INF, INF)


func vessel_role() -> int:
	var entry := HullRegistry.get_by_id(hull_id)
	if entry.is_empty():
		return VesselRole.Type.CARGO
	return int(entry.get("role", VesselRole.Type.CARGO))


func role_is_fishing() -> bool:
	return vessel_role() == VesselRole.Type.FISHING


func has_visit_port() -> bool:
	return not visit_port_id.is_empty()


func crew_slot_count() -> int:
	return VesselCrew.slot_count_for_hull(hull_id)


func normalized_crew() -> Array:
	return VesselCrew.normalize_slots({"crew": crew}, crew_slot_count())


func crew_assigned_count() -> int:
	return VesselCrew.assigned_count(normalized_crew())


func is_crew_ready() -> bool:
	var slots := normalized_crew()
	return VesselCrew.all_slots_filled(slots, crew_slot_count())


func is_wages_paid() -> bool:
	return VesselCrew.all_crew_paid(normalized_crew())


func can_activate() -> bool:
	return is_crew_ready() and is_wages_paid() and not home_port_id.is_empty()


func recompute_expense() -> void:
	expense_per_day = VesselCrew.total_daily_wages(normalized_crew())


func set_active(enabled: bool, at_unix: int = -1) -> void:
	active = enabled
	if enabled:
		active_at = at_unix if at_unix >= 0 else int(Time.get_unix_time_from_system())
	else:
		active_at = 0


func set_route(home_id: String, visit_id: String = NO_VISIT) -> void:
	home_port_id = home_id
	visit_port_id = visit_id if not visit_id.is_empty() else NO_VISIT
	_ports_hydrated = false


## True when the record should be simulated / rendered near `world_xz`.
## Checks port anchors, route midpoint, and deterministic sim position.
func is_relevant_near(world_xz: Vector2, radius_m: float) -> bool:
	if not active:
		return false
	var r2 := radius_m * radius_m
	if not _ports_hydrated:
		return _is_sim_near(world_xz, r2)
	if home_port_id.is_empty():
		return false
	if _xz(home_pos).distance_squared_to(world_xz) <= r2:
		return true
	if has_visit_port() and _xz(visit_pos).distance_squared_to(world_xz) <= r2:
		return true
	if has_visit_port():
		var mid := (_xz(home_pos) + _xz(visit_pos)) * 0.5
		if mid.distance_squared_to(world_xz) <= r2:
			return true
	return _is_sim_near(world_xz, r2)


func _is_sim_near(world_xz: Vector2, r2: float) -> bool:
	if active_at <= 0:
		return false
	var sample := AutonomousVesselSim.sample(to_sim_record())
	var pos: Vector3 = sample.get("position", Vector3.ZERO)
	return _xz(pos).distance_squared_to(world_xz) <= r2


func to_sim_record() -> Dictionary:
	var merged := merge_into_owned_vessel({
		"uid": id if not id.is_empty() else owner_id,
		"hull_id": hull_id,
		"template_path": template_path,
	})
	return AutonomousVesselLoader.normalize_spawn_record(merged)


static func filter_nearby(
	records: Array,
	world_xz: Vector2,
	radius_m: float,
	registry: Node = null,
) -> Array:
	var out: Array = []
	for raw in records:
		var rec: AutonomousVesselRecord = null
		if raw is AutonomousVesselRecord:
			rec = raw
		elif typeof(raw) == TYPE_DICTIONARY:
			rec = from_sync_dict(raw as Dictionary)
		else:
			continue
		rec.hydrate_ports(registry)
		if rec.is_relevant_near(world_xz, radius_m):
			out.append(rec)
	return out


static func collect_active_from_session(session: Node, owner_id: String = "") -> Array:
	if session == null or session.get("data") == null:
		return []
	var data: PlayerData = session.data
	var captain := owner_id if not owner_id.is_empty() else str(data.captain_id)
	var out: Array = []
	for entry_raw in data.owned_vessels:
		if typeof(entry_raw) != TYPE_DICTIONARY:
			continue
		var entry := entry_raw as Dictionary
		if not bool(entry.get("autonomous_active", false)):
			continue
		if not captain.is_empty():
			var entry_owner := str(entry.get("owner_id", captain))
			if entry_owner != captain:
				continue
		out.append(from_owned_vessel(entry, captain))
	return out


static func _vessel_id(record: Dictionary) -> String:
	var server_id := str(record.get("server_vessel_id", ""))
	if not server_id.is_empty():
		return server_id
	return str(record.get("uid", ""))


static func _copy_crew(raw: Variant) -> Array:
	if typeof(raw) != TYPE_ARRAY:
		return []
	var out: Array = []
	for entry in raw as Array:
		if typeof(entry) == TYPE_DICTIONARY:
			out.append((entry as Dictionary).duplicate())
		else:
			out.append({})
	return out


static func _registry() -> Node:
	return Engine.get_main_loop().root.get_node_or_null("/root/ContractRegistry")


static func _port_position(registry: Node, port_id: String) -> Vector3:
	if port_id.is_empty() or registry == null:
		return Vector3(INF, INF, INF)
	if registry.has_method("get_port_position"):
		return registry.call("get_port_position", port_id) as Vector3
	return Vector3(INF, INF, INF)


static func _xz(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)
