@tool
class_name MooringPost
extends StaticBody3D

## Visual style: timber cylinder (legacy), or the docking bollard mesh used on ship cleats
## (`MooringPoint`).
enum MooringVisual {
	TIMBER_POST,
	DOCKING_BOLLARD,
}

const DEFAULT_DOCKING_BOLLARD_MODEL := "res://resources/data/meshes/docks/docking_bollard.json"

## Line attachment height differs per visual; docking bollard follows `MooringPoint` cleat height.
@export var anchor_local_position: Vector3 = Vector3(0.0, 0.52, 0.0)


@export var mooring_visual: MooringVisual = MooringVisual.DOCKING_BOLLARD:
	set(v):
		if mooring_visual == v:
			return
		mooring_visual = v
		if is_node_ready():
			_rebuild()


@export var post_height: float = 1.1
@export var post_radius: float = 0.16
@export var post_color: Color = Color(0.18, 0.11, 0.06)

@export_file("*.json") var bollard_model_path: String = DEFAULT_DOCKING_BOLLARD_MODEL:
	set(v):
		bollard_model_path = v
		_rebuild_if_docking_bollard_visual()

@export_range(0.05, 4.0, 0.01) var bollard_scale: float = 1.0:
	set(v):
		bollard_scale = maxf(v, 0.05)
		_rebuild_if_docking_bollard_visual()

@export var bollard_rotation_degrees: Vector3 = Vector3(0.0, 90.0, 0.0):
	set(v):
		bollard_rotation_degrees = v
		_rebuild_if_docking_bollard_visual()

## Loose fit around `docking_bollard.json` at scale 1; scales with `bollard_scale` for rays / bump.
@export var bollard_collision_size: Vector3 = Vector3(0.62, 0.98, 0.62):
	set(v):
		bollard_collision_size = v
		_rebuild_if_docking_bollard_visual()

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

var _prompt_layer: CanvasLayer
var _prompt_label: Label


func _ready() -> void:
	_rebuild()
	if not Engine.is_editor_hint():
		add_to_group(MooringComponent.DOCK_MOORING_GROUP)
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


func _find_active_mooring() -> MooringComponent:
	var nearest: MooringComponent = null
	var best_d2 := INF
	for n in get_tree().get_nodes_in_group(MooringComponent.SHIP_MOORING_COMPONENT_GROUP):
		var mc := n as MooringComponent
		if mc == null:
			continue
		var body := mc.get_boat_rigid_body()
		if body == null:
			continue
		var d2 := global_position.distance_squared_to(body.global_position)
		if d2 < best_d2:
			best_d2 = d2
			nearest = mc
	return nearest


func _rebuild_if_docking_bollard_visual() -> void:
	if is_node_ready() and mooring_visual == MooringVisual.DOCKING_BOLLARD:
		_rebuild()


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

	match mooring_visual:
		MooringVisual.DOCKING_BOLLARD:
			_rebuild_docking_bollard()
		_:
			_rebuild_timber_post()

	if Engine.is_editor_hint():
		call_deferred("_refresh_editor_range_gizmo")


func _rebuild_docking_bollard() -> void:
	var sc := maxf(bollard_scale, 0.05)
	var box := CollisionShape3D.new()
	box.name = "PostCollision"
	var shape := BoxShape3D.new()
	shape.size = bollard_collision_size * sc
	box.shape = shape
	box.position = Vector3.UP * (shape.size.y * 0.5)
	add_child(box)

	var asm := ModelAssembler.new()
	asm.name = "DockingBollard"
	asm.build_part_colliders = false
	asm.collision_parent_path = NodePath("")
	asm.absolute_scale = sc
	asm.rotation_degrees = bollard_rotation_degrees
	asm.model_data_path = bollard_model_path
	add_child(asm)

	if Engine.is_editor_hint() and get_tree() != null:
		var esc := get_tree().edited_scene_root
		if esc != null:
			asm.owner = esc


func _rebuild_timber_post() -> void:
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



func _toggle_line() -> void:
	var mc := _find_active_mooring()
	if mc == null:
		return
	mc.call("toggle_line_from_post", self)
	_update_prompt()


func _update_prompt() -> void:
	if _prompt_label == null:
		return
	if not _player_can_interact():
		_prompt_label.visible = false
		return
	var mc := _find_active_mooring()
	_prompt_label.visible = mc != null
	if mc == null:
		return
	var action := "untie" if bool(mc.call("is_mooring_line_tied_from_post", self)) else "tie"
	_prompt_label.text = "Press F to %s mooring line" % action


func _player_can_interact() -> bool:
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
