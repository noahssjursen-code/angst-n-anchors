extends SceneTree

## Lane A. The structural piece kit: does it load, does it refuse what it should,
## and DOES A PIECE-BUILT SHELL ACTUALLY CLOSE.
##
##   xvfb-run -a --server-args="-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy \
##     --script res://tests/piece_kit_test.gd
##
## Nothing here measures whether a boat looks like a boat. That is a person's
## job and this project deleted a metric that tried (STATE.md, 2026-08-10). What
## is checked below all has a right answer:
##
##  1. THE SEAM CLAIM, and it is the one that matters. Every wall and corner
##     piece on the trawler has an OUT edge and an IN edge, and a closed shell is
##     a cycle where each piece's OUT is another piece's IN. The check walks all
##     39 of them in PLAN space — after the placement transform, not in the
##     comfortable local frame — and requires every edge to be matched to within
##     a tenth of a millimetre. A gap anywhere in the deckhouse is a hole you can
##     see daylight through, and it is exactly what a kit gets wrong.
##
##     Its negative control runs the same check over the same fixture with ONE
##     panel's rake moved one step, and requires it to go red. A seam check that
##     cannot fail is a rubber stamp, and this project spent a day removing one.
##
##  2. Values off a declared set are REFUSED and named, never clamped. Clamping
##     is how a player asks for a 7-cell panel and silently gets a 6.
##
##  3. Every piece, at EVERY combination of its choice parameters and at the ends
##     of its numeric ranges, resolves to plates StructureBaker will actually
##     draw — `plate_problem` is the baker's own degeneracy test and it is what
##     is asked, so a piece cannot be "valid" by a standard the baker rejects.
##
##  4. The strict fixture really is strict: `probe_piece_house.json` contains
##     ZERO hand-authored plate corners, and resolves to a plan that bakes.

const TestReport := preload("res://tests/support/test_report.gd")

const TRAWLER := "res://resources/data/structures/probe_piece_trawler.json"
const HOUSE := "res://resources/data/structures/probe_piece_house.json"
const REFERENCE := "res://resources/data/structures/probe_trawler_bulwark.json"

## A tenth of a millimetre. Two pieces on the same grid line at the same rake
## should agree to the bit; this is float-transform slack and nothing more.
const SEAM_EPSILON := 1e-4

## Pieces that form a shell. Decks and trim have free ends by design.
const SHELL_PIECES: Array[String] = ["wall_panel", "wall_glazed", "corner_45"]

var _t: RefCounted


func _initialize() -> void:
	_t = TestReport.new("piece_kit_test")

	_check_kit_loads()
	_check_refusals()
	_check_every_piece_draws()
	_check_grid_units()
	_check_expressions()
	_check_tiling()
	_check_shell_closes()
	_check_six_tier_block()
	_check_fixtures()

	_t.finish(self)


# ── 1. The kit itself ───────────────────────────────────────────────────────

func _check_kit_loads() -> void:
	PieceKit.reload()
	var errors := PieceKit.load_errors()
	_t.check(
		"kit loads clean (%s)" % ("no errors" if errors.is_empty() else ", ".join(errors)),
		errors.is_empty()
	)
	var ids := PieceKit.ids()
	_t.check("kit has pieces (%s)" % ", ".join(ids), ids.size() > 0)
	## Every piece a player has to learn is a cost. If this number grows, the
	## growth has to be argued for, not slipped in.
	_t.equal("kit is six pieces", ids.size(), 6)
	for id in ids:
		var piece := PieceKit.get_piece(str(id))
		_t.check("%s: has a description" % id, not str(piece.get("description", "")).is_empty())
		_t.check("%s: declares parameters" % id, (piece["params"] as Dictionary).size() > 0)


