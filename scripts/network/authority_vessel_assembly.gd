class_name AuthorityVesselAssembly
extends RefCounted

## Adapter from the new authoritative records into the existing vessel builder.
## A caller supplies fetched immutable construction + public vessel contents.
## Live ownership/save migration is separate; this never changes company data.
const CATALOG := "res://resources/data/vessels/gameplay_catalog.json"


static func instantiate(view: Dictionary, construction: Dictionary) -> BoatBody:
	if str(view.get("construction_id", "")) != str(construction.get("id", "")):
		return null
	if str(construction.get("catalog_hash", "")) != FileAccess.get_sha256(CATALOG):
		return null
	var layout: Dictionary = construction.get("layout", {})
	if not ImportedVesselLayout.valid(layout, str(layout.get("hull", ""))):
		return null
	return VesselSpawn.instantiate_from_record({"uid": view.id, "name": view.name,
		"hull_id": layout.hull, "brick_layout": layout})


static func apply_contents(boat: BoatBody, view: Dictionary, construction: Dictionary) -> String:
	if str(view.get("construction_id", "")) != str(construction.get("id", "")):
		return "Construction identity mismatch"
	var pads := {}
	for pad in boat.get_cargo_pads():
		pads[str(pad.get_meta("authority_slot_id", ""))] = pad
	var definitions := {}
	for slot: Dictionary in construction.get("cargo_slots", []): definitions[str(slot.id)] = slot
	var desired := {}
	var ids := {}
	for item: Dictionary in view.get("cargo", []):
		var slot_id := str(item.get("slot_id", ""))
		if not pads.has(slot_id) or not definitions.has(slot_id) or desired.has(slot_id):
			return "Unknown, unsupported or duplicate cargo slot"
		if str(item.get("container_type", "")) != str(definitions[slot_id].container_type):
			return "Container type does not fit the installed slot"
		if str(item.get("id", "")).is_empty() or ids.has(str(item.id)):
			return "Missing or duplicate cargo identity"
		desired[slot_id] = item
		ids[str(item.id)] = true
	# Validation completes before any existing presentation is modified.
	for slot_id: String in pads:
		var pad := pads[slot_id] as CargoSlotPadComponent
		var wanted: Dictionary = desired.get(slot_id, {})
		var current := pad.get_containers()
		if wanted.is_empty():
			if not current.is_empty(): pad.clear_all()
			continue
		if current.size() == 1 and current[0].id == str(wanted.id) and current[0].paint_variant == int(wanted.paint_variant) and current[0].mass_kg == float(wanted.get("mass_kg", 0.0)):
			continue
		pad.clear_all()
		var unit := ContainerUnit.create(str(wanted.id), "provisions", float(wanted.get("mass_kg", 0.0)), str(wanted.container_type))
		unit.paint_variant = int(wanted.paint_variant)
		if pad.add_container(unit) < 0: return "Runtime capacity disagrees with construction record"
	return ""
