class_name BuildingBrickEditor
extends CanvasLayer

## Developer building authoring app (scenes/apps/).
## Same interaction language as ShipyardBrickEditor: left palette, mouse paint/erase,
## layer filter, orbit/pan/zoom. Exports JSON blueprints under
## resources/data/buildings/.

enum Tool { PLACE = 0, ERASE = 1, MARK = 2 }

const THUMB_PX := 80
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
var _brick_id: String = "block"
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
var _camera: Camera3D
var _cam_yaw: float = 35.0
var _cam_pitch: float = -35.0
var _cam_dist: float = 28.0
var _cam_target: Vector3 = Vector3(0.0, 2.0, 0.0)
var _orbiting := false
var _panning := false
var _orbit_last: Vector2 = Vector2.ZERO

var _title_lbl: Label
var _status_lbl: Label
var _hint_lbl: Label
var _rules_lbl: Label
var _layer_lbl: Label
var _file_lbl: Label
var _name_edit: LineEdit
var _role_option: OptionButton
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
	var h := row.get_child(0) as HBoxContainer
	if h == null or h.get_child_count() < 1:
		return null
	var plate := h.get_child(0) as PanelContainer
	if plate == null or plate.get_child_count() < 1:
		return null
	return plate.get_child(0) as TextureRect


func _open_editor() -> void:
	_layer_y = 0
	_yaw = 0
	_brick_id = "block"
	_tool = Tool.PLACE
	_clear_mark()
	_name_edit.text = _layout.display_name
	_select_role(_layout.role)
	_use_catalog_color = true
	_sync_color_picker_from_catalog()
	_refresh_file_label()
	_refresh_load_options()
	_export_lbl.text = ""
	_resize()
	_root.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_rebuild_preview()
	_refresh_rules()
	_refresh_palette_selection()
	_refresh_hint()


