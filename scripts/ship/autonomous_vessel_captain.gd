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
	HOLDING,
}

const CRAB_EXTRA_CLEARANCE_M := 5.0
const CRAB_BERTH_STANDOFF_MIN_M := 3.0
const CRAB_BERTH_STANDOFF_MAX_M := 6.0
const DEPARTURE_HEADING_TOLERANCE_DEG := 7.0
const DEPARTURE_TURN_RATE_TOLERANCE := 0.10
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
var _departure_plan: MarineRoutePlan
var _lease_refresh_s := 0.0
var _lane_refresh_s := 0.0
var _origin_lane_released := false
var _arrival_ticket: Dictionary = {}


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
	preferred_destination_berth_id: String = "",
) -> bool:
	if _body == null or to_port_id.is_empty():
		return false
	contract_id = next_contract_id
	origin_port_id = from_port_id
	origin_berth_id = from_berth_id
	destination_port_id = to_port_id
	destination_family = berth_family
	destination_berth_id = preferred_destination_berth_id.strip_edges()
	_origin_lane_released = false
	_set_phase(Phase.RESERVING)
	return true


## Resume a voyage reconstructed from dormant authority. The timestamp chooses
## the initial route point once; ordinary autopilot and BoatBody physics own all
## movement after this call.
func resume_voyage(
		next_contract_id: String,
		from_port_id: String,
		from_berth_id: String,
		to_port_id: String,
		to_berth_id: String,
		plan: MarineRoutePlan,
		initial_progress_m: float,
		berth_family: String = "",
) -> bool:
	if _body == null or _autopilot == null or plan == null or not plan.is_valid():
		return false
	contract_id = next_contract_id
	origin_port_id = from_port_id
	origin_berth_id = from_berth_id
	destination_port_id = to_port_id
	destination_berth_id = to_berth_id
	destination_family = berth_family
	_origin_lane_released = initial_progress_m >= 500.0
	if not _autopilot.engage(plan, initial_progress_m, 45.0):
		return false
	_set_phase(Phase.PASSAGE)
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
	var traffic := _traffic_service()
	if traffic != null and not traffic.is_world_authority():
		return
	_maintain_destination_lease(delta)
	_maintain_lane_lock(delta)
	match phase:
		Phase.RESERVING:
			_try_reserve_and_depart()
		Phase.CASTING_OFF:
			_cast_off()
		Phase.CRAB_CLEAR:
			_crab_clear()
		Phase.DEPARTURE:
			_turn_for_departure()
		Phase.PASSAGE:
			_release_origin_lane_when_clear()
		Phase.WAITING_APPROACH:
			_try_begin_approach()
		Phase.HOLDING:
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
	if destination_berth_id.is_empty():
		destination_berth_id = _choose_destination_berth(destination)
	if destination_berth_id.is_empty():
		return
	var traffic := _traffic_service()
	if traffic != null and not traffic.request_block(
			"port:%s:departure" % origin_port_id, vessel_id, 1):
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
	if origin != null and origin.moored_ship(origin_berth_id) == _body:
		origin.unplug_ship(_body)
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
	_departure_plan = plan
	_zero_actuators()
	_set_phase(Phase.DEPARTURE)


func _turn_for_departure() -> void:
	if _departure_plan == null or not _departure_plan.is_valid() or _thruster == null:
		_fail("departure_turn_unavailable")
		return
	_propulsion.throttle = 0.0
	_rudder.rudder_input = 0.0
	_thruster.crab_mode = false
	var position := Vector2(_body.global_position.x, _body.global_position.z)
	var progress := _departure_plan.nearest_progress_m(position)
	var target := _departure_plan.point_at_distance(minf(
		progress + 120.0, _departure_plan.total_distance_m()))
	var desired := (target - position).normalized()
	var bow := NavigationAxes.vessel_bow_horizontal(_body).normalized()
	var heading_error := absf(rad_to_deg(bow.angle_to(desired)))
	if heading_error <= DEPARTURE_HEADING_TOLERANCE_DEG \
			and absf(_body.angular_velocity.y) <= DEPARTURE_TURN_RATE_TOLERANCE:
		_thruster.lateral_input = 0.0
		if not _autopilot.engage(_departure_plan, progress, 45.0):
			_fail("passage_route_failed")
			return
		_departure_plan = null
		_set_phase(Phase.PASSAGE)
		return
	_thruster.lateral_input = VesselAutopilot.rudder_for_heading(bow, desired, 42.0)


