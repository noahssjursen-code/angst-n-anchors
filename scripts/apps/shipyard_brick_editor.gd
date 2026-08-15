class_name ShipyardBrickEditor
extends CanvasLayer

## Deck-grid brick painter for official hulls.
## Run `scenes/apps/shipyard_brick_editor.tscn` as an engine app to author
## `resources/data/vessels/prebuilt/*.json`. Shipwright sells those presets in-game.

signal closed
signal layout_confirmed(
	hull_entry: Dictionary,
	layout: Dictionary,
	vessel_name: String,
	editing_uid: String,
	registration_id: String,
)

enum Tool { PLACE = 0, ERASE = 1, MARK = 2 }

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
var _brick_id: String = "" ## empty until the rebuilt catalog has entries
var _tool: int = Tool.PLACE
var _painting := false
var _last_paint_cell: Vector3i = Vector3i(-999, -999, -999)
## Container-pad rect tool: corner A, then corner B.
var _rect_anchor: Vector3i = Vector3i(-999, -999, -999)
var _rect_anchor_set := false
var _paint_color := Color(0.78, 0.80, 0.84)
var _use_catalog_color := true
## Mark region for copy/paste: click A, then B (3D box — change layer between clicks).
var _mark_anchor: Vector3i = Vector3i(-999, -999, -999)
var _mark_anchor_set := false
var _mark_complete := false
var _mark_min := Vector3i.ZERO
var _mark_max := Vector3i.ZERO
var _clipboard: Dictionary = {}
var _clipboard_src_min := Vector3i.ZERO
var _thumb_cache: Dictionary = {} ## brick_id → ImageTexture

var _root: Control
var _viewport: SubViewport
var _world: Node3D
var _boat: BoatBody
var _brick_root: Node3D
var _brick_visuals: Dictionary = {} ## cell_key → Node3D
var _grid_overlay: Node3D
var _ghost: Node3D
var _mark_preview: Node3D
var _ghost_brick_id: String = ""
var _ghost_cell: Vector3i = Vector3i(-999, -999, -999)
var _ghost_yaw: int = -1
var _ghost_valid: bool = false
var _ghost_color := Color(0, 0, 0, 0)
const EDITOR_BRICK_ROOT := "EditorBricks"
const PREBUILT_DIR := "res://resources/data/vessels/prebuilt"
const PREBUILT_FORMAT_VERSION := 2
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
var _hint_lbl: Label
var _rules_lbl: Label
var _caps_lbl: Label
var _layer_lbl: Label
var _name_edit: LineEdit
var _price_edit: LineEdit
var _power_edit: LineEdit
var _registration_option: OptionButton
var _registration_id: String = ""
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
var _palette_search: LineEdit
var _palette_category: OptionButton
var _palette_empty_lbl: Label
var _context_drawer: PanelContainer
var _context_title: Label
var _context_info: Label
var _color_section: VBoxContainer
var _sign_section: VBoxContainer
var _light_section: VBoxContainer
var _clipboard_section: VBoxContainer
var _tool_place_btn: Button
var _tool_erase_btn: Button
var _tool_mark_btn: Button
var _ship_dialog: PanelContainer
var _authoring_section: VBoxContainer
var _help_overlay: PanelContainer
var _clear_confirm: PanelContainer
var _toast_lbl: Label
var _toast_until_msec: int = 0
const THUMB_PX := 64
const MAX_VESSEL_NAME_LEN := 28
const PREBUILT_BLANK_META := "__blank__"
const PALETTE_CATEGORIES := ["All", "Structure", "Openings", "Deck", "Equipment", "Lights", "Signs"]


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
	return row.find_child("Thumb", true, false) as TextureRect


func is_open() -> bool:
	return _root != null and _root.visible


func _boot_standalone_tool() -> void:
	_authoring_mode = true
	_refresh_authoring_chrome()
	var title := _root.find_child("TitleLabel", true, false) as Label
	if title != null:
		title.text = "PREBUILT AUTHORING"
	_status_lbl.text = (
		"Load an existing prebuilt or start blank on a hull.\n"
		+ "Save overwrites the loaded preset id (or creates from the vessel name).\n"
		+ "Incomplete legal checklists can still Save as draft (not sold by the Shipwright).\n"
		+ "LMB place · RMB orbit · MMB pan · Scroll zoom · [ ] layer · R rotate · X erase\n"
		+ "M mark A→B · Ctrl+C copy · Ctrl+V paste"
	)
	_confirm_btn.text = "Save official prebuilt JSON"
	_back_btn.text = "Quit tool"
	var hull_hint := Label.new()
	hull_hint.text = "Hull (blank)"
	hull_hint.add_theme_font_size_override("font_size", 11)
	hull_hint.add_theme_color_override("font_color", BrandTokens.INK_INVERSE_DIM)
	_hull_option.get_parent().add_child(hull_hint)
	_hull_option.get_parent().move_child(hull_hint, _hull_option.get_index())
	var pre_hint := Label.new()
	pre_hint.text = "Load existing prebuilt"
	pre_hint.add_theme_font_size_override("font_size", 11)
	pre_hint.add_theme_color_override("font_color", BrandTokens.INK_INVERSE_DIM)
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
		if bool(entry.get("is_draft", false)):
			label = "[DRAFT] " + label
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
	var hull_id := str(entry.get("hull_id", entry.get("id", ""))).strip_edges()
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
	open_for_authoring(
		hull,
		layout,
		vessel_name,
		str(entry.get("registration_id", "")),
	)
	_set_price_field(int(entry.get("price_marks", hull.get("price_marks", 0))))
	_set_power_field(float(entry.get(
		"shaft_power_kw",
		hull.get("default_shaft_power_kw", 1.0)
	)))
	if _dev_save_lbl != null:
		var draft_note := " · DRAFT" if bool(entry.get("is_draft", false)) else ""
		_dev_save_lbl.text = "Loaded%s · %s" % [
			draft_note,
			str(entry.get("prebuilt_path", _authoring_prebuilt_id)),
		]
		_dev_save_lbl.add_theme_color_override(
			"font_color",
			BrandTokens.BRASS if bool(entry.get("is_draft", false)) else BrandTokens.INK_INVERSE_DIM,
		)
	_show_toast("Loaded %s" % vessel_name)


func open_for_authoring(
	hull_entry: Dictionary,
	existing_layout: Dictionary = {},
	vessel_name: String = "",
	registration_id: String = "",
) -> void:
	_authoring_mode = true
	_refresh_authoring_chrome()
	var name := vessel_name.strip_edges()
	if name.is_empty():
		name = str(hull_entry.get("display", ""))
	open_for_hull(hull_entry, existing_layout, "", name, registration_id)


func _refresh_authoring_chrome() -> void:
	var authoring := _authoring_mode or standalone_tool
	if _authoring_section != null:
		_authoring_section.visible = authoring
	if _price_edit != null:
		_price_edit.visible = authoring
	if _power_edit != null:
		_power_edit.visible = authoring
	var price_header := _root.find_child("PriceHeader", true, false) as Control
	if price_header != null:
		price_header.visible = authoring
	var power_header := _root.find_child("PowerHeader", true, false) as Control
	if power_header != null:
		power_header.visible = authoring


func open_for_hull(
	hull_entry: Dictionary,
	existing_layout: Dictionary = {},
	editing_uid: String = "",
	vessel_name: String = "",
	registration_id: String = "",
) -> void:
	_hull_entry = hull_entry.duplicate(true)
	_editing_uid = editing_uid.strip_edges()
	var hull_id := str(hull_entry.get("id", "fishing_trawler_small"))
	_grid = HullRegistry.make_grid(hull_id)
	_layout = BrickLayout.new()
	_layout.hull_id = hull_id
	_registration_id = registration_id.strip_edges()
	_select_registration_option(_registration_id)
	# Only restore a prior layout when explicitly passed — never auto-configure.
	if not existing_layout.is_empty():
		_layout = BrickLayout.from_dict(existing_layout)
	_layer_y = 0
	_yaw = 0
	_brick_id = BrickCatalog.BRICKS.keys()[0] if not BrickCatalog.BRICKS.is_empty() else ""
	_tool = Tool.PLACE
	_clear_mark()
	_clear_mark_preview()
	## Hull change must rebuild the editor boat for the selected dimensions.
	if _boat != null and is_instance_valid(_boat):
		_boat.queue_free()
		_boat = null
		_brick_root = null
		_brick_visuals.clear()
		_clear_mark_preview()
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
	_set_price_field(int(hull_entry.get("price_marks", 0)))
	_set_power_field(float(hull_entry.get("default_shaft_power_kw", 1.0)))
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
	_root.theme = BrandTheme.shared()
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
	_build_ship_dialog()
	_build_help_overlay()
	_build_clear_confirmation()


