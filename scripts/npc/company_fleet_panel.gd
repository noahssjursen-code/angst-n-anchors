class_name CompanyFleetPanel
extends CanvasLayer

## Company office fleet roster — owned hulls with live 3D preview.
## Data: PlayerSession.data.owned_vessels — in MP refreshed from `/v1/vessels` before open.

signal closed

const PANEL_FRACTION := 0.75
const PANEL_ASPECT := 16.0 / 9.0
const SIDEBAR_WIDTH := 280.0

var _panel: Panel
var _vessel_list: VBoxContainer
var _preview_host: SubViewportContainer
var _viewport: SubViewport
var _preview: ShipwrightPreview
var _camera: Camera3D
var _name_lbl: Label
var _class_lbl: Label
var _specs_lbl: Label
var _status_lbl: Label
var _empty_lbl: Label
var _company_balance_lbl: Label
var _fleet_pending_lbl: Label
var _collect_all_btn: Button
var _detail_scroll: ScrollContainer
var _route_title_lbl: Label
var _home_port_lbl: Label
var _home_port_value_lbl: Label
var _visit_port_lbl: Label
var _visit_port_value_lbl: Label
var _pick_dest_btn: Button
var _clear_dest_btn: Button
var _route_summary_lbl: Label
var _crew_title_lbl: Label
var _crew_grid: GridContainer
var _crew_summary_lbl: Label
var _pay_crew_btn: Button
var _ops_title_lbl: Label
var _checklist_lbl: Label
var _ops_status_lbl: Label
var _pending_lbl: Label
var _collect_btn: Button
var _toggle_active_btn: Button
var _blockers_lbl: Label
var _hire_panel: CrewHirePanel
var _map_picker_layer: CanvasLayer
var _map_picker: FleetRouteMapPicker
var _map_picker_cancel_btn: Button
var _map_picker_clear_btn: Button

var _vessels: Array[Dictionary] = []
var _selected_index: int = -1
var _stations: HullStations
var _pending_hire_slot: int = -1
var _crew_slot_tiles: Array[CrewSlotTile] = []
var _office_port_id: String = ""


func _init() -> void:
	name = "CompanyFleetPanel"
	layer = 12
	_build_chrome()


func _ready() -> void:
	var vp := get_viewport()
	if vp != null and not vp.size_changed.is_connected(_resize_panel):
		vp.size_changed.connect(_resize_panel)
	var session := get_node_or_null("/root/PlayerSession")
	if session != null and session.has_signal("vessels_synced"):
		if not session.vessels_synced.is_connected(_on_vessels_synced):
			session.vessels_synced.connect(_on_vessels_synced)


func _unhandled_input(event: InputEvent) -> void:
	if not is_open():
		return
	if _map_picker_layer != null and _map_picker_layer.visible and event.is_action_pressed("ui_cancel"):
		_on_map_pick_cancelled()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()


func is_open() -> bool:
	return _panel != null and _panel.visible


func open_panel(office_port_id: String = "") -> void:
	_office_port_id = office_port_id
	_resize_panel()
	_panel.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_show_loading_state()
	var session := get_node_or_null("/root/PlayerSession")
	if session == null:
		_reload_vessels()
		_finish_open_panel()
		return
	VesselSync.refresh_for_ui(session, func() -> void:
		_reload_vessels()
		_finish_open_panel()
	)


func _finish_open_panel() -> void:
	_accrue_fleet_pending()
	_refresh_company_header()
	_refresh_list()
	_select_index(maxi(_selected_index, 0) if not _vessels.is_empty() else -1)


func _show_loading_state() -> void:
	_vessels.clear()
	_refresh_list()
	if _empty_lbl != null:
		_empty_lbl.text = "Syncing fleet from server…"
		_empty_lbl.visible = true


func hide_panel() -> void:
	if _panel != null:
		_panel.visible = false
	if _preview != null:
		_preview.clear()
	if _hire_panel != null:
		_hire_panel.hide_panel()
	if _map_picker != null:
		_map_picker.hide_picker()
	_pending_hire_slot = -1


func _close() -> void:
	hide_panel()
	closed.emit()


func _on_vessels_synced() -> void:
	if not is_open():
		return
	var keep_uid := ""
	if _selected_index >= 0 and _selected_index < _vessels.size():
		keep_uid = str(_vessels[_selected_index].get("uid", ""))
	_reload_vessels()
	_refresh_list()
	if not keep_uid.is_empty():
		for i in range(_vessels.size()):
			if str(_vessels[i].get("uid", "")) == keep_uid:
				_select_index(i)
				return
	_select_index(maxi(_selected_index, 0) if not _vessels.is_empty() else -1)


