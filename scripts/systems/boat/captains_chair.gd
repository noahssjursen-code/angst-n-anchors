@tool
class_name CaptainsChair
extends Node3D

## The helm/cabin interaction point. When the player presses E within range,
## they take control of the boat: player movement is suspended, the boat
## camera activates, and BoatController starts reading input.
## Press E or Escape to exit.

signal player_boarded
signal player_exited

## Layers: world + boat hull + boat walk (see ProjectSettings layer names).
const BOARDING_RAY_COLLISION_MASK: int = (1 << 0) | (1 << 1) | (1 << 2)

@export var interact_range: float = 2.8
@export var look_distance: float = 35.0
@export var look_dot_threshold: float = 0.72
@export var prompt_text: String = "Press E to board"

@export_group("Helm boarding volume")

## Boarding pick box: pivot = this node's transform. Centre = `aim_target_offset`, size =
## `interaction_volume_size`. Runtime `HelmInteractionArea` and the editor gizmo match this;
## it is not part of the hull JSON mesh.
var _helm_aim: Vector3 = Vector3(0.0, 0.8, 0.0)

@export var aim_target_offset: Vector3:
	get:
		return _helm_aim
	set(v):
		_helm_aim = v
		_schedule_editor_gizmo_refresh()

var _helm_volume: Vector3 = Vector3(1.4, 1.8, 1.4)

@export var interaction_volume_size: Vector3:
	get:
		return _helm_volume
	set(v):
		_helm_volume = v
		_schedule_editor_gizmo_refresh()

var _helm_gizmo_on: bool = true

## Editor-only: translucent box matching the boarding pick volume.
@export var show_editor_interact_gizmo: bool:
	get:
		return _helm_gizmo_on
	set(v):
		_helm_gizmo_on = v
		_schedule_editor_gizmo_refresh()


## Local X/Z deck position used when leaving the helm. Y is calculated from
## the mesh-derived hull height so the player lands on top of the current deck.
@export var exit_deck_offset: Vector2 = Vector2(-3.4, -8.0)

var _occupied: bool = false
var _player: CharacterBody3D = null
var _interaction_area: Area3D
var _prompt_layer: CanvasLayer
var _prompt_label: Label

var _boat_cam: Camera3D = null
var _boat_controller: BoatController = null
var _boat_rigid_cached: RigidBody3D = null


func _ready() -> void:
	if Engine.is_editor_hint():
		_refresh_editor_interact_gizmo()
		return
	_ensure_interaction_area()
	_cache_boat_nodes()
	_ensure_prompt_ui()


func _schedule_editor_gizmo_refresh() -> void:
	if Engine.is_editor_hint():
		call_deferred("_refresh_editor_interact_gizmo")


func _refresh_editor_interact_gizmo() -> void:
	if not Engine.is_editor_hint():
		return
	var prev := get_node_or_null("EditorHelmInteractGizmo")
	if prev != null:
		prev.queue_free()

	if not show_editor_interact_gizmo:
		return

	var mi := MeshInstance3D.new()
	mi.name = "EditorHelmInteractGizmo"
	var box_mesh := BoxMesh.new()
	box_mesh.size = interaction_volume_size
	mi.mesh = box_mesh
	mi.position = aim_target_offset

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.25, 0.78, 1.0, 0.2)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
	mat.no_depth_test = true

	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	add_child(mi)


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_update_prompt()


func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if _occupied:
		if event.is_action_pressed("interact") or event.is_action_pressed("ui_cancel"):
			_exit()
			get_viewport().set_input_as_handled()
	else:
		if event.is_action_pressed("interact") and _boarding_player() != null:
			_board()
			get_viewport().set_input_as_handled()


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
	_boat_cam = rb.get_node_or_null("BoatCamera") as Camera3D
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
	if not _player_is_looking_at_station(body):
		return null
	return body


func _player_is_looking_at_station(body: CharacterBody3D) -> bool:
	var camera := body.get_node_or_null("Camera3D") as Camera3D
	if camera == null:
		return false

	var from := camera.global_position
	var to := from - camera.global_transform.basis.z * look_distance
	var query := PhysicsRayQueryParameters3D.create(from, to, BOARDING_RAY_COLLISION_MASK)
	query.exclude = [body.get_rid()]
	query.collide_with_areas = true
	query.collide_with_bodies = true

	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		var collider := hit.get("collider") as Node
		if collider == self:
			return true
		if collider == _interaction_area:
			return true
		if collider != null and is_ancestor_of(collider):
			return true

		var mine := _boat_rigid_body()
		var hit_boat := _collision_owning_boat(collider)
		return hit_boat != null and mine != null and hit_boat == mine

	var target := to_global(aim_target_offset)
	var to_target := target - camera.global_position
	if to_target.length_squared() <= 0.01:
		return true
	var forward := -camera.global_transform.basis.z.normalized()
	return forward.dot(to_target.normalized()) >= look_dot_threshold


func _ensure_interaction_area() -> void:
	_interaction_area = get_node_or_null("HelmInteractionArea") as Area3D
	if _interaction_area == null:
		_interaction_area = Area3D.new()
		_interaction_area.name = "HelmInteractionArea"
		add_child(_interaction_area)

	_interaction_area.position = aim_target_offset
	_interaction_area.collision_layer = 1
	_interaction_area.collision_mask = 0
	_interaction_area.monitoring = false
	_interaction_area.monitorable = true

	var collision := (
		_interaction_area.get_node_or_null("CollisionShape3D") as CollisionShape3D
	)
	if collision == null:
		collision = CollisionShape3D.new()
		collision.name = "CollisionShape3D"
		_interaction_area.add_child(collision)

	var shape := collision.shape as BoxShape3D
	if shape == null:
		shape = BoxShape3D.new()
		collision.shape = shape
	shape.size = interaction_volume_size


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
	_prompt_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_prompt_label.visible = false
	_prompt_label.add_theme_font_size_override("font_size", 22)
	_prompt_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt_label.offset_left = -180.0
	_prompt_label.offset_right = 180.0
	_prompt_label.offset_top = -92.0
	_prompt_label.offset_bottom = -48.0
	_prompt_layer.add_child(_prompt_label)


func _update_prompt() -> void:
	if _prompt_label == null:
		return
	_prompt_label.visible = not _occupied and _boarding_player() != null


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


func is_occupied() -> bool:
	return _occupied

