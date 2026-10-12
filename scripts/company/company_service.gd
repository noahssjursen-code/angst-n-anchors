class_name CompanyService
extends RefCounted

## In-process single-player authority. Public methods accept command-shaped
## Dictionaries and return explicit result contracts so this boundary can move
## behind an HTTP/RPC server without changing callers or domain rules.

var _player: PlayerData


func bind(player: PlayerData) -> void:
	_player = player
	if _player != null:
		var was_empty := _player.company.is_empty()
		var old_account_raw: Variant = _player.company.get("account", {})
		var had_company_balance := (
			typeof(old_account_raw) == TYPE_DICTIONARY
			and (old_account_raw as Dictionary).has("balance_marks")
		)
		var legacy_balance := _player.marks
		_player.company = CompanyContracts.normalize(
			_player.company,
			_player.account_id,
			_player.display_name,
			_player.home_port_id,
		)
		if (was_empty or not had_company_balance) and legacy_balance != 0:
			var account := _player.company.get("account", {}) as Dictionary
			account["balance_marks"] = legacy_balance
			account["ledger"] = [CompanyContracts.transaction(
				"runtime-migration-%s" % _player.account_id,
				"runtime-balance-migration",
				str(_player.company.get("id", "")),
				legacy_balance,
				"legacy_balance_migration",
				"Balance carried into the company ledger",
				_player.account_id,
				int(Time.get_unix_time_from_system()),
				legacy_balance,
			)]
			_player.company["account"] = account
		_sync_legacy_balance()


func create_company(command: Dictionary) -> Dictionary:
	if _player == null:
		return CompanyContracts.result_error("authority_unbound", "No player is bound.")
	var request_id := _request_id(command)
	if not _player.company.is_empty():
		var cached := _processed_result(request_id)
		if not cached.is_empty():
			return CompanyContracts.result_ok(cached)
	if not _player.company.is_empty() and bool(_player.company.get("onboarding_complete", false)):
		return CompanyContracts.result_error("company_exists", "This captain already owns a company.")
	var company_name := str(command.get("company_name", "")).strip_edges()
	if company_name.length() < 2 or company_name.length() > 48:
		return CompanyContracts.result_error("invalid_company_name", "Company name must be 2–48 characters.")
	var starter_id := str(command.get("starter_vessel", "")).strip_edges()
	var walkup := bool(command.get("walkup_purchase", false))
	if not walkup and not CompanyContracts.STARTER_VESSELS.has(starter_id):
		return CompanyContracts.result_error("invalid_starter_vessel", "Choose a valid starter vessel.")
	var color := Color.from_string(str(command.get("brand_color", "2f7f83")), Color("2f7f83"))
	var timestamp := int(command.get("timestamp_unix", Time.get_unix_time_from_system()))
	var company_id := str(command.get("company_id", "")).strip_edges()
	if company_id.is_empty():
		company_id = PlayerData.new_uuid()
	# Onboarding is one atomic authority command. A missing/corrupt starter SKU
	# must never leave opening capital, a half-company, or a partial fleet behind.
	var previous_company := _player.company.duplicate(true)
	var previous_marks := _player.marks
	var previous_total_earned := _player.total_marks_earned
	var previous_vessels := _player.owned_vessels.duplicate(true)
	var previous_active_vessel := _player.active_vessel.duplicate(true)
	var previous_starter_claimed := _player.starter_trawler_claimed
	_player.company = CompanyContracts.new_company(
		company_id,
		_player.account_id,
		_player.captain_id if not _player.captain_id.is_empty() else _player.account_id,
		company_name,
		_player.home_port_id,
		color,
		timestamp,
	)
	var opening := post_transaction({
		"request_id": "%s:capital" % request_id,
		"amount_marks": CompanyContracts.WALKUP_STARTING_MARKS if walkup else CompanyContracts.STARTING_MARKS,
		"category": "starting_capital",
		"description": "Company opening capital",
		"related_entity_id": company_id,
		"timestamp_unix": timestamp,
	})
	if not bool(opening.get("ok", false)):
		_restore_onboarding_snapshot(
			previous_company, previous_marks, previous_total_earned, previous_vessels,
			previous_active_vessel, previous_starter_claimed,
		)
		return opening
	var leases := _player.company.get("warehouse_leases", []) as Array
	leases.append(CompanyContracts.opening_warehouse_lease(company_id, _player.home_port_id, timestamp))
	_player.company["warehouse_leases"] = leases
	var vessel_result := CompanyContracts.result_ok({}) if walkup else _grant_starter_vessel(starter_id, request_id)
	if not bool(vessel_result.get("ok", false)):
		_restore_onboarding_snapshot(
			previous_company, previous_marks, previous_total_earned, previous_vessels,
			previous_active_vessel, previous_starter_claimed,
		)
		return vessel_result
	_player.company["onboarding_complete"] = true
	_player.company["walkup_purchase"] = walkup
	var completed_data := {
		"company_id": company_id,
		"starter_vessel": starter_id,
		"vessel_id": str(_player.company.get("starter_vessel_id", "")),
	}
	_mark_processed(request_id, completed_data)
	_sync_legacy_balance()
	return CompanyContracts.result_ok({
		"company": _player.company.duplicate(true),
		"vessel": (vessel_result.get("data", {}) as Dictionary).get("vessel", {}),
	})


