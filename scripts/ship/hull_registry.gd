class_name HullRegistry
extends RefCounted

## Vessel catalog. Hand-authored scenes plus data-driven hulls from HullCatalog.
## Legacy hull ids still resolve so old saves / network packets keep working.

const TRAWLER_SMALL_SCENE := "res://scenes/vessels/fishing_trawler_small.tscn"
const PASSENGER_CATAMARAN_SCENE := "res://scenes/vessels/passenger_catamaran.tscn"
const _TRAWLER_SMALL_SCRIPT := preload("res://scripts/ship/vessels/fishing_trawler_small.gd")
const _PASSENGER_CATAMARAN_SCRIPT := preload("res://scripts/ship/vessels/passenger_catamaran.gd")
const _CATALOG_HULL_SCRIPT := preload("res://scripts/ship/vessels/catalog_hull_vessel.gd")

const FISHING_TRAWLER_SMALL := {
	"id": "hull_28x10",
	"display": "28.0 × 10.0 m",
	"ship_class": ShipClass.Type.COASTAL_TRADER,
	"scene_path": TRAWLER_SMALL_SCENE,
	"default_shaft_power_kw": 1871.0,
	"displacement_t": 256.0,
	"loa_m": 28.0,
	"beam_m": 10.0,
	"depth_m": 5.6,
}

const PASSENGER_CATAMARAN := {
	"id": "hull_45x16_cat",
	"display": "45.0 × 16.0 m · catamaran",
	"ship_class": ShipClass.Type.SHORT_SEA_COASTER,
	"scene_path": PASSENGER_CATAMARAN_SCENE,
	"default_shaft_power_kw": 65000.0,
	"displacement_t": 520.0,
	"loa_m": 45.0,
	"beam_m": 16.0,
	"depth_m": 5.5,
}

## Old hull ids from the deleted fleet — map to a live hull, never listed in catalog.
const LEGACY_ID_ALIASES: Dictionary = {
	"workboat": "hull_28x10",
	"fishing_trawler_small": "hull_28x10",
	"fishing_trawler_medium": "hull_28x10",
	"fishing_trawler_large": "hull_28x10",
	"cargo_ship": "hull_90x24",
	"cargo_ship_small": "hull_90x24",
	"cargo_ship_medium": "hull_120x28",
	"cargo_ship_large": "hull_150x32",
	"cargo_ship_huge": "hull_150x32",
	"cargo_ship_ultra": "hull_150x32",
	"liquid_tanker": "hull_100x24",
	"liquid_tanker_small": "hull_70x18",
	"liquid_tanker_large": "hull_130x28",
	"liquid_tanker_huge": "hull_130x28",
	"liquid_tanker_ultra": "hull_130x28",
	"container_ship_small": "hull_90x24",
	"container_ship_medium": "hull_120x28",
	"container_ship_large": "hull_150x32",
	"container_ship_ultra": "hull_150x32",
	"container_feeder_small": "hull_90x24",
	"container_feeder_mid": "hull_120x28",
	"container_short_sea": "hull_150x32",
	"tanker_coastal": "hull_70x18",
	"tanker_product": "hull_100x24",
	"tanker_lng": "hull_130x28",
	"passenger_catamaran": "hull_45x16_cat",
	"ferry": "hull_45x16_cat",
	"ferry_small": "hull_45x16_cat",
	"ferry_large": "hull_45x16_cat",
	"fishing_boat": "hull_28x10",
	"fishing_boat_small": "hull_28x10",
	"fishing_boat_large": "hull_28x10",
}


static func catalog() -> Array[Dictionary]:
	var entries: Array[Dictionary] = [
		FISHING_TRAWLER_SMALL.duplicate(true),
		PASSENGER_CATAMARAN.duplicate(true),
	]
	for entry in HullCatalog.catalog_entries():
		entries.append(entry)
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var loa_a := float(a.get("loa_m", 0.0))
		var loa_b := float(b.get("loa_m", 0.0))
		if is_equal_approx(loa_a, loa_b):
			return str(a.get("id", "")) < str(b.get("id", ""))
		return loa_a < loa_b
	)
	return entries


static func get_by_id(hull_id: String) -> Dictionary:
	var id := resolve_network_hull_id(hull_id)
	if HullCatalog.has_id(id):
		return HullCatalog.get_by_id(id)
	match id:
		"hull_28x10":
			return FISHING_TRAWLER_SMALL.duplicate(true)
		"hull_45x16_cat":
			return PASSENGER_CATAMARAN.duplicate(true)
		_:
			return FISHING_TRAWLER_SMALL.duplicate(true)


static func get_by_file(_filename: String) -> Dictionary:
	return FISHING_TRAWLER_SMALL.duplicate(true)


