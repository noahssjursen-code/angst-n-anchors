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

const NEAR_M := 3.5
const OVER_M := 4.0
const WORK_S := 0.45
const TIMEOUT_S := 18.0
const TRAVEL_LIFT_M := 6.0
const YARD_DROP_GROUP := "container_yard_drop"

signal job_started(operation: Operation)
signal cycle_completed(operation: Operation, cycle_index: int)
signal job_finished(operation: Operation, cycles_completed: int)
signal job_stopped()
signal phase_changed(phase: Phase)

@export var max_cycles := 0

var operation := Operation.NONE

var _crane: ProvisionCrane
var _ship: BoatBody
var _pickup: ContainerNode
var _drop_pad: CargoSlotPadComponent
var _drop_world := Vector3.ZERO
var _phase := Phase.IDLE
var _timer := 0.0
var _cycles := 0
var _active := false
var _did_act := false


func _ready() -> void:
	add_to_group("provision_crane_auto")
	_crane = get_parent() as ProvisionCrane
	if _crane == null:
		push_warning("ProvisionCraneAutoOperator: parent must be ProvisionCrane")


func is_active() -> bool:
	return _active


func get_status_line() -> String:
	if not _active:
		return "Auto  idle"
	var op := "LOAD" if operation == Operation.LOAD else "UNLOAD"
	return "Auto  %s · %s · cycle %d" % [op, _phase_label(), _cycles + 1]


func stop() -> void:
	_active = false
	operation = Operation.NONE
	_ship = null
	_pickup = null
	_drop_pad = null
	_drop_world = Vector3.ZERO
	_set_phase(Phase.IDLE)
	job_stopped.emit()


func start_load(ship: BoatBody) -> bool:
	return _begin(Operation.LOAD, ship)


func start_unload(ship: BoatBody) -> bool:
	return _begin(Operation.UNLOAD, ship)


func _begin(op: Operation, ship: BoatBody) -> bool:
	if _crane == null or ship == null or not is_instance_valid(ship):
		return false
	if not _crane.can_reach_ship(ship):
		return false
	if op == Operation.LOAD and (_find_yard_pickup() == null or _find_ship_drop(ship) == null):
		return false
	if op == Operation.UNLOAD and _find_ship_pickup(ship) == null:
		return false
	stop()
	_active = true
	operation = op
	_ship = ship
	_cycles = 0
	_prepare_cycle()
	job_started.emit(operation)
	return true


func _process(delta: float) -> void:
	if not _active or _crane == null:
		return
	_timer += delta
	match _phase:
		Phase.TO_PICKUP:
			_crane.ik_hook_to(delta, _aim_point(_pickup, true), "raise")
			if _crane.is_hook_over(_aim_point(_pickup, true), OVER_M):
				_set_phase(Phase.LOWER_PICKUP)
		Phase.LOWER_PICKUP:
			_crane.ik_hook_to(delta, _aim_point(_pickup, false), "track")
			if _crane.is_hook_near(_aim_point(_pickup, false), NEAR_M) or _timer > TIMEOUT_S:
				_set_phase(Phase.GRAB)
		Phase.GRAB:
			if not _did_act:
				_did_act = true
				if _pickup != null and is_instance_valid(_pickup):
					_crane.attach_container(_pickup)
			if _crane.get_attached_container() != null or _timer > WORK_S:
				_set_phase(Phase.RAISE_PICKUP)
		Phase.RAISE_PICKUP:
			_crane.ik_hook_to(delta, _aim_point(_pickup, true), "raise")
			if _crane.hoist_length_m <= _crane.hoist_min_m + 2.5 or _timer > TIMEOUT_S:
				_set_phase(Phase.TO_DROP)
		Phase.TO_DROP:
			_crane.ik_hook_to(delta, _drop_aim(true), "raise")
			if _crane.is_hook_over(_drop_aim(true), OVER_M):
				_set_phase(Phase.LOWER_DROP)
		Phase.LOWER_DROP:
			_crane.ik_hook_to(delta, _drop_aim(false), "track")
			if _crane.is_hook_near(_drop_aim(false), NEAR_M) or _timer > TIMEOUT_S:
				_set_phase(Phase.RELEASE)
		Phase.RELEASE:
			if not _did_act:
				_did_act = true
				if operation == Operation.LOAD:
					_crane.release_container()
				else:
					_crane.release_container_to_world(_drop_world)
			if _crane.get_attached_container() == null or _timer > WORK_S:
				_set_phase(Phase.RAISE_EMPTY)
		Phase.RAISE_EMPTY:
			_crane.ik_hook_to(delta, _drop_aim(true), "raise")
			if _crane.hoist_length_m <= _crane.hoist_min_m + 2.5 or _timer > TIMEOUT_S:
				_set_phase(Phase.NEXT)
		Phase.NEXT:
			_finish_cycle()
		_:
			pass


