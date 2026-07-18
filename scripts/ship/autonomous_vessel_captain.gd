class_name AutonomousVesselCaptain
extends Node

## Server-authoritative captain layered over the shared VesselAutopilot.
## It owns harbour decisions and low-speed manoeuvres; route following remains
## identical to player autopilot.

signal phase_changed(phase: int)
signal voyage_completed(contract_id: String)
signal voyage_failed(reason: String)

enum Phase {
	IDLE,
	RESERVING,
	CASTING_OFF,
	CRAB_CLEAR,
	DEPARTURE,
	PASSAGE,
	WAITING_APPROACH,
	APPROACH,
	ALIGNING,
	CRAB_BERTH,
	SECURING,
	MOORED,
	FAILED,
}

const CRAB_EXTRA_CLEARANCE_M := 5.0
const ALIGN_TOLERANCE_DEG := 5.0
const BERTH_POSITION_TOLERANCE_M := 3.5
const BERTH_SPEED_TOLERANCE_MS := 0.8
const TRAFFIC_LEASE_REFRESH_S := 15.0

var phase := Phase.IDLE
var contract_id := ""
var origin_port_id := ""
var origin_berth_id := ""
var destination_port_id := ""
var destination_berth_id := ""
var destination_family := ""

var _body: BoatBody
var _autopilot: VesselAutopilot
var _propulsion: PropulsionComponent
var _rudder: RudderComponent
var _thruster: BowThrusterComponent
var _mooring: MooringComponent
var _crab_origin := Vector3.ZERO
var _crab_direction := Vector3.ZERO
var _destination_slot: QuayBerthSlot
var _lease_refresh_s := 0.0
var _lane_refresh_s := 0.0
var _origin_lane_released := false


func _ready() -> void:
	_body = get_parent() as BoatBody
	if _body == null:
		push_error("AutonomousVesselCaptain must be a child of BoatBody")
		return
	_autopilot = _body.get_node_or_null("VesselAutopilot") as VesselAutopilot
	if _autopilot == null:
		_autopilot = VesselAutopilot.new()
		_autopilot.name = "VesselAutopilot"
		_body.add_child.call_deferred(_autopilot)
	_propulsion = _body.get_node_or_null("PropulsionComponent") as PropulsionComponent
	_rudder = _body.get_node_or_null("RudderComponent") as RudderComponent
	_thruster = _body.get_node_or_null("BowThrusterComponent") as BowThrusterComponent
	_mooring = _body.get_node_or_null("ShipGameplay/MooringComponent") as MooringComponent
	call_deferred("_wire_autopilot")


func _wire_autopilot() -> void:
	if _autopilot != null and not _autopilot.disengaged.is_connected(_on_autopilot_disengaged):
		_autopilot.disengaged.connect(_on_autopilot_disengaged)


func assign_voyage(
	next_contract_id: String,
	from_port_id: String,
	from_berth_id: String,
	to_port_id: String,
	berth_family: String = "",
) -> bool:
	if _body == null or to_port_id.is_empty():
		return false
	contract_id = next_contract_id
	origin_port_id = from_port_id
	origin_berth_id = from_berth_id
	destination_port_id = to_port_id
	destination_family = berth_family
	destination_berth_id = ""
	_origin_lane_released = false
	_set_phase(Phase.RESERVING)
	return true


func authority_snapshot() -> Dictionary:
	return {
		"contract_id": contract_id,
		"phase": phase,
		"origin_port_id": origin_port_id,
		"origin_berth_id": origin_berth_id,
		"destination_port_id": destination_port_id,
		"destination_berth_id": destination_berth_id,
		"navigation": _autopilot.voyage_snapshot() if _autopilot != null else {},
	}


func _physics_process(delta: float) -> void:
	_maintain_destination_lease(delta)
	_maintain_lane_lock(delta)
	match phase:
		Phase.RESERVING:
			_try_reserve_and_depart()
		Phase.CASTING_OFF:
			_cast_off()
		Phase.CRAB_CLEAR:
			_crab_clear()
		Phase.PASSAGE:
			_release_origin_lane_when_clear()
		Phase.WAITING_APPROACH:
			_try_begin_approach()
		Phase.ALIGNING:
			_align_at_berth()
		Phase.CRAB_BERTH:
			_crab_into_berth()
		Phase.SECURING:
			_secure_lines()


func _try_reserve_and_depart() -> void:
	var destination := HarbourRegistry.controller(destination_port_id)
	var origin := HarbourRegistry.controller(origin_port_id)
	if destination == null or origin == null:
		return
	var vessel_id := HarbourController.ship_id_of(_body)
	destination_berth_id = destination.request_berth_reservation(
		vessel_id,
		_body.hull_size.z,
		destination_family,
	)
	if destination_berth_id.is_empty():
		return
	if not origin.request_lane_lock(origin_berth_id, vessel_id, "departure"):
		return
	_set_phase(Phase.CASTING_OFF)


