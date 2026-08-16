extends SceneTree

## SCRATCH PROBE (leading underscore — not a gate unit).
##
##   xvfb-run -a --server-args="-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy \
##     --script res://tests/_ferry_seal_probe.gd
##
## `critic_ferry` reports ZERO enclosed volume. Two candidate holes were measured
## in its roof and this decides WHICH ONE un-rooms the saloon, by patching each
## in isolation — REALITY §4e, vary one input:
##
##   A. THE RAKE WEDGE. `wall_panel` 3 rakes +4 (0.500 m) across the saloon front
##      and roof step 26 stands on the wall's FOOT line with no eave, so the top
##      0.500 m of that front is open sky for the wall's whole 4.0 m run.
##   B. THE MISSING TILE. The roof steps cover z 6.0..8.0 and the main roof starts
##      at z 8.5. Cell 16 carries nothing: a 0.5 m slot the full 9 m beam.
##
## Prints `has_cabin / cabins / area` for the fixture as shipped and for each
## patch, so the answer is a table and not an argument.

const PO := preload("res://scripts/ship/plan_outfit.gd")


func _initialize() -> void:
	PieceKit.ensure_loaded()
	var doc: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://resources/data/structures/critic_ferry.json")
	) as Dictionary
	_row("as shipped", doc)
	_row("A. front eave only", _patch(doc, true, false))
	_row("B. missing tile only", _patch(doc, false, true))
	_row("A + B", _patch(doc, true, true))
	_flood(_patch(doc, true, true))
	quit(0)


## Where the sky still gets in, on PlanOutfit's own raster. `X` is air the flood
## never reached, `O` is air it did, `#` is solid, at PROBE_Y.
func _flood(doc: Dictionary) -> void:
	var plan := StructurePlan.from_dict(doc)
	var boxes := StructureBaker.collect_colliders(
		PO._sealed_plan(StructureBaker.resolved(plan))
	)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for box_variant in boxes:
		var box := box_variant as Dictionary
		var centre: Vector3 = box["center"]
		var reach: Vector2 = PO._box_reach(box)
		lo = Vector2(minf(lo.x, centre.x - reach.x), minf(lo.y, centre.z - reach.y))
		hi = Vector2(maxf(hi.x, centre.x + reach.x), maxf(hi.y, centre.z + reach.y))
	lo -= Vector2(PO.CABIN_CELL_M, PO.CABIN_CELL_M)
	hi += Vector2(PO.CABIN_CELL_M, PO.CABIN_CELL_M)
	var w := int(ceil((hi.x - lo.x) / PO.CABIN_CELL_M)) + 1
	var h := int(ceil((hi.y - lo.y) / PO.CABIN_CELL_M)) + 1
	var solid := {}
	for box_variant in boxes:
		PO._paint_column_spans(box_variant as Dictionary, solid, lo, w, h)
	var air := {}
	var state := {}
	for key in solid.keys():
		var gaps: PackedFloat32Array = PO._air_intervals(solid[key] as PackedFloat32Array)
		air[key] = gaps
		var flags := PackedByteArray()
		flags.resize(gaps.size() / 2)
		state[key] = flags
	PO._flood_outside(air, state, w, h)
	print("A + B flood map at y = 1.0  (X sealed, O reached by the sky, # solid)")
	for z in h:
		var row := "z%7.2f " % (lo.y + (float(z) + 0.5) * PO.CABIN_CELL_M)
		for x in w:
			row += _glyph(air, state, z * w + x)
		print(row)


static func _glyph(air: Dictionary, state: Dictionary, key: int) -> String:
	if not air.has(key):
		return " "
	var gaps: PackedFloat32Array = air[key]
	var flags: PackedByteArray = state[key]
	for i in flags.size():
		if gaps[i * 2] <= 1.0 and gaps[i * 2 + 1] >= 1.0:
			return "O" if flags[i] != 0 else "X"
	return "#"


static func _patch(doc: Dictionary, eave: bool, tile: bool) -> Dictionary:
	var out := doc.duplicate(true)
	var pieces: Array = out["pieces"] as Array
	if eave:
		for placement_variant in pieces:
			var placement := placement_variant as Dictionary
			if int(placement.get("id", 0)) != 26:
				continue
			## One cell further outboard, one cell deeper: the eave the raked
			## front needs, drawn with the same piece at the same gauge.
			placement["cell"] = [6, 5, 11]
			(placement["params"] as Dictionary)["depth"] = 2
	if tile:
		pieces.append({
			"id": 900, "piece": "deck_tile", "cell": [1, 5, 16], "facing": 0,
			"params": {"span": 16, "depth": 1, "gauge": "deck"},
		})
		pieces.append({
			"id": 901, "piece": "deck_tile", "cell": [17, 5, 16], "facing": 0,
			"params": {"span": 2, "depth": 1, "gauge": "deck"},
		})
	return out


func _row(label: String, doc: Dictionary) -> void:
	var plan := StructurePlan.from_dict(doc)
	var report := PO.enclosure(plan)
	print("%-22s cabin %-5s  cabins %d  area %6.1f m2  y %.2f..%.2f  %s" % [
		label, str(bool(report.get("cabin", false))), int(report.get("cabins", 0)),
		float(report.get("area_m2", 0.0)), float(report.get("floor_y", 0.0)),
		float(report.get("roof_y", 0.0)), str(report.get("why", "")),
	])
