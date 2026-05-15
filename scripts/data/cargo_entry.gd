class_name CargoEntry
extends RefCounted

var cargo_type_id: String = ""
var display_name:  String = ""
var quantity:      int    = 0


func to_dict() -> Dictionary:
	return {
		"cargo_type_id": cargo_type_id,
		"display_name":  display_name,
		"quantity":      quantity,
	}


static func from_dict(d: Dictionary) -> CargoEntry:
	var e           := CargoEntry.new()
	e.cargo_type_id = str(d.get("cargo_type_id", ""))
	e.display_name  = str(d.get("display_name",  ""))
	e.quantity      = int(d.get("quantity",       0))
	return e
