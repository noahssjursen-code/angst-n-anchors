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
	_check_trim_lattice()
	_check_diagonal_run()
	_check_shell_closes()
	_check_deck_lands_on_walls()
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

	var eighth := WorldUnits.DECK_CELL_M * 0.25
	_t.near("an eighth-cell is 0.125 m", eighth, 0.125)

	var wide := PieceKit.resolve("wall_panel", {"span": 8, "height": 6, "rake": 6})
	var corners := ((wide["specs"] as Array)[0] as Dictionary)["corners"] as PackedVector3Array
	_t.near("span 8 is 4.00 m of run", corners[0].x, 4.0)
	_t.near("height 6 is 3.00 m", corners[2].y, 3.0)
	_t.near("rake 6 stands the top 0.75 m outboard", corners[2].z, -0.75)
	## Outward is -Z in the piece frame, so a positive rake must be negative z.
	_t.check("a positive rake leans OUT, not in", corners[2].z < 0.0)
	var tumbled := PieceKit.resolve("wall_panel", {"rake": -4})
	var t_corners := ((tumbled["specs"] as Array)[0] as Dictionary)["corners"] as PackedVector3Array
	_t.near("rake -4 tumbles home 0.50 m", t_corners[2].z, 0.50)

	## THE COMPATIBILITY CLAIM, and it is the one that makes halving the step
	## safe: the eighth-cell lattice CONTAINS the quarter-cell one. Every offset
	## version 1 could say, version 2 says with the same bits — so a panel authored
	## at the old step and a panel authored at the new one stand on the same plane
	## and their shared edge is identical, which is checked below in `_check_tiling`.
	var off_lattice := 0
	var exact := 0
	for old_rake in range(-4, 5):
		var probe := PieceKit.resolve("wall_panel", {"rake": old_rake * 2})
		var pc := ((probe["specs"] as Array)[0] as Dictionary)["corners"] as PackedVector3Array
		if pc[2].z == float(old_rake) * -0.25:
			exact += 1
		else:
			off_lattice += 1
	_t.equal(
		"all 9 of version 1's quarter-cell rakes are still EXACTLY expressible (%d exact, %d moved)"
		% [exact, off_lattice], off_lattice, 0
	)

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
	## whole wall's. sill 2 of height 5 at rake 8 -> 1.00 m x 2/5 = 0.40 m out.
	var raked := PieceKit.resolve("wall_glazed", {"span": 4, "height": 5, "rake": 8, "sill": 2, "band": 2})
	var coaming := ((raked["specs"] as Array)[0] as Dictionary)["corners"] as PackedVector3Array
	_t.near("the coaming top leans out 0.40 m, its share of a 1.00 m rake", coaming[2].z, -0.40)
	var header := ((raked["specs"] as Array)[2] as Dictionary)["corners"] as PackedVector3Array
	_t.near("the header top carries the full 1.00 m", header[2].z, -1.00)
	_t.near("and its foot carries 0.80 m, the coaming plus the band", header[0].z, -0.80)

	## And the DENOMINATOR is the total height, `head` included — which is what the
	## parenthesised division in the kit is for. head 2 makes a height-5 wall 2.75 m,
	## so the coaming's 1.00 m share of a 1.00 m rake becomes 1.00/2.75 = 0.3636.
	## Without grouping, `.../height*0.5+head*0.125` divides by height and then
	## MULTIPLIES by 0.5, which is 0.20 and looks entirely plausible.
	var headed := PieceKit.resolve(
		"wall_glazed", {"span": 4, "height": 5, "head": 2, "rake": 8, "sill": 2, "band": 2}
	)
	var h_coam := ((headed["specs"] as Array)[0] as Dictionary)["corners"] as PackedVector3Array
	var h_head := ((headed["specs"] as Array)[2] as Dictionary)["corners"] as PackedVector3Array
	_t.near("head 2 makes the wall 2.75 m tall", h_head[2].y, 2.75)
	_t.near(
		"and the coaming's share of the rake is 1.00/2.75, not 1.00/5*0.5",
		h_coam[2].z, -1.00 / 2.75, 1e-6
	)

	## Parentheses, direct. The evaluator is the only thing between a data file and
	## the geometry, and a precedence bug there is silent everywhere.
	var paren_errors := PackedStringArray()
	_t.near("2/(1+1) is 1, not 1.0 by way of 2/1+1",
		PieceKit._eval("2/(1+1)", {}, "probe", paren_errors), 1.0)
	_t.near("-(2+1)*2 is -6",
		PieceKit._eval("-(2+1)*2", {}, "probe", paren_errors), -6.0)
	_t.check("and those parsed with no complaint", paren_errors.is_empty())
	var unclosed := PackedStringArray()
	var _v := PieceKit._eval("2*(1+1", {}, "probe", unclosed)
	_t.check(
		"an unclosed bracket is an ERROR, not a silently closed one: %s" % ", ".join(unclosed),
		_says(unclosed, "unclosed")
	)


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
		"one step of rake difference opens the head by exactly 0.125 m",
		ca[3].distance_to(cc[2]), 0.125, 1e-6
	)

	## THE HALVED STEP STILL MEETS, over the WHOLE set rather than one sample.
	## Every one of the 17 rakes, butted against itself, shares its edge to the bit;
	## and every one butted against its NEIGHBOUR opens by exactly one step and no
	## other amount. The first half is the guarantee; the second is what makes the
	## first non-vacuous, because a resolver that ignored `rake` would pass the
	## first and fail the second.
	var same_open := 0
	var wrong_gap := 0
	var worst_gap := 0.0
	for spec in PieceKit.params_of("wall_panel")["rake"]["values"] as Array:
		var r := int(spec)
		var left := {"id": "L", "piece": "wall_panel", "cell": [0, 0, 0], "facing": 0,
			"params": {"span": 4, "height": 5, "rake": r}}
		var right := {"id": "R", "piece": "wall_panel", "cell": [4, 0, 0], "facing": 0,
			"params": {"span": 2, "height": 5, "rake": r}}
		var cl := PieceKit.placed_corners(left)
		var cr := PieceKit.placed_corners(right)
		if cl[0] != cr[1] or cl[3] != cr[2]:
			same_open += 1
		if r < 8:
			var stepped := right.duplicate(true)
			(stepped["params"] as Dictionary)["rake"] = r + 1
			var cs := PieceKit.placed_corners(stepped)
			var gap := cl[3].distance_to(cs[2])
			worst_gap = maxf(worst_gap, absf(gap - 0.125))
			if absf(gap - 0.125) > 1e-6:
				wrong_gap += 1
	_t.equal(
		"all 17 rakes butt BIT-IDENTICALLY against themselves (%d that did not)" % same_open,
		same_open, 0
	)
	_t.equal(
		"and every adjacent pair opens by exactly one 0.125 m step (worst error %.9f m)"
		% worst_gap, wrong_gap, 0
	)

	## And a panel on the OLD lattice meets a panel on the new one: rake -2 is
	## version 1's rake -1, to the bit, so a saved deckhouse and a new one butt.
	var old_style := {"id": "old", "piece": "wall_panel", "cell": [0, 0, 0], "facing": 0,
		"params": {"span": 4, "height": 5, "rake": -2}}
	var new_style := {"id": "new", "piece": "wall_panel", "cell": [4, 0, 0], "facing": 0,
		"params": {"span": 2, "height": 5, "rake": -2}}
	var co := PieceKit.placed_corners(old_style)
	var cn := PieceKit.placed_corners(new_style)
	_t.check(
		"a 0.25 m tumblehome reached through the halved step still lands on 0.25 m",
		co[2].z == 0.25 and co[3] == cn[2]
	)


