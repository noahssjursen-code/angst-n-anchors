extends Node

const HelmMinimapScript := preload("res://scripts/ui/chart/helm_minimap.gd")
const WorldBootstrapScript := preload("res://scripts/world/world_bootstrap.gd")

## Autoload — manages all non-ship UI: pause menu (ESC), sea chart (M),
## and the persistent walking HUD.
##
## Layer 5  — WalkingHud (always on during gameplay)
## Layer 20 — Pause / Map modal screens

enum Screen { NONE, PAUSE, MAP, COMPANY, SETTINGS }

var _screen:          Screen     = Screen.NONE
var _prev_mouse_mode: int        = Input.MOUSE_MODE_VISIBLE
var _helm_active:     bool       = false
var _helm_cursor_released: bool  = false
var _hud_layer:   CanvasLayer
var _menu_layer:  CanvasLayer
var _walking_hud: WalkingHud
var _hints:       HintOverlay
var _bg:          ColorRect
var _pause_root:  Control
var _map:         MapOverlay
var _minimap
var _settings:    SettingsPanel
var _company:     CompanyPanel
var _marks_currency: BrandCurrency


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# ── Walking HUD layer (persistent) ────────────────────────────────────────
	_hud_layer       = CanvasLayer.new()
	_hud_layer.layer = 5
	add_child(_hud_layer)

	_walking_hud = WalkingHud.new()
	_hud_layer.add_child(_walking_hud)

	_hints = HintOverlay.new()
	_hud_layer.add_child(_hints)

	# ── Modal menu layer ───────────────────────────────────────────────────────
	_menu_layer              = CanvasLayer.new()
	_menu_layer.layer        = 20
	_menu_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_menu_layer)

	_bg              = ColorRect.new()
	_bg.color        = BrandTokens.alpha(BrandTokens.SCRIM, 0.86)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu_layer.add_child(_bg)

	_pause_root              = _build_pause()
	_pause_root.process_mode = Node.PROCESS_MODE_ALWAYS
	_menu_layer.add_child(_pause_root)

	_map              = MapOverlay.new()
	_map.process_mode = Node.PROCESS_MODE_ALWAYS
	_map.close_requested.connect(func() -> void: _set_screen(Screen.NONE))
	_menu_layer.add_child(_map)

	_company = CompanyPanel.new()
	_company.process_mode = Node.PROCESS_MODE_ALWAYS
	_company.close_requested.connect(func() -> void: _set_screen(Screen.PAUSE))
	_menu_layer.add_child(_company)

	_minimap = HelmMinimapScript.new()
	_minimap.name = "HelmMinimap"
	_minimap.setup(_map)
	_hud_layer.add_child(_minimap)

	_settings              = SettingsPanel.new()
	_settings.process_mode = Node.PROCESS_MODE_ALWAYS
	_settings.close_requested.connect(func() -> void: _set_screen(Screen.PAUSE))
	_menu_layer.add_child(_settings)

	_set_screen(Screen.NONE)

	# Watch for boat controllers spawned at any point
	get_tree().node_added.connect(_on_node_added)
	for n in get_tree().root.find_children("*", "BoatController", true, false):
		_connect_controller(n as BoatController)

	var scene := get_tree().current_scene
	if scene != null and String(scene.scene_file_path).ends_with("main_menu.tscn"):
		set_gameplay_hud_visible(false)


func set_gameplay_hud_visible(visible: bool) -> void:
	if _hud_layer != null:
		_hud_layer.visible = visible


## Pause the game when the window loses focus. Skip if we're already in
## a modal screen (paused already) or sitting on the main menu (no game).
func _on_window_focus_exited() -> void:
	if _screen != Screen.NONE:
		return
	# `current_scene` is the main menu before the world boots — don't pause it.
	var scene := get_tree().current_scene
	if scene == null or String(scene.scene_file_path).ends_with("main_menu.tscn"):
		return
	_set_screen(Screen.PAUSE)


