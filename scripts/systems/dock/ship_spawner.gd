class_name ShipSpawner
extends Node3D

@export var ship_scene: PackedScene
@export var spawn_position: Vector3 = Vector3(11.0, -1.5, 47.0)
@export var spawn_rotation_degrees: Vector3 = Vector3.ZERO
@export var waterline_draft_fraction: float = 0.45
@export var front_post_path: NodePath
@export var rear_post_path: NodePath
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
			"ShipSpawner: ship has no MooringComponent (expected under ShipGameplay or boat root)."
		)
		return

	var front_post := get_node_or_null(front_post_path)
	var rear_post := get_node_or_null(rear_post_path)
	if front_post == null or rear_post == null:
		push_warning("ShipSpawner: missing mooring posts")
		return

	mooring.call("moor_to_posts", front_post, rear_post)
	_register_post(front_post, mooring, "bow")
	_register_post(rear_post, mooring, "stern")


func _register_post(post: Node, mooring: Node, station: String) -> void:
	if post.has_method("register_mooring_component"):
		post.call("register_mooring_component", mooring)
	post.set("line_station", station)


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
	for post_path in [front_post_path, rear_post_path]:
		var post := get_node_or_null(post_path)
		if post != null and post.has_method("clear_mooring_component"):
			post.call("clear_mooring_component", mooring)
