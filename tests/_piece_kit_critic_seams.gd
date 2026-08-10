extends SceneTree

## SCRATCH PROBE — leading underscore, never a gate unit.
##
## Targeted attacks on the seam claim. Everything below goes through
## PieceKit.resolve_placement + PieceKit.placed_corners, which is the same pair
## tests/piece_kit_test.gd's own seam report walks, so a gap reported here is a
## gap that check would have to see if it were pointed at the case.

const SHELL := ["wall_panel", "wall_glazed", "corner_45"]
const EPS := 1e-4


func _initialize() -> void:
	_concave()
	_chained_facet_rake()
	_back_to_back()
	_three_rings_meet()
	_corner_extremes()
	quit(0)


func _edges(p: Dictionary) -> Dictionary:
	var res := PieceKit.resolve_placement(p, 1)
	var items := res["items"] as Array
	if items.is_empty():
		return {}
	var of := Vector3.INF
	var oh := Vector3.INF
	var if_ := Vector3.INF
	var ih := Vector3.INF
	for step in items.size():
		var c := PieceKit.placed_corners(p, step)
		if c.size() != 4:
			continue
		if of == Vector3.INF or c[0].y < of.y: of = c[0]
		if oh == Vector3.INF or c[3].y > oh.y: oh = c[3]
		if if_ == Vector3.INF or c[1].y < if_.y: if_ = c[1]
		if ih == Vector3.INF or c[2].y > ih.y: ih = c[2]
	return {"out": [of, oh], "in": [if_, ih]}


func _gap(a: Array, b: Array) -> Vector2:
	return Vector2(a[0].distance_to(b[0]), a[1].distance_to(b[1]))


func _wall(cx: int, cy: int, cz: int, f: int, span: int, rake: int, h := 5) -> Dictionary:
	return {"id": "w", "piece": "wall_panel", "cell": [cx, cy, cz], "facing": f,
		"params": {"span": span, "height": h, "rake": rake}}


func _corner(cx: int, cy: int, cz: int, f: int, span: int, ra: int, rb: int, h := 5) -> Dictionary:
	return {"id": "c", "piece": "corner_45", "cell": [cx, cy, cz], "facing": f,
		"params": {"span": span, "height": h, "rake_a": ra, "rake_b": rb}}


# ── 1. THE CONCAVE CORNER ───────────────────────────────────────────────────
#
# structure_pieces.json: "Placed 180 degrees round it fills a concave corner
# instead, so there is no second inside-corner piece."
#
# The inside corner under test: an L-plan casing whose plan walks
#   ... -> +z along x = 12 (facing 270) -> +x along z = 46 (facing 0) -> ...
# The incoming wall ends with its OUT edge somewhere on x = 12; the outgoing
# wall starts with its IN edge on z = 46. A piece "fills" that corner only if
# ONE placement carries both edges. Every legal cell in a 5x5 neighbourhood is
# tried at every facing and every span, and the best total gap is reported.
func _concave() -> void:
	print("\n=== 1. THE CONCAVE CORNER (structure_pieces.json says corner_45 turned 180 fills it) ===")
	## incoming: a wall on x = 12 running +z, ending at cell (12, 45); rake -1
	var incoming := _wall(12, 0, 43, 270, 2, -1)
	## outgoing: a wall on z = 46 running +x, starting at cell (13, 46); rake 2
	var outgoing := _wall(13, 0, 46, 0, 3, 2)
	var need_in: Array = _edges(incoming)["out"]      # what the filler's IN must equal
	var need_out: Array = _edges(outgoing)["in"]      # what the filler's OUT must equal
	print("  incoming wall OUT foot %s head %s" % [str(need_in[0]), str(need_in[1])])
	print("  outgoing wall IN  foot %s head %s" % [str(need_out[0]), str(need_out[1])])
	var best := INF
	var best_desc := ""
	for f in [0, 90, 180, 270]:
		for span in [1, 2, 3, 4]:
			for dx in range(-4, 5):
				for dz in range(-4, 5):
					for ra in [-1, 0, 2]:
						for rb in [-1, 0, 2]:
							var c := _corner(12 + dx, 0, 46 + dz, f, span, ra, rb)
							var e := _edges(c)
							if e.is_empty():
								continue
							var g1 := _gap(e["in"], need_in)
							var g2 := _gap(e["out"], need_out)
							var total: float = g1.x + g1.y + g2.x + g2.y
							if total < best:
								best = total
								best_desc = ("cell (%d,0,%d) facing %d span %d rake_a %d rake_b %d"
									% [12 + dx, 46 + dz, f, span, ra, rb]
									+ "  IN foot %.4f head %.4f  OUT foot %.4f head %.4f"
									% [g1.x, g1.y, g2.x, g2.y])
	print("  best over 4 facings x 4 spans x 81 cells x 9 rake pairs = %d placements" % (4 * 4 * 81 * 9))
	print("  BEST TOTAL GAP %.4f m  at %s" % [best, best_desc])
	## and the same search for a wall_panel, in case a plain wall fills it
	var bw := INF
	var bw_desc := ""
	for f in [0, 90, 180, 270]:
		for span in [1, 2, 3, 4]:
			for dx in range(-4, 5):
				for dz in range(-4, 5):
					for rake in [-1, 0, 2]:
						var w := _wall(12 + dx, 0, 46 + dz, f, span, rake)
						var e := _edges(w)
						if e.is_empty():
							continue
						var t: float = (_gap(e["in"], need_in).x + _gap(e["in"], need_in).y
							+ _gap(e["out"], need_out).x + _gap(e["out"], need_out).y)
						if t < bw:
							bw = t
							bw_desc = "cell (%d,0,%d) facing %d span %d rake %d" % [12 + dx, 46 + dz, f, span, rake]
	print("  best wall_panel filler: %.4f m at %s" % [bw, bw_desc])
	## Control: the SAME search at a CONVEX corner, to prove the search works.
	var cin := _wall(12, 0, 43, 270, 2, -1)
	var cout := _wall(13, 0, 46, 0, 3, 2)
	## convex version: incoming runs +x on z = 46 up to x = 12, outgoing runs +z on x = 12
	cin = _wall(9, 0, 46, 0, 3, 2)
	cout = _wall(12, 0, 47, 270, 3, -1)
	var n_in: Array = _edges(cin)["out"]
	var n_out: Array = _edges(cout)["in"]
	var cb := INF
	var cb_desc := ""
	for f in [0, 90, 180, 270]:
		for span in [1, 2, 3, 4]:
			for dx in range(-4, 5):
				for dz in range(-4, 5):
					var c := _corner(12 + dx, 0, 46 + dz, f, span, -1, 2)
					var e := _edges(c)
					if e.is_empty():
						continue
					var t: float = (_gap(e["in"], n_in).x + _gap(e["in"], n_in).y
						+ _gap(e["out"], n_out).x + _gap(e["out"], n_out).y)
					if t < cb:
						cb = t
						cb_desc = "cell (%d,0,%d) facing %d span %d" % [12 + dx, 46 + dz, f, span]
	print("  CONTROL, same search at a CONVEX corner: %.4f m at %s" % [cb, cb_desc])


