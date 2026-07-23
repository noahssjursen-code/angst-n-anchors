class_name LocalWorldBackend
extends WorldBackend

## Single-player authority implementing exactly the same command/event contract
## as the remote server. Presentation code therefore has no single-player fork.

var _session: Dictionary = {}
var _processed: Dictionary = {}
var _projections: Dictionary = {}
var _stream_revisions: Dictionary = {}
var _cursor := 0
var _scheduler_clock := 0.0


func _process(delta: float) -> void:
	if not is_ready():
		return
	_scheduler_clock += delta
	if _scheduler_clock < 0.25:
		return
	_scheduler_clock = 0.0
	_complete_due_operations()


func start_session(actor_id: String, _display_name: String, _world_checksum: String, _captain_token: String = "") -> void:
	var actor := actor_id.strip_edges()
	if actor.is_empty():
		transport_failed.emit("actor_missing", "A local authority session requires a captain id.")
		return
	_session = {
		"contract_version": WorldContracts.VERSION,
		"session_id": _new_id("local-session"),
		"session_token": "local:%s" % actor,
		"actor_id": actor,
		"event_cursor": _cursor,
		"expires_at_ms": 0,
	}
	session_started.emit(_session.duplicate(true))


func stop_session() -> void:
	_session.clear()
	session_ended.emit()


func session_token() -> String:
	return str(_session.get("session_token", ""))


func is_ready() -> bool:
	return not _session.is_empty()


func send_command(command: Dictionary) -> void:
	var request_id := str(command.get("request_id", "")).strip_edges()
	if not is_ready():
		command_finished.emit(WorldContracts.result_error(request_id, "session_invalid", "Local authority is not ready."))
		return
	if _processed.has(request_id):
		command_finished.emit((_processed[request_id] as Dictionary).duplicate(true))
		return
	var name := str(command.get("name", ""))
	var body := command.get("body", {}) as Dictionary
	var expected := int(command.get("expected_revision", -1))
	var result: Dictionary
	match name:
		WorldContracts.COMMAND_VESSEL_BERTH_CLAIM:
			result = _claim_vessel_berth(request_id, body)
		WorldContracts.COMMAND_VESSEL_MOORING_SET:
			result = _set_vessel_mooring(request_id, body)
		WorldContracts.COMMAND_VESSEL_BERTH_RELEASE:
			result = _release_vessel_berth(request_id, body)
		WorldContracts.COMMAND_PORT_OPERATION_REQUEST:
			result = _request_port_operation(request_id, body, expected)
		WorldContracts.COMMAND_PORT_OPERATION_STOP:
			result = _finish_port_operation(request_id, body, expected, "stopped")
		WorldContracts.COMMAND_PORT_OPERATION_COMPLETE:
			result = _finish_port_operation(request_id, body, expected, "completed")
		WorldContracts.COMMAND_INTERACTION_SET:
			result = _set_interaction(request_id, body, expected)
		_:
			result = WorldContracts.result_error(request_id, "command_unknown", "Unsupported local authority command: %s" % name)
	_processed[request_id] = result.duplicate(true)
	command_finished.emit(result)


