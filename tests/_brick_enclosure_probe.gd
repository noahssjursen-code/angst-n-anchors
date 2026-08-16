extends SceneTree

## SCRATCH PROBE (leading underscore -> skipped by tools/gate.sh discovery).
##
## Three questions, measured rather than argued:
##
##  1. Does `BrickShellClassifier`'s exterior flood already know which air is
##     enclosed? (The complement is computed here INDEPENDENTLY of
##     `BrickShellClassifier.enclosure`, from `classify`'s own inputs, so it is a
##     check on that function and not a restatement of it.)
##  2. What does the new reading say per fixture, scale-free and under BOTH
##     candidate brick cell sizes (0.5 m and 1.0 m)?
##  3. What do the four SHIPPED prebuilt presets report?
##
## Asserts nothing. Prints numbers.

const HULL := "hull_28x10"


func _initialize() -> void:
	var grid := HullRegistry.make_grid(HULL)

	print("=== 1. is the enclosed air already knowable from `classify`'s inputs? ===")
	var hollow := _hollow(grid, 3, false)
	var shell: Dictionary = BrickShellClassifier.classify(hollow, grid)
	print("  hollow 5x5x3 + lid: exterior %d  interior %d  exterior_air_count %d"
		% [(shell["exterior"] as Array).size(), (shell["interior"] as Array).size(),
			int(shell["exterior_air_count"])])
	var independent := _independent_enclosed_count(hollow, grid)
	print("  independent complement (bounds - solid - exterior flood) = %d cells" % independent)
	var reading := BrickShellClassifier.enclosure(hollow, grid)
	print("  BrickShellClassifier.enclosure enclosed_air_cells = %d"
		% int(reading["enclosed_air_cells"]))
	print("  agree: ", independent == int(reading["enclosed_air_cells"]))

	print("\n=== 2. the fixture table ===")
	print("  %-34s %7s %6s %6s %6s %6s %6s"
		% ["fixture", "pockets", "floor", "head", "free", "0.5m", "1.0m"])
	for row in _fixtures(grid):
		var layout: BrickLayout = row["layout"]
		var free := BrickShellClassifier.enclosure(layout, grid)
		var half := BrickShellClassifier.enclosure(layout, grid, 0.5)
		var one := BrickShellClassifier.enclosure(layout, grid, 1.0)
		print("  %-34s %7d %6d %6d %6s %6s %6s" % [
			str(row["name"]),
			int(free["pockets"]), int(free["floor_cells"]), int(free["headroom_cells"]),
			str(bool(free["cabin"])), str(bool(half["cabin"])), str(bool(one["cabin"])),
		])
		print("      why(free): %s"
			% [str(free["why"])])
		print("      0.5 m: %.2f m head / %.2f m2 · 1.0 m: %.2f m head / %.2f m2" % [
			float(half["headroom_m"]), float(half["area_m2"]),
			float(one["headroom_m"]), float(one["area_m2"]),
		])
		var report := VesselOutfit.validate(layout, HULL, grid)
		var caps := report["capabilities"] as Dictionary
		print("      VesselOutfit has_cabin -> %s  (cabins %d, floor %d, head %d)" % [
			str(bool(caps.get("has_cabin"))), int(caps.get("cabins", 0)),
			int(caps.get("cabin_floor_cells", 0)), int(caps.get("cabin_headroom_cells", 0)),
		])

	print("\n=== 3. the four SHIPPED prebuilt presets ===")
	for entry_raw in PrebuiltVesselCatalog.catalog_entries():
		var entry := entry_raw as Dictionary
		var hull_id := str(entry.get("hull_id", ""))
		var preset_grid := HullRegistry.make_grid(hull_id)
		var layout := BrickLayout.from_dict(entry.get("prebuilt_layout", {}) as Dictionary)
		var free := BrickShellClassifier.enclosure(layout, preset_grid)
		var half := BrickShellClassifier.enclosure(layout, preset_grid, 0.5)
		var one := BrickShellClassifier.enclosure(layout, preset_grid, 1.0)
		print("  %-16s reg=%-16s bricks=%d" % [
			str(entry.get("prebuilt_id", "")), str(entry.get("registration_id", "")),
			layout.count(),
		])
		print("      pockets %d  floor %d  head %d  entered %s | free %s  0.5m %s  1.0m %s" % [
			int(free["pockets"]), int(free["floor_cells"]), int(free["headroom_cells"]),
			str(bool(free["entered"])),
			str(bool(free["cabin"])), str(bool(half["cabin"])), str(bool(one["cabin"])),
		])
		print("      why: %s" % str(free["why"]))
		var compliance := VesselCompliance.validate(
			layout, hull_id, str(entry.get("registration_id", "")), preset_grid
		)
		print("      compliance ok=%s  (%s)" % [
			str(bool(compliance.get("ok", false))),
			VesselCompliance.checklist_summary(compliance),
		])

	print("\n=== 4. cost of the enclosure reading inside VesselOutfit.validate ===")
	var big_hull := "hull_90x24"
	var big_grid := HullRegistry.make_grid(big_hull)
	var big := _hollow(big_grid, 3, true)
	for i in 800:
		big.set_brick(big_grid, Vector3i(20 + (i % 20), i / 20, 40), "block")
	var t0 := Time.get_ticks_usec()
	var enc := BrickShellClassifier.enclosure(big, big_grid)
	var t1 := Time.get_ticks_usec()
	var cls := BrickShellClassifier.classify(big, big_grid)
	var t2 := Time.get_ticks_usec()
	var t3 := Time.get_ticks_usec()
	var rep := VesselOutfit.validate(big, big_hull, big_grid)
	var t4 := Time.get_ticks_usec()
	print("  %d bricks on %s: enclosure %.2f ms · classify %.2f ms · VesselOutfit.validate %.2f ms"
		% [big.count(), big_hull, float(t1 - t0) / 1000.0, float(t2 - t1) / 1000.0,
			float(t4 - t3) / 1000.0])
	print("  (enclosure pockets %d, classify exterior_air %d, has_cabin %s)" % [
		int(enc["pockets"]), int(cls["exterior_air_count"]),
		str(bool((rep["capabilities"] as Dictionary).get("has_cabin"))),
	])
	quit(0)


