class_name CharacterCreatorPanel
extends Control

## Captain setup — name, colours, hat. Live NpcBase preview in a SubViewport.

signal confirmed(display_name: String, appearance: CharacterAppearance)
signal cancelled

const SKIN_PRESETS: Array[Color] = [
	Color(0.72, 0.55, 0.40),
	Color(0.58, 0.42, 0.32),
	Color(0.85, 0.70, 0.55),
	Color(0.45, 0.34, 0.28),
]

const CLOTHING_PRESETS: Array[Color] = [
	Color(0.18, 0.20, 0.30),
	Color(0.22, 0.38, 0.60),
	Color(0.15, 0.22, 0.45),
	Color(0.35, 0.28, 0.22),
	Color(0.12, 0.16, 0.14),
]

const TROUSERS_PRESETS: Array[Color] = [
	Color(0.18, 0.18, 0.20),
	Color(0.16, 0.24, 0.42),
	Color(0.28, 0.22, 0.18),
	Color(0.10, 0.12, 0.14),
]

const HAT_OPTIONS: Array[Dictionary] = [
	{"id": CharacterAppearance.HAT_NONE, "label": "Bare headed"},
	{"id": CharacterAppearance.HAT_FLAT_CAP, "label": "Flat cap"},
	{"id": CharacterAppearance.HAT_PEAKED_CAP, "label": "Peaked cap"},
]

var _appearance: CharacterAppearance = CharacterAppearance.default_appearance()
var _preview: CharacterPreview
var _viewport: SubViewport
var _camera: Camera3D
var _name_field: LineEdit
var _hat_row: HBoxContainer
var _hat_buttons: Array[Button] = []
var _skin_buttons:     Array[Button] = []
var _clothing_buttons: Array[Button] = []
var _trousers_buttons: Array[Button] = []
var _sail_btn: Button


func _ready() -> void:
	_build_ui()
	_refresh_preview()


func open_with_existing(data: PlayerData) -> void:
	if data == null:
		_appearance = CharacterAppearance.default_appearance()
		_name_field.text = "Captain"
	else:
		_appearance = data.appearance.duplicate()
		_name_field.text = data.display_name
	_refresh_preview()
	_rebuild_hat_selection()
	_refresh_swatch_selection()
	_update_sail_btn_enabled()
	visible = true


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = HudStyle.make_theme()

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	add_child(margin)

	var root := HBoxContainer.new()
	root.add_theme_constant_override("separation", 24)
	margin.add_child(root)

	# ── Preview column ──────────────────────────────────────────────────────────
	var preview_col := VBoxContainer.new()
	preview_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_col.size_flags_stretch_ratio = 1.15
	root.add_child(preview_col)

	var preview_title := Label.new()
	preview_title.text = "CAPTAIN"
	preview_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	preview_title.add_theme_font_size_override("font_size", 22)
	preview_title.add_theme_color_override("font_color", HudStyle.C_AMBER)
	preview_col.add_child(preview_title)

	var viewport_frame := Panel.new()
	viewport_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	viewport_frame.custom_minimum_size = Vector2(360, 420)
	preview_col.add_child(viewport_frame)

	var vp_container := SubViewportContainer.new()
	vp_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	vp_container.stretch = true
	viewport_frame.add_child(vp_container)

	_viewport = SubViewport.new()
	_viewport.size = Vector2i(480, 560)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.own_world_3d = true
	vp_container.add_child(_viewport)

	var env := WorldEnvironment.new()
	var we := Environment.new()
	we.background_mode = Environment.BG_COLOR
	we.background_color = Color(0.06, 0.07, 0.10)
	we.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	we.ambient_light_color = Color(0.45, 0.42, 0.38)
	we.ambient_light_energy = 0.55
	env.environment = we
	_viewport.add_child(env)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-42.0, 38.0, 0.0)
	light.light_energy = 1.1
	_viewport.add_child(light)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-18.0, -120.0, 0.0)
	fill.light_energy = 0.35
	fill.light_color = Color(0.7, 0.75, 0.9)
	_viewport.add_child(fill)

	_camera = Camera3D.new()
	_camera.transform = CharacterPreview.camera_transform()
	_camera.fov = 42.0
	_viewport.add_child(_camera)

	_preview = CharacterPreview.new()
	_viewport.add_child(_preview)

	var floor := MeshInstance3D.new()
	var floor_mesh := BoxMesh.new()
	floor_mesh.size = Vector3(4.0, 0.08, 4.0)
	floor.mesh = floor_mesh
	floor.position = Vector3(0.0, 0.0, 0.0)
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.14, 0.13, 0.12)
	floor_mat.roughness = 0.92
	floor.material_override = floor_mat
	_viewport.add_child(floor)

	# ── Options column ──────────────────────────────────────────────────────────
	var opts := VBoxContainer.new()
	opts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	opts.add_theme_constant_override("separation", 12)
	root.add_child(opts)

	var hdr := Label.new()
	hdr.text = "CREATE YOUR CAPTAIN"
	hdr.add_theme_font_size_override("font_size", 20)
	hdr.add_theme_color_override("font_color", HudStyle.C_AMBER)
	opts.add_child(hdr)

	var sub := Label.new()
	sub.text = "Name, colours, and hat — more kit when we model it."
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.add_theme_font_size_override("font_size", 12)
	sub.add_theme_color_override("font_color", HudStyle.C_LABEL)
	opts.add_child(sub)

	opts.add_child(_section_label("Name"))
	_name_field = LineEdit.new()
	_name_field.placeholder_text = "Captain"
	_name_field.text = "Captain"
	_name_field.max_length = 32
	_name_field.text_changed.connect(_on_name_changed)
	opts.add_child(_name_field)

	opts.add_child(_section_label("Complexion"))
	opts.add_child(_make_swatch_row(SKIN_PRESETS, _on_skin_picked, _skin_buttons))

	opts.add_child(_section_label("Jacket"))
	opts.add_child(_make_swatch_row(CLOTHING_PRESETS, _on_clothing_picked, _clothing_buttons))

	opts.add_child(_section_label("Trousers"))
	opts.add_child(_make_swatch_row(TROUSERS_PRESETS, _on_trousers_picked, _trousers_buttons))

	opts.add_child(_section_label("Headwear"))
	_hat_row = HBoxContainer.new()
	_hat_row.add_theme_constant_override("separation", 8)
	opts.add_child(_hat_row)
	_build_hat_buttons()

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	opts.add_child(spacer)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	actions.alignment = BoxContainer.ALIGNMENT_END
	opts.add_child(actions)

	var back_btn := Button.new()
	back_btn.text = "Back"
	back_btn.pressed.connect(func() -> void: cancelled.emit())
	actions.add_child(back_btn)

	_sail_btn = Button.new()
	_sail_btn.text = "Set sail"
	_sail_btn.pressed.connect(_on_confirm)
	actions.add_child(_sail_btn)
	_refresh_swatch_selection()
	_update_sail_btn_enabled()


