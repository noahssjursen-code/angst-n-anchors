class_name StructureStudioMath
extends RefCounted

## Pure helpers shared by Structure Studio tools (grid snap, footprints).
## Kept free of Node/UI dependencies so headless tests can exercise them.


static func wall_from_drag(a: Vector3, b: Vector3, base_y: float, grid_width := 0, grid_length := 0) -> Dictionary:
	var dx := absf(b.x - a.x)
	var dz := absf(b.z - a.z)
	var axis := "x" if dx >= dz else "z"
	var length := roundf(maxf(dx if axis == "x" else dz, 1.0))
	var start := Vector3(
		minf(a.x, b.x) if axis == "x" else roundf(a.x),
		base_y,
		minf(a.z, b.z) if axis == "z" else roundf(a.z),
	)
	start.x = roundf(start.x)
	start.z = roundf(start.z)
	if grid_width > 0 and grid_length > 0:
		if axis == "x":
			length = minf(length, maxf(float(grid_width) - start.x, 1.0))
		else:
			length = minf(length, maxf(float(grid_length) - start.z, 1.0))
	return {"axis": axis, "length": length, "start": start}


static func rect_from_drag(a: Vector3, b: Vector3, base_y: float, min_size: float) -> Dictionary:
	var min_pt := Vector3(roundf(minf(a.x, b.x)), base_y, roundf(minf(a.z, b.z)))
	var w := roundf(maxf(absf(b.x - a.x), min_size))
	var l := roundf(maxf(absf(b.z - a.z), min_size))
	return {"origin": min_pt, "width": w, "length": l}


static func clamp_origin(origin: Vector3, kind: String, dims: Vector3, grid_width: int, grid_length: int) -> Vector3:
	var clamped := origin
	clamped.y = maxf(clamped.y, 0.0)
	var max_x := float(grid_width)
	var max_z := float(grid_length)
	match kind:
		"wall":
			clamped.x = clampf(clamped.x, 0.0, max_x)
			clamped.z = clampf(clamped.z, 0.0, max_z)
		"room", "deck":
			clamped.x = clampf(clamped.x, 0.0, maxf(max_x - dims.x, 0.0))
			clamped.z = clampf(clamped.z, 0.0, maxf(max_z - dims.z, 0.0))
		_:
			clamped.x = clampf(clamped.x, 0.0, max_x)
			clamped.z = clampf(clamped.z, 0.0, max_z)
	return clamped


## Mirror an axis-aligned footprint across the plot midplane.
## `extent` is the size along the mirror axis (0 for a point-like wall normal).
static func mirror_origin_on_axis(origin: float, extent: float, grid_size: float) -> float:
	var mid := grid_size * 0.5
	return mid - (origin + extent - mid)


static func mirror_opening_offset(offset: float, width: float, run: float) -> float:
	return maxf(run - offset - width, 0.0)


## Rotate a plate cut 90° inside a W×L footprint. Returns {offset, size}.
static func rotate_plate_opening(offset: Vector2, hole: Vector2, width: float, length: float, degrees: int) -> Dictionary:
	if degrees > 0:
		return {
			"offset": Vector2(maxf(length - offset.y - hole.y, 0.0), offset.x),
			"size": Vector2(hole.y, hole.x),
		}
	return {
		"offset": Vector2(offset.y, maxf(width - offset.x - hole.x, 0.0)),
		"size": Vector2(hole.y, hole.x),
	}


static func rotate_cardinal_face(face: String, degrees: int) -> String:
	var map_pos := {"n": "e", "e": "s", "s": "w", "w": "n"}
	var map_neg := {"n": "w", "w": "s", "s": "e", "e": "n"}
	var face_map: Dictionary = map_pos if degrees > 0 else map_neg
	return str(face_map.get(face, face))
