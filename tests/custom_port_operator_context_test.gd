extends Node
const FIXTURE = preload("res://tests/custom_port_data_test.gd")
const CONTEXT = preload("res://scripts/port/building/custom_port_operator_context.gd")
const PANEL = preload("res://scripts/port/building/custom_port_inspector.gd")
var checks := 0
var failures: Array[String] = []
var events := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	assert(ShipyardPlaytestMode.active())
	get_window().content_scale_size = Vector2i(1000, 780)
	var fixture := FIXTURE.new()
	var record: Dictionary = fixture._fixture()
	var catalog: Dictionary = fixture._catalog()
	catalog.crane.reach_max_m = 30
	catalog.fish_crane = catalog.crane.duplicate(true)
	catalog.crane.cargo_types = ["bulk"]
	catalog.fish_crane.cargo_types = ["catch"]
	catalog.operator = {"kind":"npc", "footprint_m":[1,1], "placement_layer":"equipment", "requires_support":true}
	record.name = "Operator harbour"
	record.placements[5].asset_id = "fish_crane"
	record.placements[5].attributes.store_ids = ["fish-store"]
	record.placements.append(fixture._placement("fish-pad", "yard", 20, 5))
	record.placements.append(fixture._placement("bulk-operator", "operator", -35, 12))
	record.placements.append(fixture._placement("fish-operator", "operator", 35, 12, {"store_id":"fish-store"}))
	record.stores[0].name = "Coal yard"
	record.stores[0].accepted_handling_modes = ["bulk"]
	record.stores.append({"id":"fish-store", "name":"Fish receiver", "placement_id":"fish-pad", "capacity_kg":20000,
		"accepted_handling_modes":["catch"], "accepted_commodities":["fresh_groundfish"], "public_loading":true, "public_unloading":true,
		"lots":[{"id":"landed-cod", "commodity_id":"fresh_groundfish", "quantity":250, "unit_mass_kg":1, "attributes":{"species_id":"cod", "quality":.9}}]})
	record.vessels = [fixture._vessel("coal-boat"), fixture._vessel("fish-boat")]
	record.vessels[0].name = "Coal carrier"
	record.vessels[0].accepted_handling_modes = ["bulk"]
	record.vessels[1].name = "Nordlys"
	record.vessels[1].accepted_handling_modes = ["catch"]
	fixture.free()
	var state := CustomPortState.from_dict(record, record.world, catalog)
	_check(state.validation_errors.is_empty(), "Two equipped berths and two independent cargo stores validate")
	if not state.validation_errors.is_empty():
		push_error(str(state.validation_errors))
		_finish()
		return
	var berths := state.derived_berths()
	_check(berths.size() == 2, "Bollards derive two real serviceable berths")
	for index in 2:
		var result := state.apply({"command_id":"dock-%d"%index, "expected_revision":state.revision(), "actor_company_id":"company-a", "kind":"dock",
			"payload":{"vessel_id":record.vessels[index].id, "berth_id":berths[index].id}})
		_check(result.ok, "Actual authority docks the appropriate vessel")
	var snapshot := state.to_dict()
	var before := snapshot.duplicate(true)
	var bulk := CONTEXT.resolve(snapshot, "bulk-operator", "fish-boat", catalog)
	_check(bulk.ok and bulk.tab == "cargo" and bulk.store_id == "yard" and bulk.vessel_id == "coal-boat", "Nearest store wins and incompatible preferred vessel is ignored")
	var fish := CONTEXT.resolve(snapshot, "fish-operator", "coal-boat", catalog)
	_check(fish.ok and fish.store_id == "fish-store" and fish.vessel_id == "fish-boat", "Explicit fish receiver selects the actually served fishing vessel")
	var office_record:=snapshot.duplicate(true)
	for row in office_record.placements:
		if row.id=="bulk-operator":row.attributes.service="berths"
	var office:=CONTEXT.resolve(office_record,"bulk-operator","coal-boat",catalog)
	_check(office.ok and office.tab=="berths" and office.store_id.is_empty() and office.vessel_id.is_empty(),"A configured harbour office opens docking despite nearby cargo and a preferred ship")
	_check(CONTEXT.resolve(office_record,"fish-operator","",catalog).tab=="cargo","A harbour office does not change the separate fish operator's business")
	var moved := snapshot.duplicate(true)
	moved.placements.back().position_m = [-36, 0, 12]
	_check(CONTEXT.resolve(moved, "fish-operator", "", catalog).store_id == "fish-store", "Explicit business identity wins even when another store is physically nearer")
	var broken := snapshot.duplicate(true)
	broken.placements.back().attributes.store_id = "removed-store"
	var unavailable := CONTEXT.resolve(broken, "fish-operator", "", catalog)
	_check(not unavailable.ok and unavailable.code == "operator_store_unavailable" and unavailable.store_id == "", "Missing explicit storage cannot silently redirect to another business")
	_check(not CONTEXT.resolve(snapshot, "removed-operator", "", catalog).ok, "Missing operator is unavailable")
	var absent := snapshot.duplicate(true)
	absent.vessels[1].berth_id = ""
	_check(CONTEXT.resolve(absent, "fish-operator", "fish-boat", catalog).vessel_id == "", "An undocked preferred vessel is not presented as served")
	var no_stores := snapshot.duplicate(true)
	no_stores.stores = []
	var generic := CONTEXT.resolve(no_stores, "bulk-operator", "", catalog)
	_check(generic.ok and generic.tab == "berths" and generic.store_id == "", "Operator without cargo storage opens berth records")
	_check(not CONTEXT.resolve(no_stores, "fish-operator", "", catalog).ok, "Explicit missing receiver stays unavailable even when no stores remain")
	# Two reachable bulk ships: preferred only wins after geometry and mode checks.
	var shared := snapshot.duplicate(true)
	shared.vessels[1].accepted_handling_modes = ["bulk"]
	shared.placements[5].asset_id = "crane"
	shared.placements[5].attributes.store_ids = ["yard", "fish-store"]
	var wide := catalog.duplicate(true)
	wide.crane.reach_max_m = 80
	_check(CONTEXT.resolve(shared, "bulk-operator", "", wide).vessel_id == "coal-boat", "Without preference, nearest genuinely serviced docked vessel wins")
	_check(CONTEXT.resolve(shared, "bulk-operator", "fish-boat", wide).vessel_id == "fish-boat", "Eligible preferred vessel wins over nearer one")
	_check(snapshot == before and state.to_dict() == before, "Pure navigation changes no state, receipts, stock or permissions")
	fish.store_id = "caller-edited"
	_check(CONTEXT.resolve(snapshot, "fish-operator", "", catalog).store_id == "fish-store", "Returned context cannot alias or corrupt port data")
	var background := ColorRect.new()
	background.color = Color("23353e")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var panel := PANEL.new()
	add_child(panel)
	panel.position = Vector2(34, 28)
	panel.configure(state, catalog, "", Vector2(620, 690))
	panel.state_changed.connect(func(_snapshot:Dictionary, _result:Dictionary): events += 1)
	_check(panel.focus_cargo("fish-store", "fish-boat"), "Public focus accepts actual store and vessel identities")
	_check(panel._tabs.current_tab == 1 and panel._selected(panel._store) == "fish-store" and panel._selected(panel._vessel) == "fish-boat", "Native panel opens Cargo with the operator's exact receiver and boat")
	panel.refresh()
	_check(panel._tabs.current_tab == 1 and panel._selected(panel._store) == "fish-store" and panel._selected(panel._vessel) == "fish-boat", "Refresh preserves operator selection")
	_check(not panel.focus_cargo("missing", "fish-boat") and not panel.focus_cargo("fish-store", "missing"), "Bad public focus does not invent identities")
	_check(panel._selected(panel._store) == "fish-store" and panel._selected(panel._vessel) == "fish-boat", "Bad focus preserves the previous real business")
	_check(state.to_dict() == before and events == 0, "Opening and refreshing native context emits no authority event")
	_check(panel.focus_cargo("fish-store"), "A store can be inspected with no served vessel")
	panel.refresh()
	_check(panel._selected(panel._vessel) == "" and panel._reserve.disabled and panel._unload.disabled, "Empty vessel selection survives refresh without substituting the first vessel")
	panel.focus_cargo("yard", "coal-boat")
	panel._quantity.value = 100
	panel._reserve.pressed.emit()
	_check(state.to_dict().reservations.size() == 1 and panel._selected(panel._store) == "yard" and panel._selected(panel._vessel) == "coal-boat", "Real reserve action retains the operator's cargo context")
	panel._load.pressed.emit()
	_check(state.to_dict().vessels[0].lots.size() == 1 and panel._tabs.current_tab == 1 and panel._selected(panel._store) == "yard", "Real load action retains the same store and Cargo tab")
	panel._unload.pressed.emit()
	_check(state.to_dict().vessels[0].lots.is_empty() and events == 3 and panel._selected(panel._vessel) == "coal-boat", "Real unload completes without losing selected vessel")
	panel.focus_berths()
	_check(panel._tabs.current_tab == 0 and not panel._cargo_focus_active, "Generic port records explicitly return to Berths")
	panel.focus_cargo("fish-store", "fish-boat")
	_check(panel._feedback.text.is_empty(), "Opening another operator clears the previous business's action feedback")
	for frame in 5: await get_tree().process_frame
	_check(panel.size.y <= 690 and panel._load.get_global_rect().end.y <= panel.get_global_rect().end.y, "Operator cargo view retains reachable actions within the host")
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		var archive := "C:/Users/noahs/Pictures/machinescreenshots"
		DirAccess.make_dir_recursive_absolute(archive)
		var path := archive.path_join("custom-port-operator-context-%s.png" % Time.get_datetime_string_from_system().replace(":", "-"))
		_check(get_viewport().get_texture().get_image().save_png(path) == OK, "Native operator cargo view archived")
		print("OPERATOR_CONTEXT_CAPTURE ", path)
	panel.free()
	_finish()


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)


func _finish() -> void:
	for failure in failures: push_error(failure)
	print("CUSTOM PORT OPERATOR CONTEXT %s: %d checks; %d failures" % ["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
