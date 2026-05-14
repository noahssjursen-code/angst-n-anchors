class_name MooringComponent
extends Node3D

## Ship cleats: any `Node3D` in group `SHIP_MOORING_CLEAT_GROUP` under this vessel's
## `RigidBody3D` root. Distance is from cleat anchor to **this dock post's** anchor.
const SHIP_MOORING_CLEAT_GROUP := "ship_mooring_cleat"
## Dock bollards (`MooringPost`); any eligible for tie / prompts when this ship mooring registers.
const DOCK_MOORING_GROUP := "dock_mooring_bollard"

const _MAX_SEGMENT_POOL_PER_ROPE: int = 32

@export var rope_radius: float = 0.045
@export var rope_color: Color = Color(0.55, 0.42, 0.25)
@export_range(3, 33, 1) var rope_visual_points: int = 16

@export_group("Visual sag")
## Catenary-ish render only — not simulated stretch (`0` gives bar-taught wire look).
@export_range(0.0, 0.85, 0.005) var rope_visual_sag_fraction: float = 0.018

@export_group("Moor solve (physics integration)")
## Positional Gauss–Seidel passes per rope per tick (cheap, bounded; no impulses).
@export_range(6, 40, 1) var gauss_iterations: int = 18
## Fraction of each remaining length error removed per rope per pass (inelastic hitch).
@export_range(0.03, 0.55, 0.005) var length_correction_blend: float = 0.084
## Cap hull translation contributed by one rope in one solver pass — keeps heavy mass stable.
@export_range(0.0015, 0.08, 0.001) var max_length_step_m: float = 0.0078
## When **both** lines are fast, softly blend yaw/pitch/roll toward the berth attitude.
@export_range(0.0, 42.0, 0.2) var berth_heading_blend_hz: float = 3.8
## Exponential reduction on hull linear drift while tied (heavy body; no sling-shot).
@export_range(1.8, 28.0, 0.2) var mooring_lin_damping: float = 8.8
## Exponential reduction on yaw/pitch/heave spin while tied.
@export_range(3.8, 60.0, 0.2) var mooring_ang_damping: float = 18.5
## Slack allowance above target line length (meters). Keep small for boarding proximity.
@export_range(0.0, 6.0, 0.01) var rope_tension_slack_m: float = 0.24
## Margin below max length where tension is already considered active (stabilizes on boundary).
@export_range(0.0, 1.0, 0.005) var rope_tension_engage_margin_m: float = 0.05
## Heave-in amount applied when a line is first made fast (meters from measured tie distance).
@export_range(0.0, 20.0, 0.05) var tie_capture_retract_m: float = 2.2
## Absolute cap for tied line length (meters). 0 disables cap.
@export_range(0.0, 120.0, 0.1) var max_tied_rope_length_m: float = 6.0
## Tied lines remove only *separating* radial velocity at the cleat (tension-only, no push).
@export var kill_radial_velocity_at_cleats: bool = true
@export_range(1e-5, 0.06, 0.000001) var radial_velocity_kill_epsilon: float = 0.00072
## 0 disables cap — prefer a cap so freak numerics cannot spike one frame impulse.
@export_range(0.0, 2.8e8, 20000.0) var mooring_radial_impulse_abs_cap: float = 1.95e7
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
var _rope_root: Node3D

## Rest distances (world-space chord at tie-time) maintained under tension while moored.
var _rest_distance_bow: float = -1.0
var _rest_distance_stern: float = -1.0

## Hull-space cleat anchor points baked from the berth tree (cheap during integrate).
var _bow_cleat_body_local: Vector3 = Vector3.ZERO
var _stern_cleat_body_local: Vector3 = Vector3.ZERO

## Locked attitude when breast + spring lines are both fast (`moor_to_posts`).
var _moor_snap_q: Quaternion = Quaternion.IDENTITY

