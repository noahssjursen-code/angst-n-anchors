extends Node

## Scratch probe (leading underscore — NOT a gate unit). Lane B.
##
## The wheelhouse is walked into and stood in, so the question "did moving that
## geometry break it" is answered by `PhysicsServer3D` against the body the
## production spawn path actually builds — not by reading the layout dictionary.
##
## Subject: `CompanyService.build_starter_vessel_record(CompanyContracts.DEFAULT_STARTER)`
## through `VesselSpawn.instantiate_from_record`, i.e. onboarding's own two calls.
##
## EVERY sweep has a control that must come back BLOCKED. A doorway query that
## says "clear" is worthless unless the same query says "solid" against the wall
## two cells beside it — otherwise it is measuring an empty collision world and
## scoring it as a door (REALITY §4).
##
## Run:
##   xvfb-run -a --server-args="-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy res://tests/_house_capsule_probe.tscn

const RADIUS := 0.35 ## scenes/shared/player.tscn
const HEIGHTS := [1.8, 1.6, 1.4, 1.2]


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var record := CompanyService.build_starter_vessel_record(CompanyContracts.DEFAULT_STARTER)
	if record.is_empty():
		print("ABORT — onboarding grants nothing for '%s'" % CompanyContracts.DEFAULT_STARTER)
		get_tree().quit(1)
		return
	var boat: BoatBody = VesselSpawn.instantiate_from_record(record)
	if boat == null:
		print("ABORT — the granted record would not spawn")
		get_tree().quit(1)
		return
	boat.name = "HouseCapsule"
	boat.automatic_physics_lod = false
	add_child(boat)
	boat.place_at_waterline(WaveSurface.WATER_LEVEL)
	for _f in range(6):
		await get_tree().physics_frame

	var hull_id := str(record.get("hull_id", ""))
	var grid := HullRegistry.make_grid(hull_id)
	var walk := boat.call("get_walk_deck") as CollisionObject3D
	if walk == null:
		print("ABORT — no WalkDeck body")
		get_tree().quit(1)
		return
	var shapes := PhysicsServer3D.body_get_shape_count(walk.get_rid())
	print("SUBJECT hull=%s  WalkDeck shapes in PhysicsServer3D = %d" % [hull_id, shapes])
	if shapes == 0:
		print("ABORT — the walk body carries no shapes, so nothing below can fail")
		get_tree().quit(1)
		return
	var space := walk.get_world_3d().direct_space_state

	## Cell geometry of the house, derived from the grid rather than typed.
	var x0 := 2
	var x1 := 7
	var z0 := 9
	var z1 := 16
	var door_x0 := x0 + 2 ## `_prebuilt_gen._add_deckhouse` places the door here
	var deck_y := grid.deck_y

	var door_c := grid.cell_center_local(Vector3i(door_x0, 0, z1))
	var door_c2 := grid.cell_center_local(Vector3i(door_x0 + 1, 0, z1))
	var door_x := (door_c.x + door_c2.x) * 0.5
	var door_z: float = door_c.z
	var wall_x: float = grid.cell_center_local(Vector3i(x0 + 1, 0, z1)).x
	var inside_z: float = grid.cell_center_local(Vector3i(door_x0, 0, (z0 + z1) / 2)).z
	var side_x: float = grid.cell_center_local(Vector3i(x0 - 1, 0, (z0 + z1) / 2)).x

	## Start the sweep BETWEEN the door and the net drum. At door_z + 1.6 m the
	## capsule's first contact was `trommel_small` (a 4-cell run starting three
	## cells abaft the house), so every row read BLOCKED at exactly 1.00 m — the
	## door and the wall alike — and the "control blocks too" would have been
	## read as the door being solid. It was the winch.
	var start_z := grid.cell_center_local(Vector3i(door_x0, 0, z1 + 2)).z
	print("\n── THROUGH THE DOOR, and the same sweep 1.0 m to port through solid wall ──")
	print("  sweep starts at z=%.2f (%.2f m abaft the door plane), clear of the net drum" % [
		start_z, start_z - door_z,
	])
	print("  %-6s %-28s %-28s" % ["height", "door centreline", "CONTROL: wall beside it"])
	for h_variant in HEIGHTS:
		var h: float = h_variant
		## +0.25 of clearance above the deck plane, the same standing offset
		## `starter_small_hull_test._check_a_player_can_stand_on_it` uses. At
		## +0.02 every query — including one on the open working deck — came back
		## SOLID, because the capsule started inside the deck plate's own collider.
		var y := deck_y + 0.25 + h * 0.5
		var door_r := _sweep(space, boat, h, Vector3(door_x, y, start_z), Vector3(door_x, y, inside_z))
		var wall_r := _sweep(space, boat, h, Vector3(wall_x, y, start_z), Vector3(wall_x, y, inside_z))
		print("  %-6.2f %-28s %-28s%s" % [
			h, door_r, wall_r,
			"" if wall_r.begins_with("BLOCKED") else "   *** CONTROL DID NOT BLOCK ***",
		])

	print("\n── STANDING ──")
	_stand(space, boat, 1.8, Vector3(door_x, deck_y + 0.25 + 0.9, inside_z), "inside the wheelhouse, 1.8 m")
	## The side deck is cells 0 and 1; cell 0 carries the railing, so the clear
	## walkway is ONE 0.5 m cell against a 0.70 m capsule. That is a property of
	## a 6-cell house on a 10-cell beam and is unchanged by this wave — reported,
	## not fixed.
	_stand(space, boat, 1.8, Vector3(side_x, deck_y + 0.25 + 0.9, inside_z), "on the port side deck beside the house, 1.8 m")
	_stand(space, boat, 1.8, Vector3(door_x, deck_y + 0.25 + 0.9, start_z), "on the working deck abaft the house, 1.8 m")
	## Control: the same standing query INSIDE a wall must report solid.
	_stand(space, boat, 1.8, Vector3(wall_x, deck_y + 0.25 + 0.9, grid.cell_center_local(Vector3i(x0, 0, z0)).z), "CONTROL — inside the forward wall (must be SOLID)")

	print("\n── HEADROOM UNDER THE ROOF, measured ──")
	var roof_c := grid.cell_center_local(Vector3i(x0 + 1, 5, (z0 + z1) / 2))
	print("  roof cell centre y (local) = %.3f, deck_y = %.3f -> %.2f m of house" % [
		roof_c.y, deck_y, roof_c.y - deck_y,
	])
	boat.free()
	await get_tree().process_frame
	print("\nPROBE DONE")
	get_tree().quit(0)


