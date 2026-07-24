class_name BuildingBrickEditor
extends CanvasLayer

## Developer building authoring app (scenes/apps/).
## Same shell as ShipyardBrickEditor: PARTS grid, viewport tool strip, properties
## drawer, Building dialog for file/role/pad. Exports JSON under
## resources/data/buildings/.

enum Tool { PLACE = 0, ERASE = 1, MARK = 2 }

const THUMB_PX := 64
const DEFAULT_GRID := Vector3i(32, 16, 32)
const COLOR_PRESETS := [
	{"name": "Catalog", "custom": false},
	{"name": "White", "color": Color(0.92, 0.91, 0.88)},
	{"name": "Cream", "color": Color(0.86, 0.80, 0.68)},
	{"name": "Timber", "color": Color(0.48, 0.34, 0.22)},
	{"name": "Dark wood", "color": Color(0.28, 0.18, 0.12)},
	{"name": "Brick", "color": Color(0.62, 0.32, 0.24)},
	{"name": "Slate", "color": Color(0.32, 0.36, 0.40)},
	{"name": "Charcoal", "color": Color(0.18, 0.18, 0.20)},
	{"name": "Moss", "color": Color(0.28, 0.40, 0.30)},
	{"name": "Harbour", "color": Color(0.22, 0.38, 0.48)},
	{"name": "Red oxide", "color": Color(0.55, 0.18, 0.14)},
	{"name": "Yellow", "color": Color(0.82, 0.68, 0.22)},
]

var _layout := BuildingLayout.new()
var _grid: BuildingGrid
var _layer_y: int = 0
var _yaw: int = 0
var _brick_id: String = "" ## empty until the rebuilt catalog has entries
var _tool: int = Tool.PLACE
var _painting := false
var _last_paint_cell: Vector3i = Vector3i(-999, -999, -999)
var _thumb_cache: Dictionary = {}
var _paint_color := Color(0.78, 0.80, 0.84)
var _use_catalog_color := true
## Mark region for copy/paste: click A, then B (3D box — change layer between clicks).
var _mark_anchor: Vector3i = Vector3i(-999, -999, -999)
var _mark_anchor_set := false
var _mark_complete := false
var _mark_min := Vector3i.ZERO
var _mark_max := Vector3i.ZERO
var _clipboard: Dictionary = {}
## Absolute min corner of the last copied region (for “paste on this layer”).
var _clipboard_src_min := Vector3i.ZERO
## Anchor of the last successful paste — “Paste ↑” stacks above this, not the original copy.
var _last_paste_anchor := Vector3i(-999, -999, -999)

var _root: Control
var _viewport: SubViewport
var _world: Node3D
var _pad_root: Node3D
var _brick_root: Node3D
var _brick_visuals: Dictionary = {}
var _grid_overlay: Node3D
var _ghost: Node3D
var _mark_preview: Node3D
var _paste_preview: Node3D
var _ghost_brick_id: String = ""
var _ghost_cell: Vector3i = Vector3i(-999, -999, -999)
var _ghost_yaw: int = -1
var _ghost_valid: bool = false
var _ghost_color := Color(0, 0, 0, 0)
var _ghost_sign_text: String = ""
var _camera: Camera3D
var _cam_yaw: float = 35.0
var _cam_pitch: float = -35.0
var _cam_dist: float = 28.0
var _cam_target: Vector3 = Vector3(0.0, 2.0, 0.0)
var _orbiting := false
var _panning := false
var _orbit_last: Vector2 = Vector2.ZERO

var _hint_lbl: Label
var _toast_lbl: Label
var _rules_lbl: Label
var _layer_lbl: Label
var _summary_lbl: Label
var _file_lbl: Label
var _name_edit: LineEdit
var _role_option: OptionButton
var _pad_template_option: OptionButton
var _load_option: OptionButton
var _color_picker: ColorPickerButton
var _color_preset_btns: Array[Button] = []
var _brick_rows: Dictionary = {}
var _vp_host: SubViewportContainer
var _export_lbl: Label
var _open_dialog: FileDialog
var _save_dialog: FileDialog
var _current_path: String = ""
var _place_btn: Button
var _erase_btn: Button
var _mark_btn: Button
var _copy_btn: Button
var _paste_btn: Button
var _paste_layer_btn: Button
var _paste_up_btn: Button
var _confirm_btn: Button
var _context_drawer: PanelContainer
var _context_title: Label
var _context_info: Label
var _color_section: VBoxContainer
var _sign_section: VBoxContainer
var _sign_text_edit: LineEdit
var _clipboard_section: VBoxContainer
var _building_dialog: PanelContainer


func _init() -> void:
	name = "BuildingBrickEditor"
	layer = 14
	_layout.blueprint_id = ""
	_layout.display_name = "Untitled Building"
	_layout.role = "decorative"
	_layout.grid_size = DEFAULT_GRID
	_grid = _layout.grid()
	_build_chrome()


func _ready() -> void:
	var vp := get_viewport()
	if vp != null and not vp.size_changed.is_connected(_resize):
		vp.size_changed.connect(_resize)
	for id in _brick_rows.keys():
		var row: PanelContainer = _brick_rows[id]
		var thumb := _row_thumb_rect(row)
		if thumb == null:
			continue
		if _thumb_cache.has(id):
			thumb.texture = _thumb_cache[id] as Texture2D
		else:
			_bake_brick_thumbnail(str(id), thumb)
	_open_editor()


func _row_thumb_rect(row: PanelContainer) -> TextureRect:
	if row == null:
		return null
	return row.find_child("Thumb", true, false) as TextureRect


func _open_editor() -> void:
	_layer_y = 0
	_yaw = 0
	_brick_id = BrickCatalog.BRICKS.keys()[0] if not BrickCatalog.BRICKS.is_empty() else ""
	_tool = Tool.PLACE
	_clear_mark()
	if _name_edit != null:
		_name_edit.text = _layout.display_name
	_select_role(_layout.role)
	_select_pad_template(_layout.pad_template_id)
	_use_catalog_color = true
	_sync_color_picker_from_catalog()
	_refresh_file_label()
	_refresh_load_options()
	if _export_lbl != null:
		_export_lbl.text = ""
	_resize()
	_root.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_rebuild_preview()
	_refresh_rules()
	_refresh_palette_selection()
	_refresh_hint()
	_refresh_context_drawer()
	_refresh_summary()


func _build_chrome() -> void:
	_root = Control.new()
	_root.name = "EditorRoot"
	_root.visible = false
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = HudStyle.make_theme()
	add_child(_root)

	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.025, 0.04, 0.05, 1.0)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bg)

	var shell := VBoxContainer.new()
	shell.name = "EditorShell"
	shell.set_anchors_preset(Control.PRESET_FULL_RECT)
	shell.add_theme_constant_override("separation", 0)
	_root.add_child(shell)

	_build_top_bar(shell)

	var workspace := HBoxContainer.new()
	workspace.name = "Workspace"
	workspace.size_flags_vertical = Control.SIZE_EXPAND_FILL
	workspace.add_theme_constant_override("separation", 0)
	shell.add_child(workspace)

	_build_palette(workspace)

	var center := VBoxContainer.new()
	center.name = "ViewportColumn"
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.add_theme_constant_override("separation", 0)
	workspace.add_child(center)
	_build_viewport(center)
	_build_viewport_chrome(center)

	_build_context_drawer(workspace)
	_build_building_dialog()

	_open_dialog = FileDialog.new()
	_open_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_open_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_open_dialog.add_filter("*.json", "Building blueprints")
	_open_dialog.file_selected.connect(_load_json)
	_root.add_child(_open_dialog)

	_save_dialog = FileDialog.new()
	_save_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_save_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_save_dialog.add_filter("*.json", "Building blueprints")
	_save_dialog.file_selected.connect(_save_to_path)
	_root.add_child(_save_dialog)


func _build_top_bar(parent: VBoxContainer) -> void:
	var panel := UiBuilder.inner_panel()
	panel.name = "TopBar"
	panel.custom_minimum_size.y = 54.0
	parent.add_child(panel)

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	panel.add_child(bar)

	var title := Label.new()
	title.name = "TitleLabel"
	title.text = "BUILDING"
	HudStyle.apply_display_font(title, 24, HudStyle.C_AMBER)
	bar.add_child(title)

	var rule := VSeparator.new()
	rule.custom_minimum_size.x = 1.0
	bar.add_child(rule)

	_summary_lbl = Label.new()
	_summary_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_summary_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_summary_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	HudStyle.apply_body_font(_summary_lbl, 13, HudStyle.C_LABEL)
	bar.add_child(_summary_lbl)

	var building_btn := UiBuilder.compact_button("Building", 90)
	building_btn.tooltip_text = "Name, role, pad template, load / save"
	building_btn.pressed.connect(_toggle_building_dialog)
	bar.add_child(building_btn)

	_confirm_btn = UiBuilder.compact_button("Save", 90)
	_confirm_btn.pressed.connect(_save_json)
	bar.add_child(_confirm_btn)


func _build_palette(parent: HBoxContainer) -> void:
	var side := UiBuilder.panel(Vector2(292, 0))
	side.name = "PartsPalette"
	side.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(side)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	side.add_child(col)

	var heading := HBoxContainer.new()
	col.add_child(heading)
	var title := UiBuilder.section_header("PARTS")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	var count := Label.new()
	count.text = str(BrickCatalog.ids_for_buildings().size())
	count.add_theme_color_override("font_color", HudStyle.C_LABEL)
	heading.add_child(count)

	var brick_scroll := ScrollContainer.new()
	brick_scroll.name = "PartsScroll"
	brick_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	brick_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(brick_scroll)

	var grid := GridContainer.new()
	grid.name = "PartsGrid"
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	brick_scroll.add_child(grid)

	_brick_rows.clear()
	for id in BrickCatalog.ids_for_buildings():
		var row := _make_item_row(id)
		grid.add_child(row)
		_brick_rows[id] = row