func _prepare_cycle() -> void:
	_did_act = false
	_timer = 0.0
	_drop_pad = null
	_drop_world = Vector3.ZERO
	if operation == Operation.LOAD:
		_pickup = _find_yard_pickup()
		var drop := _find_ship_drop(_ship)
		if _pickup == null or drop.is_empty():
			stop()
			return
		_drop_pad = drop["pad"] as CargoSlotPadComponent
		_drop_world = drop["world"] as Vector3
	else:
		_pickup = _find_ship_pickup(_ship)
		_drop_world = _yard_drop_world()
		if _pickup == null:
			stop()
			return
	_set_phase(Phase.TO_PICKUP)


func _finish_cycle() -> void:
	_cycles += 1
	cycle_completed.emit(operation, _cycles)
	if max_cycles > 0 and _cycles >= max_cycles:
		var done_op := operation
		var n := _cycles
		stop()
		job_finished.emit(done_op, n)
		return
	if operation == Operation.LOAD:
		if _find_yard_pickup() == null or _find_ship_drop(_ship) == null:
			var done_op := operation
			var n := _cycles
			stop()
			job_finished.emit(done_op, n)
			return
	if operation == Operation.UNLOAD and _find_ship_pickup(_ship) == null:
		var done_op := operation
		var n := _cycles
		stop()
		job_finished.emit(done_op, n)
		return
	_prepare_cycle()


func _aim_point(node: ContainerNode, raised: bool) -> Vector3:
	if node == null or not is_instance_valid(node):
		return _crane.get_hook_global()
	var p := node.global_position
	p.y += ContainerUnit.DEFAULT_HEIGHT_M * 0.5
	if raised:
		p.y += TRAVEL_LIFT_M
	return p


func _drop_aim(raised: bool) -> Vector3:
	var p := _drop_world
	if raised:
		p.y += TRAVEL_LIFT_M
	return p


func _find_yard_pickup() -> ContainerNode:
	if _crane == null or not _crane.is_inside_tree():
		return null
	var best: ContainerNode = null
	var best_d := INF
	for node in _crane.get_tree().get_nodes_in_group(ContainerNode.GROUP):
		if node is not ContainerNode:
			continue
		var cn := node as ContainerNode
		if CargoSlotPadComponent.find_pad_for_node(cn) != null:
			continue
		if _crane.get_attached_container() == cn:
			continue
		var d := _crane.get_hook_global().distance_to(cn.global_position)
		if d < best_d:
			best_d = d
			best = cn
	return best


func _find_ship_pickup(ship: BoatBody) -> ContainerNode:
	if ship == null:
		return null
	var best: ContainerNode = null
	var best_y := -INF
	for pad in ship.get_cargo_pads():
		for cn in pad.iter_container_nodes():
			if cn.global_position.y > best_y:
				best_y = cn.global_position.y
				best = cn
	return best


func _find_ship_drop(ship: BoatBody) -> Dictionary:
	if ship == null:
		return {}
	for pad in ship.get_cargo_pads():
		var world := pad.slot_drop_world_for_free()
		if world != Vector3.INF:
			return {"pad": pad, "world": world}
	return {}


func _yard_drop_world() -> Vector3:
	if _crane == null or not _crane.is_inside_tree():
		return Vector3.ZERO
	var yard := _crane.get_tree().get_first_node_in_group(YARD_DROP_GROUP)
	if yard != null:
		return yard.global_position
	return _crane.global_position + Vector3(-18.0, 0.0, -20.0)


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