func _claim_vessel_berth(request_id: String, body: Dictionary) -> Dictionary:
	var vessel_id := str(body.get("vessel_id", "")).strip_edges()
	var port_id := str(body.get("port_id", "")).strip_edges()
	var replace_vessel_id := str(body.get("replace_vessel_id", "")).strip_edges()
	var raw_candidates := body.get("candidates", []) as Array
	if vessel_id.is_empty() or port_id.is_empty() or raw_candidates.is_empty():
		return WorldContracts.result_error(request_id, "command_rejected", "vessel_id, port_id, and berth candidates are required")
	var existing := _projections.get(_projection_key("vessel_berth", vessel_id), {}) as Dictionary
	if not existing.is_empty():
		var existing_state := existing.get("state", {}) as Dictionary
		if (
			str(existing_state.get("status", "")) == "assigned"
			and str(existing_state.get("owner_actor_id", "")) == str(_session.get("actor_id", ""))
		):
			if str(existing_state.get("port_id", "")) != port_id:
				return WorldContracts.result_error(
					request_id,
					"command_rejected",
					"Vessel is already deployed at another port.",
				)
			return {
				"contract_version": WorldContracts.VERSION,
				"request_id": request_id,
				"ok": true,
				"revision": int(existing.get("revision", 0)),
				"data": {"assignment": existing_state.duplicate(true)},
			}
	var replaced_projection: Dictionary = {}
	var replaced_state: Dictionary = {}
	if not replace_vessel_id.is_empty() and replace_vessel_id != vessel_id:
		replaced_projection = (
			_projections.get(_projection_key("vessel_berth", replace_vessel_id), {})
			as Dictionary
		)
		if not replaced_projection.is_empty():
			replaced_state = (
				(replaced_projection.get("state", {}) as Dictionary).duplicate(true)
			)
			if str(replaced_state.get("owner_actor_id", "")) != str(_session.get("actor_id", "")):
				return WorldContracts.result_error(
					request_id,
					"command_rejected",
					"Only the replacement vessel owner may release its berth.",
				)
	var occupied: Dictionary = {}
	for projection_variant in _projections.values():
		var projection := projection_variant as Dictionary
		if str(projection.get("kind", "")) != "vessel_berth":
			continue
		if (
			not replaced_projection.is_empty()
			and str(projection.get("id", "")) == replace_vessel_id
		):
			continue
		var state := projection.get("state", {}) as Dictionary
		if str(state.get("status", "")) == "assigned":
			occupied[str(state.get("berth_id", ""))] = str(state.get("vessel_id", ""))
	var berth_id := ""
	var valid_prefix := "%s/" % port_id
	for candidate_variant in raw_candidates:
		var candidate := str(candidate_variant).strip_edges()
		if candidate.begins_with(valid_prefix) and not occupied.has(candidate):
			berth_id = candidate
			break
	if berth_id.is_empty():
		return WorldContracts.result_error(request_id, "berth_unavailable", "No compatible berth is currently available.")
	var now_ms := int(Time.get_unix_time_from_system() * 1000.0)
	var state := {
		"vessel_id": vessel_id,
		"owner_actor_id": str(_session.get("actor_id", "")),
		"port_id": port_id,
		"berth_id": berth_id,
		"bow_line": true,
		"stern_line": true,
		"status": "assigned",
		"assigned_at_ms": now_ms,
	}
	if (
		not replaced_projection.is_empty()
		and str(replaced_state.get("status", "")) == "assigned"
	):
		replaced_state["bow_line"] = false
		replaced_state["stern_line"] = false
		replaced_state["status"] = "released"
		replaced_state["reason"] = "replaced_active_vessel"
		replaced_state["released_at_ms"] = now_ms
		_publish(
			"vessel/%s/berth" % replace_vessel_id,
			WorldContracts.EVENT_VESSEL_BERTH_RELEASED,
			replaced_state,
			"vessel_berth",
			replace_vessel_id,
		)
	var event := _publish(
		"vessel/%s/berth" % vessel_id,
		WorldContracts.EVENT_VESSEL_BERTH_ASSIGNED,
		state,
		"vessel_berth",
		vessel_id,
	)
	return _success(
		request_id,
		event,
		{
			"assignment": state.duplicate(true),
			"replaced_vessel_id": replace_vessel_id,
		},
	)


