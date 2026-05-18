class_name CargoManifest
extends RefCounted

var capacity: int                = 100
var entries:  Array[CargoEntry]  = []


func total_units() -> int:
	var t := 0
	for e in entries:
		t += e.quantity
	return t


func has_space(amount: int = 1) -> bool:
	return total_units() + amount <= capacity


func to_dict() -> Dictionary:
	var arr: Array = []
	for e in entries:
		arr.append(e.to_dict())
	return { "capacity": capacity, "entries": arr }


static func from_dict(d: Dictionary) -> CargoManifest:
	var m      := CargoManifest.new()
	m.capacity = int(d.get("capacity", 100))
	m.entries  = []
	for ed in d.get("entries", []):
		m.entries.append(CargoEntry.from_dict(ed as Dictionary))
	return m
