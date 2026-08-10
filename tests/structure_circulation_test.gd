extends SceneTree

## Headless contract test for the circulation primitive that survived the room
## purge: stairs — their geometry, their colliders, their save/load, and the
## yaw-honouring containment maths that decides whether a player can walk
## somewhere. The corridor/open-face legs went with the room primitive. Run:
##   godot --headless -s tests/structure_circulation_test.gd
## Exit 0 = all assertions hold.

var _failures := 0


func _check(label: String, ok: bool) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		_failures += 1


func _initialize() -> void:
	_test_stair_geometry()
	_test_stair_directions()
	_test_colliders_include_stairs()
	_test_roundtrip()
	_test_wall_openings_stay_passable()
	_test_diagonal_passability()
	print("---")
	print("structure_circulation_test: %s" % ("ALL PASS" if _failures == 0 else "%d FAILURES" % _failures))
	quit(0 if _failures == 0 else 1)


func _test_stair_geometry() -> void:
	var plan := StructurePlan.new()
	var stair := plan.add_stair(Vector3(2, 0, 4), "+x", 4.0, 1.5, 3.0)
	var steps := StructureBaker.stair_step_count(stair)
	_check("step count targets ~22 cm risers", steps == 14)
	var boxes := StructureBaker.stair_boxes(stair)
	_check("one box per step", boxes.size() == steps)
	var top := 0.0
	var monotonic := true
	var previous := -INF
	for box_variant in boxes:
		var box := box_variant as Dictionary
		var box_top := (box["center"] as Vector3).y + (box["size"] as Vector3).y * 0.5
		if box_top < previous:
			monotonic = false
		previous = box_top
		top = maxf(top, box_top)
	_check("steps rise monotonically", monotonic)
	_check("top tread lands flush on start.y + height", absf(top - 3.0) < 0.001)
	var first := boxes[0] as Dictionary
	var first_min_x := (first["center"] as Vector3).x - (first["size"] as Vector3).x * 0.5
	_check("+x climb starts at the low-end footprint edge", absf(first_min_x - 2.0) < 0.001)
	var last := boxes[boxes.size() - 1] as Dictionary
	var last_max_x := (last["center"] as Vector3).x + (last["size"] as Vector3).x * 0.5
	_check("run spans the full length", absf(last_max_x - 6.0) < 0.001)


func _test_stair_directions() -> void:
	var plan := StructurePlan.new()
	var stair := plan.add_stair(Vector3(0, 0, 0), "-z", 3.0, 1.0, 3.0)
	var boxes := StructureBaker.stair_boxes(stair)
	## Climbing -z: the LOW end is at the +z footprint edge (z = 3), the top
	## step hugs z = 0.
	var first := boxes[0] as Dictionary
	var first_max_z := (first["center"] as Vector3).z + (first["size"] as Vector3).z * 0.5
	_check("-z climb starts at the +z footprint edge", absf(first_max_z - 3.0) < 0.001)
	var last := boxes[boxes.size() - 1] as Dictionary
	var last_min_z := (last["center"] as Vector3).z - (last["size"] as Vector3).z * 0.5
	_check("-z climb tops out at the -z footprint edge", absf(last_min_z - 0.0) < 0.02)


func _test_colliders_include_stairs() -> void:
	var plan := StructurePlan.new()
	plan.add_stair(Vector3(0, 0, 0), "+z", 3.0, 1.0, 3.0)
	var colliders := StructureBaker.collect_colliders(plan)
	_check("colliders cover every step", colliders.size() == StructureBaker.stair_step_count(plan.stairs[0]))
	var bake := StructureBaker.bake(plan)
	_check("bake emits stair surfaces", bake.get_child_count() > 0)
	bake.free()


func _test_roundtrip() -> void:
	var plan := StructurePlan.new()
	plan.add_stair(Vector3(1, 0, 2), "-x", 5.0, 2.0, 3.0)
	plan.add_wall(Vector3(0, 0, 0), "z", 8.0, 3.0)
	var restored := StructurePlan.from_dict(plan.to_dict())
	_check("stairs survive save/load", restored.stairs.size() == 1)
	var stair := restored.stairs[0] as Dictionary
	_check("stair fields survive", str(stair.get("dir")) == "-x" and int(stair.get("length")) == 5)
	_check("entity_count counts stairs", restored.entity_count() == 2)
	_check("ids stay unique after load", restored.allocate_id() > int(stair.get("id", 0)))


