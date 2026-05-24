class_name AutonomousNpcShip
extends Node

## Drives a kinematic NPC hull from AutonomousVesselSim samples.

const GROUP := "autonomous_npc_ship"
const DOCK_LERP_RATE := 8.0
const TRANSIT_YAW_LERP := 12.0

var vessel_uid: String = ""
var owner_id: String = ""

var _body: BoatBody
var _record: Dictionary = {}
var _berth_dock: PortDock
var _berth_index: int = -1
var _last_stage: int = -1
var _has_pose: bool = false
var _stage_label: Label3D


func setup(body: BoatBody, record: Dictionary) -> void:
	_body = body
	vessel_uid = str(record.get("uid", ""))
	owner_id = "auto_%s" % vessel_uid
	sync_record(record)
	add_to_group(GROUP)
	_ensure_stage_label()
	set_physics_process(true)


func sync_record(record: Dictionary) -> void:
	_record = record.duplicate(true)


func get_body() -> BoatBody:
	return _body


func release_berth() -> void:
	if _berth_dock != null and is_instance_valid(_berth_dock):
		_berth_dock.unregister_ship(_body)
		if _berth_index >= 0:
			_berth_dock.release_berth(_berth_index)
	_berth_dock = null
	_berth_index = -1


func _physics_process(delta: float) -> void:
	if _body == null or not is_instance_valid(_body) or _record.is_empty():
		return
	if not bool(_record.get("autonomous_active", false)):
		return

	var elapsed := _sim_elapsed()
	var sample := AutonomousVesselSim.sample_at_elapsed(_record, elapsed)
	if not bool(sample.get("valid", false)):
		return

	_body.freeze = true

	var stage: int = int(sample.get("stage", AutonomousVesselSim.Stage.DOCK))
	var goal: Vector3 = sample.get("position", _body.global_position)
	var yaw: float = float(sample.get("yaw", _body.rotation.y))
	if not _vec3_is_valid(goal) or not is_finite(yaw):
		return

	if stage != _last_stage:
		_on_stage_changed(stage, str(sample.get("port_id", "")))
	_last_stage = stage

	if stage == AutonomousVesselSim.Stage.CRANE and _has_berth():
		var cycle_sec := AutonomousVesselSim.cycle_duration_for_record(_record)
		var cycle_index := int(floor(_sim_elapsed() / maxf(cycle_sec, 1.0)))
		_record = AutonomousCraneOps.process_crane_tick(
			_record,
			_body,
			_berth_dock,
			_berth_index,
			cycle_index,
			int(sample.get("leg_index", 0)),
			float(sample.get("leg_t", 0.0)),
		)
	elif stage != AutonomousVesselSim.Stage.CRANE:
		AutonomousCraneOps.clear_state(vessel_uid)

	if stage == AutonomousVesselSim.Stage.TRANSIT:
		_apply_transit_motion(sample, delta)
	else:
		if not _has_berth():
			_try_dock_at_port(str(sample.get("port_id", "")))
		if _has_berth():
			_apply_dock_berth_motion(delta)
		else:
			_apply_dock_motion(goal, yaw, delta)

	_apply_trawling(bool(sample.get("trawling", false)))
	_update_stage_label(sample)
	_has_pose = true


func _on_stage_changed(stage: int, port_id: String) -> void:
	if stage == AutonomousVesselSim.Stage.TRANSIT:
		release_berth()
		_reparent_to_world()
	elif stage == AutonomousVesselSim.Stage.DOCK or stage == AutonomousVesselSim.Stage.CRANE:
		_try_dock_at_port(port_id)


func _apply_transit_motion(sample: Dictionary, delta: float) -> void:
	var pos: Vector3 = sample.get("position", _body.global_position)
	if not _vec3_is_valid(pos):
		return

	var vel: Vector3 = sample.get("velocity", Vector3.ZERO)
	if not vel.is_finite():
		vel = Vector3.ZERO
	vel.y = 0.0

	var target_yaw := float(sample.get("yaw", _body.rotation.y))
	if vel.length_squared() > 0.01:
		target_yaw = atan2(-vel.x, -vel.z)
	var yaw_alpha := 1.0 - exp(-TRANSIT_YAW_LERP * delta)
	var yaw := lerp_angle(_body.rotation.y, target_yaw, yaw_alpha)
	_set_pose(pos, yaw)


func _apply_dock_motion(goal: Vector3, yaw: float, delta: float) -> void:
	var alpha := 1.0 - exp(-DOCK_LERP_RATE * delta)
	var next := _body.global_position.lerp(goal, alpha)
	var yaw_alpha := 1.0 - exp(-DOCK_LERP_RATE * delta)
	var next_yaw := lerp_angle(_body.rotation.y, yaw, yaw_alpha)
	_set_pose(next, next_yaw)


func _apply_dock_berth_motion(delta: float) -> void:
	var xform := _berth_spawn_transform()
	if xform == Transform3D.IDENTITY:
		return
	var alpha := 1.0 - exp(-DOCK_LERP_RATE * delta)
	_apply_transform(_body.global_transform.interpolate_with(xform, alpha))


