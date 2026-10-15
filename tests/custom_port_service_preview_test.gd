extends "res://tests/custom_port_transform_test.gd"

## Compare optimized editor previews with independent, complete authority
## commands. No diagnostic preflight is treated as permission to place.
func _run() -> void:
	assert(ShipyardPlaytestMode.active())
	for phase in ["idle", "docked", "reserved"]: _compare_phase(phase)
	_test_preflight_contract()
	_test_structural_fallback()
	for failure in failures: push_error(failure)
	print("CUSTOM PORT SERVICE PREVIEW ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)

func _compare_phase(phase: String) -> void:
	var state := _transform_state()
	if phase != "idle":
		check(_command(state,"dock",{"vessel_id":"ship-a","berth_id":state.derived_berths()[0].id}).ok, phase + ": vessel is safely docked")
	if phase == "reserved":
		check(_command(state,"reserve_cargo",{"vessel_id":"ship-a","store_id":"yard","lot_id":"coal-lot","quantity":100,"reservation_id":"service-preview"}).ok,
			"Cross-linked yard has a real active reservation")
	var editor := EDITOR.new()
	editor.configure(state,_transform_catalog(),"company-a")
	var before := state.to_dict()
	var cached_berths := state.derived_berths()
	var cached_edges := state.construction_edges()
	var cases := {
		"plant":[Vector3(30,0,8),Vector3(20,0,-8),Vector3(110,0,8),Vector3(20,0,8),Vector3(60,0,8)],
		"crane-1":[Vector3(-16,0,-8),Vector3(-20,0,5),Vector3(-110,0,-8),Vector3(-20,0,-8),Vector3(-60,0,-8)],
		"crane-2":[Vector3(24,0,-8),Vector3(20,0,8),Vector3(110,0,-8),Vector3(20,0,-8),Vector3(60,0,-8)],
		"pad-1":[Vector3(-16,0,5),Vector3(20,0,8),Vector3(-110,0,5),Vector3(-20,0,5),Vector3(-60,0,5)]}
	for id in cases:
		for at in cases[id]:
			var proposal := editor.preview_transform(id,at,0)
			var cold := STATE.from_dict(before,before.world,_transform_catalog())
			var payload := {"placement_id":id,"expected_placement":proposal.expected_placement,
				"position_m":proposal.placement.position_m,"yaw_degrees":proposal.placement.yaw_degrees}
			var committed := _command(cold,"transform_asset",payload)
			check(proposal.ok == committed.ok,"Preview equals cold full command: %s %s at %s (%s)" % [phase,id,at,committed.code])
	if phase == "reserved":
		for id in ["crane-1","crane-2","pad-1"]:
			var row := _row(before.placements,id)
			var preflight := state.preflight_nonstructural_transform(_transform_payload(state,id,CustomPortCatalog.vector3(row.position_m)+Vector3.RIGHT*4),"company-a")
			check(preflight.supported and not preflight.command_allowed and preflight.code == ("store_reserved" if id=="pad-1" else "placement_reserved"),
				"The original command protects both cross-linked cranes and their separate reserved yard: "+id)
	var valid := editor.preview_transform("plant",Vector3(30,0,8),90)
	check(valid.ok,"Unreserved stocked plant may still move during "+phase)
	valid.placement.position_m = [20,0,-8]
	var forged := editor.transform(valid)
	check(not forged.ok and forged.code == "invalid_result", "Forging a green equipment ghost cannot bypass full final overlap validation")
	check(state.to_dict() == before and state.derived_berths() == cached_berths and state.construction_edges() == cached_edges,
		"All previews/rejections preserve stock, receipts, reservations, occupied geometry and projection caches: "+phase)

func _test_preflight_contract() -> void:
	var state := _transform_state()
	var before := state.to_dict()
	var payload := _transform_payload(state,"plant",Vector3(300,0,8))
	var original_payload := payload.duplicate(true)
	var preflight := state.preflight_nonstructural_transform(payload,"company-a")
	check(preflight.supported and preflight.command_allowed and not preflight.has("ok"), "Preflight deliberately exposes command_allowed, not a complete ok/placement decision")
	check(not state.preview_transform(payload,"company-a").ok and not _command(state,"transform_asset",payload).ok,
		"A successful command preflight still requires plot/geometry validation")
	check(payload == original_payload and state.to_dict() == before,"Preflight and rejected commands do not mutate input or authority")
	preflight = state.preflight_nonstructural_transform(_transform_payload(state,"plant",Vector3(30,0,8)),"company-b")
	check(preflight.supported and not preflight.command_allowed and preflight.code == "not_port_owner", "Shared preflight rejects a foreign actor")
	var stale := _transform_payload(state,"plant",Vector3(30,0,8))
	stale.expected_placement.attributes.maintenance.inspection = "stale"
	preflight = state.preflight_nonstructural_transform(stale,"company-a")
	check(preflight.supported and not preflight.command_allowed and preflight.code == "placement_changed", "Shared preflight rejects stale source metadata")
	var malformed := _transform_payload(state,"plant",Vector3(30,0,8))
	malformed.injected_stock = 999
	preflight = state.preflight_nonstructural_transform(malformed,"company-a")
	check(preflight.supported and not preflight.command_allowed and preflight.code == "invalid_transform", "Shared command rejects extra transform payload fields")
	check(state.to_dict() == before,"Rejected preflight leaves the full source record unchanged")

func _test_structural_fallback() -> void:
	var state := _transform_state()
	for id in ["quay-1","bollard-a"]:
		var preflight := state.preflight_nonstructural_transform(_transform_payload(state,id,Vector3(10,0,0)),"company-a")
		check(not preflight.supported and not preflight.command_allowed,"Structural piece requires the complete path: "+id)
	for variant in ["unknown_kind","mooring","berth_edge"]:
		var catalog := _transform_catalog()
		if variant == "unknown_kind": catalog.plant.kind = "future_topology_asset"
		else: catalog.plant[variant] = true
		var input := _transform_fixture()
		var future := STATE.from_dict(input,input.world,catalog)
		check(future.validation_errors.is_empty(),"Fallback fixture retains valid source data: "+variant)
		var payload := _transform_payload(future,"plant",Vector3(30,0,8))
		check(not future.preflight_nonstructural_transform(payload,"company-a").supported,"Unknown/explicit topology cannot enter command-only preflight: "+variant)
		var editor := EDITOR.new()
		editor.configure(future,catalog,"company-a")
		var original := _row(future.to_dict().placements,"plant")
		check(not editor._can_preview_transform_locally(original,CustomPortPlacementRules.definition(original,catalog)),"Unknown/explicit topology cannot enter the ordinary prop shortcut: "+variant)
		var proposal := editor.preview_transform("plant",Vector3(30,0,8))
		var full := future.preview_transform(payload,"company-a")
		check(proposal.ok == full.ok,"Fallback uses complete candidate semantics: "+variant)