func _build_top_bar(parent: VBoxContainer) -> void:
	var panel := BrandComponents.inner_panel()
	panel.name = "TopBar"
	panel.custom_minimum_size.y = 54.0
	parent.add_child(panel)

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	panel.add_child(bar)

	var title := Label.new()
	title.name = "TitleLabel"
	title.text = "VESSEL BUILDER"
	BrandTheme.apply_display_font(title, 24, BrandTokens.BRASS)
	bar.add_child(title)

	var rule := VSeparator.new()
	rule.custom_minimum_size.x = 1.0
	bar.add_child(rule)

	_hull_lbl = Label.new()
	_hull_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hull_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	BrandTheme.apply_body_font(_hull_lbl, 13, BrandTokens.INK_INVERSE_DIM)
	bar.add_child(_hull_lbl)

	var ship_btn := BrandComponents.compact_button("Ship", 70)
	ship_btn.tooltip_text = "Vessel metadata, validation and authoring options"
	ship_btn.pressed.connect(_toggle_ship_dialog)
	bar.add_child(ship_btn)

	var help_btn := BrandComponents.compact_button("?", 36)
	help_btn.tooltip_text = "Controls and shortcuts"
	help_btn.pressed.connect(_toggle_help_overlay)
	bar.add_child(help_btn)

	_confirm_btn = BrandComponents.compact_button("Confirm", 112)
	_confirm_btn.pressed.connect(_on_confirm)
	bar.add_child(_confirm_btn)

	_back_btn = BrandComponents.compact_button("Back", 70)
	_back_btn.pressed.connect(_close)
	bar.add_child(_back_btn)


func _build_palette(parent: HBoxContainer) -> void:
	var side := BrandComponents.panel(Vector2(292, 0))
	side.name = "PartsPalette"
	side.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(side)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	side.add_child(col)

	var heading := HBoxContainer.new()
	col.add_child(heading)
	var title := BrandComponents.section_header("PARTS")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	var count := Label.new()
	count.name = "PaletteCount"
	count.text = str(BrickCatalog.ids().size())
	count.add_theme_color_override("font_color", BrandTokens.INK_INVERSE_DIM)
	heading.add_child(count)

	_palette_search = LineEdit.new()
	_palette_search.name = "PaletteSearch"
	_palette_search.placeholder_text = "Search parts…"
	_palette_search.clear_button_enabled = true
	_palette_search.text_changed.connect(func(_text: String) -> void: _filter_palette())
	col.add_child(_palette_search)

	_palette_category = OptionButton.new()
	_palette_category.name = "PaletteCategory"
	for category in PALETTE_CATEGORIES:
		_palette_category.add_item(category)
	_palette_category.item_selected.connect(func(_index: int) -> void: _filter_palette())
	col.add_child(_palette_category)

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
	for id in BrickCatalog.ids():
		var row := _make_item_row(id)
		grid.add_child(row)
		_brick_rows[id] = row

	_palette_empty_lbl = BrandComponents.subtitle_label("No matching parts", 12)
	_palette_empty_lbl.visible = false
	col.add_child(_palette_empty_lbl)


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
	var strip := BrandComponents.inner_panel()
	strip.name = "ContextStrip"
	strip.custom_minimum_size.y = 48.0
	parent.add_child(strip)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	strip.add_child(row)

	_tool_place_btn = BrandComponents.tool_button("Place")
	_tool_place_btn.pressed.connect(func() -> void: _set_tool(Tool.PLACE))
	row.add_child(_tool_place_btn)
	_tool_erase_btn = BrandComponents.tool_button("Erase")
	_tool_erase_btn.pressed.connect(func() -> void: _set_tool(Tool.ERASE))
	row.add_child(_tool_erase_btn)
	_tool_mark_btn = BrandComponents.tool_button("Select")
	_tool_mark_btn.pressed.connect(func() -> void: _set_tool(Tool.MARK))
	row.add_child(_tool_mark_btn)

	var rotate := BrandComponents.compact_button("Rotate  R", 86)
	rotate.pressed.connect(func() -> void:
		_rotate_yaw()
		_refresh_rules()
		_refresh_ghost_from_mouse()
	)
	row.add_child(rotate)

	var layer_down := BrandComponents.compact_button("−", 34)
	layer_down.tooltip_text = "Previous layer ([)"
	layer_down.pressed.connect(func() -> void: _set_layer_y(_layer_y - 1))
	row.add_child(layer_down)

	_layer_lbl = Label.new()
	_layer_lbl.custom_minimum_size.x = 92.0
	_layer_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_layer_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	BrandTheme.apply_body_font(_layer_lbl, 12, BrandTokens.INK_INVERSE, true)
	row.add_child(_layer_lbl)

	var layer_up := BrandComponents.compact_button("+", 34)
	layer_up.tooltip_text = "Next layer (])"
	layer_up.pressed.connect(func() -> void: _set_layer_y(_layer_y + 1))
	row.add_child(layer_up)

	_hint_lbl = Label.new()
	_hint_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hint_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hint_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	BrandTheme.apply_body_font(_hint_lbl, 12, BrandTokens.INK_INVERSE_DIM)
	row.add_child(_hint_lbl)

	_toast_lbl = Label.new()
	_toast_lbl.visible = false
	_toast_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_toast_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	BrandTheme.apply_body_font(_toast_lbl, 12, BrandTokens.OK_LIGHT, true)
	row.add_child(_toast_lbl)


func _build_context_drawer(parent: HBoxContainer) -> void:
	_context_drawer = BrandComponents.panel(Vector2(272, 0))
	_context_drawer.name = "PropertiesDrawer"
	_context_drawer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(_context_drawer)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	_context_drawer.add_child(col)
	_context_title = BrandComponents.section_header("PROPERTIES")
	col.add_child(_context_title)
	_context_info = Label.new()
	_context_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	BrandTheme.apply_body_font(_context_info, 12, BrandTokens.INK_INVERSE_DIM)
	col.add_child(_context_info)

	_color_section = VBoxContainer.new()
	_color_section.add_child(BrandComponents.section_header("COLOUR"))
	var color_row := HBoxContainer.new()
	color_row.add_theme_constant_override("separation", 6)
	_color_section.add_child(color_row)
	_color_picker = ColorPickerButton.new()
	_color_picker.custom_minimum_size = Vector2(52, 34)
	_color_picker.edit_alpha = false
	_color_picker.color = _paint_color
	_color_picker.color_changed.connect(_on_paint_color_changed)
	color_row.add_child(_color_picker)
	var default_btn := BrandComponents.compact_button("Default")
	default_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	default_btn.pressed.connect(_use_brick_catalog_color)
	color_row.add_child(default_btn)
	var presets := HFlowContainer.new()
	presets.add_theme_constant_override("h_separation", 4)
	presets.add_theme_constant_override("v_separation", 4)
	_color_section.add_child(presets)
	_color_preset_btns.clear()
	for preset in COLOR_PRESETS:
		if bool(preset.get("custom", true)) == false:
			continue
		var swatch := Button.new()
		swatch.custom_minimum_size = Vector2(26, 26)
		swatch.focus_mode = Control.FOCUS_NONE
		swatch.tooltip_text = str(preset.get("name", "Colour"))
		var sb := StyleBoxFlat.new()
		sb.bg_color = preset["color"] as Color
		sb.border_color = BrandTokens.SEA_LINE
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(2)
		swatch.add_theme_stylebox_override("normal", sb)
		swatch.add_theme_stylebox_override("hover", sb)
		var preset_copy: Dictionary = preset
		swatch.pressed.connect(func() -> void: _apply_color_preset(preset_copy))
		presets.add_child(swatch)
		_color_preset_btns.append(swatch)
	col.add_child(_color_section)

	_sign_section = VBoxContainer.new()
	_sign_section.add_child(BrandComponents.section_header("SIGN TEXT"))
	_sign_text_edit = LineEdit.new()
	_sign_text_edit.placeholder_text = "Vessel name / custom text…"
	_sign_text_edit.max_length = 32
	_sign_text_edit.text_changed.connect(func(_t: String) -> void: _refresh_ghost_from_mouse())
	_sign_section.add_child(_sign_text_edit)
	col.add_child(_sign_section)

	_light_section = VBoxContainer.new()
	_light_section.add_child(BrandComponents.section_header("LIGHT"))
	_cone_btn = BrandComponents.compact_button("Aim preview: on")
	_cone_btn.pressed.connect(_toggle_light_cones)
	_light_section.add_child(_cone_btn)
	col.add_child(_light_section)

	_clipboard_section = VBoxContainer.new()
	_clipboard_section.add_child(BrandComponents.section_header("SELECTION"))
	var copy := BrandComponents.compact_button("Copy selection  Ctrl+C")
	copy.pressed.connect(_copy_marked_region)
	_clipboard_section.add_child(copy)
	var paste := BrandComponents.compact_button("Paste at cursor  Ctrl+V")
	paste.pressed.connect(_paste_clipboard_at_cursor)
	_clipboard_section.add_child(paste)
	var paste_layer := BrandComponents.compact_button("Paste on this layer")
	paste_layer.pressed.connect(_paste_clipboard_on_layer)
	_clipboard_section.add_child(paste_layer)
	col.add_child(_clipboard_section)


