@tool
class_name ShipwrightNpc
extends NpcInteractable

## Shipwright NPC. Lets the player commission a new vessel from the available hull catalog.
## Writes a minimal ship template to user://shipwright_orders/ and calls ShipBuilder.build().

const HULL_CATALOG: Array[Dictionary] = [
	{
		"id":                 "coastal_trader",
		"display":            "Coastal Trader  •  13 m",
		"ship_class_label":   "Coastal Trader",
		"hull_file":          "hull_coastal_trader.json",
		"superstructure":     "bridge_small",
		"propulsion_thrust":  120000.0,
		"bow_thrust":          35000.0,
		"cam_dist":            20.0,
		"cam_height":           8.0,
	},
	{
		"id":                 "coastal_trader_long",
		"display":            "Coastal Trader, Extended  •  15 m",
		"ship_class_label":   "Coastal Trader",
		"hull_file":          "hull_coastal_trader_long.json",
		"superstructure":     "bridge_small",
		"propulsion_thrust":  155000.0,
		"bow_thrust":          42000.0,
		"cam_dist":            24.0,
		"cam_height":           9.0,
	},
	{
		"id":                 "short_sea_coaster",
		"display":            "Short Sea Coaster  •  22 m",
		"ship_class_label":   "Short Sea Coaster",
		"hull_file":          "hull_short_sea_coaster.json",
		"superstructure":     "bridge_small",
		"propulsion_thrust":  280000.0,
		"bow_thrust":          70000.0,
		"cam_dist":            35.0,
		"cam_height":          12.0,
	},
	{
		"id":                 "short_sea_coaster_long",
		"display":            "Short Sea Coaster, Extended  •  25 m",
		"ship_class_label":   "Short Sea Coaster",
		"hull_file":          "hull_short_sea_coaster_long.json",
		"superstructure":     "bridge_small",
		"propulsion_thrust":  340000.0,
		"bow_thrust":          85000.0,
		"cam_dist":            40.0,
		"cam_height":          13.0,
	},
	{
		"id":                 "handysize_feeder",
		"display":            "Handysize Feeder  •  35 m",
		"ship_class_label":   "Handysize Feeder",
		"hull_file":          "hull_handysize_feeder.json",
		"superstructure":     "bridge_medium",
		"propulsion_thrust":  520000.0,
		"bow_thrust":         120000.0,
		"cam_dist":            55.0,
		"cam_height":          18.0,
	},
	{
		"id":                 "handysize_feeder_long",
		"display":            "Handysize Feeder, Extended  •  40 m",
		"ship_class_label":   "Handysize Feeder",
		"hull_file":          "hull_handysize_feeder_long.json",
		"superstructure":     "bridge_medium",
		"propulsion_thrust":  630000.0,
		"bow_thrust":         145000.0,
		"cam_dist":            65.0,
		"cam_height":          20.0,
	},
	{
		"id":                 "deep_sea_freighter",
		"display":            "Deep Sea Freighter  •  50 m",
		"ship_class_label":   "Deep Sea Freighter",
		"hull_file":          "hull_deep_sea_freighter.json",
		"superstructure":     "bridge_medium",
		"propulsion_thrust":  900000.0,
		"bow_thrust":         200000.0,
		"cam_dist":            80.0,
		"cam_height":          24.0,
	},
	{
		"id":                 "deep_sea_freighter_long",
		"display":            "Deep Sea Freighter, Extended  •  60 m",
		"ship_class_label":   "Deep Sea Freighter",
		"hull_file":          "hull_deep_sea_freighter_long.json",
		"superstructure":     "bridge_medium",
		"propulsion_thrust":  1100000.0,
		"bow_thrust":          250000.0,
		"cam_dist":             95.0,
		"cam_height":           28.0,
	},
]

var _panel: Panel
var _body:  VBoxContainer

enum _Screen { MAIN, HULL_SELECT, CONFIRM }
var _screen:       _Screen     = _Screen.MAIN
var _pending_entry: Dictionary = {}


func _ready() -> void:
	prompt_text = "Press E — Shipwright"
	super._ready()
	if not Engine.is_editor_hint():
		call_deferred("_build_ui")


# ── NpcInteractable hooks ──────────────────────────────────────────────────────

func _on_interact() -> void:
	_show_main()
	_panel.visible = true
	open_ui()


func _on_ui_cancel() -> void:
	if _screen == _Screen.CONFIRM:
		_show_hull_select()
	elif _screen == _Screen.MAIN:
		_panel.visible = false
		close_ui()
	else:
		_show_main()


# ── Screens ───────────────────────────────────────────────────────────────────

func _close() -> void:
	_panel.visible = false
	close_ui()


func _show_main() -> void:
	_screen = _Screen.MAIN
	_clear_body()
	_add_quote("Good day, Captain. Looking to commission a new vessel?\nI can lay down any hull in my catalog.")
	_add_option("Show me what you can build.", _show_hull_select)
	_add_option("Not today, thank you.",        _close)


func _show_hull_select() -> void:
	_screen = _Screen.HULL_SELECT
	_clear_body()
	_add_quote("Choose your hull. I'll build her true.")
	for entry in HULL_CATALOG:
		var e   := entry as Dictionary
		var lbl := "%s  [%s]" % [str(e["display"]), str(e["ship_class_label"])]
		_add_option(lbl, _show_confirm.bind(e))
	_add_back_button()


func _show_confirm(entry: Dictionary) -> void:
	_screen        = _Screen.CONFIRM
	_pending_entry = entry
	_clear_body()
	_add_quote(
		"%s\n\nThis will be your new vessel, Captain. Ready to lay her keel?" % str(entry["display"])
	)
	_add_option("Commission her.", func() -> void: _commission(entry))
	_add_back_button()


