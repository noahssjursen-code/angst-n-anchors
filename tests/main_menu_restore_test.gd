extends Node

var failures: PackedStringArray = []
var checks := 0
var menu: Control
var capture := false

func check(value: bool, description: String) -> void:
	checks += 1
	if not value: failures.append(description)
	print("MENU_RESTORE ", "PASS " if value else "FAIL ", description)

func button_in(node: Node, text: String) -> Button:
	if node is Button and node.text.nocasecmp_to(text) == 0: return node
	for child in node.get_children():
		var result := button_in(child, text)
		if result != null: return result
	return null

func _ready() -> void:
	assert(ShipyardPlaytestMode.active(), "Use --shipyard-playtest")
	capture = OS.get_cmdline_user_args().has("--capture-menu")
	call_deferred("run")

func shot(label: String) -> void:
	if not capture: return
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var archive := "C:/Users/noahs/Pictures/machinescreenshots"
	DirAccess.make_dir_recursive_absolute(archive)
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	var path := archive.path_join("%s-restored-menu-%s.png" % [stamp, label])
	get_viewport().get_texture().get_image().save_png(path)
	print("MENU_CAPTURE ", path)

func run() -> void:
	var baseline := PlayerSession.data.to_dict()
	menu = load("res://scenes/showcases/title_ui_showcase.tscn").instantiate()
	menu.show_backdrop = capture
	add_child(menu)
	check(button_in(menu._mode_root, "Singleplayer") != null, "singleplayer entry restored")
	check(button_in(menu._mode_root, "Multiplayer") != null, "multiplayer entry restored")
	if capture: await get_tree().create_timer(3.0).timeout
	await shot("home")
	if capture:
		# UI contrast check over the production ocean renderer, not a live voyage.
		menu._mode_root.hide()
		var hud := VoyageHud.new()
		hud.preview_mode = true
		add_child(hud)
		hud.present({"helming":true,"ahead_kn":8.4,"heading":84,"rudder":-12,"order":"HALF AHEAD","autopilot":true,"thruster":"Off","fuel":.81,"side_kn":.1})
		hud.present_interaction("F  Leave helm")
		await shot("helm-night-context")
		menu._backdrop.set_process(false)
		WeatherLighting.time_of_day = .5
		await get_tree().create_timer(3.0).timeout
		await shot("helm-day-context")
		WeatherLighting.time_of_day = .02
		menu._backdrop.set_process(true)
		hud.free()
		menu._mode_root.show()
	button_in(menu._mode_root, "Singleplayer").pressed.emit()
	check(menu._sp_root.visible and not menu._mode_root.visible, "singleplayer opens captain roster")
	check(button_in(menu._sp_roster, "Delete") != null, "captain deletion is visible")
	await shot("captains")
	button_in(menu._sp_roster, "Delete").pressed.emit()
	check(menu._sp_roster._delete_confirmation.visible, "delete asks which captain before deleting")
	await shot("delete-confirmation")
	menu._sp_roster._delete_confirmation.confirmed.emit()
	menu._sp_roster._delete_confirmation.hide()
	menu._show_page(menu.Page.MODE_SELECT)
	button_in(menu._mode_root, "Multiplayer").pressed.emit()
	check(menu._mp_root.visible and menu._server_list.get_child_count() == 3, "multiplayer opens server browser")
	check(menu._account_email.visible and menu._account_password.secret, "account sign-in controls restored")
	check(menu._active_pings.is_empty(), "preview makes no server requests")
	await shot("multiplayer")
	check(PlayerData.json_equivalent(baseline, PlayerSession.data.to_dict()), "previews do not mutate captain")
	menu._show_page(menu.Page.SINGLEPLAYER)
	menu._on_new_captain()
	check(menu._creator.visible, "captain appearance creation restored")
	menu._on_creator_confirmed("Test", CharacterAppearance.default_appearance())
	check(menu._company_setup.visible and menu._company_setup._intro.text.contains("coastal home") and menu._company_setup._starter_buttons.is_empty(), "new captain receives finished home without career selection")

	# Only this unique scratch directory participates in persistence checks.
	var scratch := OS.get_cache_dir().path_join("angst-menu-restore-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()])
	LocalCaptainStore.root_override = scratch
	PlayerSession._persistent_io_enabled = true
	menu.preview_mode = false
	menu._show_page(menu.Page.SINGLEPLAYER)
	var first := menu._captains.create_local("Keep captain", CharacterAppearance.default_appearance(), "test-port", 424242, "Keep company", Color.WHITE, "") as PlayerData
	check(first != null and first.owned_vessels.is_empty(), "local creation saves walk-up company without free vessel")
	var first_id := first.account_id
	var first_path := LocalCaptainStore.captain_dir(first_id).path_join("player.json")
	var first_bytes := FileAccess.get_file_as_bytes(first_path)
	var second := menu._captains.create_local("Delete captain", CharacterAppearance.default_appearance(), "test-port", 424242, "Delete company", Color.WHITE, "") as PlayerData
	var second_id := second.account_id
	check(FileAccess.get_file_as_bytes(first_path) == first_bytes, "creating second captain preserves first save")
	check(menu._captains.load_local_into_session(first_id), "saved captain reloads through production service")
	check(PlayerSession.data.display_name == "Keep captain", "resume loads selected captain")
	menu._captains.refresh()
	menu._captains.select(second_id)
	check(LocalCaptainStore.active_id == first_id, "roster selection alone does not redirect autosave")
	var delete_rows: Array = menu._sp_roster._list.get_children()
	var target_button: Button
	for row in delete_rows:
		if button_in(row, "Delete captain") != null:
			target_button = button_in(row, "Delete")
	check(target_button != null, "second captain has delete action")
	target_button.pressed.emit()
	check(DirAccess.dir_exists_absolute(LocalCaptainStore.captain_dir(second_id)), "opening delete confirmation keeps save")
	menu._sp_roster._delete_confirmation.confirmed.emit()
	menu._sp_roster._delete_confirmation.hide()
	check(not DirAccess.dir_exists_absolute(LocalCaptainStore.captain_dir(second_id)), "confirm deletes selected scratch captain")
	check(FileAccess.get_file_as_bytes(first_path) == first_bytes, "other captain survives deletion unchanged")
	check(LocalCaptainStore.list_captains().size() == 1, "roster refreshes after deletion")
	LocalCaptainStore.create_slot("empty-save")
	check(not menu._captains.load_local_into_session("empty-save"), "unreadable captain is refused instead of overwritten")
	check(not FileAccess.file_exists(LocalCaptainStore.captain_dir("empty-save").path_join("player.json")), "failed resume writes no replacement save")
	PlayerSession._persistent_io_enabled = false
	LocalCaptainStore.clear_active()
	LocalCaptainStore.root_override = ""
	menu.free()
	await get_tree().process_frame
	print("MENU_RESTORE_RESULT ", checks, " checks; ", failures.size(), " failures: ", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
