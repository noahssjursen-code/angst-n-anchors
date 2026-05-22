extends Control

## Title flow: select game mode, continue voyage, create captain, or quit.
## Includes an orbiting 3D cinematic background showcasing Testvik in random weather!

const WORLD_SCENE := "res://scenes/world.tscn"

enum Page { MODE_SELECT, SINGLEPLAYER, MULTIPLAYER, CREATOR }

var _page: Page = Page.MODE_SELECT
var _new_game_warns: bool = false

# UI Roots
var _mode_select_root: CenterContainer = null
var _singleplayer_root: CenterContainer = null
var _multiplayer_root: CenterContainer = null
var _creator: CharacterCreatorPanel = null

# Buttons to update names dynamically
var _sp_continue_btn: Button = null
var _mp_continue_btn: Button = null

# Orbiting 3D camera variables
var _cam: Camera3D = null
var _orbit_angle: float = 0.0
var _orbit_speed: float = 0.035
var _orbit_radius: float = 80.0
var _orbit_height: float = 18.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	
	# Set up 3D Background first
	_setup_3d_background()
	
	# Build 2D overlay pages
	_build_background_vignette()
	_build_mode_select_page()
	_build_singleplayer_page()
	_build_multiplayer_page()
	
	_creator = CharacterCreatorPanel.new()
	_creator.name = "CharacterCreator"
	_creator.visible = false
	_creator.confirmed.connect(_on_creator_confirmed)
	_creator.cancelled.connect(_on_creator_cancelled)
	add_child(_creator)
	
	_show_page(Page.MODE_SELECT)


func _process(delta: float) -> void:
	if _cam != null and is_instance_valid(_cam):
		_orbit_angle += _orbit_speed * delta
		var target := Vector3(0.0, 1.5, 0.0) # Look at Testvik harbor area
		var offset := Vector3(
			cos(_orbit_angle) * _orbit_radius,
			_orbit_height,
			sin(_orbit_angle) * _orbit_radius
		)
		_cam.global_position = target + offset
		_cam.look_at(target, Vector3.UP)


func _setup_3d_background() -> void:
	# Randomize weather state on startup
	var weather_lighting := get_node_or_null("/root/WeatherLighting")
	if weather_lighting != null:
		randomize()
		weather_lighting.set("time_of_day", randf_range(0.1, 0.9)) # random hour
		weather_lighting.set("cloud_cover", randf_range(0.15, 0.85))
		weather_lighting.set("precipitation", randf_range(0.0, 0.6))
		weather_lighting.set("wind_force", randf_range(0.1, 0.6))
		weather_lighting.set("visibility", randf_range(0.5, 1.0))
	
	# Instantiate WorldRenderer (sets up wave surfaces, lighting, environment)
	const WORLD_RENDERER_SCRIPT = preload("res://scripts/world/world_renderer.gd")
	var renderer := WORLD_RENDERER_SCRIPT.new() as Node3D
	renderer.name = "BackgroundWorldRenderer"
	add_child(renderer)

	# Instantiate PortPlot (Testvik dock, lighthouse, wharves)
	var plot := PortPlot.new()
	plot.name = "BackgroundPort"
	plot.port_id = "port-test"
	plot.port_label = "Testvik"
	add_child(plot)
	
	# Cinematic camera
	_cam = Camera3D.new()
	_cam.name = "BackgroundCamera"
	_cam.current = true
	_cam.far = 1200.0 # Make sure the horizon stays beautifully rendered
	add_child(_cam)


func _build_background_vignette() -> void:
	var vignette := ColorRect.new()
	vignette.name = "VignetteOverlay"
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Soft vignette shading over the 3D scene to ensure text is readable
	vignette.color = Color(0.01, 0.02, 0.04, 0.38)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vignette)


# ── 1. Page Mode Selection ────────────────────────────────────────────────────