func _build_ship_dialog() -> void:
	_ship_dialog = BrandComponents.panel(Vector2(410, 0))
	_ship_dialog.name = "ShipDialog"
	_ship_dialog.visible = false
	_ship_dialog.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_ship_dialog.offset_left = -430.0
	_ship_dialog.offset_right = -20.0
	_ship_dialog.offset_top = -300.0
	_ship_dialog.offset_bottom = 300.0
	_root.add_child(_ship_dialog)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 9)
	_ship_dialog.add_child(col)
	var heading := HBoxContainer.new()
	col.add_child(heading)
	var title := BrandComponents.title_label("SHIP", 20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	heading.add_child(title)
	var close := BrandComponents.compact_button("×", 34)
	close.pressed.connect(func() -> void: _ship_dialog.visible = false)
	heading.add_child(close)

	_status_lbl = BrandComponents.subtitle_label("", 11)
	_status_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_status_lbl)

	_authoring_section = VBoxContainer.new()
	_authoring_section.visible = false
	_authoring_section.add_theme_constant_override("separation", 7)
	col.add_child(_authoring_section)
	_hull_option = OptionButton.new()
	_hull_option.tooltip_text = "Hull class for a blank new deck"
	_authoring_section.add_child(BrandComponents.section_header("HULL"))
	_authoring_section.add_child(_hull_option)
	_prebuilt_option = OptionButton.new()
	_prebuilt_option.tooltip_text = "Load an existing official prebuilt JSON"
	_authoring_section.add_child(BrandComponents.section_header("PREBUILT"))
	_authoring_section.add_child(_prebuilt_option)

	col.add_child(BrandComponents.section_header("VESSEL NAME"))
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Name your vessel"
	_name_edit.max_length = MAX_VESSEL_NAME_LEN
	_name_edit.text_changed.connect(func(_text: String) -> void: _refresh_ship_summary())
	col.add_child(_name_edit)
	_add_registration_picker(col)
	var price_header := BrandComponents.section_header("PRICE (MARKS)")
	price_header.name = "PriceHeader"
	price_header.visible = false
	col.add_child(price_header)
	_price_edit = LineEdit.new()
	_price_edit.visible = false
	_price_edit.placeholder_text = "0"
	_price_edit.tooltip_text = "Authoring catalog price. 0 = free."
	col.add_child(_price_edit)
	var power_header := BrandComponents.section_header("SHAFT POWER (kW)")
	power_header.name = "PowerHeader"
	power_header.visible = false
	col.add_child(power_header)
	_power_edit = LineEdit.new()
	_power_edit.visible = false
	_power_edit.placeholder_text = "1"
	_power_edit.tooltip_text = "Engine power for this finished store ship, independent of its hull."
	_power_edit.text_changed.connect(func(_text: String) -> void: _refresh_ship_summary())
	col.add_child(_power_edit)

	col.add_child(BrandComponents.separator())
	_rules_lbl = Label.new()
	_rules_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	BrandTheme.apply_body_font(_rules_lbl, 12, BrandTokens.INK_INVERSE)
	col.add_child(_rules_lbl)
	_caps_lbl = Label.new()
	_caps_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	BrandTheme.apply_body_font(_caps_lbl, 12, BrandTokens.INK_INVERSE_DIM)
	col.add_child(_caps_lbl)

	_dev_save_lbl = Label.new()
	_dev_save_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	BrandTheme.apply_body_font(_dev_save_lbl, 11, BrandTokens.INK_INVERSE_DIM)
	col.add_child(_dev_save_lbl)

	var clear := BrandComponents.compact_button("Clear deck…")
	clear.pressed.connect(_request_clear_layout)
	col.add_child(clear)


func _add_registration_picker(col: VBoxContainer) -> void:
	var header := BrandComponents.section_header("LEGAL REGISTRATION")
	header.name = "RegistrationHeader"
	col.add_child(header)
	_registration_option = OptionButton.new()
	_registration_option.name = "RegistrationOption"
	_registration_option.tooltip_text = (
		"Choose the vessel's legal operating type before placing any parts."
	)
	col.add_child(_registration_option)
	_populate_registration_option()
	_registration_option.item_selected.connect(_on_registration_selected)


func _populate_registration_option() -> void:
	if _registration_option == null:
		return
	_registration_option.clear()
	_registration_option.add_item("Choose registration…")
	_registration_option.set_item_metadata(0, "")
	var i := 1
	for entry in VesselRegistrationCatalog.registrations():
		_registration_option.add_item(str(entry.get("display", entry.get("id", ""))))
		_registration_option.set_item_metadata(i, str(entry.get("id", "")))
		i += 1
	_select_registration_option(_registration_id)


func _select_registration_option(registration_id: String) -> void:
	if _registration_option == null:
		return
	for i in range(_registration_option.item_count):
		if str(_registration_option.get_item_metadata(i)) == registration_id:
			_registration_option.select(i)
			return
	_registration_option.select(0)


func _on_registration_selected(index: int) -> void:
	if _registration_option == null or index < 0:
		return
	if not _layout.is_empty() and str(_registration_option.get_item_metadata(index)) != _registration_id:
		_select_registration_option(_registration_id)
		_show_toast("Clear the deck before changing legal registration")
		return
	_registration_id = str(_registration_option.get_item_metadata(index))
	_refresh_rules()
	if not _brick_id.is_empty() and not _brick_allowed_for_registration(_brick_id):
		var denied := VesselCompliance.brick_placement_denied_reason(
			_registration_id, _layout.hull_id if _layout != null else "", _brick_id
		)
		_brick_id = BrickCatalog.BRICKS.keys()[0] if not BrickCatalog.BRICKS.is_empty() else ""
		_show_toast(denied)
	_refresh_palette_selection()


func _build_help_overlay() -> void:
	_help_overlay = BrandComponents.panel(Vector2(460, 0))
	_help_overlay.name = "HelpOverlay"
	_help_overlay.visible = false
	_help_overlay.set_anchors_preset(Control.PRESET_CENTER)
	_help_overlay.offset_left = -230
	_help_overlay.offset_right = 230
	_help_overlay.offset_top = -190
	_help_overlay.offset_bottom = 190
	_root.add_child(_help_overlay)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 9)
	_help_overlay.add_child(col)
	col.add_child(BrandComponents.title_label("BUILDER CONTROLS", 22))
	var help := BrandComponents.body_label(
		"Place: left-click or drag\n"
		+ "Erase: X, then click or drag\n"
		+ "Select: M, click two opposite corners\n"
		+ "Copy / paste: Ctrl+C / Ctrl+V\n"
		+ "Rotate: R\n"
		+ "Layer: [ and ]\n"
		+ "Orbit / pan / zoom: RMB / MMB / wheel\n"
		+ "Cancel selection: Esc",
		13,
	)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(help)
	var close := BrandComponents.compact_button("Close")
	close.pressed.connect(func() -> void: _help_overlay.visible = false)
	col.add_child(close)


func _build_clear_confirmation() -> void:
	_clear_confirm = BrandComponents.panel(Vector2(380, 0))
	_clear_confirm.name = "ClearConfirmation"
	_clear_confirm.visible = false
	_clear_confirm.set_anchors_preset(Control.PRESET_CENTER)
	_clear_confirm.offset_left = -190
	_clear_confirm.offset_right = 190
	_clear_confirm.offset_top = -100
	_clear_confirm.offset_bottom = 100
	_root.add_child(_clear_confirm)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	_clear_confirm.add_child(col)
	col.add_child(BrandComponents.title_label("CLEAR DECK?", 20))
	var warning := BrandComponents.body_label("This removes every placed brick and cargo zone.", 13)
	warning.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(warning)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	col.add_child(row)
	var cancel := BrandComponents.compact_button("Cancel")
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel.pressed.connect(func() -> void: _clear_confirm.visible = false)
	row.add_child(cancel)
	var clear := BrandComponents.compact_button("Clear deck")
	clear.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clear.pressed.connect(_confirm_clear_layout)
	row.add_child(clear)


