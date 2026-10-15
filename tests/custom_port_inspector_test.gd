extends Node
## Exercise native owner controls and vessel actions against the same authority.
const DATA_FIXTURE = preload("res://tests/custom_port_data_test.gd")
const CATCH_FIXTURE = preload("res://tests/custom_port_catch_data_test.gd")
const STATE = preload("res://scripts/port/state/custom_port_state.gd")
const PANEL = preload("res://scripts/port/building/custom_port_inspector.gd")
const VESSELS = preload("res://scripts/port/state/custom_port_vessel_projection.gd")
var checks := 0
var failures: Array[String] = []
var changes: Array[Dictionary] = []
var panel: CustomPortInspector
var state: CustomPortState


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	if not ShipyardPlaytestMode.active():
		push_error("Inspector test requires --shipyard-playtest isolation.")
		get_tree().quit(1)
		return
	get_window().content_scale_size = Vector2i(1000, 780)
	var fixture := DATA_FIXTURE.new()
	var record: Dictionary = fixture._fixture()
	var catalog: Dictionary = fixture._catalog()
	fixture.free()
	record.vessels = [VESSELS.from_prebuilt("fishing_hook_line", "fish", "company-a", "Nordlys"),
		VESSELS.from_prebuilt("coastal_coaster", "bulk", "company-visitor", "Coastal Bulk")]
	record.stores[0].name = "Coal quay"
	record.stores[0].accepted_handling_modes = ["bulk"]
	record.stores[0].handling_capacity_kg = {"bulk": 20000}
	state = STATE.from_dict(record, record.world, catalog)
	_check(state.validation_errors.is_empty(), "UI fixture uses valid installed vessel capacities")
	var background := ColorRect.new()
	background.color = Color("23353e")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	panel = PANEL.new()
	add_child(panel)
	panel.position = Vector2(34, 28)
	panel.size = Vector2(620, 690)
	panel.configure(state, catalog, "", Vector2(620, 690))
	panel.state_changed.connect(func(_snapshot: Dictionary, result: Dictionary): changes.append(result))
	await get_tree().process_frame
	_check(panel._settings_name.editable == false and panel._save_storage.disabled, "Owner controls default read-only")
	var before := state.to_dict()
	panel._save_storage_settings()
	_check(state.to_dict() == before and changes.is_empty(), "Opening the inspector cannot grant ownership")
	_check(panel._vessel_details.text.contains("Fish hold") and not panel._vessel_details.text.contains("0 cargo positions"), "Fishing hold has readable typed capacity")
	panel.set_storage_admin_actor("company-a")
	_check(panel._settings_name.editable and not panel._save_storage.disabled, "Explicit demo owner enables storage settings")
	panel._settings_name.text = "North quay coal store"
	panel._visitors_collect.button_pressed = true
	panel._visitors_deliver.button_pressed = true
	panel._all_commodities.button_pressed = false
	for id in panel._commodity_checks: panel._commodity_checks[id].button_pressed = id == "coal"
	panel._save_storage.pressed.emit()
	var store: Dictionary = state.to_dict().stores[0]
	_check(store.name == "North quay coal store" and store.public_loading and store.public_unloading and store.accepted_commodities == ["coal"], "Save callback applies all owner fields through one command")
	_check(changes.size() == 1 and changes[0].events[0].kind == "configure_store", "Owner save publishes one authority event")
	_check(is_equal_approx(float(store.capacity_kg), 20000) and is_equal_approx(float(store.lots[0].quantity), 10000), "Settings never change capacity or cargo")
	_select(panel._vessel, "bulk")
	panel._refresh_vessel()
	_check(panel._vessel_details.text.contains("Dry bulk hold"), "Bulk vessel exposes its installed hold")
	panel._dock.pressed.emit()
	_check(not str(state.to_dict().vessels[1].berth_id).is_empty(), "Selected visitor company can dock its own vessel")
	panel._quantity.value = 1200
	panel._reserve.pressed.emit()
	_check(state.to_dict().reservations.size() == 1 and state.to_dict().reservations[0].actor_company_id == "company-visitor", "Cargo command retains vessel actor after owner editing")
	before = state.to_dict()
	panel._visitors_collect.button_pressed = false
	panel._save_storage.pressed.emit()
	_check(state.to_dict() == before and panel._feedback.text.contains("visitor has reserved"), "Owner UI explains and rejects closure with visitor cargo reserved")
	panel._refresh_storage_settings()
	panel._all_commodities.button_pressed = false
	for id in panel._commodity_checks: panel._commodity_checks[id].button_pressed = id == "iron_ore"
	panel._save_storage.pressed.emit()
	_check(state.to_dict() == before and panel._feedback.text.contains("still holds goods"), "Owner UI cannot strand existing stock by editing the filter")
	panel._refresh_storage_settings()
	panel._load.pressed.emit()
	_check(is_equal_approx(float(state.to_dict().vessels[1].lots[0].quantity), 1200), "Visitor loads the actual reserved goods")
	panel._quantity.value = 200
	panel._unload.pressed.emit()
	_check(is_equal_approx(float(state.to_dict().vessels[1].lots[0].quantity), 1000) and is_equal_approx(float(state.to_dict().stores[0].lots[0].quantity), 9000), "Visitor delivers permitted cargo without loss")
	panel._visitors_collect.button_pressed = false
	panel._save_storage.pressed.emit()
	_check(not state.to_dict().stores[0].public_loading, "Owner can close collection after visitor reservation finishes")
	panel.set_storage_admin_actor("company-visitor")
	before = state.to_dict()
	panel._save_storage_settings()
	_check(panel._save_storage.disabled and state.to_dict() == before, "Non-owner actor cannot configure storage even through callback")
	var restored := STATE.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())), record.world, catalog)
	_check(restored.validation_errors.is_empty() and restored.to_dict().stores == state.to_dict().stores, "Saved owner choices survive a new authority instance")
	panel.configure(restored, catalog, "", Vector2(620, 690))
	panel.set_storage_admin_actor("company-a")
	_check(panel._settings_name.text == "North quay coal store" and not panel._visitors_collect.button_pressed and panel._visitors_deliver.button_pressed, "Reopened native form reflects persisted owner choices")
	panel._set_feedback("Storage settings saved.", true)
	for node in panel.find_children("*", "TabContainer", true, false): node.current_tab = 2
	for frame in 5: await get_tree().process_frame
	_check(panel.size.y <= 690, "Repeated updates do not grow the fixed panel beyond its host bounds")
	_check(panel._save_storage.get_global_rect().end.y <= panel.get_global_rect().end.y, "Save action stays inside the panel below scrolling content")
	if "--capture-port-storage" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		var archive := "C:/Users/noahs/Pictures/machinescreenshots"
		DirAccess.make_dir_recursive_absolute(archive)
		var path := archive.path_join("custom-port-storage-%s.png" % Time.get_datetime_string_from_system().replace(":", "-"))
		var error := get_viewport().get_texture().get_image().save_png(path)
		_check(error == OK, "Native storage review archived successfully")
		print("PORT_STORAGE_CAPTURE ", path)
	await _test_whole_fish()
	for failure in failures: push_error(failure)
	print("CUSTOM PORT INSPECTOR %s: %d checks; %d failures" % ["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)


func _test_whole_fish() -> void:
	var fixture := CATCH_FIXTURE.new()
	var record: Dictionary = fixture._catch_fixture()
	var catalog: Dictionary = fixture._catalog()
	fixture.free()
	record.vessels[0].owner_company_id = "company-visitor"
	var cod: Dictionary = record.vessels[0].lots[0]
	cod.quantity = 1
	cod.unit_mass_kg = 38.5
	cod.attributes.custom_label = "Keep the complete cod"
	var halibut := cod.duplicate(true)
	halibut.id = "halibut-002"
	halibut.quantity = 12.5
	halibut.unit_mass_kg = 1
	halibut.attributes.species_id = "halibut"
	halibut.attributes.custom_label = "Keep the complete halibut"
	record.vessels[0].lots.append(halibut)
	state = STATE.from_dict(record, record.world, catalog)
	_check(state.validation_errors.is_empty(), "Both specimen quantity formats validate on the real fishing vessel")
	if not state.validation_errors.is_empty(): return
	var expected_lots: Array = state.to_dict().vessels[0].lots.duplicate(true)
	panel.configure(state, catalog, "", Vector2(620, 690))
	panel.set_storage_admin_actor("company-a")
	_select(panel._vessel, "ship-a")
	panel._refresh_vessel()
	panel._dock.pressed.emit()
	_check(not str(state.to_dict().vessels[0].berth_id).is_empty(), "Visitor fishing vessel docks through its native button")
	for expected in expected_lots:
		var id := str(expected.id)
		var species := str(expected.attributes.species_id)
		var mass_text := "38.5" if id == "cod-001" else "12.5"
		_select(panel._unload_lot, id)
		panel._refresh_unload_action()
		var aboard_label := panel._unload_lot.get_item_text(panel._unload_lot.selected).to_lower()
		_check(aboard_label.contains(species) and aboard_label.contains(mass_text) and aboard_label.contains("kg"), id + ": aboard selector shows species and actual fish mass")
		_check(panel._unload.text == "Unload fish" and panel._unload.tooltip_text.to_lower().contains("whole fish"), id + ": unload action explains the whole-fish operation")
		_check(not panel._unload.disabled, id + ": valid fish unloading is enabled")
		var prior_changes := changes.size()
		panel._quantity.value = 6
		panel._unload.pressed.emit()
		_check(changes.size() == prior_changes + 1, id + ": native unload publishes one successful command")
		var landed := state.to_dict()
		_check(_lot_by_id(landed.stores[0].lots, id) == expected and _lot_by_id(landed.vessels[0].lots, id).is_empty(), id + ": wrong quantity cannot split the fish or alter metadata while unloading")
		if _lot_by_id(landed.stores[0].lots, id).is_empty(): return
		_select(panel._lot, id)
		panel._refresh_stock()
		var ashore_label := panel._lot.get_item_text(panel._lot.selected).to_lower()
		_check(ashore_label.contains(species) and ashore_label.contains(mass_text) and ashore_label.contains("kg"), id + ": available selector shows species and actual fish mass")
		_check(panel._reserve.text == "Reserve fish" and panel._reserve.tooltip_text.to_lower().contains("whole fish"), id + ": reserve action explains the whole-fish operation")
		_check(not panel._reserve.disabled, id + ": valid fish reservation is enabled")
		panel._quantity.value = 999
		prior_changes = changes.size()
		panel._reserve.pressed.emit()
		_check(changes.size() == prior_changes + 1, id + ": native reserve publishes one successful command")
		var reserved := state.to_dict()
		_check(reserved.reservations.size() == 1, id + ": one complete specimen is reserved")
		if reserved.reservations.size() != 1: return
		var reservation: Dictionary = reserved.reservations[0]
		_check(reservation.lot_id == id and reservation.quantity == expected.quantity and reservation.unit_mass_kg == expected.unit_mass_kg, id + ": reservation uses the exact specimen representation instead of the shared field")
		_check(reservation.actor_company_id == "company-visitor" and reserved.vessels[0].owner_company_id == "company-visitor", id + ": storage-owner editing does not replace the vessel-owner actor")
		_check(_lot_by_id(reserved.stores[0].lots, id) == expected, id + ": reserving preserves every fish attribute")
		_select(panel._reservation, str(reservation.id))
		panel._refresh_reservation_actions()
		panel._quantity.value = 6
		prior_changes = changes.size()
		panel._load.pressed.emit()
		_check(changes.size() == prior_changes + 1, id + ": native load publishes one successful command")
		var loaded := state.to_dict()
		_check(loaded.reservations.is_empty() and _lot_by_id(loaded.stores[0].lots, id).is_empty(), id + ": loading consumes the complete shore fish and reservation")
		_check(_lot_by_id(loaded.vessels[0].lots, id) == expected, id + ": whole-fish round-trip preserves the full ID and attributes")
	var restored := STATE.from_dict(JSON.parse_string(JSON.stringify(state.to_dict(), "", true, true)), record.world, catalog)
	_check(restored.validation_errors.is_empty() and restored.to_dict() == state.to_dict(), "Both whole-fish UI round-trips reconstruct exactly from JSON")
	_check(state.to_dict().vessels[0].lots.size() == expected_lots.size() and state.to_dict().stores[0].lots.is_empty(), "Whole-fish UI actions neither duplicate nor leave fragments")
	var divisible := record.duplicate(true)
	var bulk_fish := cod.duplicate(true)
	bulk_fish.quantity = 100
	bulk_fish.unit_mass_kg = 1
	bulk_fish.attributes.specimen = false
	divisible.vessels[0].lots = [bulk_fish]
	state = STATE.from_dict(divisible, divisible.world, catalog)
	_check(state.validation_errors.is_empty(), "Ordinary divisible-catch UI fixture validates")
	if not state.validation_errors.is_empty(): return
	var canonical_bulk: Dictionary = state.to_dict().vessels[0].lots[0]
	panel.configure(state, catalog, "", Vector2(620, 690))
	panel.set_storage_admin_actor("company-a")
	panel._dock.pressed.emit()
	_check(panel._unload.text == "Unload quantity", "Ordinary catch keeps the quantity-based unload action")
	panel._quantity.value = 20
	panel._unload.pressed.emit()
	var aboard_bulk := canonical_bulk.duplicate(true)
	aboard_bulk.quantity = 80.0
	var ashore_bulk := canonical_bulk.duplicate(true)
	ashore_bulk.quantity = 20.0
	_check(state.to_dict().vessels[0].lots == [aboard_bulk] and state.to_dict().stores[0].lots == [ashore_bulk], "specimen=false catch uses the shared quantity field and preserves the remainder")
	# A whole fish can exceed one compartment despite sufficient total room.
	var cramped := record.duplicate(true)
	cramped.vessels[0].erase("prebuilt_id")
	cramped.vessels[0].cargo_holds = [
		{"id": "small-a", "handling_mode": "catch", "capacity_kg": 300},
		{"id": "small-b", "handling_mode": "catch", "capacity_kg": 300}]
	var large_fish := halibut.duplicate(true)
	large_fish.quantity = 400
	cramped.stores[0].lots = [large_fish]
	cramped.vessels[0].lots = []
	state = STATE.from_dict(cramped, cramped.world, catalog)
	_check(state.validation_errors.is_empty(), "Compartment-rejection UI fixture is individually valid")
	if not state.validation_errors.is_empty(): return
	panel.configure(state, catalog, "", Vector2(620, 690))
	panel.set_storage_admin_actor("company-a")
	panel._dock.pressed.emit()
	_check(not str(state.to_dict().vessels[0].berth_id).is_empty(), "Compartment-rejection fishing vessel docks")
	var before := state.to_dict()
	var prior_changes := changes.size()
	panel._quantity.value = 999
	panel._reserve.pressed.emit()
	_check(state.to_dict() == before and changes.size() == prior_changes, "An oversized whole fish is rejected without changing cargo or reservations")
	var message := panel._feedback.text.to_lower()
	_check(message.contains("fish") and message.contains("hold") and not message.contains("catch_compartments_exceeded"), "Compartment rejection explains the fish/hold limit in friendly text")
	await get_tree().process_frame


func _lot_by_id(lots: Array, id: String) -> Dictionary:
	for lot in lots:
		if str(lot.get("id", "")) == id: return lot
	return {}


func _select(selector: OptionButton, id: String) -> void:
	for index in selector.item_count:
		if str(selector.get_item_metadata(index)) == id:
			selector.select(index)
			return


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)
