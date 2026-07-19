extends SceneTree

const TrafficScript := preload("res://scripts/traffic/maritime_traffic_service.gd")

var _failures := PackedStringArray()
var _publish_count := 0


func _initialize() -> void:
	var traffic := TrafficScript.new()
	root.add_child(traffic)
	_test_collision_agreement(traffic)
	_test_narrow_channel_signal_overrides_head_on_turn(traffic)
	_test_overtaking_agreement(traffic)
	_test_port_queue(traffic)
	_test_stale_port_ticket_recovery(traffic)
	_test_parallel_port_resources(traffic)
	_test_exclusive_block(traffic)
	_test_directional_convoy_block(traffic)
	_test_wide_bidirectional_block(traffic)
	_test_lane_window(traffic)
	_test_atomic_lane_window_rollback(traffic)
	_test_fifty_vessel_spatial_scan(traffic)
	_test_batched_fleet_publication(traffic)
	_test_snapshot_round_trip(traffic)
	traffic.queue_free()
	_finish()


func _test_collision_agreement(traffic: Node) -> void:
	traffic.publish_intent({
		"vessel_id": "northbound", "position_xz": [-100.0, 0.0],
		"velocity_xz": [5.0, 0.0], "heading_deg": 90.0, "length_m": 28.0,
	})
	traffic.publish_intent({
		"vessel_id": "southbound", "position_xz": [100.0, 0.0],
		"velocity_xz": [-5.0, 0.0], "heading_deg": 270.0, "length_m": 28.0,
	})
	traffic.call("_resolve_conflicts")
	var agreement: Dictionary = traffic.agreement_for("northbound")
	_check(not agreement.is_empty(), "head-on conflict creates an agreement")
	_check(str(agreement.get("situation", "")) == "head_on", "head-on situation is classified")
	var instruction := agreement.get("instruction", {}) as Dictionary
	_check(float(instruction.get("heading_offset_deg", 0.0)) > 0.0,
		"head-on vessel receives a starboard alteration")
	traffic.withdraw_vessel("northbound")
	traffic.withdraw_vessel("southbound")


func _test_overtaking_agreement(traffic: Node) -> void:
	traffic.publish_intent({
		"vessel_id": "leader", "position_xz": [60.0, 0.0],
		"velocity_xz": [3.0, 0.0], "heading_deg": 90.0, "length_m": 28.0,
	})
	traffic.publish_intent({
		"vessel_id": "follower", "position_xz": [0.0, 0.0],
		"velocity_xz": [6.0, 0.0], "heading_deg": 90.0, "length_m": 28.0,
	})
	traffic.call("_resolve_conflicts")
	var agreement: Dictionary = traffic.agreement_for("follower")
	_check(str(agreement.get("situation", "")) == "overtaking",
		"closing traffic in one lane is classified as overtaking")
	_check(str((agreement.get("instruction", {}) as Dictionary).get("action", "")) \
			== "reduce_for_overtaking",
		"astern overtaking vessel reduces speed without leaving its lane")
	traffic.withdraw_vessel("leader")
	traffic.withdraw_vessel("follower")


func _test_narrow_channel_signal_overrides_head_on_turn(traffic: Node) -> void:
	var spec: Array[Dictionary] = [{
		"block_id": "lane:narrow:test",
		"direction": 1,
		"capacity": 1,
		"bidirectional": false,
		"center_xz": [0.0, 0.0],
	}]
	traffic.request_lane_window("narrow-owner", spec)
	spec[0]["direction"] = -1
	traffic.request_lane_window("narrow-waiting", spec)
	traffic.publish_intent({
		"vessel_id": "narrow-owner", "position_xz": [-100.0, 0.0],
		"velocity_xz": [5.0, 0.0], "heading_deg": 90.0, "length_m": 28.0,
	})
	traffic.publish_intent({
		"vessel_id": "narrow-waiting", "position_xz": [100.0, 0.0],
		"velocity_xz": [-5.0, 0.0], "heading_deg": 270.0, "length_m": 28.0,
	})
	traffic.call("_resolve_conflicts")
	var owner_agreement: Dictionary = traffic.agreement_for("narrow-owner")
	var waiting_agreement: Dictionary = traffic.agreement_for("narrow-waiting")
	_check(str(owner_agreement.get("situation", "")) == "narrow_channel",
		"one-lane signal replaces generic head-on alteration")
	_check(float((owner_agreement.get("instruction", {}) as Dictionary).get(
		"heading_offset_deg", 99.0)) == 0.0,
		"cleared narrow-channel vessel remains on the safe centreline")
	_check(float((waiting_agreement.get("instruction", {}) as Dictionary).get(
		"speed_limit", 1.0)) == 0.0,
		"opposing vessel receives a full hold outside the narrow channel")
	traffic.withdraw_vessel("narrow-owner")
	traffic.withdraw_vessel("narrow-waiting")


