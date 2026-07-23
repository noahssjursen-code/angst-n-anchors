class_name CharacterCreatorPanel
extends Control

## First-time captain creation. This is a focused wrapper around the shared
## CharacterAppearance contract and CharacterVisual renderer used by NPCs.

signal confirmed(display_name: String, appearance: CharacterAppearance)
signal cancelled

const CHARACTER_CATALOG := preload("res://scripts/character/character_catalog.gd")
const REFERENCE_SIZE := Vector2(1920.0, 1080.0)
const COMPLEXIONS: Array[Color] = [
	Color("e0b997"), Color("d4a37f"), Color("b98262"),
	Color("9e684c"), Color("7c513d"), Color("5d3c2e"),
]
const HAIR_COLORS: Array[Color] = [
	Color("20140d"), Color("4a2c1d"), Color("80522f"),
	Color("b08a62"), Color("d0c2a4"), Color("5d6266"), Color("17191b"),
]
const CLOTHING_COLORS: Array[Color] = [
	Color("273744"), Color("294e68"), Color("3d4937"), Color("6a392b"),
	Color("bd6a1f"), Color("d59a21"), Color("d8d1bc"), Color("22262a"),
]
const TROUSER_COLORS: Array[Color] = [
	Color("24292d"), Color("263a4b"), Color("384139"), Color("51473d"),
	Color("16191c"), Color("6b4936"),
]
const ACCESSORY_COLORS: Array[Color] = [
	Color("24292c"), Color("71503a"), Color("294e68"), Color("b45b25"),
	Color("d4a626"), Color("c7c9c5"),
]

var _appearance: CharacterAppearance = CharacterAppearance.default_appearance()
var _preview: CharacterPreview
var _name_field: LineEdit
var _confirm: Button
var _status: Label
var _preset_selector: OptionButton
var _tabs: TabContainer
var _preset_ids := PackedStringArray()
var _selectors: Dictionary = {}
var _swatch_rows: Dictionary = {}


func _ready() -> void:
	_configure_layout_scale()
	get_viewport().size_changed.connect(_configure_layout_scale)
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = HudStyle.make_theme()
	_build_ui()
	_refresh_all()


func open_with_existing(data: PlayerData) -> void:
	if not is_node_ready():
		await ready
	if data == null:
		_appearance = CharacterAppearance.default_appearance()
		_apply_outfit_preset("harbour_captain")
		_name_field.text = ""
		_name_field.placeholder_text = "Captain name"
	else:
		_appearance = data.appearance.duplicate()
		_name_field.text = data.display_name
	_refresh_all()
	visible = true
	_name_field.grab_focus()


func _build_ui() -> void:
	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.008, 0.016, 0.021, 0.95)
	add_child(shade)

	var outer := MarginContainer.new()
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	outer.add_theme_constant_override("margin_left", 42)
	outer.add_theme_constant_override("margin_right", 42)
	outer.add_theme_constant_override("margin_top", 28)
	outer.add_theme_constant_override("margin_bottom", 28)
	add_child(outer)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", HudStyle.make_title_panel_style())
	outer.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 30)
	margin.add_theme_constant_override("margin_right", 30)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	panel.add_child(margin)

	var root := HBoxContainer.new()
	root.add_theme_constant_override("separation", 32)
	margin.add_child(root)
	_build_preview_column(root)
	_build_options_column(root)


