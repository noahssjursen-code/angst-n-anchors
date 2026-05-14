class_name ShipSpawner
extends Node3D

@export var ship_scene: PackedScene
@export var spawn_position: Vector3 = Vector3(11.0, -1.5, 47.0)
@export var spawn_rotation_degrees: Vector3 = Vector3.ZERO
@export var waterline_draft_fraction: float = 0.45
@export var spawned_ship_name: String = "SpawnedShip"

var current_ship: Node3D


func spawn_ship() -> Node3D:
	if ship_scene == null:
		push_warning("ShipSpawner: no ship scene configured")
		return null

	clear_ship()

	var ship := ship_scene.instantiate() as Node3D
	if ship == null:
		push_warning("ShipSpawner: configured scene is not a Node3D")
		return null

	ship.name = spawned_ship_name
	ship.position = spawn_position
	ship.rotation_degrees = spawn_rotation_degrees
	add_child(ship)
	current_ship = ship

	if ship.has_method("place_at_waterline"):
		ship.call("place_at_waterline", WaveSurface.WATER_LEVEL, waterline_draft_fraction)

	_moor_ship(ship)
	return ship


func clear_ship() -> void:
	_clear_post_registrations()
	if current_ship != null and is_instance_valid(current_ship):
		current_ship.queue_free()
	current_ship = null


func release_current_ship() -> void:
	if current_ship == null or not is_instance_valid(current_ship):
		return
	var mooring := _find_mooring_component(current_ship)
	if mooring != null and mooring.has_method("release_mooring"):
		mooring.call("release_mooring")


func _moor_ship(ship: Node3D) -> void:
	var mooring := _find_mooring_component(ship)
	if mooring == null or not mooring.has_method("moor_to_posts"):
		push_warning(
			"ShipSpawner: ship has no MooringComponent (expected under ShipGameplay or boat root).",
		)
		return

	var tree := ship.get_tree()
	if tree == null:
		push_warning("ShipSpawner: ship not in scene tree yet")
		return

	MooringComponent.register_mooring_on_all_dock_bollards(tree, mooring)

	var mc := mooring as MooringComponent
	if mc == null:
		return

	var pair := MooringComponent.pick_two_dock_posts_for_ship(mc, tree)
	if pair.size() < 2 or pair[0] == null or pair[1] == null:
		push_warning(
			"ShipSpawner: need at least two dock bollards (group \"%s\", get_anchor_global_position)."
			% MooringComponent.DOCK_MOORING_GROUP,
		)
		return

	mc.moor_to_posts(pair[0], pair[1])


func _find_mooring_component(ship: Node) -> Node:
	if ship == null:
		return null
	var direct := ship.get_node_or_null("MooringComponent")
	if direct != null:
		return direct
	return ship.find_child("MooringComponent", true, false)


func _clear_post_registrations() -> void:
	if current_ship == null or not is_instance_valid(current_ship):
		return
	var mooring := _find_mooring_component(current_ship)
	var tree := get_tree()
	if tree != null:
		MooringComponent.clear_mooring_on_all_dock_bollards(tree, mooring)
