class_name BulkCrane
extends Node3D

## Harbour bulk crane rig. Drive via `step()` / `steer_toward()`; attach `BulkCraneAutoOperator` for auto load/unload.

const DEFAULT_MODEL := "res://resources/data/models/dockyard/bulk_crane.json"
const ASSEMBLER_SCRIPT := preload("res://scripts/core/model_assembler.gd")
const IMPORTED_RIG := preload("res://scripts/port/blender_bulk_crane_rig.gd")

## Per-shell jaw angles (degrees X). Open = spread; closed = lips meet.
const RIGHT_CLOSED_DEG := 6.0
const RIGHT_OPEN_DEG := -32.0
const LEFT_CLOSED_DEG := -6.0
const LEFT_OPEN_DEG := 32.0
const WIRE_REST_LENGTH_M := 10.0
const HOIST_CABIN_CLEARANCE_M := 0.35
const PICKUP_RADIUS_BASE_M := 8.0
const PICKUP_HEIGHT_TOLERANCE_BASE_M := 4.0
const PICKUP_OPEN_THRESHOLD := 0.55
const DROP_CLOSE_THRESHOLD := 0.12
const BUCKET_MOUTH_OFFSET_Y_M := -1.6

signal bucket_fill_changed(lot: BulkCargoLot, capacity_tonnes_t: float)
signal material_dropped(lot: BulkCargoLot, world_position: Vector3)

signal model_loaded(path: String)
signal slew_changed(degrees: float)
signal boom_changed(degrees: float)
signal hoist_changed(length_m: float)
signal bucket_changed(open_amount: float)

@export_file("*.json") var model_path: String = DEFAULT_MODEL:
	set(v):
		model_path = v
		if is_inside_tree():
			reload_model()

@export var slew_degrees: float = 0.0:
	set(v):
		slew_degrees = v
		_apply_slew()

@export_range(0.0, 80.0, 0.1) var boom_angle_deg: float = 32.0:
	set(v):
		boom_angle_deg = clampf(v, boom_min_deg, boom_max_deg)
		_apply_boom()

@export_range(2.0, 40.0, 0.1) var hoist_length_m: float = 10.0:
	set(v):
		var clamped := _clamp_hoist_m(v)
		if is_equal_approx(hoist_length_m, clamped):
			return
		hoist_length_m = clamped
		_apply_hoist()

@export_range(0.0, 1.0, 0.01) var bucket_open: float = 0.0:
	set(v):
		bucket_open = clampf(v, 0.0, 1.0)
		_apply_bucket()

@export var boom_min_deg: float = 8.0
@export var boom_max_deg: float = 72.0
@export var hoist_min_m: float = 3.0
@export var hoist_max_m: float = 28.0
@export var slew_speed_deg: float = 55.0
@export var boom_speed_deg: float = 28.0
@export var hoist_speed_m: float = 8.0
@export var bucket_speed: float = 2.5
@export var show_operator: bool = true
@export var model_scale: float = 1.5:
	set(v):
		model_scale = maxf(v, 0.01)
		scale = Vector3.ONE * model_scale
@export var bucket_scale: float = 1.5:
	set(v):
		bucket_scale = maxf(v, 0.01)
		_apply_bucket_scale()
@export var simulate_bulk_material := true

var bucket_lot := BulkCargoLot.empty()

var _assembler: Node3D
var _cabin: Node3D
var _boom: Node3D
var _wire: Node3D
var _wire_mesh: MeshInstance3D
var _wire_mesh_base_scale := Vector3.ONE
var _bucket: Node3D
var _shell_left: Node3D
var _shell_right: Node3D
var _operator: NpcBase
var _wire_rest_length := WIRE_REST_LENGTH_M
var _cabin_top_y_global := 0.0
var _bucket_open_target := 0.0
var _space_held := false
var _drop_armed := false


func _ready() -> void:
	scale = Vector3.ONE * model_scale
	reload_model()


