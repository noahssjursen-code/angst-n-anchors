class_name CarryComponent
extends Node3D

@export var camera_path: NodePath = NodePath("../Camera3D")
@export var interact_distance: float = 4.5
@export var carried_offset: Vector3 = Vector3(0.45, -0.42, -1.15)

var carried_cargo: Resource

var _camera: Camera3D
var _carried_visual: MeshInstance3D


func _ready() -> void:
	_camera = get_node_or_null(camera_path) as Camera3D


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("cargo_interact"):
		_try_interact()
		get_viewport().set_input_as_handled()


func is_carrying() -> bool:
	return carried_cargo != null


func take_cargo(data: Resource) -> bool:
	if carried_cargo != null or data == null:
		return false
	carried_cargo = data.call("duplicate_data") as Resource
	_rebuild_carried_visual()
	return true


func clear_cargo() -> void:
	carried_cargo = null
	if _carried_visual != null:
		_carried_visual.queue_free()
		_carried_visual = null


func _try_interact() -> void:
	var target := _raycast_target()
	if target == null:
		return

	var source := _find_ancestor_with_method(target, "try_take_cargo")
	var deck := _find_ancestor_with_method(target, "try_load_cargo")

	if carried_cargo == null and source != null:
		var cargo = source.call("try_take_cargo")
		if cargo is Resource:
			take_cargo(cargo)
		return

	if carried_cargo != null and deck != null:
		var loaded := bool(deck.call("try_load_cargo", carried_cargo))
		if loaded:
			clear_cargo()


func _raycast_target() -> Node:
	if _camera == null:
		return null

	var from := _camera.global_position
	var to := from - _camera.global_transform.basis.z * interact_distance
	var query := PhysicsRayQueryParameters3D.create(from, to)
	var body := get_parent() as CollisionObject3D
	if body != null:
		query.exclude = [body.get_rid()]
	query.collide_with_areas = true
	query.collide_with_bodies = true

	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return null
	return hit.get("collider") as Node


func _find_ancestor_with_method(node: Node, method_name: String) -> Node:
	var current := node
	while current != null:
		if current.has_method(method_name):
			return current
		current = current.get_parent()
	return null


func _rebuild_carried_visual() -> void:
	if _carried_visual != null:
		_carried_visual.queue_free()
		_carried_visual = null

	if carried_cargo == null or _camera == null:
		return

	_carried_visual = carried_cargo.call("make_crate_visual") as MeshInstance3D
	if _carried_visual == null:
		return
	_carried_visual.name = "CarriedCargo"
	_camera.add_child(_carried_visual)
	_carried_visual.position = carried_offset