func _build_viewport(parent: VBoxContainer) -> void:
	_vp_host = SubViewportContainer.new()
	_vp_host.name = "BuildViewport"
	_vp_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vp_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_vp_host.stretch = true
	_vp_host.mouse_filter = Control.MOUSE_FILTER_STOP
	_vp_host.gui_input.connect(_on_viewport_gui_input)
	parent.add_child(_vp_host)

	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.size = Vector2i(1280, 720)
	_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	_viewport.handle_input_locally = true
	_vp_host.add_child(_viewport)

	_world = Node3D.new()
	_world.name = "EditorWorld"
	_viewport.add_child(_world)

	_camera = Camera3D.new()
	_camera.fov = 50.0
	_camera.current = true
	_world.add_child(_camera)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48.0, 40.0, 0.0)
	sun.light_energy = 1.2
	_world.add_child(sun)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-15.0, -130.0, 0.0)
	fill.light_energy = 0.35
	_world.add_child(fill)

	var env := WorldEnvironment.new()
	var we := Environment.new()
	we.background_mode = Environment.BG_COLOR
	we.background_color = Color(0.06, 0.08, 0.11)
	we.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	we.ambient_light_color = Color(0.2, 0.22, 0.26)
	we.ambient_light_energy = 0.95
	env.environment = we
	_world.add_child(env)


func _build_viewport_chrome(parent: VBoxContainer) -> void:
	var strip := UiBuilder.inner_panel()
	strip.name = "ContextStrip"
	strip.custom_minimum_size.y = 48.0
	parent.add_child(strip)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	strip.add_child(row)

	_place_btn = UiBuilder.tool_button("Place")
	_place_btn.pressed.connect(func() -> void: _set_tool(Tool.PLACE))
	row.add_child(_place_btn)
	_erase_btn = UiBuilder.tool_button("Erase")
	_erase_btn.pressed.connect(func() -> void: _set_tool(Tool.ERASE))
	row.add_child(_erase_btn)
	_mark_btn = UiBuilder.tool_button("Mark")
	_mark_btn.tooltip_text = "Click two opposite corners to select a region (M). Press again or Esc to clear."
	_mark_btn.pressed.connect(_toggle_mark_tool)
	row.add_child(_mark_btn)

	var rotate := UiBuilder.compact_button("Rotate  R", 86)
	rotate.pressed.connect(func() -> void:
		_rotate_yaw()
		_refresh_rules()
		_refresh_ghost_from_mouse()
	)
	row.add_child(rotate)

	var clear_btn := UiBuilder.compact_button("Clear", 70)
	clear_btn.tooltip_text = "Clear all bricks on this pad"
	clear_btn.pressed.connect(_clear_layout)
	row.add_child(clear_btn)

	var layer_down := UiBuilder.compact_button("−", 34)
	layer_down.tooltip_text = "Previous layer ([)"
	layer_down.pressed.connect(func() -> void: _set_layer_y(_layer_y - 1))
	row.add_child(layer_down)

	_layer_lbl = Label.new()
	_layer_lbl.custom_minimum_size.x = 92.0
	_layer_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_layer_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	HudStyle.apply_body_font(_layer_lbl, 12, HudStyle.C_TEXT, true)
	row.add_child(_layer_lbl)

	var layer_up := UiBuilder.compact_button("+", 34)
	layer_up.tooltip_text = "Next layer (])"
	layer_up.pressed.connect(func() -> void: _set_layer_y(_layer_y + 1))
	row.add_child(layer_up)

	_hint_lbl = Label.new()
	_hint_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hint_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hint_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	HudStyle.apply_body_font(_hint_lbl, 12, HudStyle.C_LABEL)
	row.add_child(_hint_lbl)

	_toast_lbl = Label.new()
	_toast_lbl.visible = false
	_toast_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_toast_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	HudStyle.apply_body_font(_toast_lbl, 12, HudStyle.C_GREEN, true)
	row.add_child(_toast_lbl)


func _build_context_drawer(parent: HBoxContainer) -> void:
	_context_drawer = UiBuilder.panel(Vector2(272, 0))
	_context_drawer.name = "PropertiesDrawer"
	_context_drawer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(_context_drawer)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	_context_drawer.add_child(col)

	_context_title = UiBuilder.section_header("PROPERTIES")
	col.add_child(_context_title)
	_context_info = Label.new()
	_context_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	HudStyle.apply_body_font(_context_info, 12, HudStyle.C_LABEL)
	col.add_child(_context_info)

	_color_section = VBoxContainer.new()
	_color_section.add_theme_constant_override("separation", 6)
	_color_section.add_child(UiBuilder.section_header("COLOUR"))
	var color_row := HBoxContainer.new()
	color_row.add_theme_constant_override("separation", 6)
	_color_section.add_child(color_row)
	_color_picker = ColorPickerButton.new()
	_color_picker.custom_minimum_size = Vector2(52, 34)
	_color_picker.edit_alpha = false
	_color_picker.color = _paint_color
	_color_picker.color_changed.connect(_on_paint_color_changed)
	color_row.add_child(_color_picker)
	var default_btn := UiBuilder.compact_button("Default")
	default_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	default_btn.pressed.connect(_use_brick_catalog_color)
	color_row.add_child(default_btn)
	var presets := HFlowContainer.new()
	presets.add_theme_constant_override("h_separation", 4)
	presets.add_theme_constant_override("v_separation", 4)
	_color_section.add_child(presets)
	_color_preset_btns.clear()
	for preset in COLOR_PRESETS:
		var swatch := Button.new()
		swatch.custom_minimum_size = Vector2(26, 26)
		swatch.focus_mode = Control.FOCUS_NONE
		swatch.tooltip_text = str(preset.get("name", "Colour"))
		var sb := StyleBoxFlat.new()
		sb.set_border_width_all(1)
		sb.border_color = HudStyle.C_BRASS
		sb.set_corner_radius_all(2)
		if bool(preset.get("custom", true)) == false:
			sb.bg_color = Color(0.2, 0.2, 0.22)
			swatch.text = "·"
		else:
			sb.bg_color = preset["color"] as Color
		swatch.add_theme_stylebox_override("normal", sb)
		swatch.add_theme_stylebox_override("hover", sb)
		swatch.add_theme_stylebox_override("pressed", sb)
		var preset_copy: Dictionary = preset
		swatch.pressed.connect(func() -> void: _apply_color_preset(preset_copy))
		presets.add_child(swatch)
		_color_preset_btns.append(swatch)
	col.add_child(_color_section)

	_sign_section = VBoxContainer.new()
	_sign_section.add_theme_constant_override("separation", 6)
	_sign_section.add_child(UiBuilder.section_header("SIGN TEXT"))
	_sign_text_edit = LineEdit.new()
	_sign_text_edit.placeholder_text = "Building name / label…"
	_sign_text_edit.max_length = 32
	_sign_text_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sign_text_edit.text_changed.connect(func(_t: String) -> void: _refresh_ghost_from_mouse())
	_sign_section.add_child(_sign_text_edit)
	col.add_child(_sign_section)

	_clipboard_section = VBoxContainer.new()
	_clipboard_section.add_theme_constant_override("separation", 6)
	_clipboard_section.add_child(UiBuilder.section_header("SELECTION"))
	_copy_btn = UiBuilder.compact_button("Copy selection  Ctrl+C")
	_copy_btn.pressed.connect(_copy_marked_region)
	_clipboard_section.add_child(_copy_btn)
	_paste_btn = UiBuilder.compact_button("Paste at cursor  Ctrl+V")
	_paste_btn.pressed.connect(_paste_clipboard_at_cursor)
	_clipboard_section.add_child(_paste_btn)
	_paste_layer_btn = UiBuilder.compact_button("Paste on this layer")
	_paste_layer_btn.tooltip_text = "Same XZ as the copy, on the current layer — Layer+ between presses"
	_paste_layer_btn.pressed.connect(_paste_clipboard_on_layer)
	_clipboard_section.add_child(_paste_layer_btn)
	_paste_up_btn = UiBuilder.compact_button("Paste one storey ↑")
	_paste_up_btn.tooltip_text = "Stack another copy above the last paste (keeps going each press)"
	_paste_up_btn.pressed.connect(_paste_clipboard_one_up)
	_clipboard_section.add_child(_paste_up_btn)
	col.add_child(_clipboard_section)


