## BridgeInteractable — attach to any bridge superstructure scene.
## Generates its boarding interaction volume at runtime from the bridge's
## own rendered mesh geometry. No manual collision box, no editor gizmo.
## Drop this node into a bridge scene; the hull that instances the bridge
## connects to player_boarded / player_exited as needed.

class_name BridgeInteractable
extends Node3D

const VehicleGroups = preload("res://scripts/ship/vehicle_groups.gd")

func _init() -> void:
	add_to_group(VehicleGroups.SHIP_OWNER_ONLY)
	add_to_group(VehicleGroups.BOARDING_HIDES_OCCUPANT)


signal player_boarded
signal player_exited

const BOARDING_RAY_COLLISION_MASK: int = (1 << 0) | (1 << 1) | (1 << 2)

@export var look_distance: float = 35.0
@export var look_dot_threshold: float = 0.72
@export var interact_range: float = 10.0
@export var prompt_text: String = "Press F to board"
@export var exit_deck_offset: Vector2 = Vector2(0.0, 2.0)

var _occupied: bool = false
var _player: CharacterBody3D = null
var _interaction_area: Area3D
var _prompt_layer: CanvasLayer
var _prompt_label: Label
var _boat_cam: Camera3D = null
var _boat_controller: BoatController = null
var _boat_rigid_cached: RigidBody3D = null


func _ready() -> void:
	# Wait two frames so ModelAssembler finishes building mesh before we sample it.
	await get_tree().process_frame
	await get_tree().process_frame
	_build_from_mesh()
	_cache_boat_nodes()
	_ensure_prompt_ui()


# --- Mesh-derived collision --------------------------------------------------

func _build_from_mesh() -> void:
	var verts: PackedVector3Array = []
	_collect_verts(get_parent(), verts)
	if verts.is_empty():
		push_warning("BridgeInteractable: no mesh vertices found — bridge mesh may not be built yet.")
		return

	_interaction_area = Area3D.new()
	_interaction_area.name = "BridgeMeshArea"
	_interaction_area.collision_layer = 1
	_interaction_area.collision_mask = 0
	_interaction_area.monitoring = false
	_interaction_area.monitorable = true

	var shape := ConvexPolygonShape3D.new()
	shape.points = verts

	var cs := CollisionShape3D.new()
	cs.shape = shape
	_interaction_area.add_child(cs)
	add_child(_interaction_area)


func _collect_verts(node: Node, out: PackedVector3Array) -> void:
	if node is MeshInstance3D:
		var mi: MeshInstance3D = node
		if mi.mesh != null:
			for s in mi.mesh.get_surface_count():
				var arrays := mi.mesh.surface_get_arrays(s)
				if arrays.is_empty():
					continue
				var pts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var rel: Transform3D = global_transform.affine_inverse() * mi.global_transform
				for v in pts:
					out.append(rel * v)
	for child in node.get_children():
		_collect_verts(child, out)


# --- Input / prompt ----------------------------------------------------------

func _process(_delta: float) -> void:
	_update_prompt()


func _unhandled_input(event: InputEvent) -> void:
	if _occupied:
		if event.is_action_pressed("interact") or event.is_action_pressed("ui_cancel"):
			_exit()
			get_viewport().set_input_as_handled()
	else:
		if event.is_action_pressed("interact") and _boarding_player() != null:
			_board()
			get_viewport().set_input_as_handled()


# --- Boarding detection ------------------------------------------------------

func _nearest_player_in_range() -> CharacterBody3D:
	for node: Node in get_tree().get_nodes_in_group("player"):
		var body := node as CharacterBody3D
		if body and global_position.distance_to(body.global_position) <= interact_range:
			return body
	return null


func _boarding_player() -> CharacterBody3D:
	var body := _nearest_player_in_range()
	if body == null:
		return null
	if not _player_is_looking_at_bridge(body):
		return null
	return body