func _build_legacy_chrome() -> void:
	_root = Control.new()
	_root.name = "EditorRoot"
	_root.visible = false
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = BrandTheme.shared()
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
	side_sb.bg_color = BrandTokens.SEA_DEEP
	side_sb.border_color = BrandTokens.SEA_LINE
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
	title.add_theme_color_override("font_color", BrandTokens.BRASS)
	col.add_child(title)

	_hull_lbl = Label.new()
	_hull_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hull_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hull_lbl.add_theme_font_size_override("font_size", 13)
	_hull_lbl.add_theme_color_override("font_color", BrandTokens.INK_INVERSE)
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
	_status_lbl.add_theme_color_override("font_color", BrandTokens.INK_INVERSE_DIM)
	_status_lbl.text = (
		"Empty deck — place items yourself.\n"
		+ "LMB place · RMB orbit · MMB pan · Scroll zoom\n"
		+ "[ ] layer (shows this floor + below) · R rotate · X erase\n"
		+ "M mark A→B · Ctrl+C copy · Ctrl+V paste (stamp another layer/spot)\n"
		+ "Cargo zone: click A, then B · Doors open with F after deploy\n"
		+ "Cell = 1.0 m"
	)
	col.add_child(_status_lbl)

	col.add_child(HSeparator.new())

	var items_hdr := Label.new()
	items_hdr.text = "ITEMS"
	items_hdr.add_theme_color_override("font_color", BrandTokens.BRASS)
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
	var place_btn := BrandComponents.button("Place")
	place_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	place_btn.pressed.connect(func() -> void: _tool = Tool.PLACE; _clear_mark(); _refresh_palette_selection(); _refresh_ghost_from_mouse())
	tool_row.add_child(place_btn)
	var erase_btn := BrandComponents.button("Erase")
	erase_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	erase_btn.pressed.connect(func() -> void: _tool = Tool.ERASE; _clear_mark(); _refresh_palette_selection(); _clear_ghost())
	tool_row.add_child(erase_btn)

	var tool_row2 := HBoxContainer.new()
	tool_row2.add_theme_constant_override("separation", 6)
	col.add_child(tool_row2)
	var rot_btn := BrandComponents.button("Rotate")
	rot_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rot_btn.pressed.connect(func() -> void: _rotate_yaw(); _refresh_rules(); _refresh_ghost_from_mouse())
	tool_row2.add_child(rot_btn)
	var clear_btn := BrandComponents.button("Clear deck")
	clear_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clear_btn.pressed.connect(_clear_layout)
	tool_row2.add_child(clear_btn)

	_cone_btn = BrandComponents.button("Light cones: ON")
	_cone_btn.pressed.connect(_toggle_light_cones)
	col.add_child(_cone_btn)

	col.add_child(HSeparator.new())
	var color_hdr := Label.new()
	color_hdr.text = "COLOUR"
	color_hdr.add_theme_color_override("font_color", BrandTokens.BRASS)
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
	var catalog_btn := BrandComponents.button("Catalog default")
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
		sb.border_color = BrandTokens.SEA_LINE
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
	_layer_lbl.add_theme_color_override("font_color", BrandTokens.INK_INVERSE)
	col.add_child(_layer_lbl)

	var layer_row := HBoxContainer.new()
	layer_row.add_theme_constant_override("separation", 6)
	col.add_child(layer_row)
	var down := BrandComponents.button("Layer −")
	down.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	down.pressed.connect(func() -> void: _set_layer_y(_layer_y - 1))
	layer_row.add_child(down)
	var up := BrandComponents.button("Layer +")
	up.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	up.pressed.connect(func() -> void: _set_layer_y(_layer_y + 1))
	layer_row.add_child(up)

	var clip_row := HBoxContainer.new()
	clip_row.add_theme_constant_override("separation", 6)
	col.add_child(clip_row)
	var mark_btn := BrandComponents.button("Mark")
	mark_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mark_btn.tooltip_text = "Click two corners to select (M)"
	mark_btn.pressed.connect(_toggle_mark_tool)
	clip_row.add_child(mark_btn)
	var copy_btn := BrandComponents.button("Copy")
	copy_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy_btn.tooltip_text = "Copy marked region (Ctrl+C)"
	copy_btn.pressed.connect(_copy_marked_region)
	clip_row.add_child(copy_btn)

	var clip_row2 := HBoxContainer.new()
	clip_row2.add_theme_constant_override("separation", 6)
	col.add_child(clip_row2)
	var paste_btn := BrandComponents.button("Paste at cursor")
	paste_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	paste_btn.tooltip_text = "Stamp at mouse (Ctrl+V)"
	paste_btn.pressed.connect(_paste_clipboard_at_cursor)
	clip_row2.add_child(paste_btn)
	var paste_layer_btn := BrandComponents.button("Paste this layer")
	paste_layer_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	paste_layer_btn.tooltip_text = "Same XZ as the copy, on the current layer"
	paste_layer_btn.pressed.connect(_paste_clipboard_on_layer)
	clip_row2.add_child(paste_layer_btn)

	var sign_lbl := Label.new()
	sign_lbl.text = "Sign text (floor / wall)"
	sign_lbl.add_theme_color_override("font_color", BrandTokens.BRASS)
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
	_rules_lbl.add_theme_color_override("font_color", BrandTokens.INK_INVERSE)
	col.add_child(_rules_lbl)

	_caps_lbl = Label.new()
	_caps_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caps_lbl.add_theme_font_size_override("font_size", 12)
	_caps_lbl.add_theme_color_override("font_color", BrandTokens.INK_INVERSE_DIM)
	col.add_child(_caps_lbl)

	col.add_child(HSeparator.new())

	var name_lbl := Label.new()
	name_lbl.text = "Vessel name"
	name_lbl.add_theme_font_size_override("font_size", 12)
	name_lbl.add_theme_color_override("font_color", BrandTokens.INK_INVERSE_DIM)
	col.add_child(name_lbl)

	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Name your vessel"
	_name_edit.max_length = MAX_VESSEL_NAME_LEN
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(_name_edit)

	var price_lbl := Label.new()
	price_lbl.text = "Shipwright price (marks) — 0 = free"
	price_lbl.add_theme_font_size_override("font_size", 12)
	price_lbl.add_theme_color_override("font_color", BrandTokens.INK_INVERSE_DIM)
	col.add_child(price_lbl)

	_price_edit = LineEdit.new()
	_price_edit.placeholder_text = "0"
	_price_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_price_edit.tooltip_text = "Sale price in the shipwright catalog. 0 = free."
	col.add_child(_price_edit)

	_confirm_btn = BrandComponents.button("Confirm build")
	_confirm_btn.pressed.connect(_on_confirm)
	col.add_child(_confirm_btn)

	_dev_save_lbl = Label.new()
	_dev_save_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dev_save_lbl.add_theme_font_size_override("font_size", 10)
	_dev_save_lbl.add_theme_color_override("font_color", BrandTokens.INK_INVERSE_DIM)
	col.add_child(_dev_save_lbl)

	_back_btn = BrandComponents.button("Back to hulls")
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


func _process(_delta: float) -> void:
	if _toast_lbl == null or not _toast_lbl.visible or _toast_until_msec <= 0:
		return
	if Time.get_ticks_msec() >= _toast_until_msec:
		_toast_lbl.visible = false
		_toast_until_msec = 0


func _set_tool(tool: int) -> void:
	_tool = tool
	if tool != Tool.MARK:
		_clear_mark()
		_clear_mark_preview()
	else:
		_clear_mark()
		_clear_ghost()
	_refresh_palette_selection()
	_refresh_ghost_from_mouse()


func _toggle_ship_dialog() -> void:
	if _ship_dialog != null:
		_ship_dialog.visible = not _ship_dialog.visible
	if _help_overlay != null:
		_help_overlay.visible = false


func _toggle_help_overlay() -> void:
	if _help_overlay != null:
		_help_overlay.visible = not _help_overlay.visible
	if _ship_dialog != null:
		_ship_dialog.visible = false


func _show_toast(message: String, failed: bool = false, persistent: bool = false) -> void:
	if _toast_lbl == null:
		return
	_toast_lbl.text = message
	_toast_lbl.visible = true
	_toast_lbl.add_theme_color_override(
		"font_color",
		BrandTokens.ALERT if failed else BrandTokens.OK_LIGHT,
	)
	_toast_until_msec = 0 if persistent else Time.get_ticks_msec() + 3200


func _request_clear_layout() -> void:
	if _clear_confirm != null:
		_clear_confirm.visible = true
	if _ship_dialog != null:
		_ship_dialog.visible = false


func _confirm_clear_layout() -> void:
	if _clear_confirm != null:
		_clear_confirm.visible = false
	_clear_layout()
	_show_toast("Deck cleared")