func _build_mode_select_page() -> void:
	_mode_select_root = CenterContainer.new()
	_mode_select_root.name = "ModeSelectPage"
	_mode_select_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_mode_select_root)

	var panel := Panel.new()
	panel.theme = HudStyle.make_theme()
	panel.custom_minimum_size = Vector2(400, 0)
	_mode_select_root.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 32)
	margin.add_theme_constant_override("margin_bottom", 32)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "ANGST 'N ANCHORS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", HudStyle.C_AMBER)
	vbox.add_child(title)

	var tag := Label.new()
	tag.text = "Maritime trade on a cold coast"
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.add_theme_font_size_override("font_size", 13)
	tag.add_theme_color_override("font_color", HudStyle.C_LABEL)
	vbox.add_child(tag)

	vbox.add_child(HSeparator.new())

	var sp_btn := Button.new()
	sp_btn.text = "Singleplayer"
	sp_btn.pressed.connect(func() -> void: _show_page(Page.SINGLEPLAYER))
	vbox.add_child(sp_btn)

	var mp_btn := Button.new()
	mp_btn.text = "Multiplayer"
	mp_btn.pressed.connect(func() -> void: _show_page(Page.MULTIPLAYER))
	vbox.add_child(mp_btn)

	vbox.add_child(HSeparator.new())

	var quit_btn := Button.new()
	quit_btn.text = "Quit"
	quit_btn.pressed.connect(_on_quit)
	vbox.add_child(quit_btn)


# ── 2. Page Singleplayer ──────────────────────────────────────────────────────

func _build_singleplayer_page() -> void:
	_singleplayer_root = CenterContainer.new()
	_singleplayer_root.name = "SingleplayerPage"
	_singleplayer_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_singleplayer_root.visible = false
	add_child(_singleplayer_root)

	var panel := Panel.new()
	panel.theme = HudStyle.make_theme()
	panel.custom_minimum_size = Vector2(400, 0)
	_singleplayer_root.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 32)
	margin.add_theme_constant_override("margin_bottom", 32)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "SINGLEPLAYER VOYAGE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", HudStyle.C_AMBER)
	vbox.add_child(title)

	vbox.add_child(HSeparator.new())

	_sp_continue_btn = Button.new()
	_sp_continue_btn.text = "Continue voyage"
	_sp_continue_btn.pressed.connect(_on_continue)
	vbox.add_child(_sp_continue_btn)

	var new_btn := Button.new()
	new_btn.text = "New captain"
	new_btn.pressed.connect(_on_new_captain)
	vbox.add_child(new_btn)

	var edit_btn := Button.new()
	edit_btn.text = "Edit captain"
	edit_btn.pressed.connect(_on_edit_captain)
	vbox.add_child(edit_btn)

	vbox.add_child(HSeparator.new())

	var back_btn := Button.new()
	back_btn.text = "Back to Game Mode"
	back_btn.pressed.connect(func() -> void: _show_page(Page.MODE_SELECT))
	vbox.add_child(back_btn)


# ── 3. Page Multiplayer ───────────────────────────────────────────────────────

