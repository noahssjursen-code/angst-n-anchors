extends Control

## Title flow: select game mode, continue voyage, create captain, or quit.
## Includes an orbiting 3D cinematic background showcasing Testvik in random weather!

const WORLD_SCENE := "res://scenes/world.tscn"

enum Page { MODE_SELECT, SINGLEPLAYER, MULTIPLAYER, CREATOR }

var _page: Page = Page.MODE_SELECT
var _new_game_warns: bool = false

# Live Server Ping & DB Captain Variables
var _active_pings: Dictionary = {}
var _server_list_container: VBoxContainer = null
var _mp_captains_container: VBoxContainer = null
var _selected_mp_captain_id: String = ""
var _selected_mp_captain_name: String = ""

# UI Roots
var _mode_select_root: CenterContainer = null
var _singleplayer_root: CenterContainer = null
var _multiplayer_root: CenterContainer = null
var _creator: CharacterCreatorPanel = null

# Buttons to update names dynamically
var _sp_continue_btn: Button = null
var _mp_continue_btn: Button = null
var _mp_play_btn: Button = null

# Orbiting 3D camera variables
var _cam: Camera3D = null
var _orbit_angle: float = 0.0
var _orbit_speed: float = 0.02 # Slower, more cinematic camera sweep
var _orbit_radius: float = 110.0 # Broader circle to appreciate the port
var _orbit_height: float = 24.0 # Slightly higher up to fully eliminate any water clipping!

# Smooth cinematic transitions and preview NPC
var _menu_preview_npc: NpcBase = null
var _cam_look_at_smoothed: Vector3 = Vector3(0.0, 1.5, 0.0)
var _target_orbit_radius: float = 110.0
var _target_orbit_height: float = 24.0
var _target_look_at: Vector3 = Vector3(0.0, 1.5, 0.0)


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
	# Interpolate camera parameters smoothly for cinematic transitions
	_orbit_radius = lerp(_orbit_radius, _target_orbit_radius, 4.0 * delta)
	_orbit_height = lerp(_orbit_height, _target_orbit_height, 4.0 * delta)
	_cam_look_at_smoothed = _cam_look_at_smoothed.lerp(_target_look_at, 4.0 * delta)

	if _cam != null and is_instance_valid(_cam):
		_orbit_angle += _orbit_speed * delta
		var offset := Vector3(
			cos(_orbit_angle) * _orbit_radius,
			_orbit_height + sin(_orbit_angle * 0.5) * (1.5 if _page == Page.MULTIPLAYER else 4.0), # Calmer waves when zoomed
			sin(_orbit_angle) * _orbit_radius
		)
		_cam.global_position = _cam_look_at_smoothed + offset
		_cam.look_at(_cam_look_at_smoothed, Vector3.UP)


func _setup_3d_background() -> void:
	# Keep weather cinematic but calm to prevent extreme wave crests from Z-fighting with docks
	var weather_lighting := get_node_or_null("/root/WeatherLighting")
	if weather_lighting != null:
		randomize()
		weather_lighting.set("time_of_day", randf_range(0.2, 0.8)) # Golden hour or nice day hours
		weather_lighting.set("cloud_cover", randf_range(0.2, 0.5))
		weather_lighting.set("precipitation", 0.0) # Clear skies look cleaner on start
		weather_lighting.set("wind_force", randf_range(0.1, 0.35)) # Low waves to prevent port clipping
		weather_lighting.set("visibility", 1.0)
	
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
	_cam.far = 1500.0 # Make sure the horizon stays beautifully rendered
	add_child(_cam)

	# Spawn the 3D majestic preview NPC standing on the edge of the Testvik wharf
	_menu_preview_npc = NpcBase.new()
	_menu_preview_npc.name = "MenuPreviewNpc"
	_menu_preview_npc.position = Vector3(0.0, 0.12, -1.8)
	_menu_preview_npc.rotation_degrees = Vector3(0.0, 45.0, 0.0) # Stand facing slightly cinematic
	add_child(_menu_preview_npc)
	_menu_preview_npc.skin_color = Color(0.72, 0.55, 0.40)
	_menu_preview_npc.clothing_color = Color(0.18, 0.20, 0.30)
	_menu_preview_npc.trousers_color = Color(0.18, 0.18, 0.20)


func _build_background_vignette() -> void:
	var vignette := ColorRect.new()
	vignette.name = "VignetteOverlay"
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.color = Color(0.01, 0.02, 0.04, 0.32)
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


