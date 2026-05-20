@tool
class_name ShipwrightNpc
extends NpcInteractable

## Shipwright NPC. Lets the player commission a new vessel from the available hull catalog.
## Writes a minimal ship template to user://shipwright_orders/ and calls ShipBuilder.build().

## Catalog of buildable hulls. Each entry only carries identity + the hull
## file + the bridge to attach. All physics parameters (propulsion thrust,
## bow thrust, camera distance/height, rudder torque) are *derived* from
## the hull's dimensions in `_build_template` via HullStations, so adding
## a new hull is one entry here.
const HULL_CATALOG: Array[Dictionary] = [
	{
		"id":               "coastal_trader",
		"display":          "Coastal Trader  •  13 m / 43 ft",
		"ship_class_label": "Coastal Trader",
		"hull_file":        "hull_coastal_trader.json",
		"superstructure":   "bridge_coastal_trader",
	},
	{
		"id":               "coastal_trader_long",
		"display":          "Coastal Trader, Extended  •  15 m / 49 ft",
		"ship_class_label": "Coastal Trader",
		"hull_file":        "hull_coastal_trader_long.json",
		"superstructure":   "bridge_coastal_trader",
	},
	{
		"id":               "cargo_ship",
		"display":          "Twin-Deck Cargo Coaster  •  20 m / 66 ft",
		"ship_class_label": "Coastal Trader",
		"hull_file":        "hull_cargo_ship.json",
		"superstructure":   "bridge_cargo_ship",
	},
	{
		"id":               "short_sea_coaster",
		"display":          "Short Sea Coaster  •  22 m / 72 ft",
		"ship_class_label": "Short Sea Coaster",
		"hull_file":        "hull_short_sea_coaster.json",
		"superstructure":   "bridge_short_sea_coaster",
	},
	{
		"id":               "short_sea_coaster_long",
		"display":          "Short Sea Coaster, Extended  •  25 m / 82 ft",
		"ship_class_label": "Short Sea Coaster",
		"hull_file":        "hull_short_sea_coaster_long.json",
		"superstructure":   "bridge_short_sea_coaster",
	},
	{
		"id":               "handysize_feeder",
		"display":          "Handysize Feeder  •  35 m / 115 ft",
		"ship_class_label": "Handysize Feeder",
		"hull_file":        "hull_handysize_feeder.json",
		"superstructure":   "bridge_handysize_feeder",
	},
	{
		"id":               "handysize_feeder_long",
		"display":          "Handysize Feeder, Extended  •  40 m / 131 ft",
		"ship_class_label": "Handysize Feeder",
		"hull_file":        "hull_handysize_feeder_long.json",
		"superstructure":   "bridge_handysize_feeder",
	},
	{
		"id":               "deep_sea_freighter",
		"display":          "Deep Sea Freighter  •  50 m / 164 ft",
		"ship_class_label": "Deep Sea Freighter",
		"hull_file":        "hull_deep_sea_freighter.json",
		"superstructure":   "bridge_deep_sea_freighter",
	},
	{
		"id":               "deep_sea_freighter_long",
		"display":          "Deep Sea Freighter, Extended  •  60 m / 197 ft",
		"ship_class_label": "Deep Sea Freighter",
		"hull_file":        "hull_deep_sea_freighter_long.json",
		"superstructure":   "bridge_deep_sea_freighter",
	},
	{
		"id":               "large_freighter",
		"display":          "Large Freighter  •  60 m / 197 ft",
		"ship_class_label": "Deep Sea Freighter",
		"hull_file":        "hull_large.json",
		"superstructure":   "bridge_deep_sea_freighter",
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

## Build a ship template from a catalog entry. Most fields are derived from
## the hull's geometry via HullStations rather than hand-tuned per ship.
##
## Calibrated against the previous hand-tuned values so a freshly-derived
## coastal trader (13 m) gets ~58 kN thrust and a freighter (50 m) ~3.2 MN —
## matching the old gameplay feel within ~10%.
func _build_template(entry: Dictionary) -> Dictionary:
	var hull_path : String = ShipBuilder.HULL_BASE_DIR + str(entry["hull_file"])
	var hull_data : Dictionary = ShipBuilder._load_json(hull_path)
	var stations  : HullStations = HullStations.from_hull_json(hull_data, 10)

	# Mass derived from strip-theory displacement at design draft.
	var displacement_kg : float = maxf(stations.displacement_volume_m3 * 1025.0, 1000.0)
	# F = m × a. 0.7 m/s² peak steady-state acceleration. Slightly above real-
	# world cargo ships (~0.1 m/s²) for game feel — boats need to be sailable.
	var propulsion_thrust : float = displacement_kg * 0.7
	# Bow thruster as a fraction of main; ratio drops with hull length because
	# bigger ships rely on mooring / tug assistance rather than a powerful BT.
	var bow_ratio : float = clampf(0.40 - stations.length_m / 200.0, 0.10, 0.40)
	var bow_thrust : float = propulsion_thrust * bow_ratio
	# Rudder torque ∝ thrust^(4/3) — the rudder operates in propeller wash, so
	# torque grows faster than linear thrust. Coefficient calibrated against the
	# old reference: 280 kN thrust → 504 kNm torque.
	var rudder_torque : float = 0.0275 * pow(propulsion_thrust, 4.0 / 3.0)
	var cam_dist   : float = stations.length_m * 1.45 + 11.0
	var cam_height : float = stations.length_m * 0.36 + 4.0

	# Note: no `cargo_decks` key — ShipBuilder adds one deck (prefers `"main"`,
	# clamped between bridge and bow, snapped to the cell grid). Use `[]` for
	# launches with no cargo deck.
	return {
		"display_name":   str(entry["display"]),
		"hull":           str(entry["hull_file"]),
		"scale":          1.0,
		"superstructure": str(entry["superstructure"]),
		"physics": {
			"auto_mass_from_hull":    true,
			"design_draft_fraction":  0.45,
			"mass_scale":             1.28,
		},
		"buoyancy": {
			"heave_damping_per_m2": 11000.0,
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
			"max_thrust":         propulsion_thrust,
			"reverse_multiplier": 0.45,
		},
		"rudder": {
			"max_torque":              rudder_torque,
			"speed_factor":            0.65,
			"min_effectiveness_floor": 0.38,
			"rudder_flow_gate":        0.25,
			"sideslip_rudder_weight":  0.55,
		},
		"bow_thruster": {
			"max_thrust": bow_thrust,
		},
		"camera": {
			"follow_distance": cam_dist,
			"follow_height":   cam_height,
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
