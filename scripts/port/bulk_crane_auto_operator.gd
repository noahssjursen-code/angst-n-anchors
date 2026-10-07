class_name BulkCraneAutoOperator
extends Node

## Drives parent BulkCrane along an ellipse between mound (A) and cargo hold (B).
## Bucket IK (slew + boom + hoist) tracks a single point that moves along that arc.

enum Operation { NONE, LOAD, UNLOAD }
enum Phase {
	IDLE,
	TO_A, ## travel to pickup, raised, jaws OPEN
	LOWER_A, ## hoist down onto pickup, jaws OPEN
	GRAB_A, ## close jaws + take cargo
	RAISE_A, ## hoist up loaded, jaws CLOSED
	ARC_TO_B, ## travel to drop, raised, jaws CLOSED
	LOWER_B, ## hoist down onto drop, jaws CLOSED
	DUMP_B, ## open jaws + release cargo
	RAISE_B, ## hoist up empty, jaws OPEN
	ARC_TO_A, ## travel back, raised, jaws OPEN
	NEXT,
}

const ARC_HEIGHT_M := 8.0
const ELLIPSE_SPEED := 0.18 ## fraction of arc per second
const NEAR_M := 4.0
const WORK_S := 0.55
const TIMEOUT_S := 16.0
const DUMP_OPEN_FRAC := 0.5
const ELLIPSE_GIZMO_SEGS := 24
const AIM_SMOOTH := 4.0 ## higher = snappier smoothed aim

signal job_started(operation: Operation, commodity_id: String)
signal cycle_completed(operation: Operation, cycle_index: int)
signal job_finished(operation: Operation, cycles_completed: int)
signal job_stopped()
signal job_failed(reason: String)
signal phase_changed(phase: Phase)

@export var max_cycles := 0
## Local preference; still gated by DebugHud world gizmos (F3 → G).
@export var show_target_gizmos := true
@export var arc_height_m := ARC_HEIGHT_M
@export var ellipse_speed := ELLIPSE_SPEED

var operation := Operation.NONE

var _crane: BulkCrane
var _ship: BoatBody
var _hold: BulkHoldComponent
var _mound: OreMound
var _commodity_id := ""
var _phase := Phase.IDLE
var _timer := 0.0
var _cycles := 0
var _active := false
var _did_act := false
## Ellipse parameter: 0 = point A (pickup), 1 = point B (drop).
var _t := 0.0
var _smooth_aim := Vector3.ZERO
var _aim_initialized := false

var _gizmos: Node3D
var _g_a: MeshInstance3D
var _g_b: MeshInstance3D
var _g_aim: MeshInstance3D
var _g_bucket: MeshInstance3D
var _g_gap: MeshInstance3D
var _g_ellipse: Array[MeshInstance3D] = []
var _g_holds: Array[MeshInstance3D] = []


func _ready() -> void:
	add_to_group("bulk_crane_auto")
	_crane = get_parent() as BulkCrane
	if _crane == null:
		push_warning("BulkCraneAutoOperator: parent must be BulkCrane")
	_build_gizmos()
	show_target_gizmos = WorldGizmos.is_layer_enabled(WorldGizmos.LAYER_CRANES)
	var hud := get_node_or_null("/root/DebugHud")
	if hud != null and hud.has_signal("world_gizmos_changed"):
		if not hud.world_gizmos_changed.is_connected(set_show_target_gizmos):
			hud.world_gizmos_changed.connect(set_show_target_gizmos)


func set_show_target_gizmos(enabled: bool) -> void:
	show_target_gizmos = enabled
	_update_gizmos()


func is_active() -> bool:
	return _active


func get_operation() -> Operation:
	return operation


func get_phase() -> Phase:
	return _phase


func get_active_hold() -> BulkHoldComponent:
	return _hold


func get_status_line() -> String:
	if not _active:
		return "Auto  idle"
	var op := "LOAD" if operation == Operation.LOAD else "UNLOAD"
	var hold_id := _hold.hold_id if _hold != null else "?"
	return "Auto  %s · %s · t=%.2f · %s · cycle %d" % [
		op, _phase_label(), _t, hold_id, _cycles + 1,
	]


