class_name CustomPortState
extends RefCounted
## Scene-free harbour document and isolated authority simulation. Metres; Y is
## relative to the common deck. Vessels/accounts are supplied test projections,
## never a second fleet/economy service. A live backend must commit these changes
## atomically with its existing company, vessel and cargo authority records.

const FORMAT_VERSION := 1
const BERTHS = preload("res://scripts/port/state/custom_port_berths.gd")
const PLACEMENT_RULES = preload("res://scripts/port/state/custom_port_placement_rules.gd")
const COMMODITIES = preload("res://scripts/cargo/commodity_catalog.gd")
const VESSEL_PROJECTION = preload("res://scripts/port/state/custom_port_vessel_projection.gd")
const HANDLING_MODES := ["container", "general", "bulk", "catch", "liquid"]
const MAX_SUPPORT_DEPTH_M := 4096.0
const MUTABLE_FIELDS := ["plots", "placements", "stores", "vessels", "reservations"]
const EVENT_FIELDS := ["plots", "placements", "stores", "vessels", "reservations", "water_regions", "name"]
const CATALOG_GEOMETRY := ["kind", "footprint_m", "footprint_polygon_m", "occupied_rects_m", "placement_layer", "placement_kind", "requires_support",
	"berth_edge", "mooring", "reach_max_m", "reach_min_m", "crane_offset_m", "pad_size_m", "pad_offset_m", "storage_rect_m", "cargo_types", "attached_store", "attached_store_only"]
var validation_errors: Array[String] = []
var _record: Dictionary = {}
var _catalog: Dictionary = {}
var _expected_world: Dictionary = {}
var _berths_revision := -1
var _berths_cache: Array[Dictionary] = []
var _validation_berths: Array[Dictionary] = []
var _construction_edges: Array[Dictionary] = []
var _validation_edges: Array[Dictionary] = []


static func from_dict(value: Dictionary, expected_world: Dictionary = {}, catalog: Dictionary = {}) -> CustomPortState:
	var state := CustomPortState.new()
	state._record = value.duplicate(true)
	state._catalog = catalog.duplicate(true)
	state._expected_world = _canonical(expected_world)
	for key in MUTABLE_FIELDS:
		if not state._record.has(key):
			state._record[key] = []
	if not state._record.has("receipts"):
		state._record.receipts = {}
	if not state._record.has("revision"):
		state._record.revision = 0
	if _json_safe(state._record):
		state._record = _canonical(state._record)
	state.validation_errors = state.validate()
	return state


func to_dict() -> Dictionary:
	return _record.duplicate(true)


func revision() -> int:
	return int(_record.get("revision", 0))


func derived_berths() -> Array[Dictionary]:
	if not validation_errors.is_empty():
		return []
	if _berths_revision != revision():
		var geometry: Dictionary = {}
		_berths_cache = BERTHS.derive(_record, _catalog, geometry)
		_construction_edges = geometry.get("construction_edges", [])
		_berths_revision = revision()
	# Read models must not be able to modify the authority's cached projection.
	return _berths_cache.duplicate(true)


func construction_edges() -> Array[Dictionary]:
	if not validation_errors.is_empty(): return []
	if _berths_revision != revision(): derived_berths()
	return _construction_edges.duplicate(true)


## Only the current, validated document can lend its construction results.
## Cargo, reservations and vessel occupancy are checked anew below. Imported
## documents start without a cache, and every changed structural input rebuilds.
func _same_construction(data: Dictionary) -> bool:
	if not validation_errors.is_empty() or _berths_revision!=revision():return false
	for key in ["id","world","origin_m","deck_height_above_sea_m","plots","placements","water_regions","berth_rules"]:
		if data.get(key)!=_record.get(key):return false
	var stores: Variant=data.get("stores")
	if not stores is Array or stores.size()!=_record.stores.size():return false
	for index in stores.size():
		if not stores[index] is Dictionary:return false
		# Shallow copies are deliberate: removing the top-level manifest must not
		# duplicate potentially thousands of lots just to compare store fittings.
		var proposed: Dictionary=stores[index].duplicate()
		var current: Dictionary=_record.stores[index].duplicate()
		proposed.erase("lots");current.erase("lots")
		if proposed!=current:return false
	return true


func _berths_for(data: Dictionary) -> Array[Dictionary]:
	if _same_construction(data):return _berths_cache.duplicate(true)
	return BERTHS.derive(data,_catalog)


func validate() -> Array[String]:
	var errors := _validate(_record)
	if errors.is_empty(): _adopt_validated_berths()
	return errors


func _adopt_validated_berths() -> void:
	_berths_cache = _validation_berths.duplicate(true)
	_construction_edges = _validation_edges.duplicate(true)
	_berths_revision = revision()


func preview_asset(placement: Dictionary, actor_company_id: String) -> Dictionary:
	if not validation_errors.is_empty() or not _json_safe(placement):
		return {"ok": false, "errors": ["Invalid port or placement."]}
	var candidate := _record.duplicate(true)
	var result := _execute(candidate, "place_asset", actor_company_id, {"placement": _canonical(placement)}, {}, "preview")
	if not result.ok:
		return {"ok": false, "errors": [str(result.code)]}
	var errors := _validate(candidate)
	return {"ok": errors.is_empty(), "errors": errors}


func preview_transform(payload: Dictionary, actor_company_id: String) -> Dictionary:
	if not validation_errors.is_empty() or not _json_safe(payload):
		return {"ok": false, "code": "invalid_transform", "errors": ["Invalid port or transform."]}
	var candidate := _record.duplicate(true)
	var result := _execute(candidate, "transform_asset", actor_company_id, _canonical(payload), {}, "preview-transform")
	if not result.ok: return {"ok": false, "code": str(result.code), "errors": [str(result.code)]}
	var errors := _validate(candidate)
	return {"ok": errors.is_empty(), "code": "valid_transform" if errors.is_empty() else "invalid_result", "errors": errors}


## Command preflight ONLY, not permission to place. The editor must still check
## plot containment and exact support/overlap geometry. Final apply() retains
## full document validation. No preview result is trusted by an authority.
func preflight_nonstructural_transform(payload: Dictionary, actor_company_id: String) -> Dictionary:
	if not validation_errors.is_empty() or not _json_safe(payload):
		return {"supported": true, "command_allowed": false, "code": "invalid_transform", "errors": ["Invalid port or transform."]}
	var placement := _find(_record.placements, str(payload.get("placement_id", "")))
	if placement.is_empty():
		return {"supported": true, "command_allowed": false, "code": "placement_not_found", "errors": ["placement_not_found"]}
	var definition := PLACEMENT_RULES.definition(placement, _catalog)
	# Only these known non-structural kinds leave platform support, exposed
	# edges, surveyed approach water and moored hull geometry unchanged. Future
	# topology kinds and explicit mooring flags stay on complete validation.
	if str(definition.get("kind", "decoration")) not in ["decoration", "npc", "crane"] or definition.get("mooring", false) or definition.get("berth_edge", false):
		return {"supported": false, "command_allowed": false, "code": "requires_full_validation", "errors": []}
	var candidate := _record.duplicate(true)
	# Reuse the actual command, including reservation protection for a store and
	# every crane serving a cross-linked yard. Do not mirror that logic in UI.
	var result := _execute(candidate, "transform_asset", actor_company_id, _canonical(payload), {}, "preview-preflight")
	return {"supported": true, "command_allowed": bool(result.ok), "code": "preflight_passed" if result.ok else str(result.code),
		"errors": [] if result.ok else [str(result.code)]}


func apply(command: Dictionary, authority_context: Dictionary = {}) -> Dictionary:
	if not validation_errors.is_empty():
		return _failure("invalid_document", {"errors": validation_errors})
	if not _json_safe(command) or not _json_safe(authority_context):
		return _failure("non_json_command")
	var command_id := str(command.get("command_id", ""))
	var kind := str(command.get("kind", ""))
	var actor := str(command.get("actor_company_id", ""))
	if not command.get("command_id") is String or not command.get("actor_company_id") is String or not command.get("kind") is String or command_id.is_empty() or actor.is_empty() or not command.get("payload", {}) is Dictionary:
		return _failure("invalid_command")
	var fingerprint := JSON.stringify(_canonical({"kind": kind, "actor": actor, "payload": command.get("payload", {})}), "", true).sha256_text()
	if _record.receipts.has(command_id):
		var prior: Dictionary = _record.receipts[command_id]
		if prior.fingerprint != fingerprint:
			return _failure("command_id_conflict")
		return {"ok": true, "code": "already_applied", "replayed": true,
			"revision": _record.revision, "applied_revision": prior.applied_revision,
			"result": prior.result.duplicate(true), "events": [], "account_changes": [], "snapshot": to_dict()}
	if not _integer(command.get("expected_revision", -1)) or int(command.expected_revision) != int(_record.revision):
		return _failure("revision_conflict")
	var candidate := _record.duplicate(true)
	var outcome := _execute(candidate, kind, actor, _canonical(command.get("payload", {})), _canonical(authority_context), command_id)
	if not outcome.get("ok", false):
		return _failure(str(outcome.get("code", "rejected")), outcome.get("details", {}))
	var errors := _validate(candidate)
	if not errors.is_empty():
		return _failure("invalid_result", {"errors": errors})
	var next_revision := int(_record.revision) + 1
	var receipt := {"fingerprint": fingerprint, "applied_revision": next_revision,
		"result": outcome.get("result", {}).duplicate(true)}
	var changes: Dictionary = {}
	for key in EVENT_FIELDS:
		if candidate.get(key, []) != _record.get(key, []):
			changes[key] = candidate[key] if key == "name" else candidate.get(key, []).duplicate(true)
	candidate.revision = next_revision
	candidate.receipts[command_id] = receipt
	var event := {"id": "%s:%s" % [candidate.id, command_id], "port_id": candidate.id,
		"command_id": command_id, "revision": next_revision, "kind": kind,
		"changes": changes, "receipt": receipt.duplicate(true)}
	_record = _canonical(candidate)
	_adopt_validated_berths()
	event = _canonical(event)
	return {"ok": true, "code": "applied", "revision": next_revision, "applied_revision": next_revision,
		"replayed": false, "result": receipt.result.duplicate(true), "events": [event],
		"account_changes": outcome.get("account_changes", []), "snapshot": to_dict()}