func _reload_vessels() -> void:
	_vessels.clear()
	var session := get_node_or_null("/root/PlayerSession")
	if session == null or session.get("data") == null:
		return
	var data: PlayerData = session.data
	for entry_raw in data.owned_vessels:
		if typeof(entry_raw) != TYPE_DICTIONARY:
			continue
		var entry := entry_raw as Dictionary
		if PlayerData.is_legacy_starter_vessel(entry):
			continue
		_vessels.append(entry.duplicate())


func _build_chrome() -> void:
	_panel = Panel.new()
	_panel.name = "FleetPanel"
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

	var header := HBoxContainer.new()
	root_v.add_child(header)

	var title := Label.new()
	title.text = "SHIPPING COMPANY — FLEET"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", HudStyle.C_AMBER)
	header.add_child(title)

	var header_spacer := Control.new()
	header_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(header_spacer)

	var close_btn := UiBuilder.button("Close")
	close_btn.pressed.connect(_close)
	header.add_child(close_btn)

	var company_bar := HBoxContainer.new()
	company_bar.add_theme_constant_override("separation", 12)
	root_v.add_child(company_bar)

	_company_balance_lbl = _sheet_label(13, HudStyle.C_TEXT)
	company_bar.add_child(_company_balance_lbl)

	_fleet_pending_lbl = _sheet_label(13, HudStyle.C_AMBER)
	_fleet_pending_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	company_bar.add_child(_fleet_pending_lbl)

	_collect_all_btn = UiBuilder.button("Collect all")
	_collect_all_btn.pressed.connect(_on_collect_all_pressed)
	company_bar.add_child(_collect_all_btn)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	root_v.add_child(body)

	# ── Sidebar ───────────────────────────────────────────────────────────────
	var sidebar := _styled_panel(SIDEBAR_WIDTH)
	body.add_child(sidebar)

	var sidebar_margin := MarginContainer.new()
	sidebar_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	sidebar_margin.add_theme_constant_override("margin_left", 10)
	sidebar_margin.add_theme_constant_override("margin_right", 10)
	sidebar_margin.add_theme_constant_override("margin_top", 10)
	sidebar_margin.add_theme_constant_override("margin_bottom", 10)
	sidebar.add_child(sidebar_margin)

	var sidebar_v := VBoxContainer.new()
	sidebar_v.add_theme_constant_override("separation", 8)
	sidebar_margin.add_child(sidebar_v)

	var sidebar_title := Label.new()
	sidebar_title.text = "OWNED VESSELS"
	sidebar_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sidebar_title.add_theme_font_size_override("font_size", 13)
	sidebar_title.add_theme_color_override("font_color", HudStyle.C_LABEL)
	sidebar_v.add_child(sidebar_title)
	sidebar_v.add_child(HSeparator.new())

	var list_scroll := ScrollContainer.new()
	list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sidebar_v.add_child(list_scroll)

	_vessel_list = VBoxContainer.new()
	_vessel_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vessel_list.add_theme_constant_override("separation", 6)
	list_scroll.add_child(_vessel_list)

	# ── Preview ─────────────────────────────────────────────────────────────────
	var preview_panel := _styled_panel(0.0)
	preview_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(preview_panel)

	var preview_margin := MarginContainer.new()
	preview_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	preview_margin.add_theme_constant_override("margin_left", 12)
	preview_margin.add_theme_constant_override("margin_right", 12)
	preview_margin.add_theme_constant_override("margin_top", 12)
	preview_margin.add_theme_constant_override("margin_bottom", 12)
	preview_panel.add_child(preview_margin)

	var preview_v := VBoxContainer.new()
	preview_v.add_theme_constant_override("separation", 8)
	preview_margin.add_child(preview_v)

	_preview_host = SubViewportContainer.new()
	_preview_host.custom_minimum_size = Vector2(0.0, 200.0)
	_preview_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview_host.stretch = true
	preview_v.add_child(_preview_host)

	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.size = Vector2i(960, 540)
	_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	_preview_host.add_child(_viewport)

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

	var env_node := WorldEnvironment.new()
	var we := Environment.new()
	we.background_mode = Environment.BG_COLOR
	we.background_color = Color(0.05, 0.07, 0.10)
	we.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	we.ambient_light_color = Color(0.18, 0.20, 0.24)
	we.ambient_light_energy = 0.9
	env_node.environment = we
	world.add_child(env_node)

	_empty_lbl = Label.new()
	_empty_lbl.text = "No vessels on the registry.\nCommission a hull at the Shipwright."
	_empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_empty_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_empty_lbl.add_theme_font_size_override("font_size", 15)
	_empty_lbl.add_theme_color_override("font_color", HudStyle.C_LABEL)
	_empty_lbl.visible = false
	preview_v.add_child(_empty_lbl)

	_detail_scroll = ScrollContainer.new()
	_detail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	preview_v.add_child(_detail_scroll)

	var detail_v := VBoxContainer.new()
	detail_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_v.add_theme_constant_override("separation", 8)
	_detail_scroll.add_child(detail_v)

	_name_lbl = _sheet_label(22, HudStyle.C_AMBER)
	detail_v.add_child(_name_lbl)

	_class_lbl = _sheet_label(14, HudStyle.C_LABEL)
	detail_v.add_child(_class_lbl)

	_specs_lbl = _sheet_label(14, HudStyle.C_TEXT)
	_specs_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_v.add_child(_specs_lbl)

	_status_lbl = _sheet_label(13, HudStyle.C_AMBER)
	detail_v.add_child(_status_lbl)

	detail_v.add_child(HSeparator.new())

	_route_title_lbl = _sheet_label(13, HudStyle.C_LABEL)
	_route_title_lbl.text = "ROUTE"
	detail_v.add_child(_route_title_lbl)

	var route_grid := GridContainer.new()
	route_grid.columns = 2
	route_grid.add_theme_constant_override("h_separation", 10)
	route_grid.add_theme_constant_override("v_separation", 6)
	detail_v.add_child(route_grid)

	_home_port_lbl = _sheet_label(12, HudStyle.C_TEXT)
	_home_port_lbl.text = "Home port"
	route_grid.add_child(_home_port_lbl)

	_home_port_value_lbl = _sheet_label(12, HudStyle.C_AMBER)
	route_grid.add_child(_home_port_value_lbl)

	_visit_port_lbl = _sheet_label(12, HudStyle.C_TEXT)
	_visit_port_lbl.text = "Destination"
	route_grid.add_child(_visit_port_lbl)

	_visit_port_value_lbl = _sheet_label(12, HudStyle.C_TEXT)
	route_grid.add_child(_visit_port_value_lbl)

	var route_actions := HBoxContainer.new()
	route_actions.add_theme_constant_override("separation", 8)
	detail_v.add_child(route_actions)

	_pick_dest_btn = UiBuilder.button("Select on map")
	_pick_dest_btn.pressed.connect(_on_pick_destination_pressed)
	route_actions.add_child(_pick_dest_btn)

	_clear_dest_btn = UiBuilder.button("Clear destination")
	_clear_dest_btn.pressed.connect(_on_clear_destination_pressed)
	route_actions.add_child(_clear_dest_btn)

	_route_summary_lbl = _sheet_label(12, HudStyle.C_LABEL)
	detail_v.add_child(_route_summary_lbl)

	detail_v.add_child(HSeparator.new())

	_crew_title_lbl = _sheet_label(13, HudStyle.C_LABEL)
	_crew_title_lbl.text = "CREW"
	detail_v.add_child(_crew_title_lbl)

	_crew_grid = GridContainer.new()
	_crew_grid.columns = 4
	_crew_grid.add_theme_constant_override("h_separation", 8)
	_crew_grid.add_theme_constant_override("v_separation", 8)
	detail_v.add_child(_crew_grid)

	var crew_actions := HBoxContainer.new()
	crew_actions.add_theme_constant_override("separation", 10)
	detail_v.add_child(crew_actions)

	_crew_summary_lbl = _sheet_label(12, HudStyle.C_TEXT)
	_crew_summary_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	crew_actions.add_child(_crew_summary_lbl)

	_pay_crew_btn = UiBuilder.button("Pay wages")
	_pay_crew_btn.pressed.connect(_on_pay_crew_pressed)
	crew_actions.add_child(_pay_crew_btn)

	detail_v.add_child(HSeparator.new())

	_ops_title_lbl = _sheet_label(13, HudStyle.C_LABEL)
	_ops_title_lbl.text = "OPERATIONS"
	detail_v.add_child(_ops_title_lbl)

	_checklist_lbl = _sheet_label(12, HudStyle.C_TEXT)
	detail_v.add_child(_checklist_lbl)

	_ops_status_lbl = _sheet_label(13, HudStyle.C_AMBER)
	detail_v.add_child(_ops_status_lbl)

	_blockers_lbl = _sheet_label(12, HudStyle.C_LABEL)
	detail_v.add_child(_blockers_lbl)

	var earnings_row := HBoxContainer.new()
	earnings_row.add_theme_constant_override("separation", 10)
	detail_v.add_child(earnings_row)

	_pending_lbl = _sheet_label(12, HudStyle.C_TEXT)
	_pending_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	earnings_row.add_child(_pending_lbl)

	_collect_btn = UiBuilder.button("Collect")
	_collect_btn.pressed.connect(_on_collect_pressed)
	earnings_row.add_child(_collect_btn)

	_toggle_active_btn = UiBuilder.button("Activate")
	_toggle_active_btn.pressed.connect(_on_toggle_active_pressed)
	detail_v.add_child(_toggle_active_btn)

	_hire_panel = CrewHirePanel.new()
	_hire_panel.candidate_selected.connect(_on_hire_candidate_selected)
	_hire_panel.cancelled.connect(func() -> void: _pending_hire_slot = -1)
	add_child(_hire_panel)

	_map_picker_layer = CanvasLayer.new()
	_map_picker_layer.layer = 14
	_map_picker_layer.visible = false
	add_child(_map_picker_layer)

	var picker_dim := ColorRect.new()
	picker_dim.color = Color(0.02, 0.03, 0.08, 0.72)
	picker_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	picker_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_picker_layer.add_child(picker_dim)

	_map_picker = FleetRouteMapPicker.new()
	_map_picker.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map_picker.destination_picked.connect(_on_map_destination_picked)
	_map_picker.pick_cancelled.connect(_on_map_pick_cancelled)
	_map_picker_layer.add_child(_map_picker)

	var picker_bar := PanelContainer.new()
	picker_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	picker_bar.offset_left = 24.0
	picker_bar.offset_right = -24.0
	picker_bar.offset_top = 16.0
	picker_bar.offset_bottom = 56.0
	var bar_sb := StyleBoxFlat.new()
	bar_sb.bg_color = HudStyle.C_BG
	bar_sb.border_color = HudStyle.C_BRASS
	bar_sb.set_border_width_all(1)
	picker_bar.add_theme_stylebox_override("panel", bar_sb)
	_map_picker_layer.add_child(picker_bar)

	var bar_margin := MarginContainer.new()
	bar_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	bar_margin.add_theme_constant_override("margin_left", 12)
	bar_margin.add_theme_constant_override("margin_right", 12)
	bar_margin.add_theme_constant_override("margin_top", 8)
	bar_margin.add_theme_constant_override("margin_bottom", 8)
	picker_bar.add_child(bar_margin)

	var bar_h := HBoxContainer.new()
	bar_h.add_theme_constant_override("separation", 10)
	bar_margin.add_child(bar_h)

	var picker_title := Label.new()
	picker_title.text = "SELECT DESTINATION PORT"
	picker_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker_title.add_theme_font_size_override("font_size", 15)
	picker_title.add_theme_color_override("font_color", HudStyle.C_AMBER)
	bar_h.add_child(picker_title)

	_map_picker_clear_btn = UiBuilder.button("Clear destination")
	_map_picker_clear_btn.pressed.connect(_on_clear_destination_pressed)
	bar_h.add_child(_map_picker_clear_btn)

	_map_picker_cancel_btn = UiBuilder.button("Cancel")
	_map_picker_cancel_btn.pressed.connect(_on_map_pick_cancelled)
	bar_h.add_child(_map_picker_cancel_btn)


