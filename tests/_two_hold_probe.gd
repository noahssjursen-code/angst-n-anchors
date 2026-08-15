extends Node

## Scratch probe (leading underscore — NOT a gate unit). Lane B.
##
## Which two-winch LAYOUT actually makes two holds land on the same deck?
## `catch_hold_test`'s first fixture put the winches six cells apart and the two
## berths came out separate WITHOUT the fix — the check had never been shown the
## shape it exists to catch.

const HULL := "hull_28x10"


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	for spread in [-2]:
		await _try(spread)
	get_tree().quit(0)


## `spread` >= 0: second winch that many cells aft of the first, both found
## walking aft from midships. -1: winches at the two ENDS of the clear deck.
func _try(spread: int) -> void:
	var grid := HullRegistry.make_grid(HULL)
	var bare := BrickLayout.starter_cargo(HULL, grid)
	var layout := BrickLayout.starter_cargo(HULL, grid)
	var helm_at := _first_clear(layout, grid, "helm", grid.length / 2, -1)
	if helm_at.x >= 0:
		layout.place_footprint(helm_at, "helm", 0, grid)
		bare.place_footprint(helm_at, "helm", 0, grid)
	var winches: Array[Vector3i] = []
	if spread >= 0:
		var from_z := grid.length / 2
		for i in 2:
			var at := _first_clear(layout, grid, "trommel_small", from_z, 1)
			if at.x < 0 or not layout.place_footprint(at, "trommel_small", 0, grid):
				break
			winches.append(at)
			from_z = at.z + spread
	elif spread == -2:
		## No deckhouse: ONE long clear run with a winch at each end. Every other
		## fixture had the starter deckhouse sitting between the two winches,
		## which splits the deck into two runs and separates the holds by itself.
		layout = BrickLayout.new()
		layout.hull_id = HULL
		bare = BrickLayout.new()
		bare.hull_id = HULL
		var fp2 := BrickCatalog.footprint_of("trommel_small")
		var a := Vector3i(maxi((grid.width - fp2.x) / 2, 0), 0, 1)
		var b := Vector3i(a.x, 0, grid.length - fp2.z - 2)
		if layout.place_footprint(a, "trommel_small", 0, grid):
			winches.append(a)
		if layout.place_footprint(b, "trommel_small", 0, grid):
			winches.append(b)
	else:
		var fwd := _first_clear(layout, grid, "trommel_small", 2, 1)
		if fwd.x >= 0 and layout.place_footprint(fwd, "trommel_small", 0, grid):
			winches.append(fwd)
		var fp := BrickCatalog.footprint_of("trommel_small")
		var aft := _first_clear(layout, grid, "trommel_small", grid.length - fp.z - 1, -1)
		if aft.x >= 0 and layout.place_footprint(aft, "trommel_small", 0, grid):
			winches.append(aft)
	print("SPREAD %d -> winches %s" % [spread, str(winches)])
	if winches.size() != 2:
		return
	var boat := VesselSpawn.instantiate(HULL, bare.to_dict(), "fishing_vessel")
	if boat == null:
		return
	boat.freeze = true
	boat.automatic_physics_lod = false
	add_child(boat)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var root := boat.get_node_or_null(DeckFitout.FITOUT_ROOT) as Node3D
	var accepted := {}
	for cell in winches:
		accepted[cell] = true
	var state := {"brick_i": 0, "ladder_n": 0, "layout": layout}
	for cell in winches:
		var item := {"cell": cell, "brick_id": "trommel_small", "yaw": 0}
		var visual := DeckFitout.create_item_visual(root, grid, item)
		DeckFitout.mount_item_gameplay(boat, root, grid, item, visual, accepted, {}, state)
	await get_tree().physics_frame
	var holds := CatchHoldComponent.get_all_for_ship(boat)
	print("   holds: %d" % holds.size())
	var boxes: Array[AABB] = []
	for hold in holds:
		var hl := boat.to_local(hold.global_position)
		print("      %s id=%s at z %.2f footprint %v" % [
			hold.name, hold.get_state().hold_id, hl.z, hold.footprint_m])
		boxes.append(AABB(
			Vector3(hl.x - hold.footprint_m.x * 0.5, 0.0, hl.z - hold.footprint_m.z * 0.5),
			Vector3(hold.footprint_m.x, 1.0, hold.footprint_m.z),
		))
	if boxes.size() == 2:
		var dz: float = minf(boxes[0].end.z, boxes[1].end.z) - maxf(boxes[0].position.z, boxes[1].position.z)
		print("      z overlap %.3f m (negative = clear gap)" % dz)
	remove_child(boat)
	boat.free()
	await get_tree().process_frame


func _first_clear(
	layout: BrickLayout, grid: DeckGrid, brick_id: String, z_start: int, step: int
) -> Vector3i:
	var fp := BrickCatalog.footprint_of(brick_id)
	var x := maxi((grid.width - fp.x) / 2, 0)
	var iz := z_start
	while iz >= 0 and iz + fp.z <= grid.length:
		var ok := true
		for c in grid.footprint_cells(Vector3i(x, 0, iz), fp, 0):
			if not grid.in_bounds(c) or layout.has_cell(c):
				ok = false
				break
		if ok:
			return Vector3i(x, 0, iz)
		iz += step
	return Vector3i(-1, -1, -1)