## Pooled beaded rope visuals (CylinderMesh chunks).
var _bow_rope_segments: Array[MeshInstance3D] = []
var _stern_rope_segments: Array[MeshInstance3D] = []
var _bow_rope_holder: Node3D
var _stern_rope_holder: Node3D


func _ready() -> void:
	_body = _resolve_boat_rigid_body()
	_ensure_rope_root()
	if not Engine.is_editor_hint():
		call_deferred("_register_integrate_hook")


func _exit_tree() -> void:
	_unregister_integrate_hook()


func _register_integrate_hook() -> void:
	if Engine.is_editor_hint():
		return
	_body = _resolve_boat_rigid_body()
	var boat := _body as BoatBody
	if boat != null:
		boat.mount_mooring_integrate(Callable(self, "_integrate_mooring_constraints"))


func _unregister_integrate_hook() -> void:
	if _body != null:
		var boat := _body as BoatBody
		if boat != null:
			boat.clear_mooring_integrate()


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


func _integrate_mooring_constraints(state: PhysicsDirectBodyState3D) -> void:
	if not is_moored or _body == null:
		return

	var dt := clampf(state.step, 0.00001, 0.1)

	var xf := state.transform
	xf.basis = xf.basis.orthonormalized()

	var bow_taut := false
	var stern_taut := false
	var bow_max_dist := -1.0
	var stern_max_dist := -1.0
	if bow_line_tied and _front_post != null and _rest_distance_bow > 0.004:
		bow_max_dist = _rope_max_distance_from_rest(_rest_distance_bow)
		bow_taut = (
			_line_distance_excess_from_transform(
				xf,
				_bow_cleat_body_local,
				_post_anchor(_front_post),
				bow_max_dist,
			)
			>= -rope_tension_engage_margin_m
		)
	if stern_line_tied and _rear_post != null and _rest_distance_stern > 0.004:
		stern_max_dist = _rope_max_distance_from_rest(_rest_distance_stern)
		stern_taut = (
			_line_distance_excess_from_transform(
				xf,
				_stern_cleat_body_local,
				_post_anchor(_rear_post),
				stern_max_dist,
			)
			>= -rope_tension_engage_margin_m
		)

	if bow_taut and stern_taut:
		var qh := xf.basis.get_rotation_quaternion().normalized()
		var br := berth_heading_blend_hz * dt
		xf.basis = Basis(qh.slerp(_moor_snap_q, clampf(br, 0.0, 0.985)))

	var passes := gauss_iterations
	for solve_idx in range(passes):
		if bow_line_tied and _front_post != null and bow_max_dist > 0.004:
			_gauss_correction_step(
				xf,
				_bow_cleat_body_local,
				_post_anchor(_front_post),
				bow_max_dist,
			)
		if stern_line_tied and _rear_post != null and stern_max_dist > 0.004:
			_gauss_correction_step(
				xf,
				_stern_cleat_body_local,
				_post_anchor(_rear_post),
				stern_max_dist,
			)

	state.transform = xf
	if kill_radial_velocity_at_cleats:
		_kill_tied_rope_radial_motion_at_cleats(state)
	state.linear_velocity *= exp(-mooring_lin_damping * dt)
	state.angular_velocity *= exp(-mooring_ang_damping * dt)


func _gauss_correction_step(
	xf: Transform3D,
	cleat_body_local: Vector3,
	post_w: Vector3,
	max_distance: float,
) -> void:
	if max_distance <= 0.003:
		return
	var cw := xf.origin + xf.basis * cleat_body_local
	var delta := post_w - cw
	var chord := delta.length()
	if chord < 1e-7:
		return
	var err := chord - max_distance
	if not is_finite(err):
		return
	if err <= 0.0:
		return
	var move := clampf(
		err * length_correction_blend,
		0.0,
		max_length_step_m,
	)
	if absf(move) <= 1e-11:
		return
	var axis := delta / chord
	xf.origin += axis * move


