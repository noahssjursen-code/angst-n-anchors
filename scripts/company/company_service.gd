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
	if not CompanyContracts.STARTER_VESSELS.has(starter_id):
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
		"amount_marks": CompanyContracts.STARTING_MARKS,
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
	var vessel_result := _grant_starter_vessel(starter_id, request_id)
	if not bool(vessel_result.get("ok", false)):
		_restore_onboarding_snapshot(
			previous_company, previous_marks, previous_total_earned, previous_vessels,
			previous_active_vessel, previous_starter_claimed,
		)
		return vessel_result
	_player.company["onboarding_complete"] = true
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
		"onboarding_complete": bool(_player.company.get("onboarding_complete", false)),
	}


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


func _lot_index(lot_id: String) -> int:
	var lots := _player.company.get("inventory_lots", []) as Array
	for index in range(lots.size()):
		if typeof(lots[index]) == TYPE_DICTIONARY and str((lots[index] as Dictionary).get("id", "")) == lot_id:
			return index
	return -1
