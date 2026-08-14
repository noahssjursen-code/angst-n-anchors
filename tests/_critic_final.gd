extends Node

## SCRATCH PROBE. Capsule-only, because a player is a capsule and a point query
## sees ~4 mm further into a surface than a capsule does (shape margin), which
## cost me one wrong conclusion already.
##
## For each rake the kit accepts on a wall_panel with a door:
##   1. find the deck top by binary search with the SAME 1.8 m capsule, out on
##      open deck clear of the wall;
##   2. stand that capsule on it and march it through the doorway;
##   3. binary-search the tallest capsule that gets through, feet on that deck.

const PLAN_PREFIX := "BrickCol_plan_"
const CAPSULE_R := 0.35

var _space: PhysicsDirectSpaceState3D
var _offset := Vector3.ZERO

func _ready() -> void:
	print("%-6s %-9s %-9s %-9s %s" % ["rake", "deck_top", "clear_m", "tallest", "the 1.8 m figure"])
	for rake in [0, 2, 3, 4, 5, 6, 8]:
		await _case(rake)
	get_tree().quit()

func _free(centre: Vector3, height: float) -> bool:
	var shape := CapsuleShape3D.new()
	shape.radius = CAPSULE_R
	shape.height = height
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.collide_with_bodies = true
	q.collide_with_areas = false
	q.collision_mask = 0xFFFFFFFF
	q.transform = Transform3D(Basis.IDENTITY, centre + _offset)
	return _space.intersect_shape(q, 1).is_empty()

func _case(rake: int) -> void:
	var layout := JSON.parse_string(FileAccess.get_file_as_string(
		"res://resources/data/structures/probe_piece_house.json")) as Dictionary
	layout["pieces"] = [{
		"id": 900, "piece": "wall_panel", "cell": [4, 0, 40], "facing": 90,
		"params": {"span": 4, "height": 5, "rake": rake, "opening": "door"}, "color": "#e3e0d4",
	}]
	layout["items"] = []
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
	var plan := StructureBaker.resolved(StructurePlan.from_dict(layout))
	var wall: Dictionary = {}
	for item_variant in plan.items:
		if StructureBaker.item_primitive(item_variant as Dictionary) == "plate":
			wall = item_variant as Dictionary
			break
	var props := StructurePlan.item_props(wall)
	var corners := StructureBaker._transformed(
		StructureBaker.plate_corners(props), plan.item_transform(wall))
	var ref := StructureBaker.plate_ref_lengths(corners)
	var opening := (StructureBaker.plate_openings(props, ref)[0]) as Dictionary
	var u := (float(opening["off"]) + float(opening["w"]) * 0.5) / ref.x
	var normal := StructureBaker.plate_normal(corners)
	var flat := Vector3(normal.x, 0.0, normal.z).normalized()
	var centre := StructureBaker.plate_point(corners, u, 0.5)
	## Deck top as a CAPSULE sees it, probed in the doorway itself with a small
	## capsule: the shape margin is the same whatever the size, and the doorway is
	## a hole, so nothing but the deck is under it.
	var foot := StructureBaker.plate_point(corners, u, 0.0)
	var lo := -0.20
	var hi := 0.60
	for _i in 34:
		var mid := (lo + hi) * 0.5
		if _free(Vector3(foot.x, mid + 0.05, foot.z), 0.10):
			hi = mid
		else:
			lo = mid
	var deck := hi
	## Tallest capsule through the doorway, feet on that deck.
	var tallest := 0.0
	var h := 1.0
	while h <= 2.4:
		var ok := true
		for i in 60:
			var at := centre + flat * (1.4 - 0.04 * float(i))
			at.y = deck + h * 0.5
			if not _free(at, h):
				ok = false
				break
		if ok:
			tallest = h
		h += 0.002
	print("%-6d %-9.4f %-9.4f %-9.3f %s"
		% [rake, deck, tallest, tallest,
		   "walks through" if tallest >= 1.8 else "CANNOT GET THROUGH (short by %.3f m)" % (1.8 - tallest)])
	boat.queue_free()
	await get_tree().physics_frame
