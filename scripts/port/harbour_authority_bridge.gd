class_name HarbourAuthorityBridge
extends Node

## Reliable multiplayer adapter for one live harbour. HarbourController still
## owns local reach/compatibility and equipment presentation; this bridge owns
## command submission, authoritative replay, and operation ownership.

var _controller: HarbourController
var _active := false
var _applying_event := false
var _pending: Dictionary = {} ## request id -> command context
var _pending_mooring_by_vessel: Dictionary = {}
var _finishing_operations: Dictionary = {}
var _retained_scope := ""
var _reconcile_queued := false


func setup(controller: HarbourController) -> void:
	_controller = controller
	name = "HarbourAuthorityBridge"


func activate() -> void:
	if _active:
		return
	_active = true
	_retained_scope = "port:%s" % _controller.port_id()
	WorldGateway.retain_interest(_retained_scope, self)
	WorldGateway.subscribe(WorldContracts.EVENT_PORT_OPERATION_STARTED, self, _on_operation_event)
	WorldGateway.subscribe(WorldContracts.EVENT_PORT_OPERATION_STOPPED, self, _on_operation_event)
	WorldGateway.subscribe(WorldContracts.EVENT_PORT_OPERATION_COMPLETED, self, _on_operation_event)
	WorldGateway.subscribe(WorldContracts.EVENT_VESSEL_BERTH_ASSIGNED, self, _on_berth_event)
	WorldGateway.subscribe(WorldContracts.EVENT_VESSEL_MOORING_CHANGED, self, _on_berth_event)
	WorldGateway.subscribe(WorldContracts.EVENT_VESSEL_BERTH_RELEASED, self, _on_berth_event)
	if not WorldGateway.projection_changed.is_connected(_on_projection_changed):
		WorldGateway.projection_changed.connect(_on_projection_changed)
	if not WorldGateway.command_completed.is_connected(_on_command_completed):
		WorldGateway.command_completed.connect(_on_command_completed)
	if not WorldGateway.session_ready.is_connected(_on_session_ready):
		WorldGateway.session_ready.connect(_on_session_ready)
	if not _controller.ship_plugged.is_connected(_on_harbour_topology_changed):
		_controller.ship_plugged.connect(_on_harbour_topology_changed)
	if not _controller.ship_unplugged.is_connected(_on_harbour_topology_changed):
		_controller.ship_unplugged.connect(_on_harbour_topology_changed)
	_connect_remote_ship_service()
	for ship_variant in _controller.ships():
		_wire_ship(ship_variant as BoatBody)
	_reconcile_all()


func deactivate() -> void:
	if not _active:
		return
	_active = false
	if not _retained_scope.is_empty():
		WorldGateway.release_interest(_retained_scope, self)
		_retained_scope = ""
	WorldGateway.unsubscribe_owner(self)
	if WorldGateway.projection_changed.is_connected(_on_projection_changed):
		WorldGateway.projection_changed.disconnect(_on_projection_changed)
	if WorldGateway.command_completed.is_connected(_on_command_completed):
		WorldGateway.command_completed.disconnect(_on_command_completed)
	if WorldGateway.session_ready.is_connected(_on_session_ready):
		WorldGateway.session_ready.disconnect(_on_session_ready)
	if _valid_controller() and _controller.ship_plugged.is_connected(_on_harbour_topology_changed):
		_controller.ship_plugged.disconnect(_on_harbour_topology_changed)
	if _valid_controller() and _controller.ship_unplugged.is_connected(_on_harbour_topology_changed):
		_controller.ship_unplugged.disconnect(_on_harbour_topology_changed)
	_disconnect_remote_ship_service()
	_pending_mooring_by_vessel.clear()


func request_job(berth_id: String, mode: String, commodity_id: String = "", contract_id: String = "") -> bool:
	if not _valid_controller() or not WorldGateway.is_ready():
		return false
	var ship := _controller.moored_ship(berth_id)
	if ship == null:
		return false
	var equipment := _controller.best_equipment_for(berth_id, ship, mode)
	if equipment == null:
		return false
	var operation_id := WorldGateway.next_request_id("port-operation").replace(":", "-")
	var request_id := WorldGateway.next_request_id("port-operation-request")
	var body := WorldContracts.port_operation_body(
		_controller.port_id(),
		berth_id,
		equipment.equipment_id(),
		HarbourController.ship_id_of(ship),
		mode,
		commodity_id,
		contract_id,
		operation_id,
	)
	_pending[request_id] = {"kind": "start", "operation_id": operation_id}
	WorldGateway.send_command(WorldContracts.COMMAND_PORT_OPERATION_REQUEST, body, request_id)
	return true


