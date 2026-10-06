extends Node


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	for starter_id in ["fishing", "general_cargo", "bulk", "coaster"]:
		_test_onboarding(starter_id)
	_test_legacy_migration()
	print("company_service_test: PASS")
	get_tree().quit()


func _test_onboarding(starter_id: String) -> void:
	var player := PlayerData.new()
	player.account_id = "captain-%s" % starter_id
	player.display_name = "Ada"
	player.home_port_id = "port-test"
	var service := CompanyService.new()
	service.bind(player)
	var command := {
		"request_id": "create-%s" % starter_id,
		"company_id": "company-%s" % starter_id,
		"company_name": "North Star %s" % starter_id,
		"brand_color": "2f7f83",
		"starter_vessel": starter_id,
		"timestamp_unix": 1000,
	}
	var result := service.create_company(command)
	assert(bool(result.get("ok", false)), "onboarding succeeds for %s" % starter_id)
	assert(player.owned_vessels.size() == 1, "exactly one starter is granted")
	assert(player.marks == CompanyContracts.STARTING_MARKS)
	assert(player.total_marks_earned == 0, "opening capital is not lifetime revenue")
	assert((player.company.get("warehouse_leases", []) as Array).size() == 1)
	assert(bool(player.company.get("onboarding_complete", false)))
	var vessel: Dictionary = player.owned_vessels[0]
	assert(ImportedVesselLayout.valid(VesselSpawn.brick_layout_of(vessel), vessel.hull_id, true))
	assert(not VesselSpawn.resolve_deployable_record(vessel).is_empty(), "starter must actually spawn")

	var retried := service.create_company(command)
	assert(bool(retried.get("ok", false)), "same onboarding request is idempotent")
	assert(player.owned_vessels.size() == 1, "retry cannot duplicate starter")

	var debit := {
		"request_id": "fuel-%s" % starter_id,
		"amount_marks": -400,
		"category": "fuel",
		"description": "Bunkered fuel",
	}
	assert(bool(service.post_transaction(debit).get("ok", false)))
	assert(bool(service.post_transaction(debit).get("ok", false)), "transaction retry is idempotent")
	assert(player.marks == CompanyContracts.STARTING_MARKS - 400)
	assert(not bool(service.post_transaction({
		"request_id": "overspend-%s" % starter_id,
		"amount_marks": -100000,
	}).get("ok", false)))

	var stored := service.store_inventory({
		"request_id": "store-%s" % starter_id,
		"lot_id": "lot-%s" % starter_id,
		"commodity_id": "provisions",
		"quantity": 10.0,
		"storage_units": 10.0,
		"unit": "pallets",
		"port_id": "port-test",
		"origin_port_id": "port-origin",
		"acquisition_marks": 800,
		"timestamp_unix": 1010,
	})
	assert(bool(stored.get("ok", false)), "inventory can enter leased storage")
	assert(bool(service.store_inventory({
		"request_id": "store-%s" % starter_id,
		"lot_id": "duplicate-lot",
		"commodity_id": "provisions",
		"quantity": 10.0,
		"storage_units": 10.0,
		"port_id": "port-test",
	}).get("ok", false)), "inventory receipt is idempotent")
	assert((player.company.get("inventory_lots", []) as Array).size() == 1)
	assert(bool(service.reserve_inventory({
		"request_id": "reserve-%s" % starter_id,
		"lot_id": "lot-%s" % starter_id,
		"reserved_quantity": 4.0,
	}).get("ok", false)))
	assert(not bool(service.withdraw_inventory({
		"request_id": "withdraw-too-much-%s" % starter_id,
		"lot_id": "lot-%s" % starter_id,
		"quantity": 7.0,
	}).get("ok", false)), "reserved inventory cannot be withdrawn")
	assert(bool(service.withdraw_inventory({
		"request_id": "withdraw-%s" % starter_id,
		"lot_id": "lot-%s" % starter_id,
		"quantity": 6.0,
	}).get("ok", false)))
	var lots := player.company.get("inventory_lots", []) as Array
	assert(is_equal_approx(float((lots[0] as Dictionary).get("quantity", 0.0)), 4.0))
	assert(not bool(service.store_inventory({
		"request_id": "overflow-%s" % starter_id,
		"commodity_id": "grain",
		"quantity": 100.0,
		"storage_units": 100.0,
		"port_id": "port-test",
	}).get("ok", false)), "warehouse capacity is authoritative")

	var restored := PlayerData.from_dict(player.to_dict())
	var restored_service := CompanyService.new()
	restored_service.bind(restored)
	assert(int(restored_service.company_summary().get("balance_marks", 0)) == player.marks)
	assert(restored.owned_vessels.size() == 1)


func _test_legacy_migration() -> void:
	var legacy := PlayerData.from_dict({
		"account_id": "legacy-captain",
		"display_name": "Legacy",
		"home_port_id": "port-old",
		"marks": 4321,
		"owned_vessels": [],
	})
	assert(not legacy.company.is_empty())
	assert(int((legacy.company.get("account", {}) as Dictionary).get("balance_marks", 0)) == 4321)
	assert(legacy.owned_vessels.is_empty(), "migration never grants a surprise vessel")
