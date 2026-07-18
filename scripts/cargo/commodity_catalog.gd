class_name CommodityCatalog
extends RefCounted

## Trade / berth / bulk colour table.
## General cargo (provisions) = cubed break-bulk on short finger quays + T-crane.
## Shipping containers are a separate commodity (STS gantry, large freighters).
##
## terminal_family groups commodities onto the same berth / yard / handling gear:
##   general    — break-bulk / general cargo finger quay (provisions)
##   container  — ISO shipping containers, STS gantries, stack yards
##   bulk_ore   — ore / coal grabs and stockpiles
##   bulk_grain — grain elevators, silos
##   liquid     — oil / refined products / LNG jetties

const COMMODITIES := [
	{
		"id": "provisions",
		"display": "General Cargo",
		"handling_mode": "general",
		"terminal_family": "general",
		"mass_kg": 3200.0,
		"value": 14,
		"color": [0.72, 0.30, 0.22],
	},
	{
		"id": "containers",
		"display": "Containers",
		"handling_mode": "container",
		"terminal_family": "container",
		"mass_kg": 12000.0,
		"value": 40,
		"color": [0.18, 0.42, 0.72],
	},
	{
		"id": "grain",
		"display": "Grain",
		"handling_mode": "bulk",
		"terminal_family": "bulk_grain",
		"mass_kg": 180.0,
		"value": 8,
		"color": [0.90, 0.78, 0.30],
	},
	{
		"id": "iron_ore",
		"display": "Iron Ore",
		"handling_mode": "bulk",
		"terminal_family": "bulk_ore",
		"mass_kg": 480.0,
		"value": 18,
		"color": [0.72, 0.32, 0.18],
	},
	{
		"id": "coal",
		"display": "Coal",
		"handling_mode": "bulk",
		"terminal_family": "bulk_ore",
		"mass_kg": 280.0,
		"value": 10,
		"color": [0.18, 0.18, 0.22],
	},
	{
		"id": "crude_oil",
		"display": "Crude Oil",
		"handling_mode": "liquid",
		"terminal_family": "liquid",
		"mass_kg": 850.0,
		"value": 22,
		"color": [0.32, 0.18, 0.08],
	},
	{
		"id": "diesel",
		"display": "Marine Diesel",
		"handling_mode": "liquid",
		"terminal_family": "liquid",
		"mass_kg": 820.0,
		"value": 28,
		"color": [0.88, 0.62, 0.10],
	},
	{
		"id": "lng",
		"display": "LNG",
		"handling_mode": "liquid",
		"terminal_family": "liquid",
		"mass_kg": 450.0,
		"value": 35,
		"color": [0.25, 0.82, 0.95],
	},
]

## Full trade pool for seeded port profiles (import/export slots).
const PLAYABLE_TRADE := [
	"provisions", "containers", "grain", "iron_ore", "coal",
	"crude_oil", "diesel", "lng",
]

const TERMINAL_FAMILY_DISPLAY := {
	"general": "General cargo",
	"container": "Container",
	"bulk_ore": "Bulk ore / coal",
	"bulk_grain": "Bulk grain",
	"liquid": "Liquid jetty",
}

const EXCLUSIVE_PRODUCT_FAMILIES: Array[String] = []


static func commodity_info(commodity_id: String) -> Dictionary:
	for entry in COMMODITIES:
		if str((entry as Dictionary)["id"]) == commodity_id:
			return entry as Dictionary
	return {}


static func commodity_color(commodity_id: String) -> Color:
	var info := commodity_info(commodity_id)
	var arr: Array = info.get("color", [0.6, 0.6, 0.6])
	if arr.size() < 3:
		return Color(0.6, 0.6, 0.6)
	return Color(float(arr[0]), float(arr[1]), float(arr[2]))


static func commodity_handling_mode(commodity_id: String) -> String:
	return str(commodity_info(commodity_id).get("handling_mode", "general"))


static func commodity_terminal_family(commodity_id: String) -> String:
	var info := commodity_info(commodity_id)
	if info.is_empty():
		return "general"
	if info.has("terminal_family"):
		return str(info["terminal_family"])
	return commodity_handling_mode(commodity_id)


static func berth_group_id(commodity_id: String, role: String = "") -> String:
	var id := str(commodity_id)
	if id in ["provisions", "containers"]:
		return "pad:%s" % id
	var r := str(role)
	if r.is_empty():
		r = "trade"
	return "pad:%s:%s" % [id, r]


static func family_allows_shared_quay(_family: String) -> bool:
	return false


## Legacy dock-face asphalt berths (fish landings). General cargo uses short
## finger quays instead — the asphalt path buried yards in the apron slab.
static func uses_asphalt_dock(commodity_id: String) -> bool:
	return str(commodity_id) == "fish"


static func is_exclusive_berth_commodity(_commodity_id: String) -> bool:
	return true


static func commodity_display(commodity_id: String) -> String:
	return str(commodity_info(commodity_id).get("display", commodity_id))


static func terminal_family_display(family: String) -> String:
	return str(TERMINAL_FAMILY_DISPLAY.get(family, family.replace("_", " ").capitalize()))


static func terminal_family_color(family: String) -> Color:
	match family:
		"general":
			return Color(0.34, 0.38, 0.44)
		"container":
			return Color(0.16, 0.38, 0.62)
		"bulk_ore":
			return Color(0.42, 0.30, 0.24)
		"bulk_grain":
			return Color(0.72, 0.62, 0.28)
		"liquid":
			return Color(0.16, 0.20, 0.26)
		_:
			return Color(0.40, 0.42, 0.46)


static func general_cargo_mass_kg() -> float:
	return float(commodity_info("provisions").get("mass_kg", 3200.0))


static func container_mass_kg() -> float:
	return float(commodity_info("containers").get("mass_kg", 12000.0))