func replay_event(event: Dictionary) -> Dictionary:
	# Consume only authority-issued events, in order. Clients cannot submit these
	# as commands: this is reconstruction for a save or a subscribed read model.
	if not validation_errors.is_empty() or not _json_safe(event):
		return _failure("invalid_event")
	if str(event.get("port_id", "")) != str(_record.id):
		return _failure("wrong_port")
	var command_id := str(event.get("command_id", ""))
	if command_id.is_empty() or not event.get("receipt") is Dictionary:
		return _failure("invalid_event")
	if _record.receipts.has(command_id):
		if _record.receipts[command_id] == _canonical(event.receipt):
			return {"ok": true, "code": "already_applied", "snapshot": to_dict(), "events": []}
		return _failure("command_id_conflict")
	if not _integer(event.get("revision", -1)) or int(event.revision) != int(_record.revision) + 1:
		return _failure("event_gap")
	if not event.get("changes") is Dictionary:
		return _failure("invalid_event")
	var candidate := _record.duplicate(true)
	for key in event.changes:
		if key == "name":
			if str(event.get("kind", "")) != "rename_port" or not _valid_port_name(event.changes[key]):
				return _failure("invalid_event_field")
			candidate.name = event.changes[key]
			continue
		if key not in EVENT_FIELDS or not event.changes[key] is Array:
			return _failure("invalid_event_field")
		if key == "water_regions" and str(event.get("kind", "")) != "refresh_water_survey":
			return _failure("invalid_event_field")
		if key == "water_regions":
			var previous: Array = _record.get("water_regions", [])
			if event.changes[key].size() < previous.size():
				return _failure("invalid_survey_event")
			for index in previous.size():
				if not _equivalent(_canonical(previous[index]), _canonical(event.changes[key][index])):
					return _failure("invalid_survey_event")
		candidate[key] = event.changes[key].duplicate(true)
	candidate.revision = int(event.revision)
	candidate.receipts[command_id] = event.receipt.duplicate(true)
	var errors := _validate(candidate)
	if not errors.is_empty():
		return _failure("invalid_event_result", {"errors": errors})
	_record = _canonical(candidate)
	_adopt_validated_berths()
	return {"ok": true, "code": "applied", "revision": _record.revision, "snapshot": to_dict(), "events": []}


func _execute(data: Dictionary, kind: String, actor: String, payload: Dictionary, context: Dictionary, command_id: String) -> Dictionary:
	match kind:
		"rename_port":
			if actor != data.owner_company_id: return _reject("not_port_owner")
			if payload.size() != 1 or not payload.get("name") is String:
				return _reject("invalid_port_name")
			var proposed_name: String = payload.name.strip_edges()
			if not _valid_port_name(proposed_name): return _reject("invalid_port_name")
			if proposed_name == data.get("name", ""): return _reject("port_name_unchanged")
			data.name = proposed_name
			return _success({"name":proposed_name})
		"admit_vessel":
			return _admit_vessel(data, actor, payload, context)
		"refresh_water_survey":
			return _refresh_water_survey(data, actor, payload, context)
		"configure_store":
			return _configure_store(data, actor, payload, context)
		"transform_asset":
			return _transform_asset(data, actor, payload)
		"edit_assets":
			if actor != data.owner_company_id:
				return _reject("not_port_owner")
			var operations: Variant = payload.get("operations")
			if not operations is Array or operations.is_empty() or operations.size() > 4096:
				return _reject("invalid_edit_operations")
			for operation in operations:
				if not operation is Dictionary or str(operation.get("kind", "")) not in ["place_asset", "remove_asset", "transform_asset"] or not operation.get("payload") is Dictionary:
					return _reject("invalid_edit_operations")
				var changed := _execute(data, operation.kind, actor, operation.payload, context, command_id)
				if not changed.ok:
					return changed
			return _success()
		"buy_plot":
			return _buy_plot(data, actor, payload, context)
		"place_asset", "remove_asset":
			if actor != data.owner_company_id:
				return _reject("not_port_owner")
			if kind == "place_asset":
				if not payload.get("placement") is Dictionary or not _placement_schema_valid(payload.placement):
					return _reject("invalid_result", {"errors": ["Invalid placement or catalogue override."]})
				if not _find(data.placements, str(payload.placement.id)).is_empty():
					return _reject("invalid_result", {"errors": ["Duplicate placement id."]})
				var placement: Dictionary = payload.placement.duplicate(true)
				var attached := _create_attached_store(data, placement, payload)
				if not attached.ok:
					return attached
				data.placements.append(placement)
			else:
				var placement := _find(data.placements, str(payload.get("placement_id", "")))
				if placement.is_empty():
					return _reject("placement_not_found")
				if payload.has("expected_placement") and not _equivalent(_canonical(placement), _canonical(payload.expected_placement)):
					return _reject("placement_changed")
				for store in data.stores:
					if str(store.get("placement_id", "")) == str(placement.id):
						if not store.get("lots", []).is_empty() or not _catalog.get(placement.asset_id, {}).has("attached_store"):
							return _reject("placement_has_store")
						for reservation in data.reservations:
							if str(reservation.store_id) == str(store.id):
								return _reject("store_reserved")
				data.stores = data.stores.filter(func(store: Dictionary) -> bool: return str(store.get("placement_id", "")) != str(placement.id))
				data.placements.erase(placement)
			if kind == "remove_asset":
				for vessel in data.vessels:
					if not str(vessel.get("berth_id", "")).is_empty() and _find(_berths_for(data), vessel.berth_id).is_empty():
						return _reject("berth_in_use")
			return _success()
		"dock", "undock":
			return _dock(data, kind, actor, payload)
		"reserve_cargo":
			return _reserve(data, actor, payload, command_id)
		"cancel_reservation", "load_cargo":
			return _load_or_cancel(data, kind, actor, payload)
		"unload_cargo":
			return _unload(data, actor, payload)
	return _reject("unknown_command")


static func _valid_port_name(value: Variant) -> bool:
	if not value is String or value.is_empty() or value.length() > 80 or value != value.strip_edges(): return false
	for index in value.length():
		var codepoint: int = value.unicode_at(index)
		if codepoint < 32 or (codepoint >= 127 and codepoint <= 159) or codepoint in [0x2028,0x2029]: return false
	return true


## Move the existing entity, never replace it. Attached inventories stay bound to
## the same placement and retain their current quantities, IDs and permissions.
func _transform_asset(data: Dictionary, actor: String, payload: Dictionary) -> Dictionary:
	if actor != data.owner_company_id: return _reject("not_port_owner")
	if payload.size() not in [4, 5] or not payload.get("placement_id") is String or not payload.get("expected_placement") is Dictionary \
		or not _vector(payload.get("position_m"), 3) or not _number(payload.get("yaw_degrees")):
		return _reject("invalid_transform")
	for key in payload:
		if key not in ["placement_id", "expected_placement", "position_m", "yaw_degrees", "support_depth_m"]: return _reject("invalid_transform")
	var placement := _find(data.placements, payload.placement_id)
	if placement.is_empty(): return _reject("placement_not_found")
	if not _equivalent(_canonical(placement), _canonical(payload.expected_placement)): return _reject("placement_changed")
	var definition := PLACEMENT_RULES.definition(placement, _catalog)
	var depth_changed := false
	if payload.has("support_depth_m"):
		var depth: Variant = payload.support_depth_m
		if str(definition.get("kind", "")) != "platform" or (depth != null and (not _positive(depth) or float(depth) > MAX_SUPPORT_DEPTH_M)):
			return _reject("invalid_support_depth")
		depth_changed = placement.get("attributes", {}).get("support_depth_m") != depth
	if not depth_changed and _equivalent(_canonical(placement.position_m), _canonical(payload.position_m)) and _equivalent(_canonical(placement.yaw_degrees), _canonical(payload.yaw_degrees)):
		return _reject("placement_unchanged")
	var previous_berths: Array[Dictionary] = []
	if not data.reservations.is_empty():
		previous_berths = _berths_for(data)
		for reservation in data.reservations:
			var store := _find(data.stores, str(reservation.store_id))
			if str(store.get("placement_id", "")) == str(placement.id): return _reject("store_reserved")
			var vessel := _find(data.vessels, str(reservation.vessel_id))
			var berth := _find(previous_berths, str(vessel.get("berth_id", "")))
			var lot := _find(store.get("lots", []), str(reservation.lot_id))
			for service in BERTHS.services_for_vessel(berth, vessel, _handling_mode(lot)).get("crane_services", []):
				if str(service.crane_id) == str(placement.id) and str(store.id) in service.store_ids:
					return _reject("placement_reserved")
	var alters_berths: bool = str(definition.get("kind", "")) in ["platform", "bollard"] or definition.get("berth_edge", false) or definition.get("mooring", false)
	var occupied: Dictionary = {}
	if alters_berths:
		if previous_berths.is_empty(): previous_berths = _berths_for(data)
		for vessel in data.vessels:
			var id := str(vessel.get("berth_id", ""))
			if not id.is_empty(): occupied[id] = _mooring_geometry(_find(previous_berths, id))
	placement.position_m = payload.position_m.duplicate()
	placement.yaw_degrees = payload.yaw_degrees
	if depth_changed:
		if payload.support_depth_m == null: placement.attributes.erase("support_depth_m")
		else:
			if not placement.has("attributes"): placement.attributes = {}
			placement.attributes.support_depth_m = payload.support_depth_m
	if not occupied.is_empty():
		var following := _berths_for(data)
		for id in occupied:
			if not _equivalent(occupied[id], _mooring_geometry(_find(following, id))): return _reject("berth_in_use")
	return _success({"placement_id": str(placement.id)})


