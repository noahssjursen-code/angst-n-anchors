extends Node

class GuardedHarbour extends HarbourMasterNpc:
	var spawned: Array[Dictionary] = []
	func _ready() -> void: pass
	func _spawn_chosen_ship(record: Dictionary, _berth: String) -> void:
		spawned.append(record.duplicate(true))

var failed := false

func check(ok: bool, message: String) -> void:
	if not ok:
		failed = true
		push_error(message)

func _ready() -> void:
	assert(ShipyardPlaytestMode.active())
	var builds: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://resources/data/showcases/authority_builds.json"))
	var build: Dictionary = builds["28_10_m"]
	var record := {"uid": "stable-local", "server_vessel_id": "durable-server", "hull_id": build.layout.hull,
		"brick_layout": build.layout, "construction_id": build.id, "catalog_hash": build.catalog_hash,
		"layout_hash": "accepted-version", "name": "Accepted"}
	var restored: Dictionary = JSON.parse_string(JSON.stringify(PlayerData.ledger_vessel_record(record)))
	check(restored.construction_id == build.id and restored.catalog_hash == build.catalog_hash, "Ledger serialization preserves complete accepted construction identity")
	var boat := BoatBody.new()
	VesselSpawn.apply_identity(boat, restored)
	check(boat.get_meta("construction_id") == build.id and boat.get_meta("server_vessel_id") == "durable-server", "Spawned node keeps version paired with durable vessel identity")
	boat.free()
	var harbour := GuardedHarbour.new()
	var result := {"ok": true, "data": {"assignment": {"berth_id": "berth-a"}}}
	var context := {"record": restored, "old_record": {}, "vessel_id": "durable-server", "generation": 0, "session_token": WorldGateway.session_token()}
	var old_session := context.duplicate(true)
	old_session.session_token = "previous-session"
	harbour._pending_berth_claims["previous-session"] = old_session
	harbour._on_world_command_completed("previous-session", result)
	check(harbour.spawned.is_empty(), "A late berth reply from the previous session cannot spawn a ship")
	harbour._deployment_fetch_generation = 1
	harbour._pending_berth_claims["cancelled"] = context.duplicate(true)
	harbour._on_world_command_completed("cancelled", result)
	check(harbour.spawned.is_empty(), "A cancelled deployment cannot spawn from a late accepted claim")
	context.generation = 1
	harbour._pending_berth_claims["current"] = context
	harbour._on_world_command_completed("current", result)
	harbour._on_world_command_completed("current", result)
	check(harbour.spawned.size() == 1 and harbour.spawned[0].construction_id == build.id, "Current accepted claim deploys exact build once despite duplicate delivery")
	var storage_ship := BoatBody.new()
	var notifications: Array = []
	harbour.deployment_finished.connect(func(ok: bool, message: String): notifications.append([ok,message]))
	harbour._pending_storage["stale-store"] = {"ship":weakref(storage_ship),"session":"previous-session"}
	harbour._on_world_command_completed("stale-store", {"ok":true})
	check(notifications.is_empty(), "Old-session storage reply is ignored")
	harbour._pending_storage["denied-store"] = {"ship":weakref(storage_ship),"session":WorldGateway.session_token()}
	harbour._on_world_command_completed("denied-store", {"ok":false,"message":"Transfer running"})
	check(is_instance_valid(storage_ship) and notifications.size()==1 and not notifications[0][0], "Rejected storage preserves vessel and reports rejection")
	storage_ship.free()
	harbour.free()
	if not failed: print("HARBOUR BLUEPRINT DEPLOYMENT PASS: durable identity, session change, cancellation and duplicate claim guards")
	get_tree().quit(1 if failed else 0)
