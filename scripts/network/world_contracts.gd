class_name WorldContracts
extends RefCounted

const VERSION := 1

const COMMAND_PORT_OPERATION_REQUEST := "port.operation.request"
const COMMAND_PORT_OPERATION_STOP := "port.operation.stop"
const COMMAND_PORT_OPERATION_COMPLETE := "port.operation.complete"
const COMMAND_VESSEL_BERTH_CLAIM := "vessel.berth.claim"
const COMMAND_VESSEL_MOORING_SET := "vessel.mooring.set"
const COMMAND_VESSEL_BERTH_RELEASE := "vessel.berth.release"
const COMMAND_INTERACTION_SET := "world.interaction.set"

const EVENT_PORT_OPERATION_STARTED := "port.operation.started"
const EVENT_PORT_OPERATION_STOPPED := "port.operation.stopped"
const EVENT_PORT_OPERATION_COMPLETED := "port.operation.completed"
const EVENT_VESSEL_BERTH_ASSIGNED := "vessel.berth.assigned"
const EVENT_VESSEL_MOORING_CHANGED := "vessel.mooring.changed"
const EVENT_VESSEL_BERTH_RELEASED := "vessel.berth.released"
const EVENT_INTERACTION_CHANGED := "world.interaction.changed"


static func command(
		request_id: String,
		name: String,
		body: Dictionary,
		expected_revision: int = -1,
) -> Dictionary:
	var envelope := {
		"contract_version": VERSION,
		"request_id": request_id.strip_edges(),
		"name": name.strip_edges(),
		"body": body.duplicate(true),
		"sent_at_ms": int(Time.get_unix_time_from_system() * 1000.0),
	}
	if expected_revision >= 0:
		envelope["expected_revision"] = expected_revision
	return envelope


static func result_error(request_id: String, code: String, message: String) -> Dictionary:
	return {
		"contract_version": VERSION,
		"request_id": request_id,
		"ok": false,
		"code": code,
		"message": message,
	}


static func port_operation_body(
		port_id: String,
		berth_id: String,
		equipment_id: String,
		vessel_id: String,
		mode: String,
	commodity_id: String = "",
	contract_id: String = "",
	operation_id: String = "",
	duration_ms: int = 0,
) -> Dictionary:
	var body := {
		"port_id": port_id,
		"berth_id": berth_id,
		"equipment_id": equipment_id,
		"vessel_id": vessel_id,
		"mode": mode,
		"commodity_id": commodity_id,
		"contract_id": contract_id,
	}
	if not operation_id.strip_edges().is_empty():
		body["operation_id"] = operation_id.strip_edges()
	if duration_ms > 0:
		body["duration_ms"] = duration_ms
	return body


static func vessel_berth_claim_body(
		vessel_id: String,
		port_id: String,
		candidate_berth_ids: Array,
		replace_vessel_id: String = "",
) -> Dictionary:
	var candidates: Array[String] = []
	for candidate_variant in candidate_berth_ids:
		var candidate := str(candidate_variant).strip_edges()
		if not candidate.is_empty() and candidate not in candidates:
			candidates.append(candidate)
	var body := {
		"vessel_id": vessel_id.strip_edges(),
		"port_id": port_id.strip_edges(),
		"candidates": candidates,
	}
	var replacement := replace_vessel_id.strip_edges()
	if not replacement.is_empty() and replacement != vessel_id.strip_edges():
		body["replace_vessel_id"] = replacement
	return body


static func vessel_mooring_body(
		vessel_id: String,
		port_id: String,
		berth_id: String,
		bow_line: bool,
		stern_line: bool,
) -> Dictionary:
	return {
		"vessel_id": vessel_id.strip_edges(),
		"port_id": port_id.strip_edges(),
		"berth_id": berth_id.strip_edges(),
		"bow_line": bow_line,
		"stern_line": stern_line,
	}
