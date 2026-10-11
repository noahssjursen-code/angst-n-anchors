extends Node


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_currency()
	_test_legacy_company_grows_operations()
	_test_voyage_account()
	_test_crew_delivery_and_farm()
	_test_dialogue()
	print("operations_records_test: PASS")
	get_tree().quit()


func _test_currency() -> void:
	assert(PlayerData.format_money(6400) == "6 400 NOK")
	assert(PlayerData.format_money(-400) == "-400 NOK")
	assert(PlayerData.CURRENCY_CODE == "NOK")
	var company := CompanyContracts.normalize({
		"account": {"currency": "MARK", "balance_marks": 100, "ledger": [{"currency": "MARK", "amount_marks": 100}]},
	}, "ada", "Ada", "alesund")
	var account := company.get("account", {}) as Dictionary
	assert(str(account.get("currency", "")) == "NOK")
	var ledger := account.get("ledger", []) as Array
	assert(str((ledger[0] as Dictionary).get("currency", "")) == "NOK")


func _test_legacy_company_grows_operations() -> void:
	var company := CompanyContracts.normalize({"schema_version": 1, "name": "Old Co"}, "ada", "Ada", "alesund")
	assert(int(company.get("schema_version", 0)) == 2)
	assert((company.get("crew", []) as Array).is_empty())
	assert((company.get("deliveries", []) as Array).is_empty())
	assert((company.get("facilities", []) as Array).is_empty())


func _test_voyage_account() -> void:
	var owner := OperationsRecords.voyage_account(12000, 2000, 1000, 0)
	var crewed := OperationsRecords.voyage_account(12000, 2000, 1000, 7000)
	assert(int(owner.get("net_nok", 0)) == 9000)
	assert(int(crewed.get("net_nok", 0)) == 2000)
	assert(OperationsRecords.can_advance_delivery("booked", "loading"))
	assert(not OperationsRecords.can_advance_delivery("booked", "delivered"))
	assert(OperationsRecords.can_advance_delivery("underway", "failed"))
	assert(not OperationsRecords.can_advance_delivery("delivered", "failed"))


func _test_crew_delivery_and_farm() -> void:
	var player := PlayerData.new()
	player.account_id = "ada"
	player.display_name = "Ada"
	player.home_port_id = "alesund"
	var service := CompanyService.new()
	service.bind(player)
	assert(bool(service.post_transaction({
		"request_id": "capital",
		"amount_marks": 80000,
		"category": "capital",
		"description": "Opening capital",
	}).get("ok", false)))
	var hired := service.hire_crew({
		"request_id": "hire-sigrid",
		"crew_id": "crew-sigrid",
		"display_name": "Sigrid Hale",
		"role": "master",
		"wage_nok_per_day": 1800,
	})
	assert(bool(hired.get("ok", false)))
	assert(bool(service.hire_crew({"request_id": "hire-sigrid"}).get("ok", false)))
	assert((player.company.get("crew", []) as Array).size() == 1)
	assert(bool(service.file_route({
		"request_id": "route-coal",
		"route_id": "route-coal",
		"origin_port_id": "alesund",
		"destination_port_id": "maloy",
		"commodity_id": "coal",
		"vessel_uid": "vessel-nordlys",
	}).get("ok", false)))
	assert(bool(service.file_route({"request_id": "route-coal"}).get("ok", false)))
	assert((player.company.get("routes", []) as Array).size() == 1)
	assert(not bool(service.file_route({
		"request_id": "route-missing-port",
		"origin_port_id": "alesund",
	}).get("ok", false)))
	assert(bool(service.assign_crew({
		"request_id": "assign-sigrid",
		"crew_id": "crew-sigrid",
		"vessel_uid": "vessel-nordlys",
	}).get("ok", false)))
	var filed := service.file_delivery({
		"request_id": "file-coal",
		"delivery_id": "delivery-coal",
		"contract_id": "freight-coal",
		"origin_port_id": "alesund",
		"destination_port_id": "maloy",
		"commodity_id": "coal",
		"pay_nok": 12000,
	})
	assert(bool(filed.get("ok", false)))
	assert(not bool(service.advance_delivery({
		"request_id": "skip",
		"delivery_id": "delivery-coal",
		"status": "delivered",
	}).get("ok", false)))
	assert(bool(service.advance_delivery({
		"request_id": "load",
		"delivery_id": "delivery-coal",
		"status": "loading",
	}).get("ok", false)))
	assert(bool(service.advance_delivery({
		"request_id": "sail",
		"delivery_id": "delivery-coal",
		"status": "underway",
		"diesel_nok": 2000,
		"maintenance_nok": 1000,
		"wages_nok": 1800,
	}).get("ok", false)))
	assert(bool(service.advance_delivery({
		"request_id": "berth",
		"delivery_id": "delivery-coal",
		"status": "berthed",
	}).get("ok", false)))
	var before := player.marks
	var settled := service.advance_delivery({
		"request_id": "deliver",
		"delivery_id": "delivery-coal",
		"status": "delivered",
	})
	assert(bool(settled.get("ok", false)))
	assert(player.marks == before + 12000)
	assert(bool(service.advance_delivery({"request_id": "deliver"}).get("ok", false)))
	assert(player.marks == before + 12000)
	assert(not bool(service.acquire_facility({
		"request_id": "farm-broke",
		"facility_id": "farm-1",
		"price_nok": 1000000,
	}).get("ok", false)))
	assert(bool(service.acquire_facility({
		"request_id": "farm",
		"facility_id": "farm-1",
		"display_name": "Hale Havbruk",
		"site_id": "site-hjoring",
		"price_nok": 50000,
		"upkeep_nok_per_day": 900,
	}).get("ok", false)))
	assert(player.marks == before + 12000 - 50000)
	var summary := service.company_summary()
	assert((summary.get("fleet", []) as Array).is_empty())
	var facilities := summary.get("facilities", []) as Array
	assert(str((facilities[0] as Dictionary).get("kind", "")) == "fish_farm")
	assert(str(summary.get("currency", "")) == "NOK")


func _test_dialogue() -> void:
	var document := DialogueDocument.normalize({
		"id": "harbour-master",
		"title": "Harbour master",
		"speaker_role": "harbour_master",
		"entry": "main",
		"screens": {
			"main": {
				"quote": "You are expected on quay two.",
				"options": [{"label": "Book the arrival", "action": "note_arrival"}, {"label": "Goodbye", "action": "close"}],
			},
		},
	})
	assert(DialogueDocument.valid(document))
	assert(not DialogueDocument.valid(DialogueDocument.normalize({"title": "Broken"})))
	var dialogue := DialogueScript.new()
	assert(dialogue.load_from_path("res://resources/data/dialogue/tavern_keeper.json"))
	assert(dialogue.get_title() == "TAVERN KEEPER")
	assert(dialogue.get_entry() == "main")
