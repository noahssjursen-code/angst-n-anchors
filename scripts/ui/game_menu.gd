extends Node

## Autoload — manages all non-ship UI: pause menu (ESC), sea chart (M),
## and the persistent walking HUD.
##
## Layer 5  — WalkingHud (always on during gameplay)
## Layer 20 — Pause / Map modal screens

enum Screen { NONE, PAUSE, MAP, SETTINGS }

var _screen:          Screen     = Screen.NONE
var _prev_mouse_mode: int        = Input.MOUSE_MODE_VISIBLE
var _helm_active:     bool       = false
var _hud_layer:   CanvasLayer
var _menu_layer:  CanvasLayer
var _walking_hud: WalkingHud
var _journal:     ContractJournalOverlay
var _hints:       HintOverlay
var _bg:          ColorRect
var _pause_root:  Control
var _map:         MapOverlay
var _settings:    SettingsPanel


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# We keep gameplay unpaused in MP mode; focus loss should not freeze time.
	get_window().focus_exited.connect(_on_window_focus_exited)

	# ── Walking HUD layer (persistent) ────────────────────────────────────────
	_hud_layer       = CanvasLayer.new()
	_hud_layer.layer = 5
	add_child(_hud_layer)

	_walking_hud = WalkingHud.new()
	_hud_layer.add_child(_walking_hud)

	_journal = ContractJournalOverlay.new()
	_hud_layer.add_child(_journal)

	_hints = HintOverlay.new()
	_hud_layer.add_child(_hints)

	# ── Modal menu layer ───────────────────────────────────────────────────────
	_menu_layer              = CanvasLayer.new()
	_menu_layer.layer        = 20
	_menu_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_menu_layer)

	_bg              = ColorRect.new()
	_bg.color        = Color(0.02, 0.03, 0.08, 0.86)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu_layer.add_child(_bg)

	_pause_root              = _build_pause()
	_pause_root.process_mode = Node.PROCESS_MODE_ALWAYS
	_menu_layer.add_child(_pause_root)

	_map              = MapOverlay.new()
	_map.process_mode = Node.PROCESS_MODE_ALWAYS
	_menu_layer.add_child(_map)

	_settings              = SettingsPanel.new()
	_settings.process_mode = Node.PROCESS_MODE_ALWAYS
	_settings.close_requested.connect(func() -> void: _set_screen(Screen.NONE))
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


func _on_window_focus_exited() -> void:
	return


# ── Input ─────────────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _screen == Screen.SETTINGS:
			_set_screen(Screen.NONE)
			get_viewport().set_input_as_handled()
		elif _screen != Screen.NONE:
			_set_screen(Screen.NONE)
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("open_map"):
		_set_screen(Screen.MAP if _screen != Screen.MAP else Screen.NONE)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("open_journal") and _screen == Screen.NONE:
		if _journal != null:
			_journal.toggle()
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
	_settings.visible    = s == Screen.SETTINGS
	if _journal != null:
		_journal.visible = not modal
	get_tree().paused = false


# ── Pause panel ───────────────────────────────────────────────────────────────

func _build_pause() -> Control:
	var root      := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var panel := UiBuilder.panel()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left   = -170.0
	panel.offset_right  =  170.0
	panel.offset_top    = -160.0
	panel.offset_bottom =  160.0
	root.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)

	vbox.add_child(UiBuilder.title_label("ANGST 'N ANCHORS"))
	vbox.add_child(UiBuilder.subtitle_label("— PAUSED —"))
	vbox.add_child(UiBuilder.separator())

	# Marks display.
	var marks_label := Label.new()
	marks_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	marks_label.add_theme_font_size_override("font_size", 15)
	marks_label.add_theme_color_override("font_color", HudStyle.C_AMBER)
	marks_label.name = "MarksLabel"
	vbox.add_child(marks_label)
	_update_marks_label(marks_label)
	var session := get_node_or_null("/root/PlayerSession")
	if session != null:
		session.marks_changed.connect(func(bal: int) -> void:
			marks_label.text = PlayerSession.format_money(bal)
		)

	vbox.add_child(UiBuilder.separator())

	var resume := UiBuilder.button("RESUME  [ ESC ]")
	resume.pressed.connect(func() -> void: _set_screen(Screen.NONE))
	vbox.add_child(resume)

	var map_btn := UiBuilder.button("SEA CHART  [ M ]")
	map_btn.pressed.connect(func() -> void: _set_screen(Screen.MAP))
	vbox.add_child(map_btn)

	var settings_btn := UiBuilder.button("SETTINGS")
	settings_btn.pressed.connect(func() -> void: _set_screen(Screen.SETTINGS))
	vbox.add_child(settings_btn)

	var quit := UiBuilder.button("QUIT TO DESKTOP")
	quit.pressed.connect(_quit_to_desktop)
	vbox.add_child(quit)

	return root


func _update_marks_label(lbl: Label) -> void:
	var session := get_node_or_null("/root/PlayerSession")
	lbl.text = PlayerSession.format_money(session.get_marks() if session != null else 0)


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


func _on_helm_off() -> void:
	_walking_hud.visible = true
	_helm_active = false


func _quit_to_desktop() -> void:
	var session := get_node_or_null("/root/PlayerSession")
	if session != null and session.has_method("save_now"):
		session.call("save_now")
	get_tree().quit()