func reload_model() -> void:
	_cabin = null
	_boom = null
	_wire = null
	_wire_mesh = null
	_bucket = null
	_shell_left = null
	_shell_right = null
	_operator = null
	if _assembler != null and is_instance_valid(_assembler):
		_assembler.queue_free()
		_assembler = null
	if model_path == DEFAULT_MODEL:
		_assembler = IMPORTED_RIG.new()
		_assembler.name = "Model"
		add_child(_assembler)
		call_deferred("_bind_rig")
		return
	if model_path.is_empty() or not ResourceLoader.exists(model_path):
		push_warning("BulkCrane: missing model %s" % model_path)
		return
	_assembler = ASSEMBLER_SCRIPT.new()
	_assembler.name = "Model"
	add_child(_assembler)
	_assembler.model_data_path = model_path
	call_deferred("_bind_rig")


func _bind_rig() -> void:
	if _assembler == null or not is_instance_valid(_assembler):
		return
	if _assembler.has_method("rebuild"):
		_assembler.rebuild()
	_cabin = _part("cabin")
	_boom = _part("boom")
	_wire = _part("wire")
	_bucket = _part("bucket")
	_rig_hoist_parts()
	_bind_shells()
	_measure_cabin_top_y()
	var meta := _model_meta()
	_wire_rest_length = float(meta.get("wire_rest_length_m", WIRE_REST_LENGTH_M))
	hoist_length_m = _wire_rest_length
	_bucket_open_target = bucket_open
	_apply_slew()
	_apply_boom()
	_apply_hoist()
	_apply_bucket_scale()
	_apply_bucket()
	if show_operator:
		_spawn_operator()
	model_loaded.emit(model_path)


func _bind_shells() -> void:
	_shell_left = null
	_shell_right = null
	if _bucket == null or not is_instance_valid(_bucket):
		return
	if _bucket.has_method("get_part"):
		_shell_right = _bucket.get_part("shell_right") as Node3D
		_shell_left = _bucket.get_part("shell_left") as Node3D
	if _shell_right == null:
		_shell_right = _bucket.find_child("ModelPart_shell_right", true, false) as Node3D
	if _shell_left == null:
		_shell_left = _bucket.find_child("ModelPart_shell_left", true, false) as Node3D
	if _shell_right == null or _shell_left == null:
		## Nested bucket assembler may still be building.
		call_deferred("_bind_shells_retry")


func _bind_shells_retry() -> void:
	if _bucket == null or not is_instance_valid(_bucket):
		return
	if _bucket.has_method("get_part"):
		if _shell_right == null:
			_shell_right = _bucket.get_part("shell_right") as Node3D
		if _shell_left == null:
			_shell_left = _bucket.get_part("shell_left") as Node3D
	if _shell_right == null:
		_shell_right = _bucket.find_child("ModelPart_shell_right", true, false) as Node3D
	if _shell_left == null:
		_shell_left = _bucket.find_child("ModelPart_shell_left", true, false) as Node3D
	_apply_bucket()


func _rig_hoist_parts() -> void:
	if _wire == null or _boom == null:
		return
	_wire.scale = Vector3.ONE
	_wire_mesh = _find_wire_mesh(_wire)
	if _wire_mesh != null:
		_wire_mesh_base_scale = _wire_mesh.scale
	if _bucket != null and is_instance_valid(_bucket):
		## Bucket must not inherit wire scale — only the cable mesh stretches.
		if _bucket.get_parent() != _boom:
			_bucket.reparent(_boom, false)
		call_deferred("_bind_shells")