# ── 3. Page Multiplayer (Fully Upgraded for Postgres) ─────────────────────────

func _build_multiplayer_page() -> void:
	_multiplayer_root = CenterContainer.new()
	_multiplayer_root.name = "MultiplayerPage"
	_multiplayer_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_multiplayer_root.visible = false
	add_child(_multiplayer_root)

	var panel := Panel.new()
	panel.theme = HudStyle.make_theme()
	panel.custom_minimum_size = Vector2(520, 0)
	_multiplayer_root.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "MULTIPLAYER SHIPPING"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", HudStyle.C_AMBER)
	vbox.add_child(title)

	vbox.add_child(HSeparator.new())

	# Server Selector Section
	var list_title_lbl := Label.new()
	list_title_lbl.text = "SELECT MULTIPLAYER SERVER (LIVE)"
	list_title_lbl.add_theme_font_size_override("font_size", 11)
	list_title_lbl.add_theme_color_override("font_color", HudStyle.C_AMBER)
	vbox.add_child(list_title_lbl)

	var list_scroll := ScrollContainer.new()
	list_scroll.custom_minimum_size = Vector2(0, 90)
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(list_scroll)

	_server_list_container = VBoxContainer.new()
	_server_list_container.add_theme_constant_override("separation", 4)
	list_scroll.add_child(_server_list_container)

	vbox.add_child(HSeparator.new())

	# Postgres Captain Selection Section
	var cap_title_lbl := Label.new()
	cap_title_lbl.text = "SELECT SERVER CAPTAIN PROFILE (SAVED IN CLOUD)"
	cap_title_lbl.add_theme_font_size_override("font_size", 11)
	cap_title_lbl.add_theme_color_override("font_color", HudStyle.C_AMBER)
	vbox.add_child(cap_title_lbl)

	var cap_scroll := ScrollContainer.new()
	cap_scroll.custom_minimum_size = Vector2(0, 95)
	cap_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(cap_scroll)

	_mp_captains_container = VBoxContainer.new()
	_mp_captains_container.add_theme_constant_override("separation", 4)
	cap_scroll.add_child(_mp_captains_container)

	# Control buttons under Captain
	var cap_btns_row := HBoxContainer.new()
	cap_btns_row.add_theme_constant_override("separation", 10)
	vbox.add_child(cap_btns_row)

	var new_cap_btn := Button.new()
	new_cap_btn.text = "＋ Create New Captain"
	new_cap_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	new_cap_btn.pressed.connect(_on_new_captain)
	cap_btns_row.add_child(new_cap_btn)

	_mp_play_btn = Button.new()
	_mp_play_btn.text = "⚡ SAIL VOYAGE"
	_mp_play_btn.disabled = true
	_mp_play_btn.add_theme_color_override("font_color", HudStyle.C_AMBER)
	_mp_play_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mp_play_btn.pressed.connect(_on_mp_play_pressed)
	cap_btns_row.add_child(_mp_play_btn)

	vbox.add_child(HSeparator.new())

	# Advanced config label
	var advanced_lbl := Label.new()
	advanced_lbl.text = "ADVANCED / CUSTOM SERVER SETUP"
	advanced_lbl.add_theme_font_size_override("font_size", 11)
	advanced_lbl.add_theme_color_override("font_color", HudStyle.C_LABEL)
	vbox.add_child(advanced_lbl)

	var custom_grid := GridContainer.new()
	custom_grid.name = "CustomGrid"
	custom_grid.columns = 2
	custom_grid.add_theme_constant_override("h_separation", 8)
	custom_grid.add_theme_constant_override("v_separation", 4)
	vbox.add_child(custom_grid)

	var host_lbl := Label.new()
	host_lbl.text = "Custom IP:"
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

	var config := get_node_or_null("/root/ServerConfig")

	var update_ui_from_config := func() -> void:
		if config == null:
			return
		var p_name: String = config.get("preset")
		if p_name == "custom":
			custom_grid.visible = true
			host_edit.text = String(config.get("udp_host"))
			port_edit.text = String(config.get("udp_port"))
		else:
			custom_grid.visible = false

	update_ui_from_config.call()

	var save_custom := func() -> void:
		if config != null:
			var host := host_edit.text.strip_edges()
			var port := int(port_edit.text.strip_edges())
			if port <= 0:
				port = 7777
			config.call("use_custom", host, port, host, 8080)

	host_edit.text_changed.connect(func(_new_text: String) -> void:
		save_custom.call()
		_refresh_server_list()
	)
	port_edit.text_changed.connect(func(_new_text: String) -> void:
		save_custom.call()
		_refresh_server_list()
	)

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
		
	# Smoothly trigger cinematic camera shifts depending on page
	if page == Page.MULTIPLAYER:
		# Zoom right onto the preview captain model standing on the pier!
		_target_orbit_radius = 8.5
		_target_orbit_height = 2.2
		_target_look_at = Vector3(0.0, 1.0, -1.8)
	else:
		# Return to global panoramic port view
		_target_orbit_radius = 110.0
		_target_orbit_height = 24.0
		_target_look_at = Vector3(0.0, 1.5, 0.0)
		
	_refresh_continue_states()
	
	if page == Page.MULTIPLAYER:
		_refresh_server_list()


