class_name HarbourController
extends Node

## Per-port plug board: berths, equipment, yards register here; ships/equipment plug through APIs.

signal ship_plugged(berth_id: String, ship: BoatBody)
signal ship_unplugged(berth_id: String, ship: BoatBody)
signal equipment_plugged(equip_id: String, ship: BoatBody, mode: String)
signal equipment_unplugged(equip_id: String)
signal traffic_changed

var _port_id := ""
var _berths: Dictionary = {} ## berth_id -> QuayBerthSlot
var _equipment: Dictionary = {} ## equip_id -> QuayEquipmentJob
var _yards: Dictionary = {} ## yard_key -> { "berth_id", "node" }
var _ship_at_berth: Dictionary = {} ## berth_id -> BoatBody
var _berth_of_ship: Dictionary = {} ## ship instance_id -> berth_id
var _berth_reservations: Dictionary = {} ## berth_id -> authority lease
var _lane_lock: Dictionary = {} ## one harbour manoeuvre at a time in v1
var _authority_bridge: HarbourAuthorityBridge = null

const DEFAULT_RESERVATION_LEASE_S := 180.0


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		HarbourRegistry.unregister_controller(self)


func setup(port_id: String) -> void:
	_port_id = port_id.strip_edges()
	name = "HarbourController"


func port_id() -> String:
	return _port_id


func activate() -> void:
	HarbourRegistry.register(self)
	if _authority_bridge == null or not is_instance_valid(_authority_bridge):
		_authority_bridge = HarbourAuthorityBridge.new()
		add_child(_authority_bridge)
		_authority_bridge.setup(self)
	_authority_bridge.activate()


func deactivate() -> void:
	if _authority_bridge != null and is_instance_valid(_authority_bridge):
		_authority_bridge.deactivate()
	HarbourRegistry.unregister_controller(self)


func unregister_all() -> void:
	for equip_id in _equipment.keys():
		if _authority_bridge != null and is_instance_valid(_authority_bridge):
			_authority_bridge.abort_equipment(str(equip_id), "harbour_unloaded")
		else:
			unplug_equipment(str(equip_id))
	_berths.clear()
	_equipment.clear()
	_yards.clear()
	_ship_at_berth.clear()
	_berth_of_ship.clear()
	_berth_reservations.clear()
	_lane_lock.clear()


## --- Registration -----------------------------------------------------------

func register_berth(slot: QuayBerthSlot) -> void:
	if slot == null or slot.berth_id.is_empty():
		return
	_berths[slot.berth_id] = slot
	call_deferred("_bake_registered_berth_lane", slot)


func _bake_registered_berth_lane(slot: QuayBerthSlot) -> void:
	if slot != null and is_instance_valid(slot) and slot.is_inside_tree():
		BerthApproachLanes.bake_live_berth(_port_id, slot)


func unregister_equipment(equip_id: String) -> void:
	var eid := equip_id.strip_edges()
	if eid.is_empty():
		return
	unplug_equipment(eid)
	_equipment.erase(eid)


func register_equipment(equip: QuayEquipmentJob, berth_id: String = "") -> void:
	if equip == null:
		return
	var bid := berth_id.strip_edges()
	if bid.is_empty():
		bid = equip.berth_id()
	if bid.is_empty() or equip.equipment_id().is_empty():
		push_warning("HarbourController: equipment missing ids")
		return
	if not _berths.has(bid):
		push_warning("HarbourController: register_equipment unknown berth %s" % bid)
	_equipment[equip.equipment_id()] = equip
	if _authority_bridge != null and is_instance_valid(_authority_bridge):
		_authority_bridge.topology_changed()
	var freight := _freight_service()
	if freight != null and freight.has_method("stage_berth"):
		freight.call_deferred("stage_berth", _port_id, bid)