## Cast a capsule from `from` to `to` in BOAT-LOCAL coordinates and say how far
## it got. Refuses to report a clear run when the capsule STARTS overlapping —
## `cast_motion` from inside a body returns a clean 1.0 and would be scored as
## "walked straight through" (the trap `starter_small_hull_test._drop` names).
func _sweep(
	space: PhysicsDirectSpaceState3D,
	boat: BoatBody,
	height: float,
	from: Vector3,
	to: Vector3,
) -> String:
	var capsule := CapsuleShape3D.new()
	capsule.radius = RADIUS
	capsule.height = height
	var a := boat.to_global(from)
	var b := boat.to_global(to)
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = capsule
	params.transform = Transform3D(Basis.IDENTITY, a)
	params.collision_mask = BoatBody.LAYER_BOAT_WALK
	if not space.intersect_shape(params, 1).is_empty():
		return "START OVERLAPPING (unusable)"
	params.motion = b - a
	var result := space.cast_motion(params)
	var fraction: float = result[0]
	var span := a.distance_to(b)
	if fraction >= 0.999:
		return "CLEAR (%.2f m)" % span
	return "BLOCKED at %.2f of %.2f m" % [fraction * span, span]


func _stand(
	space: PhysicsDirectSpaceState3D,
	boat: BoatBody,
	height: float,
	at: Vector3,
	label: String,
) -> void:
	var capsule := CapsuleShape3D.new()
	capsule.radius = RADIUS
	capsule.height = height
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = capsule
	params.transform = Transform3D(Basis.IDENTITY, boat.to_global(at))
	params.collision_mask = BoatBody.LAYER_BOAT_WALK
	var hits := space.intersect_shape(params, 8).size()
	print("  %-52s %s (%d overlapping shapes)" % [
		label, "CLEAR" if hits == 0 else "SOLID", hits,
	])
