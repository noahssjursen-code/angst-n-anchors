extends Node3D

var failures: Array[String] = []
var checks: Array[Dictionary] = []
var harbour: HarbourController
var berth: QuayBerthSlot


func check(ok: bool, label: String) -> void:
	checks.append({"ok": ok, "check": label})
	print("FREIGHT CAPACITY ", "PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)


func _ready() -> void:
	assert(ShipyardPlaytestMode.active())
	call_deferred("run")


func run() -> void:
	await get_tree().process_frame
	WorldClock.set_process(false)
	PortCatalog._ports = {
		"capacity-origin": {"id":"capacity-origin", "position":Vector3.ZERO,
			"commodity_exports":["containers", "provisions", "iron_ore"]},
		"capacity-destination": {"id":"capacity-destination", "position":Vector3(3000,0,0),
			"commodity_imports":["containers", "provisions", "iron_ore"]},
	}
	harbour = HarbourController.new()
	harbour.setup("capacity-origin"); add_child(harbour); HarbourRegistry.register(harbour)
	berth = QuayBerthSlot.new()
	berth.setup("capacity-origin/general", "general", "general", ["containers", "provisions", "iron_ore"], 200, 30)
	add_child(berth); harbour.register_berth(berth)
	for entry in PrebuiltVesselCatalog.for_sale_entries():
		FreightService.restore_contracts([])
		var record := VesselSpawn.normalize_record({"uid":"capacity-"+str(entry.prebuilt_id),
			"hull_id":entry.hull_id, "brick_layout":entry.prebuilt_layout, "name":entry.prebuilt_name})
		var ship := VesselSpawn.instantiate_from_record(record)
		ship.freeze = true; ship.process_mode = Node.PROCESS_MODE_DISABLED; add_child(ship)
		harbour.plug_ship(berth.berth_id, ship)
		var offers := FreightService.eligible_offers_at("capacity-origin", ship)
		print("FREIGHT CAPACITY STOCK ", entry.prebuilt_name, " ", offers.map(func(o: Dictionary): return {"cargo":o.commodity_id,"quantity":o.quantity,"pay":o.pay_marks}))
		if str(entry.prebuilt_id) == "fishing_trawler":
			check(offers.is_empty(), "trawler without freight equipment gets no cargo offers")
		elif str(entry.prebuilt_id) == "28_10_m":
			check(not offers.is_empty() and offers[0].quantity == 2, "Harbour Cargo gets a two-container job")
		elif str(entry.prebuilt_id) == "container_feeder_40":
			check(not offers.is_empty() and offers[0].quantity == 40, "Northline receives a forty-container job without a test quantity override")
			if not offers.is_empty(): test_container_reservations(ship, offers[0])
		elif str(entry.prebuilt_id) == "bulk_small":
			test_bulk(ship, offers)
		else:
			check(not offers.is_empty(), "freighter gets a usable job")
		FreightService.restore_contracts([])
		harbour.unplug_ship(ship)
		ship.queue_free()
		await get_tree().process_frame
	var output := "C:/Users/noahs/Pictures/machinescreenshots/freight-capacity-" + str(Time.get_unix_time_from_system()).replace(".", "-")
	DirAccess.make_dir_recursive_absolute(output)
	FileAccess.open(output.path_join("report.json"), FileAccess.WRITE).store_string(JSON.stringify({"checks": checks, "failures": failures}, "\t"))
	print("FREIGHT CAPACITY REPORT ", output, " ", failures)
	get_tree().quit(0 if failures.is_empty() else 1)


func test_container_reservations(ship: BoatBody, original: Dictionary) -> void:
	var pads := ship.get_cargo_pads()
	for i in 7:
		check(pads[i].add_container(ContainerUnit.create("existing-%d" % i, "containers")) >= 0, "pre-existing cargo occupies real bed %d" % i)
	var available := FreightService.eligible_offers_at("capacity-origin", ship)
	check(available[0].quantity == 33, "seven real containers leave thirty-three places")
	check(str(available[0].id) != str(original.id), "changed capacity invalidates the old quote identity")
	check(not FreightService.accept_offer_for_ship(original, ship, "capacity-origin"), "stale forty-container quote cannot overbook")
	var six := available[0].duplicate(true)
	six.id = "existing-six-container-booking"; six.quantity = 6
	check(FreightService.accept_offer_for_ship(six, ship, "capacity-origin"), "existing six-container booking remains valid")
	available = FreightService.eligible_offers_at("capacity-origin", ship)
	check(available[0].quantity == 27, "new job fills only twenty-seven unreserved positions")
	check(available[0].pay_marks == 165 + 27*95, "payment uses full new quantity and one route allowance")
	var quoted := available[0].duplicate(true)
	for unit in FreightService.make_container_units(six.id, 3):
		for pad in pads:
			if pad.add_container(unit) >= 0: break
		check(FreightService.record_unit_loaded(unit, "capacity-origin", ship), "real occupied cargo converts its pending reservation")
	available = FreightService.eligible_offers_at("capacity-origin", ship)
	check(available[0] == quoted, "partial loading is not double-counted as occupied and reserved")
	check(FreightService.accept_offer_for_ship(quoted, ship, "capacity-origin"), "remaining-capacity job books")
	check(FreightService.eligible_offers_at("capacity-origin", ship).is_empty(), "fully reserved deck offers no additional cargo")
	check(FreightService.active_contracts()[0].quantity == 6, "existing accepted booking keeps its original quantity")


func test_bulk(ship: BoatBody, offers: Array[Dictionary]) -> void:
	var capacity := 0.0
	for hold in ship.get_bulk_holds():
		if hold.cargo_accessible: capacity += hold.state.capacity_tonnes_t
	check(offers.size() == 1 and offers[0].quantity == floorf(capacity), "bulk job fills actual holds, without duplicate small-load offer")
	if offers.is_empty(): return
	check(FreightService.accept_offer_for_ship(offers[0], ship, "capacity-origin"), "full-hold bulk quote books")
	check(FreightService.eligible_offers_at("capacity-origin", ship).is_empty(), "bulk booking reserves the hold capacity")
	var occupied := ship.get_bulk_holds()[0]
	var scoop := FreightService.issue_bulk_lot(ship, "iron_ore", 5)
	check(occupied.accept_lot(scoop).is_empty() and FreightService.record_bulk_loaded(scoop, ship), "partial bulk load occupies its booked hold")
	check(FreightService.eligible_offers_at("capacity-origin", ship).is_empty(), "partial bulk loading keeps all remaining booked tonnes reserved")
	FreightService.restore_contracts([])
	occupied.withdraw_lot(5)
	occupied.accept_lot(BulkCargoLot.create("iron_ore", 5, "other-consignment"))
	var remaining := maxf(0.0, floorf(capacity - occupied.state.capacity_tonnes_t))
	offers = FreightService.eligible_offers_at("capacity-origin", ship)
	check((offers.is_empty() and remaining == 0) or (not offers.is_empty() and offers[0].quantity == remaining), "new bulk shipment cannot mix into another consignment's hold")