func _styled_panel(min_width: float) -> PanelContainer:
	var panel := PanelContainer.new()
	if min_width > 0.0:
		panel.custom_minimum_size = Vector2(min_width, 0.0)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = HudStyle.C_BG_INNER
	sb.border_color = HudStyle.C_BRASS
	sb.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", sb)
	return panel


func _sheet_label(font_size: int, color: Color) -> Label:
	var lbl := Label.new()
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	return lbl


func _resize_panel() -> void:
	if _panel == null:
		return
	var vp := get_viewport()
	if vp == null:
		return
	var size := DialoguePanel.viewport_panel_size(
		vp.get_visible_rect().size, PANEL_FRACTION, PANEL_ASPECT
	)
	_panel.offset_left = -size.x * 0.5
	_panel.offset_right = size.x * 0.5
	_panel.offset_top = -size.y * 0.5
	_panel.offset_bottom = size.y * 0.5


func _refresh_list() -> void:
	for child in _vessel_list.get_children():
		child.queue_free()

	if _vessels.is_empty():
		var hint := Label.new()
		hint.text = "No owned hulls yet."
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.add_theme_font_size_override("font_size", 13)
		hint.add_theme_color_override("font_color", HudStyle.C_LABEL)
		_vessel_list.add_child(hint)
		return

	var session := get_node_or_null("/root/PlayerSession")
	var active_uid := ""
	if session != null and session.get("data") != null:
		active_uid = str(session.data.active_vessel.get("uid", ""))

	for i in range(_vessels.size()):
		var record := _vessels[i]
		var uid := str(record.get("uid", ""))
		var display := str(record.get("display", "Vessel"))
		var short := display.split("  •  ")[0] if "  •  " in display else display
		var hull_id := str(record.get("hull_id", ""))
		var line := short
		var status := CompanyFleetOps.status_label(record)
		line += "\n[%s]" % status
		if uid == active_uid:
			line += " (deployed)"
		elif not hull_id.is_empty() and status == "Idle":
			line += "\n" + hull_id

		var btn := Button.new()
		btn.text = line
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var idx := i
		btn.pressed.connect(func() -> void: _select_index(idx))
		if i == _selected_index:
			btn.add_theme_color_override("font_color", HudStyle.C_AMBER)
		_vessel_list.add_child(btn)