## Resolve stock and price on the authority. The UI never supplies a trusted
## fit-out, amount or generated vessel id. One request can be retried safely.
func purchase_vessel(command: Dictionary) -> Dictionary:
	if _player == null or not bool(_player.company.get("onboarding_complete", false)):
		return CompanyContracts.result_error("company_missing", "Create your company before buying a vessel.")
	var request_id := _request_id(command)
	var cached := _processed_result(request_id)
	if not cached.is_empty():
		return CompanyContracts.result_ok(cached)
	var entry: Dictionary = {}
	for item in PrebuiltVesselCatalog.for_sale_entries():
		if str(item.get("prebuilt_id", "")) == str(command.get("stock_id", "")):
			entry = item
			break
	if entry.is_empty():
		return CompanyContracts.result_error("stock_unavailable", "That vessel is no longer available from the yard.")
	var vessel_name := str(command.get("vessel_name", entry.get("prebuilt_name", "Vessel"))).strip_edges()
	if vessel_name.length() < 2 or vessel_name.length() > 48:
		return CompanyContracts.result_error("invalid_name", "Vessel name must be 2–48 characters.")
	var price := ShipwrightPricing.commission_price(entry, HullStations.from_box(float(entry.get("loa_m", 24)), float(entry.get("beam_m", 8)), float(entry.get("depth_m", 4)), 10), _player)
	var uid := VesselSpawn.new_vessel_uid(str(entry.get("hull_id", "")))
	var record := PlayerData.ledger_vessel_record(VesselSpawn.normalize_record({
		"uid": uid, "name": vessel_name, "display": vessel_name,
		"hull_id": entry.hull_id, "registration_id": entry.get("registration_id", ""),
		"shaft_power_kw": entry.get("shaft_power_kw", 1.0),
		"brick_layout": entry.prebuilt_layout.duplicate(true),
	}))
	if record.is_empty():
		return CompanyContracts.result_error("invalid_stock", "The yard cannot validate this vessel's fit-out.")
	if price > 0:
		var payment := post_transaction({"request_id": request_id + ":payment", "amount_marks": -price,
			"category": "vessel_purchase", "description": "Purchased " + vessel_name, "related_entity_id": uid})
		if not bool(payment.get("ok", false)):
			return payment
	_player.upsert_owned_vessel(record)
	if _player.active_vessel.is_empty():
		_player.set_active_vessel(record)
	_player.company["tablet_received"] = true
	var result := {"vessel": record, "price_marks": price, "balance_marks": _player.marks}
	_mark_processed(request_id, result)
	return CompanyContracts.result_ok(result)


func post_transaction(command: Dictionary) -> Dictionary:
	if _player == null or _player.company.is_empty():
		return CompanyContracts.result_error("company_missing", "Create a company first.")
	var request_id := _request_id(command)
	var cached := _processed_result(request_id)
	if not cached.is_empty():
		return CompanyContracts.result_ok(cached)
	var amount := int(command.get("amount_marks", 0))
	if amount == 0:
		return CompanyContracts.result_error("zero_amount", "Transaction amount cannot be zero.")
	var account := _player.company.get("account", {}) as Dictionary
	var current := int(account.get("balance_marks", 0))
	var next := current + amount
	if next < 0:
		return CompanyContracts.result_error("insufficient_funds", "The company account cannot cover this transaction.")
	var timestamp := int(command.get("timestamp_unix", Time.get_unix_time_from_system()))
	var entry := CompanyContracts.transaction(
		PlayerData.new_uuid(), request_id, str(_player.company.get("id", "")), amount,
		str(command.get("category", "uncategorized")),
		str(command.get("description", "Account transaction")),
		str(command.get("related_entity_id", "")), timestamp, next,
	)
	var ledger := account.get("ledger", []) as Array
	ledger.append(entry)
	account["ledger"] = ledger
	account["balance_marks"] = next
	_player.company["account"] = account
	if amount > 0 and bool(command.get("count_as_earned", false)):
		_player.total_marks_earned += amount
	_sync_legacy_balance()
	var data := {"entry": entry, "balance_marks": next}
	_mark_processed(request_id, data)
	return CompanyContracts.result_ok(data)


