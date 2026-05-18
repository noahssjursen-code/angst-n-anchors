class_name ShipData
extends RefCounted

var ship_id:      String       = ""
var display_name: String       = "Unnamed Vessel"
var hull_health:  float        = 1.0
var fuel:         float        = 1.0
var cargo:        CargoManifest = null


func to_dict() -> Dictionary:
	return {
		"ship_id":      ship_id,
		"display_name": display_name,
		"hull_health":  hull_health,
		"fuel":         fuel,
		"cargo":        cargo.to_dict() if cargo != null else {},
	}


static func from_dict(d: Dictionary) -> ShipData:
	var s          := ShipData.new()
	s.ship_id      = str(d.get("ship_id",      ""))
	s.display_name = str(d.get("display_name", "Unnamed Vessel"))
	s.hull_health  = float(d.get("hull_health", 1.0))
	s.fuel         = float(d.get("fuel",        1.0))
	var cd := d.get("cargo", {}) as Dictionary
	s.cargo        = CargoManifest.from_dict(cd) if not cd.is_empty() else null
	return s
