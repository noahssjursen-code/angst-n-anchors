extends Node

## Autoload — manages all non-ship UI: pause menu (ESC), sea chart (M),
## and the persistent walking HUD.
##
## Layer 5  — WalkingHud (always on during gameplay)
## Layer 20 — Pause / Map modal screens

enum Screen { NONE, PAUSE, MAP }

var _screen:          Screen     = Screen.NONE
var _prev_mouse_mode: int        = Input.MOUSE_MODE_VISIBLE
var _hud_layer:   CanvasLayer
var _menu_layer:  CanvasLayer
var _walking_hud: WalkingHud
var _bg:          ColorRect
var _pause_root:  Control
var _map:         MapOverlay


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	# ── Walking HUD layer (persistent) ────────────────────────────────────────
	_hud_layer       = CanvasLayer.new()
	_hud_layer.layer = 5
	add_child(_hud_layer)

	_walking_hud = WalkingHud.new()
	_hud_layer.add_child(_walking_hud)

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

	_set_screen(Screen.NONE)

	# Watch for boat controllers spawned at any point
	get_tree().node_added.connect(_on_node_added)
	for n in get_tree().root.find_children("*", "BoatController", true, false):
		_connect_controller(n as BoatController)


# ── Input ─────────────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_set_screen(Screen.PAUSE if _screen == Screen.NONE else Screen.NONE)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("open_map") and _screen != Screen.PAUSE:
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
	get_tree().paused    = s == Screen.PAUSE


# ── Pause panel ───────────────────────────────────────────────────────────────

func _build_pause() -> Control:
	var root      := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left   = -170.0
	panel.offset_right  =  170.0
	panel.offset_top    = -160.0
	panel.offset_bottom =  160.0

	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.04, 0.06, 0.14, 0.98)
	bg_style.border_color = Color(0.30, 0.44, 0.68, 0.82)
	bg_style.set_border_width_all(2)
	bg_style.content_margin_left   = 28.0
	bg_style.content_margin_right  = 28.0
	bg_style.content_margin_top    = 30.0
	bg_style.content_margin_bottom = 30.0
	panel.add_theme_stylebox_override("panel", bg_style)
	root.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)

	# Title
	var title := Label.new()
	title.text = "ANGST 'N ANCHORS"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.96, 0.86, 0.12, 1.00))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var sub := Label.new()
	sub.text = "— PAUSED —"
	sub.add_theme_font_size_override("font_size", 11)
	sub.add_theme_color_override("font_color", Color(0.40, 0.52, 0.72, 0.70))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(sub)

	var div := HSeparator.new()
	var div_style := StyleBoxFlat.new()
	div_style.bg_color = Color(0.28, 0.40, 0.64, 0.35)
	div_style.content_margin_top    = 4.0
	div_style.content_margin_bottom = 4.0
	div.add_theme_stylebox_override("separator", div_style)
	vbox.add_child(div)

	# Marks display inside pause menu
	var marks_label := Label.new()
	marks_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	marks_label.add_theme_font_size_override("font_size", 15)
	marks_label.add_theme_color_override("font_color", Color(0.96, 0.82, 0.28, 0.90))
	marks_label.name = "MarksLabel"
	vbox.add_child(marks_label)
	_update_marks_label(marks_label)
	var session := get_node_or_null("/root/PlayerSession")
	if session != null:
		session.marks_changed.connect(func(bal: int) -> void:
			marks_label.text = "ℳ  %d  Marks" % bal
		)

	var div2 := HSeparator.new()
	div2.add_theme_stylebox_override("separator", div_style)
	vbox.add_child(div2)

	var resume := _make_button("RESUME  [ ESC ]")
	resume.pressed.connect(func() -> void: _set_screen(Screen.NONE))
	vbox.add_child(resume)

	var map_btn := _make_button("SEA CHART  [ M ]")
	map_btn.pressed.connect(func() -> void: _set_screen(Screen.MAP))
	vbox.add_child(map_btn)

	var quit := _make_button("QUIT TO DESKTOP")
	quit.pressed.connect(func() -> void: get_tree().quit())
	vbox.add_child(quit)

	return root


func _update_marks_label(lbl: Label) -> void:
	var session := get_node_or_null("/root/PlayerSession")
	lbl.text = "ℳ  %d  Marks" % (session.get_marks() if session != null else 0)


func _make_button(txt: String) -> Button:
	var btn := Button.new()
	btn.text = txt
	btn.custom_minimum_size = Vector2(264, 46)
	btn.add_theme_font_size_override("font_size", 14)

	var sn := StyleBoxFlat.new()
	sn.bg_color      = Color(0.08, 0.11, 0.22, 0.92)
	sn.border_color  = Color(0.28, 0.40, 0.64, 0.50)
	sn.set_border_width_all(1)
	sn.content_margin_left  = 14.0
	sn.content_margin_right = 14.0

	var sh := StyleBoxFlat.new()
	sh.bg_color     = Color(0.14, 0.20, 0.38, 0.96)
	sh.border_color = Color(0.50, 0.68, 1.00, 0.90)
	sh.set_border_width_all(2)
	sh.content_margin_left  = 14.0
	sh.content_margin_right = 14.0

	var sp := StyleBoxFlat.new()
	sp.bg_color     = Color(0.20, 0.30, 0.52, 0.96)
	sp.border_color = Color(0.96, 0.86, 0.12, 0.90)
	sp.set_border_width_all(2)
	sp.content_margin_left  = 14.0
	sp.content_margin_right = 14.0

	btn.add_theme_stylebox_override("normal",  sn)
	btn.add_theme_stylebox_override("hover",   sh)
	btn.add_theme_stylebox_override("pressed", sp)
	btn.add_theme_stylebox_override("focus",   sh)
	btn.add_theme_color_override("font_color",         Color(0.78, 0.88, 1.00, 0.90))
	btn.add_theme_color_override("font_hover_color",   Color(1.00, 1.00, 1.00, 1.00))
	btn.add_theme_color_override("font_pressed_color", Color(0.96, 0.86, 0.12, 1.00))
	return btn


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


func _on_helm_off() -> void:
	_walking_hud.visible = true
