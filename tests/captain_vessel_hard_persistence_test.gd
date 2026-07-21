extends Node

const SESSION_SCRIPT := preload("res://scripts/player/player_session.gd")
const TEST_ROOT := "user://automated_tests/captain_vessel_hard"

var _failures := PackedStringArray()


func _ready() -> void:
	call_deferred("_run_hard_test")


func _run_hard_test() -> void:
	LocalCaptainStore.root_override = TEST_ROOT
	_check(PlayerSaveStore.wipe_all_local_data(), "pre-test wipe succeeds")

	# Create captain A and populate every PlayerData persistence category.
	var first := _new_session()
	first.begin_new_captain("Same Captain Name", CharacterAppearance.default_appearance())
	var captain_a := str(first.data.account_id)
	_check(not captain_a.is_empty(), "captain A receives UUID")
	_check(LocalCaptainStore.create_slot(captain_a), "captain A save slot is activated")
	_check(first.save_now(), "captain A onboarding save succeeds")

	# Commission a boat, then refit the same UUID twice.
	var vessel_uid := VesselSpawn.new_vessel_uid("hull_28x10")
	var layout_v1: Dictionary = {}
	for entry in PrebuiltVesselCatalog.catalog_entries():
		if str(entry.get("prebuilt_id", "")) == "fishing_trawler":
			layout_v1 = (entry.get("prebuilt_layout", {}) as Dictionary).duplicate(true)
			break
	_check(not layout_v1.is_empty(), "certified fixture layout is available")
	var vessel := _vessel_record(vessel_uid, layout_v1)
	_check(first.persist_vessel_configuration(vessel, true), "commission save succeeds")
	var layout_v2 := layout_v1.duplicate(true)
	(layout_v2["cells"] as Dictionary)["0,6,20"] = {
		"brick_id": "table",
		"yaw": 180,
		"text": "HARD SAVE",
		"light_id": "light_work_flood",
	}
	(layout_v2["cells"] as Dictionary)["1,6,20"] = {
		"brick_id": "window",
		"yaw": 270,
	}
	vessel["brick_layout"] = layout_v2
	_check(first.persist_vessel_configuration(vessel, true), "refit save succeeds")

	# Populate every remaining PlayerData persistence category after gameplay
	# snapshots, then flush the data model directly.
	var balance_delta: int = 4321 - int(first.get_marks())
	if balance_delta > 0:
		first.earn_marks(balance_delta)
	elif balance_delta < 0:
		_check(first.spend_marks(-balance_delta), "ledger balance adjustment succeeds")
	first.data.total_marks_earned = 9876
	first.data.contracts_completed = 7
	first.data.distance_sailed_m = 12345.5
	first.data.accepted_contracts = [{
		"id": "hard-contract",
		"taken_count": 4,
		"delivered_count": 3,
	}]
	first.data.ship_runtime_state = {
		"world_pos": [120.5, 2.25, -340.75],
		"yaw": 1.234,
		"throttle_stage_idx": 3,
		"fuel_fraction": 0.61,
	}
	first.data.world_clock_hours = 246.75
	first.data.world_context = {
		"seed": 8675309,
		"generation_version": 4,
		"layout_checksum": "hard-test-layout",
	}
	first.data.tutorial_seen = {"movement": true, "shipwright": true}
	first.data.starter_trawler_claimed = true
	_check(first._flush_save(), "full player save succeeds")
	# A second flush makes the latest complete snapshot the backup as well.
	_check(first._flush_save(), "latest snapshot rotates into backup")
	var expected_full: Dictionary = first.data.to_dict()
	_free_session(first)

	# Disconnect/reconnect: construct a completely fresh PlayerSession from disk.
	var reconnected := _new_session()
	_check(LocalCaptainStore.activate(captain_a), "captain A save slot reactivates")
	reconnected._load_from_disk()
	_check(str(reconnected.data.account_id) == captain_a, "captain UUID survives reconnect")
	_check(
		PlayerData.json_equivalent(reconnected.data.to_dict(), expected_full),
		"all PlayerData fields survive process boundary",
	)
	var restored_vessel: Dictionary = reconnected.data.find_owned_vessel(vessel_uid)
	_check(not restored_vessel.is_empty(), "commissioned vessel survives reconnect")
	_check(
		PlayerData.json_equivalent(VesselSpawn.brick_layout_of(restored_vessel), layout_v2),
		"edited cells and cargo zones survive reconnect exactly",
	)
	_check(
		FileAccess.file_exists(VesselArchive.archive_path_for_uid(vessel_uid)),
		"independent vessel UUID archive exists",
	)

	# Simulate a reconnect pull that omits the vessel. A pull is not deletion.
	var server_config := reconnected.get_node_or_null("/root/ServerConfig")
	var previous_mp := bool(server_config.get("is_multiplayer_mode")) if server_config != null else false
	for i in range(reconnected.data.owned_vessels.size()):
		var row := reconnected.data.owned_vessels[i] as Dictionary
		if str(row.get("server_vessel_id", "")).is_empty():
			row["server_vessel_id"] = "hard-preserved-%d" % i
			reconnected.data.owned_vessels[i] = row
	if server_config != null:
		server_config.set("is_multiplayer_mode", true)
	VesselSync._apply_server_vessels(reconnected, [])
	if server_config != null:
		server_config.set("is_multiplayer_mode", previous_mp)
	restored_vessel = reconnected.data.find_owned_vessel(vessel_uid)
	_check(not restored_vessel.is_empty(), "omitted server row cannot delete local vessel")
	_check(
		PlayerData.json_equivalent(VesselSpawn.brick_layout_of(restored_vessel), layout_v2),
		"omitted server row cannot erase layout",
	)

	# Simulate stale server JSON for the matching vessel.
	var stale := VesselSync._merge_server_row(reconnected.data, {
		"id": "hard-server-vessel",
		"hull_id": "passenger_catamaran",
		"display_name": "Stale Remote Name",
		"brick_layout": {"hull_id": "passenger_catamaran", "cells": {}},
		"layout_hash": "stale-empty",
	})
	_check(
		PlayerData.json_equivalent(VesselSpawn.brick_layout_of(stale), layout_v2),
		"stale server layout cannot overwrite configured local layout",
	)
	_free_session(reconnected)

	# Same display name must create an unrelated UUID and empty fleet namespace.
	LocalCaptainStore.clear_active()
	var second_captain := _new_session()
	second_captain.begin_new_captain("Same Captain Name", CharacterAppearance.default_appearance())
	var captain_b := str(second_captain.data.account_id)
	_check(LocalCaptainStore.create_slot(captain_b), "captain B save slot is activated")
	_check(second_captain.save_now(), "captain B onboarding save succeeds")
	_check(captain_b != captain_a, "same-name captain receives distinct UUID")
	_check(
		second_captain.data.find_owned_vessel(vessel_uid).is_empty(),
		"same-name captain cannot inherit captain A vessel",
	)
	var archive_leaked := false
	for row_raw in VesselArchive.load_records(captain_b):
		if typeof(row_raw) == TYPE_DICTIONARY \
				and str((row_raw as Dictionary).get("uid", "")) == vessel_uid:
			archive_leaked = true
	_check(
		not archive_leaked,
		"vessel archives are isolated by captain UUID",
	)
	_free_session(second_captain)

	_finish()