func _check_refusals() -> void:
	## Off the declared set: refused, and the refusal names the value.
	var bad := PieceKit.resolve("wall_panel", {"span": 7})
	_t.check("span 7 is refused (the set is 1,2,3,4,6,8)", (bad["specs"] as Array).is_empty())
	_t.check(
		"the refusal names the value: %s" % ", ".join(bad["errors"] as PackedStringArray),
		_says(bad["errors"] as PackedStringArray, "7")
	)
	## And it is NOT clamped to the nearest legal value — the difference between
	## a refusal and a clamp is whether the player gets what they asked for.
	var clamped := PieceKit.resolve_params("wall_panel", {"span": 7})
	_t.equal(
		"a refused span leaves the default in place, it is not clamped to 6",
		int((clamped["params"] as Dictionary)["span"]), 4
	)

	var unknown := PieceKit.resolve("wall_panel", {"thickness": 0.2})
	_t.check("an undeclared parameter is refused", (unknown["specs"] as Array).is_empty())
	_t.check(
		"the refusal lists what the piece does declare",
		_says(unknown["errors"] as PackedStringArray, "span")
	)

	var bad_choice := PieceKit.resolve("wall_panel", {"opening": "porthole"})
	_t.check("a choice off the set is refused", (bad_choice["specs"] as Array).is_empty())

	var no_piece := PieceKit.resolve("bulkhead", {})
	_t.check("an unknown piece is refused", (no_piece["specs"] as Array).is_empty())

	## Placement refusals.
	var diagonal := PieceKit.resolve_placement(
		{"id": 1, "piece": "wall_panel", "cell": [0, 0, 0], "facing": 45}, 1
	)
	_t.check(
		"facing 45 is refused — corner_45 carries its own chord",
		(diagonal["items"] as Array).is_empty()
	)
	var off_grid := PieceKit.resolve_placement(
		{"id": 1, "piece": "wall_panel", "cell": [0, 0, 3.5], "facing": 0}, 1
	)
	_t.check("a half-cell placement is refused", (off_grid["items"] as Array).is_empty())
	_t.check(
		"the refusal says the grid is whole cells",
		_says(off_grid["errors"] as PackedStringArray, "grid")
	)


func _check_every_piece_draws() -> void:
	## Every choice combination crossed with the ENDS of every numeric range.
	## A piece that only works at its defaults is a piece that will break on
	## somebody's boat, and the load-time probe only walks the choices.
	var checked := 0
	var refused := 0
	var silent := 0
	var bad := PackedStringArray()
	for id_variant in PieceKit.ids():
		var id := str(id_variant)
		var params := PieceKit.params_of(id)
		for combo_variant in _extremes(params):
			var combo := combo_variant as Dictionary
			var result := PieceKit.resolve(id, combo)
			checked += 1
			var specs := result["specs"] as Array
			if specs.is_empty():
				## A refusal is a PASS for the claim being made here: the claim is
				## that no setting silently produces geometry the baker will not
				## draw. A setting that is turned away, loudly, has not done that.
				## A setting that produces nothing and says nothing has.
				refused += 1
				if (result["errors"] as PackedStringArray).is_empty():
					silent += 1
					bad.append("%s at %s: produced nothing and said nothing" % [id, str(combo)])
				continue
			for spec_variant in specs:
				var spec := spec_variant as Dictionary
				var corners: Array = []
				for corner in spec["corners"] as PackedVector3Array:
					corners.append([corner.x, corner.y, corner.z])
				var problem := StructureBaker.plate_problem(
					{"corners": corners, "thickness": float(spec["thickness"])}
				)
				if not problem.is_empty():
					bad.append("%s at %s: %s" % [id, str(combo), problem])
	_t.check(
		"%d of %d piece/parameter settings draw, %d are refused in words, 0 are silent (%s)"
		% [checked - refused, checked, refused, "none bad" if bad.is_empty() else bad[0]],
		bad.is_empty() and silent == 0
	)
	## Every piece must work at its own defaults, or the palette hands a player a
	## broken piece the moment they pick it up.
	for id_variant in PieceKit.ids():
		var id := str(id_variant)
		_t.check(
			"%s draws at its defaults" % id, not (PieceKit.resolve(id)["specs"] as Array).is_empty()
		)
	## The only settings refused should be the ones a declared constraint names.
	var over := PieceKit.resolve("wall_glazed", {"height": 4, "sill": 2, "band": 2})
	_t.check(
		"a glazed panel with no header left is refused, not drawn flat",
		(over["specs"] as Array).is_empty()
	)
	_t.check(
		"and the refusal explains itself: %s"
		% ", ".join(over["errors"] as PackedStringArray),
		_says(over["errors"] as PackedStringArray, "header")
	)


