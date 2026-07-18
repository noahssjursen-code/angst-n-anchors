class_name BulkCargoLot
extends RefCounted

## Serializable bulk commodity quantity. MP-safe payload for bucket drops and holds.

const TONNES_EPS := 0.01

var commodity_id: String = ""
var tonnes_t: float = 0.0
var consignment_id: String = ""


static func empty() -> BulkCargoLot:
	return BulkCargoLot.new()


static func create(commodity_id_in: String, tonnes_t_in: float, consignment_id_in: String = "") -> BulkCargoLot:
	var lot := BulkCargoLot.new()
	lot.commodity_id = commodity_id_in.strip_edges()
	lot.tonnes_t = maxf(tonnes_t_in, 0.0)
	lot.consignment_id = consignment_id_in.strip_edges()
	return lot


func is_empty() -> bool:
	return commodity_id.is_empty() or tonnes_t <= TONNES_EPS


func duplicate_lot() -> BulkCargoLot:
	return BulkCargoLot.create(commodity_id, tonnes_t, consignment_id)


func clamp_to(max_tonnes_t: float) -> BulkCargoLot:
	return BulkCargoLot.create(commodity_id, minf(tonnes_t, maxf(max_tonnes_t, 0.0)), consignment_id)


func take_tonnes(amount_t: float) -> BulkCargoLot:
	var taken := clampf(amount_t, 0.0, tonnes_t)
	tonnes_t -= taken
	if tonnes_t <= TONNES_EPS:
		tonnes_t = 0.0
		if taken <= TONNES_EPS:
			commodity_id = ""
	return BulkCargoLot.create(commodity_id if taken > TONNES_EPS else commodity_id, taken, consignment_id)


func merge_from(other: BulkCargoLot) -> BulkCargoLot:
	if other == null or other.is_empty():
		return BulkCargoLot.empty()
	if is_empty():
		commodity_id = other.commodity_id
		tonnes_t = other.tonnes_t
		consignment_id = other.consignment_id
		return BulkCargoLot.empty()
	if commodity_id != other.commodity_id or consignment_id != other.consignment_id:
		return other.duplicate_lot()
	tonnes_t += other.tonnes_t
	return BulkCargoLot.empty()


func to_dict() -> Dictionary:
	return {
		"commodity_id": commodity_id,
		"tonnes_t": tonnes_t,
		"consignment_id": consignment_id,
	}


static func from_dict(data: Dictionary) -> BulkCargoLot:
	return BulkCargoLot.create(
		str(data.get("commodity_id", "")),
		float(data.get("tonnes_t", 0.0)),
		str(data.get("consignment_id", "")),
	)