static func resolve_id_from_template(template_path: String, fallback: String = "fishing_trawler_small") -> String:
	var path := template_path.strip_edges()
	if path.contains("passenger_catamaran"):
		return "hull_45x16_cat"
	if path.contains("fishing_trawler_small"):
		return "hull_28x10"
	if path.contains("workboat"):
		return "hull_28x10"
	return resolve_network_hull_id(fallback)


static func resolve_network_hull_id(hull_id: String) -> String:
	var id := hull_id.strip_edges()
	if id.is_empty():
		return "hull_28x10"
	if HullCatalog.has_id(id):
		return id
	if id == "hull_28x10" or id == "hull_45x16_cat":
		return id
	if LEGACY_ID_ALIASES.has(id):
		return str(LEGACY_ID_ALIASES[id])
	return "hull_28x10"


static func hull_id_from_network_type(network_type: String) -> String:
	if network_type.begins_with("ship_"):
		return resolve_network_hull_id(network_type.substr(5))
	return resolve_network_hull_id(network_type)


static func scene_path_for(hull_id: String) -> String:
	var entry := get_by_id(hull_id)
	return str(entry.get("scene_path", TRAWLER_SMALL_SCENE))


static func is_known_hull(hull_id: String) -> bool:
	var id := resolve_network_hull_id(hull_id)
	if HullCatalog.has_id(id):
		return true
	return id == "hull_28x10" or id == "hull_45x16_cat"


static func make_grid(hull_id: String) -> DeckGrid:
	var id := resolve_network_hull_id(hull_id)
	if HullCatalog.has_id(id):
		return _CATALOG_HULL_SCRIPT.make_grid(id)
	match id:
		"hull_28x10":
			return _TRAWLER_SMALL_SCRIPT.make_grid()
		"hull_45x16_cat":
			return _PASSENGER_CATAMARAN_SCRIPT.make_grid()
		_:
			return _TRAWLER_SMALL_SCRIPT.make_grid()


static func build_hull(hull_id: String) -> BoatBody:
	var id := resolve_network_hull_id(hull_id)
	if HullCatalog.has_id(id):
		return _CATALOG_HULL_SCRIPT.build(id) as BoatBody
	match id:
		"hull_28x10":
			return _TRAWLER_SMALL_SCRIPT.build() as BoatBody
		"hull_45x16_cat":
			return _PASSENGER_CATAMARAN_SCRIPT.build() as BoatBody
		_:
			return _TRAWLER_SMALL_SCRIPT.build() as BoatBody


static func has_capability(_hull_id: String, _capability: String) -> bool:
	## Hulls are geometry components. Gameplay capabilities come from fit-out bricks.
	return false


## Prefer this for owned vessels — capabilities come from the fit-out.
##
## ── IT READS BOTH CONSTRUCTION PATHS, and it used to read one ───────────────
##
## A vessel record's `brick_layout` field holds whichever document drew it, and
## for a Structure Studio ship that is a `structure_plan_v1`. This used to run
## `BrickLayout.from_dict` on it unconditionally, and that yields an EMPTY
## layout — the exact failure `VesselSpawn.resolve_deployable_record` carries a
## paragraph about, which is why the routing lives in
## `DeckFitout.compliance_for_layout` rather than being re-decided per caller.
## So every capability of every plan-built vessel answered false here, and
## "cabin" would have gone on answering false after `PlanOutfit.has_cabin`
## started measuring enclosure.
##
## **This function has no callers outside this file** (grepped 2026-08-16), so
## nothing was observably broken by that and nothing is observably fixed by this
## — REALITY.md §3d. It is repaired rather than deleted because the two halves of
## the split are `has_capability` above (hulls carry no capabilities) and this
## one, and a wrong answer sitting in the pair is a trap for whoever wires the
## first caller.
## `DeckFitout.compliance_for_layout` is the one place that decides which of the
## two documents a `brick_layout` field holds, and re-deciding it here would be
## the second derivation this project keeps fixing (REALITY.md §3b) — so it is
## called rather than copied. Naming `DeckFitout` here costs nothing measurable:
## `plan_compliance_test` runs green in the `--script` lane on **33 script
## errors** with this line and **33** without it, exit 0 both ways. (It first
## looked like it cost a compile: `vessel_registration_test` died on
## *"Identifier not found: WorldGateway"*. That test is LANE B and had been run
## in lane A — CONVENTIONS §1's "check the lane before diagnosing the failure",
## and REALITY.md §8's instrument, one more time.)
static func record_has_capability(record: Dictionary, capability: String) -> bool:
	var cap := capability.strip_edges()
	var hull_id := str(record.get("hull_id", "fishing_trawler_small"))
	var report: Dictionary = DeckFitout.compliance_for_layout(
		VesselSpawn.brick_layout_of(record), hull_id, str(record.get("registration_id", "")),
		make_grid(hull_id)
	)
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
			return bool(caps.get("has_fishing", false))
		_:
			return has_capability(hull_id, cap)