## One dictionary per (choice combination x numeric-parameter extreme), plus the
## all-defaults case. Not the full cross product — that is thousands of settings
## for `wall_glazed` — but it does reach every declared value of every parameter.
func _extremes(params: Dictionary) -> Array:
	var choice_combos: Array = [{}]
	for key in params.keys():
		var spec := params[key] as Dictionary
		if bool(spec["numeric"]):
			continue
		var grown: Array = []
		for combo_variant in choice_combos:
			for value in spec["values"] as Array:
				var next := (combo_variant as Dictionary).duplicate()
				next[str(key)] = value
				grown.append(next)
		choice_combos = grown
	var out: Array = []
	for combo_variant in choice_combos:
		var combo := combo_variant as Dictionary
		out.append(combo.duplicate())
		for key in params.keys():
			var spec := params[key] as Dictionary
			if not bool(spec["numeric"]):
				continue
			for value in spec["values"] as Array:
				var next := combo.duplicate()
				next[str(key)] = value
				out.append(next)
	return out


func _check_grid_units() -> void:
	## The claim that makes this a grid kit: a piece's geometry is a whole number
	## of quarter-cells in every direction, so nothing can land off the grid by a
	## fraction a player did not choose.
	var quarter := WorldUnits.DECK_CELL_M * 0.5
	_t.near("a quarter-cell is 0.25 m", quarter, 0.25)

	var wide := PieceKit.resolve("wall_panel", {"span": 8, "height": 6, "rake": 3})
	var corners := ((wide["specs"] as Array)[0] as Dictionary)["corners"] as PackedVector3Array
	_t.near("span 8 is 4.00 m of run", corners[0].x, 4.0)
	_t.near("height 6 is 3.00 m", corners[2].y, 3.0)
	_t.near("rake 3 stands the top 0.75 m outboard", corners[2].z, -0.75)
	## Outward is -Z in the piece frame, so a positive rake must be negative z.
	_t.check("a positive rake leans OUT, not in", corners[2].z < 0.0)
	var tumbled := PieceKit.resolve("wall_panel", {"rake": -2})
	var t_corners := ((tumbled["specs"] as Array)[0] as Dictionary)["corners"] as PackedVector3Array
	_t.near("rake -2 tumbles home 0.50 m", t_corners[2].z, 0.50)

	_t.equal("wall_panel footprint at span 8 is 8 cells of run",
		PieceKit.footprint_cells("wall_panel", {"span": 8}), Vector3i(8, 5, 0))
	_t.equal("corner_45 footprint at span 3 is 3 x 3 cells",
		PieceKit.footprint_cells("corner_45", {"span": 3}), Vector3i(3, 5, 3))

	## A grid node is a CORNER between cells, not a cell centre — a wall stands on
	## the line between two cells, and getting this wrong puts every wall in the
	## kit half a cell out.
	_t.equal("node (5,0,35) is plan (2.5, 0, 17.5)",
		PieceKit.node_plan(Vector3i(5, 0, 35)), Vector3(2.5, 0.0, 17.5))
	_t.not_equal("a node is not a cell centre",
		PieceKit.node_plan(Vector3i(5, 0, 35)), StructurePlan.cell_base_plan(Vector3i(5, 0, 35)))


