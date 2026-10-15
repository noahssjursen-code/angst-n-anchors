class_name CustomPortEditor
extends RefCounted
## Input-independent construction controller. Preview never mutates authority.
## Undo sends inverse construction commands at the CURRENT revision; it never
## restores a previous snapshot over somebody's docking or cargo operation.

signal changed(result: Dictionary)
const RULES = preload("res://scripts/port/state/custom_port_placement_rules.gd")
const STATE = preload("res://scripts/port/state/custom_port_state.gd")
const BERTHS = preload("res://scripts/port/state/custom_port_berths.gd")
const FOUNDATION_TERRAIN = preload("res://scripts/port/building/custom_port_foundation_terrain.gd")
const MAX_UNDO_GROUPS := 100

var state: CustomPortState
var catalog: Dictionary = {}
var actor_company_id := ""
var previews_evaluated := 0
var geometry_refreshes := 0
var _snapshot: Dictionary = {}
var _revision := -1
var _geometry: Array[Dictionary] = []
var _edges: Array[Dictionary] = []
var _preview_cache: Dictionary = {}
var _next_placement := 1
var _next_command := 1
var _history: Array = []
var _stroke: Array = []
var _editing := false
var _ground_height := Callable()
var _ground_step_m := 25.0


func configure(authority: CustomPortState, definitions: Dictionary, actor: String) -> void:
	state = authority
	catalog = definitions.duplicate(true)
	actor_company_id = actor
	_revision = -1
	_history.clear()
	_stroke.clear()
	_editing = false
	_ground_height = Callable()
	_refresh()


func configure_terrain(height_at: Callable, triangle_step_m: float) -> void:
	_ground_height = height_at
	_ground_step_m = triangle_step_m
	_preview_cache.clear()


func _foundation_buried(placement: Dictionary) -> bool:
	if state == null or _snapshot.is_empty(): return false
	var spec: Dictionary = catalog.get(str(placement.get("asset_id", "")), {})
	return FOUNDATION_TERRAIN.fully_buried(placement, spec,
		CustomPortCatalog.vector3(_snapshot.origin_m), _ground_height, _ground_step_m)


func preview(asset_id: String, local_cursor: Vector3, yaw_degrees := 0.0) -> Dictionary:
	_refresh()
	if state == null or not catalog.has(asset_id) or not local_cursor.is_finite() or not is_finite(yaw_degrees):
		return {"ok": false, "errors": ["Choose a valid construction asset."], "placement": {}}
	var spec: Dictionary = catalog[asset_id]
	var rotation_step := float(spec.get("rotation_step_degrees", 90.0 if str(spec.get("kind", "")) == "platform" or spec.get("snap_to_footprint",false) else 45.0))
	var yaw := fposmod(roundf(yaw_degrees / rotation_step) * rotation_step, 360.0)
	var snapped := _snap(spec, local_cursor, yaw)
	var position: Vector3 = snapped.position
	yaw = snapped.yaw
	var key := "%s|%.3f|%.3f|%.3f|%s" % [asset_id, position.x, position.z, yaw, snapped.get("edge_found", true)]
	if _preview_cache.has(key):
		return _preview_cache[key].duplicate(true)
	previews_evaluated += 1
	var placement := {"id": _placement_id(), "asset_id": asset_id,
		"position_m": [position.x, 0, position.z], "yaw_degrees": yaw, "attributes": {}}
	var errors: Array[String] = []
	if not state.validation_errors.is_empty():
		errors.append_array(state.validation_errors)
	elif actor_company_id != str(_snapshot.owner_company_id):
		errors.append("Only the port's company can build here.")
	elif not snapped.get("edge_found", true):
		errors.append("Choose an exposed quay edge.")
	elif _foundation_buried(placement):
		errors.append(FOUNDATION_TERRAIN.BURIED_MESSAGE)
	else:
		var footprint := _footprint_bounds(placement, spec)
		if not RULES.placement_within_plots(placement, catalog, _snapshot.get("plots", [])):
			errors.append("Buy the adjoining plot before building here.")
		var subset: Array = []
		var query := footprint.grow(1.0)
		for row in _geometry:
			if row.bounds.intersects(query):
				subset.append(row.placement)
		subset.append(placement)
		for problem in RULES.validate({"placements": subset}, catalog):
			if problem.begins_with(str(placement.id) + " ") or problem.begins_with(str(placement.id) + ":"):
				errors.append(problem)
		# Only the deck boundary and mooring anchors change occupied berth
		# topology. Decorations, buildings and extra cranes already use the local
		# support/overlap checks; they must not revalidate 674 pieces every hover.
		# Final placement still always runs complete authority validation.
		var changes_berths: bool = str(spec.get("kind", "")) in ["platform", "bollard"] or spec.get("berth_edge", false) or spec.get("mooring", false)
		if errors.is_empty() and changes_berths and _has_docked_vessel():
			var checked := state.preview_asset(placement, actor_company_id)
			if not checked.ok:
				errors.append_array(checked.errors)
	var result := {"ok": errors.is_empty(), "placement": placement,
		"errors": errors, "message": "" if errors.is_empty() else errors[0],
		"snap_m": snapped.get("step", 1.0), "revision": _revision}
	if _preview_cache.size() >= 256:
		_preview_cache.clear()
	_preview_cache[key] = result.duplicate(true)
	return result