func _build_building_dialog() -> void:
	_building_dialog = UiBuilder.panel(Vector2(410, 0))
	_building_dialog.name = "BuildingDialog"
	_building_dialog.visible = false
	_building_dialog.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_building_dialog.offset_left = -430.0
	_building_dialog.offset_right = -20.0
	_building_dialog.offset_top = -320.0
	_building_dialog.offset_bottom = 320.0
	_root.add_child(_building_dialog)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_building_dialog.add_child(scroll)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 9)
	scroll.add_child(col)

	var heading := HBoxContainer.new()
	col.add_child(heading)
	var title := UiBuilder.title_label("BUILDING", 20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	heading.add_child(title)
	var close := UiBuilder.compact_button("×", 34)
	close.pressed.connect(func() -> void: _building_dialog.visible = false)
	heading.add_child(close)

	var help := UiBuilder.subtitle_label(
		"LMB paint · RMB orbit · MMB pan · Scroll zoom · [ ] layer · R rotate · X erase\n"
		+ "M mark A→B · Ctrl+C copy · Ctrl+V paste",
		11,
	)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(help)

	col.add_child(UiBuilder.section_header("FILE"))
	_file_lbl = Label.new()
	_file_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	HudStyle.apply_body_font(_file_lbl, 12, HudStyle.C_TEXT)
	col.add_child(_file_lbl)

	col.add_child(UiBuilder.section_header("DISPLAY NAME"))
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Untitled Building"
	_name_edit.text_changed.connect(func(_t: String) -> void:
		_apply_metadata_from_fields()
		_refresh_summary()
		_refresh_rules()
	)
	col.add_child(_name_edit)

	col.add_child(UiBuilder.section_header("SERVICE ROLE"))
	_role_option = OptionButton.new()
	_populate_role_options()
	_role_option.item_selected.connect(_on_role_selected)
	col.add_child(_role_option)

	col.add_child(UiBuilder.section_header("APRON PAD"))
	_pad_template_option = OptionButton.new()
	_populate_pad_template_options()
	_pad_template_option.item_selected.connect(_on_pad_template_selected)
	col.add_child(_pad_template_option)
	var pad_hint := UiBuilder.subtitle_label("Locks volume to N×22 × M×22 m for port pads", 11)
	pad_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(pad_hint)

	col.add_child(UiBuilder.separator())
	_rules_lbl = Label.new()
	_rules_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	HudStyle.apply_body_font(_rules_lbl, 12, HudStyle.C_TEXT)
	col.add_child(_rules_lbl)

	col.add_child(UiBuilder.section_header("EXISTING"))
	_load_option = OptionButton.new()
	col.add_child(_load_option)
	var load_row := HBoxContainer.new()
	load_row.add_theme_constant_override("separation", 6)
	col.add_child(load_row)
	var load_selected := UiBuilder.compact_button("Load")
	load_selected.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	load_selected.pressed.connect(_load_selected_json)
	load_row.add_child(load_selected)
	var browse_btn := UiBuilder.compact_button("Browse…")
	browse_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	browse_btn.pressed.connect(_show_open_dialog)
	load_row.add_child(browse_btn)

	var save_row := HBoxContainer.new()
	save_row.add_theme_constant_override("separation", 6)
	col.add_child(save_row)
	var save_btn := UiBuilder.compact_button("Save")
	save_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_btn.pressed.connect(_save_json)
	save_row.add_child(save_btn)
	var save_as_btn := UiBuilder.compact_button("Save As…")
	save_as_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_as_btn.pressed.connect(_show_save_dialog)
	save_row.add_child(save_as_btn)

	var util_row := HBoxContainer.new()
	util_row.add_theme_constant_override("separation", 6)
	col.add_child(util_row)
	var new_btn := UiBuilder.compact_button("New blank")
	new_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	new_btn.pressed.connect(_new_blank)
	util_row.add_child(new_btn)
	var clear_btn := UiBuilder.compact_button("Clear pad")
	clear_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clear_btn.pressed.connect(_clear_layout)
	util_row.add_child(clear_btn)

	_export_lbl = Label.new()
	_export_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	HudStyle.apply_body_font(_export_lbl, 11, HudStyle.C_LABEL)
	col.add_child(_export_lbl)


func _toggle_building_dialog() -> void:
	if _building_dialog == null:
		return
	_building_dialog.visible = not _building_dialog.visible
	if _building_dialog.visible:
		_refresh_rules()
		_refresh_file_label()
		_refresh_load_options()


func _refresh_summary() -> void:
	if _summary_lbl == null:
		return
	var name_s := _layout.display_name.strip_edges()
	if name_s.is_empty():
		name_s = "Untitled Building"
	var role_s := _layout.role if not _layout.role.is_empty() else "decorative"
	var pad_s := _layout.pad_template_id if not _layout.pad_template_id.is_empty() else "freeform"
	_summary_lbl.text = "%s  ·  %s  ·  %s  ·  %d×%d×%d" % [
		name_s, role_s, pad_s, _grid.width, _grid.height, _grid.depth,
	]


func _resize() -> void:
	if _viewport == null or _vp_host == null:
		return
	var sz := _vp_host.size
	if sz.x > 4.0 and sz.y > 4.0:
		_viewport.size = Vector2i(int(sz.x), int(sz.y))


func _unhandled_input(event: InputEvent) -> void:
	if _root == null or not _root.visible:
		return
	if event.is_action_pressed("ui_cancel"):
		if _mark_anchor_set or _tool == Tool.MARK:
			_set_tool(Tool.PLACE)
			_set_hint("Mark cancelled.", HudStyle.C_LABEL)
			get_viewport().set_input_as_handled()
			return
	if event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		var focus_owner := get_viewport().gui_get_focus_owner()
		if focus_owner is LineEdit or focus_owner is TextEdit:
			return
		match key.keycode:
			KEY_M:
				_set_tool(Tool.MARK if _tool != Tool.MARK else Tool.PLACE)
				get_viewport().set_input_as_handled()
			KEY_C:
				if key.ctrl_pressed:
					_copy_marked_region()
					get_viewport().set_input_as_handled()
			KEY_V:
				if key.ctrl_pressed:
					if key.shift_pressed:
						_paste_clipboard_on_layer()
					else:
						_paste_clipboard_at_cursor()
					get_viewport().set_input_as_handled()
			KEY_R:
				_rotate_yaw()
				_refresh_rules()
				_refresh_ghost_from_mouse()
				get_viewport().set_input_as_handled()
			KEY_X:
				_set_tool(Tool.ERASE if _tool == Tool.PLACE else Tool.PLACE)
				get_viewport().set_input_as_handled()
			KEY_BRACKETLEFT:
				_set_layer_y(_layer_y - 1)
				get_viewport().set_input_as_handled()
			KEY_BRACKETRIGHT:
				_set_layer_y(_layer_y + 1)
				get_viewport().set_input_as_handled()


func _on_viewport_gui_input(event: InputEvent) -> void:
	if _root == null or not _root.visible:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_cam_dist = maxf(8.0, _cam_dist * 0.9)
			_update_camera()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_cam_dist = minf(80.0, _cam_dist * 1.1)
			_update_camera()
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			_orbiting = mb.pressed
			_panning = false
			_orbit_last = mb.position
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_panning = mb.pressed
			_orbiting = false
			_orbit_last = mb.position
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			_painting = mb.pressed
			if mb.pressed:
				## Ctrl+click pastes clipboard at the cursor when one exists.
				if (
					not _clipboard.is_empty()
					and _tool == Tool.PLACE
					and Input.is_key_pressed(KEY_CTRL)
				):
					_last_paint_cell = Vector3i(-999, -999, -999)
					var paste_cell := _pick_cell(mb.position)
					if paste_cell.y >= 0:
						_ghost_cell = paste_cell
						_paste_at(paste_cell)
					return
				_last_paint_cell = Vector3i(-999, -999, -999)
				_paint_at_screen(mb.position)
			else:
				_last_paint_cell = Vector3i(-999, -999, -999)
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _orbiting:
			var delta := mm.position - _orbit_last
			_orbit_last = mm.position
			_cam_yaw -= delta.x * 0.35
			_cam_pitch = clampf(_cam_pitch - delta.y * 0.25, -80.0, -8.0)
			_update_camera()
		elif _panning:
			var delta := mm.position - _orbit_last
			_orbit_last = mm.position
			var yaw_r := deg_to_rad(_cam_yaw)
			var right := Vector3(cos(yaw_r), 0.0, -sin(yaw_r))
			var forward := Vector3(-sin(yaw_r), 0.0, -cos(yaw_r))
			var scale := _cam_dist * 0.0025
			_cam_target += (-right * delta.x + forward * delta.y) * scale
			_update_camera()
		elif _painting and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			if _tool != Tool.MARK:
				_paint_at_screen(mm.position)
			else:
				_update_ghost_at_screen(mm.position)
		else:
			_update_ghost_at_screen(mm.position)


func _set_layer_y(y: int) -> void:
	var max_y := maxi(_grid.height - 1, 0) if _pad_volume_locked() and _grid != null else 9999
	_layer_y = clampi(y, 0, max_y)
	_refresh_grid_overlay()
	_apply_layer_visibility()
	_refresh_palette_selection()
	_refresh_rules()
	_refresh_ghost_from_mouse()
	if _tool == Tool.MARK and _mark_anchor_set:
		_update_mark_preview()
	elif not _clipboard.is_empty():
		_update_paste_preview()
	_refresh_hint()


## Apron pad templates lock the authoring volume — no grow-on-paint.
func _pad_volume_locked() -> bool:
	return not _layout.pad_template_id.strip_edges().is_empty()


func _apply_layer_visibility() -> void:
	var stale_keys: Array[String] = []
	for key in _brick_visuals.keys():
		var node_v: Variant = _brick_visuals[key]
		if not (node_v is Node3D) or not is_instance_valid(node_v):
			stale_keys.append(str(key))
			continue
		var node: Node3D = node_v as Node3D
		var cell_y := int(node.get_meta("cell_y", 0))
		node.visible = cell_y <= _layer_y
	for k in stale_keys:
		_brick_visuals.erase(k)


func _paint_at_screen(screen_pos: Vector2) -> void:
	var cell := _pick_cell(screen_pos)
	if cell.y < 0:
		return
	if cell == _last_paint_cell:
		return
	_last_paint_cell = cell
	if _tool == Tool.MARK:
		_handle_mark_click(cell)
		return
	if _tool == Tool.ERASE:
		## Peel mounted sign first so erase doesn't need to delete the wall.
		if _layout.clear_sign(cell):
			_sync_brick_visuals()
			_refresh_rules()
			return
		if not _layout.has_cell(cell):
			return
		_layout.erase_footprint_at(cell)
	else:
		if not _try_place(cell):
			return
	_sync_brick_visuals()
	_refresh_rules()


func _rotate_yaw() -> void:
	var step := BrickCatalog.yaw_step_of(_brick_id) if BrickCatalog.has(_brick_id) else 90
	_yaw = (_yaw + step) % 360


func _sign_text() -> String:
	if _sign_text_edit != null:
		var t := _sign_text_edit.text.strip_edges()
		if not t.is_empty():
			return t
	return str(BrickCatalog.get_entry(_brick_id).get("default_text", "NAME"))


func _try_place(cell: Vector3i) -> bool:
	if not BrickCatalog.has(_brick_id):
		return false
	if BrickCatalog.has_tag(_brick_id, "ship_only"):
		return false
	if BrickCatalog.has_tag(_brick_id, "text"):
		return _try_place_text(cell)
	if not _placement_legal(cell):
		return false
	var fp := BrickCatalog.footprint_of(_brick_id)
	var yaw_steps := int(round(float(_yaw) / 90.0)) % 4
	var placing_floor := BuildingLayout.is_surface_brick(_brick_id)
	if not placing_floor:
		## Wipe blocking content under the footprint, but leave floor underlays.
		for occupied in _grid.footprint_cells(cell, fp, yaw_steps):
			if _layout.has_blocking_content(occupied):
				_layout.erase_footprint_at(occupied)
	var before := _layout.grid_size
	var paint: Variant = null if _use_catalog_color else _paint_color
	if not _layout.place_footprint(cell, _brick_id, _yaw, null, paint):
		return false
	if _layout.grid_size != before:
		## Freeform only — locked pads reject OOB in _placement_legal first.
		_grid = _layout.grid()
		_layer_y = clampi(_layer_y, 0, maxi(_grid.height - 1, 0))
		_rebuild_preview()
	return true


func _try_place_text(cell: Vector3i) -> bool:
	## Mount onto an existing wall/block, or place free-standing on empty cells.
	if cell.y < 0 or _grid == null:
		return false
	if not _placement_legal(cell):
		return false
	var text := _sign_text()
	if _layout.has_cell(cell) and _layout.has_blocking_content(cell):
		var host := _layout.get_brick(_layout.primary_cell_of(cell))
		var host_id := str(host.get("brick_id", ""))
		if BrickCatalog.has_tag(host_id, "text"):
			_layout.erase_footprint_at(cell)
			return _layout.place_footprint(cell, _brick_id, _yaw, null, null, {"text": text})
		return _layout.attach_sign(cell, _brick_id, _yaw, text)
	var before := _layout.grid_size
	if not _layout.place_footprint(cell, _brick_id, _yaw, null, null, {"text": text}):
		return false
	if _layout.grid_size != before:
		_grid = _layout.grid()
		_layer_y = clampi(_layer_y, 0, maxi(_grid.height - 1, 0))
		_rebuild_preview()
	return true


func _placement_legal(cell: Vector3i) -> bool:
	if _grid == null or not BrickCatalog.has(_brick_id):
		return false
	if BrickCatalog.has_tag(_brick_id, "ship_only"):
		return false
	## Signs can mount on a host cell, or sit free-standing when the footprint is clear.
	if BrickCatalog.has_tag(_brick_id, "text"):
		if not _grid.in_bounds(cell):
			return false
		if _layout.has_cell(cell) and _layout.has_blocking_content(cell):
			var host := _layout.get_brick(_layout.primary_cell_of(cell))
			return not BrickCatalog.has_tag(str(host.get("brick_id", "")), "text") \
				or str(host.get("brick_id", "")) == _brick_id
		var fp := BrickCatalog.footprint_of(_brick_id)
		var yaw_steps := int(round(float(_yaw) / 90.0)) % 4
		var locked := _pad_volume_locked()
		for occupied in _grid.footprint_cells(cell, fp, yaw_steps):
			if not _grid.in_bounds(occupied):
				if locked:
					return false
				continue
			if _layout.has_blocking_content(occupied):
				return false
		return true
	var fp := BrickCatalog.footprint_of(_brick_id)
	var yaw_steps := int(round(float(_yaw) / 90.0)) % 4
	var placing_floor := BuildingLayout.is_surface_brick(_brick_id)
	var locked := _pad_volume_locked()
	for occupied in _grid.footprint_cells(cell, fp, yaw_steps):
		if not _grid.in_bounds(occupied):
			## Locked apron pads reject out-of-bounds instead of growing.
			if locked:
				return false
			continue
		var existing := _layout.get_brick(occupied)
		if existing.is_empty():
			continue
		if placing_floor:
			continue
		if existing.has("occupied_by") or BuildingLayout.entry_has_content(existing):
			return false
	return true


func _refresh_ghost_from_mouse() -> void:
	if _root == null or not _root.visible or _vp_host == null:
		return
	_update_ghost_at_screen(_vp_host.get_local_mouse_position())


func _update_ghost_at_screen(screen_pos: Vector2) -> void:
	if _root == null or not _root.visible or _world == null or _grid == null:
		return
	if _tool == Tool.MARK:
		var mark_cell := _pick_cell(screen_pos)
		if mark_cell.y < 0:
			return
		_ghost_cell = mark_cell
		_update_mark_preview()
		return
	if _tool == Tool.ERASE:
		_clear_ghost()
		_clear_paste_preview()
		return
	var cell := _pick_cell(screen_pos)
	if cell.y < 0:
		_clear_ghost()
		_clear_paste_preview()
		return
	var valid := _placement_legal(cell)
	var paint_color := _active_paint_color()
	var sign_text := _sign_text() if BrickCatalog.has_tag(_brick_id, "text") else ""
	## Do not assign _ghost_cell before these checks — that made the early-out
	## always succeed and skipped the cheap move path, forcing a full mesh rebuild
	## whenever validity flipped between cells.
	if (
		_ghost != null and is_instance_valid(_ghost)
		and _ghost_brick_id == _brick_id
		and _ghost_cell == cell
		and _ghost_yaw == _yaw
		and _ghost_valid == valid
		and _ghost_color.is_equal_approx(paint_color)
		and _ghost_sign_text == sign_text
	):
		if not _clipboard.is_empty():
			_update_paste_preview()
		return
	if (
		_ghost != null and is_instance_valid(_ghost)
		and _ghost_brick_id == _brick_id
		and _ghost_color.is_equal_approx(paint_color)
		and _ghost_sign_text == sign_text
	):
		_ghost_cell = cell
		_ghost_yaw = _yaw
		_ghost.position = _ghost_position_for(cell, _brick_id, _yaw)
		_ghost.rotation_degrees = Vector3(0.0, float(_yaw), 0.0)
		if _ghost_valid != valid:
			_ghost_valid = valid
			_tint_ghost(_ghost, valid)
		if not _clipboard.is_empty():
			_update_paste_preview()
		return
	_clear_ghost()
	_ghost_brick_id = _brick_id
	_ghost_cell = cell
	_ghost_yaw = _yaw
	_ghost_valid = valid
	_ghost_color = paint_color
	_ghost_sign_text = sign_text
	var ghost_opts: Dictionary = {"preview_mesh": true, "color": paint_color}
	if BrickCatalog.has_tag(_brick_id, "text"):
		ghost_opts["text"] = sign_text
	_ghost = BrickCatalog.create_visual(_brick_id, ghost_opts)
	_ghost.name = "PlaceGhost"
	_ghost.position = _ghost_position_for(cell, _brick_id, _yaw)
	_ghost.rotation_degrees = Vector3(0.0, float(_yaw), 0.0)
	_tint_ghost(_ghost, valid)
	_pad_root.add_child(_ghost)
	if not _clipboard.is_empty():
		_update_paste_preview()


func _ghost_position_for(cell: Vector3i, brick_id: String, yaw: int) -> Vector3:
	## Mounted signs preview on the host cell centre; free-standing use footprint centre.
	if (
		BrickCatalog.has_tag(brick_id, "text")
		and _layout.has_cell(cell)
		and _layout.has_blocking_content(cell)
	):
		return _grid.cell_center_local(cell)
	return BuildingFitout.footprint_center_local(_grid, cell, brick_id, yaw)


func _tint_ghost(root: Node3D, valid: bool) -> void:
	var tint := Color(0.35, 0.95, 0.55, 0.42) if valid else Color(0.95, 0.28, 0.25, 0.42)
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for child in n.get_children():
			stack.append(child)
		var mi := n as MeshInstance3D
		if mi == null:
			continue
		var mat := mi.material_override as StandardMaterial3D
		if mat == null:
			mat = StandardMaterial3D.new()
		else:
			mat = mat.duplicate() as StandardMaterial3D
		## Keep the untinted albedo so green↔red flips don't compound or rebuild mesh.
		var base: Color
		if mi.has_meta("ghost_base_albedo"):
			base = mi.get_meta("ghost_base_albedo") as Color
		else:
			base = mat.albedo_color
			mi.set_meta("ghost_base_albedo", base)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(
			tint.r * 0.55 + base.r * 0.45,
			tint.g * 0.55 + base.g * 0.45,
			tint.b * 0.55 + base.b * 0.45,
			tint.a,
		)
		mat.roughness = 0.85
		mat.metallic = 0.0
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.no_depth_test = true
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _clear_ghost() -> void:
	if _ghost != null and is_instance_valid(_ghost):
		_ghost.queue_free()
	_ghost = null
	_ghost_brick_id = ""
	_ghost_cell = Vector3i(-999, -999, -999)
	_ghost_yaw = -1
	_ghost_valid = false
	_ghost_color = Color(0, 0, 0, 0)
	_ghost_sign_text = ""


func _pick_cell(screen_pos: Vector2) -> Vector3i:
	if _camera == null or _grid == null:
		return Vector3i(0, -1, 0)
	var from := _camera.project_ray_origin(screen_pos)
	var dir := _camera.project_ray_normal(screen_pos)
	var plane_y := float(_layer_y) * BuildingGrid.CELL_M + 0.05
	if absf(dir.y) < 0.0001:
		return Vector3i(0, -1, 0)
	var t := (plane_y - from.y) / dir.y
	if t < 0.0:
		return Vector3i(0, -1, 0)
	var hit := from + dir * t
	var cell := _grid.local_to_cell(hit)
	cell.y = _layer_y
	## Locked pads stay fixed — ignore aim outside the volume.
	if _pad_volume_locked() and not _grid.in_bounds(cell):
		return Vector3i(0, -1, 0)
	return cell


func _make_item_row(brick_id: String) -> PanelContainer:
	var row := PanelContainer.new()
	row.custom_minimum_size = Vector2(124, 98)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	var fp := BrickCatalog.footprint_of(brick_id)
	var sz := BrickCatalog.size_m(brick_id)
	row.tooltip_text = "%s\n%d×%d×%d cells · %.1f×%.1f×%.1f m" % [
		BrickCatalog.display_name(brick_id), fp.x, fp.y, fp.z, sz.x, sz.y, sz.z,
	]
	row.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton:
			var mb := ev as InputEventMouseButton
			if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
				_select_brick(brick_id)
	)
	var sb := StyleBoxFlat.new()
	sb.bg_color = HudStyle.C_BG_INNER
	sb.border_color = HudStyle.C_BRASS
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.set_content_margin_all(5)
	row.add_theme_stylebox_override("panel", sb)
	row.set_meta("style", sb)
	row.mouse_entered.connect(func() -> void:
		if not (_tool == Tool.PLACE and _brick_id == brick_id):
			sb.border_color = HudStyle.C_COPPER
	)
	row.mouse_exited.connect(func() -> void: _refresh_palette_selection())

	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 3)
	row.add_child(col)

	var thumb_plate := PanelContainer.new()
	thumb_plate.custom_minimum_size = Vector2(THUMB_PX, THUMB_PX)
	thumb_plate.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	thumb_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var plate_sb := StyleBoxFlat.new()
	plate_sb.bg_color = Color(0.08, 0.10, 0.11, 0.9)
	plate_sb.set_corner_radius_all(3)
	thumb_plate.add_theme_stylebox_override("panel", plate_sb)
	col.add_child(thumb_plate)

	var thumb := TextureRect.new()
	thumb.name = "Thumb"
	thumb.custom_minimum_size = Vector2(THUMB_PX, THUMB_PX)
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	thumb_plate.add_child(thumb)
	if _thumb_cache.has(brick_id):
		thumb.texture = _thumb_cache[brick_id] as Texture2D

	var name_lbl := Label.new()
	name_lbl.text = BrickCatalog.display_name(brick_id)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_lbl.custom_minimum_size.x = 112
	name_lbl.add_theme_font_size_override("font_size", 11)
	name_lbl.add_theme_color_override("font_color", HudStyle.C_TEXT)
	col.add_child(name_lbl)
	return row


