class_name CustomPortVesselSession
extends Node

## The workshop's local command adapter. Port records own cargo and occupancy;
## free-sailing transforms belong only to this session, never the JSON document.
signal state_changed(snapshot: Dictionary, result: Dictionary)
signal feedback_changed(message: String)
signal helm_changed(vessel_id: String, occupied: bool)

const MAX_MOOR_SPEED_M_S := 1.2
const MAX_MOOR_ANGLE_DEGREES := 25.0
const MAX_MOOR_OFFSET_M := 3.0
var state: CustomPortState
var presenter: CustomPortPresenter
var player: CharacterBody3D
var transfers: CustomPortTransferPresenter
var input_blocked := true
var last_result: Dictionary = {}
var _boats: Dictionary = {}
var _sequence := 0

func configure(value: CustomPortState, view: CustomPortPresenter, person: CharacterBody3D, cargo: CustomPortTransferPresenter) -> void:
	assert(ShipyardPlaytestMode.active())
	state=value
	presenter=view
	player=person
	transfers=cargo
	presenter.retain_departed_vessels=true
	presenter.vessel_presented.connect(_bind_vessel)
	presenter.vessel_removing.connect(_unbind_vessel)
	for id in presenter.vessel_nodes: _bind_vessel(str(id),presenter.vessel_nodes[id])

func set_state(value: CustomPortState) -> void:
	if state==value:return
	# A restored document deliberately reconstructs only durable docked ships.
	# It must not inherit an old voyage or an abandoned body's cargo instances.
	reset_runtime()
	state=value

func reset_runtime() -> void:
	if is_instance_valid(transfers):transfers.reset()
	# Invalidate the complete presentation cache too. An identical saved revision
	# would otherwise be treated as a duplicate after its bodies were removed.
	if is_instance_valid(presenter): presenter.clear_record()
	for id in _boats.keys(): _unbind_vessel(str(id),_boats[id].boat)

func _bind_vessel(id: String, boat: BoatBody) -> void:
	if not _boats.has(id) or _boats[id].boat!=boat:
		if _boats.has(id):_unbind_vessel(id,_boats[id].boat)
		var controller:=boat.get_node_or_null("BoatController") as BoatController
		var stations: Array[BridgeInteractable]=boat.get_bridge_stations()
		var guard:=Callable(self,"_departure_reason").bind(id)
		_boats[id]={"boat":boat,"controller":controller,"stations":stations,"guard":guard}
		boat.departure_checks.append(guard)
		boat.set_meta("workshop_vessel_id",id)
		if controller!=null:
			controller.mooring_order_override=Callable(self,"order_lines").bind(id)
		for station in stations:
			station.player_boarded.connect(_station_changed.bind(id,true))
			station.player_exited.connect(_station_changed.bind(id,false))
	_project_lines(id,boat)
	_apply_input(_boats[id])

func _project_lines(id: String, boat: BoatBody) -> void:
	var vessel:=_vessel(id)
	var mooring:=boat.get_node_or_null("ShipGameplay/MooringComponent") as MooringComponent
	if mooring==null:return
	var slot:=presenter.berth_nodes.get(str(vessel.get("berth_id",""))) as QuayBerthSlot
	# These are visual lines for already accepted state, not a registry mutation.
	if slot==null:
		if mooring.is_moored:
			mooring._suppress_state_signal=true
			mooring.release_mooring()
			mooring._suppress_state_signal=false
		return
	var posts:=slot.bollards()
	if posts.size()<2:return
	if mooring.is_moored and mooring._front_post==posts[0] and mooring._rear_post==posts[1]:return
	mooring._suppress_state_signal=true
	mooring.moor_to_posts(posts[0],posts[1])
	mooring._suppress_state_signal=false

func _unbind_vessel(id: String, boat: BoatBody) -> void:
	if not _boats.has(id) or _boats[id].boat!=boat:return
	var entry: Dictionary=_boats[id]
	if is_instance_valid(boat):
		boat.departure_checks.erase(entry.guard)
		for station in entry.stations:
			if not is_instance_valid(station):continue
			if station.is_occupied():
				# Teardown cannot be refused by a blocked deck exit: the whole ship
				# is leaving the scene, and the workshop places the player safely.
				station._occupied=false
				station._player=null
				if is_instance_valid(player):player.set_vehicle_occupied(false)
			station.player_boarded.disconnect(_station_changed.bind(id,true))
			station.player_exited.disconnect(_station_changed.bind(id,false))
		var controller: BoatController=entry.controller
		if is_instance_valid(controller):
			if controller._active:controller.deactivate()
			controller.mooring_order_override=Callable()
			controller.input_suspended=false
		var camera:=boat.get_node_or_null("BoatCamera") as BoatCamera
		if camera!=null:camera.end_helm()
	_boats.erase(id)

