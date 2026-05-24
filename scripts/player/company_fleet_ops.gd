class_name CompanyFleetOps
extends RefCounted

## Local-only fleet operations helpers for the company office UI.
## Stub earnings accrue by active hours until deterministic sim exists.

const STUB_CARGO_MARKS_PER_HOUR := 55
const STUB_FISHING_MARKS_PER_HOUR := 72

enum VesselUiStatus {
	IDLE,
	READY,
	ACTIVE,
	BLOCKED,
}


static func sorted_port_options(registry: Node = null) -> Array[Dictionary]:
	var reg := _registry(registry)
	var out: Array[Dictionary] = []
	if reg == null or not reg.has_method("get_port_ids"):
		return out
	var ids: Array = reg.call("get_port_ids")
	for raw_id in ids:
		var port_id := str(raw_id)
		if port_id.is_empty():
			continue
		var name := port_id
		if reg.has_method("get_port_display_name"):
			name = str(reg.call("get_port_display_name", port_id))
		out.append({"id": port_id, "label": name})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("label", "")) < str(b.get("label", ""))
	)
	return out


static func ui_status(record: Dictionary) -> VesselUiStatus:
	var av := AutonomousVesselRecord.from_owned_vessel(record)
	if av.active:
		return VesselUiStatus.ACTIVE
	var blockers := activation_blockers(record)
	if blockers.is_empty():
		return VesselUiStatus.READY
	if not av.is_crew_ready() or not av.is_wages_paid():
		return VesselUiStatus.IDLE
	return VesselUiStatus.BLOCKED


static func status_label(record: Dictionary) -> String:
	match ui_status(record):
		VesselUiStatus.ACTIVE:
			return "Active"
		VesselUiStatus.READY:
			return "Ready"
		VesselUiStatus.BLOCKED:
			return "Blocked"
		_:
			return "Idle"


static func activation_blockers(record: Dictionary) -> PackedStringArray:
	var av := AutonomousVesselRecord.from_owned_vessel(record)
	var out: PackedStringArray = []
	if not av.is_crew_ready():
		out.append("Assign full crew (%d/%d)" % [av.crew_assigned_count(), av.crew_slot_count()])
	if not av.is_wages_paid():
		out.append("Pay crew wages")
	if av.home_port_id.is_empty():
		out.append("Open fleet panel at a company office")
	elif not av.role_is_fishing() and not av.has_visit_port():
		out.append("Set destination port")
	elif av.has_visit_port() and av.visit_port_id == av.home_port_id:
		out.append("Destination must differ from home")
	return out


static func can_activate(record: Dictionary) -> bool:
	return activation_blockers(record).is_empty()


static func route_home_label(record: Dictionary, registry: Node = null) -> String:
	var av := AutonomousVesselRecord.from_owned_vessel(record)
	if av.home_port_id.is_empty():
		return "—"
	return _port_name(registry, av.home_port_id)


static func route_visit_label(record: Dictionary, registry: Node = null) -> String:
	var av := AutonomousVesselRecord.from_owned_vessel(record)
	if not av.has_visit_port():
		return "—"
	return _port_name(registry, av.visit_port_id)


static func route_summary(record: Dictionary, registry: Node = null) -> String:
	var av := AutonomousVesselRecord.from_owned_vessel(record)
	if av.home_port_id.is_empty():
		return "No route assigned"
	var home := _port_name(registry, av.home_port_id)
	if not av.has_visit_port():
		if av.role_is_fishing():
			return "%s → fish grounds → %s" % [home, home]
		return "Set destination port"
	var visit := _port_name(registry, av.visit_port_id)
	var reg := _registry(registry)
	if reg != null and av.has_visit_port():
		av.hydrate_ports(reg)
		if av.home_pos != Vector3(INF, INF, INF) and av.visit_pos != Vector3(INF, INF, INF):
			var nm := ContractPricing.route_distance_nm(av.home_pos, av.visit_pos)
			if av.role_is_fishing():
				return "%s ⇄ %s  •  %.0f nm  •  fish & sell loop" % [home, visit, nm]
			return "%s → %s → %s  •  %.0f nm cargo loop" % [home, visit, home, nm]
	if av.role_is_fishing():
		return "%s ⇄ %s  •  fishing loop" % [home, visit]
	return "%s → %s → %s" % [home, visit, home]


