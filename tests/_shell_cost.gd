extends Node

## Scratch probe (leading underscore — not a gate unit). Lane B scene, because
## DeckFitout preloads BrickDoor, which names the WorldGateway autoload bare.
##
## Re-measures `tests/_offgrid_facts.gd` section G — "the one seam this wave did
## not close" — and prices it in MILLISECONDS at the sizes that actually reach
## `DeckFitout.apply_staged` (LARGE_LAYOUT_THRESHOLD = 1000 primaries).
##
## Run: xvfb-run -a --server-args="-screen 0 1280x720x24" godot \
##        --rendering-driver opengl3 --audio-driver Dummy \
##        res://tests/_shell_cost.tscn

const HULL := "hull_90x24"
const CLASSIFIER := preload("res://scripts/ship/brick_shell_classifier.gd")
const REPS := 3


func _ready() -> void:
	var grid := HullRegistry.make_grid(HULL)
	print("grid %s -> %d x %d  taper %d  deck_y %.2f" % [
		HULL, grid.width, grid.length, grid.bow_taper_cells, grid.deck_y,
	])

	print("\n=== 1. REPRODUCE section G: the 5x5x3 cabin, one smuggled cell ===")
	var cabin := _cabin(grid, Vector3i(20, 0, 60))
	_row("clean cabin", grid, cabin)
	_row("+1 cell (-40,0,-40)", grid, _smuggle(cabin, [Vector3i(-40, 0, -40)]))

	print("\n=== 2. REALISTIC STAGED SIZES (threshold %d) ===" % DeckFitout.LARGE_LAYOUT_THRESHOLD)
	for n in [1001, 3000]:
		var layout := _fill_blocks(grid, int(n))
		print("  -- n=%d primaries --" % int(n))
		_row("clean", grid, layout)
		## The realistic smuggle: a save authored against hull_150x32 (64 x 300
		## cells) loaded onto this 48 x 180 deck. `BrickLayout.from_dict` trusts
		## the record verbatim, so the cells arrive; `on_deck_items` refuses them
		## for drawing; the classifier still floods around them.
		_row("+4 wrong-hull cells", grid, _smuggle(layout, [
			Vector3i(63, 0, 299), Vector3i(63, 1, 299),
			Vector3i(62, 0, 298), Vector3i(0, 0, 299),
		]))
		_row("+1 cell (-40,0,-40)", grid, _smuggle(layout, [Vector3i(-40, 0, -40)]))

	print("\n=== 3. DOES AN OFF-DECK BRICK CHANGE THE SPLIT? ===")
	_shield_case(grid)

	print("\n=== 4. add_container_pad: has_deck_cell vs add_bulk_hold's in_bounds ===")
	_pad_bound_survey()

	get_tree().quit()


## `add_container_pad` bounds pad cells with `has_deck_cell`; its sibling
## `add_bulk_hold` uses `in_bounds` for the same kind of deck rectangle. The
## difference is the bow HALF cells. Does any shipped pad stand on one?
func _pad_bound_survey() -> void:
	var dir := DirAccess.open("res://resources/data/vessels/prebuilt")
	if dir == null:
		print("  no prebuilt directory")
		return
	var total_pad_cells := 0
	var total_half := 0
	var total_none := 0
	for name in dir.get_files():
		if not name.ends_with(".json"):
			continue
		var f := FileAccess.open("res://resources/data/vessels/prebuilt/%s" % name, FileAccess.READ)
		if f == null:
			continue
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		f.close()
		if parsed is not Dictionary:
			continue
		var doc := parsed as Dictionary
		var g := HullRegistry.make_grid(str(doc.get("hull_id", "")))
		var layout := BrickLayout.from_dict(doc.get("brick_layout", {}) as Dictionary)
		var cells := 0
		var half := 0
		var none := 0
		for pad_raw in layout.iter_container_pads():
			var mn := BrickLayout.zone_min(pad_raw as Dictionary)
			var mx := BrickLayout.zone_max(pad_raw as Dictionary)
			for ix in range(mn.x, mx.x + 1):
				for iz in range(mn.z, mx.z + 1):
					var c := Vector3i(ix, 0, iz)
					cells += 1
					if g.is_partial_bow_cell(c):
						half += 1
					elif not g.in_bounds(c):
						none += 1
		total_pad_cells += cells
		total_half += half
		total_none += none
		print("    %-22s pads %d  pad cells %3d  on bow HALF %d  off deck entirely %d" % [
			name, layout.iter_container_pads().size(), cells, half, none,
		])
	print("    TOTAL pad cells %d  on bow HALF %d  off deck entirely %d" % [
		total_pad_cells, total_half, total_none,
	])