func _build_preview_column(root: HBoxContainer) -> void:
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = 430
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_stretch_ratio = 0.9
	column.add_theme_constant_override("separation", 8)
	root.add_child(column)

	var label := Label.new()
	label.text = "CAPTAIN PREVIEW"
	HudStyle.apply_body_font(label, 11, HudStyle.C_COPPER, true)
	column.add_child(label)

	var frame := PanelContainer.new()
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.custom_minimum_size = Vector2(420, 540)
	var frame_style := StyleBoxFlat.new()
	frame_style.bg_color = Color("071017")
	frame_style.border_color = Color("34444d")
	frame_style.set_border_width_all(1)
	frame.add_theme_stylebox_override("panel", frame_style)
	column.add_child(frame)

	var viewport_container := SubViewportContainer.new()
	viewport_container.stretch = true
	frame.add_child(viewport_container)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(540, 680)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.own_world_3d = true
	viewport.transparent_bg = false
	viewport_container.add_child(viewport)

	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("071017")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("778b98")
	environment.ambient_light_energy = 0.52
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment_node.environment = environment
	viewport.add_child(environment_node)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-44.0, -28.0, 0.0)
	key.light_color = Color("e8f0f5")
	key.light_energy = 1.35
	key.shadow_enabled = true
	viewport.add_child(key)
	var rim := OmniLight3D.new()
	rim.position = Vector3(-1.5, 1.5, 0.5)
	rim.light_color = Color("df6428")
	rim.light_energy = 2.0
	rim.omni_range = 4.0
	viewport.add_child(rim)
	var fill := OmniLight3D.new()
	fill.position = Vector3(1.6, 1.25, 1.4)
	fill.light_color = Color("75a8cb")
	fill.light_energy = 1.15
	fill.omni_range = 4.0
	viewport.add_child(fill)

	var camera := Camera3D.new()
	camera.transform = CharacterPreview.camera_transform()
	camera.fov = 38.0
	viewport.add_child(camera)
	_preview = CharacterPreview.new()
	_preview.set_spin_enabled(false)
	viewport.add_child(_preview)

	var floor := MeshInstance3D.new()
	var floor_mesh := CylinderMesh.new()
	floor_mesh.top_radius = 1.05
	floor_mesh.bottom_radius = 1.12
	floor_mesh.height = 0.10
	floor.mesh = floor_mesh
	floor.position.y = -0.06
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color("151c22")
	floor_material.roughness = 0.92
	floor.material_override = floor_material
	viewport.add_child(floor)

	var note := Label.new()
	note.text = "The same appearance record is used for your player and every NPC."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	HudStyle.apply_body_font(note, 11, HudStyle.C_LABEL)
	column.add_child(note)


func _build_options_column(root: HBoxContainer) -> void:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_stretch_ratio = 1.25
	column.add_theme_constant_override("separation", 10)
	root.add_child(column)

	var eyebrow := Label.new()
	eyebrow.text = "NEW CAPTAIN  /  01 OF 03"
	HudStyle.apply_body_font(eyebrow, 11, HudStyle.C_COPPER, true)
	column.add_child(eyebrow)
	var title := Label.new()
	title.text = "Who is taking the helm?"
	HudStyle.apply_display_font(title, 42, HudStyle.C_TEXT)
	column.add_child(title)
	var intro := Label.new()
	intro.text = "Build a recognizable captain now. Company identity, first vessel and home waters come next."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	HudStyle.apply_body_font(intro, 13, HudStyle.C_LABEL)
	column.add_child(intro)

	_name_field = LineEdit.new()
	_name_field.placeholder_text = "Captain name"
	_name_field.max_length = 32
	_name_field.text_changed.connect(func(_text: String) -> void: _validate())
	_name_field.text_submitted.connect(func(_text: String) -> void: _submit())
	column.add_child(_labeled_control("CAPTAIN NAME", _name_field))

	var preset_row := HBoxContainer.new()
	preset_row.add_theme_constant_override("separation", 8)
	_preset_selector = OptionButton.new()
	_preset_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for preset_raw in CHARACTER_CATALOG.outfit_presets():
		var preset := preset_raw as Dictionary
		_preset_selector.add_item(str(preset.get("label", preset.get("id", "Outfit"))))
		_preset_ids.append(str(preset.get("id", "")))
	_preset_selector.item_selected.connect(func(index: int) -> void:
		if index >= 0 and index < _preset_ids.size():
			_apply_outfit_preset(_preset_ids[index])
			_refresh_all()
	)
	preset_row.add_child(_preset_selector)
	var random_button := Button.new()
	random_button.text = "Randomize"
	random_button.pressed.connect(_randomize)
	preset_row.add_child(random_button)
	column.add_child(_labeled_control("WORKING LOOK", preset_row))

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.custom_minimum_size.y = 330
	column.add_child(_tabs)
	_build_person_tab(_tabs)
	_build_clothing_tab(_tabs)
	_build_accessories_tab(_tabs)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	column.add_child(footer)
	_status = Label.new()
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	HudStyle.apply_body_font(_status, 11, HudStyle.C_AMBER)
	footer.add_child(_status)
	var back := Button.new()
	back.text = "Back"
	back.pressed.connect(func() -> void: cancelled.emit())
	footer.add_child(back)
	_confirm = MenuActionButton.new()
	_confirm.text = "Build company  >"
	_confirm.pressed.connect(_submit)
	footer.add_child(_confirm)


