extends SceneTree

## SCRATCH PROBE — not a test. Dumps the resolved plate geometry of the piece
## fixtures so a walk sweep can be aimed at it.

const FIXTURES := [
	"res://resources/data/structures/probe_piece_house.json",
	"res://resources/data/structures/probe_piece_trawler.json",
	"res://resources/data/structures/probe_piece_tug.json",
]


func _init() -> void:
	for path in FIXTURES:
		_dump(str(path))
	quit()


func _dump(path: String) -> void:
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	var layout := parsed as Dictionary
	var plan := StructurePlan.from_dict(layout)
	print("\n=== %s  pieces=%d items=%d edges=%d walls=%d decks=%d"
		% [path.get_file(), plan.pieces.size(), plan.items.size(), plan.edges.size(),
		   plan.walls.size(), plan.decks.size()])
	var res := StructureBaker.resolved(plan)
	print("  resolved items: %d" % res.items.size())
	var lo := Vector3.INF
	var hi := -Vector3.INF
	for item_variant in res.items:
		var item := item_variant as Dictionary
		if StructureBaker.item_primitive(item) != "plate":
			continue
		var props := StructurePlan.item_props(item)
		var xf := res.item_transform(item)
		var corners := StructureBaker.plate_corners(props)
		var world := PackedVector3Array()
		for c in corners:
			world.append(xf * c)
		var blo := world[0]
		var bhi := world[0]
		for w in world:
			blo = Vector3(minf(blo.x, w.x), minf(blo.y, w.y), minf(blo.z, w.z))
			bhi = Vector3(maxf(bhi.x, w.x), maxf(bhi.y, w.y), maxf(bhi.z, w.z))
		lo = Vector3(minf(lo.x, blo.x), minf(lo.y, blo.y), minf(lo.z, blo.z))
		hi = Vector3(maxf(hi.x, bhi.x), maxf(hi.y, bhi.y), maxf(hi.z, bhi.z))
		var ref := StructureBaker.plate_ref_lengths(corners)
		var openings := StructureBaker.plate_openings(props, ref)
		var op := ""
		for o_v in openings:
			var o := o_v as Dictionary
			op += " [off %.2f w %.2f sill %.2f h %.2f]" % [
				float(o["off"]), float(o["w"]), float(o["sill"]), float(o["h"])]
		print("  id %-4d %-52s x %.2f..%.2f y %.2f..%.2f z %.2f..%.2f%s" % [
			int(item.get("id", -1)), str(props.get("__piece", props.get("__is", "?"))).substr(0, 52),
			blo.x, bhi.x, blo.y, bhi.y, blo.z, bhi.z, op])
	print("  BOUNDS x %.2f..%.2f y %.2f..%.2f z %.2f..%.2f" % [lo.x, hi.x, lo.y, hi.y, lo.z, hi.z])
	print("  colliders: %d" % StructureBaker.collect_colliders(plan).size())
