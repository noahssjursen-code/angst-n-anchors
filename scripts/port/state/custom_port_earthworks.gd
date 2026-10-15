class_name CustomPortEarthworks
extends RefCounted
## Derived, local-only terrain projection. Inputs must already have passed
## CustomPortState validation; arbitrary client-authored cut zones are not used.

const CAP_CLEARANCE_M := 0.12
const CACHE_LIMIT := 16
static var _cache: Dictionary = {}
static var _order: Array[String] = []


static func forest_exclusions(projection: Dictionary) -> Array:
	var result: Array = []
	for polygon in projection.get("footprints",[]):
		result.append({"polygon":polygon.duplicate(),"forest_clear_only":true,
			"near_field_bounds":CustomPortBerths._polygon_bounds(polygon)})
	return result


static func project(snapshot: Dictionary, catalog: Dictionary, construction_edges: Array = []) -> Dictionary:
	var rows: Array = []
	for placement in snapshot.get("placements", []):
		var definition: Dictionary = catalog.get(str(placement.asset_id), {})
		if str(definition.get("kind", "")) != "platform": continue
		rows.append([placement.id, placement.asset_id, placement.position_m, placement.get("yaw_degrees", 0),
			definition.get("footprint_m", []), definition.get("footprint_polygon_m", [])])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return str(a[0]) < str(b[0]))
	var signature := JSON.stringify([snapshot.get("world", {}), snapshot.origin_m, rows], "", true, true).sha256_text()
	var key := str(snapshot.id) + ":" + signature
	if _cache.has(key):
		var cached: Dictionary = _cache[key].duplicate(true)
		cached.revision = int(snapshot.get("revision", 0))
		return cached
	var origin := Vector2(float(snapshot.origin_m[0]), float(snapshot.origin_m[2]))
	var footprints: Array[PackedVector2Array] = []
	var bounds := Rect2()
	for platform in CustomPortBerths._platforms(snapshot, catalog):
		var polygon: PackedVector2Array = platform.polygon.duplicate()
		for i in polygon.size(): polygon[i] += origin
		var box := CustomPortBerths._polygon_bounds(polygon)
		bounds = box if footprints.is_empty() else bounds.merge(box)
		footprints.append(polygon)
	var source_edges := construction_edges
	if source_edges.is_empty() and not footprints.is_empty(): source_edges = CustomPortBerths.construction_edges(snapshot, catalog)
	var edges: Array[Dictionary] = []
	for edge in source_edges:
		edges.append({"start": edge.start + origin, "direction": edge.direction, "length": edge.length, "normal": edge.normal})
	var result := {"id": str(snapshot.id), "revision": int(snapshot.get("revision", 0)), "geometry_signature": signature,
		"world": snapshot.get("world", {}).duplicate(true), "cut_height_m": float(snapshot.origin_m[1]) - CAP_CLEARANCE_M,
		"footprints": footprints, "edges": edges, "bounds": bounds}
	_cache[key] = result.duplicate(true)
	_order.append(key)
	while _order.size() > CACHE_LIMIT: _cache.erase(_order.pop_front())
	return result
