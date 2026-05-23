class_name HullRegistry
extends RefCounted

## Central registry for all playable ship hull definitions in the game.
## Decouples ship size (ShipClass) and gameplay role (VesselRole).
## Replacing hardcoded catalogs in NPCs, replication, and showcases.

const HULL_DEFINITIONS: Dictionary = {
	# --- FISHING ---
	"fishing_trawler_small": {
		"id": "fishing_trawler_small",
		"display": "Small Fishing Trawler  •  10 m",
		"role": VesselRole.Type.FISHING,
		"ship_class": ShipClass.Type.LAUNCH,
		"ship_class_label": "Launch",
		"hull_file": "hull_fishing_boat_small.json",
		"superstructure": "wheelhouse_fishing_small",
		"vendor": "boatyard",
		"capabilities": ["fishing"]
	},
	"fishing_trawler_medium": {
		"id": "fishing_trawler_medium",
		"display": "Coastal Fishing Trawler  •  13 m",
		"role": VesselRole.Type.FISHING,
		"ship_class": ShipClass.Type.COASTAL_TRADER,
		"ship_class_label": "Coastal Trader",
		"hull_file": "hull_fishing_boat.json",
		"superstructure": "wheelhouse_fishing_medium",
		"vendor": "boatyard",
		"capabilities": ["fishing"]
	},
	"fishing_trawler_large": {
		"id": "fishing_trawler_large",
		"display": "Deep Sea Trawler  •  18 m",
		"role": VesselRole.Type.FISHING,
		"ship_class": ShipClass.Type.SHORT_SEA_COASTER,
		"ship_class_label": "Short Sea Coaster",
		"hull_file": "hull_fishing_boat_large.json",
		"superstructure": "wheelhouse_fishing_large",
		"vendor": "boatyard",
		"capabilities": ["fishing"]
	},
	
	# --- TANKER ---
	"liquid_tanker_small": {
		"id": "liquid_tanker_small",
		"display": "Small Fuel Tanker  •  12 m",
		"role": VesselRole.Type.TANKER,
		"ship_class": ShipClass.Type.LAUNCH,
		"ship_class_label": "Launch",
		"hull_file": "hull_liquid_tanker_small.json",
		"superstructure": "wheelhouse_tanker_small",
		"vendor": "shipwright",
		"capabilities": ["liquid_hold"]
	},
	"liquid_tanker_medium": {
		"id": "liquid_tanker_medium",
		"display": "Coastal Fuel Tanker  •  15 m",
		"role": VesselRole.Type.TANKER,
		"ship_class": ShipClass.Type.COASTAL_TRADER,
		"ship_class_label": "Coastal Trader",
		"hull_file": "hull_liquid_tanker.json",
		"superstructure": "wheelhouse_tanker_medium",
		"vendor": "shipwright",
		"capabilities": ["liquid_hold"]
	},
	"liquid_tanker_large": {
		"id": "liquid_tanker_large",
		"display": "Harbour Fuel Tanker  •  22 m",
		"role": VesselRole.Type.TANKER,
		"ship_class": ShipClass.Type.SHORT_SEA_COASTER,
		"ship_class_label": "Short Sea Coaster",
		"hull_file": "hull_liquid_tanker_large.json",
		"superstructure": "wheelhouse_tanker_large",
		"vendor": "shipwright",
		"capabilities": ["liquid_hold"]
	},
	"liquid_tanker_huge": {
		"id": "liquid_tanker_huge",
		"display": "Deep Sea Crude Tanker  •  45 m",
		"role": VesselRole.Type.TANKER,
		"ship_class": ShipClass.Type.DEEP_SEA_FREIGHTER,
		"ship_class_label": "Deep Sea Freighter",
		"hull_file": "hull_liquid_tanker_huge.json",
		"superstructure": "wheelhouse_tanker_huge",
		"vendor": "shipwright",
		"capabilities": ["liquid_hold"]
	},
	"liquid_tanker_ultra": {
		"id": "liquid_tanker_ultra",
		"display": "VLCC Crude Tanker  •  100 m",
		"role": VesselRole.Type.TANKER,
		"ship_class": ShipClass.Type.DEEP_SEA_FREIGHTER,
		"ship_class_label": "Deep Sea Freighter",
		"hull_file": "hull_liquid_tanker_ultra.json",
		"superstructure": "wheelhouse_tanker_ultra",
		"vendor": "shipwright",
		"capabilities": ["liquid_hold"]
	},
	
	# --- CARGO ---
	"cargo_ship_small": {
		"id": "cargo_ship_small",
		"display": "Small Cargo Coaster  •  15 m",
		"role": VesselRole.Type.CARGO,
		"ship_class": ShipClass.Type.COASTAL_TRADER,
		"ship_class_label": "Coastal Trader",
		"hull_file": "hull_cargo_ship_small.json",
		"superstructure": "wheelhouse_cargo_small",
		"vendor": "shipwright",
		"capabilities": ["cargo"]
	},
	"cargo_ship_medium": {
		"id": "cargo_ship_medium",
		"display": "Twin-Deck Cargo Coaster  •  20 m",
		"role": VesselRole.Type.CARGO,
		"ship_class": ShipClass.Type.COASTAL_TRADER,
		"ship_class_label": "Coastal Trader",
		"hull_file": "hull_cargo_ship.json",
		"superstructure": "wheelhouse_cargo_medium",
		"vendor": "shipwright",
		"capabilities": ["cargo"]
	},
	"cargo_ship_large": {
		"id": "cargo_ship_large",
		"display": "Deep Sea Cargo Coaster  •  28 m",
		"role": VesselRole.Type.CARGO,
		"ship_class": ShipClass.Type.SHORT_SEA_COASTER,
		"ship_class_label": "Short Sea Coaster",
		"hull_file": "hull_cargo_ship_large.json",
		"superstructure": "wheelhouse_cargo_large",
		"vendor": "shipwright",
		"capabilities": ["cargo"]
	},
	"cargo_ship_huge": {
		"id": "cargo_ship_huge",
		"display": "Deep Sea Bulk Carrier  •  50 m",
		"role": VesselRole.Type.CARGO,
		"ship_class": ShipClass.Type.DEEP_SEA_FREIGHTER,
		"ship_class_label": "Deep Sea Freighter",
		"hull_file": "hull_cargo_ship_huge.json",
		"superstructure": "wheelhouse_cargo_huge",
		"vendor": "shipwright",
		"capabilities": ["cargo"]
	},
	"cargo_ship_ultra": {
		"id": "cargo_ship_ultra",
		"display": "Supermax Bulk Carrier  •  100 m",
		"role": VesselRole.Type.CARGO,
		"ship_class": ShipClass.Type.DEEP_SEA_FREIGHTER,
		"ship_class_label": "Deep Sea Freighter",
		"hull_file": "hull_cargo_ship_ultra.json",
		"superstructure": "wheelhouse_cargo_ultra",
		"vendor": "shipwright",
		"capabilities": ["cargo"]
	},
	
	# --- PASSENGER ---
	"passenger_ferry_small": {
		"id": "passenger_ferry_small",
		"display": "Small Passenger Ferry  •  15 m",
		"role": VesselRole.Type.PASSENGER,
		"ship_class": ShipClass.Type.LAUNCH,
		"ship_class_label": "Launch",
		"hull_file": "hull_ferry_small.json",
		"superstructure": "wheelhouse_ferry_small",
		"vendor": "ferry_office",
		"capabilities": ["passenger"]
	},
	"passenger_ferry_medium": {
		"id": "passenger_ferry_medium",
		"display": "Passenger Route Ferry  •  22 m",
		"role": VesselRole.Type.PASSENGER,
		"ship_class": ShipClass.Type.SHORT_SEA_COASTER,
		"ship_class_label": "Short Sea Coaster",
		"hull_file": "hull_ferry.json",
		"superstructure": "wheelhouse_ferry_medium",
		"vendor": "ferry_office",
		"capabilities": ["passenger"]
	},
	"passenger_ferry_large": {
		"id": "passenger_ferry_large",
		"display": "Double-Ended Car Ferry  •  30 m",
		"role": VesselRole.Type.PASSENGER,
		"ship_class": ShipClass.Type.SHORT_SEA_COASTER,
		"ship_class_label": "Short Sea Coaster",
		"hull_file": "hull_ferry_large.json",
		"superstructure": "wheelhouse_ferry_large",
		"vendor": "ferry_office",
		"capabilities": ["passenger"]
	},
	
	# --- CONTAINER ---
	"container_ship_small": {
		"id": "container_ship_small",
		"display": "Feeder Container Ship  •  20 m",
		"role": VesselRole.Type.CONTAINER,
		"ship_class": ShipClass.Type.COASTAL_TRADER,
		"ship_class_label": "Coastal Trader",
		"hull_file": "hull_container_ship_small.json",
		"superstructure": "wheelhouse_container_small",
		"vendor": "shipwright",
		"capabilities": ["cargo"] # Shares cargo capability to load containers dynamically!
	},
	"container_ship_medium": {
		"id": "container_ship_medium",
		"display": "Handysize Container Ship  •  35 m",
		"role": VesselRole.Type.CONTAINER,
		"ship_class": ShipClass.Type.HANDYSIZE_FEEDER,
		"ship_class_label": "Handysize Feeder",
		"hull_file": "hull_container_ship_medium.json",
		"superstructure": "wheelhouse_container_medium",
		"vendor": "shipwright",
		"capabilities": ["cargo"]
	},
	"container_ship_large": {
		"id": "container_ship_large",
		"display": "Panamax Container Ship  •  55 m",
		"role": VesselRole.Type.CONTAINER,
		"ship_class": ShipClass.Type.DEEP_SEA_FREIGHTER,
		"ship_class_label": "Deep Sea Freighter",
		"hull_file": "hull_container_ship_large.json",
		"superstructure": "wheelhouse_container_large",
		"vendor": "shipwright",
		"capabilities": ["cargo"]
	},
	"container_ship_ultra": {
		"id": "container_ship_ultra",
		"display": "ULCV Container Ship  •  100 m",
		"role": VesselRole.Type.CONTAINER,
		"ship_class": ShipClass.Type.DEEP_SEA_FREIGHTER,
		"ship_class_label": "Deep Sea Freighter",
		"hull_file": "hull_container_ship_ultra.json",
		"superstructure": "wheelhouse_container_ultra",
		"vendor": "shipwright",
		"capabilities": ["cargo"]
	}
}