func _build_person_tab(tabs: TabContainer) -> void:
	var content := _tab_content(tabs, "PERSON")
	_add_selector(content, "Body", &"body_presets", "body_id")
	_add_selector(content, "Hair", &"hair", "hair_id")
	_add_selector(content, "Facial hair", &"facial_hair", "facial_hair_id")
	_add_selector(content, "Face detail", &"face_surfaces", "face_texture_profile_id")
	_add_swatches(content, "Complexion", "skin_color", COMPLEXIONS)
	_add_swatches(content, "Hair colour", "hair_color", HAIR_COLORS)


func _build_clothing_tab(tabs: TabContainer) -> void:
	var content := _tab_content(tabs, "CLOTHING")
	_add_selector(content, "Top", &"tops", "top_id")
	_add_selector(content, "Outerwear", &"outerwear", "outerwear_id")
	_add_selector(content, "Trousers", &"trousers", "trousers_id")
	_add_selector(content, "Footwear", &"footwear", "footwear_id")
	_add_selector(content, "Headwear", &"headwear", "headwear_id")
	_add_swatches(content, "Top colour", "top_color", CLOTHING_COLORS)
	_add_swatches(content, "Outer colour", "clothing_color", CLOTHING_COLORS)
	_add_swatches(content, "Trouser colour", "trousers_color", TROUSER_COLORS)
	_add_swatches(content, "Footwear colour", "footwear_color", TROUSER_COLORS)
	_add_swatches(content, "Headwear colour", "headwear_color", CLOTHING_COLORS)


func _build_accessories_tab(tabs: TabContainer) -> void:
	var content := _tab_content(tabs, "ACCESSORIES")
	_add_selector(content, "Glasses", &"eyewear", "eyewear_id")
	_add_selector(content, "Mouth", &"face_accessories", "face_accessory_id")
	_add_selector(content, "Neckwear", &"neckwear", "neckwear_id")
	_add_selector(content, "Gloves", &"handwear", "handwear_id")
	_add_selector(content, "Work gear", &"utility_accessories", "utility_id")
	_add_swatches(content, "Accessory colour", "accessory_color", ACCESSORY_COLORS)
	_add_swatches(content, "Trim / badge colour", "accent_color", ACCESSORY_COLORS)


func _tab_content(tabs: TabContainer, tab_name: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = tab_name
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(scroll)
	var content := VBoxContainer.new()
	content.name = "Options"
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 7)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	margin.add_child(content)
	scroll.add_child(margin)
	return content


func _add_selector(parent: VBoxContainer, label_text: String, slot: StringName, property: String) -> void:
	var selector := OptionButton.new()
	selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var ids := PackedStringArray()
	for option_raw in CHARACTER_CATALOG.options(slot):
		var option := option_raw as Dictionary
		selector.add_item(str(option.get("label", option.get("id", ""))))
		ids.append(str(option.get("id", "")))
	selector.item_selected.connect(func(index: int) -> void:
		if index < 0 or index >= ids.size():
			return
		var item_id := ids[index]
		_appearance.set(property, item_id)
		_apply_item_default_color(slot, item_id)
		_refresh_all()
	)
	parent.add_child(_labeled_control(label_text.to_upper(), selector))
	_selectors[property] = {"control": selector, "ids": ids}


func _add_swatches(parent: VBoxContainer, label_text: String, property: String, colors: Array[Color]) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var buttons: Array[Button] = []
	for color in colors:
		var button := Button.new()
		button.custom_minimum_size = Vector2(34, 28)
		button.tooltip_text = "#%s" % color.to_html(false)
		button.set_meta("swatch_color", color)
		button.pressed.connect(func() -> void:
			_appearance.set(property, color)
			_refresh_all()
		)
		row.add_child(button)
		buttons.append(button)
	parent.add_child(_labeled_control(label_text.to_upper(), row))
	_swatch_rows[property] = buttons

func _labeled_control(label_text: String, control: Control) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	var label := Label.new()
	label.text = label_text
	HudStyle.apply_body_font(label, 10, HudStyle.C_COPPER, true)
	box.add_child(label)
	box.add_child(control)
	return box


