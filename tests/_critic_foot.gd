extends Node

## SCRATCH PROBE (leading underscore — not a gate unit).
##
## piece_interior_test measures the floor by marching a capsule down in 0.04 m
## steps and reports 0.058 on every fixture. The deck plate's real top is 0.095.
## Every march it then plants therefore sits 0.037 m LOWER than a player standing
## on the same deck. This asks what that is worth at a doorway, at the one rake
## where the answer changes.

const PLAN_PREFIX := "BrickCol_plan_"
const CAPSULE_R := 0.35
const STAND_H := 1.8
## piece_interior_test: floor_y (measured 0.058) + STAND_EPS.
const TEST_FEET := 0.058 + 0.03

var _walk: CollisionObject3D
var _space: PhysicsDirectSpaceState3D
var _offset := Vector3.ZERO


func _ready() -> void:
	for rake in [2, 3, 4, 5]:
		await _case(rake)
	get_tree().quit()


func _spawn(layout: Dictionary) -> Node3D:
	var boat: Node3D = VesselSpawn.instantiate("hull_28x10", layout, "fishing_vessel")
	add_child(boat)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_walk = boat.call("get_walk_deck") as CollisionObject3D
	_space = _walk.get_world_3d().direct_space_state
	var plan := StructurePlan.from_dict(layout)
	var boxes := StructureBaker.collect_colliders(plan)
	var rid := _walk.get_rid()
	for i in PhysicsServer3D.body_get_shape_count(rid):
		var owner: Node = _walk.shape_owner_get_owner(_walk.shape_find_owner(i)) as Node
		if owner == null or not str(owner.name).begins_with(PLAN_PREFIX):
			continue
		var index := int(str(owner.name).substr(PLAN_PREFIX.length()))
		if index < 0 or index >= boxes.size():
			continue
		var xf: Transform3D = PhysicsServer3D.body_get_shape_transform(rid, i)
		_offset = (_walk.global_transform * xf).origin \
			- ((boxes[index] as Dictionary)["center"] as Vector3)
		break
	return boat


func _capsule_free(centre: Vector3, height: float) -> bool:
	var shape := CapsuleShape3D.new()
	shape.radius = CAPSULE_R
	shape.height = height
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.collision_mask = 0xFFFFFFFF
	query.transform = Transform3D(Basis.IDENTITY, centre + _offset)
	return _space.intersect_shape(query, 1).is_empty()


func _solid(at: Vector3) -> bool:
	var query := PhysicsPointQueryParameters3D.new()
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.collision_mask = 0xFFFFFFFF
	query.position = at + _offset
	return not _space.intersect_point(query, 1).is_empty()


func _walks(centre: Vector3, flat: Vector3, feet: float) -> bool:
	for i in 46:
		var at := centre + flat * (0.9 - 0.04 * float(i))
		at.y = feet + STAND_H * 0.5
		if not _capsule_free(at, STAND_H):
			return false
	return true


func _case(rake: int) -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(
		"res://resources/data/structures/probe_piece_house.json"))
	var layout := parsed as Dictionary
	layout["pieces"] = [{
		"id": 900, "piece": "wall_panel", "cell": [4, 0, 40], "facing": 90,
		"params": {"span": 4, "height": 5, "rake": rake, "opening": "door"},
		"color": "#e3e0d4",
	}]
	layout["items"] = []
	var boat := await _spawn(layout)
	var plan := StructureBaker.resolved(StructurePlan.from_dict(layout))
	var wall: Dictionary = {}
	for item_variant in plan.items:
		if StructureBaker.item_primitive(item_variant as Dictionary) == "plate":
			wall = item_variant as Dictionary
			break
	var props := StructurePlan.item_props(wall)
	var corners := StructureBaker._transformed(
		StructureBaker.plate_corners(props), plan.item_transform(wall)
	)
	var ref := StructureBaker.plate_ref_lengths(corners)
	var opening := (StructureBaker.plate_openings(props, ref)[0]) as Dictionary
	var u := (float(opening["off"]) + float(opening["w"]) * 0.5) / ref.x
	var foot := StructureBaker.plate_point(corners, u, 0.0)
	var deck := foot.y
	var y := foot.y + 0.40
	while y > foot.y - 0.40:
		if _solid(Vector3(foot.x, y, foot.z)):
			deck = y
			break
		y -= 0.001
	var normal := StructureBaker.plate_normal(corners)
	var flat := Vector3(normal.x, 0.0, normal.z).normalized()
	var centre := StructureBaker.plate_point(corners, u, 0.5)
	var as_test := _walks(centre, flat, TEST_FEET)
	var as_player := _walks(centre, flat, deck + 0.001)
	print("rake %d · deck top %.3f · test plants feet at %.3f (%.3f m below the deck)"
		% [rake, deck, TEST_FEET, deck - TEST_FEET])
	print("   piece_interior_test's own capsule: %s"
		% ["WALKS THROUGH — the check prints PASS" if as_test else "blocked — the check prints FAIL"])
	print("   the same capsule with its feet ON the deck: %s"
		% ["walks through" if as_player else "BLOCKED — the door does not open"])
	boat.queue_free()
	await get_tree().physics_frame