func _new_session() -> Node:
	var session := SESSION_SCRIPT.new()
	session.allow_test_persistent_io = true
	get_tree().root.add_child(session)
	return session


func _free_session(session: Node) -> void:
	if session == null:
		return
	get_tree().root.remove_child(session)
	session.free()


func _vessel_record(uid: String, layout: Dictionary) -> Dictionary:
	return {
		"uid": uid,
		"hull_id": "hull_28x10",
		"registration_id": "fishing_vessel",
		"name": "Hard-Test Trawler",
		"display": "Fishing Trawler",
		"scene_path": HullRegistry.scene_path_for("hull_28x10"),
		"server_vessel_id": "hard-server-vessel",
		"layout_hash": "local-hard-layout",
		"brick_layout": layout,
	}


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)


func _finish() -> void:
	var cleanup_ok := PlayerSaveStore.wipe_all_local_data()
	LocalCaptainStore.clear_active()
	LocalCaptainStore.root_override = ""
	if not cleanup_ok:
		_failures.append("post-test wipe succeeds")
	if _failures.is_empty():
		print("Captain/vessel HARD persistence test: all checks passed")
		get_tree().quit()
		return
	for failure in _failures:
		push_error("Captain/vessel HARD persistence test: " + failure)
	get_tree().quit(1)
