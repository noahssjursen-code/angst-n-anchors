class_name BrickShellClassifier
extends RefCounted

## Separates a sparse vessel layout into outside-visible and enclosed bricks.
## The hull/deck beneath y=0 is treated as closed; flood fill enters from the
## padded sides and sky, so arbitrary superstructure shapes need no templates.
##
## THE SOLID FIELD IS WHAT WILL BE BUILT, NOT WHAT THE RECORD HOLDS. This used
## to walk `layout.cells` verbatim while its `grid` argument sat unused behind a
## leading underscore, so a cell the fit-out had already refused was still solid
## here and still stretched the flood volume. Two consequences, both measured on
## hull_90x24 (`tests/_shell_cost.gd`, 2026-08-15):
##
##   COST. One cell at (-40, 0, -40) — the shape a stale or doctored save
##   produces, since `BrickLayout.from_dict` trusts a record's cells verbatim —
##   took the 5x5x3 cabin's `exterior_air_count` from 121 to 28600 (x236) and
##   `classify` from 1.16 ms to 131.56 ms. At the sizes that actually reach
##   `DeckFitout.apply_staged` (>1000 primaries) four cells carrying hull_150x32
##   indices onto this 48 x 180 deck cost 24.61 -> 289.62 ms at n=1001 and
##   67.23 -> 311.11 ms at n=3000 (291-322 ms over two runs). `classify` runs
##   inside `DeckFitoutJob.configure`, which is called synchronously from
##   `apply_staged` and is outside the frame budget entirely — so that is about a
##   third of a second of stall at spawn, not a slow frame.
##   AFTER: `exterior_air_count` and the milliseconds are the CLEAN ones in every
##   one of those cases — 121 / 1.19-1.36 ms, 2499 / 24.5-26.2 ms,
##   4600 / 68.6-72.5 ms. The count is what a test can hold; the milliseconds are
##   llvmpipe's and are asserted nowhere (`deck_fitout_load_bench`'s header, on why).
##
##   CORRECTNESS, which the earlier measurement missed because its fixture put
##   the smuggled cell 40 cells away from anything. An off-deck brick ADJACENT to
##   an on-deck one plugs that brick's only open face: measured, an on-deck block
##   at the deck edge went `exterior` -> `interior` when a never-to-be-built cell
##   was smuggled in beside it. Interior bricks are drawn in INTERIOR_VISUALS,
##   and a remote replica stops after EXTERIOR_VISUALS — so the brick is a hole in
##   the hull side for every other player, indefinitely.
##
## So `grid` is honoured — it was meant to be, and the underscore was the record
## of a job half done, not of an argument nobody needed. It is REQUIRED and has no
## default: an un-updated caller is a compile error rather than a silently-defaulted
## null, exactly as on `BrickLayout.set_brick`. Verified, not assumed —
## `classify(BrickLayout.new())` dies at parse time with *"Too few arguments for
## classify() call. Expected at least 2 but received 1"*. Every existing call site
## already passed a grid, so nothing had to change to get that.
##
## WHAT `grid` DOES AND DOES NOT DECIDE, stated because the halves differ. It
## decides which of the layout's own primaries this class will accept when it is
## handed no item list. It does NOT re-judge a list a caller supplied — see
## `classify`, where that split is drawn and priced. So `grid == null` blanks a
## raw-layout call and is ignored by a caller that brought its own items; it is
## not the fail-shut `BrickLayout.set_brick(null, …)` is.
##
## The predicate is `BrickLayout.cell_on_grid`, the same one `DeckFitout.on_deck_items`
## filters with, so this class and the skin bake cannot disagree about what exists
## (REALITY.md §3b — one derivation). A cell is solid iff its PRIMARY was accepted,
## which is what keeps a multi-cell footprint whole: its `occupied_by` filler cells
## carry no independent verdict and inherit the origin's.

const NEIGHBORS: Array[Vector3i] = [
	Vector3i.LEFT,
	Vector3i.RIGHT,
	Vector3i.UP,
	Vector3i.DOWN,
	Vector3i.FORWARD,
	Vector3i.BACK,
]


