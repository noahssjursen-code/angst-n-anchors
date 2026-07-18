extends SceneTree

const TrafficScript := preload("res://scripts/traffic/maritime_traffic_service.gd")

var _failures := PackedStringArray()


func _initialize() -> void:
	var traffic := TrafficScript.new()
	root.add_child(traffic)
	_test_collision_agreement(traffic)
	_test_port_queue(traffic)
	_test_exclusive_block(traffic)
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


func _test_exclusive_block(traffic: Node) -> void:
	_check(traffic.request_block("narrow:bridge", "first", 1), "first vessel reserves a narrow block")
	_check(not traffic.request_block("narrow:bridge", "second", -1), "second vessel queues at occupied block")
	traffic.release_block("narrow:bridge", "first")
	var block: Dictionary = traffic.block_snapshot("narrow:bridge")
	_check(str(block.get("owner_vessel_id", "")) == "second", "block release promotes the queued vessel")


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
