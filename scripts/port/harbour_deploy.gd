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
		"loa_display_m": ShipClass.display_metres(loa_m),
		"beam_display_m": ShipClass.display_metres(beam_m),
		"loa_world_m": loa_m,
		"beam_world_m": beam_m,
		"registration_id": registration_id,
		"terminal_families": terminal_families_for_record(record),
		"display": VesselSpawn.vessel_name_of(record),
	}


## Berth routing hints from the authored fit-out, not legal registration or a
## vessel name. Runtime components still validate mounting and actual capacity.
static func terminal_families_for_record(record: Dictionary) -> PackedStringArray:
	var layout: Dictionary = record.get("brick_layout", record.get("prebuilt_layout", {}))
	if not ImportedVesselLayout.is_imported(layout):
		return terminal_families_for_registration(str(record.get("registration_id", "")))
	var ids := PackedStringArray()
	for part: Dictionary in layout.get("parts", []):
		ids.append(str(part.get("asset_id", "")))
	var families := PackedStringArray()
	if ids.has("ferry_bow_ramp_2m") and ids.has("ferry_seating_row_10"):
		families.append("passenger")
	if ImportedVesselLayout.has_capability(layout, "fishing"):
		families.append("fishing")
	if ids.has("container_bed_20ft") or ids.has("cargo_securing_bed_4m"):
		families.append("general")
		families.append("container")
	if ids.has("hold_coaming_6x12") or (ids.has("bulk_divider_5m") and not ids.has("cargo_deck_5x8")):
		families.append("bulk_ore")
		families.append("bulk_grain")
	# A general quay remains a mooring fallback for boats without a local service.
	# Specialized liquid/grain facilities must never win by being shorter.
	if not families.has("general"):
		families.append("general")
	return families


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
	var compatible := compatible_slots_for(harbour, record, max_ship_class)
	var out: Array = []
	for slot in compatible:
		var s := slot as QuayBerthSlot
		if s != null and harbour.moored_ship(s.berth_id) == null:
			out.append(s)
	return out


## Hull fit and service preferences. Multiplayer callers send this ordered list to
## world authority, which atomically chooses the first unoccupied berth.
static func compatible_slots_for(
		harbour: HarbourController,
		record: Dictionary,
		max_ship_class: ShipClass.Type = ShipClass.Type.DEEP_SEA_FREIGHTER,
) -> Array:
	if harbour == null:
		return []
	var req := ship_requirements(record)
	var ship_class: ShipClass.Type = req["ship_class"]
	# Imported hull dimensions are real metres; legacy classes predate these
	# hulls and can reject a 32 m coaster at a physically suitable 100 m quay.
	if not ImportedHullCatalog.has(str(record.get("hull_id", ""))) and not ShipClass.fits(ship_class, max_ship_class):
		return []
	var loa_world := float(req["loa_world_m"])
	var families: PackedStringArray = req["terminal_families"]
	var out: Array = []
	for slot in harbour.berths():
		var s := slot as QuayBerthSlot
		if s == null:
			continue
		if not s.accepts_loa_m(loa_world):
			continue
		out.append(s)
	## Filter by authored services (or legacy registration for legacy vessels).
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
		## Prefer shortest berth that still fits â€” save long quays for larger hulls.
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
	## Unlisted families rank below declared services and are filtered out above.
	if f == "general" or f == "twin":
		return 100 + preferred.size()
	return 200 + preferred.size()


static func pick_slot(
		harbour: HarbourController,
		record: Dictionary,
		max_ship_class: ShipClass.Type = ShipClass.Type.DEEP_SEA_FREIGHTER,
		preferred_berth_id: String = "",
) -> QuayBerthSlot:
	var preferred := preferred_berth_id.strip_edges()
	var slots := (
		compatible_slots_for(harbour, record, max_ship_class)
		if not preferred.is_empty()
		else free_slots_for(harbour, record, max_ship_class)
	)
	if slots.is_empty():
		return null
	if not preferred.is_empty():
		for slot in slots:
			var s := slot as QuayBerthSlot
			if s == null or s.berth_id != preferred:
				continue
			var occupant := harbour.moored_ship(preferred)
			if occupant == null or HarbourController.ship_id_of(occupant) == authority_vessel_id(record):
				return s
		return null
	## Require a matching free berth using the same policy as authority candidates.
	var families := terminal_families_for_record(record)
	if not families.is_empty():
		for slot in slots:
			var s := slot as QuayBerthSlot
			if s != null and _family_rank(s.family, families) < 100:
				return s
		return null
	return slots[0] as QuayBerthSlot


static func authority_vessel_id(record: Dictionary) -> String:
	var server_id := str(record.get("server_vessel_id", "")).strip_edges()
	if not server_id.is_empty():
		return server_id
	return str(record.get("uid", "")).strip_edges()


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
	## Nearest berth bollards to bow/stern â€” not the quay end-posts.
	mooring.call_deferred("moor_to_nearest_of", posts)
