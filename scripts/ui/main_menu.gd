extends Control

## Title orchestrator — pages call services; services own persistence/network.

const RosterPanelScript := preload("res://scripts/ui/captain_roster_panel.gd")
const MenuBackdropScript := preload("res://scripts/ui/menu_backdrop.gd")
const ChartPreviewBootstrapScript := preload("res://scripts/ui/chart/chart_preview_bootstrap.gd")
const CaptainServiceScript := preload("res://scripts/player/captain_service.gd")
const WorldBootstrapScript := preload("res://scripts/world/world_bootstrap.gd")
const BRAND_MARK := preload("res://resources/ui/brand/anchor-mark-paper.svg")

enum Page { MODE_SELECT, SINGLEPLAYER, MULTIPLAYER, CREATOR, COMPANY_SETUP, HOME_PORT }

var _page: Page = Page.MODE_SELECT
var _creating_new := false
var _pending_name := ""
var _pending_appearance: CharacterAppearance = null
var _pending_company_name := ""
var _pending_brand_color := Color("2f7f83")
var _pending_starter_vessel := "general_cargo"
var _pending_seed := 0
var _multiplayer_flow := false
var _waiting_to_create_mp := false
var _mp_world_options: Dictionary = {}

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
var _account_panel: VBoxContainer
var _account_status: Label
var _account_email: LineEdit
var _account_password: LineEdit
var _account_login: Button
var _account_register: Button
var _account_logout: Button
var _mp_sail_requested := false
var _authority_join_pending := false
var _authority_join_generation := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = BrandTheme.shared()
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
	_captains.account_changed.connect(_on_remote_account_changed)
	_captains.authentication_required.connect(_on_remote_authentication_required)
	var session := get_node_or_null("/root/PlayerSession")
	if session != null:
		session.remote_load_completed.connect(_on_remote_load_completed)
		session.remote_save_conflict.connect(_on_remote_save_conflict)
	var gateway := get_node_or_null("/root/WorldGateway")
	if gateway != null:
		gateway.session_ready.connect(_on_authority_session_ready)
		gateway.authority_error.connect(_on_authority_session_error)
	_captains.remote.world_options_ready.connect(_on_world_options)
	_captains.remote.request_failed.connect(func(action: String, message: String) -> void:
		if action == "world_options":
			_waiting_to_create_mp = false
			_mp_status.text = message
		else:
			_on_captain_error(message)
	)

	_show_page(Page.MODE_SELECT)


func _build_vignette() -> void:
	# Light overall wash only — ocean stays the stage.
	var wash := ColorRect.new()
	wash.set_anchors_preset(Control.PRESET_FULL_RECT)
	wash.color = BrandTokens.alpha(BrandTokens.SCRIM, 0.44)
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(wash)