## THE SOLID FIELD BOTH READINGS RUN ON, derived here and nowhere else.
## `classify` asks which BRICKS the exterior flood touches; `enclosure` asks
## which AIR it never reaches. Two questions about one field — so the field, its
## bounds and the accept predicate are computed once (REALITY.md §3b), and a
## change to what counts as solid cannot move one answer without the other.
##
## Returns `{ empty, primary_items, occupied, primary_by_occupied, brick_by_cell,
## bounds_min, bounds_max }`.
static func _solid_field(
	layout: BrickLayout,
	grid: DeckGrid,
	known_primary_items: Array,
) -> Dictionary:
	var candidates: Array = (
		known_primary_items if not known_primary_items.is_empty()
		else layout.iter_primary_cells() if layout != null
		else []
	)
	## THE GRID IS ASKED ONLY WHEN NOBODY ELSE HAS BEEN. A caller that hands over
	## an item list has already said what is being built — `DeckFitout.apply_staged`
	## partitions on `on_deck_items`, which refuses on this same static predicate —
	## and re-deciding it here would be the second derivation, not the first.
	##
	## It is also not free, which is why the split is drawn here rather than
	## "filter everything, it is only a predicate". Measured at n=3000 on
	## hull_90x24 with the item list supplied: 65.6-68.0 ms without this loop
	## against 84.8-95.8 ms with `cell_on_grid` called per item — a 25% tax on the
	## exact path this change exists to speed up, paid to re-derive an answer the
	## caller already has.
	var trust_caller := not known_primary_items.is_empty()
	var primary_items: Array = []
	## Keyed on the Vector3i rather than on `cell_key`, because it is probed once
	## per cell in the occupancy walk below and the string form costs a
	## `"%d,%d,%d" %` each time.
	var accepted := {}
	var empty_field := {
		"empty": true,
		"primary_items": [],
		"occupied": {},
		"primary_by_occupied": {},
		"brick_by_cell": {},
		"bounds_min": Vector3i.ZERO,
		"bounds_max": Vector3i.ZERO,
	}
	for raw in candidates:
		var item := raw as Dictionary
		var cell: Vector3i = item.get("cell", Vector3i(-1, -1, -1))
		if not trust_caller and not BrickLayout.cell_on_grid(
			grid, cell, str(item.get("brick_id", "")), int(item.get("yaw", 0))
		):
			continue
		primary_items.append(item)
		accepted[cell] = true
	if primary_items.is_empty() or layout == null:
		return empty_field

	## What brick each ACCEPTED primary is. `enclosure` needs it to ask whether the
	## thing beside a pocket of air is a door; `classify` does not read it.
	var brick_by_primary := {}
	for raw in primary_items:
		var item := raw as Dictionary
		brick_by_primary[item.get("cell", Vector3i.ZERO)] = str(item.get("brick_id", ""))

	var occupied := {}
	var primary_by_occupied := {}
	var brick_by_cell := {}
	var min_x := 0
	var max_x := 0
	var max_y := 0
	var min_z := 0
	var max_z := 0
	var first := true
	for key_raw in layout.cells.keys():
		var key := str(key_raw)
		var cell := BrickLayout.parse_key(key)
		if cell.y < 0:
			continue
		var entry := layout.cells[key_raw] as Dictionary
		var primary: Vector3i = (
			BrickLayout.parse_key(str(entry.get("occupied_by", key))) if entry.has("occupied_by")
			else cell
		)
		## A cell whose primary the deck refused is a cell nothing will draw, so
		## it is not solid and it does not stretch the flood volume either.
		if not accepted.has(primary):
			continue
		occupied[cell] = true
		primary_by_occupied[cell] = primary
		brick_by_cell[cell] = str(brick_by_primary.get(primary, ""))
		if first:
			min_x = cell.x
			max_x = cell.x
			max_y = cell.y
			min_z = cell.z
			max_z = cell.z
			first = false
		else:
			min_x = mini(min_x, cell.x)
			max_x = maxi(max_x, cell.x)
			max_y = maxi(max_y, cell.y)
			min_z = mini(min_z, cell.z)
			max_z = maxi(max_z, cell.z)
	if occupied.is_empty():
		return empty_field
	return {
		"empty": false,
		"primary_items": primary_items,
		"occupied": occupied,
		"primary_by_occupied": primary_by_occupied,
		"brick_by_cell": brick_by_cell,
		"bounds_min": Vector3i(min_x - 1, 0, min_z - 1),
		"bounds_max": Vector3i(max_x + 1, max_y + 1, max_z + 1),
	}


