class_name MooringComponent
extends Node3D

## Ship cleats: any `Node3D` in group `SHIP_MOORING_CLEAT_GROUP` under this vessel's
## `RigidBody3D` root. Distance is from cleat anchor to **this dock post's** anchor.
const SHIP_MOORING_CLEAT_GROUP := "ship_mooring_cleat"
## Dock bollards (`MooringPost`); any eligible for tie / prompts when this ship mooring registers.
const DOCK_MOORING_GROUP := "dock_mooring_bollard"

@export var rope_radius: float = 0.045
@export var rope_color: Color = Color(0.55, 0.42, 0.25)
@export var hold_position_rate: float = 7.5
@export var hold_velocity_damp: float = 8.0
## Used only when estimating bow/stern with no typed cleats in `SHIP_MOORING_CLEAT_GROUP`.
@export var fallback_hull_half_length_m: float = 11.5

## Rope from **front** dock post (slot 0). Name kept for save compatibility.
var bow_line_tied: bool = false
## Rope from **rear** dock post (slot 1).
var stern_line_tied: bool = false

var is_moored: bool = false

var _body: RigidBody3D
var _front_post: Node
var _rear_post: Node
## Cleat Node3D used for front-post rope — picked by geometry at tie time.
var _bow_point: Node3D
## Cleat for rear-post rope.
var _stern_point: Node3D
var _hold_transform: Transform3D
var _rope_root: Node3D


func _ready() -> void:
	_body = _resolve_boat_rigid_body()
	_ensure_rope_root()


## World anchors used to rank dock posts (closest-to-bow vs closest-to-stern).
func bow_and_stern_reference_world() -> Array[Vector3]:
	var bow_acc := Vector3.ZERO
	var stern_acc := Vector3.ZERO
	var nb := 0
	var ns := 0
	for cleat in _ship_cleat_nodes():
		var sv = cleat.get("station")
		if sv == null:
			continue
		var station := str(sv)
		match station:
			"bow":
				bow_acc += _cleat_anchor(cleat)
				nb += 1
			"stern":
				stern_acc += _cleat_anchor(cleat)
				ns += 1

	if _body == null:
		_body = _resolve_boat_rigid_body()
	if _body == null:
		return [Vector3.ZERO, Vector3.ZERO]

	var mid := _body.global_position
	var zb := _body.global_transform.basis.z
	var bow_w: Vector3
	var stern_w: Vector3
	if nb > 0:
		bow_w = bow_acc / float(nb)
	else:
		bow_w = mid - zb * fallback_hull_half_length_m
	if ns > 0:
		stern_w = stern_acc / float(ns)
	else:
		stern_w = mid + zb * fallback_hull_half_length_m
	return [bow_w, stern_w]


static func dock_post_anchor_world(post: Node) -> Vector3:
	if post != null and post.has_method("get_anchor_global_position"):
		return post.call("get_anchor_global_position")
	if post is Node3D:
		return (post as Node3D).global_position
	return Vector3.ZERO


static func pick_two_dock_posts_for_ship(
	mooring: MooringComponent,
	tree: SceneTree,
) -> Array:
	if tree == null or mooring == null:
		return [null, null]
	var refs: Array = mooring.bow_and_stern_reference_world()
	if refs.size() < 2:
		return [null, null]
	var bow_ref: Vector3 = refs[0]
	var stern_ref: Vector3 = refs[1]

	var cand: Array[Node] = []
	for n in tree.get_nodes_in_group(DOCK_MOORING_GROUP):
		if n.has_method("get_anchor_global_position"):
			cand.append(n)
	if cand.size() < 2:
		return [null, null]

	var best_bow_p: Node = null
	var best_bow_d := INF
	for n in cand:
		var d_sq := bow_ref.distance_squared_to(dock_post_anchor_world(n))
		if d_sq < best_bow_d:
			best_bow_d = d_sq
			best_bow_p = n

	var best_stern_p: Node = null
	var best_stern_d := INF
	for n in cand:
		if n == best_bow_p:
			continue
		var d_sq := stern_ref.distance_squared_to(dock_post_anchor_world(n))
		if d_sq < best_stern_d:
			best_stern_d = d_sq
			best_stern_p = n
	return [best_bow_p, best_stern_p]


static func register_mooring_on_all_dock_bollards(tree: SceneTree, mooring: Node) -> void:
	if tree == null or mooring == null:
		return
	for n in tree.get_nodes_in_group(DOCK_MOORING_GROUP):
		if n.has_method("register_mooring_component"):
			n.call("register_mooring_component", mooring)


static func clear_mooring_on_all_dock_bollards(tree: SceneTree, mooring: Node) -> void:
	if tree == null:
		return
	for n in tree.get_nodes_in_group(DOCK_MOORING_GROUP):
		if n.has_method("clear_mooring_component"):
			n.call("clear_mooring_component", mooring)


func _dock_slot_forward_for_post(post: Node) -> bool:
	if post == _front_post:
		return true
	if post == _rear_post:
		return false
	var refs := bow_and_stern_reference_world()
	var a := dock_post_anchor_world(post)
	return a.distance_squared_to(refs[0]) <= a.distance_squared_to(refs[1])


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
	_assign_closest_cleats_to_registered_posts(true)
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
	_bow_point = null
	_stern_point = null
	_clear_ropes()


