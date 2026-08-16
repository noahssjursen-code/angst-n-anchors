extends SceneTree

## SCRATCH PROBE (leading underscore, not gate-scored).
##
##   xvfb-run -a --server-args="-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy \
##     --script res://tests/_figure_deck_probe.gd
##
## Answers "where on this fixture is there open deck for a 1.8 m figure" in
## metres rather than in pixels. It goes through the PRODUCTION path the capture
## rig bakes through — `StructureBaker.entity_colliders`, which calls
## `resolved()` first, so a piece placement is measured as the plates it becomes
## — and sweeps the deck rectangle for cells the figure's body does not
## intersect.
##
## Plan space, offset zero: x 0..beam, z 0..loa, y = 0 is the deck plane, which
## is exactly the space FIGURE_SPOT is authored in.

const FIXTURES := [
	"res://resources/data/structures/probe_piece_trawler.json",
	"res://resources/data/structures/probe_piece_house.json",
	"res://resources/data/structures/probe_piece_tug.json",
	"res://resources/data/structures/probe_plate_deckhouse.json",
]

## The rig's figure: a capsule of radius 0.22 centred at y 0.75 and a head of
## radius 0.14 at y 1.66. Swept as an upright box a little wider than the
## capsule, so "clear" means clear with a margin rather than touching.
const FIG_RADIUS := 0.30
const FIG_LOW := 0.10
const FIG_HIGH := 1.80

const STEP := 0.25


func _init() -> void:
	for path in FIXTURES:
		_survey(path)
	quit()


func _survey(path: String) -> void:
	var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path)) as Dictionary
	var plan := StructurePlan.from_dict(doc)
	var hull: Dictionary = doc.get("hull", {}) as Dictionary
	var loa := float(hull.get("loa_m", 0.0))
	var beam := float(hull.get("beam_m", 0.0))
	if loa <= 0.0 and plan.hull_id != "":
		var grid := HullRegistry.make_grid(plan.hull_id)
		if grid != null:
			loa = grid.half_loa * 2.0
			beam = grid.half_beam * 2.0
	print("\n=== %s  hull_id=%s  loa=%.2f beam=%.2f  deck rect x 0..%.2f z 0..%.2f"
		% [path.get_file(), plan.hull_id, loa, beam, beam, loa])
	print("    pieces=%d items=%d walls=%d decks=%d stairs=%d edges=%d"
		% [plan.pieces.size(), plan.items.size(), plan.walls.size(),
			plan.decks.size(), plan.stairs.size(), plan.edges.size()])

	var rows: Array = StructureBaker.entity_colliders(plan, Vector3.ZERO)
	## Every collider flattened to a world AABB ONCE. Rebuilding the eight
	## rotated corners inside the sweep made this probe unrunnable.
	var all: Array[AABB] = []
	var non_edge: Array[AABB] = []
	var by_kind := {}
	for row_variant in rows:
		var row := row_variant as Dictionary
		var kind := str(row["kind"])
		by_kind[kind] = int(by_kind.get(kind, 0)) + (row["boxes"] as Array).size()
		for box_variant in row["boxes"] as Array:
			var b := _bounds_of(box_variant as Dictionary)
			all.append(b)
			if kind != "edge":
				non_edge.append(b)
	print("    collider boxes: %s  total=%d" % [by_kind, all.size()])

	## The superstructure's own footprint, printed so the open deck round it can
	## be read off directly. Anything reaching above 0.6 m and not an edges[] run
	## (the bulwark) is structure a figure has to stand clear of.
	var struct_box := AABB()
	var have := false
	for b in non_edge:
		if b.position.y + b.size.y < 0.6:
			continue
		if have:
			struct_box = struct_box.merge(b)
		else:
			struct_box = b
			have = true
	if have:
		print("    superstructure (non-edge, top>0.6 m) x %.2f..%.2f  y %.2f..%.2f  z %.2f..%.2f"
			% [struct_box.position.x, struct_box.position.x + struct_box.size.x,
				struct_box.position.y, struct_box.position.y + struct_box.size.y,
				struct_box.position.z, struct_box.position.z + struct_box.size.z])
	## The bulwark, separately: it is what hides a figure in a 3-degree profile.
	var bul := AABB()
	var bul_have := false
	for row_variant in rows:
		var row := row_variant as Dictionary
		if str(row["kind"]) != "edge":
			continue
		for box_variant in row["boxes"] as Array:
			var b := _bounds_of(box_variant as Dictionary)
			if bul_have:
				bul = bul.merge(b)
			else:
				bul = b
				bul_have = true
	if bul_have:
		print("    edges[] runs (bulwark/rail) y %.2f..%.2f  x %.2f..%.2f  z %.2f..%.2f"
			% [bul.position.y, bul.position.y + bul.size.y,
				bul.position.x, bul.position.x + bul.size.x,
				bul.position.z, bul.position.z + bul.size.z])

	for level in [0.0, 2.5, 5.0]:
		_sweep(all, loa, beam, level)