func _build_multiplayer_page() -> void:
	_multiplayer_root = CenterContainer.new()
	_multiplayer_root.name = "MultiplayerPage"
	_multiplayer_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_multiplayer_root.visible = false
	add_child(_multiplayer_root)

	var panel := Panel.new()
	panel.theme = HudStyle.make_theme()
	panel.custom_minimum_size = Vector2(400, 0)
	_multiplayer_root.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 32)
	margin.add_theme_constant_override("margin_bottom", 32)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "MULTIPLAYER SHIPPING"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", HudStyle.C_AMBER)
	vbox.add_child(title)

	vbox.add_child(HSeparator.new())

	# Fast start for local developers
	var dev_btn := Button.new()
	dev_btn.text = "⚡ DEV LOCAL QUICKSTART"
	dev_btn.add_theme_color_override("font_color", HudStyle.C_AMBER)
	dev_btn.pressed.connect(_on_dev_local_quickstart)
	vbox.add_child(dev_btn)

	_mp_continue_btn = Button.new()
	_mp_continue_btn.text = "Continue multiplayer"
	_mp_continue_btn.pressed.connect(_on_continue)
	vbox.add_child(_mp_continue_btn)

	var new_btn := Button.new()
	new_btn.text = "New captain"
	new_btn.pressed.connect(_on_new_captain)
	vbox.add_child(new_btn)

	var edit_btn := Button.new()
	edit_btn.text = "Edit captain"
	edit_btn.pressed.connect(_on_edit_captain)
	vbox.add_child(edit_btn)

	vbox.add_child(HSeparator.new())

	var server_lbl := Label.new()
	server_lbl.text = "MULTIPLAYER SERVER"
	server_lbl.add_theme_font_size_override("font_size", 11)
	server_lbl.add_theme_color_override("font_color", HudStyle.C_LABEL)
	vbox.add_child(server_lbl)

	var config := get_node_or_null("/root/ServerConfig")
	
	var server_opt := OptionButton.new()
	server_opt.add_item("Local Server", 0)
	server_opt.add_item("Digital Ocean", 1)
	server_opt.add_item("Custom...", 2)
	vbox.add_child(server_opt)

	var custom_grid := GridContainer.new()
	custom_grid.columns = 2
	custom_grid.visible = false
	custom_grid.add_theme_constant_override("h_separation", 8)
	custom_grid.add_theme_constant_override("v_separation", 6)
	vbox.add_child(custom_grid)

	var host_lbl := Label.new()
	host_lbl.text = "IP Address:"
	host_lbl.add_theme_font_size_override("font_size", 12)
	custom_grid.add_child(host_lbl)

	var host_edit := LineEdit.new()
	host_edit.text = "127.0.0.1"
	custom_grid.add_child(host_edit)

	var port_lbl := Label.new()
	port_lbl.text = "UDP Port:"
	port_lbl.add_theme_font_size_override("font_size", 12)
	custom_grid.add_child(port_lbl)

	var port_edit := LineEdit.new()
	port_edit.text = "7777"
	custom_grid.add_child(port_edit)

	var test_btn := Button.new()
	test_btn.text = "Test connection"
	vbox.add_child(test_btn)

	var test_status_lbl := Label.new()
	test_status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	test_status_lbl.add_theme_font_size_override("font_size", 11)
	vbox.add_child(test_status_lbl)

	var update_ui_from_config := func() -> void:
		if config == null:
			return
		var p_name: String = config.get("preset")
		if p_name == "local":
			server_opt.selected = 0
			custom_grid.visible = false
		elif p_name == "digital_ocean":
			server_opt.selected = 1
			custom_grid.visible = false
		else:
			server_opt.selected = 2
			custom_grid.visible = true
			host_edit.text = String(config.get("udp_host"))
			port_edit.text = String(config.get("udp_port"))

	update_ui_from_config.call()

	server_opt.item_selected.connect(func(index: int) -> void:
		test_status_lbl.text = ""
		if index == 0:
			config.call("use_preset", "local")
			custom_grid.visible = false
		elif index == 1:
			config.call("use_preset", "digital_ocean")
			custom_grid.visible = false
		else:
			custom_grid.visible = true
	)

	var save_custom := func() -> void:
		if server_opt.selected == 2 and config != null:
			var host := host_edit.text.strip_edges()
			var port := int(port_edit.text.strip_edges())
			if port <= 0:
				port = 7777
			config.call("use_custom", host, port, host, 8080)

	host_edit.text_changed.connect(func(_new_text: String) -> void:
		save_custom.call()
	)
	port_edit.text_changed.connect(func(_new_text: String) -> void:
		save_custom.call()
	)

	test_btn.pressed.connect(func() -> void:
		save_custom.call()
		test_status_lbl.text = "Testing connection..."
		test_status_lbl.add_theme_color_override("font_color", HudStyle.C_LABEL)
		
		var manager := get_node_or_null("/root/NetworkManager")
		if manager == null or manager.get("client") == null:
			test_status_lbl.text = "Error: NetworkManager not loaded"
			test_status_lbl.add_theme_color_override("font_color", Color.RED)
			return
			
		var client_node: Node = manager.get("client")
		client_node.call("test_http_connection", func(success: bool, response_code: int) -> void:
			if success:
				test_status_lbl.text = "Success! Connection OK (200)"
				test_status_lbl.add_theme_color_override("font_color", Color.GREEN)
			else:
				test_status_lbl.text = "Failed to connect! (Code: %d)" % response_code
				test_status_lbl.add_theme_color_override("font_color", Color.RED)
		)
	)

	vbox.add_child(HSeparator.new())

	var back_btn := Button.new()
	back_btn.text = "Back to Game Mode"
	back_btn.pressed.connect(func() -> void: _show_page(Page.MODE_SELECT))
	vbox.add_child(back_btn)