static func classify(
	layout: BrickLayout,
	grid: DeckGrid,
	known_primary_items: Array = [],
) -> Dictionary:
	var field := _solid_field(layout, grid, known_primary_items)
	if bool(field["empty"]):
		return {
			"exterior": [],
			"interior": [],
			"exterior_keys": {},
			"exterior_air_count": 0,
		}
	var primary_items: Array = field["primary_items"]
	var occupied: Dictionary = field["occupied"]
	var primary_by_occupied: Dictionary = field["primary_by_occupied"]
	var bounds_min: Vector3i = field["bounds_min"]
	var bounds_max: Vector3i = field["bounds_max"]
	var exterior_air := _flood_exterior_air(occupied, bounds_min, bounds_max)
	var exterior_primary := {}
	for occupied_raw in occupied.keys():
		var cell: Vector3i = occupied_raw
		for offset in NEIGHBORS:
			if exterior_air.has(cell + offset):
				var primary: Vector3i = primary_by_occupied.get(cell, cell)
				exterior_primary[BrickLayout.cell_key(primary)] = true
				break

	var exterior: Array = []
	var interior: Array = []
	for item_raw in primary_items:
		var item := (item_raw as Dictionary).duplicate(false)
		var primary: Vector3i = item.get("cell", Vector3i.ZERO)
		if exterior_primary.has(BrickLayout.cell_key(primary)):
			exterior.append(item)
		else:
			interior.append(item)
	exterior.sort_custom(_item_before)
	interior.sort_custom(_item_before)
	return {
		"exterior": exterior,
		"interior": interior,
		"exterior_keys": exterior_primary,
		"exterior_air_count": exterior_air.size(),
	}


# ── Enclosure, read off the same flood ──────────────────────────────────────

## `scenes/shared/player.tscn` is 1.8 m (CONVENTIONS §3a) and 1.2 m² is the
## smallest space a person turns round in. These are `PlanOutfit`'s
## `CABIN_MIN_HEADROOM_M` / `CABIN_MIN_AREA_M2` restated, and they are restated
## rather than imported because naming `PlanOutfit` from a class that runs inside
## `DeckFitoutJob.configure` would drag `StructureBaker` and the whole plan
## vocabulary into the spawn path's compile. **If one of these four numbers is
## ever changed, change the other pair in `plan_outfit.gd` in the same commit** —
## this is a second derivation of a threshold and it is named as one.
##
## NOTHING SHIPPED READS THEM TODAY. `VesselOutfit` asks for the SCALE-FREE
## verdict (see `enclosure`), so these apply only when a caller supplies
## `cell_m`. They exist so that the day the brick cell's metre size is settled,
## the bar is already written and already measured against both candidates.
const CABIN_MIN_HEADROOM_M := 1.8
const CABIN_MIN_AREA_M2 := 1.2