func request_stop(equipment_id: String, reason: String = "requested") -> bool:
	if not _valid_controller() or not WorldGateway.is_ready():
		return false
	var equipment := _controller.get_equipment(equipment_id)
	if equipment == null or equipment.operation_id().is_empty():
		return false
	var operation_id := equipment.operation_id()
	var request_id := WorldGateway.next_request_id("port-operation-stop")
	_pending[request_id] = {"kind": "stop", "operation_id": operation_id}
	WorldGateway.send_command(
		WorldContracts.COMMAND_PORT_OPERATION_STOP,
		{"operation_id": operation_id, "reason": reason},
		request_id,
	)
	return true


func abort_equipment(equipment_id: String, reason: String) -> void:
	## Teardown needs an immediate local stop, but it remains an authoritative
	## fact remotely. Suppress the equipment callback so only this request is sent.
	var equipment := _controller.get_equipment(equipment_id) if _valid_controller() else null
	if equipment == null:
		return
	request_stop(equipment_id, reason)
	if equipment.is_job_active():
		_applying_event = true
		equipment.stop_job()
		_applying_event = false


func topology_changed() -> void:
	## Topology changes caused by applying authoritative state must not trigger
	## another reconcile — that loop re-queries projections every frame and
	## exhausts client sockets. Reconciles are also coalesced: many topology
	## changes in one frame produce a single deferred pass.
	if not _active or _applying_event or _reconcile_queued:
		return
	_reconcile_queued = true
	call_deferred("_reconcile_all")


func _on_harbour_topology_changed(_berth_id: String, ship: BoatBody) -> void:
	_wire_ship(ship)
	topology_changed()


func _on_session_ready(_remote: bool, _session: Dictionary) -> void:
	_reconcile_all()


func _reconcile_all() -> void:
	_reconcile_queued = false
	if not _valid_controller():
		return
	for projection_variant in WorldGateway.projections("vessel_berth"):
		_apply_berth_projection(projection_variant as Dictionary)
	for projection_variant in WorldGateway.projections("port_operation"):
		_apply_projection(projection_variant as Dictionary)
	if WorldGateway.is_ready():
		WorldGateway.query_projections("vessel_berth")
		WorldGateway.query_projections("port_operation")


func _on_projection_changed(kind: String, _id: String, projection: Dictionary) -> void:
	if kind == "vessel_berth":
		_apply_berth_projection(projection)
	elif kind == "port_operation":
		_apply_projection(projection)


func _on_operation_event(event: Dictionary) -> void:
	var projection := event.get("projection", {}) as Dictionary
	if not projection.is_empty():
		_apply_projection(projection)


func _on_berth_event(event: Dictionary) -> void:
	var projection := event.get("projection", {}) as Dictionary
	if not projection.is_empty():
		_apply_berth_projection(projection)


func _apply_berth_projection(projection: Dictionary) -> void:
	if not _valid_controller():
		return
	var state := projection.get("state", {}) as Dictionary
	if str(state.get("port_id", "")) != _controller.port_id():
		return
	var vessel_id := str(state.get("vessel_id", projection.get("id", ""))).strip_edges()
	var berth_id := str(state.get("berth_id", "")).strip_edges()
	if vessel_id.is_empty() or berth_id.is_empty():
		return

	var desired_bow := bool(state.get("bow_line", false))
	var desired_stern := bool(state.get("stern_line", false))
	var pending := _pending_mooring_by_vessel.get(vessel_id, {}) as Dictionary
	if not pending.is_empty():
		if (
			bool(pending.get("bow_line", false)) != desired_bow
			or bool(pending.get("stern_line", false)) != desired_stern
		):
			return ## Do not roll a local cast-off back to an older cached projection.
		_pending_mooring_by_vessel.erase(vessel_id)

	var ship := _find_ship(vessel_id)
	if ship == null:
		return ## Projection remains cached; remote_ship_available retries it.
	var slot := _controller.berth(berth_id)
	if slot == null:
		return
	_wire_ship(ship)

	_applying_event = true
	var status := str(state.get("status", "assigned"))
	if status == "assigned":
		_clear_stale_local_occupant(berth_id, ship, slot)
		if _controller.apply_remote_ship_berth(ship, berth_id):
			var mooring := ship.find_child("MooringComponent", true, false) as MooringComponent
			if mooring != null:
				mooring.apply_authoritative_state(slot, desired_bow, desired_stern)
	else:
		var released_mooring := ship.find_child("MooringComponent", true, false) as MooringComponent
		if released_mooring != null:
			released_mooring.apply_authoritative_state(slot, false, false)
		if _controller.ship_berth_id(ship) == berth_id:
			_controller.unplug_ship(ship)
	_applying_event = false