func _build_mode_page() -> void:
	_mode_root = _make_brand_page_root("ModeSelectPage")
	var stack := _mode_root.get_node("Align/Stack") as VBoxContainer

	var brand := VBoxContainer.new()
	brand.add_theme_constant_override("separation", BrandTokens.SPACE_XS)
	stack.add_child(brand)

	var mark := TextureRect.new()
	mark.texture = BRAND_MARK
	mark.custom_minimum_size = Vector2(72.0, 72.0)
	mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mark.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	brand.add_child(mark)

	var angst := Label.new()
	angst.text = "ANGST"
	angst.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	BrandTheme.apply_display_font(angst, 92, BrandTokens.INK_INVERSE)
	brand.add_child(angst)

	var anchors := Label.new()
	anchors.text = "'N ANCHORS"
	anchors.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	BrandTheme.apply_display_font(anchors, 56, BrandTokens.BRASS)
	brand.add_child(anchors)

	var rule := ColorRect.new()
	rule.custom_minimum_size = Vector2(148, BrandTokens.RULE_WIDTH)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	rule.color = BrandTokens.BRASS
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rule_pad := MarginContainer.new()
	rule_pad.add_theme_constant_override("margin_top", 8)
	rule_pad.add_theme_constant_override("margin_bottom", 12)
	rule_pad.add_child(rule)
	brand.add_child(rule_pad)

	var tag := Label.new()
	tag.text = "Build a company on cold northern waters"
	BrandTheme.apply_body_font(tag, 15, BrandTokens.INK_INVERSE_DIM)
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
	var quit := BrandMenuButton.new()
	quit.text = "Quit"
	BrandTheme.apply_body_font(quit, 14, BrandTokens.INK_INVERSE_DIM, false)
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
	BrandTheme.apply_body_font(servers_lbl, 11, BrandTokens.BRASS_DEEP, true)
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

	_account_panel = VBoxContainer.new()
	_account_panel.add_theme_constant_override("separation", 7)
	vbox.add_child(_account_panel)
	var account_heading := Label.new()
	account_heading.text = "SERVER ACCOUNT"
	BrandTheme.apply_body_font(account_heading, 11, BrandTokens.BRASS_DEEP, true)
	_account_panel.add_child(account_heading)
	_account_status = Label.new()
	_account_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	BrandTheme.apply_body_font(_account_status, 12, BrandTokens.INK_INVERSE_DIM)
	_account_panel.add_child(_account_status)
	_account_email = LineEdit.new()
	_account_email.placeholder_text = "Email"
	_account_email.custom_minimum_size.y = 34
	_account_panel.add_child(_account_email)
	_account_password = LineEdit.new()
	_account_password.placeholder_text = "Password (10 characters minimum)"
	_account_password.secret = true
	_account_password.custom_minimum_size.y = 34
	_account_password.text_submitted.connect(func(_value: String) -> void: _login_remote_account())
	_account_panel.add_child(_account_password)
	var account_actions := HBoxContainer.new()
	account_actions.add_theme_constant_override("separation", 8)
	_account_panel.add_child(account_actions)
	_account_login = Button.new()
	_account_login.text = "Log in"
	_account_login.pressed.connect(_login_remote_account)
	account_actions.add_child(_account_login)
	_account_register = Button.new()
	_account_register.text = "Create account"
	_account_register.pressed.connect(_register_remote_account)
	account_actions.add_child(_account_register)
	_account_logout = Button.new()
	_account_logout.text = "Sign out"
	_account_logout.visible = false
	_account_logout.pressed.connect(_logout_remote_account)
	account_actions.add_child(_account_logout)

	_mp_roster = RosterPanelScript.new()
	_mp_roster.configure(false, OS.is_debug_build(), func(entry: Dictionary) -> void:
		push_warning("Debug balance writes are disabled in multiplayer; economy mutations are server-authoritative.")
	)
	_mp_roster.sail_pressed.connect(_on_mp_sail)
	_mp_roster.delete_pressed.connect(func(id: String) -> void: _captains.delete_selected_or(id))
	_mp_roster.create_pressed.connect(_on_new_captain)
	_mp_roster.selected.connect(_on_mp_select)
	_mp_roster.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_mp_roster)

	_mp_status = Label.new()
	_mp_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	BrandTheme.apply_body_font(_mp_status, 12, BrandTokens.INK_INVERSE_DIM)
	vbox.add_child(_mp_status)
	_mp_roster.visible = false
	_account_status.text = "Select a server, then log in to see your captains."

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

	match page:
		Page.SINGLEPLAYER:
			_multiplayer_flow = false
			_set_multiplayer_mode(false)
			_backdrop.set_cinematic("singleplayer")
			_captains.configure_local()
		Page.MULTIPLAYER:
			_multiplayer_flow = true
			_set_multiplayer_mode(true)
			_backdrop.set_cinematic("multiplayer")
			_refresh_servers()
		Page.CREATOR:
			_backdrop.set_cinematic("creator")
		Page.COMPANY_SETUP:
			_backdrop.set_cinematic("creator")
		_:
			if page == Page.MODE_SELECT:
				_multiplayer_flow = false
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
		if not _captains.has_remote_account() and _account_status != null:
			_set_account_form_busy(false)
			_account_status.text = message
		else:
			_mp_roster.set_message(message)
	elif _page == Page.SINGLEPLAYER and _sp_roster != null:
		_sp_roster.set_message(message)


func _on_new_captain() -> void:
	if _page == Page.MULTIPLAYER and not _captains.has_remote_account():
		_account_status.text = "Log in before creating a captain on this server."
		return
	_creating_new = true
	_multiplayer_flow = _page == Page.MULTIPLAYER
	if _multiplayer_flow:
		_pending_seed = int(_mp_world_options.get("world_seed", 0))
		if _pending_seed <= 0:
			_waiting_to_create_mp = true
			_mp_status.text = "Loading authoritative world settings…"
			_captains.remote.fetch_world_options()
			return
	else:
		_pending_seed = WorldBootstrapScript.roll_seed()
	_creator.open_with_existing(null)
	_show_page(Page.CREATOR)


