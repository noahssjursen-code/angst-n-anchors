class_name MapOverlay
extends Control

## Full-screen, north-up marine chart. Navigation mode, or home-port pick
## (select a harbour → review info → confirm).

signal close_requested
signal home_port_confirmed(port_id: String)
signal home_port_cancelled
signal port_selected(port_id: String)
signal plot_selected(plot: Dictionary)
signal plot_action_requested(plot: Dictionary)

enum Mode { NAVIGATION, HOME_PORT_PICK }

const CameraModel := preload("res://scripts/ui/chart/chart_camera.gd")
const LayerManager := preload("res://scripts/ui/chart/chart_layer_manager.gd")
const Renderer := preload("res://scripts/ui/chart/chart_layer_renderer.gd")
const Snapshot := preload("res://scripts/ui/chart/chart_data_snapshot.gd")

const FRAME := 26.0
const TOP_H := 58.0
const BOTTOM_H := 48.0
const NAV_REFRESH_S := 0.35
const OVERLAY_DEBOUNCE_S := 0.28
const INTERACTION_SETTLE_S := 0.16

var mode := Mode.NAVIGATION
var preview_mode := false
var data
var camera := CameraModel.new()
var layers := LayerManager.new()
var renderer := Renderer.new()
var nav := ChartNavSnapshot.new()

var selected_port := ""
var selected_plot := ""
var hover_plot := ""
var home_port_required_family := ""
var hover_screen := Vector2(-1.0, -1.0)
var dragging := false
var drag_origin_mouse := Vector2.ZERO
var drag_origin_center := Vector2.ZERO
var drag_distance := 0.0
var nav_elapsed := NAV_REFRESH_S
var overlay_debounce := 0.0
var overlays_dirty := true
var first_visible_frame := true
var camera_initialized := false
var weather_elapsed := 0.0
var interaction_settle := 0.0
var last_ctx: Dictionary = {}
var hover_rows: Array[String] = []
var hover_sample_screen := Vector2(-1000.0, -1000.0)
var hover_layer_revision := -1

var title_label: Label
var hint_label: Label
var weather_button: Button
var center_button: Button
var close_button: Button
var plots_button: Button
var zoom_in_button: Button
var zoom_out_button: Button
var plot_panel: PanelContainer
var plot_heading: Label
var plot_meta: Label
var plot_body: Label
var plot_focus: Button
var plot_action: Button
var plot_note: Label
var plot_inspector_provider := Callable()
var chart_clip: Control
var geography_surface: ChartSurface
var contact_surface: ChartSurface

var pick_panel: PanelContainer
var pick_title: Label
var pick_meta: Label
var pick_body: RichTextLabel
var pick_confirm: Button
var pick_back: Button


func _ready() -> void:
	add_to_group("marine_chart")
	# CanvasLayer / Node parents do not supply a Control layout rectangle.
	# This is a full-viewport overlay in gameplay and in isolated previews.
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	_sync_viewport_size()
	get_viewport().size_changed.connect(_sync_viewport_size)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_build_surfaces()
	_build_toolbar()
	_build_pick_panel()
	_build_plot_panel()
	resized.connect(_redraw_geography)
	_load_layer_preferences()
	_apply_mode_ui()
	_refresh_pick_panel()


func _exit_tree() -> void:
	ChartBaseRaster.finish_pending_detail()


func set_data_snapshot(snapshot) -> void:
	var same_world: bool = data != null and snapshot != null \
		and data.layout_checksum == snapshot.layout_checksum \
		and data.world_size_m == snapshot.world_size_m
	data = snapshot
	renderer.set_snapshot(data)
	if data != null and data.layout != null:
		camera.configure_world(float(data.layout.half_extent_m))
	if not same_world:
		camera.user_moved = false
		camera_initialized = false
	overlays_dirty = true
	first_visible_frame = true
	if not selected_plot.is_empty() and (renderer.plots.index == null \
			or renderer.plots.index.get_plot(selected_plot).is_empty()):
		selected_plot = ""
	_refresh_plot_panel()
	_redraw_geography()