func get_progress_label() -> String:
	if not _active:
		return "idle"
	return "%s · %s · grab %d" % [
		"Loading" if operation == Operation.LOAD else "Unloading", _phase_label(), _cycles + 1,
	]


func stop() -> void:
	var was_active := _active
	_clear_operation()
	if was_active:
		job_stopped.emit()


func _clear_operation() -> void:
	_active = false
	operation = Operation.NONE
	_ship = null
	_hold = null
	_mound = null
	_commodity_id = ""
	_t = 0.0
	_set_phase(Phase.IDLE)
	_update_gizmos()


func start_load(
		ship: BoatBody,
		commodity_id: String = "iron_ore",
		mound: OreMound = null,
		hold: BulkHoldComponent = null,
) -> bool:
	return _begin(Operation.LOAD, ship, commodity_id, mound, hold)


func start_unload(
		ship: BoatBody,
		commodity_id: String = "",
		mound: OreMound = null,
		hold: BulkHoldComponent = null,
) -> bool:
	return _begin(Operation.UNLOAD, ship, commodity_id, mound, hold)


func _process(delta: float) -> void:
	if not _active or _crane == null:
		_update_gizmos()
		return
	if not is_instance_valid(_ship) or not is_instance_valid(_hold) or not is_instance_valid(_mound):
		_fail("Crane target is no longer available.")
		return
	if not _hold.cargo_accessible:
		_fail("The cargo hatch is closed. Open it before restarting.")
		return
	_timer += delta
	_tick(delta)
	_update_gizmos()


func _begin(
		op: Operation,
		ship: BoatBody,
		commodity_id: String,
		mound: OreMound,
		hold: BulkHoldComponent,
) -> bool:
	if _active or _crane == null or ship == null or _crane.get_bucket() == null:
		return false
	_clear_operation()
	_ship = ship
	_commodity_id = commodity_id.strip_edges()
	var payload := _crane.get_bucket_lot()
	if _commodity_id.is_empty() and not payload.is_empty():
		_commodity_id = payload.commodity_id
	_mound = mound
	_hold = hold
	_cycles = 0
	operation = op

	if operation == Operation.LOAD:
		if _commodity_id.is_empty():
			_commodity_id = "iron_ore"
		if _hold == null:
			_hold = _best_load_hold(_ship, _commodity_id)
		if _mound == null:
			_mound = _crane.find_nearest_ore_mound(_commodity_id)
	else:
		if _hold == null:
			_hold = _best_unload_hold(_ship, _commodity_id)
		# The last scoop may already have emptied its hold when Stop was pressed.
		if _hold == null and not payload.is_empty():
			for candidate in _ship.get_bulk_holds():
				if candidate.cargo_accessible and _crane.can_reach_point(candidate.get_crane_aim_global()):
					_hold = candidate
					break
		if _hold == null:
			_clear_operation()
			return false
		if _commodity_id.is_empty():
			_commodity_id = _hold.state.commodity_id
		if _mound == null:
			_mound = _crane.find_nearest_ore_mound(_commodity_id)

	if _hold == null or _mound == null or not _hold.cargo_accessible:
		_clear_operation()
		return false
	if not _crane.can_reach_point(_mound.pickup_global()) or not _crane.can_reach_point(_hold_aim()):
		_clear_operation()
		return false
	if not payload.is_empty() and payload.commodity_id != _commodity_id:
		_clear_operation()
		return false

	_clear_hold_gizmos()
	_t = 0.0
	_aim_initialized = false
	_active = true
	# A stopped loaded grab retains its lot; restart carries it to the discharge
	# instead of collecting a second payload and losing inventory.
	_set_phase(Phase.TO_A if payload.is_empty() else Phase.ARC_TO_B)
	job_started.emit(operation, _commodity_id)
	return true


func _set_phase(phase: Phase) -> void:
	_phase = phase
	_timer = 0.0
	_did_act = false
	phase_changed.emit(phase)


