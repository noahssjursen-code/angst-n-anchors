class_name ShipyardBrickEditor
extends CanvasLayer

## Deck-grid brick painter for official hulls.
## Run `scenes/apps/shipyard_brick_editor.tscn` as an engine app to author
## `resources/data/vessels/prebuilt/*.json`. Shipwright sells those presets in-game.

signal closed
signal layout_confirmed(hull_entry: Dictionary, layout: Dictionary, vessel_name: String, editing_uid: String)

enum Tool { PLACE = 0, ERASE = 1 }

## When true (tool scene), open immediately and Save writes official prebuilt JSON.
@export var standalone_tool: bool = false

const COLOR_PRESETS := [
	{"name": "Catalog", "custom": false},
	{"name": "Steel", "color": Color(0.78, 0.80, 0.84)},
	{"name": "White", "color": Color(0.92, 0.91, 0.88)},
	{"name": "Cream", "color": Color(0.86, 0.80, 0.68)},
	{"name": "Timber", "color": Color(0.48, 0.34, 0.22)},
	{"name": "Charcoal", "color": Color(0.18, 0.18, 0.20)},
	{"name": "Slate", "color": Color(0.32, 0.36, 0.40)},
	{"name": "Hull red", "color": Color(0.55, 0.18, 0.14)},
	{"name": "Harbour", "color": Color(0.22, 0.38, 0.48)},
	{"name": "Yellow", "color": Color(0.82, 0.68, 0.22)},
]

var _hull_entry: Dictionary = {}
var _editing_uid: String = ""
var _authoring_mode := false
var _layout: BrickLayout = BrickLayout.new()
var _grid: DeckGrid
var _layer_y: int = 0
var _yaw: int = 0
var _brick_id: String = "block"
var _tool: int = Tool.PLACE
var _painting := false
var _last_paint_cell: Vector3i = Vector3i(-999, -999, -999)
var _paint_color := Color(0.78, 0.80, 0.84)
var _use_catalog_color := true
## Cargo zone: click corner A, then corner B.
var _cargo_anchor: Vector3i = Vector3i(-999, -999, -999)
var _cargo_anchor_set := false
var _thumb_cache: Dictionary = {} ## brick_id → ImageTexture

var _root: Control
var _viewport: SubViewport
var _world: Node3D
var _boat: BoatBody
var _brick_root: Node3D
var _brick_visuals: Dictionary = {} ## cell_key → Node3D
var _grid_overlay: Node3D
var _ghost: Node3D
var _ghost_brick_id: String = ""
var _ghost_cell: Vector3i = Vector3i(-999, -999, -999)
var _ghost_yaw: int = -1
var _ghost_valid: bool = false
var _ghost_color := Color(0, 0, 0, 0)
const EDITOR_BRICK_ROOT := "EditorBricks"
const PREBUILT_DIR := "res://resources/data/vessels/prebuilt"
const PREBUILT_FORMAT_VERSION := 1
var _camera: Camera3D
var _cam_yaw: float = 35.0
var _cam_pitch: float = -35.0
var _cam_dist: float = 48.0
var _cam_target: Vector3 = Vector3(0.0, 2.5, 0.0)
var _orbiting := false
var _panning := false
var _orbit_last: Vector2 = Vector2.ZERO

var _hull_lbl: Label
var _status_lbl: Label
var _rules_lbl: Label
var _caps_lbl: Label
var _layer_lbl: Label
var _name_edit: LineEdit
var _sign_text_edit: LineEdit
var _brick_rows: Dictionary = {} ## brick_id → PanelContainer
var _confirm_btn: Button
var _back_btn: Button
var _hull_option: OptionButton
var _prebuilt_option: OptionButton
var _authoring_prebuilt_id: String = ""
var _option_guard := false
var _show_light_cones := true
var _cone_btn: Button
var _color_picker: ColorPickerButton
var _color_preset_btns: Array[Button] = []
var _dev_save_lbl: Label
var _vp_host: SubViewportContainer
const THUMB_PX := 80
const MAX_VESSEL_NAME_LEN := 28
const PREBUILT_BLANK_META := "__blank__"


func _init() -> void:
	name = "ShipyardBrickEditor"
	layer = 14
	_build_chrome()


func _ready() -> void:
	var vp := get_viewport()
	if vp != null and not vp.size_changed.is_connected(_resize):
		vp.size_changed.connect(_resize)
	# Bake palette icons after we're in the tree (SubViewport needs a SceneTree).
	for id in _brick_rows.keys():
		var row: PanelContainer = _brick_rows[id]
		var thumb := _row_thumb_rect(row)
		if thumb == null:
			continue
		if _thumb_cache.has(id):
			thumb.texture = _thumb_cache[id] as Texture2D
		else:
			_bake_brick_thumbnail(str(id), thumb)
	if standalone_tool:
		call_deferred("_boot_standalone_tool")


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


func is_open() -> bool:
	return _root != null and _root.visible


func _boot_standalone_tool() -> void:
	_authoring_mode = true
	var title := _root.find_child("TitleLabel", true, false) as Label
	if title != null:
		title.text = "PREBUILT AUTHORING"
	_status_lbl.text = (
		"Load an existing prebuilt or start blank on a hull.\n"
		+ "Save overwrites the loaded preset id (or creates from the vessel name).\n"
		+ "LMB place · RMB orbit · MMB pan · Scroll zoom · [ ] layer · R rotate · X erase"
	)
	_confirm_btn.text = "Save official prebuilt JSON"
	_back_btn.text = "Quit tool"
	var hull_hint := Label.new()
	hull_hint.text = "Hull (blank)"
	hull_hint.add_theme_font_size_override("font_size", 11)
	hull_hint.add_theme_color_override("font_color", HudStyle.C_LABEL)
	_hull_option.get_parent().add_child(hull_hint)
	_hull_option.get_parent().move_child(hull_hint, _hull_option.get_index())
	var pre_hint := Label.new()
	pre_hint.text = "Load existing prebuilt"
	pre_hint.add_theme_font_size_override("font_size", 11)
	pre_hint.add_theme_color_override("font_color", HudStyle.C_LABEL)
	_prebuilt_option.get_parent().add_child(pre_hint)
	_prebuilt_option.get_parent().move_child(pre_hint, _prebuilt_option.get_index())
	_populate_hull_option()
	_populate_prebuilt_option()
	if _hull_option != null:
		_hull_option.visible = true
	if _prebuilt_option != null:
		_prebuilt_option.visible = true
	if _prebuilt_option != null and _prebuilt_option.item_count > 1:
		## Prefer first existing preset so the tool opens with something to edit.
		_prebuilt_option.select(1)
		_on_standalone_prebuilt_selected(1)
	elif _hull_option != null and _hull_option.item_count > 0:
		_on_standalone_hull_selected(0)
	else:
		push_error("ShipyardBrickEditor: no hulls in HullRegistry")


func _populate_hull_option() -> void:
	if _hull_option == null:
		return
	_option_guard = true
	_hull_option.clear()
	var i := 0
	for entry in HullRegistry.catalog():
		_hull_option.add_item(str(entry.get("display", entry.get("id", "Hull"))), i)
		_hull_option.set_item_metadata(i, entry)
		i += 1
	_option_guard = false
	if not _hull_option.item_selected.is_connected(_on_standalone_hull_selected):
		_hull_option.item_selected.connect(_on_standalone_hull_selected)


func _populate_prebuilt_option(select_prebuilt_id: String = "") -> void:
	if _prebuilt_option == null:
		return
	_option_guard = true
	_prebuilt_option.clear()
	_prebuilt_option.add_item("— New blank deck —", 0)
	_prebuilt_option.set_item_metadata(0, PREBUILT_BLANK_META)
	var select_index := 0
	var i := 1
	for entry in PrebuiltVesselCatalog.catalog_entries():
		var preset_id := str(entry.get("prebuilt_id", ""))
		var label := "%s  (%s)" % [
			str(entry.get("prebuilt_name", preset_id)),
			preset_id,
		]
		_prebuilt_option.add_item(label, i)
		_prebuilt_option.set_item_metadata(i, entry)
		if not select_prebuilt_id.is_empty() and preset_id == select_prebuilt_id:
			select_index = i
		i += 1
	_prebuilt_option.select(select_index)
	_option_guard = false
	if not _prebuilt_option.item_selected.is_connected(_on_standalone_prebuilt_selected):
		_prebuilt_option.item_selected.connect(_on_standalone_prebuilt_selected)