func _kill_tied_rope_radial_motion_at_cleats(state: PhysicsDirectBodyState3D) -> void:
	var inv_mass: float = state.inverse_mass
	if inv_mass <= 0.0 or not is_finite(inv_mass):
		return

	var xf: Transform3D = state.transform
	var com_world: Vector3 = xf.origin + xf.basis * _body.center_of_mass

	if bow_line_tied and _front_post != null and _rest_distance_bow > 0.004:
		var cw := xf.origin + xf.basis * _bow_cleat_body_local
		var bow_max_dist := _rope_max_distance_from_rest(_rest_distance_bow)
		_apply_radial_velocity_impulse(
			state,
			com_world,
			cw,
			_post_anchor(_front_post),
			bow_max_dist,
		)

	if stern_line_tied and _rear_post != null and _rest_distance_stern > 0.004:
		var cw := xf.origin + xf.basis * _stern_cleat_body_local
		var stern_max_dist := _rope_max_distance_from_rest(_rest_distance_stern)
		_apply_radial_velocity_impulse(
			state,
			com_world,
			cw,
			_post_anchor(_rear_post),
			stern_max_dist,
		)


## Rope tension-only: if near/above max line length, remove radial velocity that increases length.
func _apply_radial_velocity_impulse(
	state: PhysicsDirectBodyState3D,
	com_world: Vector3,
	cleat_world: Vector3,
	post_world: Vector3,
	max_distance: float,
) -> void:
	var chord := post_world - cleat_world
	var mag_sq := chord.length_squared()
	if mag_sq < 1e-14:
		return
	var chord_len := sqrt(mag_sq)
	if chord_len < max_distance - rope_tension_engage_margin_m:
		return
	var n := chord / chord_len
	var r := cleat_world - com_world

	var vn: float = state.linear_velocity.dot(n) + state.angular_velocity.dot(r.cross(n))
	# n points cleat -> post, so vn < 0 means cleat moving away (line length increasing).
	if vn >= -radial_velocity_kill_epsilon or not is_finite(vn):
		return

	var rcn := r.cross(n)
	var w := state.inverse_inertia_tensor * rcn
	var denom: float = state.inverse_mass + rcn.dot(w)
	if not is_finite(denom) or denom <= 1e-12:
		return

	var j := -vn / denom
	if mooring_radial_impulse_abs_cap > 0.0:
		j = clampf(j, -mooring_radial_impulse_abs_cap, mooring_radial_impulse_abs_cap)

	var offset_from_origin: Vector3 = cleat_world - state.transform.origin
	state.apply_impulse(n * j, offset_from_origin)


func _line_distance_excess_from_transform(
	xf: Transform3D,
	cleat_body_local: Vector3,
	post_w: Vector3,
	max_distance: float,
) -> float:
	if max_distance <= 0.0:
		return -INF
	var cw := xf.origin + xf.basis * cleat_body_local
	return post_w.distance_to(cw) - max_distance


func _rope_max_distance_from_rest(rest_distance: float) -> float:
	if rest_distance <= 0.0:
		return 0.0
	var target := maxf(rest_distance - tie_capture_retract_m, 0.6)
	var max_distance := target + rope_tension_slack_m
	if max_tied_rope_length_m > 0.0:
		max_distance = minf(max_distance, max_tied_rope_length_m)
	return max_distance


func _physics_process(_delta: float) -> void:
	if not is_moored:
		return
	_update_rope_visuals()


func moor_to_posts(front_post: Node, rear_post: Node) -> void:
	if _body == null:
		_body = _resolve_boat_rigid_body()
	if _body == null:
		return

	_front_post = front_post
	_rear_post = rear_post
	_assign_closest_cleats_to_registered_posts(true)
	bow_line_tied = true
	stern_line_tied = true
	is_moored = true
	_capture_rest_distances()


