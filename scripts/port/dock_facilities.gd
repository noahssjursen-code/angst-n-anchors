class_name DockFacilities
extends Node3D

const _SCRIPT_SELF := preload("res://scripts/port/dock_facilities.gd")

## Mooring posts, ship spawner, and dock terminal in one subtree. Instantiate under any
## island root; positions are in the parent's local space.
## Pass every shore `MooringPost` world position here (minimum two). Spawn logic picks two
## closest to bow/stern; any grouped bollard accepts line toggles via `MooringComponent`.
##
## Instantiate via `_SCRIPT_SELF` because `DockFacilities.new()` is not resolved inside this file.


static func attach(
	parent: Node,
	mooring_post_positions: PackedVector3Array,
	terminal_position: Vector3,
	terminal_yaw_degrees: float,
	spawn_position: Vector3,
	ship_scene: PackedScene,
) -> Node3D:
	var kit: Node3D = _SCRIPT_SELF.new()
	kit.name = "DockFacilities"
	parent.add_child(kit)

	if mooring_post_positions.size() < 2:
		push_warning(
			"DockFacilities.attach: expected at least two mooring positions, got "
			+ str(mooring_post_positions.size())
		)

	for i in mooring_post_positions.size():
		var post := MooringPost.new()
		post.name = "MooringPost_" + str(i + 1)
		post.position = mooring_post_positions[i]
		kit.add_child(post)

	var spawner := ShipSpawner.new()
	spawner.name = "ShipSpawner"
	spawner.ship_scene = ship_scene
	spawner.spawn_position = spawn_position
	kit.add_child(spawner)

	# Ramp intentionally disabled for now.

	var terminal := DockTerminal.new()
	terminal.name = "DockTerminal"
	terminal.position = terminal_position
	terminal.rotation_degrees = Vector3(0.0, terminal_yaw_degrees, 0.0)
	kit.add_child(terminal)
	terminal.spawner_path = terminal.get_path_to(spawner)

	return kit


func get_ship_spawner() -> ShipSpawner:
	return get_node_or_null("ShipSpawner") as ShipSpawner