func _apply_transform(xform: Transform3D) -> void:
	if not _vec3_is_valid(xform.origin):
		return
	_body.global_transform = xform
	_body.linear_velocity = Vector3.ZERO
	_body.angular_velocity = Vector3.ZERO
	_body.place_at_waterline(WaveSurface.WATER_LEVEL)


func _has_berth() -> bool:
	return _berth_dock != null and is_instance_valid(_berth_dock) and _berth_index >= 0


func _berth_spawn_transform() -> Transform3D:
	if not _has_berth():
		return Transform3D.IDENTITY
	return _berth_dock.get_berth_spawn_transform(_berth_index, _body.get_half_beam_m())


func _set_pose(pos: Vector3, yaw: float) -> void:
	if not _vec3_is_valid(pos) or not is_finite(yaw):
		return
	_body.global_position = pos
	_body.rotation.y = yaw
	_body.linear_velocity = Vector3.ZERO
	_body.angular_velocity = Vector3.ZERO
	_body.place_at_waterline(WaveSurface.WATER_LEVEL)


func _apply_trawling(enabled: bool) -> void:
	var fishing := _body.find_child("FishingSystem", true, false) as FishingSystem
	if fishing == null:
		return
	fishing.apply_trawl_desired(enabled)


func _try_dock_at_port(port_id: String) -> void:
	if port_id.is_empty():
		return
	var dock := AutonomousVesselSim.find_dock(port_id)
	if dock == null:
		return
	var berth := _acquire_berth(dock)
	if berth < 0:
		return
	_berth_dock = dock
	_berth_index = berth
	var plot := dock.get_parent()
	if plot != null and _body.get_parent() != plot:
		_body.reparent(plot)
	dock.register_ship_at_berth(berth, _body, owner_id)
	_body.dock_at_berth(dock, berth)
	_has_pose = true


func _acquire_berth(dock: PortDock) -> int:
	var berths := dock.get_berths()
	for i in range(berths.size()):
		var b := berths[i] as Dictionary
		if str(b.get("owner_id", "")) == owner_id:
			return i
	for i in range(berths.size()):
		if dock.reserve_berth(i, owner_id):
			return i
	return -1


func _reparent_to_world() -> void:
	var world := _world_root()
	if world != null and _body.get_parent() != world:
		_body.reparent(world)


func _world_root() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	if tree.current_scene != null:
		return tree.current_scene
	return tree.root


func snap_to_sample() -> void:
	if _body == null or _record.is_empty():
		return
	var sample := AutonomousVesselSim.sample_at_elapsed(_record, _sim_elapsed())
	if not bool(sample.get("valid", false)):
		return
	var stage: int = int(sample.get("stage", AutonomousVesselSim.Stage.DOCK))
	var pos: Vector3 = sample.get("position", _body.global_position)
	var yaw: float = float(sample.get("yaw", 0.0))
	if not _vec3_is_valid(pos) or not is_finite(yaw):
		return
	if stage == AutonomousVesselSim.Stage.TRANSIT:
		release_berth()
		_reparent_to_world()
		_set_pose(pos, yaw)
	elif _has_berth():
		_apply_transform(_berth_spawn_transform())
	else:
		_try_dock_at_port(str(sample.get("port_id", "")))
	_apply_trawling(bool(sample.get("trawling", false)))
	_update_stage_label(sample)
	_last_stage = stage
	_has_pose = true


static func _vec3_is_valid(v: Vector3) -> bool:
	return v.is_finite() and absf(v.x) < 1.0e8 and absf(v.z) < 1.0e8


func _sim_elapsed() -> float:
	return AutonomousSimDebug.scaled_elapsed(int(_record.get("autonomous_active_at", 0)))


func _ensure_stage_label() -> void:
	if _body == null or _stage_label != null:
		return
	_stage_label = Label3D.new()
	_stage_label.name = "AutonomousStageLabel"
	_stage_label.font_size = 48
	_stage_label.pixel_size = 0.005
	_stage_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_stage_label.no_depth_test = true
	_stage_label.double_sided = true
	_stage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stage_label.modulate = Color(0.92, 0.95, 1.0)
	_stage_label.outline_size = 8
	_stage_label.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
	_stage_label.position = Vector3(0.0, _label_height(), 0.0)
	_body.add_child(_stage_label)


func _update_stage_label(sample: Dictionary) -> void:
	_ensure_stage_label()
	if _stage_label == null:
		return
	if not bool(sample.get("valid", false)):
		_stage_label.visible = false
		return
	_stage_label.visible = true
	var stage_name := str(sample.get("stage_name", "Idle"))
	if not bool(sample.get("active", false)):
		_stage_label.text = stage_name
		return
	var remaining := float(sample.get("stage_remaining_sec", 0.0))
	_stage_label.text = "%s\n%s" % [stage_name, AutonomousVesselSim.format_stage_remaining(remaining)]


func _label_height() -> float:
	if _body == null:
		return 8.0
	if _body.hull_stations != null and _body.hull_stations.height_m > 0.0:
		return _body.hull_stations.height_m * _body.mesh_scale + 2.5
	return _body.hull_size.y + 2.5
