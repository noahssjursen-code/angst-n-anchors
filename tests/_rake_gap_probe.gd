extends SceneTree

## SCRATCH PROBE (leading underscore — not a gate unit).
##
##   xvfb-run -a --server-args="-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy \
##     --script res://tests/_rake_gap_probe.gd -- [fixtures|sweep|both]
##
## WHAT IT MEASURES, and it is deliberately not "is rake a multiple of 4".
##
## A raked wall's TOP EDGE stands `rake * 0.125 m` outboard of its foot. A
## `deck_tile`'s edges land only on the 0.5 m node lattice (its `lift` moves it
## in Y, never in Z). So a roof edge is FLUSH with a raked wall top only at
## rake multiples of 4 — but flush is not the property anybody needs. The
## property is that the weather stays out, and a roof that OVERHANGS the wall
## top seals just as well. The kit's own `deck_tile` text calls that overhang the
## EAVE.
##
## So this measures the thing itself, on the baker's own collider boxes (the
## drawing, REALITY §3b):
##
##   for each station along a wall piece's top edge, take the interior air 0.15 m
##   inboard of the plate and 0.15 m below the top edge, and cast UP. If solid is
##   overhead, that station is roofed and sealed. If not, step inboard until
##   something IS overhead: that distance is how far the roof falls short — a
##   wedge of open sky at the wall head. If nothing is overhead within
##   `SCAN_MAX_M`, the wall is not roofed at all (a bulwark), which is not this
##   defect.
##
## Reported per wall: `short_m`, the worst shortfall over its stations.

const PO := preload("res://scripts/ship/plan_outfit.gd")

const WALL_PIECES: Array[String] = ["wall_panel", "wall_glazed", "corner_45"]
## How far inboard of the plate, and how far below the top edge, the interior
## sample sits. 0.15 m clears the plate's own 0.05 m half-thickness and the
## stepped-box slop with room to spare, and is well under the 0.5 m lattice step
## this is measuring against.
const INSET_M := 0.0
const DROP_M := 0.05
const SCAN_STEP_M := 0.0125
## Flush within this is flush: the roof edge and the wall top are two floats
## computed by different expressions and a boundary sample is a coin toss.
const FLUSH_M := 0.02
const SCAN_MAX_M := 2.0
const STATIONS: int = 9


func _initialize() -> void:
	PieceKit.ensure_loaded()
	var mode := "both"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		mode = str(args[0])
	if mode == "fixtures" or mode == "both":
		_fixtures()
	if mode == "sweep" or mode == "both":
		_sweep()
	quit(0)


# ── The measurement ─────────────────────────────────────────────────────────

## Boxes of the sealed, resolved plan, minus the ones the named item ids drew.
static func _boxes_without(plan: StructurePlan, skip: Dictionary) -> Array:
	var out: Array = []
	for row_variant in StructureBaker.entity_colliders(plan):
		var row := row_variant as Dictionary
		if str(row["kind"]) == "item" and skip.has(int(row["id"])):
			continue
		out.append_array(row["boxes"] as Array)
	return out


## Is any box entirely above this point, and over it in plan?
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


## The plate of a placement whose top edge stands highest — `wall_glazed`'s first
## plate is its COAMING, and measuring a ribbon window's sill against the roof
## would have been a whole fixture's worth of phantom gaps.
static func _top_plate(placement: Dictionary) -> PackedVector3Array:
	var params: Dictionary = (
		placement.get("params", {}) as Dictionary
		if placement.get("params") is Dictionary else {}
	)
	var resolved := PieceKit.resolve(str(placement.get("piece", "")), params)
	var best := PackedVector3Array()
	var best_y := -INF
	for step in (resolved["specs"] as Array).size():
		var corners := PieceKit.placed_corners(placement, step)
		if corners.size() != 4:
			continue
		var y := maxf(corners[2].y, corners[3].y)
		if y > best_y:
			best_y = y
			best = corners
	return best