func _commission(entry: Dictionary) -> void:
	var template := _build_template(entry)

	DirAccess.make_dir_recursive_absolute("user://shipwright_orders")
	var path := "user://shipwright_orders/" + str(entry["id"]) + ".json"
	var f    := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		_clear_body()
		_add_quote("Something went wrong in the yard. Try again.")
		_add_back_button()
		return
	f.store_string(JSON.stringify(template))
	f.close()

	var ship := ShipBuilder.build(path)
	if ship == null:
		_clear_body()
		_add_quote("The yard couldn't build that vessel. Please report this bug.")
		_add_back_button()
		return

	var placed := _try_place_at_berth(ship)

	if not placed:
		var plot := get_parent() as Node3D
		if plot != null:
			plot.add_child(ship)
			var dock := _get_dock()
			var anchor := dock.global_position if dock != null else global_position
			ship.global_position = anchor + Vector3(0.0, 0.0, -20.0)
			ship.call_deferred("place_at_waterline", WaveSurface.WATER_LEVEL, ship.design_draft_fraction)

	var plot := get_parent() as PortPlot
	if plot != null:
		plot.respawn_staged_cargo()

	_pending_entry = {}
	_clear_body()
	if placed:
		_add_quote("She's alongside, Captain. %s — ready for sea." % str(entry["display"]))
	else:
		_add_quote("She's afloat, Captain, but all berths are occupied.\nYou'll find her in the water nearby.")
	_add_option("Much obliged.", _close)


func _try_place_at_berth(ship: BoatBody) -> bool:
	var dock := _get_dock()
	if dock == null:
		return false
	var berths := dock.get_berths()
	for i in range(berths.size()):
		var b := berths[i] as Dictionary
		if int(b["status"]) == PortDock.BerthStatus.FREE:
			if dock.reserve_berth(i, "Captain"):
				var placed := dock.place_ship_at_berth(i, ship)
				if placed != null:
					return true
				dock.release_berth(i)
	return false


# ── Template builder ──────────────────────────────────────────────────────────

func _build_template(entry: Dictionary) -> Dictionary:
	return {
		"display_name":   str(entry["display"]),
		"hull":           str(entry["hull_file"]),
		"scale":          1.0,
		"superstructure": str(entry["superstructure"]),
		"cargo_decks":    [],
		"physics": {
			"auto_mass_from_hull": true,
			"design_draft_fraction": 0.45,
		},
		"buoyancy": {
			"block_coefficient": 0.72,
			"vertical_damping":  3000.0,
		},
		"hydrodynamics": {
			"forward_drag_coeff":    0.05,
			"lateral_drag_coeff":    4.0,
			"rotational_drag_coeff": 6.5,
			"orbital_flow_scale":    0.08,
			"bulk_horizontal_drag":  400.0,
			"draft_fraction":        0.44,
		},
		"propulsion": {
			"max_thrust":          float(entry["propulsion_thrust"]),
			"reverse_multiplier":  0.45,
		},
		"rudder": {
			"max_torque":              float(entry["propulsion_thrust"]) * 1.8,
			"speed_factor":            0.65,
			"min_effectiveness_floor": 0.38,
			"rudder_flow_gate":        0.25,
			"sideslip_rudder_weight":  0.55,
		},
		"bow_thruster": {
			"max_thrust": float(entry["bow_thrust"]),
		},
		"camera": {
			"follow_distance": float(entry["cam_dist"]),
			"follow_height":   float(entry["cam_height"]),
		},
	}


# ── UI helpers ────────────────────────────────────────────────────────────────

func _clear_body() -> void:
	for child in _body.get_children():
		child.queue_free()


func _add_quote(text: String) -> void:
	var lbl                   := Label.new()
	lbl.text                  = text
	lbl.autowrap_mode         = TextServer.AUTOWRAP_WORD
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.add_theme_font_size_override("font_size", 15)
	_body.add_child(lbl)
	_body.add_child(HSeparator.new())


func _add_option(text: String, callback: Callable) -> void:
	var btn                   := Button.new()
	btn.text                  = text
	btn.alignment             = HORIZONTAL_ALIGNMENT_LEFT
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.pressed.connect(callback)
	_body.add_child(btn)


func _add_back_button() -> void:
	_body.add_child(HSeparator.new())
	if _screen == _Screen.CONFIRM:
		_add_option("← Back", _show_hull_select)
	else:
		_add_option("← Back", _show_main)


# ── Dock lookup ───────────────────────────────────────────────────────────────

func _get_dock() -> PortDock:
	var parent := get_parent()
	if parent == null:
		return null
	return parent.get_node_or_null("PortDock") as PortDock


# ── Build UI ──────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	var layer  := CanvasLayer.new()
	layer.name = "ShipwrightLayer"
	add_child(layer)

	_panel               = Panel.new()
	_panel.name          = "ShipwrightPanel"
	_panel.visible       = false
	_panel.theme         = HudStyle.make_theme()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.offset_left   = -300.0
	_panel.offset_right  =  300.0
	_panel.offset_top    = -250.0
	_panel.offset_bottom =  250.0
	layer.add_child(_panel)

	var title                  := Label.new()
	title.text                 = "SHIPWRIGHT"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", HudStyle.C_AMBER)
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_top    = 10.0
	title.offset_bottom = 40.0
	_panel.add_child(title)

	var scroll           := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.offset_top    = 48.0
	scroll.offset_bottom = -8.0
	_panel.add_child(scroll)

	_body                       = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_body)
