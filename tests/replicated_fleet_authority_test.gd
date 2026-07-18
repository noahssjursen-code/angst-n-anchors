extends SceneTree

const AuthorityScript := preload("res://scripts/traffic/replicated_fleet_authority.gd")

var _failures := PackedStringArray()


func _initialize() -> void:
	var authority := AuthorityScript.new()
	root.add_child(authority)
	var result: Dictionary = authority.apply_server_snapshot({
		"schema_version": 1,
		"revision": 2,
		"server_unix_msec": 123456,
		"vessels": [_wire("remote-1"), {"invalid": true}],
	})
	_check(bool(result.get("ok", false)), "supported snapshot applies")
	_check(int(result.get("accepted", 0)) == 1, "valid remote vessel is accepted")
	_check(int(result.get("rejected", 0)) == 1, "invalid remote vessel is rejected")
	var records: Array = authority.projection_records()
	_check(records.size() == 1, "replicated authority publishes one projection record")
	if not records.is_empty():
		var projection := (records[0] as Dictionary).get("projection", {}) as Dictionary
		var position := projection.get("position", Vector3.ZERO) as Vector3
		_check(position.is_equal_approx(Vector3(100.0, WaveSurface.WATER_LEVEL, 200.0)),
			"wire XZ pose becomes the initial local projection")
	var rejected_schema: Dictionary = authority.apply_server_snapshot({
		"schema_version": 99, "vessels": []})
	_check(not bool(rejected_schema.get("ok", true)), "unknown schema is rejected")
	var duplicate_result: Dictionary = authority.apply_server_snapshot({
		"schema_version": 1,
		"revision": 3,
		"server_unix_msec": 123456,
		"vessels": [_wire("duplicate"), _wire("duplicate")],
	})
	_check(int(duplicate_result.get("accepted", 0)) == 1 \
			and int(duplicate_result.get("rejected", 0)) == 1,
		"duplicate server vessel identities cannot create two projections")
	var stale_result: Dictionary = authority.apply_server_snapshot({
		"schema_version": 1,
		"revision": 1,
		"server_unix_msec": 999999,
		"vessels": [_wire("rewind")],
	})
	_check(str(stale_result.get("reason", "")) == "stale_revision",
		"out-of-order network snapshots cannot rewind the local fleet")
	authority.queue_free()
	_finish()


func _wire(uid: String) -> Dictionary:
	return {
		"schema_version": 1,
		"server_unix_msec": 123456,
		"vessel_id": uid,
		"owner_id": "server",
		"vessel": {"uid": uid, "hull_id": "hull_28x10", "name": "Remote"},
		"assignment": {"status": "berthed", "commodity_id": "provisions"},
		"navigation": {
			"route_id": "route:test",
			"route_progress_m": 50.0,
			"origin_port_id": "port-a",
			"origin_berth_id": "berth-a",
			"destination_port_id": "port-b",
			"destination_berth_id": "berth-b",
			"position_xz": [100.0, 200.0],
			"heading_xz": [1.0, 0.0],
		},
		"runtime": {},
	}


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)


func _finish() -> void:
	if _failures.is_empty():
		print("Replicated fleet authority tests: all checks passed")
		quit()
		return
	for failure in _failures:
		push_error("Replicated fleet authority test: " + failure)
	quit(1)
