extends SceneTree

## Lane A. IS THIS BRICK LAYOUT A CABIN? Run:
##   xvfb-run -a --server-args="-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy \
##     --script res://tests/brick_enclosure_test.gd
##
## Until 2026-08-16 NOTHING IN THIS REPOSITORY ASSERTED ANYTHING ABOUT THE BRICK
## PATH'S `has_cabin`. `plan_outfit.gd`'s header claimed `plan_compliance_test`
## pinned it; that test pins the PLAN side of the same question, and a citation
## is not a verification (REALITY.md §4d). The rule it was not pinning was
## `door_n >= 1 or wall_n >= 8`, and measured through `VesselOutfit.validate` on
## hull_28x10 it certified **eight blocks in a straight line** and **one
## `block_door` lying alone on a bare deck** as enclosed passenger
## accommodation.
##
## This file is the check the fix has to survive. It asserts the PROPERTY —
## there is a pocket of air in here you cannot see the sky from, standing on
## something, with a door into it — and never the old number (REALITY.md §4a: a
## regression test on a known-wrong answer holds it in place).
##
## ── What each section is for ────────────────────────────────────────────────
##
## 1. THE TWO SHIPPED WRONG YESES, through `VesselOutfit.validate` and then all
##    the way through `VesselCompliance` to the `passenger_vessel` checklist
##    line that reads *"Enclosed passenger accommodation"*. The first is the
##    unit's answer; the second is the sentence a player would have been shown.
##
## 2. THE CLAUSES, one adversarial layout each, every one built from the SAME
##    hollow box so a pass and a fail differ by one edit: no lid (the sky gets
##    in), one wall missing (the sky gets in sideways), no floor course under a
##    box in the air, a window instead of a door, and the door itself.
##
## 3. THE SCALE, which is the one thing this reading refuses to decide.
##    `BuildingGrid.CELL_M` is 1.0 and `BrickCatalog.size_m` is 0.5 — CONVENTIONS
##    §3a's open product decision. The verdict `VesselOutfit` publishes is the
##    scale-free one and must be IDENTICAL under both candidates; the metre bars
##    are a parameter, and the three-course cabin is the fixture whose answer
##    genuinely differs between them. Both facts are asserted, so neither the
##    invariance nor the difference can be lost quietly.
##
## 4. THE FLEET. Every shipped prebuilt preset, on the property rather than on a
##    remembered verdict: whatever `has_cabin` says, it must agree with the
##    geometry, and a preset that certifies today must not be silently
##    decertified.
##
## 5. THE SEAM. What `VesselOutfit.validate` publishes, and that a cabin built
##    OFF the deck is not accommodation on this boat.
##
## Every check here has been shown RED against a deliberately broken
## `BrickShellClassifier` — the mutants and their scores are in the wave report.
##
## The check count is pinned because a script error aborts the enclosing
## function and lets `_initialize` carry on, so a broken classifier could report
## ALL PASS having asserted nothing.

const TestReport := preload("res://tests/support/test_report.gd")
const BSC := preload("res://scripts/ship/brick_shell_classifier.gd")
const HULL := "hull_28x10"
const EXPECTED_CHECKS := 59

var _t: RefCounted


func _initialize() -> void:
	_t = TestReport.new("brick_enclosure_test")
	_test_the_two_wrong_yeses()
	_test_the_clauses()
	_test_the_scale()
	_test_the_fleet()
	_test_the_seam()
	if _t.check_count() != EXPECTED_CHECKS:
		_t.check(
			"ran %d checks, expected %d — a check aborted before asserting"
				% [_t.check_count(), EXPECTED_CHECKS],
			false,
		)
	_t.finish(self)


# ── 1. The two shipped wrong yeses ──────────────────────────────────────────