func _check_expressions() -> void:
	## The evaluator is the only thing standing between a data file and the
	## geometry, so it gets checked directly rather than through a piece.
	var glazed := PieceKit.resolve("wall_glazed", {"span": 4, "height": 5, "sill": 2, "band": 2, "lights": 3})
	var specs := glazed["specs"] as Array
	_t.equal("a 3-light band is coaming + glass + header + 2 mullions", specs.size(), 5)
	var mull_a := ((specs[3] as Dictionary)["corners"] as PackedVector3Array)
	var mull_b := ((specs[4] as Dictionary)["corners"] as PackedVector3Array)
	## Mullions at 1/3 and 2/3 of a 2.00 m run, 0.10 m wide IN METRES — authored
	## as a fraction of the plate they came out 3 m wide on a ferry and the whole
	## band read as portholes.
	_t.near("mullion 1 stands at 1/3 of the run", (mull_a[0].x + mull_a[1].x) * 0.5, 2.0 / 3.0)
	_t.near("mullion 2 stands at 2/3 of the run", (mull_b[0].x + mull_b[1].x) * 0.5, 4.0 / 3.0)
	_t.near("a mullion is 0.10 m wide in metres", absf(mull_a[0].x - mull_a[1].x), 0.10)
	var one_light := PieceKit.resolve("wall_glazed", {"lights": 1})
	_t.equal("a 1-light band has no mullions", (one_light["specs"] as Array).size(), 3)

	## The rake distributes with height: the glass leans by its share, not the
	## whole wall's. sill 2 of height 5 at rake 4 -> 1.00 m x 2/5 = 0.40 m out.
	var raked := PieceKit.resolve("wall_glazed", {"span": 4, "height": 5, "rake": 4, "sill": 2, "band": 2})
	var coaming := ((raked["specs"] as Array)[0] as Dictionary)["corners"] as PackedVector3Array
	_t.near("the coaming top leans out 0.40 m, its share of a 1.00 m rake", coaming[2].z, -0.40)
	var header := ((raked["specs"] as Array)[2] as Dictionary)["corners"] as PackedVector3Array
	_t.near("the header top carries the full 1.00 m", header[2].z, -1.00)
	_t.near("and its foot carries 0.80 m, the coaming plus the band", header[0].z, -0.80)


func _check_tiling() -> void:
	## Two panels butted on one line at one rake. The shared edge must be
	## IDENTICAL, and it is identical because neither number was typed as a float.
	var a := {"id": "a", "piece": "wall_panel", "cell": [0, 0, 0], "facing": 0,
		"params": {"span": 4, "height": 5, "rake": 2}}
	var b := {"id": "b", "piece": "wall_panel", "cell": [4, 0, 0], "facing": 0,
		"params": {"span": 2, "height": 5, "rake": 2}}
	var ca := PieceKit.placed_corners(a)
	var cb := PieceKit.placed_corners(b)
	_t.check("butted panels share their foot exactly", ca[0].distance_to(cb[1]) < SEAM_EPSILON)
	_t.check("butted panels share their head exactly", ca[3].distance_to(cb[2]) < SEAM_EPSILON)
	_t.check(
		"and unequal widths still butt (4 cells against 2)",
		absf(ca[0].x - 2.0) < SEAM_EPSILON
	)

	## Negative control: one step of rake between them and the head opens by
	## exactly a quarter-cell. This is the failure the kit is built to make
	## impossible when both pieces carry the same setting, and visible when they
	## do not.
	var c := b.duplicate(true)
	(c["params"] as Dictionary)["rake"] = 1
	var cc := PieceKit.placed_corners(c)
	_t.near(
		"one step of rake difference opens the head by exactly 0.25 m",
		ca[3].distance_to(cc[2]), 0.25, 1e-6
	)


# ── The seam claim ──────────────────────────────────────────────────────────

