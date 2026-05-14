@tool
class_name MooringPost
extends StaticBody3D

@export var post_height: float = 1.1
@export var post_radius: float = 0.16
@export var anchor_local_position: Vector3 = Vector3(0.0, 0.85, 0.0)
@export var post_color: Color = Color(0.18, 0.11, 0.06)
@export_enum("bow", "stern") var line_station: String = "bow"

var _moor_interact_range: float = 3.2

## Max distance / ray depth for mooring prompts and E toggle.
@export var interact_range: float:
	get:
		return _moor_interact_range
	set(v):
		_moor_interact_range = maxf(0.05, v)
		_refresh_editor_range_gizmo_deferred()


var _show_interact_sphere: bool = true

## Editor-only: translucent sphere at the mooring anchor; matches interact_range.
@export var show_editor_interact_range_gizmo: bool:
	get:
		return _show_interact_sphere
	set(v):
		_show_interact_sphere = v
		_refresh_editor_range_gizmo_deferred()

var _mooring_component: Node
var _prompt_layer: CanvasLayer
var _prompt_label: Label


func _ready() -> void:
	_rebuild()
	if not Engine.is_editor_hint():
		_ensure_prompt_ui()


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_update_prompt()


func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if event.is_action_pressed("interact") and _player_can_interact():
		_toggle_line()
		get_viewport().set_input_as_handled()


func get_anchor_global_position() -> Vector3:
	return to_global(anchor_local_position)


func register_mooring_component(component: Node) -> void:
	_mooring_component = component


func clear_mooring_component(component: Node) -> void:
	if _mooring_component == component:
		_mooring_component = null


func _refresh_editor_range_gizmo_deferred() -> void:
	if Engine.is_editor_hint():
		call_deferred("_refresh_editor_range_gizmo")


func _refresh_editor_range_gizmo() -> void:
	if not Engine.is_editor_hint():
		return
	var prev := get_node_or_null("EditorMooringInteractSphere")
	if prev != null:
		prev.queue_free()
	if not show_editor_interact_range_gizmo:
		return

	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = "EditorMooringInteractSphere"
	var sphere := SphereMesh.new()
	sphere.radius = interact_range
	sphere.height = interact_range * 2.0
	mesh_inst.mesh = sphere
	mesh_inst.position = anchor_local_position

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.72, 0.18, 0.12)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
	mat.no_depth_test = true
	mesh_inst.material_override = mat
	mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	add_child(mesh_inst)


func _rebuild() -> void:
	for child in get_children():
		child.queue_free()

	var shape := CylinderShape3D.new()
	shape.radius = post_radius
	shape.height = post_height

	var collision := CollisionShape3D.new()
	collision.name = "PostCollision"
	collision.shape = shape
	collision.position = Vector3.UP * (post_height * 0.5)
	add_child(collision)

	var visual := MeshBuilder.cylinder(post_radius, post_height, post_color, 0.95, 0.0)
	visual.name = "PostVisual"
	visual.position = Vector3.UP * (post_height * 0.5)
	add_child(visual)

	var cap := MeshBuilder.cylinder(post_radius * 1.28, 0.16, post_color.lightened(0.08), 0.9, 0.0)
	cap.name = "PostCap"
	cap.position = Vector3.UP * post_height
	add_child(cap)

	if Engine.is_editor_hint():
		call_deferred("_refresh_editor_range_gizmo")


func _toggle_line() -> void:
	if _mooring_component == null or not is_instance_valid(_mooring_component):
		return
	if _mooring_component.has_method("toggle_line"):
		_mooring_component.call("toggle_line", line_station)
	_update_prompt()


func _update_prompt() -> void:
	if _prompt_label == null:
		return
	var can_interact := _player_can_interact()
	_prompt_label.visible = can_interact
	if not can_interact:
		return
	var action := "tie"
	if _mooring_component != null and _mooring_component.has_method("is_line_tied"):
		if bool(_mooring_component.call("is_line_tied", line_station)):
			action = "untie"
	_prompt_label.text = "Press E to %s %s line" % [action, line_station]


func _player_can_interact() -> bool:
	if _mooring_component == null or not is_instance_valid(_mooring_component):
		return false
	var player := _nearest_player()
	if player == null:
		return false
	var camera := player.get_node_or_null("Camera3D") as Camera3D
	if camera == null:
		return false

	var from := camera.global_position
	var to := from - camera.global_transform.basis.z * interact_range
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [player.get_rid()]
	query.collide_with_areas = false
	query.collide_with_bodies = true

	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return false
	var collider := hit.get("collider") as Node
	return collider == self or (collider != null and is_ancestor_of(collider))


func _nearest_player() -> CharacterBody3D:
	for node in get_tree().get_nodes_in_group("player"):
		var body := node as CharacterBody3D
		if body != null and global_position.distance_to(body.global_position) <= interact_range:
			return body
	return null


func _ensure_prompt_ui() -> void:
	if _prompt_layer != null:
		return

	_prompt_layer = CanvasLayer.new()
	_prompt_layer.name = "MooringPostPromptLayer"
	add_child(_prompt_layer)

	_prompt_label = Label.new()
	_prompt_label.name = "MooringPostPrompt"
	_prompt_label.visible = false
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.add_theme_font_size_override("font_size", 20)
	_prompt_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt_label.offset_left = -200.0
	_prompt_label.offset_right = 200.0
	_prompt_label.offset_top = -148.0
	_prompt_label.offset_bottom = -108.0
	_prompt_layer.add_child(_prompt_label)
