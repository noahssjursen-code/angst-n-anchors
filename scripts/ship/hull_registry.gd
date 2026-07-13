class_name HullRegistry
extends RefCounted

## Vessel catalog. Each entry needs a hand-authored scene under scenes/vessels/.
## Legacy hull ids still resolve so old saves / network packets keep working.

const WORKBOAT_SCENE := "res://scenes/vessels/workboat.tscn"
const TRAWLER_SMALL_SCENE := "res://scenes/vessels/fishing_trawler_small.tscn"
const _WORKBOAT_SCRIPT := preload("res://scripts/ship/vessels/workboat.gd")
const _TRAWLER_SMALL_SCRIPT := preload("res://scripts/ship/vessels/fishing_trawler_small.gd")

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
	"loa_m": 30.0,
	"beam_m": 24.0,
	"depth_m": 6.0,
}

const FISHING_TRAWLER_SMALL := {
	"id": "fishing_trawler_small",
	"display": "Fishing trawler  •  28 × 10 m",
	"role": VesselRole.Type.FISHING,
	"ship_class": ShipClass.Type.COASTAL_TRADER,
	"ship_class_label": "Coastal day trawler",
	"scene_path": TRAWLER_SMALL_SCENE,
	"capabilities": ["fishing"],
	"price_marks": 0,
	"displacement_t": 256.0,
	"loa_m": 28.0,
	"beam_m": 10.0,
	"depth_m": 5.6,
}

## Old hull ids from the deleted fleet — map to a live hull, never listed in catalog.
const LEGACY_ID_ALIASES: Dictionary = {
	"fishing_trawler_medium": "fishing_trawler_small",
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
	"fishing_boat": "fishing_trawler_small",
	"fishing_boat_small": "fishing_trawler_small",
	"fishing_boat_large": "workboat",
}


static func catalog() -> Array[Dictionary]:
	return [
		FISHING_TRAWLER_SMALL.duplicate(true),
		WORKBOAT.duplicate(true),
	]


static func get_by_id(hull_id: String) -> Dictionary:
	var id := resolve_network_hull_id(hull_id)
	match id:
		"fishing_trawler_small":
			return FISHING_TRAWLER_SMALL.duplicate(true)
		_:
			return WORKBOAT.duplicate(true)


static func get_by_file(_filename: String) -> Dictionary:
	return WORKBOAT.duplicate(true)


static func resolve_id_from_template(template_path: String, fallback: String = "workboat") -> String:
	var path := template_path.strip_edges()
	if path.contains("fishing_trawler_small"):
		return "fishing_trawler_small"
	if path.contains("workboat"):
		return "workboat"
	return resolve_network_hull_id(fallback)


static func resolve_network_hull_id(hull_id: String) -> String:
	var id := hull_id.strip_edges()
	if id.is_empty():
		return "workboat"
	if id == "workboat" or id == "fishing_trawler_small":
		return id
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


static func make_grid(hull_id: String) -> DeckGrid:
	match resolve_network_hull_id(hull_id):
		"fishing_trawler_small":
			return _TRAWLER_SMALL_SCRIPT.make_grid()
		_:
			return _WORKBOAT_SCRIPT.make_grid()


static func build_hull(hull_id: String) -> BoatBody:
	match resolve_network_hull_id(hull_id):
		"fishing_trawler_small":
			return _TRAWLER_SMALL_SCRIPT.build() as BoatBody
		_:
			return _WORKBOAT_SCRIPT.build() as BoatBody


static func has_capability(hull_id: String, capability: String) -> bool:
	var entry := get_by_id(hull_id)
	var caps = entry.get("capabilities", [])
	return caps is Array and (caps as Array).has(capability)


## Prefer this for owned vessels — capabilities come from the brick fit-out.
static func record_has_capability(record: Dictionary, capability: String) -> bool:
	var cap := capability.strip_edges()
	var hull_id := str(record.get("hull_id", "workboat"))
	var layout := BrickLayout.from_dict(VesselSpawn.brick_layout_of(record))
	var report := BrickRules.validate(layout, make_grid(hull_id))
	var caps: Dictionary = report.get("capabilities", {})
	match cap:
		"cargo":
			return int(caps.get("cargo_cells", 0)) > 0
		"crane":
			return bool(caps.get("has_crane", false))
		"cabin":
			return bool(caps.get("has_cabin", false))
		"helm":
			return bool(caps.get("has_helm", false))
		"fishing":
			return layout.count_tag("fishing") > 0
		_:
			return has_capability(hull_id, cap)
