extends Node

## Scratch probe (leading underscore — NOT a gate unit). Lane B.
## Why 7 of 63 stand-stations on hull_150x32 find the deck instead of the hold.

const HULL := "hull_150x32"


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var grid := HullRegistry.make_grid(HULL)
	var layout := BrickLayout.starter_cargo(HULL, grid)
	var helm_at := _first_clear(layout, grid, "helm", grid.length / 2, -1)
	if helm_at.x >= 0:
		layout.place_footprint(helm_at, "helm", 0, grid)
	var winch_at := _first_clear(layout, grid, "trommel_small", grid.length / 2, 1)
	layout.place_footprint(winch_at, "trommel_small", 0, grid)
	var boat := VesselSpawn.instantiate(HULL, layout.to_dict(), "fishing_vessel")
	boat.freeze = true
	boat.automatic_physics_lod = false
	add_child(boat)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var holds := CatchHoldComponent.get_all_for_ship(boat)
	print("HOLDS %d  grid deck_y=%.3f half_beam=%.3f" % [holds.size(), grid.deck_y, grid.half_beam])
	for hold in holds:
		var hl := boat.to_local(hold.global_position)
		print("HOLD at %v footprint %v" % [hl, hold.footprint_m])
		var to_boat := boat.global_transform.affine_inverse()
		for node in hold.find_children("*", "MeshInstance3D", true, false):
			var mi := node as MeshInstance3D
			if mi.mesh == null:
				continue
			var b := (to_boat * mi.global_transform) * mi.get_aabb()
			print("   mesh %-14s x %8.3f..%8.3f  y %8.3f..%8.3f  z %8.3f..%8.3f" % [
				mi.name, b.position.x, b.end.x, b.position.y, b.end.y, b.position.z, b.end.z])
		print("   SOLID boxes declared: %d" % hold.solid_boxes().size())
		for box in hold.solid_boxes():
			var p: Vector3 = box["pos"]
			var s: Vector3 = box["size"]
			print("      solid pos %v size %v -> boat x %.3f..%.3f" % [
				p, s, hl.x + p.x - s.x * 0.5, hl.x + p.x + s.x * 0.5])
	var walk := boat.get_walk_deck()
	var n := 0
	for child in walk.get_children():
		if str(child.name).begins_with("BrickCol_hold_"):
			var cs := child as CollisionShape3D
			var size := (cs.shape as BoxShape3D).size
			print("   COLLIDER %-18s size %v at walk-local %v" % [cs.name, size, cs.position])
			n += 1
	print("hold colliders on the body: %d" % n)
	get_tree().quit(0)


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
