class_name BulkHoldState
extends RefCounted

## Serializable bulk-hold inventory. Sync this object in MP — not the scene node mesh.

signal changed(state: BulkHoldState)

var hold_id: String = ""
var commodity_id: String = ""
var consignment_id: String = ""
var capacity_tonnes_t: float = 0.0
var filled_tonnes_t: float = 0.0


func is_empty() -> bool:
	return filled_tonnes_t <= BulkCargoLot.TONNES_EPS


func available_tonnes_t() -> float:
	return maxf(capacity_tonnes_t - filled_tonnes_t, 0.0)


func fill_ratio() -> float:
	if capacity_tonnes_t <= BulkCargoLot.TONNES_EPS:
		return 0.0
	return clampf(filled_tonnes_t / capacity_tonnes_t, 0.0, 1.0)


func can_accept_commodity(commodity_id_in: String) -> bool:
	var cid := commodity_id_in.strip_edges()
	if cid.is_empty():
		return false
	if is_empty():
		return true
	return commodity_id == cid


func withdraw_tonnes(amount_t: float) -> BulkCargoLot:
	if is_empty() or amount_t <= BulkCargoLot.TONNES_EPS:
		return BulkCargoLot.empty()
	var taken := minf(amount_t, filled_tonnes_t)
	var cid := commodity_id
	var shipment := consignment_id
	filled_tonnes_t -= taken
	if filled_tonnes_t <= BulkCargoLot.TONNES_EPS:
		filled_tonnes_t = 0.0
		commodity_id = ""
		consignment_id = ""
	changed.emit(self)
	return BulkCargoLot.create(cid, taken, shipment)


## Returns overflow lot (empty when fully accepted).
func accept_lot(lot: BulkCargoLot) -> BulkCargoLot:
	if lot == null or lot.is_empty():
		return BulkCargoLot.empty()
	if not can_accept_commodity(lot.commodity_id) or (not is_empty() and consignment_id != lot.consignment_id):
		return lot.duplicate_lot()
	var free_t := available_tonnes_t()
	if free_t <= BulkCargoLot.TONNES_EPS:
		return lot.duplicate_lot()
	var accepted := minf(lot.tonnes_t, free_t)
	if is_empty():
		commodity_id = lot.commodity_id
		consignment_id = lot.consignment_id
	filled_tonnes_t += accepted
	changed.emit(self)
	var overflow_t := lot.tonnes_t - accepted
	if overflow_t <= BulkCargoLot.TONNES_EPS:
		return BulkCargoLot.empty()
	return BulkCargoLot.create(lot.commodity_id, overflow_t, lot.consignment_id)


func to_dict() -> Dictionary:
	return {
		"hold_id": hold_id,
		"commodity_id": commodity_id,
		"consignment_id": consignment_id,
		"capacity_tonnes_t": capacity_tonnes_t,
		"filled_tonnes_t": filled_tonnes_t,
	}


static func from_dict(data: Dictionary) -> BulkHoldState:
	var state := BulkHoldState.new()
	state.hold_id = str(data.get("hold_id", ""))
	state.commodity_id = str(data.get("commodity_id", ""))
	state.consignment_id = str(data.get("consignment_id", ""))
	state.capacity_tonnes_t = maxf(float(data.get("capacity_tonnes_t", 0.0)), 0.0)
	state.filled_tonnes_t = clampf(
		float(data.get("filled_tonnes_t", 0.0)),
		0.0,
		state.capacity_tonnes_t,
	)
	return state
