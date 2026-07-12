class_name VesselKits
extends RefCounted

## Job kits — constrained loadout presets (one attachment per socket; kinds must match).

const KIT_FISHING := "fishing"
const KIT_CARGO := "cargo"
const KIT_CRANE := "crane"


static func catalog() -> Array[Dictionary]:
	return [
		{
			"id": KIT_FISHING,
			"display": "Fishing kit",
			"blurb": "Cabin, cargo grid, and stern trawl gear.",
			"attachments": _with_core([
				VesselLoadout.entry("cargo_main", "cargo_deck_grid"),
				VesselLoadout.entry("fishing_stern", "trawl_system"),
			]),
		},
		{
			"id": KIT_CARGO,
			"display": "Cargo kit",
			"blurb": "Cabin and deck grid — no trawl gear.",
			"attachments": _with_core([
				VesselLoadout.entry("cargo_main", "cargo_deck_grid"),
			]),
		},
		{
			"id": KIT_CRANE,
			"display": "Crane kit",
			"blurb": "Cabin, deck grid, and a small ship-mounted crane.",
			"attachments": _with_core([
				VesselLoadout.entry("cargo_main", "cargo_deck_grid"),
				VesselLoadout.entry("crane_deck", "ship_crane_small"),
			]),
		},
	]


static func get_by_id(kit_id: String) -> Dictionary:
	var want := kit_id.strip_edges()
	for kit in catalog():
		if str(kit.get("id", "")) == want:
			return kit.duplicate(true)
	return {}


static func attachments_for(kit_id: String) -> Array:
	var kit := get_by_id(kit_id)
	if kit.is_empty():
		return VesselLoadout.workboat_default()
	return (kit.get("attachments", []) as Array).duplicate(true)


static func _with_core(job_rows: Array) -> Array:
	var rows: Array = [
		VesselLoadout.entry("cabin", "cabin_workboat_basic"),
		VesselLoadout.entry("mooring_port_fwd", "mooring_cleat"),
		VesselLoadout.entry("mooring_stbd_fwd", "mooring_cleat"),
		VesselLoadout.entry("mooring_port_aft", "mooring_cleat"),
		VesselLoadout.entry("mooring_stbd_aft", "mooring_cleat"),
		VesselLoadout.entry("nav_port", "nav_light_port"),
		VesselLoadout.entry("nav_stbd", "nav_light_starboard"),
		VesselLoadout.entry("nav_bow", "nav_light_bow"),
		VesselLoadout.entry("nav_stern", "nav_light_stern"),
	]
	for row in job_rows:
		rows.append(row)
	return rows
