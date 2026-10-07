class_name ProvisionCraneAutoOperator
extends Node

## Auto load/unload for ProvisionCrane — yard container ↔ ship cargo pad.

enum Operation { NONE, LOAD, UNLOAD }
enum Phase {
	IDLE,
	TO_PICKUP,
	LOWER_PICKUP,
	GRAB,
	RAISE_PICKUP,
	TO_DROP,
	LOWER_DROP,
	RELEASE,
	RAISE_EMPTY,
	NEXT,
}

const NEAR_M := 0.22
const OVER_M := 0.25
const WORK_S := 0.45
const TIMEOUT_S := 45.0
const TRAVEL_LIFT_M := 6.0
const YARD_DROP_GROUP := "container_yard_drop"
const CRANE_SCRIPT := preload("res://scripts/port/provision_crane.gd")
const TRAVEL_GIZMO_SEGS := 24

@export var show_target_gizmos := true

signal job_started(operation: Operation)
signal cycle_completed(operation: Operation, cycle_index: int)
signal job_finished(operation: Operation, cycles_completed: int)
signal job_stopped()
signal job_failed(reason: String)
signal phase_changed(phase: Phase)

@export var max_cycles := 0

var operation := Operation.NONE

var _crane: CRANE_SCRIPT
var _ship: BoatBody
var _pickup: ContainerNode
var _drop_pad: CargoSlotPadComponent
var _yard_pad: CargoSlotPadComponent
var _drop_world := Vector3.ZERO
var _drop_local := Vector3.ZERO
var _lift_height := 0.0
var _movement_recorded := false
var _phase := Phase.IDLE
var _timer := 0.0
var _cycles := 0
var _active := false
var _did_act := false

var _gizmos: Node3D
var _g_a: MeshInstance3D
var _g_b: MeshInstance3D
var _g_aim: MeshInstance3D
var _g_hook: MeshInstance3D
var _g_gap: MeshInstance3D
var _g_travel: Array[MeshInstance3D] = []


func _ready() -> void:
	add_to_group("provision_crane_auto")
	_crane = get_parent() as CRANE_SCRIPT
	if _crane == null:
		push_warning("ProvisionCraneAutoOperator: parent must be ProvisionCrane")
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


func get_status_line() -> String:
	if not _active:
		return "Auto  idle"
	var op := "LOAD" if operation == Operation.LOAD else "UNLOAD"
	return "Auto  %s · %s · cycle %d" % [op, _phase_label(), _cycles + 1]


func stop() -> void:
	var was_active := _active
	_clear_operation()
	if was_active:
		job_stopped.emit()


func _clear_operation() -> void:
	_active = false
	operation = Operation.NONE
	_ship = null
	_pickup = null
	_drop_pad = null
	_yard_pad = null
	_drop_world = Vector3.ZERO
	_set_phase(Phase.IDLE)
	_update_gizmos()


func get_progress_label() -> String:
	return "%s · %s · container %d" % ["Loading" if operation == Operation.LOAD else "Unloading", _phase_label(), _cycles + 1] if _active else "idle"


func _finish() -> void:
	var completed_op := operation
	var count := _cycles
	_clear_operation()
	job_finished.emit(completed_op, count)


func _fail(reason: String) -> void:
	# A failed or cancelled lift keeps its cargo attached. Never leave a floating
	# unregistered box behind and never report a failed transfer as completion.
	_clear_operation()
	job_failed.emit(reason)


func start_load(ship: BoatBody) -> bool:
	return _begin(Operation.LOAD, ship)


func start_unload(ship: BoatBody) -> bool:
	return _begin(Operation.UNLOAD, ship)


func _begin(op: Operation, ship: BoatBody) -> bool:
	if _active or _crane == null or ship == null or not is_instance_valid(ship):
		return false
	if not _crane.can_reach_ship(ship):
		return false
	_clear_operation()
	operation = op
	_ship = ship
	_cycles = 0
	if not _prepare_cycle():
		_clear_operation()
		return false
	_active = true
	job_started.emit(operation)
	return true