func _check_shell_closes() -> void:
	var doc := _load(TRAWLER)
	if doc.is_empty():
		_t.fail("%s did not load" % TRAWLER)
		return
	var report := _seam_report(doc)
	_t.equal(
		"every shell piece on the trawler has a mate: %d edges, %s"
		% [int(report["edges"]), str(report["unmatched"])],
		int(report["open"]), 0
	)
	## Three closed rings — the lower tier, the wheelhouse and the funnel — and
	## every piece in all three is a wall, a glazed wall or a corner facet.
	_t.check(
		"the trawler's shell is %d pieces in 3 closed rings" % int(report["pieces"]),
		int(report["pieces"]) == 32
	)

	## NEGATIVE CONTROL. Move one panel's rake by one step and the same check must
	## go red — otherwise it is measuring nothing. The mutation is exactly what a
	## player would do by mis-setting a neighbour.
	var mutated := doc.duplicate(true)
	var touched := ""
	for placement_variant in mutated["pieces"] as Array:
		var placement := placement_variant as Dictionary
		if str(placement.get("piece", "")) != "wall_panel":
			continue
		var params := placement.get("params", {}) as Dictionary
		if int(params.get("rake", 0)) != 2:
			continue
		params["rake"] = 1
		touched = str(placement.get("_is", placement.get("id", "?")))
		break
	var mutated_report := _seam_report(mutated)
	_t.check(
		"MUTATION: de-raking \"%s\" by one step opens %d seams (was 0)"
		% [touched, int(mutated_report["open"])],
		int(mutated_report["open"]) > 0
	)

	## Second mutation: delete a corner facet. Two walls that used to be joined by
	## it are then both open, and the check must say so.
	var gapped := doc.duplicate(true)
	var pieces: Array = gapped["pieces"] as Array
	for i in pieces.size():
		if str((pieces[i] as Dictionary).get("piece", "")) == "corner_45":
			pieces.remove_at(i)
			break
	var gapped_report := _seam_report(gapped)
	_t.check(
		"MUTATION: removing one corner facet opens %d seams (was 0)"
		% int(gapped_report["open"]),
		int(gapped_report["open"]) > 0
	)


## Every shell piece's OUT edge (local corners 0 and 3) must be another shell
## piece's IN edge (local corners 1 and 2), in PLAN space. Returns
## {"pieces","edges","open","unmatched"}.
##
## The IN/OUT convention is not a coincidence: `plate` corners are a ring ordered
## counter-clockwise from outside, so corners 1->2 is always the lateral edge the
## run starts on and 0->3 is always the one it ends on — for a wall panel, for a
## glazed panel, and for a corner facet, whose two edges belong to its two
## neighbours by construction.
func _seam_report(doc: Dictionary) -> Dictionary:
	var outs: Array = []
	var ins: Array = []
	var pieces := 0
	for placement_variant in doc.get("pieces", []) as Array:
		var placement := placement_variant as Dictionary
		var id := str(placement.get("piece", ""))
		if not SHELL_PIECES.has(id):
			continue
		pieces += 1
		var edges := _lateral_edges(placement)
		if edges.is_empty():
			continue
		outs.append({"label": _label(placement), "edge": edges["out"]})
		ins.append({"label": _label(placement), "edge": edges["in"]})
	var open := 0
	var unmatched := PackedStringArray()
	var used: Dictionary = {}
	for out_variant in outs:
		var out_entry := out_variant as Dictionary
		var found := -1
		for i in ins.size():
			if used.has(i):
				continue
			if _edges_meet(out_entry["edge"] as PackedVector3Array, (ins[i] as Dictionary)["edge"] as PackedVector3Array):
				found = i
				break
		if found < 0:
			open += 1
			if unmatched.size() < 4:
				unmatched.append(str(out_entry["label"]))
		else:
			used[found] = true
	return {"pieces": pieces, "edges": outs.size(), "open": open, "unmatched": unmatched}