func _cast_off() -> void:
	_zero_actuators()
	if _mooring != null and _mooring.is_moored:
		_mooring.release_mooring()
		return
	var origin := HarbourRegistry.controller(origin_port_id)
	var slot := origin.berth(origin_berth_id) if origin != null else null
	if slot == null:
		_fail("origin_berth_missing")
		return
	_crab_origin = _body.global_position
	_crab_direction = slot.global_transform.basis * slot.water_dir_local
	_crab_direction.y = 0.0
	_crab_direction = _crab_direction.normalized()
	_set_phase(Phase.CRAB_CLEAR)


func _crab_clear() -> void:
	if _thruster == null or _crab_direction.length_squared() < 0.5:
		_fail("crab_thruster_unavailable")
		return
	var cleared := (_body.global_position - _crab_origin).dot(_crab_direction)
	var target_clearance := maxf(_body.get_half_beam_m() * 0.65, CRAB_EXTRA_CLEARANCE_M)
	if cleared >= target_clearance:
		_zero_actuators()
		_begin_departure_route()
		return
	_propulsion.throttle = 0.0
	_rudder.rudder_input = 0.0
	_thruster.crab_mode = true
	var local_away := _body.global_transform.basis.inverse() * _crab_direction
	_thruster.lateral_input = clampf(local_away.x * 1.5, -1.0, 1.0)


func _begin_departure_route() -> void:
	var origin := HarbourRegistry.controller(origin_port_id)
	var destination := HarbourRegistry.controller(destination_port_id)
	if origin == null or destination == null:
		_fail("harbour_unavailable")
		return
	var origin_slot := origin.berth(origin_berth_id)
	_destination_slot = destination.berth(destination_berth_id)
	if origin_slot == null or _destination_slot == null:
		_fail("berth_unavailable")
		return
	var destination_lane_kind := BerthApproachLanes.best_approach_lane_kind(
		_destination_slot.global_position,
		_body.global_position,
		destination_port_id,
	)
	var destination_lane := BerthApproachLanes.get_target_lane(
		destination_port_id, destination_berth_id, destination_lane_kind
	)
	if destination_lane.size() < 2:
		_fail("destination_lane_unavailable")
		return
	var destination_outer := destination_lane[-1] as Vector3
	var world := get_tree().get_first_node_in_group("world")
	var layout := world.call("get_world_layout") as WorldLayout if world != null else null
	if layout == null:
		_fail("navigation_unavailable")
		return
	var planner := MarineRoutePlanner.new(layout)
	var plan := planner.plan_departure(
		Vector2(_body.global_position.x, _body.global_position.z),
		Vector2(destination_outer.x, destination_outer.z),
		origin_port_id,
		origin_berth_id,
		destination_port_id,
	)
	if not _autopilot.engage(plan, -1.0, 45.0):
		_fail("passage_route_failed")
		return
	_set_phase(Phase.PASSAGE)


func _try_begin_approach() -> void:
	var destination := HarbourRegistry.controller(destination_port_id)
	if destination == null:
		return
	var vessel_id := HarbourController.ship_id_of(_body)
	if not destination.request_lane_lock(destination_berth_id, vessel_id, "approach"):
		return
	_destination_slot = destination.berth(destination_berth_id)
	if _destination_slot == null:
		_fail("destination_berth_missing")
		return
	var lane_kind := BerthApproachLanes.best_approach_lane_kind(
		_destination_slot.global_position, _body.global_position, destination_port_id
	)
	var lane := BerthApproachLanes.get_target_lane(destination_port_id, destination_berth_id, lane_kind)
	if lane.size() < 2:
		_fail("approach_lane_unavailable")
		return
	var points := PackedVector2Array()
	for i in range(lane.size() - 1, -1, -1):
		var point := lane[i] as Vector3
		points.append(Vector2(point.x, point.z))
	var plan := MarineRoutePlan.create(points, "harbour:%s" % destination_port_id,
		origin_port_id, destination_port_id)
	if not _autopilot.engage(plan, -1.0, 18.0):
		_fail("approach_route_failed")
		return
	_set_phase(Phase.APPROACH)


func _maintain_destination_lease(delta: float) -> void:
	if destination_berth_id.is_empty() or phase in [Phase.IDLE, Phase.MOORED, Phase.FAILED]:
		return
	_lease_refresh_s += delta
	if _lease_refresh_s < 30.0:
		return
	_lease_refresh_s = 0.0
	var destination := HarbourRegistry.controller(destination_port_id)
	if destination != null:
		destination.request_berth_reservation(
			HarbourController.ship_id_of(_body),
			_body.hull_size.z,
			destination_family,
			destination_berth_id,
		)


func _maintain_lane_lock(delta: float) -> void:
	if phase not in [Phase.CRAB_CLEAR, Phase.DEPARTURE, Phase.APPROACH, Phase.ALIGNING, Phase.CRAB_BERTH]:
		_lane_refresh_s = 0.0
		return
	_lane_refresh_s += delta
	if _lane_refresh_s < TRAFFIC_LEASE_REFRESH_S:
		return
	_lane_refresh_s = 0.0
	var vessel_id := HarbourController.ship_id_of(_body)
	if phase in [Phase.CRAB_CLEAR, Phase.DEPARTURE]:
		var origin := HarbourRegistry.controller(origin_port_id)
		if origin != null:
			origin.request_lane_lock(origin_berth_id, vessel_id, "departure")
	else:
		var destination := HarbourRegistry.controller(destination_port_id)
		if destination != null:
			destination.request_lane_lock(destination_berth_id, vessel_id, "approach")


