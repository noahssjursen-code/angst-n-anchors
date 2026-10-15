extends "res://tests/custom_port_data_test.gd"
const EDITOR = preload("res://scripts/port/building/custom_port_editor.gd")

func _run() -> void:
	assert(ShipyardPlaytestMode.active())
	_test_stocked_transform()
	_test_transform_rejections()
	_test_occupied_and_reserved_transform()
	_test_transform_editor()
	_test_support_depth_and_group_undo()
	_test_rotate_authored_pivots()
	_test_local_preview_matches_authority()
	for failure in failures: push_error(failure)
	print("CUSTOM PORT TRANSFORM ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)


func _transform_catalog() -> Dictionary:
	var catalog := _catalog()
	catalog.plant = catalog.crane.duplicate(true)
	catalog.plant.attached_store_only = true
	catalog.plant.reach_min_m = 0
	catalog.plant.storage_rect_m = [-2,-2,4,4]
	catalog.plant.attached_store = {"capacity_kg":10000, "accepted_handling_modes":["bulk"], "accepted_commodities":["iron_ore"]}
	return catalog


func _transform_fixture() -> Dictionary:
	var record := _fixture()
	record.placements.append(_placement("plant", "plant", 20, 8, {"display_name":"Iron receiver", "store_ids":["plant-store"], "maintenance":{"inspection":"Keep me"}}))
	record.placements.append(_placement("lamp", "lamp", 40, 10, {"custom_colour":"green"}))
	record.stores.append({"id":"plant-store", "placement_id":"plant", "name":"Ore receiver", "capacity_kg":10000, "public_loading":true,
		"accepted_handling_modes":["bulk"], "accepted_commodities":["iron_ore"], "lots":[{"id":"ore-lot", "commodity_id":"iron_ore", "quantity":1500, "unit_mass_kg":1, "attributes":{"consignment_id":"ordered-ore", "quality":.8}}]})
	return record


func _transform_state(record: Dictionary = {}) -> CustomPortState:
	var input := _transform_fixture() if record.is_empty() else record
	var state := STATE.from_dict(input, input.world, _transform_catalog())
	check(state.validation_errors.is_empty(), "Transform fixture validates")
	return state


func _row(rows: Array, id: String) -> Dictionary:
	for row in rows:
		if str(row.get("id", "")) == id: return row
	return {}


func _transform_payload(state: CustomPortState, id: String, at: Vector3, yaw := 0.0) -> Dictionary:
	return {"placement_id":id, "expected_placement":_row(state.to_dict().placements, id).duplicate(true), "position_m":[at.x,at.y,at.z], "yaw_degrees":yaw}


func _test_stocked_transform() -> void:
	var state := _transform_state()
	var before := state.to_dict()
	var payload := _transform_payload(state, "plant", Vector3(30,0,8), 90)
	var checked := state.preview_transform(payload, "company-a")
	check(checked.ok and state.to_dict() == before, "Stocked plant move/rotation preview changes no authority")
	var applied := _command(state, "transform_asset", payload)
	check(applied.ok and applied.events.size() == 1, "Stocked plant moves in one accepted event")
	if not applied.ok: return
	var current := state.to_dict()
	var plant := _row(current.placements, "plant")
	check(plant.position_m == [30.0,0.0,8.0] and plant.yaw_degrees == 90, "Accepted transform updates only pose")
	check(plant.id == payload.expected_placement.id and plant.asset_id == payload.expected_placement.asset_id and plant.attributes == payload.expected_placement.attributes, "Placement identity, asset and all custom metadata survive")
	check(current.stores == before.stores and current.vessels == before.vessels and applied.account_changes.is_empty(), "Attached stock, lots, identities, owner access and fleet are unchanged")
	check(applied.events[0].changes.keys() == ["placements"], "Event carries a placement update, not a replacement inventory")
	var replica := _transform_state(before)
	check(replica.replay_event(JSON.parse_string(JSON.stringify(applied.events[0], "", true, true))).ok and replica.to_dict() == current, "Event-only replica reconstructs the moved stocked plant")
	check(_transform_state(JSON.parse_string(JSON.stringify(current, "", true, true))).to_dict() == current, "Moved plant and untouched stock survive JSON save/load")
	check(replica.replay_event(applied.events[0]).code == "already_applied" and replica.to_dict() == current, "Repeated transform event cannot duplicate inventory")


func _test_transform_rejections() -> void:
	var state := _transform_state()
	for case in [Vector3(20,0,-8), Vector3(60,0,8), Vector3(110,0,8), Vector3(30,1,8)]:
		_reject_unchanged(state, "transform_asset", _transform_payload(state, "plant", case), "invalid_result")
	_reject_unchanged(state, "transform_asset", _transform_payload(state, "plant", Vector3(30,0,8), 22), "invalid_result")
	var payload := _transform_payload(state, "plant", Vector3(30,0,8))
	_reject_unchanged(state, "transform_asset", payload, "not_port_owner", "company-stranger")
	var bad := payload.duplicate(true); bad.erase("expected_placement")
	_reject_unchanged(state, "transform_asset", bad, "invalid_transform")
	bad = payload.duplicate(true); bad.asset_id = "lamp"
	_reject_unchanged(state, "transform_asset", bad, "invalid_transform")
	bad = payload.duplicate(true); bad.attributes = {"store_ids":[]}
	_reject_unchanged(state, "transform_asset", bad, "invalid_transform")
	bad = payload.duplicate(true); bad.expected_placement.attributes.display_name = "stale"
	_reject_unchanged(state, "transform_asset", bad, "placement_changed")
	bad = payload.duplicate(true); bad.position_m = [1,2]
	_reject_unchanged(state, "transform_asset", bad, "invalid_transform")
	bad = payload.duplicate(true); bad.position_m = [1,0,"north"]
	_reject_unchanged(state, "transform_asset", bad, "invalid_transform")
	_reject_unchanged(state, "transform_asset", _transform_payload(state, "plant", Vector3(20,0,8)), "placement_unchanged")
	var before := state.to_dict()
	check(not state.preview_transform(_transform_payload(state,"plant",Vector3(20,0,-8)),"company-a").ok and state.to_dict() == before, "Rejected speculative overlap leaves caches and committed plant intact")
	check(state.derived_berths() == CustomPortBerths.derive(before, _transform_catalog()), "Rejected move does not poison the committed berth cache")


func _test_occupied_and_reserved_transform() -> void:
	var state := _transform_state()
	var berth := state.derived_berths()[0]
	check(_command(state,"dock",{"vessel_id":"ship-a","berth_id":berth.id}).ok, "Transform safety fixture docks a real-sized vessel")
	var shifted := state.to_dict()
	_row(shifted.placements, "bollard-a").position_m = [-38,0,-19]
	check(_transform_state(shifted).validation_errors.is_empty(), "Changing anchor slightly would still pass ordinary fit validation")
	_reject_unchanged(state,"transform_asset",_transform_payload(state,"bollard-a",Vector3(-38,0,-19)),"berth_in_use")
	check(_command(state,"transform_asset",_transform_payload(state,"crane-2",Vector3(24,0,-8))).ok, "Idle crane can move without moving a safely secured hull")
	check(_command(state,"reserve_cargo",{"vessel_id":"ship-a","store_id":"yard","lot_id":"coal-lot","quantity":100,"reservation_id":"pending-coal"}).ok, "Transfer reservation establishes equipment protection")
	_reject_unchanged(state,"transform_asset",_transform_payload(state,"pad-1",Vector3(-16,0,5)),"store_reserved")
	_reject_unchanged(state,"transform_asset",_transform_payload(state,"crane-1",Vector3(-16,0,-8)),"placement_reserved")
	check(_command(state,"transform_asset",_transform_payload(state,"lamp",Vector3(38,0,10))).ok, "Unrelated decoration is not locked by another store's reservation")
	check(_command(state,"cancel_reservation",{"reservation_id":"pending-coal"}).ok, "Cancelling releases reserved equipment")
	check(_command(state,"transform_asset",_transform_payload(state,"pad-1",Vector3(-16,0,5))).ok, "Stocked cargo pad may move again after the reservation is cancelled")


func _test_transform_editor() -> void:
	var input := _transform_fixture()
	input.vessels[0].lots = [{"id":"later-ore", "commodity_id":"iron_ore", "quantity":700, "unit_mass_kg":1, "attributes":{"consignment_id":"new-shipment"}}]
	var state := _transform_state(input)
	var editor := EDITOR.new()
	editor.configure(state, _transform_catalog(), "company-a")
	var before := state.to_dict()
	var proposal := editor.preview_transform("plant", Vector3(22.2,900,8.2), 86)
	check(proposal.ok and proposal.placement.position_m == [22.0,0,8.0] and proposal.placement.yaw_degrees == 90, "Moving snaps to real units, common deck plane and rotation grid")
	check(proposal.placement.attributes == proposal.expected_placement.attributes and proposal.placement.id == "plant", "Transform preview retains existing metadata and identity")
	check(state.to_dict() == before, "A valid move ghost leaves the original plant and stock untouched")
	var count_before := editor.previews_evaluated
	for index in 50: editor.preview_transform("plant",Vector3(22.2+index*.001,-900,8.2),86)
	check(editor.previews_evaluated == count_before, "Pointer movement within one snapped cell reuses validated move preview")
	var moved := editor.transform(proposal)
	check(moved.ok and editor.undo_count() == 1, "Existing stocked piece transforms without deleting/rebuilding it")
	check(state.to_dict().stores == before.stores, "Editor transform cannot replace or clear attached stock")
	var manipulated := editor.preview_transform("plant",Vector3(28,0,8),0)
	manipulated.placement.attributes.maintenance = {"inspection":"forged"}
	check(not editor.transform(manipulated).ok, "A modified move proposal cannot smuggle attribute edits")
	# A later valid stock change is independent of the placement transform. Undo
	# must target only pose, preserving the current inventory instead of a snapshot.
	var authority := state
	check(_command(authority,"dock",{"vessel_id":"ship-a","berth_id":authority.derived_berths()[1].id}).ok, "Another ship docks after the plant has moved")
	check(_command(authority,"unload_cargo",{"vessel_id":"ship-a","store_id":"plant-store","lot_id":"later-ore","quantity":700}).ok, "A real accepted cargo command receives more stock after the move")
	check(_command(authority,"undock",{"vessel_id":"ship-a"}).ok, "Arrival leaves without interfering with construction history")
	var received_stores: Array = authority.to_dict().stores
	check(editor.undo().ok, "Undo submits an inverse transform at the current revision")
	check(_row(authority.to_dict().placements,"plant") == _row(before.placements,"plant"), "Undo restores exact original pose and metadata")
	check(authority.to_dict().stores == received_stores and STATE._mass(_row(received_stores,"plant-store").lots) == 2200, "Undo preserves exact lots and stock received since the move")
	check(editor.undo_count() == 0, "Accepted inverse clears one undo group")
	var stale := editor.preview_transform("plant",Vector3(26,0,8),0)
	check(_command(authority,"transform_asset",_transform_payload(authority,"plant",Vector3(24,0,8))).ok, "Another accepted edit changes the original pose")
	var latest := authority.to_dict()
	check(not editor.transform(stale).ok and authority.to_dict() == latest, "Stale expected placement cannot overwrite a newer move")
	check(not editor.preview_transform("unknown",Vector3.ZERO).ok, "Missing selection cannot become a new piece")
	# Move the only platform out from under otherwise valid equipment: the old
	# support failure must be checked as well as overlap at the destination.
	check(not editor.preview_transform("quay-1",Vector3(60,0,0)).ok, "Moving a foundation cannot strand supported equipment behind it")


func _test_support_depth_and_group_undo() -> void:
	var record := _fixture()
	record.placements = [_placement("tile", "paving", 2, 2, {"support_depth_m":4, "custom_marker":"keep"})]
	record.stores = []
	record.vessels = []
	var state := _transform_state(record)
	var editor := EDITOR.new()
	editor.configure(state, _transform_catalog(), "company-a")
	var before := state.to_dict()
	var proposal := editor.preview_transform("tile", Vector3(-1,900,-1), 88)
	check(proposal.ok and proposal.placement.position_m == [-2.0,0,-2.0] and proposal.placement.yaw_degrees == 90, "Moving a foundation uses its own size at negative coordinates and rotated yaw")
	proposal.placement.attributes.support_depth_m = 12.5
	check(editor.transform(proposal).ok and state.to_dict().placements[0].attributes.support_depth_m == 12.5, "Host-sampled new support depth is committed atomically with the platform pose")
	check(editor.undo().ok and state.to_dict().placements == before.placements, "Undo restores the old support depth and exact original platform")
	for value in [0, -1, 5000, "deep", true]:
		var payload := _transform_payload(state,"tile",Vector3(6,0,2))
		payload.support_depth_m = value
		_reject_unchanged(state,"transform_asset",payload,"invalid_support_depth")
	var equipment := _transform_state()
	var payload := _transform_payload(equipment,"plant",Vector3(30,0,8))
	payload.support_depth_m = 20
	_reject_unchanged(equipment,"transform_asset",payload,"invalid_support_depth")
	record.placements[0].attributes.erase("support_depth_m")
	state = _transform_state(record)
	editor.configure(state,_transform_catalog(),"company-a")
	before = state.to_dict()
	proposal = editor.preview_transform("tile",Vector3(6,0,2))
	proposal.placement.attributes.support_depth_m = 16
	check(editor.transform(proposal).ok and editor.undo().ok and state.to_dict().placements == before.placements, "Undo removes a newly sampled support override when the old tile used its default depth")
	state = _transform_state()
	editor.configure(state,_transform_catalog(),"company-a")
	before = state.to_dict()
	editor.begin_edit()
	check(editor.transform(editor.preview_transform("plant",Vector3(28,0,8))).ok, "Grouped transform moves first existing asset")
	check(editor.transform(editor.preview_transform("lamp",Vector3(38,0,10))).ok, "Grouped transform moves second existing asset")
	editor.end_edit()
	check(editor.undo_count() == 1 and editor.undo().ok and state.to_dict().placements == before.placements and state.to_dict().stores == before.stores, "Ctrl+Z applies a complete inverse transform group without replacing stores")
	var latest := state.to_dict()
	var operations := [{"kind":"transform_asset","payload":_transform_payload(state,"plant",Vector3(28,0,8))},
		{"kind":"transform_asset","payload":_transform_payload(state,"lamp",Vector3(300,0,10))}]
	check(not _command(state,"edit_assets",{"operations":operations}).ok and state.to_dict() == latest, "An invalid second move rolls back the entire transform group")
	var bollard_move := editor.preview_transform("bollard-a",Vector3(-38,0,-19))
	check(editor.transform(bollard_move).ok, "An unoccupied mooring anchor may move")
	check(_command(state,"dock",{"vessel_id":"ship-a","berth_id":state.derived_berths()[0].id}).ok, "A vessel may subsequently dock at the edited berth")
	latest = state.to_dict()
	check(not editor.undo().ok and state.to_dict() == latest and editor.undo_count() == 1, "Undo cannot move an anchor underneath a now-secured vessel and keeps its pending history")


func _test_rotate_authored_pivots() -> void:
	for sign_value in [-1.0, 1.0]:
		var input := _transform_fixture()
		var authored := Vector3(20.25 * sign_value, 0, 14.35)
		_row(input.placements, "plant").position_m = [authored.x,0,authored.z]
		var state := _transform_state(input)
		var editor := EDITOR.new()
		editor.configure(state, _transform_catalog(), "company-a")
		var before := state.to_dict()
		for yaw in [90,180,270]:
			var proposal := editor.preview_transform("plant", authored + Vector3(0,100,0), yaw)
			check(proposal.ok and proposal.placement.position_m == [authored.x,0,authored.z], "Rotating at an authored off-grid pivot does not translate it")
		var proposal := editor.preview_transform("plant", authored, 90)
		check(editor.transform(proposal).ok and editor.undo().ok and state.to_dict().placements == before.placements,
			"Off-grid rotation and undo preserve exact centre, metadata and stock")
		var moved := editor.preview_transform("plant", authored + Vector3(4.1,0,0), 90)
		check(moved.placement.position_m[0] == snappedf(authored.x + 4.1, 1.0), "Dragging away from the authored pivot resumes ordinary position snapping")


func _test_local_preview_matches_authority() -> void:
	for busy in [false, true]:
		var state := _transform_state()
		if busy:
			check(_command(state,"dock",{"vessel_id":"ship-a","berth_id":state.derived_berths()[0].id}).ok, "Preview parity fixture has an occupied berth")
			check(_command(state,"reserve_cargo",{"vessel_id":"ship-a","store_id":"yard","lot_id":"coal-lot","quantity":100,"reservation_id":"preview-reservation"}).ok, "Preview parity fixture has reserved cargo")
		var editor := EDITOR.new()
		editor.configure(state,_transform_catalog(),"company-a")
		var before := state.to_dict()
		for position in [Vector3(38,0,10),Vector3(20,0,-8),Vector3(60,0,10),Vector3(110,0,10),Vector3(40,0,10)]:
			for yaw in [0.0,90.0]:
				var preview := editor.preview_transform("lamp",position,yaw)
				var cold := STATE.from_dict(before,before.world,_transform_catalog())
				var payload := {"placement_id":"lamp","expected_placement":preview.expected_placement,"position_m":preview.placement.position_m,"yaw_degrees":preview.placement.yaw_degrees}
				var checked := cold.preview_transform(payload,"company-a")
				check(preview.ok == checked.ok, "Local decoration preview equals cold full validation with occupancy/reservations=%s at %s yaw=%s" % [busy,position,yaw])
		check(state.to_dict() == before, "Local preview never changes stock, reservation, occupancy or committed pose")
		if busy:
			check(not editor.preview_transform("pad-1",Vector3(-16,0,5)).ok, "An abstract store pad remains fully checked and cannot evade its reservation")
			check(not editor.preview_transform("crane-1",Vector3(-16,0,-8)).ok, "Serving crane remains fully checked while reserved")
			check(not editor.preview_transform("bollard-a",Vector3(-38,0,-19)).ok, "Occupied mooring remains fully checked")
		var valid := editor.preview_transform("lamp",Vector3(38,0,10))
		valid.placement.position_m = [20,0,-8]
		check(not editor.transform(valid).ok and state.to_dict() == before, "Even a forged locally-green proposal still receives full final overlap validation")
