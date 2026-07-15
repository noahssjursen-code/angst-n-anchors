class_name CommodityCatalog
extends RefCounted

## Static commodity packing / pricing catalog. Survives the contract purge so
## fishing, replication, and future trade systems share one commodity table.
##
## terminal_family groups commodities onto the same berth / yard / handling gear:
##   fishing    — fish landings, ice, chill sheds
##   general    — break-bulk / pallet cargo (timber, provisions, …)
##   container  — ISO boxes, STS gantries, stack yards
##   bulk_ore   — ore / coal grabs and stockpiles
##   bulk_ore   — ore / coal grabs and stockpiles
##   bulk_grain — grain elevators, silos, spout loaders
##   liquid     — oil / refined products / LNG jetties with loading arms

const COMMODITIES := [
	{
		"id": "fish",
		"display": "Fresh Fish",
		"handling_mode": "fishing",
		"terminal_family": "fishing",
		"mass_kg": 200.0,
		"value": 125,
		"max_pallet_units": 4,
		"color": [0.35, 0.65, 0.85],
	},
	{
		"id": "timber",
		"display": "Timber",
		"handling_mode": "general",
		"terminal_family": "general",
		"mass_kg": 320.0,
		"value": 12,
		"max_pallet_units": 4,
		"color": [0.52, 0.33, 0.18],
	},
	{
		"id": "provisions",
		"display": "Provisions",
		"handling_mode": "general",
		"terminal_family": "general",
		"mass_kg": 150.0,
		"value": 14,
		"max_pallet_units": 6,
		"color": [0.72, 0.30, 0.22],
	},
	{
		"id": "containers",
		"display": "Containers",
		"handling_mode": "container",
		"terminal_family": "container",
		"mass_kg": 12000.0,
		"value": 40,
		"max_pallet_units": 1,
		"color": [0.18, 0.42, 0.72],
	},
	{
		"id": "grain",
		"display": "Grain",
		"handling_mode": "bulk",
		"terminal_family": "bulk_grain",
		"mass_kg": 180.0,
		"value": 8,
		"max_pallet_units": 4,
		"color": [0.90, 0.78, 0.30],
	},
	{
		"id": "iron_ore",
		"display": "Iron Ore",
		"handling_mode": "bulk",
		"terminal_family": "bulk_ore",
		"mass_kg": 480.0,
		"value": 18,
		"max_pallet_units": 2,
		"color": [0.72, 0.32, 0.18],
	},
	{
		"id": "coal",
		"display": "Coal",
		"handling_mode": "bulk",
		"terminal_family": "bulk_ore",
		"mass_kg": 280.0,
		"value": 10,
		"max_pallet_units": 4,
		"color": [0.18, 0.18, 0.22],
	},
	{
		"id": "crude_oil",
		"display": "Crude Oil",
		"handling_mode": "liquid",
		"terminal_family": "liquid",
		"mass_kg": 850.0,
		"value": 22,
		"max_pallet_units": 1,
		"color": [0.32, 0.18, 0.08],
	},
	{
		"id": "diesel",
		"display": "Marine Diesel",
		"handling_mode": "liquid",
		"terminal_family": "liquid",
		"mass_kg": 820.0,
		"value": 28,
		"max_pallet_units": 1,
		"color": [0.88, 0.62, 0.10],
	},
	{
		"id": "lng",
		"display": "LNG",
		"handling_mode": "liquid",
		"terminal_family": "liquid",
		"mass_kg": 450.0,
		"value": 35,
		"max_pallet_units": 1,
		"color": [0.25, 0.82, 0.95],
	},
]

## Full trade pool for seeded port profiles (import/export slots).
const PLAYABLE_TRADE := [
	"fish", "timber", "provisions", "containers", "grain", "iron_ore", "coal",
	"crude_oil", "diesel", "lng",
]

## Display labels for terminal families (berth / yard / gear grouping).
const TERMINAL_FAMILY_DISPLAY := {
	"fishing": "Fish landing",
	"general": "General / pallet",
	"container": "Container",
	"bulk_ore": "Bulk ore / coal",
	"bulk_grain": "Bulk grain",
	"liquid": "Liquid jetty",
}

## Unused — pad exclusivity is enforced by berth_group_id (per commodity + role).
const EXCLUSIVE_PRODUCT_FAMILIES: Array[String] = []

const FISH_CRATE_BASE_GOLD := 500


static func fish_crate_value(zone_price_mul: float = 1.0) -> int:
	return maxi(int(round(float(FISH_CRATE_BASE_GOLD) * zone_price_mul)), 1)


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


## Berth / yard / equipment family for layout generation.
static func commodity_terminal_family(commodity_id: String) -> String:
	var info := commodity_info(commodity_id)
	if info.is_empty():
		return "general"
	if info.has("terminal_family"):
		return str(info["terminal_family"])
	return commodity_handling_mode(commodity_id)


## One dedicated pad per commodity direction.
## Containers alone share a single bidirectional pad (load + unload).
static func berth_group_id(commodity_id: String, role: String = "") -> String:
	var id := str(commodity_id)
	if id == "containers":
		return "pad:containers"
	var r := str(role)
	if r.is_empty():
		r = "trade"
	return "pad:%s:%s" % [id, r]


## Pads never share — iron export and coal import are different stations.
static func family_allows_shared_quay(_family: String) -> bool:
	return false


## Small apron cargo — no dedicated pier.
static func uses_asphalt_dock(commodity_id: String) -> bool:
	match str(commodity_id):
		"fish", "provisions":
			return true
		_:
			return false


## Deprecated alias — exclusivity is now per pad via berth_group_id.
static func is_exclusive_berth_commodity(_commodity_id: String) -> bool:
	return true


static func commodity_display(commodity_id: String) -> String:
	return str(commodity_info(commodity_id).get("display", commodity_id))


static func terminal_family_display(family: String) -> String:
	return str(TERMINAL_FAMILY_DISPLAY.get(family, family.replace("_", " ").capitalize()))


## Rough layout colour for a terminal family (quay tint when no commodity colour).
static func terminal_family_color(family: String) -> Color:
	match family:
		"fishing":
			return Color(0.22, 0.55, 0.68)
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
