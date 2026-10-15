extends RefCounted
## Checks the original terrain, before a proposed foundation excavates it.
## Clip against its triangle lattice: corners alone miss dips inside a pad,
## and a bounding rectangle would include the missing corner of a chamfer.
const RULES = preload("res://scripts/port/state/custom_port_placement_rules.gd")
const SURFACE_EPS_M := .02
const BURIED_MESSAGE := "Entire foundation is below the land. Build closer to the shoreline."

static func fully_buried(placement: Dictionary, spec: Dictionary, origin: Vector3,
		height_at: Callable, terrain_step_m: float) -> bool:
	if str(spec.get("kind", "")) != "platform" or not height_at.is_valid() or terrain_step_m <= 0:
		return false
	if not placement.get("position_m") is Array or placement.position_m.size() != 3:
		return false # Malformed proposals are rejected by the ordinary record validator.
	var found_surface := false
	var deck_y := origin.y + float(placement.position_m[1])
	for local_polygon in RULES.polygons(placement, spec):
		var polygon: PackedVector2Array = local_polygon.duplicate()
		for i in polygon.size(): polygon[i] += Vector2(origin.x, origin.z)
		var bounds := RULES.polygon_bounds(polygon)
		for z in range(floori(bounds.position.y / terrain_step_m), ceili(bounds.end.y / terrain_step_m)):
			for x in range(floori(bounds.position.x / terrain_step_m), ceili(bounds.end.x / terrain_step_m)):
				var a := Vector2(x, z) * terrain_step_m
				var b := a + Vector2(terrain_step_m, 0)
				var c := a + Vector2(0, terrain_step_m)
				var d := a + Vector2.ONE * terrain_step_m
				for triangle in [PackedVector2Array([a, b, c]), PackedVector2Array([b, d, c])]:
					for clipped in Geometry2D.intersect_polygons(polygon, triangle):
						if RULES.polygon_area(clipped) <= .00001: continue
						found_surface = true
						for point in clipped:
							var height := float(height_at.call(point))
							if not is_finite(height) or height <= deck_y + SURFACE_EPS_M:
								return false
	return found_surface