func _on_creator_confirmed(display_name: String, appearance: CharacterAppearance) -> void:
	_pending_name = display_name
	_pending_appearance = appearance
	if _creating_new:
		_company_setup.open_for_captain(_pending_name)
		_show_page(Page.COMPANY_SETUP)
	else:
		_show_page(Page.SINGLEPLAYER)


func _on_creator_cancelled() -> void:
	_creating_new = false
	if _multiplayer_flow:
		_show_page(Page.MULTIPLAYER)
	else:
		_show_page(Page.SINGLEPLAYER)


func _on_company_confirmed(company_name: String, brand_color: Color, starter_vessel: String) -> void:
	_pending_company_name = company_name
	_pending_brand_color = brand_color
	_pending_starter_vessel = starter_vessel
	# Brand colours are part of the shared appearance record so future company
	# uniforms render identically for the player, hired NPCs and remote clients.
	if _pending_appearance != null:
		_pending_appearance.company_primary_color = brand_color
		_pending_appearance.company_secondary_color = _company_accent_for(brand_color)
	_show_home_port_picker()


static func _company_accent_for(primary: Color) -> Color:
	# Preserve the game's practical maritime palette while guaranteeing enough
	# contrast for badges, reflective trim and later vessel/company markings.
	return Color("d79a35") if primary.get_luminance() < 0.48 else Color("263640")


func _show_home_port_picker() -> void:
	if _pending_seed <= 0:
		if _multiplayer_flow:
			_mp_status.text = "Server world settings are not ready."
			_show_page(Page.MULTIPLAYER)
			return
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
	if _multiplayer_flow:
		_captains.create_remote_onboarded(
			_pending_name, _pending_appearance, port_id, _pending_seed,
			_pending_company_name, _pending_brand_color, _pending_starter_vessel,
		)
		_creating_new = false
		_show_page(Page.MULTIPLAYER)
		return
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
	if not _captains.has_remote_account():
		_account_status.text = "Log in before selecting a captain."
		return
	for entry_raw in _captains.entries():
		if typeof(entry_raw) != TYPE_DICTIONARY:
			continue
		var entry := entry_raw as Dictionary
		if str(entry.get("id", "")) == captain_id:
			_mp_status.text = "Loading captain progress…"
			_captains.apply_remote_selection(entry)
			return


func _on_mp_sail(captain_id: String) -> void:
	if not _captains.has_remote_account():
		_account_status.text = "Log in before joining shared waters."
		return
	if _captains.selected_id.is_empty():
		return
	_mp_sail_requested = true
	var session := get_node_or_null("/root/PlayerSession")
	if session == null or not session.is_remote_captain_ready(captain_id):
		_mp_status.text = "Loading captain progress…"
		_on_mp_select(captain_id)
		return
	_mp_status.text = "Loading world settings…"
	_captains.remote.fetch_world_options()


func _on_world_options(options: Dictionary) -> void:
	var seed := WorldBootstrapScript.apply_mp_world_options(options)
	if seed <= 0:
		_waiting_to_create_mp = false
		_mp_status.text = "Server returned invalid world settings."
		return
	_mp_world_options = options.duplicate(true)
	_pending_seed = seed
	_mp_status.text = ""
	if _waiting_to_create_mp:
		_waiting_to_create_mp = false
		_creator.open_with_existing(null)
		_show_page(Page.CREATOR)
		return
	var session := get_node_or_null("/root/PlayerSession")
	if not _captains.selected_id.is_empty() and (
			session == null or not session.is_remote_captain_ready(_captains.selected_id)
	):
		_mp_status.text = "Captain progress is still loading."
		return
	_begin_authority_join()