func _clear_stale_local_occupant(
		berth_id: String,
		authoritative_ship: BoatBody,
		slot: QuayBerthSlot,
) -> void:
	var occupant := _controller.moored_ship(berth_id)
	if occupant == null or occupant == authoritative_ship:
		return
	## A berth assignment is a server-serialized fact. Local scene-tree
	## occupancy may lag behind a release/replacement event, but it must never
	## veto the newer authoritative occupant.
	var mooring := occupant.find_child("MooringComponent", true, false) as MooringComponent
	if mooring != null:
		mooring.apply_authoritative_state(slot, false, false)
	_controller.unplug_ship(occupant)


func _find_ship(vessel_id: String) -> BoatBody:
	for ship_variant in _controller.ships():
		var ship := ship_variant as BoatBody
		if ship != null and HarbourController.ship_id_of(ship) == vessel_id:
			return ship
	var active := LocalPlayerView.get_active_ship() as BoatBody
	if active != null and HarbourController.ship_id_of(active) == vessel_id:
		return active
	var drawing := NetworkManager.drawing_service
	if drawing != null and drawing.has_method("find_remote_ship_by_vessel_id"):
		return drawing.call("find_remote_ship_by_vessel_id", vessel_id) as BoatBody
	return null


func _wire_ship(ship: BoatBody) -> void:
	if ship == null or not is_instance_valid(ship) or bool(ship.get_meta("remote_replica", false)):
		return
	var mooring := ship.find_child("MooringComponent", true, false) as MooringComponent
	if mooring == null:
		return
	var callback := Callable(self, "_on_local_mooring_changed").bind(ship)
	if not mooring.mooring_state_changed.is_connected(callback):
		mooring.mooring_state_changed.connect(callback)


func _on_local_mooring_changed(
		port_id: String,
		berth_id: String,
		bow_line: bool,
		stern_line: bool,
		ship: BoatBody,
) -> void:
	if (
		not _active
		or _applying_event
		or ship == null
		or not is_instance_valid(ship)
		or port_id != _controller.port_id()
		or not WorldGateway.is_ready()
	):
		return
	var vessel_id := HarbourController.ship_id_of(ship)
	if vessel_id.is_empty() or not _owns_vessel(vessel_id):
		return
	var request_id := WorldGateway.next_request_id("vessel-mooring")
	var context := {
		"kind": "mooring",
		"vessel_id": vessel_id,
		"port_id": port_id,
		"berth_id": berth_id,
		"bow_line": bow_line,
		"stern_line": stern_line,
	}
	_pending[request_id] = context
	_pending_mooring_by_vessel[vessel_id] = context
	WorldGateway.send_command(
		WorldContracts.COMMAND_VESSEL_MOORING_SET,
		WorldContracts.vessel_mooring_body(
			vessel_id,
			port_id,
			berth_id,
			bow_line,
			stern_line,
		),
		request_id,
	)
	NetworkManager.force_local_ship_meta_resync()


func _owns_vessel(vessel_id: String) -> bool:
	return HarbourDeploy.authority_vessel_id(
		LocalPlayerView.get_active_vessel_record()
	) == vessel_id


func _connect_remote_ship_service() -> void:
	var drawing := NetworkManager.drawing_service
	if drawing == null or not drawing.has_signal("remote_ship_available"):
		return
	var callback := Callable(self, "_on_remote_ship_available")
	if not drawing.is_connected("remote_ship_available", callback):
		drawing.connect("remote_ship_available", callback)


func _disconnect_remote_ship_service() -> void:
	var drawing := NetworkManager.drawing_service
	if drawing == null or not drawing.has_signal("remote_ship_available"):
		return
	var callback := Callable(self, "_on_remote_ship_available")
	if drawing.is_connected("remote_ship_available", callback):
		drawing.disconnect("remote_ship_available", callback)


func _on_remote_ship_available(vessel_id: String, _ship: BoatBody) -> void:
	var projection := WorldGateway.projection("vessel_berth", vessel_id)
	if not projection.is_empty():
		_apply_berth_projection(projection)


