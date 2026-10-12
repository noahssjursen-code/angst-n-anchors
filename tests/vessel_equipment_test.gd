extends Node
func _ready() -> void:
	assert(ShipyardPlaytestMode.active())
	PlayerSession.begin_new_captain("Equipment Test",CharacterAppearance.default_appearance(),"test-port","equipment-test",424242,"Test Shipping",Color.WHITE,"")
	var ship:=CompanyService.build_starter_vessel_record("fishing")
	ship.uid="equipment-ship-a"
	PlayerSession.data.upsert_owned_vessel(ship);PlayerSession.data.set_active_vessel(ship)
	var other:=ship.duplicate(true);other.uid="equipment-ship-b"
	PlayerSession.data.upsert_owned_vessel(other)
	var balance:=PlayerSession.data.marks
	var command:={"request_id":"equipment-order","vessel_id":ship.uid,"item_id":"crab_trap","quantity":6,"price_nok":1}
	assert(PlayerSession.purchase_ship_equipment(command).ok)
	assert(PlayerSession.data.marks==balance-3900,"Authority owns price")
	assert(VesselEquipment.count(PlayerSession.data.get_active_vessel_record(),"crab_trap")==6)
	assert(VesselEquipment.count(PlayerSession.data.find_owned_vessel(other.uid),"crab_trap")==0)
	assert(PlayerSession.purchase_ship_equipment(command).ok)
	assert(PlayerSession.data.marks==balance-3900,"Retry cannot duplicate charge")
	var conflict:=command.duplicate(true);conflict.item_id="harpe"
	assert(not PlayerSession.purchase_ship_equipment(conflict).ok,"Order IDs cannot change products")
	var restored:=PlayerData.from_dict(JSON.parse_string(JSON.stringify(PlayerSession.data.to_dict())))
	assert(VesselEquipment.count(restored.find_owned_vessel(ship.uid),"crab_trap")==6,"Save roundtrip")
	restored.upsert_owned_vessel({"uid":ship.uid,"hull_id":ship.hull_id,"name":"Renamed"})
	assert(VesselEquipment.count(restored.find_owned_vessel(ship.uid),"crab_trap")==6,"Partial update preserves equipment")
	for patch in [{"vessel_id":"unowned"},{"item_id":"missing"},{"quantity":0},{"quantity":13}]:
		var bad:=command.duplicate(true);bad.merge(patch,true);bad.request_id=PlayerData.new_uuid()
		var before:=PlayerSession.data.to_dict()
		assert(not PlayerSession.purchase_ship_equipment(bad).ok)
		assert(PlayerData.json_equivalent(before,PlayerSession.data.to_dict()))
	PlayerSession._persistent_io_enabled=true
	var before:=PlayerSession.data.to_dict()
	command.request_id="failed-save"
	assert(not PlayerSession.purchase_ship_equipment(command).ok)
	assert(PlayerData.json_equivalent(before,PlayerSession.data.to_dict()),"Save failure rolls back money and items")
	PlayerSession._persistent_io_enabled=false
	PlayerSession.company_service.post_transaction({"request_id":"empty-account","amount_marks":-PlayerSession.data.marks})
	before=PlayerSession.data.to_dict();command.request_id="no-funds"
	assert(not PlayerSession.purchase_ship_equipment(command).ok)
	assert(PlayerData.json_equivalent(before,PlayerSession.data.to_dict()),"Insufficient funds cannot create stores")
	print("EQUIPMENT PASS: authority price, ownership, ship separation, retry, save roundtrip, partial updates, invalid input, atomic save rollback")
	get_tree().quit()