## IS THERE A POCKET OF AIR IN THIS LAYOUT THAT THE SKY CANNOT REACH, WITH A
## DOOR INTO IT?
##
## Returns `{ cabin, cabins, pockets, enclosed_air_cells, floor_cells,
## headroom_cells, entered, area_m2, headroom_m, cell_m, why }`.
##
## ── Why this function exists, and what it replaced ──────────────────────────
##
## `VesselOutfit`'s `has_cabin` was `door_n >= 1 or wall_n >= 8` — a count of
## brick IDS that asked nothing about shape. Measured through `VesselOutfit.validate`
## on hull_28x10 (`tests/_brick_cabin_probe.gd`): **eight `block` bricks in a
## straight line reported a cabin, and ONE `block_door` alone on an open deck
## reported a cabin**, which put `passenger_vessel/cabin` on the registration
## checklist as *"Enclosed passenger accommodation: required (current: true)"*.
##
## ── THE CLAUSES, AND WHICH OF THEM NEED A METRE SIZE ────────────────────────
##
## Two of the plan path's four clauses are pure topology on the voxel grid, a
## third turns out to be implied by the first, and only the fourth needs a scale.
## That is the whole reason this could be built while the brick cell's metre size
## is still an open product decision (CONVENTIONS §3a):
##
##   sky cannot reach it  the exterior flood `classify` already runs. A cell in
##                        bounds, above the deck, that is neither solid nor
##                        reached is enclosed. SCALE-FREE.
##   a floor under it     NOT A SEPARATE CLAUSE — it follows from enclosure on
##                        this grid, proved and mutation-measured in
##                        `_read_pocket`'s header. There is no floor test in this
##                        file because a floor test here cannot fail.
##   a way in             a `door`-tagged brick face-adjacent to the pocket. A
##                        door brick is SOLID here, exactly as `PlanOutfit`
##                        fills a door opening back in before flooding, so it
##                        seals the envelope and admits a person — the same two
##                        predicates that file draws apart, drawn apart here by
##                        the tag rather than by the opening type. A `window`
##                        brick is solid too and carries no `door` tag, so it
##                        seals and does not admit. SCALE-FREE.
##   tall and big enough  1.8 m of headroom over 1.2 m² of floor. THIS ONE, AND
##                        ONLY THIS ONE, NEEDS THE METRE SIZE. Pass `cell_m` to
##                        apply it; pass 0.0 (the default) and the reading stops
##                        at the clauses above and reports the cell counts
##                        instead, so a caller can apply any bar later without
##                        this function having decided anything.
##
## THE SECOND BLOCKER ON RECORD FOR THIS — *"a brick cell has no agreed metre
## size"* — is real and is NOT ON THIS PATH. The factor of two is between
## `BuildingGrid.CELL_M` (1.0) and `BrickCatalog.size_m` (0.5), and `BuildingGrid`
## is the LAND blueprint lattice in `scripts/port/` with zero references from
## `scripts/ship/`. A vessel brick is positioned by `DeckGrid.cell_center_local`,
## which steps `DeckGrid.CELL_M` = 0.5, and drawn at `BrickCatalog.size_m`, which
## is that same constant: on a boat the lattice and the brick agree. What is open
## is whether 0.5 m is the right BRICK, which is a product question about the
## whole system — so the parameter stays a parameter and both answers are
## reported rather than one being picked here.
##
## ── What the scale-free verdict costs, named ────────────────────────────────
##
## Without the metre bars this admits a pocket ONE CELL tall and one cell square
## — half a metre or a metre of headroom depending on the decision, and neither
## is a cabin. It is a strictly smaller class of wrong answer than the rule it
## replaces (which needed no pocket at all), and it is invariant under the
## decision it refuses to make, which is the property that makes it shippable:
## settling the brick cell at 0.5 m or at 1.0 m does not move `has_cabin` on any
## layout. Applying the bars would.
##
## ── Measured, both candidate cell sizes ─────────────────────────────────────
##
## `tests/_brick_enclosure_probe.gd`, hull_28x10, 2026-08-16. `free` is the
## scale-free verdict this class is asked for; the last two columns are what
## ADDING the metre bars would give at each candidate cell size.
##
##     fixture                        pockets  floor  head   free  0.5 m  1.0 m
##     8 blocks in a straight line          0      0     0  false  false  false
##     one block_door alone                 0      0     0  false  false  false
##     hollow 5x5x3, lid, no door           1      9     3  false  false  false
##     the same with a door cut in          1      9     3   TRUE  FALSE   TRUE
##     the same 4 courses tall              1      9     4   TRUE   TRUE   TRUE
##     the same 5 courses tall              1      9     5   TRUE   TRUE   TRUE
##     the same with no lid                 0      0     0  false  false  false
##     sealed box with a WINDOW in it       1      9     3  false  false  false
##     BrickLayout.starter_cargo            1      1     2  false  false  false
##
## ONE FIXTURE DIFFERS BETWEEN THE TWO CANDIDATE CELL SIZES, and it is the
## classic three-course brick cabin: 1.50 m of headroom at 0.5 m/cell against
## 3.00 m at 1.0 m/cell, so the same layout is a crawl space or a saloon
## depending on a constant nobody has settled. At 0.5 m the bar first clears at
## FOUR courses (2.00 m). Nothing else in the table moves — including both rows
## of the shipped defect, which are false under every reading, which is why
## closing it never needed the decision.
##
## `starter_cargo` is the other number worth reading: the "cabin" the starter
## painter draws is a 3 x 3 ring of blocks with a lid, whose interior is ONE
## column two courses tall and has no door in it. It is a closet, and it has
## never been a cabin under any reading — the old `wall_n >= 8` said it was.
##
## THE FOUR SHIPPED PREBUILT PRESETS ALL KEEP THEIR CABINS: 28_10_m, bulk_small
## and fishing_trawler report 182 cells of floor under 5 of headroom, sjark_15m
## 24 under 5, all entered, all `true` scale-free and at both cell sizes, and all
## four still pass their full registration checklist (10/10, 11/11, 10/10, 10/10).
##
## COST, llvmpipe, one process. The reading is a second exterior flood over the
## same field, and it prices like one: 25 ms on sjark_15m (271 bricks), 123-129 ms
## on the three 1087-brick presets, 207 ms against `classify`'s own 203 ms on a
## deliberately tall 873-brick layout on hull_90x24. The complement enumeration
## itself is ~4 ms of that; the flood is the rest. It runs inside
## `VesselOutfit.validate`, which `DeckFitoutJob` calls synchronously at spawn,
## so it is a spawn stall and not a frame cost — and the obvious saving, sharing
## one flood with the `classify` the same spawn already runs, is NOT taken here
## because the two calls come from different callers and threading one through
## would be a bigger change than this reading.
static func enclosure(
	layout: BrickLayout,
	grid: DeckGrid,
	cell_m: float = 0.0,
	known_primary_items: Array = [],
) -> Dictionary:
	var empty := {
		"cabin": false, "cabins": 0, "pockets": 0, "enclosed_air_cells": 0,
		"floor_cells": 0, "headroom_cells": 0, "entered": false,
		"area_m2": 0.0, "headroom_m": 0.0, "cell_m": cell_m,
	}
	var field := _solid_field(layout, grid, known_primary_items)
	if bool(field["empty"]):
		return _enclosure_result(empty, "the layout builds nothing")
	var occupied: Dictionary = field["occupied"]
	var brick_by_cell: Dictionary = field["brick_by_cell"]
	var bounds_min: Vector3i = field["bounds_min"]
	var bounds_max: Vector3i = field["bounds_max"]
	var exterior_air := _flood_exterior_air(occupied, bounds_min, bounds_max)

	## 1. What the flood never reached, and is not brick, is enclosed air. The
	## exterior flood already knows this — it was simply never published.
	var enclosed := {}
	for y in range(bounds_min.y, bounds_max.y + 1):
		for z in range(bounds_min.z, bounds_max.z + 1):
			for x in range(bounds_min.x, bounds_max.x + 1):
				var cell := Vector3i(x, y, z)
				if occupied.has(cell) or exterior_air.has(cell):
					continue
				enclosed[cell] = true
	if enclosed.is_empty():
		return _enclosure_result(
			empty, "no air inside this layout is out of the sky's reach"
		)
	empty["enclosed_air_cells"] = enclosed.size()

	## 2. Group it, and read each pocket.
	var seen := {}
	var pockets := 0
	var cabins := 0
	var best := empty.duplicate()
	var best_pocket := empty.duplicate()
	for start_raw in enclosed.keys():
		var start: Vector3i = start_raw
		if seen.has(start):
			continue
		pockets += 1
		var pocket := _read_pocket(start, enclosed, seen, occupied, brick_by_cell, cell_m)
		pocket["enclosed_air_cells"] = enclosed.size()
		pocket["cell_m"] = cell_m
		if int(pocket["floor_cells"]) > int(best_pocket["floor_cells"]):
			best_pocket = pocket
		if not _pocket_is_cabin(pocket, cell_m):
			continue
		cabins += 1
		if int(pocket["floor_cells"]) > int(best["floor_cells"]):
			best = pocket
	if cabins > 0:
		best["cabin"] = true
		best["cabins"] = cabins
		best["pockets"] = pockets
		return _enclosure_result(best, "%d enclosed cell%s of floor under %d of headroom, with a door into it" % [
			int(best["floor_cells"]), "" if int(best["floor_cells"]) == 1 else "s",
			int(best["headroom_cells"]),
		])
	best_pocket["cabins"] = 0
	best_pocket["pockets"] = pockets
	var why := "%d pocket%s of enclosed air, largest %d cell%s of floor under %d of headroom — " % [
		pockets, "" if pockets == 1 else "s",
		int(best_pocket["floor_cells"]), "" if int(best_pocket["floor_cells"]) == 1 else "s",
		int(best_pocket["headroom_cells"]),
	]
	if not bool(best_pocket["entered"]):
		why += "no door opens onto it"
	elif cell_m > 0.0:
		why += "%.2f m of headroom over %.2f m2 at %.2f m per cell" % [
			float(best_pocket["headroom_m"]), float(best_pocket["area_m2"]), cell_m,
		]
	else:
		why += "nothing a person could get into"
	return _enclosure_result(best_pocket, why)