func _bake_brick_thumbnail(brick_id: String, target: TextureRect) -> void:
	var svp := SubViewport.new()
	svp.size = Vector2i(THUMB_PX * 2, THUMB_PX * 2)
	svp.transparent_bg = false
	svp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	svp.own_world_3d = true
	svp.disable_3d = false
	add_child(svp)

	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.14, 0.15, 0.18)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.70, 0.71, 0.74)
	env.ambient_light_energy = 1.0
	env_node.environment = env
	svp.add_child(env_node)

	var visual := BrickCatalog.create_visual(brick_id, {"preview_mesh": true})
	svp.add_child(visual)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-42.0, 38.0, 0.0)
	light.light_energy = 1.35
	svp.add_child(light)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-12.0, -125.0, 0.0)
	fill.light_energy = 0.6
	svp.add_child(fill)

	var cam := Camera3D.new()
	cam.fov = 32.0
	cam.current = true
	var sz := BrickCatalog.size_m(brick_id)
	var reach := maxf(sz.x, maxf(sz.y, sz.z)) * 1.55 + 0.55
	svp.add_child(cam)
	cam.position = Vector3(reach * 0.78, reach * 0.58, reach * 0.92)
	cam.look_at(Vector3.ZERO, Vector3.UP)

	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	if not is_instance_valid(svp):
		return
	var img := svp.get_texture().get_image()
	svp.queue_free()
	if img == null:
		return
	img.resize(THUMB_PX, THUMB_PX, Image.INTERPOLATE_LANCZOS)
	var tex := ImageTexture.create_from_image(img)
	_thumb_cache[brick_id] = tex
	if is_instance_valid(target):
		target.texture = tex