func _on_standalone_hull_selected(index: int) -> void:
	if _option_guard or _hull_option == null or index < 0:
		return
	var entry: Variant = _hull_option.get_item_metadata(index)
	if typeof(entry) != TYPE_DICTIONARY:
		return
	_authoring_prebuilt_id = ""
	if _prebuilt_option != null:
		_option_guard = true
		_prebuilt_option.select(0)
		_option_guard = false
	open_for_authoring(entry as Dictionary)


func _on_standalone_prebuilt_selected(index: int) -> void:
	if _option_guard or _prebuilt_option == null or index < 0:
		return
	var meta: Variant = _prebuilt_option.get_item_metadata(index)
	if typeof(meta) == TYPE_STRING and str(meta) == PREBUILT_BLANK_META:
		_authoring_prebuilt_id = ""
		if _hull_option != null and _hull_option.item_count > 0:
			var hull_meta: Variant = _hull_option.get_item_metadata(_hull_option.selected)
			if typeof(hull_meta) == TYPE_DICTIONARY:
				open_for_authoring(hull_meta as Dictionary)
		return
	if typeof(meta) != TYPE_DICTIONARY:
		return
	_load_prebuilt_entry(meta as Dictionary)


func _load_prebuilt_entry(entry: Dictionary) -> void:
	var hull_id := str(entry.get("id", entry.get("hull_id", ""))).strip_edges()
	var hull := HullRegistry.get_by_id(hull_id)
	if hull.is_empty():
		_show_dev_save_result("LOAD FAILED · unknown hull '%s'" % hull_id, true)
		return
	var layout_raw: Variant = entry.get("prebuilt_layout", {})
	var layout: Dictionary = (
		(layout_raw as Dictionary).duplicate(true)
		if typeof(layout_raw) == TYPE_DICTIONARY
		else {}
	)
	_authoring_prebuilt_id = str(entry.get("prebuilt_id", "")).strip_edges()
	var vessel_name := str(entry.get("prebuilt_name", entry.get("display", ""))).strip_edges()
	## Sync hull dropdown to the preset's hull without clearing the load.
	if _hull_option != null:
		_option_guard = true
		for i in range(_hull_option.item_count):
			var hm: Variant = _hull_option.get_item_metadata(i)
			if typeof(hm) == TYPE_DICTIONARY and str((hm as Dictionary).get("id", "")) == hull_id:
				_hull_option.select(i)
				break
		_option_guard = false
	open_for_authoring(hull, layout, vessel_name)
	if _dev_save_lbl != null:
		_dev_save_lbl.text = "Loaded · %s" % str(entry.get("prebuilt_path", _authoring_prebuilt_id))
		_dev_save_lbl.add_theme_color_override("font_color", HudStyle.C_LABEL)


func open_for_authoring(
	hull_entry: Dictionary,
	existing_layout: Dictionary = {},
	vessel_name: String = "",
) -> void:
	_authoring_mode = true
	var name := vessel_name.strip_edges()
	if name.is_empty():
		name = str(hull_entry.get("display", ""))
	open_for_hull(hull_entry, existing_layout, "", name)


func open_for_hull(
	hull_entry: Dictionary,
	existing_layout: Dictionary = {},
	editing_uid: String = "",
	vessel_name: String = "",
) -> void:
	_hull_entry = hull_entry.duplicate(true)
	_editing_uid = editing_uid.strip_edges()
	var hull_id := str(hull_entry.get("id", "workboat"))
	_grid = HullRegistry.make_grid(hull_id)
	_layout = BrickLayout.new()
	_layout.hull_id = hull_id
	# Only restore a prior layout when explicitly passed — never auto-configure.
	if not existing_layout.is_empty():
		_layout = BrickLayout.from_dict(existing_layout)
	_layer_y = 0
	_yaw = 0
	_brick_id = "block"
	_tool = Tool.PLACE
	_clear_cargo_anchor()
	## Hull change must rebuild the editor boat (workboat vs trawler sizes).
	if _boat != null and is_instance_valid(_boat):
		_boat.queue_free()
		_boat = null
		_brick_root = null
	var hull_label := str(hull_entry.get("display", "Vessel"))
	if _authoring_mode or standalone_tool:
		_hull_lbl.text = "Official prebuilt — %s" % hull_label
		_confirm_btn.text = "Save official prebuilt JSON"
		_back_btn.text = "Quit tool"
	elif _editing_uid.is_empty():
		_hull_lbl.text = "New build — %s" % hull_label
		_confirm_btn.text = "Confirm build"
		_back_btn.text = "Back to hulls"
	else:
		_hull_lbl.text = "Refit — %s" % hull_label
		_confirm_btn.text = "Save refit"
		_back_btn.text = "Back to yard"
	var suggested := vessel_name.strip_edges()
	if suggested.is_empty():
		suggested = VesselSpawn.vessel_name_of({
			"name": "",
			"display": hull_label,
		})
	_name_edit.text = suggested
	if _sign_text_edit != null:
		_sign_text_edit.text = suggested
	if _dev_save_lbl != null:
		_dev_save_lbl.text = ""
	_resize()
	_root.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_rebuild_preview()
	_refresh_rules()
	_refresh_palette_selection()


func is_refitting() -> bool:
	return not _editing_uid.is_empty()


func hide_editor() -> void:
	_root.visible = false
	_clear_preview()


func _close() -> void:
	if standalone_tool or _authoring_mode:
		get_tree().quit()
		return
	hide_editor()
	closed.emit()


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

	# ── LEFT: item list ──────────────────────────────────────────────────────
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
	title.name = "TitleLabel"
	title.text = "BUILD"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", HudStyle.C_AMBER)
	col.add_child(title)

	_hull_lbl = Label.new()
	_hull_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hull_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hull_lbl.add_theme_font_size_override("font_size", 13)
	_hull_lbl.add_theme_color_override("font_color", HudStyle.C_TEXT)
	col.add_child(_hull_lbl)

	_hull_option = OptionButton.new()
	_hull_option.visible = false
	_hull_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hull_option.tooltip_text = "Hull class for a blank new deck"
	col.add_child(_hull_option)

	_prebuilt_option = OptionButton.new()
	_prebuilt_option.visible = false
	_prebuilt_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_prebuilt_option.tooltip_text = "Load an existing official prebuilt JSON"
	col.add_child(_prebuilt_option)

	_status_lbl = Label.new()
	_status_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_lbl.add_theme_font_size_override("font_size", 12)
	_status_lbl.add_theme_color_override("font_color", HudStyle.C_LABEL)
	_status_lbl.text = "Empty deck — place items yourself.\nLMB place · RMB orbit · MMB pan · Scroll zoom\n[ ] layer (shows this floor + below) · R rotate · X erase\nCargo zone: click A, then B · Doors open with F after deploy\nCell = 1.0 m"
	col.add_child(_status_lbl)

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
	for id in BrickCatalog.ids():
		var row := _make_item_row(id)
		brick_col.add_child(row)
		_brick_rows[id] = row

	var tool_row := HBoxContainer.new()
	tool_row.add_theme_constant_override("separation", 6)
	col.add_child(tool_row)
	var place_btn := UiBuilder.button("Place")
	place_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	place_btn.pressed.connect(func() -> void: _tool = Tool.PLACE; _clear_cargo_anchor(); _refresh_palette_selection(); _refresh_ghost_from_mouse())
	tool_row.add_child(place_btn)
	var erase_btn := UiBuilder.button("Erase")
	erase_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	erase_btn.pressed.connect(func() -> void: _tool = Tool.ERASE; _clear_cargo_anchor(); _refresh_palette_selection(); _clear_ghost())
	tool_row.add_child(erase_btn)

	var tool_row2 := HBoxContainer.new()
	tool_row2.add_theme_constant_override("separation", 6)
	col.add_child(tool_row2)
	var rot_btn := UiBuilder.button("Rotate")
	rot_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rot_btn.pressed.connect(func() -> void: _rotate_yaw(); _refresh_rules(); _refresh_ghost_from_mouse())
	tool_row2.add_child(rot_btn)
	var clear_btn := UiBuilder.button("Clear deck")
	clear_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clear_btn.pressed.connect(_clear_layout)
	tool_row2.add_child(clear_btn)

	_cone_btn = UiBuilder.button("Light cones: ON")
	_cone_btn.pressed.connect(_toggle_light_cones)
	col.add_child(_cone_btn)

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

	var sign_lbl := Label.new()
	sign_lbl.text = "Sign text (floor / wall)"
	sign_lbl.add_theme_color_override("font_color", HudStyle.C_AMBER)
	sign_lbl.add_theme_font_size_override("font_size", 12)
	col.add_child(sign_lbl)
	_sign_text_edit = LineEdit.new()
	_sign_text_edit.placeholder_text = "Vessel name / custom text…"
	_sign_text_edit.max_length = 32
	_sign_text_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sign_text_edit.text_changed.connect(func(_t: String) -> void: _refresh_ghost_from_mouse())
	col.add_child(_sign_text_edit)

	col.add_child(HSeparator.new())

	_rules_lbl = Label.new()
	_rules_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rules_lbl.add_theme_font_size_override("font_size", 12)
	_rules_lbl.add_theme_color_override("font_color", HudStyle.C_TEXT)
	col.add_child(_rules_lbl)

	_caps_lbl = Label.new()
	_caps_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caps_lbl.add_theme_font_size_override("font_size", 12)
	_caps_lbl.add_theme_color_override("font_color", HudStyle.C_LABEL)
	col.add_child(_caps_lbl)

	col.add_child(HSeparator.new())

	var name_lbl := Label.new()
	name_lbl.text = "Vessel name"
	name_lbl.add_theme_font_size_override("font_size", 12)
	name_lbl.add_theme_color_override("font_color", HudStyle.C_LABEL)
	col.add_child(name_lbl)

	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Name your vessel"
	_name_edit.max_length = MAX_VESSEL_NAME_LEN
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(_name_edit)

	_confirm_btn = UiBuilder.button("Confirm build")
	_confirm_btn.pressed.connect(_on_confirm)
	col.add_child(_confirm_btn)

	_dev_save_lbl = Label.new()
	_dev_save_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dev_save_lbl.add_theme_font_size_override("font_size", 10)
	_dev_save_lbl.add_theme_color_override("font_color", HudStyle.C_LABEL)
	col.add_child(_dev_save_lbl)

	_back_btn = UiBuilder.button("Back to hulls")
	_back_btn.pressed.connect(_close)
	col.add_child(_back_btn)

	# ── RIGHT: 3D hull canvas ────────────────────────────────────────────────
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