func _begin_authority_join() -> void:
	if _authority_join_pending:
		return
	var gateway := get_node_or_null("/root/WorldGateway")
	if gateway == null:
		_mp_sail_requested = false
		_mp_status.text = "World authority is unavailable."
		return
	_authority_join_pending = true
	_authority_join_generation += 1
	var generation := _authority_join_generation
	_mp_status.text = "Joining server…"
	gateway.call("begin_session", true)
	get_tree().create_timer(10.0, true).timeout.connect(func() -> void:
		if not _authority_join_pending or generation != _authority_join_generation:
			return
		_cancel_authority_join()
		_mp_status.text = "The server did not accept the world session in time."
	)


func _on_authority_session_ready(remote: bool, authority_session: Dictionary) -> void:
	if not _authority_join_pending:
		return
	var token := str(authority_session.get("session_token", "")).strip_edges()
	if not remote or token.is_empty():
		_cancel_authority_join()
		_mp_status.text = "Server accepted an invalid multiplayer session."
		return
	_authority_join_pending = false
	_authority_join_generation += 1
	_mp_sail_requested = false
	_mp_status.text = "Joined. Preparing voyage…"
	WorldBootstrapScript.enter_world(get_tree(), true, true)


func _on_authority_session_error(code: String, message: String) -> void:
	if not _authority_join_pending:
		return
	_cancel_authority_join()
	_mp_status.text = "%s (%s)" % [message, code]


func _cancel_authority_join() -> void:
	_authority_join_pending = false
	_authority_join_generation += 1
	_mp_sail_requested = false
	var gateway := get_node_or_null("/root/WorldGateway")
	if gateway != null and gateway.has_method("stop_session"):
		gateway.call("stop_session")


func _login_remote_account() -> void:
	var email := _account_email.text.strip_edges()
	var password := _account_password.text
	if email.is_empty() or password.is_empty():
		_account_status.text = "Enter your email and password."
		return
	_set_account_form_busy(true)
	_account_status.text = "Signing in…"
	_captains.login_remote_account(email, password)
	_account_password.clear()


func _register_remote_account() -> void:
	var email := _account_email.text.strip_edges()
	var password := _account_password.text
	if email.is_empty() or password.length() < 10:
		_account_status.text = "Use a valid email and a password of at least 10 characters."
		return
	_set_account_form_busy(true)
	_account_status.text = "Creating account…"
	_captains.register_remote_account(email, password)
	_account_password.clear()


func _logout_remote_account() -> void:
	_mp_sail_requested = false
	_captains.logout_remote_account()
	_account_status.text = "Signing out…"


func _on_remote_account_changed(account: Dictionary) -> void:
	_set_account_form_busy(false)
	var signed_in := not account.is_empty()
	_account_email.visible = not signed_in
	_account_password.visible = not signed_in
	_account_login.visible = not signed_in
	_account_register.visible = not signed_in
	_account_logout.visible = signed_in
	_mp_roster.visible = signed_in
	if signed_in:
		_account_status.text = "Signed in as %s" % str(account.get("email", "account"))
	else:
		_account_status.text = "Log in to see the captains owned by your account on this server."
		_mp_status.text = ""


func _on_remote_authentication_required() -> void:
	_on_remote_account_changed({})


func _set_account_form_busy(busy: bool) -> void:
	if _account_email == null:
		return
	_account_email.editable = not busy
	_account_password.editable = not busy
	_account_login.disabled = busy
	_account_register.disabled = busy


func _on_remote_load_completed(captain_id: String, success: bool, message: String) -> void:
	if captain_id != _captains.selected_id:
		return
	if not success:
		_mp_sail_requested = false
		_mp_status.text = message
		return
	_mp_status.text = "Captain ready."
	if _mp_sail_requested:
		_mp_status.text = "Loading world settings…"
		_captains.remote.fetch_world_options()


func _on_remote_save_conflict(_captain_id: String, _current_revision: int) -> void:
	_mp_status.text = "This captain changed on another device. Return to the menu and reload before continuing."


func _set_multiplayer_mode(enabled: bool) -> void:
	var config := get_node_or_null("/root/ServerConfig")
	if config != null:
		config.set("is_multiplayer_mode", enabled)


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
		{"id": "local", "label": "Localhost", "is_preset": true, "host": "127.0.0.1", "http_scheme": "http", "http_host": "127.0.0.1", "http_port": 8080},
		{"id": "digital_ocean", "label": "Ocean server", "is_preset": true, "host": "142.93.43.16", "http_scheme": "http", "http_host": "142.93.43.16", "http_port": 8080},
		{"id": "custom", "label": "Custom", "is_preset": false, "host": str(config.get("udp_host")), "http_scheme": str(config.get("http_scheme")), "http_host": str(config.get("http_host")), "http_port": int(config.get("http_port"))},
	]
	for s in servers:
		_add_server_row(s, config)


