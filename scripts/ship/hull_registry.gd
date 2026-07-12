class_name HullRegistry
extends RefCounted

## Vessel catalog after the fleet wipe. Add new hull entries here to expose them
## in the shipwright catalog / shipyard outfit UI (each needs a scene + sockets).
## Only the hand-authored workboat is for sale today.
## Legacy hull ids still resolve to workboat so old saves / network packets keep working.

const WORKBOAT_SCENE := "res://scenes/vessels/workboat.tscn"

const WORKBOAT := {
	"id": "workboat",
	"display": "Workboat  •  30 × 24 m",
	"role": VesselRole.Type.FISHING,
	"ship_class": ShipClass.Type.COASTAL_TRADER,
	"ship_class_label": "Coastal workboat",
	"scene_path": WORKBOAT_SCENE,
	"capabilities": ["fishing", "cargo"],
	"price_marks": 5000,
	"displacement_t": 960.0,
}

## Old hull ids from the deleted fleet — map to workboat, never listed in catalog.
const LEGACY_ID_ALIASES: Dictionary = {
	"fishing_trawler_small": "workboat",
	"fishing_trawler_medium": "workboat",
	"fishing_trawler_large": "workboat",
	"cargo_ship": "workboat",
	"cargo_ship_small": "workboat",
	"cargo_ship_medium": "workboat",
	"cargo_ship_large": "workboat",
	"cargo_ship_huge": "workboat",
	"cargo_ship_ultra": "workboat",
	"liquid_tanker": "workboat",
	"liquid_tanker_small": "workboat",
	"liquid_tanker_large": "workboat",
	"liquid_tanker_huge": "workboat",
	"liquid_tanker_ultra": "workboat",
	"container_ship_small": "workboat",
	"container_ship_medium": "workboat",
	"container_ship_large": "workboat",
	"container_ship_ultra": "workboat",
	"ferry": "workboat",
	"ferry_small": "workboat",
	"ferry_large": "workboat",
	"fishing_boat": "workboat",
	"fishing_boat_small": "workboat",
	"fishing_boat_large": "workboat",
}


static func catalog() -> Array[Dictionary]:
	## Only ships that still exist as hand-authored scenes.
	return [WORKBOAT.duplicate(true)]


static func get_by_id(hull_id: String) -> Dictionary:
	var id := resolve_network_hull_id(hull_id)
	if id == "workboat":
		return WORKBOAT.duplicate(true)
	return WORKBOAT.duplicate(true)


static func get_by_file(_filename: String) -> Dictionary:
	return WORKBOAT.duplicate(true)


static func resolve_id_from_template(_template_path: String, fallback: String = "workboat") -> String:
	return resolve_network_hull_id(fallback)


static func resolve_network_hull_id(hull_id: String) -> String:
	var id := hull_id.strip_edges()
	if id.is_empty():
		return "workboat"
	if id == "workboat":
		return "workboat"
	if LEGACY_ID_ALIASES.has(id):
		return str(LEGACY_ID_ALIASES[id])
	return "workboat"


static func hull_id_from_network_type(network_type: String) -> String:
	if network_type.begins_with("ship_"):
		return resolve_network_hull_id(network_type.substr(5))
	return resolve_network_hull_id(network_type)


static func scene_path_for(hull_id: String) -> String:
	var entry := get_by_id(hull_id)
	return str(entry.get("scene_path", WORKBOAT_SCENE))


static func has_capability(hull_id: String, capability: String) -> bool:
	var entry := get_by_id(hull_id)
	var caps = entry.get("capabilities", [])
	return caps is Array and (caps as Array).has(capability)


## Prefer this for owned vessels — capabilities come from the brick fit-out.
static func record_has_capability(record: Dictionary, capability: String) -> bool:
	var cap := capability.strip_edges()
	var layout := BrickLayout.from_dict(VesselSpawn.brick_layout_of(record))
	var report := BrickRules.validate(layout, Workboat.make_grid())
	var caps: Dictionary = report.get("capabilities", {})
	match cap:
		"cargo":
			return int(caps.get("cargo_cells", 0)) > 0
		"crane":
			return bool(caps.get("has_crane", false))
		"cabin":
			return bool(caps.get("has_cabin", false))
		"fishing":
			return layout.count_tag("fishing") > 0
		_:
			return has_capability(str(record.get("hull_id", "workboat")), cap)