func register_yard(yard: Node, berth_id: String) -> void:
	if yard == null or not is_instance_valid(yard):
		return
	var bid := berth_id.strip_edges()
	if bid.is_empty():
		return
	var key := "%s/%s" % [bid, yard.get_instance_id()]
	_yards[key] = {"berth_id": bid, "node": yard}
	var slot := berth(bid)
	if slot != null:
		slot.add_yard(yard)
	var freight := _freight_service()
	if freight != null and freight.has_method("stage_berth"):
		freight.call_deferred("stage_berth", _port_id, bid)


## --- Boat ↔ quay ------------------------------------------------------------

func plug_ship(berth_id: String, ship: BoatBody) -> bool:
	if ship == null or not is_instance_valid(ship):
		return false
	var bid := berth_id.strip_edges()
	if not _berths.has(bid):
		return false
	_cleanup_traffic_leases()
	var reservation := _berth_reservations.get(bid, {}) as Dictionary
	var arriving_id := ship_id_of(ship)
	if not reservation.is_empty() and str(reservation.get("vessel_id", "")) != arriving_id:
		return false
	var existing: BoatBody = _ship_at_berth.get(bid) as BoatBody
	if existing != null and is_instance_valid(existing) and existing != ship:
		return false
	var prev_berth := ship_berth_id(ship)
	if not prev_berth.is_empty() and prev_berth != bid:
		unplug_ship(ship)
	_ship_at_berth[bid] = ship
	_berth_of_ship[ship.get_instance_id()] = bid
	ship.set_meta("harbour_berth_id", bid)
	ship.set_meta("harbour_port_id", _port_id)
	ship_plugged.emit(bid, ship)
	if not reservation.is_empty():
		_berth_reservations.erase(bid)
	traffic_changed.emit()
	var freight := _freight_service()
	if freight != null and freight.has_method("stage_berth"):
		freight.call_deferred("stage_berth", _port_id, bid)
	return true


func unplug_ship(ship: BoatBody) -> void:
	if ship == null:
		return
	var bid := ship_berth_id(ship)
	if bid.is_empty():
		return
	var freight := _freight_service()
	if freight != null and freight.has_method("unstage_berth"):
		freight.call("unstage_berth", _port_id, bid, ship)
	for equip_id in equipment_ids_on_berth(bid):
		var equip := get_equipment(equip_id)
		if equip != null and equip.served_ship() == ship:
			if _authority_bridge != null and is_instance_valid(_authority_bridge):
				_authority_bridge.abort_equipment(equip_id, "ship_unmoored")
			else:
				unplug_equipment(equip_id)
	_ship_at_berth.erase(bid)
	_berth_of_ship.erase(ship.get_instance_id())
	if is_instance_valid(ship):
		ship.remove_meta("harbour_berth_id")
		ship.remove_meta("harbour_port_id")
	ship_unplugged.emit(bid, ship)


func unplug_berth(berth_id: String) -> void:
	var ship := moored_ship(berth_id)
	if ship != null:
		unplug_ship(ship)


## --- Crane ↔ boat -----------------------------------------------------------

func plug_equipment(
		equip_id: String,
		ship: BoatBody,
		mode: String,
		commodity_id: String = "",
		context: Dictionary = {},
) -> bool:
	var equip := get_equipment(equip_id)
	if equip == null or ship == null:
		return false
	var bid := equip.berth_id()
	var moored := moored_ship(bid)
	if moored != ship:
		return false
	if equip.is_job_active() and equip.served_ship() != ship:
		return false
	if not equip.can_serve(ship, mode):
		return false
	if not equip.start_job(ship, mode, commodity_id, context):
		return false
	equipment_plugged.emit(equip.equipment_id(), ship, mode.strip_edges().to_lower())
	return true


func unplug_equipment(equip_id: String) -> void:
	var equip := get_equipment(equip_id)
	if equip == null:
		return
	if equip.is_job_active():
		equip.stop_job()
	equipment_unplugged.emit(equip_id.strip_edges())


func request_load(berth_id: String, commodity_id: String = "") -> bool:
	return _request_job(berth_id, QuayEquipmentJob.MODE_LOAD, commodity_id)


func request_unload(berth_id: String, commodity_id: String = "") -> bool:
	return _request_job(berth_id, QuayEquipmentJob.MODE_UNLOAD, commodity_id)