# ── 2. A RAKED 45 DEGREE FACET, WHICH THE PIECE ADVERTISES ──────────────────
#
# corner_45's own description: "at span 3 it is a fast ferry's bow facet".
# A ferry bow facet is longer than 2.83 m (span 4 chord) and it is RAKED. Two
# corner_45 chained make the run. What does the rake do at the joint?
func _chained_facet_rake() -> void:
	print("\n=== 2. A RAKED 45 DEGREE BOW FACET, CHAINED (the piece's own use case) ===")
	for rake in [1, 2, 3, 4]:
		## chain step: node B = node A + (span, 0, -span) cells at facing 0
		var a := _corner(10, 0, 20, 0, 4, rake, rake)
		var b := _corner(14, 0, 16, 0, 4, rake, rake)
		var g := _gap(_edges(a)["out"], _edges(b)["in"])
		print("  rake %d on both halves: foot gap %.4f m, HEAD GAP %.4f m  (0.25*sqrt(ra^2+rb^2) = %.4f)"
			% [rake, g.x, g.y, 0.25 * sqrt(float(rake * rake + rake * rake))])
	var a0 := _corner(10, 0, 20, 0, 4, 0, 0)
	var b0 := _corner(14, 0, 16, 0, 4, 0, 0)
	var g0 := _gap(_edges(a0)["out"], _edges(b0)["in"])
	print("  rake 0 on both halves: foot gap %.4f m, head gap %.4f m  <- the only setting that closes"
		% [g0.x, g0.y])
	## What that costs geometrically: a facet forced plumb in the middle while
	## its two ends carry the neighbours' rake.
	print("  so a bow facet longer than one piece (span 4 = 2.83 m of chord) is PLUMB at every")
	print("  interior joint; the surface deviates from a straight raked facet by 0.25*rake m there.")