## The complement, computed here from `classify`'s OWN inputs rather than from
## the function under test — so §1 above is a check and not an echo.
func _independent_enclosed_count(layout: BrickLayout, grid: DeckGrid) -> int:
	var occupied := {}
	var mn := Vector3i(9999, 0, 9999)
	var mx := Vector3i(-9999, 0, -9999)
	for item_raw in layout.iter_primary_cells():
		var item := item_raw as Dictionary
		var cell: Vector3i = item["cell"]
		if not BrickLayout.cell_on_grid(
			grid, cell, str(item.get("brick_id", "")), int(item.get("yaw", 0))
		):
			continue
		for c in grid.footprint_cells(
			cell, BrickCatalog.footprint_of(str(item.get("brick_id", ""))),
			int(item.get("yaw", 0)) / 90
		):
			occupied[c] = true
			mn = Vector3i(mini(mn.x, c.x), 0, mini(mn.z, c.z))
			mx = Vector3i(maxi(mx.x, c.x), maxi(mx.y, c.y), maxi(mx.z, c.z))
	var lo := Vector3i(mn.x - 1, 0, mn.z - 1)
	var hi := Vector3i(mx.x + 1, mx.y + 1, mx.z + 1)
	## Flood from the whole boundary shell inward.
	var reached := {}
	var queue: Array[Vector3i] = []
	for y in range(lo.y, hi.y + 1):
		for z in range(lo.z, hi.z + 1):
			for x in range(lo.x, hi.x + 1):
				var on_shell := (
					x == lo.x or x == hi.x or z == lo.z or z == hi.z or y == hi.y
				)
				var cell := Vector3i(x, y, z)
				if on_shell and not occupied.has(cell) and not reached.has(cell):
					reached[cell] = true
					queue.append(cell)
	var read_i := 0
	while read_i < queue.size():
		var cell: Vector3i = queue[read_i]
		read_i += 1
		for offset in BrickShellClassifier.NEIGHBORS:
			var next: Vector3i = cell + offset
			if next.x < lo.x or next.y < lo.y or next.z < lo.z:
				continue
			if next.x > hi.x or next.y > hi.y or next.z > hi.z:
				continue
			if occupied.has(next) or reached.has(next):
				continue
			reached[next] = true
			queue.append(next)
	var volume := (hi.x - lo.x + 1) * (hi.y - lo.y + 1) * (hi.z - lo.z + 1)
	return volume - occupied.size() - reached.size()


func _fixtures(grid: DeckGrid) -> Array:
	var out: Array = []

	var fence := BrickLayout.new()
	fence.hull_id = HULL
	for i in 8:
		fence.set_brick(grid, Vector3i(6 + i, 0, 20), "block")
	out.append({"name": "8 blocks in a straight line", "layout": fence})

	var lone := BrickLayout.new()
	lone.hull_id = HULL
	lone.set_brick(grid, Vector3i(10, 0, 20), "block_door")
	out.append({"name": "one block_door alone", "layout": lone})

	out.append({"name": "hollow 5x5x3, lid, no door", "layout": _hollow(grid, 3, false)})
	out.append({"name": "the same with a door cut in", "layout": _hollow(grid, 3, true)})
	out.append({"name": "the same 5 courses tall", "layout": _hollow(grid, 5, true)})
	out.append({"name": "the same 4 courses tall", "layout": _hollow(grid, 4, true)})

	var roofless := _hollow(grid, 3, true)
	for x in 5:
		for z in 5:
			roofless.erase_cell(Vector3i(6 + x, 3, 18 + z))
	out.append({"name": "roofless: the same with no lid", "layout": roofless})

	var glazed := _hollow(grid, 3, false)
	glazed.set_brick(grid, Vector3i(8, 0, 18), "block_window")
	out.append({"name": "sealed box with a WINDOW in it", "layout": glazed})

	out.append({
		"name": "BrickLayout.starter_cargo", "layout": BrickLayout.starter_cargo(HULL, grid),
	})
	return out


## 5 x 5 footprint, `courses` high, hollow, with a lid. `door` swaps one wall
## cell on the bottom course for a `block_door`.
func _hollow(grid: DeckGrid, courses: int, door: bool) -> BrickLayout:
	var layout := BrickLayout.new()
	layout.hull_id = str(grid.width) if false else HULL
	for x in 5:
		for z in 5:
			for y in courses:
				var edge := x == 0 or x == 4 or z == 0 or z == 4
				if edge:
					layout.set_brick(grid, Vector3i(6 + x, y, 18 + z), "block")
			layout.set_brick(grid, Vector3i(6 + x, courses, 18 + z), "block")
	if door:
		layout.set_brick(grid, Vector3i(8, 0, 18), "block_door")
	return layout