func stop_equipment(equip_id: String) -> void:
	if _authority_bridge != null and _authority_bridge.request_stop(equip_id):
		return
	unplug_equipment(equip_id)


func stop_berth_equipment(berth_id: String) -> void:
	for equip_id in equipment_ids_on_berth(berth_id):
		stop_equipment(equip_id)


func _request_job(berth_id: String, mode: String, commodity_id: String) -> bool:
	if _authority_bridge != null and is_instance_valid(_authority_bridge):
		return _authority_bridge.request_job(berth_id, mode, commodity_id)
	var ship := moored_ship(berth_id)
	if ship == null:
		return false
	var equip := best_equipment_for(berth_id, ship, mode)
	if equip == null:
		return false
	return plug_equipment(equip.equipment_id(), ship, mode, commodity_id)


func _freight_service() -> Node:
	## This controller can outlive its harbour node briefly while a vessel is
	## leaving the scene tree. Resolve autoloads from the active SceneTree root
	## instead of using an absolute NodePath on a detached controller.
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("FreightService")


## --- Queries ----------------------------------------------------------------

func berths() -> Array:
	var out: Array = []
	for bid in _berths.keys():
		var slot: QuayBerthSlot = _berths[bid]
		if slot != null and is_instance_valid(slot):
			out.append(slot)
	return out


func berth(berth_id: String) -> QuayBerthSlot:
	return _berths.get(berth_id.strip_edges()) as QuayBerthSlot


func berth_for_bollard(post: Node) -> QuayBerthSlot:
	if post == null:
		return null
	var meta_id := str(post.get_meta("berth_id", ""))
	if not meta_id.is_empty():
		var slot := berth(meta_id)
		if slot != null:
			return slot
	for slot in berths():
		if (slot as QuayBerthSlot).contains_bollard(post):
			return slot as QuayBerthSlot
	return null


func ships() -> Array:
	var out: Array = []
	for bid in _ship_at_berth.keys():
		var ship: BoatBody = _ship_at_berth[bid]
		if ship != null and is_instance_valid(ship):
			out.append(ship)
	return out


func moored_ship(berth_id: String) -> BoatBody:
	var ship: BoatBody = _ship_at_berth.get(berth_id.strip_edges()) as BoatBody
	if ship != null and is_instance_valid(ship):
		return ship
	_ship_at_berth.erase(berth_id.strip_edges())
	return null


func ship_berth(ship: BoatBody) -> QuayBerthSlot:
	return berth(ship_berth_id(ship))


func ship_berth_id(ship: BoatBody) -> String:
	if ship == null or not is_instance_valid(ship):
		return ""
	var bid := str(_berth_of_ship.get(ship.get_instance_id(), ""))
	if bid.is_empty():
		bid = str(ship.get_meta("harbour_berth_id", ""))
	return bid


func occupied_berths() -> Array:
	var out: Array = []
	for slot in berths():
		var s := slot as QuayBerthSlot
		if moored_ship(s.berth_id) != null:
			out.append(s)
	return out


func free_berths(family: String = "") -> Array:
	_cleanup_traffic_leases()
	var out: Array = []
	for slot in berths():
		var s := slot as QuayBerthSlot
		if moored_ship(s.berth_id) != null:
			continue
		if _berth_reservations.has(s.berth_id):
			continue
		if not s.matches_family(family):
			continue
		out.append(s)
	return out


