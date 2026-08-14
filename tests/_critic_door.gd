extends Node

## SCRATCH PROBE (leading underscore — not a gate unit).
##
## One table. For a `wall_panel` with a door at every rake the kit accepts:
##
##   drawn head  — what piece_interior_test's `doors_low` measures (plate_point
##                 on the DRAWN opening), against its bar of floor + 1.80 + 0.05
##   physics head — what PhysicsServer3D says, straight up the doorway centre
##   clear width at the three bands the NEW check samples (0.25/0.5/0.75 of the
##                 opening height) and at 0.90, which it does not
##   tallest figure that actually gets through, feet ON the deck
##
## Everything through VesselSpawn -> DeckFitout.apply_plan -> PhysicsServer3D.

const PLAN_PREFIX := "BrickCol_plan_"
const CAPSULE_R := 0.35

var _walk: CollisionObject3D
var _space: PhysicsDirectSpaceState3D
var _offset := Vector3.ZERO


func _ready() -> void:
	print("%-6s %-9s %-9s %-9s | %-7s %-7s %-7s %-7s | %-7s %s"
		% ["rake", "rake_m", "drawn_hd", "phys_hd", "w@.25", "w@.50", "w@.75", "w@.90",
		   "tallest", "verdict vs the 1.8 m figure"])
	for rake in [0, 1, 2, 3, 4, 5, 6, 7, 8, -4, -6, -8]:
		await _case({"span": 4, "height": 5, "rake": rake, "opening": "door"}, rake)
	get_tree().quit()


func _load(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed as Dictionary if parsed is Dictionary else {}


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


func _solid(at: Vector3) -> bool:
	var query := PhysicsPointQueryParameters3D.new()
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.collision_mask = 0xFFFFFFFF
	query.position = at + _offset
	return not _space.intersect_point(query, 1).is_empty()


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


func _v_at_height(corners: PackedVector3Array, u: float, y: float) -> float:
	var lo := 0.0
	var hi := 1.0
	if StructureBaker.plate_point(corners, u, 0.0).y > StructureBaker.plate_point(corners, u, 1.0).y:
		lo = 1.0
		hi = 0.0
	for _i in 24:
		var mid := (lo + hi) * 0.5
		if StructureBaker.plate_point(corners, u, mid).y < y:
			lo = mid
		else:
			hi = mid
	return (lo + hi) * 0.5


## The widest run of free points across the doorway at one band, exactly the way
## piece_interior_test's `_physics_clear_width` does it.
func _clear_at(corners: PackedVector3Array, ref: Vector2, opening: Dictionary, band: float) -> float:
	var off := float(opening["off"])
	var width := float(opening["w"])
	var v := (float(opening["sill"]) + float(opening["h"]) * band) / ref.y
	var best := 0.0
	var run_lo := NAN
	var u := off - 0.10
	while u <= off + width + 0.10:
		if not _solid(StructureBaker.plate_point(corners, clampf(u / ref.x, 0.0, 1.0), v)):
			if is_nan(run_lo):
				run_lo = u
			best = maxf(best, u - run_lo)
		else:
			run_lo = NAN
		u += 0.01
	return best


func _case(params: Dictionary, rake: int) -> void:
	var layout := _load("res://resources/data/structures/probe_piece_house.json")
	layout["pieces"] = [{
		"id": 900, "piece": "wall_panel", "cell": [4, 0, 40], "facing": 90,
		"params": params, "color": "#e3e0d4",
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

	## The deck the wall stands on, to the millimetre.
	var deck := foot.y
	var y := foot.y + 0.40
	while y > foot.y - 0.40:
		if _solid(Vector3(foot.x, y, foot.z)):
			deck = y
			break
		y -= 0.001
	## What `doors_low` measures: the DRAWN head, lowest across the opening.
	var v_head := (float(opening["sill"]) + float(opening["h"])) / ref.y
	var drawn := INF
	for i in 9:
		var uu := lerpf(float(opening["off"]),
			float(opening["off"]) + float(opening["w"]), float(i) / 8.0) / ref.x
		drawn = minf(drawn, StructureBaker.plate_point(corners, uu, v_head).y)
	## What the body says: first solid point straight up the doorway's centre.
	var phys := NAN
	y = deck + 0.005
	while y <= deck + 3.0:
		var v := _v_at_height(corners, u, y)
		if v > 1.0:
			break
		if _solid(StructureBaker.plate_point(corners, u, v)):
			phys = y
			break
		y += 0.002
	## Tallest capsule that marches through, FEET ON THE DECK.
	var normal := StructureBaker.plate_normal(corners)
	var flat := Vector3(normal.x, 0.0, normal.z).normalized()
	var centre := StructureBaker.plate_point(corners, u, 0.5)
	var tallest := 0.0
	var trial := 1.0
	while trial <= 2.6:
		var clear := true
		for i in 46:
			var at := centre + flat * (0.9 - 0.04 * float(i))
			at.y = deck + trial * 0.5
			if not _capsule_free(at, trial):
				clear = false
				break
		if clear:
			tallest = trial
		trial += 0.005
	var bar := deck + 1.8 + 0.05
	print("%-6d %-9.3f %-9.3f %-9.3f | %-7.3f %-7.3f %-7.3f %-7.3f | %-7.3f %s"
		% [rake, rake * 0.125, drawn - deck,
		   (NAN if is_nan(phys) else phys - deck),
		   _clear_at(corners, ref, opening, 0.25), _clear_at(corners, ref, opening, 0.5),
		   _clear_at(corners, ref, opening, 0.75), _clear_at(corners, ref, opening, 0.90),
		   tallest,
		   "%s · doors_low says %s" % [
			   "PASSES" if tallest >= 1.8 else "IMPASSABLE",
			   "ok" if drawn >= bar else "too low",
		   ]])
	boat.queue_free()
	await get_tree().physics_frame
