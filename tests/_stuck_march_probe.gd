extends SceneTree

## SCRATCH PROBE. WHY DOES A WALL MARCH STILL BEGIN INSIDE SOMETHING?
##
## plan_interior_test starts every horizontal march START_OUT (0.60 m) outboard
## of the point where the plate's own surface reaches the figure's CENTRE height.
## A capsule is 1.8 m tall. On a plate that rakes 0.56 m over its height the
## surface at the capsule's crown stands a long way outboard of that point, so the
## question this settles is whether the remaining stuck marches begin inside a
## COLLIDER that is too fat, or inside the DRAWN PLATE itself — in which case the
## rig is starting the player in the wall and the geometry is innocent.
##
## Reports, per stuck station, the capsule's deepest penetration of the DRAWN
## mid-surface (positive = the capsule and the drawing overlap before the march
## has taken a step).

const CAPSULE_R := 0.35
const CAPSULE_H := 1.8
const STAND_EPS := 0.03
const START_OUT := 0.60

const CASES := [
	{
		"path": "res://resources/data/structures/demo_workboat.json",
		"plate": "lower tier, front",
		"us": [2.20, 5.50],
		"inside": Vector3(5.0, 0.0, 13.0),
	},
	{
		"path": "res://resources/data/structures/probe_trawler_bulwark.json",
		"plate": "lower tier, raked front",
		"us": [1.50, 2.30, 3.00, 3.90, 4.00],
		"inside": Vector3(5.0, 0.0, 21.5),
	},
]


func _initialize() -> void:
	for case_variant in CASES:
		_survey(case_variant as Dictionary)
	quit()


func _survey(case: Dictionary) -> void:
	var doc := JSON.parse_string(FileAccess.get_file_as_string(str(case["path"]))) as Dictionary
	var plan := StructureBaker.resolved(StructurePlan.from_dict(doc))
	print("── %s / %s" % [str(case["path"]).get_file(), str(case["plate"])])
	for item_variant in plan.items:
		var item := item_variant as Dictionary
		if StructureBaker.item_primitive(item) != "plate":
			continue
		var props := StructurePlan.item_props(item)
		var note := str(props.get("__is", ""))
		if not note.begins_with(str(case["plate"])) or note.contains("GLASS"):
			continue
		var corners := StructureBaker.plate_corners(props)
		var ref := StructureBaker.plate_ref_lengths(corners)
		var n := StructureBaker.plate_normal(corners)
		var flat := Vector3(n.x, 0.0, n.z).normalized()
		var mid := StructureBaker.plate_point(corners, 0.5, 0.5)
		if flat.dot(mid - (case["inside"] as Vector3)) < 0.0:
			flat = -flat
		print("  plate %s  ref %.2f x %.2f" % [note.substr(0, 46), ref.x, ref.y])
		for u_variant in case["us"] as Array:
			var u := float(u_variant)
			var centre_y := 0.08 + STAND_EPS + CAPSULE_H * 0.5
			var at := StructureBaker.plate_point(
				corners, u / ref.x, _v_at(corners, u / ref.x, centre_y))
			var start := at + flat * START_OUT
			## Deepest overlap of the capsule with the DRAWN mid-surface, over the
			## heights the capsule occupies. At height dy off centre the capsule's
			## half-width is the capsule profile, and the plate's own surface sits
			## `out` metres outboard of `at` along the horizontal normal.
			var worst := -INF
			var worst_y := 0.0
			for i in 61:
				var dy := (float(i) / 60.0 - 0.5) * CAPSULE_H
				var y := centre_y + dy
				var half_w := CAPSULE_R
				if absf(dy) > CAPSULE_H * 0.5 - CAPSULE_R:
					var t := (absf(dy) - (CAPSULE_H * 0.5 - CAPSULE_R)) / CAPSULE_R
					half_w = CAPSULE_R * sqrt(maxf(1.0 - t * t, 0.0))
				var here := StructureBaker.plate_point(
					corners, u / ref.x, _v_at(corners, u / ref.x, y))
				var out := (here - start).dot(flat)
				## Positive when the plate's surface reaches into the capsule.
				var pen := out + half_w
				if pen > worst:
					worst = pen
					worst_y = y
			print("    u=%.2f  capsule/mid-surface overlap %+.4f m at plan y %.2f  (%s)"
				% [u, worst, worst_y,
				   "STARTS IN THE DRAWING" if worst > 0.0 else "clear of the drawing"])
			_blame(plan, start, centre_y)


