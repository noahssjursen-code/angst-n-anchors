class_name OperationsRecords
extends RefCounted

## JSON-safe company operations records. CompanyService is the authority.
## These helpers only shape and check documents.

const SCHEMA_VERSION := 1
const ACTIVITY_LIMIT := 40

const DELIVERY_FLOW := ["booked", "loading", "underway", "berthed", "delivered"]

## IALA-A cardinal marks. Colour codes are top to bottom.
const CARDINAL_MARKS := [
	{"code": "BY", "name": "North cardinal", "colours": "Black over yellow", "safe_water": "North of the mark"},
	{"code": "BYB", "name": "East cardinal", "colours": "Black, yellow, black", "safe_water": "East of the mark"},
	{"code": "YB", "name": "South cardinal", "colours": "Yellow over black", "safe_water": "South of the mark"},
	{"code": "YBY", "name": "West cardinal", "colours": "Yellow, black, yellow", "safe_water": "West of the mark"},
]


static func crew_member(
	crew_id: String,
	company_id: String,
	display_name: String,
	role: String,
	qualification: String,
	wage_nok_per_day: int,
	timestamp: int,
) -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"id": crew_id,
		"company_id": company_id,
		"display_name": display_name.strip_edges(),
		"role": role.strip_edges(),
		"qualification": qualification.strip_edges(),
		"wage_nok_per_day": maxi(wage_nok_per_day, 0),
		"availability": "available",
		"vessel_uid": "",
		"hired_at_unix": timestamp,
		"status": "active",
	}


static func route_plan(
	route_id: String,
	company_id: String,
	vessel_uid: String,
	origin_port_id: String,
	destination_port_id: String,
	commodity_id: String,
) -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"id": route_id,
		"company_id": company_id,
		"vessel_uid": vessel_uid,
		"origin_port_id": origin_port_id,
		"destination_port_id": destination_port_id,
		"commodity_id": commodity_id,
		"crew_ids": [],
		"status": "draft",
		"funded": false,
	}


static func delivery(
	delivery_id: String,
	company_id: String,
	contract_id: String,
	consignment_id: String,
	vessel_uid: String,
	origin_port_id: String,
	destination_port_id: String,
	commodity_id: String,
	pay_nok: int,
	timestamp: int,
) -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"id": delivery_id,
		"company_id": company_id,
		"contract_id": contract_id,
		"consignment_id": consignment_id,
		"vessel_uid": vessel_uid,
		"origin_port_id": origin_port_id,
		"destination_port_id": destination_port_id,
		"commodity_id": commodity_id,
		"pay_nok": maxi(pay_nok, 0),
		"status": "booked",
		"settled": false,
		"diesel_nok": 0,
		"maintenance_nok": 0,
		"wages_nok": 0,
		"opened_at_unix": timestamp,
		"events": [],
	}


static func facility(
	facility_id: String,
	company_id: String,
	kind: String,
	display_name: String,
	site_id: String,
	price_nok: int,
	upkeep_nok_per_day: int,
	timestamp: int,
) -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"id": facility_id,
		"company_id": company_id,
		"kind": kind,
		"display_name": display_name.strip_edges(),
		"site_id": site_id,
		"price_nok": maxi(price_nok, 0),
		"upkeep_nok_per_day": maxi(upkeep_nok_per_day, 0),
		"worker_ids": [],
		"stored_quantity": 0.0,
		"capacity_units": 0.0,
		"status": "owned",
		"acquired_at_unix": timestamp,
	}


static func activity_entry(
	entry_id: String,
	company_id: String,
	kind: String,
	summary: String,
	related_entity_id: String,
	timestamp: int,
) -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"id": entry_id,
		"company_id": company_id,
		"kind": kind,
		"summary": summary,
		"related_entity_id": related_entity_id,
		"created_at_unix": timestamp,
	}


static func voyage_account(revenue_nok: int, diesel_nok: int, maintenance_nok: int, wages_nok: int) -> Dictionary:
	var revenue := maxi(revenue_nok, 0)
	var diesel := maxi(diesel_nok, 0)
	var maintenance := maxi(maintenance_nok, 0)
	var wages := maxi(wages_nok, 0)
	return {
		"currency": "NOK",
		"revenue_nok": revenue,
		"diesel_nok": diesel,
		"maintenance_nok": maintenance,
		"wages_nok": wages,
		"net_nok": revenue - diesel - maintenance - wages,
	}


static func wages_nok(crew: Array, days: int) -> int:
	var total := 0
	var span := maxi(days, 0)
	for raw in crew:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var member := raw as Dictionary
		if str(member.get("status", "")) != "active":
			continue
		total += maxi(int(member.get("wage_nok_per_day", 0)), 0) * span
	return total


static func can_advance_delivery(current: String, target: String) -> bool:
	if target == "failed":
		return current != "delivered" and current != "failed"
	var from_index := DELIVERY_FLOW.find(current)
	var to_index := DELIVERY_FLOW.find(target)
	return from_index >= 0 and to_index == from_index + 1