static func _mooring_geometry(berth: Dictionary) -> Dictionary:
	var geometry := berth.duplicate(true)
	# An idle crane may move while a ship remains safely secured. Its operating
	# reservation and reach are checked separately; the moored pose cannot move.
	for key in ["crane_ids", "store_ids", "crane_services"]: geometry.erase(key)
	return geometry


## Import an existing authoritative vessel projection into this port's local
## operating view. The command carries an ID, never client-authored capacity or
## cargo. A production adapter must supply this context from its fleet authority.
func _admit_vessel(data: Dictionary, actor: String, payload: Dictionary, context: Dictionary) -> Dictionary:
	if payload.size()!=1 or not payload.get("vessel_id") is String or str(payload.vessel_id).is_empty():return _reject("invalid_vessel_reference")
	var id: String=payload.vessel_id
	if not _find(data.vessels,id).is_empty():return _reject("vessel_already_known")
	var records: Variant=context.get("vessel_records",{})
	if not records is Dictionary or not records.get(id) is Dictionary:return _reject("authority_vessel_unavailable")
	var vessel: Dictionary=records[id].duplicate(true)
	if vessel.get("id")!=id:return _reject("invalid_authority_vessel")
	if vessel.get("owner_company_id")!=actor:return _reject("not_vessel_owner")
	# Admission is not docking. It cannot reserve a berth or bypass its fit check.
	if not vessel.get("berth_id","") is String or not str(vessel.get("berth_id","")).is_empty():return _reject("vessel_already_docked")
	var physical:=VESSEL_PROJECTION.validate_vessel(vessel)
	if not physical.ok:return _reject("invalid_authority_vessel",{"errors":physical.errors})
	data.vessels.append(vessel)
	return _success({"vessel_id":id})


func _placement_schema_valid(placement: Dictionary) -> bool:
	if not placement.get("id") is String or str(placement.id).is_empty() or not placement.get("asset_id") is String or not _catalog.has(placement.asset_id):
		return false
	if not _vector(placement.get("position_m"), 3) or not _number(placement.get("yaw_degrees")) or not placement.get("attributes", {}) is Dictionary:
		return false
	var attributes: Dictionary = placement.get("attributes", {})
	var definition: Dictionary = _canonical(_catalog[placement.asset_id])
	if attributes.has("support_depth_m") and (not _positive(attributes.support_depth_m) or float(attributes.support_depth_m) > MAX_SUPPORT_DEPTH_M):
		return false
	for key in CATALOG_GEOMETRY:
		if attributes.has(key) and (not definition.has(key) or not _equivalent(attributes[key], definition[key])):
			return false
	if not attributes.get("store_ids", []) is Array:
		return false
	for store_id in attributes.get("store_ids", []):
		if not store_id is String:
			return false
	return true


func _create_attached_store(data: Dictionary, placement: Dictionary, payload: Dictionary) -> Dictionary:
	var definition: Dictionary = _catalog.get(placement.asset_id, {})
	if not definition.has("attached_store"):
		return _reject("asset_has_no_attached_store") if payload.has("restore_empty_stores") else _success()
	var spec: Dictionary = definition.attached_store
	var store: Dictionary = spec.duplicate(true)
	store.id = "store:%s" % placement.id
	store.placement_id = placement.id
	store.name = str(spec.get("name", definition.get("name", "Cargo store")))
	store.lots = []
	store.public_loading = false
	store.public_unloading = false
	if payload.has("restore_empty_stores"):
		var saved: Variant = payload.restore_empty_stores
		if not saved is Array or saved.size() != 1 or not saved[0] is Dictionary:
			return _reject("invalid_attached_store")
		var original: Dictionary = saved[0]
		if not original.get("lots") is Array or not original.lots.is_empty() or str(original.get("placement_id", "")) != str(placement.id):
			return _reject("cannot_restore_stock")
		# Undo may restore access restrictions and identity, but cannot use this
		# endpoint to invent goods or exceed the catalog's physical capacities.
		if not _nonnegative(original.get("capacity_kg")) or float(original.capacity_kg) > float(spec.get("capacity_kg", 0)):
			return _reject("invalid_attached_store_capacity")
		if spec.has("capacity_units") and (not _integer(original.get("capacity_units")) or float(original.capacity_units) < 0 or float(original.capacity_units) > float(spec.capacity_units)):
			return _reject("invalid_attached_store_capacity")
		for key in ["accepted_handling_modes", "accepted_container_types", "accepted_commodities"]:
			if not original.has(key):
				continue
			if not original[key] is Array:
				return _reject("invalid_attached_store")
			var allowed: Array = spec.get(key, [])
			if not allowed.is_empty():
				if original[key].is_empty():
					return _reject("invalid_attached_store")
				for value in original[key]:
					if value not in allowed:
						return _reject("invalid_attached_store")
		for key in ["id", "name", "capacity_kg", "capacity_units", "accepted_handling_modes", "accepted_container_types", "accepted_commodities", "public_loading", "public_unloading", "attributes"]:
			if original.has(key):
				store[key] = original[key].duplicate(true) if original[key] is Dictionary or original[key] is Array else original[key]
	if not _find(data.stores, str(store.id)).is_empty():
		return _reject("attached_store_id_conflict")
	data.stores.append(store)
	if not placement.has("attributes"):
		placement.attributes = {}
	var links: Array = placement.attributes.get("store_ids", []).duplicate()
	if store.id not in links:
		links.append(store.id)
	placement.attributes.store_ids = links
	return _success()


func _refresh_water_survey(data: Dictionary, actor: String, payload: Dictionary, context: Dictionary) -> Dictionary:
	if actor != data.owner_company_id:
		return _reject("not_port_owner")
	if not payload.is_empty():
		return _reject("survey_payload_not_allowed")
	if not context.get("water_survey") is Dictionary:
		return _reject("trusted_survey_required")
	var survey: Dictionary = context.water_survey
	if str(survey.get("port_id", "")) != str(data.id):
		return _reject("survey_port_mismatch")
	if not survey.get("world") is Dictionary or not _equivalent(_canonical(survey.world), _canonical(data.world)):
		return _reject("survey_world_mismatch")
	if not _integer(survey.get("for_revision")) or int(survey.for_revision) != int(data.revision):
		return _reject("survey_revision_mismatch")
	if not survey.get("regions") is Array:
		return _reject("invalid_survey_regions")
	var regions: Array = data.get("water_regions", []).duplicate(true)
	var added := 0
	for raw in survey.regions:
		if not raw is Dictionary or not _rect(raw.get("rect_m")) or not _nonnegative(raw.get("depth_m")):
			return _reject("invalid_survey_regions")
		var rect := _as_rect(raw.rect_m)
		var duplicate := false
		for old in regions:
			var previous := _as_rect(old.rect_m)
			if previous.is_equal_approx(rect):
				if not is_equal_approx(float(old.depth_m), float(raw.depth_m)):
					return _reject("survey_depth_conflict")
				duplicate = true
				break
			var overlap := previous.intersection(rect)
			if overlap.size.x > 0.00001 and overlap.size.y > 0.00001:
				return _reject("survey_overlap")
		if not duplicate:
			regions.append({"rect_m": raw.rect_m.duplicate(), "depth_m": raw.depth_m})
			added += 1
	data.water_regions = regions
	return _success({"regions_added": added, "regions_total": regions.size()})