func enter_home_port_pick_mode(preselect_port_id: String = "") -> void:
	mode = Mode.HOME_PORT_PICK
	camera_initialized = false
	selected_port = preselect_port_id.strip_edges()
	layers.apply_preset(ChartLayerManager.Preset.NAVIGATION)
	layers.set_visible("routes", false)
	layers.set_visible("approaches", false)
	## Home-port selection shows geography, not hidden fish populations.
	layers.set_visible("weather", false)
	layers.set_visible("plots", false)
	_apply_mode_ui()
	_refresh_mode_buttons()
	_refresh_pick_panel()
	camera.user_moved = false
	overlays_dirty = true
	overlay_debounce = 0.0
	first_visible_frame = true
	visible = true
	_redraw_geography()


func set_home_port_required_family(family: String) -> void:
	home_port_required_family = family.strip_edges()
	_refresh_pick_panel()


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
	if not preview_mode and (data == null or not data.is_valid() or not data.matches_live_tree(get_tree())):
		set_data_snapshot(Snapshot.from_live_tree(get_tree()))
	## Reload prefs — home-port pick forces its own overlay set and must not
	## stick on the shared gameplay chart after the captain sails.
	_load_layer_preferences()
	_apply_mode_ui()
	overlays_dirty = true
	overlay_debounce = 0.0
	first_visible_frame = true
	visible = true
	_redraw_geography()


func get_debug_stats() -> Dictionary:
	var stats := renderer.debug_stats()
	stats["preset"] = ChartLayerManager.PRESET_NAMES[layers.preset]
	return stats


func ensure_live_data() -> bool:
	## Home-port pick uses the preview snapshot only — never rebuild from the
	## live world tree (and never thrash PortCatalog while the menu is up).
	if mode == Mode.HOME_PORT_PICK or preview_mode:
		return data != null and data.is_valid()
	if data == null or not data.is_valid() or not data.matches_live_tree(get_tree()):
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
	if ChartBaseRaster.poll_detail() or renderer.base.needs_redraw():
		_redraw_geography()
	if interaction_settle > 0.0:
		interaction_settle = maxf(interaction_settle - delta, 0.0)
		if interaction_settle <= 0.0:
			## One detailed redraw after movement settles. Expensive layers never
			## execute in the mouse-motion path.
			_redraw_geography()
	if first_visible_frame:
		if mode != Mode.HOME_PORT_PICK:
			_capture_nav()
		if not camera_initialized:
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
			_redraw_contacts()
		weather_elapsed += delta
		if weather_elapsed >= 1.0 and layers.is_visible("weather") and not dragging:
			weather_elapsed = 0.0
			var previous := renderer.weather.rebuild_count
			renderer.prepare_overlays(_camera_bounds(), layers, WeatherField.current_game_time())
			if renderer.weather.rebuild_count != previous:
				_redraw_geography()
	if overlays_dirty:
		overlay_debounce -= delta
		if overlay_debounce <= 0.0 and not dragging:
			renderer.prepare_overlays(
				_camera_bounds(),
				layers,
				WeatherField.current_game_time(),
			)
			overlays_dirty = false
			_redraw_geography()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		hover_screen = motion.position
		if dragging:
			interaction_settle = INTERACTION_SETTLE_S
			drag_distance += motion.relative.length()
			camera.pan_pixels(
				motion.position - drag_origin_mouse,
				camera.pixels_per_world_unit(_chart_rect().size),
				drag_origin_center,
			)
			## Skip weather/fishing hover samples while panning — those compose
			## per cursor move and dominate drag lag when overlays are on.
			_redraw_geography()
			return
		_refresh_hover_readout()
		_redraw_contacts()
		return
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		hover_screen = mouse.position
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
				_refresh_hover_readout(true)
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
	elif key.keycode == KEY_G and mode != Mode.HOME_PORT_PICK:
		_toggle_overlay("plots")
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
	_draw_status(chart)


func _build_surfaces() -> void:
	chart_clip = Control.new()
	chart_clip.name = "ChartClip"
	chart_clip.clip_contents = true
	chart_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(chart_clip)
	geography_surface = ChartSurface.new()
	geography_surface.name = "CachedGeography"
	geography_surface.chart = self
	geography_surface.geography = true
	geography_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chart_clip.add_child(geography_surface)
	contact_surface = ChartSurface.new()
	contact_surface.name = "NavigationAndSelection"
	contact_surface.chart = self
	contact_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chart_clip.add_child(contact_surface)


