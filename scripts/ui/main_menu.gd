extends Control

## Title orchestrator — pages call services; services own persistence/network.

const RosterPanelScript := preload("res://scripts/ui/captain_roster_panel.gd")
const MenuBackdropScript := preload("res://scripts/ui/menu_backdrop.gd")
const ChartPreviewBootstrapScript := preload("res://scripts/ui/chart/chart_preview_bootstrap.gd")
const CaptainServiceScript := preload("res://scripts/player/captain_service.gd")
const WorldBootstrapScript := preload("res://scripts/world/world_bootstrap.gd")

enum Page { MODE_SELECT, SINGLEPLAYER, MULTIPLAYER, CREATOR, HOME_PORT }

var _page: Page = Page.MODE_SELECT
var _creating_new := false
var _pending_name := ""
var _pending_appearance: CharacterAppearance = null
var _pending_seed := 0

var _captains = CaptainServiceScript.new()
var _backdrop
var _mode_root: CenterContainer
var _sp_root: CenterContainer
var _mp_root: CenterContainer
var _sp_roster
var _mp_roster
var _creator: CharacterCreatorPanel
var _home_port_layer: CanvasLayer
var _home_port_chart: MapOverlay
var _chart_bootstrap = ChartPreviewBootstrapScript.new()

var _server_list: VBoxContainer
var _active_pings: Dictionary = {}
var _mp_status: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_ensure_menu_offline()
	LocalCaptainStore.ensure_migrated()

	_backdrop = MenuBackdropScript.new()
	_backdrop.name = "MenuBackdrop"
	add_child(_backdrop)

	_build_vignette()
	_build_mode_page()
	_build_singleplayer_page()
	_build_multiplayer_page()
	_build_creator()
	_build_home_port()

	_captains.roster_changed.connect(_on_roster_changed)
	_captains.captain_selected.connect(_on_captain_selected)
	_captains.error_message.connect(_on_captain_error)
	_captains.remote.world_options_ready.connect(_on_world_options)
	_captains.remote.request_failed.connect(func(action: String, message: String) -> void:
		if action == "world_options":
			_mp_status.text = message
			WorldBootstrapScript.apply_seed(42)
			WorldBootstrapScript.enter_world(get_tree(), true)
		else:
			_on_captain_error(message)
	)

	_show_page(Page.MODE_SELECT)


func _build_vignette() -> void:
	var vignette := ColorRect.new()
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.color = Color(0.01, 0.02, 0.04, 0.34)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vignette)


func _build_mode_page() -> void:
	_mode_root = _make_page_root("ModeSelectPage")
	var vbox := _make_panel(_mode_root, Vector2(400, 0))
	_add_title(vbox, "ANGST 'N ANCHORS", 28)
	_add_tag(vbox, "Maritime trade on a cold coast")
	vbox.add_child(HSeparator.new())
	_add_button(vbox, "Singleplayer", func() -> void: _show_page(Page.SINGLEPLAYER))
	_add_button(vbox, "Multiplayer", func() -> void: _show_page(Page.MULTIPLAYER))
	vbox.add_child(HSeparator.new())
	_add_button(vbox, "Quit", _on_quit)


func _build_singleplayer_page() -> void:
	_sp_root = _make_page_root("SingleplayerPage")
	_sp_root.visible = false
	var vbox := _make_panel(_sp_root, Vector2(520, 0))
	_add_title(vbox, "SINGLEPLAYER", 18)
	vbox.add_child(HSeparator.new())
	_sp_roster = RosterPanelScript.new()
	_sp_roster.configure(true, false)
	_sp_roster.sail_pressed.connect(_on_sp_sail)
	_sp_roster.delete_pressed.connect(func(id: String) -> void: _captains.delete_selected_or(id))
	_sp_roster.create_pressed.connect(_on_new_captain)
	_sp_roster.selected.connect(func(id: String) -> void: _captains.select(id))
	vbox.add_child(_sp_roster)
	vbox.add_child(HSeparator.new())
	_add_button(vbox, "Back", func() -> void: _show_page(Page.MODE_SELECT))


