extends Node

const Gateway = preload("res://scripts/network/world_gateway.gd")
const Binding = preload("res://scripts/network/world_record_binding.gd")
class FakeTransport extends RemoteWorldBackend:
	var resync_requested := false
	func _poll_events_deferred(_value: int) -> void: pass
	func _sync_interests() -> void: pass
	func query_projections(_kind: String = "", _id: String = "") -> void: pass
	func query_state() -> void: resync_requested = true
	func _request_detached_session_close(_token: String) -> void: pass

var failed := false
func check(ok: bool, message: String) -> void:
	if not ok:
		failed = true
		push_error(message)

func _ready() -> void:
	assert(ShipyardPlaytestMode.active())
	var gateway := Gateway.new()
	add_child(gateway)
	var backend := FakeTransport.new()
	gateway.use_backend(backend, true)
	backend.adopt_session({"contract_version": 1, "session_token": "test-only", "actor_id": "test", "event_cursor": 0})
	var binding := Binding.new()
	add_child(binding)
	var updates: Array = []
	binding.updated.connect(func(state: Dictionary, revision: int):
		updates.append([state, revision])
		check(not gateway.projection("cargo", "cargo-a").is_empty(), "Observer sees cargo and ship together"))
	var removals: Array = []
	binding.removed.connect(func(): removals.append(true))
	binding.bind_record("vessel", "ship-a", "entity:ship-a", gateway)
	var cargo := {"kind": "cargo", "id": "cargo-a", "revision": 1, "state": {"location": "ship-a"}}
	var ship := {"kind": "vessel", "id": "ship-a", "revision": 1, "state": {"cargo": ["cargo-a"]}}
	backend._on_event_page({"transport_ok": true, "payload": {"next_cursor": 1, "events": [{"cursor": 1, "commit_cursor": 2, "type": "cargo.loaded", "projection": cargo}]}}, backend._generation, backend._interest_epoch)
	check(gateway.projections().is_empty(), "Incomplete transaction stays invisible across event pages")
	backend._on_event_page({"transport_ok": true, "payload": {"next_cursor": 2, "events": [{"cursor": 2, "commit_cursor": 2, "type": "vessel.changed", "projection": ship}]}}, backend._generation, backend._interest_epoch)
	check(updates.size() == 1, "Generic binding receives the complete ship update")
	gateway._on_projections_received([ship])
	check(updates.size() == 1, "Duplicate revision does not notify twice")
	backend._on_event_page({"transport_ok": true, "payload": {"resync_required": true, "events": [], "next_cursor": 2}}, backend._generation, backend._interest_epoch)
	check(backend.resync_requested, "Expired cursor triggers snapshot recovery")
	gateway._on_state_snapshot({"projections": []})
	check(removals.size() == 1 and gateway.projections().is_empty(), "Resync removes inaccessible/stale records")
	binding.queue_free()
	gateway.stop_session()
	gateway.queue_free()
	if not failed: print("AUTHORITY BINDING PASS: atomic paged events, generic record subscriptions, duplicate suppression, cursor recovery, snapshot removal")
	get_tree().quit(1 if failed else 0)
