class_name HarbourBoardPanel
extends Control

## Schematic harbour board for the marine chart (Harbour profile).
## Data from HarbourController.snapshot + PortCatalog / PortData trade.

signal berth_chosen(berth_id: String)

const PAD := 12.0

var _port_id := ""
var _plot: PortPlot
var _selected_berth := ""
var _hover_berth := ""
var _berth_rects: Dictionary = {} ## berth_id -> Rect2
var _read_only := true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(360, 260)
	theme = HudStyle.make_theme()


func bind_port(port_id: String, plot: PortPlot = null, read_only: bool = true) -> void:
	_unbind_harbour_signals()
	_port_id = port_id.strip_edges()
	_plot = plot
	if _plot == null and not _port_id.is_empty():
		var harbour := HarbourRegistry.controller(_port_id)
		if harbour != null:
			_plot = harbour.get_parent() as PortPlot
	_read_only = read_only
	_selected_berth = ""
	_hover_berth = ""
	_bind_harbour_signals()
	queue_redraw()


func _bind_harbour_signals() -> void:
	var harbour := _harbour()
	if harbour == null:
		return
	if not harbour.ship_plugged.is_connected(_on_harbour_changed):
		harbour.ship_plugged.connect(_on_harbour_changed)
	if not harbour.ship_unplugged.is_connected(_on_harbour_changed):
		harbour.ship_unplugged.connect(_on_harbour_changed)


func _unbind_harbour_signals() -> void:
	var harbour := _harbour()
	if harbour == null:
		return
	if harbour.ship_plugged.is_connected(_on_harbour_changed):
		harbour.ship_plugged.disconnect(_on_harbour_changed)
	if harbour.ship_unplugged.is_connected(_on_harbour_changed):
		harbour.ship_unplugged.disconnect(_on_harbour_changed)


func _on_harbour_changed(_berth_id: String = "", _ship: BoatBody = null) -> void:
	queue_redraw()


func selected_berth_id() -> String:
	return _selected_berth


func clear_selection() -> void:
	_selected_berth = ""
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if _read_only:
		if event is InputEventMouseMotion:
			var next := _hit_berth((event as InputEventMouseMotion).position)
			if next != _hover_berth:
				_hover_berth = next
				queue_redraw()
		return
	if event is InputEventMouseMotion:
		var next2 := _hit_berth((event as InputEventMouseMotion).position)
		if next2 != _hover_berth:
			_hover_berth = next2
			queue_redraw()
	elif event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
			var hit := _hit_berth(mouse.position)
			if hit.is_empty():
				return
			var harbour := _harbour()
			if harbour != null and harbour.moored_ship(hit) != null:
				return
			_selected_berth = hit
			berth_chosen.emit(hit)
			queue_redraw()
			accept_event()


func _hit_berth(local_pos: Vector2) -> String:
	for berth_id in _berth_rects.keys():
		var rect: Rect2 = _berth_rects[berth_id]
		if rect.has_point(local_pos):
			return str(berth_id)
	return ""


func _harbour() -> HarbourController:
	if _plot != null:
		return _plot.harbour_controller()
	if not _port_id.is_empty():
		return HarbourRegistry.controller(_port_id)
	return null