## Server-authority seam. A reservation is separate from occupancy: it protects
## an arrival before the vessel reaches the quay and expires if its owner dies.
func request_berth_reservation(
	vessel_id: String,
	loa_m: float,
	family: String = "",
	preferred_berth_id: String = "",
	lease_s: float = DEFAULT_RESERVATION_LEASE_S,
) -> String:
	var owner := vessel_id.strip_edges()
	if owner.is_empty():
		return ""
	_cleanup_traffic_leases()
	for berth_id in _berth_reservations:
		var existing := _berth_reservations[berth_id] as Dictionary
		if str(existing.get("vessel_id", "")) == owner:
			_renew_reservation(str(berth_id), lease_s)
			return str(berth_id)
	var candidates := free_berths_for_loa(loa_m, family)
	if not preferred_berth_id.is_empty():
		candidates.sort_custom(func(a: QuayBerthSlot, b: QuayBerthSlot) -> bool:
			return a.berth_id == preferred_berth_id and b.berth_id != preferred_berth_id
		)
	if candidates.is_empty():
		return ""
	var slot := candidates[0] as QuayBerthSlot
	_berth_reservations[slot.berth_id] = {
		"berth_id": slot.berth_id,
		"vessel_id": owner,
		"expires_msec": Time.get_ticks_msec() + int(maxf(lease_s, 5.0) * 1000.0),
	}
	traffic_changed.emit()
	return slot.berth_id


func release_berth_reservation(berth_id: String, vessel_id: String) -> bool:
	var bid := berth_id.strip_edges()
	var lease := _berth_reservations.get(bid, {}) as Dictionary
	if lease.is_empty() or str(lease.get("vessel_id", "")) != vessel_id.strip_edges():
		return false
	_berth_reservations.erase(bid)
	traffic_changed.emit()
	return true


func reservation_for_berth(berth_id: String) -> Dictionary:
	_cleanup_traffic_leases()
	return (_berth_reservations.get(berth_id.strip_edges(), {}) as Dictionary).duplicate(true)


func request_lane_lock(berth_id: String, vessel_id: String, phase: String) -> bool:
	_cleanup_traffic_leases()
	var owner := vessel_id.strip_edges()
	if owner.is_empty() or berth(berth_id) == null:
		return false
	if not _lane_lock.is_empty() and str(_lane_lock.get("vessel_id", "")) != owner:
		return false
	_lane_lock = {
		"berth_id": berth_id.strip_edges(),
		"vessel_id": owner,
		"phase": phase.strip_edges(),
		"expires_msec": Time.get_ticks_msec() + 60000,
	}
	traffic_changed.emit()
	return true


func release_lane_lock(vessel_id: String) -> bool:
	if _lane_lock.is_empty() or str(_lane_lock.get("vessel_id", "")) != vessel_id.strip_edges():
		return false
	_lane_lock.clear()
	traffic_changed.emit()
	return true


func traffic_snapshot() -> Dictionary:
	_cleanup_traffic_leases()
	var reservations: Array[Dictionary] = []
	for berth_id in _berth_reservations:
		reservations.append((_berth_reservations[berth_id] as Dictionary).duplicate(true))
	return {
		"port_id": _port_id,
		"reservations": reservations,
		"lane_lock": _lane_lock.duplicate(true),
	}


func _renew_reservation(berth_id: String, lease_s: float) -> void:
	var lease := _berth_reservations.get(berth_id, {}) as Dictionary
	if lease.is_empty():
		return
	lease["expires_msec"] = Time.get_ticks_msec() + int(maxf(lease_s, 5.0) * 1000.0)
	_berth_reservations[berth_id] = lease


func _cleanup_traffic_leases() -> void:
	var now := Time.get_ticks_msec()
	var changed := false
	for berth_id in _berth_reservations.keys():
		var lease := _berth_reservations[berth_id] as Dictionary
		if int(lease.get("expires_msec", 0)) > now:
			continue
		_berth_reservations.erase(berth_id)
		changed = true
	if not _lane_lock.is_empty() and int(_lane_lock.get("expires_msec", 0)) <= now:
		_lane_lock.clear()
		changed = true
	if changed:
		traffic_changed.emit()


func free_berths_for_loa(loa_world_m: float, family: String = "") -> Array:
	var out: Array = []
	for slot in free_berths(family):
		var s := slot as QuayBerthSlot
		if s != null and s.accepts_loa_m(loa_world_m):
			out.append(s)
	return out


func all_equipment() -> Array:
	var out: Array = []
	for eid in _equipment.keys():
		var equip: QuayEquipmentJob = _equipment[eid]
		if equip != null and is_instance_valid(equip):
			out.append(equip)
	return out


