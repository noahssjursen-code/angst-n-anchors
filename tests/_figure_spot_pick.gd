extends SceneTree

## SCRATCH PROBE (leading underscore, not gate-scored).
##
##   xvfb-run -a --server-args="-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy \
##     --script res://tests/_figure_spot_pick.gd
##
## Second pass of `_figure_deck_probe.gd`. That one found WHERE the open deck is;
## this one names WHAT is standing on each fixture — every piece placement's
## resolved box, and every authored plate's — and then scores a short list of
## candidate figure spots against the same colliders.
##
## Plan space, offset zero, y = 0 is the deck plane. Same space as FIGURE_SPOT.

const PieceKitScript := preload("res://scripts/construction/piece_kit.gd")

const FIG_RADIUS := 0.30
const FIG_LOW := 0.10
const FIG_HIGH := 1.80

const CANDIDATES := {
	"probe_piece_trawler": [
		Vector3(2.5, 0.0, 7.0),    ## the DEFAULT it was being shot at
		Vector3(5.0, 0.0, 2.5),    ## forecastle head — profile_port measured 0 px
		Vector3(1.35, 0.0, 12.5),  ## port side deck — stern_quarter measured 0 px
		Vector3(5.0, 0.77, 12.5),  ## hatch cover, at origin.y + thickness — FLOATS
		Vector3(5.0, 0.65, 12.5),  ## CHOSEN: on the fish hatch cover, centreline
		Vector3(5.0, 0.0, 7.0),    ## centreline working deck, abaft the breakwater apex
		Vector3(5.0, 0.0, 8.0),    ## the same, a metre further aft
		Vector3(8.65, 0.0, 12.5),  ## starboard side deck — the quarters shoot from +X
	],
	"probe_piece_house": [
		Vector3(4.5, 5.0, 20.5),  ## the wheelhouse roof, as authored today
		Vector3(4.5, 4.94, 20.5), ## the same, sat down on the roof's own top
		Vector3(4.5, 5.0, 19.0),  ## further forward, where the sloped roof is higher
		Vector3(5.0, 0.0, 3.0),   ## foredeck at deck level, for comparison
		Vector3(5.0, 0.0, 8.0),   ## main deck forward of the house
	],
	"probe_piece_tug": [
		Vector3(5.0, 0.0, 5.0),   ## CHOSEN (unchanged): foredeck, centreline
		Vector3(5.0, 0.0, 22.0),  ## the after towing deck
	],
	"probe_plate_deckhouse": [
		Vector3(2.5, 0.0, 7.0),   ## the DEFAULT it was being shot at
		Vector3(5.0, 0.0, 10.0),  ## CHOSEN: mid-foredeck, centreline
	],
	## The two shipped fixtures that are AUTHORED inside the breakwater. Same hull,
	## same walls[] and same decks[] as `probe_piece_trawler` — only the deckhouse
	## differs (hand-authored plates rather than pieces), and the deckhouse starts
	## at z = 17, well aft of every spot below.
	"probe_trawler_bulwark": [
		Vector3(2.5, 0.0, 7.0),    ## AUTHORED TODAY — inside the breakwater
		Vector3(5.0, 0.0, 7.0),    ## centreline working deck, abaft the breakwater apex
		Vector3(5.0, 0.0, 8.0),    ## the same, a metre further aft
		Vector3(1.35, 0.0, 12.5),  ## port side deck, between bulwark and hatch
		Vector3(8.65, 0.0, 12.5),  ## starboard side deck — the quarters shoot from +X
		Vector3(5.0, 0.65, 12.5),  ## on the fish hatch cover, as the piece trawler is
	],
	"probe_trawler_bow_bulwark": [
		Vector3(2.5, 0.0, 7.0),
		Vector3(5.0, 0.0, 7.0),
		Vector3(5.0, 0.0, 8.0),
		Vector3(1.35, 0.0, 12.5),
		Vector3(8.65, 0.0, 12.5),
		Vector3(5.0, 0.65, 12.5),
	],
	## EVERY REMAINING SHIPPED FIXTURE, AT THE SPOT IT IS AUTHORED AT. A capture-time
	## collider assertion is only affordable if it is also SATISFIED by the fleet it
	## is about to be turned on over, and "we fixed the three we looked at" is not
	## that claim (REALITY §3c — run it over every fixture, not the one you are
	## working on).
	"probe_ferry_catamaran": [Vector3(12.0, 0.0, 39.0)],
	"probe_ferry_catamaran_trim": [Vector3(12.0, 0.0, 39.0)],
	"probe_spar_kit": [Vector3(2.5, 0.0, 7.0)],
	"probe_sheer_bulwark": [Vector3(2.5, 0.0, 7.0)],
	"probe_sheer_bulwark_flat": [Vector3(2.5, 0.0, 7.0)],
	"demo_workboat": [Vector3(2.5, 0.0, 7.0)],
	## The forecastle spot, and the one entry in the table with a non-zero y that is
	## not standing on a `decks[]` plate — the fo'c'sle deck is an `items[]` plate.
	## ⚠ AUTHORED AT (11.0, 3.46, 10.0), AND THAT SPOT IS BOTH BLOCKED AND FLOATING.
	## It is 0.064 m above the fo'c'sle deck's own collider top (3.396) and its
	## shoulder is inside `items[]` 682, the WARPING DRUM — a 0.92 m tube standing
	## 1.55 m at (11.4, 10.6). Candidates for a replacement, all at the deck's
	## measured height rather than at the authored 3.46.
	"probe_container_feeder": [
		Vector3(11.0, 3.46, 10.0),    ## AUTHORED TODAY
		Vector3(11.0, 3.396, 10.0),   ## the same, sat down on the deck
		Vector3(9.5, 3.396, 10.0),    ## outboard of the windlass, port side
		Vector3(16.0, 3.396, 9.0),    ## centreline, forward of the winch group
		Vector3(16.0, 3.396, 13.0),   ## centreline, further aft on the fo'c'sle
		Vector3(13.0, 3.396, 14.0),   ## between the centreline and the port rail
		Vector3(19.0, 3.396, 14.0),   ## starboard of the centreline
		Vector3(22.0, 3.396, 10.0),   ## starboard side of the fo'c'sle
	],
	"critic_ferry": [Vector3(5.0, 0.0, 3.0)],
	"critic_yacht": [Vector3(5.0, 0.0, 3.0)],
	"critic_barge": [Vector3(5.0, 0.0, 2.0)],
}