func _test_the_two_wrong_yeses() -> void:
	print("\n-- the two layouts the old rule certified --")
	var grid := HullRegistry.make_grid(HULL)

	var fence := BrickLayout.new()
	fence.hull_id = HULL
	for i in 8:
		fence.set_brick(grid, Vector3i(6 + i, 0, 20), "block")
	_t.equal("the line of blocks is eight bricks", fence.count(), 8)
	_t.check(
		"eight blocks in a straight line enclose nothing and are not a cabin",
		not _has_cabin(fence, grid),
	)
	_t.equal("and there is no pocket of air in them at all",
		int(BSC.enclosure(fence, grid)["pockets"]), 0)

	var lone := BrickLayout.new()
	lone.hull_id = HULL
	lone.set_brick(grid, Vector3i(10, 0, 20), "block_door")
	_t.equal("the lone door is one brick", lone.count(), 1)
	_t.check(
		"one door brick lying on a bare deck is not a cabin",
		not _has_cabin(lone, grid),
	)

	## THE SENTENCE A PLAYER WOULD HAVE BEEN SHOWN. `passenger_vessel` is the one
	## registration in the catalogue whose rules name `has_cabin`, and its
	## `cabin` line used to read "required (current: true)" for both layouts
	## above. Asserted through `VesselCompliance` rather than off the capability
	## dictionary, because the checklist is the artefact and the dictionary is
	## the intermediate one (REALITY.md §3).
	for named in [["a line of blocks", fence], ["a lone door brick", lone]]:
		var row := _cabin_checklist_row(named[1] as BrickLayout, grid)
		if not _t.check("%s: the passenger cabin rule is on the checklist" % str(named[0]),
			not row.is_empty()):
			continue
		_t.check(
			"%s: and it now FAILS — \"%s\"" % [str(named[0]), str(row.get("message", ""))],
			not bool(row.get("ok", true)),
		)


# ── 2. The clauses ──────────────────────────────────────────────────────────

func _test_the_clauses() -> void:
	print("\n-- one adversarial layout per clause --")
	var grid := HullRegistry.make_grid(HULL)

	var sealed := _box(grid, 4, false)
	_t.check("a sealed box with no way in is not a cabin", not _has_cabin(sealed, grid))
	_t.equal("but it IS enclosed — the reading found the pocket",
		int(BSC.enclosure(sealed, grid)["pockets"]), 1)
	_t.check("and it says why",
		str(BSC.enclosure(sealed, grid)["why"]).contains("no door opens onto it"))

	var doored := _box(grid, 4, true)
	_t.check("cutting a door into the same box makes it a cabin", _has_cabin(doored, grid))

	## THE SKY, STRAIGHT UP. The brick twin of the plan path's fence.
	var roofless := _box(grid, 4, true)
	for x in 5:
		for z in 5:
			roofless.erase_cell(Vector3i(6 + x, 4, 18 + z))
	_t.check("the same walls with no lid over them are not a cabin",
		not _has_cabin(roofless, grid))
	_t.equal("because the air inside runs to the sky and no pocket is left",
		int(BSC.enclosure(roofless, grid)["pockets"]), 0)

	## THE SKY, SIDEWAYS. One wall taken out of the ring.
	var gapped := _box(grid, 4, true)
	for y in 4:
		gapped.erase_cell(Vector3i(6, y, 20))
	_t.check("a box with one side open is not a cabin", not _has_cabin(gapped, grid))

	## A WINDOW SEALS AND DOES NOT ADMIT — the same two predicates `PlanOutfit`
	## draws apart, drawn apart here by the brick's tag.
	var glazed := _box(grid, 4, false)
	glazed.set_brick(grid, Vector3i(8, 0, 18), "block_window")
	_t.check("a compartment you can only see into is not a cabin",
		not _has_cabin(glazed, grid))
	_t.equal("and it is still sealed, so the window did not open it",
		int(BSC.enclosure(glazed, grid)["pockets"]), 1)

	## NO FLOOR — which on this grid is the SAME question as enclosure and not a
	## second one. The box hoisted two courses off the deck with nothing under it
	## is not refused by a floor test (there is none, and one could not fail —
	## see `_read_pocket`'s header): the exterior flood simply comes up from
	## below, so there is no pocket at all.
	var floating := _box_at(grid, 2, 4, true)
	_t.check("a box in the air with no sole under it is not a cabin",
		not _has_cabin(floating, grid))
	_t.equal("and the reason is that it is not enclosed, not that it is unfloored",
		int(BSC.enclosure(floating, grid)["pockets"]), 0)
	var floored := _box_at(grid, 2, 4, true)
	for x in 5:
		for z in 5:
			floored.set_brick(grid, Vector3i(6 + x, 1, 18 + z), "block")
	_t.check("laying a sole under the same box makes it one", _has_cabin(floored, grid))

	## THE STARTER PAINTER'S "CABIN". A 3 x 3 ring with a lid: one column of
	## interior air, two courses tall, no door. The old rule called it a cabin
	## on eight wall bricks.
	var starter := BrickLayout.starter_cargo(HULL, grid)
	var starter_read := BSC.enclosure(starter, grid)
	_t.check("BrickLayout.starter_cargo paints a closet, not a cabin",
		not _has_cabin(starter, grid))
	_t.equal("its pocket is one column of floor", int(starter_read["floor_cells"]), 1)
	_t.check("with no door into it", not bool(starter_read["entered"]))


