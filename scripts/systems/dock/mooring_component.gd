class_name MooringComponent
extends Node3D

@export_enum("port", "starboard") var dock_side: String = "port"
@export var auto_select_closest_side: bool = true
@export var bow_point_path: NodePath
@export var stern_point_path: NodePath
@export var rope_radius: float = 0.045
@export var rope_color: Color = Color(0.55, 0.42, 0.25)
@export var hold_position_rate: float = 7.5
@export var hold_velocity_damp: float = 8.0

var is_moored: bool = false
var bow_line_tied: bool = false
var stern_line_tied: bool = false

var _body: RigidBody3D
var _front_post: Node
var _rear_post: Node
var _bow_point: Node3D
var _stern_point: Node3D
var _hold_transform: Transform3D
var _rope_root: Node3D


func _ready() -> void:
	_body = _resolve_boat_rigid_body()
	_ensure_rope_root()
	_resolve_mooring_points()


func _physics_process(delta: float) -> void:
	if not is_moored or _body == null:
		return

	var weight := clampf(hold_position_rate * delta, 0.0, 1.0)
	_body.global_transform = _body.global_transform.interpolate_with(_hold_transform, weight)
	_body.linear_velocity = (
		_body.linear_velocity.move_toward(Vector3.ZERO, hold_velocity_damp * delta)
	)
	_body.angular_velocity = (
		_body.angular_velocity.move_toward(Vector3.ZERO, hold_velocity_damp * delta)
	)
	_rebuild_ropes()


func moor_to_posts(front_post: Node, rear_post: Node) -> void:
	if _body == null:
		_body = _resolve_boat_rigid_body()
	if _body == null:
		return

	_front_post = front_post
	_rear_post = rear_post
	if auto_select_closest_side:
		_select_closest_dock_side(front_post, rear_post)
	else:
		_resolve_mooring_points()
	_hold_transform = _body.global_transform
	bow_line_tied = true
	stern_line_tied = true
	is_moored = true
	_rebuild_ropes()


func release_mooring() -> void:
	is_moored = false
	bow_line_tied = false
	stern_line_tied = false
	_front_post = null
	_rear_post = null
	_clear_ropes()


func toggle_line(station: String) -> bool:
	var next_tied := not is_line_tied(station)
	set_line_tied(station, next_tied)
	return next_tied


func set_line_tied(station: String, tied: bool) -> void:
	var had_any_line := bow_line_tied or stern_line_tied
	match station:
		"bow":
			bow_line_tied = tied
		"stern":
			stern_line_tied = tied
		_:
			return

	var has_any_line := bow_line_tied or stern_line_tied
	is_moored = has_any_line
	if has_any_line and not had_any_line and _body != null:
		_hold_transform = _body.global_transform
	if not has_any_line and _body != null:
		_body.linear_velocity = Vector3.ZERO
		_body.angular_velocity = Vector3.ZERO
	_rebuild_ropes()


func is_line_tied(station: String) -> bool:
	match station:
		"bow":
			return bow_line_tied
		"stern":
			return stern_line_tied
		_:
			return false


func _ensure_rope_root() -> void:
	_rope_root = get_node_or_null("Ropes") as Node3D
	if _rope_root == null:
		_rope_root = Node3D.new()
		_rope_root.name = "Ropes"
		add_child(_rope_root)


func _rebuild_ropes() -> void:
	_ensure_rope_root()
	_clear_ropes()
	if _body == null or _front_post == null or _rear_post == null:
		return

	var bow_anchor: Variant = _point_anchor(_bow_point)
	var stern_anchor: Variant = _point_anchor(_stern_point)
	if bow_anchor == null or stern_anchor == null:
		return

	if bow_line_tied:
		_add_rope("ForwardRope", bow_anchor, _post_anchor(_front_post))
	if stern_line_tied:
		_add_rope("RearRope", stern_anchor, _post_anchor(_rear_post))


func _clear_ropes() -> void:
	if _rope_root == null:
		return
	for child in _rope_root.get_children():
		child.queue_free()


func _add_rope(rope_name: String, start: Vector3, end: Vector3) -> void:
	var delta := end - start
	var length := delta.length()
	if length <= 0.01:
		return

	var mesh := CylinderMesh.new()
	mesh.top_radius = rope_radius
	mesh.bottom_radius = rope_radius
	mesh.height = length

	var rope := MeshInstance3D.new()
	rope.name = rope_name
	rope.mesh = mesh
	rope.material_override = MeshBuilder.make_material(rope_color, 0.92, 0.0)
	_rope_root.add_child(rope)

	var y_axis := delta.normalized()
	var x_axis := Vector3.UP.cross(y_axis)
	if x_axis.length_squared() < 0.001:
		x_axis = Vector3.RIGHT.cross(y_axis)
	x_axis = x_axis.normalized()
	var z_axis := x_axis.cross(y_axis).normalized()
	rope.global_transform = Transform3D(Basis(x_axis, y_axis, z_axis), start + delta * 0.5)


func _post_anchor(post: Node) -> Vector3:
	if post != null and post.has_method("get_anchor_global_position"):
		return post.call("get_anchor_global_position")
	if post is Node3D:
		return (post as Node3D).global_position
	return Vector3.ZERO


func _resolve_mooring_points() -> void:
	_bow_point = get_node_or_null(bow_point_path) as Node3D
	_stern_point = get_node_or_null(stern_point_path) as Node3D
	if _bow_point == null:
		_bow_point = _find_point(dock_side, "bow")
	if _stern_point == null:
		_stern_point = _find_point(dock_side, "stern")


func _select_closest_dock_side(front_post: Node, rear_post: Node) -> void:
	var best_side := dock_side
	var best_score := INF
	for side in ["port", "starboard"]:
		var bow_point := _find_point(side, "bow")
		var stern_point := _find_point(side, "stern")
		if bow_point == null or stern_point == null:
			continue
		var score := (
			bow_point.global_position.distance_to(_post_anchor(front_post))
			+ stern_point.global_position.distance_to(_post_anchor(rear_post))
		)
		if score < best_score:
			best_score = score
			best_side = side
			_bow_point = bow_point
			_stern_point = stern_point
	dock_side = best_side


func _resolve_boat_rigid_body() -> RigidBody3D:
	var p := get_parent()
	while p != null:
		if p is RigidBody3D:
			return p as RigidBody3D
		p = p.get_parent()
	return null


func _find_point(requested_side: String, requested_station: String) -> Node3D:
	var boat := get_parent()
	if boat == null:
		return null
	for child in boat.get_children():
		var node := child as Node
		if node != null and node.has_method("matches"):
			if bool(node.call("matches", requested_side, requested_station)):
				return node as Node3D
	return null


func _point_anchor(point: Node3D):
	if point == null:
		return null
	if point.has_method("get_anchor_global_position"):
		return point.call("get_anchor_global_position")
	return point.global_position
