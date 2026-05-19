@tool
class_name ShipwrightNpc
extends NpcInteractable

## Shipwright NPC. Lets the player commission a new vessel from the available hull catalog.
## Writes a minimal ship template to user://shipwright_orders/ and calls ShipBuilder.build().

const HULL_CATALOG: Array[Dictionary] = [
	{
		"id":                 "coastal_trader",
		"display":            "Coastal Trader  •  13 m / 43 ft",
		"ship_class_label":   "Coastal Trader",
		"hull_file":          "hull_coastal_trader.json",
		"superstructure":     "bridge_coastal_trader",
		"propulsion_thrust":   58000.0,
		"bow_thrust":          24000.0,
		"cam_dist":            20.0,
		"cam_height":           8.0,
	},
	{
		"id":                 "coastal_trader_long",
		"display":            "Coastal Trader, Extended  •  15 m / 49 ft",
		"ship_class_label":   "Coastal Trader",
		"hull_file":          "hull_coastal_trader_long.json",
		"superstructure":     "bridge_coastal_trader",
		"propulsion_thrust":   89000.0,
		"bow_thrust":          33000.0,
		"cam_dist":            24.0,
		"cam_height":           9.0,
	},
	{
		"id":                 "short_sea_coaster",
		"display":            "Short Sea Coaster  •  22 m / 72 ft",
		"ship_class_label":   "Short Sea Coaster",
		"hull_file":          "hull_short_sea_coaster.json",
		"superstructure":     "bridge_short_sea_coaster",
		"propulsion_thrust":  280000.0,
		"bow_thrust":          70000.0,
		"cam_dist":            35.0,
		"cam_height":          12.0,
	},
	{
		"id":                 "short_sea_coaster_long",
		"display":            "Short Sea Coaster, Extended  •  25 m / 82 ft",
		"ship_class_label":   "Short Sea Coaster",
		"hull_file":          "hull_short_sea_coaster_long.json",
		"superstructure":     "bridge_short_sea_coaster",
		"propulsion_thrust":  410000.0,
		"bow_thrust":          90000.0,
		"cam_dist":            40.0,
		"cam_height":          13.0,
	},
	{
		"id":                 "handysize_feeder",
		"display":            "Handysize Feeder  •  35 m / 115 ft",
		"ship_class_label":   "Handysize Feeder",
		"hull_file":          "hull_handysize_feeder.json",
		"superstructure":     "bridge_handysize_feeder",
		"propulsion_thrust":  1130000.0,
		"bow_thrust":          177000.0,
		"cam_dist":            55.0,
		"cam_height":          18.0,
	},
	{
		"id":                 "handysize_feeder_long",
		"display":            "Handysize Feeder, Extended  •  40 m / 131 ft",
		"ship_class_label":   "Handysize Feeder",
		"hull_file":          "hull_handysize_feeder_long.json",
		"superstructure":     "bridge_handysize_feeder",
		"propulsion_thrust":  1680000.0,
		"bow_thrust":          231000.0,
		"cam_dist":            65.0,
		"cam_height":          20.0,
	},
	{
		"id":                 "deep_sea_freighter",
		"display":            "Deep Sea Freighter  •  50 m / 164 ft",
		"ship_class_label":   "Deep Sea Freighter",
		"hull_file":          "hull_deep_sea_freighter.json",
		"superstructure":     "bridge_deep_sea_freighter",
		"propulsion_thrust":  3290000.0,
		"bow_thrust":          362000.0,
		"cam_dist":            80.0,
		"cam_height":          24.0,
	},
	{
		"id":                 "deep_sea_freighter_long",
		"display":            "Deep Sea Freighter, Extended  •  60 m / 197 ft",
		"ship_class_label":   "Deep Sea Freighter",
		"hull_file":          "hull_deep_sea_freighter_long.json",
		"superstructure":     "bridge_deep_sea_freighter",
		"propulsion_thrust":  5680000.0,
		"bow_thrust":          521000.0,
		"cam_dist":             95.0,
		"cam_height":           28.0,
	},
]

var _dialogue: DialoguePanel

enum _Screen { MAIN, HULL_SELECT, CONFIRM }
var _screen:       _Screen     = _Screen.MAIN
var _pending_entry: Dictionary = {}


func _ready() -> void:
	prompt_text = "Press F — Shipwright"
	super._ready()
	if not Engine.is_editor_hint():
		call_deferred("_build_ui")