func _set_vessel_mooring(request_id: String, body: Dictionary) -> Dictionary:
	var vessel_id := str(body.get("vessel_id", "")).strip_edges()
	var port_id := str(body.get("port_id", "")).strip_edges()
	var berth_id := str(body.get("berth_id", "")).strip_edges()
	if vessel_id.is_empty() or port_id.is_empty() or berth_id.is_empty():
		return WorldContracts.result_error(request_id, "command_rejected", "vessel_id, port_id, and berth_id are required")
	var projection := _projections.get(_projection_key("vessel_berth", vessel_id), {}) as Dictionary
	if projection.is_empty():
		return WorldContracts.result_error(request_id, "command_rejected", "Vessel berth assignment not found.")
	var state := (projection.get("state", {}) as Dictionary).duplicate(true)
	if str(state.get("owner_actor_id", "")) != str(_session.get("actor_id", "")):
		return WorldContracts.result_error(request_id, "command_rejected", "Only the vessel owner may change its mooring.")
	if str(state.get("port_id", "")) != port_id or str(state.get("berth_id", "")) != berth_id:
		return WorldContracts.result_error(request_id, "command_rejected", "Mooring update does not match the assigned berth.")
	var bow_line := bool(body.get("bow_line", false))
	var stern_line := bool(body.get("stern_line", false))
	var status := str(state.get("status", ""))
	if status != "assigned" and status != "released":
		return WorldContracts.result_error(request_id, "command_rejected", "Vessel berth assignment is not active.")
	var event_type := WorldContracts.EVENT_VESSEL_MOORING_CHANGED
	if status == "released" and (bow_line or stern_line):
		for candidate_variant in _projections.values():
			var candidate_projection := candidate_variant as Dictionary
			if (
				str(candidate_projection.get("kind", "")) != "vessel_berth"
				or str(candidate_projection.get("id", "")) == vessel_id
			):
				continue
			var candidate_state := candidate_projection.get("state", {}) as Dictionary
			if (
				str(candidate_state.get("status", "")) == "assigned"
				and str(candidate_state.get("berth_id", "")) == berth_id
			):
				return WorldContracts.result_error(request_id, "berth_unavailable", "Assigned berth is no longer available.")
		state["status"] = "assigned"
		state["assigned_at_ms"] = int(Time.get_unix_time_from_system() * 1000.0)
		state.erase("released_at_ms")
		state.erase("reason")
		event_type = WorldContracts.EVENT_VESSEL_BERTH_ASSIGNED
	state["bow_line"] = bow_line
	state["stern_line"] = stern_line
	state["updated_at_ms"] = int(Time.get_unix_time_from_system() * 1000.0)
	if not bow_line and not stern_line:
		state["status"] = "released"
		state["released_at_ms"] = state["updated_at_ms"]
		event_type = WorldContracts.EVENT_VESSEL_BERTH_RELEASED
	var event := _publish(
		"vessel/%s/berth" % vessel_id,
		event_type,
		state,
		"vessel_berth",
		vessel_id,
	)
	return _success(request_id, event, {"assignment": state.duplicate(true)})


func _release_vessel_berth(request_id: String, body: Dictionary) -> Dictionary:
	var vessel_id := str(body.get("vessel_id", "")).strip_edges()
	if vessel_id.is_empty():
		return WorldContracts.result_error(request_id, "command_rejected", "vessel_id is required")
	var projection := _projections.get(_projection_key("vessel_berth", vessel_id), {}) as Dictionary
	if projection.is_empty():
		return {
			"contract_version": WorldContracts.VERSION,
			"request_id": request_id,
			"ok": true,
			"revision": 0,
			"data": {"vessel_id": vessel_id, "status": "released"},
		}
	var state := (projection.get("state", {}) as Dictionary).duplicate(true)
	if str(state.get("owner_actor_id", "")) != str(_session.get("actor_id", "")):
		return WorldContracts.result_error(request_id, "command_rejected", "Only the vessel owner may release its berth.")
	if str(state.get("status", "")) == "released":
		return {
			"contract_version": WorldContracts.VERSION,
			"request_id": request_id,
			"ok": true,
			"revision": int(projection.get("revision", 0)),
			"data": {"assignment": state},
		}
	state["status"] = "released"
	state["bow_line"] = false
	state["stern_line"] = false
	state["reason"] = str(body.get("reason", "requested"))
	state["released_at_ms"] = int(Time.get_unix_time_from_system() * 1000.0)
	var event := _publish(
		"vessel/%s/berth" % vessel_id,
		WorldContracts.EVENT_VESSEL_BERTH_RELEASED,
		state,
		"vessel_berth",
		vessel_id,
	)
	return _success(request_id, event, {"assignment": state.duplicate(true)})


func query_projections(kind: String = "", id: String = "") -> void:
	var out: Array = []
	for projection_variant in _projections.values():
		var projection := projection_variant as Dictionary
		if not kind.is_empty() and str(projection.get("kind", "")) != kind:
			continue
		if not id.is_empty() and str(projection.get("id", "")) != id:
			continue
		out.append(projection.duplicate(true))
	projections_received.emit(out)