# ── 3. The scale, which this reading refuses to decide ──────────────────────

func _test_the_scale() -> void:
	print("\n-- the same layouts under both candidate brick cell sizes --")
	var grid := HullRegistry.make_grid(HULL)
	var cases := {
		"eight blocks in a line": _line(grid),
		"a lone door brick": _lone_door(grid),
		"a 3-course box with a door": _box(grid, 3, true),
		"a 4-course box with a door": _box(grid, 4, true),
		"a sealed box": _box(grid, 4, false),
	}
	## THE INVARIANCE. This is the property that makes the scale-free verdict
	## shippable while the cell size is undecided: settling it must not move
	## `has_cabin` on any layout.
	for label in cases.keys():
		var layout: BrickLayout = cases[label]
		_t.equal(
			"%s: the published verdict does not depend on the metre size" % label,
			bool(BSC.enclosure(layout, grid, 0.5)["entered"])
				and int(BSC.enclosure(layout, grid, 0.5)["floor_cells"]) > 0,
			_has_cabin(layout, grid),
		)

	## THE DIFFERENCE, NAMED. Applying the 1.8 m bar is exactly what a metre size
	## buys, and on this fixture the two candidates disagree. If someone settles
	## the cell size and wires the bars, this is the check that tells them which
	## boats change.
	var three := _box(grid, 3, true)
	_t.near("a 3-course pocket is 1.50 m at 0.5 m per cell",
		float(BSC.enclosure(three, grid, 0.5)["headroom_m"]), 1.5, 0.001)
	_t.near("and 3.00 m at 1.0 m per cell",
		float(BSC.enclosure(three, grid, 1.0)["headroom_m"]), 3.0, 0.001)
	_t.check("so with the 1.8 m bar applied it is a crawl space at 0.5 m",
		not bool(BSC.enclosure(three, grid, 0.5)["cabin"]))
	_t.check("and accommodation at 1.0 m",
		bool(BSC.enclosure(three, grid, 1.0)["cabin"]))

	var four := _box(grid, 4, true)
	_t.check("a 4-course pocket clears the bar at 0.5 m too",
		bool(BSC.enclosure(four, grid, 0.5)["cabin"]))
	_t.near("at 2.00 m of headroom over 2.25 m2",
		float(BSC.enclosure(four, grid, 0.5)["area_m2"]), 2.25, 0.001)

	## And the bars must actually bite on the AREA term as well as the height:
	## a 3 x 3 shaft five courses tall is standable and is not a room.
	var shaft := BrickLayout.new()
	shaft.hull_id = HULL
	for x in 3:
		for z in 3:
			for y in 5:
				if x == 1 and z == 1:
					continue
				shaft.set_brick(grid, Vector3i(6 + x, y, 18 + z), "block")
			shaft.set_brick(grid, Vector3i(6 + x, 5, 18 + z), "block")
	shaft.set_brick(grid, Vector3i(7, 0, 18), "block_door")
	var shaft_read := BSC.enclosure(shaft, grid, 0.5)
	_t.equal("a one-column shaft has one cell of floor", int(shaft_read["floor_cells"]), 1)
	_t.near("which is 0.25 m2 at 0.5 m per cell", float(shaft_read["area_m2"]), 0.25, 0.001)
	_t.check("under the 1.2 m2 bar, so with the bar applied it is not a cabin",
		not bool(shaft_read["cabin"]))


