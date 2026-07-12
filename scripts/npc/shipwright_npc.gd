@tool
class_name ShipwrightNpc
extends NpcInteractable

## Shipwright — yard menu → commission new hull or refit / rename owned vessels.
var _catalog: ShipwrightCatalogPanel
var _editor: ShipyardBrickEditor
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
	VesselSync.refresh_for_ui(session, func() -> void:
		_show_yard_menu()
		open_ui()
	)


func _on_ui_cancel() -> void:
	if _editor != null and _editor.is_open():
		var was_refit := _editor.is_refitting()
		_editor.hide_editor()
		if was_refit:
			_show_yard_menu()
		else:
			_open_catalog()
		return
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
	if _editor != null and _editor.is_open():
		_editor.hide_editor()

	_dialogue.clear()
	_dialogue.add_quote(
		"Yard's open, Captain.\n"
		+ "Commission a fresh hull, or bring one of yours in for a refit."
	)
	_dialogue.add_option("Commission a new hull", _open_catalog)

	var session := get_node_or_null("/root/PlayerSession")
	var fleet: Array = []
	if session != null and session.data != null:
		fleet = session.data.get_harbour_vessel_records()
	for entry_raw in fleet:
		var record := entry_raw as Dictionary
		var vessel_name := VesselSpawn.vessel_name_of(record)
		_dialogue.add_option(
			"Refit %s" % vessel_name,
			_open_refit.bind(record),
		)

	_dialogue.add_option("Farewell.", _close_after_result)
	_dialogue.show_panel()


func _open_catalog() -> void:
	if _dialogue != null and _dialogue.is_open():
		_dialogue.hide_panel()
	if _editor != null and _editor.is_open():
		_editor.hide_editor()
	var catalog: Array[Dictionary] = HullRegistry.catalog()
	_catalog.open_catalog(catalog, 0)
	_catalog.show_panel()


func _open_refit(record: Dictionary) -> void:
	var hull_id := str(record.get("hull_id", "workboat"))
	var entry := HullRegistry.get_by_id(hull_id)
	if entry.is_empty():
		entry = {
			"id": hull_id,
			"display": str(record.get("display", "Workboat")),
			"scene_path": VesselSpawn.resolve_template_path(record),
			"price_marks": 0,
		}
	_dialogue.hide_panel()
	_editor.open_for_hull(
		entry,
		VesselSpawn.brick_layout_of(record),
		str(record.get("uid", "")),
		VesselSpawn.vessel_name_of(record),
	)


func _build_ui() -> void:
	_catalog = ShipwrightCatalogPanel.new()
	add_child(_catalog)
	_catalog.closed.connect(_on_catalog_closed)
	_catalog.commission_requested.connect(_on_commission_requested)

	_editor = ShipyardBrickEditor.new()
	add_child(_editor)
	_editor.closed.connect(_on_editor_closed)
	_editor.layout_confirmed.connect(_on_layout_confirmed)

	_dialogue = DialoguePanel.new("SHIPWRIGHT", Vector2(520.0, 360.0))
	add_child(_dialogue)

	var session := get_node_or_null("/root/PlayerSession")
	if session != null and session.has_signal("marks_changed"):
		if not session.marks_changed.is_connected(_on_marks_changed):
			session.marks_changed.connect(_on_marks_changed)


func _on_catalog_closed() -> void:
	_show_yard_menu()


func _on_editor_closed() -> void:
	if _editor != null and _editor.is_refitting():
		_show_yard_menu()
	else:
		_open_catalog()


func _on_marks_changed(_balance: int) -> void:
	if _catalog != null and _catalog.is_open():
		_catalog.refresh()


func _on_commission_requested(entry: Dictionary) -> void:
	## Catalog only selects a hull; building happens in the build window.
	_catalog.hide_catalog()
	_editor.open_for_hull(entry)