func get_equipment(equip_id: String) -> QuayEquipmentJob:
	return _equipment.get(equip_id.strip_edges()) as QuayEquipmentJob


func primary_equipment(berth_id: String) -> QuayEquipmentJob:
	var ids := equipment_ids_on_berth(berth_id)
	if ids.is_empty():
		return null
	return get_equipment(ids[0])


## Prefer the tool closest to the ship that can actually serve the mode.
## Returns null when no tool on the berth can reach / serve — never a blind fallback.
func best_equipment_for(berth_id: String, ship: BoatBody, mode: String) -> QuayEquipmentJob:
	var bid := berth_id.strip_edges()
	if ship == null or not is_instance_valid(ship):
		return primary_equipment(bid)
	var best: QuayEquipmentJob = null
	var best_d2 := INF
	var ship_pos := ship.global_position
	for equip_id in equipment_ids_on_berth(bid):
		var equip := get_equipment(equip_id)
		if equip == null or not equip.can_serve(ship, mode):
			continue
		var origin := _equipment_world_origin(equip)
		var d2 := origin.distance_squared_to(ship_pos)
		if d2 < best_d2:
			best_d2 = d2
			best = equip
	return best


func _equipment_world_origin(equip: QuayEquipmentJob) -> Vector3:
	if equip == null:
		return Vector3.ZERO
	## Jobs extend Node (not Node3D); world pose comes from the crane/tool parent.
	var n: Node = equip.get_parent()
	while n != null:
		if n is Node3D and (n as Node3D).is_inside_tree():
			return (n as Node3D).global_position
		n = n.get_parent()
	return Vector3.ZERO


func equipment_ids_on_berth(berth_id: String) -> PackedStringArray:
	var bid := berth_id.strip_edges()
	var out := PackedStringArray()
	for equip in all_equipment():
		var e := equip as QuayEquipmentJob
		if e.berth_id() == bid:
			out.append(e.equipment_id())
	out.sort()
	return out


func equipment_serving(ship: BoatBody) -> Array:
	var out: Array = []
	if ship == null:
		return out
	for equip in all_equipment():
		var e := equip as QuayEquipmentJob
		if e.served_ship() == ship:
			out.append(e)
	return out


func active_jobs() -> Array:
	var out: Array = []
	for equip in all_equipment():
		var e := equip as QuayEquipmentJob
		if e.is_job_active():
			out.append({
				"equip_id": e.equipment_id(),
				"ship_id": ship_id_of(e.served_ship()),
				"mode": e.job_mode(),
				"commodity_id": e.commodity_id(),
			})
	return out


func yards_on_berth(berth_id: String) -> Array:
	var bid := berth_id.strip_edges()
	var out: Array = []
	for key in _yards.keys():
		var entry: Dictionary = _yards[key]
		if str(entry.get("berth_id", "")) != bid:
			continue
		var node: Node = entry.get("node") as Node
		if node != null and is_instance_valid(node):
			out.append(node)
	return out


func serviceable_yards_on_berth(berth_id: String, ship: BoatBody = null) -> Array:
	var ranked: Array[Dictionary] = []
	for yard in yards_on_berth(berth_id):
		var paired_id := str((yard as Node).get_meta("equipment_id", ""))
		var candidate_ids := PackedStringArray([paired_id]) if not paired_id.is_empty() \
			else equipment_ids_on_berth(berth_id)
		for equip_id in candidate_ids:
			var equip := get_equipment(equip_id)
			if equip == null or not equip.can_reach_yard(yard as Node):
				continue
			if ship != null and (
				not equip.has_method("can_reach_ship")
				or not bool(equip.call("can_reach_ship", ship))
			):
				continue
			var score := 0.0
			if ship != null:
				score = _equipment_world_origin(equip).distance_squared_to(ship.global_position)
			ranked.append({"yard": yard, "score": score})
			break
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("score", INF)) < float(b.get("score", INF))
	)
	var out: Array = []
	for row in ranked:
		out.append((row as Dictionary).get("yard"))
	return out


