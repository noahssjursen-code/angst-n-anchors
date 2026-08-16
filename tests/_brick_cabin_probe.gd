extends SceneTree

## SCRATCH PROBE (leading underscore -> skipped by tools/gate.sh discovery).
## What `VesselOutfit`'s `has_cabin` actually says today, and what the brick
## cell is worth in metres. Prints numbers; asserts nothing.

const HULL := "hull_28x10"


func _initialize() -> void:
	var grid := HullRegistry.make_grid(HULL)

	print("=== the brick cell, measured rather than quoted ===")
	print("  BuildingGrid.CELL_M          = ", BuildingGrid.CELL_M)
	print("  WorldUnits.DECK_CELL_M       = ", WorldUnits.DECK_CELL_M)
	for id in ["block", "wall", "door", "window"]:
		if BrickCatalog.has(id):
			print("  BrickCatalog.size_m(\"%s\")  = %s  footprint %s"
				% [id, str(BrickCatalog.size_m(id)), str(BrickCatalog.footprint_of(id))])

	print("\n=== which bricks feed door_n / wall_n ===")
	var doors: Array[String] = []
	var walls: Array[String] = []
	for raw in BrickCatalog.BRICKS.keys():
		var id := str(raw)
		if BrickCatalog.has_tag(id, "door"):
			doors.append(id)
		if BrickCatalog.has_tag(id, "wall") or BrickCatalog.has_tag(id, "solid"):
			walls.append(id)
	print("  door-tagged: %d %s" % [doors.size(), str(doors)])
	print("  wall/solid-tagged: %d  (first 12) %s" % [walls.size(), str(walls.slice(0, 12))])

	print("\n=== a FENCE of bricks: 8 wall/solid bricks in a straight line ===")
	var brick := walls[0] if not walls.is_empty() else "block"
	var fence := BrickLayout.new()
	fence.hull_id = HULL
	for i in 8:
		fence.set_brick(grid, Vector3i(6 + i, 0, 20), brick)
	var fence_report := VesselOutfit.validate(fence, HULL, grid)
	print("  bricks placed: ", fence.count(), " of brick \"%s\"" % brick)
	print("  has_cabin -> ", bool((fence_report["capabilities"] as Dictionary).get("has_cabin")))

	print("\n=== ONE door brick, standing alone on the deck ===")
	if not doors.is_empty():
		var lone := BrickLayout.new()
		lone.hull_id = HULL
		lone.set_brick(grid, Vector3i(10, 0, 20), doors[0])
		var lone_report := VesselOutfit.validate(lone, HULL, grid)
		print("  bricks placed: ", lone.count())
		print("  has_cabin -> ",
			bool((lone_report["capabilities"] as Dictionary).get("has_cabin")))

	print("\n=== does that certify passenger_vessel/cabin? ===")
	var compliance := VesselCompliance.validate(fence, HULL, "passenger_vessel", grid)
	for row_raw in compliance.get("checklist", []) as Array:
		var row := row_raw as Dictionary
		if str(row.get("id", "")).contains("cabin"):
			print("  rule %s -> ok=%s  %s"
				% [str(row.get("id")), str(row.get("ok")), str(row.get("message", ""))])

	print("\n=== BrickShellClassifier: what it publishes ===")
	var hollow := BrickLayout.new()
	hollow.hull_id = HULL
	## A 5 x 5 footprint, 3 courses high, hollow, with a lid.
	for x in 5:
		for z in 5:
			for y in 3:
				var edge := x == 0 or x == 4 or z == 0 or z == 4
				if edge:
					hollow.set_brick(grid, Vector3i(6 + x, y, 18 + z), brick)
			hollow.set_brick(grid, Vector3i(6 + x, 3, 18 + z), brick)
	var shell: Dictionary = BrickShellClassifier.classify(hollow, grid)
	print("  hollow cabin bricks: ", hollow.count())
	print("  exterior: %d  interior: %d  exterior_air_count: %d"
		% [(shell["exterior"] as Array).size(), (shell["interior"] as Array).size(),
			int(shell["exterior_air_count"])])
	print("  keys published: ", shell.keys())
	var hollow_report := VesselOutfit.validate(hollow, HULL, grid)
	print("  has_cabin -> ",
		bool((hollow_report["capabilities"] as Dictionary).get("has_cabin")))
	quit(0)