func _build_multiplayer_page() -> void:
	_mp_root = _make_page_root("MultiplayerPage")
	_mp_root.visible = false
	var vbox := _make_panel(_mp_root, Vector2(560, 0))
	_add_title(vbox, "MULTIPLAYER", 18)
	vbox.add_child(HSeparator.new())

	var servers_lbl := Label.new()
	servers_lbl.text = "SERVERS"
	servers_lbl.add_theme_font_size_override("font_size", 12)
	servers_lbl.add_theme_color_override("font_color", HudStyle.C_AMBER)
	vbox.add_child(servers_lbl)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 90)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)
	_server_list = VBoxContainer.new()
	_server_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_server_list)

	vbox.add_child(HSeparator.new())
	_mp_roster = RosterPanelScript.new()
	_mp_roster.configure(false, OS.is_debug_build(), func(entry: Dictionary) -> void:
		_captains.remote.update_marks(str(entry.get("id", "")), int(entry.get("marks", 0)) + 1_000_000)
	)
	_mp_roster.sail_pressed.connect(_on_mp_sail)
	_mp_roster.delete_pressed.connect(func(id: String) -> void: _captains.delete_selected_or(id))
	_mp_roster.create_pressed.connect(_on_new_captain)
	_mp_roster.selected.connect(_on_mp_select)
	vbox.add_child(_mp_roster)

	_mp_status = Label.new()
	_mp_status.add_theme_font_size_override("font_size", 11)
	_mp_status.add_theme_color_override("font_color", HudStyle.C_LABEL)
	vbox.add_child(_mp_status)

	vbox.add_child(HSeparator.new())
	_add_button(vbox, "Back", func() -> void: _show_page(Page.MODE_SELECT))


func _build_creator() -> void:
	_creator = CharacterCreatorPanel.new()
	_creator.name = "CharacterCreator"
	_creator.visible = false
	_creator.confirmed.connect(_on_creator_confirmed)
	_creator.cancelled.connect(_on_creator_cancelled)
	add_child(_creator)


func _build_home_port() -> void:
	_home_port_layer = CanvasLayer.new()
	_home_port_layer.layer = 25
	_home_port_layer.visible = false
	add_child(_home_port_layer)
	_home_port_chart = MapOverlay.new()
	_home_port_chart.visible = false
	_home_port_chart.process_mode = Node.PROCESS_MODE_ALWAYS
	_home_port_chart.home_port_confirmed.connect(_on_home_port_confirmed)
	_home_port_chart.home_port_cancelled.connect(_on_home_port_cancelled)
	_home_port_layer.add_child(_home_port_chart)


func _show_page(page: Page) -> void:
	_page = page
	_mode_root.visible = page == Page.MODE_SELECT
	_sp_root.visible = page == Page.SINGLEPLAYER
	_mp_root.visible = page == Page.MULTIPLAYER
	_creator.visible = page == Page.CREATOR
	_home_port_layer.visible = page == Page.HOME_PORT
	if page != Page.HOME_PORT:
		_teardown_home_port_chart()

	var config := get_node_or_null("/root/ServerConfig")
	if config != null:
		config.set("is_multiplayer_mode", page == Page.MULTIPLAYER)

	match page:
		Page.SINGLEPLAYER:
			_backdrop.set_cinematic("singleplayer")
			_captains.configure_local()
		Page.MULTIPLAYER:
			_backdrop.set_cinematic("multiplayer")
			_refresh_servers()
		Page.CREATOR:
			_backdrop.set_cinematic("creator")
		_:
			_backdrop.set_cinematic("mode")
			_ensure_menu_offline()


func _on_roster_changed(entries: Array) -> void:
	if _page == Page.SINGLEPLAYER and _sp_roster != null:
		_sp_roster.set_entries(entries, _captains.selected_id)
	elif _page == Page.MULTIPLAYER and _mp_roster != null:
		_mp_roster.set_entries(entries, _captains.selected_id)


func _on_captain_selected(_entry: Dictionary) -> void:
	if _page == Page.SINGLEPLAYER and _sp_roster != null:
		_sp_roster.set_entries(_captains.entries(), _captains.selected_id)
	elif _page == Page.MULTIPLAYER and _mp_roster != null:
		_mp_roster.set_entries(_captains.entries(), _captains.selected_id)


func _on_captain_error(message: String) -> void:
	if _page == Page.MULTIPLAYER and _mp_roster != null:
		_mp_roster.set_message(message)
	elif _page == Page.SINGLEPLAYER and _sp_roster != null:
		_sp_roster.set_message(message)


func _on_new_captain() -> void:
	_creating_new = true
	_pending_seed = WorldBootstrapScript.roll_seed() if _page == Page.SINGLEPLAYER else 0
	_creator.open_with_existing(null)
	_show_page(Page.CREATOR)