func release_mooring() -> void:
	is_moored = false
	bow_line_tied = false
	stern_line_tied = false
	_rest_distance_bow = -1.0
	_rest_distance_stern = -1.0
	_front_post = null
	_rear_post = null
	_bow_point = null
	_stern_point = null
	_hide_all_rope_segments()


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
	if forward_slot:
		bow_line_tied = tied
	else:
		stern_line_tied = tied

	var has_any_line := bow_line_tied or stern_line_tied
	is_moored = has_any_line
	if not has_any_line and _body != null:
		_body.linear_velocity = Vector3.ZERO
		_body.angular_velocity = Vector3.ZERO
		_rest_distance_bow = -1.0
		_rest_distance_stern = -1.0
		_hide_all_rope_segments()
	else:
		_capture_rest_distances()


func is_slot_tied(forward_slot: bool) -> bool:
	return bow_line_tied if forward_slot else stern_line_tied


func _capture_rest_distances() -> void:
	if _body == null:
		_body = _resolve_boat_rigid_body()

	if bow_line_tied and _bow_point != null and _front_post != null:
		_rest_distance_bow = _cleat_anchor(_bow_point).distance_to(_post_anchor(_front_post))

	if stern_line_tied and _stern_point != null and _rear_post != null:
		_rest_distance_stern = _cleat_anchor(_stern_point).distance_to(_post_anchor(_rear_post))

	_refresh_solver_cache()


func _refresh_solver_cache() -> void:
	if _body == null:
		_body = _resolve_boat_rigid_body()
	if _body == null:
		return

	var inv := _body.global_transform.affine_inverse()
	if bow_line_tied and _bow_point != null:
		_bow_cleat_body_local = inv * _cleat_anchor(_bow_point)
	if stern_line_tied and _stern_point != null:
		_stern_cleat_body_local = inv * _cleat_anchor(_stern_point)

	if bow_line_tied and stern_line_tied:
		var b_orient := _body.global_transform.basis.orthonormalized()
		_moor_snap_q = b_orient.get_rotation_quaternion().normalized()


## Mean dock post anchors (cargo ramp directional hint alongside mid-gap cues).
func tied_dock_anchors_average_world() -> Vector3:
	var pts: Array[Vector3] = []
	if bow_line_tied and _front_post != null:
		pts.append(_post_anchor(_front_post))
	if stern_line_tied and _rear_post != null:
		pts.append(_post_anchor(_rear_post))
	if pts.is_empty():
		return Vector3.ZERO
	var acc := Vector3.ZERO
	for p in pts:
		acc += p
	return acc / float(pts.size())


## Horizontal centre of each tied line (between cleat and pier); good when lines move with the hull.
func tied_gap_hint_world() -> Vector3:
	var acc := Vector3.ZERO
	var n := 0
	if bow_line_tied and _bow_point != null and _front_post != null:
		acc += (_cleat_anchor(_bow_point) + _post_anchor(_front_post)) * 0.5
		n += 1
	if stern_line_tied and _stern_point != null and _rear_post != null:
		acc += (_cleat_anchor(_stern_point) + _post_anchor(_rear_post)) * 0.5
		n += 1
	if n <= 0:
		return Vector3.ZERO
	var m := acc / float(n)
	return m


func _post_anchor(post: Node) -> Vector3:
	if post != null and post.has_method("get_anchor_global_position"):
		return post.call("get_anchor_global_position")
	if post is Node3D:
		return (post as Node3D).global_position
	return Vector3.ZERO


func get_boat_rigid_body() -> RigidBody3D:
	return _resolve_boat_rigid_body()


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


func _ensure_rope_root() -> void:
	_rope_root = get_node_or_null("Ropes") as Node3D
	if _rope_root == null:
		_rope_root = Node3D.new()
		_rope_root.name = "Ropes"
		add_child(_rope_root)

	if _bow_rope_holder == null:
		_bow_rope_holder = Node3D.new()
		_bow_rope_holder.name = "BowLine"
		_rope_root.add_child(_bow_rope_holder)
	if _stern_rope_holder == null:
		_stern_rope_holder = Node3D.new()
		_stern_rope_holder.name = "SternLine"
		_rope_root.add_child(_stern_rope_holder)


