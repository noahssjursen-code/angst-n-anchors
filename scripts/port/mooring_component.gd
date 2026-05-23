class_name MooringComponent
extends Node3D

## Emitted when a `toggle_line_from_post` call is rejected (e.g. lines on
## different berths). HUDs subscribe via the `LocalPlayerView.helmed_boat`
## reference to surface a brief toast to the player.
signal mooring_rejected(reason: String)

## Ship cleats: any `Node3D` in group `SHIP_MOORING_CLEAT_GROUP` under this vessel's
## `RigidBody3D` root. Distance is from cleat anchor to **this dock post's** anchor.
const SHIP_MOORING_CLEAT_GROUP := "ship_mooring_cleat"
## Dock bollards (`MooringPost`); any eligible for tie / prompts when this ship mooring registers.
const DOCK_MOORING_GROUP := "dock_mooring_bollard"
## Group that MooringComponent joins at runtime so new bollards can auto-register.
const SHIP_MOORING_COMPONENT_GROUP := "ship_mooring_component"

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
## Set when a tie is rejected (e.g. lines on different berths); cleared on success.
var last_mooring_reject: String = ""


func _ready() -> void:
	_body = _resolve_boat_rigid_body()
	_ensure_rope_root()
	if not Engine.is_editor_hint():
		add_to_group(SHIP_MOORING_COMPONENT_GROUP)
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


static func dock_post_anchor_world(post: Node) -> Vector3:
	if post != null and post.has_method("get_anchor_global_position"):
		return post.call("get_anchor_global_position")
	if post is Node3D:
		return (post as Node3D).global_position
	return Vector3.ZERO


## Each cleat finds its nearest bollard: bow cleats → front post, stern cleats → rear post.
func auto_moor(tree: SceneTree) -> void:
	auto_moor_at_berth(tree, -1)


## Prefer bollards on the same berth slot so lines do not yank the ship along the quay.
func auto_moor_at_berth(tree: SceneTree, berth_index: int) -> void:
	if tree == null:
		return
	var posts: Array[Node] = _berth_bollard_candidates(tree, berth_index)
	if posts.size() < 2:
		if berth_index >= 0:
			push_warning(
				"MooringComponent: fewer than 2 bollards for berth %d — using nearest pair"
				% (berth_index + 1)
			)
		posts = []
		for n in tree.get_nodes_in_group(DOCK_MOORING_GROUP):
			if n.has_method("get_anchor_global_position"):
				posts.append(n)
	if posts.size() < 2:
		push_warning("MooringComponent: need ≥2 bollards to auto-moor")
		return
	var cleats := _ship_cleat_nodes()
	if cleats.is_empty():
		push_warning("MooringComponent: no cleats for auto-moor")
		return
	var bow_pos   := _mean_cleat_position(cleats, "bow")
	var stern_pos := _mean_cleat_position(cleats, "stern")
	var front := _closest_post_to(bow_pos,   posts, null)
	var rear  := _closest_post_to(stern_pos, posts, front)
	if front == null or rear == null:
		push_warning("MooringComponent: could not pair bollards for auto-moor")
		return
	moor_to_posts(front, rear)


func _berth_bollard_candidates(tree: SceneTree, berth_index: int) -> Array[Node]:
	var out: Array[Node] = []
	if berth_index < 0:
		return out
	if _body == null:
		_body = _resolve_boat_rigid_body()
	if _body == null:
		return out
	var dock := _find_port_dock()
	if dock == null:
		return out
	var berth_cx := dock.get_berth_cx(berth_index)
	var slot_half := dock.get_berth_slot_half_width(berth_index)
	var reach := slot_half + 4.0
	for n in tree.get_nodes_in_group(DOCK_MOORING_GROUP):
		if not n.has_method("get_anchor_global_position"):
			continue
		var local := dock.to_local(dock_post_anchor_world(n))
		if absf(local.x - berth_cx) <= reach:
			out.append(n)
	return out


func _mean_cleat_position(cleats: Array[Node3D], station_filter: String) -> Vector3:
	var acc := Vector3.ZERO
	var count := 0
	for c in cleats:
		if c.get("station") == station_filter:
			acc += _cleat_anchor(c)
			count += 1
	if count == 0:
		for c in cleats:
			acc += _cleat_anchor(c)
		count = cleats.size()
	return acc / float(count) if count > 0 else Vector3.ZERO


func _closest_post_to(target: Vector3, posts: Array, exclude: Node) -> Node:
	var best: Node = null
	var best_d2 := INF
	for p in posts:
		if p == exclude:
			continue
		var d2 := target.distance_squared_to(dock_post_anchor_world(p))
		if d2 < best_d2:
			best_d2 = d2
			best = p
	return best