func _select_index(index: int) -> void:
	if index < 0 or index >= _vessels.size():
		_selected_index = -1
		_show_empty_preview()
		_refresh_list()
		return
	_selected_index = index
	_refresh_list()
	if _selected_index >= 0:
		_ensure_office_home_port()
	_show_vessel(_vessels[index])


func _show_empty_preview() -> void:
	_preview.clear()
	_preview_host.visible = false
	_empty_lbl.visible = true
	_name_lbl.text = ""
	_class_lbl.text = ""
	_specs_lbl.text = ""
	_status_lbl.text = ""
	_clear_detail_ui()


func _show_vessel(record: Dictionary) -> void:
	var entry := _preview_entry_for_owned(record)
	if entry.is_empty():
		_show_empty_preview()
		_specs_lbl.text = "Unknown hull — cannot render preview."
		return

	_preview_host.visible = true
	_empty_lbl.visible = false
	_stations = _preview.show_entry(entry)
	_camera.transform = ShipwrightPreview.camera_transform_for_length(
		_stations.length_m if _stations != null else 18.0
	)

	var display := str(record.get("display", entry.get("display", "Vessel")))
	var short := display.split("  •  ")[0] if "  •  " in display else display
	_name_lbl.text = short
	_class_lbl.text = "%s  •  %s" % [
		str(entry.get("ship_class_label", "")),
		VesselRole.display_name(int(entry.get("role", VesselRole.Type.CARGO))),
	]

	var len_m := _stations.length_m if _stations != null else 0.0
	var beam_m := _stations.beam_m if _stations != null else 0.0
	var disp_t := (_stations.displacement_volume_m3 * 1.025) if _stations != null else 0.0
	_specs_lbl.text = (
		"%s\nLength %.0f m  •  Beam %.1f m  •  ~%.0f t displacement"
		% [display, len_m, beam_m, disp_t]
	)

	var session := get_node_or_null("/root/PlayerSession")
	var active_uid := ""
	if session != null and session.get("data") != null:
		active_uid = str(session.data.active_vessel.get("uid", ""))
	var uid := str(record.get("uid", ""))
	var server_id := str(record.get("server_vessel_id", ""))
	if uid == active_uid:
		_status_lbl.text = "Status: deployed to sea"
	elif not server_id.is_empty():
		_status_lbl.text = "Status: in registry (server %s…)" % server_id.substr(0, 8)
	else:
		_status_lbl.text = "Status: in registry (local save)"

	_refresh_crew_section(record)
	_refresh_route_section(record)
	_refresh_operations_section(record)
	_detail_scroll.visible = true


