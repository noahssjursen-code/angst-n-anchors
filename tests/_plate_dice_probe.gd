extends SceneTree

## SCRATCH PROBE (leading underscore). WHERE THE BOXES GO.
##
## `_plate_phantom_probe` says the fleet's plate collider count grows as ~1/eps^2
## when PLATE_COLLIDER_STEP shrinks, which is a bad trade for a linear error. That
## only happens when BOTH parametric directions are being diced. This prints, per
## slab, the off-axis excursion each direction contributes and the step counts
## that fall out of it, so the blow-up can be attributed rather than guessed at.

const FIXTURES := [
	"res://resources/data/structures/demo_workboat.json",
	"res://resources/data/structures/probe_trawler_bulwark.json",
	"res://resources/data/structures/probe_piece_trawler.json",
	"res://resources/data/structures/probe_container_feeder.json",
]


func _initialize() -> void:
	for path in FIXTURES:
		_survey(str(path))
	quit()


func _survey(path: String) -> void:
	var doc := JSON.parse_string(FileAccess.get_file_as_string(path)) as Dictionary
	var plan := StructureBaker.resolved(StructurePlan.from_dict(doc))
	print("── %s ───────────────────────────" % path.get_file())
	var rows: Array = []
	var total := 0
	for item_variant in plan.items:
		var item := item_variant as Dictionary
		if StructureBaker.item_primitive(item) != "plate":
			continue
		var props := StructurePlan.item_props(item)
		if not bool(props.get("solid", true)):
			continue
		var corners := StructureBaker.plate_corners(props)
		if corners.size() != 4:
			continue
		var note := str(props.get("__is", "item %d" % int(item.get("id", -1))))
		var boxes := 0
		var worst_u := 0.0
		var worst_v := 0.0
		var worst_nu := 0
		var worst_nv := 0
		for slab_variant in StructureBaker.plate_slabs(props):
			var slab := slab_variant as Dictionary
			var quad := StructureBaker.plate_subquad(corners,
				float(slab["u0"]), float(slab["u1"]), float(slab["v0"]), float(slab["v1"]))
			var inv := Basis(Vector3.UP, deg_to_rad(StructureBaker._plate_yaw(quad))).transposed()
			var l: Array[Vector3] = []
			for p in quad:
				l.append(inv * p)
			var eu := _off(StructureBaker._max_abs(l[1] - l[0], l[2] - l[3]))
			var ev := _off(StructureBaker._max_abs(l[3] - l[0], l[2] - l[1]))
			var n: int = StructureBaker._plate_panel_colliders(
				corners, float(slab["thickness"]), Vector3.ZERO,
				float(slab["u0"]), float(slab["u1"]), float(slab["v0"]), float(slab["v1"])
			).size()
			boxes += n
			if n > worst_nu:
				worst_nu = n
				worst_nv = 1
				worst_u = eu
				worst_v = ev
		total += boxes
		rows.append([boxes, note.substr(0, 44), worst_nu, worst_nv, worst_u, worst_v])
	rows.sort_custom(func(a, b): return int(a[0]) > int(b[0]))
	for i in mini(8, rows.size()):
		var r: Array = rows[i]
		print("  %5d boxes  worst slab %d cells (nv col unused %d)  off_u=%.4f off_v=%.4f  %s"
			% [int(r[0]), int(r[2]), int(r[3]), float(r[4]), float(r[5]), str(r[1])])
	print("  total plate boxes %d over %d plates" % [total, rows.size()])


func _off(span: Vector3) -> float:
	var s := [absf(span.x), absf(span.y), absf(span.z)]
	s.sort()
	return float(s[0]) + float(s[1])
