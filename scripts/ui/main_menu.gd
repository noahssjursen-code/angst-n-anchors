extends Control

## Title orchestrator — pages call services; services own persistence/network.

const RosterPanelScript := preload("res://scripts/ui/captain_roster_panel.gd")
const MenuBackdropScript := preload("res://scripts/ui/menu_backdrop.gd")
const ChartPreviewBootstrapScript := preload("res://scripts/ui/chart/chart_preview_bootstrap.gd")
const CaptainServiceScript := preload("res://scripts/player/captain_service.gd")
const WorldBootstrapScript := preload("res://scripts/world/world_bootstrap.gd")

enum Page { MODE_SELECT, SINGLEPLAYER, MULTIPLAYER, CREATOR, COMPANY_SETUP, HOME_PORT }

var _page: Page = Page.MODE_SELECT
var _creating_new := false
var _pending_name := ""
var _pending_appearance: CharacterAppearance = null
var _pending_company_name := ""
var _pending_brand_color := Color("2f7f83")
var _pending_starter_vessel := "general_cargo"
var _pending_seed := 0

var _captains = CaptainServiceScript.new()
var _backdrop
var _mode_root: MarginContainer
var _sp_root: MarginContainer
var _mp_root: MarginContainer
var _sp_roster
var _mp_roster
var _creator: CharacterCreatorPanel
var _company_setup: CompanySetupPanel
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
	_build_company_setup()
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
	# Light overall wash only — ocean stays the stage.
	var wash := ColorRect.new()
	wash.set_anchors_preset(Control.PRESET_FULL_RECT)
	wash.color = Color(0.02, 0.04, 0.05, 0.16)
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(wash)


func _build_mode_page() -> void:
	_mode_root = _make_brand_page_root("ModeSelectPage")
	var stack := _mode_root.get_node("Align/Stack") as VBoxContainer

	var brand := VBoxContainer.new()
	brand.add_theme_constant_override("separation", 0)
	stack.add_child(brand)

	var angst := Label.new()
	angst.text = "ANGST"
	angst.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	HudStyle.apply_display_font(angst, 92, HudStyle.C_TEXT)
	brand.add_child(angst)

	var anchors := Label.new()
	anchors.text = "'N ANCHORS"
	anchors.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	HudStyle.apply_display_font(anchors, 56, HudStyle.C_AMBER)
	brand.add_child(anchors)

	var rule := ColorRect.new()
	rule.custom_minimum_size = Vector2(148, 2)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	rule.color = HudStyle.C_COPPER
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rule_pad := MarginContainer.new()
	rule_pad.add_theme_constant_override("margin_top", 8)
	rule_pad.add_theme_constant_override("margin_bottom", 12)
	rule_pad.add_child(rule)
	brand.add_child(rule_pad)

	var tag := Label.new()
	tag.text = "Build a company on cold northern waters"
	HudStyle.apply_body_font(tag, 15, HudStyle.C_LABEL)
	brand.add_child(tag)

	var actions := VBoxContainer.new()
	actions.add_theme_constant_override("separation", 4)
	var actions_pad := MarginContainer.new()
	actions_pad.add_theme_constant_override("margin_top", 32)
	actions_pad.add_child(actions)
	stack.add_child(actions_pad)

	_add_action(actions, "Singleplayer", func() -> void: _show_page(Page.SINGLEPLAYER))
	_add_action(actions, "Multiplayer", func() -> void: _show_page(Page.MULTIPLAYER))

	var quit_pad := MarginContainer.new()
	quit_pad.add_theme_constant_override("margin_top", 20)
	stack.add_child(quit_pad)
	var quit := MenuActionButton.new()
	quit.text = "Quit"
	HudStyle.apply_body_font(quit, 14, HudStyle.C_LABEL, false)
	quit.pressed.connect(_on_quit)
	quit_pad.add_child(quit)


func _build_singleplayer_page() -> void:
	_sp_root = _make_side_page_root("SingleplayerPage")
	_sp_root.visible = false
	var vbox := _sp_root.get_node("Panel/Margin/VBox") as VBoxContainer
	_add_page_heading(vbox, "SINGLEPLAYER", "Local captains · private waters")
	_sp_roster = RosterPanelScript.new()
	_sp_roster.configure(true, false)
	_sp_roster.sail_pressed.connect(_on_sp_sail)
	_sp_roster.delete_pressed.connect(func(id: String) -> void: _captains.delete_selected_or(id))
	_sp_roster.create_pressed.connect(_on_new_captain)
	_sp_roster.selected.connect(func(id: String) -> void: _captains.select(id))
	_sp_roster.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_sp_roster)
	_add_action(vbox, "Back", func() -> void: _show_page(Page.MODE_SELECT))


