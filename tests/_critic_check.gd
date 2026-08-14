extends Node

## SCRATCH PROBE. My point query says the deck top is 0.092; the test's standing
## capsule with its bottom at 0.088 reports clear. Both cannot be right. Same
## spawn, same offset, both instruments, one run.

const PLAN_PREFIX := "BrickCol_plan_"
var _space: PhysicsDirectSpaceState3D
var _offset := Vector3.ZERO

func _ready() -> void:
	var layout := JSON.parse_string(FileAccess.get_file_as_string(
		"res://resources/data/structures/probe_piece_house.json")) as Dictionary
	var boat: Node3D = VesselSpawn.instantiate("hull_28x10", layout, "fishing_vessel")
	add_child(boat)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var walk := boat.call("get_walk_deck") as CollisionObject3D
	_space = walk.get_world_3d().direct_space_state
	var boxes := StructureBaker.collect_colliders(StructurePlan.from_dict(layout))
	var rid := walk.get_rid()
	for i in PhysicsServer3D.body_get_shape_count(rid):
		var o: Node = walk.shape_owner_get_owner(walk.shape_find_owner(i)) as Node
		if o == null or not str(o.name).begins_with(PLAN_PREFIX):
			continue
		var idx := int(str(o.name).substr(PLAN_PREFIX.length()))
		if idx < 0 or idx >= boxes.size():
			continue
		_offset = (walk.global_transform * PhysicsServer3D.body_get_shape_transform(rid, i)).origin \
			- ((boxes[idx] as Dictionary)["center"] as Vector3)
		break
	var x := 5.0
	var z := 21.0
	print("offset %v" % _offset)
	for y in [0.080, 0.085, 0.088, 0.090, 0.092, 0.095, 0.100]:
		print("  point at plan y %.3f: %s" % [y, "SOLID" if _point(Vector3(x, y, z)) else "free"])
	## The test's own capsule, bottom at floor_y + STAND_EPS.
	for bottom in [0.058, 0.070, 0.088, 0.092, 0.100, 0.120]:
		var shape := CapsuleShape3D.new()
		shape.radius = 0.35
		shape.height = 1.8
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = shape
		q.collide_with_bodies = true
		q.collide_with_areas = false
		q.collision_mask = 0xFFFFFFFF
		q.transform = Transform3D(Basis.IDENTITY, Vector3(x, bottom + 0.9, z) + _offset)
		var hits := _space.intersect_shape(q, 8)
		print("  1.8 m capsule, feet at plan y %.3f: %d hit(s)%s"
			% [bottom, hits.size(),
			   "" if hits.is_empty() else " — first %s" % str((hits[0].get("collider") as Node).name)])
	## And a THIN probe capsule, to show it is the capsule tip and not the box.
	for bottom in [0.088, 0.092]:
		var shape := CapsuleShape3D.new()
		shape.radius = 0.02
		shape.height = 1.8
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = shape
		q.collide_with_bodies = true
		q.collide_with_areas = false
		q.collision_mask = 0xFFFFFFFF
		q.transform = Transform3D(Basis.IDENTITY, Vector3(x, bottom + 0.9, z) + _offset)
		print("  0.02 m radius capsule, feet at %.3f: %d hit(s)"
			% [bottom, _space.intersect_shape(q, 8).size()])
	boat.queue_free()
	get_tree().quit()

func _point(at: Vector3) -> bool:
	var q := PhysicsPointQueryParameters3D.new()
	q.collide_with_bodies = true
	q.collide_with_areas = false
	q.collision_mask = 0xFFFFFFFF
	q.position = at + _offset
	return not _space.intersect_point(q, 4).is_empty()