const FIXTURES := [
	"res://resources/data/structures/probe_piece_trawler.json",
	"res://resources/data/structures/probe_piece_house.json",
	"res://resources/data/structures/probe_piece_tug.json",
	"res://resources/data/structures/probe_plate_deckhouse.json",
	"res://resources/data/structures/probe_trawler_bulwark.json",
	"res://resources/data/structures/probe_trawler_bow_bulwark.json",
	"res://resources/data/structures/demo_workboat.json",
	"res://resources/data/structures/probe_ferry_catamaran.json",
	"res://resources/data/structures/probe_ferry_catamaran_trim.json",
	"res://resources/data/structures/probe_spar_kit.json",
	"res://resources/data/structures/probe_sheer_bulwark.json",
	"res://resources/data/structures/probe_sheer_bulwark_flat.json",
	"res://resources/data/structures/probe_container_feeder.json",
	"res://resources/data/structures/critic_ferry.json",
	"res://resources/data/structures/critic_yacht.json",
	"res://resources/data/structures/critic_barge.json",
]


func _init() -> void:
	for path in FIXTURES:
		_look(path)
	quit()


func _look(path: String) -> void:
	var stem := path.get_file().get_basename()
	var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path)) as Dictionary
	var plan := StructurePlan.from_dict(doc)
	print("\n================ %s" % stem)

	## What is standing on this deck, one line per authored placement, at the box
	## its plates actually draw. This is the resolver's own output, not the
	## fixture's cell numbers.
	var placements: Array = doc.get("pieces", []) as Array
	if not placements.is_empty():
		print("  -- piece placements, resolved --")
		for placement_variant in placements:
			var placement := placement_variant as Dictionary
			var result := PieceKitScript.resolve_placement(placement, 1)
			var box: Variant = _items_box(result["items"] as Array)
			if box == null:
				continue
			var b := box as AABB
			print("   %-14s x %5.2f..%-5.2f  y %5.2f..%-5.2f  z %6.2f..%-6.2f  %s"
				% [str(placement.get("piece", "?")),
					b.position.x, b.position.x + b.size.x,
					b.position.y, b.position.y + b.size.y,
					b.position.z, b.position.z + b.size.z,
					str(placement.get("_is", ""))])
	if not plan.items.is_empty() and placements.is_empty() and plan.items.size() <= 200:
		print("  -- authored items --")
		for item_variant in plan.items:
			var item := item_variant as Dictionary
			var box: Variant = _items_box([item])
			if box == null:
				continue
			var b := box as AABB
			var props := StructurePlan.item_props(item)
			print("   id=%-4d %-8s x %5.2f..%-5.2f  y %5.2f..%-5.2f  z %6.2f..%-6.2f  %s"
				% [int(item.get("id", -1)), str(props.get("primitive", "?")),
					b.position.x, b.position.x + b.size.x,
					b.position.y, b.position.y + b.size.y,
					b.position.z, b.position.z + b.size.z,
					str(props.get("__is", ""))])

	var boxes: Array[AABB] = []
	var kinds := PackedStringArray()
	var raw: Array[Dictionary] = []
	for row_variant in StructureBaker.entity_colliders(plan, Vector3.ZERO):
		var row := row_variant as Dictionary
		for box_variant in row["boxes"] as Array:
			boxes.append(_bounds_of(box_variant as Dictionary))
			raw.append(box_variant as Dictionary)
			kinds.append("%s[%d] id=%d" % [str(row["kind"]), int(row["index"]), int(row["id"])])

	print("  -- candidate spots --")
	for spot_variant in CANDIDATES.get(stem, []) as Array:
		var spot := spot_variant as Vector3
		var blocker := _blocker(raw, boxes, kinds, spot)
		## `nearest` is measured against axis-aligned BOUNDS and is therefore a
		## lower bound, not a distance: a 45-degree wall's bounds reach 2 m past its
		## plating, so a spot 2.55 m clear of the breakwater still prints 0.00.
		## CLEAR/BLOCKED above is the exact answer; this column is a hint.
		print("   (%.2f, %.2f, %.2f)  %s  nearest(bounds)=%.2f m  sky=%s  underfoot=%s"
			% [spot.x, spot.y, spot.z,
				"CLEAR " if blocker.is_empty() else "BLOCKED by " + blocker,
				_clearance(boxes, spot), _open_sky(boxes, spot), _supported(boxes, spot)])