# ── Input ─────────────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if (
		event is InputEventKey
		and event.pressed
		and not event.echo
		and event.keycode == KEY_C
		and _helm_active
		and _screen == Screen.NONE
	):
		_toggle_helm_cursor()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		if _screen == Screen.SETTINGS or _screen == Screen.COMPANY:
			_set_screen(Screen.PAUSE)
			get_viewport().set_input_as_handled()
		elif _screen != Screen.NONE:
			_set_screen(Screen.NONE)
			get_viewport().set_input_as_handled()
		elif not _helm_active:
			# Helm exit is handled by CaptainsChair. NPC dialogs consume ESC while open.
			_set_screen(Screen.PAUSE)
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("open_map") and _screen != Screen.PAUSE:
		# Main menu hosts its own chart for home-port pick; don't open the
		# empty gameplay overlay over the title screen.
		var scene := get_tree().current_scene
		if scene != null and String(scene.scene_file_path).ends_with("main_menu.tscn"):
			return
		_set_screen(Screen.MAP if _screen != Screen.MAP else Screen.NONE)
		get_viewport().set_input_as_handled()


# ── Screen switching ──────────────────────────────────────────────────────────

func _set_screen(s: Screen) -> void:
	var was_modal        := _screen != Screen.NONE
	_screen              = s
	var modal            := s != Screen.NONE
	if modal and not was_modal:
		_prev_mouse_mode = Input.mouse_mode
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif not modal and was_modal:
		Input.mouse_mode = _prev_mouse_mode
	_menu_layer.visible  = modal
	_bg.visible          = modal
	_pause_root.visible  = s == Screen.PAUSE
	_map.visible         = s == Screen.MAP
	_company.visible     = s == Screen.COMPANY
	## The sea chart is opaque and simulation stays live, including in MP. Do
	## not spend a full 3D frame rendering a world the chart completely covers.
	var viewport := get_viewport()
	if viewport != null:
		RenderingServer.viewport_set_disable_3d(viewport.get_viewport_rid(), s == Screen.MAP)
	if s == Screen.MAP:
		_map.open_navigation()
	_settings.visible    = s == Screen.SETTINGS
	if _minimap != null:
		_minimap.set_modal_hidden(modal)
	# Pause while on Pause OR Settings — both are reached from the pause menu
	# and a moving world behind the settings panel is jarring.
	# However, in multiplayer mode, we must never pause the tree!
	var config := get_node_or_null("/root/ServerConfig")
	var is_mp := false
	if config != null:
		is_mp = bool(config.get("is_multiplayer_mode"))
		
	get_tree().paused    = (s == Screen.PAUSE or s == Screen.COMPANY or s == Screen.SETTINGS) and not is_mp


# ── Pause panel ───────────────────────────────────────────────────────────────