func _configure_store(data: Dictionary, actor: String, payload: Dictionary, context: Dictionary) -> Dictionary:
	if actor != data.owner_company_id:
		return _reject("not_port_owner")
	var store := _find(data.stores, str(payload.get("store_id", "")))
	if store.is_empty():
		return _reject("store_not_found")
	if not payload.get("changes") is Dictionary or payload.changes.is_empty():
		return _reject("invalid_store_changes")
	var changes: Dictionary = payload.changes
	for key in changes:
		if key not in ["name", "public_loading", "public_unloading", "accepted_commodities"]:
			return _reject("store_field_not_editable", {"field": key})
	if changes.has("name") and (not changes.name is String or changes.name.strip_edges().is_empty() or changes.name.length() > 80 or changes.name.contains("\n") or changes.name.contains("\r") or changes.name.contains("\t")):
		return _reject("invalid_store_name")
	for key in ["public_loading", "public_unloading"]:
		if changes.has(key) and not changes[key] is bool:
			return _reject("invalid_store_access")
	if changes.has("accepted_commodities"):
		if not changes.accepted_commodities is Array or changes.accepted_commodities.size() > 256:
			return _reject("invalid_commodity_filter")
		if not context.get("commodity_ids", []) is Array:
			return _reject("invalid_authority_context")
		var known: Array[String] = []
		for entry in COMMODITIES.COMMODITIES:
			known.append(str(entry.id))
		for id in context.get("commodity_ids", []):
			if not id is String or id.is_empty():
				return _reject("invalid_authority_context")
			known.append(id)
		for existing in data.stores + data.vessels:
			for lot in existing.get("lots", []):
				known.append(str(lot.commodity_id))
			for id in existing.get("accepted_commodities", []):
				known.append(str(id))
		var placement := _find(data.placements, str(store.placement_id))
		var definition: Dictionary = _catalog.get(placement.get("asset_id", ""), {}).get("attached_store", {})
		var supported: Array = definition.get("accepted_commodities", [])
		if not supported.is_empty() and changes.accepted_commodities.is_empty():
			return _reject("unsupported_commodity_filter")
		var seen: Array[String] = []
		for id in changes.accepted_commodities:
			if not id is String or id.is_empty() or id in seen:
				return _reject("invalid_commodity_filter")
			if id not in known and id not in supported:
				return _reject("unknown_commodity", {"commodity_id": id})
			if not supported.is_empty() and id not in supported:
				return _reject("unsupported_commodity_filter", {"commodity_id": id})
			seen.append(id)
		if not changes.accepted_commodities.is_empty():
			for lot in store.lots:
				if lot.commodity_id not in changes.accepted_commodities:
					return _reject("store_contains_excluded_goods", {"commodity_id": lot.commodity_id})
	var public_loading: bool = changes.get("public_loading", store.get("public_loading", false))
	for reservation in data.reservations:
		if str(reservation.store_id) == str(store.id) and str(reservation.actor_company_id) != str(data.owner_company_id) and not public_loading:
			return _reject("store_has_visitor_reservation")
	for key in changes:
		store[key] = changes[key].duplicate(true) if changes[key] is Array else changes[key]
	if changes.has("name"):
		store.name = str(store.name).strip_edges()
	return _success({"store_id": store.id})


func _dock(data: Dictionary, kind: String, actor: String, payload: Dictionary) -> Dictionary:
	var vessel := _find(data.vessels, str(payload.get("vessel_id", "")))
	if vessel.is_empty():
		return _reject("vessel_not_found")
	if vessel.owner_company_id != actor:
		return _reject("not_vessel_owner")
	if kind == "undock":
		if str(vessel.get("berth_id", "")).is_empty():
			return _reject("not_docked")
		for reservation in data.reservations:
			if reservation.vessel_id == vessel.id:
				return _reject("cargo_reserved")
		vessel.berth_id = ""
		return _success()
	if not str(vessel.get("berth_id", "")).is_empty():
		return _reject("already_docked")
	var berth := _find(_berths_for(data), str(payload.get("berth_id", "")))
	if berth.is_empty():
		return _reject("berth_not_found")
	var occupancy: Array = []
	for other in data.vessels:
		if not str(other.get("berth_id", "")).is_empty():
			occupancy.append({"berth_id": other.berth_id, "vessel_id": other.id})
	var fit: Dictionary = BERTHS.fit(berth, vessel, occupancy)
	if not fit.get("ok", false):
		return _reject("vessel_does_not_fit", {"reasons": fit.get("reasons", [])})
	vessel.berth_id = berth.id
	return _success({"berth_id": berth.id})


func _reserve(data: Dictionary, actor: String, payload: Dictionary, command_id: String) -> Dictionary:
	var store := _find(data.stores, str(payload.get("store_id", "")))
	var vessel := _find(data.vessels, str(payload.get("vessel_id", "")))
	var lot := _find(store.get("lots", []), str(payload.get("lot_id", "")))
	var permission := _cargo_access(data, store, vessel, actor, true, lot)
	if not permission.ok:
		return permission
	if lot.is_empty():
		return _reject("lot_not_found")
	var compatibility := _cargo_compatibility(vessel, lot)
	if not compatibility.ok:
		return compatibility
	var quantity: Variant = payload.get("quantity", 0)
	if not _valid_quantity(quantity, lot):
		return _reject("invalid_quantity")
	var available := float(lot.quantity)
	var reserved_mass := 0.0
	var reserved_units := 0.0
	var reserved_kind_mass := 0.0
	for reservation in data.reservations:
		if reservation.store_id == store.id and reservation.lot_id == lot.id:
			available -= float(reservation.quantity)
		if reservation.vessel_id == vessel.id:
			reserved_mass += float(reservation.quantity) * float(reservation.unit_mass_kg)
			reserved_units += float(reservation.quantity) * float(reservation.get("slots_per_unit", 1))
			var source := _find(data.stores, str(reservation.store_id))
			var source_lot := _find(source.get("lots", []), str(reservation.lot_id))
			if _handling_mode(source_lot) == _handling_mode(lot):
				reserved_kind_mass += float(reservation.quantity) * float(reservation.unit_mass_kg)
	if (float(quantity)-available)*float(lot.unit_mass_kg)>0.000001:
		return _reject("insufficient_stock", {"requested": quantity, "available": maxf(available, 0.0)})
	var free_mass := float(vessel.capacity_kg) - _mass(vessel.lots) - reserved_mass
	if float(quantity) * float(lot.unit_mass_kg) > free_mass + 0.000001:
		return _reject("vessel_capacity_exceeded", {"free_mass_kg": maxf(0.0, free_mass)})
	if not _typed_capacity_fits(vessel, lot, float(quantity), reserved_kind_mass):
		return _reject("handling_capacity_exceeded")
	var slots_per_unit := _lot_slots(lot)
	if vessel.has("capacity_units") and _units(vessel.lots) + reserved_units + float(quantity) * slots_per_unit > float(vessel.capacity_units) + 0.000001:
		return _reject("vessel_slots_exceeded", {"free_units": maxf(0, float(vessel.capacity_units) - _units(vessel.lots) - reserved_units)})
	var bulk_plan := _reserved_hold_plan(data, vessel, lot, float(quantity))
	if not bulk_plan.ok:
		return _reject(str(bulk_plan.code), bulk_plan)
	var reservation_id := str(payload.get("reservation_id", command_id))
	if reservation_id.is_empty() or not _find(data.reservations, reservation_id).is_empty():
		return _reject("reservation_id_conflict")
	data.reservations.append({"id": reservation_id, "store_id": store.id, "vessel_id": vessel.id,
		"lot_id": lot.id, "quantity": float(quantity), "unit_mass_kg": lot.unit_mass_kg,
		"slots_per_unit": slots_per_unit, "actor_company_id": actor})
	return _success({"reservation_id": reservation_id, "quantity": quantity})


func _load_or_cancel(data: Dictionary, kind: String, actor: String, payload: Dictionary) -> Dictionary:
	var reservation := _find(data.reservations, str(payload.get("reservation_id", "")))
	if reservation.is_empty():
		return _reject("reservation_not_found")
	if reservation.actor_company_id != actor and data.owner_company_id != actor:
		return _reject("not_reservation_owner")
	if kind == "cancel_reservation":
		data.reservations.erase(reservation)
		return _success()
	var store := _find(data.stores, reservation.store_id)
	var vessel := _find(data.vessels, reservation.vessel_id)
	var lot := _find(store.get("lots", []), reservation.lot_id)
	var permission := _cargo_access(data, store, vessel, actor, true, lot)
	if not permission.ok:
		return permission
	if lot.is_empty() or float(lot.quantity) < float(reservation.quantity):
		return _reject("insufficient_stock")
	var compatibility := _cargo_compatibility(vessel, lot)
	if not compatibility.ok:
		return compatibility
	if not _typed_capacity_fits(vessel, lot, float(reservation.quantity)):
		return _reject("handling_capacity_exceeded")
	if _mass(vessel.lots) + float(reservation.quantity) * float(lot.unit_mass_kg) > float(vessel.capacity_kg) + 0.000001:
		return _reject("vessel_capacity_exceeded")
	if vessel.has("capacity_units") and _units(vessel.lots) + float(reservation.quantity) * float(reservation.get("slots_per_unit", 1)) > float(vessel.capacity_units) + 0.000001:
		return _reject("vessel_slots_exceeded")
	if not _compatible_lot(vessel.lots, lot):
		return _reject("lot_identity_conflict")
	var loaded := vessel.duplicate(true)
	_append_projected_lot(loaded.lots, lot, float(reservation.quantity))
	var bulk_plan := _hold_plan(loaded, loaded.lots)
	if not bulk_plan.ok:
		return _reject(str(bulk_plan.code), bulk_plan)
	bulk_plan = _reserved_hold_plan(data, loaded, {}, 0, str(reservation.id))
	if not bulk_plan.ok:
		return _reject(str(bulk_plan.code), bulk_plan)
	_move_lot(store.lots, vessel.lots, lot, float(reservation.quantity))
	data.reservations.erase(reservation)
	var result: Dictionary = permission.result.duplicate()
	result.merge({"quantity": reservation.quantity, "lot_id": lot.id})
	return _success(result)