func _select_brick(id: String) -> void:
	_brick_id = id
	## Keep clipboard; only leave mark mode so painting works again.
	if _tool == Tool.MARK:
		_set_tool(Tool.PLACE)
	else:
		_tool = Tool.PLACE
		_refresh_palette_selection()
	_yaw = BuildingLayout.norm_yaw(_yaw, BrickCatalog.yaw_step_of(id))
	if _use_catalog_color:
		_sync_color_picker_from_catalog()
	_clear_ghost()
	_refresh_ghost_from_mouse()
	_refresh_hint()
	_refresh_context_drawer()


func _active_paint_color() -> Color:
	if _use_catalog_color:
		return BrickCatalog.get_entry(_brick_id).get("color", Color(0.7, 0.7, 0.7)) as Color
	return _paint_color


func _on_paint_color_changed(color: Color) -> void:
	_paint_color = color
	_use_catalog_color = false
	_clear_ghost()
	_refresh_ghost_from_mouse()


func _use_brick_catalog_color() -> void:
	_use_catalog_color = true
	_sync_color_picker_from_catalog()
	_clear_ghost()
	_refresh_ghost_from_mouse()


func _apply_color_preset(preset: Dictionary) -> void:
	if not bool(preset.get("custom", true)):
		_use_brick_catalog_color()
		return
	_paint_color = preset["color"] as Color
	_use_catalog_color = false
	if _color_picker != null:
		_color_picker.set_block_signals(true)
		_color_picker.color = _paint_color
		_color_picker.set_block_signals(false)
	_clear_ghost()
	_refresh_ghost_from_mouse()


func _sync_color_picker_from_catalog() -> void:
	_paint_color = BrickCatalog.get_entry(_brick_id).get("color", Color(0.7, 0.7, 0.7)) as Color
	if _color_picker != null:
		_color_picker.set_block_signals(true)
		_color_picker.color = _paint_color
		_color_picker.set_block_signals(false)


func _refresh_palette_selection() -> void:
	for id in _brick_rows.keys():
		var row: PanelContainer = _brick_rows[id]
		var selected := _tool == Tool.PLACE and str(id) == _brick_id
		var sb: StyleBoxFlat = row.get_meta("style") as StyleBoxFlat
		if sb != null:
			sb.border_color = HudStyle.C_AMBER if selected else HudStyle.C_BRASS
			sb.set_border_width_all(2 if selected else 1)
			sb.bg_color = Color(0.16, 0.14, 0.10) if selected else HudStyle.C_BG_INNER
	if _layer_lbl != null:
		_layer_lbl.text = "Layer %d" % _layer_y
	_refresh_tool_buttons()
	_refresh_hint()
	_refresh_context_drawer()
	_refresh_summary()


func _refresh_tool_buttons() -> void:
	_style_tool_button(_place_btn, _tool == Tool.PLACE)
	_style_tool_button(_erase_btn, _tool == Tool.ERASE)
	_style_tool_button(_mark_btn, _tool == Tool.MARK)
	if _copy_btn != null:
		_copy_btn.disabled = not _mark_complete
	var has_clip := not _clipboard.is_empty()
	if _paste_btn != null:
		_paste_btn.disabled = not has_clip
	if _paste_layer_btn != null:
		_paste_layer_btn.disabled = not has_clip
	if _paste_up_btn != null:
		_paste_up_btn.disabled = not has_clip


func _style_tool_button(btn: Button, active: bool) -> void:
	if btn == null:
		return
	btn.modulate = Color(1.15, 1.05, 0.75) if active else Color(1, 1, 1)


func _set_hint(text: String, color: Color = HudStyle.C_AMBER) -> void:
	if _hint_lbl == null:
		return
	_hint_lbl.text = text
	_hint_lbl.add_theme_color_override("font_color", color)


func _refresh_hint() -> void:
	if _hint_lbl == null:
		return
	if _tool == Tool.MARK:
		if not _mark_anchor_set:
			_set_hint("MARK: click the first corner of the region.")
		elif not _mark_complete:
			_set_hint("MARK: click the opposite corner (change layer first if you want height).")
		else:
			var sz := _mark_max - _mark_min + Vector3i.ONE
			_set_hint("Marked %d×%d×%d — press Copy (Ctrl+C)." % [sz.x, sz.y, sz.z])
		return
	if not _clipboard.is_empty():
		var n := int(_clipboard.get("cell_count", 0))
		_set_hint(
			"Clipboard: %d bricks. Layer+ then “Paste this layer”, or hover + Ctrl+V." % n,
			HudStyle.C_GREEN,
		)
		return
	if _tool == Tool.ERASE:
		_set_hint("ERASE: click or drag to remove bricks.", HudStyle.C_LABEL)
		return
	_set_hint("PLACE: paint bricks. Mark a region when you want to copy a floor.", HudStyle.C_LABEL)


func _set_tool(tool: int) -> void:
	_tool = tool
	_clear_mark()
	_clear_mark_preview()
	if tool == Tool.MARK:
		_clear_ghost()
		_clear_paste_preview()
	_refresh_palette_selection()
	_refresh_ghost_from_mouse()
	_refresh_hint()
	_refresh_context_drawer()


func _toggle_mark_tool() -> void:
	if _tool == Tool.MARK:
		_set_tool(Tool.PLACE)
		_set_hint("Mark cleared.", HudStyle.C_LABEL)
	else:
		_set_tool(Tool.MARK)