## Point A = pickup, point B = drop. Ellipse is the travel arc between them.
func point_a() -> Vector3:
	if operation == Operation.LOAD:
		return _mound.pickup_global() if _mound != null else _crane.global_position
	return _hold_aim() if _hold != null else _crane.global_position


func point_b() -> Vector3:
	if operation == Operation.LOAD:
		return _hold_aim() if _hold != null else _crane.global_position
	return _mound.pickup_global() if _mound != null else _crane.global_position


func _hold_aim() -> Vector3:
	if _hold == null:
		return _crane.global_position if _crane != null else Vector3.ZERO
	var hint := _crane.get_boom_hinge_global() if _crane != null else _crane.global_position
	return _hold.get_crane_aim_toward(hint)


func ellipse_point(t: float) -> Vector3:
	## t=0 → A (pickup), t=1 → B (drop). Peak height at t=0.5.
	var a := point_a()
	var b := point_b()
	var center := (a + b) * 0.5
	var half := (b - a) * 0.5
	var height := maxf(arc_height_m, half.length() * 0.25)
	var theta := PI * (1.0 - clampf(t, 0.0, 1.0))
	return center + half * cos(theta) + Vector3(0.0, height, 0.0) * sin(theta)


## Horizontal guide on the ellipse; Y is ignored by travel IK (hoist uses raise/track).
func _guide_point(t: float) -> Vector3:
	var p := ellipse_point(t)
	## Keep guide at arc height so slew/boom aim at the raised corridor, not the ground.
	var a := point_a()
	var b := point_b()
	var mid_y := maxf(a.y, b.y) + maxf(arc_height_m, 6.0)
	return Vector3(p.x, mid_y, p.z)


func _update_smooth_aim(desired: Vector3, delta: float) -> Vector3:
	if not _aim_initialized:
		_smooth_aim = desired
		_aim_initialized = true
	else:
		var k := clampf(AIM_SMOOTH * delta, 0.0, 1.0)
		_smooth_aim = _smooth_aim.lerp(desired, k)
	return _smooth_aim