# ── 3. A "CLOSED SHELL" THAT IS A FLAT FENCE ────────────────────────────────
#
# _seam_report matches every OUT to some unused IN and calls open == 0 a closed
# shell. It never asks whether the matching forms one cycle, whether the cycle
# encloses anything, or whether the pieces are coplanar.
func _back_to_back() -> void:
	print("\n=== 3. A SHELL THAT PASSES THE SEAM CHECK AND ENCLOSES NOTHING ===")
	var a := _wall(0, 0, 0, 0, 4, 0)
	var b := _wall(4, 0, 0, 180, 4, 0)
	var e_a := _edges(a)
	var e_b := _edges(b)
	var g1 := _gap(e_a["out"], e_b["in"])
	var g2 := _gap(e_b["out"], e_a["in"])
	print("  two wall_panels on ONE LINE, facing 0 and facing 180, rake 0:")
	print("    A.OUT vs B.IN  foot %.6f  head %.6f" % [g1.x, g1.y])
	print("    B.OUT vs A.IN  foot %.6f  head %.6f" % [g2.x, g2.y])
	print("    every OUT has a mate -> open == 0. Plan area enclosed: 0.000 m2.")
	var ca := PieceKit.placed_corners(a)
	var cb := PieceKit.placed_corners(b)
	print("    A corners %s" % str(ca))
	print("    B corners %s" % str(cb))


# ── 4. THREE RINGS MEETING AT ONE WALL ──────────────────────────────────────
func _three_rings_meet() -> void:
	print("\n=== 4. A T-JUNCTION: THREE WALL RUNS MEETING ON ONE LINE ===")
	## Two rooms sharing a bulkhead. The shared bulkhead has TWO neighbours on
	## one edge, and the kit's IN/OUT convention allows exactly one.
	var shared := _wall(8, 0, 10, 0, 4, 0)
	var left := _wall(4, 0, 10, 0, 4, 0)
	var branch := _wall(8, 0, 10, 270, 4, 0)
	print("  shared.IN  %s" % str(_edges(shared)["in"]))
	print("  left.OUT   %s  gap %.4f" % [str(_edges(left)["out"]), _gap(_edges(left)["out"], _edges(shared)["in"]).x])
	print("  branch.IN  %s  gap %.4f" % [str(_edges(branch)["in"]), _gap(_edges(branch)["in"], _edges(shared)["in"]).x])
	print("  two pieces want the same IN edge; the seam report's greedy matcher gives it to")
	print("  whichever it reaches first and calls the other open.")


# ── 5. EVERY PARAMETER AT AN EXTREME AT ONCE ────────────────────────────────
#
# piece_kit_test._extremes moves ONE numeric parameter off its default at a
# time. The interactions are never probed. This walks the full cross product
# for corner_45 (4 x 5 x 9 x 9 = 1620) and wall_glazed.
func _corner_extremes() -> void:
	print("\n=== 5. THE FULL CROSS PRODUCT (piece_kit_test._extremes moves ONE param at a time) ===")
	var refused := 0
	var drawn := 0
	var worst_ratio := 0.0
	var worst := ""
	for span in [1, 2, 3, 4]:
		for h in [2, 3, 4, 5, 6]:
			for ra in range(-4, 5):
				for rb in range(-4, 5):
					var r := PieceKit.resolve("corner_45",
						{"span": span, "height": h, "rake_a": ra, "rake_b": rb})
					if (r["specs"] as Array).is_empty():
						refused += 1
						continue
					drawn += 1
					var c := (r["specs"][0] as Dictionary)["corners"] as PackedVector3Array
					var foot := c[0].distance_to(c[1])
					var head := c[3].distance_to(c[2])
					var ratio := head / foot
					if ratio > worst_ratio:
						worst_ratio = ratio
						worst = "span %d height %d rake_a %d rake_b %d: chord %.3f m at the foot, %.3f m at the head" % [span, h, ra, rb, foot, head]
	print("  corner_45 full cross product: %d drawn, %d refused" % [drawn, refused])
	print("  widest flare: %s (x%.2f)" % [worst, worst_ratio])
	## The same for the trawler's own wheelhouse knuckle.
	var t := PieceKit.resolve("corner_45", {"span": 1, "height": 5, "rake_a": 4, "rake_b": -1})
	var tc := (t["specs"][0] as Dictionary)["corners"] as PackedVector3Array
	print("  probe_piece_house's wheelhouse knuckle (span 1, rake_a 4, rake_b -1): chord %.3f m at the deck, %.3f m at the eaves"
		% [tc[0].distance_to(tc[1]), tc[3].distance_to(tc[2])])

	var g_refused := 0
	var g_drawn := 0
	for span in [1, 2, 3, 4, 6, 8]:
		for h in [3, 4, 5, 6]:
			for rake in range(-4, 5):
				for sill in [1, 2, 3]:
					for band in [1, 2, 3]:
						for lights in [1, 2, 3, 4, 5, 6]:
							var r := PieceKit.resolve("wall_glazed", {
								"span": span, "height": h, "rake": rake,
								"sill": sill, "band": band, "lights": lights})
							if (r["specs"] as Array).is_empty():
								g_refused += 1
							else:
								g_drawn += 1
	print("  wall_glazed full cross product: %d drawn, %d refused" % [g_drawn, g_refused])