static func _enclosure_result(report: Dictionary, why: String) -> Dictionary:
	var out := report.duplicate()
	out["why"] = why
	return out


## Whether a pocket clears the clauses in force. With `cell_m` at 0.0 that is
## enclosure and a way in; with a metre size it is those plus the two bars.
##
## There is no floor test here either, and for the same reason `_read_pocket` has
## none: a `floor_cells <= 0` guard stood on this line and could not fail, since
## a pocket has at least one cell and therefore at least one column.
static func _pocket_is_cabin(pocket: Dictionary, cell_m: float) -> bool:
	if not bool(pocket["entered"]):
		return false
	if cell_m <= 0.0:
		return true
	return (
		float(pocket["headroom_m"]) >= CABIN_MIN_HEADROOM_M
		and float(pocket["area_m2"]) >= CABIN_MIN_AREA_M2
	)


## One enclosed pocket, grown from `start` through the SAME six neighbours the
## exterior flood uses.
##
## `floor_cells` counts the plan columns the pocket occupies and `area_m2` counts
## only the columns with standing headroom — the eave of a pocket under a sloping
## course is part of the compartment and is not floor a person can use, which is
## the distinction `PlanOutfit._enclosed_group` draws with `standable`.
##
## ── "A FLOOR UNDER IT" IS NOT A CLAUSE HERE. IT IS A CONSEQUENCE ────────────
##
## This function had a floor test: a run counted only if `run_lo == 0` (the deck)
## or the cell under its base was a brick, with a `floorless_runs` counter beside
## it for the ones that were not. **Mutating that condition to `true` reddened
## nothing** — `brick_enclosure_test` stayed PASS (59 checks) with every run
## counted unconditionally. A mutation that passes is a finding (REALITY.md §8),
## and the finding is that the condition could not fail, for a reason worth
## writing down rather than restoring:
##
##   the cell under an enclosed run's base is enclosed air (then it is part of
##   the same run, so this is not the base), or exterior air (then the flood came
##   up through it and the run was never enclosed), or below y = 0 (the deck,
##   which the flood treats as closed). Nothing else is left. It is ALWAYS solid.
##
## So enclosure implies a floor on this grid, and the branch was deleted rather
## than kept as belt and braces, exactly as `PlanOutfit._flood_outside` deleted
## its sky seed for the same class of reason. The test that used to assert
## `floorless_runs == 0` went with it — an assertion that cannot fail is a
## vacuous pass (REALITY.md §4), not a guarantee.
##
## What still matters, and what a mutation DOES redden, is the flood's floor
## itself: `bounds_min.y` is 0, so nothing below the deck is air. Open that to
## −1 and every deckhouse on every vessel drains through its own sole.
static func _read_pocket(
	start: Vector3i,
	enclosed: Dictionary,
	seen: Dictionary,
	occupied: Dictionary,
	brick_by_cell: Dictionary,
	cell_m: float,
) -> Dictionary:
	var queue: Array[Vector3i] = [start]
	seen[start] = true
	var read_i := 0
	var cells := {}
	var entered := false
	while read_i < queue.size():
		var cell: Vector3i = queue[read_i]
		read_i += 1
		cells[cell] = true
		for offset in NEIGHBORS:
			var next: Vector3i = cell + offset
			if occupied.has(next):
				## The one place a brick's IDENTITY is asked. A door brick seals the
				## envelope like any other solid and is also the way through it.
				if not entered and BrickCatalog.has_tag(str(brick_by_cell.get(next, "")), "door"):
					entered = true
				continue
			if not enclosed.has(next) or seen.has(next):
				continue
			seen[next] = true
			queue.append(next)

	## Columns, and the contiguous vertical runs inside each.
	## An `Array`, not a `PackedInt32Array`: a packed array read back out of a
	## Dictionary is a COPY (copy-on-write value semantics), so `.append` on it
	## lands in a temporary and every column stays empty. That is not a
	## hypothetical — it was the first cut of this function, and it read as a
	## hang: `ys[0]` raised on every column of every pocket, the error aborted
	## `_read_pocket` so `enclosure` indexed a null, and the four shipped presets
	## printed enough backtraces to stall the process for minutes.
	var runs_by_column := {}
	for cell_raw in cells.keys():
		var cell: Vector3i = cell_raw
		var column := Vector2i(cell.x, cell.z)
		if not runs_by_column.has(column):
			runs_by_column[column] = ([] as Array[int])
		(runs_by_column[column] as Array[int]).append(cell.y)
	var standable_cells := 0
	var headroom_cells := 0
	var needed := 0
	if cell_m > 0.0:
		needed = int(ceil(CABIN_MIN_HEADROOM_M / cell_m - 0.000001))
	for column_raw in runs_by_column.keys():
		var ys: Array[int] = runs_by_column[column_raw]
		ys.sort()
		var run_lo := int(ys[0])
		var run_hi := int(ys[0])
		var tallest := 0
		var standable := false
		for i in range(1, ys.size() + 1):
			var y := int(ys[i]) if i < ys.size() else -9999
			if y == run_hi + 1:
				run_hi = y
				continue
			var height := run_hi - run_lo + 1
			tallest = maxi(tallest, height)
			if needed > 0 and height >= needed:
				standable = true
			if i < ys.size():
				run_lo = y
				run_hi = y
		if standable:
			standable_cells += 1
		headroom_cells = maxi(headroom_cells, tallest)
	return {
		"cabin": false, "cabins": 0, "pockets": 0, "enclosed_air_cells": cells.size(),
		## Every column of an enclosed pocket stands on something — see the header.
		"floor_cells": runs_by_column.size(),
		"headroom_cells": headroom_cells,
		"entered": entered,
		"area_m2": float(standable_cells) * cell_m * cell_m,
		"headroom_m": float(headroom_cells) * cell_m,
		"cell_m": cell_m,
	}


