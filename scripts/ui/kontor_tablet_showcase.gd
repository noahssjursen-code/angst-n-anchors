extends Control

var panel: VoyagePanel
func _ready() -> void:
	assert(ShipyardPlaytestMode.active(), "Use --shipyard-playtest")
	GameMenu.set_gameplay_hud_visible(false)
	var background := ColorRect.new()
	background.color = Color("929b90")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	panel = VoyagePanel.new()
	panel.preview_mode = true
	panel.preview_data = {"balance":248650,"company":{"name":"Nordlys Maritime","vessels":[{"uid":"nordlys","name":"Nordlys"},{"uid":"havfrakt","name":"Havfrakt"}],"recent_transactions":[{"description":"Fish landing · Nordland Seafood","amount_marks":21840},{"description":"Fuel · Bodø Harbour","amount_marks":-1240}]},"voyage":{"ship":true,"name":"Nordlys","port":"Bodø","objective":"Nordlys is alongside. Your catch is ready to land."},"jobs":[{"id":"preview","commodity_id":"provisions","destination_name":"Svolvær","quantity":2,"loaded_quantity":1,"delivered_quantity":0,"quantity_unit":"containers","pay_marks":18400}]}
	add_child(panel)
	panel.show_tablet()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if OS.get_cmdline_user_args().has("--capture-tablet"): capture.call_deferred()

func capture() -> void:
	var archive := "C:/Users/noahs/Pictures/machinescreenshots"
	DirAccess.make_dir_recursive_absolute(archive)
	var stamp := str(Time.get_unix_time_from_system()).replace(".", "-")
	for page in ["Overview", "My fleet", "Contracts", "Finances", "SeaMail"]:
		panel.show_tablet(page)
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var path := archive.path_join("kontor-godot-%s-%s.png" % [stamp,page.replace(" ", "-")])
		get_viewport().get_texture().get_image().save_png(path)
		print("KONTOR_CAPTURE ", path)
	get_tree().quit()
