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
	_check_cross_products()
	_check_openings_fit()
	_check_production_path()
	_check_shell_closes()
	_check_every_shell()
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

	## ── The opening/span constraint ──────────────────────────────────────────
	##
	## The one relationship in the kit whose LEFT-HAND SIDE depends on a CHOICE:
	## how many cells of panel a hole needs is a fact about WHICH hole. A 1.20 m
	## door wants 3 cells, a 0.80 m window 2, a 0.40 m scuttle 1, and no
	## per-parameter value set can say that — `span` and `opening` are each legal
	## alone. Before it existed the baker CLAMPED: `plate_openings` cuts the
	## opening down to what is left of the plate, so a door on a two-cell panel
	## came out as a 1.00 m hole with NO plating either side of it, silently, which
	## is the "a kit whose pieces quietly change size" failure the header forbids.
	var narrow := PieceKit.resolve("wall_panel", {"span": 2, "opening": "door"})
	_t.check(
		"a door on a two-cell panel is refused, not clamped to what fits",
		(narrow["specs"] as Array).is_empty()
	)
	_t.check(
		"and the refusal names the span: %s" % ", ".join(narrow["errors"] as PackedStringArray),
		_says(narrow["errors"] as PackedStringArray, "span")
	)
	## Paired, so the constraint is not simply refusing everything — which is the
	## cheapest way for a refusal to look like a working rule.
	_t.check(
		"the same door on a three-cell panel draws",
		not (PieceKit.resolve("wall_panel", {"span": 3, "opening": "door"})["specs"] as Array).is_empty()
	)
	_t.check(
		"...and a two-cell panel still takes a window",
		not (PieceKit.resolve("wall_panel", {"span": 2, "opening": "window"})["specs"] as Array).is_empty()
	)
	_t.check(
		"...and a one-cell panel still takes a scuttle",
		not (PieceKit.resolve("wall_panel", {"span": 1, "opening": "scuttle"})["specs"] as Array).is_empty()
	)
	_t.check(
		"...and a one-cell panel with no opening at all is still a panel",
		not (PieceKit.resolve("wall_panel", {"span": 1, "opening": "none"})["specs"] as Array).is_empty()
	)
	## THE PROPERTY, not the numbers: whatever the kit's holes are sized at, no
	## legal (span, opening) pair may resolve to an opening the baker had to shrink
	## to make fit. Stated over the whole cross product rather than the three cases
	## above, so widening a hole without widening its constraint turns this red.
	var clamped := PackedStringArray()
	var pairs := 0
	var params := PieceKit.params_of("wall_panel")
	for span_value in (params["span"] as Dictionary)["values"] as Array:
		for opening_value in (params["opening"] as Dictionary)["values"] as Array:
			var given := {"span": span_value, "opening": opening_value}
			var resolved := PieceKit.resolve("wall_panel", given)
			var specs := resolved["specs"] as Array
			if specs.is_empty():
				continue
			pairs += 1
			var spec := specs[0] as Dictionary
			var corners: Array = []
			for corner in spec["corners"] as PackedVector3Array:
				corners.append([corner.x, corner.y, corner.z])
			var probe := {"corners": corners, "thickness": float(spec["thickness"])}
			var ref := StructureBaker.plate_ref_lengths(StructureBaker.plate_corners(probe))
			probe["openings"] = spec.get("openings", [])
			for asked_variant in probe["openings"] as Array:
				var asked := asked_variant as Dictionary
				var got_list := StructureBaker.plate_openings(probe, ref)
				if got_list.is_empty():
					clamped.append("%s@span %s: the opening vanished" % [opening_value, span_value])
					continue
				var got := got_list[0] as Dictionary
				if absf(float(got["w"]) - float(asked["width"])) > 1e-6 \
						or absf(float(got["off"]) - float(asked["offset"])) > 1e-6 \
						or absf(float(got["h"]) - float(asked["height"])) > 1e-6:
					clamped.append(
						"%s@span %s: asked %.3f wide at %.3f, got %.3f at %.3f"
						% [opening_value, span_value, float(asked["width"]),
						   float(asked["offset"]), float(got["w"]), float(got["off"])]
					)
	_t.check("the span x opening cross product was walked (%d legal pairs draw)" % pairs, pairs >= 12)
	_t.check(
		"no legal (span, opening) pair resolves to an opening the baker had to shrink (%d: %s)"
		% [clamped.size(), "none" if clamped.is_empty() else clamped[0]],
		clamped.is_empty()
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

	## `sqrt` and `abs`, which the door's geometry needs: an opening is measured
	## ALONG the plate, and a raked plate's surface length is Pythagorean. Before
	## these the kit could not say so, and what it could not say it did not check.
	var fn_errors := PackedStringArray()
	_t.near("sqrt(2.5*2.5+1.0*1.0) is the v-length of a wall raked 1.0 m over 2.5 m",
		PieceKit._eval("sqrt(2.5*2.5+1.0*1.0)", {}, "probe", fn_errors), 2.6925824, 1e-6)
	_t.near("abs(-4)*0.125 is 0.5 whichever way the fall goes",
		PieceKit._eval("abs(-4)*0.125", {}, "probe", fn_errors), 0.5)
	_t.near("a function binds tighter than the arithmetic round it: 1/sqrt(4)+1 is 1.5",
		PieceKit._eval("1/sqrt(4)+1", {}, "probe", fn_errors), 1.5)
	_t.check("and those parsed with no complaint", fn_errors.is_empty())
	var bad_fn := PackedStringArray()
	var _w := PieceKit._eval("hypot(3)", {}, "probe", bad_fn)
	_t.check(
		"an unknown function is NAMED, not read as a parameter: %s" % ", ".join(bad_fn),
		_says(bad_fn, "no function")
	)
	var neg_root := PackedStringArray()
	var _x := PieceKit._eval("sqrt(0-1)", {}, "probe", neg_root)
	_t.check(
		"sqrt of a negative is an error, not a plausible 0: %s" % ", ".join(neg_root),
		_says(neg_root, "negative")
	)
	## A derived name resolves in a constraint, in the build tree and in the
	## footprint alike — one formula, and the piece cannot hold two copies of it.
	var derived_errors := PackedStringArray()
	_t.near(
		"wall_panel's own `door_h` is the opening height its build step asks for",
		PieceKit._eval(
			"door_h",
			PieceKit._with_derived(
				(PieceKit.get_piece("wall_panel")["derived"] as Array),
				{"span": 4.0, "height": 5.0, "head": 0.0, "rake": 8.0, "fall": 0.0, "lift": 0.0},
				"probe", derived_errors
			),
			"probe", derived_errors
		),
		2.10 * 2.6925824 / 2.5, 1e-6
	)
	_t.check("and it evaluated with no complaint", derived_errors.is_empty())


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

	## THE WRONG WAY TO CHAIN A FALL, and the kit now says so in `fall`'s own words
	## because a critic read the old wording as a promise that it chained by itself.
	## Taking the drop out of `lift` moves the WHOLE piece: the head closes and the
	## FOOT opens by the same 0.125*fall. There is no setting that does neither.
	## `matched` is panel B still carrying A's STARTING head — the natural mistake,
	## and on its own it leaves the joint 0.125 m open.
	var matched := next.duplicate(true)
	(matched["params"] as Dictionary)["head"] = 1
	_t.near(
		"a neighbour that keeps the falling panel's STARTING head is 0.125 m out",
		ca[3].distance_to(PieceKit.placed_corners(matched)[2]), 0.125, 1e-9
	)
	var by_lift := matched.duplicate(true)
	(by_lift["params"] as Dictionary)["lift"] = -1
	var cl := PieceKit.placed_corners(by_lift)
	_t.near("taking a fall out of `lift` closes the head", ca[3].distance_to(cl[2]), 0.0, 1e-9)
	_t.near(
		"and opens the FOOT by exactly the same 0.125 m — head or foot, never neither",
		ca[0].distance_to(cl[1]), 0.125, 1e-9
	)
	var same_fall := matched.duplicate(true)
	(same_fall["params"] as Dictionary)["fall"] = 1
	_t.near(
		"and two panels at the SAME fall are a sawtooth, not a plane: 0.125 m at the joint",
		ca[3].distance_to(PieceKit.placed_corners(same_fall)[2]), 0.125, 1e-9
	)

	## A STRAKE ON A WALL THAT TUMBLES HOME. `offset` was 0..8 and only pushed
	## OUTBOARD, while its own `_is` claimed it solved a raked wall — half true. A
	## wall at rake -8 leans 1.00 m INBOARD over 2.50 m, so at 2.00 m up the plating
	## is 0.80 m inboard of the foot line and no positive offset reaches it. The
	## claim here is the one that matters: the strake TOUCHES THE PLATING.
	var wall_in := PieceKit.resolve("wall_panel", {"span": 4, "height": 5, "rake": -8})
	var wc := ((wall_in["specs"] as Array)[0] as Dictionary)["corners"] as PackedVector3Array
	## Plating z at 2.00 m up, interpolated between foot (z 0) and head (z +1.00).
	var plating_z := wc[1].z + (wc[2].z - wc[1].z) * (2.00 / wc[2].y)
	var best := INF
	var best_offset := 0
	for value in PieceKit.params_of("trim_band")["offset"]["values"] as Array:
		var strake := PieceKit.resolve("trim_band", {"span": 4, "profile": "strake", "offset": int(value)})
		var sc := ((strake["specs"] as Array)[0] as Dictionary)["corners"] as PackedVector3Array
		## The strake's own face sits 0.05 m proud; the gap is what is left.
		var gap := absf((sc[0].z + 0.05) - plating_z)
		if gap < best:
			best = gap
			best_offset = int(value)
	_t.check(
		"a strake reaches a wall that TUMBLES HOME: offset %d leaves %.4f m (the old set's "
		% [best_offset, best] + "best was 0.355 m and it could only push outboard)",
		best < 0.07 and best_offset < 0
	)
	_t.check(
		"and the set really does reach inboard",
		(PieceKit.params_of("trim_band")["offset"]["values"] as Array).has(-8)
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

	## THE CHAIN IS BUILT RAKED, and that is not a detail. The first version of this
	## check built it at the default rake 0 — the ONE value at which both chain modes
	## agree — so it could not see the 0.1768 m of daylight the shipped fixture had,
	## and its negative control slid a facet one cell sideways: a POSITIONAL mutation
	## on a check whose real failure mode is a PARAMETER. REALITY §4 and standing
	## order 8. The rake below is the ferry-bow case the piece's own text names.
	var span := 8
	var rake := -2
	var facets: Array = []
	for i in 3:
		facets.append({
			"id": "facet %d" % i, "piece": "corner_45",
			"cell": [24 - span * i, 0, span * i], "facing": 0,
			"params": {"span": span, "height": 5, "chain": "run", "rake_a": rake, "rake_b": rake},
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
		"three RAKED facets chained in `chain: run` share every joint BIT-IDENTICALLY "
		% [] + "(rake %d, worst %.9f m)" % [rake, worst], open, 0
	)

	## THE RAKE IS STILL A RAKE. Closing the joints is cheap — any consistent wrong
	## number closes them, because every facet carries the same one. What pins the
	## geometry is the PROPERTY: the top edge stands 0.125*rake m outboard of the
	## foot edge measured PERPENDICULAR TO THE WALL, exactly as it does on a
	## wall_panel. Splitting 0.125 into each axis instead of 0.125/sqrt2 closes every
	## joint and silently makes the wall 41% more raked than the player asked for.
	var wrong := 0
	var measured := 0.0
	for facet in facets:
		var c := PieceKit.placed_corners(facet as Dictionary)
		if c.size() != 4:
			wrong += 1
			continue
		var along := (c[1] - c[0]).normalized()
		var normal := Vector3(along.z, 0.0, -along.x).normalized()
		var offset := ((c[2] + c[3]) * 0.5 - (c[0] + c[1]) * 0.5).dot(normal)
		measured = offset
		if absf(absf(offset) - absf(float(rake)) * 0.125) > 1e-6:
			wrong += 1
	_t.equal(
		"and every facet's top stands %.4f m off its foot perpendicular to the wall, "
		% absf(measured) + "which is |rake| eighth-cells and nothing else", wrong, 0
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

	## MUTATION A — THE PARAMETER. The same three facets in the default
	## `chain: corner`, which is what the strict fixture shipped with. Each top
	## corner then moves along an AXIS wall's normal instead of the facet's, and the
	## joint opens by 0.125*sqrt(rake_a^2 + rake_b^2) — 0.3536 m at rake -2.
	var axis_mode: Array = facets.duplicate(true)
	var axis_open := 0
	var axis_gap := 0.0
	for facet in axis_mode:
		((facet as Dictionary)["params"] as Dictionary)["chain"] = "corner"
	for i in 2:
		var here := PieceKit.placed_corners(axis_mode[i] as Dictionary)
		var next := PieceKit.placed_corners(axis_mode[i + 1] as Dictionary)
		if here[2] != next[3]:
			axis_open += 1
		axis_gap = maxf(axis_gap, here[2].distance_to(next[3]))
	_t.check(
		"MUTATION: the same chain in `chain: corner` opens %d of 2 joints (was 0)" % axis_open,
		axis_open == 2
	)
	_t.near(
		"MUTATION: and by exactly 0.125*sqrt(rake_a^2+rake_b^2)",
		axis_gap, 0.125 * sqrt(float(rake * rake + rake * rake)), 1e-6
	)
	_t.check(
		"MUTATION: while its FEET stay closed, which is why it looked fine",
		PieceKit.placed_corners(axis_mode[0] as Dictionary)[1]
			== PieceKit.placed_corners(axis_mode[1] as Dictionary)[0]
	)

	## MUTATION B — THE POSITION. Kept, because a chain can break two ways.
	var bent: Array = facets.duplicate(true)
	(bent[1] as Dictionary)["cell"] = [24 - span + 1, 0, span]
	var bent_open := 0
	for i in 2:
		var here := PieceKit.placed_corners(bent[i] as Dictionary)
		var next := PieceKit.placed_corners(bent[i + 1] as Dictionary)
		if here.size() != 4 or next.size() != 4 or here[1] != next[0] or here[2] != next[3]:
			bent_open += 1
	_t.check(
		"MUTATION: one cell of offset on the middle facet opens %d of 2 joints (was 0)"
		% bent_open, bent_open > 0
	)


# ── THE PRODUCTION PATH, which is where every other check in this file is not ─
#
# Everything above resolves a placement with `PieceKit.resolve_*` and measures
# the corners that come back. That is the RESOLVER. For most of this wave the
# game did not call it: `StructureBaker` had no reference to `pieces[]`, and a
# plan handed to `bake()` drew its hull and its sheer band and NOTHING of the
# superstructure. Measured on `probe_piece_trawler` before the seam was wired:
# 6224 triangles and 596 colliders as authored against 7388 and 788 resolved —
# 1164 triangles and 192 collider boxes that existed only inside the test rig,
# because `piece_kit_capture.gd` resolves into a `user://` copy BEFORE baking.
# REALITY §3, the layer trap, exactly: correct fixtures, correct resolver,
# honest captures, and a path the game does not take.
#
# `StructureBaker.resolved()` now opens both public entries. These checks hold it
# there. They assert the PROPERTY — a plan carrying placements bakes and collides
# identically to the same plan with those placements already resolved — so they
# survive any change to how the resolution is reached, and they go red the moment
# either entry stops resolving.
#
# `collect_colliders` is used for the per-fixture sweep because it is the cheap
# entry; the mesh identity is asserted on a synthetic plan that carries one of
# every piece, including the two that resolve to more than one plate.

func _check_production_path() -> void:
	## One of every piece, and deliberately including `wall_glazed` (five plates
	## from one placement) and an `opening` (which changes both triangle count and
	## collider count). A one-plate-per-placement approximation passes a wall_panel
	## and fails here.
	var placements: Array = [
		{"id": 1, "piece": "wall_panel", "cell": [0, 0, 0], "facing": 0,
			"params": {"span": 4, "height": 5, "opening": "door"}},
		{"id": 2, "piece": "wall_glazed", "cell": [4, 0, 0], "facing": 0,
			"params": {"span": 4, "height": 5, "sill": 2, "band": 2, "lights": 3}},
		{"id": 3, "piece": "corner_45", "cell": [8, 0, 0], "facing": 0,
			"params": {"span": 2, "height": 5, "rake_a": 3, "rake_b": -1}},
		{"id": 4, "piece": "deck_tile", "cell": [0, 5, 0], "facing": 0,
			"params": {"span": 8, "depth": 4, "fall": 2, "lift": 1}},
		{"id": 5, "piece": "roof_slope", "cell": [0, 5, 4], "facing": 0,
			"params": {"span": 8, "depth": 2, "rise": 1}},
		{"id": 6, "piece": "trim_band", "cell": [0, 5, 0], "facing": 0,
			"params": {"span": 8, "profile": "eave", "offset": -2}},
	]
	var doc := {"format": "structure_plan_v1", "hull_id": "hull_28x10", "pieces": placements}
	var authored := StructurePlan.from_dict(doc)
	var resolved := StructurePlan.from_dict(
		PieceKit.resolve_document(doc.duplicate(true))["doc"] as Dictionary
	)
	_t.check(
		"the authored plan really does carry placements and no items (%d/%d)"
		% [authored.pieces.size(), authored.items.size()],
		authored.pieces.size() == 6 and authored.items.size() == 0
	)
	_t.check(
		"and its resolved twin carries %d items and no placements — the two are not the "
		% resolved.items.size() + "same object dressed twice",
		resolved.items.size() > authored.pieces.size() and resolved.pieces.is_empty()
	)

	var a_tris := _bake_triangles(authored)
	var r_tris := _bake_triangles(resolved)
	_t.equal(
		"StructureBaker.bake() draws a plan's PLACEMENTS: %d triangles as authored, "
		% a_tris + "%d with them pre-resolved" % r_tris, a_tris, r_tris
	)
	var a_cols := StructureBaker.collect_colliders(authored).size()
	var r_cols := StructureBaker.collect_colliders(resolved).size()
	_t.equal(
		"StructureBaker.collect_colliders() collides them too: %d against %d"
		% [a_cols, r_cols], a_cols, r_cols
	)
	## ONE DERIVATION (REALITY §3b): what is DRAWN and what is COLLIDED have to come
	## from the same resolution, and the sharpest thing to point at is the door —
	## `wall_panel`'s `opening` is a hole with a casing, so it changes the mesh AND
	## splits the plate's collider (10 plates give %d boxes, not 10). An entry that
	## resolved placements for drawing and not for collision passes the two identity
	## checks above on its own; it cannot pass this.
	var no_door := doc.duplicate(true)
	((no_door["pieces"] as Array)[0] as Dictionary)["params"] = {
		"span": 4, "height": 5, "opening": "none",
	}
	var plain := StructurePlan.from_dict(no_door)
	var plain_tris := _bake_triangles(plain)
	var plain_cols := StructureBaker.collect_colliders(plain).size()
	_t.check(
		"the door in a PLACEMENT reaches the mesh (%d triangles with it, %d without) "
		% [a_tris, plain_tris] + "and the collider (%d boxes against %d)" % [a_cols, plain_cols],
		plain_tris != a_tris and plain_cols != a_cols
	)
	_t.equal(
		"and that plan too bakes identically authored or pre-resolved",
		plain_tris,
		_bake_triangles(StructurePlan.from_dict(
			PieceKit.resolve_document(no_door.duplicate(true))["doc"] as Dictionary
		))
	)

	## NEGATIVE CONTROL, and it is the one the coordinator's measurement turned on:
	## delete the placements and the counts must FALL. Without this the identity
	## above is satisfied by a baker that draws nothing from either plan.
	var stripped_doc := doc.duplicate(true)
	stripped_doc["pieces"] = []
	var stripped := StructurePlan.from_dict(stripped_doc)
	var s_tris := _bake_triangles(stripped)
	var s_cols := StructureBaker.collect_colliders(stripped).size()
	_t.check(
		"MUTATION: deleting the placements drops the bake from %d triangles to %d and "
		% [a_tris, s_tris] + "%d colliders to %d — they were contributing, not decorating"
		% [a_cols, s_cols],
		s_tris < a_tris and s_cols < a_cols
	)

	## AND OVER EVERY PIECE-BUILT FIXTURE IN THE REPO, not the one being worked on
	## (REALITY §3c). `collect_colliders` is the cheap entry; a full bake of the
	## trawler is about a minute under llvmpipe and this is a lane-A test.
	var swept := 0
	for stem in FIXTURE_SHELLS.keys():
		var fixture := _load("%s/%s.json" % [STRUCTURES_DIR, str(stem)])
		if fixture.is_empty():
			_t.fail("%s did not load" % stem)
			continue
		swept += 1
		var as_authored := StructurePlan.from_dict(fixture)
		var as_resolved := StructurePlan.from_dict(
			PieceKit.resolve_document(fixture.duplicate(true))["doc"] as Dictionary
		)
		var bare := fixture.duplicate(true)
		bare["pieces"] = []
		var without := StructurePlan.from_dict(bare)
		var authored_boxes := StructureBaker.collect_colliders(as_authored).size()
		var resolved_boxes := StructureBaker.collect_colliders(as_resolved).size()
		var bare_boxes := StructureBaker.collect_colliders(without).size()
		_t.equal(
			"%s: %d collider boxes as authored, %d pre-resolved — a player walks into "
			% [stem, authored_boxes, resolved_boxes] + "the same deckhouse either way",
			authored_boxes, resolved_boxes
		)
		_t.check(
			"%s: and %d of them are the %d placements' (bare plan has %d)"
			% [stem, authored_boxes - bare_boxes, (fixture["pieces"] as Array).size(), bare_boxes],
			authored_boxes > bare_boxes
		)
	_t.equal("swept every declared piece-built fixture", swept, FIXTURE_SHELLS.size())


func _bake_triangles(plan: StructurePlan) -> int:
	var node := StructureBaker.bake(plan)
	var tris := 0
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mesh := (child as MeshInstance3D).mesh
		if mesh == null:
			continue
		for surface in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(surface)
			var index: Variant = arrays[Mesh.ARRAY_INDEX]
			if index is PackedInt32Array:
				tris += (index as PackedInt32Array).size() / 3
			else:
				tris += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	node.queue_free()
	return tris


# ── Every shell, in every fixture, decomposed into RINGS ────────────────────
#
# `_seam_report` counts unmatched edges and a critic broke it three ways:
#
#   • it was only ever pointed at the trawler, so `probe_piece_house` — the
#     STRICT fixture, the evidence for the whole design — shipped with 0.1768 m
#     of daylight in the diagonal run its own note advertises, and two open
#     triangular ends on a `roof_slope` prism. Nothing was asking. (REALITY §4b.)
#   • "three closed rings" lived in a LABEL. The assertion was a piece COUNT, and
#     a count cannot tell one ring from three. Two wall panels facing each other
#     on ONE LINE have every OUT matched, `open == 0`, and enclose 0.000 m².
#   • the matcher was greedy first-fit, so two pieces presenting identical IN
#     edges could consume an edge a later OUT needed.
#
# So: match only where the mate is UNIQUE BOTH WAYS, follow the links into rings,
# and require every closed ring to enclose real plan area. Every fixture in the
# repo that carries `pieces[]` is walked, and one that is not declared here is a
# failure rather than a silence.

const STRUCTURES_DIR := "res://resources/data/structures"

const FIXTURE_SHELLS := {
	## Lower tier, wheelhouse, funnel. Nothing open.
	"probe_piece_trawler": {"rings": 3, "runs": 0, "run_pieces": 0},
	## The same three rings, plus the diagonal wall run — three chained facets
	## with two free ends, which is what a wall run IS.
	"probe_piece_house": {"rings": 3, "runs": 1, "run_pieces": 3},
	## Built through the studio's piece tool: casing ring, wheelhouse ring,
	## exhaust casing ring. Owned by `structure_studio.gd`; walked here because a
	## structural check that is pointed at one fixture is pointed at none.
	"probe_piece_tug": {"rings": 3, "runs": 0, "run_pieces": 0},
}

## Plan area a closed ring has to enclose to be a room and not a fence. The
## smallest ring the kit can build is a 1-cell square of four facets, 0.25 m².
const RING_MIN_AREA := 0.20


func _check_every_shell() -> void:
	var seen: Array = []
	var dir := DirAccess.open(STRUCTURES_DIR)
	if dir == null:
		_t.fail("cannot list %s" % STRUCTURES_DIR)
		return
	for file in dir.get_files():
		if not file.ends_with(".json"):
			continue
		var doc := _load("%s/%s" % [STRUCTURES_DIR, file])
		var pieces: Variant = doc.get("pieces", null)
		if not (pieces is Array) or (pieces as Array).is_empty():
			continue
		var stem := file.get_basename()
		seen.append(stem)
		var report := _shell_report(doc)
		if not FIXTURE_SHELLS.has(stem):
			## Not one of the kit's own fixtures — another agent's probe. Its ring
			## COUNT is its author's intent and this file has no business asserting
			## it, but the invariants below hold for any shell whatever it is for,
			## and they are asserted. The shape is printed so it is not a silence.
			print("  [shell] %s (undeclared): rings=%s runs=%d areas=%s open=%d"
				% [stem, str(report["rings"]), int(report["runs"]), str(report["areas"]),
					int(report["open"])])
			_t.check(
				"%s: undeclared fixture, but it is NOT a probe_piece_* one" % stem,
				not stem.begins_with("probe_piece_")
			)
			_t.equal(
				"%s: no ambiguous edge match (%s)" % [stem, str(report["ambiguous"])],
				(report["ambiguous"] as PackedStringArray).size(), 0
			)
			continue
		var want := FIXTURE_SHELLS[stem] as Dictionary
		_t.equal(
			"%s: no ambiguous edge match (%s)" % [stem, str(report["ambiguous"])],
			(report["ambiguous"] as PackedStringArray).size(), 0
		)
		_t.equal(
			"%s: %d closed rings" % [stem, int(report["rings"])], int(report["rings"]),
			int(want["rings"])
		)
		_t.equal(
			"%s: %d open runs, ends %s" % [stem, int(report["runs"]), str(report["open_ends"])],
			int(report["runs"]), int(want["runs"])
		)
		_t.equal(
			"%s: %d pieces in open runs" % [stem, int(report["run_pieces"])],
			int(report["run_pieces"]), int(want["run_pieces"])
		)
		var small := 0
		for area in report["areas"] as Array:
			if float(area) < RING_MIN_AREA:
				small += 1
		_t.equal(
			"%s: every ring encloses real plan area (%s m2)" % [stem, str(report["areas"])],
			small, 0
		)
	_t.check("walked every piece-built fixture in the repo (%s)" % str(seen), seen.size() >= 3)

	## MUTATION 1, and it is a PARAMETER mutation because the failure this check
	## missed was a parameter. Put the house's diagonal run back in the default
	## `chain: corner` — the mode it shipped in — and the two interior joints open
	## by 0.1768 m, so one run of three becomes three runs of one.
	var house := _load(HOUSE)
	var corner_mode := house.duplicate(true)
	var touched := 0
	for placement_variant in corner_mode["pieces"] as Array:
		var placement := placement_variant as Dictionary
		if not str(placement.get("_is", "")).begins_with("diagonal wall run"):
			continue
		(placement["params"] as Dictionary)["chain"] = "corner"
		touched += 1
	var broken := _shell_report(corner_mode)
	_t.check(
		"MUTATION: the %d diagonal facets back in chain \"corner\" break into %d runs (was 1)"
		% [touched, int(broken["runs"])],
		int(broken["runs"]) > 1
	)
	## And the gap is the derived one, not some other failure.
	var facets: Array = []
	for placement_variant in corner_mode["pieces"] as Array:
		var placement := placement_variant as Dictionary
		if str(placement.get("_is", "")).begins_with("diagonal wall run"):
			facets.append(placement)
	if facets.size() >= 2:
		var a_in := _lateral_edges(facets[0] as Dictionary)["in"] as PackedVector3Array
		var b_out := _lateral_edges(facets[1] as Dictionary)["out"] as PackedVector3Array
		_t.near(
			"MUTATION: and the head gap is 0.125*sqrt(rake_a^2+rake_b^2) = 0.1768 m",
			a_in[1].distance_to(b_out[1]), 0.125 * sqrt(2.0), 1e-5
		)
		_t.near("with the feet still closed", a_in[0].distance_to(b_out[0]), 0.0, 1e-5)

	## MUTATION 2 — THE FLAT FENCE. Two wall panels on ONE LINE facing each other.
	## Every OUT has a mate and `open == 0`, which is what the old check asked; the
	## ring encloses 0.000 m², which is what this one asks.
	var fence: Array = [
		{"id": "f0", "piece": "wall_panel", "cell": [0, 0, 0], "facing": 0,
			"params": {"span": 4, "height": 5}},
		{"id": "f1", "piece": "wall_panel", "cell": [4, 0, 0], "facing": 180,
			"params": {"span": 4, "height": 5}},
	]
	var fence_report := _shell_report({"pieces": fence})
	_t.equal(
		"MUTATION: a flat fence has no open edge at all (%d)" % int(fence_report["open"]),
		int(fence_report["open"]), 0
	)
	var fence_area := 0.0
	for area in fence_report["areas"] as Array:
		fence_area = maxf(fence_area, float(area))
	_t.check(
		"MUTATION: and it encloses %.4f m2, which the ring check refuses" % fence_area,
		int(fence_report["rings"]) > 0 and fence_area < RING_MIN_AREA
	)


## Shell decomposition. Returns {"rings","runs","run_pieces","areas","open",
## "open_ends","ambiguous"}.
##
## A link is only made where piece A's OUT edge matches piece B's IN edge AND no
## other piece's IN edge matches that OUT and no other OUT matches that IN. An
## ambiguous pair is reported, never guessed at — the greedy matcher this replaces
## could consume an edge a later piece needed and report a false open seam.
func _shell_report(doc: Dictionary) -> Dictionary:
	var pieces: Array = []
	for placement_variant in doc.get("pieces", []) as Array:
		var placement := placement_variant as Dictionary
		if not SHELL_PIECES.has(str(placement.get("piece", ""))):
			continue
		var edges := _lateral_edges(placement)
		if edges.is_empty():
			continue
		pieces.append({
			"label": _label(placement),
			"out": edges["out"], "in": edges["in"],
		})
	var count := pieces.size()
	var next_of: Dictionary = {}
	var prev_of: Dictionary = {}
	var ambiguous := PackedStringArray()
	for i in count:
		var out_edge := (pieces[i] as Dictionary)["out"] as PackedVector3Array
		var hits: Array = []
		for j in count:
			if _edges_meet(out_edge, (pieces[j] as Dictionary)["in"] as PackedVector3Array):
				hits.append(j)
		if hits.size() > 1 and ambiguous.size() < 4:
			ambiguous.append("%s has %d mates" % [str((pieces[i] as Dictionary)["label"]), hits.size()])
		if hits.size() == 1:
			next_of[i] = int(hits[0])
	for i in next_of.keys():
		var j := int(next_of[i])
		if prev_of.has(j):
			if ambiguous.size() < 4:
				ambiguous.append("%s is claimed twice" % str((pieces[j] as Dictionary)["label"]))
			continue
		prev_of[j] = int(i)
	var open := 0
	var open_ends := PackedStringArray()
	for i in count:
		if not next_of.has(i):
			open += 1
			if open_ends.size() < 6:
				open_ends.append(str((pieces[i] as Dictionary)["label"]))
	var visited: Dictionary = {}
	var rings := 0
	var runs := 0
	var run_pieces := 0
	var areas: Array = []
	## Open runs first: start at every piece with no predecessor and walk forward.
	for i in count:
		if prev_of.has(i) or visited.has(i):
			continue
		var walked := 0
		var cursor := i
		while not visited.has(cursor):
			visited[cursor] = true
			walked += 1
			if not next_of.has(cursor):
				break
			cursor = int(next_of[cursor])
		runs += 1
		run_pieces += walked
	## What is left is cycles.
	for i in count:
		if visited.has(i):
			continue
		var ring: Array = []
		var cursor := i
		while not visited.has(cursor):
			visited[cursor] = true
			ring.append(cursor)
			if not next_of.has(cursor):
				break
			cursor = int(next_of[cursor])
		rings += 1
		## Shoelace over the ring's OUT feet, in the order the links give them.
		var area := 0.0
		for k in ring.size():
			var a := ((pieces[int(ring[k])] as Dictionary)["out"] as PackedVector3Array)[0]
			var b := ((pieces[int(ring[(k + 1) % ring.size()])] as Dictionary)["out"] as PackedVector3Array)[0]
			area += a.x * b.z - b.x * a.z
		areas.append(snappedf(absf(area) * 0.5, 0.0001))
	return {
		"rings": rings, "runs": runs, "run_pieces": run_pieces, "areas": areas,
		"open": open, "open_ends": open_ends, "ambiguous": ambiguous,
	}


# ── The full cross product, for the pieces whose parameters INTERACT ────────
#
# `_extremes` moves one numeric parameter off its default at a time. Its own
# comment admits it, and a critic used that to find 109 settings of `corner_45`
# that the BAKER refuses as self-crossing quads and that no constraint named — a
# player picking them got silence and no plate. The interaction is between `span`
# and the two rakes, which one-at-a-time can never reach.
#
# The claim is NOT "everything draws". It is: NOTHING IS REFUSED IN SILENCE. A
# setting that the piece turns away in its own words is a good outcome.

func _check_cross_products() -> void:
	var silent := PackedStringArray()
	var named := 0
	var drawn := 0
	var p := PieceKit.params_of("corner_45")
	for chain in ["corner", "run"]:
		for span in p["span"]["values"]:
			for rake_a in p["rake_a"]["values"]:
				for rake_b in p["rake_b"]["values"]:
					for fall in [0, 4]:
						var setting := {
							"chain": chain, "span": span, "height": 2,
							"rake_a": rake_a, "rake_b": rake_b, "fall": fall,
						}
						var result := PieceKit.resolve("corner_45", setting)
						if not (result["specs"] as Array).is_empty():
							drawn += 1
							continue
						if _says(result["errors"] as PackedStringArray, "which is under"):
							named += 1
						elif silent.size() < 4:
							silent.append("%s: %s" % [str(setting), ", ".join(result["errors"] as PackedStringArray)])
	_t.equal(
		"corner_45's full (chain x span x rake_a x rake_b x fall) cross draws %d and refuses %d "
		% [drawn, named] + "IN ITS OWN WORDS — %d refused in silence (%s)"
		% [silent.size(), "none" if silent.is_empty() else silent[0]],
		silent.size(), 0
	)
	## And the constraint is not just refusing everything: the settings the fleet
	## actually uses have to survive it.
	for probe in [
		{"span": 1, "rake_a": 4, "rake_b": -1}, {"span": 1, "rake_a": 7, "rake_b": -1},
		{"span": 4, "chain": "run", "rake_a": -1, "rake_b": -1}, {"span": 8, "rake_a": -8, "rake_b": 8},
	]:
		_t.check(
			"and %s still draws" % str(probe),
			not (PieceKit.resolve("corner_45", probe)["specs"] as Array).is_empty()
		)

	## `wall_glazed`'s (height, sill, band, head, fall) space is half illegal —
	## measured, and every one of those is the header constraint speaking.
	var g_silent := PackedStringArray()
	var g_named := 0
	var g_drawn := 0
	var g := PieceKit.params_of("wall_glazed")
	for height in g["height"]["values"]:
		for sill in g["sill"]["values"]:
			for band in g["band"]["values"]:
				for head in g["head"]["values"]:
					for fall in g["fall"]["values"]:
						var setting := {
							"height": height, "sill": sill, "band": band,
							"head": head, "fall": fall,
						}
						var result := PieceKit.resolve("wall_glazed", setting)
						if not (result["specs"] as Array).is_empty():
							g_drawn += 1
						elif _says(result["errors"] as PackedStringArray, "which is under"):
							g_named += 1
						elif g_silent.size() < 4:
							g_silent.append("%s: %s" % [str(setting), ", ".join(result["errors"] as PackedStringArray)])
	_t.equal(
		"wall_glazed's full (height x sill x band x head x fall) cross: %d draw, %d are refused "
		% [g_drawn, g_named] + "in words, %d in silence (%s)"
		% [g_silent.size(), "none" if g_silent.is_empty() else g_silent[0]],
		g_silent.size(), 0
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


# ── The hole a panel asks for is the hole it gets ───────────────────────────
#
# `wall_panel`'s opening was related to `span` and to nothing else, and `span` is
# the ONE parameter that does not set the plate's v-length: `height`, `head`,
# `rake` and `fall` all do. Over the 91,800 legal settings that punch a hole,
# 19,742 — 21.5% — had that hole silently CUT DOWN by `plate_openings`, which
# clamps to `ref.y - sill`. A `height 2` panel with a `door` asked for a
# 1.20 x 1.95 m opening and got 1.20 x 1.00 with no lintel over it, and nothing
# in the kit, the baker or this test said a word. The piece's own header calls
# that out as the thing it exists to prevent.
#
# The two claims below are properties, not restatements:
#
#   THE HOLE. For every accepted setting, the opening the baker CUTS equals the
#   opening the piece ASKED FOR, to the bit, and every casing member the opening
#   calls for is emitted. Nothing here names a constraint or a number out of the
#   kit file — it compares what went in against what came out.
#
#   THE HEAD. An opening's sill and height are measured ALONG THE PLATE, so a
#   1.95 m door in a wall raked 1.0 m over 2.5 m stands 1.81 m tall in the world.
#   That is the bug the rake stepper shipped: the doorway stopped admitting a
#   1.80 m player between rake 3 and rake 4, and the stepper goes to 8. So the
#   claim is stated in WORLD VERTICAL — how far the lowest point of the head
#   stands above the panel's own foot — and the bar it has to clear is built out
#   of the player, the thickest sole the kit itself can lay under him, and the
#   collider hang. Not one of those terms is the door's own number.

## The player, and how far the physics world may sit below the drawing at a head:
## a casing box is fitted to the slab plus and minus half its 0.20 m thickness
## ALONG THE PLATE NORMAL, and a raked plate's normal tilts, so the lintel's box
## hangs below the lintel. Measured on a spawned vessel through PhysicsServer3D
## by `piece_interior_test`: 0.022 m at rake 2, 0.052 m at rake 8. This is the
## drawing-side bound, and it is the same 0.06 m that test allows a doorway to
## lose between the drawing and the physics — one number, two places to spend it.
const FIGURE_H := 1.80
const COLLIDER_HANG := 0.06
const HEAD_PLAY := 0.02

## `head` and `fall` are sampled rather than walked: both move the plate's
## v-length monotonically and neither interacts with the rake, so a quarter of
## each is a sample and the axis that carries the bug — `rake` — is complete,
## as are span, height and the opening choice. The full product is 146,880
## settings and 56 s; this is 40,800 and 14 s. `lift` is excluded because it is a
## pure translation of all four corners, which is checked in `_check_grid_units`.
const HEAD_SAMPLE: Array[int] = [0, 2, 5, 7]
const FALL_SAMPLE: Array[int] = [-4, -1, 0, 1, 4]


func _check_openings_fit() -> void:
	## THE WORST FLOOR THE KIT CAN LAY, read off the kit rather than typed here: a
	## deck tile's plate is centred on its node, so its walking surface stands half
	## its own gauge above the node the wall beside it stands on.
	var sole := 0.0
	for gauge in (PieceKit.params_of("deck_tile")["gauge"] as Dictionary)["values"] as Array:
		for spec_variant in PieceKit.resolve("deck_tile", {"gauge": gauge})["specs"] as Array:
			sole = maxf(sole, float((spec_variant as Dictionary).get("thickness", 0.0)) * 0.5)
	_t.check("the thickest sole the kit can lay stands %.3f m over its node" % sole, sole > 0.14)
	var need := FIGURE_H + sole + COLLIDER_HANG + HEAD_PLAY

	var p := PieceKit.params_of("wall_panel")
	var accepted := 0
	var clamped := PackedStringArray()
	var casing := PackedStringArray()
	var low := PackedStringArray()
	var worst_head := INF
	var worst_at := ""
	var doors := 0
	for opening in (p["opening"] as Dictionary)["values"] as Array:
		if str(opening) == "none":
			continue
		for span in (p["span"] as Dictionary)["values"] as Array:
			for height in (p["height"] as Dictionary)["values"] as Array:
				for head in HEAD_SAMPLE:
					for rake in (p["rake"] as Dictionary)["values"] as Array:
						for fall in FALL_SAMPLE:
							var setting := {
								"opening": opening, "span": span, "height": height,
								"head": head, "rake": rake, "fall": fall,
							}
							var result := PieceKit.resolve("wall_panel", setting)
							var specs := result["specs"] as Array
							if specs.is_empty():
								continue
							accepted += 1
							var spec := specs[0] as Dictionary
							var corners := StructureBaker.plate_corners(spec)
							var ref := StructureBaker.plate_ref_lengths(corners)
							var asked := (spec["openings"] as Array)[0] as Dictionary
							var cut := StructureBaker.plate_openings(spec, ref)
							if cut.size() != 1:
								if clamped.size() < 3:
									clamped.append("%s: the opening did not survive at all" % str(setting))
								continue
							var got := cut[0] as Dictionary
							if (absf(float(got["w"]) - float(asked["width"])) > 1e-6
									or absf(float(got["h"]) - float(asked["height"])) > 1e-6
									or absf(float(got["sill"]) - float(asked["sill"])) > 1e-6
									or absf(float(got["off"]) - float(asked["offset"])) > 1e-6):
								if clamped.size() < 3:
									clamped.append("%s: asked %.2f x %.3f at sill %.2f, cut %.2f x %.3f at sill %.2f"
										% [str(setting), float(asked["width"]), float(asked["height"]),
										   float(asked["sill"]), float(got["w"]), float(got["h"]),
										   float(got["sill"])])
								continue
							## A door has jambs and a lintel; anything with a sill has a
							## fourth member under it.
							var members := 4 if float(got["sill"]) > 0.05 else 3
							if StructureBaker.plate_frames(spec).size() < members and casing.size() < 3:
								casing.append("%s: %d casing members of %d"
									% [str(setting), StructureBaker.plate_frames(spec).size(), members])
							if str(opening) != "door":
								continue
							doors += 1
							var v := (float(got["sill"]) + float(got["h"])) / ref.y
							var clear := INF
							for i in 9:
								var u := lerpf(float(got["off"]),
									float(got["off"]) + float(got["w"]), float(i) / 8.0) / ref.x
								clear = minf(clear, StructureBaker.plate_point(corners, u, v).y)
							clear -= minf(corners[0].y, corners[1].y)
							if clear < worst_head:
								worst_head = clear
								worst_at = str(setting)
							if clear < need and low.size() < 3:
								low.append("%s: %.3f m of head, needs %.3f" % [str(setting), clear, need])
	_t.check(
		"wall_panel: %d accepted settings punch a hole and the baker cuts every one of them "
		% accepted + "AS ASKED — %d clamped (%s)"
		% [clamped.size(), "none" if clamped.is_empty() else clamped[0]],
		## The coverage floor: 16,877 settings punch a hole in the sampled sweep,
		## measured. A check that walks nothing passes everything.
		clamped.is_empty() and accepted > 16000
	)
	_t.check(
		"...and every one keeps its casing — %d short (%s)"
		% [casing.size(), "none" if casing.is_empty() else casing[0]],
		casing.is_empty()
	)
	_t.check(
		"every one of the %d accepted DOORS stands %.3f m clear over the panel's foot at its "
		% [doors, worst_head] + "worst point (%s), against %.3f m of player + sole + collider — "
		% [worst_at, need] + "%d too low (%s)"
		% [low.size(), "none" if low.is_empty() else low[0]],
		## 2,380 of the sampled settings carry a door, measured. A floor, so a
		## sweep that stops sweeping cannot pass by testing nothing.
		low.is_empty() and doors > 2300
	)

	## THE REFUSALS SPEAK, and these three are the settings a critic measured
	## being clamped in silence.
	for probe in [
		{"opening": "door", "span": 3, "height": 2},
		{"opening": "window", "span": 2, "height": 2},
		{"opening": "scuttle", "span": 1, "height": 3},
	]:
		var refusal := PieceKit.resolve("wall_panel", probe)
		_t.check(
			"%s is refused in the piece's own words (%s)"
			% [str(probe), ", ".join((refusal["errors"] as PackedStringArray))],
			(refusal["specs"] as Array).is_empty()
				and _says(refusal["errors"] as PackedStringArray, "which is under")
		)
	## ...and the constraint is not simply refusing every door: the whole rake
	## stepper still carries one on a tier-height panel, which is the case the
	## fleet is built out of and the case the old geometry lost.
	for rake in (p["rake"] as Dictionary)["values"] as Array:
		var built := PieceKit.resolve(
			"wall_panel", {"opening": "door", "span": 3, "height": 5, "rake": rake}
		)
		_t.check(
			"a tier-height panel still carries a door at rake %d" % int(rake),
			not (built["specs"] as Array).is_empty()
		)


func _load(path: String) -> Dictionary:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return raw as Dictionary if raw is Dictionary else {}


func _says(messages: PackedStringArray, needle: String) -> bool:
	for message in messages:
		if message.contains(needle):
			return true
	return false