func _sync_viewport_size() -> void:
	position = Vector2.ZERO
	size = get_viewport_rect().size
	_redraw_geography()


func surface_context() -> Dictionary:
	var chart := _chart_rect()
	return {"chart_rect": Rect2(Vector2.ZERO, chart.size),
		"world_bounds": camera.world_bounds(chart.size), "world_span": camera.span}


func _redraw_geography() -> void:
	var chart := _chart_rect()
	last_ctx = {"chart_rect": chart, "world_bounds": camera.world_bounds(chart.size),
		"world_span": camera.span}
	if chart_clip != null:
		chart_clip.position = chart.position
		chart_clip.size = chart.size
		geography_surface.size = chart.size
		contact_surface.size = chart.size
		geography_surface.queue_redraw()
	_redraw_contacts()


func _redraw_contacts() -> void:
	if contact_surface != null:
		contact_surface.queue_redraw()
	queue_redraw()


func _build_plot_panel() -> void:
	plot_panel = Ui.sheet()
	plot_panel.name = "CoastalPlotInspector"
	plot_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	plot_panel.offset_left = -FRAME - 294.0
	plot_panel.offset_right = -FRAME - 12.0
	plot_panel.offset_top = TOP_H + 14.0
	plot_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(plot_panel)
	var body := Ui.vbox(9)
	plot_panel.add_child(body)
	body.add_child(Ui.eyebrow("Coastal plots"))
	plot_heading = Ui.heading("Choose a stretch of coast")
	plot_heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(plot_heading)
	plot_meta = Ui.caption("200 × 200 m per plot", "positive")
	body.add_child(plot_meta)
	plot_body = Ui.caption("Click a green square to inspect it.\nAdjoining coast plots are highlighted.")
	plot_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	plot_body.custom_minimum_size.x = 246.0
	body.add_child(plot_body)
	plot_focus = Ui.button("Zoom to plot", "secondary", _focus_plot)
	body.add_child(plot_focus)
	plot_action = Ui.button("Buy plot", "primary", _request_plot_action)
	body.add_child(plot_action)
	plot_note = Ui.caption("Property purchases come later.")
	body.add_child(plot_note)
	_refresh_plot_panel()


## Optional host-owned plot information/action. The ordinary navigation chart
## remains inspection-only unless a host explicitly supplies this presentation.
func set_plot_inspector(provider: Callable) -> void:
	plot_inspector_provider = provider
	_refresh_plot_panel()


func _request_plot_action() -> void:
	if plot_action == null or not plot_action.visible or plot_action.disabled or not plot_inspector_provider.is_valid(): return
	var row := renderer.plots.index.get_plot(selected_plot) if renderer.plots.index != null else {}
	if not row.is_empty(): plot_action_requested.emit(row.duplicate(true))


func _refresh_plot_panel() -> void:
	if plot_panel == null:
		return
	plot_panel.visible = mode == Mode.NAVIGATION and layers.is_visible("plots")
	var row := renderer.plots.index.get_plot(selected_plot) if renderer.plots.index != null else {}
	plot_focus.visible = not row.is_empty()
	plot_action.hide()
	plot_note.visible = not plot_inspector_provider.is_valid()
	if plot_inspector_provider.is_valid():
		var content: Variant = plot_inspector_provider.call(row.duplicate(true))
		if content is Dictionary:
			plot_heading.text = str(content.get("heading", "Choose a plot"))
			plot_meta.text = str(content.get("meta", ""))
			plot_body.text = str(content.get("body", ""))
			plot_action.text = str(content.get("action_text", "Buy plot"))
			plot_action.visible = bool(content.get("action_visible", false)) and not row.is_empty()
			plot_action.disabled = not bool(content.get("action_enabled", false))
			return
	if row.is_empty():
		plot_heading.text = "Choose a stretch of coast"
		plot_meta.text = "200 × 200 m · 4 hectares"
		plot_body.text = "Click a green square to inspect it.\nAdjoining coast plots are highlighted."
		return
	var grid: Array = row.get("grid", [0, 0])
	plot_heading.text = "Coast plot %s / %s" % [grid[0], grid[1]]
	plot_meta.text = "200 × 200 m · 4 hectares"
	plot_body.text = "Shoreline  %.0f m\nAdjoining plots  %d\n\n%s" % [
		float(row.get("shore_length_m", 0.0)), renderer.plots.index.neighbour_ids(selected_plot).size(),
		"Near an existing harbour" if _plot_near_port(row) else "Coastal land and waterfront"]
	if bool(row.get("boundary_review_required", false)):
		plot_body.text += "\nBoundary needs review before purchase."


