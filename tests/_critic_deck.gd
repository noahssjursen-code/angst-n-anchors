extends Node

## SCRATCH PROBE. Where is the deck top, to the millimetre, under the four
## `inside` stations piece_interior_test uses — against the 0.058 m it reports
## as "the floor" and the 0.088 m at which it plants the standing figure's feet.

const PLAN_PREFIX := "BrickCol_plan_"
var _space: PhysicsDirectSpaceState3D
var _offset := Vector3.ZERO

func _ready() -> void:
	for f in [["res://resources/data/structures/probe_piece_house.json", [[5.0,21.0],[3.6,19.0],[6.4,23.0],[5.0,24.2]]],
			["res://resources/data/structures/probe_piece_tug.json", [[5.0,12.0],[3.6,10.5],[6.4,14.5],[5.0,15.2]]]]:
		await _run(str(f[0]), f[1] as Array)
	get_tree().quit()

func _run(path: String, stations: Array) -> void:
	var layout := JSON.parse_string(FileAccess.get_file_as_string(path)) as Dictionary
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
	print("\n%s" % path.get_file())
	for s_v in stations:
		var s: Array = s_v
		var y := 0.400
		var top := NAN
		while y > -0.400:
			var q := PhysicsPointQueryParameters3D.new()
			q.collide_with_bodies = true
			q.collision_mask = 0xFFFFFFFF
			q.position = Vector3(float(s[0]), y, float(s[1])) + _offset
			if not _space.intersect_point(q, 1).is_empty():
				top = y
				break
			y -= 0.001
		print("  (%.1f, %.1f) deck top %.3f · test reports floor 0.058 · plants feet at 0.088 (%+.3f m over the deck)"
			% [float(s[0]), float(s[1]), top, 0.088 - top])
	boat.queue_free()
	await get_tree().physics_frame