func _accrue_fleet_pending() -> void:
	var session := get_node_or_null("/root/PlayerSession")
	if session == null or session.get("data") == null:
		return
	for i in range(_vessels.size()):
		var rolled := CompanyFleetOps.roll_pending(_vessels[i])
		if rolled != _vessels[i]:
			_vessels[i] = rolled
			session.data.upsert_owned_vessel(rolled)
	if session.has_method("save_now"):
		session.save_now()


func _ensure_office_home_port() -> void:
	if _office_port_id.is_empty() or _selected_index < 0 or _selected_index >= _vessels.size():
		return
	var record := _vessels[_selected_index].duplicate()
	if str(record.get("home_port_id", "")) == _office_port_id:
		return
	var visit_id := str(record.get("visit_port_id", ""))
	if visit_id == _office_port_id:
		visit_id = ""
	record = CompanyFleetOps.apply_route(record, _office_port_id, visit_id)
	_persist_vessel_record(record)
	_vessels[_selected_index] = record


func _office_port_display_name() -> String:
	if _office_port_id.is_empty():
		return "Unknown harbour"
	var reg := _registry()
	if reg != null and reg.has_method("get_port_display_name"):
		return str(reg.call("get_port_display_name", _office_port_id))
	return _office_port_id


func _refresh_route_section(record: Dictionary) -> void:
	_route_title_lbl.visible = true
	_home_port_lbl.visible = true
	_home_port_value_lbl.visible = true
	_visit_port_lbl.visible = true
	_visit_port_value_lbl.visible = true
	_pick_dest_btn.visible = true
	_clear_dest_btn.visible = true
	_route_summary_lbl.visible = true

	var av := AutonomousVesselRecord.from_owned_vessel(record)
	var home_id := _office_port_id if not _office_port_id.is_empty() else av.home_port_id
	_home_port_value_lbl.text = _port_display_name(home_id)
	if _office_port_id.is_empty():
		_home_port_value_lbl.text += " (visit a company office)"

	var optional_dest := CompanyFleetOps.visit_port_optional(record)
	_visit_port_lbl.text = "Also sell at" if optional_dest else "Destination"

	if av.has_visit_port():
		_visit_port_value_lbl.text = _port_display_name(av.visit_port_id)
	elif optional_dest:
		_visit_port_value_lbl.text = "None — out & back from home"
	else:
		_visit_port_value_lbl.text = "Not selected — use map"

	_pick_dest_btn.disabled = _office_port_id.is_empty()
	_clear_dest_btn.visible = optional_dest or av.has_visit_port()
	_clear_dest_btn.disabled = not av.has_visit_port()
	_route_summary_lbl.text = CompanyFleetOps.route_summary(record, _registry())


