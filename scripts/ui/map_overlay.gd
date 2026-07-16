class_name MapOverlay
extends Control

## Full-screen, north-up marine chart. Navigation mode, or home-port pick
## (select a harbour → review info → confirm).

signal close_requested
signal home_port_confirmed(port_id: String)
signal home_port_cancelled
signal port_selected(port_id: String)

enum Mode { NAVIGATION, HOME_PORT_PICK }

const CameraModel := preload("res://scripts/ui/chart/chart_camera.gd")
const LayerManager := preload("res://scripts/ui/chart/chart_layer_manager.gd")
const Renderer := preload("res://scripts/ui/chart/chart_layer_renderer.gd")
const Snapshot := preload("res://scripts/ui/chart/chart_data_snapshot.gd")

const FRAME := 26.0
const TOP_H := 58.0
const BOTTOM_H := 48.0
const NAV_REFRESH_S := 0.20
const OVERLAY_DEBOUNCE_S := 0.14

var mode := Mode.NAVIGATION
var data
var camera := CameraModel.new()
var layers := LayerManager.new()
var renderer := Renderer.new()
var nav := ChartNavSnapshot.new()

var selected_port := ""
var hover_screen := Vector2(-1.0, -1.0)
var dragging := false
var drag_origin_mouse := Vector2.ZERO
var drag_origin_center := Vector2.ZERO
var drag_distance := 0.0
var nav_elapsed := NAV_REFRESH_S
var overlay_debounce := 0.0
var overlays_dirty := true
var first_visible_frame := true
var last_ctx: Dictionary = {}
var hover_rows: Array[String] = []
var hover_sample_screen := Vector2(-1000.0, -1000.0)
var hover_layer_revision := -1

var title_label: Label
var hint_label: Label
var mode_buttons: Array[Button] = []
var weather_button: Button
var fishing_button: Button
var center_button: Button
var close_button: Button

var pick_panel: PanelContainer
var pick_title: Label
var pick_meta: Label
var pick_body: RichTextLabel
var pick_confirm: Button
var pick_back: Button

var harbour_board: HarbourBoardPanel


func _ready() -> void:
	add_to_group("marine_chart")
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	theme = HudStyle.make_theme()
	_build_toolbar()
	_build_pick_panel()
	_build_harbour_board()
	_load_layer_preferences()
	_apply_mode_ui()
	_refresh_pick_panel()
	_refresh_harbour_board()


func set_data_snapshot(snapshot) -> void:
	data = snapshot
	renderer.set_snapshot(data)
	camera.user_moved = false
	overlays_dirty = true
	first_visible_frame = true


func enter_home_port_pick_mode(preselect_port_id: String = "") -> void:
	mode = Mode.HOME_PORT_PICK
	selected_port = preselect_port_id.strip_edges()
	layers.apply_preset(ChartLayerManager.Preset.NAVIGATION)
	layers.set_visible("routes", false)
	layers.set_visible("approaches", false)
	## Heavy field overlays — leave off during onboarding for responsiveness.
	layers.set_visible("weather", false)
	layers.set_visible("fishing", false)
	_apply_mode_ui()
	_refresh_mode_buttons()
	_refresh_pick_panel()
	camera.user_moved = false
	overlays_dirty = false
	first_visible_frame = true
	visible = true


func exit_home_port_pick_mode() -> void:
	mode = Mode.NAVIGATION
	selected_port = ""
	_apply_mode_ui()
	_refresh_pick_panel()
	visible = false


func is_home_port_pick_mode() -> bool:
	return mode == Mode.HOME_PORT_PICK


func get_selected_port_id() -> String:
	return selected_port


func open_navigation() -> void:
	mode = Mode.NAVIGATION
	if data == null or not data.is_valid():
		set_data_snapshot(Snapshot.from_live_tree(get_tree()))
	layers.apply_preset(ChartLayerManager.Preset.NAVIGATION)
	_apply_mode_ui()
	_refresh_harbour_board()
	first_visible_frame = true
	visible = true