func _on_creator_confirmed(display_name: String, appearance: CharacterAppearance) -> void:
	_pending_name = display_name
	_pending_appearance = appearance
	var config := get_node_or_null("/root/ServerConfig")
	var is_mp := config != null and bool(config.get("is_multiplayer_mode"))
	if is_mp:
		_captains.create_remote(display_name, appearance)
		_show_page(Page.MULTIPLAYER)
		return
	if _creating_new:
		_show_home_port_picker()
	else:
		_show_page(Page.SINGLEPLAYER)


func _on_creator_cancelled() -> void:
	_creating_new = false
	var config := get_node_or_null("/root/ServerConfig")
	if config != null and bool(config.get("is_multiplayer_mode")):
		_show_page(Page.MULTIPLAYER)
	else:
		_show_page(Page.SINGLEPLAYER)


func _show_home_port_picker() -> void:
	if _pending_seed <= 0:
		_pending_seed = WorldBootstrapScript.roll_seed()
	WorldBootstrapScript.apply_seed(_pending_seed)
	var snapshot = _chart_bootstrap.activate(self, _pending_seed)
	_home_port_chart.set_data_snapshot(snapshot)
	_home_port_chart.enter_home_port_pick_mode()
	_home_port_chart.visible = true
	_show_page(Page.HOME_PORT)


func _on_home_port_confirmed(port_id: String) -> void:
	var preview_checksum := ""
	if _chart_bootstrap != null and _chart_bootstrap.snapshot != null:
		preview_checksum = str(_chart_bootstrap.snapshot.layout_checksum)
	_teardown_home_port_chart()
	# Keep the exact seed shown on the picker — do not re-roll after create.
	var settings := get_node_or_null("/root/GameSettings")
	var gen_version := int(settings.get("map_generation_version")) if settings != null else 4
	WorldBootstrapScript.apply_seed(_pending_seed, gen_version, preview_checksum)
	_captains.create_local(_pending_name, _pending_appearance, port_id, _pending_seed)
	var session := get_node_or_null("/root/PlayerSession")
	if session != null and session.data != null:
		session.data.world_context = {
			"seed": _pending_seed,
			"generation_version": gen_version,
			"layout_checksum": preview_checksum,
		}
		# Save without letting an empty live-world snapshot wipe the seed again.
		session.save_now()
		WorldBootstrapScript.apply_seed(_pending_seed, gen_version, preview_checksum)
	_creating_new = false
	WorldBootstrapScript.enter_world(get_tree(), false)


func _on_home_port_cancelled() -> void:
	_teardown_home_port_chart()
	_show_page(Page.CREATOR)


func _teardown_home_port_chart() -> void:
	_chart_bootstrap.deactivate()
	if _home_port_chart != null:
		if _home_port_chart.is_home_port_pick_mode():
			_home_port_chart.exit_home_port_pick_mode()
		_home_port_chart.visible = false


func _on_sp_sail(captain_id: String) -> void:
	if not _captains.load_local_into_session(captain_id):
		_sp_roster.set_message("Could not load that captain.")
		return
	var session := get_node("/root/PlayerSession")
	WorldBootstrapScript.apply_player_world_context(session.data)
	WorldBootstrapScript.enter_world(get_tree(), false)


func _on_mp_select(captain_id: String) -> void:
	for entry_raw in _captains.entries():
		if typeof(entry_raw) != TYPE_DICTIONARY:
			continue
		var entry := entry_raw as Dictionary
		if str(entry.get("id", "")) == captain_id:
			_captains.apply_remote_selection(entry)
			return


func _on_mp_sail(_captain_id: String) -> void:
	if _captains.selected_id.is_empty():
		return
	_mp_status.text = "Loading world settings…"
	_captains.remote.fetch_world_options()


func _on_world_options(options: Dictionary) -> void:
	_mp_status.text = ""
	WorldBootstrapScript.apply_mp_world_options(options)
	WorldBootstrapScript.enter_world(get_tree(), true)


func _refresh_servers() -> void:
	for child in _server_list.get_children():
		child.queue_free()
	for req in _active_pings.values():
		if is_instance_valid(req):
			req.queue_free()
	_active_pings.clear()

	var config := get_node_or_null("/root/ServerConfig")
	if config == null:
		return
	var servers: Array = [
		{"id": "local", "label": "Localhost", "is_preset": true, "host": "127.0.0.1", "http_host": "127.0.0.1", "http_port": 8080},
		{"id": "digital_ocean", "label": "Ocean server", "is_preset": true, "host": "142.93.43.16", "http_host": "142.93.43.16", "http_port": 8080},
		{"id": "custom", "label": "Custom", "is_preset": false, "host": str(config.get("udp_host")), "http_host": str(config.get("http_host")), "http_port": int(config.get("http_port"))},
	]
	for s in servers:
		_add_server_row(s, config)