func preview_world(asset_id: String, world_cursor: Vector3, yaw_degrees := 0.0) -> Dictionary:
	_refresh()
	var origin: Array = _snapshot.get("origin_m", [0, 0, 0])
	return preview(asset_id, world_cursor - Vector3(float(origin[0]), float(origin[1]), float(origin[2])), yaw_degrees)


func preview_transform(placement_id: String, local_cursor: Vector3, yaw_degrees := 0.0) -> Dictionary:
	_refresh()
	var original := _find(_snapshot.get("placements", []), placement_id)
	if state == null or original.is_empty() or not local_cursor.is_finite() or not is_finite(yaw_degrees):
		return {"ok": false, "errors": ["Select an existing piece and a valid position."], "placement": {}}
	var spec := RULES.definition(original, catalog)
	var step := float(spec.get("rotation_step_degrees", 90.0 if str(spec.get("kind", "")) == "platform" or spec.get("snap_to_footprint", false) else 45.0))
	var yaw := fposmod(roundf(yaw_degrees/step)*step, 360.0)
	var snapped := _snap(spec, local_cursor, yaw, placement_id)
	var position: Vector3 = snapped.position
	yaw = snapped.yaw
	# A rotation requested at the existing pivot must preserve authored centres,
	# including older valid placements that predate today's snapping lattice.
	# The host supplies the displayed ghost centre when R is pressed; normal
	# pointer movement continues to use this asset's translation snap.
	var original_at: Array = original.position_m
	if str(spec.get("placement_kind", "")) != "edge" and str(spec.get("kind", "")) != "bollard" \
		and Vector2(local_cursor.x - float(original_at[0]), local_cursor.z - float(original_at[2])).length() <= 0.001:
		position = Vector3(float(original_at[0]), 0, float(original_at[2]))
	var key := "transform|%s|%.3f|%.3f|%.3f|%s" % [placement_id, position.x, position.z, yaw, snapped.get("edge_found", true)]
	if _preview_cache.has(key): return _preview_cache[key].duplicate(true)
	previews_evaluated += 1
	var replacement := original.duplicate(true)
	replacement.position_m = [position.x, 0, position.z]
	replacement.yaw_degrees = yaw
	var checked: Dictionary
	if not snapped.get("edge_found", true): checked = {"ok":false, "errors":["Choose an exposed quay edge."]}
	elif _foundation_buried(replacement): checked = {"ok":false, "errors":[FOUNDATION_TERRAIN.BURIED_MESSAGE]}
	elif _can_preview_transform_locally(original, spec): checked = _preview_local_transform(original, replacement, spec)
	else:
		var payload := {"placement_id":placement_id, "expected_placement":original,
			"position_m":replacement.position_m, "yaw_degrees":yaw}
		var preflight := state.preflight_nonstructural_transform(payload, actor_company_id)
		if preflight.supported:
			# Stocked equipment changes pose only. Its real command checks identity,
			# ownership and all reservation links; the same local RULES below check
			# support, exact overlap and plots. Final transform still validates all.
			checked = _preview_local_transform(original, replacement, spec) if preflight.command_allowed else {"ok":false, "errors":preflight.errors}
		else:
			# Structural changes also affect support left behind, exposed edges and
			# occupied moorings, so they retain complete candidate validation.
			checked = state.preview_transform(payload, actor_company_id)
	var errors: Array = checked.get("errors", []).duplicate()
	var messages := {"placement_unchanged":"Move or rotate the selected piece.", "placement_changed":"This piece changed. Select it again.",
		"store_reserved":"Finish or cancel reserved cargo before moving this store.", "placement_reserved":"Finish or cancel reserved cargo before moving this equipment.",
		"berth_in_use":"Move the secured vessel away before changing its berth.", "not_port_owner":"Only the port's company can build here."}
	if not errors.is_empty() and messages.has(str(errors[0])): errors[0] = messages[str(errors[0])]
	var result := {"ok":checked.ok, "placement":replacement, "expected_placement":original.duplicate(true), "placement_id":placement_id,
		"errors":errors, "message":"" if errors.is_empty() else str(errors[0]), "snap_m":snapped.get("step",1.0), "revision":_revision}
	if _preview_cache.size() >= 256: _preview_cache.clear()
	_preview_cache[key] = result.duplicate(true)
	return result