func _items_box(items: Array) -> Variant:
	var out := AABB()
	var first := true
	for item_variant in items:
		var item := item_variant as Dictionary
		var at_raw: Variant = item.get("at", [0, 0, 0])
		var at := Vector3.ZERO
		if at_raw is Array:
			var l := at_raw as Array
			at = Vector3(float(l[0]), float(l[1]), float(l[2]))
		elif at_raw is Vector3:
			at = at_raw as Vector3
		var yaw := deg_to_rad(float(item.get("yaw", 0.0)))
		var basis := Basis(Vector3.UP, yaw)
		var props: Dictionary = item.get("props", {}) as Dictionary
		var corners: Variant = props.get("corners")
		if not (corners is Array):
			continue
		for corner_variant in corners as Array:
			var c: Variant = corner_variant
			var world := at
			if c is Array:
				var cl := c as Array
				world = at + basis * Vector3(float(cl[0]), float(cl[1]), float(cl[2]))
			if first:
				out = AABB(world, Vector3.ZERO)
				first = false
			else:
				out = out.expand(world)
	if first:
		return null
	return out


func _bounds_of(box: Dictionary) -> AABB:
	var centre := box["center"] as Vector3
	var size := box["size"] as Vector3
	var basis := Basis(Vector3.UP, deg_to_rad(float(box.get("yaw_deg", 0.0))))
	var out := AABB()
	for i in 8:
		var local := Vector3(
			size.x * (0.5 if (i & 1) else -0.5),
			size.y * (0.5 if (i & 2) else -0.5),
			size.z * (0.5 if (i & 4) else -0.5)
		)
		var world := centre + basis * local
		if i == 0:
			out = AABB(world, Vector3.ZERO)
		else:
			out = out.expand(world)
	return out