func _port_display_name(port_id: String) -> String:
	if port_id.is_empty():
		return "—"
	var reg := _registry()
	if reg != null and reg.has_method("get_port_display_name"):
		return str(reg.call("get_port_display_name", port_id))
	return port_id


func _on_pick_destination_pressed() -> void:
	if _office_port_id.is_empty() or _selected_index < 0:
		return
	var record := _vessels[_selected_index]
	var current := str(record.get("visit_port_id", ""))
	_map_picker_layer.visible = true
	_map_picker.open_picker(_office_port_id, current)
	var optional := CompanyFleetOps.visit_port_optional(record)
	_map_picker_clear_btn.visible = optional


func _on_map_destination_picked(port_id: String) -> void:
	_map_picker_layer.visible = false
	if _selected_index < 0 or port_id.is_empty():
		return
	var record := _vessels[_selected_index].duplicate()
	record = CompanyFleetOps.apply_route(record, _office_port_id, port_id)
	_persist_vessel_record(record)
	_refresh_list()
	_show_vessel(record)


func _on_map_pick_cancelled() -> void:
	_map_picker_layer.visible = false
	_map_picker.hide_picker()


func _on_clear_destination_pressed() -> void:
	if _selected_index < 0 or _office_port_id.is_empty():
		return
	var record := _vessels[_selected_index].duplicate()
	record = CompanyFleetOps.apply_route(record, _office_port_id, "")
	_persist_vessel_record(record)
	_map_picker_layer.visible = false
	_map_picker.hide_picker()
	_show_vessel(record)


func _refresh_operations_section(record: Dictionary) -> void:
	var rolled := CompanyFleetOps.roll_pending(record.duplicate())
	if (
		int(rolled.get("pending_earnings", 0)) != int(record.get("pending_earnings", 0))
		or int(rolled.get("last_accrual_at", 0)) != int(record.get("last_accrual_at", 0))
	):
		_persist_vessel_record(rolled)
	record = rolled
	if _selected_index >= 0 and _selected_index < _vessels.size():
		_vessels[_selected_index] = record

	_ops_title_lbl.visible = true
	_checklist_lbl.visible = true
	_ops_status_lbl.visible = true
	_toggle_active_btn.visible = true

	var lines := CompanyFleetOps.checklist_lines(record)
	_checklist_lbl.text = "\n".join(lines)

	var status := CompanyFleetOps.status_label(record)
	var sim := AutonomousVesselSim.sample(record)
	var sim_line := ""
	if bool(record.get("autonomous_active", false)):
		sim_line = "  •  %s" % str(sim.get("stage_name", ""))
	_ops_status_lbl.text = "Fleet status: %s%s" % [status, sim_line]

	var blockers := CompanyFleetOps.activation_blockers(record)
	if blockers.is_empty():
		_blockers_lbl.visible = false
		_blockers_lbl.text = ""
	else:
		_blockers_lbl.visible = true
		_blockers_lbl.text = "Before activate: " + ", ".join(blockers)

	var pending := CompanyFleetOps.pending_earnings(record)
	_pending_lbl.text = "Pending earnings: %s" % PlayerData.format_money(pending)
	_collect_btn.disabled = pending <= 0

	var av := AutonomousVesselRecord.from_owned_vessel(record)
	if av.active:
		_toggle_active_btn.text = "Deactivate autonomous run"
		_toggle_active_btn.disabled = false
	else:
		_toggle_active_btn.text = "Activate autonomous run"
		_toggle_active_btn.disabled = not CompanyFleetOps.can_activate(record)

	_refresh_company_header()