func _plot_near_port(row: Dictionary) -> bool:
	if data == null:
		return false
	var bounds := ChartPlotLayer.plot_rect(row).grow(400.0)
	for port in data.ports:
		var point := port.get("position", Vector3.INF) as Vector3
		if point.is_finite() and bounds.has_point(Vector2(point.x, point.z)):
			return true
	return false


func _focus_plot() -> void:
	if renderer.plots.index == null:
		return
	var row := renderer.plots.index.get_plot(selected_plot)
	if row.is_empty():
		return
	var rect := ChartPlotLayer.plot_rect(row)
	camera.focus_harbour(rect.get_center(), 1800.0)
	_schedule_overlays()
	_redraw_geography()


func _build_pick_panel() -> void:
	pick_panel = Ui.sheet()
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
	add_child(pick_panel)

	var vbox := Ui.vbox(10)
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pick_panel.add_child(vbox)
	vbox.add_child(Ui.eyebrow("Home harbour"))

	pick_title = Ui.heading("Select a harbour")
	pick_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(pick_title)

	pick_meta = Ui.caption("Click a marker on the chart", "caution")
	pick_meta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(pick_meta)

	pick_body = RichTextLabel.new()
	pick_body.bbcode_enabled = true
	pick_body.fit_content = true
	pick_body.scroll_active = false
	pick_body.custom_minimum_size = Vector2(0, 120)
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

	pick_back = Ui.button("Back", "ghost", func() -> void: home_port_cancelled.emit())
	pick_back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(pick_back)

	pick_confirm = Ui.button("Sail from here", "primary", _confirm_home_port)
	pick_confirm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pick_confirm.disabled = true
	row.add_child(pick_confirm)


func _confirm_home_port() -> void:
	if mode != Mode.HOME_PORT_PICK:
		return
	if selected_port.is_empty():
		return
	if data!=null and str(data.port_info(selected_port).get("source",""))=="custom":return
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
				"Your home port is where you begin. Look for a harbour that matches the trade you want — ore, grain, general cargo, or containers."
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
	if str(info.get("source",""))=="custom":
		pick_meta.text="Constructed port · %d constructed berths"%int(info.get("derived_berth_count",0))
		pick_body.text="Company ref: %s\nHome-port selection is unavailable for this constructed port."%str(info.get("owner_company_id","—"))
		if pick_confirm!=null:pick_confirm.disabled=true
		return
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
	var compatible := _home_port_supports_required_family(info)
	var compatibility_line := ""
	if not compatible:
		compatibility_line = "\n[color=#e27a63]This harbour has no %s berth for your selected starter vessel.[/color]" \
				% CommodityCatalog.terminal_family_display(home_port_required_family)
	pick_body.text = "\n".join(PackedStringArray([
		"[color=#8a9a94]Population[/color]  %s" % _format_population(int(info.get("population", 0))),
		"[color=#8a9a94]Primary export[/color]  %s" % export_label,
		"[color=#8a9a94]Imports[/color]  %s" % import_line,
		"[color=#8a9a94]Max class[/color]  %s" % ship_class,
		"[color=#8a9a94]Facilities[/color]  %s" % features_line,
	])) + compatibility_line
	if pick_confirm != null:
		pick_confirm.disabled = not compatible