func _refresh_context_drawer() -> void:
	if _context_drawer == null:
		return
	var erase := _tool == Tool.ERASE
	_context_drawer.visible = not erase
	if erase:
		return
	var is_mark := _tool == Tool.MARK
	if is_mark:
		_context_title.text = "SELECTION"
		if not _mark_anchor_set:
			_context_info.text = "Click the first corner of the region."
		elif not _mark_complete:
			_context_info.text = "Click the opposite corner. Change layer first to include height."
		else:
			var size := _mark_max - _mark_min + Vector3i.ONE
			_context_info.text = "Selected %d × %d × %d cells." % [size.x, size.y, size.z]
	else:
		_context_title.text = BrickCatalog.display_name(_brick_id).to_upper()
		var fp := BrickCatalog.footprint_of(_brick_id)
		var size := BrickCatalog.size_m(_brick_id)
		_context_info.text = "%d × %d × %d cells  ·  %.1f × %.1f × %.1f m\nPad %d×%d×%d" % [
			fp.x, fp.y, fp.z, size.x, size.y, size.z,
			_grid.width, _grid.height, _grid.depth,
		]
	if _color_section != null:
		_color_section.visible = not is_mark and not BrickCatalog.has_tag(_brick_id, "text")
	if _sign_section != null:
		_sign_section.visible = not is_mark and BrickCatalog.has_tag(_brick_id, "text")
	if _clipboard_section != null:
		_clipboard_section.visible = is_mark or not _clipboard.is_empty()


func _clear_mark() -> void:
	_mark_anchor_set = false
	_mark_complete = false
	_mark_anchor = Vector3i(-999, -999, -999)
	_mark_min = Vector3i.ZERO
	_mark_max = Vector3i.ZERO


func _clear_mark_preview() -> void:
	if _mark_preview != null and is_instance_valid(_mark_preview):
		_mark_preview.queue_free()
	_mark_preview = null


func _clear_paste_preview() -> void:
	if _paste_preview != null and is_instance_valid(_paste_preview):
		_paste_preview.queue_free()
	_paste_preview = null


func _handle_mark_click(cell: Vector3i) -> void:
	if _mark_complete or not _mark_anchor_set:
		_mark_anchor = cell
		_mark_anchor_set = true
		_mark_complete = false
		_ghost_cell = cell
		_set_hint("Corner A set at %d,%d,%d — click corner B." % [cell.x, cell.y, cell.z])
	else:
		var bounds := BrickRegionClipboard.bounds_from_corners(_mark_anchor, cell)
		_mark_min = bounds["min"]
		_mark_max = bounds["max"]
		_mark_complete = true
		var sz := _mark_max - _mark_min + Vector3i.ONE
		_set_hint("Marked %d×%d×%d — press Copy (Ctrl+C)." % [sz.x, sz.y, sz.z], HudStyle.C_GREEN)
	_refresh_palette_selection()
	_update_mark_preview()


func _update_mark_preview() -> void:
	if _tool != Tool.MARK or not _mark_anchor_set or _grid == null:
		_clear_mark_preview()
		return
	var cursor := _ghost_cell
	if cursor.y < 0 and _vp_host != null:
		cursor = _pick_cell(_vp_host.get_local_mouse_position())
	if cursor.y < 0:
		cursor = _mark_anchor
	var min_c := _mark_min
	var max_c := _mark_max
	if not _mark_complete:
		var bounds := BrickRegionClipboard.bounds_from_corners(_mark_anchor, cursor)
		min_c = bounds["min"]
		max_c = bounds["max"]
	var key := "%d,%d,%d:%d,%d,%d" % [min_c.x, min_c.y, min_c.z, max_c.x, max_c.y, max_c.z]
	if (
		_mark_preview != null and is_instance_valid(_mark_preview)
		and str(_mark_preview.get_meta("mark_key", "")) == key
	):
		return
	_clear_mark_preview()
	_mark_preview = _make_volume_box(min_c, max_c, Color(0.35, 0.72, 1.0, 0.28))
	_mark_preview.name = "MarkPreview"
	_mark_preview.set_meta("mark_key", key)
	_attach_preview(_mark_preview)


func _update_paste_preview() -> void:
	if _clipboard.is_empty() or _tool == Tool.MARK or _grid == null:
		_clear_paste_preview()
		return
	var dest := _ghost_cell
	if dest.y < 0 and _vp_host != null:
		dest = _pick_cell(_vp_host.get_local_mouse_position())
	if dest.y < 0:
		_clear_paste_preview()
		return
	var sz := BrickRegionClipboard.size_cells(_clipboard)
	if sz.x <= 0:
		_clear_paste_preview()
		return
	var max_c := dest + sz - Vector3i.ONE
	var ok := _can_paste_at(dest)
	var col := Color(0.35, 0.95, 0.55, 0.28) if ok else Color(0.95, 0.28, 0.25, 0.32)
	var key := "paste:%d,%d,%d:%s" % [dest.x, dest.y, dest.z, str(ok)]
	if (
		_paste_preview != null and is_instance_valid(_paste_preview)
		and str(_paste_preview.get_meta("paste_key", "")) == key
	):
		return
	_clear_paste_preview()
	_paste_preview = _make_volume_box(dest, max_c, col)
	_paste_preview.name = "PastePreview"
	_paste_preview.set_meta("paste_key", key)
	_attach_preview(_paste_preview)


func _attach_preview(node: Node3D) -> void:
	if _pad_root != null and is_instance_valid(_pad_root):
		_pad_root.add_child(node)
	elif _world != null and is_instance_valid(_world):
		_world.add_child(node)


func _make_volume_box(min_c: Vector3i, max_c: Vector3i, col: Color) -> Node3D:
	var w := float(max_c.x - min_c.x + 1) * BuildingGrid.CELL_M
	var h := float(max_c.y - min_c.y + 1) * BuildingGrid.CELL_M
	var l := float(max_c.z - min_c.z + 1) * BuildingGrid.CELL_M
	var min_center := _grid.cell_center_local(min_c)
	var max_center := _grid.cell_center_local(max_c)
	var root := Node3D.new()
	root.position = (min_center + max_center) * 0.5
	var box := MeshBuilder.box(
		Vector3(maxf(w, 0.05) * 0.98, maxf(h, 0.05) * 0.98, maxf(l, 0.05) * 0.98),
		col,
		0.9,
		0.0,
	)
	var mat := box.material_override as StandardMaterial3D
	if mat != null:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.no_depth_test = true
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	root.add_child(box)
	return root


func _copy_marked_region() -> void:
	if not _mark_complete:
		_set_hint("Nothing marked yet — press Mark, then click two corners.", HudStyle.C_RED)
		return
	_clipboard = BrickRegionClipboard.extract_region(_layout.cells, _mark_min, _mark_max)
	_clipboard_src_min = _mark_min
	_last_paste_anchor = Vector3i(-999, -999, -999)
	var n := int(_clipboard.get("cell_count", 0))
	if n <= 0:
		_clipboard.clear()
		_set_hint("Marked region is empty — nothing to copy.", HudStyle.C_RED)
		_refresh_palette_selection()
		return
	## Leave mark mode so the next action is paste, not another mark click.
	_set_tool(Tool.PLACE)
	_set_hint(
		"Copied %d bricks. Layer+ → Paste on this layer, or Paste ↑ to stack floors." % n,
		HudStyle.C_GREEN,
	)
	_refresh_palette_selection()
	_update_paste_preview()


func _building_paste_blocks(dest: Vector3i) -> bool:
	var key := BuildingLayout.cell_key(dest)
	if not _layout.cells.has(key):
		return false
	var existing: Dictionary = _layout.cells[key]
	return not BuildingLayout.entry_is_surface_only(existing)


func _can_paste_at(dest: Vector3i) -> bool:
	if _clipboard.is_empty() or _grid == null:
		return false
	for cell in BrickRegionClipboard.iter_dest_cells(_clipboard, dest):
		if _grid.in_bounds(cell) and _building_paste_blocks(cell):
			return false
	return true


func _paste_at(dest: Vector3i) -> bool:
	if _clipboard.is_empty():
		_set_hint("Clipboard empty — Mark a region and Copy first.", HudStyle.C_RED)
		return false
	if not _can_paste_at(dest):
		_set_hint("Can't paste there — clear blocking bricks first.", HudStyle.C_RED)
		_update_paste_preview()
		return false
	var needed := BrickRegionClipboard.iter_dest_cells(_clipboard, dest)
	if needed.is_empty():
		_set_hint("Clipboard empty.", HudStyle.C_RED)
		return false
	var before_size := _layout.grid_size
	if _pad_volume_locked():
		for cell in needed:
			if not _grid.in_bounds(cell):
				_set_hint("Paste stays inside the locked pad.", HudStyle.C_RED)
				return false
	else:
		var shift := _layout.ensure_fit_cells(needed)
		dest += shift
		_clipboard_src_min += shift
	## Re-check after any remap from pad growth.
	if not _can_paste_at(dest):
		_set_hint("Can't paste there — clear blocking bricks first.", HudStyle.C_RED)
		return false
	_layout.cells = BrickRegionClipboard.paste_region(_clipboard, dest, _layout.cells)
	_last_paste_anchor = dest
	if before_size != _layout.grid_size:
		_grid = _layout.grid()
		_rebuild_preview()
	else:
		_sync_brick_visuals()
	_refresh_rules()
	_set_hint(
		"Pasted %d bricks at %d,%d,%d." % [
			int(_clipboard.get("cell_count", 0)), dest.x, dest.y, dest.z,
		],
		HudStyle.C_GREEN,
	)
	_update_paste_preview()
	return true


func _paste_clipboard_at_cursor() -> void:
	var dest := _ghost_cell
	if dest.y < 0 and _vp_host != null:
		dest = _pick_cell(_vp_host.get_local_mouse_position())
	if dest.y < 0:
		_set_hint("Aim at the pad, then Paste (Ctrl+V).", HudStyle.C_RED)
		return
	_paste_at(dest)