## Accepts goods already awarded by another authority (market, fishing, cargo,
## admin). Money is deliberately separate: the future market service commits
## payment and inventory together on the server, while this contract remains a
## reusable warehouse boundary.
func store_inventory(command: Dictionary) -> Dictionary:
	if _player == null or _player.company.is_empty():
		return CompanyContracts.result_error("company_missing", "Create a company first.")
	var request_id := _request_id(command)
	var cached := _processed_result(request_id)
	if not cached.is_empty():
		return CompanyContracts.result_ok(cached)
	var quantity := float(command.get("quantity", 0.0))
	var storage_units := float(command.get("storage_units", quantity))
	if quantity <= 0.0 or storage_units <= 0.0:
		return CompanyContracts.result_error("invalid_quantity", "Stored quantity must be positive.")
	var port_id := str(command.get("port_id", "")).strip_edges()
	var lease_index := _active_lease_index(port_id)
	if lease_index < 0:
		return CompanyContracts.result_error("warehouse_missing", "No active warehouse lease exists at this port.")
	var leases := _player.company.get("warehouse_leases", []) as Array
	var lease := (leases[lease_index] as Dictionary).duplicate(true)
	var capacity := float(lease.get("capacity_units", 0.0))
	var used := float(lease.get("used_units", 0.0))
	if used + storage_units > capacity + 0.0001:
		return CompanyContracts.result_error("warehouse_full", "The warehouse does not have enough free capacity.")
	var timestamp := int(command.get("timestamp_unix", Time.get_unix_time_from_system()))
	var lot_id := str(command.get("lot_id", "")).strip_edges()
	if lot_id.is_empty():
		lot_id = PlayerData.new_uuid()
	if _lot_index(lot_id) >= 0:
		return CompanyContracts.result_error("duplicate_inventory_lot", "That inventory lot already exists.")
	var lot := CompanyContracts.inventory_lot(
		lot_id,
		str(_player.company.get("id", "")),
		str(command.get("commodity_id", "unknown")),
		quantity,
		str(command.get("unit", "units")),
		str(lease.get("id", "")),
		str(command.get("origin_port_id", port_id)),
		int(command.get("acquisition_marks", 0)),
		storage_units,
		timestamp,
	)
	var lots := _player.company.get("inventory_lots", []) as Array
	lots.append(lot)
	_player.company["inventory_lots"] = lots
	lease["used_units"] = used + storage_units
	leases[lease_index] = lease
	_player.company["warehouse_leases"] = leases
	var data := {"lot": lot, "warehouse_lease": lease}
	_mark_processed(request_id, data)
	return CompanyContracts.result_ok(data)


func reserve_inventory(command: Dictionary) -> Dictionary:
	if _player == null or _player.company.is_empty():
		return CompanyContracts.result_error("company_missing", "Create a company first.")
	var request_id := _request_id(command)
	var cached := _processed_result(request_id)
	if not cached.is_empty():
		return CompanyContracts.result_ok(cached)
	var lots := _player.company.get("inventory_lots", []) as Array
	var lot_index := _lot_index(str(command.get("lot_id", "")))
	if lot_index < 0:
		return CompanyContracts.result_error("inventory_lot_missing", "The inventory lot does not exist.")
	var lot := (lots[lot_index] as Dictionary).duplicate(true)
	var reserved := float(command.get("reserved_quantity", 0.0))
	if reserved < 0.0 or reserved > float(lot.get("quantity", 0.0)) + 0.0001:
		return CompanyContracts.result_error("invalid_reservation", "Reservation exceeds the available lot quantity.")
	lot["reserved_quantity"] = reserved
	lots[lot_index] = lot
	_player.company["inventory_lots"] = lots
	var data := {"lot": lot}
	_mark_processed(request_id, data)
	return CompanyContracts.result_ok(data)