## Returns the definition of a specific hull by its ID, or an empty Dictionary if not found.
static func get_by_id(id: String) -> Dictionary:
	return HULL_DEFINITIONS.get(id, {}).duplicate()


## Returns a list of all defined hulls.
static func all() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for key in HULL_DEFINITIONS.keys():
		list.append(HULL_DEFINITIONS[key].duplicate())
	return list


## Returns all hulls of a given role.
static func by_role(role_type: VesselRole.Type) -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for key in HULL_DEFINITIONS.keys():
		var def: Dictionary = HULL_DEFINITIONS[key]
		if int(def["role"]) == int(role_type):
			list.append(def.duplicate())
	return list


## Returns all hulls of a given ShipClass.
static func by_ship_class(class_type: ShipClass.Type) -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for key in HULL_DEFINITIONS.keys():
		var def: Dictionary = HULL_DEFINITIONS[key]
		if int(def["ship_class"]) == int(class_type):
			list.append(def.duplicate())
	return list


## Returns all hulls associated with a specific vendor (e.g. "shipwright", "harbour_master").
static func by_vendor(vendor_id: String) -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for key in HULL_DEFINITIONS.keys():
		var def: Dictionary = HULL_DEFINITIONS[key]
		if str(def.get("vendor", "")) == vendor_id:
			list.append(def.duplicate())
	return list