func _resize() -> void:
	if _viewport == null or _vp_host == null:
		return
	var sz := _vp_host.size
	if sz.x > 4.0 and sz.y > 4.0:
		_viewport.size = Vector2i(int(sz.x), int(sz.y))


func _unhandled_input(event: InputEvent) -> void:
	if not is_open():
		return
	if event.is_action_pressed("ui_cancel"):
		if _cargo_anchor_set:
			_clear_cargo_anchor()
			_refresh_palette_selection()
			_refresh_ghost_from_mouse()
			get_viewport().set_input_as_handled()
			return
		_close()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		match key.keycode:
			KEY_R:
				_rotate_yaw()
				_refresh_rules()
				_refresh_ghost_from_mouse()
				get_viewport().set_input_as_handled()
			KEY_X:
				_tool = Tool.ERASE if _tool == Tool.PLACE else Tool.PLACE
				_clear_cargo_anchor()
				_refresh_palette_selection()
				_clear_ghost()
				_refresh_ghost_from_mouse()
				get_viewport().set_input_as_handled()
			KEY_BRACKETLEFT:
				_set_layer_y(_layer_y - 1)
				get_viewport().set_input_as_handled()
			KEY_BRACKETRIGHT:
				_set_layer_y(_layer_y + 1)
				get_viewport().set_input_as_handled()


func _on_viewport_gui_input(event: InputEvent) -> void:
	if not is_open():
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_cam_dist = maxf(12.0, _cam_dist * 0.9)
			_update_camera()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_cam_dist = minf(120.0, _cam_dist * 1.1)
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
			# Cargo zones are click-A / click-B — never drag-paint.
			if not _is_cargo_tool():
				_paint_at_screen(mm.position)
			else:
				_update_ghost_at_screen(mm.position)
		else:
			_update_ghost_at_screen(mm.position)


func _set_layer_y(y: int) -> void:
	_layer_y = clampi(y, 0, 24)
	_refresh_grid_overlay()
	_apply_layer_visibility()
	_refresh_palette_selection()
	_refresh_rules()
	_refresh_ghost_from_mouse()


func _apply_layer_visibility() -> void:
	## Current edit layer and everything below stay visible; hide floors above.
	for key in _brick_visuals.keys():
		var node: Node3D = _brick_visuals[key]
		if node == null or not is_instance_valid(node):
			continue
		var cell_y := int(node.get_meta("cell_y", 0))
		node.visible = cell_y <= _layer_y
	## Cargo zones live on deck (y=0).
	if _brick_root != null:
		var cargo := _brick_root.get_node_or_null("CargoZonePreview")
		if cargo != null:
			cargo.visible = _layer_y >= 0


func _is_cargo_tool() -> bool:
	return BrickCatalog.has_tag(_brick_id, "cargo") or str(BrickCatalog.get_entry(_brick_id).get("place_mode", "")) == "rect"


func _clear_cargo_anchor() -> void:
	_cargo_anchor_set = false
	_cargo_anchor = Vector3i(-999, -999, -999)


func _paint_at_screen(screen_pos: Vector2) -> void:
	var cell := _pick_cell(screen_pos)
	if cell.x < 0:
		return
	if cell == _last_paint_cell:
		return
	_last_paint_cell = cell

	if _is_cargo_tool():
		_paint_cargo_at(cell)
		return

	if _tool == Tool.ERASE:
		if _layout.erase_cargo_zone_at(cell):
			_clear_cargo_anchor()
			_sync_brick_visuals()
			_refresh_rules()
			return
		## Fixtures peel first so erase doesn't delete the host wall.
		if _layout.clear_light(cell):
			_sync_brick_visuals()
			_refresh_rules()
			return
		## Signs come off first so erase doesn't have to delete the wall to clear text.
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


func _paint_cargo_at(cell: Vector3i) -> void:
	## Place: corner A then B. Erase: remove the whole zone under the cursor.
	if cell.y != 0:
		return
	if _tool == Tool.ERASE:
		if not _layout.erase_cargo_zone_at(cell):
			return
		_clear_cargo_anchor()
		_sync_brick_visuals()
		_refresh_rules()
		_refresh_palette_selection()
		_refresh_ghost_from_mouse()
		return

	if not _cargo_anchor_set:
		_cargo_anchor = Vector3i(cell.x, 0, cell.z)
		_cargo_anchor_set = true
		_refresh_palette_selection()
		_refresh_ghost_from_mouse()
		return

	var ok := _layout.add_cargo_zone(_cargo_anchor, Vector3i(cell.x, 0, cell.z))
	_clear_cargo_anchor()
	_refresh_palette_selection()
	if not ok:
		_refresh_ghost_from_mouse()
		return
	_sync_brick_visuals()
	_refresh_rules()
	_refresh_ghost_from_mouse()


func _rotate_yaw() -> void:
	var step := BrickCatalog.yaw_step_of(_brick_id) if BrickCatalog.has(_brick_id) else 90
	_yaw = (_yaw + step) % 360