func _tick(delta: float) -> void:
	match _phase:
		Phase.TO_A:
			## Empty travel — jaws open, ready to scoop.
			_t = move_toward(_t, 0.0, ellipse_speed * delta * 1.4)
			var aim := _update_smooth_aim(_guide_point(_t), delta)
			_crane.set_bucket_jaws_target(1.0)
			_crane.ik_mouth_to(delta, aim, "raise")
			_crane.step_jaws(delta)
			if (
				(_t <= 0.02 and _crane.is_bucket_over(point_a(), NEAR_M))
				or _timer >= TIMEOUT_S
			):
				_t = 0.0
				_set_phase(Phase.LOWER_A)

		Phase.LOWER_A:
			## Lower open bucket onto the stockpile / hold.
			_crane.set_bucket_jaws_target(1.0)
			_crane.ik_mouth_to(delta, point_a(), "track")
			_crane.step_jaws(delta)
			if _lower_ready(point_a()):
				_set_phase(Phase.GRAB_A)

		Phase.GRAB_A:
			## Close jaws, then take cargo once shut.
			_crane.set_bucket_jaws_target(0.0)
			_crane.ik_mouth_to(delta, point_a(), "track")
			_crane.step_jaws(delta)
			if not _did_act and (_crane.is_bucket_at_target(0.08) or _timer >= WORK_S + 1.0):
				if operation == Operation.LOAD:
					_crane.grab_from_mound(_mound, _hold.state.available_tonnes_t())
				else:
					_crane.grab_from_hold(_hold)
				_did_act = true
			if _did_act and not _crane.get_bucket_lot().is_empty():
				_set_phase(Phase.RAISE_A)
			elif _did_act and _timer >= 4.0:
				_finish()

		Phase.RAISE_A:
			## Lift loaded grab — keep closed.
			_crane.set_bucket_jaws_target(0.0)
			_crane.ik_mouth_to(delta, _guide_point(0.0), "raise")
			_crane.step_jaws(delta)
			if _crane.hoist_length_m <= _crane.hoist_min_m + 1.35:
				_set_phase(Phase.ARC_TO_B)

		Phase.ARC_TO_B:
			## Loaded swing — jaws stay closed.
			_t = move_toward(_t, 1.0, ellipse_speed * delta)
			var aim_b := _update_smooth_aim(_guide_point(_t), delta)
			_crane.set_bucket_jaws_target(0.0)
			_crane.ik_mouth_to(delta, aim_b, "raise")
			_crane.step_jaws(delta)
			if _t >= 0.995 and (
				_crane.is_bucket_over(point_b(), NEAR_M) or _timer >= TIMEOUT_S
			):
				_t = 1.0
				_set_phase(Phase.LOWER_B)

		Phase.LOWER_B:
			## Lower closed bucket over the drop target.
			_crane.set_bucket_jaws_target(0.0)
			_crane.ik_mouth_to(delta, point_b(), "track")
			_crane.step_jaws(delta)
			if _lower_ready(point_b()):
				_set_phase(Phase.DUMP_B)

		Phase.DUMP_B:
			## Open jaws and release — dump as soon as shells are half open.
			_crane.set_bucket_jaws_target(1.0)
			_crane.ik_mouth_to(delta, point_b(), "track")
			_crane.step_jaws(delta)
			if not _did_act and (
				_crane.bucket_open >= DUMP_OPEN_FRAC
				or _crane.is_bucket_at_target(0.08)
				or _timer >= WORK_S + 0.35
			):
				_crane.force_release_at(_crane.get_bucket_mouth_global())
				_did_act = true
			if _did_act and (_crane.get_bucket_lot().is_empty() or _timer >= WORK_S + 0.6):
				_set_phase(Phase.RAISE_B)

		Phase.RAISE_B:
			## Lift empty grab — keep open for next scoop.
			_crane.set_bucket_jaws_target(1.0)
			_crane.ik_mouth_to(delta, _guide_point(1.0), "raise")
			_crane.step_jaws(delta)
			if _crane.hoist_length_m <= _crane.hoist_min_m + 1.35:
				_set_phase(Phase.ARC_TO_A)

		Phase.ARC_TO_A:
			## Empty return — jaws stay open.
			_t = move_toward(_t, 0.0, ellipse_speed * delta)
			var aim_a := _update_smooth_aim(_guide_point(_t), delta)
			_crane.set_bucket_jaws_target(1.0)
			_crane.ik_mouth_to(delta, aim_a, "raise")
			_crane.step_jaws(delta)
			if _t <= 0.005 and (
				_crane.is_bucket_over(point_a(), NEAR_M * 1.2) or _timer >= TIMEOUT_S
			):
				_t = 0.0
				_set_phase(Phase.NEXT)

		Phase.NEXT:
			_cycles += 1
			cycle_completed.emit(operation, _cycles)
			if _can_continue():
				_rebind_targets()
				_t = 0.0
				_aim_initialized = false
				_set_phase(Phase.TO_A)
			else:
				_finish()


## Dump/grab only after the bucket has actually lowered. Horizontal "over" alone
## is already true at travel height when ARC_TO_B finishes.
func _lower_ready(target: Vector3) -> bool:
	if _crane == null:
		return false
	var mouth := _crane.get_bucket_mouth_global()
	var at_hold := (_phase == Phase.LOWER_B and operation == Operation.LOAD) or (_phase == Phase.LOWER_A and operation == Operation.UNLOAD)
	var inside := not at_hold or not _hold is ImportedBulkHold or (_hold as ImportedBulkHold).contains_grab_mouth(mouth)
	if inside and mouth.distance_to(target) <= 0.6:
		return true
	if _timer >= TIMEOUT_S:
		_fail("Grab cannot reach the cargo target. Reposition the ship or use a nearer crane.")
	return false


func _finish() -> void:
	var op := operation
	var n := _cycles
	_clear_operation()
	job_finished.emit(op, n)


