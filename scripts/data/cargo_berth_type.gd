class_name CargoBerthType
extends RefCounted

## Cargo handling type for a berth slot.
## Determines crane shape, accepted cargo, and eventually what ships can load/unload there.

enum Type {
	GENERAL   = 0,  ## Derrick crane — crates, pallets, break-bulk timber
	BULK      = 1,  ## Grab/bucket crane — coal, iron ore, grain
	CONTAINER = 2,  ## Gantry portal crane — ISO containers
}

const DISPLAY_NAME: Dictionary = {
	Type.GENERAL:   "General Cargo",
	Type.BULK:      "Bulk Cargo",
	Type.CONTAINER: "Container",
}

## Crane accent color per type.
const CRANE_COLOR: Dictionary = {
	Type.GENERAL:   Color(0.22, 0.48, 0.82),   # steel blue
	Type.BULK:      Color(0.62, 0.32, 0.12),   # rust brown
	Type.CONTAINER: Color(0.90, 0.58, 0.08),   # port orange
}

static func display_name(type: Type) -> String:
	return str(DISPLAY_NAME.get(type, "Unknown"))

static func crane_color(type: Type) -> Color:
	return CRANE_COLOR.get(type, Color(0.22, 0.48, 0.82)) as Color
