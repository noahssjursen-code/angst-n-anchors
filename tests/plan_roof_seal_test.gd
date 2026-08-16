extends SceneTree

## Lane A. DOES THE ROOF MEET THE WALL IT SITS ON? Run:
##   xvfb-run -a --server-args="-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy \
##     --script res://tests/plan_roof_seal_test.gd
##
## ── The defect this holds down ──────────────────────────────────────────────
##
## A raked wall's TOP EDGE stands `rake * 0.125 m` outboard of its foot; a
## `deck_tile`'s edges land only on the 0.5 m node lattice. Where the roof stops
## inboard of the head, a wedge of open sky runs the length of the wall, widest
## at the top. It is invisible in every render — a thin wedge at a roof/wall
## junction seen edge-on — and it un-rooms the compartment underneath, so a
## player gets a deckhouse that looks right, cannot be certified as a cabin and
## lets weather in, with nothing telling them why.
##
## ── The constraint is NOT "rake must be a multiple of four" ─────────────────
##
## Flush happens only at multiples of 4, which is where that claim came from, and
## flush is not what anybody needs: a roof that OVERHANGS the head seals just as
## well, and that overhang is the kit's own EAVE. Section A sweeps the whole rake
## set against eaves of 0, 1 and 2 cells and asserts the inequality
##
##     sealed  <=>  eave_cells * 0.5 >= max(rake, 0) * 0.125
##
## with `height`, `head` and ring size varied to show none of them moves it.
## Constraining `rake` to multiples of 4 would delete twelve of the kit's
## seventeen values, break `rake +4 / eave 0` anyway (which is `critic_ferry`'s
## saloon front, measured), and leave rake 5..8 with a one-cell eave still open.
##
## ── Sections ────────────────────────────────────────────────────────────────
##
## A. THE SWEPT PARAMETER SPACE. A four-wall ring with one roof tile, built out
##    of placements exactly as a player would put it down. Both directions:
##    every legal combination must be flagged or clean according to the
##    inequality, and the flagged ones must report the RIGHT SHORTFALL — a check
##    that only counts is one that cannot tell a 0.125 m wedge from a 1 m one.
##
## B. THE AUTHORED FIXTURES, as a ratchet. The fleet was authored around this
##    defect and five fixtures still carry it. Every fixture NOT on the list must
##    be clean, so a new one cannot regress quietly; every fixture ON it must
##    still be short, so fixing one turns this RED and says "delete your row".
##    The list is a record of open defects, not a tolerance.
##
## C. THE SEAM. `validate()` must put the finding in front of the builder, and
##    must stay quiet on a plan that is sealed.
##
## Mutation-verified: see the wave report for both numbers, including the BLIND
## variant — reading the wall's head off its grid NODE instead of off its drawn
## corners, which is the same source the roof is placed from and which goes green
## on every one of the seventeen real gaps.

const TestReport := preload("res://tests/support/test_report.gd")
const PO := preload("res://scripts/ship/plan_outfit.gd")
const HULL := "hull_28x10"
const EXPECTED_CHECKS := 116

## Fixtures whose roof is short of a wall head TODAY, worst gap in metres,
## measured 2026-08-16. Each row is an OPEN DEFECT IN THE FIXTURE — the drawing
## is missing an eave — not a tolerance this reading is allowed. Fix the fixture
## and delete the row; the check below will tell you which.
const KNOWN_SHORT := {
	"critic_ferry": 0.718,
	"probe_piece_house": 0.374,
	"probe_piece_trawler": 0.374,
	"probe_piece_tug": 0.386,
	"critic_yacht": 0.144,
}

var _t: TestReport


func _initialize() -> void:
	_t = TestReport.new("plan_roof_seal_test")
	PieceKit.ensure_loaded()
	_test_the_swept_parameter_space()
	_test_the_shortfall_is_measured()
	_test_the_shipped_fleet()
	_test_the_seam()
	_t.equal(
		"the run executed every check it was written with",
		_t.check_count() + 1, EXPECTED_CHECKS,
	)
	_t.finish(self)


# ── A. the swept parameter space ────────────────────────────────────────────

func _test_the_swept_parameter_space() -> void:
	## Ring sizes are chosen so that `span + 2 * eave` stays in `deck_tile`'s
	## declared span set {1,2,3,4,6,8,12,16} at every eave below — a 4-cell ring
	## with a 1-cell eave wants a 6-cell tile, which is legal, while an 8-cell one
	## would want 10, which is not. That is a real limit of the kit and it is why
	## these two sizes and not three.
	for rake in range(-8, 9):
		for eave in [0, 1, 2]:
			var gaps := PO.roof_gaps(_ring(4, 4, 5, 0, rake, eave))
			_t.check(
				"rake %+d under a %.1f m eave: %s" % [
					rake, float(eave) * 0.5,
					"sealed" if _seals(rake, eave) else "open sky at the head",
				],
				gaps.is_empty() == _seals(rake, eave),
			)
	## REALITY §4d — vary ONE input. If wall height, the `head` trim or the ring's
	## size moved this answer, the constraint would not be the plan-space
	## inequality above and every row here would disagree with the rows above.
	for variant in [
		[4, 4, 2, 0], [4, 4, 6, 0], [4, 4, 5, 3], [4, 4, 5, 7], [2, 2, 5, 0],
	]:
		var clean := true
		for rake in range(-8, 9):
			var gaps := PO.roof_gaps(
				_ring(variant[0], variant[1], variant[2], variant[3], rake, 1)
			)
			if gaps.is_empty() != _seals(rake, 1):
				clean = false
		_t.check(
			"a %d x %d ring, height %d, head %d answers the same at every rake"
			% [variant[0], variant[1], variant[2], variant[3]],
			clean,
		)


