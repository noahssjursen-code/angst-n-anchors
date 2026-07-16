class_name BulkCrane
extends Node3D

## Harbour bulk crane — A/D slew · W/S boom · Q/E hoist · Space bucket jaws.

const DEFAULT_MODEL := "res://resources/data/models/dockyard/bulk_crane.json"
const ASSEMBLER_SCRIPT := preload("res://scripts/core/model_assembler.gd")

## Per-shell jaw angles (degrees X). Closed = lips meet at bottom. Open = spread (img2).
const RIGHT_CLOSED_DEG := -32.0
const RIGHT_OPEN_DEG := 6.0
const LEFT_CLOSED_DEG := 32.0
const LEFT_OPEN_DEG := -6.0
const WIRE_REST_LENGTH_M := 10.0
const HOIST_CABIN_CLEARANCE_M := 0.35

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
@export var slew_speed_deg: float = 40.0
@export var boom_speed_deg: float = 28.0
@export var hoist_speed_m: float = 8.0
@export var bucket_speed: float = 2.5
@export var show_operator: bool = true

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


func _ready() -> void:
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
	_apply_bucket()
	if show_operator:
		_spawn_operator()
	model_loaded.emit(model_path)


func _rig_hoist_parts() -> void:
	if _wire == null or _boom == null:
		return
	_wire.scale = Vector3.ONE
	_wire_mesh = _find_wire_mesh(_wire)
	if _wire_mesh != null:
		_wire_mesh_base_scale = _wire_mesh.scale
	if _bucket != null and is_instance_valid(_bucket):
		## Bucket must not inherit wire scale — only the cable mesh stretches.
		_bucket.reparent(_boom, false)


func _bind_shells() -> void:
	_shell_left = null
	_shell_right = null
	if _bucket == null:
		return
	if _bucket.has_method("get_part"):
		_shell_right = _bucket.get_part("shell_right") as Node3D
		_shell_left = _bucket.get_part("shell_left") as Node3D


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
	_operator.position = Vector3(0.0, -0.12, 0.28)
	_operator.rotation_degrees = Vector3(0.0, 0.0, 0.0)
	_operator.skin_color = Color(0.72, 0.55, 0.40)
	_operator.clothing_color = Color(0.18, 0.22, 0.28)
	_operator.trousers_color = Color(0.14, 0.14, 0.16)
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
	if _operator.assembler == null:
		call_deferred("_pose_operator_seated")
		return
	_set_part_rotation(_operator, "leg_left", Vector3(78.0, 0.0, 0.0))
	_set_part_rotation(_operator, "leg_right", Vector3(78.0, 0.0, 0.0))
	_set_part_rotation(_operator, "arm_left", Vector3(40.0, 0.0, 12.0))
	_set_part_rotation(_operator, "arm_right", Vector3(40.0, 0.0, -12.0))


func _set_part_rotation(npc: NpcBase, part_name: String, degrees: Vector3) -> void:
	var part := npc.assembler.get_part(part_name) as Node3D
	if part == null:
		return
	part.rotation_degrees = degrees


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
		_bucket.scale = Vector3.ONE
	hoist_changed.emit(hoist_length_m)


func _apply_bucket() -> void:
	var t := bucket_open
	if _shell_right != null and is_instance_valid(_shell_right):
		_shell_right.rotation_degrees = Vector3(
			lerpf(RIGHT_CLOSED_DEG, RIGHT_OPEN_DEG, t), 0.0, 0.0)
	if _shell_left != null and is_instance_valid(_shell_left):
		_shell_left.rotation_degrees = Vector3(
			lerpf(LEFT_CLOSED_DEG, LEFT_OPEN_DEG, t), 0.0, 0.0)
	bucket_changed.emit(bucket_open)


func toggle_bucket() -> void:
	_bucket_open_target = 0.0 if _bucket_open_target > 0.5 else 1.0


func playtest_input(delta: float) -> void:
	var slew_dir := 0.0
	if Input.is_key_pressed(KEY_A):
		slew_dir += 1.0
	if Input.is_key_pressed(KEY_D):
		slew_dir -= 1.0
	if not is_zero_approx(slew_dir):
		slew_degrees = slew_degrees + slew_dir * slew_speed_deg * delta

	var boom_dir := 0.0
	if Input.is_key_pressed(KEY_W):
		boom_dir += 1.0
	if Input.is_key_pressed(KEY_S):
		boom_dir -= 1.0
	if not is_zero_approx(boom_dir):
		boom_angle_deg = boom_angle_deg + boom_dir * boom_speed_deg * delta

	var hoist_dir := 0.0
	if Input.is_key_pressed(KEY_Q):
		hoist_dir -= 1.0
	if Input.is_key_pressed(KEY_E):
		hoist_dir += 1.0
	if not is_zero_approx(hoist_dir):
		hoist_length_m = hoist_length_m + hoist_dir * hoist_speed_m * delta

	var space_down := Input.is_physical_key_pressed(KEY_SPACE)
	if space_down and not _space_held:
		toggle_bucket()
	_space_held = space_down

	if not is_equal_approx(bucket_open, _bucket_open_target):
		bucket_open = move_toward(bucket_open, _bucket_open_target, bucket_speed * delta)


func get_bucket() -> Node3D:
	return _bucket


func get_status_lines() -> PackedStringArray:
	var jaw := "open" if bucket_open > 0.5 else "closed"
	return PackedStringArray([
		"Model  %s" % model_path.get_file(),
		"Slew   %.1f°   (A / D)" % slew_degrees,
		"Boom   %.1f°   (W / S)" % boom_angle_deg,
		"Hoist  %.1f m  (Q / E)" % hoist_length_m,
		"Bucket %s (%.0f%%)  (Space)" % [jaw, bucket_open * 100.0],
	])