func _release_origin_lane_when_clear() -> void:
	if _origin_lane_released or _autopilot == null or _autopilot.progress_m < 500.0:
		return
	var origin := HarbourRegistry.controller(origin_port_id)
	if origin != null:
		origin.release_lane_lock(HarbourController.ship_id_of(_body))
	_origin_lane_released = true


func _align_at_berth() -> void:
	if _destination_slot == null or _thruster == null:
		_fail("berth_alignment_unavailable")
		return
	_propulsion.throttle = 0.0
	_rudder.rudder_input = 0.0
	_thruster.crab_mode = false
	var water := _destination_slot.global_transform.basis * _destination_slot.water_dir_local
	water.y = 0.0
	var along := Vector2(-water.z, water.x).normalized()
	var bow := NavigationAxes.vessel_bow_horizontal(_body).normalized()
	if bow.dot(along) < 0.0:
		along = -along
	var error := absf(rad_to_deg(bow.angle_to(along)))
	if error <= ALIGN_TOLERANCE_DEG:
		_thruster.lateral_input = 0.0
		_set_phase(Phase.CRAB_BERTH)
		return
	_thruster.lateral_input = VesselAutopilot.rudder_for_heading(bow, along)


func _crab_into_berth() -> void:
	if _destination_slot == null or _propulsion == null or _rudder == null or _thruster == null:
		_fail("berthing_controls_unavailable")
		return
	var target := _destination_slot.to_global(
		_destination_slot.ship_dock_local(_body.get_half_beam_m()).origin
	)
	var delta := target - _body.global_position
	delta.y = 0.0
	var speed := Vector2(_body.linear_velocity.x, _body.linear_velocity.z).length()
	if delta.length() <= BERTH_POSITION_TOLERANCE_M and speed <= BERTH_SPEED_TOLERANCE_MS:
		_zero_actuators()
		_set_phase(Phase.SECURING)
		return
	_rudder.rudder_input = 0.0
	_thruster.crab_mode = true
	var local_delta := _body.global_transform.basis.inverse() * delta
	## Crab closes the quay-normal error while a very small ahead/astern command
	## removes residual along-quay error. Without this second axis a vessel can
	## settle beside the correct berth but several metres ahead or astern of it.
	_thruster.lateral_input = clampf(local_delta.x / 8.0, -0.55, 0.55)
	_propulsion.throttle = clampf(local_delta.z / 24.0, -0.22, 0.16)


func _secure_lines() -> void:
	var destination := HarbourRegistry.controller(destination_port_id)
	if destination == null or _destination_slot == null or _mooring == null:
		_fail("mooring_unavailable")
		return
	_mooring.moor_to_nearest_of(_destination_slot.bollards())
	if not _mooring.is_moored:
		_fail("mooring_failed")
		return
	if not destination.plug_ship(destination_berth_id, _body):
		_fail("berth_occupancy_rejected")
		return
	destination.release_lane_lock(HarbourController.ship_id_of(_body))
	_set_phase(Phase.MOORED)
	voyage_completed.emit(contract_id)


func _on_autopilot_disengaged(reason: String) -> void:
	if reason == "arrived" and phase == Phase.PASSAGE:
		var origin := HarbourRegistry.controller(origin_port_id)
		if origin != null and not _origin_lane_released:
			origin.release_lane_lock(HarbourController.ship_id_of(_body))
		_origin_lane_released = true
		_set_phase(Phase.WAITING_APPROACH)
	elif reason == "arrived" and phase == Phase.APPROACH:
		_set_phase(Phase.ALIGNING)
	elif phase in [Phase.PASSAGE, Phase.APPROACH]:
		_fail("autopilot_%s" % reason)


func _zero_actuators() -> void:
	if _propulsion != null:
		_propulsion.throttle = 0.0
	if _rudder != null:
		_rudder.rudder_input = 0.0
	if _thruster != null:
		_thruster.lateral_input = 0.0
		_thruster.crab_mode = false


func _set_phase(next: int) -> void:
	if phase == next:
		return
	phase = next
	phase_changed.emit(phase)


func _fail(reason: String) -> void:
	_zero_actuators()
	if _autopilot != null and _autopilot.is_engaged():
		_autopilot.disengage(reason)
	_release_traffic_claims()
	_set_phase(Phase.FAILED)
	voyage_failed.emit(reason)


func _release_traffic_claims() -> void:
	if _body == null:
		return
	var vessel_id := HarbourController.ship_id_of(_body)
	var origin := HarbourRegistry.controller(origin_port_id)
	if origin != null:
		origin.release_lane_lock(vessel_id)
	var destination := HarbourRegistry.controller(destination_port_id)
	if destination != null:
		destination.release_lane_lock(vessel_id)
		if not destination_berth_id.is_empty():
			destination.release_berth_reservation(destination_berth_id, vessel_id)
