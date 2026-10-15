extends "res://tests/home_onboarding_review.gd"

func _after_deploy() -> void:
	var ship := LocalPlayerView.get_active_ship() as BoatBody
	var holds := ship.get_catch_holds()
	check(not holds.is_empty(), "fishing boat has a catch crate")
	if holds.is_empty(): return
	var hold: CatchHoldComponent = holds[0]
	var port_id := PlayerSession.data.home_port_id
	check(HomeFishSale.available(PlayerSession.data.home_port_document), "starter Fiskemottak is a sale service")
	check(not HomeFishSale.snapshot(port_id).reason.is_empty(), "empty crate cannot sell")
	for item in [{"lot_id":"review-cod","species_id":"cod","mass_kg":2.0,"length_cm":60.0},
		{"lot_id":"review-cod-2","species_id":"cod","mass_kg":3.0,"length_cm":70.0}]:
		item["specimen"] = true
		hold.accept_lot(CatchLot.create(item))
	var persisted := PlayerData.from_dict(JSON.parse_string(JSON.stringify(PlayerSession.data.to_dict())))
	check(persisted.local_fishing.get("holds", {}).get(LocalCatchStore.key(ship, hold.hold_id), {}).get("lots", []).size() == 2, "unsold catches survive captain JSON")
	var offer := HomeFishSale.snapshot(port_id)
	print("FISH_OFFER ", offer, " PORT ", ship.get_harbour_port_id(), " BERTH ", ship.get_moored_berth(), " OWN ", PlayerSession.data.home_port_id)
	check(offer.reason.is_empty() and int(offer.value_marks) == 400, "moored fish quoted at species price")
	GameMenu.open_tablet()
	var tablet: KontorTablet = GameMenu._panel._tablet
	tablet.open_page("Harbour services")
	await capture("fiskemottak-before-sale")
	var service := LocalPlayerView.get_tablet_harbour()
	var before := PlayerSession.data.marks
	var ids: Array[String] = ["review-cod", "review-cod-2"]
	var vessel_id := HarbourController.ship_id_of(ship)
	var sale_id := "home-fish-" + JSON.stringify([vessel_id, port_id, ids]).sha256_text()
	var body := {"operation_id":sale_id,"port_id":port_id,"vessel_id":vessel_id,"lot_ids":ids}
	# A failed disk write must not consume the fish or award money.
	var berth: Dictionary = WorldGateway.projection("vessel_berth", vessel_id).get("state", {})
	var original_root := PlayerSaveStore.storage_root_override
	var blocker := "user://fish-sale-write-blocker"
	var file := FileAccess.open(blocker, FileAccess.WRITE)
	file.store_string("file, not a directory"); file.close()
	PlayerSaveStore.storage_root_override = blocker + "/save"
	PlayerSession._persistent_io_enabled = true
	var failed := HomeFishSale.execute_local(body, WorldGateway.actor_id(), berth)
	PlayerSession._persistent_io_enabled = false
	PlayerSaveStore.storage_root_override = original_root
	DirAccess.remove_absolute(ProjectSettings.globalize_path(blocker))
	check(not failed.get("ok",false) and hold.state.lots.size()==2 and PlayerSession.data.marks==before, "failed save keeps both fish and money")
	await tablet._service_order(service, "sell_fish")
	print("SALE_NOTICE ", tablet.notice)
	check(hold.state.is_empty(), "tablet sale empties actual boat crate")
	check(PlayerSession.data.marks == before + 400, "tablet sale pays exact 400 NOK")
	await capture("fiskemottak-paid")
	var receipt := await HomePortService.request("fishing.catch.sell", body)
	check(receipt.get("ok",false) and PlayerSession.data.marks==before+400, "repeated receipt cannot pay twice")
	# Save/read and restart the authority, then retry the accepted operation.
	PlayerSaveStore.storage_root_override = "user://home-fish-sale-review-" + str(OS.get_process_id())
	check(PlayerSaveStore.save_player(PlayerSession.data), "fish sale writes to isolated save")
	PlayerSession.data = PlayerSaveStore.load_player()
	PlayerSession.company_service.bind(PlayerSession.data)
	check(PlayerSession.data.local_fishing.holds[LocalCatchStore.key(ship,hold.hold_id)].lots.is_empty(), "sold catches stay empty after disk reload")
	var backend := LocalWorldBackend.new()
	WorldGateway.use_backend(backend,false)
	backend.start_session("review-home","Review","")
	var retried := await HomePortService.request("fishing.catch.sell", body)
	check(retried.get("ok",false) and PlayerSession.data.marks==before+400, "restart retry is idempotent")
	PlayerSaveStore.storage_root_override = original_root
	check(HomeFishSale.snapshot(port_id).reason == "Your catch crate is empty.", "empty state ready for another fishing trip")
	print("HOME_FISH_SALE_RESULT failures=",failures)
