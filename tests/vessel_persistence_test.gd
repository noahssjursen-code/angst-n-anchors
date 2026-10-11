extends Node

var _failures := PackedStringArray()


func _ready() -> void:
	var source := PlayerData.new()
	var expected: Dictionary = {}
	var index := 0
	for hull in HullRegistry.catalog():
		var hull_id := str(hull.get("id", ""))
		var cells: Dictionary = {}
		cells["%d,0,1" % index] = {
			"brick_id": "block",
			"yaw": index * 90,
			"sign_id": "wall_text",
			"sign_yaw": 180,
			"text": "Saved %s" % hull_id,
			"light_id": "light_work_flood",
			"light_yaw": 45,
		}
		cells["%d,1,1" % index] = {
			"brick_id": "bench",
			"yaw": 90,
		}
		var layout := {
			"hull_id": hull_id,
			"cells": cells,
			"container_pads": [{"a": [index, 0, 2], "b": [index + 3, 0, 5]}],
		}
		var uid := "persistence_%s" % hull_id
		var record := {
			"uid": uid,
			"hull_id": hull_id,
			"name": "Configured %s" % hull_id,
			"display": str(hull.get("display", hull_id)),
			"shaft_power_kw": 1000.0 + index * 500.0,
			"scene_path": str(hull.get("scene_path", "")),
			"brick_layout": layout,
		}
		source.upsert_owned_vessel(record)
		expected[uid] = layout
		index += 1
	source.set_active_vessel(source.find_owned_vessel("persistence_hull_45x16_cat"))
	source.ship_runtime_state = {
		"world_pos": Vector3(10.0, -0.4, 30.0),
		"yaw": 0.4,
		"throttle_stage_idx": 1,
		"fuel_fraction": 0.62,
		"aboard": true,
		"helming": false,
	}
	source.port_operations_state = {
		"active_call": {
			"id": "port-home:call:test",
			"port_id": "port-home",
			"owner_id": "Captain",
		},
		"assigned_cranes": ["port-home:crane:gantry_01"],
		"yard_cargo": [],
	}

	# This is the actual inter-instance boundary: Variant data -> JSON text ->
	# fresh PlayerData. Every current hull goes through the exact same path.
	var json := JSON.stringify({"version": PlayerSaveStore.SAVE_VERSION, "player": source.to_dict()})
	var parsed: Variant = JSON.parse_string(json)
	_check(typeof(parsed) == TYPE_DICTIONARY, "player envelope parses after JSON write")
	var player_raw: Variant = (parsed as Dictionary).get("player", {}) if typeof(parsed) == TYPE_DICTIONARY else {}
	var restored := PlayerData.from_dict(player_raw as Dictionary)
	_check(restored.owned_vessels.size() == HullRegistry.catalog().size(), "all configured hulls survive reload")
	for uid in expected:
		var restored_record := restored.find_owned_vessel(str(uid))
		_check(not restored_record.is_empty(), "%s survives reload" % uid)
		_check(
			PlayerData.json_equivalent(VesselSpawn.brick_layout_of(restored_record), expected[uid]),
			"%s brick layout survives reload exactly" % uid,
		)
		_check(float(restored_record.get("shaft_power_kw", 0.0)) > 0.0, "%s power survives reload" % uid)
	_check(
		str(restored.active_vessel.get("uid", "")) == "persistence_hull_45x16_cat",
		"active configured vessel survives reload",
	)
	_check(restored.ship_runtime_state.is_empty(), "legacy resume-in-vessel state is discarded")
	# port_operations_state may round-trip in JSON but is unused after the port purge.
	_check(
		typeof(restored.port_operations_state) == TYPE_DICTIONARY,
		"port_operations_state remains a dictionary field",
	)

	# A stale multiplayer pull may fill a bare local record, but must never
	# overwrite an already configured local deck.
	var configured := source.find_owned_vessel("persistence_hull_28x10")
	var stale_server := {
		"layout_hash": "stale",
		"brick_layout": {"hull_id": "fishing_trawler_small", "cells": {}},
	}
	var protected_patch := VesselSync._layout_patch_from_row(stale_server, configured)
	_check(not protected_patch.has("brick_layout"), "stale server layout cannot erase local fit-out")
	var hydrate_patch := VesselSync._layout_patch_from_row(stale_server, {
		"hull_id": "fishing_trawler_small",
		"brick_layout": {"hull_id": "fishing_trawler_small", "cells": {}},
	})
	_check(hydrate_patch.has("brick_layout"), "server can hydrate a bare local vessel")
	var server_linked := configured.duplicate(true)
	server_linked["server_vessel_id"] = "server-linked-test"
	var preserved_server_rows := VesselSync._collect_preserved_local_vessels([server_linked])
	_check(
		preserved_server_rows.size() == 1,
		"pull omission cannot delete a server-linked local vessel",
	)

	var uid_a := VesselSpawn.new_vessel_uid("fishing_trawler_small")
	var uid_b := VesselSpawn.new_vessel_uid("fishing_trawler_small")
	_check(uid_a != uid_b, "commissioned vessel UIDs do not collide")

	var collision_layout_a := {"hull_id": "fishing_trawler_small", "cells": {"1,0,1": {"brick_id": "block", "yaw": 0}}}
	var collision_layout_b := {"hull_id": "fishing_trawler_small", "cells": {"2,0,2": {"brick_id": "bench", "yaw": 90}}}
	var repaired_collision := PlayerData.from_dict({
		"owned_vessels": [
			{"uid": "old_second_uid", "hull_id": "fishing_trawler_small", "server_vessel_id": "server-a", "brick_layout": collision_layout_a},
			{"uid": "old_second_uid", "hull_id": "fishing_trawler_small", "server_vessel_id": "server-b", "brick_layout": collision_layout_b},
		],
		"active_vessel": {
			"uid": "old_second_uid",
			"hull_id": "fishing_trawler_small",
			"server_vessel_id": "server-b",
			"brick_layout": collision_layout_b,
		},
	})
	_check(repaired_collision.owned_vessels.size() == 2, "legacy UID collision keeps both vessels")
	_check(
		str(repaired_collision.active_vessel.get("server_vessel_id", "")) == "server-b",
		"legacy UID collision restores the correct active vessel",
	)
	_check(
		PlayerData.json_equivalent(
			VesselSpawn.brick_layout_of(repaired_collision.active_vessel),
			collision_layout_b,
		),
		"legacy UID collision preserves the active vessel layout",
	)

	var uuid_a := PlayerData.new_uuid()
	var uuid_b := PlayerData.new_uuid()
	_check(uuid_a != uuid_b, "new captains always receive distinct UUIDs")
	_check(
		uuid_a.length() == 36 and uuid_a.substr(14, 1) == "4",
		"local captain identity is RFC 4122 UUIDv4",
	)

	var prebuilts := PrebuiltVesselCatalog.catalog_entries()
	var found_prebuilt := false
	for prebuilt in prebuilts:
		if str(prebuilt.get("prebuilt_id", "")) == "fishing_trawler":
			found_prebuilt = true
			_check(
				(VesselSpawn.brick_layout_of({
					"hull_id": prebuilt.get("hull_id", ""),
					"brick_layout": prebuilt.get("prebuilt_layout", {}),
				}).get("parts", []) as Array).size() > 0,
				"ready-built catalog loads the exported deck layout",
			)
			_check(
				str(prebuilt.get("registration_id", "")) == "",
				"imported starters do not need legal registration",
			)
			var catalog_record := VesselSpawn.normalize_record({
				"uid": "catalog_persistence_test",
				"hull_id": str(prebuilt.get("hull_id", "")),
				"scene_path": "",
				"registration_id": prebuilt.get("registration_id", ""),
				"brick_layout": prebuilt.get("prebuilt_layout", {}),
			})
			_check(
				not VesselSpawn.resolve_deployable_record(catalog_record).is_empty(),
				"catalog prebuilt remains deployable after persistence normalization",
			)
	_check(found_prebuilt, "exported official prebuilt appears in shipwright catalog")

	var archive_owner := PlayerData.new_uuid()
	var archive_uid := "archive_roundtrip_test"
	var archive_record := {
		"uid": archive_uid,
		"hull_id": "passenger_catamaran",
		"name": "Archive Test",
		"scene_path": HullRegistry.scene_path_for("passenger_catamaran"),
		"brick_layout": {
			"hull_id": "passenger_catamaran",
			"cells": {"3,0,4": {"brick_id": "table", "yaw": 90}},
			"container_pads": [],
		},
	}
	_check(VesselArchive.save_record(archive_owner, archive_record), "per-vessel archive writes atomically")
	var archive_records := VesselArchive.load_records(archive_owner)
	_check(archive_records.size() == 1, "per-vessel archive reloads by captain UUID")
	if archive_records.size() == 1:
		_check(
			PlayerData.json_equivalent(
				VesselSpawn.brick_layout_of(archive_records[0] as Dictionary),
				VesselSpawn.brick_layout_of(archive_record),
			),
			"per-vessel archive preserves full layout",
		)
	DirAccess.remove_absolute(VesselArchive.archive_path_for_uid(archive_uid))
	_finish()


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)


func _finish() -> void:
	if _failures.is_empty():
		print("Vessel persistence tests: all checks passed")
		get_tree().quit()
		return
	for failure in _failures:
		push_error("Vessel persistence test: " + failure)
	get_tree().quit(1)