func _request_port_operation(request_id: String, body: Dictionary, expected: int) -> Dictionary:
	for required in ["port_id", "berth_id", "equipment_id", "vessel_id", "mode"]:
		if str(body.get(required, "")).strip_edges().is_empty():
			return WorldContracts.result_error(request_id, "command_rejected", "%s is required" % required)
	var mode := str(body.get("mode", "")).to_lower()
	if mode != "load" and mode != "unload":
		return WorldContracts.result_error(request_id, "command_rejected", "mode must be load or unload")
	var vessel_id := str(body.get("vessel_id", ""))
	var berth_projection := _projections.get(_projection_key("vessel_berth", vessel_id), {}) as Dictionary
	if berth_projection.is_empty():
		return WorldContracts.result_error(request_id, "command_rejected", "Vessel has no authoritative berth assignment.")
	var berth_state := berth_projection.get("state", {}) as Dictionary
	if (
		str(berth_state.get("status", "")) != "assigned"
		or str(berth_state.get("port_id", "")) != str(body.get("port_id", ""))
		or str(berth_state.get("berth_id", "")) != str(body.get("berth_id", ""))
		or not bool(berth_state.get("bow_line", false))
		or not bool(berth_state.get("stern_line", false))
	):
		return WorldContracts.result_error(request_id, "command_rejected", "Vessel must be fully moored at this berth.")
	var stream := "port-equipment/%s/%s" % [body["port_id"], body["equipment_id"]]
	var conflict := _revision_conflict(request_id, stream, expected)
	if not conflict.is_empty():
		return conflict
	for projection_variant in _projections.values():
		var projection := projection_variant as Dictionary
		if str(projection.get("kind", "")) != "port_operation":
			continue
		var state := projection.get("state", {}) as Dictionary
		if (
			str(state.get("port_id", "")) == str(body["port_id"])
			and str(state.get("equipment_id", "")) == str(body["equipment_id"])
			and str(state.get("status", "")) == "running"
		):
			return WorldContracts.result_error(request_id, "command_rejected", "Equipment is already serving another operation.")
	var operation_id := str(body.get("operation_id", "")).strip_edges()
	if operation_id.is_empty():
		operation_id = _new_id("operation")
	var now_ms := int(Time.get_unix_time_from_system() * 1000.0)
	var state := body.duplicate(true)
	state["operation_id"] = operation_id
	state["mode"] = mode
	state["status"] = "running"
	state["started_at_ms"] = now_ms
	state["owner_actor_id"] = str(_session.get("actor_id", ""))
	var event := _publish(stream, WorldContracts.EVENT_PORT_OPERATION_STARTED, state, "port_operation", operation_id)
	return _success(request_id, event, {"operation": event.get("projection", {})})


func _complete_due_operations() -> void:
	var now_ms := int(Time.get_unix_time_from_system() * 1000.0)
	var due: Array[String] = []
	for projection_variant in _projections.values():
		var projection := projection_variant as Dictionary
		if str(projection.get("kind", "")) != "port_operation":
			continue
		var state := projection.get("state", {}) as Dictionary
		var duration_ms := int(state.get("duration_ms", 0))
		if (
			str(state.get("status", "")) == "running"
			and duration_ms > 0
			and int(state.get("started_at_ms", now_ms)) + duration_ms <= now_ms
		):
			due.append(str(state.get("operation_id", projection.get("id", ""))))
	for operation_id in due:
		send_command(WorldContracts.command(
			"local-system-complete:%s" % operation_id,
			WorldContracts.COMMAND_PORT_OPERATION_COMPLETE,
			{"operation_id": operation_id},
		))