func _try_begin_approach() -> void:
	var destination := HarbourRegistry.controller(destination_port_id)
	if destination == null:
		return
	var vessel_id := HarbourController.ship_id_of(_body)
	var traffic := _traffic_service()
	if traffic != null:
		_register_destination_holding_zones(traffic, destination)
		_arrival_ticket = traffic.request_port_arrival(
			destination_port_id, vessel_id, destination_family,
			destination_berth_id, int(Time.get_unix_time_from_system()), 0)
		if not bool(_arrival_ticket.get("cleared_for_approach", false)):
			_move_to_holding_position(_arrival_ticket)
			return
		if phase == Phase.HOLDING and _autopilot != null and _autopilot.is_engaged():
			_autopilot.disengage("traffic_clearance")
			return
		if not traffic.request_block(
				"port:%s:approach" % destination_port_id, vessel_id, -1):
			_zero_actuators()
			return
	if not _ensure_destination_reservation(destination):
		return
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
	var dock := _destination_slot.global_transform * \
		_destination_slot.ship_dock_local(_body.get_half_beam_m())
	var water := _destination_slot.global_transform.basis * _destination_slot.water_dir_local
	water.y = 0.0
	water = water.normalized()
	var standoff := clampf(
		_body.get_half_beam_m() * 0.35,
		CRAB_BERTH_STANDOFF_MIN_M,
		CRAB_BERTH_STANDOFF_MAX_M,
	)
	var staging := dock.origin + water * standoff
	var points := PackedVector2Array()
	# Live lanes begin berth -> old 16 m crab point -> seaward approach.
	# Arrival uses only the seaward portion, then a hull-specific staging point.
	# This prevents forward autopilot from handing 16-20 m of lateral travel to
	# the bow thruster after it aligns beside the quay.
	for i in range(lane.size() - 1, 1, -1):
		var point := lane[i] as Vector3
		points.append(Vector2(point.x, point.z))
	var staging_xz := Vector2(staging.x, staging.z)
	if points.is_empty() or not points[-1].is_equal_approx(staging_xz):
		points.append(staging_xz)
	var plan := MarineRoutePlan.create(points, "harbour:%s" % destination_port_id,
		origin_port_id, destination_port_id)
	if not _autopilot.engage(plan, -1.0, 4.0):
		_fail("approach_route_failed")
		return
	_set_phase(Phase.APPROACH)


func _maintain_destination_lease(delta: float) -> void:
	if destination_berth_id.is_empty() or phase not in [
		Phase.WAITING_APPROACH, Phase.APPROACH, Phase.ALIGNING,
		Phase.CRAB_BERTH, Phase.SECURING,
	]:
		return
	_lease_refresh_s += delta
	if _lease_refresh_s < 30.0:
		return
	_lease_refresh_s = 0.0
	var destination := HarbourRegistry.controller(destination_port_id)
	if destination != null:
		_ensure_destination_reservation(destination)


func _ensure_destination_reservation(destination: HarbourController) -> bool:
	if destination == null or _body == null:
		return false
	var vessel_id := HarbourController.ship_id_of(_body)
	var occupied := destination.moored_ship(destination_berth_id) \
		if not destination_berth_id.is_empty() else null
	if occupied != null and occupied != _body:
		destination.release_berth_reservation(destination_berth_id, vessel_id)
		destination_berth_id = ""
	var reserved := destination.request_berth_reservation(
		vessel_id,
		_body.hull_size.z,
		destination_family,
		destination_berth_id,
	)
	if reserved.is_empty():
		return false
	destination_berth_id = reserved
	return destination.berth(destination_berth_id) != null


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
	var traffic := _traffic_service()
	if traffic != null:
		traffic.release_block(
			"port:%s:departure" % origin_port_id,
			HarbourController.ship_id_of(_body),
		)
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
	var traffic := _traffic_service()
	if traffic != null:
		traffic.complete_port_arrival(destination_port_id, HarbourController.ship_id_of(_body))
		traffic.release_block(
			"port:%s:approach" % destination_port_id,
			HarbourController.ship_id_of(_body),
		)
	_set_phase(Phase.MOORED)
	voyage_completed.emit(contract_id)


