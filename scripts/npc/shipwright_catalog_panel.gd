class_name ShipwrightCatalogPanel
extends CanvasLayer

## Full-screen shipwright showroom: 3D preview + specs + slideshow + price.

signal closed
signal commission_requested(entry: Dictionary)

const PANEL_FRAC := Vector2(0.90, 0.86)
const PREVIEW_MIN_SIZE := Vector2(520, 320)

var _panel: Panel
var _preview: ShipwrightPreview
var _viewport: SubViewport
var _camera: Camera3D
var _name_lbl: Label
var _class_lbl: Label
var _specs_lbl: Label
var _price_lbl: Label
var _index_lbl: Label
var _commission_btn: Button

var _catalog: Array[Dictionary] = []
var _index: int = 0
var _stations: HullStations


func _init() -> void:
	name = "ShipwrightCatalogPanel"
	layer = 12
	_build_chrome()


func _ready() -> void:
	var vp := get_viewport()
	if vp != null and not vp.size_changed.is_connected(_resize_panel):
		vp.size_changed.connect(_resize_panel)


func _unhandled_input(event: InputEvent) -> void:
	if not is_open():
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				_step(-1)
				get_viewport().set_input_as_handled()
				return
			if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_step(1)
				get_viewport().set_input_as_handled()
				return
	if event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_left"):
		_step(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right"):
		_step(1)
		get_viewport().set_input_as_handled()


func is_open() -> bool:
	return _panel != null and _panel.visible


func open_catalog(catalog: Array, start_index: int = 0) -> void:
	_catalog.clear()
	for item in catalog:
		_catalog.append(item as Dictionary)
	_index = clampi(start_index, 0, maxi(_catalog.size() - 1, 0))
	_resize_panel()
	_panel.visible = true
	_refresh_entry()


func hide_catalog() -> void:
	_panel.visible = false
	if _preview != null:
		_preview.clear()


func _close() -> void:
	hide_catalog()
	closed.emit()


func _build_chrome() -> void:
	_panel = Panel.new()
	_panel.name = "CatalogPanel"
	_panel.visible = false
	_panel.theme = HudStyle.make_theme()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	add_child(_panel)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	_panel.add_child(margin)

	var root_v := VBoxContainer.new()
	root_v.add_theme_constant_override("separation", 10)
	margin.add_child(root_v)

	var title := Label.new()
	title.text = "SHIPWRIGHT'S CATALOG"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", HudStyle.C_AMBER)
	root_v.add_child(title)

	var tagline := Label.new()
	tagline.text = "Browse the fleet — commission any hull we have on the slips."
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tagline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tagline.add_theme_font_size_override("font_size", 13)
	tagline.add_theme_color_override("font_color", HudStyle.C_LABEL)
	root_v.add_child(tagline)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16)
	root_v.add_child(body)

	# ── 3D preview (left) ─────────────────────────────────────────────────────
	var preview_panel := PanelContainer.new()
	preview_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview_panel.custom_minimum_size = PREVIEW_MIN_SIZE
	var preview_sb := StyleBoxFlat.new()
	preview_sb.bg_color = HudStyle.C_BG_INNER
	preview_sb.border_color = HudStyle.C_BRASS
	preview_sb.set_border_width_all(1)
	preview_panel.add_theme_stylebox_override("panel", preview_sb)
	body.add_child(preview_panel)

	var preview_v := VBoxContainer.new()
	preview_v.set_anchors_preset(Control.PRESET_FULL_RECT)
	preview_v.add_theme_constant_override("separation", 6)
	preview_panel.add_child(preview_v)

	var vp_container := SubViewportContainer.new()
	vp_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vp_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vp_container.stretch = true
	preview_v.add_child(vp_container)

	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.size = Vector2i(960, 540)
	_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	_viewport.transparent_bg = false
	vp_container.add_child(_viewport)

	var world := Node3D.new()
	world.name = "PreviewWorld"
	_viewport.add_child(world)

	_preview = ShipwrightPreview.new()
	_preview.name = "ShipPreview"
	world.add_child(_preview)

	_camera = Camera3D.new()
	_camera.name = "PreviewCamera"
	_camera.fov = 54.0
	_camera.current = true
	world.add_child(_camera)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42.0, 38.0, 0.0)
	sun.light_energy = 1.15
	world.add_child(sun)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-18.0, -120.0, 0.0)
	fill.light_energy = 0.35
	world.add_child(fill)

	var env := WorldEnvironment.new()
	var we := Environment.new()
	we.background_mode = Environment.BG_COLOR
	we.background_color = Color(0.05, 0.07, 0.10)
	we.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	we.ambient_light_color = Color(0.18, 0.20, 0.24)
	we.ambient_light_energy = 0.9
	env.environment = we
	world.add_child(env)

	var nav := HBoxContainer.new()
	nav.alignment = BoxContainer.ALIGNMENT_CENTER
	nav.add_theme_constant_override("separation", 12)
	preview_v.add_child(nav)

	var prev_btn := UiBuilder.button("◀  Previous")
	prev_btn.pressed.connect(func() -> void: _step(-1))
	nav.add_child(prev_btn)

	_index_lbl = Label.new()
	_index_lbl.custom_minimum_size = Vector2(100, 0)
	_index_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_index_lbl.add_theme_font_size_override("font_size", 14)
	_index_lbl.add_theme_color_override("font_color", HudStyle.C_TEXT)
	nav.add_child(_index_lbl)

	var next_btn := UiBuilder.button("Next  ▶")
	next_btn.pressed.connect(func() -> void: _step(1))
	nav.add_child(next_btn)

	# ── Spec sheet (right) ────────────────────────────────────────────────────
	var sheet := VBoxContainer.new()
	sheet.custom_minimum_size = Vector2(300, 0)
	sheet.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sheet.add_theme_constant_override("separation", 8)
	body.add_child(sheet)

	_name_lbl = _make_sheet_label(22, HudStyle.C_AMBER)
	sheet.add_child(_name_lbl)

	_class_lbl = _make_sheet_label(14, HudStyle.C_LABEL)
	sheet.add_child(_class_lbl)

	sheet.add_child(HSeparator.new())

	_specs_lbl = _make_sheet_label(14, HudStyle.C_TEXT)
	_specs_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sheet.add_child(_specs_lbl)

	sheet.add_child(HSeparator.new())

	_price_lbl = _make_sheet_label(18, HudStyle.C_AMBER)
	sheet.add_child(_price_lbl)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sheet.add_child(spacer)

	_commission_btn = UiBuilder.button("Commission vessel")
	_commission_btn.pressed.connect(_on_commission_pressed)
	sheet.add_child(_commission_btn)

	var back_btn := UiBuilder.button("Leave catalog")
	back_btn.pressed.connect(_close)
	sheet.add_child(back_btn)