func _palette_category_of(brick_id: String) -> String:
	if BrickCatalog.has_tag(brick_id, "text"):
		return "Signs"
	if BrickCatalog.has_tag(brick_id, "light"):
		return "Lights"
	if (
		BrickCatalog.has_tag(brick_id, "window")
		or BrickCatalog.has_tag(brick_id, "door")
	):
		return "Openings"
	if (
		BrickCatalog.has_tag(brick_id, "floor")
		or BrickCatalog.has_tag(brick_id, "railing")
		or BrickCatalog.has_tag(brick_id, "ladder")
	):
		return "Deck"
	if (
		BrickCatalog.has_tag(brick_id, "helm")
		or BrickCatalog.has_tag(brick_id, "bulk_hold")
		or BrickCatalog.has_tag(brick_id, "container_pad")
		or BrickCatalog.has_tag(brick_id, "cargo")
		or BrickCatalog.has_tag(brick_id, "crane")
		or BrickCatalog.has_tag(brick_id, "crane_base")
		or BrickCatalog.has_tag(brick_id, "fishing")
		or BrickCatalog.has_tag(brick_id, "mooring")
		or BrickCatalog.has_tag(brick_id, "mast")
		or BrickCatalog.has_tag(brick_id, "chimney")
		or BrickCatalog.has_tag(brick_id, "prop")
	):
		return "Equipment"
	return "Structure"


func _filter_palette() -> void:
	var query := ""
	if _palette_search != null:
		query = _palette_search.text.strip_edges().to_lower()
	var category := "All"
	if _palette_category != null and _palette_category.selected >= 0:
		category = _palette_category.get_item_text(_palette_category.selected)
	var shown := 0
	for id_v in _brick_rows.keys():
		var id := str(id_v)
		var row := _brick_rows[id] as PanelContainer
		if row == null:
			continue
		var category_match := category == "All" or _palette_category_of(id) == category
		var name := BrickCatalog.display_name(id).to_lower()
		var search_match := query.is_empty() or query in name or query in id.to_lower()
		row.visible = category_match and search_match
		if row.visible:
			shown += 1
	if _palette_empty_lbl != null:
		_palette_empty_lbl.visible = shown == 0
	var count := _root.find_child("PaletteCount", true, false) as Label
	if count != null:
		count.text = str(shown)


func _brick_supports_color(brick_id: String) -> bool:
	return (
		BrickCatalog.has(brick_id)
		and not BrickCatalog.has_tag(brick_id, "cargo")
		and not BrickCatalog.has_tag(brick_id, "text")
		and not BrickCatalog.has_tag(brick_id, "light")
	)


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
		_context_info.text = "%d × %d × %d cells  ·  %.1f × %.1f × %.1f m" % [
			fp.x, fp.y, fp.z, size.x, size.y, size.z,
		]
	_color_section.visible = not is_mark and _brick_supports_color(_brick_id)
	_sign_section.visible = not is_mark and BrickCatalog.has_tag(_brick_id, "text")
	_light_section.visible = not is_mark and BrickCatalog.has_tag(_brick_id, "light")
	_clipboard_section.visible = is_mark or not _clipboard.is_empty()


func _refresh_hint() -> void:
	if _hint_lbl == null:
		return
	if _tool == Tool.ERASE:
		_hint_lbl.text = "Click or drag to erase. Press X to return to Place."
	elif _tool == Tool.MARK:
		if not _mark_anchor_set:
			_hint_lbl.text = "Select: click corner A."
		elif not _mark_complete:
			_hint_lbl.text = "Select: click corner B. Change layer first to include height."
		else:
			_hint_lbl.text = "Selection ready — Copy in the properties drawer or press Ctrl+C."
	elif _is_fixed_rect_tool():
		_hint_lbl.text = "Bulk hold: click once on deck. R rotates footprint."
	elif not _clipboard.is_empty():
		_hint_lbl.text = "Clipboard ready — Ctrl+V at cursor, or Paste on this layer."
	else:
		_hint_lbl.text = "LMB place · RMB orbit · MMB pan · wheel zoom"


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
		if _clear_confirm != null and _clear_confirm.visible:
			_clear_confirm.visible = false
			get_viewport().set_input_as_handled()
			return
		if _help_overlay != null and _help_overlay.visible:
			_help_overlay.visible = false
			get_viewport().set_input_as_handled()
			return
		if _ship_dialog != null and _ship_dialog.visible:
			_ship_dialog.visible = false
			get_viewport().set_input_as_handled()
			return
		if _mark_anchor_set:
			_set_tool(Tool.PLACE)
			get_viewport().set_input_as_handled()
			return
		_close()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
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
			# Fixed-rect and mark corners are click-A / click-B — never drag-paint.
			if not _is_fixed_rect_tool() and _tool != Tool.MARK:
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
	if _tool == Tool.MARK:
		if _vp_host != null:
			var layer_cell := _pick_cell(_vp_host.get_local_mouse_position())
			if layer_cell.x >= 0:
				_ghost_cell = layer_cell
		_update_mark_preview()
	else:
		_refresh_ghost_from_mouse()


func _apply_layer_visibility() -> void:
	## Current edit layer and everything below stay visible; hide floors above.
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
	## Cargo zones live on deck (y=0).
	if _brick_root != null:
		var bulk := _brick_root.get_node_or_null("BulkHoldPreview")
		if bulk != null:
			bulk.visible = _layer_y >= 0


func _is_fixed_rect_tool() -> bool:
	return str(BrickCatalog.get_entry(_brick_id).get("place_mode", "")) == "fixed_rect"


func _is_container_pad_tool() -> bool:
	return str(BrickCatalog.get_entry(_brick_id).get("place_mode", "")) == "rect" \
		or BrickCatalog.has_tag(_brick_id, "container_pad")


func _paint_at_screen(screen_pos: Vector2) -> void:
	var cell := _pick_cell(screen_pos)
	if cell.x < 0:
		return
	if cell == _last_paint_cell:
		return
	_last_paint_cell = cell

	if _is_fixed_rect_tool():
		_paint_fixed_rect_at(cell)
		return

	if _is_container_pad_tool():
		_paint_container_pad_at(cell)
		return

	if _tool == Tool.MARK:
		_handle_mark_click(cell)
		return

	if _tool == Tool.ERASE:
		if _layout.erase_container_pad_at(cell):
			_sync_brick_visuals()
			_refresh_rules()
			return
		if _layout.erase_bulk_hold_at(cell):
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


func _paint_fixed_rect_at(cell: Vector3i) -> void:
	if cell.y != 0:
		return
	if _tool == Tool.ERASE:
		if not _layout.erase_bulk_hold_at(cell):
			return
		_sync_brick_visuals()
		_refresh_rules()
		_refresh_ghost_from_mouse()
		return
	if _registration_id.is_empty():
		_show_toast("Choose a legal vessel registration before building")
		return
	var yaw := _yaw
	if not _fixed_rect_placeable(cell, _brick_id, yaw):
		return
	if not _layout.add_bulk_hold(cell, _brick_id, yaw, _grid):
		return
	_sync_brick_visuals()
	_refresh_rules()
	_refresh_ghost_from_mouse()


func _paint_container_pad_at(cell: Vector3i) -> void:
	if cell.y != 0:
		return
	if _tool == Tool.ERASE:
		_rect_anchor_set = false
		if not _layout.erase_container_pad_at(cell):
			return
		_sync_brick_visuals()
		_refresh_rules()
		_refresh_ghost_from_mouse()
		return
	if _registration_id.is_empty():
		_show_toast("Choose a legal vessel registration before building")
		return
	if not _rect_anchor_set:
		_rect_anchor = cell
		_rect_anchor_set = true
		_show_toast("Container pad: click opposite corner (multiples of %d×%d m)"
			% [ContainerUnit.DEFAULT_FOOTPRINT.x, ContainerUnit.DEFAULT_FOOTPRINT.y])
		return
	var a := _rect_anchor
	_rect_anchor_set = false
	if not _layout.add_container_pad(a, cell, _grid):
		_show_toast("Invalid container pad — need even width/depth on open deck")
		return
	_sync_brick_visuals()
	_refresh_rules()
	_refresh_ghost_from_mouse()


func _rotate_yaw() -> void:
	var step := BrickCatalog.yaw_step_of(_brick_id) if BrickCatalog.has(_brick_id) else 90
	_yaw = (_yaw + step) % 360