func is_mooring_line_tied_from_post(post: Node) -> bool:
	if post != null and post == _front_post:
		return bow_line_tied
	if post != null and post == _rear_post:
		return stern_line_tied
	return false


func toggle_line_from_post(post: Node) -> bool:
	if _body == null:
		_body = _resolve_boat_rigid_body()
	if not post.is_in_group(DOCK_MOORING_GROUP):
		push_warning(
			"MooringComponent: expected a dock bollard (group \"" + DOCK_MOORING_GROUP + "\")."
		)
		return false

	var forward_slot: bool = _dock_slot_forward_for_post(post)
	var next_tied := not is_slot_tied(forward_slot)

	if next_tied:
		if forward_slot:
			_front_post = post
		else:
			_rear_post = post

		var exclude: Node3D = null
		if forward_slot and stern_line_tied and _stern_point != null:
			exclude = _stern_point
		elif not forward_slot and bow_line_tied and _bow_point != null:
			exclude = _bow_point

		var cleats := _ship_cleat_nodes()
		if cleats.is_empty():
			push_warning(
				"MooringComponent: no cleats — add MooringPoint (or nodes in group '"
				+ SHIP_MOORING_CLEAT_GROUP
				+ "') under the boat.",
			)
			return false

		var tgt := _post_anchor(post)
		var pick := _closest_cleat_to(tgt, cleats, exclude)
		if pick == null:
			pick = _closest_cleat_to(tgt, cleats, null)
		if pick == null:
			return false
		if forward_slot:
			_bow_point = pick
		else:
			_stern_point = pick

	set_line_tied(forward_slot, next_tied)
	return next_tied


func set_line_tied(forward_slot: bool, tied: bool) -> void:
	var had_any_line := bow_line_tied or stern_line_tied
	if forward_slot:
		bow_line_tied = tied
	else:
		stern_line_tied = tied

	var has_any_line := bow_line_tied or stern_line_tied
	is_moored = has_any_line
	if has_any_line and not had_any_line and _body != null:
		_hold_transform = _body.global_transform
	if not has_any_line and _body != null:
		_body.linear_velocity = Vector3.ZERO
		_body.angular_velocity = Vector3.ZERO
	_rebuild_ropes()


func is_slot_tied(forward_slot: bool) -> bool:
	return bow_line_tied if forward_slot else stern_line_tied


func _ensure_rope_root() -> void:
	_rope_root = get_node_or_null("Ropes") as Node3D
	if _rope_root == null:
		_rope_root = Node3D.new()
		_rope_root.name = "Ropes"
		add_child(_rope_root)


func _rebuild_ropes() -> void:
	_ensure_rope_root()
	_clear_ropes()
	if _body == null:
		return

	if bow_line_tied and _front_post != null and _bow_point != null:
		_add_rope(
			"ForwardRope",
			_point_anchor_vector(_bow_point),
			_post_anchor(_front_post),
		)
	if stern_line_tied and _rear_post != null and _stern_point != null:
		_add_rope(
			"RearRope",
			_point_anchor_vector(_stern_point),
			_post_anchor(_rear_post),
		)


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


func _resolve_boat_rigid_body() -> RigidBody3D:
	var p := get_parent()
	while p != null:
		if p is RigidBody3D:
			return p as RigidBody3D
		p = p.get_parent()
	return null


func _ship_cleat_nodes() -> Array[Node3D]:
	var out: Array[Node3D] = []
	if _body == null:
		return out
	for node in get_tree().get_nodes_in_group(SHIP_MOORING_CLEAT_GROUP):
		var n := node as Node3D
		if n == null:
			continue
		if _body.is_ancestor_of(n):
			out.append(n)
	return out


func _assign_closest_cleats_to_registered_posts(require_distinct_when_possible: bool) -> void:
	var cleats := _ship_cleat_nodes()
	if cleats.is_empty():
		push_warning(
			"MooringComponent: no cleats — add nodes in group '"
			+ SHIP_MOORING_CLEAT_GROUP
			+ "' parented under the vessel RigidBody (e.g. MooringPoint).",
		)
		return

	var pf := _post_anchor(_front_post)
	var pr := _post_anchor(_rear_post)

	_bow_point = _closest_cleat_to(pf, cleats, null)
	var exclude_second: Node3D = (
		_bow_point if require_distinct_when_possible and cleats.size() > 1 else null
	)
	_stern_point = _closest_cleat_to(pr, cleats, exclude_second)
	if _stern_point == null:
		_stern_point = _closest_cleat_to(pr, cleats, null)


func _closest_cleat_to(
	world_target: Vector3,
	candidates: Array[Node3D],
	exclude: Node3D,
) -> Node3D:
	var best: Node3D = null
	var best_d := INF
	for candidate in candidates:
		if exclude != null and candidate == exclude:
			continue
		var d := world_target.distance_squared_to(_cleat_anchor(candidate))
		if d < best_d:
			best_d = d
			best = candidate
	return best


func _cleat_anchor(point: Node3D) -> Vector3:
	if point.has_method("get_anchor_global_position"):
		return point.call("get_anchor_global_position")
	return point.global_position


func _point_anchor_vector(point: Node3D) -> Vector3:
	if point == null:
		return Vector3.ZERO
	return _cleat_anchor(point)