# ── The trim lattice: head, fall and lift ───────────────────────────────────
#
# The three parameters version 2 added, and they are all the same idea: the
# placement grid is whole cells and a deckhouse is not. Each one is checked for
# the PROPERTY it has to have — it moves what it says it moves, it moves nothing
# else, and two pieces carrying the same value meet exactly — rather than for the
# number it was written with.

func _check_trim_lattice() -> void:
	var base := PieceKit.resolve("wall_panel", {"span": 4, "height": 5})
	var b := ((base["specs"] as Array)[0] as Dictionary)["corners"] as PackedVector3Array

	## HEAD. Adds to the top and to nothing else.
	var moved_foot := 0
	var wrong_top := 0
	for h in range(0, 8):
		var probe := PieceKit.resolve("wall_panel", {"span": 4, "height": 5, "head": h})
		var p := ((probe["specs"] as Array)[0] as Dictionary)["corners"] as PackedVector3Array
		if p[0] != b[0] or p[1] != b[1]:
			moved_foot += 1
		if p[2].y != b[2].y + float(h) * 0.125 or p[3].y != b[3].y + float(h) * 0.125:
			wrong_top += 1
		if p[2].z != b[2].z:
			wrong_top += 1
	_t.equal("head moves the head and only the head (%d feet moved)" % moved_foot, moved_foot, 0)
	_t.equal("head h raises the top by exactly h eighth-cells", wrong_top, 0)
	_t.near(
		"a 2.75 m tier is height 5 + head 2, which version 1 could not say",
		((PieceKit.resolve("wall_panel", {"height": 5, "head": 2})["specs"] as Array)[0]
			as Dictionary)["corners"][2].y, 2.75
	)

	## LIFT. Moves the whole piece and changes no shape.
	var lifted := PieceKit.resolve("wall_panel", {"span": 4, "height": 5, "lift": 3})
	var l := ((lifted["specs"] as Array)[0] as Dictionary)["corners"] as PackedVector3Array
	var rigid := true
	for i in 4:
		if l[i] != b[i] + Vector3(0.0, 0.375, 0.0):
			rigid = false
	_t.check("lift 3 translates every corner by exactly 0.375 m and deforms nothing", rigid)
	_t.check(
		"a negative lift lowers it the same way",
		((PieceKit.resolve("wall_panel", {"lift": -4})["specs"] as Array)[0]
			as Dictionary)["corners"][1].y == -0.5
	)

	## FALL. Drops the OUT head, leaves the IN head and both feet where they were.
	var wrong_fall := 0
	for f in range(-4, 5):
		var probe := PieceKit.resolve("wall_panel", {"span": 8, "height": 5, "fall": f})
		var p := ((probe["specs"] as Array)[0] as Dictionary)["corners"] as PackedVector3Array
		if p[0].y != 0.0 or p[1].y != 0.0 or p[2].y != 2.5:
			wrong_fall += 1
		if p[3].y != 2.5 - float(f) * 0.125:
			wrong_fall += 1
	_t.equal("fall f drops the far head by exactly f eighth-cells and moves nothing else",
		wrong_fall, 0)

	## THE CHAIN. A falling run is several panels, and the whole point is that the
	## next one starts where the last one ended. Panel A (head 1, fall 1) ends its
	## top 0.125 m lower than it started; panel B (head 0) starts there.
	var a := {"id": "a", "piece": "wall_panel", "cell": [0, 0, 0], "facing": 0,
		"params": {"span": 4, "height": 5, "head": 1, "fall": 1}}
	var next := {"id": "b", "piece": "wall_panel", "cell": [4, 0, 0], "facing": 0,
		"params": {"span": 4, "height": 5, "head": 0, "fall": 0}}
	var ca := PieceKit.placed_corners(a)
	var cb := PieceKit.placed_corners(next)
	_t.check("a falling panel hands the next one its exact head", ca[3] == cb[2])
	_t.check("and its exact foot", ca[0] == cb[1])
	## Negative control: the same two panels with the fall left off. This is the
	## mistake the parameter exists to make impossible to have silently, and it must
	## show up as a gap of exactly one step.
	var flat := a.duplicate(true)
	(flat["params"] as Dictionary)["fall"] = 0
	_t.near(
		"MUTATION: dropping the fall opens that seam by exactly 0.125 m",
		PieceKit.placed_corners(flat)[3].distance_to(cb[2]), 0.125, 1e-9
	)

	## A DECK THAT FALLS, and the CAMBER two of them make.
	var tile := PieceKit.resolve("deck_tile", {"span": 4, "depth": 16, "fall": 2})
	var dt := ((tile["specs"] as Array)[0] as Dictionary)["corners"] as PackedVector3Array
	_t.check("a deck tile's near edge stays on its node", dt[2].y == 0.0 and dt[3].y == 0.0)
	_t.near("and fall 2 drops its far edge exactly 0.25 m over 8.00 m", dt[0].y, -0.25, 0.0)
	_t.check("which is a plane, not a fold — both far corners drop together", dt[0].y == dt[1].y)
	_t.check(
		"version 1's deck is still there at fall 0",
		((PieceKit.resolve("deck_tile", {"span": 4, "depth": 16})["specs"] as Array)[0]
			as Dictionary)["corners"][0].y == 0.0
	)

	## Chaining a fall down the slope: the next tile carries the lift its neighbour
	## ended at, and because fall and lift count the same unit the edge is identical.
	var up := {"id": "up", "piece": "deck_tile", "cell": [0, 5, 0], "facing": 0,
		"params": {"span": 4, "depth": 8, "fall": 2, "lift": 2}}
	var down := {"id": "down", "piece": "deck_tile", "cell": [0, 5, 8], "facing": 0,
		"params": {"span": 4, "depth": 8, "fall": 2, "lift": 0}}
	var cu := PieceKit.placed_corners(up)
	var cd := PieceKit.placed_corners(down)
	_t.check("a chained deck's far edge IS the next tile's near edge", cu[0] == cd[3] and cu[1] == cd[2])
	_t.check("and the chain keeps falling", cd[0].y < cd[3].y)

	## CAMBER. Two tiles at the same fall, back to back off a centreline: they meet
	## exactly along the crown and both fall away from it. This is the answer to
	## "camber is not in the vocabulary" — it is not a piece, it is two placements.
	var port := {"id": "p", "piece": "deck_tile", "cell": [0, 5, 0], "facing": 0,
		"params": {"span": 4, "depth": 4, "fall": 1}}
	var stbd := {"id": "s", "piece": "deck_tile", "cell": [4, 5, 0], "facing": 180,
		"params": {"span": 4, "depth": 4, "fall": 1}}
	var cp := PieceKit.placed_corners(port)
	var cs := PieceKit.placed_corners(stbd)
	## Compared to 1e-6 rather than to the bit, and the slack is the ENGINE's, not
	## the kit's: `Basis` is real_t, which is float32 in this build, so
	## sin(deg_to_rad(180)) is -8.7e-8 rather than 0 and a 2 m lever turns that into
	## 1.7e-7 m of z. Measured, not assumed. Every comparison in this file that does
	## NOT cross a rotation is `==`, and they all hold. 1e-6 is still a hundred times
	## tighter than the 1e-4 seam bound.
	_t.check(
		"a camber's two halves share the crown line exactly (%.9f m apart, float32 basis)"
		% maxf(cp[2].distance_to(cs[3]), cp[3].distance_to(cs[2])),
		cp[2].distance_to(cs[3]) < 1e-6 and cp[3].distance_to(cs[2]) < 1e-6
	)
	_t.check(
		"and both fall away from it, which is what makes it a crown and not a slope",
		cp[0].y < cp[3].y and cs[0].y < cs[3].y and cp[0].z != cs[0].z
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


# ── The diagonal wall run ───────────────────────────────────────────────────
#
# Version 1 wrote "DIAGONAL WALL RUNS DO NOT EXIST … corner_45 carries the only
# 45-degree chord, capped at 4 cells". The cap is now 8 and the chaining is the
# answer to the rest of it: a facet's OUT edge is the next facet's IN edge, so
# any number of them make one straight 45-degree wall. No seventh piece, and
# nothing is placed at 45 degrees — every facing below is 0.

func _check_diagonal_run() -> void:
	var spans := PieceKit.params_of("corner_45")["span"]["values"] as Array
	_t.check("corner_45 reaches 8 cells (%s)" % str(spans), spans.has(8))
	_t.check(
		"a span off the set is still refused — the cap moved, it did not open",
		(PieceKit.resolve("corner_45", {"span": 5})["specs"] as Array).is_empty()
	)
	var chord := PieceKit.resolve("corner_45", {"span": 8, "height": 5})
	var cc := ((chord["specs"] as Array)[0] as Dictionary)["corners"] as PackedVector3Array
	_t.near("and at span 8 its chord is 5.66 m, a bow facet", cc[0].distance_to(cc[1]), 5.6569, 1e-3)

	## Three facets chained nose to tail, each one placed span cells back in X and
	## span forward in Z, all at facing 0.
	var facets: Array = []
	var span := 8
	for i in 3:
		facets.append({
			"id": "facet %d" % i, "piece": "corner_45",
			"cell": [24 - span * i, 0, span * i], "facing": 0,
			"params": {"span": span, "height": 5},
		})
	var open := 0
	var worst := 0.0
	for i in 2:
		var here := PieceKit.placed_corners(facets[i] as Dictionary)
		var next := PieceKit.placed_corners(facets[i + 1] as Dictionary)
		## A facet that refuses to resolve is an OPEN joint, not a skipped check —
		## otherwise capping the span back at 4 would delete this claim instead of
		## breaking it, which is the vacuous-pass trap (REALITY §4).
		if here.size() != 4 or next.size() != 4:
			open += 1
			continue
		## facet i's IN edge (1,2) is facet i+1's OUT edge (0,3).
		if here[1] != next[0] or here[2] != next[3]:
			open += 1
		worst = maxf(worst, maxf(here[1].distance_to(next[0]), here[2].distance_to(next[3])))
	_t.equal(
		"three chained facets share every joint BIT-IDENTICALLY (worst %.9f m)" % worst, open, 0
	)
	## And the chain is STRAIGHT — a diagonal wall, not a staircase of facets. Every
	## foot corner of every facet lies on one line, and that line runs at 45 degrees.
	var ends := PieceKit.placed_corners(facets[0] as Dictionary)
	var tails := PieceKit.placed_corners(facets[2] as Dictionary)
	if not _t.check("the chain resolves at all", ends.size() == 4 and tails.size() == 4):
		return
	var head := ends[0]
	var tail := tails[1]
	var axis := (tail - head)
	var off_line := 0.0
	for facet in facets:
		for point in [PieceKit.placed_corners(facet as Dictionary)[0], PieceKit.placed_corners(facet as Dictionary)[1]]:
			var t: float = (point - head).dot(axis) / axis.length_squared()
			off_line = maxf(off_line, (point - (head + axis * t)).length())
	_t.check("and the run is one straight line (worst departure %.9f m)" % off_line, off_line < 1e-6)
	_t.near("at 45 degrees in plan", absf(axis.x), absf(axis.z), 1e-9)
	_t.near("and 8.49 m long — three 5.66 m chords", axis.length(), 3.0 * 8.0 * 0.5 * sqrt(2.0), 1e-6)

	## MUTATION. Slide the middle facet one cell off the diagonal and the joints
	## must open. A chain check that cannot fail is a chain of nothing.
	var bent: Array = facets.duplicate(true)
	(bent[1] as Dictionary)["cell"] = [24 - span + 1, 0, span]
	var bent_open := 0
	for i in 2:
		var here := PieceKit.placed_corners(bent[i] as Dictionary)
		var next := PieceKit.placed_corners(bent[i + 1] as Dictionary)
		if here[1] != next[0] or here[2] != next[3]:
			bent_open += 1
	_t.check(
		"MUTATION: one cell of offset on the middle facet opens %d of 2 joints (was 0)"
		% bent_open, bent_open > 0
	)


# ── The falling deck actually lands on the walls ────────────────────────────
#
# The one claim that is about the VESSEL rather than about a piece, and the one
# the four widened sets exist for. `probe_piece_trawler`'s boat deck is no longer
# level; the tier under it is a two-step chord of that plane. So the property to
# hold is not "the fall is 0.25" — that restates the input — it is: EVERY HEAD
# CORNER OF THE TIER LIES INSIDE THE DECK PLATE THAT COVERS IT. A wall whose head
# is above the deck pokes through the roof; one below it opens a slot of daylight,
# and that is the failure a stepped approximation actually risks.

const DECK_GAUGE_M := 0.13


func _check_deck_lands_on_walls() -> void:
	var doc := _load(TRAWLER)
	if doc.is_empty():
		_t.fail("%s did not load" % TRAWLER)
		return
	var report := _deck_report(doc)
	_t.check(
		"the boat deck is not level: it falls %.4f m over its length" % float(report["fall"]),
		float(report["fall"]) > 0.2
	)
	_t.equal(
		"every one of the %d tier head corners lands inside the deck plate covering it "
		% int(report["sampled"]) + "(worst departure %.4f m, half-gauge %.4f)"
		% [float(report["worst"]), DECK_GAUGE_M * 0.5],
		int(report["outside"]), 0
	)
	_t.check("and the check actually sampled the tier", int(report["sampled"]) >= 20)

	## MUTATION 1 — flatten the deck. The tier still steps down 0.25 m aft, so its
	## after end drops clear of a level deck.
	var flat := doc.duplicate(true)
	for placement_variant in flat["pieces"] as Array:
		var placement := placement_variant as Dictionary
		if not str(placement.get("_is", "")).begins_with("boat deck"):
			continue
		(placement["params"] as Dictionary)["fall"] = 0
	var flat_report := _deck_report(flat)
	_t.check(
		"MUTATION: a level boat deck leaves %d head corners outside it (worst %.4f m, was 0)"
		% [int(flat_report["outside"]), float(flat_report["worst"])],
		int(flat_report["outside"]) > 0
	)

	## MUTATION 2 — take the tier's extra head off. 2.75 m becomes 2.50 and the
	## forward end of the deck is left standing 0.25 m above nothing.
	var short := doc.duplicate(true)
	for placement_variant in short["pieces"] as Array:
		var placement := placement_variant as Dictionary
		if not str(placement.get("_is", "")).begins_with("lower tier"):
			continue
		var params := placement.get("params", {}) as Dictionary
		if int(params.get("head", 0)) > 0:
			params["head"] = 0
	var short_report := _deck_report(short)
	_t.check(
		"MUTATION: dropping the tier's head leaves %d corners outside (worst %.4f m, was 0)"
		% [int(short_report["outside"]), float(short_report["worst"])],
		int(short_report["outside"]) > 0
	)

	## THE OTHER HALF OF THE SAME CLAIM, and it is a boundary the kit STATES: a
	## wall's foot is level, so the wheelhouse standing on the falling boat deck
	## cannot follow it — it sits on the mean and wanders. The kit says that wander
	## stays inside the deck plate. Nothing was checking that it does.
	var feet := _deck_report(doc, "wheelhouse", false)
	_t.equal(
		"the wheelhouse's %d level feet stay inside the falling deck they stand on "
		% int(feet["sampled"]) + "(worst %.4f m, half-gauge %.4f)"
		% [float(feet["worst"]), DECK_GAUGE_M * 0.5],
		int(feet["outside"]), 0
	)
	## MUTATION: put the wheelhouse back on the whole-cell lattice. Its foot then
	## sits 0.125 m under the forward end of the deck it is supposed to stand on.
	var unlifted := doc.duplicate(true)
	for placement_variant in unlifted["pieces"] as Array:
		var placement := placement_variant as Dictionary
		if not str(placement.get("_is", "")).begins_with("wheelhouse"):
			continue
		var params := placement.get("params", {}) as Dictionary
		if params.has("lift"):
			params["lift"] = 0
	var unlifted_feet := _deck_report(unlifted, "wheelhouse", false)
	_t.check(
		"MUTATION: dropping the wheelhouse's lift puts %d feet outside the deck (worst %.4f m, was 0)"
		% [int(unlifted_feet["outside"]), float(unlifted_feet["worst"])],
		int(unlifted_feet["outside"]) > 0
	)


## Head corners of every `lower tier` shell piece, measured against the plane of
## whichever `boat deck` tile covers them in plan. Returns
## {"sampled","outside","worst","fall"}.
func _deck_report(doc: Dictionary, prefix := "lower tier", heads_not_feet := true) -> Dictionary:
	var tiles: Array = []
	var low := INF
	var high := -INF
	for placement_variant in doc.get("pieces", []) as Array:
		var placement := placement_variant as Dictionary
		if str(placement.get("piece", "")) != "deck_tile":
			continue
		if not str(placement.get("_is", "")).begins_with("boat deck"):
			continue
		var corners := PieceKit.placed_corners(placement)
		if corners.size() != 4:
			continue
		var lo := corners[0]
		var hi := corners[0]
		for point in corners:
			lo = Vector3(minf(lo.x, point.x), minf(lo.y, point.y), minf(lo.z, point.z))
			hi = Vector3(maxf(hi.x, point.x), maxf(hi.y, point.y), maxf(hi.z, point.z))
			low = minf(low, point.y)
			high = maxf(high, point.y)
		## y = a*x + b*z + c through three of the tile's corners. The tile is a
		## plane by construction (`fall` drops both far corners together), which
		## `_check_trim_lattice` asserts separately.
		var p0 := corners[0]
		var p1 := corners[1]
		var p2 := corners[2]
		var u := p1 - p0
		var v := p2 - p0
		var n := u.cross(v)
		if absf(n.y) < 1e-9:
			continue
		tiles.append({"lo": lo, "hi": hi, "n": n, "p": p0})
	var sampled := 0
	var outside := 0
	var worst := 0.0
	for placement_variant in doc.get("pieces", []) as Array:
		var placement := placement_variant as Dictionary
		if not SHELL_PIECES.has(str(placement.get("piece", ""))):
			continue
		if not str(placement.get("_is", "")).begins_with(prefix):
			continue
		var result := PieceKit.resolve_placement(placement, 1)
		## The piece's own head, which for a glazed panel is the HEADER and not the
		## coaming under it — the same "highest of the plates it draws" rule
		## `_lateral_edges` uses. Sampling every plate would measure the window sill
		## against the roof and report a metre and a quarter of nothing.
		var heads := PackedVector3Array()
		for step in (result["items"] as Array).size():
			var corners := PieceKit.placed_corners(placement, step)
			if corners.size() != 4:
				continue
			if not heads_not_feet:
				## Feet: every plate of a piece shares them, so the first is the piece's.
				heads = PackedVector3Array([corners[1], corners[0]])
				break
			if heads.is_empty():
				heads = PackedVector3Array([corners[2], corners[3]])
				continue
			if corners[2].y > heads[0].y:
				heads[0] = corners[2]
			if corners[3].y > heads[1].y:
				heads[1] = corners[3]
		if not heads.is_empty():
			for point in heads:
				var best := INF
				for tile_variant in tiles:
					var tile := tile_variant as Dictionary
					var lo := tile["lo"] as Vector3
					var hi := tile["hi"] as Vector3
					if point.x < lo.x - 1e-6 or point.x > hi.x + 1e-6:
						continue
					if point.z < lo.z - 1e-6 or point.z > hi.z + 1e-6:
						continue
					var n := tile["n"] as Vector3
					var p := tile["p"] as Vector3
					var y := p.y - (n.x * (point.x - p.x) + n.z * (point.z - p.z)) / n.y
					best = minf(best, absf(point.y - y))
				if best == INF:
					continue
				sampled += 1
				worst = maxf(worst, best)
				if best > DECK_GAUGE_M * 0.5 + 1e-9:
					outside += 1
	return {"sampled": sampled, "outside": outside, "worst": worst, "fall": high - low}


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