func snapshot() -> Dictionary:
	var berth_rows: Array = []
	for slot in berths():
		var s := slot as QuayBerthSlot
		var ship := moored_ship(s.berth_id)
		var reservation := reservation_for_berth(s.berth_id)
		## Plot-local XZ for the harbour board (nudge by water face so twin sides separate).
		var host := get_parent() as Node3D
		var face_nudge := s.water_dir_local * maxf(s.width_m * 0.35, 8.0)
		var world_pos := s.to_global(face_nudge)
		var local := host.to_local(world_pos) if host != null else world_pos
		berth_rows.append({
			"berth_id": s.berth_id,
			"station_id": s.station_id,
			"free": ship == null and reservation.is_empty(),
			"ship_id": ship_id_of(ship),
			"reserved_by": str(reservation.get("vessel_id", "")),
			"family": s.family,
			"commodities": Array(s.commodities),
			"length_m": s.length_m,
			"width_m": s.width_m,
			"face_offset_m": s.face_offset_m,
			"local_xz": [local.x, local.z],
			"equip_ids": Array(equipment_ids_on_berth(s.berth_id)),
		})
	var ship_rows: Array = []
	for ship in ships():
		var b := ship as BoatBody
		ship_rows.append({
			"ship_id": ship_id_of(b),
			"berth_id": ship_berth_id(b),
		})
	var equip_rows: Array = []
	for equip in all_equipment():
		var e := equip as QuayEquipmentJob
		equip_rows.append({
			"equip_id": e.equipment_id(),
			"berth_id": e.berth_id(),
			"kind": e.equipment_kind(),
			"ship_id": ship_id_of(e.served_ship()),
			"job": e.job_mode(),
		})
	return {
		"port_id": _port_id,
		"berths": berth_rows,
		"ships": ship_rows,
		"equipment": equip_rows,
		"jobs": active_jobs(),
		"traffic": traffic_snapshot(),
	}


## --- MP-shaped apply (same APIs; peers call these) ---------------------------

func apply_remote_ship_berth(ship: BoatBody, berth_id: String) -> bool:
	## Remote occupancy paint — uses the same plug path.
	if ship == null:
		return false
	var bid := berth_id.strip_edges()
	if bid.is_empty():
		unplug_ship(ship)
		return true
	return plug_ship(bid, ship)


func ship_berth_meta(ship: BoatBody) -> String:
	## UDP-friendly: berth=<berth_id>
	var bid := ship_berth_id(ship)
	if bid.is_empty():
		return ""
	return "berth=%s" % bid


static func ship_id_of(ship: BoatBody) -> String:
	if ship == null or not is_instance_valid(ship):
		return ""
	## Durable gameplay identity wins. network_ship_id is only the lossy UDP
	## presentation identity and must never authorize cargo or port operations.
	var server_id := str(ship.get_meta("server_vessel_id", "")).strip_edges()
	if not server_id.is_empty():
		return server_id
	var named := str(ship.get_meta("network_ship_id", "")).strip_edges()
	if not named.is_empty():
		return named
	var uid := str(ship.get_meta("vessel_uid", "")).strip_edges()
	if not uid.is_empty():
		return uid
	var display := str(ship.get_meta("vessel_display_name", "")).strip_edges()
	if not display.is_empty():
		return display
	var ctrl := ship.get_node_or_null("BoatController") as BoatController
	if ctrl != null:
		var ship_name := ctrl.ship_name.strip_edges()
		if not ship_name.is_empty() and ship_name != "Unnamed Vessel":
			return ship_name
	if not ship.name.is_empty() and ship.name != "PlayerShip":
		return ship.name
	return "ship_%d" % ship.get_instance_id()


static func make_berth_id(port_id: String, station_id: String) -> String:
	return "%s/%s" % [port_id.strip_edges(), station_id.strip_edges()]


static func make_equip_id(berth_id: String, kind: String, index: int) -> String:
	return "%s/%s_%d" % [berth_id.strip_edges(), kind.strip_edges(), index]