func _fail(reason: String) -> void:
	_clear_operation()
	job_failed.emit(reason)


func _can_continue() -> bool:
	if max_cycles > 0 and _cycles >= max_cycles:
		return false
	if _ship == null:
		return false
	if operation == Operation.LOAD:
		return _best_load_hold(_ship, _commodity_id) != null
	return _best_unload_hold(_ship, _commodity_id) != null


func _rebind_targets() -> void:
	if operation == Operation.LOAD:
		_hold = _best_load_hold(_ship, _commodity_id)
	else:
		_hold = _best_unload_hold(_ship, _commodity_id)
	_mound = _crane.find_nearest_ore_mound(_commodity_id)


func _best_load_hold(ship: BoatBody, commodity_id: String) -> BulkHoldComponent:
	return _pick_hold(ship, commodity_id, true)


func _best_unload_hold(ship: BoatBody, commodity_id: String) -> BulkHoldComponent:
	return _pick_hold(ship, commodity_id, false)


## Multi-crane safe: only holds this boom can reach, prefer fewer workers + nearer
## so parallel tools split hatches instead of stacking on one lip.
func _pick_hold(ship: BoatBody, commodity_id: String, loading: bool) -> BulkHoldComponent:
	if ship == null or _crane == null:
		return null
	var cid := commodity_id.strip_edges()
	var best: BulkHoldComponent = null
	var best_score := -INF
	var hinge := _crane.get_boom_hinge_global()
	for hold in ship.get_bulk_holds():
		if not hold.cargo_accessible: continue
		if loading:
			if cid.is_empty() or not hold.can_accept_commodity(cid):
				continue
			if hold.state.available_tonnes_t() <= BulkCargoLot.TONNES_EPS:
				continue
		else:
			if hold.state.is_empty():
				continue
			if not cid.is_empty() and hold.state.commodity_id != cid:
				continue
		var aim := hold.get_crane_aim_toward(hinge)
		if not _crane.can_reach_point(aim):
			continue
		var dist := Vector2(aim.x - hinge.x, aim.z - hinge.z).length()
		var workers := _active_workers_on_hold(hold)
		var cargo_term := (
			hold.state.available_tonnes_t() if loading else hold.state.filled_tonnes_t
		)
		var score := -float(workers) * 1000.0 - dist * 10.0 + cargo_term * 0.05
		if score > best_score:
			best_score = score
			best = hold
	return best


func _active_workers_on_hold(hold: BulkHoldComponent) -> int:
	if hold == null or not is_inside_tree():
		return 0
	var n := 0
	for node in get_tree().get_nodes_in_group("bulk_crane_auto"):
		if node == self or node is not BulkCraneAutoOperator:
			continue
		var op := node as BulkCraneAutoOperator
		if op.is_active() and op.get_active_hold() == hold:
			n += 1
	return n


func _phase_label() -> String:
	match _phase:
		Phase.TO_A:
			return "to pickup"
		Phase.LOWER_A:
			return "lower open"
		Phase.GRAB_A:
			return "close + scoop"
		Phase.RAISE_A:
			return "raise closed"
		Phase.ARC_TO_B:
			return "arc loaded"
		Phase.LOWER_B:
			return "lower closed"
		Phase.DUMP_B:
			return "open + dump"
		Phase.RAISE_B:
			return "raise open"
		Phase.ARC_TO_A:
			return "arc empty"
		Phase.NEXT:
			return "next"
		_:
			return "idle"


func _build_gizmos() -> void:
	_gizmos = Node3D.new()
	_gizmos.name = "TargetGizmos"
	add_child(_gizmos)
	_g_a = _sphere(Color(0.2, 0.95, 0.35, 0.6), 0.9)
	_g_b = _sphere(Color(0.98, 0.55, 0.12, 0.6), 0.9)
	_g_aim = _sphere(Color(0.98, 0.95, 0.2, 0.85), 0.55)
	_g_bucket = _sphere(Color(0.95, 0.2, 0.55, 0.8), 0.45)
	_g_gap = _line(Color(0.95, 0.35, 0.95, 0.7), 0.08)
	for n in [_g_a, _g_b, _g_aim, _g_bucket, _g_gap]:
		_gizmos.add_child(n)
	for i in range(ELLIPSE_GIZMO_SEGS):
		var seg := _line(Color(0.55, 0.85, 1.0, 0.45), 0.1)
		seg.name = "EllipseSeg_%d" % i
		_gizmos.add_child(seg)
		_g_ellipse.append(seg)