static func _flood_exterior_air(
	occupied: Dictionary,
	bounds_min: Vector3i,
	bounds_max: Vector3i,
) -> Dictionary:
	var reached := {}
	var queue: Array[Vector3i] = []
	for y in range(bounds_min.y, bounds_max.y + 1):
		for z in range(bounds_min.z, bounds_max.z + 1):
			_seed_air(Vector3i(bounds_min.x, y, z), occupied, reached, queue)
			_seed_air(Vector3i(bounds_max.x, y, z), occupied, reached, queue)
		for x in range(bounds_min.x + 1, bounds_max.x):
			_seed_air(Vector3i(x, y, bounds_min.z), occupied, reached, queue)
			_seed_air(Vector3i(x, y, bounds_max.z), occupied, reached, queue)
	for x in range(bounds_min.x + 1, bounds_max.x):
		for z in range(bounds_min.z + 1, bounds_max.z):
			_seed_air(Vector3i(x, bounds_max.y, z), occupied, reached, queue)

	var read_i := 0
	while read_i < queue.size():
		var cell := queue[read_i]
		read_i += 1
		for offset in NEIGHBORS:
			var next := cell + offset
			if not _inside_bounds(next, bounds_min, bounds_max):
				continue
			if occupied.has(next) or reached.has(next):
				continue
			reached[next] = true
			queue.append(next)
	return reached


