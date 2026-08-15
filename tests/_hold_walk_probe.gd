extends Node

## Scratch probe (leading underscore — NOT a gate unit). Lane B.
##
## Establishes what is ACTUALLY there at the fish hold on the starter boat:
## what the hold draws, what colliders the WalkDeck carries over its aperture,
## and what a 1.8 m capsule finds under its feet when it marches across it.
##
## Everything here goes through PhysicsServer3D on the body the fit-out really
## built (REALITY §3) — no AABBs, no baker dictionaries.

const CAP_R := 0.35
const CAP_H := 1.8
const STEP := 0.10


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var granted := CompanyService.build_starter_vessel_record(CompanyContracts.DEFAULT_STARTER)
	if granted.is_empty():
		print("ABORT: no starter grant")
		get_tree().quit(1)
		return
	var hull_id := str(granted.get("hull_id", ""))
	print("SUBJECT hull=%s prebuilt=%s" % [hull_id, str(granted.get("name", ""))])
	var boat := VesselSpawn.instantiate_from_record(granted)
	if boat == null:
		print("ABORT: no spawn")
		get_tree().quit(1)
		return
	boat.freeze = true
	boat.automatic_physics_lod = false
	add_child(boat)
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame

	var grid := HullRegistry.make_grid(hull_id)
	print("GRID deck_y=%.3f half_beam=%.3f half_loa=%.3f w=%d l=%d" % [
		grid.deck_y, grid.half_beam, grid.half_loa, grid.width, grid.length])

	var holds := CatchHoldComponent.get_all_for_ship(boat)
	print("HOLDS %d" % holds.size())
	for hold in holds:
		_describe_hold(hold, boat, grid)

	var walk := boat.get_walk_deck()
	print("WALKDECK %s layer=%d shapes=%d xf=%s" % [
		walk, walk.collision_layer, walk.get_child_count(), str(walk.global_transform)])
	if holds.is_empty():
		get_tree().quit(0)
		return
	var hold: CatchHoldComponent = holds[0]
	_describe_shapes_over(walk, boat, hold)
	_march(boat, grid, hold, true)
	_march(boat, grid, hold, false)
	_drop(boat, grid, hold)
	get_tree().quit(0)


func _describe_hold(hold: CatchHoldComponent, boat: BoatBody, grid: DeckGrid) -> void:
	var local := boat.to_local(hold.global_position)
	print("HOLD %s at boat-local %v footprint=%v capacity=%.0f (deck_y=%.3f)" % [
		hold.name, local, hold.footprint_m, hold.capacity_kg, grid.deck_y])
	var meshes := 0
	var bodies := 0
	var shapes := 0
	for node in hold.find_children("*", "", true, false):
		if node is MeshInstance3D:
			meshes += 1
		if node is CollisionObject3D:
			bodies += 1
			print("   BODY %s (%s)" % [node.name, node.get_class()])
		if node is CollisionShape3D:
			shapes += 1
	print("   drawn MeshInstance3D=%d  CollisionObject3D=%d  CollisionShape3D=%d" % [
		meshes, bodies, shapes])
	var box := _drawn_bounds(hold, boat)
	print("   drawn bounds (boat-local) x %.3f..%.3f  y %.3f..%.3f  z %.3f..%.3f" % [
		box.position.x, box.end.x, box.position.y, box.end.y, box.position.z, box.end.z])
	## Filled, because the water and the fish are drawn only when there is catch.
	hold.accept_lot(CatchLot.create({"lot_id": "probe", "mass_kg": 3900.0}))
	for node in hold.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		var xf := boat.global_transform.affine_inverse() * mi.global_transform
		var b := xf * mi.get_aabb()
		print("      mesh %-22s y %.3f..%.3f  x %.3f..%.3f  z %.3f..%.3f" % [
			str(mi.get_parent().name) + "/" + str(mi.name),
			b.position.y, b.end.y, b.position.x, b.end.x, b.position.z, b.end.z])
	var plate := boat.get_node_or_null("HullVisual/Deck") as MeshInstance3D
	if plate != null:
		var pb := (boat.global_transform.affine_inverse() * plate.global_transform) * plate.get_aabb()
		print("   HULL DECK PLATE y %.3f..%.3f (stations.deck_y=%.3f)" % [
			pb.position.y, pb.end.y, boat.hull_stations.deck_y])


func _drawn_bounds(hold: CatchHoldComponent, frame: Node3D) -> AABB:
	var to_frame := frame.global_transform.affine_inverse()
	var out := AABB()
	var first := true
	for node in hold.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree():
			continue
		var xf := to_frame * mi.global_transform
		for i in range(8):
			var p := xf * mi.get_aabb().get_endpoint(i)
			if first:
				out = AABB(p, Vector3.ZERO)
				first = false
			else:
				out = out.expand(p)
	return out