func get_debug_stats() -> Dictionary:
	var stats := renderer.debug_stats()
	stats["preset"] = ChartLayerManager.PRESET_NAMES[layers.preset]
	return stats


func ensure_live_data() -> bool:
	## Home-port pick uses the preview snapshot only — never rebuild from the
	## live world tree (and never thrash PortCatalog while the menu is up).
	if mode == Mode.HOME_PORT_PICK:
		return data != null and data.is_valid()
	if data == null or not data.is_valid():
		set_data_snapshot(Snapshot.from_live_tree(get_tree()))
	return data != null and data.is_valid()


func refresh_shared_chart(bounds: Rect2) -> bool:
	if not refresh_shared_nav():
		return false
	prepare_shared_overlays(bounds)
	return true


func refresh_shared_nav() -> bool:
	if not ensure_live_data():
		return false
	_capture_nav()
	return true


func prepare_shared_overlays(bounds: Rect2) -> void:
	renderer.prepare_overlays(bounds, layers, WeatherField.current_game_time())


func _process(delta: float) -> void:
	if not visible:
		return
	if not ensure_live_data():
		return
	if first_visible_frame:
		if mode != Mode.HOME_PORT_PICK:
			_capture_nav()
		_home()
		first_visible_frame = false
		if mode != Mode.HOME_PORT_PICK:
			overlays_dirty = true
		queue_redraw()
	if mode != Mode.HOME_PORT_PICK:
		nav_elapsed += delta
		if nav_elapsed >= NAV_REFRESH_S:
			nav_elapsed = 0.0
			_capture_nav()
			queue_redraw()
	if overlays_dirty and mode != Mode.HOME_PORT_PICK:
		overlay_debounce -= delta
		if overlay_debounce <= 0.0 and not dragging:
			renderer.prepare_overlays(
				_camera_bounds(),
				layers,
				WeatherField.current_game_time(),
			)
			overlays_dirty = false
			queue_redraw()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		hover_screen = motion.position
		if dragging:
			drag_distance += motion.relative.length()
			camera.pan_pixels(
				motion.position - drag_origin_mouse,
				camera.pixels_per_world_unit(_chart_rect().size),
				drag_origin_center,
			)
		_refresh_hover_readout()
		queue_redraw()
		return
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		## Let the pick panel / toolbar own their clicks (Confirm, Back, etc.).
		if _pointer_over_chrome(mouse.position):
			if not mouse.pressed and dragging:
				dragging = false
			return
		var chart := _chart_rect()
		if mouse.button_index == MOUSE_BUTTON_LEFT:
			if mouse.pressed and chart.has_point(mouse.position):
				dragging = true
				drag_distance = 0.0
				drag_origin_mouse = mouse.position
				drag_origin_center = camera.center
				get_viewport().set_input_as_handled()
			elif not mouse.pressed and dragging:
				dragging = false
				if mode != Mode.HOME_PORT_PICK:
					_schedule_overlays()
				var viewport := get_viewport()
				if viewport != null:
					viewport.set_input_as_handled()
				if drag_distance < 5.0 and chart.has_point(mouse.position):
					_click_chart(mouse.position)
		elif (
			mouse.pressed
			and chart.has_point(mouse.position)
			and mouse.button_index == MOUSE_BUTTON_WHEEL_UP
		):
			_zoom_at(mouse.position, 1)
			_refresh_hover_readout(true)
			get_viewport().set_input_as_handled()
		elif (
			mouse.pressed
			and chart.has_point(mouse.position)
			and mouse.button_index == MOUSE_BUTTON_WHEEL_DOWN
		):
			_zoom_at(mouse.position, -1)
			_refresh_hover_readout(true)
			get_viewport().set_input_as_handled()
		return
	if not event is InputEventKey:
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	if key.keycode == KEY_ESCAPE or key.is_action_pressed("ui_cancel"):
		if mode == Mode.HOME_PORT_PICK:
			home_port_cancelled.emit()
		else:
			close_requested.emit()
		get_viewport().set_input_as_handled()
	elif key.keycode == KEY_H:
		_home()
		get_viewport().set_input_as_handled()
	elif key.keycode == KEY_W and mode != Mode.HOME_PORT_PICK:
		_toggle_overlay("weather")
		get_viewport().set_input_as_handled()
	elif key.keycode == KEY_F and mode != Mode.HOME_PORT_PICK:
		_toggle_overlay("fishing")
		get_viewport().set_input_as_handled()
	elif key.keycode == KEY_N:
		_set_preset(ChartLayerManager.Preset.NAVIGATION)
		get_viewport().set_input_as_handled()


