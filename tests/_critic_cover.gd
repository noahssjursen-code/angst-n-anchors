extends SceneTree

## SCRATCH PROBE (leading underscore — not a gate unit).
##
## piece_interior_test checks the EIGHT CORNERS of each drawn slab. A box fitted
## to a cell's corners contains that cell's bilinear patch, so corners are the
## right sample IF the emitter draws what plate_slabs enumerates and nothing
## else. This samples the drawn surface densely instead — the mid-surface grid
## `_append_slab` actually emits, both offset skins, and the skirt band between
## them — and reports the deepest escape in metres.
##
## It also counts, per piece, what plate_slabs enumerated against what
## plate_layers emitted, so a layer with no slab behind it would show up as a
## count mismatch rather than as a containment pass.

const SAMPLES := 9
const SKIRT := 5


func _init() -> void:
	for path in [
		"res://resources/data/structures/probe_piece_house.json",
		"res://resources/data/structures/probe_piece_trawler.json",
		"res://resources/data/structures/probe_piece_tug.json",
		"res://resources/data/structures/probe_plate_deckhouse.json",
	]:
		_run(path)
	quit()


func _run(path: String) -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		print("%s: not a plan" % path)
		return
	var plan := StructureBaker.resolved(StructurePlan.from_dict(parsed as Dictionary))
	var boxes := StructureBaker.collect_colliders(plan)
	var points := 0
	var loose := 0
	var deepest := 0.0
	var worst := Vector3.ZERO
	var layers_seen := 0
	var slabs_seen := 0
	var non_slab := 0
	for item_variant in plan.items:
		var item := item_variant as Dictionary
		if StructureBaker.item_primitive(item) != "plate":
			continue
		var props := StructurePlan.item_props(item)
		var corners := StructureBaker._transformed(
			StructureBaker.plate_corners(props), plan.item_transform(item)
		)
		if corners.size() != 4:
			continue
		slabs_seen += StructureBaker.plate_slabs(props).size()
		for layer_variant in StructureBaker.plate_layers(props, corners, int(item.get("id", -1))):
			var layer := layer_variant as Dictionary
			if str(layer.get("kind", "")) != "slab":
				non_slab += 1
				continue
			layers_seen += 1
			var quad := layer["quad"] as PackedVector3Array
			var half := StructureBaker.plate_normal(quad) * (float(layer["thickness"]) * 0.5)
			var segs := maxi(int(layer.get("segments", 1)), 1)
			var n := maxi(segs, SAMPLES)
			for j in n + 1:
				for i in n + 1:
					var mid := StructureBaker.plate_point(
						quad, float(i) / float(n), float(j) / float(n)
					)
					## Both skins and the skirt band between them: every point the
					## closed slab surface actually occupies along the normal.
					for k in SKIRT + 1:
						var t := lerpf(-1.0, 1.0, float(k) / float(SKIRT))
						var p := mid + half * t
						points += 1
						var d := _escape(p, boxes)
						if d > 0.0:
							loose += 1
							if d > deepest:
								deepest = d
								worst = p
	print("%s" % path.get_file())
	print("   %d plate items · %d slabs enumerated · %d slab layers drawn · %d non-slab layers"
		% [_plate_items(plan), slabs_seen, layers_seen, non_slab])
	print("   %d surface samples, %d outside every collider, deepest escape %.6f m at %v"
		% [points, loose, deepest, worst])


func _plate_items(plan: StructurePlan) -> int:
	var n := 0
	for item_variant in plan.items:
		if StructureBaker.item_primitive(item_variant as Dictionary) == "plate":
			n += 1
	return n


## 0.0 when the point is inside some box, otherwise how far outside the nearest
## one it is, in metres.
func _escape(point: Vector3, boxes: Array) -> float:
	var best := INF
	for box_variant in boxes:
		var box := box_variant as Dictionary
		var inv := Basis(Vector3.UP, deg_to_rad(float(box["yaw_deg"]))).transposed()
		var q := (inv * (point - (box["center"] as Vector3))).abs()
		var half := (box["size"] as Vector3) * 0.5
		var d := maxf(maxf(q.x - half.x, q.y - half.y), q.z - half.z)
		best = minf(best, d)
		if best <= 0.0:
			return 0.0
	return maxf(best, 0.0)