func _test_port_queue(traffic: Node) -> void:
	traffic.register_holding_zones("port-a", [[10.0, 20.0], [30.0, 40.0]])
	traffic.request_port_arrival("port-a", "ordinary", "general_cargo", "", 200, 0)
	var priority: Dictionary = traffic.request_port_arrival(
		"port-a", "priority", "general_cargo", "", 210, 2)
	_check(bool(priority.get("cleared_for_approach", false)), "priority vessel heads the port queue")
	var ordinary: Dictionary = traffic.request_port_arrival(
		"port-a", "ordinary", "general_cargo", "", 200, 0)
	_check(int(ordinary.get("queue_position", 0)) == 2, "ordinary vessel holds behind priority traffic")
	_check((ordinary.get("holding_position_xz", []) as Array).size() == 2,
		"queued vessel receives a holding position")


func _test_stale_port_ticket_recovery(traffic: Node) -> void:
	traffic.request_port_arrival("stale-port", "gone", "general_cargo", "berth-a")
	traffic.request_port_arrival("stale-port", "waiting", "general_cargo", "berth-a")
	var queues := traffic.get("_port_queues") as Dictionary
	var queue := queues["stale-port"] as Array
	(queue[0] as Dictionary)["last_refresh_unix_msec"] = 1
	traffic.call("_cleanup_expired")
	var refreshed: Dictionary = traffic.request_port_arrival(
		"stale-port", "waiting", "general_cargo", "berth-a")
	_check(bool(refreshed.get("cleared_for_approach", false)),
		"stale disconnected vessel cannot permanently block a berth queue")


func _test_exclusive_block(traffic: Node) -> void:
	_check(traffic.request_block("narrow:bridge", "first", 1), "first vessel reserves a narrow block")
	_check(not traffic.request_block("narrow:bridge", "second", -1), "second vessel queues at occupied block")
	traffic.release_block("narrow:bridge", "first")
	var block: Dictionary = traffic.block_snapshot("narrow:bridge")
	_check(str(block.get("owner_vessel_id", "")) == "second", "block release promotes the queued vessel")


func _test_parallel_port_resources(traffic: Node) -> void:
	var first_a: Dictionary = traffic.request_port_arrival(
		"port-parallel", "a-1", "general_cargo", "berth-a", 100, 0)
	var second_a: Dictionary = traffic.request_port_arrival(
		"port-parallel", "a-2", "general_cargo", "berth-a", 101, 0)
	var first_b: Dictionary = traffic.request_port_arrival(
		"port-parallel", "b-1", "general_cargo", "berth-b", 102, 0)
	_check(bool(first_a.get("cleared_for_approach", false)),
		"first vessel for berth A is cleared")
	_check(not bool(second_a.get("cleared_for_approach", false)),
		"second vessel for berth A waits")
	_check(bool(first_b.get("cleared_for_approach", false)),
		"free berth B is not clogged by berth A queue")


func _test_directional_convoy_block(traffic: Node) -> void:
	var block_id := "fjord:convoy"
	_check(traffic.request_block(block_id, "east-1", 1, 0, 3),
		"first same-direction vessel enters capacity block")
	_check(traffic.request_block(block_id, "east-2", 1, 0, 3),
		"second same-direction vessel convoys through wide block")
	_check(not traffic.request_block(block_id, "west-1", -1, 0, 3),
		"opposing vessel waits for convoy")
	_check(not traffic.request_block(block_id, "east-3", 1, 0, 3),
		"new same-direction traffic cannot starve an opposing queue")
	traffic.release_block(block_id, "east-1")
	traffic.release_block(block_id, "east-2")
	var block: Dictionary = traffic.block_snapshot(block_id)
	_check((block.get("owner_vessel_ids", []) as Array).has("west-1"),
		"direction flips fairly after active convoy clears")


