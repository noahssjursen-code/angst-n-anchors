extends SceneTree

## SCRATCH PROBE (leading underscore — not a gate unit).
##
##   xvfb-run -a --server-args="-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy \
##     --script res://tests/_ferry_roof_probe.gd -- <fixture_stem>
##
## `PlanOutfit.enclosure` reports that `critic_ferry` closes NO volume at all,
## which is not the same claim as "a sealed saloon with no door". This runs
## PlanOutfit's OWN raster (its statics, not a second copy of them) and prints a
## plan of the result at waist height: `X` is air the sky cannot reach, `O` is
## air the flood got into, `#` is solid. A hole in the saloon shows up as `O`
## inside the wall ring.

const PO := preload("res://scripts/ship/plan_outfit.gd")
const PROBE_Y := 1.0


func _initialize() -> void:
	var stem := "critic_ferry"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		stem = str(args[0])
	var path := "res://resources/data/structures/%s.json" % stem
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	var plan := StructurePlan.from_dict(parsed as Dictionary)
	var resolved := StructureBaker.resolved(plan)
	var boxes := StructureBaker.collect_colliders(PO._sealed_plan(resolved))
	print("%s: %d collider boxes (doors and windows filled back in)" % [stem, boxes.size()])

	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for b_v in boxes:
		var b := b_v as Dictionary
		var c: Vector3 = b["center"]
		var reach: Vector2 = PO._box_reach(b)
		lo = Vector2(minf(lo.x, c.x - reach.x), minf(lo.y, c.z - reach.y))
		hi = Vector2(maxf(hi.x, c.x + reach.x), maxf(hi.y, c.z + reach.y))
	lo -= Vector2(PO.CABIN_CELL_M, PO.CABIN_CELL_M)
	hi += Vector2(PO.CABIN_CELL_M, PO.CABIN_CELL_M)
	var w := int(ceil((hi.x - lo.x) / PO.CABIN_CELL_M)) + 1
	var h := int(ceil((hi.y - lo.y) / PO.CABIN_CELL_M)) + 1
	var solid := {}
	for b_v in boxes:
		PO._paint_column_spans(b_v as Dictionary, solid, lo, w, h)
	var air := {}
	var state := {}
	for key in solid.keys():
		var gaps: PackedFloat32Array = PO._air_intervals(solid[key] as PackedFloat32Array)
		air[key] = gaps
		var flags := PackedByteArray()
		flags.resize(gaps.size() / 2)
		state[key] = flags
	PO._flood_outside(air, state, w, h)

	print("  raster %d x %d cells of %.2f m; x %.2f..%.2f  z %.2f..%.2f"
		% [w, h, PO.CABIN_CELL_M, lo.x, hi.x, lo.y, hi.y])
	print("  one char per cell in x, every other row in z. X=sealed  O=open  #=solid")
	var header := "         "
	for x in w:
		header += "%d" % (int(floor(lo.x + (float(x) + 0.5) * PO.CABIN_CELL_M)) % 10)
	print(header)
	for z in range(0, h, 1):
		var row := "z%7.2f " % (lo.y + (float(z) + 0.5) * PO.CABIN_CELL_M)
		for x in w:
			row += _glyph(air, state, z * w + x)
		print(row)

	## Every enclosed group, including the ones under the 1.2 m2 floor.
	var groups := []
	for key in air.keys():
		var flags: PackedByteArray = state[key]
		for i in flags.size():
			if flags[i] != 0:
				continue
			groups.append(PO._enclosed_group(air, state, w, h, int(key), i))
	groups.sort_custom(func(a, b): return float(a["area_m2"]) > float(b["area_m2"]))
	print("  %d enclosed pocket(s):" % groups.size())
	for i in mini(8, groups.size()):
		var g := groups[i] as Dictionary
		print("    %6.2f m2  y %.2f..%.2f" % [
			float(g["area_m2"]), float(g["floor_y"]), float(g["roof_y"])])
	quit()


func _glyph(air: Dictionary, state: Dictionary, key: int) -> String:
	var gaps: Variant = air.get(key, null)
	if gaps == null:
		return " "
	var spans: PackedFloat32Array = gaps
	var flags: PackedByteArray = state[key]
	for i in flags.size():
		if spans[i * 2] <= PROBE_Y and spans[i * 2 + 1] > PROBE_Y:
			return "O" if flags[i] != 0 else "X"
	return "#"
