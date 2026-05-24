@tool
class_name ShipwrightNpc
extends NpcInteractable

## Shipwright NPC — catalog showroom with 3D previews, prices, and registry commission.
## Hull spawning is handled by the Harbour Master after a berth is assigned.
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
		_open_catalog()
		open_ui()
		return
	VesselSync.refresh_for_ui(session, func() -> void:
		_open_catalog()
		open_ui()
	)


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
	var catalog: Array[Dictionary] = HullRegistry.catalog()
	_catalog.open_catalog(catalog, 0)
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
	var hull_data := JsonUtil.load(hull_path)
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

	_register_commissioned_vessel(entry, path, uid)

	_show_result(
		(
			"%s is on your registry, Captain.\n"
			+ "Visit the Harbour Master to request a berth and bring her alongside."
		)
		% str(entry.get("display", "Your vessel")),
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


func _register_commissioned_vessel(entry: Dictionary, template_path: String, uid: String) -> void:
	var session := get_node_or_null("/root/PlayerSession")
	if session == null:
		return
	var record := {
		"uid":           uid,
		"hull_id":       str(entry.get("id", "")),
		"display":       str(entry.get("display", "Vessel")),
		"template_path": template_path,
	}
	session.data.upsert_owned_vessel(record)
	session.save_now()
	VesselSync.publish_commission(session, entry, template_path, uid)


func _build_template(entry: Dictionary) -> Dictionary:
	return StarterVessel.build_template(entry)
