class_name StructureStudioOpenings
extends RefCounted

## Pure opening helpers for Structure Studio (no Node dependencies).
## Defaults, span/rect snapping, and ghost geometry for wall + plate cuts.


static func defaults_for(opening_type: String) -> Dictionary:
	match opening_type:
		StructurePlan.OPENING_WINDOW:
			return {"type": "window", "width": 2.0, "sill": 1.2, "height": 1.2}
		StructurePlan.OPENING_HOLE:
			return {"type": "hole", "width": 2.0, "sill": 0.0, "height": 2.4}
		StructurePlan.OPENING_STAIRWELL:
			return {"type": "stairwell", "width": 1.0, "sill": 0.0, "height": 3.0}
		_:
			return {"type": "door", "width": 2.0, "sill": 0.0, "height": 2.2}


static func wall_span(length: float, a: float, b: float, dragged: bool, default_width: float) -> Vector2:
	if not dragged:
		var width: float = minf(default_width, length)
		var off := clampf(roundf(a - width * 0.5), 0.0, maxf(length - width, 0.0))
		return Vector2(off, width)
	var e0 := roundf(minf(a, b) * 2.0) / 2.0
	var e1 := roundf(maxf(a, b) * 2.0) / 2.0
	e0 = clampf(e0, 0.0, maxf(length - 1.0, 0.0))
	e1 = clampf(maxf(e1, e0 + 1.0), e0 + 1.0, length)
	return Vector2(e0, e1 - e0)


static func plate_rect(extent: Vector2, a: Vector2, b: Vector2, dragged: bool) -> Rect2:
	if not dragged:
		var w := minf(1.0, extent.x)
		var l := minf(3.0, extent.y)
		return Rect2(
			clampf(roundf(a.x - w * 0.5), 0.0, maxf(extent.x - w, 0.0)),
			clampf(roundf(a.y - l * 0.5), 0.0, maxf(extent.y - l, 0.0)),
			w, l,
		)
	var mn := Vector2(roundf(minf(a.x, b.x)), roundf(minf(a.y, b.y)))
	var mx := Vector2(roundf(maxf(a.x, b.x)), roundf(maxf(a.y, b.y)))
	mn = mn.clamp(Vector2.ZERO, Vector2(maxf(extent.x - 1.0, 0.0), maxf(extent.y - 1.0, 0.0)))
	mx = mx.clamp(mn + Vector2.ONE, extent)
	return Rect2(mn, mx - mn)


static func wall_geom(start: Vector3, axis_z: bool, thickness: float, span: Vector2, sill: float, height: float) -> Dictionary:
	var u := span.x + span.y * 0.5
	var v: float = start.y + sill + height * 0.5
	var t := thickness + 0.14
	if axis_z:
		return {"center": Vector3(start.x, v, start.z + u), "size": Vector3(t, height, span.y)}
	return {"center": Vector3(start.x + u, v, start.z), "size": Vector3(span.y, height, t)}


static func room_wall_geom(origin: Vector3, size: Vector3, face: String, span: Vector2, sill: float, height: float) -> Dictionary:
	var u := span.x + span.y * 0.5
	var v: float = origin.y + sill + height * 0.5
	match face:
		"n":
			return {"center": Vector3(origin.x + u, v, origin.z), "size": Vector3(span.y, height, 0.34)}
		"s":
			return {"center": Vector3(origin.x + u, v, origin.z + size.z), "size": Vector3(span.y, height, 0.34)}
		"w":
			return {"center": Vector3(origin.x, v, origin.z + u), "size": Vector3(0.34, height, span.y)}
		_:
			return {"center": Vector3(origin.x + size.x, v, origin.z + u), "size": Vector3(0.34, height, span.y)}


static func plate_geom(origin: Vector3, plane_y: float, rect: Rect2) -> Dictionary:
	return {
		"center": Vector3(
			origin.x + rect.position.x + rect.size.x * 0.5,
			plane_y,
			origin.z + rect.position.y + rect.size.y * 0.5,
		),
		"size": Vector3(rect.size.x, 0.4, rect.size.y),
	}


## Plate cuts: stairwell for decks/floors; hole type allowed for ceiling voids.
static func plate_opening_type(requested: String, face: String) -> String:
	if face == "ceiling" and requested == StructurePlan.OPENING_HOLE:
		return StructurePlan.OPENING_HOLE
	return StructurePlan.OPENING_STAIRWELL