func withdraw_inventory(command: Dictionary) -> Dictionary:
	if _player == null or _player.company.is_empty():
		return CompanyContracts.result_error("company_missing", "Create a company first.")
	var request_id := _request_id(command)
	var cached := _processed_result(request_id)
	if not cached.is_empty():
		return CompanyContracts.result_ok(cached)
	var lots := _player.company.get("inventory_lots", []) as Array
	var lot_index := _lot_index(str(command.get("lot_id", "")))
	if lot_index < 0:
		return CompanyContracts.result_error("inventory_lot_missing", "The inventory lot does not exist.")
	var lot := (lots[lot_index] as Dictionary).duplicate(true)
	var quantity := float(command.get("quantity", 0.0))
	var total_quantity := float(lot.get("quantity", 0.0))
	if total_quantity <= 0.0:
		return CompanyContracts.result_error("invalid_inventory_lot", "The stored lot has no valid quantity.")
	var free_quantity := total_quantity - float(lot.get("reserved_quantity", 0.0))
	if quantity <= 0.0 or quantity > free_quantity + 0.0001:
		return CompanyContracts.result_error("quantity_unavailable", "That quantity is unavailable or reserved.")
	var released_storage := float(lot.get("storage_units", total_quantity)) * (quantity / total_quantity)
	var leases := _player.company.get("warehouse_leases", []) as Array
	var lease_index := _lease_index_by_id(str(lot.get("location_id", "")))
	if lease_index >= 0:
		var lease := (leases[lease_index] as Dictionary).duplicate(true)
		lease["used_units"] = maxf(float(lease.get("used_units", 0.0)) - released_storage, 0.0)
		leases[lease_index] = lease
		_player.company["warehouse_leases"] = leases
	var remaining := maxf(total_quantity - quantity, 0.0)
	if remaining <= 0.0001:
		lots.remove_at(lot_index)
	else:
		lot["quantity"] = remaining
		lot["storage_units"] = maxf(float(lot.get("storage_units", 0.0)) - released_storage, 0.0)
		lots[lot_index] = lot
	_player.company["inventory_lots"] = lots
	var data := {"lot_id": str(lot.get("id", "")), "withdrawn_quantity": quantity, "remaining_quantity": remaining}
	_mark_processed(request_id, data)
	return CompanyContracts.result_ok(data)


func company_summary() -> Dictionary:
	if _player == null or _player.company.is_empty():
		return {}
	var account := _player.company.get("account", {}) as Dictionary
	return {
		"id": str(_player.company.get("id", "")),
		"name": str(_player.company.get("name", "")),
		"brand_color": str(_player.company.get("brand_color", "2f7f83")),
		"home_port_id": str(_player.company.get("home_port_id", _player.home_port_id)),
		"balance_marks": int(account.get("balance_marks", 0)),
		"vessels": _player.owned_vessels.duplicate(true),
		"inventory_lots": (_player.company.get("inventory_lots", []) as Array).duplicate(true),
		"warehouse_leases": (_player.company.get("warehouse_leases", []) as Array).duplicate(true),
		"recent_transactions": _recent_transactions(account.get("ledger", []) as Array, 12),
		"currency": "NOK",
		"crew": (_player.company.get("crew", []) as Array).duplicate(true),
		"routes": (_player.company.get("routes", []) as Array).duplicate(true),
		"deliveries": (_player.company.get("deliveries", []) as Array).duplicate(true),
		"facilities": (_player.company.get("facilities", []) as Array).duplicate(true),
		"activity": (_player.company.get("activity", []) as Array).duplicate(true),
		"fleet": OperationsRecords.fleet_postings(
			_player.owned_vessels,
			_player.company.get("crew", []) as Array,
			str(_player.active_vessel.get("uid", "")),
		),
		"onboarding_complete": bool(_player.company.get("onboarding_complete", false)),
	}


func hire_crew(command: Dictionary) -> Dictionary:
	if _player == null or _player.company.is_empty():
		return CompanyContracts.result_error("company_missing", "Create a company first.")
	var request_id := _request_id(command)
	var cached := _processed_result(request_id)
	if not cached.is_empty():
		return CompanyContracts.result_ok(cached)
	var display_name := str(command.get("display_name", "")).strip_edges()
	if display_name.is_empty():
		return CompanyContracts.result_error("name_required", "A crew member needs a name.")
	var timestamp := int(command.get("timestamp_unix", Time.get_unix_time_from_system()))
	var crew_id := str(command.get("crew_id", "")).strip_edges()
	if crew_id.is_empty():
		crew_id = "crew-%s" % PlayerData.new_uuid()
	if _index_by_id("crew", crew_id) >= 0:
		return CompanyContracts.result_error("crew_exists", "That crew member is already on the books.")
	var member := OperationsRecords.crew_member(
		crew_id,
		str(_player.company.get("id", "")),
		display_name,
		str(command.get("role", "deck")),
		str(command.get("qualification", "")),
		int(command.get("wage_nok_per_day", 0)),
		timestamp,
	)
	var crew := _player.company.get("crew", []) as Array
	crew.append(member)
	_player.company["crew"] = crew
	_append_activity("crew_hired", "%s hired as %s." % [display_name, member.role], crew_id, timestamp)
	var data := {"crew": member}
	_mark_processed(request_id, data)
	return CompanyContracts.result_ok(data)


