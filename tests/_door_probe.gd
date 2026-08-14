extends SceneTree

## SCRATCH PROBE — not a test. Answers three questions about the piece fixtures:
##  1. what each doorway's clear opening is, drawn and collided;
##  2. what collider a floor probe starts inside;
##  3. which drawn casing corners are loose, and by how much.

const FIXTURES := [
	"res://resources/data/structures/probe_piece_house.json",
	"res://resources/data/structures/probe_piece_trawler.json",
	"res://resources/data/structures/probe_piece_tug.json",
]

const INSIDE := {
	"probe_piece_house": [[5.0, 21.0], [3.6, 19.0], [6.4, 23.0], [5.0, 24.2]],
	"probe_piece_trawler": [[5.0, 21.0], [3.6, 19.0], [6.4, 23.0], [5.0, 24.2]],
	"probe_piece_tug": [[5.0, 12.0], [3.6, 10.5], [6.4, 14.5], [5.0, 15.2]],
}

var _boxes: Array = []
var _owner_of: Dictionary = {}


func _init() -> void:
	for path in FIXTURES:
		_dump(str(path))
	quit()


func _dump(path: String) -> void:
	var text := FileAccess.get_file_as_string(path)
	var layout := JSON.parse_string(text) as Dictionary
	var plan := StructurePlan.from_dict(layout)
	var res := StructureBaker.resolved(plan)
	_boxes = StructureBaker.collect_colliders(plan)
	_map(res)
	var stem := path.get_file().get_basename()
	print("\n=== %s  items=%d colliders=%d" % [stem, res.items.size(), _boxes.size()])

	for item_variant in res.items:
		var item := item_variant as Dictionary
		if StructureBaker.item_primitive(item) != "plate":
			continue
		var props := StructurePlan.item_props(item)
		var corners := StructureBaker._transformed(
			StructureBaker.plate_corners(props), res.item_transform(item)
		)
		if corners.size() != 4:
			continue
		var ref := StructureBaker.plate_ref_lengths(corners)
		for o_variant in StructureBaker.plate_openings(props, ref):
			var o := o_variant as Dictionary
			if float(o["sill"]) > 0.05:
				continue
			print("  [door] item %d %s ref %.3f x %.3f  off %.3f w %.3f sill %.3f h %.3f"
				% [int(item.get("id", -1)), str(props.get("__piece", "")).substr(0, 46),
				   ref.x, ref.y, float(o["off"]), float(o["w"]), float(o["sill"]), float(o["h"])])
			_scan_gap(corners, ref, o)

	for station_variant in INSIDE.get(stem, []) as Array:
		var st: Array = station_variant
		var lo := Vector3(float(st[0]) - 0.35, 0.6, float(st[1]) - 0.35)
		var hi := Vector3(float(st[0]) + 0.35, 2.4, float(st[1]) + 0.35)
		var hits := _overlapping(lo, hi)
		print("  [floor] capsule at (%.1f, %.1f) y 0.60..2.40 overlaps %s"
			% [float(st[0]), float(st[1]), "nothing" if hits.is_empty() else str(hits)])


## Walk the door's clear width at the standing figure's chest height and report
## the interval that no collider occupies.
func _scan_gap(corners: PackedVector3Array, ref: Vector2, o: Dictionary) -> void:
	var off := float(o["off"])
	var w := float(o["w"])
	var v := (float(o["sill"]) + float(o["h"]) * 0.5) / ref.y
	var free_lo := INF
	var free_hi := -INF
	var u := off - 0.20
	while u <= off + w + 0.20:
		var p := StructureBaker.plate_point(corners, clampf(u / ref.x, 0.0, 1.0), v)
		if _covering(p).is_empty():
			free_lo = minf(free_lo, u)
			free_hi = maxf(free_hi, u)
		u += 0.01
	print("    collider gap along the run: u %.3f .. %.3f  (%.3f m clear of %.3f drawn)"
		% [free_lo, free_hi, free_hi - free_lo, w])


func _covering(p: Vector3) -> Array:
	var out: Array = []
	for i in _boxes.size():
		var box := _boxes[i] as Dictionary
		var inv := Basis(Vector3.UP, deg_to_rad(float(box["yaw_deg"]))).transposed()
		var q := (inv * (p - (box["center"] as Vector3))).abs()
		var half := (box["size"] as Vector3) * 0.5
		if q.x <= half.x and q.y <= half.y and q.z <= half.z:
			out.append("#%d(item %s)" % [i, str(_owner_of.get(i, "?"))])
	return out


## Colliders whose own AABB (yaw applied to the box corners) overlaps [lo, hi].
func _overlapping(lo: Vector3, hi: Vector3) -> Array:
	var out: Array = []
	for i in _boxes.size():
		var box := _boxes[i] as Dictionary
		var basis := Basis(Vector3.UP, deg_to_rad(float(box["yaw_deg"])))
		var half := (box["size"] as Vector3) * 0.5
		var c := box["center"] as Vector3
		var blo := Vector3.INF
		var bhi := -Vector3.INF
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					var p := c + basis * Vector3(half.x * sx, half.y * sy, half.z * sz)
					blo = Vector3(minf(blo.x, p.x), minf(blo.y, p.y), minf(blo.z, p.z))
					bhi = Vector3(maxf(bhi.x, p.x), maxf(bhi.y, p.y), maxf(bhi.z, p.z))
		if blo.x > hi.x or bhi.x < lo.x or blo.y > hi.y or bhi.y < lo.y \
				or blo.z > hi.z or bhi.z < lo.z:
			continue
		out.append("#%d(item %s) y %.2f..%.2f" % [i, str(_owner_of.get(i, "?")), blo.y, bhi.y])
	return out


func _map(plan: StructurePlan) -> void:
	_owner_of = {}
	var index := 0
	var expanded := StructureBaker.expand(plan)
	for e in expanded["walls"] as Array:
		index += StructureBaker.wall_boxes(e as Dictionary).size()
	for e in expanded["decks"] as Array:
		index += StructureBaker.deck_boxes(e as Dictionary).size()
	for e in expanded["stairs"] as Array:
		index += StructureBaker.stair_boxes(e as Dictionary).size()
	for item_variant in plan.items:
		var item := item_variant as Dictionary
		var props := StructurePlan.item_props(item)
		var label := "%d %s" % [int(item.get("id", -1)),
			str(props.get("__piece", StructureBaker.item_primitive(item))).substr(0, 40)]
		var count: int = StructureBaker._item_colliders(plan, item, Vector3.ZERO).size()
		for _i in count:
			_owner_of[index] = label
			index += 1
