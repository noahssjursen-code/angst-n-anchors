extends SceneTree

## SCRATCH PROBE — leading underscore so tools/gate.sh never runs it (REALITY §4).
##
## Resolves a piece-built fixture through the PRODUCTION path and dumps every
## plate in PLAN metres so the geometry can be analysed off-line:
##
##   PieceKit.resolve_document -> StructurePlan.from_dict -> plan.item_transform
##
## That is the same chain StructureBaker._item_layers walks (it calls
## plate_corners(spec) and _transformed(..., plan.item_transform(item))), so what
## comes out here is what the baker draws — not the dictionary in the middle.
##
##   xvfb-run -a --server-args="-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy \
##     --script res://tests/_piece_kit_critic_dump.gd -- <out.json> <fixture> ...

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		printerr("usage: -- <out.json> <fixture.json> ...")
		quit(2)
		return
	var out_path := args[0]
	var report: Dictionary = {}
	for i in range(1, args.size()):
		report[args[i]] = _dump(args[i])
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(report))
	f.close()
	print("wrote %s" % out_path)
	quit(0)


func _dump(path: String) -> Dictionary:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (raw is Dictionary):
		return {"error": "not a JSON object"}
	var doc := raw as Dictionary
	var placements: Array = doc.get("pieces", []) as Array if doc.get("pieces") is Array else []
	var resolved := PieceKit.resolve_document(doc)
	var out: Dictionary = {
		"errors": Array(resolved["errors"] as PackedStringArray),
		"warnings": Array(resolved["warnings"] as PackedStringArray),
		"placed": int(resolved["placed"]),
		"made": int(resolved["items"]),
		"authored_plates": PieceKit.authored_plate_count(doc),
		"placements": [],
		"plates": [],
	}
	for p_variant in placements:
		var p := p_variant as Dictionary
		## Item count per placement, so the plan-space plates below can be sliced
		## back to the placement that made them (resolve_document appends in order).
		var solo := PieceKit.resolve_placement(p, 1)
		out["placements"].append({
			"id": str(p.get("id", "?")), "piece": str(p.get("piece", "")),
			"cell": p.get("cell", []), "facing": int(p.get("facing", 0)),
			"params": p.get("params", {}), "_is": str(p.get("_is", "")),
			"footprint": _foot(p),
			"n_items": (solo["items"] as Array).size(),
			"solo_errors": Array(solo["errors"] as PackedStringArray),
		})
	var plan := StructurePlan.from_dict(resolved["doc"] as Dictionary)
	for item_variant in plan.items:
		var item := item_variant as Dictionary
		var props := StructurePlan.item_props(item)
		if StructureBaker.item_primitive(item) != "plate":
			continue
		var xform := plan.item_transform(item)
		var corners := StructureBaker.plate_corners(props)
		var world: Array = []
		for c in corners:
			var w: Vector3 = xform * c
			world.append([w.x, w.y, w.z])
		out["plates"].append({
			"id": int(item.get("id", -1)),
			"piece": str(props.get("__piece", "")),
			"corners": world,
			"thickness": StructureBaker.plate_thickness(props),
			"problem": StructureBaker.plate_problem(props),
			"openings": props.get("openings", []),
			"color": props.get("color", []),
		})
	return out


func _foot(p: Dictionary) -> Array:
	var v := PieceKit.footprint_cells(str(p.get("piece", "")), p.get("params", {}) as Dictionary)
	return [v.x, v.y, v.z]
