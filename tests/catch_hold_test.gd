extends Node

var _failures := PackedStringArray()


func _ready() -> void:
	_test_lot_round_trip()
	_test_capacity_and_overflow()
	_test_fifo_withdrawal()
	_test_landing_quote()
	_test_component_mass_and_discovery()
	await _test_shore_rsw_transfer_and_capacity()
	await _test_official_trawler_runtime()
	if _failures.is_empty():
		print("CatchHold: serialization, capacity, FIFO, and vessel mass checks passed")
		get_tree().quit()
	else:
		for failure in _failures:
			push_error("CatchHold: " + failure)
		get_tree().quit(1)


func _test_lot_round_trip() -> void:
	var lot := CatchLot.create({
		"lot_id": "haul-1",
		"mass_kg": 275.0,
		"caught_game_hours": 42.5,
		"caught_position": [120.0, -88.0],
		"ground_tier": "rich",
		"price_multiplier": 1.75,
		"vessel_id": "vessel-1",
	})
	var restored := CatchLot.from_dict(lot.to_dict())
	_check(restored.lot_id == "haul-1", "lot id survives serialization")
	_check(is_equal_approx(restored.mass_kg, 275.0), "lot mass survives serialization")
	_check(restored.caught_position == Vector2(120.0, -88.0), "catch position survives serialization")


func _test_capacity_and_overflow() -> void:
	var state := CatchHoldState.new()
	state.hold_id = "hold-a"
	state.capacity_kg = 500.0
	var overflow := state.accept_lot(CatchLot.create({"lot_id": "a", "mass_kg": 650.0}))
	_check(is_equal_approx(state.total_mass_kg(), 500.0), "hold clamps accepted catch to capacity")
	_check(is_equal_approx(overflow.mass_kg, 150.0), "hold returns exact overflow")
	var restored := CatchHoldState.from_dict(state.to_dict())
	_check(is_equal_approx(restored.total_mass_kg(), 500.0), "hold inventory survives serialization")


func _test_fifo_withdrawal() -> void:
	var state := CatchHoldState.new()
	state.capacity_kg = 1000.0
	state.accept_lot(CatchLot.create({"lot_id": "old", "mass_kg": 300.0, "caught_game_hours": 1.0}))
	state.accept_lot(CatchLot.create({"lot_id": "new", "mass_kg": 400.0, "caught_game_hours": 3.0}))
	var taken := state.withdraw_oldest(450.0)
	_check(taken.size() == 2, "withdrawal spans lots when requested")
	_check(taken[0].lot_id == "old", "oldest catch leaves first")
	_check(is_equal_approx(state.total_mass_kg(), 250.0), "withdrawal removes requested mass")


func _test_landing_quote() -> void:
	var state := CatchHoldState.new()
	state.capacity_kg = 2000.0
	state.accept_lot(CatchLot.create({
		"lot_id": "market",
		"mass_kg": 1000.0,
		"quality": 0.8,
		"price_multiplier": 1.5,
	}))
	var quote := FishingLandingService.quote([state])
	_check(is_equal_approx(float(quote.get("mass_kg", 0.0)), 1000.0), "landing quote weighs catch")
	_check(int(quote.get("value_marks", 0)) == 288, "landing quote applies quality and ground value")


func _test_component_mass_and_discovery() -> void:
	var boat := BoatBody.new()
	boat.name = "TestBoat"
	boat.displacement_t = 20.0
	add_child(boat)
	var hold := CatchHoldComponent.new()
	hold.name = "CatchHold"
	hold.configure("primary", 1000.0)
	boat.add_child(hold)
	var before := boat.get_total_mass_kg()
	hold.accept_lot(CatchLot.create({"lot_id": "mass", "mass_kg": 600.0}))
	_check(boat.get_catch_holds().size() == 1, "boat discovers its catch hold")
	_check(boat.get_total_mass_kg() >= before + 599.0, "catch contributes to vessel payload mass")
	var fishing := FishingSystem.new()
	fishing.name = "FishingSystem"
	boat.add_child(fishing)
	fishing.set("_haul_zone", {"tier_id": "normal", "tier_label": "Normal", "price_mul": 1.0})
	var completed := bool(fishing.call("_complete_one_haul_crate"))
	_check(completed, "trawl haul deposits into the dedicated catch hold")
	_check(is_equal_approx(hold.state.total_mass_kg(), 850.0), "trawl adds weighed catch rather than containers")
	boat.remove_child(fishing)
	fishing.free()
	boat.remove_child(hold)
	hold.free()
	remove_child(boat)
	boat.free()