func _can_preview_transform_locally(original: Dictionary, spec: Dictionary) -> bool:
	# Only platforms provide support. Berth geometry/services consume platforms,
	# bollards, cranes and store placements; moving ordinary walls or decoration
	# cannot change another piece's support, a secured hull or reserved stock.
	# Keep this narrow even when an abstract catalog assigns a store to a prop.
	if str(spec.get("kind", "decoration")) not in ["decoration", "npc"] or spec.get("mooring", false) or spec.get("berth_edge", false) or spec.has("attached_store"):
		return false
	for store in _snapshot.get("stores", []):
		if str(store.get("placement_id", "")) == str(original.id): return false
	return true


func _preview_local_transform(original: Dictionary, replacement: Dictionary, spec: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	if not state.validation_errors.is_empty(): errors.append_array(state.validation_errors)
	elif actor_company_id != str(_snapshot.owner_company_id): errors.append("not_port_owner")
	elif STATE._canonical([original.position_m, original.yaw_degrees]) == STATE._canonical([replacement.position_m, replacement.yaw_degrees]): errors.append("placement_unchanged")
	else:
		if not RULES.placement_within_plots(replacement, catalog, _snapshot.get("plots", [])):
			errors.append("Buy the adjoining plot before building here.")
		var source := _footprint_bounds(original, spec).grow(1.0)
		var destination := _footprint_bounds(replacement, spec).grow(1.0)
		var subset: Array = []
		for row in _geometry:
			if str(row.placement.id) != str(original.id) and (row.bounds.intersects(source) or row.bounds.intersects(destination)):
				subset.append(row.placement)
		# Append last so overlap diagnostics identify the changed piece. Unchanged
		# neighbours already belong to the validated current revision; a partial
		# neighbourhood may omit THEIR distant support, but includes every platform
		# that can support the replacement and every piece it can intersect.
		subset.append(replacement)
		for problem in RULES.validate({"placements": subset}, catalog):
			if problem.begins_with(str(replacement.id) + " ") or problem.begins_with(str(replacement.id) + ":"):
				errors.append(problem)
	return {"ok": errors.is_empty(), "errors": errors}


func transform(proposal: Dictionary) -> Dictionary:
	_refresh()
	if not proposal.get("ok", false) or not proposal.get("placement") is Dictionary or not proposal.get("expected_placement") is Dictionary:
		return _failure("invalid_preview", proposal.get("errors", ["Choose a valid transform."]))
	var original: Dictionary = proposal.expected_placement.duplicate(true)
	var replacement: Dictionary = proposal.placement.duplicate(true)
	if _foundation_buried(replacement):
		return _failure("foundation_buried", [FOUNDATION_TERRAIN.BURIED_MESSAGE])
	var unchanged := replacement.duplicate(true)
	for key in ["position_m", "yaw_degrees"]: unchanged[key] = original.get(key)
	if not original.get("attributes", {}) is Dictionary or not replacement.get("attributes", {}) is Dictionary:
		return _failure("invalid_transform", ["Moving a piece cannot change its attributes."])
	var original_attributes: Dictionary = original.get("attributes", {})
	var proposed_attributes: Dictionary = replacement.get("attributes", {})
	var depth_changed: bool = original_attributes.get("support_depth_m") != proposed_attributes.get("support_depth_m")
	if depth_changed:
		if not unchanged.has("attributes"): unchanged.attributes = {}
		if original_attributes.has("support_depth_m"): unchanged.attributes.support_depth_m = original_attributes.support_depth_m
		else: unchanged.attributes.erase("support_depth_m")
		if not original.has("attributes") and unchanged.attributes.is_empty(): unchanged.erase("attributes")
	if unchanged != original: return _failure("invalid_transform", ["Moving a piece cannot change its identity or attributes."])
	var payload := {"placement_id":str(original.get("id", "")), "expected_placement":original,
		"position_m":replacement.get("position_m"), "yaw_degrees":replacement.get("yaw_degrees")}
	if depth_changed: payload.support_depth_m = proposed_attributes.get("support_depth_m")
	var result := _apply("transform_asset", payload)
	if result.ok:
		var stored := _find(result.snapshot.placements, str(original.id))
		var inverse := {"placement_id":original.id, "expected_placement":stored.duplicate(true),
			"position_m":original.position_m.duplicate(), "yaw_degrees":original.yaw_degrees}
		if depth_changed: inverse.support_depth_m = original_attributes.get("support_depth_m")
		_remember({"kind":"transform_asset", "payload":inverse})
		changed.emit(result)
	return result


func place(proposal: Dictionary) -> Dictionary:
	_refresh()
	if not proposal.get("ok", false) or not proposal.get("placement") is Dictionary:
		return _failure("invalid_preview", proposal.get("errors", ["Choose a valid placement."]))
	var placement: Dictionary = proposal.placement.duplicate(true)
	if _foundation_buried(placement):
		return _failure("foundation_buried", [FOUNDATION_TERRAIN.BURIED_MESSAGE])
	var result := _apply("place_asset", {"placement": placement})
	if result.ok:
		_next_placement += 1
		var stored := _find(result.snapshot.placements, str(placement.id))
		_remember({"kind": "remove_asset", "payload": {"placement_id": placement.id, "expected_placement": stored.duplicate(true)}})
		changed.emit(result)
	return result


func place_asset(asset_id: String, local_cursor: Vector3, yaw_degrees := 0.0) -> Dictionary:
	return place(preview(asset_id, local_cursor, yaw_degrees))


func remove(placement_id: String) -> Dictionary:
	_refresh()
	var placement := _find(_snapshot.get("placements", []), placement_id)
	if placement.is_empty():
		return _failure("placement_not_found", ["Nothing is built here."])
	var saved := placement.duplicate(true)
	var stores: Array = []
	for store in _snapshot.get("stores", []):
		if str(store.get("placement_id", "")) == placement_id:
			stores.append(store.duplicate(true))
	var result := _apply("remove_asset", {"placement_id": placement_id, "expected_placement": saved})
	if result.ok:
		var inverse_payload := {"placement": saved}
		if not stores.is_empty():
			inverse_payload.restore_empty_stores = stores
		_remember({"kind": "place_asset", "payload": inverse_payload})
		changed.emit(result)
	return result


func paint_cladding(placement_id: String, colour: Color) -> Dictionary:
	_refresh()
	var original := _find(_snapshot.get("placements", []), placement_id)
	if original.is_empty(): return _failure("placement_not_found", ["Aim at a wall, window or door."])
	var spec: Dictionary = catalog.get(str(original.asset_id), {})
	if not "Office cladding" in spec.get("paint_regions", []):
		return _failure("not_paintable", ["This piece has no painted cladding."])
	for channel in [colour.r, colour.g, colour.b]:
		if not is_finite(channel) or channel < 0.0 or channel > 1.0:
			return _failure("invalid_colour", ["Choose a valid cladding colour."])
	if colour.a != 1.0: return _failure("invalid_colour", ["Cladding must remain opaque."])
	var tint := "#" + colour.to_html(false)
	if str(original.get("attributes", {}).get("wall_colour", "")) == tint:
		return _failure("colour_unchanged", ["This piece already has that colour."])
	var replacement := original.duplicate(true)
	if not replacement.has("attributes"): replacement.attributes = {}
	replacement.attributes.wall_colour = tint
	# Reuse the same atomic, optimistic edit used by the working door. This
	# changes one material attribute; stock, geometry and identity stay intact.
	var result := _apply("edit_assets", {"operations": [
		{"kind":"remove_asset", "payload":{"placement_id":placement_id, "expected_placement":original}},
		{"kind":"place_asset", "payload":{"placement":replacement}}
	]})
	if result.ok:
		var stored := _find(result.snapshot.placements, placement_id)
		# _stroke is reversed at commit, so record place then remove while a
		# brush stroke is grouped. A standalone change needs that same grouping.
		var standalone := not _editing
		if standalone: begin_edit()
		_remember({"kind":"place_asset", "payload":{"placement":original.duplicate(true)}})
		_remember({"kind":"remove_asset", "payload":{"placement_id":placement_id, "expected_placement":stored.duplicate(true)}})
		if standalone: end_edit()
		changed.emit(result)
	return result


func begin_edit() -> void:
	if _editing:
		end_edit()
	_editing = true
	_stroke.clear()


func end_edit() -> void:
	if not _stroke.is_empty():
		_stroke.reverse()
		_history.append(_stroke.duplicate(true))
		_trim_history()
	_stroke.clear()
	_editing = false


func undo() -> Dictionary:
	if _editing:
		end_edit()
	if _history.is_empty():
		return _failure("nothing_to_undo", ["Nothing to undo."])
	var operations: Array = _history.back().duplicate(true)
	var result := _apply("edit_assets", {"operations": operations})
	if result.ok:
		_history.pop_back()
		changed.emit(result)
	return result


func undo_count() -> int:
	return _history.size() + (1 if not _stroke.is_empty() else 0)


func _apply(kind: String, payload: Dictionary) -> Dictionary:
	_refresh()
	if state == null:
		return _failure("not_configured", ["No port is loaded."])
	var command_id := "%s:builder:%s:%d" % [_snapshot.id, actor_company_id, _next_command]
	while _snapshot.receipts.has(command_id):
		_next_command += 1
		command_id = "%s:builder:%s:%d" % [_snapshot.id, actor_company_id, _next_command]
	_next_command += 1
	var result := state.apply({"command_id": command_id, "expected_revision": _revision,
		"actor_company_id": actor_company_id, "kind": kind, "payload": payload})
	if result.ok:
		_revision = -1
		_refresh()
	return result


func _remember(inverse: Dictionary) -> void:
	if _editing:
		_stroke.append(inverse)
	else:
		_history.append([inverse])
		_trim_history()


func _trim_history() -> void:
	while _history.size() > MAX_UNDO_GROUPS:
		_history.pop_front()


func _refresh() -> void:
	if state == null:
		return
	# Reading a revision must not clone hundreds of placements every frame.
	var current: int = state.revision()
	if current == _revision:
		return
	_snapshot = state.to_dict()
	_revision = current
	geometry_refreshes += 1
	_preview_cache.clear()
	_geometry.clear()
	_edges = state.construction_edges()
	for placement in _snapshot.get("placements", []):
		var spec := RULES.definition(placement, catalog)
		var rectangles := RULES.rectangles(placement, spec)
		var bounds := _footprint_bounds(placement, spec)
		_geometry.append({"placement": placement, "spec": spec, "bounds": bounds, "rects": rectangles})


func _snap(spec: Dictionary, cursor: Vector3, yaw: float, excluded_id := "") -> Dictionary:
	var kind := str(spec.get("kind", "decoration"))
	var placement_kind := str(spec.get("placement_kind", ""))
	var dimensions: Array = spec.get("footprint_m", [1, 1])
	var width := float(dimensions[0])
	var depth := float(dimensions[1])
	if posmod(roundi(yaw / 90.0), 2) == 1:
		var temporary := width
		width = depth
		depth = temporary
	if kind == "platform" or spec.get("snap_to_footprint",false):
		return {"position": Vector3(floorf(cursor.x / width) * width + width * 0.5, 0,
			floorf(cursor.z / depth) * depth + depth * 0.5), "yaw": yaw, "step": [width, depth]}
	# Roof planes cover the same cells as the floor and the rooms between wall
	# sockets. Plain snappedf(..., 4) lands on corners, offsetting a 4m roof by
	# half a cell on both axes. Edge strips still use the wall-socket path below.
	if placement_kind == "building" and str(spec.get("placement_layer", "")) == "roof":
		return {"position": Vector3(floorf(cursor.x / width) * width + width * 0.5, 0,
			floorf(cursor.z / depth) * depth + depth * 0.5), "yaw": yaw, "step": [width, depth]}
	var step := maxf(0.1, float(spec.get("snap_m", 1)))
	if spec.get("snap_cells") is Array:
		step = maxf(0.5, float(spec.snap_cells[0]) * 2.0)
	if placement_kind == "edge" or kind == "bollard":
		var edge := _nearest_edge(Vector2(cursor.x, cursor.z), 3.0)
		if not edge.is_empty():
			var normal: Vector2 = edge.normal
			var direction: Vector2 = edge.direction
			var start: Vector2 = edge.start
			var distance := (Vector2(cursor.x, cursor.z) - start).dot(direction)
			var along := snappedf(distance, step)
			if step >= 3.9:
				along = floorf(distance / step) * step + step * 0.5
			along = clampf(along, 0, float(edge.length))
			if kind == "bollard":
				# The edge-aligned yaw makes local X the tangent and local Z the
				# outward normal. Keep the complete base on the deck, including
				# the older 2m bollard and targets near the end of a quay.
				var end_clearance := float(dimensions[0]) * 0.5 + 0.05
				along = clampf(along, minf(end_clearance, float(edge.length) * 0.5), maxf(float(edge.length) - end_clearance, float(edge.length) * 0.5))
			var point := start + direction * along
			if kind == "bollard":
				var inset := maxf(float(spec.get("edge_inset_m", 0.75)), float(dimensions[1]) * 0.5 + 0.05)
				point -= normal * inset
			return {"position": Vector3(point.x, 0, point.y), "yaw": rad_to_deg(atan2(-normal.x, -normal.y)), "step": step}
		if placement_kind == "edge":
			return {"position": Vector3(snappedf(cursor.x, step), 0, snappedf(cursor.z, step)), "yaw": yaw, "step": step, "edge_found": false}
	if placement_kind == "building" and maxf(width, depth) >= 3.9 and minf(width, depth) < 1.0:
		var socket := _wall_socket(cursor, yaw, float(dimensions[0]), excluded_id)
		if not socket.is_empty():
			return {"position": socket.position, "yaw": yaw, "step": 4.0}
		if not is_zero_approx(fposmod(yaw, 90.0)):
			return {"position": Vector3(snappedf(cursor.x, 1.0), 0, snappedf(cursor.z, 1.0)), "yaw": yaw, "step": 1.0}
		# Wall midpoints are between corner sockets on a 4m construction lattice.
		if width > depth:
			return {"position": Vector3(floorf(cursor.x / 4.0) * 4.0 + 2.0, 0, snappedf(cursor.z, 4.0)), "yaw": yaw, "step": 4.0}
		return {"position": Vector3(snappedf(cursor.x, 4.0), 0, floorf(cursor.z / 4.0) * 4.0 + 2.0), "yaw": yaw, "step": 4.0}
	return {"position": Vector3(snappedf(cursor.x, step), 0, snappedf(cursor.z, step)), "yaw": yaw, "step": step}


func _wall_socket(cursor: Vector3, yaw: float, width: float, excluded_id := "") -> Dictionary:
	var heading := Vector3.RIGHT.rotated(Vector3.UP, deg_to_rad(yaw))
	var best := 2.25
	var result: Dictionary = {}
	for row in _geometry:
		if str(row.placement.id) == excluded_id: continue
		var spec: Dictionary = row.spec
		var fp: Array = spec.get("footprint_m", [1, 1])
		if str(spec.get("placement_kind", "")) != "building" or float(fp[0]) < 3.9 or float(fp[1]) >= 1.0:
			continue
		var at: Array = row.placement.position_m
		var center := Vector3(float(at[0]), 0, float(at[2]))
		var axis := Vector3.RIGHT.rotated(Vector3.UP, deg_to_rad(float(row.placement.yaw_degrees)))
		for end_sign in [-1, 1]:
			var end: Vector3 = center + axis * float(fp[0]) * 0.5 * end_sign
			for next_sign in [-1, 1]:
				var candidate: Vector3 = end + heading * width * 0.5 * next_sign
				var distance := Vector2(candidate.x - cursor.x, candidate.z - cursor.z).length()
				if distance < best:
					best = distance
					result.position = candidate
	return result


func _nearest_edge(point: Vector2, maximum: float) -> Dictionary:
	var best := maximum
	var result: Dictionary = {}
	for edge in _edges:
		var t := clampf((point - edge.start).dot(edge.direction), 0, float(edge.length))
		var contact: Vector2 = edge.start + edge.direction * t
		var distance := point.distance_to(contact)
		if distance < best:
			best = distance
			result = edge
	return result


func _has_docked_vessel() -> bool:
	for vessel in _snapshot.get("vessels", []):
		if not str(vessel.get("berth_id", "")).is_empty():
			return true
	return false


func _placement_id() -> String:
	var result := "%s:build:%d" % [_snapshot.get("id", "port"), _next_placement]
	while not _find(_snapshot.get("placements", []), result).is_empty():
		_next_placement += 1
		result = "%s:build:%d" % [_snapshot.get("id", "port"), _next_placement]
	return result


static func _footprint_bounds(placement: Dictionary, spec: Dictionary) -> Rect2:
	var areas := RULES.rectangles(placement, spec)
	if areas.is_empty():
		return Rect2()
	var bounds: Rect2 = areas[0]
	for area in areas:
		bounds = bounds.merge(area)
	return bounds


static func _find(records: Array, id: String) -> Dictionary:
	for record in records:
		if str(record.get("id", "")) == id:
			return record
	return {}


func _failure(code: String, errors: Array) -> Dictionary:
	return {"ok": false, "code": code, "errors": errors, "events": [],
		"snapshot": state.to_dict() if state != null else {}}