static func visit_port_optional(record: Dictionary) -> bool:
	return AutonomousVesselRecord.from_owned_vessel(record).role_is_fishing()


static func apply_route(
	record: Dictionary,
	home_port_id: String,
	visit_port_id: String,
) -> Dictionary:
	var out := record.duplicate(true)
	out["home_port_id"] = home_port_id
	out["visit_port_id"] = visit_port_id
	var av := AutonomousVesselRecord.from_owned_vessel(out)
	if av.active:
		av.set_active(true, int(Time.get_unix_time_from_system()))
		out = av.merge_into_owned_vessel(out)
	return out


static func set_autonomous_active(record: Dictionary, enabled: bool) -> Dictionary:
	var out := record.duplicate(true)
	var av := AutonomousVesselRecord.from_owned_vessel(out)
	if enabled:
		if not can_activate(out):
			return out
		av.set_active(true)
	else:
		av.set_active(false)
	return av.merge_into_owned_vessel(out)


static func roll_pending(record: Dictionary, now_unix: int = -1) -> Dictionary:
	var out := record.duplicate(true)
	var av := AutonomousVesselRecord.from_owned_vessel(out)
	if not av.active or av.active_at <= 0:
		return out
	var now := now_unix if now_unix >= 0 else int(Time.get_unix_time_from_system())
	var anchor := int(out.get("last_collected_at", 0))
	if anchor < av.active_at:
		anchor = av.active_at
	var last_roll := int(out.get("last_accrual_at", anchor))
	if last_roll < anchor:
		last_roll = anchor
	var hours := maxf(0.0, float(now - last_roll) / 3600.0)
	if hours <= 0.0:
		return out
	var rate := _stub_hourly_rate(av)
	out["pending_earnings"] = int(out.get("pending_earnings", 0)) + int(hours * rate)
	out["last_accrual_at"] = now
	return out


static func pending_earnings(record: Dictionary) -> int:
	return int(record.get("pending_earnings", 0))


static func collect_earnings(record: Dictionary) -> Dictionary:
	var out := roll_pending(record)
	var amount := pending_earnings(out)
	if amount <= 0:
		return out
	out["pending_earnings"] = 0
	out["last_collected_at"] = int(Time.get_unix_time_from_system())
	out["last_accrual_at"] = int(out["last_collected_at"])
	return out


static func fleet_roll_pending(vessels: Array) -> Array:
	var out: Array = []
	for raw in vessels:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		out.append(roll_pending(raw as Dictionary))
	return out


static func fleet_total_pending(vessels: Array) -> int:
	var total := 0
	for raw in vessels:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		total += pending_earnings(raw as Dictionary)
	return total


static func checklist_lines(record: Dictionary) -> PackedStringArray:
	var av := AutonomousVesselRecord.from_owned_vessel(record)
	var lines: PackedStringArray = []
	lines.append("%s Crew %d/%d" % [
		"OK" if av.is_crew_ready() else "—",
		av.crew_assigned_count(),
		av.crew_slot_count(),
	])
	lines.append("%s Wages paid" % ("OK" if av.is_wages_paid() else "—"))
	var route_ok := av.home_port_id.is_empty() == false
	if av.role_is_fishing():
		route_ok = route_ok
	else:
		route_ok = route_ok and av.has_visit_port() and av.visit_port_id != av.home_port_id
	lines.append("%s Route set" % ("OK" if route_ok else "—"))
	return lines


static func _stub_hourly_rate(av: AutonomousVesselRecord) -> float:
	if av.role_is_fishing() and av.active:
		return 0.0
	var rate := float(STUB_CARGO_MARKS_PER_HOUR)
	if av.role_is_fishing():
		rate = float(STUB_FISHING_MARKS_PER_HOUR)
	var visit_mul := 1.0 if av.has_visit_port() else 0.65
	return rate * visit_mul


static func _port_name(registry: Node, port_id: String) -> String:
	var reg := _registry(registry)
	if reg != null and reg.has_method("get_port_display_name"):
		return str(reg.call("get_port_display_name", port_id))
	return port_id


static func _registry(registry: Node) -> Node:
	if registry != null:
		return registry
	return Engine.get_main_loop().root.get_node_or_null("/root/ContractRegistry")