# ── 4. The fleet ────────────────────────────────────────────────────────────

func _test_the_fleet() -> void:
	print("\n-- every shipped prebuilt preset --")
	var entries := PrebuiltVesselCatalog.catalog_entries()
	if not _t.check("the prebuilt presets loaded (%d)" % entries.size(), entries.size() >= 4):
		return
	for entry_raw in entries:
		var entry := entry_raw as Dictionary
		var id := str(entry.get("prebuilt_id", ""))
		var hull_id := str(entry.get("hull_id", ""))
		var grid := HullRegistry.make_grid(hull_id)
		var layout := BrickLayout.from_dict(entry.get("prebuilt_layout", {}) as Dictionary)
		var read := BSC.enclosure(layout, grid)
		## THE PROPERTY, NOT THE VERDICT. A preset may gain or lose a deckhouse
		## without this file changing; what may never happen is `has_cabin`
		## disagreeing with the geometry it is supposed to be measured off.
		if bool(read["cabin"]):
			_t.check(
				"%s: its cabin is a real pocket with a door (%s)" % [id, str(read["why"])],
				int(read["pockets"]) > 0
					and int(read["floor_cells"]) > 0
					and bool(read["entered"]),
			)
		else:
			_t.check(
				"%s: no cabin, and the reading says why (%s)" % [id, str(read["why"])],
				not bool(read["entered"]) or int(read["floor_cells"]) == 0,
			)
		## And nothing a player is handed may be decertified by this change: all
		## four ship certified today, and the starter grant refuses a draft.
		var compliance := VesselCompliance.validate(
			layout, hull_id, str(entry.get("registration_id", "")), grid
		)
		_t.check(
			"%s: still passes its registration (%s)"
				% [id, VesselCompliance.checklist_summary(compliance)],
			bool(compliance.get("ok", false)),
		)


# ── 5. The seam ─────────────────────────────────────────────────────────────