func _unload(data: Dictionary, actor: String, payload: Dictionary) -> Dictionary:
	var store := _find(data.stores, str(payload.get("store_id", "")))
	var vessel := _find(data.vessels, str(payload.get("vessel_id", "")))
	var lot := _find(vessel.get("lots", []), str(payload.get("lot_id", "")))
	var permission := _cargo_access(data, store, vessel, actor, false, lot)
	if not permission.ok:
		return permission
	if lot.is_empty():
		return _reject("lot_not_found")
	var quantity: Variant = payload.get("quantity", 0)
	if not _valid_quantity(quantity, lot):
		return _reject("invalid_quantity")
	if float(quantity) > float(lot.quantity):
		return _reject("insufficient_cargo", {"available": lot.quantity})
	var accepted: Array = store.get("accepted_commodities", [])
	if not accepted.is_empty() and lot.commodity_id not in accepted:
		return _reject("commodity_not_accepted")
	var compatibility := _cargo_compatibility(store, lot)
	if not compatibility.ok:
		return compatibility
	if not _typed_capacity_fits(store, lot, float(quantity)):
		return _reject("handling_capacity_exceeded")
	if _mass(store.lots) + float(quantity) * float(lot.unit_mass_kg) > float(store.capacity_kg) + 0.000001:
		return _reject("store_capacity_exceeded")
	if store.has("capacity_units") and _units(store.lots) + float(quantity) * _lot_slots(lot) > float(store.capacity_units) + 0.000001:
		return _reject("store_slots_exceeded")
	if not _compatible_lot(store.lots, lot):
		return _reject("lot_identity_conflict")
	_move_lot(vessel.lots, store.lots, lot, float(quantity))
	var result: Dictionary = permission.result.duplicate()
	result.merge({"quantity": quantity, "lot_id": lot.id})
	return _success(result)


func _cargo_access(data: Dictionary, store: Dictionary, vessel: Dictionary, actor: String, loading: bool, lot: Dictionary = {}) -> Dictionary:
	if store.is_empty() or vessel.is_empty():
		return _reject("store_or_vessel_not_found")
	if vessel.owner_company_id != actor:
		return _reject("not_vessel_owner")
	var public_key := "public_loading" if loading else "public_unloading"
	if actor != data.owner_company_id and not store.get(public_key, false):
		return _reject("store_access_denied")
	var berth := _find(_berths_for(data), str(vessel.get("berth_id", "")))
	if berth.is_empty():
		return _reject("not_docked")
	if store.id not in BERTHS.services_for_vessel(berth, vessel).get("store_ids", []):
		return _reject("store_out_of_reach")
	if not lot.is_empty():
		var mode := _handling_mode(lot)
		var services: Dictionary = BERTHS.services_for_vessel(berth, vessel, mode)
		for service in services.get("crane_services", []):
			if str(store.id) in service.get("store_ids", []):
				return _success({"crane_id": service.crane_id, "store_id": store.id, "vessel_id": vessel.id})
		return _reject("crane_handling_not_supported", {"handling_mode": mode})
	return _success()


func _buy_plot(data: Dictionary, actor: String, payload: Dictionary, context: Dictionary) -> Dictionary:
	if actor != data.owner_company_id:
		return _reject("not_port_owner")
	var plot_id := str(payload.get("plot_id", ""))
	if not context.get("plot_offers", {}) is Dictionary or not context.get("accounts", {}) is Dictionary:
		return _reject("invalid_authority_context")
	var offers: Dictionary = context.get("plot_offers", {})
	var accounts: Dictionary = context.get("accounts", {})
	if not offers.get(plot_id) is Dictionary or not accounts.get(actor) is Dictionary:
		return _reject("plot_offer_or_account_missing")
	var offer: Dictionary = offers[plot_id]
	var account: Dictionary = accounts[actor]
	if not offer.get("available", false) is bool or not offer.get("owner_company_id", "") is String:
		return _reject("invalid_plot_offer")
	if not offer.get("available", false) or not str(offer.get("owner_company_id", "")).is_empty():
		return _reject("plot_unavailable")
	if not _find(data.plots, plot_id).is_empty():
		return _reject("plot_already_owned")
	if offer.get("world", {}) != data.world or not _rect(offer.get("rect_m")):
		return _reject("invalid_plot_offer")
	if not _nonnegative(offer.get("price_nok")) or not _nonnegative(account.get("balance_nok")):
		return _reject("invalid_plot_price_or_balance")
	var target := _as_rect(offer.rect_m)
	var adjoining := false
	for existing in data.plots:
		var bounds := _as_rect(existing.rect_m)
		if bounds.intersects(target):
			return _reject("plot_overlap")
		if _adjacent(bounds, target):
			adjoining = true
	if not data.plots.is_empty() and not adjoining:
		return _reject("plot_not_adjacent")
	if float(account.balance_nok) < float(offer.price_nok):
		return _reject("insufficient_funds")
	data.plots.append({"id": plot_id, "rect_m": offer.rect_m.duplicate(), "owner_company_id": actor})
	var result := _success({"plot_id": plot_id})
	result.account_changes = [{"company_id": actor, "previous_balance_nok": account.balance_nok,
		"balance_nok": float(account.balance_nok) - float(offer.price_nok), "delta_nok": -float(offer.price_nok)}]
	return result