func _dock_slot_forward_for_post(post: Node) -> bool:
	if _front_post != null and post == _front_post:
		return true
	if _rear_post != null and post == _rear_post:
		return false
	return not bow_line_tied


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
	_sync_berth_with_dock()


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
	_sync_berth_with_dock()


func is_mooring_line_tied_from_post(post: Node) -> bool:
	if post != null and post == _front_post:
		return bow_line_tied
	if post != null and post == _rear_post:
		return stern_line_tied
	return false


func toggle_line_from_post(post: Node) -> bool:
	last_mooring_reject = ""
	if _body == null:
		_body = _resolve_boat_rigid_body()
	if not post.is_in_group(DOCK_MOORING_GROUP):
		push_warning(
			"MooringComponent: expected a dock bollard (group \"" + DOCK_MOORING_GROUP + "\")."
		)
		return false

	var forward_slot: bool = _dock_slot_forward_for_post(post)
	var next_tied := not is_slot_tied(forward_slot)

	if next_tied and _would_split_berths(post):
		last_mooring_reject = "Both lines must be made fast within the same berth."
		mooring_rejected.emit(last_mooring_reject)
		return false

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
	_sync_berth_with_dock()


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


func _dock_from_node(node: Node) -> PortDock:
	var n: Node = node
	while n != null:
		if n is PortDock:
			return n as PortDock
		n = n.get_parent()
	return null


## Resolve the quay you are tied to. Sailed-in vessels live under World, not
## PortPlot — walk up from the bollard posts, not only from the ship hierarchy.
func _find_port_dock() -> PortDock:
	if bow_line_tied and _front_post != null:
		var bow_dock := _dock_from_node(_front_post)
		if bow_dock != null:
			return bow_dock
	if stern_line_tied and _rear_post != null:
		var stern_dock := _dock_from_node(_rear_post)
		if stern_dock != null:
			return stern_dock
	var n: Node = get_parent()
	while n != null:
		if n is PortDock:
			return n as PortDock
		if n is PortPlot:
			return (n as PortPlot).get_node_or_null("PortDock") as PortDock
		n = n.get_parent()
	return null


func _sync_berth_with_dock() -> void:
	var dock := _find_port_dock()
	if dock == null:
		return
	var ship := get_boat_rigid_body() as BoatBody
	if ship == null:
		return
	var owner_id: String = PortDock.local_player_owner_id()
	if is_moored and bow_line_tied and stern_line_tied:
		if _mooring_splits_berths(dock):
			dock.unregister_ship(ship)
			return
		var idx: int = _resolved_berth_index(dock, ship)
		if idx >= 0:
			dock.register_ship_at_berth(idx, ship, owner_id)
			var plot := dock.get_parent() as PortPlot
			if plot != null and plot.has_method("respawn_staged_cargo"):
				plot.call_deferred("respawn_staged_cargo")
	else:
		dock.unregister_ship(ship)


func _berth_index_for_post(dock: PortDock, post: Node) -> int:
	if dock == null or post == null:
		return -1
	return dock.find_berth_index_at_position(_post_anchor(post))


func _would_split_berths(new_post: Node) -> bool:
	var new_dock := _dock_from_node(new_post)
	if new_dock == null:
		return false
	var new_berth := _berth_index_for_post(new_dock, new_post)
	if new_berth < 0:
		return false
	var other_post: Node = null
	if bow_line_tied and _front_post != null and new_post != _front_post:
		other_post = _front_post
	elif stern_line_tied and _rear_post != null and new_post != _rear_post:
		other_post = _rear_post
	if other_post == null:
		return false
	var other_dock := _dock_from_node(other_post)
	if other_dock == null:
		return false
	if other_dock != new_dock:
		return true
	var other_berth := _berth_index_for_post(other_dock, other_post)
	return other_berth >= 0 and other_berth != new_berth


func _mooring_splits_berths(dock: PortDock) -> bool:
	if not bow_line_tied or not stern_line_tied:
		return false
	if _front_post == null or _rear_post == null:
		return false
	var bow_berth := _berth_index_for_post(dock, _front_post)
	var stern_berth := _berth_index_for_post(dock, _rear_post)
	return bow_berth >= 0 and stern_berth >= 0 and bow_berth != stern_berth


func _resolved_berth_index(dock: PortDock, ship: BoatBody) -> int:
	var bow_berth := _berth_index_for_post(dock, _front_post) if _front_post != null else -1
	var stern_berth := _berth_index_for_post(dock, _rear_post) if _rear_post != null else -1
	if bow_berth >= 0 and bow_berth == stern_berth:
		return bow_berth
	if bow_berth >= 0 and stern_berth < 0:
		return bow_berth
	if stern_berth >= 0 and bow_berth < 0:
		return stern_berth
	if ship != null:
		return dock.find_berth_index_at_position(ship.global_position)
	return -1


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