func _model_meta() -> Dictionary:
	if model_path.is_empty() or not FileAccess.file_exists(model_path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(model_path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var meta: Variant = (parsed as Dictionary).get("meta", {})
	return meta as Dictionary if typeof(meta) == TYPE_DICTIONARY else {}


func _measure_cabin_top_y() -> void:
	_cabin_top_y_global = global_position.y + 4.0
	if _cabin == null or not is_instance_valid(_cabin):
		return
	var meta := _model_meta()
	if meta.has("cabin_top_y_m"):
		_cabin_top_y_global = global_position.y + float(meta["cabin_top_y_m"])
		return
	var top_local_y := 1.6
	if _cabin is ModelAssembler:
		var body: MeshTransformer = (_cabin as ModelAssembler).get_part("body") as MeshTransformer
		if body != null:
			top_local_y = body.actual_max.y
	_cabin_top_y_global = _cabin.to_global(Vector3(0.0, top_local_y, 0.0)).y


func _clamp_hoist_m(length: float) -> float:
	return clampf(length, hoist_min_m, _effective_hoist_max_m())


func _effective_hoist_max_m() -> float:
	return minf(hoist_max_m, _max_hoist_for_cabin_m())


func _max_hoist_for_cabin_m() -> float:
	if _wire == null or _boom == null:
		return hoist_max_m
	if not is_inside_tree():
		return hoist_max_m
	var origin := _boom.to_global(_wire.position)
	var down := (_boom.global_basis * _wire.basis * Vector3.DOWN).normalized()
	if down.y >= -0.001:
		return hoist_max_m
	var limit_y := _cabin_top_y_global + HOIST_CABIN_CLEARANCE_M
	var drop_available := origin.y - limit_y
	if drop_available <= 0.0:
		return hoist_min_m
	return drop_available / -down.y


func _spawn_operator() -> void:
	if _cabin == null or not is_instance_valid(_cabin):
		return
	var existing := _cabin.get_node_or_null("Operator")
	if existing != null:
		existing.queue_free()
	var seat := _cabin.get_node_or_null("OperatorSeat")
	if seat == null:
		_add_seat()
	_operator = NpcBase.new()
	_operator.name = "Operator"
	_operator.appearance = CharacterCatalog.appearance_preset("dock_worker")
	_operator.position = Vector3(0.0, -0.12, 0.28)
	_operator.rotation_degrees = Vector3(0.0, 0.0, 0.0)
	_cabin.add_child(_operator)
	call_deferred("_pose_operator_seated")


func _add_seat() -> void:
	var seat := MeshBuilder.box(
		Vector3(0.55, 0.12, 0.50),
		Color(0.12, 0.12, 0.13),
		0.85,
		0.0,
	)
	seat.name = "OperatorSeat"
	seat.position = Vector3(0.0, 0.42, 0.32)
	_cabin.add_child(seat)
	var back := MeshBuilder.box(
		Vector3(0.55, 0.55, 0.08),
		Color(0.12, 0.12, 0.13),
		0.85,
		0.0,
	)
	back.name = "OperatorSeatBack"
	back.position = Vector3(0.0, 0.72, 0.54)
	_cabin.add_child(back)


func _pose_operator_seated() -> void:
	if _operator == null or not is_instance_valid(_operator):
		return
	if _operator.animator != null:
		_operator.animator.set_preview_motion(&"seated")


func _part(name_or_role: String) -> Node3D:
	if _assembler == null:
		return null
	if _assembler.has_method("get_part"):
		var by_name: Node3D = _assembler.get_part(name_or_role) as Node3D
		if by_name != null:
			return by_name
	if _assembler.has_method("get_first_part_by_role"):
		return _assembler.get_first_part_by_role(name_or_role) as Node3D
	return null


func _apply_slew() -> void:
	if _cabin == null or not is_instance_valid(_cabin):
		return
	var r := _cabin.rotation_degrees
	r.y = slew_degrees
	_cabin.rotation_degrees = r
	slew_changed.emit(slew_degrees)


func _apply_boom() -> void:
	if _boom == null or not is_instance_valid(_boom):
		return
	var r := _boom.rotation_degrees
	r.x = boom_angle_deg
	_boom.rotation_degrees = r
	if _assembler is BlenderBulkCraneRig:
		(_assembler as BlenderBulkCraneRig).update_luff_cylinder()
	if _wire != null and is_instance_valid(_wire):
		var wr := _wire.rotation_degrees
		wr.x = -boom_angle_deg
		_wire.rotation_degrees = wr
	var clamped := _clamp_hoist_m(hoist_length_m)
	if not is_equal_approx(hoist_length_m, clamped):
		hoist_length_m = clamped
	else:
		_apply_hoist()
	boom_changed.emit(boom_angle_deg)


func _find_wire_mesh(wire_node: Node3D) -> MeshInstance3D:
	if wire_node == null:
		return null
	for child in wire_node.get_children():
		if child is MeshInstance3D:
			return child as MeshInstance3D
		if child is Node3D:
			var nested := _find_wire_mesh(child as Node3D)
			if nested != null:
				return nested
	return null


func _hoist_attachment_on_boom() -> Vector3:
	if _wire == null or not is_instance_valid(_wire):
		return Vector3.ZERO
	return _wire.position + _wire.basis * Vector3(0.0, -hoist_length_m, 0.0)


func _apply_hoist() -> void:
	if _wire == null or not is_instance_valid(_wire):
		return
	if _wire_mesh == null or not is_instance_valid(_wire_mesh):
		_wire_mesh = _find_wire_mesh(_wire)
		if _wire_mesh != null:
			_wire_mesh_base_scale = _wire_mesh.scale
	var rest := maxf(_wire_rest_length, 0.1)
	var ratio := hoist_length_m / rest
	## Never scale the wire node — only the cable mesh visual stretches.
	_wire.scale = Vector3.ONE
	if _wire_mesh != null and is_instance_valid(_wire_mesh):
		_wire_mesh.scale = Vector3(
			_wire_mesh_base_scale.x,
			_wire_mesh_base_scale.y * ratio,
			_wire_mesh_base_scale.z,
		)
	if _bucket != null and is_instance_valid(_bucket):
		_bucket.position = _hoist_attachment_on_boom()
		_bucket.rotation = _wire.rotation
	hoist_changed.emit(hoist_length_m)


func _apply_bucket_scale() -> void:
	if _bucket == null or not is_instance_valid(_bucket):
		return
	_bucket.scale = Vector3.ONE
	if _bucket is ModelAssembler:
		(_bucket as ModelAssembler).absolute_scale = bucket_scale
	elif _assembler is BlenderBulkCraneRig:
		(_assembler as BlenderBulkCraneRig).set_grab_scale(bucket_scale)
	call_deferred("_bind_shells")


func get_bucket_mouth_global() -> Vector3:
	if _bucket == null or not is_instance_valid(_bucket):
		return global_position
	return _bucket.global_position + _bucket.global_basis * Vector3(
		0.0, BUCKET_MOUTH_OFFSET_Y_M * bucket_scale, 0.0)


func get_bucket_global() -> Vector3:
	if _bucket == null or not is_instance_valid(_bucket):
		return global_position
	return _bucket.global_position


func get_boom_hinge_global() -> Vector3:
	if _boom == null or not is_instance_valid(_boom):
		return global_position
	return _boom.global_position


func get_boom_tip_global() -> Vector3:
	if _boom == null or _wire == null:
		return get_boom_hinge_global()
	return _boom.to_global(_wire.position)


func get_boom_length_m() -> float:
	return get_boom_hinge_global().distance_to(get_boom_tip_global())


func get_slew_pivot_global() -> Vector3:
	if _cabin != null and is_instance_valid(_cabin):
		return _cabin.global_position
	return global_position


func get_tower_global() -> Vector3:
	return get_slew_pivot_global() + Vector3(0.0, 3.6 * model_scale, 0.0)


func get_effective_hoist_max_m() -> float:
	return _effective_hoist_max_m()


## Inverse kinematics from bucket position.
## `hoist_mode`: "hold" = leave hoist alone · "raise" = reel up · "track" = match target Y
func ik_bucket_to(delta: float, target: Vector3, hoist_mode: String = "track") -> void:
	if _cabin == null or not is_instance_valid(_cabin):
		return
	var bucket := get_bucket_global()
	var pivot := get_slew_pivot_global()
	var hinge := get_boom_hinge_global()

	## Slew — azimuth error, deadzoned to kill jitter.
	var bucket_az := Vector2(bucket.x - pivot.x, bucket.z - pivot.z)
	var target_az := Vector2(target.x - pivot.x, target.z - pivot.z)
	var slew_err_deg := 0.0
	if bucket_az.length() > 0.3 and target_az.length() > 0.3:
		slew_err_deg = rad_to_deg(bucket_az.angle_to(target_az))
		if absf(slew_err_deg) > 2.0:
			var slew_step := slew_speed_deg * delta
			slew_degrees -= clampf(slew_err_deg, -slew_step, slew_step)

	## Boom — only once slew is roughly on target, with a wide deadzone + soft gain.
	var bucket_reach := Vector2(bucket.x - hinge.x, bucket.z - hinge.z).length()
	var target_reach := Vector2(target.x - hinge.x, target.z - hinge.z).length()
	var reach_err := target_reach - bucket_reach
	if absf(slew_err_deg) < 12.0 and absf(reach_err) > 1.25:
		var boom_step := boom_speed_deg * delta * 0.55
		var soft := clampf(absf(reach_err) / 8.0, 0.15, 1.0)
		boom_angle_deg += clampf(-reach_err * 1.1 * soft, -boom_step, boom_step)

	## Hoist — explicit modes so travel does not fight the ellipse height.
	var hoist_step := hoist_speed_m * delta * 1.5
	match hoist_mode:
		"raise":
			var raised := hoist_min_m + 1.2
			hoist_length_m = move_toward(hoist_length_m, raised, hoist_step)
		"track":
			var y_err := target.y - bucket.y
			if y_err < -0.35:
				hoist_length_m += hoist_step
			elif y_err > 0.35:
				hoist_length_m -= hoist_step
		_:
			pass


func bucket_distance_to(target: Vector3) -> float:
	return get_bucket_global().distance_to(target)


func bucket_horizontal_distance_to(target: Vector3) -> float:
	var bucket := get_bucket_global()
	return Vector2(target.x - bucket.x, target.z - bucket.z).length()


func is_bucket_near(target: Vector3, radius_m: float = 2.5) -> bool:
	return bucket_distance_to(target) <= radius_m


func is_bucket_over(target: Vector3, radius_m: float = 3.5) -> bool:
	return bucket_horizontal_distance_to(target) <= radius_m


## Horizontal working envelope from boom hinge (min steep → max flat), metres.
func horizontal_reach_limits_m() -> Vector2:
	var boom_len := maxf(get_boom_length_m(), 8.0)
	var r_min := boom_len * cos(deg_to_rad(boom_max_deg))
	var r_max := boom_len * cos(deg_to_rad(boom_min_deg))
	if r_min > r_max:
		var swap := r_min
		r_min = r_max
		r_max = swap
	return Vector2(r_min, r_max)


## True when the grab can plumb over `target` within boom angle limits.
func can_reach_point(target: Vector3, margin_m: float = 2.0) -> bool:
	var hinge := get_boom_hinge_global()
	var horiz := Vector2(target.x - hinge.x, target.z - hinge.z).length()
	var limits := horizontal_reach_limits_m()
	return horiz >= limits.x - margin_m and horiz <= limits.y + margin_m


## True when at least one bulk hold lip is inside this crane's reach.
func can_reach_ship(ship: BoatBody) -> bool:
	if ship == null or not is_instance_valid(ship):
		return false
	var any_hold := false
	for hold in ship.get_bulk_holds():
		any_hold = true
		if can_reach_point(hold.get_crane_aim_global()):
			return true
	if any_hold:
		return false
	return can_reach_point(ship.global_position)


## @deprecated — use ik_bucket_to
func drive_toward_target(delta: float, target: Vector3, travel_high: bool = false) -> void:
	ik_bucket_to(delta, target, "raise" if travel_high else "track")


func is_close_to_target(target: Vector3, travel_high: bool = false) -> bool:
	if travel_high:
		return is_bucket_over(target, 3.5)
	return is_bucket_near(target, 2.5)


func aim_at_target(delta: float, target: Vector3, travel_high: bool = false) -> bool:
	ik_bucket_to(delta, target, "raise" if travel_high else "track")
	return is_close_to_target(target, travel_high)


func find_nearest_ore_mound(commodity_id: String = "") -> OreMound:
	if not is_inside_tree():
		return null
	var origin := global_position
	var cid := commodity_id.strip_edges()
	var best: OreMound = null
	var best_dist := INF
	for node in get_tree().get_nodes_in_group("ore_mound"):
		if node is not OreMound:
			continue
		var mound := node as OreMound
		if not cid.is_empty() and mound.commodity_id != cid:
			continue
		var dist := origin.distance_to(mound.global_position)
		if dist < best_dist:
			best_dist = dist
			best = mound
	return best


func set_bucket_jaws_target(open_amount: float) -> void:
	_bucket_open_target = clampf(open_amount, 0.0, 1.0)


func get_bucket_jaws_target() -> float:
	return _bucket_open_target


func is_bucket_at_target(tolerance: float = 0.04) -> bool:
	return absf(bucket_open - _bucket_open_target) <= tolerance


func step(delta: float, command: BulkCraneCommand = null) -> void:
	if command == null:
		command = BulkCraneCommand.new()
	if not is_zero_approx(command.slew_rate):
		slew_degrees = slew_degrees + command.slew_rate * slew_speed_deg * delta
	if not is_zero_approx(command.boom_rate):
		boom_angle_deg = boom_angle_deg + command.boom_rate * boom_speed_deg * delta
	if not is_zero_approx(command.hoist_rate):
		hoist_length_m = hoist_length_m + command.hoist_rate * hoist_speed_m * delta
	if command.bucket_target >= 0.0:
		_bucket_open_target = clampf(command.bucket_target, 0.0, 1.0)
	step_jaws(delta)
	_tick_bulk_material(delta)


func step_jaws(delta: float) -> void:
	if _shell_left == null or _shell_right == null:
		_bind_shells()
	if not is_equal_approx(bucket_open, _bucket_open_target):
		bucket_open = move_toward(bucket_open, _bucket_open_target, bucket_speed * delta)


func grab_from_mound(mound: OreMound) -> void:
	if mound == null:
		return
	var capacity_t := bucket_capacity_tonnes_t()
	bucket_lot = BulkCargoLot.create(mound.commodity_id, capacity_t)
	mound.take(capacity_t)
	bucket_fill_changed.emit(bucket_lot.duplicate_lot(), capacity_t)


func grab_from_hold(hold: BulkHoldComponent) -> void:
	if hold == null:
		return
	var capacity_t := bucket_capacity_tonnes_t()
	var withdrawn := hold.withdraw_lot(capacity_t)
	if withdrawn.is_empty():
		return
	bucket_lot = withdrawn.duplicate_lot()
	bucket_fill_changed.emit(bucket_lot.duplicate_lot(), capacity_t)


func force_release_at(world_pos: Vector3) -> void:
	if bucket_lot.is_empty():
		_drop_armed = false
		return
	_drop_armed = true
	var dropped := bucket_lot.duplicate_lot()
	var drop_parent := get_parent()
	if drop_parent == null:
		drop_parent = self
	BulkMaterialDrop.spawn(
		drop_parent,
		dropped,
		world_pos,
		Vector3.DOWN * 1.5,
		bucket_capacity_tonnes_t(),
		bucket_scale,
	)
	material_dropped.emit(dropped, world_pos)
	bucket_lot = BulkCargoLot.empty()
	bucket_fill_changed.emit(bucket_lot.duplicate_lot(), bucket_capacity_tonnes_t())


func _pickup_mound() -> OreMound:
	if not is_inside_tree():
		return null
	var mouth := get_bucket_mouth_global()
	var best: OreMound = null
	var best_dist := PICKUP_RADIUS_BASE_M * bucket_scale
	for node in get_tree().get_nodes_in_group("ore_mound"):
		if node is not OreMound:
			continue
		var mound := node as OreMound
		var dist := mouth.distance_to(mound.pickup_global())
		if dist < best_dist:
			best_dist = dist
			best = mound
	return best


func _tick_bulk_material(_delta: float) -> void:
	if not simulate_bulk_material:
		return
	_try_pickup_from_mound()
	_try_pickup_from_hold()
	_try_drop_material()


func bucket_capacity_tonnes_t() -> float:
	return BulkCargoRules.bucket_capacity_tonnes(bucket_scale)


func get_bucket_lot() -> BulkCargoLot:
	return bucket_lot.duplicate_lot()


func _try_pickup_from_mound() -> void:
	var capacity_t := bucket_capacity_tonnes_t()
	if bucket_open < PICKUP_OPEN_THRESHOLD:
		return
	if (
		not bucket_lot.is_empty()
		and bucket_lot.tonnes_t >= capacity_t - BulkCargoLot.TONNES_EPS
	):
		return
	var mound := _pickup_mound()
	if mound == null:
		return
	var mouth := get_bucket_mouth_global()
	var pick := mound.pickup_global()
	if mouth.distance_to(pick) > PICKUP_RADIUS_BASE_M * bucket_scale:
		return
	if absf(mouth.y - pick.y) > PICKUP_HEIGHT_TOLERANCE_BASE_M * bucket_scale:
		return
	bucket_lot = BulkCargoLot.create(mound.commodity_id, capacity_t)
	mound.take(capacity_t)
	bucket_fill_changed.emit(bucket_lot.duplicate_lot(), capacity_t)


func _try_pickup_from_hold() -> void:
	var capacity_t := bucket_capacity_tonnes_t()
	if bucket_open < PICKUP_OPEN_THRESHOLD:
		return
	if (
		not bucket_lot.is_empty()
		and bucket_lot.tonnes_t >= capacity_t - BulkCargoLot.TONNES_EPS
	):
		return
	var mouth := get_bucket_mouth_global()
	var hold := BulkHoldComponent.find_filled_hold_at(mouth)
	if hold == null:
		return
	var aim := hold.get_crane_aim_global()
	if mouth.distance_to(aim) > PICKUP_RADIUS_BASE_M * bucket_scale:
		return
	if absf(mouth.y - aim.y) > PICKUP_HEIGHT_TOLERANCE_BASE_M * bucket_scale:
		return
	var need_t := capacity_t - bucket_lot.tonnes_t
	var withdrawn := hold.withdraw_lot(need_t)
	if withdrawn.is_empty():
		return
	if bucket_lot.is_empty():
		bucket_lot = withdrawn.duplicate_lot()
	else:
		bucket_lot.tonnes_t += withdrawn.tonnes_t
	bucket_fill_changed.emit(bucket_lot.duplicate_lot(), capacity_t)


func _try_drop_material() -> void:
	if bucket_lot.is_empty():
		_drop_armed = false
		return
	if bucket_open > DROP_CLOSE_THRESHOLD:
		_drop_armed = false
		return
	if _drop_armed:
		return
	_drop_armed = true
	var dropped := bucket_lot.duplicate_lot()
	var mouth := get_bucket_mouth_global()
	var drop_parent := get_parent()
	if drop_parent == null:
		drop_parent = self
	var drop_vel := Vector3.DOWN * 2.0 + _bucket.global_basis.x * 1.2
	BulkMaterialDrop.spawn(
		drop_parent,
		dropped,
		mouth,
		drop_vel,
		bucket_capacity_tonnes_t(),
		bucket_scale,
	)
	material_dropped.emit(dropped, mouth)
	bucket_lot = BulkCargoLot.empty()
	bucket_fill_changed.emit(bucket_lot.duplicate_lot(), bucket_capacity_tonnes_t())


func _apply_bucket() -> void:
	var t := bucket_open
	if _shell_right != null and is_instance_valid(_shell_right):
		_shell_right.rotation_degrees = Vector3(
			lerpf(RIGHT_CLOSED_DEG, RIGHT_OPEN_DEG, t), 0.0, 0.0)
	if _shell_left != null and is_instance_valid(_shell_left):
		_shell_left.rotation_degrees = Vector3(
			lerpf(LEFT_CLOSED_DEG, LEFT_OPEN_DEG, t), 0.0, 0.0)
	if _assembler is BlenderBulkCraneRig:
		(_assembler as BlenderBulkCraneRig).update_grab_actuators()
	bucket_changed.emit(bucket_open)


func toggle_bucket() -> void:
	set_bucket_jaws_target(0.0 if _bucket_open_target > 0.5 else 1.0)


func playtest_input(delta: float) -> void:
	var cmd := BulkCraneCommand.new()
	if Input.is_key_pressed(KEY_A):
		cmd.slew_rate += 1.0
	if Input.is_key_pressed(KEY_D):
		cmd.slew_rate -= 1.0
	if Input.is_key_pressed(KEY_W):
		cmd.boom_rate += 1.0
	if Input.is_key_pressed(KEY_S):
		cmd.boom_rate -= 1.0
	if Input.is_key_pressed(KEY_Q):
		cmd.hoist_rate -= 1.0
	if Input.is_key_pressed(KEY_E):
		cmd.hoist_rate += 1.0
	var space_down := Input.is_physical_key_pressed(KEY_SPACE)
	if space_down and not _space_held:
		toggle_bucket()
	_space_held = space_down
	step(delta, cmd)


func get_bucket() -> Node3D:
	return _bucket


func get_auto_operator() -> BulkCraneAutoOperator:
	return get_node_or_null("AutoOperator") as BulkCraneAutoOperator


func start_auto_load(
		ship: BoatBody,
		commodity_id: String = "iron_ore",
		mound: OreMound = null,
		hold: BulkHoldComponent = null,
) -> bool:
	var op := get_auto_operator()
	if op == null:
		return false
	return op.start_load(ship, commodity_id, mound, hold)


func start_auto_unload(
		ship: BoatBody,
		commodity_id: String = "",
		mound: OreMound = null,
		hold: BulkHoldComponent = null,
) -> bool:
	var op := get_auto_operator()
	if op == null:
		return false
	return op.start_unload(ship, commodity_id, mound, hold)


func stop_auto() -> void:
	var op := get_auto_operator()
	if op != null:
		op.stop()


func is_auto_active() -> bool:
	var op := get_auto_operator()
	return op != null and op.is_active()


func get_status_lines() -> PackedStringArray:
	var jaw := "open" if bucket_open > 0.5 else "closed"
	var cargo := "empty"
	if not bucket_lot.is_empty():
		var cap_t := bucket_capacity_tonnes_t()
		cargo = "%s %.1f / %.1f t" % [bucket_lot.commodity_id, bucket_lot.tonnes_t, cap_t]
	return PackedStringArray([
		"Model  %s" % model_path.get_file(),
		"Slew   %.1f°   (A / D)" % slew_degrees,
		"Boom   %.1f°   (W / S)" % boom_angle_deg,
		"Hoist  %.1f m  (Q / E)" % hoist_length_m,
		"Bucket %s (%.0f%%)  (Space)" % [jaw, bucket_open * 100.0],
		"Cargo  %s" % cargo,
	])
