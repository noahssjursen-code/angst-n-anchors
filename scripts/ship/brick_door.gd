class_name BrickDoor
extends Node3D

## Interactable door on a `block_door` / `block_door_double` brick.
## Look at a leaf (camera ray) + F to open / close.
## Closed = walk blocker; open = pass-through.
## Double doors also drive `DoorHingeR` (opposite swing) when present.

const GROUP := "brick_door"
const OPEN_ANGLE_DEG := -95.0
const OPEN_ANGLE_R_DEG := 95.0
const ANIM_SEC := 0.28
const LAYER_WORLD := 1

@export var interact_range: float = 3.5
@export var prompt_open: String = "Press F — open door"
@export var prompt_close: String = "Press F — close door"

var _open := false
var _animating := false
var _hinge: Node3D
var _hinge_r: Node3D
var _leaf: Node3D
var _leaf_r: Node3D
var _boat: BoatBody
var _leaf_body: StaticBody3D
var _collider: CollisionShape3D
var _interact_area: Area3D
var _interact_area_r: Area3D
var _prompt_layer: CanvasLayer
var _prompt_label: Label
var _yaw_deg: float = 0.0
var _boat_local: Vector3 = Vector3.ZERO
var _leaf_size: Vector3 = Vector3(1.8, 2.8, 0.1)


func configure(
	boat: BoatBody,
	boat_local: Vector3,
	yaw_deg: float,
	leaf_size: Vector3,
) -> void:
	## `boat` may be null for land buildings — leaf collider is owned locally then.
	_boat = boat
	_boat_local = boat_local
	_yaw_deg = yaw_deg
	_leaf_size = leaf_size


func _ready() -> void:
	add_to_group(GROUP)
	var parent := get_parent()
	_hinge = parent.get_node_or_null("DoorHinge") as Node3D if parent != null else null
	_leaf = null if _hinge == null else _hinge.get_node_or_null("DoorLeaf") as Node3D
	_hinge_r = parent.get_node_or_null("DoorHingeR") as Node3D if parent != null else null
	_leaf_r = null if _hinge_r == null else _hinge_r.get_node_or_null("DoorLeaf") as Node3D
	if _hinge == null or _leaf == null:
		push_warning("BrickDoor: missing DoorHinge / DoorLeaf under parent")
		return
	_ensure_prompt_ui()
	_ensure_interact_area()
	_ensure_collider()
	_apply_open_state(false, true)


func _process(_delta: float) -> void:
	_update_prompt()


func _unhandled_input(event: InputEvent) -> void:
	if _animating:
		return
	if not event.is_action_pressed("interact"):
		return
	if not _can_interact():
		return
	toggle()
	get_viewport().set_input_as_handled()


func toggle() -> void:
	set_open(not _open)


func set_open(want_open: bool) -> void:
	if _animating or _hinge == null:
		return
	if want_open == _open:
		return
	_open = want_open
	_apply_open_state(_open, false)


func is_open() -> bool:
	return _open


func _can_interact() -> bool:
	## Camera-forward ray must hit this door's interact volume (not just stand near it).
	var player := _nearest_player_in_range()
	if player == null or _interact_area == null:
		return false
	var camera := player.get_node_or_null("Camera3D") as Camera3D
	if camera == null:
		return false
	var from := camera.global_position
	var to := from - camera.global_transform.basis.z * interact_range
	var space := get_world_3d().direct_space_state

	## Prefer a leaf Area so the closed walk-slab doesn't steal the hit.
	var area_q := PhysicsRayQueryParameters3D.create(from, to)
	area_q.exclude = [player.get_rid()]
	area_q.collide_with_areas = true
	area_q.collide_with_bodies = false
	var area_hit := space.intersect_ray(area_q)
	var hit_area := area_hit.get("collider") as Area3D if not area_hit.is_empty() else null
	if hit_area == null or (hit_area != _interact_area and hit_area != _interact_area_r):
		return false

	## Block if a solid body is clearly closer (wall / other brick in front).
	var body_q := PhysicsRayQueryParameters3D.create(from, to)
	body_q.exclude = [player.get_rid()]
	body_q.collide_with_areas = false
	body_q.collide_with_bodies = true
	var body_hit := space.intersect_ray(body_q)
	if body_hit.is_empty():
		return true
	var area_dist := from.distance_to(area_hit.position as Vector3)
	var body_dist := from.distance_to(body_hit.position as Vector3)
	if body_dist + 0.05 < area_dist and not _is_own_door_body_hit(body_hit):
		return false
	return true


func _is_own_door_body_hit(hit: Dictionary) -> bool:
	## Closed leaf walk collider — treat as this door if it is ours / near a leaf.
	if _leaf == null or not is_instance_valid(_leaf):
		return false
	var collider := hit.get("collider") as Node
	if collider == null:
		return false
	if _leaf_body != null and is_instance_valid(_leaf_body) and collider == _leaf_body:
		return true
	var walk: Node = null if _boat == null else _boat.get_walk_deck()
	if collider != walk and collider != _boat:
		return false
	var hit_pos: Vector3 = hit.position as Vector3
	if hit_pos.distance_to(_leaf.global_position) <= 1.6:
		return true
	if _leaf_r != null and is_instance_valid(_leaf_r):
		return hit_pos.distance_to(_leaf_r.global_position) <= 1.6
	return false


