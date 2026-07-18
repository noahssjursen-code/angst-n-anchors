extends SceneTree

const DebugFleetScript := preload("res://scripts/traffic/debug_npc_fleet.gd")


func _init() -> void:
	var fleet := DebugFleetScript.new() as DebugNpcFleet
	root.add_child(fleet)
	var general := fleet.call("_prebuilt_record", "28_10_m", "test-general", 0) as Dictionary
	var bulk := fleet.call("_prebuilt_record", "bulk_small", "test-bulk", 1) as Dictionary
	_assert(not general.is_empty(), "general-cargo prebuilt is available")
	_assert(not bulk.is_empty(), "bulk prebuilt is available")
	_assert(str(general.get("registration_id", "")) == "cargo_vessel",
		"general ship retains cargo registration")
	_assert(str(bulk.get("registration_id", "")) == "bulk_vessel",
		"bulk ship retains bulk registration")
	_assert(not VesselSpawn.resolve_deployable_record(general).is_empty(),
		"general traffic vessel is deployable")
	_assert(not VesselSpawn.resolve_deployable_record(bulk).is_empty(),
		"bulk traffic vessel is deployable")
	var candidates: Array[Dictionary] = [
		{"id": "g1", "handling_mode": "general"},
		{"id": "g2", "handling_mode": "general"},
		{"id": "b1", "handling_mode": "bulk"},
		{"id": "b2", "handling_mode": "bulk"},
	]
	var mixed := fleet.call("_select_mixed_contracts", candidates, 5) as Array[Dictionary]
	var bulk_count := 0
	for row in mixed:
		if str(row.get("handling_mode", "")) == "bulk":
			bulk_count += 1
	_assert(mixed.size() == 5 and bulk_count == 2,
		"five-vessel debug traffic includes three general and two bulk ships")
	var contract := {
		"id": "test-route", "handling_mode": "general", "commodity_id": "provisions",
		"origin_port_id": "port-a", "origin_berth_id": "berth-a",
		"destination_port_id": "port-b", "destination_berth_id": "berth-b",
	}
	var manifest := fleet.call("_cargo_manifest", contract, "test-general") as Dictionary
	var manifest_contract := manifest.get("contract", {}) as Dictionary
	_assert(str(manifest_contract.get("vessel_uid", "")) == "test-general",
		"ambient cargo contract is authority-bound to its real vessel")
	_assert(int(manifest_contract.get("loaded_quantity", 0)) == 6,
		"join snapshot carries authoritative loaded cargo accounting")
	for raw in manifest.get("units", []) as Array:
		var unit := ContainerUnit.from_dict(raw as Dictionary)
		_assert(unit.commodity_id == "provisions" and not unit.consignment_id.is_empty(),
			"ambient cargo units carry the same commodity and consignment authority as owned cargo")
	print("Debug NPC fleet tests: all checks passed")
	quit()


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("FAILED: %s" % message)
	quit(1)