func _try_place(cell: Vector3i) -> bool:
	if _registration_id.is_empty():
		_show_toast("Choose a legal vessel registration before building")
		return false
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
		if _layout.deck_reserved_contains(c):
			return false
	var denied := _registration_place_denied(_brick_id, cells)
	if not denied.is_empty():
		_show_toast(denied)
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
	## Attach lights mount on host faces. Top-mount floods sit on a block roof (layer above).
	if cell.x < 0 or _grid == null:
		return false
	var yaw := BrickLayout.norm_yaw_step(_yaw, BrickCatalog.yaw_step_of(_brick_id))
	_yaw = yaw
	if BrickCatalog.has_tag(_brick_id, "attach"):
		if _layout.has_cell(cell):
			var host := _layout.get_brick(_layout.primary_cell_of(cell))
			var host_id := str(host.get("brick_id", ""))
			if BrickCatalog.has_tag(host_id, "light"):
				_layout.erase_footprint_at(cell)
				return _layout.place_footprint(cell, _brick_id, yaw, _grid)
			return _layout.attach_light(cell, _brick_id, yaw)
		var fp_attach := BrickCatalog.footprint_of(_brick_id)
		var yaw_steps_attach := int(round(float(yaw) / 90.0)) % 4
		for c in _grid.footprint_cells(cell, fp_attach, yaw_steps_attach):
			if not _grid.in_bounds(c):
				return false
			if _layout.has_cell(c):
				return false
		return _layout.place_footprint(cell, _brick_id, yaw, _grid)

	## Freestanding / roof floods — click a block to stack on the cell above it.
	var place_cell := cell
	if _layout.has_cell(cell):
		var host := _layout.get_brick(_layout.primary_cell_of(cell))
		var host_id := str(host.get("brick_id", ""))
		if BrickCatalog.has_tag(host_id, "light"):
			_layout.erase_footprint_at(cell)
			return _layout.place_footprint(cell, _brick_id, yaw, _grid)
		place_cell = Vector3i(cell.x, cell.y + 1, cell.z)
	var fp := BrickCatalog.footprint_of(_brick_id)
	var yaw_steps := int(round(float(yaw) / 90.0)) % 4
	for c in _grid.footprint_cells(place_cell, fp, yaw_steps):
		if not _grid.in_bounds(c):
			return false
		if _layout.has_cell(c):
			return false
	return _layout.place_footprint(place_cell, _brick_id, yaw, _grid)


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
	if str(entry.get("place_mode", "")) == "fixed_rect":
		return _fixed_rect_placeable(cell, brick_id, yaw)
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
		if not (
			BrickCatalog.has_tag(brick_id, "diagonal_plan")
			and fp == Vector3i.ONE
			and not _layout.deck_reserved_contains(cell)
		):
			return false
		return _registration_place_denied(brick_id, [cell]).is_empty()
	if bool(entry.get("edge_only", false)):
		if cell.y != 0:
			return false
		use_yaw = _grid.outboard_yaw_degrees(cell, fp, 0)
		var ys := int(round(float(use_yaw) / 90.0)) % 4
		if not _grid.footprint_touches_edge(cell, fp, ys):
			return false
	var yaw_steps := int(round(float(use_yaw) / 90.0)) % 4
	var allow_on_cargo := BrickCatalog.has_tag(brick_id, "text")
	var cells := _grid.footprint_cells(cell, fp, yaw_steps)
	for c in cells:
		if not _grid.in_bounds(c):
			return false
		if not allow_on_cargo and _layout.deck_reserved_contains(c):
			return false
	return _registration_place_denied(brick_id, cells).is_empty()


func _registration_place_denied(brick_id: String, replace_cells: Array = []) -> String:
	var hull_id := _layout.hull_id if _layout != null else ""
	return VesselCompliance.brick_placement_denied_reason(
		_registration_id, hull_id, brick_id, _layout, replace_cells
	)


func _brick_allowed_for_registration(brick_id: String) -> bool:
	var hull_id := _layout.hull_id if _layout != null else ""
	return VesselCompliance.brick_allowed_for_registration(_registration_id, hull_id, brick_id)


func _ghost_position_for(cell: Vector3i, brick_id: String, yaw: int) -> Vector3:
	## Face-mount attach lights; top-mount floods preview on the roof cell above a host block.
	if BrickCatalog.has_tag(brick_id, "light") and _layout.has_cell(cell):
		var host := _layout.get_brick(_layout.primary_cell_of(cell))
		var host_id := str(host.get("brick_id", ""))
		if not BrickCatalog.has_tag(host_id, "light"):
			if BrickCatalog.has_tag(brick_id, "attach"):
				return _grid.cell_center_local(cell) + DeckFitout.light_mount_offset(yaw, brick_id)
			if BrickCatalog.has_tag(brick_id, "top_mount"):
				var above := Vector3i(cell.x, cell.y + 1, cell.z)
				if _grid.in_bounds(above):
					return DeckFitout.footprint_center_local(_grid, above, brick_id, yaw)
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
	if _tool == Tool.MARK:
		var mark_cell := _pick_cell(screen_pos)
		if mark_cell.x < 0:
			_clear_ghost()
			return
		_ghost_cell = mark_cell
		_update_mark_preview()
		return
	if _tool == Tool.ERASE:
		_clear_ghost()
		return
	var cell := _pick_cell(screen_pos)
	if cell.x < 0:
		_clear_ghost()
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


