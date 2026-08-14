extends Node

## SCRATCH PROBE. Replays piece_interior_test's own sequence for the house —
## spawn, offset over every shape, spawn-and-free the stripped vessel, the
## kneeling floor drop, then the standing headroom capsule — printing the raw
## numbers at each step. My own probe says a 1.8 m capsule with its feet at
## plan y 0.088 hits the WalkDeck at (5, 21); the test says that station is
## clear. One of us is measuring wrong.

const PLAN_PREFIX := "BrickCol_plan_"
const CAPSULE_R := 0.35
const STAND_H := 1.8
const KNEE_H := 0.8
const STAND_EPS := 0.03
const MARCH_STEP := 0.04
const DROP_FROM := 0.60
const DROP_LEN := 1.20

var _walk: CollisionObject3D
var _space: PhysicsDirectSpaceState3D
var _offset := Vector3.ZERO
var _boxes: Array = []

func _ready() -> void:
	var path := "res://resources/data/structures/probe_piece_house.json"
	var layout := JSON.parse_string(FileAccess.get_file_as_string(path)) as Dictionary
	var boat: Node3D = VesselSpawn.instantiate("hull_28x10", layout, "fishing_vessel")
	add_child(boat)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_walk = boat.call("get_walk_deck") as CollisionObject3D
	_space = _walk.get_world_3d().direct_space_state
	_boxes = StructureBaker.collect_colliders(StructurePlan.from_dict(layout))
	var rid := _walk.get_rid()
	var offsets: Array[Vector3] = []
	for i in PhysicsServer3D.body_get_shape_count(rid):
		var o: Node = _walk.shape_owner_get_owner(_walk.shape_find_owner(i)) as Node
		if o == null or not str(o.name).begins_with(PLAN_PREFIX):
			continue
		var idx := int(str(o.name).substr(PLAN_PREFIX.length()))
		if idx < 0 or idx >= _boxes.size():
			continue
		offsets.append((_walk.global_transform
			* PhysicsServer3D.body_get_shape_transform(rid, i)).origin
			- ((_boxes[idx] as Dictionary)["center"] as Vector3))
	_offset = offsets[0]
	print("offset %v over %d shapes" % [_offset, offsets.size()])

	## The stripped spawn the test does before it measures anything.
	var stripped := (JSON.parse_string(FileAccess.get_file_as_string(path)) as Dictionary)
	stripped.erase("pieces")
	var bare: Node3D = VesselSpawn.instantiate("hull_28x10", stripped, "fishing_vessel")
	add_child(bare)
	await get_tree().physics_frame
	await get_tree().physics_frame
	bare.queue_free()
	await get_tree().physics_frame

	## The kneeling drop, exactly as _check_floor does it.
	var query := _figure(KNEE_H)
	var here := Vector3(5.0, 0.0, 21.0)
	var from := here + Vector3(0.0, DROP_FROM + KNEE_H * 0.5, 0.0) + _offset
	var motion := Vector3.DOWN * DROP_LEN
	var steps := maxi(2, int(ceil(DROP_LEN / MARCH_STEP)))
	var stop := DROP_LEN
	for i in steps + 1:
		var at := from + motion * (float(i) / float(steps))
		query.transform = Transform3D(Basis.IDENTITY, at)
		if not _space.intersect_shape(query, 8).is_empty():
			stop = (float(i) / float(steps)) * DROP_LEN
			print("  drop blocked at step %d of %d, stop_m %.4f, capsule feet plan y %.4f"
				% [i, steps, stop, DROP_FROM - stop])
			break
	var floor_y := DROP_FROM - stop
	print("  floor_y as the test computes it: %.4f" % floor_y)

	## The headroom capsule, exactly as _check_headroom does it.
	var stand := _figure(STAND_H)
	var at2 := Vector3(5.0, floor_y + STAND_EPS + STAND_H * 0.5, 21.0) + _offset
	stand.transform = Transform3D(Basis.IDENTITY, at2)
	var hits := _space.intersect_shape(stand, 8)
	print("  headroom capsule centre %v (feet plan y %.4f): %d hit(s)"
		% [at2, floor_y + STAND_EPS, hits.size()])
	for h in hits:
		var body := h.get("collider") as CollisionObject3D
		var o := body.shape_owner_get_owner(body.shape_find_owner(int(h.get("shape", -1)))) as Node
		print("     hit body %s owner %s" % [str((body as Node).name), "?" if o == null else str(o.name)])
	get_tree().quit()

func _figure(height: float) -> PhysicsShapeQueryParameters3D:
	var shape := CapsuleShape3D.new()
	shape.radius = CAPSULE_R
	shape.height = height
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.collide_with_bodies = true
	q.collide_with_areas = false
	q.collision_mask = 0xFFFFFFFF
	return q
