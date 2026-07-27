class_name HarbourBoardPanel
extends Control

## Compact harbour ops status for the chart Harbour profile.
## Geometry lives on the chart birdseye (ChartHarbourPlan) — this is the readout.

signal berth_chosen(berth_id: String)

const PAD := 12.0

var _port_id := ""
var _plot: PortPlot
var _selected_berth := ""
var _read_only := true
var _row_rects: Dictionary = {} ## berth_id -> Rect2


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(320, 220)
	theme = BrandTheme.shared()


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
	if not harbour.equipment_plugged.is_connected(_on_equipment_changed):
		harbour.equipment_plugged.connect(_on_equipment_changed)
	if not harbour.equipment_unplugged.is_connected(_on_equipment_id_changed):
		harbour.equipment_unplugged.connect(_on_equipment_id_changed)


func _unbind_harbour_signals() -> void:
	var harbour := _harbour()
	if harbour == null:
		return
	if harbour.ship_plugged.is_connected(_on_harbour_changed):
		harbour.ship_plugged.disconnect(_on_harbour_changed)
	if harbour.ship_unplugged.is_connected(_on_harbour_changed):
		harbour.ship_unplugged.disconnect(_on_harbour_changed)
	if harbour.equipment_plugged.is_connected(_on_equipment_changed):
		harbour.equipment_plugged.disconnect(_on_equipment_changed)
	if harbour.equipment_unplugged.is_connected(_on_equipment_id_changed):
		harbour.equipment_unplugged.disconnect(_on_equipment_id_changed)


func _on_harbour_changed(_berth_id: String = "", _ship: BoatBody = null) -> void:
	queue_redraw()


func _on_equipment_changed(_equip_id: String = "", _ship: BoatBody = null, _mode: String = "") -> void:
	queue_redraw()


func _on_equipment_id_changed(_equip_id: String = "") -> void:
	queue_redraw()


func selected_berth_id() -> String:
	return _selected_berth


func clear_selection() -> void:
	_selected_berth = ""
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if _read_only:
		return
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
			var hit := _hit_row(mouse.position)
			if hit.is_empty():
				return
			var harbour := _harbour()
			if harbour != null and harbour.moored_ship(hit) != null:
				return
			_selected_berth = hit
			berth_chosen.emit(hit)
			queue_redraw()
			accept_event()


func _hit_row(local_pos: Vector2) -> String:
	for berth_id in _row_rects.keys():
		var rect: Rect2 = _row_rects[berth_id]
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
	_row_rects.clear()
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, BrandTokens.SEA_DEEP)
	draw_rect(rect, BrandTokens.SEA_LINE, false, 1.0)

	var data := _plot.port_data() if _plot != null else null
	var harbour := _harbour()
	var snap: Dictionary = harbour.snapshot() if harbour != null else {}
	var berths: Array = snap.get("berths", []) as Array
	var jobs: Array = snap.get("jobs", []) as Array

	var port_name := _port_id if not _port_id.is_empty() else "Harbour"
	var export_id := ""
	var imports: Array = []
	if data != null:
		port_name = data.display_name
		export_id = data.commodity_export
		imports = data.commodity_imports
	else:
		var tree := Engine.get_main_loop() as SceneTree
		if tree != null:
			var reg := tree.root.get_node_or_null("/root/PortCatalog")
			if reg != null and not _port_id.is_empty():
				var info: Dictionary = reg.call("get_port_info", _port_id) as Dictionary
				if not info.is_empty():
					port_name = str(info.get("display_name", _port_id))
					export_id = str(info.get("commodity_export", ""))
					imports = info.get("commodity_imports", []) as Array

	draw_string(
		BrandTheme.font_data(),
		Vector2(PAD, 20.0),
		"HARBOUR OPS — %s" % port_name.to_upper(),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, BrandTokens.INK_INVERSE,
	)
	var export_label := CommodityCatalog.commodity_display(export_id) if not export_id.is_empty() \
			else "—"
	var import_bits: PackedStringArray = PackedStringArray()
	for raw in imports:
		import_bits.append(CommodityCatalog.commodity_display(str(raw)))
	var import_line := ", ".join(import_bits) if not import_bits.is_empty() else "—"
	var free_n := 0
	var taken_n := 0
	for raw in berths:
		if bool((raw as Dictionary).get("free", true)):
			free_n += 1
		else:
			taken_n += 1
	draw_string(
		BrandTheme.font_data(),
		Vector2(PAD, 38.0),
		"Export %s · Imports %s" % [export_label, import_line],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, BrandTokens.BRASS_DEEP,
	)
	draw_string(
		BrandTheme.font_data(),
		Vector2(PAD, 54.0),
		"%d free / %d taken · %d jobs" % [free_n, taken_n, jobs.size()],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, BrandTokens.INK_INVERSE_DIM,
	)

	var y := 72.0
	if berths.is_empty():
		draw_string(
			BrandTheme.font_data(),
			Vector2(PAD, y + 16.0),
			"No live berth board — sail closer for occupancy",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, BrandTokens.INK_INVERSE_DIM,
		)
	else:
		for raw in berths:
			var row := raw as Dictionary
			var berth_id := str(row.get("berth_id", ""))
			var free := bool(row.get("free", true))
			var family := str(row.get("family", "general"))
			var station := str(row.get("station_id", berth_id)).get_file()
			if station.length() > 22:
				station = station.substr(0, 21) + "…"
			var ship_id := str(row.get("ship_id", "")).strip_edges()
			var equip_n := (row.get("equip_ids", []) as Array).size()
			var row_rect := Rect2(PAD, y - 2.0, size.x - PAD * 2.0, 36.0)
			_row_rects[berth_id] = row_rect
			var fill := CommodityCatalog.terminal_family_color(family)
			fill.a = 0.22 if free else 0.4
			if berth_id == _selected_berth:
				fill = BrandTokens.BRASS
				fill.a = 0.35
			draw_rect(row_rect, fill)
			draw_rect(row_rect, BrandTokens.alpha(BrandTokens.SEA_LINE, 0.8), false, 1.0)
			var status := "FREE" if free else "TAKEN"
			draw_string(
				BrandTheme.font_data(),
				Vector2(PAD + 6.0, y + 12.0),
				"%s  %s" % [status, station],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 10, BrandTokens.INK_INVERSE,
			)
			var detail := CommodityCatalog.terminal_family_display(family)
			if equip_n > 0:
				detail += " · %d crane%s" % [equip_n, "s" if equip_n != 1 else ""]
			if not free and not ship_id.is_empty():
				detail += " · %s" % ship_id
			draw_string(
				BrandTheme.font_data(),
				Vector2(PAD + 6.0, y + 26.0),
				detail,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 9, BrandTokens.INK_INVERSE_DIM,
			)
			y += 40.0
			if y > size.y - 28.0:
				break

	draw_string(
		BrandTheme.font_data(),
		Vector2(PAD, size.y - 10.0),
		"Plan outline is on the chart · this panel is occupancy only",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 9, BrandTokens.INK_INVERSE_DIM,
	)
