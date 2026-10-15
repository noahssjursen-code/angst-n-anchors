class_name CustomPortBerths
extends RefCounted
## Scene-independent berth geometry. Saved berth inputs and outputs are JSON-safe;
## construction_edges() is a Vector2 adapter for the in-process editor only.
## Metres are port-local; Y=0 is the common deck plane. Water regions must cover
## the complete approach envelope: isolated depth probes do not certify water.

const EPS := 0.001
const DEFAULT_RULES := {
	"bollard_max_offset_m": 2.0, "end_clearance_m": 2.0,
	"side_clearance_m": 1.0, "fender_gap_m": 0.75,
	"under_keel_clearance_m": 0.5, "minimum_length_m": 8.0,
	"minimum_beam_m": 2.0, "maximum_beam_m": 24.0, "approach_width_factor": 2.0,
}


static func derive(record: Dictionary, catalog: Dictionary = {}, geometry_out: Dictionary = {}) -> Array[Dictionary]:
	var rules := _rules(record)
	var platforms := _platforms(record, catalog)
	var edges := _exposed_edges(platforms)
	geometry_out.construction_edges = _construction_edges(edges)
	var anchors := _anchors(record, catalog, edges, rules)
	var regions := _water_regions(record)
	var berths: Array[Dictionary] = []
	for edge_index in range(edges.size()):
		var edge: Dictionary = edges[edge_index]
		var along: Array = anchors.get(edge_index, [])
		along.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if absf(float(a.t) - float(b.t)) > EPS: return float(a.t) < float(b.t)
			return str(a.id) < str(b.id))
		for index in range(along.size() - 1):
			var first: Dictionary = along[index]
			var last: Dictionary = along[index + 1]
			var length_m := float(last.t) - float(first.t)
			var usable := length_m - 2.0 * float(rules.end_clearance_m)
			if usable < float(rules.minimum_length_m) - EPS: continue
			var segment := edge.duplicate()
			segment.start = float(first.t)
			segment.end = float(last.t)
			var available := _available_water(segment, rules, regions, platforms)
			var normal := _normal(segment)
			var start := _edge_point(segment, float(first.t))
			var end := _edge_point(segment, float(last.t))
			var beam := float(available.beam_m)
			var center := (start + end) * 0.5 + normal * (float(rules.fender_gap_m) + beam * 0.5)
			var mooring := _envelope_polygon(segment, float(rules.fender_gap_m), beam + float(rules.side_clearance_m))
			var identity: Array[String] = [str(first.id), str(last.id)]
			identity.sort()
			var berth := {
				"id": str(record.get("id", "port")) + ":berth:" + identity[0].uri_encode() + ":" + identity[1].uri_encode(),
				"bollard_ids": [str(first.id), str(last.id)],
				"edge_start_m": _xyz(start), "edge_end_m": _xyz(end),
				"outward_normal": _xyz(normal), "center_m": _xyz(center),
				"length_m": length_m, "max_length_m": usable,
				"max_beam_m": beam, "depth_m": float(available.depth_m),
				"clearance_m": float(rules.end_clearance_m),
				"side_clearance_m": float(rules.side_clearance_m),
				"fender_gap_m": float(rules.fender_gap_m),
				"under_keel_clearance_m": float(rules.under_keel_clearance_m),
				"water_verified": bool(available.verified),
				"approach_envelope_m": _rect_array(available.envelope),
				"approach_polygon_m": _polygon_array(available.polygon),
				"mooring_envelope_m": _rect_array(_polygon_bounds(mooring)), "mooring_polygon_m": _polygon_array(mooring),
				"crane_ids": [], "store_ids": [], "crane_services": [], "conflicting_berth_ids": [],
			}
			_link_cranes(berth, record, catalog)
			berths.append(berth)
	berths.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.id) < str(b.id))
	# Approach water can be shared. Actual moored hull envelopes cannot.
	for a in range(berths.size()):
		for b in range(a + 1, berths.size()):
			if _polygons_overlap(_polygon(berths[a].mooring_polygon_m), _polygon(berths[b].mooring_polygon_m)):
				berths[a].conflicting_berth_ids.append(berths[b].id)
				berths[b].conflicting_berth_ids.append(berths[a].id)
	return berths