func assign_crew(command: Dictionary) -> Dictionary:
	if _player == null or _player.company.is_empty():
		return CompanyContracts.result_error("company_missing", "Create a company first.")
	var request_id := _request_id(command)
	var cached := _processed_result(request_id)
	if not cached.is_empty():
		return CompanyContracts.result_ok(cached)
	var index := _index_by_id("crew", str(command.get("crew_id", "")))
	if index < 0:
		return CompanyContracts.result_error("crew_missing", "That crew member is not on the books.")
	var crew := _player.company.get("crew", []) as Array
	var member := (crew[index] as Dictionary).duplicate(true)
	if str(member.get("status", "")) != "active":
		return CompanyContracts.result_error("crew_inactive", "Only an active crew member can be assigned.")
	var vessel_uid := str(command.get("vessel_uid", "")).strip_edges()
	member["vessel_uid"] = vessel_uid
	member["availability"] = "assigned" if not vessel_uid.is_empty() else "available"
	crew[index] = member
	_player.company["crew"] = crew
	var timestamp := int(command.get("timestamp_unix", Time.get_unix_time_from_system()))
	_append_activity("crew_assigned", "%s assignment updated." % str(member.get("display_name", "")), str(member.get("id", "")), timestamp)
	var data := {"crew": member}
	_mark_processed(request_id, data)
	return CompanyContracts.result_ok(data)


func file_route(command: Dictionary) -> Dictionary:
	if _player == null or _player.company.is_empty():
		return CompanyContracts.result_error("company_missing", "Create a company first.")
	var request_id := _request_id(command)
	var cached := _processed_result(request_id)
	if not cached.is_empty():
		return CompanyContracts.result_ok(cached)
	var origin := str(command.get("origin_port_id", "")).strip_edges()
	var destination := str(command.get("destination_port_id", "")).strip_edges()
	if origin.is_empty() or destination.is_empty():
		return CompanyContracts.result_error("route_ports", "A route needs an origin and a destination.")
	var route_id := str(command.get("route_id", "")).strip_edges()
	if route_id.is_empty():
		route_id = "route-%s" % PlayerData.new_uuid()
	if _index_by_id("routes", route_id) >= 0:
		return CompanyContracts.result_error("route_exists", "That route is already filed.")
	var record := OperationsRecords.route_plan(
		route_id,
		str(_player.company.get("id", "")),
		str(command.get("vessel_uid", "")),
		origin,
		destination,
		str(command.get("commodity_id", "")),
	)
	var routes := _player.company.get("routes", []) as Array
	routes.append(record)
	_player.company["routes"] = routes
	var timestamp := int(command.get("timestamp_unix", Time.get_unix_time_from_system()))
	_append_activity("route_filed", "Route filed from %s to %s." % [origin, destination], route_id, timestamp)
	var data := {"route": record}
	_mark_processed(request_id, data)
	return CompanyContracts.result_ok(data)


func file_delivery(command: Dictionary) -> Dictionary:
	if _player == null or _player.company.is_empty():
		return CompanyContracts.result_error("company_missing", "Create a company first.")
	var request_id := _request_id(command)
	var cached := _processed_result(request_id)
	if not cached.is_empty():
		return CompanyContracts.result_ok(cached)
	var contract_id := str(command.get("contract_id", "")).strip_edges()
	if contract_id.is_empty():
		return CompanyContracts.result_error("contract_required", "A delivery needs a contract.")
	var timestamp := int(command.get("timestamp_unix", Time.get_unix_time_from_system()))
	var delivery_id := str(command.get("delivery_id", "")).strip_edges()
	if delivery_id.is_empty():
		delivery_id = "delivery-%s" % contract_id
	if _index_by_id("deliveries", delivery_id) >= 0:
		return CompanyContracts.result_error("delivery_exists", "That delivery is already filed.")
	var record := OperationsRecords.delivery(
		delivery_id,
		str(_player.company.get("id", "")),
		contract_id,
		str(command.get("consignment_id", "")),
		str(command.get("vessel_uid", "")),
		str(command.get("origin_port_id", "")),
		str(command.get("destination_port_id", "")),
		str(command.get("commodity_id", "")),
		int(command.get("pay_nok", command.get("pay_marks", 0))),
		timestamp,
	)
	var deliveries := _player.company.get("deliveries", []) as Array
	deliveries.append(record)
	_player.company["deliveries"] = deliveries
	_append_activity("delivery_filed", "Delivery filed for %s." % contract_id, delivery_id, timestamp)
	var data := {"delivery": record}
	_mark_processed(request_id, data)
	return CompanyContracts.result_ok(data)


