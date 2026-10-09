extends Node

var failures: Array[String] = []
var checks: Array[Dictionary] = []
var output := ""


func check(ok: bool, label: String) -> bool:
	checks.append({"ok": ok, "check": label})
	print("DEV CAPTAIN ", "PASS " if ok else "FAIL ", label)
	if not ok:
		failures.append(label)
	return ok


func _ready() -> void:
	assert(ShipyardPlaytestMode.active())
	call_deferred("run")


func run() -> void:
	output = "C:/Users/noahs/Pictures/machinescreenshots/development-captain-" + str(Time.get_unix_time_from_system()).replace(".", "-")
	DirAccess.make_dir_recursive_absolute(output)
	LocalCaptainStore.root_override = output.path_join("scratch-save")
	LocalCaptainStore.clear_active()
	PlayerSession._persistent_io_enabled = true
	var service := CaptainService.new()
	service.configure_local()
	var normal := service.create_local("Ordinary captain", CharacterAppearance.default_appearance(), "port-home", 424242)
	if not check(normal != null, "ordinary captain saved in isolated slot"):
		finish(); return
	var normal_id := normal.account_id
	var normal_path := LocalCaptainStore.captain_dir(normal_id).path_join("player.json")
	var normal_hash := FileAccess.get_sha256(normal_path)
	check(DevelopmentFleet.synchronize(normal) == 0, "normal captain receives no development grants")
	var menu := preload("res://scripts/ui/main_menu.gd").new()
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(menu)
	menu._show_page(menu.Page.SINGLEPLAYER)
	var action: Button
	for node in menu.find_children("*", "Button", true, false):
		if node.text.to_lower() == "development captain · all ships":
			action = node
	if not check(action != null, "single-player menu exposes development captain"):
		finish(); return
	action.pressed.emit()
	var dev: PlayerData = PlayerSession.data
	if not check(DevelopmentFleet.is_development(dev), "menu creates development captain"):
		finish(); return
	var dev_id := dev.account_id
	var count := DevelopmentFleet.catalog_entries().size()
	check(dev_id != normal_id, "development captain uses a separate save slot")
	check(dev.owned_vessels.size() == count and count >= 6, "all catalog vessels owned, including Northline and ferry")
	var names: Array[String] = []
	for record: Dictionary in dev.owned_vessels:
		names.append(VesselSpawn.vessel_name_of(record))
		check(not VesselSpawn.resolve_deployable_record(record).is_empty(), "deployable: " + names.back())
	check(bool(dev.company.get("tablet_received", false)), "company tablet unlocked")
	check(FileAccess.get_sha256(normal_path) == normal_hash, "creating development fleet preserves ordinary captain bytes")
	var saved := PlayerSaveStore.load_player()
	check(saved.owned_vessels.size() == count and DevelopmentFleet.is_development(saved), "fleet and opt-in marker survive disk roundtrip")
	# Model an older development save from before the latest stock was added.
	var first: Dictionary = dev.owned_vessels[0].duplicate(true)
	first.name = "My edited development ship"
	first.brick_layout.hull_colors = {"hull": [0.3, 0.4, 0.5, 1.0]}
	dev.upsert_owned_vessel(first)
	dev.set_active_vessel(first)
	var missing_id := "coastal_express"
	var missing_uid := str(dev.company.development_fleet[missing_id])
	dev.owned_vessels = dev.owned_vessels.filter(func(record: Dictionary): return str(record.uid) != missing_uid)
	dev.company.development_fleet.erase(missing_id)
	# An older save cannot already contain a recovery archive of future stock.
	var future_archive := LocalCaptainStore.captain_dir(dev_id).path_join("vessels").path_join(missing_uid + ".json")
	check(DirAccess.remove_absolute(future_archive) == OK, "older-save fixture removes future vessel recovery copy")
	check(PlayerSaveStore.save_player(dev), "older development fleet fixture saved")
	check(service.load_local_into_session(dev_id), "normal Sail load synchronizes newly added stock")
	dev = PlayerSession.data
	check(dev.owned_vessels.size() == count and dev.company.development_fleet.has(missing_id), "missing catalog entry added automatically")
	check(PlayerData.json_equivalent(dev.find_owned_vessel(str(first.uid)), first), "custom name and paint preserved exactly")
	check(str(dev.active_vessel.uid) == str(first.uid), "active vessel selection preserved")
	var fleet_before := JSON.stringify(dev.owned_vessels)
	action.pressed.emit()
	check(PlayerSession.data.account_id == dev_id and LocalCaptainStore.list_captains().size() == 2, "repeated button reuses development captain")
	check(JSON.stringify(PlayerSession.data.owned_vessels) == fleet_before, "repeated load does not duplicate or reset ships")
	check(FileAccess.get_sha256(normal_path) == normal_hash, "all development operations leave normal save unchanged")
	for frame in 80:
		await get_tree().process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(output.path_join("singleplayer-development-captain.png"))
	check(service.load_local_into_session(normal_id), "normal captain can still load")
	check(PlayerSession.data.owned_vessels.size() == normal.owned_vessels.size(), "normal captain still has only its original fleet")
	# No cleanup touches real saves; retain the scratch files for report inspection.
	finish(names)


func finish(names: Array[String] = []) -> void:
	PlayerSession._persistent_io_enabled = false
	var file := FileAccess.open(output.path_join("report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "failures": failures, "ships": names}, "\t"))
	print("DEV CAPTAIN REPORT ", output, " ", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