## [foot, head] of a placed piece's two lateral edges, in plan metres. A piece
## that resolves to several plates (a glazed panel is four) reports the LOWEST
## foot and the HIGHEST head, which is the edge the shell actually presents.
func _lateral_edges(placement: Dictionary) -> Dictionary:
	var result := PieceKit.resolve_placement(placement, 1)
	var items := result["items"] as Array
	if items.is_empty():
		return {}
	var out_foot := Vector3.INF
	var out_head := Vector3.INF
	var in_foot := Vector3.INF
	var in_head := Vector3.INF
	for step in items.size():
		var corners := PieceKit.placed_corners(placement, step)
		if corners.size() != 4:
			continue
		if out_foot == Vector3.INF or corners[0].y < out_foot.y:
			out_foot = corners[0]
		if out_head == Vector3.INF or corners[3].y > out_head.y:
			out_head = corners[3]
		if in_foot == Vector3.INF or corners[1].y < in_foot.y:
			in_foot = corners[1]
		if in_head == Vector3.INF or corners[2].y > in_head.y:
			in_head = corners[2]
	return {
		"out": PackedVector3Array([out_foot, out_head]),
		"in": PackedVector3Array([in_foot, in_head]),
	}


func _edges_meet(a: PackedVector3Array, b: PackedVector3Array) -> bool:
	return a[0].distance_to(b[0]) < SEAM_EPSILON and a[1].distance_to(b[1]) < SEAM_EPSILON


func _label(placement: Dictionary) -> String:
	var note := str(placement.get("_is", ""))
	return "%s %s" % [str(placement.get("piece", "?")), note if not note.is_empty() else str(placement.get("id", "?"))]


# ── The third target: a container ship's six-tier aft block ─────────────────
#
# There is no such fixture in this repo to read corners off, so this builds one
# from the kit and asks whether it holds together. A tall accommodation block is
# the case where a piece kit is SUPPOSED to be effortless — it is pure repetition
# — and the thing worth checking is that stacking a tier introduces nothing: the
# same eight placements at cy += height, six times, and every ring still closes.
#
# The top tier's front rakes, because a bridge front does, and its two forward
# corner facets are handed a raked wall on one edge and a plumb one on the other.
# That asymmetry is the case the adapter exists for and it is checked here rather
# than assumed.

func _check_six_tier_block() -> void:
	var pieces: Array = []
	var tiers := 6
	var height := 5
	for tier in tiers:
		var cy := tier * height
		var rake := 2 if tier == tiers - 1 else 0
		pieces.append(_corner(0, cy, 0, 0, rake, 0))
		pieces.append(_corner(12, cy, 0, 270, 0, rake))
		pieces.append(_corner(12, cy, 12, 180, 0, 0))
		pieces.append(_corner(0, cy, 12, 90, 0, 0))
		pieces.append_array(_wall_run(1, cy, 0, 0, rake))
		pieces.append_array(_wall_run(12, cy, 1, 270, 0))
		pieces.append_array(_wall_run(11, cy, 12, 180, 0))
		pieces.append_array(_wall_run(0, cy, 11, 90, 0))
	var report := _seam_report({"pieces": pieces})
	_t.equal(
		"a six-tier aft block closes at every tier: %d pieces, %s"
		% [int(report["pieces"]), str(report["unmatched"])],
		int(report["open"]), 0
	)
	_t.equal(
		"and it is the same twelve placements six times over — four corner facets "
		+ "and four sides of two panels each", pieces.size(), 6 * 12
	)
	## The tier above stands exactly on the tier below — 5 cells is 2.50 m and
	## nothing accumulates a fraction, which is what lets six of them stack.
	var lower := PieceKit.placed_corners(pieces[4] as Dictionary)
	var upper := PieceKit.placed_corners(pieces[12] as Dictionary)
	_t.near("tier 2 stands on tier 1's head, to the millimetre", upper[1].y - lower[2].y, 0.0, 1e-6)


func _corner(cx: int, cy: int, cz: int, facing: int, rake_a: int, rake_b: int) -> Dictionary:
	return {
		"id": "corner %d/%d/%d" % [cx, cy, cz], "piece": "corner_45",
		"cell": [cx, cy, cz], "facing": facing,
		"params": {"span": 1, "height": 5, "rake_a": rake_a, "rake_b": rake_b},
	}