## Does `box`, read the way `StructureBaker.collect_colliders` says it must be
## read, contain `probe`? The reported `size` is measured in the box's OWN
## frame, so the probe is rotated back by the box's yaw before it meets the
## half extents. Comparing world coordinates straight against `size` tests an
## axis-aligned box nobody drew: on a 45 degree wall that phantom is a solid
## slab out over the open deck AND a clear lane straight along the material.
## Every collider a stair or an axis-aligned wall produces reports yaw 0 and is
## unaffected.
func _contains(box: Dictionary, probe: Vector3) -> bool:
	var half := (box["size"] as Vector3) * 0.5
	var local := probe - (box["center"] as Vector3)
	var yaw := float(box.get("yaw_deg", 0.0))
	if not is_zero_approx(yaw):
		## Pure rotation: transpose == inverse.
		local = Basis(Vector3.UP, deg_to_rad(yaw)).transposed() * local
	return absf(local.x) < half.x and absf(local.y) < half.y and absf(local.z) < half.z


func _test_wall_openings_stay_passable() -> void:
	## A wall run with a door cut into it: no collider may block the door's
	## clear span (walking through must be possible), and the solid wall either
	## side of it must still stop the player. This is the passability claim the
	## corridor leg used to make, asked of the primitive that outlived it.
	var plan := StructurePlan.new()
	var wall := plan.add_wall(Vector3(0, 0, 0), "z", 10.0, 3.0)
	(wall["openings"] as Array).append({"type": "door", "offset": 4.0, "width": 1.6, "height": 2.2})
	var blocked_door := false
	var blocked_wall := false
	for box_variant in StructureBaker.collect_colliders(plan):
		var box := box_variant as Dictionary
		## Middle of the door span at chest height, on the wall's own line.
		if _contains(box, Vector3(0.0, 1.2, 4.8)):
			blocked_door = true
		## Solid material a metre short of the cut, same height.
		if _contains(box, Vector3(0.0, 1.2, 3.0)):
			blocked_wall = true
	_check("door span stays passable", not blocked_door)
	_check("the wall either side of the door is still solid", blocked_wall)


func _test_diagonal_passability() -> void:
	## The same containment question asked of a wall that is not axis-aligned,
	## so that the yaw-honouring maths above is itself covered.
	##
	## A "+x+z" wall 8 m long and 0.4 m thick comes back as ONE 8 x 3 x 0.4 box
	## carrying yaw -45. Both probes below sit 3.2 m from that box's centre —
	## one along the box's own +X (the run), one along world +X. Honouring the
	## yaw, the first is deep inside the drawn panel and the second is 2.26 m
	## clear of it. Ignoring the yaw swaps them exactly: the phantom box is only
	## 0.2 m half-thick in world z, so the on-run probe falls out of it and the
	## beside probe falls into it. Either check going the wrong way says the
	## containment maths dropped the yaw.
	var plan := StructurePlan.new()
	plan.add_wall(Vector3.ZERO, "+x+z", 8.0, 3.0, 0.4)
	var colliders := StructureBaker.collect_colliders(plan)
	_check("the diagonal wall reports one collider", colliders.size() == 1)
	if colliders.size() != 1:
		return
	var box := colliders[0] as Dictionary
	_check("the diagonal collider carries its drawn yaw",
			absf(float(box.get("yaw_deg", 0.0)) - -45.0) < 0.001)
	var center := box["center"] as Vector3
	var run := StructurePlan.wall_run("+x+z")
	var on_run := center + run * 3.2
	on_run.y = 1.2
	var beside := center + Vector3(3.2, 0.0, 0.0)
	beside.y = 1.2
	var blocked_run := false
	var blocked_beside := false
	for box_variant in colliders:
		var collider := box_variant as Dictionary
		if _contains(collider, on_run):
			blocked_run = true
		if _contains(collider, beside):
			blocked_beside = true
	_check("diagonal wall is solid along its own run", blocked_run)
	_check("open deck beside the diagonal wall stays passable", not blocked_beside)