func _try_place(cell: Vector3i) -> bool:
	var entry := BrickCatalog.get_entry(_brick_id)
	if entry.is_empty():
		return false
	if bool(entry.get("deck_only", false)) and cell.y != 0:
		return false
	if BrickCatalog.has_tag(_brick_id, "text"):
		return _try_place_text(cell)
	if BrickCatalog.has_tag(_brick_id, "light"):
		return _try_place_light(cell)
	var fp := BrickCatalog.footprint_of(_brick_id)
	var yaw := _yaw
	if _grid.is_partial_bow_cell(cell):
		if not BrickCatalog.has_tag(_brick_id, "diagonal_plan") or fp != Vector3i.ONE:
			return false
		yaw = _grid.partial_bow_yaw_degrees(cell)
		_yaw = yaw
	# Edge pieces (hull ladder) snap yaw outboard and must sit on the perimeter.
	if bool(entry.get("edge_only", false)):
		if cell.y != 0:
			return false
		yaw = _grid.outboard_yaw_degrees(cell, fp, 0)
		var yaw_steps_edge := int(round(float(yaw) / 90.0)) % 4
		if not _grid.footprint_touches_edge(cell, fp, yaw_steps_edge):
			return false
		_yaw = yaw
	var yaw_steps := int(round(float(yaw) / 90.0)) % 4
	var cells := _grid.footprint_cells(cell, fp, yaw_steps)
	for c in cells:
		if _grid.is_partial_bow_cell(c):
			if not BrickCatalog.has_tag(_brick_id, "diagonal_plan") or cells.size() != 1:
				return false
		elif not _grid.in_bounds(c):
			return false
		if _layout.cargo_contains(c):
			return false
	for c in cells:
		if _layout.has_cell(c):
			_layout.erase_footprint_at(c)
	var props := {}
	if not _use_catalog_color:
		props["color"] = _paint_color
	return _layout.place_footprint(cell, _brick_id, yaw, _grid, props)


func _try_place_text(cell: Vector3i) -> bool:
	## Signs mount onto existing walls/blocks — never delete the host brick.
	if cell.x < 0 or _grid == null:
		return false
	var entry := BrickCatalog.get_entry(_brick_id)
	if bool(entry.get("deck_only", false)) and cell.y != 0:
		return false
	var yaw := _yaw
	var text := _sign_text()
	if _layout.has_cell(cell):
		var host := _layout.get_brick(_layout.primary_cell_of(cell))
		var host_id := str(host.get("brick_id", ""))
		if BrickCatalog.has_tag(host_id, "text"):
			## Replace a free-standing sign brick.
			_layout.erase_footprint_at(cell)
			return _layout.place_footprint(cell, _brick_id, yaw, _grid, {"text": text})
		## Attach plaque to the wall / block under the cursor.
		return _layout.attach_sign(cell, _brick_id, yaw, text)
	## Empty cell — free-standing floor/wall sign.
	var fp := BrickCatalog.footprint_of(_brick_id)
	var yaw_steps := int(round(float(yaw) / 90.0)) % 4
	for c in _grid.footprint_cells(cell, fp, yaw_steps):
		if not _grid.in_bounds(c):
			return false
		if _layout.has_cell(c):
			## Footprint would eat a neighbour — mount on the clicked empty? fail soft.
			return false
	return _layout.place_footprint(cell, _brick_id, yaw, _grid, {"text": text})


func _try_place_light(cell: Vector3i) -> bool:
	## Lights mount onto existing walls/blocks — cone gizmo shows aim (45° yaw).
	if cell.x < 0 or _grid == null:
		return false
	var yaw := BrickLayout.norm_yaw_step(_yaw, BrickCatalog.yaw_step_of(_brick_id))
	_yaw = yaw
	if _layout.has_cell(cell):
		var host := _layout.get_brick(_layout.primary_cell_of(cell))
		var host_id := str(host.get("brick_id", ""))
		if BrickCatalog.has_tag(host_id, "light"):
			_layout.erase_footprint_at(cell)
			return _layout.place_footprint(cell, _brick_id, yaw, _grid)
		return _layout.attach_light(cell, _brick_id, yaw)
	## Empty cell — free-standing fixture.
	var fp := BrickCatalog.footprint_of(_brick_id)
	var yaw_steps := int(round(float(yaw) / 90.0)) % 4
	for c in _grid.footprint_cells(cell, fp, yaw_steps):
		if not _grid.in_bounds(c):
			return false
		if _layout.has_cell(c):
			return false
	return _layout.place_footprint(cell, _brick_id, yaw, _grid)


func _sign_text() -> String:
	if _sign_text_edit != null:
		var t := _sign_text_edit.text.strip_edges()
		if not t.is_empty():
			return t
	if _name_edit != null:
		var n := _name_edit.text.strip_edges()
		if not n.is_empty():
			return n
	return str(BrickCatalog.get_entry("deck_text").get("default_text", "NAME"))


func _placement_legal(cell: Vector3i, brick_id: String, yaw: int) -> bool:
	if cell.x < 0 or _grid == null:
		return false
	var entry := BrickCatalog.get_entry(brick_id)
	if entry.is_empty():
		return false
	if BrickCatalog.has_tag(brick_id, "cargo") or str(entry.get("place_mode", "")) == "rect":
		return cell.y == 0 and _grid.in_bounds(Vector3i(cell.x, 0, cell.z))
	## Signs / lights can mount on existing walls / sit on empty deck.
	if BrickCatalog.has_tag(brick_id, "text") or BrickCatalog.has_tag(brick_id, "light"):
		if bool(entry.get("deck_only", false)) and cell.y != 0:
			return false
		return _grid.in_bounds(cell)
	if bool(entry.get("deck_only", false)) and cell.y != 0:
		return false
	var fp := BrickCatalog.footprint_of(brick_id)
	var use_yaw := yaw
	if _grid.is_partial_bow_cell(cell):
		return (
			BrickCatalog.has_tag(brick_id, "diagonal_plan")
			and fp == Vector3i.ONE
			and not _layout.cargo_contains(cell)
		)
	if bool(entry.get("edge_only", false)):
		if cell.y != 0:
			return false
		use_yaw = _grid.outboard_yaw_degrees(cell, fp, 0)
		var ys := int(round(float(use_yaw) / 90.0)) % 4
		if not _grid.footprint_touches_edge(cell, fp, ys):
			return false
	var yaw_steps := int(round(float(use_yaw) / 90.0)) % 4
	var allow_on_cargo := BrickCatalog.has_tag(brick_id, "text")
	for c in _grid.footprint_cells(cell, fp, yaw_steps):
		if not _grid.in_bounds(c):
			return false
		if not allow_on_cargo and _layout.cargo_contains(c):
			return false
	return true


func _ghost_position_for(cell: Vector3i, brick_id: String, yaw: int) -> Vector3:
	## Mounted lights sit on the host face; everything else uses footprint centre.
	if BrickCatalog.has_tag(brick_id, "light") and _layout.has_cell(cell):
		var host := _layout.get_brick(_layout.primary_cell_of(cell))
		if not BrickCatalog.has_tag(str(host.get("brick_id", "")), "light"):
			return _grid.cell_center_local(cell) + DeckFitout.light_mount_offset(yaw, brick_id)
	return DeckFitout.footprint_center_local(_grid, cell, brick_id, yaw)


func _ghost_yaw_for(cell: Vector3i, brick_id: String) -> int:
	var entry := BrickCatalog.get_entry(brick_id)
	if _grid.is_partial_bow_cell(cell) and BrickCatalog.has_tag(brick_id, "diagonal_plan"):
		return _grid.partial_bow_yaw_degrees(cell)
	if bool(entry.get("edge_only", false)):
		return _grid.outboard_yaw_degrees(cell, BrickCatalog.footprint_of(brick_id), 0)
	return _yaw


func _refresh_ghost_from_mouse() -> void:
	if not is_open() or _vp_host == null:
		return
	_update_ghost_at_screen(_vp_host.get_local_mouse_position())