static func fit(berth: Dictionary, ship: Dictionary, occupancy: Array = []) -> Dictionary:
	var reasons: Array[String] = []
	for key in ["length_m", "beam_m", "draft_m"]:
		if not _number(ship.get(key)) or float(ship[key]) <= 0.0:
			reasons.append("invalid_vessel_dimensions")
			return {"ok": false, "reasons": reasons}
	if not bool(berth.get("water_verified", false)): reasons.append("water_unverified")
	if float(ship.length_m) > float(berth.get("max_length_m", 0.0)) + EPS: reasons.append("insufficient_length")
	if float(ship.beam_m) > float(berth.get("max_beam_m", 0.0)) + EPS: reasons.append("insufficient_beam")
	if float(ship.draft_m) + float(berth.get("under_keel_clearance_m", 0.5)) > float(berth.get("depth_m", 0.0)) + EPS:
		reasons.append("insufficient_depth")
	var berth_id := str(berth.get("id", ""))
	var vessel_id := str(ship.get("id", ship.get("vessel_id", "")))
	for raw in occupancy:
		if not raw is Dictionary: continue
		var occupied_id := str(raw.get("berth_id", ""))
		var occupant := str(raw.get("vessel_id", ""))
		if not vessel_id.is_empty() and vessel_id == occupant: continue
		if occupied_id == berth_id and not berth_id.is_empty():
			if not reasons.has("occupied"): reasons.append("occupied")
		elif berth.get("conflicting_berth_ids", []).has(occupied_id):
			if not reasons.has("adjacent_berth_occupied"): reasons.append("adjacent_berth_occupied")
	return {"ok": reasons.is_empty(), "reasons": reasons}


static func construction_edges(record: Dictionary, catalog: Dictionary = {}) -> Array[Dictionary]:
	return _construction_edges(_exposed_edges(_platforms(record, catalog)))


static func _construction_edges(edges: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for edge in edges:
		result.append({"start": _edge_point(edge, float(edge.start)), "direction": edge.tangent,
			"length": float(edge.end) - float(edge.start), "normal": edge.normal})
	return result


static func docking_pose(berth: Dictionary, ship: Dictionary) -> Dictionary:
	var start := _position(berth.get("edge_start_m", []))
	var end := _position(berth.get("edge_end_m", []))
	var normal := _position(berth.get("outward_normal", []))
	if not start.is_finite() or not end.is_finite() or not normal.is_finite(): return {}
	if not _number(ship.get("beam_m")) or float(ship.beam_m) <= 0.0: return {}
	var center := (start + end) * 0.5 + normal * (float(berth.get("fender_gap_m", 0.75)) + float(ship.beam_m) * 0.5)
	var direction := (end - start).normalized()
	return {"center_m": [center.x, center.y, center.z], "yaw_degrees": rad_to_deg(atan2(-direction.x, -direction.z))}


static func services_for_vessel(berth: Dictionary, ship: Dictionary, handling_mode := "") -> Dictionary:
	# Geometry inspection may omit the handling mode. Cargo authority supplies
	# the lot's mode; absent capability metadata never grants a transfer.
	var result := {"crane_ids": [], "store_ids": [], "crane_services": []}
	if not bool(berth.get("water_verified", false)): return result
	if not _number(ship.get("length_m")) or float(ship.length_m) <= 0.0: return result
	var pose := docking_pose(berth, ship)
	if pose.is_empty(): return result
	var center := _position(pose.center_m)
	var normal3 := _position(berth.outward_normal)
	var normal := Vector2(normal3.x, normal3.z)
	var tangent := Vector2(-normal.y, normal.x)
	var along := tangent * float(ship.length_m) * 0.5
	var across := normal * float(ship.beam_m) * 0.5
	var at := Vector2(center.x, center.z)
	var hull := PackedVector2Array([at-along-across, at+along-across, at+along+across, at-along+across])
	for service in berth.get("crane_services", []):
		if not handling_mode.is_empty() and handling_mode not in service.get("cargo_types", []): continue
		var p := _position(service.get("pivot_m", []))
		if not p.is_finite() or not _polygon_within_reach(hull, Vector2(p.x, p.z), float(service.reach_min_m), float(service.reach_max_m)): continue
		result.crane_ids.append(str(service.crane_id))
		result.crane_services.append(service.duplicate(true))
		for store_id in service.store_ids:
			if not result.store_ids.has(store_id): result.store_ids.append(store_id)
	result.crane_ids.sort()
	result.store_ids.sort()
	result.crane_services.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.crane_id) < str(b.crane_id))
	return result


