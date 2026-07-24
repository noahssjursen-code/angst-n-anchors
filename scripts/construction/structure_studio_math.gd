class_name StructureStudioMath
extends RefCounted

## Pure helpers shared by Structure Studio tools (grid snap, footprints).
## Kept free of Node/UI dependencies so headless tests can exercise them.


static func wall_from_drag(a: Vector3, b: Vector3, base_y: float) -> Dictionary:
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