func _fixed_rect_placeable(cell: Vector3i, brick_id: String, yaw: int) -> bool:
	if cell.y != 0 or _grid == null:
		return false
	var fp := BrickCatalog.footprint_of(brick_id)
	var yaw_steps := int(round(float(yaw) / 90.0)) % 4
	for c in _grid.footprint_cells(cell, fp, yaw_steps):
		if not _grid.in_bounds(c):
			return false
		if _layout.has_cell(c):
			return false
		if _layout.deck_reserved_contains(c):
			return false
	return _registration_place_denied(brick_id, _grid.footprint_cells(cell, fp, yaw_steps)).is_empty()


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
	row.custom_minimum_size = Vector2(124, 98)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.tooltip_text = _brick_tooltip(brick_id)
	row.set_meta("category", _palette_category_of(brick_id))
	row.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton:
			var mb := ev as InputEventMouseButton
			if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
				_select_brick(brick_id)
	)
	var sb := StyleBoxFlat.new()
	sb.bg_color = BrandTokens.SCRIM
	sb.border_color = BrandTokens.SEA_LINE
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.set_content_margin_all(5)
	row.add_theme_stylebox_override("panel", sb)
	row.set_meta("style", sb)
	row.mouse_entered.connect(func() -> void:
		if not (_tool == Tool.PLACE and _brick_id == brick_id):
			sb.border_color = BrandTokens.BRASS_DEEP
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
	name_lbl.add_theme_color_override("font_color", BrandTokens.INK_INVERSE)
	col.add_child(name_lbl)
	return row


func _brick_tooltip(brick_id: String) -> String:
	var fp := BrickCatalog.footprint_of(brick_id)
	var size := BrickCatalog.size_m(brick_id)
	var detail := "%d×%d×%d cells · %.1f×%.1f×%.1f m" % [
		fp.x, fp.y, fp.z, size.x, size.y, size.z,
	]
	if BrickCatalog.has_tag(brick_id, "bulk_hold"):
		detail = "Click once on deck to place a bulk hold"
	elif BrickCatalog.has_tag(brick_id, "text"):
		detail += "\nText options appear after selection"
	elif BrickCatalog.has_tag(brick_id, "external"):
		detail += "\nExternal light · rotate to aim"
	elif BrickCatalog.has_tag(brick_id, "light"):
		detail += "\nMount on a block · rotate to aim"
	var denied := _registration_place_denied(brick_id)
	if not denied.is_empty():
		detail += "\n" + denied
	return "%s\n%s" % [BrickCatalog.display_name(brick_id), detail]


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
	if not _brick_allowed_for_registration(id):
		_show_toast(
			VesselCompliance.brick_placement_denied_reason(
				_registration_id, _layout.hull_id if _layout != null else "", id
			)
		)
		return
	_brick_id = id
	_tool = Tool.PLACE
	_yaw = BrickLayout.norm_yaw_step(_yaw, BrickCatalog.yaw_step_of(id))
	_clear_mark()
	_clear_mark_preview()
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
		var allowed := _brick_allowed_for_registration(str(id))
		var selected := _tool == Tool.PLACE and str(id) == _brick_id and allowed
		row.modulate = Color(1.0, 1.0, 1.0, 1.0) if allowed else Color(1.0, 1.0, 1.0, 0.38)
		row.tooltip_text = _brick_tooltip(str(id))
		var sb: StyleBoxFlat = row.get_meta("style") as StyleBoxFlat
		if sb != null:
			sb.border_color = BrandTokens.BRASS if selected else BrandTokens.SEA_LINE
			sb.set_border_width_all(2 if selected else 1)
			sb.bg_color = Color(0.16, 0.14, 0.10) if selected else BrandTokens.SCRIM
	if _layer_lbl != null:
		_layer_lbl.text = "Layer %d · %d°" % [_layer_y, _yaw]
	if _tool_place_btn != null:
		_tool_place_btn.set_pressed_no_signal(_tool == Tool.PLACE)
	if _tool_erase_btn != null:
		_tool_erase_btn.set_pressed_no_signal(_tool == Tool.ERASE)
	if _tool_mark_btn != null:
		_tool_mark_btn.set_pressed_no_signal(_tool == Tool.MARK)
	_refresh_context_drawer()
	_refresh_hint()


func _toggle_light_cones() -> void:
	_show_light_cones = not _show_light_cones
	_refresh_cone_button()
	_apply_all_aim_gizmo_visibility()
	_clear_ghost()
	_refresh_ghost_from_mouse()


func _refresh_cone_button() -> void:
	if _cone_btn == null:
		return
	_cone_btn.text = "Aim preview: on" if _show_light_cones else "Aim preview: off"


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


func _clear_mark() -> void:
	_mark_anchor_set = false
	_mark_complete = false
	_mark_anchor = Vector3i(-999, -999, -999)
	_mark_min = Vector3i.ZERO
	_mark_max = Vector3i.ZERO


func _toggle_mark_tool() -> void:
	if _tool == Tool.MARK:
		_tool = Tool.PLACE
		_clear_mark()
		_clear_mark_preview()
	else:
		_tool = Tool.MARK
		_clear_mark()
		_clear_ghost()
	_refresh_palette_selection()
	_refresh_ghost_from_mouse()


func _clear_mark_preview() -> void:
	if _mark_preview != null and is_instance_valid(_mark_preview):
		_mark_preview.queue_free()
	_mark_preview = null


func _handle_mark_click(cell: Vector3i) -> void:
	if _mark_complete or not _mark_anchor_set:
		_mark_anchor = cell
		_mark_anchor_set = true
		_mark_complete = false
	else:
		var bounds := BrickRegionClipboard.bounds_from_corners(_mark_anchor, cell)
		_mark_min = bounds["min"]
		_mark_max = bounds["max"]
		_mark_complete = true
	_refresh_palette_selection()
	_update_mark_preview()


func _update_mark_preview() -> void:
	if _tool != Tool.MARK or not _mark_anchor_set or _grid == null:
		return
	var min_c := _mark_min
	var max_c := _mark_max
	if not _mark_complete:
		var bounds := BrickRegionClipboard.bounds_from_corners(_mark_anchor, _ghost_cell)
		min_c = bounds["min"]
		max_c = bounds["max"]
	var key := "%d,%d,%d:%d,%d,%d" % [min_c.x, min_c.y, min_c.z, max_c.x, max_c.y, max_c.z]
	if (
		_mark_preview != null and is_instance_valid(_mark_preview)
		and str(_mark_preview.get_meta("mark_key", "")) == key
	):
		return
	_clear_mark_preview()
	_mark_preview = _make_mark_box_visual(min_c, max_c)
	_mark_preview.name = "MarkPreview"
	_mark_preview.set_meta("mark_key", key)
	if _boat != null and is_instance_valid(_boat):
		_boat.add_child(_mark_preview)
	elif _world != null and is_instance_valid(_world):
		_world.add_child(_mark_preview)


func _make_mark_box_visual(min_c: Vector3i, max_c: Vector3i) -> Node3D:
	var w := float(max_c.x - min_c.x + 1) * DeckGrid.CELL_M
	var h := float(max_c.y - min_c.y + 1) * DeckGrid.CELL_M
	var l := float(max_c.z - min_c.z + 1) * DeckGrid.CELL_M
	var min_center := _grid.cell_center_local(min_c)
	var max_center := _grid.cell_center_local(max_c)
	var root := Node3D.new()
	root.position = (min_center + max_center) * 0.5
	var col := Color(0.35, 0.72, 1.0, 0.22)
	var box := MeshBuilder.box(Vector3(w * 0.98, h * 0.98, l * 0.98), col, 0.9, 0.0)
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
		_show_toast("Select two corners first", true, true)
		return
	_clipboard = BrickRegionClipboard.extract_region(_layout.cells, _mark_min, _mark_max)
	_clipboard_src_min = _mark_min
	var n := int(_clipboard.get("cell_count", 0))
	if n <= 0:
		_clipboard.clear()
		_show_toast("Selection is empty", true, true)
		_refresh_palette_selection()
		return
	_tool = Tool.PLACE
	_clear_mark()
	_clear_mark_preview()
	_refresh_palette_selection()
	_refresh_ghost_from_mouse()
	_show_toast("Copied %d bricks" % n)


func _paste_clipboard_at_cursor() -> void:
	if _clipboard.is_empty():
		_show_toast("Clipboard empty", true, true)
		return
	var dest := _ghost_cell
	if dest.x < 0 and _vp_host != null:
		dest = _pick_cell(_vp_host.get_local_mouse_position())
	if dest.x < 0:
		_show_toast("Aim at the deck, then paste", true, true)
		return
	_paste_at(dest)


func _paste_clipboard_on_layer() -> void:
	if _registration_id.is_empty():
		_show_toast("Choose a legal vessel registration before building")
		return
	if _clipboard.is_empty():
		_show_toast("Clipboard empty", true, true)
		return
	_paste_at(Vector3i(_clipboard_src_min.x, _layer_y, _clipboard_src_min.z))


func _paste_at(dest: Vector3i) -> void:
	var allowed := func(c: Vector3i) -> bool:
		return _grid != null and _grid.has_deck_cell(c)
	if not BrickRegionClipboard.can_paste(_clipboard, dest, _layout.cells, allowed):
		_show_toast("Paste blocked — choose empty deck cells", true, true)
		return
	_layout.cells = BrickRegionClipboard.paste_region(_clipboard, dest, _layout.cells)
	_sync_brick_visuals()
	_refresh_rules()
	_show_toast("Pasted %d bricks" % int(_clipboard.get("cell_count", 0)))


func _clear_layout() -> void:
	_layout.clear()
	_clear_mark()
	_sync_brick_visuals()
	_refresh_rules()


func _rebuild_preview() -> void:
	## Build the bare hull once; brick meshes are maintained incrementally afterward.
	_clear_ghost()
	_clear_mark_preview()
	_ensure_editor_boat()
	_sync_brick_visuals()
	_refresh_grid_overlay()
	_update_camera()
	_refresh_ghost_from_mouse()


func _ensure_editor_boat() -> void:
	var want_id := str(_hull_entry.get("id", "fishing_trawler_small"))
	if _boat != null and is_instance_valid(_boat):
		if str(_boat.get_meta("editor_hull_id", "")) == want_id:
			return
		_boat.queue_free()
		_boat = null
		_brick_root = null
		_brick_visuals.clear()
		_clear_mark_preview()
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
		var node_v: Variant = _brick_visuals[k]
		if not (node_v is Node3D) or not is_instance_valid(node_v):
			stale.append(k)
			continue
		var node: Node3D = node_v as Node3D
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

	_refresh_bulk_hold_preview(_layout.iter_bulk_holds())
	_refresh_container_pad_preview(_layout.iter_container_pads())
	_apply_layer_visibility()


func _refresh_container_pad_preview(pads: Array) -> void:
	if _brick_root == null:
		return
	var existing := _brick_root.get_node_or_null("ContainerPadPreview")
	if existing != null:
		_brick_root.remove_child(existing)
		existing.free()
	if pads.is_empty() or _grid == null:
		return
	var root := Node3D.new()
	root.name = "ContainerPadPreview"
	_brick_root.add_child(root)
	var color := BrickCatalog.get_entry("container_pad").get("color", Color(0.16, 0.22, 0.32)) as Color
	for pad_v in pads:
		var pad := pad_v as Dictionary
		var mn := BrickLayout.zone_min(pad)
		var mx := BrickLayout.zone_max(pad)
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
		var plate := MeshBuilder.box(Vector3(w, 0.08, l), color, 0.9, 0.05)
		plate.position = sum / float(n) + Vector3(0.0, 0.04, 0.0)
		root.add_child(plate)


func _refresh_bulk_hold_preview(holds: Array) -> void:
	if _brick_root == null:
		return
	var existing := _brick_root.get_node_or_null("BulkHoldPreview")
	if existing != null:
		_brick_root.remove_child(existing)
		existing.free()
	if holds.is_empty() or _grid == null:
		return

	var root := Node3D.new()
	root.name = "BulkHoldPreview"
	_brick_root.add_child(root)

	for hold_v in holds:
		var hold := hold_v as Dictionary
		var mn := BrickLayout.zone_min(hold)
		var mx := BrickLayout.zone_max(hold)
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
		var brick_id := str(hold.get("brick_id", "bulk_hold_6x12"))
		var entry := BrickCatalog.get_entry(brick_id)
		var depth_m := float(entry.get("hold_depth_m", 2.5))
		var pad := Node3D.new()
		pad.position = sum / float(n)
		pad.position.y = _grid.deck_y + 0.04
		pad.rotation_degrees = Vector3(0.0, float(int(hold.get("yaw", 0))), 0.0)
		root.add_child(pad)
		var visual := BulkHoldComponent.build_visual(w, l, depth_m, true)
		pad.add_child(visual)


func _clear_preview() -> void:
	_clear_ghost()
	_clear_mark_preview()
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
	var report := BrickRules.validate(_layout, _grid, 0, 0, _registration_id)
	var budget: Dictionary = report.get("budget", {})
	var usage: Dictionary = report.get("usage", {})
	var summary := VesselOutfit.budget_summary(budget, usage)
	var errors: PackedStringArray = report.get("errors", PackedStringArray())
	var warnings: PackedStringArray = report.get("warnings", PackedStringArray())
	var registration_name := (
		VesselRegistrationCatalog.display_name(_registration_id)
		if not _registration_id.is_empty()
		else "Unregistered"
	)
	_rules_lbl.text = "%s · %s\n" % [registration_name, summary]
	var checklist: Array = report.get("checklist", [])
	if checklist.is_empty():
		_rules_lbl.text += "✗ Choose a registration before building."
	else:
		for raw in checklist:
			var item := raw as Dictionary
			_rules_lbl.text += "%s %s — %s (current: %s)\n" % [
				"✓" if bool(item.get("ok", false)) else "✗",
				str(item.get("label", "Requirement")),
				str(item.get("requirement", "required")),
				str(item.get("current", 0)),
			]
	if not warnings.is_empty():
		_rules_lbl.text += "\n" + "\n".join(warnings)
	## Errors used to be printed ONLY when the checklist was empty — i.e. only
	## when no registration had been chosen, whose sole error is "Choose a vessel
	## registration before building". With a registration selected (the normal
	## case, and the only one in which you can build) every other error VesselOutfit
	## raises — the cargo budget, the helm budget, and now "3 bricks sit off the
	## deck" — was computed, returned, and thrown away one line before the label.
	##
	## This is the REALITY.md §3d strip test for the off-deck report: with the
	## `and checklist.is_empty()` still there, the fix reaches nothing a player
	## can see, because the checklist merely says the helm is missing and gives no
	## reason. `shipyard_editor_ui_test` holds the property both ways.
	if not errors.is_empty():
		_rules_lbl.text += "\n" + "\n".join(errors)
	var caps: Dictionary = report.get("capabilities", {})
	_caps_lbl.text = (
		"%s\nHelm live: %s\nCabin: %s\nFishing live: %s\nParts: %d"
		% [
			summary,
			"yes" if bool(caps.get("has_helm", false)) else "no",
			"yes" if bool(caps.get("has_cabin", false)) else "no",
			"yes" if bool(caps.get("has_fishing", false)) else "no",
			int(caps.get("brick_count", 0)),
		]
	)
	## Authoring: incomplete checklists stay savable as drafts. In-game refit still hard-gates.
	var authoring := _authoring_mode or standalone_tool
	var ok := bool(report.get("ok", false))
	if authoring:
		_confirm_btn.disabled = _registration_id.is_empty()
		_confirm_btn.text = (
			"Save official prebuilt JSON" if ok else "Save draft (not for sale)"
		)
	else:
		_confirm_btn.disabled = not ok
	if _registration_option != null:
		_registration_option.disabled = not _layout.is_empty()


func _on_confirm() -> void:
	var report := BrickRules.validate(_layout, _grid, 0, 0, _registration_id)
	var authoring := _authoring_mode or standalone_tool
	if not authoring and not bool(report.get("ok", false)):
		var errors: PackedStringArray = report.get("errors", PackedStringArray())
		_show_dev_save_result("OUTFIT INVALID · " + " · ".join(errors), true)
		return
	if authoring:
		if _registration_id.is_empty():
			_show_dev_save_result("SAVE BLOCKED · choose a registration first", true)
			return
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
		_registration_id,
	)