func _validate(data: Dictionary) -> Array[String]:
	_validation_berths = []
	_validation_edges = []
	var errors: Array[String] = []
	if not _json_safe(data):
		errors.append("Document must contain only finite JSON values.")
		return errors
	if not _integer(data.get("schema_version", -1)) or int(data.get("schema_version", -1)) != FORMAT_VERSION:
		errors.append("Unsupported schema_version.")
	for key in ["id", "owner_company_id"]:
		if not data.get(key) is String or str(data[key]).is_empty():
			errors.append("Missing %s." % key)
	if not _integer(data.get("revision", -1)) or int(data.get("revision", -1)) < 0:
		errors.append("Invalid revision.")
	if not data.get("world") is Dictionary:
		errors.append("Missing world identity.")
	else:
		for key in ["seed", "generation_version", "checksum"]:
			if not data.world.has(key):
				errors.append("World identity missing %s." % key)
		if not _integer(data.world.get("seed")) or not data.world.get("checksum") is String or str(data.world.get("checksum", "")).is_empty():
			errors.append("Invalid world seed or checksum.")
		if not _integer(data.world.get("generation_version")) and not data.world.get("generation_version") is String:
			errors.append("Invalid world generation version.")
		if not _expected_world.is_empty() and data.world != _expected_world:
			errors.append("World identity mismatch.")
	if not _vector(data.get("origin_m"), 3) or not _positive(data.get("deck_height_above_sea_m")):
		errors.append("Invalid origin or deck datum.")
	for key in MUTABLE_FIELDS:
		if not data.get(key) is Array:
			errors.append("%s must be an array." % key)
		else:
			_validate_ids(data[key], key, errors)
	if not data.get("receipts") is Dictionary:
		errors.append("Receipts must be an object.")
	if not data.get("water_regions", []) is Array:
		errors.append("Water regions must be an array.")
	else:
		for region in data.get("water_regions", []):
			if not region is Dictionary or not _rect(region.get("rect_m")) or not _nonnegative(region.get("depth_m")):
				errors.append("Invalid surveyed water region.")
	if not data.get("berth_rules", {}) is Dictionary:
		errors.append("Berth rules must be an object.")
	else:
		for key in data.get("berth_rules", {}):
			if not _nonnegative(data.berth_rules[key]):
				errors.append("Invalid berth rule %s." % key)
	for asset_id in _catalog:
		if not _catalog[asset_id] is Dictionary:
			errors.append("Invalid catalogue asset %s." % asset_id)
	if not errors.is_empty():
		return errors
	# JSON scalars are float64, while Godot's geometry and scene coordinates are
	# real_t (float32 in the shipping build). Reject unrepresentable spatial data
	# before polygon clipping, spatial indexing, charting or scene publication.
	errors.append_array(_spatial_errors(data))
	if not errors.is_empty():
		return errors
	for key in data.receipts:
		var receipt: Variant = data.receipts[key]
		if not receipt is Dictionary or not receipt.get("fingerprint") is String or not _integer(receipt.get("applied_revision", -1)) or not receipt.get("result") is Dictionary:
			errors.append("Invalid command receipt %s." % key)
		elif int(receipt.applied_revision) <= 0 or int(receipt.applied_revision) > int(data.revision):
			errors.append("Invalid receipt revision %s." % key)
	for plot in data.plots:
		if not _rect(plot.get("rect_m")) or not plot.get("owner_company_id") is String or plot.owner_company_id != data.owner_company_id:
			errors.append("Invalid/foreign plot %s." % plot.id)
	for a in data.plots.size():
		if not _rect(data.plots[a].get("rect_m")):
			continue
		for b in range(a + 1, data.plots.size()):
			if _rect(data.plots[b].get("rect_m")) and _as_rect(data.plots[a].rect_m).intersects(_as_rect(data.plots[b].rect_m)):
				errors.append("Plots overlap.")
	for placement in data.placements:
		if not placement.get("asset_id") is String or str(placement.get("asset_id", "")).is_empty() or not _vector(placement.get("position_m"), 3) or not _number(placement.get("yaw_degrees")) or not placement.get("attributes", {}) is Dictionary:
			errors.append("Invalid placement %s." % placement.id)
			continue
		if not _catalog.has(placement.asset_id):
			errors.append("Unknown asset %s." % placement.asset_id)
			continue
		var definition: Dictionary = _canonical(_catalog[placement.asset_id])
		var attributes: Dictionary = placement.get("attributes", {})
		if attributes.has("support_depth_m") and (not _positive(attributes.support_depth_m) or float(attributes.support_depth_m) > MAX_SUPPORT_DEPTH_M):
			errors.append("Invalid support depth for %s." % placement.id)
		for key in CATALOG_GEOMETRY:
			if attributes.has(key) and (not definition.has(key) or not _equivalent(attributes[key], definition[key])):
				errors.append("Placement %s cannot override catalogue %s." % [placement.id, key])
		if not attributes.get("store_ids", []) is Array:
			errors.append("Invalid store links on %s." % placement.id)
		else:
			for store_id in attributes.get("store_ids", []):
				if not store_id is String or _find(data.stores, store_id).is_empty():
					errors.append("Unknown linked store on %s." % placement.id)
		var footprint: Variant = placement.get("attributes", {}).get("footprint_m", _catalog.get(placement.asset_id, {}).get("footprint_m", [0.1, 0.1]))
		if not _vector(footprint, 2) or float(footprint[0]) <= 0.0 or float(footprint[1]) <= 0.0:
			errors.append("Invalid footprint for %s." % placement.id)
		elif not _placement_projection_representable(placement, data.origin_m, _catalog):
			errors.append("Unrepresentable construction geometry for %s." % placement.id)
		elif not PLACEMENT_RULES.placement_within_plots(placement, _catalog, data.plots):
			errors.append("Placement outside owned plots: %s." % placement.id)
	var all_lots: Dictionary = {}
	for container in data.stores + data.vessels:
		if not _nonnegative(container.get("capacity_kg")) or not container.get("lots") is Array:
			errors.append("Invalid cargo container %s." % container.id)
			continue
		if not _validate_capacity_schema(container, errors):
			continue
		_validate_ids(container.lots, "lots in %s" % container.id, errors)
		if container.has("capacity_units") and (not _nonnegative(container.capacity_units) or not _integer(container.capacity_units)):
			errors.append("Invalid unit capacity in %s." % container.id)
		for lot in container.lots:
			if not lot is Dictionary:
				continue
			if not lot.get("commodity_id") is String or str(lot.get("commodity_id", "")).is_empty() or not _positive(lot.get("quantity")) or not _positive(lot.get("unit_mass_kg")) or not lot.get("attributes", {}) is Dictionary:
				errors.append("Invalid lot in %s." % container.id)
				continue
			if not _valid_quantity(lot.quantity, lot):
				errors.append("Fractional indivisible lot in %s." % container.id)
			if _handling_mode(lot)=="catch":
				var catch_error:=VESSEL_PROJECTION.catch_lot_error(lot)
				if not catch_error.is_empty():errors.append("Invalid catch in %s: %s."%[container.id,catch_error])
				var specimen: Variant=lot.get("attributes",{}).get("specimen",false)
				if specimen is bool and specimen and all_lots.has(lot.get("id","")):
					errors.append("Specimen cannot be present in two inventories: %s."%lot.get("id",""))
			if not lot.get("attributes", {}).get("whole_units", false) is bool or not lot.get("attributes", {}).get("indivisible", false) is bool:
				errors.append("Invalid whole-unit flag in %s." % container.id)
			if not lot.get("attributes", {}).get("container_type", "") is String:
				errors.append("Invalid container type in %s." % container.id)
			var box_type := str(lot.get("attributes", {}).get("container_type", ""))
			if box_type not in ["", "20ft", "40ft", "legacy_4m"]:
				errors.append("Unknown container type in %s." % container.id)
			if not _nonnegative(lot.get("attributes", {}).get("slots_per_unit", 1)):
				errors.append("Invalid lot slot usage in %s." % container.id)
			elif not box_type.is_empty() and lot.get("attributes", {}).has("slots_per_unit") and not is_equal_approx(float(lot.attributes.slots_per_unit), _lot_slots(lot)):
				errors.append("Container cannot override its physical slot usage in %s." % container.id)
			if not lot.get("attributes", {}).get("handling_mode", "") is String:
				errors.append("Invalid handling mode in %s." % container.id)
			if not _cargo_compatibility(container, lot).ok:
				errors.append("Incompatible cargo in %s." % container.id)
			var identity: Dictionary = lot.duplicate(true)
			identity.erase("quantity")
			if all_lots.has(lot.get("id", "")) and all_lots[lot.get("id", "")] != identity:
				errors.append("Conflicting lot identity: %s." % lot.get("id", ""))
			all_lots[lot.get("id", "")] = identity
		if _mass(container.lots) > float(container.capacity_kg) + 0.000001:
			errors.append("Cargo capacity exceeded in %s." % container.id)
		if _nonnegative(container.get("capacity_units")) and _units(container.lots) > float(container.capacity_units) + 0.000001:
			errors.append("Cargo unit capacity exceeded in %s." % container.id)
		for mode in container.get("handling_capacity_kg", {}):
			if _mode_mass(container.lots, mode) > float(container.handling_capacity_kg[mode]) + 0.000001:
				errors.append("Handling capacity exceeded in %s for %s." % [container.id, mode])
	for store in data.stores:
		var placement := _find(data.placements, str(store.get("placement_id", "")))
		if placement.is_empty():
			errors.append("Store %s has no placement." % store.id)
		else:
			var asset: Dictionary = _catalog.get(placement.get("asset_id", ""), {})
			if asset.has("attached_store"):
				_validate_attached_store(store, asset.attached_store, errors)
		if not store.get("accepted_commodities", []) is Array:
			errors.append("Invalid accepted commodities in %s." % store.id)
		else:
			for commodity in store.get("accepted_commodities", []):
				if not commodity is String or commodity.is_empty():
					errors.append("Invalid commodity id in %s." % store.id)
			if not store.get("accepted_commodities", []).is_empty():
				for lot in store.get("lots", []):
					if str(lot.get("commodity_id", "")) not in store.accepted_commodities:
						errors.append("Stored goods excluded by the commodity filter in %s." % store.id)
		for key in ["public_loading", "public_unloading"]:
			if not store.get(key, false) is bool:
				errors.append("Invalid access flag in %s." % store.id)
	for placement in data.placements:
		if not _catalog.get(placement.get("asset_id", ""), {}).has("attached_store"): continue
		var attached_count := 0
		for store in data.stores:
			if str(store.get("placement_id", "")) == str(placement.id): attached_count += 1
		if attached_count != 1:
			errors.append("Placement %s must have exactly one attached storage record." % placement.id)
	for vessel in data.vessels:
		for key in ["length_m", "beam_m", "draft_m"]:
			if not _positive(vessel.get(key)):
				errors.append("Invalid vessel %s %s." % [vessel.id, key])
		if not vessel.get("owner_company_id") is String or str(vessel.get("owner_company_id", "")).is_empty() or not vessel.get("berth_id", "") is String:
			errors.append("Invalid vessel owner or berth id.")
	if not errors.is_empty():
		return errors
	for vessel in data.vessels:
		var plan := _hold_plan(vessel, vessel.lots)
		if not plan.ok:
			errors.append("Vessel %s hold projection rejected: %s." % [vessel.id, plan.code])
	if not errors.is_empty():
		return errors
	for reservation in data.reservations:
		var store := _find(data.stores, str(reservation.get("store_id", "")))
		var vessel := _find(data.vessels, str(reservation.get("vessel_id", "")))
		if store.is_empty() or vessel.is_empty() or not _positive(reservation.get("quantity")) or not _positive(reservation.get("unit_mass_kg")):
			errors.append("Invalid reservation %s." % reservation.id)
			continue
		var lot := _find(store.get("lots", []), str(reservation.get("lot_id", "")))
		if lot.is_empty() or float(lot.get("unit_mass_kg", 0)) != float(reservation.unit_mass_kg) or str(reservation.get("actor_company_id", "")) != str(vessel.owner_company_id):
			errors.append("Invalid reservation source or owner %s." % reservation.id)
		elif not _valid_quantity(reservation.quantity, lot) or str(vessel.get("berth_id", "")).is_empty() or not _equivalent(_canonical(reservation.get("slots_per_unit", 1)), _canonical(_lot_slots(lot))):
			errors.append("Invalid reservation quantity or undocked vessel: %s." % reservation.id)
		elif not _cargo_compatibility(vessel, lot).ok:
			errors.append("Incompatible reserved cargo: %s." % reservation.id)
	if not errors.is_empty():
		return errors
	var reuse_construction:=_same_construction(data)
	if not reuse_construction:errors.append_array(PLACEMENT_RULES.validate(data, _catalog))
	for store in data.stores:
		for lot in store.lots:
			var reserved := 0.0
			for reservation in data.reservations:
				if reservation.store_id == store.id and reservation.lot_id == lot.id:
					reserved += float(reservation.quantity)
			if (reserved-float(lot.quantity))*float(lot.unit_mass_kg)>0.000001:
				errors.append("Stock over-reserved: %s." % lot.id)
	for vessel in data.vessels:
		var reserved_mass := 0.0
		var reserved_units := 0.0
		var reserved_by_mode: Dictionary = {}
		for reservation in data.reservations:
			if reservation.vessel_id == vessel.id:
				reserved_mass += float(reservation.quantity) * float(reservation.unit_mass_kg)
				reserved_units += float(reservation.quantity) * float(reservation.get("slots_per_unit", 1))
				var store := _find(data.stores, str(reservation.store_id))
				var mode := _handling_mode(_find(store.get("lots", []), str(reservation.lot_id)))
				reserved_by_mode[mode] = float(reserved_by_mode.get(mode, 0)) + float(reservation.quantity) * float(reservation.unit_mass_kg)
		if _mass(vessel.lots) + reserved_mass > float(vessel.capacity_kg) + 0.000001:
			errors.append("Vessel over-reserved: %s." % vessel.id)
		if vessel.has("capacity_units") and _units(vessel.lots) + reserved_units > float(vessel.capacity_units) + 0.000001:
			errors.append("Vessel slots over-reserved: %s." % vessel.id)
		for mode in vessel.get("handling_capacity_kg", {}):
			if _mode_mass(vessel.lots, mode) + float(reserved_by_mode.get(mode, 0)) > float(vessel.handling_capacity_kg[mode]) + 0.000001:
				errors.append("Vessel handling capacity over-reserved: %s." % vessel.id)
		var bulk_plan := _reserved_hold_plan(data, vessel)
		if not bulk_plan.ok:
			errors.append("Vessel %s holds over-reserved: %s." % [vessel.id, bulk_plan.code])
	var berths: Array[Dictionary]
	if reuse_construction:
		berths=_berths_cache.duplicate(true)
		_validation_edges=_construction_edges.duplicate(true)
	else:
		var geometry: Dictionary = {}
		berths=BERTHS.derive(data, _catalog, geometry)
		_validation_edges=geometry.get("construction_edges", [])
	_validation_berths = berths
	var occupancy: Array = []
	for vessel in data.vessels:
		if str(vessel.get("berth_id", "")).is_empty():
			continue
		var berth := _find(berths, vessel.berth_id)
		if berth.is_empty():
			errors.append("Vessel %s references missing berth." % vessel.id)
		elif not BERTHS.fit(berth, vessel, occupancy).get("ok", false):
			errors.append("Vessel %s cannot occupy berth." % vessel.id)
		occupancy.append({"vessel_id": vessel.id, "berth_id": vessel.berth_id})
	for reservation in data.reservations:
		var vessel := _find(data.vessels, reservation.vessel_id)
		var berth := _find(berths, str(vessel.get("berth_id", "")))
		var store := _find(data.stores, reservation.store_id)
		var lot := _find(store.get("lots", []), reservation.lot_id)
		if reservation.store_id not in BERTHS.services_for_vessel(berth, vessel, _handling_mode(lot)).get("store_ids", []):
			errors.append("Reservation %s no longer has reachable handling equipment." % reservation.id)
	return errors


