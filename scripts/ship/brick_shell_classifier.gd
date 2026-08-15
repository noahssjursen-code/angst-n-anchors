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


static func classify(
	layout: BrickLayout,
	grid: DeckGrid,
	known_primary_items: Array = [],
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
	for raw in candidates:
		var item := raw as Dictionary
		var cell: Vector3i = item.get("cell", Vector3i(-1, -1, -1))
		if not trust_caller and not BrickLayout.cell_on_grid(
			grid, cell, str(item.get("brick_id", "")), int(item.get("yaw", 0))
		):
			continue
		primary_items.append(item)
		accepted[cell] = true
	if primary_items.is_empty():
		return {
			"exterior": [],
			"interior": [],
			"exterior_keys": {},
			"exterior_air_count": 0,
		}

	var occupied := {}
	var primary_by_occupied := {}
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

	var bounds_min := Vector3i(min_x - 1, 0, min_z - 1)
	var bounds_max := Vector3i(max_x + 1, max_y + 1, max_z + 1)
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