func _test_shore_rsw_transfer_and_capacity() -> void:
	var boat := BoatBody.new()
	boat.name = "LandingTestBoat"
	boat.freeze = true
	add_child(boat)
	var hold := CatchHoldComponent.new()
	hold.name = "CatchHold"
	hold.configure("landing-hold", 1000.0)
	boat.add_child(hold)
	hold.accept_lot(CatchLot.create({
		"lot_id": "landing-lot",
		"species_id": "herring",
		"mass_kg": 800.0,
		"quality": 0.9,
	}))

	var bank := ShoreRswTankBank.new()
	bank.name = "TestShoreRswBank"
	bank.capacity_kg = 600.0
	add_child(bank)
	var pump := FishLandingPump.new()
	pump.name = "TestFishLandingPump"
	pump.connect_seconds = 0.01
	pump.flush_seconds = 0.01
	pump.pump_rate_kg_s = 1000.0
	add_child(pump)
	pump.bind_receiver(bank)
	await get_tree().process_frame
	_check(pump.start_unload(boat), "landing pump accepts a trawler with catch")
	var hose := pump.get_node_or_null("FlexibleSuctionHose") as Node3D
	_check(hose != null and hose.visible, "landing hose deploys when unloading starts")
	pump.stop()
	_check(hose != null and not hose.visible, "manual stop retracts the landing hose")
	_check(pump.start_unload(boat), "landing pump can restart after a manual stop")
	pump.set_process(false)
	for i in range(20):
		pump.call("_process", 0.1)
		if pump.state_label() == FishLandingPump.STATE_COMPLETE:
			break
	_check(is_equal_approx(bank.total_mass_kg(), 600.0), "shore RSW bank receives catch up to capacity")
	_check(is_equal_approx(hold.state.total_mass_kg(), 200.0), "catch beyond shore capacity remains aboard")
	_check(pump.state_label() == FishLandingPump.STATE_COMPLETE, "pump finishes cleanly when shore tanks fill")
	_check(hose != null and not hose.visible, "completed unloading retracts the landing hose")
	var stored := bank.withdraw_oldest(600.0)
	_check(stored.size() == 1 and stored[0].lot_id == "landing-lot", "shore storage preserves catch lot identity")

	remove_child(pump)
	pump.free()
	remove_child(bank)
	bank.free()
	boat.remove_child(hold)
	hold.free()
	remove_child(boat)
	boat.free()


func _test_official_trawler_runtime() -> void:
	var record: Dictionary = {}
	for entry in PrebuiltVesselCatalog.catalog_entries():
		if str(entry.get("prebuilt_id", "")) == "fishing_trawler":
			record = entry
			break
	_check(not record.is_empty(), "official fishing trawler exists")
	if record.is_empty():
		return
	var vessel_name := str(record.get("prebuilt_name", record.get("display", "Fishing trawler")))
	var owned_record := VesselSpawn.normalize_record({
		"uid": VesselSpawn.new_vessel_uid(str(record.get("hull_id", VesselSpawn.TRAWLER_SMALL_ID))),
		"hull_id": str(record.get("hull_id", VesselSpawn.TRAWLER_SMALL_ID)),
		"registration_id": str(record.get("registration_id", "fishing_vessel")),
		"name": vessel_name,
		"display": vessel_name,
		"shaft_power_kw": float(record.get("shaft_power_kw", 1871.0)),
		"brick_layout": (record.get("prebuilt_layout", {}) as Dictionary).duplicate(true),
	})
	var boat := VesselSpawn.instantiate_from_record(owned_record)
	_check(boat != null, "official fishing trawler record is deployable")
	if boat == null:
		return
	add_child(boat)
	await get_tree().process_frame
	await get_tree().process_frame
	var systems := boat.get_fishing_systems()
	var holds := boat.get_catch_holds()
	_check(systems.size() == 1, "official trawler mounts one live fishing system")
	_check(holds.size() == 1, "official trawler mounts one insulated catch hold")
	if systems.size() == 1 and holds.size() == 1:
		var system: FishingSystem = systems[0]
		boat.freeze = true
		system.catch_interval_seconds = 0.01
		system.apply_trawl_desired(true)
		system.call("_physics_process", 0.02)
		system.call("_physics_process", 0.01)
		_check(system.get_activity_status() == "ACTIVE", "official trawler reports active fishing")
		_check(is_equal_approx(holds[0].state.total_mass_kg(), 250.0), "official trawler receives catch data")
	remove_child(boat)
	boat.free()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