## Full shipwright showroom catalog — every registered hull, grouped by role then size.
static func catalog() -> Array[Dictionary]:
	var by_role: Dictionary = {}
	for def: Dictionary in all():
		var role_label: String = VesselRole.display_name(def.get("role", VesselRole.Type.CARGO))
		if not by_role.has(role_label):
			by_role[role_label] = []
		(by_role[role_label] as Array).append(def)

	var out: Array[Dictionary] = []
	for role_label in [
		"Fishing Vessel",
		"Liquid Tanker",
		"Cargo Freighter",
		"Passenger Ferry",
		"Container Carrier",
	]:
		if not by_role.has(role_label):
			continue
		var entries: Array = by_role[role_label]
		entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return _hull_size_rank(str(a.get("id", ""))) < _hull_size_rank(str(b.get("id", "")))
		)
		for entry in entries:
			out.append(entry as Dictionary)
	return out


static func _hull_size_rank(id: String) -> int:
	if id.contains("small"):
		return 0
	if id.contains("large"):
		return 2
	if id.contains("huge"):
		return 3
	if id.contains("ultra"):
		return 4
	return 1


## Returns the registry entry matching a hull filename (e.g. "hull_large.json" or "hull_coastal_trader.json").
static func get_by_file(filename: String) -> Dictionary:
	var file_clean := filename.get_file()
	for key in HULL_DEFINITIONS.keys():
		var def: Dictionary = HULL_DEFINITIONS[key]
		if def.get("hull_file", "").get_file() == file_clean:
			return def.duplicate()
	return {}


## Strip the wire entity prefix once: ship_container_ship_ultra -> container_ship_ultra.
static func hull_id_from_network_type(network_type: String) -> String:
	if network_type.begins_with("ship_"):
		return network_type.substr(5)
	return network_type


## Maps a network hull id (registry id, filename stem, or legacy alias) to a registry id.
static func resolve_network_hull_id(hull_id: String) -> String:
	if hull_id.is_empty():
		return ""
	if HULL_DEFINITIONS.has(hull_id):
		return hull_id
	var from_file := get_by_file("hull_%s.json" % hull_id)
	if not from_file.is_empty():
		return str(from_file.get("id", ""))
	var recovered := _recover_double_stripped_hull_id(hull_id)
	if HULL_DEFINITIONS.has(recovered):
		return recovered
	return hull_id


static func _recover_double_stripped_hull_id(hull_id: String) -> String:
	# e.g. container_ultra (from ship_container_ship_ultra with replace-all) -> container_ship_ultra
	var parts: PackedStringArray = hull_id.split("_")
	if parts.size() == 2 and parts[0] in ["container", "cargo"]:
		return "%s_ship_%s" % [parts[0], parts[1]]
	return hull_id


## Resolve the registry hull id used on the wire from a template path and/or saved id.
static func resolve_id_from_template(template_path: String, preferred_id: String = "") -> String:
	var resolved := resolve_network_hull_id(preferred_id)
	if HULL_DEFINITIONS.has(resolved):
		return resolved
	if template_path.is_empty():
		return resolved
	var f := FileAccess.open(template_path, FileAccess.READ)
	if f == null:
		return resolved
	var json = JSON.parse_string(f.get_as_text())
	f.close()
	if json is Dictionary and json.has("hull"):
		var entry := get_by_file(str(json["hull"]))
		if not entry.is_empty():
			return str(entry.get("id", ""))
	return resolved