func _paste_clipboard_on_layer() -> void:
	if _clipboard.is_empty():
		_set_hint("Clipboard empty — Mark + Copy first.", HudStyle.C_RED)
		return
	## Stamp at the current layer (same XZ as the copy). Change layer between presses.
	var dest := Vector3i(_clipboard_src_min.x, _layer_y, _clipboard_src_min.z)
	_paste_at(dest)


func _paste_clipboard_one_up() -> void:
	if _clipboard.is_empty():
		_set_hint("Clipboard empty — Mark + Copy first.", HudStyle.C_RED)
		return
	var sz := BrickRegionClipboard.size_cells(_clipboard)
	var step := maxi(sz.y, 1)
	## Stack above the last paste (or the original copy on first press).
	var base_y := _clipboard_src_min.y
	if _last_paste_anchor.y >= 0:
		base_y = _last_paste_anchor.y
	var dest := Vector3i(_clipboard_src_min.x, base_y + step, _clipboard_src_min.z)
	_set_layer_y(dest.y)
	_paste_at(dest)


func _clear_layout() -> void:
	_layout.clear()
	_clear_mark()
	_clear_mark_preview()
	_clear_paste_preview()
	_sync_brick_visuals()
	_refresh_rules()
	_refresh_hint()


func _rebuild_preview() -> void:
	_clear_ghost()
	_clear_mark_preview()
	_clear_paste_preview()
	_ensure_pad()
	_sync_brick_visuals()
	_refresh_grid_overlay()
	_update_camera()
	_refresh_ghost_from_mouse()
	if _tool == Tool.MARK:
		_update_mark_preview()
	elif not _clipboard.is_empty():
		_update_paste_preview()


func _ensure_pad() -> void:
	if _pad_root != null and is_instance_valid(_pad_root):
		_clear_mark_preview()
		_clear_paste_preview()
		_pad_root.queue_free()
	_pad_root = Node3D.new()
	_pad_root.name = "BuildingPad"
	_world.add_child(_pad_root)

	var pad := MeshBuilder.box(
		Vector3(float(_grid.width), 0.08, float(_grid.depth)),
		Color(0.20, 0.22, 0.23),
		0.96,
		0.0,
	)
	pad.name = "GroundPad"
	pad.position.y = -0.04
	_pad_root.add_child(pad)

	_brick_root = Node3D.new()
	_brick_root.name = "EditorBricks"
	_pad_root.add_child(_brick_root)
	_brick_visuals.clear()


func _sync_brick_visuals() -> void:
	if _brick_root == null:
		return
	var keep: Dictionary = {}
	## Surfaces on every cell (including fillers under multi-cell bricks).
	for item in _layout.iter_cells():
		var cell := item["cell"] as Vector3i
		if item.has("surface"):
			var surface: Dictionary = item["surface"]
			_sync_one_visual(
				keep,
				cell,
				str(surface.get("brick_id", "floor")),
				int(surface.get("yaw", 0)),
				surface,
				"%s#surface" % BuildingLayout.cell_key(cell),
				true,
			)
		elif BuildingLayout.entry_is_surface_only(item):
			_sync_one_visual(
				keep,
				cell,
				str(item.get("brick_id", "floor")),
				int(item.get("yaw", 0)),
				item,
				"%s#floor" % BuildingLayout.cell_key(cell),
				true,
			)
	## Content primaries (+ mounted wall plaques).
	for item in _layout.iter_primary_cells():
		if BuildingLayout.entry_is_surface_only(item):
			continue
		var cell := item["cell"] as Vector3i
		_sync_one_visual(
			keep,
			cell,
			str(item.get("brick_id", "")),
			int(item.get("yaw", 0)),
			item,
			BuildingLayout.cell_key(cell),
			false,
		)
		var sign_id := str(item.get("sign_id", ""))
		if BrickCatalog.has(sign_id) and BrickCatalog.has_tag(sign_id, "text"):
			var sign_entry := {
				"brick_id": sign_id,
				"yaw": int(item.get("sign_yaw", item.get("yaw", 0))),
				"text": str(item.get("text", "")),
			}
			_sync_one_visual(
				keep,
				cell,
				sign_id,
				int(sign_entry["yaw"]),
				sign_entry,
				"%s#sign" % BuildingLayout.cell_key(cell),
				false,
			)
	var remove_keys: Array = []
	for key in _brick_visuals.keys():
		if not keep.has(key):
			remove_keys.append(key)
	for key in remove_keys:
		var node_v: Variant = _brick_visuals.get(key, null)
		_brick_visuals.erase(key)
		if node_v is Node3D and is_instance_valid(node_v):
			(node_v as Node).queue_free()
	_apply_layer_visibility()


func _sync_one_visual(
		keep: Dictionary,
		cell: Vector3i,
		brick_id: String,
		yaw: int,
		entry: Dictionary,
		key: String,
		surface_tile: bool,
) -> void:
	if not BrickCatalog.has(brick_id):
		return
	keep[key] = true
	var color := BuildingLayout.color_from_entry(entry, brick_id)
	var color_key := "%.3f,%.3f,%.3f" % [color.r, color.g, color.b]
	var sign_text := str(entry.get("text", "")) if BrickCatalog.has_tag(brick_id, "text") else ""
	var mounted_sign := str(key).ends_with("#sign")
	var pos := _grid.cell_center_local(cell) if surface_tile or mounted_sign \
		else BuildingFitout.footprint_center_local(_grid, cell, brick_id, yaw)
	var existing: Node3D = _brick_visuals.get(key) as Node3D
	if (
		existing != null and is_instance_valid(existing)
		and str(existing.get_meta("brick_id", "")) == brick_id
		and int(existing.get_meta("yaw", 0)) == yaw
		and str(existing.get_meta("color_key", "")) == color_key
		and str(existing.get_meta("sign_text", "")) == sign_text
	):
		existing.position = pos
		existing.rotation_degrees = Vector3(0.0, float(yaw), 0.0)
		existing.set_meta("cell_y", cell.y)
		return
	if existing != null and is_instance_valid(existing):
		existing.queue_free()
	var opts: Dictionary = {"color": color}
	if BrickCatalog.has_tag(brick_id, "text"):
		opts["text"] = sign_text
	var visual := BrickCatalog.create_visual(brick_id, opts)
	visual.name = "%s_%s" % [brick_id, key]
	visual.position = pos
	visual.rotation_degrees = Vector3(0.0, float(yaw), 0.0)
	visual.set_meta("brick_id", brick_id)
	visual.set_meta("yaw", yaw)
	visual.set_meta("color_key", color_key)
	visual.set_meta("sign_text", sign_text)
	visual.set_meta("cell_y", cell.y)
	_brick_root.add_child(visual)
	_brick_visuals[key] = visual


func _refresh_grid_overlay() -> void:
	if _pad_root == null:
		return
	if _grid_overlay != null and is_instance_valid(_grid_overlay):
		_grid_overlay.queue_free()
	_grid_overlay = Node3D.new()
	_grid_overlay.name = "GridOverlay"
	_pad_root.add_child(_grid_overlay)
	var y := float(_layer_y) * BuildingGrid.CELL_M + 0.02
	var line_color := Color(0.46, 0.49, 0.50, 0.65)
	for x in range(_grid.width + 1):
		var x_line := MeshBuilder.box(
			Vector3(0.018, 0.012, float(_grid.depth)),
			line_color,
			0.9,
			0.0,
		)
		x_line.position = Vector3(float(x) - float(_grid.width) * 0.5, y, 0.0)
		_grid_overlay.add_child(x_line)
	for z in range(_grid.depth + 1):
		var z_line := MeshBuilder.box(
			Vector3(float(_grid.width), 0.012, 0.018),
			line_color,
			0.9,
			0.0,
		)
		z_line.position = Vector3(0.0, y, float(z) - float(_grid.depth) * 0.5)
		_grid_overlay.add_child(z_line)
	_add_scale_figure()


func _add_scale_figure() -> void:
	## Same 1.8 m NpcBase dummy the shipyard uses, so brick height is readable.
	if _grid == null or _grid_overlay == null:
		return
	var h := WorldUnits.PLAYER_HEIGHT_M
	var root := Node3D.new()
	root.name = "ScaleFigure"
	root.position = Vector3(float(_grid.width) * 0.5 + 1.2, 0.0, 0.0)
	_grid_overlay.add_child(root)

	var npc := NpcBase.new()
	npc.name = "PlayerDummy"
	npc.rotation.y = -PI * 0.5
	root.add_child(npc)

	var pole := MeshBuilder.box(Vector3(0.05, h, 0.05), Color(0.95, 0.82, 0.15), 0.5, 0.0)
	pole.position = Vector3(0.55, h * 0.5, 0.0)
	root.add_child(pole)
	var tick_y := 0.5
	while tick_y <= h + 0.001:
		var tick := MeshBuilder.box(Vector3(0.22, 0.03, 0.03), Color(0.95, 0.82, 0.15), 0.5, 0.0)
		tick.position = Vector3(0.55, tick_y, 0.0)
		root.add_child(tick)
		tick_y += 0.5

	var tag := Label3D.new()
	tag.text = "%.1f m  (player)" % h
	tag.font_size = 48
	tag.pixel_size = 0.004
	tag.position = Vector3(0.55, h + 0.35, 0.0)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.modulate = Color(0.95, 0.88, 0.35, 0.95)
	tag.outline_size = 6
	root.add_child(tag)


func _update_camera() -> void:
	if _camera == null:
		return
	var pitch := deg_to_rad(_cam_pitch)
	var yaw := deg_to_rad(_cam_yaw)
	var offset := Vector3(
		cos(pitch) * sin(yaw),
		-sin(pitch),
		cos(pitch) * cos(yaw),
	) * _cam_dist
	_camera.position = _cam_target + offset
	_camera.look_at(_cam_target, Vector3.UP)