func set_input_blocked(blocked: bool) -> void:
	input_blocked=blocked
	for entry in _boats.values():_apply_input(entry)

func _apply_input(entry: Dictionary) -> void:
	var controller: BoatController=entry.controller
	if is_instance_valid(controller):controller.input_suspended=input_blocked
	for station in entry.stations:
		if is_instance_valid(station):station.set_process_unhandled_input(not input_blocked)
	var boat: BoatBody=entry.boat
	if is_instance_valid(boat):
		var camera:=boat.get_node_or_null("BoatCamera")
		if camera!=null:camera.set_process_unhandled_input(not input_blocked)

func occupied_station() -> BridgeInteractable:
	for entry in _boats.values():
		for station in entry.stations:
			if is_instance_valid(station) and station.is_occupied():return station
	return null

func leave_helm() -> bool:
	var station:=occupied_station()
	if station==null:return true
	station._exit()
	if station.is_occupied():
		feedback_changed.emit("The deck exit is blocked. Clear it before leaving the helm.")
		return false
	return true

func _station_changed(id: String, occupied: bool) -> void:
	if not occupied and input_blocked and is_instance_valid(player):
		# Station exit normally resumes walking. A released cursor or workshop
		# panel still owns input until its existing mode transition resumes it.
		player.set_physics_process(false)
		player.set_process_unhandled_input(false)
	helm_changed.emit(id,occupied)
	if occupied:feedback_changed.emit(helm_status())
	else:feedback_changed.emit("WASD · Walk   F · Talk / helm   1 · Build tool   H · Home")

func helm_vessel_id() -> String:
	for id in _boats:
		for station in _boats[id].stations:
			if is_instance_valid(station) and station.is_occupied():return str(id)
	return ""

func helm_status() -> String:
	var id:=helm_vessel_id()
	if id.is_empty():return ""
	var station:=occupied_station()
	if station!=null and station._boat_controller==null:return "Seated · F / Esc · Stand up"
	var vessel:=_vessel(id)
	var boat: BoatBody=_boats[id].boat
	var controller: BoatController=_boats[id].controller
	var prop:=boat.get_node_or_null("PropulsionComponent") as PropulsionComponent
	var engine:="Engine off" if prop==null or not prop.engine_running else "Engine running"
	var order:="B · Let go" if not str(vessel.get("berth_id","")).is_empty() else "B · Make fast alongside"
	var speed:=Vector2(boat.linear_velocity.x,boat.linear_velocity.z).length()*1.943844
	var throttle:=controller._target_throttle_from_stage() if controller!=null else 0.0
	var order_name:="Stop" if is_zero_approx(throttle) else ("Astern" if throttle<0 else "Ahead %d%%"%roundi(throttle*100))
	return "%s · %.1f kn · %s · %s\n%s   I · Engine   W/S · Throttle   A/D · Rudder   F / Esc · Leave helm"%[str(vessel.get("name","Vessel")),speed,engine,order_name,order]

func _departure_reason(id: String) -> String:
	if is_instance_valid(transfers) and transfers.is_busy():return "Wait for the port transfer to finish."
	for reservation in state.to_dict().get("reservations",[]):
		if str(reservation.vessel_id)==id:return "Load or cancel this vessel's reservation before leaving."
	return ""

func order_lines(id: String) -> Dictionary:
	if input_blocked:return _reject("input_blocked","Close the panel before ordering the lines.")
	var vessel:=_vessel(id)
	if vessel.is_empty() or not _boats.has(id):return _reject("vessel_not_available","This vessel is not in the workshop.")
	if not str(vessel.get("berth_id","")).is_empty():
		var blocked:=_departure_reason(id)
		if not blocked.is_empty():return _reject("departure_blocked",blocked)
		return _submit("undock",vessel,{"vessel_id":id})
	var boat: BoatBody=_boats[id].boat
	var nearest: Dictionary={}
	var distance:=INF
	for berth in state.derived_berths():
		var target:=berth_pose(berth,vessel)
		var delta:=target.origin-boat.global_position
		var candidate:=Vector2(delta.x,delta.z).length()
		if candidate<distance:distance=candidate;nearest=berth
	if nearest.is_empty():return _reject("no_berth","Build a surveyed berth with two bollards before making fast.")
	return request_dock(id,str(nearest.id))

