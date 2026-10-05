class_name ShipPartState
extends Node

## Visual state consumer. Requests are commands; snapshots are authority output.
## Remote mode never applies a request optimistically. Bind request_sent to authority.
signal request_sent(action: String, value: Variant)
signal state_applied(state: Dictionary, revision: int)
var local_authority := false
var revision := -1
var state := {"steering":0.0,"throttle":0.0,"door_open":false,"door_swing":1.0,"occupied":false,"powered":true}
var current_steering := 0.0
var current_throttle := 0.0
var current_door := 0.0
var visual: Node3D
var local_helm: BoatController

func _init() -> void:
	process_physics_priority = -20

func setup(root: Node3D, local: bool = false) -> void:
	visual=root
	local_authority=local

func request(action: String, value: Variant = null) -> void:
	if not action in ["steering","throttle","door_open","door_swing","occupied","powered"]: return
	request_sent.emit(action,value)
	if local_authority:
		var next := state.duplicate()
		next[action]=not bool(state[action]) if value==null and state[action] is bool else value
		apply_snapshot(next,revision+1)

## Opening direction is chosen in the authored hinge frame, not from wall draw order.
## Keep that direction through closing; changing it mid-swing would teleport the leaf.
func request_door_from(world_position: Vector3) -> void:
	if not is_instance_valid(visual): return
	if not bool(state["door_open"]) and current_door <= .001:
		var pivots := visual.find_children("DoorLeafPivot*", "Node3D", true, false)
		if not pivots.is_empty():
			var local: Vector3 = (pivots[0] as Node3D).to_local(world_position)
			request("door_swing", 1.0 if local.x >= 0.0 else -1.0)
	request("door_open")

func apply_snapshot(snapshot: Dictionary, sequence: int, immediate: bool = false) -> bool:
	if sequence<=revision: return false
	var next := state.duplicate()
	for key in snapshot:
		if not state.has(key): return false
		var value: Variant=snapshot[key]
		if key in ["steering","throttle","door_swing"]:
			if not (value is float or value is int) or not is_finite(float(value)): return false
			next[key]=clampf(float(value),-1,1)
			if key == "door_swing" and absf(float(value)) != 1.0: return false
		elif value is bool: next[key]=value
		else: return false
	state=next;revision=sequence
	if immediate:
		current_steering=state["steering"];current_throttle=state["throttle"];current_door=1.0 if state["door_open"] else 0.0
		_pose()
	state_applied.emit(state.duplicate(),revision)
	return true

func bind_local_helm(controller: BoatController) -> void:
	local_helm=controller
	local_authority=false

func _physics_process(delta: float) -> void:
	if is_instance_valid(local_helm): apply_snapshot(local_helm.get_helm_visual_state(),revision+1)
	current_steering=move_toward(current_steering,float(state["steering"]),delta*2)
	current_throttle=move_toward(current_throttle,float(state["throttle"]),delta*2)
	current_door=move_toward(current_door,1.0 if state["door_open"] else 0.0,delta*1.5)
	_pose()

func _pose() -> void:
	if not is_instance_valid(visual): return
	for pivot in visual.find_children("WheelPivot*","Node3D",true,false): pivot.rotation.z=-current_steering*TAU
	for pivot in visual.find_children("ThrottlePivot*","Node3D",true,false): pivot.rotation.x=current_throttle*.65
	for pivot in visual.find_children("DoorLeafPivot*","Node3D",true,false): pivot.rotation.y=current_door*float(state["door_swing"])*deg_to_rad(110.0)
	visual.set_meta("occupied",state["occupied"])
	visual.set_meta("powered",state["powered"])
