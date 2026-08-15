extends SceneTree

## SCRATCH PROBE (leading underscore — the gate skips it in both lanes).
##
## Settles ONE claim, because it is now written into a comment in
## structure_plate_test and a comment is the softest artefact in a codebase:
## that the literal sample point (5.0, 4.82, 18.0) the old `_check_slope_is_followed`
## asserted to be "INSIDE the roof at its forward end" is NOT inside the roof at
## all — it is above the drawn slab, and the check was green only because the
## collider stood proud of what it wraps.
##
## Run against either baker; the DRAWN answer does not move and the SOLID one does.

const FIXTURE := "res://resources/data/structures/probe_plate_deckhouse.json"
const ID_ROOF := 109
const SAMPLE := Vector3(5.0, 4.82, 18.0)


func _initialize() -> void:
	var doc := JSON.parse_string(FileAccess.get_file_as_string(FIXTURE)) as Dictionary
	var plan := StructurePlan.from_dict(doc)
	for item_variant in plan.items:
		var item := item_variant as Dictionary
		if int(item.get("id", -1)) != ID_ROOF:
			continue
		var props := StructurePlan.item_props(item)
		var xform := plan.item_transform(item)
		var corners := PackedVector3Array()
		for point in StructureBaker.plate_corners(props):
			corners.append(xform * point)
		var thickness := StructureBaker.plate_thickness(props)
		## The drawn surface under the sample, found by walking the parameter that
		## runs fore-and-aft until the point's z is reached.
		var u := _u_at_z(corners, SAMPLE.z)
		var surface := StructureBaker.plate_point(corners, u, 0.5)
		var n := StructureBaker.plate_normal(corners)
		var top := surface.y + thickness * 0.5 * absf(n.y)
		print("roof at z=%.2f: drawn mid-surface y=%.4f, thickness %.3f, drawn top y=%.4f"
			% [SAMPLE.z, surface.y, thickness, top])
		print("sample y=%.3f stands %+.4f m above the drawn top" % [SAMPLE.y, SAMPLE.y - top])
		var boxes := StructureBaker.plate_colliders(props, corners, Vector3.ZERO)
		print("this baker: %d boxes for the roof, sample is %s"
			% [boxes.size(), "SOLID" if _inside_any(boxes, SAMPLE) else "open air"])
	quit()


func _u_at_z(corners: PackedVector3Array, z: float) -> float:
	var lo := 0.0
	var hi := 1.0
	if StructureBaker.plate_point(corners, 0.0, 0.5).z > StructureBaker.plate_point(corners, 1.0, 0.5).z:
		lo = 1.0
		hi = 0.0
	for _i in 40:
		var m := (lo + hi) * 0.5
		if StructureBaker.plate_point(corners, m, 0.5).z < z:
			lo = m
		else:
			hi = m
	return (lo + hi) * 0.5


func _inside_any(boxes: Array, p: Vector3) -> bool:
	for box_variant in boxes:
		var box := box_variant as Dictionary
		var inv := Basis(Vector3.UP, deg_to_rad(float(box.get("yaw_deg", 0.0)))).transposed()
		var local := inv * (p - (box["center"] as Vector3))
		var half := (box["size"] as Vector3) * 0.5
		if absf(local.x) <= half.x and absf(local.y) <= half.y and absf(local.z) <= half.z:
			return true
	return false