## {short_m, roofed_stations, open_stations, worst_at}
static func _wall_shortfall(
	boxes: Array, corners: PackedVector3Array, facing: float
) -> Dictionary:
	var inboard := Basis.from_euler(
		Vector3(0.0, deg_to_rad(facing), 0.0), EULER_ORDER_YXZ
	) * Vector3(0.0, 0.0, 1.0)
	var top_a := corners[2]
	var top_b := corners[3]
	var worst := 0.0
	var worst_at := Vector3.ZERO
	var roofed := 0
	var open := 0
	for i in STATIONS:
		## 0.15..0.85 of the run: the ends belong to the corner pieces butted
		## against them, whose boxes would answer for the roof.
		var t := 0.15 + 0.7 * (float(i) + 0.5) / float(STATIONS)
		var top := top_a.lerp(top_b, t)
		var base := top + inboard * INSET_M + Vector3(0.0, -DROP_M, 0.0)
		var found := -1.0
		var d := 0.0
		while d <= SCAN_MAX_M:
			if _solid_above(boxes, base + inboard * d):
				found = d
				break
			d += SCAN_STEP_M
		if found < 0.0:
			open += 1
			continue
		if found <= FLUSH_M:
			roofed += 1
			continue
		if found > worst:
			worst = found
			worst_at = top
	return {
		"short_m": worst, "roofed": roofed, "open": open, "worst_at": worst_at,
	}


# ── Fixtures ────────────────────────────────────────────────────────────────

func _fixtures() -> void:
	print("=== AUTHORED FIXTURES: how far short of each raked wall top the roof stops ===")
	print("fixture                    walls  rake!=0  wedges  worst_short_m  where")
	var dir := DirAccess.open("res://resources/data/structures")
	var names := dir.get_files()
	names.sort()
	for name in names:
		if not name.ends_with(".json"):
			continue
		var stem := name.get_basename()
		var parsed: Variant = JSON.parse_string(
			FileAccess.get_file_as_string("res://resources/data/structures/%s" % name)
		)
		if not (parsed is Dictionary):
			continue
		var plan := StructurePlan.from_dict(parsed as Dictionary)
		if plan.pieces.is_empty():
			continue
		_report_plan(stem, plan)


func _report_plan(stem: String, plan: StructurePlan) -> void:
	var sealed := PO._sealed_plan(StructureBaker.resolved(plan))
	## The id each placement's plates were handed, replaying resolve_document.
	var next_id := 1
	for item_variant in plan.items:
		if item_variant is Dictionary:
			next_id = maxi(next_id, int((item_variant as Dictionary).get("id", 0)) + 1)
	var walls := 0
	var raked := 0
	var wedges := 0
	var worst := 0.0
	var worst_line := ""
	for placement_variant in plan.pieces:
		var placement := placement_variant as Dictionary
		var piece_id := str(placement.get("piece", ""))
		var result := PieceKit.resolve_placement(placement, next_id)
		var own := {}
		for item_variant in result["items"] as Array:
			own[int((item_variant as Dictionary)["id"])] = true
		next_id = int(result["next_id"])
		if not WALL_PIECES.has(piece_id):
			continue
		walls += 1
		var params: Dictionary = (
			placement.get("params", {}) as Dictionary
			if placement.get("params") is Dictionary else {}
		)
		var rake := absf(float(params.get("rake", params.get("rake_a", 0))))
		rake = maxf(rake, absf(float(params.get("rake_b", 0))))
		if rake == 0.0:
			continue
		raked += 1
		var corners := _top_plate(placement)
		if corners.size() != 4:
			continue
		var boxes := _boxes_without(sealed, own)
		var short := _wall_shortfall(
			boxes, corners, float(placement.get("facing", 0))
		)
		var d := float(short["short_m"])
		if d <= 0.0:
			continue
		## A WEDGE is a roof edge standing between the wall's own top line and its
		## own foot line — the roof is over this wall and stops short of its head.
		## Further inboard than the foot and the roof is not this wall's roof at
		## all: that is an open deck beside a deckhouse, not this defect.
		var lean := rake * 0.125
		if d > lean + 0.001:
			continue
		wedges += 1
		print("    WEDGE %-11s #%-4s rake %+3d  lean %.3f m  roof stops %.3f m inboard"
			% [piece_id, str(placement.get("id", "?")), int(rake), lean, d]
			+ "  (%d/%d stations open) at %s" % [
				int(short["open"]) + STATIONS - int(short["roofed"]) - int(short["open"]),
				STATIONS, str(short["worst_at"])
			])
		if d > worst:
			worst = d
			worst_line = "%s#%s rake %d" % [
				piece_id, str(placement.get("id", "?")), int(rake)
			]
	print("%-26s %5d  %7d  %6d  %13.3f  %s" % [
		stem, walls, raked, wedges, worst, worst_line
	])