static func _rules(record: Dictionary) -> Dictionary:
	var result := DEFAULT_RULES.duplicate()
	var requested: Dictionary = record.get("berth_rules", {}) if record.get("berth_rules", {}) is Dictionary else {}
	for key in result:
		if _number(requested.get(key)) and float(requested[key]) >= 0.0: result[key] = float(requested[key])
	result.approach_width_factor = maxf(1.0, float(result.approach_width_factor))
	result.minimum_beam_m = maxf(0.5, float(result.minimum_beam_m))
	result.maximum_beam_m = clampf(float(result.maximum_beam_m), float(result.minimum_beam_m), 100.0)
	return result


static func _metadata(placement: Dictionary, catalog: Dictionary) -> Dictionary:
	var asset_id := str(placement.get("asset_id", ""))
	var definition: Dictionary = {}
	if catalog.get(asset_id) is Dictionary: definition = catalog[asset_id].duplicate(true)
	elif catalog.get("assets") is Array:
		for item in catalog.assets:
			if item is Dictionary and str(item.get("id", "")) == asset_id:
				definition = item.duplicate(true)
				break
	if definition.get("attributes") is Dictionary: definition.merge(definition.attributes, true)
	if placement.get("attributes") is Dictionary: definition.merge(placement.attributes, true)
	return definition