func _home_port_supports_required_family(info: Dictionary) -> bool:
	if str(info.get("source",""))=="custom":return false
	if home_port_required_family.is_empty():
		return true
	if home_port_required_family == "fishing":
		return bool(info.get("has_fish_landing", false)) \
				and (info.get("features", []) as Array).has("Fish Landing")
	var commodity_ids: Array = []
	commodity_ids.append_array(info.get("export_slots", []) as Array)
	commodity_ids.append_array(info.get("commodity_imports", []) as Array)
	for raw in commodity_ids:
		var family := CommodityCatalog.commodity_terminal_family(str(raw))
		if family == home_port_required_family \
				or (home_port_required_family == "bulk" and family.begins_with("bulk_")):
			return true
	return false


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

	title_label = Ui.eyebrow("Navigation chart")
	title_label.custom_minimum_size.x = 220.0
	bar.add_child(title_label)

	hint_label = Ui.caption("Click a harbour for details, then confirm")
	hint_label.visible = false
	hint_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(hint_label)

	weather_button = Ui.button("Weather", "chip")
	weather_button.pressed.connect(_toggle_overlay.bind("weather"))
	bar.add_child(weather_button)
	plots_button = Ui.button("Coastal plots · G", "chip")
	plots_button.toggle_mode = true
	plots_button.pressed.connect(_toggle_overlay.bind("plots"))
	bar.add_child(plots_button)
	var depth_key := Ui.caption("Depth m: light <10 / 25 / 50 / 100 / 200+ dark")
	depth_key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(depth_key)
	zoom_out_button = Ui.button("−", "secondary", func() -> void:
		_zoom_at(_chart_rect().get_center(), -1))
	zoom_out_button.tooltip_text = "Zoom out"
	bar.add_child(zoom_out_button)
	zoom_in_button = Ui.button("+", "secondary", func() -> void:
		_zoom_at(_chart_rect().get_center(), 1))
	zoom_in_button.tooltip_text = "Zoom in"
	bar.add_child(zoom_in_button)

	center_button = Ui.button("Center", "secondary", _home)
	bar.add_child(center_button)

	close_button = Ui.button("Close", "ghost", func() -> void: close_requested.emit())
	bar.add_child(close_button)
	_refresh_mode_buttons()


func _apply_mode_ui() -> void:
	var picking := mode == Mode.HOME_PORT_PICK
	if title_label != null:
		title_label.text = "CHOOSE YOUR HOME PORT" if picking else "NAVIGATION CHART"
	if hint_label != null:
		hint_label.visible = picking
		if picking:
			hint_label.text = "Click a harbour for details, then confirm"
	if weather_button != null:
		weather_button.visible = not picking
	if center_button != null:
		center_button.visible = not picking
	if close_button != null:
		close_button.visible = not picking
	if pick_panel != null:
		pick_panel.visible = picking
	if pick_back != null:
		pick_back.visible = picking
	if plots_button != null:
		plots_button.visible = not picking
	_refresh_plot_panel()


func _refresh_mode_buttons() -> void:
	if weather_button != null:
		weather_button.set_pressed_no_signal(layers.is_visible("weather"))
	if plots_button != null:
		plots_button.set_pressed_no_signal(layers.is_visible("plots"))


func _toggle_overlay(layer_name: String) -> void:
	if mode == Mode.HOME_PORT_PICK:
		return
	layers.toggle(layer_name)
	_refresh_mode_buttons()
	_refresh_plot_panel()
	if mode != Mode.HOME_PORT_PICK:
		_persist_chart_settings()
	_refresh_hover_readout(true)
	_schedule_overlays()
	_redraw_geography()


func _load_layer_preferences() -> void:
	var settings := get_node_or_null("/root/GameSettings")
	if settings == null:
		return
	## Legacy fishing preferences are ignored.
	layers.apply_preset(int(settings.get("chart_profile")))
	layers.set_visible("plots", true)
	layers.set_overlay_preferences(
		bool(settings.get("chart_weather_enabled")),
		false,
	)
	_refresh_mode_buttons()


func _persist_chart_settings() -> void:
	var settings := get_node_or_null("/root/GameSettings")
	if settings == null:
		return
	settings.set("chart_weather_enabled", layers.is_visible("weather"))
	settings.set("chart_fishing_enabled", false)
	settings.set("chart_profile", layers.preset)
	if settings.has_method("save_settings"):
		settings.call("save_settings")