func _on_dev_save_prebuilt() -> void:
	if _registration_id.is_empty():
		_show_dev_save_result("SAVE BLOCKED · choose a registration first", true)
		return
	var report := BrickRules.validate(_layout, _grid, 0, 0, _registration_id)
	var as_draft := not bool(report.get("ok", false))
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
		_authoring_price_marks(),
		_authoring_shaft_power_kw(),
		_registration_id,
		as_draft,
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
	var saved_price := int(payload.get("price_marks", 0))
	if as_draft:
		var errors: PackedStringArray = report.get("errors", PackedStringArray())
		_show_dev_save_result(
			"DRAFT SAVED · not for sale · %s · %s" % [path, " · ".join(errors)],
			false,
		)
		print("[Shipyard] Saved draft prebuilt preset: %s" % ProjectSettings.globalize_path(path))
	else:
		_show_dev_save_result("SAVED · %s marks · %s" % [saved_price, path], false)
		print("[Shipyard] Saved official prebuilt preset: %s (price_marks=%d)" % [
			ProjectSettings.globalize_path(path),
			saved_price,
		])


static func make_prebuilt_payload(
	preset_id: String,
	vessel_name: String,
	hull_entry: Dictionary,
	layout: Dictionary,
	price_marks: int = -1,
	shaft_power_kw: float = -1.0,
	registration_id: String = "",
	as_draft: bool = false,
) -> Dictionary:
	var hull_id := str(layout.get("hull_id", hull_entry.get("id", "fishing_trawler_small")))
	var price := price_marks
	if price < 0:
		price = maxi(int(hull_entry.get("price_marks", 0)), 0)
	var power_kw := shaft_power_kw
	if power_kw <= 0.0:
		power_kw = maxf(float(hull_entry.get("default_shaft_power_kw", 1.0)), 1.0)
	var payload := {
		"format_version": PREBUILT_FORMAT_VERSION,
		"id": preset_id,
		"name": vessel_name,
		"hull_id": hull_id,
		"price_marks": maxi(price, 0),
		"shaft_power_kw": power_kw,
		"registration_id": registration_id,
		"brick_layout": layout.duplicate(true),
	}
	if as_draft:
		payload["draft"] = true
	return payload


func _set_price_field(price_marks: int) -> void:
	if _price_edit == null:
		return
	_price_edit.text = str(maxi(price_marks, 0))


func _authoring_price_marks() -> int:
	if _price_edit == null:
		return maxi(int(_hull_entry.get("price_marks", 0)), 0)
	var typed := _price_edit.text.strip_edges().replace(",", "").replace(" ", "")
	if typed.is_empty():
		return 0
	if typed.is_valid_int():
		return maxi(typed.to_int(), 0)
	if typed.is_valid_float():
		return maxi(int(typed.to_float()), 0)
	push_warning("ShipyardBrickEditor: invalid price '%s' — saving as 0" % typed)
	return 0


func _set_power_field(shaft_power_kw: float) -> void:
	if _power_edit == null:
		return
	_power_edit.text = "%.0f" % maxf(shaft_power_kw, 1.0)
	_refresh_ship_summary()


func _authoring_shaft_power_kw() -> float:
	var fallback := maxf(float(_hull_entry.get("default_shaft_power_kw", 1.0)), 1.0)
	if _power_edit == null:
		return fallback
	var typed := _power_edit.text.strip_edges().replace(",", "").replace(" ", "")
	if typed.is_valid_float():
		return maxf(typed.to_float(), 1.0)
	push_warning("ShipyardBrickEditor: invalid shaft power '%s' — using hull default" % typed)
	return fallback


func _refresh_ship_summary() -> void:
	if _status_lbl == null or _hull_entry.is_empty():
		return
	var name := _name_edit.text.strip_edges() if _name_edit != null else "Vessel"
	var power_kw := _authoring_shaft_power_kw()
	_status_lbl.text = "%s\n%.0f × %.0f m · %.0f kW" % [
		name if not name.is_empty() else "Unnamed vessel",
		float(_hull_entry.get("loa_m", 0.0)),
		float(_hull_entry.get("beam_m", 0.0)),
		power_kw,
	]


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
	if _dev_save_lbl != null:
		_dev_save_lbl.text = message
		_dev_save_lbl.add_theme_color_override(
			"font_color",
			BrandTokens.ALERT if failed else BrandTokens.OK_LIGHT,
		)
	_show_toast(message, failed, failed)