# ── The parameter sweep ─────────────────────────────────────────────────────

## A minimal four-wall deckhouse with one roof tile, built entirely out of
## placements — nothing hand-authored, exactly what a player would put down.
static func _ring_doc(
	span_a: int, span_b: int, height: int, head: int, rake: int, eave: int
) -> Dictionary:
	var eighths := height * 4 + head
	var level := int(round(float(eighths) / 4.0))
	var lift := eighths - level * 4
	var pieces: Array = []
	var walls := [
		[Vector3i(0, 0, 0), 0, span_a],
		[Vector3i(span_a, 0, 0), 270, span_b],
		[Vector3i(span_a, 0, span_b), 180, span_a],
		[Vector3i(0, 0, span_b), 90, span_b],
	]
	var id := 1
	for row in walls:
		var cell: Vector3i = row[0]
		pieces.append({
			"id": id,
			"piece": "wall_panel",
			"cell": [cell.x, cell.y, cell.z],
			"facing": row[1],
			"params": {
				"span": row[2], "height": height, "head": head, "rake": rake,
				"opening": "door" if id == 1 else "none",
			},
		})
		id += 1
	pieces.append({
		"id": id,
		"piece": "deck_tile",
		"cell": [-eave, level, -eave],
		"facing": 0,
		"params": {
			"span": span_a + 2 * eave, "depth": span_b + 2 * eave, "lift": lift,
		},
	})
	return {
		"version": 1, "hull_id": "hull_28x10", "name": "ring",
		"walls": [], "decks": [], "stairs": [], "edges": [], "items": [],
		"pieces": pieces,
	}


func _sweep() -> void:
	print("")
	print("=== SWEEP: a four-wall ring with one roof tile, over the whole rake set ===")
	print("A `-` is sealed (roof reaches the wall top). A number is the shortfall in metres.")
	print("")
	var header := "                  |"
	for rake in range(-8, 9):
		header += "%7d" % rake
	print("A. rake x eave, at height 5, head 0, a 4 x 4 cell ring")
	print(header)
	for eave in [0, 1, 2, 3]:
		var row := "eave %d (%.2f m)   |" % [eave, float(eave) * 0.5]
		for rake in range(-8, 9):
			row += "%7s" % _ring_short(4, 4, 5, 0, rake, eave)
		print(row)
	print("")
	## REALITY §4d — vary ONE input. If height, head or span moved this answer the
	## constraint would not be a plan-space one, and every row below would differ.
	print("B. does anything but rake and eave move it? eave 1 throughout")
	print(header)
	for variant in [
		[4, 4, 2, 0], [4, 4, 3, 0], [4, 4, 5, 0], [4, 4, 6, 0],
		[4, 4, 5, 1], [4, 4, 5, 3], [4, 4, 5, 7],
		[2, 2, 5, 0], [8, 6, 5, 0], [8, 8, 5, 0], [6, 4, 3, 5],
	]:
		var row := "%-17s|" % ("%d x %d  h%d hd%d" % [
			variant[0], variant[1], variant[2], variant[3]
		])
		for rake in range(-8, 9):
			row += "%7s" % _ring_short(
				variant[0], variant[1], variant[2], variant[3], rake, 1
			)
		print(row)
	print("")


static func _ring_short(
	span_a: int, span_b: int, height: int, head: int, rake: int, eave: int
) -> String:
	var doc := _ring_doc(span_a, span_b, height, head, rake, eave)
	var plan := StructurePlan.from_dict(doc)
	var sealed := PO._sealed_plan(StructureBaker.resolved(plan))
	var next_id := 1
	var worst := 0.0
	var any := false
	for placement_variant in plan.pieces:
		var placement := placement_variant as Dictionary
		var result := PieceKit.resolve_placement(placement, next_id)
		var own := {}
		for item_variant in result["items"] as Array:
			own[int((item_variant as Dictionary)["id"])] = true
		next_id = int(result["next_id"])
		if str(placement.get("piece", "")) != "wall_panel":
			continue
		var corners := _top_plate(placement)
		if corners.size() != 4:
			continue
		any = true
		var short := _wall_shortfall(
			_boxes_without(sealed, own), corners, float(placement.get("facing", 0))
		)
		worst = maxf(worst, float(short["short_m"]))
	if not any:
		return "?"
	if worst <= 0.0:
		return "-"
	return "%.3f" % worst