func _click_chart(screen: Vector2) -> void:
	var hit := renderer.hit_test_port(screen, last_ctx, 28.0 if mode == Mode.HOME_PORT_PICK else 18.0)
	if hit.is_empty() and mode == Mode.NAVIGATION and layers.is_visible("plots") and renderer.plots.index != null:
		var row := renderer.plots.index.plot_at(renderer.world_at(screen, last_ctx))
		if not row.is_empty() and renderer.plots.allows_plot(str(row.get("id", ""))):
			selected_plot = str(row.get("id", ""))
			selected_port = ""
			_refresh_plot_panel()
			plot_selected.emit(row.duplicate(true))
			_redraw_contacts()
			return
	if hit.is_empty():
		if mode == Mode.NAVIGATION:
			selected_port = ""
			selected_plot = ""
			_refresh_plot_panel()
			_redraw_contacts()
		return
	selected_port = hit
	selected_plot = ""
	_refresh_plot_panel()
	if mode == Mode.HOME_PORT_PICK:
		_refresh_pick_panel()
		_redraw_contacts()
	else:
		port_selected.emit(hit)
		_redraw_contacts()


func _home() -> void:
	if data == null:
		return
	camera.home(nav.ship_position, data.port_positions())
	camera_initialized = true
	_schedule_overlays()
	_redraw_geography()


func _zoom_at(screen: Vector2, steps: int) -> void:
	var chart := _chart_rect()
	var before := _screen_to_world(screen)
	camera.zoom(steps)
	var bounds := camera.world_bounds(chart.size)
	var uv := (screen - chart.position) / chart.size
	var after := bounds.position + uv * bounds.size
	camera.center += before - after
	camera._clamp_center()
	interaction_settle = INTERACTION_SETTLE_S
	_schedule_overlays()
	_redraw_geography()


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
	if plot_panel != null and plot_panel.visible and plot_panel.get_global_rect().has_point(screen):
		return true
	var toolbar := get_node_or_null("ChartToolbar") as Control
	if toolbar != null and toolbar.get_global_rect().has_point(screen):
		return true
	return false


func _refresh_hover_readout(force: bool = false) -> void:
	if not _chart_rect().has_point(hover_screen) or _pointer_over_chrome(hover_screen):
		hover_rows.clear()
		hover_plot = ""
		return
	if (
		not force
		and hover_screen.distance_to(hover_sample_screen) < 4.0
		and hover_layer_revision == layers.revision
	):
		return
	hover_sample_screen = hover_screen
	hover_plot = ""
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
	if layers.is_visible("plots") and renderer.plots.index != null:
		var row := renderer.plots.index.plot_at(_screen_to_world(hover_screen))
		if not row.is_empty() and renderer.plots.allows_plot(str(row.get("id", ""))):
			hover_plot = str(row.get("id", ""))
			var grid: Array = row.get("grid", [0, 0])
			hover_rows.append("COAST PLOT %s / %s · 200 × 200 m" % [grid[0], grid[1]])


func _draw_compass(chart: Rect2, canvas: CanvasItem) -> void:
	var center := chart.position + Vector2(34.0, 35.0)
	canvas.draw_circle(center, 22.0, Color(0.94, 0.93, 0.84, 0.90))
	canvas.draw_arc(center, 22.0, 0.0, TAU, 32, Color(0.10, 0.18, 0.20), 1.0)
	canvas.draw_line(center, center + Vector2(0.0, -17.0), Color(0.78, 0.12, 0.10), 2.0)
	canvas.draw_string(
		ThemeDB.fallback_font,
		center + Vector2(-4.0, -4.0),
		"N",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.08, 0.14, 0.15),
	)


func _draw_scale(chart: Rect2, bounds: Rect2, canvas: CanvasItem) -> void:
	var metres_per_px := bounds.size.x / chart.size.x
	var target_m := metres_per_px * 100.0
	var nice := _nice_distance(target_m)
	var width := nice / metres_per_px
	var origin := chart.position + Vector2(18.0, chart.size.y - 22.0)
	canvas.draw_line(origin, origin + Vector2(width, 0.0), Color(0.08, 0.14, 0.15), 2.0)
	canvas.draw_line(origin, origin + Vector2(0.0, -5.0), Color(0.08, 0.14, 0.15), 2.0)
	canvas.draw_line(origin + Vector2(width, 0.0), origin + Vector2(width, -5.0), Color(0.08, 0.14, 0.15), 2.0)
	canvas.draw_string(
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