static func fleet_postings(vessels: Array, crew: Array, active_uid: String) -> Array:
	var out: Array = []
	for raw in vessels:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var vessel := raw as Dictionary
		var uid := str(vessel.get("uid", ""))
		var assigned: Array = []
		for member_raw in crew:
			if typeof(member_raw) != TYPE_DICTIONARY:
				continue
			var member := member_raw as Dictionary
			if str(member.get("status", "")) == "active" and str(member.get("vessel_uid", "")) == uid:
				assigned.append(str(member.get("id", "")))
		var status := "idle"
		if uid == active_uid and not uid.is_empty():
			status = "commanded"
		elif not assigned.is_empty():
			status = "assigned"
		out.append({
			"uid": uid,
			"name": str(vessel.get("name", vessel.get("display", "Vessel"))),
			"hull_id": str(vessel.get("hull_id", "")),
			"asset_kind": "unique_vessel",
			"status": status,
			"crew_ids": assigned,
			"engine_hours": float(vessel.get("engine_hours", 0.0)),
		})
	return out


static func normalize_crew(raw: Variant) -> Array:
	return _normalize_list(raw, "crew")


static func normalize_routes(raw: Variant) -> Array:
	return _normalize_list(raw, "route")


static func normalize_deliveries(raw: Variant) -> Array:
	return _normalize_list(raw, "delivery")


static func normalize_facilities(raw: Variant) -> Array:
	return _normalize_list(raw, "facility")


static func normalize_activity(raw: Variant) -> Array:
	var entries := _normalize_list(raw, "activity")
	if entries.size() > ACTIVITY_LIMIT:
		return entries.slice(entries.size() - ACTIVITY_LIMIT)
	return entries


static func _normalize_list(raw: Variant, kind: String) -> Array:
	if typeof(raw) != TYPE_ARRAY:
		return []
	var out: Array = []
	for item in raw as Array:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var entry := (item as Dictionary).duplicate(true)
		entry["schema_version"] = SCHEMA_VERSION
		entry["id"] = str(entry.get("id", ""))
		entry["company_id"] = str(entry.get("company_id", ""))
		if str(entry.get("id", "")).is_empty():
			continue
		out.append(_shape(kind, entry))
	return out


static func _shape(kind: String, entry: Dictionary) -> Dictionary:
	match kind:
		"crew":
			entry["display_name"] = str(entry.get("display_name", "")).strip_edges()
			entry["role"] = str(entry.get("role", "deck"))
			entry["qualification"] = str(entry.get("qualification", ""))
			entry["wage_nok_per_day"] = maxi(int(entry.get("wage_nok_per_day", 0)), 0)
			entry["availability"] = str(entry.get("availability", "available"))
			entry["vessel_uid"] = str(entry.get("vessel_uid", ""))
			entry["status"] = str(entry.get("status", "active"))
			entry["hired_at_unix"] = int(entry.get("hired_at_unix", 0))
		"route":
			entry["vessel_uid"] = str(entry.get("vessel_uid", ""))
			entry["origin_port_id"] = str(entry.get("origin_port_id", ""))
			entry["destination_port_id"] = str(entry.get("destination_port_id", ""))
			entry["commodity_id"] = str(entry.get("commodity_id", ""))
			if typeof(entry.get("crew_ids", [])) != TYPE_ARRAY:
				entry["crew_ids"] = []
			entry["status"] = str(entry.get("status", "draft"))
			entry["funded"] = bool(entry.get("funded", false))
		"delivery":
			entry["contract_id"] = str(entry.get("contract_id", ""))
			entry["consignment_id"] = str(entry.get("consignment_id", ""))
			entry["vessel_uid"] = str(entry.get("vessel_uid", ""))
			entry["origin_port_id"] = str(entry.get("origin_port_id", ""))
			entry["destination_port_id"] = str(entry.get("destination_port_id", ""))
			entry["commodity_id"] = str(entry.get("commodity_id", ""))
			entry["pay_nok"] = maxi(int(entry.get("pay_nok", entry.get("pay_marks", 0))), 0)
			entry["status"] = str(entry.get("status", "booked"))
			entry["settled"] = bool(entry.get("settled", false))
			entry["diesel_nok"] = maxi(int(entry.get("diesel_nok", 0)), 0)
			entry["maintenance_nok"] = maxi(int(entry.get("maintenance_nok", 0)), 0)
			entry["wages_nok"] = maxi(int(entry.get("wages_nok", 0)), 0)
			entry["opened_at_unix"] = int(entry.get("opened_at_unix", 0))
			if typeof(entry.get("events", [])) != TYPE_ARRAY:
				entry["events"] = []
		"facility":
			entry["kind"] = str(entry.get("kind", "fish_farm"))
			entry["display_name"] = str(entry.get("display_name", "")).strip_edges()
			entry["site_id"] = str(entry.get("site_id", ""))
			entry["price_nok"] = maxi(int(entry.get("price_nok", 0)), 0)
			entry["upkeep_nok_per_day"] = maxi(int(entry.get("upkeep_nok_per_day", 0)), 0)
			if typeof(entry.get("worker_ids", [])) != TYPE_ARRAY:
				entry["worker_ids"] = []
			entry["stored_quantity"] = maxf(float(entry.get("stored_quantity", 0.0)), 0.0)
			entry["capacity_units"] = maxf(float(entry.get("capacity_units", 0.0)), 0.0)
			entry["status"] = str(entry.get("status", "owned"))
			entry["acquired_at_unix"] = int(entry.get("acquired_at_unix", 0))
		"activity":
			entry["kind"] = str(entry.get("kind", "note"))
			entry["summary"] = str(entry.get("summary", ""))
			entry["related_entity_id"] = str(entry.get("related_entity_id", ""))
			entry["created_at_unix"] = int(entry.get("created_at_unix", 0))
	return entry