func _finish_port_operation(request_id: String, body: Dictionary, expected: int, status: String) -> Dictionary:
	var operation_id := str(body.get("operation_id", "")).strip_edges()
	var projection := _projections.get(_projection_key("port_operation", operation_id), {}) as Dictionary
	if projection.is_empty():
		return WorldContracts.result_error(request_id, "command_rejected", "Operation not found.")
	var state := (projection.get("state", {}) as Dictionary).duplicate(true)
	var stream := "port-equipment/%s/%s" % [state.get("port_id", ""), state.get("equipment_id", "")]
	var conflict := _revision_conflict(request_id, stream, expected)
	if not conflict.is_empty():
		return conflict
	if str(state.get("status", "")) != "running":
		return {"contract_version": WorldContracts.VERSION, "request_id": request_id, "ok": true, "revision": int(projection.get("revision", 0)), "data": {"operation": projection}}
	var owner_actor_id := str(state.get("owner_actor_id", ""))
	if not owner_actor_id.is_empty() and owner_actor_id != str(_session.get("actor_id", "")):
		return WorldContracts.result_error(request_id, "command_rejected", "Only the operation owner may finish this operation.")
	state["status"] = status
	state["finished_at_ms"] = int(Time.get_unix_time_from_system() * 1000.0)
	if body.has("reason"):
		state["reason"] = body["reason"]
	var event_type := WorldContracts.EVENT_PORT_OPERATION_STOPPED if status == "stopped" else WorldContracts.EVENT_PORT_OPERATION_COMPLETED
	var event := _publish(stream, event_type, state, "port_operation", operation_id)
	return _success(request_id, event, {"operation": event.get("projection", {})})


func _set_interaction(request_id: String, body: Dictionary, expected: int) -> Dictionary:
	var entity_id := str(body.get("entity_id", "")).strip_edges()
	var kind := str(body.get("kind", "")).strip_edges()
	var action := str(body.get("action", "")).strip_edges()
	if entity_id.is_empty() or kind.is_empty() or action.is_empty():
		return WorldContracts.result_error(request_id, "command_rejected", "entity_id, kind, and action are required")
	var stream := "interaction/%s" % entity_id
	var conflict := _revision_conflict(request_id, stream, expected)
	if not conflict.is_empty():
		return conflict
	var state := {"entity_id": entity_id, "kind": kind, "action": action, "state": (body.get("state", {}) as Dictionary).duplicate(true), "changed_by": str(_session.get("actor_id", ""))}
	var event := _publish(stream, WorldContracts.EVENT_INTERACTION_CHANGED, state, "interaction", entity_id)
	return _success(request_id, event, {"interaction": event.get("projection", {})})


func _publish(stream: String, event_type: String, body: Dictionary, kind: String, id: String) -> Dictionary:
	_cursor += 1
	var revision := int(_stream_revisions.get(stream, 0)) + 1
	_stream_revisions[stream] = revision
	var projection := {
		"kind": kind,
		"id": id,
		"scope": _scope_for(kind, body, id),
		"revision": revision,
		"updated_at_ms": int(Time.get_unix_time_from_system() * 1000.0),
		"state": body.duplicate(true),
	}
	_projections[_projection_key(kind, id)] = projection
	var event := {
		"contract_version": WorldContracts.VERSION,
		"id": _new_id("event"),
		"cursor": _cursor,
		"stream": stream,
		"type": event_type,
		"revision": revision,
		"actor_id": str(_session.get("actor_id", "")),
		"scope": projection["scope"],
		"occurred_at_ms": int(Time.get_unix_time_from_system() * 1000.0),
		"body": body.duplicate(true),
		"projection": projection.duplicate(true),
	}
	event_received.emit(event.duplicate(true))
	return event


func _scope_for(kind: String, body: Dictionary, id: String) -> String:
	if kind == "port_operation" or kind == "vessel_berth":
		return "port:%s" % str(body.get("port_id", ""))
	if kind == "interaction":
		return "entity:%s" % id
	return "global"


func _revision_conflict(request_id: String, stream: String, expected: int) -> Dictionary:
	if expected < 0 or expected == int(_stream_revisions.get(stream, 0)):
		return {}
	return WorldContracts.result_error(request_id, "command_rejected", "Revision conflict.")


func _success(request_id: String, event: Dictionary, data: Dictionary) -> Dictionary:
	return {"contract_version": WorldContracts.VERSION, "request_id": request_id, "ok": true, "revision": int(event.get("revision", 0)), "data": data, "event_ids": [str(event.get("id", ""))]}


func _projection_key(kind: String, id: String) -> String:
	return "%s\u001f%s" % [kind, id]


func _new_id(prefix: String) -> String:
	return "%s-%s-%s" % [prefix, Time.get_ticks_usec(), randi()]
