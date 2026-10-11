extends Node3D

class BusyEquipment extends QuayEquipmentJob:
	func is_job_active() -> bool:
		return true

var checks := 0
var failures: PackedStringArray = []
var harbour: HarbourController
var yard: CargoSlotPadComponent
var berth: QuayBerthSlot

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)
	print("CANCELLATION ","PASS " if ok else "FAIL ",message)

func _ready() -> void:
	assert(ShipyardPlaytestMode.active(),"Use --shipyard-playtest")
	call_deferred("run")

func book(id: String, mode: String = "general") -> void:
	check(FreightService.accept_offer({"id":id,"status":"offered","origin_port_id":"cancel-origin","destination_port_id":"cancel-destination","berth_id":"cancel-origin/general","vessel_uid":"test-vessel","commodity_id":"provisions" if mode=="general" else "iron_ore","handling_mode":mode,"quantity":2.0,"quantity_unit":"units" if mode=="general" else "tonnes","pay_marks":900}),"book "+id)

func press(panel: VoyagePanel, text: String) -> void:
	for button in panel._body.find_children("*","Button",true,false):
		if button.text == text:
			button.pressed.emit()
			return
	check(false,"button found: "+text)

func run() -> void:
	await get_tree().process_frame
	PlayerSession.begin_new_captain("Cancellation test",CharacterAppearance.default_appearance(),"cancel-origin","cancel-test",424242,"Test Shipping",Color.WHITE,"")
	var opening_balance: int = PlayerSession.data.marks
	harbour = HarbourController.new()
	harbour.setup("cancel-origin")
	add_child(harbour)
	HarbourRegistry.register(harbour)
	berth = QuayBerthSlot.new()
	berth.setup("cancel-origin/general","general","general",[],60.0,20.0)
	add_child(berth)
	harbour.register_berth(berth)
	yard = CargoSlotPadComponent.new()
	yard.deck_width_m=20
	yard.deck_length_m=20
	yard.show_pad_visual=false
	yard.affects_boat_cargo_mass=false
	yard.is_quay_yard_pad=true
	add_child(yard)
	harbour.register_yard(yard,berth.berth_id)
	book("cancel-me")
	book("keep-me")
	for id in ["cancel-me","keep-me"]:
		for unit in FreightService.make_container_units(id):
			check(yard.add_container(unit)>=0,"stage physical cargo for "+id)
	var free_before := yard.get_free_slot_count()
	check(bool(FreightService.cancellation_status("cancel-me").allowed),"staged, unloaded booking is cancellable")
	var panel := VoyagePanel.new()
	add_child(panel)
	panel.show_tablet("Jobs")
	press(panel,"Cancel job")
	check(panel.page=="cancel_job","tablet asks before cancelling")
	press(panel,"Keep job")
	check(FreightService.active_contracts().size()==2,"keeping job has no side effects")
	press(panel,"Cancel job")
	press(panel,"Cancel job")
	check(FreightService.active_contracts().size()==1 and FreightService.active_contracts()[0].id=="keep-me","confirm cancels only selected job")
	check(yard.get_containers().size()==2 and yard.get_containers()[0].freight_contract_id=="keep-me","only cancelled job's physical quay cargo removed")
	check(yard.get_free_slot_count()>free_before,"yard capacity released")
	var boat := BoatBody.new()
	boat.set_meta("vessel_uid","test-vessel")
	check(is_equal_approx(FreightService._reserved_quantity(boat,false),2.0),"only remaining booking reserves ship capacity")
	boat.free()
	check(PlayerSession.data.accepted_contracts.size()==1,"saved captain projection drops cancelled job")
	check(PlayerSession.data.marks==opening_balance and PlayerSession.data.contracts_completed==0,"cancellation earns no payout and charges no fee")
	check(not FreightService.cancel_contract("cancel-me").get("ok",true),"repeated/stale cancellation cannot affect another job")
	book("loaded")
	FreightService.record_loaded("loaded",1)
	check(not FreightService.cancel_contract("loaded").get("ok",true),"loaded cargo cannot be orphaned")
	book("in-flight","bulk")
	FreightService._active[FreightService._contract_index("in-flight")]["issued_quantity"]=1.0
	check(not FreightService.cancel_contract("in-flight").get("ok",true),"issued bulk on crane cannot be orphaned")
	book("unloaded-bulk","bulk")
	check(FreightService.cancel_contract("unloaded-bulk").get("ok",false),"unloaded bulk reservation can be cancelled")
	book("busy")
	var equipment := BusyEquipment.new()
	equipment.setup("test-equipment","general",berth.berth_id)
	harbour.add_child(equipment)
	harbour.register_equipment(equipment,berth.berth_id)
	check(not FreightService.cancel_contract("busy").get("ok",true),"active transfer blocks cancellation after panel opened")
	harbour.unregister_equipment(equipment.equipment_id())
	equipment.free()
	PlayerSession.persistence_mode=PlayerSession.PersistenceMode.REMOTE
	check(not FreightService.cancel_contract("busy").get("ok",true),"remote account cannot be mutated by local cancellation")
	PlayerSession.persistence_mode=PlayerSession.PersistenceMode.LOCAL
	# A real failed disk write, contained inside a unique temporary test folder.
	var folder := OS.get_cache_dir().path_join("angst-cancel-test-%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(folder)
	var blocker := FileAccess.open(folder.path_join("blocked"),FileAccess.WRITE)
	blocker.store_string("not a directory")
	blocker.close()
	PlayerSaveStore.storage_root_override=folder.path_join("blocked/captain")
	LocalCaptainStore.active_id="test-slot"
	PlayerSession._persistent_io_enabled=true
	var before := FreightService.active_contracts()
	check(not FreightService.cancel_contract("keep-me").get("ok",true),"failed save rejects cancellation")
	check(PlayerData.json_equivalent(before,FreightService.active_contracts()) and yard.get_containers().size()==2,"failed save keeps booking, counters and physical cargo")
	# Now persist successfully to a separate scratch slot and inspect the file.
	PlayerSaveStore.storage_root_override=folder.path_join("captain")
	LocalCaptainStore.root_override=folder
	check(FreightService.cancel_contract("keep-me").get("ok",false),"cancellation persists to scratch captain slot")
	var saved := PlayerSaveStore.load_player()
	check(not saved.accepted_contracts.any(func(job):return str(job.get("id",""))=="keep-me"),"cancelled job cannot return on reload")
	PlayerSession._persistent_io_enabled=false
	LocalCaptainStore.clear_active()
	LocalCaptainStore.root_override=""
	panel.free()
	harbour.unregister_all()
	harbour.free()
	yard.free()
	berth.free()
	await get_tree().process_frame
	print("CANCELLATION_RESULT ",checks," checks; ",failures.size()," failures: ",failures)
	get_tree().quit(0 if failures.is_empty() else 1)
