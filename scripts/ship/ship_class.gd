class_name ShipClass
extends RefCounted

## Ship size classification. Used by PortDock to enforce max vessel size
## and calculate how many berths are available for a given class.

enum Type {
	LAUNCH             = 0,  ## < 10 m  — tenders, pilot boats, small ferries
	COASTAL_TRADER     = 1,  ## 10–30 m — small cargo coasters, fishing vessels
	SHORT_SEA_COASTER  = 2,  ## 30–60 m — inter-island and coastal dry cargo
	HANDYSIZE_FEEDER   = 3,  ## 60–100 m — regional feeder cargo ships
	DEEP_SEA_FREIGHTER = 4,  ## 100 m+  — ocean-going bulk and general cargo
}

## Game-scale maximum length (m) per class. Sized so the player's coastal trader
## (~13 m hull) fits naturally and multiple berths appear at each port size.
const MAX_LENGTH_M: Dictionary = {
	Type.LAUNCH:              5.0,
	Type.COASTAL_TRADER:     15.0,
	Type.SHORT_SEA_COASTER:  25.0,
	Type.HANDYSIZE_FEEDER:   40.0,
	Type.DEEP_SEA_FREIGHTER: 60.0,
}

## Typical beam (m) — sets how far berth indicators extend into the water.
const BEAM_M: Dictionary = {
	Type.LAUNCH:              2.0,
	Type.COASTAL_TRADER:      3.5,
	Type.SHORT_SEA_COASTER:   5.5,
	Type.HANDYSIZE_FEEDER:    8.0,
	Type.DEEP_SEA_FREIGHTER: 11.0,
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

static func cargo_cells(type: Type) -> int:
	return int(CARGO_CELLS.get(type, 4))

static func max_length(type: Type) -> float:
	return float(MAX_LENGTH_M.get(type, 10.0))

static func beam(type: Type) -> float:
	return float(BEAM_M.get(type, 3.0))

static func display_name(type: Type) -> String:
	return str(DISPLAY_NAME.get(type, "Unknown"))

## Returns true if ship_type is small enough to dock at a port with dock_max.
static func fits(ship_type: Type, dock_max: Type) -> bool:
	return int(ship_type) <= int(dock_max)

## How many ships of ship_type fit along a dock of dock_length_m, with a gap between each.
static func berth_count(dock_length_m: float, ship_type: Type, gap_m: float = 3.0) -> int:
	var slot := max_length(ship_type) + gap_m
	return maxi(1, int(dock_length_m / slot))
