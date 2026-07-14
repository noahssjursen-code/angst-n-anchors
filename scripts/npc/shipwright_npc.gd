@tool
class_name ShipwrightNpc
extends NpcInteractable

## Shipwright — sells official ready-built vessels from PrebuiltVesselCatalog.
var _catalog: ShipwrightCatalogPanel
var _dialogue: DialoguePanel


func _ready() -> void:
	prompt_text = "Press F — Shipwright"
	super._ready()
	if not Engine.is_editor_hint():
		call_deferred("_build_ui")


func _on_interact() -> void:
	var session := get_node_or_null("/root/PlayerSession")
	if session == null:
		_show_yard_menu()
		open_ui()
		return
	## Singleplayer: local ledger is authoritative — never wait on / wipe from server.
	var config := get_node_or_null("/root/ServerConfig")
	if config == null or not bool(config.get("is_multiplayer_mode")):
		_show_yard_menu()
		open_ui()
		return
	VesselSync.refresh_for_ui(session, func() -> void:
		_show_yard_menu()
		open_ui()
	)


func _on_ui_cancel() -> void:
	if _catalog != null and _catalog.is_open():
		_catalog.hide_catalog()
		_show_yard_menu()
		return
	if _dialogue != null and _dialogue.is_open():
		_dialogue.hide_panel()
		close_ui()


func _show_yard_menu() -> void:
	if _catalog != null and _catalog.is_open():
		_catalog.hide_catalog()

	_dialogue.clear()
	_dialogue.add_quote(
		"Yard's open, Captain.\n"
		+ "Official ready-builts on the floor — pick one and she's yours."
	)
	_dialogue.add_option("Browse vessels for sale", _open_catalog)
	_dialogue.add_option("Farewell.", _close_after_result)
	_dialogue.show_panel()


func _open_catalog() -> void:
	if _dialogue != null and _dialogue.is_open():
		_dialogue.hide_panel()
	var catalog: Array[Dictionary] = PrebuiltVesselCatalog.catalog_entries()
	_catalog.open_catalog(catalog, 0)
	_catalog.show_panel()


func _build_ui() -> void:
	_catalog = ShipwrightCatalogPanel.new()
	add_child(_catalog)
	_catalog.closed.connect(_on_catalog_closed)
	_catalog.commission_requested.connect(_on_commission_requested)

	_dialogue = DialoguePanel.new("SHIPWRIGHT", Vector2(520.0, 360.0))
	add_child(_dialogue)

	var session := get_node_or_null("/root/PlayerSession")
	if session != null and session.has_signal("marks_changed"):
		if not session.marks_changed.is_connected(_on_marks_changed):
			session.marks_changed.connect(_on_marks_changed)


func _on_catalog_closed() -> void:
	_show_yard_menu()


func _on_marks_changed(_balance: int) -> void:
	if _catalog != null and _catalog.is_open():
		_catalog.refresh()


func _on_commission_requested(entry: Dictionary) -> void:
	_catalog.hide_catalog()
	if not bool(entry.get("is_prebuilt", false)):
		_show_commission_error("That vessel isn't on the official yard list.")
		return
	var layout_raw: Variant = entry.get("prebuilt_layout", {})
	var layout: Dictionary = (
		(layout_raw as Dictionary).duplicate(true)
		if typeof(layout_raw) == TYPE_DICTIONARY
		else {}
	)
	if layout.is_empty():
		_show_commission_error("That ready-built vessel has no valid fit-out.")
		return
	if not _try_pay_for_commission(entry):
		return
	_commission(entry, layout, str(entry.get("prebuilt_name", "Vessel")))


