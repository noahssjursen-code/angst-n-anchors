extends Node

const TestReport := preload("res://tests/support/test_report.gd")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var t := TestReport.new("company_service_test")
	for starter_id in ["fishing", "general_cargo", "bulk"]:
		_test_onboarding(t, starter_id)
	_test_legacy_migration(t)
	t.finish(get_tree())


func _test_onboarding(t: TestReport, starter_id: String) -> void:
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
	t.check("onboarding succeeds for %s" % starter_id, bool(result.get("ok", false)))
	if not t.check("exactly one starter is granted", player.owned_vessels.size() == 1):
		return
	t.check("marks open at the starting balance", player.marks == CompanyContracts.STARTING_MARKS)
	t.check("opening capital is not lifetime revenue", player.total_marks_earned == 0)
	t.check(
		"onboarding grants one warehouse lease",
		(player.company.get("warehouse_leases", []) as Array).size() == 1,
	)
	t.check(
		"onboarding is flagged complete",
		bool(player.company.get("onboarding_complete", false)),
	)
	var registration := str((player.owned_vessels[0] as Dictionary).get("registration_id", ""))
	var expected: String = str({
		"fishing": "fishing_vessel",
		"general_cargo": "cargo_vessel",
		"bulk": "bulk_vessel",
	}[starter_id])
	t.check("%s starter has correct registration" % starter_id, registration == expected)

	var retried := service.create_company(command)
	t.check("same onboarding request is idempotent", bool(retried.get("ok", false)))
	t.check("retry cannot duplicate starter", player.owned_vessels.size() == 1)

	var debit := {
		"request_id": "fuel-%s" % starter_id,
		"amount_marks": -400,
		"category": "fuel",
		"description": "Bunkered fuel",
	}
	t.check("fuel debit posts", bool(service.post_transaction(debit).get("ok", false)))
	t.check(
		"transaction retry is idempotent",
		bool(service.post_transaction(debit).get("ok", false)),
	)
	t.check("balance reflects a single debit", player.marks == CompanyContracts.STARTING_MARKS - 400)
	t.check("a debit beyond the balance is rejected", not bool(service.post_transaction({
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
	t.check("inventory can enter leased storage", bool(stored.get("ok", false)))
	t.check("inventory receipt is idempotent", bool(service.store_inventory({
		"request_id": "store-%s" % starter_id,
		"lot_id": "duplicate-lot",
		"commodity_id": "provisions",
		"quantity": 10.0,
		"storage_units": 10.0,
		"port_id": "port-test",
	}).get("ok", false)))
	if not t.check(
		"the idempotent receipt left exactly one lot",
		(player.company.get("inventory_lots", []) as Array).size() == 1,
	):
		return
	t.check("inventory can be reserved", bool(service.reserve_inventory({
		"request_id": "reserve-%s" % starter_id,
		"lot_id": "lot-%s" % starter_id,
		"reserved_quantity": 4.0,
	}).get("ok", false)))
	t.check("reserved inventory cannot be withdrawn", not bool(service.withdraw_inventory({
		"request_id": "withdraw-too-much-%s" % starter_id,
		"lot_id": "lot-%s" % starter_id,
		"quantity": 7.0,
	}).get("ok", false)))
	t.check("unreserved inventory can be withdrawn", bool(service.withdraw_inventory({
		"request_id": "withdraw-%s" % starter_id,
		"lot_id": "lot-%s" % starter_id,
		"quantity": 6.0,
	}).get("ok", false)))
	var lots := player.company.get("inventory_lots", []) as Array
	t.check(
		"the reserved remainder stays on the lot",
		is_equal_approx(float((lots[0] as Dictionary).get("quantity", 0.0)), 4.0),
	)
	t.check("warehouse capacity is authoritative", not bool(service.store_inventory({
		"request_id": "overflow-%s" % starter_id,
		"commodity_id": "grain",
		"quantity": 100.0,
		"storage_units": 100.0,
		"port_id": "port-test",
	}).get("ok", false)))

	var restored := PlayerData.from_dict(player.to_dict())
	var restored_service := CompanyService.new()
	restored_service.bind(restored)
	t.check(
		"balance survives a save round-trip",
		int(restored_service.company_summary().get("balance_marks", 0)) == player.marks,
	)
	t.check("the starter vessel survives a save round-trip", restored.owned_vessels.size() == 1)


func _test_legacy_migration(t: TestReport) -> void:
	var legacy := PlayerData.from_dict({
		"account_id": "legacy-captain",
		"display_name": "Legacy",
		"home_port_id": "port-old",
		"marks": 4321,
		"owned_vessels": [],
	})
	t.check("a legacy save gains a company record", not legacy.company.is_empty())
	t.check(
		"legacy marks migrate to the company balance",
		int((legacy.company.get("account", {}) as Dictionary).get("balance_marks", 0)) == 4321,
	)
	t.check("migration never grants a surprise vessel", legacy.owned_vessels.is_empty())