static func _seed_air(
	cell: Vector3i,
	occupied: Dictionary,
	reached: Dictionary,
	queue: Array[Vector3i],
) -> void:
	if occupied.has(cell) or reached.has(cell):
		return
	reached[cell] = true
	queue.append(cell)


static func _inside_bounds(cell: Vector3i, mn: Vector3i, mx: Vector3i) -> bool:
	return (
		cell.x >= mn.x and cell.x <= mx.x
		and cell.y >= mn.y and cell.y <= mx.y
		and cell.z >= mn.z and cell.z <= mx.z
	)


static func _item_before(a_raw: Variant, b_raw: Variant) -> bool:
	var a := a_raw as Dictionary
	var b := b_raw as Dictionary
	var ac: Vector3i = a.get("cell", Vector3i.ZERO)
	var bc: Vector3i = b.get("cell", Vector3i.ZERO)
	if ac.y != bc.y:
		return ac.y < bc.y
	if ac.z != bc.z:
		return ac.z < bc.z
	if ac.x != bc.x:
		return ac.x < bc.x
	var aid := str(a.get("brick_id", ""))
	var bid := str(b.get("brick_id", ""))
	if aid != bid:
		return aid < bid
	return int(a.get("yaw", 0)) < int(b.get("yaw", 0))