func _process(delta: float) -> void:
	if not _active or _crane == null:
		return
	if not is_instance_valid(_ship) or (not _movement_recorded and not is_instance_valid(_pickup)):
		_fail("The cargo or vessel is no longer available.")
		return
	if _timer > TIMEOUT_S:
		_fail("Crane could not align with the cargo bed. Cargo is still secured; reposition the vessel and retry.")
		return
	_timer += delta
	match _phase:
		Phase.TO_PICKUP:
			_crane.ik_hook_to(delta, _aim_point(_pickup, true), "raise")
			if _hook_over(_aim_point(_pickup, true), OVER_M):
				_set_phase(Phase.LOWER_PICKUP)
		Phase.LOWER_PICKUP:
			_crane.ik_hook_to(delta, _aim_point(_pickup, false), "track")
			if _hook_near(_aim_point(_pickup, false), NEAR_M):
				_set_phase(Phase.GRAB)
		Phase.GRAB:
			if not _did_act:
				_did_act = true
				if not _crane.attach_container(_pickup):
					_fail("Cargo pickup failed; the container has not been moved.")
					return
			if _crane.get_attached_container() == _pickup:
				_set_phase(Phase.RAISE_PICKUP)
		Phase.RAISE_PICKUP:
			# Raise vertically before slewing a loaded container over the quay.
			_crane.ik_hook_to(delta, _crane.get_hook_global(), "raise")
			if _crane.hoist_length_m <= _crane.hoist_min_m + 2.05:
				_set_phase(Phase.TO_DROP)
		Phase.TO_DROP:
			_crane.ik_hook_to(delta, _drop_aim(true), "raise")
			if _hook_over(_drop_aim(true), OVER_M):
				_set_phase(Phase.LOWER_DROP)
		Phase.LOWER_DROP:
			_crane.ik_hook_to(delta, _drop_aim(false), "track")
			var destination := _destination_pad()
			if not is_instance_valid(destination):
				_fail("The cargo bed is no longer available.")
				return
			_crane.align_attached_container(destination.global_basis.orthonormalized(), delta)
			if _hook_near(_drop_aim(false), NEAR_M):
				_set_phase(Phase.RELEASE)
		Phase.RELEASE:
			if not _did_act:
				_did_act = true
				# The selected bed, not whichever overlapping pad is found first.
				var target := _destination_pad()
				if not is_instance_valid(target) or _crane.release_container_on_pad(target) == null:
					_fail("The selected cargo bed is occupied or out of alignment. Cargo remains on the hook.")
					return
				_movement_recorded = _report_freight_movement()
				if not _movement_recorded:
					_fail("Cargo landed, but freight confirmation failed. Check the contract before continuing.")
					return
			if _crane.get_attached_container() == null:
				_set_phase(Phase.RAISE_EMPTY)
		Phase.RAISE_EMPTY:
			_crane.ik_hook_to(delta, _drop_aim(true), "raise")
			if _crane.hoist_length_m <= _crane.hoist_min_m + 2.05:
				_set_phase(Phase.NEXT)
		Phase.NEXT:
			_finish_cycle()
		_:
			pass
	_update_gizmos()


func _prepare_cycle() -> bool:
	_did_act = false
	_timer = 0.0
	_drop_pad = null
	_yard_pad = null
	_drop_world = Vector3.ZERO
	_movement_recorded = false
	var suspended := _crane.get_attached_container()
	if operation == Operation.LOAD:
		_pickup = suspended if is_instance_valid(suspended) else _find_yard_pickup(_ship)
		if not is_instance_valid(_pickup) or not _is_loadable_here(_pickup, _ship): return false
		var drop := _find_ship_drop(_ship, _pickup.unit)
		if _pickup == null or drop.is_empty():
			return false
		_drop_pad = drop["pad"] as CargoSlotPadComponent
		_drop_world = drop["world"] as Vector3
	else:
		_pickup = suspended if is_instance_valid(suspended) else _find_ship_pickup(_ship)
		_yard_pad = _find_yard_pad()
		if _pickup == null or not _is_deliverable_here(_pickup, _ship) or _yard_pad == null:
			return false
		_drop_world = _yard_pad.slot_drop_world_for_free(_pickup.unit.footprint_cells(_yard_pad.cell_size_m))
		if _drop_world == Vector3.INF:
			return false
	_drop_local = _destination_pad().to_local(_drop_world)
	_lift_height = _pickup.lift_height_m()
	if not _crane.can_reach_point(_drop_aim(false), .1): return false
	_set_phase(Phase.RAISE_PICKUP if is_instance_valid(suspended) else Phase.TO_PICKUP)
	return true


func _finish_cycle() -> void:
	if not _movement_recorded:
		_fail("Cargo transfer was not confirmed.")
		return
	_cycles += 1
	cycle_completed.emit(operation, _cycles)
	if max_cycles > 0 and _cycles >= max_cycles:
		_finish()
		return
	if not _prepare_cycle(): _finish()


func _aim_point(node: ContainerNode, raised: bool) -> Vector3:
	if node == null or not is_instance_valid(node):
		return _crane.get_hook_global()
	var p := node.to_global(Vector3.UP * node.lift_height_m())
	if raised:
		p.y += TRAVEL_LIFT_M
	return p


