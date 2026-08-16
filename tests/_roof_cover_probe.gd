extends SceneTree

## SCRATCH PROBE (leading underscore — not a gate unit).
##
##   xvfb-run -a --server-args="-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy \
##     --script res://tests/_roof_cover_probe.gd -- <stem> <y> [patch]
##
## A plan of what is OVER a deckhouse at height `y`. `#` means solid overhead,
## `.` means open sky. A wedge at a raked wall front and a missing roof tile look
## identical in an enclosure verdict (both are "closes nothing") and completely
## different here.

const PO := preload("res://scripts/ship/plan_outfit.gd")
const STEP := 0.25


func _initialize() -> void:
	PieceKit.ensure_loaded()
	var args := OS.get_cmdline_user_args()
	var stem := str(args[0]) if args.size() > 0 else "critic_ferry"
	var y := float(args[1]) if args.size() > 1 else 2.4
	var doc: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string(
			"res://resources/data/structures/%s.json" % stem
		)
	) as Dictionary
	if args.size() > 2 and str(args[2]) == "patch":
		doc = _patched(doc)
	var plan := StructurePlan.from_dict(doc)
	var boxes := StructureBaker.collect_colliders(PO._sealed_plan(StructureBaker.resolved(plan)))
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for box_variant in boxes:
		var box := box_variant as Dictionary
		var centre: Vector3 = box["center"]
		var reach: Vector2 = PO._box_reach(box)
		lo = Vector2(minf(lo.x, centre.x - reach.x), minf(lo.y, centre.z - reach.y))
		hi = Vector2(maxf(hi.x, centre.x + reach.x), maxf(hi.y, centre.z + reach.y))
	print("%s: %d boxes, overhead cover at y = %.2f  (x %.2f..%.2f, z %.2f..%.2f)"
		% [stem, boxes.size(), y, lo.x, hi.x, lo.y, hi.y])
	var header := "          "
	var x := lo.x
	while x <= hi.x:
		header += "%d" % (int(floor(x)) % 10)
		x += STEP
	print(header)
	var z := lo.y
	while z <= hi.y:
		var row := "z%8.2f " % z
		x = lo.x
		while x <= hi.x:
			row += "#" if _solid_above(boxes, Vector3(x, y, z)) else "."
			x += STEP
		print(row)
		z += STEP


static func _patched(doc: Dictionary) -> Dictionary:
	var out := doc.duplicate(true)
	var pieces: Array = out["pieces"] as Array
	for placement_variant in pieces:
		var placement := placement_variant as Dictionary
		if int(placement.get("id", 0)) != 26:
			continue
		placement["cell"] = [6, 5, 11]
		(placement["params"] as Dictionary)["depth"] = 2
	pieces.append({
		"id": 900, "piece": "deck_tile", "cell": [1, 5, 16], "facing": 0,
		"params": {"span": 16, "depth": 1, "gauge": "deck"},
	})
	pieces.append({
		"id": 901, "piece": "deck_tile", "cell": [17, 5, 16], "facing": 0,
		"params": {"span": 2, "depth": 1, "gauge": "deck"},
	})
	return out


static func _solid_above(boxes: Array, p: Vector3) -> bool:
	for box_variant in boxes:
		var box := box_variant as Dictionary
		var centre: Vector3 = box["center"]
		var size: Vector3 = box["size"]
		if centre.y - size.y * 0.5 < p.y - 0.02:
			continue
		var yaw := deg_to_rad(float(box.get("yaw_deg", 0.0)))
		var dx := p.x - centre.x
		var dz := p.z - centre.z
		var cs := cos(yaw)
		var sn := sin(yaw)
		if absf(dx * cs - dz * sn) > size.x * 0.5:
			continue
		if absf(dx * sn + dz * cs) > size.z * 0.5:
			continue
		return true
	return false