func _refresh_rules() -> void:
	_apply_metadata_from_fields()
	var report := BuildingRules.validate(_layout)
	var lines: PackedStringArray = []
	lines.append("%d bricks" % _layout.count())
	if bool(report.get("ok", false)):
		lines.append("OK to save")
	else:
		for err in report.get("errors", PackedStringArray()):
			lines.append("Error: %s" % str(err))
	for warning in report.get("warnings", PackedStringArray()):
		lines.append("Warn: %s" % str(warning))
	if _rules_lbl != null:
		_rules_lbl.text = "\n".join(lines)
	_refresh_summary()


func _apply_metadata_from_fields() -> void:
	if _name_edit != null:
		_layout.display_name = _name_edit.text.strip_edges()
	if _role_option != null and _role_option.selected >= 0:
		_layout.role = str(_role_option.get_item_metadata(_role_option.selected))
	if _pad_template_option != null and _pad_template_option.selected >= 0:
		_layout.pad_template_id = str(_pad_template_option.get_item_metadata(_pad_template_option.selected))


func _populate_role_options() -> void:
	if _role_option == null:
		return
	_role_option.clear()
	_role_option.add_item("decorative", 0)
	_role_option.set_item_metadata(0, "decorative")
	var index := 1
	for role_id in PortApronPadCatalog.role_ids():
		_role_option.add_item(PortApronPadCatalog.role_label(role_id), index)
		_role_option.set_item_metadata(index, role_id)
		index += 1


func _populate_pad_template_options() -> void:
	if _pad_template_option == null:
		return
	_pad_template_option.clear()
	_pad_template_option.add_item("(freeform — no pad)", 0)
	_pad_template_option.set_item_metadata(0, "")
	var index := 1
	for template_id in PortApronPadCatalog.template_ids():
		var entry: Dictionary = PortApronPadCatalog.template(template_id)
		var label := str(entry.get("label", template_id))
		_pad_template_option.add_item("%s — %s" % [template_id, label], index)
		_pad_template_option.set_item_metadata(index, template_id)
		index += 1


func _select_pad_template(template_id: String) -> void:
	if _pad_template_option == null:
		return
	var wanted := template_id.strip_edges()
	for i in range(_pad_template_option.item_count):
		if str(_pad_template_option.get_item_metadata(i)) == wanted:
			_pad_template_option.select(i)
			return
	_pad_template_option.select(0)


func _on_role_selected(_index: int) -> void:
	_apply_metadata_from_fields()
	## When picking a pad role, default the template size if still freeform.
	var role_id := _layout.role
	if role_id == "decorative" or role_id.is_empty():
		_refresh_rules()
		return
	if _layout.pad_template_id.is_empty():
		var default_pad := PortApronPadCatalog.default_template_for_role(role_id)
		_select_pad_template(default_pad)
		_apply_pad_template_volume(default_pad)
	_refresh_rules()


func _on_pad_template_selected(_index: int) -> void:
	_apply_metadata_from_fields()
	_apply_pad_template_volume(_layout.pad_template_id)
	_refresh_rules()


func _apply_pad_template_volume(template_id: String) -> void:
	var trimmed := template_id.strip_edges()
	if trimmed.is_empty():
		return
	var volume := PortApronPadCatalog.brick_volume(trimmed)
	if volume == _layout.grid_size:
		_layout.pad_template_id = trimmed
		return
	_layout.pad_template_id = trimmed
	_layout.grid_size = volume
	_grid = _layout.grid()
	_layer_y = clampi(_layer_y, 0, maxi(_grid.height - 1, 0))
	_rebuild_preview()


func _refresh_file_label() -> void:
	if _file_lbl == null:
		return
	if _current_path.is_empty():
		_file_lbl.text = "not saved yet — Save writes a .json under buildings/"
	else:
		_file_lbl.text = _current_path.get_file()


func _filename_slug() -> String:
	var raw := ""
	if _name_edit != null:
		raw = _name_edit.text.strip_edges()
	if raw.is_empty():
		raw = _layout.display_name.strip_edges()
	var out := ""
	var lowered := raw.to_lower()
	for i in range(lowered.length()):
		var code := lowered.unicode_at(i)
		var is_letter := code >= 97 and code <= 122
		var is_number := code >= 48 and code <= 57
		if is_letter or is_number:
			out += lowered[i]
		elif not out.is_empty() and not out.ends_with("_"):
			out += "_"
	out = out.trim_suffix("_")
	if out.is_empty():
		return "building"
	return out


func _refresh_load_options() -> void:
	if _load_option == null:
		return
	_load_option.clear()
	_load_option.add_item("(pick a building JSON)", 0)
	_load_option.set_item_metadata(0, "")
	var index := 1
	for blueprint_id in BuildingBlueprintCatalog.ids():
		_load_option.add_item("%s.json" % blueprint_id, index)
		_load_option.set_item_metadata(index, blueprint_id)
		index += 1


func _select_role(role_id: String) -> void:
	if _role_option == null:
		return
	var wanted := role_id.strip_edges()
	if wanted.is_empty():
		wanted = "decorative"
	for i in range(_role_option.item_count):
		if str(_role_option.get_item_metadata(i)) == wanted:
			_role_option.select(i)
			return
	_role_option.select(0)


func _show_open_dialog() -> void:
	_open_dialog.current_dir = ProjectSettings.globalize_path(BuildingBlueprintCatalog.BLUEPRINT_DIR)
	_open_dialog.popup_centered_ratio(0.7)


func _show_save_dialog() -> void:
	var directory := ProjectSettings.globalize_path(BuildingBlueprintCatalog.BLUEPRINT_DIR)
	DirAccess.make_dir_recursive_absolute(directory)
	_save_dialog.current_dir = directory
	if not _current_path.is_empty():
		_save_dialog.current_file = _current_path.get_file()
	else:
		_save_dialog.current_file = _filename_slug() + ".json"
	_save_dialog.popup_centered_ratio(0.7)


func _load_selected_json() -> void:
	if _load_option == null or _load_option.selected < 1:
		_export_lbl.text = "Pick a building JSON first"
		return
	var blueprint_id := str(_load_option.get_item_metadata(_load_option.selected))
	_load_json(BuildingBlueprintCatalog.path_for(blueprint_id))


func _load_json(path: String) -> void:
	var res_path := path
	if not res_path.begins_with("res://"):
		var localized := ProjectSettings.localize_path(path)
		if localized.begins_with("res://"):
			res_path = localized
	var loaded := BuildingBlueprintCatalog.load_path(res_path)
	if loaded == null:
		_export_lbl.text = "Could not load %s" % path
		return
	_layout = loaded
	_grid = _layout.grid()
	_layer_y = clampi(_layer_y, 0, maxi(_grid.height - 1, 0))
	_current_path = BuildingBlueprintCatalog.path_for(_layout.blueprint_id)
	_name_edit.text = _layout.display_name
	_select_role(_layout.role)
	_select_pad_template(_layout.pad_template_id)
	_refresh_file_label()
	_refresh_load_options()
	_rebuild_preview()
	_refresh_rules()
	_refresh_palette_selection()
	_export_lbl.text = "Loaded %s" % _current_path


func _new_blank() -> void:
	_layout = BuildingLayout.new()
	_layout.blueprint_id = ""
	_layout.display_name = "Untitled Building"
	_layout.role = "decorative"
	_layout.pad_template_id = ""
	_layout.grid_size = DEFAULT_GRID
	_grid = _layout.grid()
	_current_path = ""
	_layer_y = 0
	_name_edit.text = _layout.display_name
	_select_role(_layout.role)
	_select_pad_template("")
	_refresh_file_label()
	_rebuild_preview()
	_refresh_rules()
	_export_lbl.text = "New blank blueprint"


func _save_json() -> void:
	## First save: ask for a filename. Later saves overwrite the loaded/saved path.
	if _current_path.is_empty():
		_show_save_dialog()
		return
	_save_to_path(_current_path)


func _save_to_path(path: String) -> void:
	_apply_metadata_from_fields()
	var res_path := path
	if not res_path.begins_with("res://"):
		var localized := ProjectSettings.localize_path(path)
		if localized.begins_with("res://"):
			res_path = localized
		else:
			# Always land under buildings/ — the file name is the id.
			res_path = BuildingBlueprintCatalog.path_for(path.get_file().get_basename())
	if not res_path.ends_with(".json"):
		res_path += ".json"
	var stem := res_path.get_file().get_basename().strip_edges()
	if stem.is_empty():
		stem = _filename_slug()
		res_path = BuildingBlueprintCatalog.path_for(stem)
	_layout.blueprint_id = stem

	var report := BuildingRules.validate(_layout)
	if not bool(report.get("ok", false)):
		_export_lbl.text = "Save blocked: %s" % ", ".join(report.get("errors", PackedStringArray()))
		_refresh_rules()
		return

	var directory := ProjectSettings.globalize_path(res_path.get_base_dir())
	DirAccess.make_dir_recursive_absolute(directory)
	var file := FileAccess.open(res_path, FileAccess.WRITE)
	if file == null:
		_export_lbl.text = "Could not write %s (is res:// writable?)" % res_path
		return
	file.store_string(JSON.stringify(_layout.to_dict(), "\t") + "\n")
	file.close()
	_current_path = res_path
	_refresh_file_label()
	_refresh_load_options()
	var warnings := report.get("warnings", PackedStringArray()) as PackedStringArray
	_export_lbl.text = "Saved %s%s" % [
		res_path,
		"\nWarnings: " + ", ".join(warnings) if not warnings.is_empty() else "",
	]
	_refresh_rules()