func _make_sheet_label(font_size: int, color: Color) -> Label:
	var lbl := Label.new()
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	return lbl


func _resize_panel() -> void:
	if _panel == null:
		return
	var rect := get_viewport().get_visible_rect().size
	var w := rect.x * PANEL_FRAC.x
	var h := rect.y * PANEL_FRAC.y
	_panel.offset_left = -w * 0.5
	_panel.offset_right = w * 0.5
	_panel.offset_top = -h * 0.5
	_panel.offset_bottom = h * 0.5


func show_panel() -> void:
	_resize_panel()
	_panel.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _step(delta_index: int) -> void:
	if _catalog.is_empty():
		return
	_index = (_index + delta_index) % _catalog.size()
	if _index < 0:
		_index += _catalog.size()
	_refresh_entry()


func _refresh_entry() -> void:
	if _catalog.is_empty():
		return
	var entry := _catalog[_index] as Dictionary
	_stations = _preview.show_entry(entry)

	_camera.transform = ShipwrightPreview.camera_transform_for_length(
		_stations.length_m if _stations != null else 18.0
	)

	var display := str(entry.get("display", "Vessel"))
	var short_name := display.split("  •  ")[0] if "  •  " in display else display
	_name_lbl.text = short_name
	_class_lbl.text = str(entry.get("ship_class_label", ""))

	var len_m := _stations.length_m if _stations != null else 0.0
	var beam_m := _stations.beam_m if _stations != null else 0.0
	var disp_t := (_stations.displacement_volume_m3 * 1.025) if _stations != null else 0.0
	_specs_lbl.text = (
		"%s\nLength %.0f m  •  Beam %.1f m\nDisplacement ~%.0f t\nBrowse with ◀ ▶ or arrow keys."
		% [display, len_m, beam_m, disp_t]
	)

	_index_lbl.text = "%d / %d" % [_index + 1, _catalog.size()]

	var session := get_node_or_null("/root/PlayerSession")
	var balance := 0
	var player_data: PlayerData = null
	if session != null:
		balance = session.get_marks()
		player_data = session.data

	var price := ShipwrightPricing.commission_price(entry, _stations, player_data)
	_price_lbl.text = ShipwrightPricing.price_label(price)

	var can_afford := balance >= price
	_commission_btn.disabled = not can_afford
	if can_afford:
		_commission_btn.text = "Commission — %s" % PlayerSession.format_money(price)
	else:
		_commission_btn.text = "Need %s" % PlayerSession.format_money(price - balance)


func _on_commission_pressed() -> void:
	if _catalog.is_empty():
		return
	commission_requested.emit(_catalog[_index] as Dictionary)


func get_current_entry() -> Dictionary:
	if _catalog.is_empty():
		return {}
	return _catalog[_index] as Dictionary


func refresh() -> void:
	if is_open():
		_refresh_entry()
