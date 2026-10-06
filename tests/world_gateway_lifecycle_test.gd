extends Node3D

# Use a real harbour/master/deploy stack without generating an entire coast.
class TestPortPlot extends PortPlot:
	func _ready() -> void:
		pass

class EventSink extends Node:
	var events: Array[Dictionary] = []

	func receive(event: Dictionary) -> void:
		events.append(event)

var failed := false
var results: Dictionary = {}


func check(ok: bool, message: String) -> void:
	if not ok:
		failed = true
		push_error(message)


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	assert(ShipyardPlaytestMode.active(), "Run isolated from captain saves")
	# The isolation flag suppresses normal sessions. Wire a real local authority
	# in this test process only, using the same signals as begin_session().
	var backend := LocalWorldBackend.new()
	WorldGateway.add_child(backend)
	WorldGateway._backend = backend
	backend.session_started.connect(WorldGateway._on_session_started)
	backend.session_ended.connect(WorldGateway._on_session_ended)
	backend.event_received.connect(WorldGateway._on_world_event)
	backend.command_finished.connect(WorldGateway._on_command_finished)
	backend.projections_received.connect(WorldGateway._on_projections_received)
	WorldGateway.command_completed.connect(func(id: String, result: Dictionary) -> void:
		results[id] = result)
	backend.start_session("lifecycle-test", "Lifecycle Test", "")

	_test_freed_listener_berth_claim()
	_test_unsubscribe_with_freed_listener()
	_test_changes_during_dispatch()
	await _test_harbour_unload()
	await _test_harbourmaster_deployment()
	WorldGateway.stop_session()
	await get_tree().process_frame
	if not failed:
		print("WORLD GATEWAY LIFECYCLE PASS: berth claims, freed listeners, unsubscribe, dispatch mutations, harbour unload, harbourmaster spawn/replacement")
	get_tree().quit(1 if failed else 0)


func _test_freed_listener_berth_claim() -> void:
	var live := EventSink.new()
	var wildcard := EventSink.new()
	var dead_owner := Node.new()
	var dead_callback := EventSink.new()
	# The callback can outlive its owner, or the owner can outlive its callback.
	WorldGateway.subscribe(WorldContracts.EVENT_VESSEL_BERTH_ASSIGNED, dead_owner, live.receive)
	WorldGateway.subscribe(WorldContracts.EVENT_VESSEL_BERTH_ASSIGNED, live, dead_callback.receive)
	WorldGateway.subscribe(WorldContracts.EVENT_VESSEL_BERTH_ASSIGNED, live, live.receive)
	WorldGateway.subscribe(WorldContracts.EVENT_VESSEL_BERTH_ASSIGNED, live, live.receive)
	WorldGateway.subscribe("*", dead_owner, wildcard.receive)
	WorldGateway.subscribe("*", wildcard, wildcard.receive)
	dead_owner.free()
	dead_callback.free()
	WorldGateway.send_command(
		WorldContracts.COMMAND_VESSEL_BERTH_CLAIM,
		WorldContracts.vessel_berth_claim_body("test-ship", "test-port", ["test-port/quay"]),
		"test-claim",
	)
	check(bool(results.get("test-claim", {}).get("ok", false)), "Berth claim must complete")
	check(live.events.size() == 1, "Live berth listener receives the event exactly once after dead listeners")
	check(wildcard.events.size() == 1, "Wildcard dispatch must also survive freed owners")
	check(WorldGateway.projection("vessel_berth", "test-ship").state.berth_id == "test-port/quay", "Berth projection retained")
	check((WorldGateway._subscriptions.get(WorldContracts.EVENT_VESSEL_BERTH_ASSIGNED, []) as Array).size() == 1,
		"Dead owners and callbacks must be pruned")
	WorldGateway.unsubscribe_owner(live)
	WorldGateway.unsubscribe_owner(wildcard)
	live.free()
	wildcard.free()


func _test_unsubscribe_with_freed_listener() -> void:
	var stale := Node.new()
	var live := EventSink.new()
	WorldGateway.subscribe("test.unsubscribe", stale, live.receive)
	WorldGateway.subscribe("test.unsubscribe", live, live.receive)
	WorldGateway.retain_interest("port:test-unsubscribe", live)
	stale.free()
	WorldGateway.unsubscribe_owner(live)
	check(not WorldGateway._subscriptions.has("test.unsubscribe"), "Unsubscribe must prune freed entries without casting them")
	check(not WorldGateway.active_interests().has("port:test-unsubscribe"), "Unsubscribe releases owner interests")
	live.free()