# ── Page Flow & Transition Controllers ────────────────────────────────────────

func _show_page(page: Page) -> void:
	_page = page
	
	_mode_select_root.visible = page == Page.MODE_SELECT
	_singleplayer_root.visible = page == Page.SINGLEPLAYER
	_multiplayer_root.visible = page == Page.MULTIPLAYER
	_creator.visible = page == Page.CREATOR
	
	var config := get_node_or_null("/root/ServerConfig")
	if config != null:
		config.set("is_multiplayer_mode", page == Page.MULTIPLAYER)
		
	_refresh_continue_states()


func _refresh_continue_states() -> void:
	var session: Node = get_node_or_null("/root/PlayerSession")
	var has_save: bool = false
	if session != null:
		has_save = session.has_local_save()
		
	var sp_label := "Continue voyage"
	var mp_label := "Continue multiplayer"
	
	if has_save and session != null:
		var pdata: PlayerData = session.get("data") as PlayerData
		if pdata != null:
			sp_label = "Continue as %s" % pdata.display_name
			mp_label = "Continue as %s" % pdata.display_name
			
	_sp_continue_btn.disabled = not has_save
	_sp_continue_btn.text = sp_label
	
	_mp_continue_btn.disabled = not has_save
	_mp_continue_btn.text = mp_label


func _show_creator(new_voyage: bool) -> void:
	_page = Page.CREATOR
	_new_game_warns = new_voyage
	
	_mode_select_root.visible = false
	_singleplayer_root.visible = false
	_multiplayer_root.visible = false
	_creator.visible = true
	
	var session := get_node_or_null("/root/PlayerSession")
	if new_voyage:
		_creator.open_with_existing(null)
	else:
		_creator.open_with_existing(session.data if session != null else null)


func _on_continue() -> void:
	_go_to_world()


func _on_new_captain() -> void:
	_show_creator(true)


func _on_edit_captain() -> void:
	_show_creator(false)


func _on_creator_cancelled() -> void:
	if _page == Page.CREATOR:
		var config := get_node_or_null("/root/ServerConfig")
		var is_mp := false
		if config != null:
			is_mp = bool(config.get("is_multiplayer_mode"))
		_show_page(Page.MULTIPLAYER if is_mp else Page.SINGLEPLAYER)


func _on_creator_confirmed(display_name: String, appearance: CharacterAppearance) -> void:
	var session := get_node_or_null("/root/PlayerSession")
	if session == null:
		_go_to_world()
		return
	if _new_game_warns:
		session.begin_new_captain(display_name, appearance)
	else:
		session.set_display_name(display_name)
		session.set_appearance(appearance)
	_go_to_world()


func _on_dev_local_quickstart() -> void:
	# Instantly select the local server preset
	var config := get_node_or_null("/root/ServerConfig")
	if config != null:
		config.call("use_preset", "local")
		config.set("is_multiplayer_mode", true)
		
	# Instantly begin/continue a local captain profile if possible
	var session := get_node_or_null("/root/PlayerSession")
	if session != null and not session.has_local_save():
		# Force mock standard avatar configuration for instantaneous developer start
		var mock_appearance := CharacterAppearance.new()
		session.begin_new_captain("DevCaptain", mock_appearance)
		
	_go_to_world()


func _go_to_world() -> void:
	var menu := get_node_or_null("/root/GameMenu")
	if menu != null and menu.has_method("set_gameplay_hud_visible"):
		menu.set_gameplay_hud_visible(true)
	get_tree().change_scene_to_file(WORLD_SCENE)


func _on_quit() -> void:
	var session := get_node_or_null("/root/PlayerSession")
	if session != null:
		session.save_now()
	get_tree().quit()