func _apply_outfit_preset(id: String) -> void:
	var preset := CHARACTER_CATALOG.outfit_preset(id)
	if preset.is_empty():
		return
	for property in [
		"body_id", "face_texture_profile_id", "top_id", "outerwear_id", "trousers_id", "footwear_id",
		"headwear_id", "facial_hair_id", "hair_id",
	]:
		if preset.has(property):
			_appearance.set(property, str(preset[property]))
	for property in [
		"eyewear_id", "face_accessory_id", "neckwear_id", "handwear_id", "utility_id", "uniform_id",
	]:
		_appearance.set(property, str(preset.get(property, "none")))
	for property in [
		"top_color", "clothing_color", "trousers_color", "footwear_color",
		"skin_color", "hair_color", "headwear_color", "accent_color", "accessory_color",
		"company_primary_color", "company_secondary_color",
	]:
		if preset.has(property):
			_appearance.set(property, Color.from_string(str(preset[property]), _appearance.get(property)))


func _apply_item_default_color(slot: StringName, id: String) -> void:
	var option := CHARACTER_CATALOG.option(slot, id)
	if not option.has("default_color"):
		return
	var property := ""
	match slot:
		&"tops": property = "top_color"
		&"outerwear": property = "clothing_color"
		&"trousers": property = "trousers_color"
		&"footwear": property = "footwear_color"
		&"headwear": property = "headwear_color"
		&"eyewear", &"face_accessories", &"neckwear", &"handwear", &"utility_accessories":
			property = "accessory_color"
	if not property.is_empty():
		_appearance.set(property, Color.from_string(str(option.default_color), _appearance.get(property)))


func _randomize() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	if not _preset_ids.is_empty():
		_apply_outfit_preset(_preset_ids[rng.randi_range(0, _preset_ids.size() - 1)])
	var bodies := CHARACTER_CATALOG.ids(&"body_presets")
	if not bodies.is_empty():
		_appearance.body_id = bodies[rng.randi_range(0, bodies.size() - 1)]
	_appearance.skin_color = COMPLEXIONS[rng.randi_range(0, COMPLEXIONS.size() - 1)]
	_appearance.hair_color = HAIR_COLORS[rng.randi_range(0, HAIR_COLORS.size() - 1)]
	_refresh_all()
	_status.text = "Randomized. Adjust any detail before continuing."


func _refresh_all() -> void:
	if _preview != null:
		_preview.apply_appearance(_appearance)
	for property in _selectors:
		var entry := _selectors[property] as Dictionary
		var control := entry.get("control") as OptionButton
		var ids := entry.get("ids") as PackedStringArray
		if control != null:
			control.select(maxi(0, ids.find(str(_appearance.get(property)))))
	for property in _swatch_rows:
		var current := _appearance.get(property) as Color
		for button_raw in _swatch_rows[property]:
			var button := button_raw as Button
			var color := button.get_meta("swatch_color", Color.WHITE) as Color
			_style_swatch(button, color, color.is_equal_approx(current))
	_validate()


func _style_swatch(button: Button, color: Color, selected: bool) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = HudStyle.C_TEXT if selected else color.darkened(0.35)
	style.set_border_width_all(3 if selected else 1)
	style.set_corner_radius_all(3)
	button.add_theme_stylebox_override("normal", style)
	button.add_theme_stylebox_override("hover", style)
	button.add_theme_stylebox_override("pressed", style)
	button.add_theme_stylebox_override("focus", style)


func _validate() -> bool:
	if _name_field == null:
		return false
	var length := _name_field.text.strip_edges().length()
	var valid := length >= 2
	if _confirm != null:
		_confirm.disabled = not valid
	if _status != null:
		_status.text = "Enter at least two characters." if length < 2 else "Appearance is saved with this captain."
	return valid


func _submit() -> void:
	if not _validate():
		return
	confirmed.emit(_name_field.text.strip_edges(), _appearance.duplicate())


func select_working_look(id: String) -> void:
	_apply_outfit_preset(id)
	var index := _preset_ids.find(id)
	if index >= 0 and _preset_selector != null:
		_preset_selector.select(index)
	_refresh_all()


func select_editor_section(index: int) -> void:
	if _tabs != null:
		_tabs.current_tab = clampi(index, 0, _tabs.get_tab_count() - 1)


func _configure_layout_scale() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	var factor := minf(viewport_size.x / REFERENCE_SIZE.x, viewport_size.y / REFERENCE_SIZE.y)
	factor = maxf(factor, 0.5)
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	position = Vector2.ZERO
	scale = Vector2.ONE * factor
	size = viewport_size / factor
