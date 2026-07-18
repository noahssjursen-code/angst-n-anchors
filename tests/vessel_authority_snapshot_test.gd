extends SceneTree


func _init() -> void:
	var plan := MarineRoutePlan.create(
		PackedVector2Array([Vector2(10.0, 20.0), Vector2(500.0, 700.0)]),
		"world-checksum", "port-a", "port-b")
	var record := {
		"uid": "server-vessel-1",
		"vessel": {"uid": "server-vessel-1", "hull_id": "hull_28x10", "brick_layout": {"cells": {}}},
		"assignment": {
			"status": "underway", "leg_origin_port_id": "port-a",
			"leg_origin_berth_id": "a-1", "leg_destination_port_id": "port-b",
			"leg_destination_berth_id": "b-1", "route_progress_m": 120.0,
		},
		"projection": {
			"position": Vector3(100.0, 2.0, 200.0), "heading_xz": Vector2(0.5, -0.5),
			"route_progress_m": 120.0,
		},
	}
	var wire := VesselAuthoritySnapshot.from_projection_record(record, plan, null, 123456)
	_assert(VesselAuthoritySnapshot.is_valid(wire), "wire vessel validates")
	var decoded := VesselAuthoritySnapshot.json_round_trip(wire)
	_assert(VesselAuthoritySnapshot.is_valid(decoded), "wire vessel survives JSON")
	_assert(int(decoded.get("server_unix_msec", 0)) == 123456, "server timestamp survives")
	var navigation := decoded.get("navigation", {}) as Dictionary
	_assert(str(navigation.get("route_id", "")) == plan.route_id, "route identity survives")
	_assert((navigation.get("position_xz", []) as Array).size() == 2, "position uses JSON-safe XZ")
	print("Vessel authority snapshot tests: all checks passed")
	quit()


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("FAILED: %s" % message)
	quit(1)