func _build_pause() -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = BrandTheme.shared()

	var safe_margin := MarginContainer.new()
	safe_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	safe_margin.add_theme_constant_override(&"margin_left", BrandTokens.SPACE_XXXL)
	safe_margin.add_theme_constant_override(&"margin_top", BrandTokens.SPACE_XXXL)
	safe_margin.add_theme_constant_override(&"margin_bottom", BrandTokens.SPACE_XXXL)
	root.add_child(safe_margin)

	var panel := BrandPanel.new(BrandPanel.Variant.DARK_RULED)
	panel.custom_minimum_size.x = 424.0
	panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	safe_margin.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override(&"separation", BrandTokens.SPACE_MD)
	panel.add_child(vbox)

	var eyebrow := BrandLabel.new(tr("SHIP'S OFFICE"), BrandLabel.Role.INVERSE_DATA)
	eyebrow.add_theme_color_override(&"font_color", BrandTokens.BRASS)
	vbox.add_child(eyebrow)
	var title := BrandLabel.new(tr("PAUSED"), BrandLabel.Role.DISPLAY_LARGE)
	title.add_theme_color_override(&"font_color", BrandTokens.INK_INVERSE)
	vbox.add_child(title)
	var subtitle := BrandLabel.new(
		tr("Company business and navigation"),
		BrandLabel.Role.INVERSE_BODY
	)
	subtitle.add_theme_color_override(&"font_color", BrandTokens.INK_INVERSE_DIM)
	vbox.add_child(subtitle)
	vbox.add_child(HSeparator.new())

	var view := get_node_or_null("/root/LocalPlayerView")
	_marks_currency = BrandCurrency.new(view.get_marks() if view != null else 0, true)
	_marks_currency.name = "Marks"
	vbox.add_child(_marks_currency)
	if view != null and view.has_signal("marks_changed"):
		view.marks_changed.connect(_on_marks_changed)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)

	var resume := BrandMenuButton.new(tr("RESUME") + "     [ ESC ]")
	resume.pressed.connect(func() -> void: _set_screen(Screen.NONE))
	vbox.add_child(resume)

	var map_btn := BrandMenuButton.new(tr("SEA CHART") + "     [ M ]")
	map_btn.pressed.connect(func() -> void: _set_screen(Screen.MAP))
	vbox.add_child(map_btn)

	var company_btn := BrandMenuButton.new(tr("COMPANY"))
	company_btn.pressed.connect(func() -> void: _set_screen(Screen.COMPANY))
	vbox.add_child(company_btn)

	var settings_btn := BrandMenuButton.new(tr("SETTINGS"))
	settings_btn.pressed.connect(func() -> void: _set_screen(Screen.SETTINGS))
	vbox.add_child(settings_btn)

	vbox.add_child(HSeparator.new())
	var title_btn := BrandButton.new(tr("RETURN TO TITLE"), BrandButton.Variant.QUIET)
	title_btn.pressed.connect(_return_to_title)
	vbox.add_child(title_btn)
	var quit := BrandButton.new(tr("QUIT TO DESKTOP"), BrandButton.Variant.DANGER)
	quit.pressed.connect(_quit_to_desktop)
	vbox.add_child(quit)

	return root


func _on_marks_changed(balance: int) -> void:
	if _marks_currency != null:
		_marks_currency.set_amount(balance)


# ── Boat controller wiring ────────────────────────────────────────────────────

func _on_node_added(node: Node) -> void:
	if node is BoatController:
		_connect_controller(node as BoatController)


func _connect_controller(bc: BoatController) -> void:
	if not bc.helm_activated.is_connected(_on_helm_on):
		bc.helm_activated.connect(_on_helm_on)
	if not bc.helm_deactivated.is_connected(_on_helm_off):
		bc.helm_deactivated.connect(_on_helm_off)


func _on_helm_on() -> void:
	_walking_hud.visible = false
	_helm_active = true
	_helm_cursor_released = Input.mouse_mode == Input.MOUSE_MODE_VISIBLE
	if _minimap != null:
		_minimap.set_helm_active(true)


func _on_helm_off() -> void:
	_walking_hud.visible = true
	_helm_active = false
	if _helm_cursor_released and _screen == Screen.NONE:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_helm_cursor_released = false
	if _minimap != null:
		_minimap.set_helm_active(false)


func _toggle_helm_cursor() -> void:
	_helm_cursor_released = Input.mouse_mode != Input.MOUSE_MODE_VISIBLE
	Input.mouse_mode = (
		Input.MOUSE_MODE_VISIBLE
		if _helm_cursor_released
		else Input.MOUSE_MODE_CAPTURED
	)


func _quit_to_desktop() -> void:
	var view := get_node_or_null("/root/LocalPlayerView")
	if view != null and view.has_method("save_player_state"):
		view.call("save_player_state")
	get_tree().quit()


func _return_to_title() -> void:
	_set_screen(Screen.NONE)
	get_tree().paused = false
	WorldBootstrapScript.return_to_title(get_tree())
