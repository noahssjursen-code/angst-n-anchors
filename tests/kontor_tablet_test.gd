extends Node
var failures: Array[String] = []
var checks := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)
	print("KONTOR ", "PASS " if ok else "FAIL ", message)
func _ready() -> void:
	assert(ShipyardPlaytestMode.active())
	run.call_deferred()
func run() -> void:
	await get_tree().process_frame
	PlayerSession.begin_new_captain("Tablet Captain", CharacterAppearance.default_appearance(), "test-port", "tablet-test", 424242, "Tablet Shipping", Color.WHITE, "")
	var before := PlayerSession.data.to_dict()
	var ui := VoyagePanel.new()
	add_child(ui)
	ui.show_tablet()
	check(ui._tablet.visible and not ui._card.visible, "J tablet uses native workspace")
	check(ui._tablet.snapshot.captain == "Tablet Captain", "real captain identity")
	check(ui._tablet.snapshot.company.name == "Tablet Shipping", "real company identity")
	check(ui._tablet.snapshot.balance == LocalPlayerView.get_marks(), "balance comes from read seam")
	check(ui._tablet.snapshot.fleet.is_empty(), "no invented vessels for empty company")
	for page in KontorTablet.PAGES:
		ui._tablet.open_page(page)
		await get_tree().process_frame
		check(ui._tablet.current_page == page, "opens " + page)
	check(PlayerData.json_equivalent(before, PlayerSession.data.to_dict()), "navigation cannot mutate saved game")
	PlayerSession.company_service.post_transaction({"request_id":"tablet-income", "amount_marks":500, "category":"test_fixture"})
	ui._tablet.refresh()
	check(ui._tablet.snapshot.balance == LocalPlayerView.get_marks(), "account changes refresh")
	var purchase := PlayerSession.purchase_yard_vessel({"stock_id":"fishing_hook_line", "vessel_name":"Tablet Fisher", "request_id":"tablet-vessel"})
	check(bool(purchase.get("ok", false)), "purchase fixture through real company authority")
	if not PlayerSession.data.owned_vessels.is_empty():
		var record: Dictionary = PlayerSession.data.owned_vessels[0]
		PlayerSession.data.active_vessel = record
		var boat := VesselSpawn.instantiate_from_record(record)
		add_child(boat)
		boat.freeze = true
		PlayerVessel.mark_player_ship(boat)
		await get_tree().process_frame
		var holds := CatchHoldComponent.get_all_for_ship(boat)
		check(not holds.is_empty(), "production fishing vessel has real catch holds")
		if not holds.is_empty():
			holds[0].accept_lot(CatchLot.create({"lot_id":"tablet-cod", "species_id":"atlantic_cod", "mass_kg":12.0}))
			var data := LocalPlayerView.get_tablet_snapshot()
			check(data.fleet.size() == 1 and data.fleet[0].deployed, "snapshot identifies owned deployed vessel")
			check(is_equal_approx(float(data.fleet[0].catch_mass_kg), 12.0), "tablet mass follows real catch inventory")
			check(not data.fleet[0].cargo.is_empty(), "tablet manifest includes actual catch")
			holds[0].withdraw_oldest(12.0)
			check(is_zero_approx(float(LocalPlayerView.get_tablet_snapshot().fleet[0].catch_mass_kg)), "landing removes catch from tablet snapshot")
		PlayerVessel.unmark_player_ship(boat)
		boat.queue_free()
		await get_tree().process_frame
	ui.show_pause()
	check(not ui._tablet.visible and ui._card.visible, "pause and NPC panel regain presentation")
	ui.preview_mode = true
	ui.preview_data = {"balance":123,"company":{"name":"Preview","vessels":[]},"jobs":[{"id":"preview","commodity_id":"provisions"}],"voyage":{}}
	ui.show_tablet("Jobs")
	check(ui._tablet.current_page == "Contracts", "old Jobs entry routes to Contracts")
	ui._tablet.cancel_job_requested.emit(ui.preview_data.jobs[0])
	check(ui.page == "cancel_job" and ui._card.visible and not ui._tablet.visible, "cancel routes to existing confirmation")
	ui.show_tablet("Fleet")
	check(ui._tablet.current_page == "My fleet", "return to tablet after confirmation")
	ui.free()
	print("KONTOR_RESULT ", checks, " checks; failures: ", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