func _hook_near(target: Vector3, radius_m: float) -> bool:
	return _crane.get_hook_global().distance_to(target) <= radius_m


func _hook_over(target: Vector3, radius_m: float) -> bool:
	var hook := _crane.get_hook_global()
	return Vector2(target.x - hook.x, target.z - hook.z).length() <= radius_m


func _drop_aim(raised: bool) -> Vector3:
	var p := _drop_world
	var pad := _destination_pad()
	if is_instance_valid(pad):
		var offset := ContainerNode.floor_offset_y() if pad.show_pad_visual else 0.0
		p = pad.to_global(_drop_local + Vector3.UP * (_lift_height + offset))
	if raised:
		p.y += TRAVEL_LIFT_M
	return p


func _destination_pad() -> CargoSlotPadComponent:
	return _drop_pad if operation == Operation.LOAD else _yard_pad


func _find_yard_pickup(ship: BoatBody) -> ContainerNode:
	if _crane == null or not _crane.is_inside_tree():
		return null
	var yard := _find_yard_pad()
	if yard == null:
		return null
	var best: ContainerNode = null
	var best_d := INF
	for node in _crane.get_tree().get_nodes_in_group(ContainerNode.GROUP):
		if node is not ContainerNode:
			continue
		var cn := node as ContainerNode
		if cn.unit == null: continue
		if CargoSlotPadComponent.is_on_ship_pad(cn):
			continue
		if _crane.get_attached_container() == cn:
			continue
		var fits := false
		for pad in ship.get_cargo_pads():
			if pad.find_free_slot(cn.unit.footprint_cells(pad.cell_size_m)) >= 0: fits = true
		if not fits or not _is_loadable_here(cn, ship):
			continue
		## Prefer cargo on this crane's yard when several berths share the scene.
		if not yard.contains_node(cn): continue
		if not _crane.can_reach_point(_aim_point(cn, false), .1): continue
		var d := _crane.get_hook_global().distance_to(cn.global_position)
		if d < best_d:
			best_d = d
			best = cn
	return best


func _is_loadable_here(container: ContainerNode, ship: BoatBody) -> bool:
	if container == null or container.unit == null or ship == null:
		return false
	var freight := get_node_or_null("/root/FreightService")
	return freight != null \
		and freight.has_method("can_load_unit") \
		and bool(freight.call("can_load_unit", container.unit,
			ship.get_harbour_port_id(), ship))


func _find_ship_pickup(ship: BoatBody) -> ContainerNode:
	if ship == null:
		return null
	var best: ContainerNode = null
	var best_y := -INF
	for pad in ship.get_cargo_pads():
		for cn in pad.iter_container_nodes():
			if not _is_deliverable_here(cn, ship):
				continue
			if cn.global_position.y > best_y:
				best_y = cn.global_position.y
				best = cn
	return best


func _is_deliverable_here(container: ContainerNode, ship: BoatBody) -> bool:
	if container == null or container.unit == null or ship == null:
		return false
	var freight := get_node_or_null("/root/FreightService")
	return freight != null \
		and freight.has_method("can_deliver_unit") \
		and bool(freight.call(
			"can_deliver_unit",
			container.unit,
			ship.get_harbour_port_id(),
			ship,
		))


func _report_freight_movement() -> bool:
	if _pickup == null or not is_instance_valid(_pickup) or _pickup.unit == null or _ship == null:
		return false
	var freight := get_node_or_null("/root/FreightService")
	if freight == null:
		return false
	var port_id := _ship.get_harbour_port_id()
	if operation == Operation.LOAD and CargoSlotPadComponent.is_on_ship_pad(_pickup):
		return bool(freight.call("record_unit_loaded", _pickup.unit, port_id, _ship))
	elif operation == Operation.UNLOAD and CargoSlotPadComponent.is_on_yard_pad(_pickup):
		var recorded := bool(freight.call("record_unit_delivered", _pickup.unit, port_id, _ship))
		if recorded and _yard_pad != null:
			_yard_pad.take_container_node(_pickup)
			_pickup.queue_free()
		return recorded
	return false


func _find_ship_drop(ship: BoatBody, unit: ContainerUnit = null) -> Dictionary:
	if ship == null:
		return {}
	for pad in ship.get_cargo_pads():
		var world := pad.slot_drop_world_for_free(unit.footprint_cells(pad.cell_size_m) if unit != null else Vector2i.ZERO)
		if world != Vector3.INF and _crane.can_reach_point(world, .1):
			return {"pad": pad, "world": world}
	return {}