func _update_ghost_at_screen(screen_pos: Vector2) -> void:
	if not is_open() or _world == null or _grid == null:
		return
	if _tool == Tool.ERASE:
		_clear_ghost()
		return
	var cell := _pick_cell(screen_pos)
	if cell.x < 0:
		_clear_ghost()
		return
	if _is_cargo_tool():
		_update_cargo_ghost(cell)
		return
	var yaw := _ghost_yaw_for(cell, _brick_id)
	var valid := _placement_legal(cell, _brick_id, yaw)
	var sign := _sign_text() if BrickCatalog.has_tag(_brick_id, "text") else ""
	var paint_color := _active_paint_color()
	if (
		_ghost != null and is_instance_valid(_ghost)
		and _ghost_brick_id == _brick_id
		and _ghost_cell == cell
		and _ghost_yaw == yaw
		and _ghost_valid == valid
		and _ghost_color.is_equal_approx(paint_color)
		and str(_ghost.get_meta("sign_text", "")) == sign
	):
		return
	if (
		_ghost != null and is_instance_valid(_ghost)
		and _ghost_brick_id == _brick_id
		and _ghost_valid == valid
		and _ghost_color.is_equal_approx(paint_color)
		and not _is_cargo_tool()
		and str(_ghost.get_meta("sign_text", "")) == sign
		and not BrickCatalog.has_tag(_brick_id, "text")
	):
		_ghost_cell = cell
		_ghost_yaw = yaw
		_ghost.position = _ghost_position_for(cell, _brick_id, yaw)
		_ghost.rotation_degrees = Vector3(0.0, float(yaw), 0.0)
		return
	_clear_ghost()
	_ghost_brick_id = _brick_id
	_ghost_cell = cell
	_ghost_yaw = yaw
	_ghost_valid = valid
	_ghost_color = paint_color
	var ghost_opts: Dictionary = {"preview_mesh": true, "color": paint_color}
	if BrickCatalog.has_tag(_brick_id, "text"):
		ghost_opts["text"] = sign
	if BrickCatalog.has_tag(_brick_id, "light"):
		ghost_opts["show_aim_gizmo"] = true
	_ghost = BrickCatalog.create_visual(_brick_id, ghost_opts)
	_ghost.name = "PlaceGhost"
	_ghost.set_meta("sign_text", sign)
	_apply_aim_gizmo_visibility(_ghost)
	_ghost.position = _ghost_position_for(cell, _brick_id, yaw)
	_ghost.rotation_degrees = Vector3(0.0, float(yaw), 0.0)
	_tint_ghost(_ghost, valid)
	if _boat != null and is_instance_valid(_boat):
		_boat.add_child(_ghost)
	else:
		_world.add_child(_ghost)


func _update_cargo_ghost(cell: Vector3i) -> void:
	var a := _cargo_anchor if _cargo_anchor_set else Vector3i(cell.x, 0, cell.z)
	var b := Vector3i(cell.x, 0, cell.z)
	var zone := BrickLayout.normalize_cargo_rect(a, b)
	var key := "cargo:%d,%d:%d,%d:%s" % [
		BrickLayout.zone_min(zone).x, BrickLayout.zone_min(zone).z,
		BrickLayout.zone_max(zone).x, BrickLayout.zone_max(zone).z,
		str(_cargo_anchor_set),
	]
	var valid := cell.y == 0 and _cargo_rect_placeable(zone)
	if (
		_ghost != null and is_instance_valid(_ghost)
		and str(_ghost.get_meta("cargo_key", "")) == key
		and _ghost_valid == valid
	):
		return
	_clear_ghost()
	_ghost_brick_id = _brick_id
	_ghost_cell = cell
	_ghost_yaw = 0
	_ghost_valid = valid
	_ghost = _make_cargo_zone_visual(zone)
	_ghost.name = "PlaceGhost"
	_ghost.set_meta("cargo_key", key)
	_tint_ghost(_ghost, valid)
	if _boat != null and is_instance_valid(_boat):
		_boat.add_child(_ghost)
	else:
		_world.add_child(_ghost)


func _cargo_rect_placeable(zone: Dictionary) -> bool:
	var mn := BrickLayout.zone_min(zone)
	var mx := BrickLayout.zone_max(zone)
	if _grid == null:
		return false
	for ix in range(mn.x, mx.x + 1):
		for iz in range(mn.z, mx.z + 1):
			var c := Vector3i(ix, 0, iz)
			if not _grid.in_bounds(c):
				return false
			if _layout.has_cell(c):
				return false
	return true


func _make_cargo_zone_visual(zone: Dictionary) -> Node3D:
	var mn := BrickLayout.zone_min(zone)
	var mx := BrickLayout.zone_max(zone)
	var w := float(mx.x - mn.x + 1) * DeckGrid.CELL_M
	var l := float(mx.z - mn.z + 1) * DeckGrid.CELL_M
	var sum := Vector3.ZERO
	var n := 0
	for ix in range(mn.x, mx.x + 1):
		for iz in range(mn.z, mx.z + 1):
			sum += _grid.cell_center_local(Vector3i(ix, 0, iz))
			n += 1
	var root := Node3D.new()
	if n <= 0:
		return root
	var center := sum / float(n)
	center.y = _grid.deck_y + 0.08
	root.position = center
	var plate := MeshBuilder.box(Vector3(w * 0.98, 0.04, l * 0.98), Color(0.40, 0.36, 0.30), 0.95, 0.0)
	root.add_child(plate)
	var hx := w * 0.5
	var hz := l * 0.5
	var arm := clampf(minf(hx, hz) * 0.25, 0.3, 1.2)
	var col := Color(0.95, 0.82, 0.12)
	_cargo_zone_corner(root, -hx, -hz, 1.0, 1.0, arm, 0.12, 0.03, col)
	_cargo_zone_corner(root, hx, -hz, -1.0, 1.0, arm, 0.12, 0.03, col)
	_cargo_zone_corner(root, -hx, hz, 1.0, -1.0, arm, 0.12, 0.03, col)
	_cargo_zone_corner(root, hx, hz, -1.0, -1.0, arm, 0.12, 0.03, col)
	return root


func _tint_ghost(root: Node3D, valid: bool) -> void:
	var tint := Color(0.35, 0.95, 0.55, 0.42) if valid else Color(0.95, 0.28, 0.25, 0.42)
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
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
		return Vector3i(-1, -1, -1)
	var from := _camera.project_ray_origin(screen_pos)
	var dir := _camera.project_ray_normal(screen_pos)
	var plane_y := _grid.deck_y + float(_layer_y) * DeckGrid.CELL_M + 0.05
	if absf(dir.y) < 0.0001:
		return Vector3i(-1, -1, -1)
	var t := (plane_y - from.y) / dir.y
	if t < 0.0:
		return Vector3i(-1, -1, -1)
	var hit := from + dir * t
	var cell := _grid.local_to_cell(hit)
	cell.y = _layer_y
	if not _grid.has_deck_cell(cell):
		return Vector3i(-1, -1, -1)
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

	# Thumbnail plate — baked ImageTexture (live SubViewports in ScrollContainer stay blank).
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
	if _thumb_cache.has(brick_id):
		thumb.texture = _thumb_cache[brick_id] as Texture2D
	# else: baked from _ready once the editor is in the scene tree

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
	if BrickCatalog.has_tag(brick_id, "cargo"):
		size_lbl.text = "Click A → B rectangle on deck"
	elif brick_id == "deck_text":
		size_lbl.text = "Flat on deck  ·  %d×%d m" % [fp.x, fp.z]
	elif brick_id == "wall_text":
		size_lbl.text = "Mounts on wall  ·  rotate to face  ·  erase peels sign first"
	elif BrickCatalog.has_tag(brick_id, "external"):
		size_lbl.text = "Outboard flood  ·  25° down  ·  yaw aims quay / sea"
	elif BrickCatalog.has_tag(brick_id, "work") and BrickCatalog.has_tag(brick_id, "light"):
		size_lbl.text = "Deck flood  ·  45° down  ·  mount high, yaw aims throw"
	elif BrickCatalog.has_tag(brick_id, "light"):
		size_lbl.text = "Mounts on block  ·  rotate 45°  ·  cone shows aim"
	elif BrickCatalog.has_tag(brick_id, "text"):
		size_lbl.text = "Sign  ·  edit text below"
	else:
		size_lbl.text = "%d×%d×%d cells  (%.1f×%.1f×%.1f m)" % [
			fp.x, fp.y, fp.z, sz.x, sz.y, sz.z
		]
	size_lbl.add_theme_font_size_override("font_size", 11)
	size_lbl.add_theme_color_override("font_color", HudStyle.C_LABEL)
	text_col.add_child(size_lbl)

	return row


func _bake_brick_thumbnail(brick_id: String, target: TextureRect) -> void:
	## Off-tree SubViewport → ImageTexture. Avoids blank nested viewports in the item list.
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

	var visual := BrickCatalog.create_visual(brick_id, {
		"preview_mesh": true,
		"text": "NAME" if BrickCatalog.has_tag(brick_id, "text") else "",
	})
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
	var reach := maxf(sz.x, maxf(sz.y, sz.z))
	if brick_id == "hull_ladder":
		reach = maxf(reach, 3.2)
	reach = reach * 1.55 + 0.55
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
	_tool = Tool.PLACE
	_yaw = BrickLayout.norm_yaw_step(_yaw, BrickCatalog.yaw_step_of(id))
	_clear_cargo_anchor()
	if _use_catalog_color:
		_sync_color_picker_from_catalog()
	_refresh_palette_selection()
	_clear_ghost()
	_refresh_ghost_from_mouse()
	if BrickCatalog.has_tag(id, "text") and _sign_text_edit != null:
		_sign_text_edit.grab_focus()
		_sign_text_edit.select_all()


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
	if bool(preset.get("custom", true)) == false:
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
	var mode := "ERASE" if _tool == Tool.ERASE else "PLACE"
	if _tool == Tool.PLACE and _is_cargo_tool():
		mode = "CARGO A" if not _cargo_anchor_set else "CARGO B"
	_layer_lbl.text = "Layer %d  (%.1f m)  ·  showing 0–%d  ·  Yaw %d°  ·  %s" % [
		_layer_y, float(_layer_y) * DeckGrid.CELL_M, _layer_y, _yaw, mode,
	]