func _draw() -> void:
	_berth_rects.clear()
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, HudStyle.C_BG)
	draw_rect(rect, HudStyle.C_BRASS, false, 1.0)

	var data := _plot.port_data() if _plot != null else null
	var harbour := _harbour()
	var snap: Dictionary = harbour.snapshot() if harbour != null else {}
	var berths: Array = snap.get("berths", []) as Array

	var export_id := ""
	var imports: Array = []
	var port_name := _port_id if not _port_id.is_empty() else "Harbour"
	if data != null:
		export_id = data.commodity_export
		imports = data.commodity_imports
		port_name = data.display_name
	else:
		var catalog := Engine.get_main_loop() as SceneTree
		if catalog != null:
			var reg := catalog.root.get_node_or_null("/root/PortCatalog")
			if reg != null and not _port_id.is_empty():
				var info: Dictionary = reg.call("get_port_info", _port_id) as Dictionary
				if not info.is_empty():
					port_name = str(info.get("display_name", _port_id))
					export_id = str(info.get("commodity_export", ""))
					imports = info.get("commodity_imports", []) as Array

	draw_string(
		ThemeDB.fallback_font,
		Vector2(PAD, 22.0),
		"HARBOUR BOARD — %s" % port_name.to_upper(),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, HudStyle.C_TEXT,
	)
	var export_label := CommodityCatalog.commodity_display(export_id) if not export_id.is_empty() \
			else "—"
	var import_bits: PackedStringArray = PackedStringArray()
	for raw in imports:
		import_bits.append(CommodityCatalog.commodity_display(str(raw)))
	var import_line := ", ".join(import_bits) if not import_bits.is_empty() else "—"
	draw_string(
		ThemeDB.fallback_font,
		Vector2(PAD, 40.0),
		"Export %s   ·   Imports %s" % [export_label, import_line],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, HudStyle.C_COPPER,
	)

	var map_rect := Rect2(
		PAD,
		52.0,
		maxf(size.x - PAD * 2.0, 40.0),
		maxf(size.y - 52.0 - 28.0, 40.0),
	)
	draw_rect(map_rect, Color(0.05, 0.10, 0.14, 0.95))
	draw_rect(map_rect, Color(0.20, 0.32, 0.36, 0.8), false, 1.0)

	if berths.is_empty():
		var msg := "No live berths — sail closer to this harbour"
		if _port_id.is_empty():
			msg = "Select a harbour on the chart"
		draw_string(
			ThemeDB.fallback_font,
			map_rect.position + Vector2(10.0, 28.0),
			msg,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, HudStyle.C_LABEL,
		)
		_draw_legend(rect)
		return

	var bounds := _berth_bounds(berths)
	var pad_m := 18.0
	var world := Rect2(
		bounds.position - Vector2(pad_m, pad_m),
		bounds.size + Vector2(pad_m * 2.0, pad_m * 2.0),
	)
	if world.size.x < 1.0:
		world.size.x = 1.0
	if world.size.y < 1.0:
		world.size.y = 1.0
	var scale := minf(map_rect.size.x / world.size.x, map_rect.size.y / world.size.y)

	for raw in berths:
		var row := raw as Dictionary
		var berth_id := str(row.get("berth_id", ""))
		var xz: Array = row.get("local_xz", [0.0, 0.0]) as Array
		var cx := float(xz[0]) if xz.size() > 0 else 0.0
		var cz := float(xz[1]) if xz.size() > 1 else 0.0
		var length_m := maxf(float(row.get("length_m", 40.0)), 20.0)
		var width_m := maxf(float(row.get("width_m", 24.0)), 12.0)
		var w_px := length_m * scale
		var h_px := clampf(width_m * scale * 0.55, 16.0, 48.0)
		var center := map_rect.position + Vector2(
			(cx - world.position.x) * scale,
			(cz - world.position.y) * scale,
		)
		var berth_rect := Rect2(center - Vector2(w_px, h_px) * 0.5, Vector2(w_px, h_px))
		berth_rect = berth_rect.intersection(map_rect.grow(-2.0))
		if berth_rect.size.x < 4.0 or berth_rect.size.y < 4.0:
			continue
		_berth_rects[berth_id] = berth_rect

		var free := bool(row.get("free", true))
		var family := str(row.get("family", "general"))
		var fill := CommodityCatalog.terminal_family_color(family)
		if free:
			fill = fill.lightened(0.15)
			fill.a = 0.85
		else:
			fill = fill.darkened(0.45)
			fill.a = 0.9
		if berth_id == _selected_berth:
			fill = HudStyle.C_AMBER
		elif berth_id == _hover_berth and free:
			fill = fill.lightened(0.25)
		draw_rect(berth_rect, fill)
		draw_rect(
			berth_rect,
			HudStyle.C_TEXT if berth_id == _selected_berth else Color(0.1, 0.12, 0.12, 0.9),
			false,
			2.0 if berth_id == _selected_berth else 1.0,
		)
		var label := str(row.get("station_id", berth_id)).get_file()
		if label.length() > 14:
			label = label.substr(0, 13) + "…"
		var status := "FREE" if free else "TAKEN"
		draw_string(
			ThemeDB.fallback_font,
			berth_rect.position + Vector2(4.0, 12.0),
			"%s  %s" % [status, label],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
			Color(0.95, 0.96, 0.94) if free else Color(0.75, 0.72, 0.70),
		)
		var family_label := CommodityCatalog.terminal_family_display(family)
		draw_string(
			ThemeDB.fallback_font,
			berth_rect.position + Vector2(4.0, 24.0),
			family_label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 9, HudStyle.C_LABEL,
		)

	_draw_legend(rect)


func _draw_legend(rect: Rect2) -> void:
	var y := rect.size.y - 12.0
	draw_string(
		ThemeDB.fallback_font,
		Vector2(PAD, y),
		"Colour = cargo family   ·   FREE / TAKEN from harbour board",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, HudStyle.C_LABEL,
	)


static func _berth_bounds(berths: Array) -> Rect2:
	var min_v := Vector2(INF, INF)
	var max_v := Vector2(-INF, -INF)
	for raw in berths:
		var row := raw as Dictionary
		var xz: Array = row.get("local_xz", [0.0, 0.0]) as Array
		var p := Vector2(
			float(xz[0]) if xz.size() > 0 else 0.0,
			float(xz[1]) if xz.size() > 1 else 0.0,
		)
		var half := Vector2(
			maxf(float(row.get("length_m", 40.0)), 20.0) * 0.5,
			maxf(float(row.get("width_m", 24.0)), 12.0) * 0.5,
		)
		min_v = min_v.min(p - half)
		max_v = max_v.max(p + half)
	if not min_v.is_finite() or not max_v.is_finite():
		return Rect2(-40, -40, 80, 80)
	return Rect2(min_v, max_v - min_v)
