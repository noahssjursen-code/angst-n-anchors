class_name VesselRole
extends RefCounted

## Vessel functional role. Gates which contracts the vessel can accept,
## who sells the vessel, and what HUD overlays are shown.

enum Type {
	CARGO     = 0,  ## Freight, bulk cargo
	FISHING   = 1,  ## Inshore skiffs, deep-sea trawlers
	PASSENGER = 2,  ## Small ferries, water taxis
	TANKER    = 3,  ## Liquid tankers (fuel, water, chemicals)
	CONTAINER = 4,  ## Container carrier
}

static func display_name(type: Type) -> String:
	match type:
		Type.CARGO:     return "Cargo Freighter"
		Type.FISHING:   return "Fishing Vessel"
		Type.PASSENGER: return "Passenger Ferry"
		Type.TANKER:    return "Liquid Tanker"
		Type.CONTAINER: return "Container Carrier"
		_:              return "Unknown Role"
