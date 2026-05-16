class_name ProximityLoader
extends Node

## Loads and unloads world content based on distance from the active camera.
## Register entries with a world position, a factory Callable, and a load radius.
## The factory is called once when the player enters the radius; the returned node
## is placed at the entry position and freed when they leave.
##
## Uses camera position (not player position) so it works correctly when sailing.

const CHECK_INTERVAL := 1.0

var _entries: Array = []
var _timer:   float = 0.0


func register(world_position: Vector3, factory: Callable, load_radius: float) -> void:
	_entries.append({
		"position": world_position,
		"factory":  factory,
		"radius":   load_radius,
		"instance": null,
	})


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = CHECK_INTERVAL
	_tick()


func _tick() -> void:
	var ref_pos := _reference_position()
	for entry in _entries:
		if ref_pos.distance_to(entry["position"]) <= entry["radius"]:
			_load(entry)
		else:
			_unload(entry)


func _load(entry: Dictionary) -> void:
	if entry["instance"] != null and is_instance_valid(entry["instance"]):
		return
	var node := (entry["factory"] as Callable).call() as Node3D
	if node == null:
		push_warning("ProximityLoader: factory did not return a Node3D")
		return
	get_parent().add_child(node)
	node.global_position = entry["position"]
	entry["instance"] = node


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
	# Camera tracks the boat when sailing — more reliable than player body position.
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		return cam.global_position
	var players := get_tree().get_nodes_in_group("player")
	if not players.is_empty():
		return (players[0] as Node3D).global_position
	return Vector3.ZERO