func _add_server_row(s: Dictionary, config: Node) -> void:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = BrandTokens.MIN_HIT_TARGET
	row.add_theme_constant_override(&"separation", BrandTokens.SPACE_SM)
	_server_list.add_child(row)
	var status_dot := Label.new()
	status_dot.text = "●"
	status_dot.add_theme_color_override("font_color", BrandTokens.IDLE)
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
	var select_btn := BrandButton.new("Select", BrandButton.Variant.SECONDARY)
	select_btn.text = "Select"
	row.add_child(select_btn)

	var is_active := str(config.get("preset")) == str(s["id"])
	if is_active:
		select_btn.text = "Active"
		select_btn.disabled = true
		name_lbl.add_theme_color_override("font_color", BrandTokens.BRASS)
	else:
		select_btn.pressed.connect(func() -> void:
			# World identity belongs to the selected server. Never reuse options
			# fetched from a previously selected host.
			_mp_world_options.clear()
			_pending_seed = 0
			_waiting_to_create_mp = false
			if bool(s["is_preset"]):
				config.call("use_preset", str(s["id"]))
			else:
				config.call("use_custom", str(s["host"]), int(config.get("udp_port")), str(s["http_host"]), int(s["http_port"]), str(s["http_scheme"]))
			_refresh_servers()
		)

	## The server browser uses the public health summary. Live entity inspection
	## is a private opt-in debug route and must not be required for joining.
	var http_url := "%s://%s:%d/healthz" % [s["http_scheme"], s["http_host"], s["http_port"]]
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
			status_dot.add_theme_color_override("font_color", BrandTokens.OK)
			ping_lbl.text = "%d ms" % duration_ms
			var count := 0
			var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
			if typeof(parsed) == TYPE_DICTIONARY:
				count = int((parsed as Dictionary).get("active_sessions", 0))
			players_lbl.text = "%d active" % count
			if is_active:
				_captains.configure_remote(self, "%s://%s:%d" % [s["http_scheme"], s["http_host"], s["http_port"]])
				_on_remote_account_changed(_captains.remote_account())
		else:
			status_dot.add_theme_color_override("font_color", BrandTokens.ALERT)
			ping_lbl.text = "Offline"
			players_lbl.text = "Offline"
			if is_active:
				_mp_roster.set_message("Server is offline.")
	)
	if http_req.request(http_url) != OK:
		status_dot.add_theme_color_override("font_color", BrandTokens.ALERT)
		ping_lbl.text = "Error"
		http_req.queue_free()
		_active_pings.erase(http_url)


func _ensure_menu_offline() -> void:
	if _authority_join_pending:
		_cancel_authority_join()
	var config := get_node_or_null("/root/ServerConfig")
	if config != null:
		config.set("is_multiplayer_mode", false)
	var network := get_node_or_null("/root/NetworkManager")
	if network != null and network.has_method("end_multiplayer_session"):
		network.call("end_multiplayer_session", true)
	var gateway := get_node_or_null("/root/WorldGateway")
	if gateway != null and gateway.has_method("stop_session"):
		gateway.call("stop_session")


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

	var panel := BrandPanel.new(BrandPanel.Variant.RULED)
	panel.name = "Panel"
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
	BrandTheme.apply_display_font(title, BrandTokens.DISPLAY_L, BrandTokens.INK)
	parent.add_child(title)
	var sub := Label.new()
	sub.text = subtitle
	BrandTheme.apply_body_font(sub, BrandTokens.BUTTON, BrandTokens.INK_MUTED)
	parent.add_child(sub)
	var rule := ColorRect.new()
	rule.custom_minimum_size = Vector2(120, BrandTokens.RULE_WIDTH)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	rule.color = BrandTokens.BRASS
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(rule)


func _add_action(parent: Node, text: String, on_press: Callable) -> BrandMenuButton:
	var button := BrandMenuButton.new()
	button.text = text
	button.pressed.connect(on_press)
	parent.add_child(button)
	return button
