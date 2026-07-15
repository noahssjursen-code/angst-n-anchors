class_name ShipClass
extends RefCounted

## Ship size classification used by port metadata and vessel systems.

enum Type {
	LAUNCH             = 0,  ## < 10 m  — tenders, pilot boats, small ferries
	COASTAL_TRADER     = 1,  ## 10–30 m — small cargo coasters, fishing vessels
	SHORT_SEA_COASTER  = 2,  ## 30–60 m — inter-island and coastal dry cargo
	HANDYSIZE_FEEDER   = 3,  ## 60–100 m — regional feeder cargo ships
	DEEP_SEA_FREIGHTER = 4,  ## 100 m+  — ocean-going bulk and general cargo
}

## Catalog length/beam are authored in "actual" metres. World hulls and berth
## clearances use 2× those values (a 5 m beam ship occupies 10 m in world space).
const METRIC_SCALE := 2.0

## Authored maximum length (m) per class — multiply by METRIC_SCALE for world space.
const MAX_LENGTH_M: Dictionary = {
	Type.LAUNCH:              10.0,
	Type.COASTAL_TRADER:     35.0,
	Type.SHORT_SEA_COASTER:  50.0,
	Type.HANDYSIZE_FEEDER:  120.0,
	Type.DEEP_SEA_FREIGHTER: 160.0,
}

## Authored typical beam (m) — multiply by METRIC_SCALE for world space.
const BEAM_M: Dictionary = {
	Type.LAUNCH:              4.0,
	Type.COASTAL_TRADER:     24.0,
	Type.SHORT_SEA_COASTER:  14.0,
	Type.HANDYSIZE_FEEDER:   28.0,
	Type.DEEP_SEA_FREIGHTER: 32.0,
}

const DISPLAY_NAME: Dictionary = {
	Type.LAUNCH:             "Launch / Tender",
	Type.COASTAL_TRADER:     "Coastal Trader",
	Type.SHORT_SEA_COASTER:  "Short Sea Coaster",
	Type.HANDYSIZE_FEEDER:   "Handysize Feeder",
	Type.DEEP_SEA_FREIGHTER: "Deep Sea Freighter",
}

## Indicative cargo grid cells a ship of this class is built to hold. Used by
## the ContractNpc UI to show "X cells free / Y needed" before accepting.
## Actual capacity comes from the ship's CargoDeckComponent(s); this is just
## an upper-bound hint when no boat is currently berthed.
const CARGO_CELLS: Dictionary = {
	Type.LAUNCH:              2,
	Type.COASTAL_TRADER:      8,
	Type.SHORT_SEA_COASTER:  20,
	Type.HANDYSIZE_FEEDER:   48,
	Type.DEEP_SEA_FREIGHTER: 96,
}

## Minimum crew slots required before a vessel can run autonomously.
const CREW_SLOTS: Dictionary = {
	Type.LAUNCH:              2,
	Type.COASTAL_TRADER:      3,
	Type.SHORT_SEA_COASTER:   5,
	Type.HANDYSIZE_FEEDER:    8,
	Type.DEEP_SEA_FREIGHTER: 12,
}

static func crew_slots(type: Type) -> int:
	return int(CREW_SLOTS.get(type, 3))


static func cargo_cells(type: Type) -> int:
	return int(CARGO_CELLS.get(type, 4))

static func max_length(type: Type) -> float:
	return float(MAX_LENGTH_M.get(type, 10.0))

static func beam(type: Type) -> float:
	return float(BEAM_M.get(type, 3.0))

## World-space length/beam (authored × METRIC_SCALE). Use for berths, fairways,
## and anything that must clear a live hull mesh.
static func world_max_length(type: Type) -> float:
	return max_length(type) * METRIC_SCALE

static func world_beam(type: Type) -> float:
	return beam(type) * METRIC_SCALE

## @deprecated: use world_max_length
static func physical_max_length(type: Type) -> float:
	return world_max_length(type)

## @deprecated: use world_beam
static func physical_beam(type: Type) -> float:
	return world_beam(type)

static func display_name(type: Type) -> String:
	return str(DISPLAY_NAME.get(type, "Unknown"))

## Returns true if ship_type is small enough to dock at a port with dock_max.
static func fits(ship_type: Type, dock_max: Type) -> bool:
	return int(ship_type) <= int(dock_max)

## How many ships of ship_type fit along a dock of dock_length_m, with a gap between each.
static func berth_count(dock_length_m: float, ship_type: Type, gap_m: float = 3.0) -> int:
	var slot := max_length(ship_type) + gap_m
	return maxi(1, int(dock_length_m / slot))