func _try_pay_for_commission(entry: Dictionary) -> bool:
	var scene_path := str(entry.get("scene_path", VesselSpawn.WORKBOAT_SCENE))
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		_show_commission_error("That hull is unavailable in the yard right now.")
		return false

	var loa := float(entry.get("loa_m", Workboat.LOA_M))
	var beam := float(entry.get("beam_m", Workboat.BEAM_M))
	var depth := float(entry.get("depth_m", Workboat.DEPTH_M))
	var stations: HullStations = HullStations.from_box(loa, beam, depth, 10)
	var session := get_node_or_null("/root/PlayerSession")
	if session == null:
		return true
	var price := ShipwrightPricing.commission_price(entry, stations, session.data)
	if price <= 0:
		return true
	if not session.spend_marks(price):
		_dialogue.clear()
		_dialogue.add_quote(
			"Your balance won't cover that vessel, Captain.\nNeed %s more in the ledger."
			% PlayerSession.format_money(price - session.get_marks())
		)
		_dialogue.add_option("Back to yard.", _show_yard_menu)
		_dialogue.show_panel()
		return false
	return true


func _show_commission_error(line: String) -> void:
	_dialogue.clear()
	_dialogue.add_quote(line)
	_dialogue.add_option("Back to yard.", _show_yard_menu)
	_dialogue.show_panel()


func _commission(entry: Dictionary, layout: Dictionary, vessel_name: String) -> void:
	var hull_id := str(entry.get("id", "workboat")).strip_edges()
	if hull_id.is_empty():
		hull_id = "workboat"
	var uid := VesselSpawn.new_vessel_uid(hull_id)
	var scene_path := str(entry.get("scene_path", VesselSpawn.WORKBOAT_SCENE)).strip_edges()
	if scene_path.is_empty():
		scene_path = HullRegistry.scene_path_for(hull_id)
	var name := vessel_name.strip_edges()
	if name.is_empty():
		name = VesselSpawn.vessel_name_of({"display": str(entry.get("display", "Workboat"))})
	if not _register_commissioned_vessel(entry, scene_path, uid, layout, name):
		_show_commission_error(
			"The yard could not verify this vessel on disk. Ask again in a moment."
		)
		return

	_show_result(
		(
			"%s is on your registry, Captain.\n"
			+ "Visit the Harbour Master to request a berth and bring her alongside."
		)
		% name,
		_close_after_result,
	)


func _show_result(message: String, on_done: Callable) -> void:
	_dialogue.clear()
	_dialogue.add_quote(message)
	_dialogue.add_option("Much obliged.", on_done)
	_dialogue.show_panel()


func _close_after_result() -> void:
	_dialogue.hide_panel()
	close_ui()


func _register_commissioned_vessel(
	entry: Dictionary,
	scene_path: String,
	uid: String,
	layout: Dictionary,
	vessel_name: String,
) -> bool:
	var session := get_node_or_null("/root/PlayerSession")
	if session == null or session.data == null:
		return false
	var hull_id := str(entry.get("id", "workboat")).strip_edges()
	if hull_id.is_empty():
		hull_id = "workboat"
	var safe_layout: Dictionary = layout.duplicate(true) if typeof(layout) == TYPE_DICTIONARY else {}
	if safe_layout.is_empty():
		safe_layout = VesselSpawn.default_brick_layout(hull_id)
	var record := VesselSpawn.normalize_record({
		"uid":           uid,
		"hull_id":       hull_id,
		"name":          vessel_name,
		"display":       str(entry.get("display", "Workboat")),
		"template_path": scene_path,
		"scene_path":    scene_path,
		"brick_layout":  safe_layout,
	})
	## JSON-safe ledger row only — never persist catalog Colors / enums.
	record = PlayerData.ledger_vessel_record(record)
	var saved := (
		session.has_method("persist_vessel_configuration")
		and bool(session.call("persist_vessel_configuration", record, true))
	)
	if not saved:
		push_error("Shipwright: failed to persist commissioned vessel uid=%s hull=%s" % [uid, hull_id])
		return false
	VesselSync.publish_commission(session, entry, scene_path, uid, vessel_name)
	return true