func _rope_sample_points(start: Vector3, end_: Vector3) -> PackedVector3Array:
	var n_pts := mini(maxi(rope_visual_points, 3), _MAX_SEGMENT_POOL_PER_ROPE + 1)
	var chord := end_ - start
	var span := chord.length()
	if span <= 0.001:
		return PackedVector3Array([start, end_])

	var sag := rope_visual_sag_fraction * span
	var ctrl := start.lerp(end_, 0.5)
	ctrl.y -= sag

	var out := PackedVector3Array()
	out.resize(n_pts)
	var denom := float(n_pts - 1)
	for i in range(n_pts):
		var t := float(i) / denom
		var omt := 1.0 - t
		out[i] = (
			start * (omt * omt)
			+ ctrl * (2.0 * omt * t)
			+ end_ * (t * t)
		)
	return out


func _ensure_segment_holder_pool(
	parent: Node3D,
	pool: Array[MeshInstance3D],
	needed_segments: int,
) -> void:
	while pool.size() < needed_segments:
		var cyl := MeshInstance3D.new()
		cyl.name = "Seg_%d" % pool.size()
		var mesh := CylinderMesh.new()
		mesh.top_radius = rope_radius
		mesh.bottom_radius = rope_radius
		mesh.height = 0.05
		cyl.mesh = mesh
		cyl.material_override = MeshBuilder.make_material(rope_color, 0.92, 0.0)
		parent.add_child(cyl)
		pool.append(cyl)


func _orient_cylinder(mi: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var delta := b - a
	var l := delta.length()
	if l <= 0.001:
		mi.visible = false
		return
	mi.visible = true
	var ys := delta / l
	var xs := Vector3.UP.cross(ys)
	if xs.length_squared() < 0.0001:
		xs = Vector3.RIGHT.cross(ys)
	xs = xs.normalized()
	var zs := xs.cross(ys).normalized()

	var mh := mi.mesh as CylinderMesh
	if mh != null:
		mh.height = l
	mi.global_transform = Transform3D(Basis(xs, ys, zs), (a + b) * 0.5)


func _update_rope_visuals() -> void:
	_ensure_rope_root()
	if bow_line_tied and _bow_point != null and _front_post != null:
		var a := _cleat_anchor(_bow_point)
		var b := _post_anchor(_front_post)
		_draw_curve_on_holder(_bow_rope_holder, _bow_rope_segments, a, b)
	elif _bow_rope_holder != null:
		_hide_rope_segments(_bow_rope_segments)

	if stern_line_tied and _stern_point != null and _rear_post != null:
		var a2 := _cleat_anchor(_stern_point)
		var b2 := _post_anchor(_rear_post)
		_draw_curve_on_holder(_stern_rope_holder, _stern_rope_segments, a2, b2)
	elif _stern_rope_holder != null:
		_hide_rope_segments(_stern_rope_segments)


func _draw_curve_on_holder(
	holder: Node3D,
	pool: Array[MeshInstance3D],
	start: Vector3,
	end_: Vector3,
) -> void:
	var pts := _rope_sample_points(start, end_)
	var segment_count := maxi(pts.size() - 1, 1)
	if segment_count > _MAX_SEGMENT_POOL_PER_ROPE:
		push_warning(
			"MooringComponent: rope_visual_points too high (%d)." % pts.size(),
		)
		return

	_ensure_segment_holder_pool(holder, pool, segment_count)

	for idx in range(segment_count):
		_orient_cylinder(pool[idx], pts[idx], pts[idx + 1])

	for j in range(segment_count, pool.size()):
		pool[j].visible = false


func _hide_rope_segments(pool: Array[MeshInstance3D]) -> void:
	for seg in pool:
		seg.visible = false


func _hide_all_rope_segments() -> void:
	if _bow_rope_holder != null:
		_hide_rope_segments(_bow_rope_segments)
	if _stern_rope_holder != null:
		_hide_rope_segments(_stern_rope_segments)