func request_dock(id: String, berth_id: String) -> Dictionary:
	if input_blocked:return _reject("input_blocked","Close the panel before ordering the lines.")
	var vessel:=_vessel(id)
	var boat: BoatBody=_boats.get(id,{}).get("boat")
	if vessel.is_empty() or not is_instance_valid(boat):return _reject("vessel_not_available","This vessel is not in the workshop.")
	var berth: Dictionary={}
	for row in state.derived_berths():
		if str(row.id)==berth_id:berth=row;break
	if berth.is_empty():return _reject("berth_not_found","This berth is no longer available.")
	var occupancy: Array=[]
	for row in state.to_dict().vessels:
		if not str(row.get("berth_id","")).is_empty():occupancy.append({"vessel_id":row.id,"berth_id":row.berth_id})
	var fit:=CustomPortBerths.fit(berth,vessel,occupancy)
	if not fit.ok:
		var messages: Array[String]=[]
		var friendly:={"occupied":"Berth occupied","adjacent_berth_occupied":"An adjacent vessel needs this space","insufficient_length":"Vessel too long","insufficient_beam":"Vessel too wide","insufficient_depth":"Not enough water beneath the keel","water_unverified":"Water depth has not been surveyed"}
		for reason in fit.reasons:messages.append(str(friendly.get(reason,str(reason).replace("_"," "))))
		return _reject("vessel_does_not_fit","Cannot make fast · "+" · ".join(messages),{"reasons":fit.reasons})
	var pose:=berth_pose(berth,vessel)
	var approach:=arrival_check(boat.global_transform,boat.linear_velocity,pose,vessel,berth)
	if not approach.ok:return _reject(str(approach.code),str(approach.message))
	var reversed:=boat.global_basis.z.dot(pose.basis.z)<0
	boat.set_meta("workshop_reverse_berth",reversed)
	return _submit("dock",vessel,{"vessel_id":id,"berth_id":berth_id})

func berth_pose(berth: Dictionary, vessel: Dictionary) -> Transform3D:
	var slot:=presenter.berth_nodes.get(str(berth.id)) as QuayBerthSlot
	var pose:=slot.global_transform*slot.ship_dock_local(float(vessel.beam_m)*.5,float(vessel.length_m))
	pose.origin.y=WaveSurface.WATER_LEVEL-float(vessel.draft_m)
	return pose

static func arrival_check(pose: Transform3D, velocity: Vector3, target: Transform3D, vessel: Dictionary, berth: Dictionary) -> Dictionary:
	if not pose.is_finite() or not target.is_finite() or not velocity.is_finite():return {"ok":false,"code":"invalid_pose","message":"The vessel position is unavailable."}
	if Vector2(velocity.x,velocity.z).length()>MAX_MOOR_SPEED_M_S:return {"ok":false,"code":"too_fast","message":"Slow below 2.3 kn before making fast."}
	var forward:=Vector2(pose.basis.z.x,pose.basis.z.z).normalized()
	var along:=Vector2(target.basis.z.x,target.basis.z.z).normalized()
	if absf(forward.dot(along))<cos(deg_to_rad(MAX_MOOR_ANGLE_DEGREES)):return {"ok":false,"code":"not_aligned","message":"Line up alongside the quay before making fast."}
	var delta:=Vector2(pose.origin.x-target.origin.x,pose.origin.z-target.origin.z)
	var room:=maxf(0.5,minf(MAX_MOOR_OFFSET_M,(float(berth.max_length_m)-float(vessel.length_m))*.5))
	if absf(delta.dot(along))>room or absf(delta.cross(along))>MAX_MOOR_OFFSET_M:return {"ok":false,"code":"not_alongside","message":"Come alongside the berth centre before making fast."}
	return {"ok":true}

func _submit(kind: String, vessel: Dictionary, payload: Dictionary) -> Dictionary:
	_sequence+=1
	last_result=state.apply({"command_id":"workshop-lines-%d-%d-%d"%[get_instance_id(),Time.get_ticks_usec(),_sequence],
		"expected_revision":state.revision(),"actor_company_id":str(vessel.owner_company_id),"kind":kind,"payload":payload})
	if last_result.ok:
		state_changed.emit(last_result.snapshot,last_result)
		feedback_changed.emit("Lines let go · I starts the engine, W/S sets the throttle." if kind=="undock" else "Both lines fast · F leaves the helm; the gangway opens to the quay.")
	else:feedback_changed.emit("Cannot change the lines · "+str(last_result.code).replace("_"," "))
	return last_result

func _reject(code: String, message: String, details: Dictionary={}) -> Dictionary:
	last_result={"ok":false,"code":code,"details":details}
	feedback_changed.emit(message)
	return last_result

func _vessel(id: String) -> Dictionary:
	if state!=null:
		for row in state.to_dict().vessels:
			if str(row.id)==id:return row
	return {}

func shutdown() -> void:
	# Root teardown must only release references/input ownership. Removing the
	# vessel subtree here would ask gangways to play sounds while siblings exit.
	for id in _boats.keys():_unbind_vessel(str(id),_boats[id].boat)
	if is_instance_valid(presenter):
		if presenter.vessel_presented.is_connected(_bind_vessel):presenter.vessel_presented.disconnect(_bind_vessel)
		if presenter.vessel_removing.is_connected(_unbind_vessel):presenter.vessel_removing.disconnect(_unbind_vessel)

func _exit_tree() -> void:
	shutdown()