func _build_multiplayer_page() -> void:
	_mp_root = _make_side_page_root("MultiplayerPage")
	_mp_root.visible = false
	var vbox := _mp_root.get_node("Panel/Margin/VBox") as VBoxContainer
	_add_page_heading(vbox, "MULTIPLAYER", "Shared waters · pick a harbour net")

	var servers_lbl := Label.new()
	servers_lbl.text = "SERVERS"
	HudStyle.apply_body_font(servers_lbl, 11, HudStyle.C_COPPER, true)
	vbox.add_child(servers_lbl)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 100)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)
	_server_list = VBoxContainer.new()
	_server_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_server_list)

	var rule := HSeparator.new()
	vbox.add_child(rule)

	_mp_roster = RosterPanelScript.new()
	_mp_roster.configure(false, OS.is_debug_build(), func(entry: Dictionary) -> void:
		_captains.remote.update_marks(str(entry.get("id", "")), int(entry.get("marks", 0)) + 1_000_000)
	)
	_mp_roster.sail_pressed.connect(_on_mp_sail)
	_mp_roster.delete_pressed.connect(func(id: String) -> void: _captains.delete_selected_or(id))
	_mp_roster.create_pressed.connect(_on_new_captain)
	_mp_roster.selected.connect(_on_mp_select)
	_mp_roster.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_mp_roster)

	_mp_status = Label.new()
	HudStyle.apply_body_font(_mp_status, 12, HudStyle.C_LABEL)
	vbox.add_child(_mp_status)

	_add_action(vbox, "Back", func() -> void: _show_page(Page.MODE_SELECT))


func _build_creator() -> void:
	_creator = CharacterCreatorPanel.new()
	_creator.name = "CharacterCreator"
	_creator.visible = false
	_creator.confirmed.connect(_on_creator_confirmed)
	_creator.cancelled.connect(_on_creator_cancelled)
	add_child(_creator)


func _build_company_setup() -> void:
	_company_setup = CompanySetupPanel.new()
	_company_setup.name = "CompanySetup"
	_company_setup.visible = false
	_company_setup.confirmed.connect(_on_company_confirmed)
	_company_setup.cancelled.connect(func() -> void: _show_page(Page.CREATOR))
	add_child(_company_setup)


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
	_company_setup.visible = page == Page.COMPANY_SETUP
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
		Page.COMPANY_SETUP:
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
		_company_setup.open_for_captain(_pending_name)
		_show_page(Page.COMPANY_SETUP)
	else:
		_show_page(Page.SINGLEPLAYER)


func _on_creator_cancelled() -> void:
	_creating_new = false
	var config := get_node_or_null("/root/ServerConfig")
	if config != null and bool(config.get("is_multiplayer_mode")):
		_show_page(Page.MULTIPLAYER)
	else:
		_show_page(Page.SINGLEPLAYER)


func _on_company_confirmed(company_name: String, brand_color: Color, starter_vessel: String) -> void:
	_pending_company_name = company_name
	_pending_brand_color = brand_color
	_pending_starter_vessel = starter_vessel
	_show_home_port_picker()


func _show_home_port_picker() -> void:
	if _pending_seed <= 0:
		_pending_seed = WorldBootstrapScript.roll_seed()
	WorldBootstrapScript.apply_seed(_pending_seed)
	var settings := get_node_or_null("/root/GameSettings")
	var world_size_m := float(settings.get("map_world_size_m")) if settings != null else 40000.0
	var world_preset := str(settings.get("map_world_preset")) if settings != null else "standard"
	var snapshot = _chart_bootstrap.activate(
		self,
		_pending_seed,
		35,
		world_size_m,
		world_preset,
	)
	_home_port_chart.set_data_snapshot(snapshot)
	_home_port_chart.set_home_port_required_family(_starter_terminal_family(_pending_starter_vessel))
	_home_port_chart.enter_home_port_pick_mode()
	_home_port_chart.visible = true
	_show_page(Page.HOME_PORT)


static func _starter_terminal_family(starter_vessel: String) -> String:
	match starter_vessel:
		"fishing":
			return "fishing"
		"bulk":
			return "bulk"
		"general_cargo":
			return "general"
	return ""