func _on_autopilot_disengaged(reason: String) -> void:
	if reason == "arrived" and phase == Phase.PASSAGE:
		var origin := HarbourRegistry.controller(origin_port_id)
		if origin != null and not _origin_lane_released:
			origin.release_lane_lock(HarbourController.ship_id_of(_body))
			_origin_lane_released = true
		var traffic := _traffic_service()
		if traffic != null:
			traffic.release_block(
				"port:%s:departure" % origin_port_id,
				HarbourController.ship_id_of(_body),
			)
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
	var traffic := _traffic_service()
	if traffic != null:
		traffic.cancel_port_arrival(destination_port_id, vessel_id)
		traffic.release_block("port:%s:departure" % origin_port_id, vessel_id)
		traffic.release_block("port:%s:approach" % destination_port_id, vessel_id)
		traffic.withdraw_vessel(vessel_id)


func _exit_tree() -> void:
	_release_traffic_claims()


func _choose_destination_berth(destination: HarbourController) -> String:
	if destination == null:
		return ""
	for raw in destination.berths():
		var slot := raw as QuayBerthSlot
		if slot != null and slot.matches_family(destination_family) \
				and slot.accepts_loa_m(_body.hull_size.z):
			return slot.berth_id
	return ""


func _register_destination_holding_zones(traffic: Node, destination: HarbourController) -> void:
	if traffic == null or destination == null:
		return
	var anchor := Vector2(INF, INF)
	for raw in destination.berths():
		var slot := raw as QuayBerthSlot
		if slot == null or not slot.matches_family(destination_family):
			continue
		if not destination_berth_id.is_empty() and slot.berth_id != destination_berth_id:
			continue
		var lane_kind := BerthApproachLanes.best_approach_lane_kind(
			slot.global_position, _body.global_position, destination_port_id)
		var lane := BerthApproachLanes.get_target_lane(
			destination_port_id, slot.berth_id, lane_kind)
		if not lane.is_empty():
			var outer := lane[-1] as Vector3
			anchor = Vector2(outer.x, outer.z)
			break
	if not anchor.is_finite():
		return
	var catalog := get_node_or_null("/root/PortCatalog")
	var port_position := catalog.get_port_position(destination_port_id) as Vector3 \
		if catalog != null else Vector3.ZERO
	var away := (anchor - Vector2(port_position.x, port_position.z)).normalized()
	if away.length_squared() < 0.5:
		away = Vector2(0.0, 1.0)
	var across := Vector2(-away.y, away.x)
	var spacing := maxf(_body.hull_size.z * 2.5, 80.0)
	var zones: Array = []
	for index in range(8):
		var rank := int(index / 2) + 1
		var side := -1.0 if index % 2 == 0 else 1.0
		var point := anchor + away * (rank * spacing) + across * side * spacing * 0.55
		zones.append([point.x, point.y])
	traffic.register_holding_zones(destination_port_id, zones)


func _move_to_holding_position(ticket: Dictionary) -> void:
	if _autopilot == null or _autopilot.is_engaged():
		return
	var raw := ticket.get("holding_position_xz", []) as Array
	if raw.size() < 2:
		_zero_actuators()
		_set_phase(Phase.HOLDING)
		return
	var current := Vector2(_body.global_position.x, _body.global_position.z)
	var holding := Vector2(float(raw[0]), float(raw[1]))
	if current.distance_to(holding) <= 12.0:
		_zero_actuators()
		_set_phase(Phase.HOLDING)
		return
	var plan := MarineRoutePlan.create(
		PackedVector2Array([current, holding]),
		"holding:%s" % destination_port_id,
		origin_port_id,
		destination_port_id,
	)
	if _autopilot.engage(plan, 0.0, 10.0):
		_set_phase(Phase.HOLDING)


func _traffic_service() -> Node:
	return get_node_or_null("/root/MaritimeTraffic")
