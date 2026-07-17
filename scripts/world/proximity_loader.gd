class_name ProximityLoader
extends Node

## Loads and unloads world content based on distance from the active camera.
## Register entries with a world position, a factory Callable, and a load radius.
## The factory is called once when the player enters the radius; the returned node
## is placed at the entry position and freed when they leave.
##
## Uses camera position (including freecam) so distant ports stream in while flying.
## Unload sits farther than load so orbiting/panning at the edge does not thrash.

const CHECK_INTERVAL := 1.0
## Unload only when past load radius + this (orbit at the edge must not thrash).
const UNLOAD_HYSTERESIS_M := 800.0
const WorldReference := preload("res://scripts/world/world_reference.gd")

var _entries: Array = []
var _timer:   float = 0.0
var _pending_operations: Array[Dictionary] = []


func _ready() -> void:
	var telemetry := get_node_or_null("/root/Telemetry")
	if telemetry != null and telemetry.has_method("register_provider"):
		telemetry.register_provider(&"world.ports", self, &"get_debug_stats", &"world")


func _exit_tree() -> void:
	var telemetry := get_node_or_null("/root/Telemetry")
	if telemetry != null and telemetry.has_method("unregister_provider"):
		telemetry.unregister_provider(&"world.ports", self)


func register(world_position: Vector3, factory: Callable, load_radius: float, debug_name: String = "") -> void:
	_entries.append({
		"position":   world_position,
		"factory":    factory,
		"radius":     load_radius,
		"instance":   null,
		"debug_name": debug_name,
		"pending_action": "",
	})


func _process(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		_timer = CHECK_INTERVAL
		_tick()
	# PortPlot rebuilds are synchronous once their deferred callback runs. Queue
	# at most one lifecycle change per frame so clustered ports cannot all stamp
	# thousands of nodes in the same frame.
	_process_one_operation()


func _tick() -> void:
	var ref_pos := _reference_position()
	for entry in _entries:
		var dist := ref_pos.distance_to(entry["position"] as Vector3)
		var radius := float(entry["radius"])
		var loaded := entry["instance"] != null and is_instance_valid(entry["instance"])
		if not loaded:
			entry["instance"] = null
			if dist <= radius:
				_queue_operation(entry, "load")
		elif dist > radius + UNLOAD_HYSTERESIS_M:
			_queue_operation(entry, "unload")


func _queue_operation(entry: Dictionary, action: String) -> void:
	if not str(entry.get("pending_action", "")).is_empty():
		return
	entry["pending_action"] = action
	_pending_operations.append({"entry": entry, "action": action})


func _process_one_operation() -> void:
	if _pending_operations.is_empty():
		return
	var operation := _pending_operations.pop_front() as Dictionary
	var entry := operation.get("entry", {}) as Dictionary
	var action := str(operation.get("action", ""))
	entry["pending_action"] = ""
	var ref_pos := _reference_position()
	var distance := ref_pos.distance_to(entry.get("position", Vector3.ZERO) as Vector3)
	var radius := float(entry.get("radius", 0.0))
	if action == "load" and distance <= radius:
		_load(entry)
	elif action == "unload" and distance > radius + UNLOAD_HYSTERESIS_M:
		_unload(entry)


func _load(entry: Dictionary) -> void:
	if entry["instance"] != null and is_instance_valid(entry["instance"]):
		return
	var t := get_node_or_null("/root/Telemetry")
	var ev_name := "port.load:%s" % str(entry.get("debug_name", "port"))
	var handle: int = t.mark_load_event(ev_name) if t != null else 0
	var node := (entry["factory"] as Callable).call() as Node3D
	if node == null:
		push_warning("ProximityLoader: factory did not return a Node3D")
		if t != null:
			t.end_load_event(handle)
		return
	var waits_for_rebuild := node.has_signal("rebuild_completed")
	if waits_for_rebuild and t != null:
		node.connect(
			"rebuild_completed",
			Callable(self, "_on_port_rebuilt").bind(t, handle, str(entry.get("debug_name", "port"))),
			CONNECT_ONE_SHOT,
		)
		t.set_context_flag(
			StringName("stream.port_building.%s" % str(entry.get("debug_name", "port"))),
			true,
			&"proximity_loader",
		)
	get_parent().add_child(node)
	node.global_position = entry["position"]
	entry["instance"] = node
	if t != null and not waits_for_rebuild:
		t.end_load_event(handle)


func _on_port_rebuilt(duration_ms: float, t: Node, handle: int, debug_name: String) -> void:
	if t == null or not is_instance_valid(t):
		return
	t.end_load_event(handle)
	t.clear_context_flag(StringName("stream.port_building.%s" % debug_name))
	t.record_event(&"stream", &"port_rebuilt", "info", {
		"port": debug_name,
		"rebuild_ms": duration_ms,
	})


func _unload(entry: Dictionary) -> void:
	if entry["instance"] == null or not is_instance_valid(entry["instance"]):
		entry["instance"] = null
		return
	# Never unload a port that contains the player's active ship.
	var instance := entry["instance"] as Node
	if instance != null:
		for boat in get_tree().get_nodes_in_group("player_boat"):
			if boat is Node and instance.is_ancestor_of(boat as Node):
				return
	entry["instance"].queue_free()
	entry["instance"] = null


func _reference_position() -> Vector3:
	return WorldReference.stream_position(get_viewport())


func get_debug_stats() -> Dictionary:
	var loaded := 0
	for entry in _entries:
		var instance: Variant = (entry as Dictionary).get("instance", null)
		if instance is Node and is_instance_valid(instance):
			loaded += 1
	return {
		"registered": _entries.size(),
		"loaded": loaded,
		"pending_operations": _pending_operations.size(),
	}