static func _validate_attached_store(store: Dictionary, definition: Dictionary, errors: Array[String]) -> void:
	if not _nonnegative(store.get("capacity_kg")) or float(store.capacity_kg) > float(definition.get("capacity_kg", 0)):
		errors.append("Store %s exceeds its installed storage capacity." % store.id)
	if definition.has("capacity_units") and (not _nonnegative(store.get("capacity_units")) or float(store.capacity_units) > float(definition.capacity_units)):
		errors.append("Store %s exceeds its installed cargo positions." % store.id)
	for key in ["accepted_handling_modes", "accepted_container_types", "accepted_commodities"]:
		var supported: Array = definition.get(key, [])
		if supported.is_empty(): continue
		var accepted: Variant = store.get(key)
		if not accepted is Array or accepted.is_empty():
			errors.append("Store %s must preserve installed %s." % [store.id, key])
			continue
		for item in accepted:
			if item not in supported:
				errors.append("Store %s cannot expand installed %s." % [store.id, key])


static func _validate_ids(records: Array, label: String, errors: Array[String]) -> void:
	var ids: Dictionary = {}
	for record in records:
		if not record is Dictionary or not record.get("id") is String or str(record.get("id", "")).is_empty():
			errors.append("Invalid record id in %s." % label)
			continue
		if ids.has(record.id):
			errors.append("Duplicate id in %s: %s." % [label, record.id])
		ids[record.id] = true


static func _adjacent(a: Rect2, b: Rect2) -> bool:
	var overlap_x := minf(a.end.x, b.end.x) - maxf(a.position.x, b.position.x)
	var overlap_y := minf(a.end.y, b.end.y) - maxf(a.position.y, b.position.y)
	return ((is_equal_approx(a.end.x, b.position.x) or is_equal_approx(b.end.x, a.position.x)) and overlap_y > 0.0001) or ((is_equal_approx(a.end.y, b.position.y) or is_equal_approx(b.end.y, a.position.y)) and overlap_x > 0.0001)


static func _find(records: Array, id: String) -> Dictionary:
	for record in records:
		if record is Dictionary and str(record.get("id", "")) == id:
			return record
	return {}


static func _mass(lots: Array) -> float:
	var total := 0.0
	for lot in lots:
		if lot is Dictionary and _number(lot.get("quantity")) and _number(lot.get("unit_mass_kg")):
			total += float(lot.quantity) * float(lot.unit_mass_kg)
	return total


static func _compatible_lot(lots: Array, lot: Dictionary) -> bool:
	var existing := _find(lots, str(lot.id)).duplicate(true)
	if existing.is_empty():
		return true
	var identity := lot.duplicate(true)
	existing.erase("quantity")
	identity.erase("quantity")
	return existing == identity


static func _units(lots: Array) -> float:
	var total := 0.0
	for lot in lots:
		if lot is Dictionary and _number(lot.get("quantity")) and lot.get("attributes", {}) is Dictionary:
			total += float(lot.quantity) * _lot_slots(lot)
	return total


static func _handling_mode(lot: Dictionary) -> String:
	var attributes: Dictionary = lot.get("attributes", {}) if lot.get("attributes", {}) is Dictionary else {}
	var type := str(attributes.get("container_type", ""))
	if not type.is_empty():
		return "general" if type == "legacy_4m" else "container"
	for entry in COMMODITIES.COMMODITIES:
		if str(entry.id) == str(lot.get("commodity_id", "")):
			return str(entry.handling_mode)
	return str(attributes.get("handling_mode", "general"))


static func _lot_slots(lot: Dictionary) -> float:
	var attributes: Dictionary = lot.get("attributes", {}) if lot.get("attributes", {}) is Dictionary else {}
	# ISO length is physical capacity, never an arbitrary cargo attribute.
	var box_type := str(attributes.get("container_type", ""))
	if box_type == "40ft": return 2.0
	if box_type in ["20ft", "legacy_4m"]: return 1.0
	var count: Variant = attributes.get("slots_per_unit", 1 if _handling_mode(lot) in ["container", "general"] else 0)
	return float(count) if _number(count) else 0


static func _mode_mass(lots: Array, mode: String) -> float:
	var total := 0.0
	for lot in lots:
		if lot is Dictionary and _number(lot.get("quantity")) and _number(lot.get("unit_mass_kg")) and _handling_mode(lot) == mode:
			total += float(lot.quantity) * float(lot.unit_mass_kg)
	return total


static func _cargo_compatibility(container: Dictionary, lot: Dictionary) -> Dictionary:
	var mode := _handling_mode(lot)
	if container.has("accepted_handling_modes") and mode not in container.accepted_handling_modes:
		return _reject("handling_not_supported", {"handling_mode": mode})
	if container.has("handling_capacity_kg") and not container.handling_capacity_kg.has(mode):
		return _reject("handling_not_supported", {"handling_mode": mode})
	if container.has("accepted_container_types") and mode in ["container", "general"]:
		var type := str(lot.get("attributes", {}).get("container_type", ""))
		if type not in container.accepted_container_types:
			return _reject("container_does_not_fit", {"container_type": type})
	return _success()


static func _typed_capacity_fits(container: Dictionary, lot: Dictionary, quantity: float, reserved_mass := 0.0) -> bool:
	if not container.has("handling_capacity_kg"):
		return true
	var mode := _handling_mode(lot)
	return _mode_mass(container.lots, mode) + reserved_mass + quantity * float(lot.unit_mass_kg) <= float(container.handling_capacity_kg.get(mode, 0)) + 0.000001


static func _bulk_plan(vessel: Dictionary, lots: Array) -> Dictionary:
	if not vessel.has("cargo_holds"): return {"ok":true,"code":"abstract_capacity"}
	var bulk_lots: Array = []
	for lot in lots:
		if _handling_mode(lot) == "bulk": bulk_lots.append(lot)
	return VESSEL_PROJECTION.bulk_hold_plan(vessel, bulk_lots)