## An off-deck brick that is ADJACENT to an on-deck one plugs the only air gap
## that brick has. The item list is filtered, so the plug is never built — but
## the classifier still counts it as solid, and files the on-deck brick as
## INTERIOR. A remote replica stops after EXTERIOR_VISUALS and never draws it.
func _shield_case(grid: DeckGrid) -> void:
	var edge := _edge_cell(grid)
	if edge.x < 0:
		print("  no edge cell found")
		return
	var outside := edge + Vector3i(1, 0, 0)
	print("  target %s in_bounds=%s   plug %s in_bounds=%s deck=%s" % [
		str(edge), str(grid.in_bounds(edge)),
		str(outside), str(grid.in_bounds(outside)), str(grid.has_deck_cell(outside)),
	])
	var layout := BrickLayout.new()
	layout.hull_id = HULL
	for c in [edge, edge + Vector3i(-1, 0, 0), edge + Vector3i(0, 0, 1),
			edge + Vector3i(0, 0, -1), edge + Vector3i(0, 1, 0)]:
		if not layout.set_brick(grid, c as Vector3i, "block", 0):
			print("  FIXTURE REFUSED %s — the surround is not on the deck" % str(c))
			return
	var kept: Array = DeckFitout.on_deck_items(grid, layout.iter_primary_cells())["kept"]
	var clean: Dictionary = CLASSIFIER.classify(layout, grid, kept)
	var plugged := _smuggle(layout, [outside])
	var kept2: Array = DeckFitout.on_deck_items(grid, plugged.iter_primary_cells())["kept"]
	var dirty: Dictionary = CLASSIFIER.classify(plugged, grid, kept2)
	print("  clean    exterior %d interior %d   target exterior=%s" % [
		(clean.get("exterior", []) as Array).size(),
		(clean.get("interior", []) as Array).size(),
		str((clean.get("exterior_keys", {}) as Dictionary).has(BrickLayout.cell_key(edge))),
	])
	print("  +1 off-deck plug at %s (filtered OUT of the item list, kept %d):" % [
		str(outside), kept2.size(),
	])
	print("           exterior %d interior %d   target exterior=%s" % [
		(dirty.get("exterior", []) as Array).size(),
		(dirty.get("interior", []) as Array).size(),
		str((dirty.get("exterior_keys", {}) as Dictionary).has(BrickLayout.cell_key(edge))),
	])


## First cell whose +X neighbour is off the deck, with room for the surround.
func _edge_cell(grid: DeckGrid) -> Vector3i:
	for z in range(2, grid.length - 2):
		for x in range(grid.width - 1, 0, -1):
			var c := Vector3i(x, 0, z)
			if not grid.in_bounds(c):
				continue
			if grid.in_bounds(c + Vector3i(1, 0, 0)):
				continue
			if (grid.in_bounds(c + Vector3i(-1, 0, 0))
					and grid.in_bounds(c + Vector3i(0, 0, 1))
					and grid.in_bounds(c + Vector3i(0, 0, -1))):
				return c
	return Vector3i(-1, -1, -1)


func _row(label: String, grid: DeckGrid, layout: BrickLayout) -> void:
	var kept: Array = DeckFitout.on_deck_items(grid, layout.iter_primary_cells())["kept"]
	var best := 1 << 62
	var result: Dictionary = {}
	for _i in range(REPS):
		var t0 := Time.get_ticks_usec()
		result = CLASSIFIER.classify(layout, grid, kept)
		best = mini(best, Time.get_ticks_usec() - t0)
	print("    %-22s cells %5d  kept %5d  ext %5d int %5d  exterior_air %8d  classify %8.2f ms" % [
		label, layout.cells.size(), kept.size(),
		(result.get("exterior", []) as Array).size(),
		(result.get("interior", []) as Array).size(),
		int(result.get("exterior_air_count", -1)),
		float(best) / 1000.0,
	])


## Round-trips through the SAVE path — `to_dict` then `from_dict` — because that
## is how an off-deck cell reaches a live layout in production. `from_dict`
## trusts the record's cells verbatim (documented, deliberate), so the doctored
## dictionary here is exactly a doctored / stale save file.
func _smuggle(layout: BrickLayout, cells: Array) -> BrickLayout:
	var d := layout.to_dict()
	var raw := (d.get("cells", {}) as Dictionary).duplicate(true)
	for c in cells:
		raw[BrickLayout.cell_key(c as Vector3i)] = {"brick_id": "block", "yaw": 0}
	d["cells"] = raw
	return BrickLayout.from_dict(d)


func _cabin(grid: DeckGrid, origin: Vector3i) -> BrickLayout:
	var layout := BrickLayout.new()
	layout.hull_id = HULL
	for y in range(3):
		for x in range(5):
			for z in range(5):
				if x == 0 or x == 4 or z == 0 or z == 4 or y == 2:
					layout.set_brick(
						grid, Vector3i(origin.x + x, origin.y + y, origin.z + z), "block", 0
					)
	layout.set_brick(grid, Vector3i(origin.x + 2, origin.y + 1, origin.z + 2), "block", 0)
	return layout


## Same shape as `deck_fitout_load_bench._fill_blocks`, so the numbers here are
## comparable with the bench's own.
func _fill_blocks(grid: DeckGrid, count: int) -> BrickLayout:
	var layout := BrickLayout.new()
	layout.hull_id = HULL
	var remaining := count
	var y := 0
	while remaining > 0 and y < 40:
		for iz in range(grid.length):
			for ix in range(grid.width):
				if remaining <= 0:
					return layout
				if layout.set_brick(grid, Vector3i(ix, y, iz), "block", 0):
					remaining -= 1
		y += 1
	return layout
