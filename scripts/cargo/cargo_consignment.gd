class_name CargoConsignment
extends RefCounted

## Transport-neutral, JSON-safe cargo authority record. In multiplayer the
## server can issue this payload and remain authoritative over revisions/status.

const SCHEMA_VERSION := 1

var consignment_id := ""
var contract_id := ""
var commodity_id := ""
var handling_mode := ""
var origin_port_id := ""
var destination_port_id := ""
var quantity := 0.0
var quantity_unit := "units"
var delivery_value_marks := 0
var assigned_vessel_uid := ""
var status := "booked"
var authority_revision := 0


static func from_contract(contract: Dictionary) -> CargoConsignment:
	var record := CargoConsignment.new()
	record.contract_id = str(contract.get("id", ""))
	record.consignment_id = str(contract.get("consignment_id", ""))
	if record.consignment_id.is_empty():
		record.consignment_id = "consignment:%s" % record.contract_id
	record.commodity_id = str(contract.get("commodity_id", ""))
	record.handling_mode = str(contract.get("handling_mode", ""))
	record.origin_port_id = str(contract.get("origin_port_id", ""))
	record.destination_port_id = str(contract.get("destination_port_id", ""))
	record.quantity = maxf(float(contract.get("quantity", 0.0)), 0.0)
	record.quantity_unit = str(contract.get("quantity_unit", "units"))
	record.delivery_value_marks = maxi(int(contract.get("pay_marks", 0)), 0)
	record.assigned_vessel_uid = str(contract.get("vessel_uid", ""))
	return record


func to_dict() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"consignment_id": consignment_id,
		"contract_id": contract_id,
		"commodity_id": commodity_id,
		"handling_mode": handling_mode,
		"origin_port_id": origin_port_id,
		"destination_port_id": destination_port_id,
		"quantity": quantity,
		"quantity_unit": quantity_unit,
		"delivery_value_marks": delivery_value_marks,
		"assigned_vessel_uid": assigned_vessel_uid,
		"status": status,
		"authority_revision": authority_revision,
	}


static func from_dict(data: Dictionary) -> CargoConsignment:
	var record := CargoConsignment.new()
	record.consignment_id = str(data.get("consignment_id", ""))
	record.contract_id = str(data.get("contract_id", ""))
	record.commodity_id = str(data.get("commodity_id", ""))
	record.handling_mode = str(data.get("handling_mode", ""))
	record.origin_port_id = str(data.get("origin_port_id", ""))
	record.destination_port_id = str(data.get("destination_port_id", ""))
	record.quantity = maxf(float(data.get("quantity", 0.0)), 0.0)
	record.quantity_unit = str(data.get("quantity_unit", "units"))
	record.delivery_value_marks = maxi(int(data.get("delivery_value_marks", 0)), 0)
	record.assigned_vessel_uid = str(data.get("assigned_vessel_uid", ""))
	record.status = str(data.get("status", "booked"))
	record.authority_revision = maxi(int(data.get("authority_revision", 0)), 0)
	return record
