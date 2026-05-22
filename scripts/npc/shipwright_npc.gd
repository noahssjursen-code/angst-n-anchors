@tool
class_name ShipwrightNpc
extends NpcInteractable

## Shipwright NPC — catalog showroom with 3D previews, prices, and commission.

## Retail catalog — starter 13 m Coastal Trader is harbour-master only (StarterVessel).
const HULL_CATALOG: Array[Dictionary] = [
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

var _catalog: ShipwrightCatalogPanel
var _dialogue: DialoguePanel


func _ready() -> void:
	prompt_text = "Press F — Shipwright"
	super._ready()
	if not Engine.is_editor_hint():
		call_deferred("_build_ui")


func _on_interact() -> void:
	_open_catalog()
	open_ui()


func _on_ui_cancel() -> void:
	if _catalog != null and _catalog.is_open():
		_catalog.hide_catalog()
		close_ui()
	elif _dialogue != null and _dialogue.is_open():
		_dialogue.hide_panel()
		close_ui()


func _open_catalog() -> void:
	if _dialogue != null and _dialogue.is_open():
		_dialogue.hide_panel()
	_catalog.open_catalog(HULL_CATALOG, 0)
	_catalog.show_panel()


func _build_ui() -> void:
	_catalog = ShipwrightCatalogPanel.new()
	add_child(_catalog)
	_catalog.closed.connect(_on_catalog_closed)
	_catalog.commission_requested.connect(_on_commission_requested)

	_dialogue = DialoguePanel.new("SHIPWRIGHT", Vector2(520.0, 280.0))
	add_child(_dialogue)

	var session := get_node_or_null("/root/PlayerSession")
	if session != null and session.has_signal("marks_changed"):
		if not session.marks_changed.is_connected(_on_marks_changed):
			session.marks_changed.connect(_on_marks_changed)


func _on_catalog_closed() -> void:
	close_ui()


func _on_marks_changed(_balance: int) -> void:
	if _catalog != null and _catalog.is_open():
		_catalog.refresh()


func _on_commission_requested(entry: Dictionary) -> void:
	if not _try_pay_for_commission(entry):
		return
	_catalog.hide_catalog()
	_commission(entry)


func _try_pay_for_commission(entry: Dictionary) -> bool:
	# Validate the hull JSON exists and has usable geometry BEFORE charging
	# the player. Without this guard a missing / corrupt hull file would
	# silently deduct marks and then crash on HullStations.from_hull_json.
	var hull_path := ShipBuilder.HULL_BASE_DIR + str(entry.get("hull_file", ""))
	if not FileAccess.file_exists(hull_path):
		_show_commission_error("That hull is unavailable in the yard right now.")
		return false
	var hull_data := ShipBuilder._load_json(hull_path)
	if hull_data.is_empty() or not hull_data.has("parts"):
		_show_commission_error("The hull blueprint is corrupted — please report this bug.")
		return false

	var stations := HullStations.from_hull_json(hull_data, 10)
	var session := get_node_or_null("/root/PlayerSession")
	if session == null:
		return true
	var price := ShipwrightPricing.commission_price(entry, stations, session.data)
	if price <= 0:
		return true
	if not session.spend_marks(price):
		_dialogue.clear()
		_dialogue.add_quote(
			"Your balance won't cover that hull, Captain.\nNeed %s more in the ledger."
			% PlayerSession.format_money(price - session.get_marks())
		)
		_dialogue.add_option("Back to catalog.", _open_catalog)
		_dialogue.show_panel()
		return false
	return true


## Show a polite "we can't build that" message without charging the player.
func _show_commission_error(line: String) -> void:
	_dialogue.clear()
	_dialogue.add_quote(line)
	_dialogue.add_option("Back to catalog.", _open_catalog)
	_dialogue.show_panel()


func _commission(entry: Dictionary) -> void:
	var template := _build_template(entry)

	DirAccess.make_dir_recursive_absolute("user://shipwright_orders")
	var uid := "%s_%d" % [str(entry["id"]), Time.get_unix_time_from_system()]
	var path := "user://shipwright_orders/" + uid + ".json"
	var f    := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		_show_result("Something went wrong in the yard. Try again.", _open_catalog)
		return
	f.store_string(JSON.stringify(template))
	f.close()

	PlayerVessel.replace_before_spawn(get_tree())

	var ship := ShipBuilder.build(path)
	if ship == null:
		_show_result("The yard couldn't build that vessel. Please report this bug.", _open_catalog)
		return

	PlayerVessel.mark_player_ship(ship)
	_network_register_ship(ship, path)
	# Freshly-built vessel sails with a full tank — captain pays the
	# commission, the yard hands over a ready ship.
	if ship.has_method("fill_tank"):
		ship.fill_tank()
	_register_active_vessel(entry, path, uid)

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

	if placed:
		_show_result("She's alongside, Captain.\n%s — ready for sea." % str(entry["display"]), _close_after_result)
	else:
		_show_result(
			"She's afloat, Captain, but all berths are occupied.\nYou'll find her in the water nearby.",
			_close_after_result
		)


func _show_result(message: String, on_done: Callable) -> void:
	_dialogue.clear()
	_dialogue.add_quote(message)
	_dialogue.add_option("Much obliged.", on_done)
	_dialogue.show_panel()


func _close_after_result() -> void:
	_dialogue.hide_panel()
	close_ui()


func _register_active_vessel(entry: Dictionary, template_path: String, uid: String) -> void:
	var session := get_node_or_null("/root/PlayerSession")
	if session == null:
		return
	session.data.set_active_vessel({
		"uid":           uid,
		"hull_id":       str(entry.get("id", "")),
		"display":       str(entry.get("display", "Vessel")),
		"template_path": template_path,
	})
	session.save_now()


func _try_place_at_berth(ship: BoatBody) -> bool:
	var dock := _get_dock()
	if dock == null:
		return false
	var owner_id := PortDock.local_player_owner_id()
	var berths := dock.get_berths()
	for i in range(berths.size()):
		var b := berths[i] as Dictionary
		if int(b["status"]) == PortDock.BerthStatus.FREE:
			if dock.reserve_berth(i, owner_id):
				var placed := dock.place_ship_at_berth(i, ship)
				if placed != null:
					return true
				dock.release_berth(i)
	return false


func _build_template(entry: Dictionary) -> Dictionary:
	return StarterVessel.build_template(entry)


func _get_dock() -> PortDock:
	var parent := get_parent()
	if parent == null:
		return null
	return parent.get_node_or_null("PortDock") as PortDock


func _network_register_ship(ship_node: Node3D, template_path: String) -> void:
	var manager := get_node_or_null("/root/NetworkManager")
	if manager == null:
		return
		
	var hull_id := ""
	var f := FileAccess.open(template_path, FileAccess.READ)
	if f != null:
		var json = JSON.parse_string(f.get_as_text())
		f.close()
		if json is Dictionary and json.has("hull"):
			var hull_file: String = json["hull"]
			hull_id = hull_file.replace("hull_", "").replace(".json", "")
			
	if hull_id.is_empty():
		hull_id = "coastal_trader"
		
	var ship_id := "player_ship"
	var session := get_node_or_null("/root/PlayerSession")
	if session != null and session.get("data") != null:
		var record: Dictionary = session.data.get_active_vessel_record()
		if not record.is_empty():
			ship_id = String(record.get("uid", "player_ship"))
			
	manager.call("register_ship_spawn", ship_id, hull_id, ship_node)