static func _platforms(record: Dictionary, catalog: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for raw in record.get("placements", []):
		if not raw is Dictionary: continue
		var meta := _metadata(raw, catalog)
		if str(meta.get("kind", "")) != "platform": continue
		var position := _position(raw.get("position_m", []))
		var size := _pair(meta.get("footprint_m", []))
		var yaw := float(raw.get("yaw_degrees", 0.0))
		# Upper floors and diagonal AABBs cannot pretend to be sea-level quays.
		if not is_finite(yaw) or not position.is_finite() or absf(position.y) > 0.05 or size.x <= 0.0 or size.y <= 0.0: continue
		var turns := roundi(yaw / 90.0)
		if absf(yaw - float(turns) * 90.0) > 0.01: continue
		var local := _polygon(meta.get("footprint_polygon_m", []))
		if local.size() < 3:
			if meta.has("footprint_polygon_m"): continue
			local = _rectangle_polygon(Rect2(-size * 0.5, size))
		var points := PackedVector2Array()
		for point in local:
			points.append(point.rotated(-deg_to_rad(yaw)) + Vector2(position.x, position.z))
		if absf(_signed_area(points)) <= EPS: continue
		result.append({"polygon": points, "bounds": _polygon_bounds(points)})
	return result


static func _exposed_edges(platforms: Array[Dictionary]) -> Array[Dictionary]:
	var exposed: Array[Dictionary] = []
	var spatial: Dictionary = {}
	var shared_edges: Dictionary = {}
	for index in range(platforms.size()):
		for cell in _cells(platforms[index].bounds.grow(EPS * 2.0)):
			if not spatial.has(cell): spatial[cell] = []
			spatial[cell].append(index)
		var polygon: PackedVector2Array = platforms[index].polygon
		for side in range(polygon.size()):
			var key := _segment_key(polygon[side], polygon[(side + 1) % polygon.size()])
			if not shared_edges.has(key): shared_edges[key] = []
			shared_edges[key].append(index)
	for platform_index in range(platforms.size()):
		var platform: Dictionary = platforms[platform_index]
		var polygon: PackedVector2Array = platform.polygon
		var winding := 1.0 if _signed_area(polygon) > 0.0 else -1.0
		for index in range(polygon.size()):
			var a := polygon[index]
			var b := polygon[(index + 1) % polygon.size()]
			if a.distance_to(b) <= EPS: continue
			var direction := (b-a).normalized()
			var normal := Vector2(direction.y, -direction.x) * winding
			var tangent := direction
			if tangent.x < -EPS or (absf(tangent.x) <= EPS and tangent.y < 0.0): tangent = -tangent
			var origin := normal * normal.dot(a)
			var start := minf(tangent.dot(a), tangent.dot(b))
			var end := maxf(tangent.dot(a), tangent.dot(b))
			# Tiled decks mostly contain interior seams. Check exact shared endpoints
			# first, using the same polygon clipping as the general union below.
			# A match alone is not proof: duplicate faces, thin pieces and concave
			# polygons still need their actual outward-side coverage checked.
			var hidden := false
			for other_index in shared_edges[_segment_key(a, b)]:
				if other_index == platform_index: continue
				for cut in _inside_line_intervals(origin + normal * EPS, tangent, start, end, platforms[other_index].polygon):
					if _subtract([Vector2(start, end)], cut).is_empty():
						hidden = true
						break
				if hidden: break
			if hidden: continue
			var intervals: Array[Vector2] = [Vector2(start, end)]
			var nearby: Dictionary = {}
			var bounds := Rect2(a, Vector2.ZERO).expand(b).grow(EPS * 2.0)
			for cell in _cells(bounds):
				for other_index in spatial.get(cell, []): nearby[other_index] = true
			for other_index in nearby:
				var other: Dictionary = platforms[other_index]
				if not bounds.intersects(other.bounds.grow(EPS * 2.0)): continue
				for cut in _inside_line_intervals(origin + normal * EPS, tangent, start, end, other.polygon):
					intervals = _subtract(intervals, cut)
				if intervals.is_empty(): break
			if intervals.is_empty(): continue
			var edge := {"origin": origin, "normal": normal, "tangent": tangent, "start": start, "end": end,
				"key": "%d:%d:%d" % [roundi(normal.x * 1000000.0), roundi(normal.y * 1000000.0), roundi(normal.dot(a) / EPS)]}
			for interval in intervals:
				var part: Dictionary = edge.duplicate()
				part.start = interval.x
				part.end = interval.y
				exposed.append(part)
	exposed.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.key != b.key: return str(a.key) < str(b.key)
		return float(a.start) < float(b.start))
	var merged: Array[Dictionary] = []
	for edge in exposed:
		if not merged.is_empty():
			var last: Dictionary = merged.back()
			if last.key == edge.key and float(edge.start) <= float(last.end) + EPS:
				last.end = maxf(float(last.end), float(edge.end))
				continue
		merged.append(edge)
	return merged


static func _segment_key(a: Vector2, b: Vector2) -> Vector4:
	# No quantization: nearly coincident pieces retain the full union path.
	if a.x > b.x or (a.x == b.x and a.y > b.y): return Vector4(b.x, b.y, a.x, a.y)
	return Vector4(a.x, a.y, b.x, b.y)


static func _cells(bounds: Rect2) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for x in range(floori(bounds.position.x / 16.0), floori(bounds.end.x / 16.0) + 1):
		for z in range(floori(bounds.position.y / 16.0), floori(bounds.end.y / 16.0) + 1): result.append(Vector2i(x, z))
	return result


static func _inside_line_intervals(origin: Vector2, tangent: Vector2, start: float, end: float, polygon: PackedVector2Array) -> Array[Vector2]:
	var cuts: Array[float] = [start, end]
	for i in range(polygon.size()):
		var a := polygon[i]
		var side := polygon[(i + 1) % polygon.size()] - a
		var divisor := tangent.cross(side)
		if absf(divisor) < EPS * EPS: continue
		var t := (a-origin).cross(side) / divisor
		var s := (a-origin).cross(tangent) / divisor
		if s >= 0.0 and s <= 1.0 and t > start and t < end: cuts.append(t)
	cuts.sort()
	var result: Array[Vector2] = []
	for i in range(cuts.size() - 1):
		if cuts[i + 1] - cuts[i] <= EPS: continue
		if Geometry2D.is_point_in_polygon(origin + tangent * ((cuts[i] + cuts[i + 1]) * 0.5), polygon):
			result.append(Vector2(cuts[i], cuts[i + 1]))
	return result