func _nearest_player_in_range() -> CharacterBody3D:
	if not is_inside_tree():
		return null
	var hinge_pos := _hinge.global_position if _hinge != null else global_position
	if _hinge_r != null and is_instance_valid(_hinge_r):
		hinge_pos = (hinge_pos + _hinge_r.global_position) * 0.5
	for node in get_tree().get_nodes_in_group("player"):
		var body := node as CharacterBody3D
		if body == null:
			continue
		if hinge_pos.distance_to(body.global_position) <= interact_range:
			return body
	return null


func _apply_open_state(open: bool, instant: bool) -> void:
	var target := OPEN_ANGLE_DEG if open else 0.0
	var target_r := OPEN_ANGLE_R_DEG if open else 0.0
	if _collider != null and is_instance_valid(_collider):
		_collider.disabled = open
	if instant or _hinge == null:
		_hinge.rotation_degrees.y = target
		if _hinge_r != null and is_instance_valid(_hinge_r):
			_hinge_r.rotation_degrees.y = target_r
		_animating = false
		return
	_animating = true
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_CUBIC)
	tw.set_ease(Tween.EASE_OUT)
	tw.set_parallel(true)
	tw.tween_property(_hinge, "rotation_degrees:y", target, ANIM_SEC)
	if _hinge_r != null and is_instance_valid(_hinge_r):
		tw.tween_property(_hinge_r, "rotation_degrees:y", target_r, ANIM_SEC)
	tw.finished.connect(func() -> void: _animating = false)


func _ensure_interact_area() -> void:
	## Area on each leaf so the look-target swings open/closed with the door.
	## Slightly thicker than the mesh so the ray hits this before the walk brick.
	var per_leaf_w := _leaf_size.x
	if _leaf_r != null:
		per_leaf_w = maxf(_leaf_size.x * 0.5, 0.4)
	_interact_area = _make_leaf_interact_area("DoorInteractArea", per_leaf_w)
	_leaf.add_child(_interact_area)
	if _leaf_r != null and is_instance_valid(_leaf_r):
		_interact_area_r = _make_leaf_interact_area("DoorInteractAreaR", per_leaf_w)
		_leaf_r.add_child(_interact_area_r)


func _make_leaf_interact_area(area_name: String, width: float) -> Area3D:
	var area := Area3D.new()
	area.name = area_name
	area.collision_layer = LAYER_WORLD
	area.collision_mask = 0
	area.monitoring = false
	area.monitorable = true
	var col := CollisionShape3D.new()
	col.name = "Shape"
	var box := BoxShape3D.new()
	box.size = Vector3(
		maxf(width, 0.4),
		maxf(_leaf_size.y, 0.8),
		maxf(_leaf_size.z, 0.22),
	)
	col.shape = box
	area.add_child(col)
	return area


func _ensure_collider() -> void:
	var size := Vector3(_leaf_size.x * 0.95, _leaf_size.y * 0.95, maxf(_leaf_size.z, 0.12))
	if _boat != null and is_instance_valid(_boat):
		## Thin slab in the doorway when closed — disabled while open.
		var basis := Basis.from_euler(Vector3(0.0, deg_to_rad(_yaw_deg), 0.0))
		var leaf_center_local := _boat_local + basis * Vector3(0.0, 0.0, 0.0)
		_collider = _boat.add_walk_brick_collider(
			"door_%d_%d_%d" % [int(_boat_local.x * 10.0), int(_boat_local.y * 10.0), int(_boat_local.z * 10.0)],
			leaf_center_local,
			size,
			_yaw_deg,
		)
		return
	## Land building: own static leaf blocker under this door node.
	_leaf_body = StaticBody3D.new()
	_leaf_body.name = "DoorLeafBody"
	_leaf_body.collision_layer = LAYER_WORLD
	_leaf_body.collision_mask = 0
	_collider = CollisionShape3D.new()
	_collider.name = "Shape"
	var box := BoxShape3D.new()
	box.size = size
	_collider.shape = box
	_leaf_body.add_child(_collider)
	add_child(_leaf_body)


func _ensure_prompt_ui() -> void:
	_prompt_layer = CanvasLayer.new()
	_prompt_layer.name = "DoorPromptLayer"
	_prompt_layer.layer = 20
	add_child(_prompt_layer)
	_prompt_label = Label.new()
	_prompt_label.visible = false
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.add_theme_font_size_override("font_size", 18)
	_prompt_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt_label.offset_left = -220.0
	_prompt_label.offset_right = 220.0
	_prompt_label.offset_top = -148.0
	_prompt_label.offset_bottom = -108.0
	_prompt_label.add_theme_color_override("font_color", HudStyle.C_AMBER)
	_prompt_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.85))
	_prompt_label.add_theme_constant_override("shadow_offset_x", 1)
	_prompt_label.add_theme_constant_override("shadow_offset_y", 1)
	_prompt_label.add_theme_constant_override("shadow_as_outline", 1)
	_prompt_layer.add_child(_prompt_label)


func _update_prompt() -> void:
	if _prompt_label == null:
		return
	var show := _can_interact() and not _animating
	_prompt_label.visible = show
	if show:
		_prompt_label.text = prompt_close if _open else prompt_open