## Every deck cell whose figure volume misses every collider, at one height.
func _sweep(boxes: Array[AABB], loa: float, beam: float, y0: float) -> void:
	var clear: Array = []
	var x := STEP
	while x < beam:
		var z := STEP
		while z < loa:
			if not _hits(boxes, Vector3(x, y0, z)):
				clear.append(Vector2(x, z))
			z += STEP
		x += STEP
	if clear.is_empty():
		print("    y=%.2f: NO clear cell anywhere on the deck rectangle" % y0)
		return
	var lo := Vector2(1e9, 1e9)
	var hi := Vector2(-1e9, -1e9)
	for p_variant in clear:
		var p := p_variant as Vector2
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	print("    y=%.2f: %d clear cells, bounding x %.2f..%.2f  z %.2f..%.2f"
		% [y0, clear.size(), lo.x, hi.x, lo.y, hi.y])
	## The single most open point: the clear cell furthest from any structure.
	var best := Vector2.ZERO
	var best_d := -1.0
	for p_variant in clear:
		var p := p_variant as Vector2
		var d := _clearance(boxes, Vector3(p.x, y0, p.y))
		if d > best_d:
			best_d = d
			best = p
	print("      most open: (%.2f, %.2f, %.2f)  nearest structure %.2f m   support: %s   sky: %s"
		% [best.x, y0, best.y, best_d,
			_supported(boxes, Vector3(best.x, y0, best.y)),
			_open_sky(boxes, Vector3(best.x, y0, best.y))])
	## Every clear cell on the centreline, so the fore-and-aft shape of the open
	## deck is readable rather than inferred from a bounding box.
	var mid := snappedf(beam * 0.5, STEP)
	var line := PackedStringArray()
	for p_variant in clear:
		var p := p_variant as Vector2
		if is_equal_approx(p.x, mid):
			line.append("%.2f" % p.y)
	if not line.is_empty():
		print("      clear z on the centreline x=%.2f: %s" % [mid, ", ".join(line)])


func _bounds_of(box: Dictionary) -> AABB:
	var centre := box["center"] as Vector3
	var size := box["size"] as Vector3
	var yaw := deg_to_rad(float(box.get("yaw_deg", 0.0)))
	## Yaw-aware: expand the eight rotated corners, so a diagonal wall is not
	## measured as its axis-aligned half.
	var basis := Basis(Vector3.UP, yaw)
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


func _hits(boxes: Array[AABB], at: Vector3) -> bool:
	var fig := AABB(
		Vector3(at.x - FIG_RADIUS, at.y + FIG_LOW, at.z - FIG_RADIUS),
		Vector3(FIG_RADIUS * 2.0, FIG_HIGH - FIG_LOW, FIG_RADIUS * 2.0)
	)
	for b in boxes:
		if b.intersects(fig):
			return true
	return false


## Horizontal distance from this spot to the nearest collider that rises above
## knee height. Bulwarks count — standing on the centreline beats standing in
## the scuppers — but a deck plate underfoot does not.
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


## Is there a collider directly under the figure's feet within 1 m? A spot with
## nothing under it may still be on deck — the HULL's own deck plate is not in
## the PLAN's colliders — so this is printed, never judged.
func _supported(boxes: Array[AABB], at: Vector3) -> String:
	for b in boxes:
		var top := b.position.y + b.size.y
		if top > at.y + 0.05 or top < at.y - 1.0:
			continue
		if at.x < b.position.x or at.x > b.position.x + b.size.x:
			continue
		if at.z < b.position.z or at.z > b.position.z + b.size.z:
			continue
		return "plan deck at y=%.2f" % top
	return "hull deck (nothing in the plan)"


func _open_sky(boxes: Array[AABB], at: Vector3) -> String:
	for b in boxes:
		if b.position.y < at.y + FIG_HIGH:
			continue
		if at.x < b.position.x - FIG_RADIUS or at.x > b.position.x + b.size.x + FIG_RADIUS:
			continue
		if at.z < b.position.z - FIG_RADIUS or at.z > b.position.z + b.size.z + FIG_RADIUS:
			continue
		return "ROOFED at y=%.2f" % b.position.y
	return "open"