func _on_layout_confirmed(
	entry: Dictionary,
	layout: Dictionary,
	vessel_name: String,
	editing_uid: String,
) -> void:
	_editor.hide_editor()
	if not editing_uid.is_empty():
		_refit(editing_uid, entry, layout, vessel_name)
		return
	if not _try_pay_for_commission(entry):
		return
	_commission(entry, layout, vessel_name)


func _try_pay_for_commission(entry: Dictionary) -> bool:
	var scene_path := str(entry.get("scene_path", VesselSpawn.WORKBOAT_SCENE))
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		_show_commission_error("That hull is unavailable in the yard right now.")
		return false

	var stations: HullStations = HullStations.from_box(Workboat.LOA_M, Workboat.BEAM_M, Workboat.DEPTH_M, 10)
	var session := get_node_or_null("/root/PlayerSession")
	if session == null:
		return true
	var price := int(entry.get("price_marks", 0))
	if price <= 0:
		price = ShipwrightPricing.commission_price(entry, stations, session.data)
	if price <= 0:
		return true
	if not session.spend_marks(price):
		_dialogue.clear()
		_dialogue.add_quote(
			"Your balance won't cover that hull, Captain.\nNeed %s more in the ledger."
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
	var uid := "%s_%d" % [str(entry.get("id", "workboat")), Time.get_unix_time_from_system()]
	var scene_path := str(entry.get("scene_path", VesselSpawn.WORKBOAT_SCENE))
	var name := vessel_name.strip_edges()
	if name.is_empty():
		name = VesselSpawn.vessel_name_of({"display": str(entry.get("display", "Workboat"))})
	_register_commissioned_vessel(entry, scene_path, uid, layout, name)

	_show_result(
		(
			"%s is on your registry, Captain.\n"
			+ "Visit the Harbour Master to request a berth and bring her alongside."
		)
		% name,
		_close_after_result,
	)


func _refit(uid: String, entry: Dictionary, layout: Dictionary, vessel_name: String) -> void:
	var session := get_node_or_null("/root/PlayerSession")
	if session == null or session.data == null:
		_show_commission_error("No captain ledger on file.")
		return
	var existing: Dictionary = session.data.find_owned_vessel(uid)
	if existing.is_empty():
		_show_commission_error("That vessel isn't on your registry.")
		return

	var name := vessel_name.strip_edges()
	if name.is_empty():
		name = VesselSpawn.vessel_name_of(existing)

	var patch := {
		"brick_layout": layout,
		"name": name,
		"display": str(entry.get("display", existing.get("display", "Workboat"))),
	}
	var updated := VesselSpawn.normalize_record(
		PlayerData.merge_vessel_record(existing, patch)
	)
	session.data.upsert_owned_vessel(updated)
	session.save_now()
	_apply_live_refit(updated)
	VesselSync.push_brick_layout(session, updated)

	_show_result(
		"%s's fit-out is updated, Captain.\nShe's ready whenever you call for a berth."
		% name,
		_show_yard_menu,
	)


func _apply_live_refit(record: Dictionary) -> void:
	var session := get_node_or_null("/root/PlayerSession")
	if session == null or session.data == null:
		return
	var uid := str(record.get("uid", ""))
	if uid.is_empty() or str(session.data.active_vessel.get("uid", "")) != uid:
		return
	var ship := LocalPlayerView.get_active_ship() as BoatBody
	if ship == null:
		return
	if ship.has_method("apply_brick_layout"):
		ship.call("apply_brick_layout", VesselSpawn.brick_layout_of(record))
	VesselSpawn.apply_identity(ship, record)


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
) -> void:
	var session := get_node_or_null("/root/PlayerSession")
	if session == null:
		return
	var record := VesselSpawn.normalize_record({
		"uid":           uid,
		"hull_id":       str(entry.get("id", "workboat")),
		"name":          vessel_name,
		"display":       str(entry.get("display", "Workboat")),
		"template_path": scene_path,
		"scene_path":    scene_path,
		"brick_layout":  layout,
	})
	session.data.upsert_owned_vessel(record)
	session.save_now()
	VesselSync.publish_commission(session, entry, scene_path, uid, vessel_name)