func _test_changes_during_dispatch() -> void:
	var first := Node.new()
	var freed_during_dispatch := Node.new()
	var freed_during_dispatch_id := freed_during_dispatch.get_instance_id()
	var removed := EventSink.new()
	var survivor := EventSink.new()
	var added := EventSink.new()
	var changed := [false]
	WorldGateway.subscribe("test.mutation", first, func(_event: Dictionary) -> void:
		if changed[0]:
			return
		changed[0] = true
		instance_from_id(freed_during_dispatch_id).free()
		WorldGateway.unsubscribe_owner(removed)
		WorldGateway.subscribe("test.mutation", added, added.receive))
	WorldGateway.subscribe("test.mutation", freed_during_dispatch, survivor.receive)
	WorldGateway.subscribe("test.mutation", removed, removed.receive)
	WorldGateway.subscribe("test.mutation", survivor, survivor.receive)
	WorldGateway._on_world_event({"type": "test.mutation"})
	check(removed.events.is_empty(), "Unsubscribing during dispatch takes effect immediately")
	check(survivor.events.size() == 1, "Freeing the next owner must not interrupt live listeners")
	check(added.events.is_empty(), "New subscriptions start on the next event")
	WorldGateway._on_world_event({"type": "test.mutation"})
	check(added.events.size() == 1 and survivor.events.size() == 2, "Callback changes survive into the next dispatch")
	for owner in [first, removed, survivor, added]:
		WorldGateway.unsubscribe_owner(owner)
		owner.free()


func _test_harbour_unload() -> void:
	for cycle in range(3):
		var harbour := HarbourController.new()
		harbour.setup("unload-test")
		add_child(harbour)
		harbour.activate()
		check(WorldGateway.active_interests().has("port:unload-test"), "Loaded harbour retains its authority interest")
		harbour.queue_free()
		await get_tree().process_frame
		check(not WorldGateway.active_interests().has("port:unload-test"), "Unloading harbour releases its interest")
		check(WorldGateway._subscriptions.is_empty(), "Unloading harbour removes all six event subscriptions")
		check(HarbourRegistry.controller("unload-test") == null, "Unloaded harbour leaves registry")
	# Same command emitted by HarbourMasterNpc after harbour streaming churn.
	WorldGateway.send_command(
		WorldContracts.COMMAND_VESSEL_BERTH_CLAIM,
		WorldContracts.vessel_berth_claim_body("after-unload", "unload-test", ["unload-test/quay"]),
		"claim-after-unload",
	)
	check(bool(results.get("claim-after-unload", {}).get("ok", false)), "Deploy berth command succeeds after unloads")


func _test_harbourmaster_deployment() -> void:
	var plot := TestPortPlot.new()
	plot.port_id = "master-deploy-test"
	add_child(plot)
	var harbour := HarbourController.new()
	harbour.setup(plot.port_id)
	plot.add_child(harbour)
	var berth := QuayBerthSlot.new()
	berth.setup("master-deploy-test/quay", "quay", "general", [], 100.0, 20.0)
	plot.add_child(berth)
	for along in [-12.0, 12.0]:
		var bollard := MooringPost.new()
		bollard.position = Vector3(along, 2.0, 10.0)
		plot.add_child(bollard)
		berth.add_bollard(bollard)
	harbour.register_berth(berth)
	harbour.activate()
	var master := HarbourMasterNpc.new()
	master.port_id = plot.port_id
	plot.add_child(master)
	await get_tree().process_frame
	await get_tree().process_frame
	for starter_id in ["fishing", "general_cargo"]:
		var record := CompanyService.build_starter_vessel_record(starter_id)
		master._deploy_fleet_vessel(record)
		var ship := PlayerVessel.find_active_ship(get_tree())
		check(ship != null, "Harbourmaster must spawn " + starter_id)
		if ship == null:
			continue
		ship.freeze = true
		check(str(ship.get_meta("vessel_uid", "")) == str(record.uid), "Deployed vessel matches requested owned record")
		check(harbour.moored_ship(berth.berth_id) == ship, "Spawned vessel occupies assigned quay")
		check(get_tree().get_nodes_in_group(PlayerVessel.GROUP).size() == 1, "Replacement must leave only one player vessel")
		check(master._pending_berth_claims.is_empty(), "Harbourmaster consumes claim completion")
		await get_tree().process_frame
		var mooring := ship.find_child("MooringComponent", true, false) as MooringComponent
		check(mooring != null and mooring.bow_line_tied and mooring.stern_line_tied, "Deployed ship ties both lines")
	PlayerVessel.despawn_all_ships(get_tree())
	plot.queue_free()
	await get_tree().process_frame
	check(not WorldGateway.active_interests().has("port:master-deploy-test"), "Deployed harbour unload releases authority interest")
	check(WorldGateway._subscriptions.is_empty(), "Deployed harbour unload removes listeners")