## Every collision shape on the WalkDeck whose footprint overlaps the hold's,
## as PhysicsServer3D holds it.
func _describe_shapes_over(walk: CollisionObject3D, boat: BoatBody, hold: CatchHoldComponent) -> void:
	var body := walk.get_rid()
	var n := PhysicsServer3D.body_get_shape_count(body)
	var hold_local := boat.to_local(hold.global_position)
	var half := Vector2(hold.footprint_m.x * 0.5, hold.footprint_m.z * 0.5)
	print("SHAPES on WalkDeck body: %d" % n)
	var owners := {}
	for child in walk.get_children():
		if child is CollisionShape3D:
			var cs := child as CollisionShape3D
			owners[cs.shape.get_rid()] = "%s%s" % [cs.name, " DISABLED" if cs.disabled else ""]
	for i in range(n):
		var sh := PhysicsServer3D.body_get_shape(body, i)
		var xf: Transform3D = PhysicsServer3D.body_get_shape_transform(body, i)
		var data: Variant = PhysicsServer3D.shape_get_data(sh)
		var world := walk.global_transform * xf
		var bl := boat.to_local(world.origin)
		var name_of := str(owners.get(sh, "?"))
		var size := (data as Vector3) * 2.0 if data is Vector3 else Vector3.ZERO
		if absf(bl.x - hold_local.x) > half.x + size.x * 0.5:
			continue
		if absf(bl.z - hold_local.z) > half.y + size.z * 0.5:
			continue
		print("   [%d] %-28s size=%v  boat-local centre=%v" % [i, name_of, size, bl])


## A 1.8 m capsule marched across the hold's footprint, feet on the deck plane.
## At every station: does the capsule overlap anything, and what is under its
## feet — the answer that says whether the aperture is a hole you walk over.
func _march(boat: BoatBody, grid: DeckGrid, hold: CatchHoldComponent, across: bool) -> void:
	var space := boat.get_world_3d().direct_space_state
	var capsule := CapsuleShape3D.new()
	capsule.radius = CAP_R
	capsule.height = CAP_H
	var hl := boat.to_local(hold.global_position)
	var half := Vector2(hold.footprint_m.x * 0.5, hold.footprint_m.z * 0.5)
	var span := (half.x if across else half.y) + 1.2
	var stations := 0
	var blocked := 0
	var supported_at_deck := 0
	var over_pit := 0
	var over_pit_supported := 0
	var lines := PackedStringArray()
	var u := -span
	while u <= span + 0.0001:
		var at := Vector3(hl.x + u, 0.0, hl.z) if across else Vector3(hl.x, 0.0, hl.z + u)
		var feet := grid.deck_y + 0.02
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = capsule
		q.transform = Transform3D(Basis.IDENTITY, boat.to_global(
			Vector3(at.x, feet + CAP_H * 0.5, at.z)))
		q.collision_mask = BoatBody.LAYER_BOAT_WALK
		var hits := space.intersect_shape(q, 8)
		var is_blocked := not hits.is_empty()
		## What holds the feet up: a ray straight down from ankle height.
		var ray := PhysicsRayQueryParameters3D.create(
			boat.to_global(Vector3(at.x, grid.deck_y + 0.60, at.z)),
			boat.to_global(Vector3(at.x, grid.deck_y - 4.0, at.z)),
			BoatBody.LAYER_BOAT_WALK,
		)
		var hit := space.intersect_ray(ray)
		var support := -999.0
		if not hit.is_empty():
			support = boat.to_local(hit["position"] as Vector3).y
		var inside := absf(u) <= (half.x if across else half.y)
		stations += 1
		if is_blocked:
			blocked += 1
		if inside:
			over_pit += 1
			if support > grid.deck_y - 0.5:
				over_pit_supported += 1
		if support > grid.deck_y - 0.5:
			supported_at_deck += 1
		lines.append("   u=%+.2f %s  blocked=%s  support_y=%.3f (deck %.3f, pit floor %.3f)" % [
			u, "INSIDE " if inside else "outside", str(is_blocked), support,
			grid.deck_y, grid.deck_y - hold.footprint_m.y,
		])
		u += STEP
	print("MARCH %s the hold: %d stations, %d blocked, %d supported at deck level; "
		% ["across (x)" if across else "along (z)", stations, blocked, supported_at_deck]
		+ "%d stations stand over the aperture, %d of those find deck under their feet"
		% [over_pit, over_pit_supported])
	for l in lines:
		print(l)


## Drop a capsule from above the hatch centre and report where it comes to rest.
func _drop(boat: BoatBody, grid: DeckGrid, hold: CatchHoldComponent) -> void:
	var space := boat.get_world_3d().direct_space_state
	var capsule := CapsuleShape3D.new()
	capsule.radius = CAP_R
	capsule.height = CAP_H
	var hl := boat.to_local(hold.global_position)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = capsule
	q.transform = Transform3D(Basis.IDENTITY, boat.to_global(
		Vector3(hl.x, grid.deck_y + 6.0 + CAP_H * 0.5, hl.z)))
	q.collision_mask = BoatBody.LAYER_BOAT_WALK
	q.motion = Vector3(0.0, -20.0, 0.0)
	var res := space.cast_motion(q)
	var fall: float = 20.0 * float(res[0])
	var rest := grid.deck_y + 6.0 - fall
	print("DROP at hatch centre: capsule feet come to rest at boat-local y=%.3f "
		% rest + "(deck %.3f, pit floor %.3f, hull bottom-ish %.3f)" % [
			grid.deck_y, grid.deck_y - hold.footprint_m.y, 0.0])