func _player_is_looking_at_bridge(body: CharacterBody3D) -> bool:
	var camera := body.get_node_or_null("Camera3D") as Camera3D
	if camera == null:
		return false

	var from := camera.global_position
	var to   := from - camera.global_transform.basis.z * look_distance
	var query := PhysicsRayQueryParameters3D.create(from, to, BOARDING_RAY_COLLISION_MASK)
	query.exclude = [body.get_rid()]
	query.collide_with_areas  = true
	query.collide_with_bodies = true

	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		var collider := hit.get("collider") as Node
		# Hit the bridge mesh area directly
		if collider == _interaction_area or (collider != null and is_ancestor_of(collider)):
			return true
		# Hit any part of the same boat (hull, deck, etc.)
		var mine     := _boat_rigid_body()
		var hit_boat := _collision_owning_boat(collider)
		return hit_boat != null and mine != null and hit_boat == mine

	# Dot-product fallback: player is close and broadly facing the bridge
	var to_bridge := global_position - camera.global_position
	if to_bridge.length_squared() <= 0.01:
		return true
	return (-camera.global_transform.basis.z.normalized()).dot(to_bridge.normalized()) >= look_dot_threshold


# --- Board / exit ------------------------------------------------------------

func _board() -> void:
	_player = _boarding_player()
	if _player == null:
		return
	_occupied = true
	if _prompt_label != null:
		_prompt_label.visible = false
	_player.set_physics_process(false)
	_player.set_process_unhandled_input(false)
	_player.velocity = Vector3.ZERO
	if _boat_cam != null:
		_boat_cam.current = true
	if _boat_controller != null:
		_boat_controller.activate()
	player_boarded.emit()


func _exit() -> void:
	_occupied = false
	if _player != null:
		_place_player_on_deck(_player)
		_player.set_physics_process(true)
		_player.set_process_unhandled_input(true)
		var player_cam := _player.get_node_or_null("Camera3D") as Camera3D
		if player_cam != null:
			player_cam.current = true
		_player = null
	if _boat_controller != null:
		_boat_controller.deactivate()
	player_exited.emit()


func _place_player_on_deck(body: CharacterBody3D) -> void:
	var boat := _boat_rigid_body()
	if boat == null:
		return
	var hull_size := Vector3(6.0, 2.0, 14.0)
	if "hull_size" in boat:
		hull_size = boat.get("hull_size")
	var half := hull_size * 0.5
	var local_exit := Vector3(
		clampf(exit_deck_offset.x, -half.x * 0.85, half.x * 0.85),
		half.y + 0.5,
		clampf(exit_deck_offset.y, -half.z * 0.85, half.z * 0.85)
	)
	body.global_position = boat.to_global(local_exit)
	body.velocity = Vector3.ZERO


# --- Helpers -----------------------------------------------------------------

func _boat_rigid_body() -> RigidBody3D:
	if _boat_rigid_cached != null and is_instance_valid(_boat_rigid_cached):
		return _boat_rigid_cached
	var p := get_parent()
	while p != null:
		if p is RigidBody3D:
			_boat_rigid_cached = p as RigidBody3D
			return _boat_rigid_cached
		p = p.get_parent()
	return null


func _cache_boat_nodes() -> void:
	var rb := _boat_rigid_body()
	if rb == null:
		return
	_boat_cam        = rb.get_node_or_null("BoatCamera") as Camera3D
	_boat_controller = rb.get_node_or_null("BoatController") as BoatController


func _collision_owning_boat(collider: Node) -> RigidBody3D:
	if collider == null:
		return null
	var co := collider as CollisionObject3D
	if co != null and co.has_meta("_boat_owner"):
		var owner_node = co.get_meta("_boat_owner")
		if owner_node is RigidBody3D:
			return owner_node as RigidBody3D
	var p := collider
	while p != null:
		if p is RigidBody3D:
			return p as RigidBody3D
		p = p.get_parent()
	return null


func _ensure_prompt_ui() -> void:
	if _prompt_layer != null:
		return
	_prompt_layer = CanvasLayer.new()
	_prompt_layer.name = "BoardPromptLayer"
	add_child(_prompt_layer)
	_prompt_label = Label.new()
	_prompt_label.name = "BoardPrompt"
	_prompt_label.text = prompt_text
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_prompt_label.visible = false
	_prompt_label.add_theme_font_size_override("font_size", 22)
	_prompt_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt_label.offset_left   = -180.0
	_prompt_label.offset_right  =  180.0
	_prompt_label.offset_top    =  -92.0
	_prompt_label.offset_bottom =  -48.0
	_prompt_layer.add_child(_prompt_label)


func _update_prompt() -> void:
	if _prompt_label == null:
		return
	_prompt_label.visible = not _occupied and _boarding_player() != null


func is_occupied() -> bool:
	return _occupied