func _test_the_seam() -> void:
	print("\n-- what VesselOutfit.validate publishes --")
	var grid := HullRegistry.make_grid(HULL)
	var caps := _caps(_box(grid, 4, true), grid)
	_t.check("validate publishes the cabin", bool(caps.get("has_cabin", false)))
	_t.equal("and its count", int(caps.get("cabins", -1)), 1)
	_t.equal("and the floor it stands on, in CELLS", int(caps.get("cabin_floor_cells", -1)), 9)
	_t.equal("and its headroom, in CELLS", int(caps.get("cabin_headroom_cells", -1)), 4)
	_t.check("and no metre figure, because the cell size is undecided",
		not caps.has("cabin_area_m2"))
	_t.check("and it says why (%s)" % str(caps.get("cabin_why", "")),
		not str(caps.get("cabin_why", "")).is_empty())

	var bare := _caps(BrickLayout.new(), grid)
	_t.check("an empty layout has no cabin", not bool(bare.get("has_cabin", true)))
	_t.equal("and no pocket", int(bare.get("cabins", -1)), 0)
	_t.check("and a null layout publishes no capabilities at all",
		_caps(null, grid).is_empty())

	## OFF THE DECK. The same box, AUTHORED ON A BIGGER HULL and then judged
	## against this one — the shape `BrickLayout.set_brick` cannot produce,
	## because it refuses an off-grid cell at authoring time, and the shape a
	## saved record from another hull DOES produce (`from_dict` trusts the
	## record verbatim; see its header). `VesselOutfit`'s walk refuses every
	## brick of it, and the enclosure reading is handed that refusal rather than
	## re-deriving it — so a cabin in the sea is not accommodation on this boat.
	var big := HullRegistry.make_grid("hull_90x24")
	var adrift := BrickLayout.new()
	adrift.hull_id = HULL
	var far := Vector2i(30, 100)
	for x in 5:
		for z in 5:
			for y in 4:
				if x == 0 or x == 4 or z == 0 or z == 4:
					adrift.set_brick(big, Vector3i(far.x + x, y, far.y + z), "block")
			adrift.set_brick(big, Vector3i(far.x + x, 4, far.y + z), "block")
	adrift.set_brick(big, Vector3i(far.x + 2, 0, far.y), "block_door")
	_t.check("the box was authored on the bigger hull (%d bricks)" % adrift.count(),
		adrift.count() > 0 and not grid.has_deck_cell(Vector3i(far.x, 0, far.y)))
	var adrift_report := VesselOutfit.validate(adrift, HULL, grid)
	_t.check("a box built 20 m past the bow is refused by the deck",
		(adrift_report["off_grid"] as Array).size() > 0)
	_t.check("and it is not accommodation on this boat",
		not bool((adrift_report["capabilities"] as Dictionary).get("has_cabin", true)))


# ── Fixtures ────────────────────────────────────────────────────────────────

## 5 x 5 footprint, `courses` of wall, a lid over the top. `door` swaps one wall
## cell on the bottom course for a `block_door`.
func _box(grid: DeckGrid, courses: int, door: bool) -> BrickLayout:
	return _box_at(grid, 0, courses, door)


## The same box with its lowest wall course at `base`. Nothing is placed below
## it, so at `base > 0` the compartment hangs in the air over open deck.
func _box_at(grid: DeckGrid, base: int, courses: int, door: bool) -> BrickLayout:
	var layout := BrickLayout.new()
	layout.hull_id = HULL
	for x in 5:
		for z in 5:
			for y in range(base, base + courses):
				var edge := x == 0 or x == 4 or z == 0 or z == 4
				if edge:
					layout.set_brick(grid, Vector3i(6 + x, y, 18 + z), "block")
			layout.set_brick(grid, Vector3i(6 + x, base + courses, 18 + z), "block")
	if door:
		layout.set_brick(grid, Vector3i(8, base, 18), "block_door")
	return layout


func _line(grid: DeckGrid) -> BrickLayout:
	var layout := BrickLayout.new()
	layout.hull_id = HULL
	for i in 8:
		layout.set_brick(grid, Vector3i(6 + i, 0, 20), "block")
	return layout


func _lone_door(grid: DeckGrid) -> BrickLayout:
	var layout := BrickLayout.new()
	layout.hull_id = HULL
	layout.set_brick(grid, Vector3i(10, 0, 20), "block_door")
	return layout


## THROUGH `VesselOutfit.validate`, never off `BrickShellClassifier` directly:
## the capability dictionary is the artefact the licence reads, and a reading
## that is right in the classifier and unwired in the outfit is the layer trap
## (REALITY.md §3).
func _has_cabin(layout: BrickLayout, grid: DeckGrid) -> bool:
	return bool(_caps(layout, grid).get("has_cabin", false))


func _caps(layout: BrickLayout, grid: DeckGrid) -> Dictionary:
	return VesselOutfit.validate(layout, HULL, grid)["capabilities"] as Dictionary


## The `passenger_vessel` checklist line about accommodation, or {}.
func _cabin_checklist_row(layout: BrickLayout, grid: DeckGrid) -> Dictionary:
	var report := VesselCompliance.validate(layout, HULL, "passenger_vessel", grid)
	for raw in report.get("checklist", []) as Array:
		var row := raw as Dictionary
		if str(row.get("id", "")) == "cabin":
			return row
	return {}