func _test_wide_bidirectional_block(traffic: Node) -> void:
	var block_id := "open-water:passing"
	_check(traffic.request_block(block_id, "north", 1, 0, 2, true),
		"first vessel enters a wide bidirectional block")
	_check(traffic.request_block(block_id, "south", -1, 0, 2, true),
		"opposing vessel can pass when the water block has safe capacity")
	_check(not traffic.request_block(block_id, "queued", 1, 0, 2, true),
		"third vessel queues when wide-water capacity is full")
	traffic.release_block(block_id, "north")
	var block: Dictionary = traffic.block_snapshot(block_id)
	_check((block.get("owner_vessel_ids", []) as Array).has("queued"),
		"wide-water release promotes the oldest queued vessel")


func _test_lane_window(traffic: Node) -> void:
	var specs: Array[Dictionary] = [
		{"block_id": "lane:test:0", "direction": 1, "capacity": 2},
		{"block_id": "lane:test:1", "direction": 1, "capacity": 2},
	]
	var first: Dictionary = traffic.request_lane_window("lane-a", specs)
	var second: Dictionary = traffic.request_lane_window("lane-b", specs)
	var opposing_specs: Array[Dictionary] = [{
		"block_id": "lane:test:1", "direction": -1, "capacity": 2}]
	var opposing: Dictionary = traffic.request_lane_window("lane-c", opposing_specs)
	_check(bool(first.get("granted", false)) and bool(second.get("granted", false)),
		"same-direction lane window admits a convoy up to capacity")
	_check(not bool(opposing.get("granted", false)),
		"opposing lane window stops at its first red signal")
	traffic.release_lane_window("lane-a")
	traffic.release_lane_window("lane-b")


func _test_atomic_lane_window_rollback(traffic: Node) -> void:
	traffic.request_block("lane:atomic:z", "blocker", -1)
	var specs: Array[Dictionary] = [
		{"block_id": "lane:atomic:a", "direction": 1, "capacity": 1},
		{"block_id": "lane:atomic:z", "direction": 1, "capacity": 1},
	]
	var result: Dictionary = traffic.request_lane_window("requester", specs)
	_check(not bool(result.get("granted", true)),
		"multi-block lane window reports a downstream red signal")
	var first: Dictionary = traffic.block_snapshot("lane:atomic:a")
	_check(not (first.get("owner_vessel_ids", []) as Array).has("requester"),
		"failed lane window rolls back new claims instead of holding half a route")
	traffic.release_block("lane:atomic:z", "blocker")


func _test_fifty_vessel_spatial_scan(traffic: Node) -> void:
	for index in range(50):
		traffic.publish_intent({
			"vessel_id": "stress-%02d" % index,
			"position_xz": [float(index % 10) * 90.0, float(index / 10) * 90.0],
			"velocity_xz": [4.0 if index % 2 == 0 else -4.0, 0.0],
			"heading_deg": 90.0 if index % 2 == 0 else 270.0,
			"length_m": 28.0,
		})
	var before := Time.get_ticks_usec()
	traffic.call("_resolve_conflicts")
	var elapsed_ms := float(Time.get_ticks_usec() - before) / 1000.0
	print("50-vessel traffic conflict scan: %.3f ms" % elapsed_ms)
	_check(elapsed_ms < 25.0,
		"50-vessel authority conflict pass remains below its 25 ms regression budget")


func _test_batched_fleet_publication(traffic: Node) -> void:
	_publish_count = 0
	traffic.traffic_changed.connect(_on_traffic_published)
	traffic.begin_batch()
	for index in range(50):
		var specs: Array[Dictionary] = [{
			"block_id": "batch:%d" % index,
			"direction": 1,
			"capacity": 1,
		}]
		traffic.request_lane_window("batch-vessel:%d" % index, specs)
	traffic.end_batch()
	_check(_publish_count == 1,
		"50-vessel lane renewal publishes one authority snapshot, not one per block")
	traffic.traffic_changed.disconnect(_on_traffic_published)


func _on_traffic_published(_snapshot: Dictionary) -> void:
	_publish_count += 1


func _test_snapshot_round_trip(traffic: Node) -> void:
	var encoded := JSON.stringify(traffic.snapshot())
	var decoded := JSON.parse_string(encoded) as Dictionary
	var replica := TrafficScript.new()
	root.add_child(replica)
	_check(replica.apply_authority_snapshot(decoded), "authority snapshot applies to a replica")
	_check(replica.port_queue("port-a").size() == 2, "port queue survives JSON replication")
	replica.queue_free()


func _check(condition: bool, label: String) -> void:
	if not condition and not _failures.has(label):
		_failures.append(label)


func _finish() -> void:
	if _failures.is_empty():
		print("Maritime traffic tests: all checks passed")
		quit()
		return
	for failure in _failures:
		push_error("Maritime traffic test: " + failure)
	quit(1)