static func _subtract(intervals: Array[Vector2], cut: Vector2) -> Array[Vector2]:
	var result: Array[Vector2] = []
	for interval in intervals:
		if cut.y <= interval.x + EPS or cut.x >= interval.y - EPS:
			result.append(interval)
			continue
		if cut.x > interval.x + EPS: result.append(Vector2(interval.x, minf(cut.x, interval.y)))
		if cut.y < interval.y - EPS: result.append(Vector2(maxf(cut.y, interval.x), interval.y))
	return result


static func _anchors(record: Dictionary, catalog: Dictionary, edges: Array[Dictionary], rules: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for raw in record.get("placements", []):
		if not raw is Dictionary or str(raw.get("id", "")).is_empty(): continue
		if str(_metadata(raw, catalog).get("kind", "")) != "bollard": continue
		var position := _position(raw.get("position_m", []))
		if not position.is_finite() or absf(position.y) > 0.5: continue
		var point := Vector2(position.x, position.z)
		var closest_index := -1
		var closest_distance := INF
		var closest_t := 0.0
		for index in range(edges.size()):
			var edge: Dictionary = edges[index]
			var t: float = point.dot(edge.tangent)
			if t < float(edge.start) - EPS or t > float(edge.end) + EPS: continue
			var foot := _edge_point(edge, t)
			var signed_offset := (point - foot).dot(_normal(edge))
			if signed_offset > 0.25 or signed_offset < -float(rules.bollard_max_offset_m): continue
			var distance := absf(signed_offset)
			if distance < closest_distance - EPS:
				closest_index = index
				closest_distance = distance
				closest_t = t
		if closest_index < 0: continue
		if not result.has(closest_index): result[closest_index] = []
		result[closest_index].append({"id": str(raw.id), "t": closest_t})
	return result


static func _water_regions(record: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for raw in record.get("water_regions", []):
		if not raw is Dictionary or not _number(raw.get("depth_m")): continue
		var rect := _rect(raw.get("rect_m", []))
		if rect.size.x <= 0.0 or rect.size.y <= 0.0: continue
		result.append({"rect": rect, "depth_m": maxf(0.0, float(raw.depth_m))})
	return result


static func _available_water(edge: Dictionary, rules: Dictionary, regions: Array[Dictionary], platforms: Array[Dictionary]) -> Dictionary:
	var minimum := float(rules.minimum_beam_m)
	var maximum := float(rules.maximum_beam_m)
	var gap := float(rules.fender_gap_m)
	var factor := float(rules.approach_width_factor)
	var side := float(rules.side_clearance_m)
	var minimum_polygon := _envelope_polygon(edge, gap, minimum * factor + side)
	var minimum_info := _water_info(minimum_polygon, regions, platforms)
	if not minimum_info.ok:
		return {"verified": false, "beam_m": 0.0, "depth_m": 0.0, "envelope": _polygon_bounds(minimum_polygon), "polygon": minimum_polygon}
	var polygon := _envelope_polygon(edge, gap, maximum * factor + side)
	var info := _water_info(polygon, regions, platforms)
	if not info.ok:
		var low := minimum
		var high := maximum
		for _iteration in range(16):
			var middle := (low + high) * 0.5
			if _water_info(_envelope_polygon(edge, gap, middle * factor + side), regions, platforms).ok: low = middle
			else: high = middle
		maximum = floorf(low * 100.0) / 100.0
		polygon = _envelope_polygon(edge, gap, maximum * factor + side)
		info = _water_info(polygon, regions, platforms)
	return {"verified": bool(info.ok), "beam_m": maximum, "depth_m": float(info.depth_m), "envelope": _polygon_bounds(polygon), "polygon": polygon}


static func _water_info(polygon: PackedVector2Array, regions: Array[Dictionary], platforms: Array[Dictionary]) -> Dictionary:
	var envelope := _polygon_bounds(polygon)
	for platform in platforms:
		if _positive_intersection(envelope, platform.bounds) and _polygons_overlap(polygon, platform.polygon): return {"ok": false, "depth_m": 0.0}
	var xcuts: Array[float] = [envelope.position.x, envelope.end.x]
	var relevant: Array[Dictionary] = []
	var minimum := INF
	for region in regions:
		var clipped: Rect2 = envelope.intersection(region.rect)
		if clipped.size.x <= 0.0 or clipped.size.y <= 0.0: continue
		if absf(_signed_area(_clip_to_rect(polygon, clipped))) <= EPS * EPS: continue
		relevant.append({"rect": clipped, "depth_m": region.depth_m})
		minimum = minf(minimum, float(region.depth_m))
		xcuts.append(clipped.position.x)
		xcuts.append(clipped.end.x)
	if relevant.is_empty(): return {"ok": false, "depth_m": 0.0}
	xcuts.sort()
	# Sweep exact rectangle boundaries, then merge covered Z intervals per strip.
	# This catches narrow survey gaps without a cubic raster cross-product.
	for x in range(xcuts.size() - 1):
		if xcuts[x + 1] - xcuts[x] <= EPS * 0.01: continue
		var strip := Rect2(xcuts[x], envelope.position.y, xcuts[x + 1] - xcuts[x], envelope.size.y)
		var required_polygon := _clip_to_rect(polygon, strip)
		if absf(_signed_area(required_polygon)) <= EPS * EPS: continue
		var required := _polygon_bounds(required_polygon)
		var midpoint := (xcuts[x] + xcuts[x + 1]) * 0.5
		var intervals: Array[Vector2] = []
		for region in relevant:
			var rect: Rect2 = region.rect
			if midpoint >= rect.position.x and midpoint < rect.end.x:
				intervals.append(Vector2(rect.position.y, rect.end.y))
		intervals.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
		var covered_to := required.position.y
		for interval in intervals:
			if interval.y <= covered_to: continue
			if covered_to >= required.end.y - EPS * 0.01: break
			if interval.x > covered_to + EPS * 0.01: return {"ok": false, "depth_m": 0.0}
			covered_to = maxf(covered_to, interval.y)
		if covered_to < required.end.y - EPS * 0.01: return {"ok": false, "depth_m": 0.0}
	return {"ok": minimum > 0.0 and is_finite(minimum), "depth_m": minimum if is_finite(minimum) else 0.0}


static func _link_cranes(berth: Dictionary, record: Dictionary, catalog: Dictionary) -> void:
	if not berth.water_verified: return
	var service_area := _rect(berth.mooring_envelope_m)
	for raw in record.get("placements", []):
		if not raw is Dictionary: continue
		var meta := _metadata(raw, catalog)
		if str(meta.get("kind", "")) != "crane": continue
		var reach := float(meta.get("reach_max_m", 0.0))
		var minimum := maxf(0.0, float(meta.get("reach_min_m", 0.0)))
		if not is_finite(reach) or not is_finite(minimum) or reach <= minimum: continue
		var offset_data: Array = meta.get("crane_offset_m", []) if meta.get("crane_offset_m", []) is Array else []
		var offset := Vector2.ZERO
		if offset_data.size() == 3: offset = Vector2(float(offset_data[0]), float(offset_data[2]))
		elif offset_data.size() == 2: offset = Vector2(float(offset_data[0]), float(offset_data[1]))
		var yaw := deg_to_rad(float(raw.get("yaw_degrees", 0.0)))
		# Godot positive Y rotation maps local +X toward -Z.
		offset = offset.rotated(-yaw)
		var p := _position(raw.get("position_m", []))
		var pivot := Vector2(p.x, p.z) + offset
		if not pivot.is_finite(): continue
		# Berth capacity is not the size of every arriving vessel. Keep potential
		# services here; validate each actual hull in services_for_vessel().
		if not _reach_intersects(service_area, pivot, minimum, reach): continue
		var crane_id := str(raw.get("id", ""))
		if crane_id.is_empty(): continue
		berth.crane_ids.append(crane_id)
		var cargo_types: Array[String] = []
		if meta.get("cargo_types") is Array:
			for type in meta.cargo_types:
				if type is String and type in ["container", "general", "bulk", "catch", "liquid"] and type not in cargo_types: cargo_types.append(type)
		cargo_types.sort()
		var service := {"crane_id": crane_id, "pivot_m": _xyz(pivot), "reach_min_m": minimum, "reach_max_m": reach, "store_ids": [], "cargo_types": cargo_types}
		for store in record.get("stores", []):
			if not store is Dictionary: continue
			var store_id := str(store.get("id", ""))
			var placement_id := str(store.get("placement_id", ""))
			# A piped receiver cannot serve another bank merely because a client
			# lists that bank's ID. Movable cranes retain their explicit yard links.
			if meta.get("attached_store_only",false) and placement_id!=crane_id:continue
			if placement_id != crane_id and not meta.get("store_ids", []).has(store_id): continue
			# A configured link is only a pairing preference, not permission to
			# move goods from an unreachable yard across the port.
			var pad := _store_bounds(store, raw, meta, record, catalog)
			if pad.has_area() and _within_reach(pad, pivot, minimum, reach):
				service.store_ids.append(store_id)
				if not berth.store_ids.has(store_id): berth.store_ids.append(store_id)
		berth.crane_services.append(service)
	berth.crane_ids.sort()
	berth.store_ids.sort()


static func _reach_intersects(area: Rect2, pivot: Vector2, minimum: float, maximum: float) -> bool:
	var nearest := Vector2(clampf(pivot.x, area.position.x, area.end.x), clampf(pivot.y, area.position.y, area.end.y))
	if pivot.distance_to(nearest) > maximum + EPS: return false
	for corner in [area.position, area.end, Vector2(area.position.x, area.end.y), Vector2(area.end.x, area.position.y)]:
		if pivot.distance_to(corner) >= minimum - EPS: return true
	return false


static func _within_reach(area: Rect2, pivot: Vector2, minimum: float, maximum: float) -> bool:
	var nearest := Vector2(clampf(pivot.x, area.position.x, area.end.x), clampf(pivot.y, area.position.y, area.end.y))
	if pivot.distance_to(nearest) < minimum - EPS: return false
	for corner in [area.position, area.end, Vector2(area.position.x, area.end.y), Vector2(area.end.x, area.position.y)]:
		if pivot.distance_to(corner) > maximum + EPS: return false
	return true


static func _polygon_within_reach(polygon: PackedVector2Array, pivot: Vector2, minimum: float, maximum: float) -> bool:
	if polygon.size() < 3: return false
	var nearest := 0.0 if Geometry2D.is_point_in_polygon(pivot, polygon) else INF
	for i in range(polygon.size()):
		if pivot.distance_to(polygon[i]) > maximum + EPS: return false
		nearest = minf(nearest, pivot.distance_to(Geometry2D.get_closest_point_to_segment(pivot, polygon[i], polygon[(i + 1) % polygon.size()])))
	return nearest >= minimum - EPS


static func _store_bounds(store: Dictionary, crane: Dictionary, crane_meta: Dictionary, record: Dictionary, catalog: Dictionary) -> Rect2:
	var placement: Dictionary = {}
	for item in record.get("placements", []):
		if item is Dictionary and str(item.get("id", "")) == str(store.get("placement_id", "")):
			placement = item
			break
	if placement.is_empty(): return Rect2()
	var meta := _metadata(placement, catalog)
	var size := _pair(meta.get("footprint_m", []))
	var offset := Vector2.ZERO
	if str(placement.id) == str(crane.id):
		var storage := _rect(crane_meta.get("storage_rect_m", []))
		if storage.has_area():
			size = storage.size
			offset = storage.get_center()
		else:
			size = _pair(crane_meta.get("pad_size_m", []))
			var values: Variant = crane_meta.get("pad_offset_m", [])
			if values is Array and values.size() == 3: offset = Vector2(float(values[0]), float(values[2]))
			elif values is Array and values.size() == 2: offset = _pair(values)
	if size.x <= 0.0 or size.y <= 0.0: return Rect2()
	var yaw := deg_to_rad(float(placement.get("yaw_degrees", 0.0)))
	var p := _position(placement.get("position_m", []))
	var center := Vector2(p.x, p.z) + offset.rotated(-yaw)
	if not center.is_finite(): return Rect2()
	# Axis-aligned envelope is conservative for unusual custom yard rotations.
	var rotated_size := Vector2(absf(cos(yaw)) * size.x + absf(sin(yaw)) * size.y, absf(sin(yaw)) * size.x + absf(cos(yaw)) * size.y)
	return Rect2(center - rotated_size * 0.5, rotated_size)


static func _envelope(edge: Dictionary, gap: float, width: float) -> Rect2:
	return _polygon_bounds(_envelope_polygon(edge, gap, width))


static func _envelope_polygon(edge: Dictionary, gap: float, width: float) -> PackedVector2Array:
	var normal := _normal(edge)
	var start := _edge_point(edge, float(edge.start))
	var end := _edge_point(edge, float(edge.end))
	return PackedVector2Array([start + normal * gap, end + normal * gap, end + normal * (gap + width), start + normal * (gap + width)])


static func _normal(edge: Dictionary) -> Vector2:
	return edge.normal


static func _edge_point(edge: Dictionary, t: float) -> Vector2:
	return edge.origin + edge.tangent * t


static func _polygon(value: Variant) -> PackedVector2Array:
	var result := PackedVector2Array()
	if not value is Array: return result
	for point in value:
		if not point is Array or point.size() != 2 or not _number(point[0]) or not _number(point[1]): return PackedVector2Array()
		result.append(Vector2(float(point[0]), float(point[1])))
	return result


static func _polygon_array(polygon: PackedVector2Array) -> Array:
	var result: Array = []
	for point in polygon: result.append([point.x, point.y])
	return result


static func _rectangle_polygon(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])


static func _polygon_bounds(polygon: PackedVector2Array) -> Rect2:
	if polygon.is_empty(): return Rect2()
	var result := Rect2(polygon[0], Vector2.ZERO)
	for point in polygon: result = result.expand(point)
	return result


static func _signed_area(polygon: PackedVector2Array) -> float:
	var area := 0.0
	for i in range(polygon.size()): area += polygon[i].cross(polygon[(i + 1) % polygon.size()])
	return area * 0.5


static func _polygons_overlap(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	if a.size() < 3 or b.size() < 3: return false
	if not _positive_intersection(_polygon_bounds(a), _polygon_bounds(b)): return false
	for piece in Geometry2D.intersect_polygons(a, b):
		if absf(_signed_area(piece)) > EPS * EPS: return true
	return false


static func _clip_to_rect(polygon: PackedVector2Array, rect: Rect2) -> PackedVector2Array:
	var result := polygon
	for side in range(4):
		var clipped := PackedVector2Array()
		for i in range(result.size()):
			var a := result[i]
			var b := result[(i + 1) % result.size()]
			var da := _rect_signed_distance(a, rect, side)
			var db := _rect_signed_distance(b, rect, side)
			if da >= 0.0: clipped.append(a)
			if (da >= 0.0) != (db >= 0.0): clipped.append(a.lerp(b, da / (da-db)))
		result = clipped
		if result.is_empty(): break
	return result


static func _rect_signed_distance(point: Vector2, rect: Rect2, side: int) -> float:
	match side:
		0: return point.x - rect.position.x
		1: return rect.end.x - point.x
		2: return point.y - rect.position.y
	return rect.end.y - point.y


static func _positive_intersection(a: Rect2, b: Rect2) -> bool:
	var intersection := a.intersection(b)
	return intersection.size.x > EPS and intersection.size.y > EPS


static func _xyz(point: Vector2) -> Array:
	return [point.x, 0.0, point.y]


static func _rect_array(rect: Rect2) -> Array:
	return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]


static func _rect(value: Variant) -> Rect2:
	if not value is Array or value.size() != 4: return Rect2()
	for number in value:
		if not _number(number): return Rect2()
	return Rect2(float(value[0]), float(value[1]), float(value[2]), float(value[3]))


static func _pair(value: Variant) -> Vector2:
	if not value is Array or value.size() != 2 or not _number(value[0]) or not _number(value[1]): return Vector2.ZERO
	return Vector2(float(value[0]), float(value[1]))


static func _position(value: Variant) -> Vector3:
	if not value is Array or value.size() != 3: return Vector3(INF, INF, INF)
	for number in value:
		if not _number(number): return Vector3(INF, INF, INF)
	return Vector3(float(value[0]), float(value[1]), float(value[2]))


static func _number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))