func _toggle_light_cones() -> void:
	_show_light_cones = not _show_light_cones
	_refresh_cone_button()
	_apply_all_aim_gizmo_visibility()
	_clear_ghost()
	_refresh_ghost_from_mouse()


func _refresh_cone_button() -> void:
	if _cone_btn == null:
		return
	_cone_btn.text = "Light cones: ON" if _show_light_cones else "Light cones: OFF"


func _apply_aim_gizmo_visibility(root: Node) -> void:
	if root == null:
		return
	var gizmo := root.find_child("AimGizmo", true, false) as Node3D
	if gizmo != null:
		gizmo.visible = _show_light_cones


func _apply_all_aim_gizmo_visibility() -> void:
	for key in _brick_visuals.keys():
		var node: Node = _brick_visuals[key] as Node
		if node != null and is_instance_valid(node):
			_apply_aim_gizmo_visibility(node)


func _clear_layout() -> void:
	_layout.clear()
	_clear_cargo_anchor()
	_sync_brick_visuals()
	_refresh_rules()


func _rebuild_preview() -> void:
	## Build the bare hull once; brick meshes are maintained incrementally afterward.
	_clear_ghost()
	_ensure_editor_boat()
	_sync_brick_visuals()
	_refresh_grid_overlay()
	_update_camera()
	_refresh_ghost_from_mouse()


func _ensure_editor_boat() -> void:
	var want_id := str(_hull_entry.get("id", "workboat"))
	if _boat != null and is_instance_valid(_boat):
		if str(_boat.get_meta("editor_hull_id", "")) == want_id:
			return
		_boat.queue_free()
		_boat = null
		_brick_root = null
	_boat = HullRegistry.build_hull(want_id)
	_boat.name = "EditorBoat"
	_boat.set_meta("editor_hull_id", want_id)
	# Skip deferred gameplay fit-out / WalkDeck brick colliders in the editor.
	_boat.set_meta("fitout_applied", true)
	for child_name in ["BoatController", "BoatCamera", "BoatAudio"]:
		var n := _boat.get_node_or_null(child_name)
		if n != null:
			n.queue_free()
	_world.add_child(_boat)
	## After enter-tree, BoatBody LOD would flip freeze off and buoyancy lifts the hull.
	_boat.automatic_physics_lod = false
	_boat.set_physics_quality(BoatBody.PhysicsQuality.SLEEP)
	_boat.global_position = Vector3.ZERO


func _ensure_brick_root() -> void:
	if _boat == null or not is_instance_valid(_boat):
		_brick_root = null
		return
	_brick_root = _boat.get_node_or_null(EDITOR_BRICK_ROOT) as Node3D
	if _brick_root == null:
		_brick_root = Node3D.new()
		_brick_root.name = EDITOR_BRICK_ROOT
		_boat.add_child(_brick_root)


func _sync_brick_visuals() -> void:
	_ensure_editor_boat()
	_ensure_brick_root()
	if _brick_root == null or _grid == null:
		return

	var wanted: Dictionary = {} ## key → { cell, brick_id, yaw, text, is_sign? }
	for item in _layout.iter_primary_cells():
		var cell: Vector3i = item["cell"]
		var brick_id := str(item.get("brick_id", ""))
		wanted[BrickLayout.cell_key(cell)] = item
		var sign_id := str(item.get("sign_id", ""))
		if BrickCatalog.has(sign_id) and BrickCatalog.has_tag(sign_id, "text"):
			wanted["sign:%s" % BrickLayout.cell_key(cell)] = {
				"cell": cell,
				"brick_id": sign_id,
				"yaw": int(item.get("sign_yaw", 0)),
				"text": str(item.get("text", "")),
				"is_sign": true,
			}
		var light_id := str(item.get("light_id", ""))
		if BrickCatalog.has(light_id) and BrickCatalog.has_tag(light_id, "light"):
			wanted["light:%s" % BrickLayout.cell_key(cell)] = {
				"cell": cell,
				"brick_id": light_id,
				"yaw": int(item.get("light_yaw", 0)),
				"text": "",
				"is_light": true,
			}

	var stale: Array[String] = []
	for key in _brick_visuals.keys():
		var k := str(key)
		if not wanted.has(k):
			stale.append(k)
			continue
		var node: Node3D = _brick_visuals[k]
		if node == null or not is_instance_valid(node):
			stale.append(k)
			continue
		var want: Dictionary = wanted[k]
		var want_id := str(want.get("brick_id", ""))
		var want_yaw := int(want.get("yaw", 0))
		var want_text := str(want.get("text", ""))
		var want_color := BrickLayout.color_from_entry(want, want_id)
		var want_color_key := "%.3f,%.3f,%.3f" % [want_color.r, want_color.g, want_color.b]
		if (
			str(node.get_meta("brick_id", "")) != want_id
			or int(node.get_meta("yaw", 0)) != want_yaw
			or str(node.get_meta("sign_text", "")) != want_text
			or str(node.get_meta("color_key", "")) != want_color_key
		):
			stale.append(k)

	for k in stale:
		var old: Variant = _brick_visuals.get(k, null)
		_brick_visuals.erase(k)
		if old is Node and is_instance_valid(old as Node):
			(old as Node).queue_free()

	for key in wanted.keys():
		var k := str(key)
		if _brick_visuals.has(k):
			continue
		var item: Dictionary = wanted[k]
		var cell: Vector3i = item["cell"]
		var brick_id := str(item.get("brick_id", ""))
		var yaw := int(item.get("yaw", 0))
		if not BrickCatalog.has(brick_id):
			continue
		var color := BrickLayout.color_from_entry(item, brick_id)
		var color_key := "%.3f,%.3f,%.3f" % [color.r, color.g, color.b]
		var opts: Dictionary = {"color": color}
		if BrickCatalog.has_tag(brick_id, "text"):
			opts["text"] = str(item.get("text", ""))
		if BrickCatalog.has_tag(brick_id, "light"):
			opts["show_aim_gizmo"] = true
		var visual := BrickCatalog.create_visual(brick_id, opts)
		visual.name = "%s_%d_%d_%d" % [brick_id, cell.x, cell.y, cell.z]
		visual.set_meta("brick_id", brick_id)
		visual.set_meta("yaw", yaw)
		visual.set_meta("sign_text", str(item.get("text", "")))
		visual.set_meta("color_key", color_key)
		visual.set_meta("cell_y", cell.y)
		_apply_aim_gizmo_visibility(visual)
		if bool(item.get("is_sign", false)):
			visual.position = _grid.cell_center_local(cell)
		elif bool(item.get("is_light", false)):
			visual.position = _grid.cell_center_local(cell) + DeckFitout.light_mount_offset(yaw, brick_id)
		else:
			visual.position = DeckFitout.footprint_center_local(_grid, cell, brick_id, yaw)
		visual.rotation_degrees = Vector3(0.0, float(yaw), 0.0)
		_brick_root.add_child(visual)
		_brick_visuals[k] = visual

	_refresh_cargo_zone_preview(_layout.iter_cargo_zones())
	_apply_layer_visibility()


