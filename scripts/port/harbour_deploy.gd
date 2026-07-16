class_name HarbourDeploy
extends RefCounted

## Deploy a ledger vessel into a free harbour berth via HarbourController.


static func ship_requirements(record: Dictionary) -> Dictionary:
	var hull_id := str(record.get("hull_id", ""))
	var hull := HullRegistry.get_by_id(hull_id)
	var ship_class := int(hull.get("ship_class", ShipClass.Type.COASTAL_TRADER)) as ShipClass.Type
	## Hull catalog LOA is already world metres (same contract as PortSizing berths).
	var loa_m := float(hull.get("loa_m", ShipClass.max_length(ship_class)))
	var beam_m := float(hull.get("beam_m", ShipClass.beam(ship_class)))
	var registration_id := str(record.get("registration_id", "")).strip_edges()
	return {
		"hull_id": str(hull.get("id", hull_id)),
		"ship_class": ship_class,
		"ship_class_name": ShipClass.display_name(ship_class),
		"loa_m": loa_m,
		"loa_world_m": loa_m,
		"beam_world_m": beam_m,
		"registration_id": registration_id,
		"terminal_families": terminal_families_for_registration(registration_id),
		"display": VesselSpawn.vessel_name_of(record),
	}


static func terminal_families_for_registration(registration_id: String) -> PackedStringArray:
	var reg := VesselRegistrationCatalog.resolved_registration(registration_id)
	var out := PackedStringArray()
	for raw in reg.get("terminal_families", []) as Array:
		var family := str(raw).strip_edges()
		if not family.is_empty() and family not in out:
			out.append(family)
	return out


static func free_slots_for(
		harbour: HarbourController,
		record: Dictionary,
		max_ship_class: ShipClass.Type = ShipClass.Type.DEEP_SEA_FREIGHTER,
) -> Array:
	if harbour == null:
		return []
	var req := ship_requirements(record)
	var ship_class: ShipClass.Type = req["ship_class"]
	if not ShipClass.fits(ship_class, max_ship_class):
		return []
	var loa_world := float(req["loa_world_m"])
	var families: PackedStringArray = req["terminal_families"]
	var out: Array = []
	for slot in harbour.free_berths():
		var s := slot as QuayBerthSlot
		if s == null:
			continue
		if not s.accepts_loa_m(loa_world):
			continue
		out.append(s)
	## If registration declares quay families, only offer those faces.
	if not families.is_empty():
		var matched: Array = []
		for slot in out:
			var s := slot as QuayBerthSlot
			if s != null and _family_rank(s.family, families) < 100:
				matched.append(s)
		out = matched
	out.sort_custom(func(a: QuayBerthSlot, b: QuayBerthSlot) -> bool:
		var a_match := _family_rank(a.family, families)
		var b_match := _family_rank(b.family, families)
		if a_match != b_match:
			return a_match < b_match
		## Prefer shortest berth that still fits — save long quays for larger hulls.
		if not is_equal_approx(a.length_m, b.length_m):
			return a.length_m < b.length_m
		return a.berth_id < b.berth_id
	)
	return out


static func _family_rank(family: String, preferred: PackedStringArray) -> int:
	if preferred.is_empty():
		return 1
	var f := family.strip_edges()
	if f.is_empty():
		f = "general"
	for i in range(preferred.size()):
		if preferred[i] == f:
			return i
	## Soft fallback: bulk registrations may still use a general asphalt if no bulk free.
	if f == "general" or f == "twin":
		return 100 + preferred.size()
	return 200 + preferred.size()


static func pick_slot(
		harbour: HarbourController,
		record: Dictionary,
		max_ship_class: ShipClass.Type = ShipClass.Type.DEEP_SEA_FREIGHTER,
		preferred_berth_id: String = "",
) -> QuayBerthSlot:
	var slots := free_slots_for(harbour, record, max_ship_class)
	if slots.is_empty():
		return null
	var preferred := preferred_berth_id.strip_edges()
	if not preferred.is_empty():
		for slot in slots:
			var s := slot as QuayBerthSlot
			if s != null and s.berth_id == preferred:
				return s
		return null
	## When registration names terminal families, require a matching free berth.
	var families := terminal_families_for_registration(str(record.get("registration_id", "")))
	if not families.is_empty():
		for slot in slots:
			var s := slot as QuayBerthSlot
			if s != null and _family_rank(s.family, families) < 100:
				return s
		return null
	return slots[0] as QuayBerthSlot


static func deploy(
		plot: PortPlot,
		record: Dictionary,
		preferred_berth_id: String = "",
) -> BoatBody:
	if plot == null:
		return null
	var harbour := plot.harbour_controller()
	if harbour == null:
		return null
	var max_class := ShipClass.Type.DEEP_SEA_FREIGHTER
	if plot.port_data() != null:
		max_class = plot.port_data().max_ship_class
	var resolved := VesselSpawn.resolve_deployable_record(record)
	if resolved.is_empty():
		return null
	var slot := pick_slot(harbour, resolved, max_class, preferred_berth_id)
	if slot == null:
		return null

	PlayerVessel.replace_before_spawn(plot.get_tree())
	var ship := VesselSpawn.instantiate_from_record(resolved)
	if ship == null:
		return null
	VesselSpawn.apply_propulsion_override(ship, resolved)
	VesselSpawn.apply_identity(ship, resolved)
	ship.name = "PlayerShip"
	PlayerVessel.mark_player_ship(ship)
	plot.add_child(ship)
	ship.dock_at_berth(slot)
	if not harbour.plug_ship(slot.berth_id, ship):
		ship.queue_free()
		return null
	_auto_moor_slot(ship, slot)
	return ship


static func _auto_moor_slot(ship: BoatBody, slot: QuayBerthSlot) -> void:
	if ship == null or slot == null:
		return
	var mooring := ship.find_child("MooringComponent", true, false) as MooringComponent
	if mooring == null:
		return
	var posts := slot.bollards()
	if posts.size() < 2:
		mooring.call_deferred("auto_moor", ship.get_tree())
		return
	## Nearest berth bollards to bow/stern — not the quay end-posts.
	mooring.call_deferred("moor_to_nearest_of", posts)