## A 10-cell side, as a 4-cell panel and a 6-cell panel — because 10 is not a
## width the kit sells, and a run is what a player builds instead.
func _wall_run(cx: int, cy: int, cz: int, facing: int, rake: int) -> Array:
	var step := {0: Vector2i(1, 0), 90: Vector2i(0, -1), 180: Vector2i(-1, 0), 270: Vector2i(0, 1)}[facing] as Vector2i
	var out: Array = []
	var at := Vector2i(cx, cz)
	for span in [4, 6]:
		out.append({
			"id": "wall %s" % str(at), "piece": "wall_panel",
			"cell": [at.x, cy, at.y], "facing": facing,
			"params": {"span": span, "height": 5, "rake": rake},
		})
		at += step * int(span)
	return out


# ── 4. The fixtures ─────────────────────────────────────────────────────────

func _check_fixtures() -> void:
	var house := _load(HOUSE)
	if not _t.check("%s loads" % HOUSE, not house.is_empty()):
		return
	## THE STRICT CLAIM: not one hand-authored plate corner in the whole file.
	_t.equal(
		"probe_piece_house has ZERO hand-authored plates", PieceKit.authored_plate_count(house), 0
	)
	var resolved := PieceKit.resolve_document(house)
	_t.check(
		"it resolves clean (%s)"
		% ("no errors" if (resolved["errors"] as PackedStringArray).is_empty()
			else ", ".join(resolved["errors"] as PackedStringArray)),
		(resolved["errors"] as PackedStringArray).is_empty()
	)
	_t.check("it places %d pieces" % int(resolved["placed"]), int(resolved["placed"]) > 0)
	_t.check(
		"which become %d plates the baker draws" % int(resolved["items"]),
		int(resolved["items"]) > int(resolved["placed"])
	)
	var house_plan := StructurePlan.from_dict(resolved["doc"] as Dictionary)
	_t.check("the resolved document is a plan", StructurePlan.is_plan(resolved["doc"] as Dictionary))
	_t.check("with entities in it", house_plan.entity_count() > 0)
	var mute := 0
	for item_variant in house_plan.items:
		var item := item_variant as Dictionary
		if StructureBaker.item_primitive(item) != "plate":
			mute += 1
			continue
		if not StructureBaker.plate_problem(StructurePlan.item_props(item)).is_empty():
			mute += 1
	_t.equal("every resolved item is a plate the baker draws", mute, 0)

	var trawler := _load(TRAWLER)
	if not _t.check("%s loads" % TRAWLER, not trawler.is_empty()):
		return
	var t_resolved := PieceKit.resolve_document(trawler)
	_t.check(
		"the trawler resolves clean (%s)"
		% ("no errors" if (t_resolved["errors"] as PackedStringArray).is_empty()
			else ", ".join(t_resolved["errors"] as PackedStringArray)),
		(t_resolved["errors"] as PackedStringArray).is_empty()
	)

	## The honest accounting, and it is stated as a number rather than a claim:
	## the DECKHOUSE is gone from the authored plates; what is left is bow
	## bulwark and gallows steelwork, which this kit deliberately does not try to
	## express (a sheer-following bulwark is a swept curve, not a grid piece).
	var authored := PieceKit.authored_plate_count(trawler)
	_t.equal("the trawler fixture keeps 39 authored plates, none of them deckhouse", authored, 39)
	var reference := _load(REFERENCE)
	if not reference.is_empty():
		var before := PieceKit.authored_plate_count(reference)
		_t.check(
			"probe_trawler_bulwark authors %d plates; the piece-built one authors %d — %d fewer"
			% [before, authored, before - authored],
			authored < before
		)


func _load(path: String) -> Dictionary:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return raw as Dictionary if raw is Dictionary else {}


func _says(messages: PackedStringArray, needle: String) -> bool:
	for message in messages:
		if message.contains(needle):
			return true
	return false