func _sphere(color: Color, radius: float) -> MeshInstance3D:
	var mi := MeshBuilder.sphere(radius, color, 0.9, 0.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := mi.material_override as StandardMaterial3D
	if mat != null:
		mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	return mi


func _line(color: Color, thickness: float) -> MeshInstance3D:
	var mi := MeshBuilder.box(Vector3(thickness, 1.0, thickness), color, 0.9, 0.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := mi.material_override as StandardMaterial3D
	if mat != null:
		mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	return mi


func _stretch(line: MeshInstance3D, from: Vector3, to: Vector3) -> void:
	var dir := to - from
	var length := dir.length()
	if length < 0.05:
		line.visible = false
		return
	line.visible = true
	line.global_position = from + dir * 0.5
	if absf(dir.normalized().dot(Vector3.UP)) > 0.995:
		line.global_basis = Basis.IDENTITY
	else:
		line.look_at(to, Vector3.UP)
		line.rotate_object_local(Vector3.RIGHT, -PI * 0.5)
	line.scale = Vector3(1.0, length, 1.0)


func _clear_hold_gizmos() -> void:
	for g in _g_holds:
		if is_instance_valid(g):
			g.queue_free()
	_g_holds.clear()


func _ensure_hold_gizmos() -> void:
	if not _g_holds.is_empty() or _ship == null:
		return
	for hold in _ship.get_bulk_holds():
		var box := MeshBuilder.box(Vector3.ONE, Color(0.35, 0.85, 1.0, 0.18), 0.9, 0.0)
		box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat := box.material_override as StandardMaterial3D
		if mat != null:
			mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		box.set_meta("hold_id", hold.hold_id)
		_gizmos.add_child(box)
		_g_holds.append(box)


func _update_gizmos() -> void:
	if _gizmos == null:
		return
	_gizmos.visible = show_target_gizmos \
		and WorldGizmos.is_layer_enabled(WorldGizmos.LAYER_CRANES) and _active
	if not _gizmos.visible or _crane == null:
		return
	_ensure_hold_gizmos()
	var a := point_a()
	var b := point_b()
	var aim := _smooth_aim if _aim_initialized else ellipse_point(_t)
	var bucket := _crane.get_bucket_global()
	_g_a.global_position = a
	_g_b.global_position = b
	_g_aim.global_position = aim
	_g_bucket.global_position = bucket
	_stretch(_g_gap, bucket, aim)
	for i in range(_g_ellipse.size()):
		var t0 := float(i) / float(ELLIPSE_GIZMO_SEGS)
		var t1 := float(i + 1) / float(ELLIPSE_GIZMO_SEGS)
		_stretch(_g_ellipse[i], ellipse_point(t0), ellipse_point(t1))
	for box in _g_holds:
		if not is_instance_valid(box):
			continue
		var hold := _find_hold(str(box.get_meta("hold_id", "")))
		if hold == null:
			box.visible = false
			continue
		box.visible = true
		var bounds := hold.get_crane_bounds_global()
		box.global_position = bounds["center"]
		box.basis = hold.global_basis
		box.scale = (bounds["half_extents"] as Vector3) * 2.0
		var mat := box.material_override as StandardMaterial3D
		if mat != null:
			mat.albedo_color = (
				Color(0.35, 0.95, 1.0, 0.4) if hold == _hold
				else Color(0.35, 0.85, 1.0, 0.16)
			)


func _find_hold(hold_id: String) -> BulkHoldComponent:
	if _ship == null:
		return null
	for hold in _ship.get_bulk_holds():
		if hold.hold_id == hold_id:
			return hold
	return null