func _refresh_cargo_zone_preview(zones: Array) -> void:
	## One pad + yellow corner brackets per cargo rect.
	if _brick_root == null:
		return
	var existing := _brick_root.get_node_or_null("CargoZonePreview")
	if existing != null:
		_brick_root.remove_child(existing)
		existing.free()
	if zones.is_empty() or _grid == null:
		return

	var root := Node3D.new()
	root.name = "CargoZonePreview"
	_brick_root.add_child(root)

	for zone_v in zones:
		var zone := zone_v as Dictionary
		var mn := BrickLayout.zone_min(zone)
		var mx := BrickLayout.zone_max(zone)
		var w := float(mx.x - mn.x + 1) * DeckGrid.CELL_M
		var l := float(mx.z - mn.z + 1) * DeckGrid.CELL_M
		var sum := Vector3.ZERO
		var n := 0
		for ix in range(mn.x, mx.x + 1):
			for iz in range(mn.z, mx.z + 1):
				sum += _grid.cell_center_local(Vector3i(ix, 0, iz))
				n += 1
		if n <= 0:
			continue
		var center := sum / float(n)
		center.y = _grid.deck_y + 0.06
		var pad := Node3D.new()
		pad.position = center
		root.add_child(pad)
		var plate := MeshBuilder.box(Vector3(w * 0.995, 0.03, l * 0.995), Color(0.32, 0.30, 0.26), 0.95, 0.0)
		plate.position = Vector3(0.0, -0.01, 0.0)
		pad.add_child(plate)
		var hx := w * 0.5
		var hz := l * 0.5
		var arm := clampf(minf(hx, hz) * 0.25, 0.3, 1.2)
		var thick := 0.12
		var h := 0.02
		var col := Color(0.95, 0.82, 0.12)
		_cargo_zone_corner(pad, -hx, -hz, 1.0, 1.0, arm, thick, h, col)
		_cargo_zone_corner(pad, hx, -hz, -1.0, 1.0, arm, thick, h, col)
		_cargo_zone_corner(pad, -hx, hz, 1.0, -1.0, arm, thick, h, col)
		_cargo_zone_corner(pad, hx, hz, -1.0, -1.0, arm, thick, h, col)


func _cargo_zone_corner(
	root: Node3D,
	cx: float,
	cz: float,
	sx: float,
	sz: float,
	arm: float,
	thick: float,
	h: float,
	color: Color,
) -> void:
	var a := MeshBuilder.box(Vector3(arm, h, thick), color, 0.85, 0.0)
	a.position = Vector3(cx + sx * arm * 0.5, h * 0.5, cz)
	root.add_child(a)
	var b := MeshBuilder.box(Vector3(thick, h, arm), color, 0.85, 0.0)
	b.position = Vector3(cx, h * 0.5, cz + sz * arm * 0.5)
	root.add_child(b)


func _clear_preview() -> void:
	_clear_ghost()
	_brick_visuals.clear()
	_brick_root = null
	if _boat != null and is_instance_valid(_boat):
		_boat.queue_free()
	_boat = null
	if _grid_overlay != null and is_instance_valid(_grid_overlay):
		_grid_overlay.queue_free()
	_grid_overlay = null


func _refresh_grid_overlay() -> void:
	if _grid_overlay != null and is_instance_valid(_grid_overlay):
		_grid_overlay.queue_free()
	_grid_overlay = Node3D.new()
	_grid_overlay.name = "GridOverlay"
	_world.add_child(_grid_overlay)
	if _grid == null:
		return

	var y := _grid.deck_y + float(_layer_y) * DeckGrid.CELL_M + 0.04
	var half_x := _grid.half_beam
	var half_z := _grid.half_loa
	var cell := DeckGrid.CELL_M

	# Soft deck wash follows the actual buildable hull plan.
	var wash: MeshInstance3D
	if _grid.bow_taper_cells > 0:
		wash = MeshBuilder.pointed_deck_plate(
			float(_grid.length) * cell,
			float(_grid.width) * cell,
			y - 0.015,
			0.01,
			float(_grid.bow_taper_cells) / float(_grid.length),
			Color(0.15, 0.45, 0.75, 0.12),
			1.0,
		)
	else:
		wash = MeshBuilder.box(
			Vector3(float(_grid.width) * cell, 0.01, float(_grid.length) * cell),
			Color(0.15, 0.45, 0.75, 0.12),
			1.0,
			0.0,
		)
		wash.position = Vector3(0.0, y - 0.02, 0.0)
	var wash_mat := wash.material_override as StandardMaterial3D
	if wash_mat != null:
		wash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		wash_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_grid_overlay.add_child(wash)

	# 1 m cell lines.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	var line_col := Color(0.55, 0.85, 1.0, 0.85)
	if _grid.bow_taper_cells <= 0:
		for ix in range(_grid.width + 1):
			var x := -half_x + float(ix) * cell
			st.set_color(line_col)
			st.add_vertex(Vector3(x, y, -half_z))
			st.set_color(line_col)
			st.add_vertex(Vector3(x, y, half_z))
		for iz in range(_grid.length + 1):
			var z := -half_z + float(iz) * cell
			st.set_color(line_col)
			st.add_vertex(Vector3(-half_x, y, z))
			st.set_color(line_col)
			st.add_vertex(Vector3(half_x, y, z))
	else:
		## Draw full squares and exact triangular half-cells at the 45° bow.
		for iz in range(_grid.length):
			for ix in range(_grid.width):
				var shape := _grid.cell_shape(ix, iz)
				if shape == DeckGrid.CellShape.NONE:
					continue
				var x0 := -half_x + float(ix) * cell
				var x1 := x0 + cell
				var z0 := -half_z + float(iz) * cell
				var z1 := z0 + cell
				var corners: Array[Vector3]
				match shape:
					DeckGrid.CellShape.BOW_PORT_HALF:
						corners = [Vector3(x1, y, z0), Vector3(x1, y, z1), Vector3(x0, y, z1)]
					DeckGrid.CellShape.BOW_STARBOARD_HALF:
						corners = [Vector3(x0, y, z0), Vector3(x1, y, z1), Vector3(x0, y, z1)]
					_:
						corners = [
							Vector3(x0, y, z0), Vector3(x1, y, z0),
							Vector3(x1, y, z1), Vector3(x0, y, z1),
						]
				for i in range(corners.size()):
					st.set_color(line_col)
					st.add_vertex(corners[i])
					st.set_color(line_col)
					st.add_vertex(corners[(i + 1) % corners.size()])
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var line_mat := StandardMaterial3D.new()
	line_mat.vertex_color_use_as_albedo = true
	line_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_mat.albedo_color = Color(1, 1, 1, 1)
	mi.material_override = line_mat
	_grid_overlay.add_child(mi)

	# Outer border thicker (second pass slightly elevated).
	var border := SurfaceTool.new()
	border.begin(Mesh.PRIMITIVE_LINES)
	var edge := Color(1.0, 0.78, 0.25, 1.0)
	var yb := y + 0.01
	var corners: Array[Vector3] = []
	if _grid.bow_taper_cells > 0:
		var shoulder_z := -half_z + float(_grid.bow_taper_cells) * cell
		corners = [
			Vector3(0.0, yb, -half_z), Vector3(half_x, yb, shoulder_z),
			Vector3(half_x, yb, shoulder_z), Vector3(half_x, yb, half_z),
			Vector3(half_x, yb, half_z), Vector3(-half_x, yb, half_z),
			Vector3(-half_x, yb, half_z), Vector3(-half_x, yb, shoulder_z),
			Vector3(-half_x, yb, shoulder_z), Vector3(0.0, yb, -half_z),
		]
	else:
		corners = [
			Vector3(-half_x, yb, -half_z), Vector3(half_x, yb, -half_z),
			Vector3(half_x, yb, -half_z), Vector3(half_x, yb, half_z),
			Vector3(half_x, yb, half_z), Vector3(-half_x, yb, half_z),
			Vector3(-half_x, yb, half_z), Vector3(-half_x, yb, -half_z),
		]
	for i in range(0, corners.size(), 2):
		border.set_color(edge)
		border.add_vertex(corners[i])
		border.set_color(edge)
		border.add_vertex(corners[i + 1])
	var border_mi := MeshInstance3D.new()
	border_mi.mesh = border.commit()
	var border_mat := StandardMaterial3D.new()
	border_mat.vertex_color_use_as_albedo = true
	border_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	border_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	border_mi.material_override = border_mat
	_grid_overlay.add_child(border_mi)

	_add_build_face_labels()
	_add_scale_figure()