## The property, in one line: a roof seals a raked head when it reaches at least
## as far out as the head does. A NEGATIVE rake tumbles the head home and needs
## no eave at all.
static func _seals(rake: int, eave: int) -> bool:
	return float(eave) * 0.5 + 0.0001 >= float(maxi(rake, 0)) * 0.125


# ── A2. and it measures how far short, not just that it is ──────────────────

func _test_the_shortfall_is_measured() -> void:
	for rake in [1, 2, 3, 4, 5, 6, 7, 8]:
		for eave in [0, 1]:
			if _seals(rake, eave):
				continue
			var gaps := PO.roof_gaps(_ring(4, 4, 5, 0, rake, eave))
			if not _t.check(
				"rake %+d under a %.1f m eave is flagged" % [rake, float(eave) * 0.5],
				not gaps.is_empty(),
			):
				continue
			var expected := float(rake) * 0.125 - float(eave) * 0.5
			_t.near(
				"and it is %.3f m short, not merely short" % expected,
				float((gaps[0] as Dictionary)["short_m"]), expected, 0.03,
			)


# ── B. the shipped fleet, as a ratchet ──────────────────────────────────────

func _test_the_shipped_fleet() -> void:
	var stems := _stems()
	if not _t.check("the fixtures are readable (%d)" % stems.size(), stems.size() >= 19):
		return
	for stem in stems:
		var plan := _plan(stem)
		if plan == null:
			continue
		var gaps := PO.roof_gaps(plan)
		if not KNOWN_SHORT.has(stem):
			_t.check(
				"%s: every roof reaches the wall it sits on%s" % [
					stem,
					"" if gaps.is_empty() else " — %d short, worst %.3f m at %s" % [
						gaps.size(), float((gaps[0] as Dictionary)["short_m"]),
						str((gaps[0] as Dictionary)["at"]),
					],
				],
				gaps.is_empty(),
			)
			continue
		## The ratchet. If this fires, somebody has fixed the fixture — good, and
		## the row above belongs in the bin, not in this file.
		_t.check(
			"%s is STILL short of its own wall heads (open defect; if this failed,"
			% stem + " the fixture was fixed — delete its KNOWN_SHORT row)",
			not gaps.is_empty(),
		)
		if gaps.is_empty():
			continue
		_t.near(
			"%s's worst gap is the one on record" % stem,
			float((gaps[0] as Dictionary)["short_m"]),
			float(KNOWN_SHORT[stem]),
			0.02,
		)
		_t.check(
			"%s names the piece that is short (%s #%s)" % [
				stem, str((gaps[0] as Dictionary)["piece"]),
				str((gaps[0] as Dictionary)["id"]),
			],
			not str((gaps[0] as Dictionary)["piece"]).is_empty(),
		)


# ── C. the seam ─────────────────────────────────────────────────────────────

func _test_the_seam() -> void:
	_t.check("roof_gaps(null) is empty", PO.roof_gaps(null).is_empty())
	var bare := StructurePlan.new()
	bare.hull_id = HULL
	_t.check(
		"a plan with no placements has nothing to say about rake",
		PO.roof_gaps(bare).is_empty(),
	)
	var grid := HullRegistry.make_grid(HULL)
	var open := PO.validate(_ring(4, 4, 5, 0, 8, 1), HULL, grid)
	var warnings := open["warnings"] as PackedStringArray
	var named := false
	for line in warnings:
		if line.contains("short of this wall's head"):
			named = true
	_t.check("validate tells the builder the roof is short", named)
	_t.check(
		"and it is a WARNING, not a refusal — the drawing is buildable",
		bool(open["ok"]),
	)
	var sealed := PO.validate(_ring(4, 4, 5, 0, 8, 2), HULL, grid)
	var quiet := true
	for line in sealed["warnings"] as PackedStringArray:
		if line.contains("short of this wall's head"):
			quiet = false
	_t.check("and says nothing about a ring whose eave carries its rake", quiet)


# ── The ring ────────────────────────────────────────────────────────────────

## A four-wall deckhouse with one roof tile, entirely out of placements: no
## hand-authored plate, no coordinate typed, exactly what the kit is for.
static func _ring(
	span_a: int, span_b: int, height: int, head: int, rake: int, eave: int
) -> StructurePlan:
	var eighths := height * 4 + head
	var level := int(round(float(eighths) / 4.0))
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
			"id": id, "piece": "wall_panel",
			"cell": [cell.x, cell.y, cell.z], "facing": row[1],
			"params": {
				"span": row[2], "height": height, "head": head, "rake": rake,
				"opening": "door" if id == 1 else "none",
			},
		})
		id += 1
	pieces.append({
		"id": id, "piece": "deck_tile",
		"cell": [-eave, level, -eave], "facing": 0,
		"params": {
			"span": span_a + 2 * eave, "depth": span_b + 2 * eave,
			"lift": eighths - level * 4,
		},
	})
	return StructurePlan.from_dict({
		"version": 1, "hull_id": HULL, "name": "ring",
		"walls": [], "decks": [], "stairs": [], "edges": [], "items": [],
		"pieces": pieces,
	})


static func _stems() -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open("res://resources/data/structures")
	if dir == null:
		return out
	var names := dir.get_files()
	names.sort()
	for name in names:
		if name.ends_with(".json"):
			out.append(name.get_basename())
	return out


static func _plan(stem: String) -> StructurePlan:
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(
			"res://resources/data/structures/%s.json" % stem
		)
	)
	if not (parsed is Dictionary) or not StructurePlan.is_plan(parsed as Dictionary):
		return null
	return StructurePlan.from_dict(parsed as Dictionary)