func advance_delivery(command: Dictionary) -> Dictionary:
	if _player == null or _player.company.is_empty():
		return CompanyContracts.result_error("company_missing", "Create a company first.")
	var request_id := _request_id(command)
	var cached := _processed_result(request_id)
	if not cached.is_empty():
		return CompanyContracts.result_ok(cached)
	var index := _index_by_id("deliveries", str(command.get("delivery_id", "")))
	if index < 0:
		return CompanyContracts.result_error("delivery_missing", "That delivery is not on the books.")
	var deliveries := _player.company.get("deliveries", []) as Array
	var record := (deliveries[index] as Dictionary).duplicate(true)
	var target := str(command.get("status", "")).strip_edges()
	if not OperationsRecords.can_advance_delivery(str(record.get("status", "")), target):
		return CompanyContracts.result_error("delivery_status", "That delivery cannot move to %s." % target)
	var timestamp := int(command.get("timestamp_unix", Time.get_unix_time_from_system()))
	record["status"] = target
	record["diesel_nok"] = maxi(int(command.get("diesel_nok", record.get("diesel_nok", 0))), 0)
	record["maintenance_nok"] = maxi(int(command.get("maintenance_nok", record.get("maintenance_nok", 0))), 0)
	record["wages_nok"] = maxi(int(command.get("wages_nok", record.get("wages_nok", 0))), 0)
	var events := record.get("events", []) as Array
	events.append({"status": target, "at_unix": timestamp})
	record["events"] = events
	if target == "delivered" and not bool(record.get("settled", false)):
		var pay := int(record.get("pay_nok", 0))
		if pay > 0:
			var paid := post_transaction({
				"request_id": "%s:pay" % request_id,
				"amount_marks": pay,
				"category": "freight",
				"description": "Delivery %s" % str(record.get("id", "")),
				"related_entity_id": str(record.get("id", "")),
				"count_as_earned": true,
				"timestamp_unix": timestamp,
			})
			if not bool(paid.get("ok", false)):
				return paid
		record["settled"] = true
	deliveries[index] = record
	_player.company["deliveries"] = deliveries
	_append_activity("delivery_%s" % target, "Delivery %s." % target, str(record.get("id", "")), timestamp)
	var data := {"delivery": record, "account": OperationsRecords.voyage_account(
		int(record.get("pay_nok", 0)),
		int(record.get("diesel_nok", 0)),
		int(record.get("maintenance_nok", 0)),
		int(record.get("wages_nok", 0)),
	)}
	_mark_processed(request_id, data)
	return CompanyContracts.result_ok(data)


func acquire_facility(command: Dictionary) -> Dictionary:
	if _player == null or _player.company.is_empty():
		return CompanyContracts.result_error("company_missing", "Create a company first.")
	var request_id := _request_id(command)
	var cached := _processed_result(request_id)
	if not cached.is_empty():
		return CompanyContracts.result_ok(cached)
	var kind := str(command.get("kind", "fish_farm")).strip_edges()
	if kind != "fish_farm":
		return CompanyContracts.result_error("facility_kind", "Only a fish farm can be acquired in this pass.")
	var price := maxi(int(command.get("price_nok", 0)), 0)
	var timestamp := int(command.get("timestamp_unix", Time.get_unix_time_from_system()))
	var facility_id := str(command.get("facility_id", "")).strip_edges()
	if facility_id.is_empty():
		facility_id = "facility-%s" % PlayerData.new_uuid()
	if _index_by_id("facilities", facility_id) >= 0:
		return CompanyContracts.result_error("facility_exists", "That site is already owned.")
	if price > 0:
		var paid := post_transaction({
			"request_id": "%s:price" % request_id,
			"amount_marks": -price,
			"category": "facility",
			"description": "Acquired %s" % kind,
			"related_entity_id": facility_id,
			"timestamp_unix": timestamp,
		})
		if not bool(paid.get("ok", false)):
			return paid
	var record := OperationsRecords.facility(
		facility_id,
		str(_player.company.get("id", "")),
		kind,
		str(command.get("display_name", "Fish farm")),
		str(command.get("site_id", "")),
		price,
		int(command.get("upkeep_nok_per_day", 0)),
		timestamp,
	)
	var facilities := _player.company.get("facilities", []) as Array
	facilities.append(record)
	_player.company["facilities"] = facilities
	_append_activity("facility_acquired", "%s acquired." % str(record.get("display_name", "")), facility_id, timestamp)
	var data := {"facility": record}
	_mark_processed(request_id, data)
	return CompanyContracts.result_ok(data)