func _build_chrome() -> void:
	_root = Control.new()
	_root.name = "EditorRoot"
	_root.visible = false
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = HudStyle.make_theme()
	add_child(_root)

	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.04, 0.05, 0.07, 1.0)
	_root.add_child(bg)

	var main := HBoxContainer.new()
	main.set_anchors_preset(Control.PRESET_FULL_RECT)
	main.add_theme_constant_override("separation", 0)
	_root.add_child(main)

	var side := PanelContainer.new()
	side.custom_minimum_size = Vector2(360, 0)
	side.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var side_sb := StyleBoxFlat.new()
	side_sb.bg_color = HudStyle.C_BG
	side_sb.border_color = HudStyle.C_BRASS
	side_sb.set_border_width_all(1)
	side.add_theme_stylebox_override("panel", side_sb)
	main.add_child(side)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	side.add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	margin.add_child(col)

	var title := Label.new()
	title.text = "BUILDING"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", HudStyle.C_AMBER)
	col.add_child(title)

	_title_lbl = Label.new()
	_title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title_lbl.add_theme_font_size_override("font_size", 13)
	_title_lbl.add_theme_color_override("font_color", HudStyle.C_TEXT)
	_title_lbl.text = "Official voxel blueprint authoring"
	col.add_child(_title_lbl)

	_status_lbl = Label.new()
	_status_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_lbl.add_theme_font_size_override("font_size", 11)
	_status_lbl.add_theme_color_override("font_color", HudStyle.C_LABEL)
	_status_lbl.text = (
		"LMB paint · RMB orbit · MMB pan · Scroll zoom · [ ] layer · R rotate · X erase\n"
		+ "Copy a floor: Mark → two clicks → Copy → Layer+ → Paste this layer"
	)
	col.add_child(_status_lbl)

	_hint_lbl = Label.new()
	_hint_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_lbl.add_theme_font_size_override("font_size", 13)
	_hint_lbl.add_theme_color_override("font_color", HudStyle.C_AMBER)
	_hint_lbl.text = "Place bricks, or press Mark to copy a region."
	col.add_child(_hint_lbl)

	col.add_child(HSeparator.new())

	var file_hdr := Label.new()
	file_hdr.text = "JSON FILE"
	file_hdr.add_theme_color_override("font_color", HudStyle.C_AMBER)
	col.add_child(file_hdr)

	_file_lbl = Label.new()
	_file_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_file_lbl.add_theme_font_size_override("font_size", 12)
	_file_lbl.add_theme_color_override("font_color", HudStyle.C_TEXT)
	col.add_child(_file_lbl)

	_name_edit = _add_labeled_edit(col, "Display name", "Untitled Building")

	var role_lbl := Label.new()
	role_lbl.text = "Service role"
	role_lbl.add_theme_font_size_override("font_size", 12)
	role_lbl.add_theme_color_override("font_color", HudStyle.C_LABEL)
	col.add_child(role_lbl)
	_role_option = OptionButton.new()
	_role_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_role_option.add_item("decorative", 0)
	_role_option.set_item_metadata(0, "decorative")
	col.add_child(_role_option)

	col.add_child(HSeparator.new())

	var items_hdr := Label.new()
	items_hdr.text = "ITEMS"
	items_hdr.add_theme_color_override("font_color", HudStyle.C_AMBER)
	col.add_child(items_hdr)

	var brick_scroll := ScrollContainer.new()
	brick_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	brick_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(brick_scroll)

	var brick_col := VBoxContainer.new()
	brick_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	brick_col.add_theme_constant_override("separation", 6)
	brick_scroll.add_child(brick_col)

	_brick_rows.clear()
	for id in BrickCatalog.ids_for_buildings():
		var row := _make_item_row(id)
		brick_col.add_child(row)
		_brick_rows[id] = row

	var tool_row := HBoxContainer.new()
	tool_row.add_theme_constant_override("separation", 6)
	col.add_child(tool_row)
	_place_btn = UiBuilder.button("Place")
	_place_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_place_btn.pressed.connect(func() -> void: _set_tool(Tool.PLACE))
	tool_row.add_child(_place_btn)
	_erase_btn = UiBuilder.button("Erase")
	_erase_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_erase_btn.pressed.connect(func() -> void: _set_tool(Tool.ERASE))
	tool_row.add_child(_erase_btn)
	_mark_btn = UiBuilder.button("Mark")
	_mark_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mark_btn.tooltip_text = "Click two opposite corners to select a region (M)"
	_mark_btn.pressed.connect(func() -> void: _set_tool(Tool.MARK))
	tool_row.add_child(_mark_btn)

	col.add_child(HSeparator.new())
	var color_hdr := Label.new()
	color_hdr.text = "COLOUR"
	color_hdr.add_theme_color_override("font_color", HudStyle.C_AMBER)
	col.add_child(color_hdr)

	var color_row := HBoxContainer.new()
	color_row.add_theme_constant_override("separation", 8)
	col.add_child(color_row)
	_color_picker = ColorPickerButton.new()
	_color_picker.custom_minimum_size = Vector2(72, 28)
	_color_picker.edit_alpha = false
	_color_picker.color = _paint_color
	_color_picker.color_changed.connect(_on_paint_color_changed)
	color_row.add_child(_color_picker)
	var catalog_btn := UiBuilder.button("Catalog default")
	catalog_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	catalog_btn.pressed.connect(_use_brick_catalog_color)
	color_row.add_child(catalog_btn)

	var preset_grid := HFlowContainer.new()
	preset_grid.add_theme_constant_override("h_separation", 4)
	preset_grid.add_theme_constant_override("v_separation", 4)
	col.add_child(preset_grid)
	_color_preset_btns.clear()
	for preset in COLOR_PRESETS:
		var swatch := Button.new()
		swatch.custom_minimum_size = Vector2(28, 28)
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
		preset_grid.add_child(swatch)
		_color_preset_btns.append(swatch)

	var tool_row2 := HBoxContainer.new()
	tool_row2.add_theme_constant_override("separation", 6)
	col.add_child(tool_row2)
	var rot_btn := UiBuilder.button("Rotate")
	rot_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rot_btn.pressed.connect(func() -> void:
		_rotate_yaw()
		_refresh_rules()
		_refresh_ghost_from_mouse()
	)
	tool_row2.add_child(rot_btn)
	var clear_btn := UiBuilder.button("Clear pad")
	clear_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clear_btn.pressed.connect(_clear_layout)
	tool_row2.add_child(clear_btn)

	_layer_lbl = Label.new()
	_layer_lbl.add_theme_color_override("font_color", HudStyle.C_TEXT)
	col.add_child(_layer_lbl)

	var layer_row := HBoxContainer.new()
	layer_row.add_theme_constant_override("separation", 6)
	col.add_child(layer_row)
	var down := UiBuilder.button("Layer −")
	down.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	down.pressed.connect(func() -> void: _set_layer_y(_layer_y - 1))
	layer_row.add_child(down)
	var up := UiBuilder.button("Layer +")
	up.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	up.pressed.connect(func() -> void: _set_layer_y(_layer_y + 1))
	layer_row.add_child(up)

	var clip_hdr := Label.new()
	clip_hdr.text = "COPY / PASTE"
	clip_hdr.add_theme_color_override("font_color", HudStyle.C_AMBER)
	col.add_child(clip_hdr)

	var clip_row := HBoxContainer.new()
	clip_row.add_theme_constant_override("separation", 6)
	col.add_child(clip_row)
	_copy_btn = UiBuilder.button("Copy")
	_copy_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_copy_btn.tooltip_text = "Copy the marked region (Ctrl+C)"
	_copy_btn.pressed.connect(_copy_marked_region)
	clip_row.add_child(_copy_btn)
	_paste_btn = UiBuilder.button("Paste at cursor")
	_paste_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_paste_btn.tooltip_text = "Stamp clipboard with min corner under the mouse (Ctrl+V)"
	_paste_btn.pressed.connect(_paste_clipboard_at_cursor)
	clip_row.add_child(_paste_btn)

	var clip_row2 := HBoxContainer.new()
	clip_row2.add_theme_constant_override("separation", 6)
	col.add_child(clip_row2)
	_paste_layer_btn = UiBuilder.button("Paste this layer")
	_paste_layer_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_paste_layer_btn.tooltip_text = "Same XZ as the copy, on the current layer — use for floors"
	_paste_layer_btn.pressed.connect(_paste_clipboard_on_layer)
	clip_row2.add_child(_paste_layer_btn)
	_paste_up_btn = UiBuilder.button("Paste ↑")
	_paste_up_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_paste_up_btn.tooltip_text = "Paste one storey above the original copy"
	_paste_up_btn.pressed.connect(_paste_clipboard_one_up)
	clip_row2.add_child(_paste_up_btn)

	col.add_child(HSeparator.new())

	_rules_lbl = Label.new()
	_rules_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rules_lbl.add_theme_font_size_override("font_size", 12)
	_rules_lbl.add_theme_color_override("font_color", HudStyle.C_TEXT)
	col.add_child(_rules_lbl)

	col.add_child(HSeparator.new())

	var load_hdr := Label.new()
	load_hdr.text = "Existing buildings"
	load_hdr.add_theme_font_size_override("font_size", 12)
	load_hdr.add_theme_color_override("font_color", HudStyle.C_LABEL)
	col.add_child(load_hdr)
	_load_option = OptionButton.new()
	_load_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(_load_option)

	var load_row := HBoxContainer.new()
	load_row.add_theme_constant_override("separation", 6)
	col.add_child(load_row)
	var load_selected := UiBuilder.button("Load selected")
	load_selected.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	load_selected.pressed.connect(_load_selected_json)
	load_row.add_child(load_selected)
	var browse_btn := UiBuilder.button("Browse…")
	browse_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	browse_btn.pressed.connect(_show_open_dialog)
	load_row.add_child(browse_btn)

	var save_btn := UiBuilder.button("Save JSON")
	save_btn.pressed.connect(_save_json)
	col.add_child(save_btn)
	var save_as_btn := UiBuilder.button("Save As…")
	save_as_btn.pressed.connect(_show_save_dialog)
	col.add_child(save_as_btn)
	var new_btn := UiBuilder.button("New blank")
	new_btn.pressed.connect(_new_blank)
	col.add_child(new_btn)

	_export_lbl = Label.new()
	_export_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_export_lbl.add_theme_font_size_override("font_size", 10)
	_export_lbl.add_theme_color_override("font_color", HudStyle.C_LABEL)
	col.add_child(_export_lbl)

	_vp_host = SubViewportContainer.new()
	_vp_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vp_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_vp_host.stretch = true
	_vp_host.mouse_filter = Control.MOUSE_FILTER_STOP
	_vp_host.gui_input.connect(_on_viewport_gui_input)
	main.add_child(_vp_host)

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