func _add_scale_figure() -> void:
	## Real player mesh at WorldUnits.PLAYER_HEIGHT_M so deck cells can be eyeballed.
	if _grid == null or _grid_overlay == null:
		return
	var h := WorldUnits.PLAYER_HEIGHT_M
	var root := Node3D.new()
	root.name = "ScaleFigure"
	# Starboard midships, just outside the deck edge.
	root.position = Vector3(_grid.half_beam + 0.85, _grid.deck_y, 0.0)
	_grid_overlay.add_child(root)

	var npc := NpcBase.new()
	npc.name = "PlayerDummy"
	# Mesh authored facing +Z; stand outside starboard facing the hull (−X).
	npc.rotation.y = PI * 0.5
	root.add_child(npc)

	# Vertical height pole — exact metres, ticks every 0.5 m.
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

	# One-metre stick on the deck (= one cell) — vertical for easy compare to the dummy.
	var stick := MeshBuilder.box(
		Vector3(0.08, 1.0, 0.08),
		Color(0.95, 0.2, 0.15, 0.95),
		0.5,
		0.0,
	)
	stick.position = Vector3(_grid.half_beam - 0.35, _grid.deck_y + 0.5, 0.55)
	_grid_overlay.add_child(stick)
	var stick_lbl := Label3D.new()
	stick_lbl.text = "1 m"
	stick_lbl.font_size = 40
	stick_lbl.pixel_size = 0.004
	stick_lbl.position = stick.position + Vector3(0.0, 0.7, 0.0)
	stick_lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	stick_lbl.modulate = Color(0.95, 0.35, 0.3, 0.9)
	stick_lbl.outline_size = 5
	_grid_overlay.add_child(stick_lbl)


func _add_build_face_labels() -> void:
	## Build-editor only orientation cues (not on the live vessel).
	if _grid == null or _grid_overlay == null:
		return
	var y := _grid.deck_y + 0.08
	var inset := 0.35
	var labels := [
		{"text": "BOW", "pos": Vector3(0.0, y, -_grid.half_loa - inset)},
		{"text": "STERN", "pos": Vector3(0.0, y, _grid.half_loa + inset)},
		{"text": "PORT", "pos": Vector3(-_grid.half_beam - inset, y, 0.0)},
		{"text": "STARBOARD", "pos": Vector3(_grid.half_beam + inset, y, 0.0)},
	]
	for spec in labels:
		var label := Label3D.new()
		label.name = "BuildFace_%s" % str(spec["text"])
		label.text = str(spec["text"])
		label.position = spec["pos"] as Vector3
		label.font_size = 28
		label.pixel_size = 0.008
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.modulate = Color(0.75, 0.82, 0.90, 0.45)
		label.outline_modulate = Color(0.02, 0.04, 0.06, 0.35)
		label.outline_size = 4
		label.no_depth_test = true
		_grid_overlay.add_child(label)


func _update_camera() -> void:
	if _camera == null:
		return
	var yaw_r := deg_to_rad(_cam_yaw)
	var pitch_r := deg_to_rad(_cam_pitch)
	var target := _cam_target
	var offset := Vector3(
		_cam_dist * cos(pitch_r) * sin(yaw_r),
		_cam_dist * -sin(pitch_r),
		_cam_dist * cos(pitch_r) * cos(yaw_r),
	)
	_camera.global_position = target + offset
	_camera.look_at(target, Vector3.UP)


func _refresh_rules() -> void:
	_refresh_palette_selection()
	if _grid == null:
		return
	var report := BrickRules.validate(_layout, _grid)
	if _layout.is_empty():
		_rules_lbl.text = "Free build — 1.0 m cells. Place anything."
	else:
		_rules_lbl.text = "Free build — no constraints."
	var caps: Dictionary = report.get("capabilities", {})
	_caps_lbl.text = (
		"Cargo cells: %d\nHelm: %s\nCabin: %s\nShip crane: %s\nParts: %d"
		% [
			int(caps.get("cargo_cells", 0)),
			"yes" if bool(caps.get("has_helm", false)) else "no",
			"yes" if bool(caps.get("has_cabin", false)) else "no",
			"yes" if bool(caps.get("has_crane", false)) else "no",
			int(caps.get("brick_count", 0)),
		]
	)
	_confirm_btn.disabled = false


func _on_confirm() -> void:
	if _authoring_mode or standalone_tool:
		_on_dev_save_prebuilt()
		return
	var vessel_name := _name_edit.text.strip_edges()
	if vessel_name.is_empty():
		vessel_name = VesselSpawn.vessel_name_of({
			"name": "",
			"display": str(_hull_entry.get("display", "Vessel")),
		})
	layout_confirmed.emit(
		_hull_entry.duplicate(true),
		_layout.to_dict(),
		vessel_name,
		_editing_uid,
	)


func _on_dev_save_prebuilt() -> void:
	var vessel_name := _name_edit.text.strip_edges()
	if vessel_name.is_empty():
		vessel_name = str(_hull_entry.get("display", _layout.hull_id))
	var preset_id := _authoring_prebuilt_id.strip_edges()
	if preset_id.is_empty():
		preset_id = _prebuilt_slug(vessel_name)
	if preset_id.is_empty():
		preset_id = "%s_prebuilt" % _prebuilt_slug(_layout.hull_id)
	var payload := make_prebuilt_payload(
		preset_id,
		vessel_name,
		_hull_entry,
		_layout.to_dict(),
	)
	var absolute_dir := ProjectSettings.globalize_path(PREBUILT_DIR)
	var err := DirAccess.make_dir_recursive_absolute(absolute_dir)
	if err != OK and err != ERR_ALREADY_EXISTS:
		_show_dev_save_result("SAVE FAILED · could not create preset folder", true)
		push_error("ShipyardBrickEditor: could not create %s (err %d)" % [PREBUILT_DIR, err])
		return
	var path := "%s/%s.json" % [PREBUILT_DIR, preset_id]
	var temp_path := path + ".tmp"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		_show_dev_save_result("SAVE FAILED · res:// is not writable", true)
		push_error("ShipyardBrickEditor: could not write %s (err %d)" % [
			temp_path, FileAccess.get_open_error(),
		])
		return
	file.store_string(JSON.stringify(payload, "\t"))
	file.flush()
	file.close()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(temp_path))
	if typeof(parsed) != TYPE_DICTIONARY:
		DirAccess.remove_absolute(temp_path)
		_show_dev_save_result("SAVE FAILED · generated JSON did not validate", true)
		return
	if FileAccess.file_exists(path):
		err = DirAccess.remove_absolute(path)
		if err != OK:
			DirAccess.remove_absolute(temp_path)
			_show_dev_save_result("SAVE FAILED · existing preset is locked", true)
			return
	err = DirAccess.rename_absolute(temp_path, path)
	if err != OK:
		_show_dev_save_result("SAVE FAILED · could not install preset", true)
		return
	_authoring_prebuilt_id = preset_id
	_populate_prebuilt_option(preset_id)
	_show_dev_save_result("SAVED · %s" % path, false)
	print("[Shipyard] Saved official prebuilt preset: %s" % ProjectSettings.globalize_path(path))


static func make_prebuilt_payload(
	preset_id: String,
	vessel_name: String,
	hull_entry: Dictionary,
	layout: Dictionary,
) -> Dictionary:
	var hull_id := str(layout.get("hull_id", hull_entry.get("id", "workboat")))
	var scene_path := str(hull_entry.get("scene_path", HullRegistry.scene_path_for(hull_id)))
	return {
		"format_version": PREBUILT_FORMAT_VERSION,
		"id": preset_id,
		"name": vessel_name,
		"hull_id": hull_id,
		"scene_path": scene_path,
		"price_marks": maxi(int(hull_entry.get("price_marks", 0)), 0),
		"brick_layout": layout.duplicate(true),
	}


static func _prebuilt_slug(value: String) -> String:
	var out := ""
	var lowered := value.strip_edges().to_lower()
	for i in range(lowered.length()):
		var code := lowered.unicode_at(i)
		var is_letter := code >= 97 and code <= 122
		var is_number := code >= 48 and code <= 57
		if is_letter or is_number:
			out += lowered[i]
		elif not out.is_empty() and not out.ends_with("_"):
			out += "_"
	return out.trim_suffix("_")


func _show_dev_save_result(message: String, failed: bool) -> void:
	if _dev_save_lbl == null:
		return
	_dev_save_lbl.text = message
	_dev_save_lbl.add_theme_color_override(
		"font_color",
		HudStyle.C_RED if failed else HudStyle.C_GREEN,
	)
