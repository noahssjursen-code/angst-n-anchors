extends Node

## Scratch probe (leading underscore — NOT a gate unit). Lane B.
##
## Every capsule sweep taken at the wheelhouse so far measured `BrickDoor` in its
## CLOSED state, so "a 1.8 m capsule is blocked at the door" could not be told
## apart from "the doorway is too small". This drives the door open through its
## own API — `toggle()`, the same call `_unhandled_input` makes on F — and
## re-measures.
##
## Subject: `CompanyService.build_starter_vessel_record(CompanyContracts.DEFAULT_STARTER)`
## through `VesselSpawn.instantiate_from_record`, i.e. onboarding's own two calls.
##
## Run:
##   xvfb-run -a --server-args="-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy res://tests/_house_door_probe.tscn

const RADIUS := 0.35 ## scenes/shared/player.tscn
const CELL := 0.5

var _boat: BoatBody
var _grid: DeckGrid
var _space: PhysicsDirectSpaceState3D


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var record := CompanyService.build_starter_vessel_record(CompanyContracts.DEFAULT_STARTER)
	if record.is_empty():
		print("ABORT — onboarding grants nothing")
		get_tree().quit(1)
		return
	_boat = VesselSpawn.instantiate_from_record(record)
	if _boat == null:
		print("ABORT — the granted record would not spawn")
		get_tree().quit(1)
		return
	_boat.name = "DoorProbe"
	_boat.automatic_physics_lod = false
	add_child(_boat)
	_boat.place_at_waterline(WaveSurface.WATER_LEVEL)
	for _f in range(6):
		await get_tree().physics_frame

	var hull_id := str(record.get("hull_id", ""))
	_grid = HullRegistry.make_grid(hull_id)
	var layout := BrickLayout.from_dict(VesselSpawn.brick_layout_of(record))
	var walk := _boat.call("get_walk_deck") as CollisionObject3D
	if walk == null:
		print("ABORT — no WalkDeck body")
		get_tree().quit(1)
		return
	_space = walk.get_world_3d().direct_space_state
	var shapes_closed := PhysicsServer3D.body_get_shape_count(walk.get_rid())
	print("SUBJECT %s on %s — WalkDeck shapes = %d" % [
		str(record.get("prebuilt_id", record.get("name", "?"))), hull_id, shapes_closed,
	])

	## Where the door is, taken from the layout rather than typed.
	var door_cell := Vector3i(-1, -1, -1)
	var door_id := ""
	for item in layout.iter_primary_cells():
		if BrickCatalog.has_tag(str(item.get("brick_id", "")), "door"):
			door_cell = item["cell"]
			door_id = str(item.get("brick_id", ""))
			break
	if door_cell.x < 0:
		print("ABORT — no door brick in the granted layout")
		get_tree().quit(1)
		return
	var fp := BrickCatalog.footprint_of(door_id)
	var sz := BrickCatalog.size_m(door_id)
	print("\n── THE DOORWAY AS DRAWN ──")
	print("  brick '%s' at %v, footprint %v cells, drawn %.2f x %.2f x %.2f m" % [
		door_id, door_cell, fp, sz.x, sz.y, sz.z,
	])
	var opening := _drawn_opening(door_id)
	print("  clear opening between the frame members: %.3f m wide x %.3f m high" % [
		opening.x, opening.y,
	])
	print("  a 1.8 m player capsule is %.2f m across (radius %.2f) and 1.80 m tall" % [
		RADIUS * 2.0, RADIUS,
	])

	## Sweep line: start on the working deck abaft the house, finish inside it.
	var door_x := (
		_grid.cell_center_local(door_cell).x
		+ _grid.cell_center_local(door_cell + Vector3i(fp.x - 1, 0, 0)).x
	) * 0.5
	var door_z := _grid.cell_center_local(door_cell).z
	var wall_x := _grid.cell_center_local(door_cell - Vector3i(2, 0, 0)).x
	var start_z := door_z + 1.0
	var inside_z := door_z - 1.5
	var deck_y := _grid.deck_y

	var door := _find_door()
	if door == null:
		print("ABORT — the fit-out mounted no BrickDoor node")
		get_tree().quit(1)
		return

	print("\n── CLOSED (every earlier sweep's state) ──")
	_sweep_table(door_x, wall_x, start_z, inside_z, deck_y)

	## The real API. `toggle()` routes through WorldStateBinding when a session is
	## up and falls back to `set_open` otherwise; either way this is the call F
	## makes, not a hand-set flag.
	door.call("toggle")
	for _f in range(30):
		await get_tree().process_frame
	await get_tree().physics_frame
	var shapes_open := PhysicsServer3D.body_get_shape_count(walk.get_rid())
	print("\n── OPEN — door.is_open()=%s, WalkDeck shapes %d -> %d ──" % [
		str(door.call("is_open")), shapes_closed, shapes_open,
	])
	if not bool(door.call("is_open")):
		print("  *** toggle() DID NOT OPEN THE DOOR — everything below is still the closed state ***")
	_sweep_table(door_x, wall_x, start_z, inside_z, deck_y)

	print("\n── HOW BIG A CAPSULE DOES THE OPEN DOOR PASS? ──")
	print("  Two independent limits, so they are varied one at a time (REALITY §4e).")
	for r_variant in [0.35, 0.30, 0.20, 0.10]:
		var r: float = r_variant
		var tallest := 0.0
		var h := 1.90
		while h >= 0.40:
			var y := deck_y + 0.25 + h * 0.5
			if _sweep(r, h, Vector3(door_x, y, start_z), Vector3(door_x, y, inside_z)).begins_with("CLEAR"):
				tallest = h
				break
			h -= 0.05
		print("  radius %.2f m (%.2f m across): tallest capsule that walks through = %s" % [
			r, r * 2.0, "%.2f m" % tallest if tallest > 0.0 else "none above 0.40 m",
		])
	print("  Height is the binding limit and width is not: shrinking the capsule to")
	print("  0.20 m across buys nothing, because the wall block above the door brick")
	print("  is what the head hits.")

	_boat.free()
	await get_tree().process_frame
	print("\nPROBE DONE")
	get_tree().quit(0)