func _refresh_continue_states() -> void:
	var session: Node = get_node_or_null("/root/PlayerSession")
	var has_save: bool = false
	if session != null:
		has_save = session.has_local_save()
		
	var sp_label := "Continue voyage"
	
	if has_save and session != null:
		var pdata: PlayerData = session.get("data") as PlayerData
		if pdata != null:
			sp_label = "Continue as %s" % pdata.display_name
			
	_sp_continue_btn.disabled = not has_save
	_sp_continue_btn.text = sp_label


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
	var config := get_node_or_null("/root/ServerConfig")
	var is_mp := false
	if config != null:
		is_mp = bool(config.get("is_multiplayer_mode"))

	if is_mp:
		# Write New Captain profile directly to Postgres REST Server
		_create_postgres_captain(display_name, appearance)
	else:
		# Traditional Local Singleplayer Save
		var session := get_node_or_null("/root/PlayerSession")
		if session != null:
			if _new_game_warns:
				session.begin_new_captain(display_name, appearance)
			else:
				session.set_display_name(display_name)
				session.set_appearance(appearance)
		_go_to_world()


func _on_quit() -> void:
	var session := get_node_or_null("/root/PlayerSession")
	if session != null:
		session.save_now()
	get_tree().quit()


func _refresh_server_list() -> void:
	if _server_list_container == null:
		return
		
	# Clear previous rows
	for c in _server_list_container.get_children():
		c.queue_free()
		
	# Cancel any running HTTP pings
	for url in _active_pings.keys():
		var req = _active_pings[url]
		if is_instance_valid(req):
			req.queue_free()
	_active_pings.clear()
	
	var config := get_node_or_null("/root/ServerConfig")
	if config == null:
		return
		
	# Get all available servers to ping
	var servers = []
	
	# Add presets
	var presets: Dictionary = config.PRESETS
	for p_id in presets.keys():
		var p_data = presets[p_id]
		servers.append({
			"id": p_id,
			"label": p_data["label"],
			"host": p_data["udp_host"],
			"http_host": p_data["http_host"],
			"http_port": p_data["http_port"],
			"is_preset": true
		})
		
	# Add custom if preset is custom
	if config.get("preset") == "custom":
		servers.append({
			"id": "custom",
			"label": "Custom Server",
			"host": config.get("udp_host"),
			"http_host": config.get("http_host"),
			"http_port": config.get("http_port"),
			"is_preset": false
		})
	else:
		# Always add a slot for custom option so they can click to edit it!
		servers.append({
			"id": "custom",
			"label": "Custom IP Setup",
			"host": config.get("udp_host"),
			"http_host": config.get("http_host"),
			"http_port": config.get("http_port"),
			"is_preset": false
		})
		
	# Build rows
	for s in servers:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		_server_list_container.add_child(row)
		
		# 1. Status Indicator Dot
		var status_dot := Label.new()
		status_dot.text = "●"
		status_dot.add_theme_color_override("font_color", Color.GRAY) # Gray initially while pinging
		row.add_child(status_dot)
		
		# 2. Server Name
		var name_lbl := Label.new()
		name_lbl.text = s["label"]
		name_lbl.add_theme_font_size_override("font_size", 12)
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_lbl)
		
		# 3. Latency Ping Label
		var ping_lbl := Label.new()
		ping_lbl.text = "..."
		ping_lbl.add_theme_font_size_override("font_size", 11)
		ping_lbl.add_theme_color_override("font_color", HudStyle.C_LABEL)
		row.add_child(ping_lbl)
		
		# 4. Players Count Label
		var players_lbl := Label.new()
		players_lbl.text = "—"
		players_lbl.add_theme_font_size_override("font_size", 11)
		players_lbl.add_theme_color_override("font_color", HudStyle.C_LABEL)
		row.add_child(players_lbl)
		
		# 5. Active/Select Button
		var select_btn := Button.new()
		select_btn.text = "Select"
		select_btn.add_theme_font_size_override("font_size", 10)
		row.add_child(select_btn)
		
		# Determine if currently active
		var is_active := false
		if s["id"] == config.get("preset"):
			is_active = true
		elif s["id"] == "custom" and config.get("preset") == "custom":
			is_active = true
			
		if is_active:
			select_btn.text = "Active"
			select_btn.disabled = true
			name_lbl.add_theme_color_override("font_color", HudStyle.C_AMBER)
		else:
			var s_id: String = s["id"]
			var is_preset: bool = s["is_preset"]
			var s_host: String = s["host"]
			var s_http_host: String = s["http_host"]
			var s_http_port: int = int(s["http_port"])
			select_btn.pressed.connect(func() -> void:
				if is_preset:
					config.call("use_preset", s_id)
				else:
					config.call("use_custom", s_host, config.get("udp_port"), s_http_host, s_http_port)
				
				# Update advanced UI components
				var grid = _multiplayer_root.find_child("CustomGrid", true, false)
				if grid != null:
					grid.visible = (s_id == "custom")
					
				_refresh_server_list()
			)
			
		# Fire off the asynchronous HTTP ping to `/v1/entities`
		var http_url := "http://%s:%d/v1/entities" % [s["http_host"], s["http_port"]]
		var start_time := Time.get_ticks_msec()
		
		var http_req := HTTPRequest.new()
		add_child(http_req)
		http_req.timeout = 2.0
		_active_pings[http_url] = http_req
		
		http_req.request_completed.connect(func(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
			if not is_instance_valid(row) or not is_instance_valid(status_dot):
				if is_instance_valid(http_req):
					http_req.queue_free()
				return
				
			var duration_ms := Time.get_ticks_msec() - start_time
			
			if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
				var json := JSON.new()
				var parse_err := json.parse(body.get_string_from_utf8())
				var count := 0
				if parse_err == OK and json.data is Dictionary:
					count = int(json.data.get("count", 0))
					
				status_dot.add_theme_color_override("font_color", Color.GREEN)
				ping_lbl.text = "%d ms" % duration_ms
				ping_lbl.add_theme_color_override("font_color", Color.GREEN)
				players_lbl.text = "%d active" % count
				players_lbl.add_theme_color_override("font_color", HudStyle.C_AMBER if count > 0 else HudStyle.C_LABEL)
				
				# If this server is currently active, load its captains!
				if is_active:
					_load_postgres_captains(s["http_host"], s["http_port"])
			else:
				status_dot.add_theme_color_override("font_color", Color.RED)
				ping_lbl.text = "Offline"
				ping_lbl.add_theme_color_override("font_color", Color.RED)
				players_lbl.text = "Offline"
				players_lbl.add_theme_color_override("font_color", Color.RED)
				if is_active:
					_clear_mp_captains_ui("Server is offline.")
				
			http_req.queue_free()
			_active_pings.erase(http_url)
		)
		
		var err := http_req.request(http_url)
		if err != OK:
			status_dot.add_theme_color_override("font_color", Color.RED)
			ping_lbl.text = "Error"
			players_lbl.text = "Offline"
			http_req.queue_free()
			_active_pings.erase(http_url)


# ── PostgreSQL REST API Integration ──────────────────────────────────────────

func _load_postgres_captains(http_host: String, http_port: int) -> void:
	if _mp_captains_container == null:
		return
		
	# Clear list first
	for c in _mp_captains_container.get_children():
		c.queue_free()
		
	var loading_lbl := Label.new()
	loading_lbl.text = "Loading Captains..."
	loading_lbl.add_theme_font_size_override("font_size", 11)
	_mp_captains_container.add_child(loading_lbl)
	
	var http_url := "http://%s:%d/v1/captains" % [http_host, http_port]
	var req := HTTPRequest.new()
	add_child(req)
	
	req.request_completed.connect(func(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
		req.queue_free()
		if not is_instance_valid(_mp_captains_container):
			return
			
		for c in _mp_captains_container.get_children():
			c.queue_free()
			
		if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
			_clear_mp_captains_ui("Failed to load captains.")
			return
			
		var json := JSON.new()
		var parse_err := json.parse(body.get_string_from_utf8())
		if parse_err != OK or not (json.data is Array):
			_clear_mp_captains_ui("No captains registered on this server.")
			return
			
		var captains_list: Array = json.data
		if captains_list.is_empty():
			_clear_mp_captains_ui("No captains registered. Create one below!")
			return
			
		for cap: Dictionary in captains_list:
			var row := HBoxContainer.new()
			_mp_captains_container.add_child(row)
			
			var name_btn := Button.new()
			name_btn.text = "%s (%s Marks)" % [cap["display_name"], PlayerSession.format_money(int(cap["marks"]))]
			name_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			name_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			row.add_child(name_btn)
			
			var cheat_btn := Button.new()
			cheat_btn.text = "💸 +1M"
			cheat_btn.flat = true
			cheat_btn.add_theme_color_override("font_color", Color.GREEN)
			row.add_child(cheat_btn)
			
			var del_btn := Button.new()
			del_btn.text = "❌"
			del_btn.flat = true
			row.add_child(del_btn)
			
			var cap_id: String = cap["id"]
			var cap_name: String = cap["display_name"]
			var cap_marks: int = int(cap["marks"])
			
			# Parse appearance safely
			var cap_app: CharacterAppearance = null
			var app_str: String = cap.get("appearance_json", "")
			if not app_str.is_empty():
				var app_json := JSON.new()
				if app_json.parse(app_str) == OK and app_json.data is Dictionary:
					cap_app = CharacterAppearance.from_dict(app_json.data)
			
			# Selected Captain highlight
			if _selected_mp_captain_id == cap_id:
				name_btn.add_theme_color_override("font_color", HudStyle.C_AMBER)
				_mp_play_btn.disabled = false
				# Instantly draw their appearance on the background preview model!
				_update_menu_preview_npc(cap_app)
				
			name_btn.pressed.connect(func() -> void:
				_selected_mp_captain_id = cap_id
				_selected_mp_captain_name = cap_name
				
				# Cache selection in local player session fields temporarily
				var session := get_node_or_null("/root/PlayerSession")
				if session != null:
					session.set_captain_profile(cap_id, cap_name, cap_marks, cap_app)
					
				_load_postgres_captains(http_host, http_port) # Redraw highlighting
			)
			
			cheat_btn.pressed.connect(func() -> void:
				_add_postgres_captain_marks(http_host, http_port, cap_id, cap_marks)
			)
			
			del_btn.pressed.connect(func() -> void:
				_delete_postgres_captain(http_host, http_port, cap_id)
			)
	)
	
	req.request(http_url)


func _create_postgres_captain(display_name: String, appearance: CharacterAppearance) -> void:
	var config := get_node_or_null("/root/ServerConfig")
	if config == null:
		return
		
	var http_host: String = config.get("http_host")
	var http_port: int = int(config.get("http_port"))
	var http_url := "http://%s:%d/v1/captains" % [http_host, http_port]
	
	var req := HTTPRequest.new()
	add_child(req)
	
	var app_dict: Dictionary = appearance.to_dict() if appearance != null else {}
	var body_dict := {
		"display_name": display_name,
		"appearance_json": JSON.stringify(app_dict)
	}
	
	req.request_completed.connect(func(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
		req.queue_free()
		if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
			var json := JSON.new()
			if json.parse(body.get_string_from_utf8()) == OK and json.data is Dictionary:
				_selected_mp_captain_id = String(json.data.get("id", ""))
				_selected_mp_captain_name = String(json.data.get("display_name", ""))
				
				var session := get_node_or_null("/root/PlayerSession")
				if session != null:
					session.set_captain_profile(
						_selected_mp_captain_id,
						_selected_mp_captain_name,
						int(json.data.get("marks", 1000)),
						appearance
					)
					
			_show_page(Page.MULTIPLAYER)
		else:
			_show_page(Page.MULTIPLAYER)
	)
	
	var headers := PackedStringArray(["Content-Type: application/json"])
	req.request(http_url, headers, HTTPClient.METHOD_POST, JSON.stringify(body_dict))


func _delete_postgres_captain(http_host: String, http_port: int, captain_id: String) -> void:
	var http_url := "http://%s:%d/v1/captains?id=%s" % [http_host, http_port, captain_id]
	var req := HTTPRequest.new()
	add_child(req)
	
	req.request_completed.connect(func(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
		req.queue_free()
		if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
			if _selected_mp_captain_id == captain_id:
				_selected_mp_captain_id = ""
				_selected_mp_captain_name = ""
				_mp_play_btn.disabled = true
			_load_postgres_captains(http_host, http_port)
	)
	
	req.request(http_url, PackedStringArray(), HTTPClient.METHOD_DELETE)


func _add_postgres_captain_marks(http_host: String, http_port: int, captain_id: String, current_marks: int) -> void:
	var http_url := "http://%s:%d/v1/captains" % [http_host, http_port]
	var req := HTTPRequest.new()
	add_child(req)
	
	var headers := PackedStringArray(["Content-Type: application/json"])
	var body_dict := {
		"id": captain_id,
		"marks": current_marks + 1000000
	}
	
	req.request_completed.connect(func(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
		req.queue_free()
		if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
			if _selected_mp_captain_id == captain_id:
				var json := JSON.new()
				if json.parse(body.get_string_from_utf8()) == OK and json.data is Dictionary:
					var new_marks := int(json.data.get("marks", 0))
					var session := get_node_or_null("/root/PlayerSession")
					if session != null:
						session.data.marks = new_marks
			_load_postgres_captains(http_host, http_port)
	)
	
	req.request(http_url, headers, HTTPClient.METHOD_PUT, JSON.stringify(body_dict))


func _clear_mp_captains_ui(msg: String) -> void:
	for c in _mp_captains_container.get_children():
		c.queue_free()
	var lbl := Label.new()
	lbl.text = msg
	lbl.add_theme_font_size_override("font_size", 11)
	_mp_captains_container.add_child(lbl)
	_mp_play_btn.disabled = true


func _on_mp_play_pressed() -> void:
	var config := get_node_or_null("/root/ServerConfig")
	if config == null or _selected_mp_captain_id.is_empty():
		return
		
	# First query GET /v1/world-options to fetch the stable world seed
	var http_host: String = config.get("http_host")
	var http_port: int = int(config.get("http_port"))
	var http_url := "http://%s:%d/v1/world-options" % [http_host, http_port]
	
	var req := HTTPRequest.new()
	add_child(req)
	
	_mp_play_btn.text = "Loading World settings..."
	_mp_play_btn.disabled = true
	
	req.request_completed.connect(func(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
		req.queue_free()
		_mp_play_btn.text = "⚡ SAIL VOYAGE"
		_mp_play_btn.disabled = false
		
		var seed_val := 42 # Safe fallback
		if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
			var json := JSON.new()
			if json.parse(body.get_string_from_utf8()) == OK and json.data is Dictionary:
				seed_val = int(json.data.get("world_seed", 42))
				
		# Force set the world seed locally before transition!
		# (Assuming your world generator is wired to a global seed singleton/autoload or GameState settings)
		var game_settings := get_node_or_null("/root/GameSettings")
		if game_settings != null and game_settings.has_method("set"):
			game_settings.set("map_generation_seed", seed_val)
			
		_go_to_world()
	)
	
	req.request(http_url)


func _go_to_world() -> void:
	var menu := get_node_or_null("/root/GameMenu")
	if menu != null and menu.has_method("set_gameplay_hud_visible"):
		menu.set_gameplay_hud_visible(true)
	get_tree().change_scene_to_file(WORLD_SCENE)


func _update_menu_preview_npc(appearance: CharacterAppearance) -> void:
	if _menu_preview_npc == null or not is_instance_valid(_menu_preview_npc):
		return
	if appearance == null:
		appearance = CharacterAppearance.default_appearance()
		
	_menu_preview_npc.skin_color = appearance.skin_color
	_menu_preview_npc.clothing_color = appearance.clothing_color
	_menu_preview_npc.trousers_color = appearance.trousers_color
	
	_menu_preview_npc.remove_overlay("hat")
	if not appearance.hat_id.is_empty():
		var hat_path: String = CharacterAppearance.HAT_PATHS.get(appearance.hat_id, "")
		if not hat_path.is_empty():
			_menu_preview_npc.add_overlay("hat", hat_path)


func _on_dev_local_quickstart() -> void:
	var config := get_node_or_null("/root/ServerConfig")
	if config != null:
		config.set("is_multiplayer_mode", true)
		config.call("save_to_disk")
		
	var session := get_node_or_null("/root/PlayerSession")
	if session != null and not session.has_local_save():
		var mock_appearance := CharacterAppearance.new()
		session.begin_new_captain("DevCaptain", mock_appearance)
		
	_go_to_world()