func _apply_projection(projection: Dictionary) -> void:
	if not _valid_controller():
		return
	var state := projection.get("state", {}) as Dictionary
	if str(state.get("port_id", "")) != _controller.port_id():
		return
	var operation_id := str(state.get("operation_id", projection.get("id", "")))
	var equipment := _controller.get_equipment(str(state.get("equipment_id", "")))
	if equipment == null:
		return ## The port may still be streaming in; the projection stays cached.
	var status := str(state.get("status", ""))
	if status == "running":
		if _finishing_operations.has(operation_id) or equipment.operation_id() == operation_id:
			return
		if equipment.is_job_active():
			return ## Never interrupt a newer locally applied authoritative operation.
		var ship := _controller.moored_ship(str(state.get("berth_id", "")))
		if ship == null or HarbourController.ship_id_of(ship) != str(state.get("vessel_id", "")):
			return ## Ship/port streaming order will reconcile again when occupancy changes.
		_connect_equipment(equipment)
		_applying_event = true
		_controller.plug_equipment(
			equipment.equipment_id(),
			ship,
			str(state.get("mode", "")),
			str(state.get("commodity_id", "")),
			state,
		)
		_applying_event = false
		return
	_finishing_operations.erase(operation_id)
	if equipment.operation_id() == operation_id and equipment.is_job_active():
		_applying_event = true
		equipment.stop_job()
		_applying_event = false


func _connect_equipment(equipment: QuayEquipmentJob) -> void:
	if not equipment.job_completed.is_connected(_on_job_completed):
		equipment.job_completed.connect(_on_job_completed)
	if not equipment.job_stopped.is_connected(_on_job_stopped):
		equipment.job_stopped.connect(_on_job_stopped)


func _on_job_completed(context: Dictionary, report: Dictionary) -> void:
	if not _active or _applying_event or not _owns_operation(context):
		return
	## Remote completion is a server-timed fact. The local equipment animation
	## ending is not permission to declare cargo work complete. Single-player's
	## in-process authority can close immediately for responsive local play.
	if WorldGateway.is_remote():
		return
	_finish_from_local(WorldContracts.COMMAND_PORT_OPERATION_COMPLETE, context, report)


func _on_job_stopped(context: Dictionary) -> void:
	if not _active or _applying_event or not _owns_operation(context):
		return
	_finish_from_local(WorldContracts.COMMAND_PORT_OPERATION_STOP, context, {"reason": "equipment_stopped"})


func _finish_from_local(command_name: String, context: Dictionary, extra: Dictionary) -> void:
	var operation_id := str(context.get("operation_id", ""))
	if operation_id.is_empty() or _finishing_operations.has(operation_id):
		return
	_finishing_operations[operation_id] = true
	var body := {"operation_id": operation_id}
	if extra.has("reason"):
		body["reason"] = extra["reason"]
	if not extra.is_empty():
		body["report"] = extra.duplicate(true)
	var request_id := WorldGateway.next_request_id("port-operation-finish")
	_pending[request_id] = {"kind": "finish", "operation_id": operation_id}
	WorldGateway.send_command(command_name, body, request_id)


func _owns_operation(context: Dictionary) -> bool:
	return str(context.get("owner_actor_id", "")) == WorldGateway.actor_id()


func _on_command_completed(request_id: String, result: Dictionary) -> void:
	if not _pending.has(request_id):
		return
	var pending := _pending[request_id] as Dictionary
	_pending.erase(request_id)
	if bool(result.get("ok", false)):
		if str(pending.get("kind", "")) == "mooring":
			var assignment := (
				(result.get("data", {}) as Dictionary).get("assignment", {}) as Dictionary
			)
			if not assignment.is_empty():
				_apply_berth_projection({
					"kind": "vessel_berth",
					"id": str(pending.get("vessel_id", "")),
					"state": assignment,
				})
			WorldGateway.query_projections(
				"vessel_berth",
				str(pending.get("vessel_id", "")),
			)
		return
	var operation_id := str(pending.get("operation_id", ""))
	_finishing_operations.erase(operation_id)
	var vessel_id := str(pending.get("vessel_id", ""))
	if not vessel_id.is_empty():
		_pending_mooring_by_vessel.erase(vessel_id)
	push_warning("Harbour authority rejected %s: %s" % [pending.get("kind", "operation"), result.get("message", "unknown error")])
	_reconcile_all()


func _valid_controller() -> bool:
	return _controller != null and is_instance_valid(_controller)
