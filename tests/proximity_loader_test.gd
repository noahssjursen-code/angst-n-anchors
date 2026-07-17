extends SceneTree

const LOADER := preload("res://scripts/world/proximity_loader.gd")


class FakePort extends Node3D:
	signal rebuild_completed(duration_ms: float)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var loader := LOADER.new()
	root.add_child(loader)
	var created: Array[Node3D] = []
	var factory := func() -> Node3D:
		var port := FakePort.new()
		created.append(port)
		return port
	var first := {
		"position": Vector3.ZERO,
		"factory": factory,
		"radius": 100.0,
		"instance": null,
		"debug_name": "first",
		"pending_action": "",
	}
	var second := first.duplicate()
	second["debug_name"] = "second"
	loader._queue_operation(first, "load")
	loader._queue_operation(second, "load")
	assert(loader._pending_operations.size() == 2)
	loader._process_one_operation()
	assert(created.size() == 1)
	assert(loader._pending_operations.size() == 1)
	loader._process_one_operation()
	assert(created.size() == 2)
	assert(loader._pending_operations.is_empty())
	for port in created:
		port.rebuild_completed.emit(4.0)
	loader.free()
	for port in created:
		if is_instance_valid(port):
			port.free()
	print("proximity_loader_test: PASS")
	quit(0)
