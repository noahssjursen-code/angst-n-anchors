class_name CatchHoldState
extends RefCounted

## Serializable insulated-hold inventory. It never stores scene nodes.

signal changed(state: CatchHoldState)

var hold_id: String = ""
var capacity_kg: float = 0.0
var lots: Array[CatchLot] = []


func total_mass_kg() -> float:
	var total := 0.0
	for lot in lots:
		total += lot.mass_kg
	return total


func available_kg() -> float:
	return maxf(capacity_kg - total_mass_kg(), 0.0)


func fill_ratio() -> float:
	if capacity_kg <= CatchLot.MASS_EPS_KG:
		return 0.0
	return clampf(total_mass_kg() / capacity_kg, 0.0, 1.0)


func is_empty() -> bool:
	return total_mass_kg() <= CatchLot.MASS_EPS_KG


## Accepts as much as fits and returns an overflow lot.
func accept_lot(incoming: CatchLot) -> CatchLot:
	if incoming == null or incoming.is_empty():
		return CatchLot.new()
	var accepted_kg := minf(incoming.mass_kg, available_kg())
	if accepted_kg <= CatchLot.MASS_EPS_KG:
		return incoming.duplicate_lot()
	var accepted := incoming.duplicate_lot()
	accepted.mass_kg = accepted_kg
	var merged := false
	for existing in lots:
		if existing.merge_from(accepted):
			merged = true
			break
	if not merged:
		lots.append(accepted)
	changed.emit(self)
	var overflow_kg := incoming.mass_kg - accepted_kg
	if overflow_kg <= CatchLot.MASS_EPS_KG:
		return CatchLot.new()
	var overflow := incoming.duplicate_lot()
	overflow.mass_kg = overflow_kg
	return overflow


func withdraw_oldest(max_mass_kg: float) -> Array[CatchLot]:
	var remaining := maxf(max_mass_kg, 0.0)
	var out: Array[CatchLot] = []
	while remaining > CatchLot.MASS_EPS_KG and not lots.is_empty():
		var first := lots[0]
		var taken := first.split(remaining)
		if not taken.is_empty():
			out.append(taken)
			remaining -= taken.mass_kg
		if first.is_empty():
			lots.remove_at(0)
	if not out.is_empty():
		changed.emit(self)
	return out


func to_dict() -> Dictionary:
	var encoded: Array[Dictionary] = []
	for lot in lots:
		encoded.append(lot.to_dict())
	return {
		"hold_id": hold_id,
		"capacity_kg": capacity_kg,
		"lots": encoded,
	}


static func from_dict(data: Dictionary) -> CatchHoldState:
	var state := CatchHoldState.new()
	state.hold_id = str(data.get("hold_id", ""))
	state.capacity_kg = maxf(float(data.get("capacity_kg", 0.0)), 0.0)
	for raw in data.get("lots", []) as Array:
		if raw is not Dictionary:
			continue
		var lot := CatchLot.from_dict(raw as Dictionary)
		if lot.is_empty():
			continue
		var room := state.available_kg()
		if room <= CatchLot.MASS_EPS_KG:
			break
		lot.mass_kg = minf(lot.mass_kg, room)
		state.lots.append(lot)
	return state
