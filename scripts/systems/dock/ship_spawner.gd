class_name ShipSpawner
extends Node3D

@export var ship_scene: PackedScene
@export var spawn_position: Vector3 = Vector3(11.0, -1.5, 47.0)
@export var spawn_rotation_degrees: Vector3 = Vector3.ZERO
## Used only when the spawned scene root is not a `BoatBody`. Otherwise spawn uses `design_draft_fraction`.
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

	var draft_frac := waterline_draft_fraction
	var boat := ship as BoatBody
	if boat != null:
		draft_frac = boat.design_draft_fraction

	if ship.has_method("place_at_waterline"):
		ship.call("place_at_waterline", WaveSurface.WATER_LEVEL, draft_frac)

	_moor_ship(ship)
	return ship


func clear_ship() -> void:
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
	var mooring := _find_mooring_component(ship) as MooringComponent
	if mooring == null:
		push_warning("ShipSpawner: ship has no MooringComponent")
		return
	mooring.auto_moor(ship.get_tree())


func _find_mooring_component(ship: Node) -> Node:
	if ship == null:
		return null
	var direct := ship.get_node_or_null("MooringComponent")
	if direct != null:
		return direct
	return ship.find_child("MooringComponent", true, false)