static func _hold_plan(vessel: Dictionary, lots: Array) -> Dictionary:
	var bulk:=_bulk_plan(vessel,lots)
	if not bulk.ok:return bulk
	var catches: Array=[]
	for lot in lots:
		if _handling_mode(lot)=="catch":catches.append(lot)
	return VESSEL_PROJECTION.catch_hold_plan(vessel,catches)


static func _reserved_hold_plan(data: Dictionary, vessel: Dictionary, extra: Dictionary = {}, quantity := 0.0, excluded_reservation := "") -> Dictionary:
	if not vessel.has("cargo_holds"): return {"ok":true,"code":"abstract_capacity"}
	var projected: Array = vessel.lots.duplicate(true)
	for reservation in data.reservations:
		if str(reservation.vessel_id) != str(vessel.id) or str(reservation.id) == excluded_reservation: continue
		var store := _find(data.stores, str(reservation.store_id))
		var source := _find(store.get("lots", []), str(reservation.lot_id))
		_append_projected_lot(projected, source, float(reservation.quantity))
	if not extra.is_empty(): _append_projected_lot(projected, extra, quantity)
	return _hold_plan(vessel, projected)


static func _append_projected_lot(lots: Array, source: Dictionary, quantity: float) -> void:
	var existing := _find(lots, str(source.id))
	if existing.is_empty():
		existing = source.duplicate(true)
		existing.quantity = 0.0
		lots.append(existing)
	existing.quantity = float(existing.quantity) + quantity


static func _validate_capacity_schema(container: Dictionary, errors: Array[String]) -> bool:
	var before := errors.size()
	for key in ["accepted_handling_modes", "accepted_container_types"]:
		if not container.has(key):
			continue
		if not container[key] is Array:
			errors.append("Invalid %s in %s." % [key, container.id])
			continue
		for value in container[key]:
			var allowed: Array = HANDLING_MODES if key == "accepted_handling_modes" else ["20ft", "40ft", "legacy_4m"]
			if not value is String or value not in allowed:
				errors.append("Invalid %s value in %s." % [key, container.id])
	if container.has("handling_capacity_kg"):
		if not container.handling_capacity_kg is Dictionary:
			errors.append("Invalid handling capacities in %s." % container.id)
		else:
			for mode in container.handling_capacity_kg:
				if mode not in HANDLING_MODES or not _nonnegative(container.handling_capacity_kg[mode]):
					errors.append("Invalid handling capacity in %s." % container.id)
	return errors.size() == before


static func _move_lot(source: Array, destination: Array, lot: Dictionary, quantity: float) -> void:
	var existing := _find(destination, str(lot.id))
	if existing.is_empty():
		existing = lot.duplicate(true)
		existing.quantity = 0.0
		destination.append(existing)
	existing.quantity = float(existing.quantity) + quantity
	lot.quantity = float(lot.quantity) - quantity
	# Quantities may represent heavy individual units, not only kilograms. A
	# small positive count can still be substantial cargo and must remain.
	if float(lot.quantity) <= 0:
		source.erase(lot)


static func _valid_quantity(value: Variant, lot: Dictionary) -> bool:
	var attributes: Dictionary = lot.get("attributes", {})
	var whole: bool = attributes.get("whole_units", false) or attributes.get("indivisible", false) or not str(attributes.get("container_type", "")).is_empty()
	if not _positive(value) or (whole and not _integer(value)):return false
	if _handling_mode(lot)=="catch":
		# A fish is one specimen regardless of whether its quantity is encoded as
		# one unit or kilograms. It must never be split into two copies of its ID.
		var specimen: Variant=attributes.get("specimen",false)
		if not specimen is bool:return false
		if specimen and float(value)!=float(lot.quantity):return false
		var mass:=float(value)*float(lot.unit_mass_kg)
		var remainder:=(float(lot.quantity)-float(value))*float(lot.unit_mass_kg)
		if mass<=CatchLot.MASS_EPS_KG or (remainder>0.000001 and remainder<=CatchLot.MASS_EPS_KG):return false
	return true


static func _json_safe(value: Variant) -> bool:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING:
			return true
		TYPE_FLOAT:
			return is_finite(value)
		TYPE_ARRAY:
			for item in value:
				if not _json_safe(item):
					return false
			return true
		TYPE_DICTIONARY:
			for key in value:
				if (not key is String and not key is StringName) or not _json_safe(value[key]):
					return false
			return true
	return false


static func _canonical(value: Variant) -> Variant:
	# JSON parses integral numbers as floats. A retry through JSON must hash the
	# same as the original in-memory command; dictionary key order is irrelevant.
	if value is int or value is float:
		# Godot's full-precision decimal parser can move an arbitrary computed
		# double by one ULP. Canonicalize at the authority boundary, rather than
		# waiting until a saved receipt or surveyed depth is read back from disk.
		# This uses the wire representation; it does not round metres/stock/custom
		# values to an unrelated fixed number of decimal places.
		if not is_finite(float(value)): return float(value)
		return JSON.parse_string(JSON.stringify(float(value), "", true, true))
	if value is Array:
		var array: Array = []
		for item in value:
			array.append(_canonical(item))
		return array
	if value is Dictionary:
		var dictionary: Dictionary = {}
		for key in value:
			dictionary[str(key)] = _canonical(value[key])
		return dictionary
	return value


static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


## Spatial validation deliberately does not change generic JSON/financial
## number validation or impose a gameplay map-size limit.
static func _spatial_errors(data: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var origin := _spatial_vector(data.origin_m)
	var deck := Vector3(0, float(data.deck_height_above_sea_m), 0)
	if not origin.is_finite() or not deck.is_finite() or not (origin + deck).is_finite():
		errors.append("Unrepresentable origin or deck datum.")
		return errors
	var offset := Vector2(origin.x, origin.z)
	for collection in ["plots", "water_regions"]:
		for row in data.get(collection, []):
			# Structural errors retain their existing descriptive validation.
			if not row is Dictionary or not _rect(row.get("rect_m")): continue
			var rect := _as_rect(row.rect_m)
			if not _spatial_rect_representable(rect) or not _spatial_rect_representable(Rect2(rect.position + offset, rect.size)) \
					or not (rect.end + offset).is_finite():
				errors.append("Unrepresentable %s rectangle %s." % [collection, row.get("id", "")])
	for placement in data.placements:
		if not placement is Dictionary or not _vector(placement.get("position_m"), 3) or not _number(placement.get("yaw_degrees")): continue
		var position := _spatial_vector(placement.position_m)
		var rotation := Vector3(0, deg_to_rad(float(placement.yaw_degrees)), 0)
		if not position.is_finite() or not (origin + deck + position).is_finite() or not rotation.is_finite():
			errors.append("Unrepresentable placement position or rotation %s." % placement.get("id", ""))
	return errors


static func _spatial_vector(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))


static func _spatial_rect_representable(rect: Rect2) -> bool:
	return rect.position.is_finite() and rect.size.is_finite() and rect.end.is_finite() \
		and rect.size.x > 0 and rect.size.y > 0 and rect.end.x > rect.position.x and rect.end.y > rect.position.y


static func _placement_projection_representable(placement: Dictionary, origin: Array, catalog: Dictionary) -> bool:
	var offset := Vector2(float(origin[0]), float(origin[2]))
	var metadata := PLACEMENT_RULES.definition(placement, catalog)
	for polygon: PackedVector2Array in PLACEMENT_RULES.polygons(placement, metadata):
		var projected := PackedVector2Array()
		for point: Vector2 in polygon:
			if not point.is_finite() or not (point + offset).is_finite(): return false
			projected.append(point + offset)
		if not _spatial_rect_representable(PLACEMENT_RULES.polygon_bounds(polygon)) \
				or not _spatial_rect_representable(PLACEMENT_RULES.polygon_bounds(projected)): return false
		# An edge lost to real_t rounding cannot represent its authored asset.
		for index in polygon.size():
			var next := (index + 1) % polygon.size()
			if polygon[index] == polygon[next] or projected[index] == projected[next]: return false
	return true


static func _equivalent(a: Variant, b: Variant) -> bool:
	return typeof(a) == typeof(b) and a == b


static func _integer(value: Variant) -> bool:
	return _number(value) and float(value) == floorf(float(value))


static func _nonnegative(value: Variant) -> bool:
	return _number(value) and float(value) >= 0.0


static func _positive(value: Variant) -> bool:
	return _number(value) and float(value) > 0.0


static func _vector(value: Variant, length: int) -> bool:
	if not value is Array or value.size() != length:
		return false
	for component in value:
		if not _number(component):
			return false
	return true


static func _rect(value: Variant) -> bool:
	return _vector(value, 4) and float(value[2]) > 0.0 and float(value[3]) > 0.0


static func _as_rect(value: Array) -> Rect2:
	return Rect2(float(value[0]), float(value[1]), float(value[2]), float(value[3]))


static func _success(result: Dictionary = {}) -> Dictionary:
	return {"ok": true, "result": result}


static func _reject(code: String, details: Dictionary = {}) -> Dictionary:
	return {"ok": false, "code": code, "details": details}


func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	return {"ok": false, "code": code, "details": details, "revision": _record.get("revision", 0), "events": [], "account_changes": [], "snapshot": to_dict()}