func _section_label(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", HudStyle.C_LABEL)
	return lbl


func _make_swatch_row(
	colors: Array[Color], on_pick: Callable, store: Array[Button]
) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	for c in colors:
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(36, 28)
		btn.tooltip_text = "#%s" % c.to_html(false)
		btn.set_meta("swatch_color", c)
		btn.pressed.connect(on_pick.bind(c))
		_apply_swatch_style(btn, c, false)
		row.add_child(btn)
		store.append(btn)
	return row


func _apply_swatch_style(btn: Button, c: Color, selected: bool) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.border_color = HudStyle.C_AMBER if selected else HudStyle.C_BRASS
	sb.set_border_width_all(2 if selected else 1)
	sb.set_corner_radius_all(2)
	btn.add_theme_stylebox_override("normal",  sb)
	btn.add_theme_stylebox_override("hover",   sb)
	btn.add_theme_stylebox_override("pressed", sb)
	btn.add_theme_stylebox_override("focus",   sb)


func _refresh_swatch_selection() -> void:
	_highlight_swatch_for(_skin_buttons,     _appearance.skin_color)
	_highlight_swatch_for(_clothing_buttons, _appearance.clothing_color)
	_highlight_swatch_for(_trousers_buttons, _appearance.trousers_color)


func _highlight_swatch_for(buttons: Array[Button], current: Color) -> void:
	for btn in buttons:
		if btn == null:
			continue
		var c: Color = btn.get_meta("swatch_color", Color.WHITE)
		var selected := c.is_equal_approx(current)
		_apply_swatch_style(btn, c, selected)


func _update_sail_btn_enabled() -> void:
	if _sail_btn == null or _name_field == null:
		return
	_sail_btn.disabled = _name_field.text.strip_edges().is_empty()


func _build_hat_buttons() -> void:
	for child in _hat_row.get_children():
		child.queue_free()
	_hat_buttons.clear()
	for opt in HAT_OPTIONS:
		var btn := Button.new()
		btn.text = str(opt.get("label", "Hat"))
		btn.toggle_mode = true
		btn.pressed.connect(_on_hat_pressed.bind(str(opt.get("id", ""))))
		_hat_row.add_child(btn)
		_hat_buttons.append(btn)
	_rebuild_hat_selection()


func _rebuild_hat_selection() -> void:
	for i in range(_hat_buttons.size()):
		if i >= HAT_OPTIONS.size():
			continue
		var id: String = str(HAT_OPTIONS[i].get("id", ""))
		_hat_buttons[i].button_pressed = id == _appearance.hat_id


func _on_name_changed(_text: String) -> void:
	_update_sail_btn_enabled()


func _on_skin_picked(c: Color) -> void:
	_appearance.skin_color = c
	_refresh_preview()
	_refresh_swatch_selection()


func _on_clothing_picked(c: Color) -> void:
	_appearance.clothing_color = c
	_refresh_preview()
	_refresh_swatch_selection()


func _on_trousers_picked(c: Color) -> void:
	_appearance.trousers_color = c
	_refresh_preview()
	_refresh_swatch_selection()


func _on_hat_pressed(hat_id: String) -> void:
	_appearance.hat_id = hat_id
	_rebuild_hat_selection()
	_refresh_preview()


func _refresh_preview() -> void:
	if _preview != null:
		_preview.apply_appearance(_appearance)


func _on_confirm() -> void:
	var name := _name_field.text.strip_edges()
	if name.is_empty():
		name = "Captain"
	confirmed.emit(name, _appearance.duplicate())