func _add_server_row(s: Dictionary, config: Node) -> void:
	var row := HBoxContainer.new()
	_server_list.add_child(row)
	var status_dot := Label.new()
	status_dot.text = "●"
	status_dot.add_theme_color_override("font_color", Color.GRAY)
	row.add_child(status_dot)
	var name_lbl := Label.new()
	name_lbl.text = str(s["label"])
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_lbl)
	var ping_lbl := Label.new()
	ping_lbl.text = "…"
	ping_lbl.custom_minimum_size.x = 70
	row.add_child(ping_lbl)
	var players_lbl := Label.new()
	players_lbl.text = ""
	players_lbl.custom_minimum_size.x = 80
	row.add_child(players_lbl)
	var select_btn := Button.new()
	select_btn.text = "Select"
	row.add_child(select_btn)

	var is_active := str(config.get("preset")) == str(s["id"])
	if is_active:
		select_btn.text = "Active"
		select_btn.disabled = true
		name_lbl.add_theme_color_override("font_color", HudStyle.C_AMBER)
	else:
		select_btn.pressed.connect(func() -> void:
			if bool(s["is_preset"]):
				config.call("use_preset", str(s["id"]))
			else:
				config.call("use_custom", str(s["host"]), int(config.get("udp_port")), str(s["http_host"]), int(s["http_port"]))
			_refresh_servers()
		)

	var http_url := "http://%s:%d/v1/entities" % [s["http_host"], s["http_port"]]
	var start_time := Time.get_ticks_msec()
	var http_req := HTTPRequest.new()
	add_child(http_req)
	http_req.timeout = 2.0
	_active_pings[http_url] = http_req
	http_req.request_completed.connect(func(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
		if is_instance_valid(http_req):
			http_req.queue_free()
		_active_pings.erase(http_url)
		if not is_instance_valid(row):
			return
		var duration_ms := Time.get_ticks_msec() - start_time
		if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
			status_dot.add_theme_color_override("font_color", Color.GREEN)
			ping_lbl.text = "%d ms" % duration_ms
			var count := 0
			var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
			if typeof(parsed) == TYPE_DICTIONARY:
				count = int((parsed as Dictionary).get("count", 0))
			players_lbl.text = "%d active" % count
			if is_active:
				_captains.configure_remote(self, "http://%s:%d" % [s["http_host"], s["http_port"]])
		else:
			status_dot.add_theme_color_override("font_color", Color.RED)
			ping_lbl.text = "Offline"
			players_lbl.text = "Offline"
			if is_active:
				_mp_roster.set_message("Server is offline.")
	)
	if http_req.request(http_url) != OK:
		status_dot.add_theme_color_override("font_color", Color.RED)
		ping_lbl.text = "Error"
		http_req.queue_free()
		_active_pings.erase(http_url)


func _ensure_menu_offline() -> void:
	var config := get_node_or_null("/root/ServerConfig")
	if config != null:
		config.set("is_multiplayer_mode", false)
	var network := get_node_or_null("/root/NetworkManager")
	if network != null and network.has_method("end_multiplayer_session"):
		network.call("end_multiplayer_session", true)


func _on_quit() -> void:
	var session := get_node_or_null("/root/PlayerSession")
	if session != null and session.has_method("save_now"):
		session.call("save_now")
	get_tree().quit()


func _make_page_root(page_name: String) -> CenterContainer:
	var root := CenterContainer.new()
	root.name = page_name
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	return root


func _make_panel(root: CenterContainer, min_size: Vector2) -> VBoxContainer:
	var panel := Panel.new()
	panel.theme = HudStyle.make_theme()
	panel.custom_minimum_size = min_size
	root.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_bottom", 28)
	panel.add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)
	return vbox


func _add_title(parent: Node, text: String, size: int) -> void:
	var title := Label.new()
	title.text = text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", size)
	title.add_theme_color_override("font_color", HudStyle.C_AMBER)
	parent.add_child(title)


func _add_tag(parent: Node, text: String) -> void:
	var tag := Label.new()
	tag.text = text
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.add_theme_font_size_override("font_size", 13)
	tag.add_theme_color_override("font_color", HudStyle.C_LABEL)
	parent.add_child(tag)


func _add_button(parent: Node, text: String, on_press: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(on_press)
	parent.add_child(button)
	return button