# ── NpcInteractable hooks ──────────────────────────────────────────────────────

func _on_interact() -> void:
	_show_main()
	_dialogue.show_panel()
	open_ui()


func _on_ui_cancel() -> void:
	if _screen == _Screen.CONFIRM:
		_show_hull_select()
	elif _screen == _Screen.MAIN:
		_dialogue.hide_panel()
		close_ui()
	else:
		_show_main()


# ── Screens ───────────────────────────────────────────────────────────────────

func _close() -> void:
	_dialogue.hide_panel()
	close_ui()


func _show_main() -> void:
	_screen = _Screen.MAIN
	_dialogue.clear()
	_dialogue.add_quote("Good day, Captain. Looking to commission a new vessel?\nI can lay down any hull in my catalog.")
	_dialogue.add_option("Show me what you can build.", _show_hull_select)
	_dialogue.add_option("Not today, thank you.",        _close)


func _show_hull_select() -> void:
	_screen = _Screen.HULL_SELECT
	_dialogue.clear()
	_dialogue.add_quote("Choose your hull. I'll build her true.")
	for entry in HULL_CATALOG:
		var e   := entry as Dictionary
		var lbl := "%s  [%s]" % [str(e["display"]), str(e["ship_class_label"])]
		_dialogue.add_option(lbl, _show_confirm.bind(e))
	_dialogue.add_back_button(_show_main)


func _show_confirm(entry: Dictionary) -> void:
	_screen        = _Screen.CONFIRM
	_pending_entry = entry
	_dialogue.clear()
	_dialogue.add_quote(
		"%s\n\nThis will be your new vessel, Captain. Ready to lay her keel?" % str(entry["display"])
	)
	_dialogue.add_option("Commission her.", func() -> void: _commission(entry))
	_dialogue.add_back_button(_show_hull_select)


func _commission(entry: Dictionary) -> void:
	var template := _build_template(entry)

	DirAccess.make_dir_recursive_absolute("user://shipwright_orders")
	var path := "user://shipwright_orders/" + str(entry["id"]) + ".json"
	var f    := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		_dialogue.clear()
		_dialogue.add_quote("Something went wrong in the yard. Try again.")
		_dialogue.add_back_button(_show_hull_select)
		return
	f.store_string(JSON.stringify(template))
	f.close()

	var ship := ShipBuilder.build(path)
	if ship == null:
		_dialogue.clear()
		_dialogue.add_quote("The yard couldn't build that vessel. Please report this bug.")
		_dialogue.add_back_button(_show_hull_select)
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
	_dialogue.clear()
	if placed:
		_dialogue.add_quote("She's alongside, Captain. %s — ready for sea." % str(entry["display"]))
	else:
		_dialogue.add_quote("She's afloat, Captain, but all berths are occupied.\nYou'll find her in the water nearby.")
	_dialogue.add_option("Much obliged.", _close)


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
	# Note: no `cargo_decks` key — ShipBuilder will instantiate every deck the
	# hull JSON declares (sized properly to the hull). Add an explicit array to
	# restrict the set, or `[]` to commission with no cargo decks.
	return {
		"display_name":   str(entry["display"]),
		"hull":           str(entry["hull_file"]),
		"scale":          1.0,
		"superstructure": str(entry["superstructure"]),
		"physics": {
			"auto_mass_from_hull": true,
			"design_draft_fraction": 0.45,
		},
		"buoyancy": {
			"heave_damping_per_m2": 8000.0,
		},
		"hydrodynamics": {
			"frictional_coeff":       0.0025,
			"form_factor":            1.20,
			"wave_making_peak_coeff": 0.005,
			"hull_speed_fn":          0.40,
			"lateral_drag_coeff":     2.0,
			"yaw_drag_coeff":         5.0,
		},
		"propulsion": {
			"max_thrust":          float(entry["propulsion_thrust"]),
			"reverse_multiplier":  0.45,
		},
		"rudder": {
			"max_torque":              504000.0 * pow(float(entry["propulsion_thrust"]) / 280000.0, 4.0 / 3.0),
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


# ── Dock lookup ───────────────────────────────────────────────────────────────

func _get_dock() -> PortDock:
	var parent := get_parent()
	if parent == null:
		return null
	return parent.get_node_or_null("PortDock") as PortDock


# ── Build UI ──────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	_dialogue = DialoguePanel.new("SHIPWRIGHT", Vector2(600.0, 500.0))
	add_child(_dialogue)