func _yard_drop_world() -> Vector3:
	if _crane == null or not _crane.is_inside_tree():
		return Vector3.ZERO
	var pad := _find_yard_pad()
	if pad != null:
		var slot := pad.slot_drop_world_for_free()
		if slot != Vector3.INF:
			return slot
		return pad.global_position
	var yard := _crane.get_tree().get_first_node_in_group(YARD_DROP_GROUP)
	if yard != null:
		return yard.global_position
	return _crane.global_position + Vector3(-18.0, 0.0, -20.0)


func _find_yard_pad() -> CargoSlotPadComponent:
	if _crane == null or not _crane.is_inside_tree():
		return null
	return CargoSlotPadComponent.find_nearest_yard_pad(
		_crane.get_tree(),
		_crane.get_hook_global(),
		_serving_berth_id(),
		_serving_equipment_id(),
	)


func _serving_berth_id() -> String:
	if _crane == null:
		return ""
	for child in _crane.get_children():
		if child is QuayEquipmentJob:
			return (child as QuayEquipmentJob).berth_id()
	return ""


func _serving_equipment_id() -> String:
	if _crane == null:
		return ""
	for child in _crane.get_children():
		if child is QuayEquipmentJob:
			return (child as QuayEquipmentJob).equipment_id()
	return ""


func _yard_has_free_slot() -> bool:
	var pad := _find_yard_pad()
	return pad != null and pad.find_free_slot() >= 0


func _set_phase(phase: Phase) -> void:
	_phase = phase
	_timer = 0.0
	_did_act = false
	phase_changed.emit(phase)


func _phase_label() -> String:
	match _phase:
		Phase.TO_PICKUP: return "to pickup"
		Phase.LOWER_PICKUP: return "lower pickup"
		Phase.GRAB: return "grab"
		Phase.RAISE_PICKUP: return "raise"
		Phase.TO_DROP: return "to drop"
		Phase.LOWER_DROP: return "lower drop"
		Phase.RELEASE: return "release"
		Phase.RAISE_EMPTY: return "clear"
		Phase.NEXT: return "next"
		_: return "idle"


func point_a() -> Vector3:
	return _aim_point(_pickup, true)


func point_b() -> Vector3:
	return _drop_aim(true)


func travel_point(t: float) -> Vector3:
	return point_a().lerp(point_b(), clampf(t, 0.0, 1.0))


func _current_aim() -> Vector3:
	match _phase:
		Phase.TO_PICKUP, Phase.LOWER_PICKUP, Phase.GRAB, Phase.RAISE_PICKUP:
			return _aim_point(_pickup, _phase != Phase.LOWER_PICKUP and _phase != Phase.GRAB)
		Phase.TO_DROP, Phase.LOWER_DROP, Phase.RELEASE, Phase.RAISE_EMPTY:
			return _drop_aim(_phase != Phase.LOWER_DROP and _phase != Phase.RELEASE)
		_:
			return _crane.get_hook_global() if _crane != null else Vector3.ZERO


func _build_gizmos() -> void:
	_gizmos = Node3D.new()
	_gizmos.name = "TargetGizmos"
	add_child(_gizmos)
	_g_a = _sphere(Color(0.2, 0.95, 0.35, 0.6), 0.9)
	_g_b = _sphere(Color(0.98, 0.55, 0.12, 0.6), 0.9)
	_g_aim = _sphere(Color(0.98, 0.95, 0.2, 0.85), 0.55)
	_g_hook = _sphere(Color(0.95, 0.2, 0.55, 0.8), 0.45)
	_g_gap = _line(Color(0.95, 0.35, 0.95, 0.7), 0.08)
	for n in [_g_a, _g_b, _g_aim, _g_hook, _g_gap]:
		_gizmos.add_child(n)
	for i in range(TRAVEL_GIZMO_SEGS):
		var seg := _line(Color(0.55, 0.85, 1.0, 0.45), 0.1)
		seg.name = "TravelSeg_%d" % i
		_gizmos.add_child(seg)
		_g_travel.append(seg)


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


func _update_gizmos() -> void:
	if _gizmos == null:
		return
	_gizmos.visible = show_target_gizmos \
		and WorldGizmos.is_layer_enabled(WorldGizmos.LAYER_CRANES) and _active
	if not _gizmos.visible or _crane == null:
		return
	var a := point_a()
	var b := point_b()
	var aim := _current_aim()
	var hook := _crane.get_hook_global()
	_g_a.global_position = a
	_g_b.global_position = b
	_g_aim.global_position = aim
	_g_hook.global_position = hook
	_stretch(_g_gap, hook, aim)
	for i in range(_g_travel.size()):
		var t0 := float(i) / float(TRAVEL_GIZMO_SEGS)
		var t1 := float(i + 1) / float(TRAVEL_GIZMO_SEGS)
		_stretch(_g_travel[i], travel_point(t0), travel_point(t1))