## Every collider box the start capsule actually overlaps, named by the entity it
## came from — the question "what IS that" the test's own message cannot answer.
func _blame(plan: StructurePlan, start: Vector3, centre_y: float) -> void:
	var lo := start + Vector3(0.0, -(CAPSULE_H * 0.5 - CAPSULE_R), 0.0)
	var hi := start + Vector3(0.0, CAPSULE_H * 0.5 - CAPSULE_R, 0.0)
	for entry_variant in _boxes_by_owner(plan):
		var entry := entry_variant as Dictionary
		var box := entry["box"] as Dictionary
		if _capsule_hits_box(lo, hi, CAPSULE_R, box):
			print("        overlaps %s  centre %s half %s yaw %.1f"
				% [str(entry["owner"]), str(box["center"]),
				   str((box["size"] as Vector3) * 0.5), float(box["yaw_deg"])])


func _boxes_by_owner(plan: StructurePlan) -> Array:
	var out: Array = []
	for item_variant in plan.items:
		var item := item_variant as Dictionary
		var props := StructurePlan.item_props(item)
		var owner := "%s #%d: %s" % [
			StructureBaker.item_primitive(item), int(item.get("id", -1)),
			str(props.get("__is", "")).substr(0, 40)]
		for box_variant in _item_boxes(plan, item):
			out.append({"owner": owner, "box": box_variant})
	for edge_variant in plan.edges:
		var edge := edge_variant as Dictionary
		for box_variant in StructureBaker.edge_collider_boxes(plan, edge):
			out.append({"owner": "edge #%d" % int(edge.get("id", -1)), "box": box_variant})
	return out


func _item_boxes(plan: StructurePlan, item: Dictionary) -> Array:
	var props := StructurePlan.item_props(item)
	if StructureBaker.item_primitive(item) == "plate":
		return StructureBaker.plate_colliders(
			props, StructureBaker.plate_corners(props), Vector3.ZERO)
	return StructureBaker._item_colliders(plan, item, Vector3.ZERO)


func _capsule_hits_box(lo: Vector3, hi: Vector3, radius: float, box: Dictionary) -> bool:
	var inv := Basis(Vector3.UP, deg_to_rad(float(box["yaw_deg"]))).transposed()
	var half := (box["size"] as Vector3) * 0.5
	var a := inv * (lo - (box["center"] as Vector3))
	var b := inv * (hi - (box["center"] as Vector3))
	## Sample the segment finely; exact enough to name a culprit.
	for i in 33:
		var p: Vector3 = a.lerp(b, float(i) / 32.0)
		var d := Vector3(
			maxf(absf(p.x) - half.x, 0.0),
			maxf(absf(p.y) - half.y, 0.0),
			maxf(absf(p.z) - half.z, 0.0))
		if d.length() < radius:
			return true
	return false


func _v_at(corners: PackedVector3Array, u: float, y: float) -> float:
	var lo := 0.0
	var hi := 1.0
	if StructureBaker.plate_point(corners, u, 0.0).y > StructureBaker.plate_point(corners, u, 1.0).y:
		lo = 1.0
		hi = 0.0
	for _i in 24:
		var m := (lo + hi) * 0.5
		if StructureBaker.plate_point(corners, u, m).y < y:
			lo = m
		else:
			hi = m
	return (lo + hi) * 0.5