func _on_toggle_active_pressed() -> void:
	if _selected_index < 0:
		return
	var record := _vessels[_selected_index].duplicate()
	var av := AutonomousVesselRecord.from_owned_vessel(record)
	record = CompanyFleetOps.set_autonomous_active(record, not av.active)
	_persist_vessel_record(record)
	var mgr := get_node_or_null("/root/AutonomousVesselManager")
	if mgr != null and mgr.has_method("refresh_vessel"):
		mgr.call("refresh_vessel", str(record.get("uid", "")))
	_refresh_list()
	_show_vessel(record)


func _on_collect_pressed() -> void:
	if _selected_index < 0:
		return
	var record := CompanyFleetOps.roll_pending(_vessels[_selected_index].duplicate())
	var amount := CompanyFleetOps.pending_earnings(record)
	if amount <= 0:
		return
	record = CompanyFleetOps.collect_earnings(record)
	var session := get_node_or_null("/root/PlayerSession")
	if session == null:
		return
	session.earn_marks(amount)
	_persist_vessel_record(record)
	_refresh_company_header()
	_show_vessel(record)


func _on_collect_all_pressed() -> void:
	var session := get_node_or_null("/root/PlayerSession")
	if session == null:
		return
	var total := 0
	for i in range(_vessels.size()):
		var record := CompanyFleetOps.roll_pending(_vessels[i])
		var amount := CompanyFleetOps.pending_earnings(record)
		if amount <= 0:
			continue
		record = CompanyFleetOps.collect_earnings(record)
		total += amount
		_vessels[i] = record
		session.data.upsert_owned_vessel(record)
	if total > 0:
		session.earn_marks(total)
	if session.has_method("save_now"):
		session.save_now()
	_refresh_company_header()
	_refresh_list()
	if _selected_index >= 0:
		_show_vessel(_vessels[_selected_index])


func _registry() -> Node:
	return get_node_or_null("/root/ContractRegistry")


func _refresh_company_header() -> void:
	var session := get_node_or_null("/root/PlayerSession")
	var balance := 0
	if session != null and session.get("data") != null:
		balance = int(session.data.marks)
	_company_balance_lbl.text = "Company balance: %s" % PlayerData.format_money(balance)
	var pending := CompanyFleetOps.fleet_total_pending(_vessels)
	_fleet_pending_lbl.text = "Fleet pending: %s" % PlayerData.format_money(pending)
	_collect_all_btn.disabled = pending <= 0


func _clear_detail_ui() -> void:
	for tile in _crew_slot_tiles:
		if is_instance_valid(tile):
			tile.queue_free()
	_crew_slot_tiles.clear()
	_route_title_lbl.visible = false
	_home_port_lbl.visible = false
	_home_port_value_lbl.visible = false
	_visit_port_lbl.visible = false
	_visit_port_value_lbl.visible = false
	_pick_dest_btn.visible = false
	_clear_dest_btn.visible = false
	_route_summary_lbl.visible = false
	_crew_title_lbl.visible = false
	_crew_grid.visible = false
	_crew_summary_lbl.text = ""
	_pay_crew_btn.disabled = true
	_ops_title_lbl.visible = false
	_checklist_lbl.text = ""
	_checklist_lbl.visible = false
	_ops_status_lbl.text = ""
	_ops_status_lbl.visible = false
	_blockers_lbl.text = ""
	_blockers_lbl.visible = false
	_pending_lbl.text = ""
	_collect_btn.disabled = true
	_toggle_active_btn.visible = false
	_detail_scroll.visible = false


func _hull_id_for_record(record: Dictionary) -> String:
	var hull_id := str(record.get("hull_id", ""))
	if hull_id.is_empty():
		var path := str(record.get("template_path", ""))
		hull_id = HullRegistry.resolve_id_from_template(path, hull_id)
	return hull_id