func _draw() -> void:
	var viewport := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, viewport), Color(0.015, 0.025, 0.03, 0.98))
	var chart := _chart_rect()
	draw_rect(chart.grow(1.0), Color(0.55, 0.56, 0.49, 1.0), false, 1.0)
	var bounds := camera.world_bounds(chart.size)
	last_ctx = {
		"chart_rect": chart,
		"world_bounds": bounds,
		"world_span": camera.span,
	}
	renderer.render(
		self,
		last_ctx,
		layers,
		nav,
		selected_port,
		mode != Mode.HOME_PORT_PICK,
	)
	_draw_compass(chart)
	_draw_scale(chart, bounds)
	_draw_status(chart)


func _build_pick_panel() -> void:
	pick_panel = PanelContainer.new()
	pick_panel.name = "HomePortPickPanel"
	pick_panel.visible = false
	pick_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	## Left dock — coastal harbours sit on the east; keep that chart clear.
	pick_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	pick_panel.anchor_left = 0.0
	pick_panel.anchor_top = 0.0
	pick_panel.anchor_right = 0.0
	pick_panel.anchor_bottom = 1.0
	pick_panel.offset_left = FRAME
	pick_panel.offset_top = TOP_H + 6.0
	pick_panel.offset_right = FRAME + 320.0
	pick_panel.offset_bottom = -(BOTTOM_H + 10.0)
	var panel_sb := StyleBoxFlat.new()
	panel_sb.bg_color = Color(HudStyle.C_BG.r, HudStyle.C_BG.g, HudStyle.C_BG.b, 0.94)
	panel_sb.border_color = HudStyle.C_BRASS
	panel_sb.set_border_width_all(1)
	panel_sb.set_content_margin_all(16)
	pick_panel.add_theme_stylebox_override("panel", panel_sb)
	add_child(pick_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pick_panel.add_child(vbox)

	var eyebrow := Label.new()
	eyebrow.text = "HOME HARBOUR"
	eyebrow.add_theme_font_size_override("font_size", 12)
	eyebrow.add_theme_color_override("font_color", HudStyle.C_LABEL)
	if HudStyle.font_medium() != null:
		eyebrow.add_theme_font_override("font", HudStyle.font_medium())
	vbox.add_child(eyebrow)

	pick_title = Label.new()
	pick_title.text = "Select a harbour"
	pick_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pick_title.add_theme_font_size_override("font_size", 28)
	pick_title.add_theme_color_override("font_color", HudStyle.C_TEXT)
	if HudStyle.font_display() != null:
		pick_title.add_theme_font_override("font", HudStyle.font_display())
	vbox.add_child(pick_title)

	pick_meta = Label.new()
	pick_meta.text = "Click a marker on the chart"
	pick_meta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pick_meta.add_theme_font_size_override("font_size", 13)
	pick_meta.add_theme_color_override("font_color", HudStyle.C_COPPER)
	vbox.add_child(pick_meta)

	pick_body = RichTextLabel.new()
	pick_body.bbcode_enabled = true
	pick_body.fit_content = true
	pick_body.scroll_active = false
	pick_body.custom_minimum_size = Vector2(0, 120)
	pick_body.add_theme_font_size_override("normal_font_size", 14)
	pick_body.add_theme_color_override("default_color", HudStyle.C_TEXT)
	vbox.add_child(pick_body)

	## Push actions to the bottom of the dock.
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(spacer)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.size_flags_vertical = Control.SIZE_SHRINK_END
	vbox.add_child(row)

	pick_back = Button.new()
	pick_back.text = "Back"
	pick_back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pick_back.pressed.connect(func() -> void: home_port_cancelled.emit())
	row.add_child(pick_back)

	pick_confirm = Button.new()
	pick_confirm.text = "Sail from here"
	pick_confirm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pick_confirm.disabled = true
	pick_confirm.pressed.connect(_confirm_home_port)
	var confirm_normal := StyleBoxFlat.new()
	confirm_normal.bg_color = Color(0.22, 0.42, 0.36, 1.0)
	confirm_normal.border_color = HudStyle.C_COPPER
	confirm_normal.set_border_width_all(1)
	confirm_normal.set_content_margin_all(10)
	var confirm_hover := confirm_normal.duplicate()
	confirm_hover.bg_color = Color(0.28, 0.52, 0.44, 1.0)
	var confirm_disabled := confirm_normal.duplicate()
	confirm_disabled.bg_color = Color(0.16, 0.20, 0.19, 1.0)
	confirm_disabled.border_color = Color(0.30, 0.34, 0.32, 0.6)
	pick_confirm.add_theme_stylebox_override("normal", confirm_normal)
	pick_confirm.add_theme_stylebox_override("hover", confirm_hover)
	pick_confirm.add_theme_stylebox_override("pressed", confirm_hover)
	pick_confirm.add_theme_stylebox_override("disabled", confirm_disabled)
	pick_confirm.add_theme_color_override("font_color", HudStyle.C_TEXT)
	pick_confirm.add_theme_color_override("font_disabled_color", Color(0.45, 0.50, 0.48))
	row.add_child(pick_confirm)


func _confirm_home_port() -> void:
	if mode != Mode.HOME_PORT_PICK:
		return
	if selected_port.is_empty():
		return
	home_port_confirmed.emit(selected_port)


func _refresh_pick_panel() -> void:
	if pick_panel == null:
		return
	var picking := mode == Mode.HOME_PORT_PICK
	pick_panel.visible = picking
	if not picking:
		return
	if selected_port.is_empty() or data == null:
		pick_title.text = "Select a harbour"
		pick_meta.text = "Click a marker on the chart"
		pick_body.text = \
				"Your home port is where you begin. Look for a harbour that matches the trade you want — fish, ore, timber, containers."
		if pick_confirm != null:
			pick_confirm.disabled = true
		return
	var info: Dictionary = data.port_info(selected_port)
	if info.is_empty():
		pick_title.text = selected_port
		pick_meta.text = "No dossier for this harbour"
		pick_body.text = "Chart data missing for this port id."
		if pick_confirm != null:
			pick_confirm.disabled = true
		return
	pick_title.text = str(info.get("display_name", selected_port))
	var region := str(info.get("region", "coastal")).capitalize()
	var size_n := int(info.get("size", 0))
	pick_meta.text = "%s  ·  size %d  ·  %d berths" % [
		region,
		size_n,
		int(info.get("berth_count", 1)),
	]
	var export_id := str(info.get("commodity_export", ""))
	var export_label := CommodityCatalog.commodity_display(export_id) if not export_id.is_empty() \
			else "—"
	var imports: Array = info.get("commodity_imports", []) as Array
	var import_bits: PackedStringArray = PackedStringArray()
	for raw in imports:
		import_bits.append(CommodityCatalog.commodity_display(str(raw)))
	var import_line := ", ".join(import_bits) if not import_bits.is_empty() else "—"
	var ship_class := str(info.get("max_ship_class_name", "Vessel"))
	var feature_bits: PackedStringArray = PackedStringArray()
	for raw in info.get("features", []) as Array:
		var feature := str(raw)
		if feature.begins_with("Export:"):
			continue
		feature_bits.append(feature)
	var features_line := ", ".join(feature_bits) if not feature_bits.is_empty() else "Standard apron"
	pick_body.text = "\n".join(PackedStringArray([
		"[color=#8a9a94]Population[/color]  %s" % _format_population(int(info.get("population", 0))),
		"[color=#8a9a94]Primary export[/color]  %s" % export_label,
		"[color=#8a9a94]Imports[/color]  %s" % import_line,
		"[color=#8a9a94]Max class[/color]  %s" % ship_class,
		"[color=#8a9a94]Facilities[/color]  %s" % features_line,
	]))
	if pick_confirm != null:
		pick_confirm.disabled = false


static func _format_population(value: int) -> String:
	if value >= 1000000:
		return "%.1fM" % (float(value) / 1000000.0)
	if value >= 1000:
		return "%.1fk" % (float(value) / 1000.0)
	return str(value)


func _build_toolbar() -> void:
	var bar := HBoxContainer.new()
	bar.name = "ChartToolbar"
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.offset_left = FRAME
	bar.offset_right = -FRAME
	bar.offset_top = 13.0
	bar.offset_bottom = 48.0
	bar.add_theme_constant_override("separation", 8)
	add_child(bar)

	title_label = Label.new()
	title_label.text = "NAVIGATION CHART"
	title_label.custom_minimum_size.x = 190.0
	title_label.add_theme_font_size_override("font_size", 18)
	title_label.add_theme_color_override("font_color", Color(0.92, 0.86, 0.62))
	bar.add_child(title_label)

	hint_label = Label.new()
	hint_label.visible = false
	hint_label.text = "Click a harbour for details, then confirm"
	hint_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint_label.add_theme_font_size_override("font_size", 15)
	hint_label.add_theme_color_override("font_color", Color(0.90, 0.92, 0.82))
	bar.add_child(hint_label)

	for spec in [
		["Navigate", ChartLayerManager.Preset.NAVIGATION],
		["Harbour", ChartLayerManager.Preset.HARBOUR],
	]:
		var button := Button.new()
		button.text = str(spec[0])
		button.toggle_mode = true
		button.pressed.connect(_set_preset.bind(int(spec[1])))
		mode_buttons.append(button)
		bar.add_child(button)

	weather_button = Button.new()
	weather_button.text = "Weather"
	weather_button.toggle_mode = true
	weather_button.pressed.connect(_toggle_overlay.bind("weather"))
	bar.add_child(weather_button)

	fishing_button = Button.new()
	fishing_button.text = "Fishing"
	fishing_button.toggle_mode = true
	fishing_button.pressed.connect(_toggle_overlay.bind("fishing"))
	bar.add_child(fishing_button)

	center_button = Button.new()
	center_button.text = "Center"
	center_button.pressed.connect(_home)
	bar.add_child(center_button)

	close_button = Button.new()
	close_button.text = "Close"
	close_button.pressed.connect(func() -> void: close_requested.emit())
	bar.add_child(close_button)
	_refresh_mode_buttons()


func _apply_mode_ui() -> void:
	var picking := mode == Mode.HOME_PORT_PICK
	if title_label != null:
		title_label.text = "CHOOSE YOUR HOME PORT" if picking else "NAVIGATION CHART"
	if hint_label != null:
		hint_label.visible = picking or layers.preset == ChartLayerManager.Preset.HARBOUR
		if picking:
			hint_label.text = "Click a harbour for details, then confirm"
		elif layers.preset == ChartLayerManager.Preset.HARBOUR:
			hint_label.text = "Harbour board — click a port on the chart"
	for index in range(mode_buttons.size()):
		mode_buttons[index].visible = not picking
	if weather_button != null:
		weather_button.visible = not picking
	if fishing_button != null:
		fishing_button.visible = not picking
	if center_button != null:
		center_button.visible = not picking
	if close_button != null:
		close_button.visible = not picking
	if pick_panel != null:
		pick_panel.visible = picking
	if pick_back != null:
		pick_back.visible = picking
	_refresh_harbour_board()


func _set_preset(next: int) -> void:
	layers.apply_preset(next)
	if mode == Mode.HOME_PORT_PICK:
		layers.set_visible("routes", false)
		layers.set_visible("approaches", false)
	_refresh_mode_buttons()
	_persist_chart_settings()
	_refresh_hover_readout(true)
	_schedule_overlays()
	_apply_mode_ui()
	queue_redraw()


func _refresh_mode_buttons() -> void:
	if mode_buttons.size() >= 2:
		mode_buttons[0].set_pressed_no_signal(layers.preset == ChartLayerManager.Preset.NAVIGATION)
		mode_buttons[1].set_pressed_no_signal(layers.preset == ChartLayerManager.Preset.HARBOUR)
	if weather_button != null:
		weather_button.set_pressed_no_signal(layers.is_visible("weather"))
	if fishing_button != null:
		fishing_button.set_pressed_no_signal(layers.is_visible("fishing"))


func _toggle_overlay(layer_name: String) -> void:
	if mode == Mode.HOME_PORT_PICK:
		return
	layers.toggle(layer_name)
	_refresh_mode_buttons()
	_persist_chart_settings()
	_refresh_hover_readout(true)
	_schedule_overlays()
	queue_redraw()


func _load_layer_preferences() -> void:
	var settings := get_node_or_null("/root/GameSettings")
	if settings == null:
		return
	layers.set_overlay_preferences(
		bool(settings.get("chart_weather_enabled")),
		bool(settings.get("chart_fishing_enabled")),
	)
	var saved_profile := int(settings.get("chart_profile"))
	layers.apply_preset(
		ChartLayerManager.Preset.HARBOUR
		if saved_profile == ChartLayerManager.Preset.HARBOUR
		else ChartLayerManager.Preset.NAVIGATION
	)
	_refresh_mode_buttons()


func _persist_chart_settings() -> void:
	var settings := get_node_or_null("/root/GameSettings")
	if settings == null:
		return
	settings.set("chart_weather_enabled", layers.is_visible("weather"))
	settings.set("chart_fishing_enabled", layers.is_visible("fishing"))
	settings.set("chart_profile", layers.preset)
	if settings.has_method("save_settings"):
		settings.call("save_settings")


func _click_chart(screen: Vector2) -> void:
	var hit := renderer.hit_test_port(screen, last_ctx, 28.0 if mode == Mode.HOME_PORT_PICK else 18.0)
	if hit.is_empty():
		if mode == Mode.NAVIGATION:
			selected_port = ""
			_refresh_harbour_board()
			queue_redraw()
		return
	selected_port = hit
	if mode == Mode.HOME_PORT_PICK:
		_refresh_pick_panel()
		queue_redraw()
	else:
		port_selected.emit(hit)
		_refresh_harbour_board()
		queue_redraw()


func _home() -> void:
	if data == null:
		return
	camera.home(nav.ship_position, data.port_positions())
	_schedule_overlays()
	queue_redraw()


func _zoom_at(screen: Vector2, steps: int) -> void:
	var chart := _chart_rect()
	var before := _screen_to_world(screen)
	camera.zoom(steps)
	var bounds := camera.world_bounds(chart.size)
	var uv := (screen - chart.position) / chart.size
	var after := bounds.position + uv * bounds.size
	camera.center += before - after
	_schedule_overlays()
	queue_redraw()


func _schedule_overlays() -> void:
	overlays_dirty = true
	overlay_debounce = OVERLAY_DEBOUNCE_S


func _capture_nav() -> void:
	nav = ChartNavSnapshot.capture(get_tree())


func _camera_bounds() -> Rect2:
	return camera.world_bounds(_chart_rect().size)


func _chart_rect() -> Rect2:
	var size := get_viewport_rect().size
	return Rect2(
		Vector2(FRAME, TOP_H),
		Vector2(
			maxf(size.x - FRAME * 2.0, 1.0),
			maxf(size.y - TOP_H - BOTTOM_H, 1.0),
		),
	)


func _screen_to_world(screen: Vector2) -> Vector2:
	var chart := _chart_rect()
	var bounds := camera.world_bounds(chart.size)
	return bounds.position + (screen - chart.position) / chart.size * bounds.size


func _pointer_over_chrome(screen: Vector2) -> bool:
	if pick_panel != null and pick_panel.visible and pick_panel.get_global_rect().has_point(screen):
		return true
	if harbour_board != null and harbour_board.visible \
			and harbour_board.get_global_rect().has_point(screen):
		return true
	var toolbar := get_node_or_null("ChartToolbar") as Control
	if toolbar != null and toolbar.get_global_rect().has_point(screen):
		return true
	return false


func _build_harbour_board() -> void:
	harbour_board = HarbourBoardPanel.new()
	harbour_board.name = "HarbourBoard"
	harbour_board.visible = false
	harbour_board.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	harbour_board.anchor_left = 1.0
	harbour_board.anchor_top = 1.0
	harbour_board.anchor_right = 1.0
	harbour_board.anchor_bottom = 1.0
	harbour_board.offset_left = -380.0
	harbour_board.offset_top = -320.0
	harbour_board.offset_right = -FRAME
	harbour_board.offset_bottom = -(BOTTOM_H + 10.0)
	add_child(harbour_board)


func _refresh_harbour_board() -> void:
	if harbour_board == null:
		return
	var show_board := (
		mode == Mode.NAVIGATION
		and layers.preset == ChartLayerManager.Preset.HARBOUR
	)
	harbour_board.visible = show_board
	if not show_board:
		return
	var port_id := selected_port.strip_edges()
	if port_id.is_empty():
		port_id = _default_harbour_board_port()
		if not port_id.is_empty():
			selected_port = port_id
	var plot := _resolve_port_plot(port_id)
	harbour_board.bind_port(port_id, plot, true)


func _default_harbour_board_port() -> String:
	var home := get_tree().root.find_child("HomePort", true, false) as PortPlot
	if home != null and not home.port_id.is_empty():
		return home.port_id
	var live := HarbourRegistry.all_port_ids()
	if not live.is_empty():
		return live[0]
	if data != null and data.is_valid():
		var ids: PackedStringArray = data.port_ids()
		if not ids.is_empty():
			return ids[0]
	return ""


func _resolve_port_plot(port_id: String) -> PortPlot:
	if port_id.is_empty():
		return null
	var harbour := HarbourRegistry.controller(port_id)
	if harbour != null:
		return harbour.get_parent() as PortPlot
	var home := get_tree().root.find_child("HomePort", true, false) as PortPlot
	if home != null and home.port_id == port_id:
		return home
	return null


func _refresh_hover_readout(force: bool = false) -> void:
	if not _chart_rect().has_point(hover_screen) or _pointer_over_chrome(hover_screen):
		hover_rows.clear()
		return
	if (
		not force
		and hover_screen.distance_to(hover_sample_screen) < 4.0
		and hover_layer_revision == layers.revision
	):
		return
	hover_sample_screen = hover_screen
	hover_layer_revision = layers.revision
	if mode == Mode.HOME_PORT_PICK:
		var hit := renderer.hit_test_port(hover_screen, last_ctx, 28.0)
		hover_rows.clear()
		if not hit.is_empty() and data != null:
			var info: Dictionary = data.port_info(hit)
			hover_rows.append(str(info.get("display_name", hit)))
			var export_id := str(info.get("commodity_export", ""))
			if not export_id.is_empty():
				hover_rows.append("Export %s" % CommodityCatalog.commodity_display(export_id))
		return
	# Snapshot once per cursor move/layer change. Nav refreshes and chart redraws
	# reuse these strings instead of continuously re-sampling weather.
	hover_rows = renderer.overlay_readout(
		_screen_to_world(hover_screen),
		layers,
		WeatherField.current_game_time(),
	)


func _draw_compass(chart: Rect2) -> void:
	var center := chart.position + Vector2(34.0, 35.0)
	draw_circle(center, 22.0, Color(0.94, 0.93, 0.84, 0.90))
	draw_arc(center, 22.0, 0.0, TAU, 32, Color(0.10, 0.18, 0.20), 1.0)
	draw_line(center, center + Vector2(0.0, -17.0), Color(0.78, 0.12, 0.10), 2.0)
	draw_string(
		ThemeDB.fallback_font,
		center + Vector2(-4.0, -4.0),
		"N",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.08, 0.14, 0.15),
	)


