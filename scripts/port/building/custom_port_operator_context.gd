class_name CustomPortOperatorContext
extends RefCounted
## Passive navigation for an already validated port document. Resolving a counter
## grants no storage access, ownership, berth occupancy, cargo or money.
const BERTHS = preload("res://scripts/port/state/custom_port_berths.gd")
const CATALOG = preload("res://scripts/port/building/custom_port_catalog.gd")
const MODES := ["container", "general", "bulk", "catch", "liquid"]


static func resolve(snapshot: Dictionary, operator_placement_id: String, preferred_vessel_id := "", catalog: Dictionary = {}) -> Dictionary:
	var operator := _find(snapshot.get("placements", []), operator_placement_id)
	if operator.is_empty(): return _unavailable("operator_not_found", "This operator is no longer available.")
	var attributes: Dictionary = operator.get("attributes", {})
	# A harbour office remains a docking counter even when cargo stores are
	# nearby. Automatic nearest-facility selection is for cargo/general clerks.
	if str(attributes.get("service", "")) == "berths":
		return {"ok":true,"code":"berths","tab":"berths","store_id":"","vessel_id":""}
	var store: Dictionary = {}
	if attributes.has("store_id"):
		if attributes.store_id is String: store = _find(snapshot.get("stores", []), attributes.store_id)
		if store.is_empty(): return _unavailable("operator_store_unavailable", "This operator's storage is no longer available.")
	else:
		var nearest := INF
		for candidate in snapshot.get("stores", []):
			var placement := _find(snapshot.get("placements", []), str(candidate.get("placement_id", "")))
			if placement.is_empty(): continue
			var distance := _position(operator).distance_squared_to(_position(placement))
			if distance < nearest or (distance == nearest and str(candidate.id) < str(store.get("id", ""))):
				store = candidate
				nearest = distance
	if store.is_empty(): return {"ok": true, "code": "berths", "tab": "berths", "store_id": "", "vessel_id": ""}
	var definitions := CATALOG.definitions() if catalog.is_empty() else catalog
	var berths := BERTHS.derive(snapshot, definitions)
	var at := _position(_find(snapshot.get("placements", []), str(store.get("placement_id", ""))))
	var selected := ""
	var nearest := INF
	for vessel in snapshot.get("vessels", []):
		var berth := _find(berths, str(vessel.get("berth_id", "")))
		if berth.is_empty() or not _served(berth, vessel, store): continue
		var id := str(vessel.id)
		if id == preferred_vessel_id:
			selected = id
			break
		var pose := BERTHS.docking_pose(berth, vessel)
		var center: Array = pose.get("center_m", [0, 0, 0])
		var distance := at.distance_squared_to(Vector2(float(center[0]), float(center[2])))
		if distance < nearest or (distance == nearest and id < selected):
			selected = id
			nearest = distance
	return {"ok": true, "code": "cargo" if not selected.is_empty() else "cargo_no_served_vessel", "tab": "cargo", "store_id": str(store.id), "vessel_id": selected}


static func _served(berth: Dictionary, vessel: Dictionary, store: Dictionary) -> bool:
	for mode in MODES:
		if not _supports(store, mode) or not _supports(vessel, mode): continue
		if mode in ["container", "general"] and store.has("accepted_container_types") and vessel.has("accepted_container_types"):
			var common := false
			for type in store.accepted_container_types:
				if type in vessel.accepted_container_types: common = true
			if not common: continue
		if str(store.id) in BERTHS.services_for_vessel(berth, vessel, mode).get("store_ids", []): return true
	return false


static func _supports(record: Dictionary, mode: String) -> bool:
	if float(record.get("capacity_kg", 0)) <= 0: return false
	if record.has("accepted_handling_modes") and mode not in record.accepted_handling_modes: return false
	if record.has("handling_capacity_kg") and float(record.handling_capacity_kg.get(mode, 0)) <= 0: return false
	return true


static func _position(placement: Dictionary) -> Vector2:
	var values: Array = placement.get("position_m", [0, 0, 0])
	return Vector2(float(values[0]), float(values[2]))


static func _find(records: Array, id: String) -> Dictionary:
	for record in records:
		if record is Dictionary and str(record.get("id", "")) == id: return record
	return {}


static func _unavailable(code: String, message: String) -> Dictionary:
	return {"ok": false, "code": code, "message": message, "tab": "", "store_id": "", "vessel_id": ""}