func _on_home_port_confirmed(port_id: String) -> void:
	var preview_checksum := ""
	var preview_snapshot = _chart_bootstrap.snapshot if _chart_bootstrap != null else null
	if preview_snapshot != null:
		preview_checksum = str(preview_snapshot.layout_checksum)
	_teardown_home_port_chart()
	# Keep the exact seed shown on the picker — do not re-roll after create.
	var settings := get_node_or_null("/root/GameSettings")
	var gen_version := int(settings.get("map_generation_version")) if settings != null else 8
	var world_size_m := float(preview_snapshot.world_size_m) \
			if preview_snapshot != null else 40000.0
	var world_preset := str(preview_snapshot.world_preset) \
			if preview_snapshot != null else "standard"
	WorldBootstrapScript.apply_seed(_pending_seed, gen_version, preview_checksum, 3, world_size_m, world_preset)
	_captains.create_local(
		_pending_name, _pending_appearance, port_id, _pending_seed,
		_pending_company_name, _pending_brand_color, _pending_starter_vessel,
	)
	var session := get_node_or_null("/root/PlayerSession")
	if session != null and session.data != null:
		session.data.world_context = {
			"seed": _pending_seed,
			"world_size_m": world_size_m,
			"world_preset": world_preset,
			"generation_version": gen_version,
			"weather_generation_version": 3,
			"layout_checksum": preview_checksum,
		}
		# Save without letting an empty live-world snapshot wipe the seed again.
		session.save_now()
		WorldBootstrapScript.apply_seed(_pending_seed, gen_version, preview_checksum, 3, world_size_m, world_preset)
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


func _make_brand_page_root(page_name: String) -> MarginContainer:
	var root := MarginContainer.new()
	root.name = page_name
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("margin_left", 56)
	root.add_theme_constant_override("margin_right", 56)
	root.add_theme_constant_override("margin_top", 48)
	root.add_theme_constant_override("margin_bottom", 48)
	add_child(root)

	var align := VBoxContainer.new()
	align.name = "Align"
	align.set_anchors_preset(Control.PRESET_FULL_RECT)
	align.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(align)

	var stack := VBoxContainer.new()
	stack.name = "Stack"
	stack.add_theme_constant_override("separation", 8)
	stack.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	stack.custom_minimum_size = Vector2(420, 0)
	align.add_child(stack)
	return root


func _make_side_page_root(page_name: String) -> MarginContainer:
	var root := MarginContainer.new()
	root.name = page_name
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("margin_left", 48)
	root.add_theme_constant_override("margin_right", 48)
	root.add_theme_constant_override("margin_top", 48)
	root.add_theme_constant_override("margin_bottom", 48)
	add_child(root)

	var panel := Panel.new()
	panel.name = "Panel"
	panel.theme = HudStyle.make_theme()
	panel.add_theme_stylebox_override("panel", HudStyle.make_title_panel_style())
	panel.custom_minimum_size = Vector2(520, 520)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(panel)

	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	vbox.add_theme_constant_override("separation", 14)
	margin.add_child(vbox)
	return root


func _add_page_heading(parent: Node, title_text: String, subtitle: String) -> void:
	var title := Label.new()
	title.text = title_text
	HudStyle.apply_display_font(title, 42, HudStyle.C_TEXT)
	parent.add_child(title)
	var sub := Label.new()
	sub.text = subtitle
	HudStyle.apply_body_font(sub, 13, HudStyle.C_LABEL)
	parent.add_child(sub)
	var rule := ColorRect.new()
	rule.custom_minimum_size = Vector2(120, 2)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	rule.color = HudStyle.C_COPPER
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(rule)


func _add_action(parent: Node, text: String, on_press: Callable) -> MenuActionButton:
	var button := MenuActionButton.new()
	button.text = text
	button.pressed.connect(on_press)
	parent.add_child(button)
	return button


## Legacy helpers kept for any remaining call sites.
func _make_page_root(page_name: String) -> CenterContainer:
	var root := CenterContainer.new()
	root.name = page_name
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	return root


func _make_panel(root: CenterContainer, min_size: Vector2) -> VBoxContainer:
	var panel := Panel.new()
	panel.theme = HudStyle.make_theme()
	panel.add_theme_stylebox_override("panel", HudStyle.make_title_panel_style())
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
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	HudStyle.apply_display_font(title, size, HudStyle.C_TEXT)
	parent.add_child(title)


func _add_tag(parent: Node, text: String) -> void:
	var tag := Label.new()
	tag.text = text
	HudStyle.apply_body_font(tag, 13, HudStyle.C_LABEL)
	parent.add_child(tag)


func _add_button(parent: Node, text: String, on_press: Callable) -> Button:
	return _add_action(parent, text, on_press)