func _grant_starter_vessel(starter_id: String, request_id: String) -> Dictionary:
	if not _player.owned_vessels.is_empty():
		return CompanyContracts.result_error("starter_already_granted", "A starter vessel has already been granted.")
	var vessel := build_starter_vessel_record(starter_id)
	if vessel.is_empty():
		return CompanyContracts.result_error("starter_unavailable", "The selected starter vessel is not available.")
	_player.upsert_owned_vessel(vessel)
	_player.set_active_vessel(vessel)
	_player.company["starter_vessel_id"] = str(vessel.get("uid", ""))
	_player.starter_trawler_claimed = starter_id == "fishing"
	return CompanyContracts.result_ok({"vessel": vessel, "request_id": request_id})


## Builds the same certified starter record for local onboarding and the
## multiplayer recovery/onboarding path. There is one source of truth for the
## hull, registration, power and complete deck fit-out.
static func build_starter_vessel_record(starter_id: String, uid_override: String = "") -> Dictionary:
	if not CompanyContracts.STARTER_VESSELS.has(starter_id):
		return {}
	var def := CompanyContracts.STARTER_VESSELS[starter_id] as Dictionary
	var prebuilt_id := str(def.get("prebuilt_id", ""))
	for entry in PrebuiltVesselCatalog.catalog_entries():
		if str(entry.get("prebuilt_id", "")) != prebuilt_id:
			continue
		if bool(entry.get("is_draft", true)) or not bool(entry.get("compliance_ok", false)):
			return {}
		var vessel_name := str(entry.get("prebuilt_name", entry.get("display", "Starter vessel")))
		var uid := uid_override.strip_edges()
		if uid.is_empty():
			uid = VesselSpawn.new_vessel_uid(str(entry.get("hull_id", "hull_28x10")))
		return VesselSpawn.normalize_record({
			"uid": uid,
			"hull_id": str(entry.get("hull_id", "hull_28x10")),
			"registration_id": str(entry.get("registration_id", "review_required")),
			"name": vessel_name,
			"display": vessel_name,
			"shaft_power_kw": float(entry.get("shaft_power_kw", 1.0)),
			"brick_layout": (entry.get("prebuilt_layout", {}) as Dictionary).duplicate(true),
		})
	return {}


func _restore_onboarding_snapshot(
	company: Dictionary,
	marks: int,
	total_earned: int,
	vessels: Array,
	active_vessel: Dictionary,
	starter_claimed: bool,
) -> void:
	_player.company = company
	_player.marks = marks
	_player.total_marks_earned = total_earned
	_player.owned_vessels = vessels
	_player.active_vessel = active_vessel
	_player.starter_trawler_claimed = starter_claimed


func _request_id(command: Dictionary) -> String:
	var request_id := str(command.get("request_id", "")).strip_edges()
	return request_id if not request_id.is_empty() else PlayerData.new_uuid()


func _mark_processed(request_id: String, result: Dictionary) -> void:
	var processed := _player.company.get("processed_requests", {}) as Dictionary
	processed[request_id] = result.duplicate(true)
	# Local saves stay bounded. A server implementation can use a durable request table.
	if processed.size() > 256:
		processed.erase(processed.keys()[0])
	_player.company["processed_requests"] = processed


func _processed_result(request_id: String) -> Dictionary:
	var processed := _player.company.get("processed_requests", {}) as Dictionary
	var raw: Variant = processed.get(request_id, {})
	return (raw as Dictionary).duplicate(true) if typeof(raw) == TYPE_DICTIONARY else {}


func _sync_legacy_balance() -> void:
	if _player == null or _player.company.is_empty():
		return
	var account := _player.company.get("account", {}) as Dictionary
	_player.marks = int(account.get("balance_marks", _player.marks))


func _recent_transactions(ledger: Array, limit: int) -> Array:
	var start := maxi(ledger.size() - limit, 0)
	var out: Array = []
	for index in range(start, ledger.size()):
		if typeof(ledger[index]) == TYPE_DICTIONARY:
			out.append((ledger[index] as Dictionary).duplicate(true))
	return out


func _active_lease_index(port_id: String) -> int:
	var leases := _player.company.get("warehouse_leases", []) as Array
	for index in range(leases.size()):
		if typeof(leases[index]) != TYPE_DICTIONARY:
			continue
		var lease := leases[index] as Dictionary
		if str(lease.get("port_id", "")) == port_id and str(lease.get("status", "")) == "active":
			return index
	return -1


