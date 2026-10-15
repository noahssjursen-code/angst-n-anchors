extends RefCounted

## Presentation policy for this world's fixed construction plane. The reusable
## scene-free port state may describe another world's explicit vertical datum.
const DECK_HEIGHT_ABOVE_SEA_M := 2.0

static func validate_deck_plane(snapshot: Dictionary) -> Dictionary:
	# Called after CustomPortState validation, before installing any projections.
	var height:=float(snapshot.deck_height_above_sea_m)
	var deck_y:=float(snapshot.origin_m[1])
	if absf(height-DECK_HEIGHT_ABOVE_SEA_M)>.00001 or absf(deck_y-(WaveSurface.WATER_LEVEL+DECK_HEIGHT_ABOVE_SEA_M))>.00001:
		return {"ok":false,"code":"incompatible_deck_plane","errors":["This world builds on one plane, 2 m above sea level."]}
	return {"ok":true,"code":"compatible_deck_plane"}