func _refresh_crew_section(record: Dictionary) -> void:
	for tile in _crew_slot_tiles:
		if is_instance_valid(tile):
			tile.queue_free()
	_crew_slot_tiles.clear()

	var hull_id := _hull_id_for_record(record)
	var slot_count := VesselCrew.slot_count_for_hull(hull_id)
	var crew := VesselCrew.normalize_slots(record, slot_count)

	_crew_title_lbl.visible = true
	_crew_grid.visible = true
	_crew_grid.columns = mini(4, maxi(slot_count, 1))

	for i in range(slot_count):
		var tile := CrewSlotTile.new()
		tile.setup(i)
		var slot_raw: Variant = crew[i] if i < crew.size() else {}
		if typeof(slot_raw) == TYPE_DICTIONARY:
			tile.set_employee(slot_raw as Dictionary)
		tile.slot_pressed.connect(_on_crew_slot_pressed)
		_crew_grid.add_child(tile)
		_crew_slot_tiles.append(tile)

	var assigned := VesselCrew.assigned_count(crew)
	var wages := VesselCrew.total_daily_wages(crew)
	var paid := VesselCrew.all_crew_paid(crew) or assigned == 0

	_crew_summary_lbl.text = (
		"%d/%d crew  •  %s/day wages"
		% [assigned, slot_count, PlayerData.format_money(wages)]
	)

	_pay_crew_btn.disabled = assigned == 0 or wages <= 0 or paid
	_pay_crew_btn.text = "Pay wages (%s)" % PlayerData.format_money(wages)


func _on_crew_slot_pressed(slot_index: int) -> void:
	if _selected_index < 0 or _selected_index >= _vessels.size():
		return
	_pending_hire_slot = slot_index
	var candidates := VesselCrew.generate_candidates(6)
	_hire_panel.open_for_slot(slot_index, candidates)


func _on_hire_candidate_selected(candidate: Dictionary) -> void:
	if _pending_hire_slot < 0 or _selected_index < 0 or _selected_index >= _vessels.size():
		return
	var slot_index := _pending_hire_slot
	_pending_hire_slot = -1

	var record := _vessels[_selected_index].duplicate()
	var hull_id := _hull_id_for_record(record)
	var slot_count := VesselCrew.slot_count_for_hull(hull_id)
	var crew := VesselCrew.normalize_slots(record, slot_count)
	var employee := VesselCrew.employee_from_candidate(candidate)
	crew[slot_index] = employee
	record = _apply_crew_assignment(record, crew, slot_count)
	_persist_vessel_record(record)
	_show_vessel(record)


func _on_pay_crew_pressed() -> void:
	if _selected_index < 0 or _selected_index >= _vessels.size():
		return
	var record := _vessels[_selected_index].duplicate()
	var hull_id := _hull_id_for_record(record)
	var slot_count := VesselCrew.slot_count_for_hull(hull_id)
	var crew := VesselCrew.normalize_slots(record, slot_count)
	var total := VesselCrew.total_daily_wages(crew)
	if total <= 0:
		return

	var session := get_node_or_null("/root/PlayerSession")
	if session == null or session.get("data") == null:
		return
	if not session.spend_marks(total):
		_crew_summary_lbl.text = "Not enough marks to pay crew (%s due)." % PlayerData.format_money(total)
		return

	crew = VesselCrew.mark_all_paid(crew)
	record = _apply_crew_assignment(record, crew, slot_count)
	_persist_vessel_record(record)
	_show_vessel(record)


func _persist_vessel_record(record: Dictionary) -> void:
	var session := get_node_or_null("/root/PlayerSession")
	if session == null or session.get("data") == null:
		return
	session.data.upsert_owned_vessel(record)
	VesselSync.persist_fleet_state(session, record)
	if session.has_method("save_now"):
		session.save_now()
	if _selected_index >= 0 and _selected_index < _vessels.size():
		_vessels[_selected_index] = record.duplicate()
	var mgr := get_node_or_null("/root/AutonomousVesselManager")
	if mgr != null and mgr.has_method("refresh_vessel"):
		mgr.call("refresh_vessel", str(record.get("uid", "")))


func _apply_crew_assignment(record: Dictionary, crew: Array, slot_count: int) -> Dictionary:
	record["crew"] = crew
	var av := AutonomousVesselRecord.from_owned_vessel(record)
	av.crew = crew
	av.recompute_expense()
	if av.active and not VesselCrew.compute_autonomous_active(crew, slot_count):
		av.set_active(false)
	return av.merge_into_owned_vessel(record)


static func _preview_entry_for_owned(record: Dictionary) -> Dictionary:
	var hull_id := str(record.get("hull_id", ""))
	if hull_id.is_empty():
		var path := str(record.get("template_path", ""))
		hull_id = HullRegistry.resolve_id_from_template(path, hull_id)
	var entry := HullRegistry.get_by_id(hull_id)
	if entry.is_empty():
		return {}
	var out := entry.duplicate()
	var display := str(record.get("display", ""))
	if not display.is_empty():
		out["display"] = display
	return out