func _sweep_table(
	door_x: float, wall_x: float, start_z: float, inside_z: float, deck_y: float
) -> void:
	print("  %-7s %-30s %-30s" % ["height", "door centreline", "CONTROL: wall beside it"])
	for h_variant in [1.8, 1.6, 1.4, 1.2, 1.0]:
		var h: float = h_variant
		var y := deck_y + 0.25 + h * 0.5
		var d := _sweep(RADIUS, h, Vector3(door_x, y, start_z), Vector3(door_x, y, inside_z))
		var w := _sweep(RADIUS, h, Vector3(wall_x, y, start_z), Vector3(wall_x, y, inside_z))
		print("  %-7.2f %-30s %-30s%s" % [
			h, d, w, "" if w.begins_with("BLOCKED") else "   *** CONTROL DID NOT BLOCK ***",
		])


## The clear rectangle the door's own visual leaves between its frame members,
## measured off the meshes rather than re-derived from the frame constants.
func _drawn_opening(brick_id: String) -> Vector2:
	var sample := BrickCatalog.create_visual(brick_id, {})
	var sz := BrickCatalog.size_m(brick_id)
	var left := -sz.x * 0.5
	var right := sz.x * 0.5
	var top := sz.y * 0.5
	var bottom := -sz.y * 0.5
	for child in sample.get_children():
		var mi := child as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var aabb := mi.mesh.get_aabb()
		aabb.position += mi.position
		## Full-height members are the jambs; full-width ones are lintel and sill.
		if aabb.size.y > sz.y * 0.9:
			if aabb.position.x < 0.0:
				left = maxf(left, aabb.position.x + aabb.size.x)
			else:
				right = minf(right, aabb.position.x)
		elif aabb.size.x > sz.x * 0.5:
			if aabb.position.y < 0.0:
				bottom = maxf(bottom, aabb.position.y + aabb.size.y)
			else:
				top = minf(top, aabb.position.y)
	sample.free()
	return Vector2(right - left, top - bottom)


func _find_door() -> Node:
	for node in get_tree().get_nodes_in_group(BrickDoor.GROUP):
		if _boat.is_ancestor_of(node):
			return node
	return null


func _sweep(radius: float, height: float, from: Vector3, to: Vector3) -> String:
	var capsule := CapsuleShape3D.new()
	capsule.radius = radius
	capsule.height = height
	var a := _boat.to_global(from)
	var b := _boat.to_global(to)
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = capsule
	params.transform = Transform3D(Basis.IDENTITY, a)
	params.collision_mask = BoatBody.LAYER_BOAT_WALK
	if not _space.intersect_shape(params, 1).is_empty():
		return "START OVERLAPPING (unusable)"
	params.motion = b - a
	var result := _space.cast_motion(params)
	var fraction: float = result[0]
	var span := a.distance_to(b)
	if fraction >= 0.999:
		return "CLEAR (%.2f m)" % span
	return "BLOCKED at %.2f of %.2f m" % [fraction * span, span]