func _add_labeled_edit(parent: VBoxContainer, label_text: String, value: String) -> LineEdit:
	var label := Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", HudStyle.C_LABEL)
	parent.add_child(label)
	var edit := LineEdit.new()
	edit.text = value
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(edit)
	return edit


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
	# No upper clamp — painting above the pad grows building height.
	_layer_y = maxi(y, 0)
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


func _try_place(cell: Vector3i) -> bool:
	if not BrickCatalog.has(_brick_id):
		return false
	if BrickCatalog.has_tag(_brick_id, "ship_only"):
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
		_grid = _layout.grid()
		_layer_y = clampi(_layer_y, 0, maxi(_grid.height - 1, 0))
		_rebuild_preview()
	return true


func _placement_legal(cell: Vector3i) -> bool:
	if _grid == null or not BrickCatalog.has(_brick_id):
		return false
	if BrickCatalog.has_tag(_brick_id, "ship_only"):
		return false
	var fp := BrickCatalog.footprint_of(_brick_id)
	var yaw_steps := int(round(float(_yaw) / 90.0)) % 4
	var placing_floor := BuildingLayout.is_surface_brick(_brick_id)
	for occupied in _grid.footprint_cells(cell, fp, yaw_steps):
		if not _grid.in_bounds(occupied):
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
	_ghost_cell = cell
	if not _clipboard.is_empty():
		_update_paste_preview()
	var valid := _placement_legal(cell)
	var paint_color := _active_paint_color()
	if (
		_ghost != null and is_instance_valid(_ghost)
		and _ghost_brick_id == _brick_id
		and _ghost_cell == cell
		and _ghost_yaw == _yaw
		and _ghost_valid == valid
		and _ghost_color.is_equal_approx(paint_color)
	):
		return
	if (
		_ghost != null and is_instance_valid(_ghost)
		and _ghost_brick_id == _brick_id
		and _ghost_valid == valid
		and _ghost_color.is_equal_approx(paint_color)
	):
		_ghost_cell = cell
		_ghost_yaw = _yaw
		_ghost.position = BuildingFitout.footprint_center_local(_grid, cell, _brick_id, _yaw)
		_ghost.rotation_degrees = Vector3(0.0, float(_yaw), 0.0)
		return
	_clear_ghost()
	_ghost_brick_id = _brick_id
	_ghost_cell = cell
	_ghost_yaw = _yaw
	_ghost_valid = valid
	_ghost_color = paint_color
	_ghost = BrickCatalog.create_visual(_brick_id, {"preview_mesh": true, "color": paint_color})
	_ghost.name = "PlaceGhost"
	_ghost.position = BuildingFitout.footprint_center_local(_grid, cell, _brick_id, _yaw)
	_ghost.rotation_degrees = Vector3(0.0, float(_yaw), 0.0)
	_tint_ghost(_ghost, valid)
	_pad_root.add_child(_ghost)


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
		var mat := StandardMaterial3D.new()
		if mi.material_override is StandardMaterial3D:
			mat = (mi.material_override as StandardMaterial3D).duplicate() as StandardMaterial3D
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(
			tint.r * 0.55 + mat.albedo_color.r * 0.45,
			tint.g * 0.55 + mat.albedo_color.g * 0.45,
			tint.b * 0.55 + mat.albedo_color.b * 0.45,
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
	# Pad grows on place — allow aiming past the current edge.
	return cell


func _make_item_row(brick_id: String) -> PanelContainer:
	var row := PanelContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.mouse_filter = Control.MOUSE_FILTER_STOP
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
	sb.set_content_margin_all(6)
	row.add_theme_stylebox_override("panel", sb)
	row.set_meta("style", sb)

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	row.add_child(h)

	var thumb_plate := PanelContainer.new()
	thumb_plate.custom_minimum_size = Vector2(THUMB_PX + 4, THUMB_PX + 4)
	thumb_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var plate_sb := StyleBoxFlat.new()
	plate_sb.bg_color = Color(0.10, 0.11, 0.13, 1.0)
	plate_sb.set_corner_radius_all(4)
	plate_sb.set_content_margin_all(2)
	thumb_plate.add_theme_stylebox_override("panel", plate_sb)
	h.add_child(thumb_plate)

	var thumb := TextureRect.new()
	thumb.custom_minimum_size = Vector2(THUMB_PX, THUMB_PX)
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	thumb_plate.add_child(thumb)

	var text_col := VBoxContainer.new()
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_col.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(text_col)

	var name_lbl := Label.new()
	name_lbl.text = BrickCatalog.display_name(brick_id)
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_lbl.add_theme_font_size_override("font_size", 14)
	name_lbl.add_theme_color_override("font_color", HudStyle.C_TEXT)
	text_col.add_child(name_lbl)

	var fp := BrickCatalog.footprint_of(brick_id)
	var sz := BrickCatalog.size_m(brick_id)
	var size_lbl := Label.new()
	size_lbl.text = "%d×%d×%d cells  (%.1f×%.1f×%.1f m)" % [
		fp.x, fp.y, fp.z, sz.x, sz.y, sz.z,
	]
	size_lbl.add_theme_font_size_override("font_size", 11)
	size_lbl.add_theme_color_override("font_color", HudStyle.C_LABEL)
	text_col.add_child(size_lbl)
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
	var mode := "Place"
	match _tool:
		Tool.ERASE:
			mode = "Erase"
		Tool.MARK:
			if not _mark_anchor_set:
				mode = "Mark · click corner A"
			elif not _mark_complete:
				mode = "Mark · click corner B"
			else:
				mode = "Marked · ready to Copy"
	var clip_note := ""
	if not _clipboard.is_empty():
		var sz := BrickRegionClipboard.size_cells(_clipboard)
		clip_note = " · clipboard %d (%d×%d×%d)" % [
			int(_clipboard.get("cell_count", 0)), sz.x, sz.y, sz.z,
		]
	_layer_lbl.text = "Layer %d  (%.1f m)  ·  pad %d×%d×%d  ·  %s%s" % [
		_layer_y,
		float(_layer_y) * BuildingGrid.CELL_M,
		_grid.width,
		_grid.height,
		_grid.depth,
		mode,
		clip_note,
	]
	_refresh_tool_buttons()
	_refresh_hint()


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
	if tool != Tool.MARK:
		_clear_mark()
		_clear_mark_preview()
	else:
		_clear_mark()
		_clear_ghost()
		_clear_paste_preview()
	_refresh_palette_selection()
	_refresh_ghost_from_mouse()
	_refresh_hint()


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
	var n := int(_clipboard.get("cell_count", 0))
	if n <= 0:
		_clipboard.clear()
		_set_hint("Marked region is empty — nothing to copy.", HudStyle.C_RED)
		_refresh_palette_selection()
		return
	## Leave mark mode so the next action is paste, not another mark click.
	_set_tool(Tool.PLACE)
	_set_hint(
		"Copied %d bricks. Layer+ then “Paste this layer”, or hover + Ctrl+V." % n,
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
	var shift := _layout.ensure_fit_cells(needed)
	dest += shift
	_clipboard_src_min += shift
	## Re-check after any remap from pad growth.
	if not _can_paste_at(dest):
		_set_hint("Can't paste there — clear blocking bricks first.", HudStyle.C_RED)
		return false
	_layout.cells = BrickRegionClipboard.paste_region(_clipboard, dest, _layout.cells)
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
	var dest := Vector3i(_clipboard_src_min.x, _layer_y, _clipboard_src_min.z)
	_paste_at(dest)


func _paste_clipboard_one_up() -> void:
	if _clipboard.is_empty():
		_set_hint("Clipboard empty — Mark + Copy first.", HudStyle.C_RED)
		return
	var sz := BrickRegionClipboard.size_cells(_clipboard)
	var dest := Vector3i(
		_clipboard_src_min.x,
		_clipboard_src_min.y + maxi(sz.y, 1),
		_clipboard_src_min.z,
	)
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
	## Content primaries.
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
	var pos := _grid.cell_center_local(cell) if surface_tile \
		else BuildingFitout.footprint_center_local(_grid, cell, brick_id, yaw)
	var existing: Node3D = _brick_visuals.get(key) as Node3D
	if (
		existing != null and is_instance_valid(existing)
		and str(existing.get_meta("brick_id", "")) == brick_id
		and int(existing.get_meta("yaw", 0)) == yaw
		and str(existing.get_meta("color_key", "")) == color_key
	):
		existing.position = pos
		existing.rotation_degrees = Vector3(0.0, float(yaw), 0.0)
		existing.set_meta("cell_y", cell.y)
		return
	if existing != null and is_instance_valid(existing):
		existing.queue_free()
	var visual := BrickCatalog.create_visual(brick_id, {"color": color})
	visual.name = "%s_%s" % [brick_id, key]
	visual.position = pos
	visual.rotation_degrees = Vector3(0.0, float(yaw), 0.0)
	visual.set_meta("brick_id", brick_id)
	visual.set_meta("yaw", yaw)
	visual.set_meta("color_key", color_key)
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
	_rules_lbl.text = "\n".join(lines)


func _apply_metadata_from_fields() -> void:
	if _name_edit != null:
		_layout.display_name = _name_edit.text.strip_edges()
	if _role_option != null and _role_option.selected >= 0:
		_layout.role = str(_role_option.get_item_metadata(_role_option.selected))


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
	if out.is_empty() or out == "untitled_building" or out == "untitled":
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
	_layout.grid_size = DEFAULT_GRID
	_grid = _layout.grid()
	_current_path = ""
	_layer_y = 0
	_name_edit.text = _layout.display_name
	_select_role(_layout.role)
	_refresh_file_label()
	_rebuild_preview()
	_refresh_rules()
	_export_lbl.text = "New blank blueprint"


func _save_json() -> void:
	# One click: overwrite current file, or write buildings/<display_name>.json.
	if _current_path.is_empty():
		_save_to_path(BuildingBlueprintCatalog.path_for(_filename_slug()))
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