## ⚠ THIS TEST USED TO BE `AABB.intersects` AGAINST `_bounds_of`, AND ON A YAWED
## WALL THAT IS NOT THE WALL — MEASURED 2026-08-16.
##
## `_bounds_of` rotates a collider's eight corners and takes their bounds, so the
## trawlers' 45-degree breakwater — 5.66 m long and 0.18 m thick — scores as a
## 4.12 x 4.12 m SQUARE. Every point in that square read BLOCKED. The centreline
## working deck at (5.0, 0, 7.0) is 1.84 m clear of the plating and this probe
## called it blocked; only (2.5, 0, 7.0) was genuinely inside, at 0.071 m off a
## centre line with a 0.09 m half-thickness. A spot search run through an
## instrument that fails a legal spot is a search that will land somewhere odd,
## which is REALITY §8: suspect the instrument before the subject.
##
## The body is sampled against each collider in ITS OWN yawed frame instead —
## the same maths `vessel_render_capture._guarded` already uses.
func _blocker(raw: Array[Dictionary], boxes: Array[AABB], kinds: PackedStringArray,
		at: Vector3) -> String:
	var y := FIG_LOW
	while y <= FIG_HIGH:
		for offset in [Vector3.ZERO, Vector3(FIG_RADIUS, 0, 0), Vector3(-FIG_RADIUS, 0, 0),
				Vector3(0, 0, FIG_RADIUS), Vector3(0, 0, -FIG_RADIUS)]:
			var p := at + Vector3(0.0, y, 0.0) + (offset as Vector3)
			for i in raw.size():
				if not _inside(raw[i], p):
					continue
				var b := boxes[i]
				return "%s box x %.2f..%.2f y %.2f..%.2f z %.2f..%.2f (bounds; yaw %.1f)" % [
					kinds[i], b.position.x, b.position.x + b.size.x,
					b.position.y, b.position.y + b.size.y,
					b.position.z, b.position.z + b.size.z,
					float(raw[i].get("yaw_deg", 0.0))]
		y += 0.10
	return ""


func _inside(box: Dictionary, p: Vector3) -> bool:
	var centre := box["center"] as Vector3
	var size := box["size"] as Vector3
	if p.y < centre.y - size.y * 0.5 or p.y > centre.y + size.y * 0.5:
		return false
	var flat := Vector3(p.x - centre.x, 0.0, p.z - centre.z)
	var yaw := float(box.get("yaw_deg", 0.0))
	if not is_zero_approx(yaw):
		flat = flat.rotated(Vector3.UP, -deg_to_rad(yaw))
	return absf(flat.x) <= size.x * 0.5 and absf(flat.z) <= size.z * 0.5


func _clearance(boxes: Array[AABB], at: Vector3) -> float:
	var best := 1e9
	for b in boxes:
		if b.position.y + b.size.y < at.y + 0.5:
			continue
		if b.position.y > at.y + FIG_HIGH:
			continue
		var dx := maxf(maxf(b.position.x - at.x, at.x - (b.position.x + b.size.x)), 0.0)
		var dz := maxf(maxf(b.position.z - at.z, at.z - (b.position.z + b.size.z)), 0.0)
		best = minf(best, sqrt(dx * dx + dz * dz))
	return best


## What the figure is standing ON: the HIGHEST collider top under its feet, and
## the gap between that surface and the sole of the capsule.
##
## `StructureBaker._plate_span` reads a deck's `origin.y` as the plate's TOP and
## hangs the thickness below it, so a hatch authored at `origin.y = 0.65` with
## `thickness = 0.12` has its walking surface at 0.65 and not at 0.77. Standing
## the figure on 0.65 + thickness floats it, and at three degrees of elevation
## the bulwark hides the feet, so nothing in a frame would ever show it. This is
## the only thing that can see it.
##
## `gap` positive = hovering. Negative = feet inside the surface.
func _supported(boxes: Array[AABB], at: Vector3) -> String:
	var best := -1e9
	for b in boxes:
		var top := b.position.y + b.size.y
		if top > at.y + 0.30:
			continue
		if at.x < b.position.x - 0.05 or at.x > b.position.x + b.size.x + 0.05:
			continue
		if at.z < b.position.z - 0.05 or at.z > b.position.z + b.size.z + 0.05:
			continue
		best = maxf(best, top)
	if best < -1.0e8:
		return "hull deck (nothing in the plan under it)"
	return "plan surface y=%.3f, gap %+.3f m" % [best, at.y - best]


func _open_sky(boxes: Array[AABB], at: Vector3) -> String:
	for b in boxes:
		if b.position.y < at.y + FIG_HIGH:
			continue
		if at.x < b.position.x - FIG_RADIUS or at.x > b.position.x + b.size.x + FIG_RADIUS:
			continue
		if at.z < b.position.z - FIG_RADIUS or at.z > b.position.z + b.size.z + FIG_RADIUS:
			continue
		return "ROOFED y=%.2f" % b.position.y
	return "open"