func _draw_scale(chart: Rect2, bounds: Rect2) -> void:
	var metres_per_px := bounds.size.x / chart.size.x
	var target_m := metres_per_px * 100.0
	var nice := _nice_distance(target_m)
	var width := nice / metres_per_px
	var origin := chart.position + Vector2(18.0, chart.size.y - 22.0)
	draw_line(origin, origin + Vector2(width, 0.0), Color(0.08, 0.14, 0.15), 2.0)
	draw_line(origin, origin + Vector2(0.0, -5.0), Color(0.08, 0.14, 0.15), 2.0)
	draw_line(origin + Vector2(width, 0.0), origin + Vector2(width, -5.0), Color(0.08, 0.14, 0.15), 2.0)
	draw_string(
		ThemeDB.fallback_font,
		origin + Vector2(0.0, -7.0),
		_format_distance(nice),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.08, 0.14, 0.15),
	)


func _draw_status(chart: Rect2) -> void:
	var text := ""
	if mode == Mode.HOME_PORT_PICK:
		if selected_port.is_empty():
			text = "SELECT A HARBOUR ON THE CHART   ·   ESC BACK"
		else:
			var info: Dictionary = data.port_info(selected_port) if data != null else {}
			text = "SELECTED  %s   ·   CONFIRM IN THE PANEL   ·   ESC BACK" % \
					str(info.get("display_name", selected_port)).to_upper()
	else:
		text = "HDG %s   COG %s   SOG %.1f kt   WIND %s %.1f kt   FUEL %s   TIME %s" % [
			_format_degrees(nav.heading_deg if nav.has_ship() else NAN),
			_format_degrees(nav.course_deg),
			nav.speed_knots,
			_format_degrees(nav.wind_direction_deg),
			nav.wind_speed_knots,
			("%.0f%%" % (nav.fuel_fraction * 100.0)) if is_finite(nav.fuel_fraction) else "—",
			nav.time_label,
		]
	draw_string(
		ThemeDB.fallback_font,
		Vector2(chart.position.x, chart.end.y + 17.0),
		text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.76, 0.82, 0.78),
	)
	if not hover_rows.is_empty():
		draw_string(
			ThemeDB.fallback_font,
			Vector2(chart.position.x, chart.end.y + 35.0),
			"   ·   ".join(hover_rows),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.66, 0.74, 0.70),
		)


static func _nice_distance(value: float) -> float:
	var power := pow(10.0, floorf(log(value) / log(10.0)))
	var normalized := value / power
	var step := 1.0
	if normalized >= 5.0:
		step = 5.0
	elif normalized >= 2.0:
		step = 2.0
	return step * power


static func _format_distance(metres: float) -> String:
	return "%.0f m" % metres if metres < 1852.0 else "%.1f nm" % (metres / 1852.0)


static func _format_degrees(value: float) -> String:
	return "%03d°" % roundi(value) if is_finite(value) else "—"