func _lease_index_by_id(lease_id: String) -> int:
	var leases := _player.company.get("warehouse_leases", []) as Array
	for index in range(leases.size()):
		if typeof(leases[index]) == TYPE_DICTIONARY and str((leases[index] as Dictionary).get("id", "")) == lease_id:
			return index
	return -1


func _append_activity(kind: String, summary: String, related_entity_id: String, timestamp: int) -> void:
	var activity := _player.company.get("activity", []) as Array
	activity.append(OperationsRecords.activity_entry(
		"activity-%s" % PlayerData.new_uuid(),
		str(_player.company.get("id", "")),
		kind,
		summary,
		related_entity_id,
		timestamp,
	))
	_player.company["activity"] = OperationsRecords.normalize_activity(activity)


func _index_by_id(key: String, record_id: String) -> int:
	var records := _player.company.get(key, []) as Array
	for index in range(records.size()):
		if typeof(records[index]) == TYPE_DICTIONARY and str((records[index] as Dictionary).get("id", "")) == record_id:
			return index
	return -1


func _lot_index(lot_id: String) -> int:
	var lots := _player.company.get("inventory_lots", []) as Array
	for index in range(lots.size()):
		if typeof(lots[index]) == TYPE_DICTIONARY and str((lots[index] as Dictionary).get("id", "")) == lot_id:
			return index
	return -1


func purchase_equipment(command: Dictionary) -> Dictionary:
	if _player==null or _player.company.is_empty():
		return CompanyContracts.result_error("company_missing","Create a company first.")
	var request_id:=str(command.get("request_id","")).strip_edges()
	if request_id.is_empty():return CompanyContracts.result_error("request_missing","Purchase requires an order ID.")
	var cached:=_processed_result(request_id)
	if not cached.is_empty():
		if str(cached.get("item_id",""))!=str(command.get("item_id","")) or str(cached.get("vessel",{}).get("uid",""))!=str(command.get("vessel_id","")) or int(cached.get("quantity",0))!=int(command.get("quantity",1)):
			return CompanyContracts.result_error("order_conflict","This order ID already belongs to another purchase.")
		return CompanyContracts.result_ok(cached)
	var record:=_player.find_owned_vessel(str(command.get("vessel_id","")))
	if record.is_empty():return CompanyContracts.result_error("vessel_missing","Choose a vessel you own.")
	var stock:=VesselEquipment.item(str(command.get("item_id","")))
	if stock.is_empty():return CompanyContracts.result_error("stock_missing","That equipment is unavailable.")
	var quantity:=int(command.get("quantity",1))
	if quantity<1 or quantity>12:return CompanyContracts.result_error("quantity_invalid","Choose between 1 and 12 items.")
	var price:=int(stock.price_nok)*quantity
	var payment:=post_transaction({"request_id":request_id+":payment","amount_marks":-price,"category":"equipment_purchase","description":"Purchased "+str(stock.name),"related_entity_id":record.uid})
	if not bool(payment.get("ok",false)):return payment
	var stores:=VesselEquipment.normalize(record.get("purchased_items",[]))
	stores.append({"uid":PlayerData.new_uuid(),"item_id":stock.id,"quantity":quantity,"purchased_at_unix":int(Time.get_unix_time_from_system())})
	record["purchased_items"]=stores
	_player.upsert_owned_vessel(record)
	var result:={"item_id":stock.id,"quantity":quantity,"vessel":record,"price_nok":price,"message":"Purchased %s × %d for %s. Stored aboard."%[stock.name,quantity,VesselSpawn.vessel_name_of(record)]}
	_mark_processed(request_id,result)
	return CompanyContracts.result_ok(result)


func equip_fishing_item(command:Dictionary)->Dictionary:
	if _player==null:return CompanyContracts.result_error("missing_player","No captain.")
	var record:=_player.find_owned_vessel(str(command.get("vessel_id","")))
	var id:=str(command.get("item_id",""))
	if record.is_empty() or not VesselEquipment.has_mount(record):return CompanyContracts.result_error("missing_mount","This vessel needs a fishing-equipment mount.")
	if id not in ["fishing_rod","harpe"]:return CompanyContracts.result_error("wrong_tool","Choose a rod or harpe.")
	# The original rod is included with the authored mount on existing vessels.
	if id=="harpe" and VesselEquipment.count(record,id)<1:return CompanyContracts.result_error("not_owned","Purchase a harpe for this ship first.")
	record["equipped_fishing_item"]=id
	_player.upsert_owned_vessel(record)
	return CompanyContracts.result_ok({"vessel":record,"message":"Equipped "+str(VesselEquipment.item(id).name)})
