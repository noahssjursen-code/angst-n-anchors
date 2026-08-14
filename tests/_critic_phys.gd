extends Node

## SCRATCH PROBE (leading underscore — not a gate unit).
##
## Two questions piece_interior_test does not ask, both through the production
## path VesselSpawn -> DeckFitout.apply_plan -> PhysicsServer3D.
##
##  A. INTERIORS. Are the four `inside` stations of each shipped fixture
##     actually ENCLOSED — is there a ceiling over them, walls round them — and
##     how much standing room does a piece-built deckhouse really leave? The
##     headroom check plants a 1.8 m capsule and asserts nothing overlaps it;
##     under open sky that check cannot fail.
##
##  B. COMBINATIONS NOBODY SHIPPED. The three fixtures carry doors at span 3,
##     height 5, rake -1..+2 only. The kit ACCEPTS span 3..8 x height 2..6 x
##     rake -8..8 x head 0..7 x fall -4..4 with a door. Build the ones the
##     constraint does not refuse and measure the doorway on a real body.

const PLAN_PREFIX := "BrickCol_plan_"
const CAPSULE_R := 0.35
const STAND_H := 1.8

const FIXTURES: Array[Dictionary] = [
	{
		"path": "res://resources/data/structures/probe_piece_house.json",
		"inside": [[5.0, 21.0], [3.6, 19.0], [6.4, 23.0], [5.0, 24.2]],
	},
	{
		"path": "res://resources/data/structures/probe_piece_trawler.json",
		"inside": [[5.0, 21.0], [3.6, 19.0], [6.4, 23.0], [5.0, 24.2]],
	},
	{
		"path": "res://resources/data/structures/probe_piece_tug.json",
		"inside": [[5.0, 12.0], [3.6, 10.5], [6.4, 14.5], [5.0, 15.2]],
	},
]

## Every one of these is on the kit's declared value sets and is REFUSED BY
## NOTHING. `_is` says what the kit thinks it built.
const CASES: Array[Dictionary] = [
	{"params": {"span": 4, "height": 5, "rake": 3, "opening": "door"}, "_is": "rake 3 (0.375 m)"},
	{"params": {"span": 4, "height": 5, "rake": 4, "opening": "door"}, "_is": "rake 4 (0.500 m)"},
	{"params": {"span": 4, "height": 5, "rake": 5, "opening": "door"}, "_is": "rake 5 (0.625 m)"},
	{"params": {"span": 4, "height": 5, "rake": 6, "opening": "door"}, "_is": "rake 6 (0.750 m)"},
	{"params": {"span": 4, "height": 5, "rake": -6, "opening": "door"}, "_is": "rake -6 (tumblehome)"},
	{"params": {"span": 8, "height": 6, "rake": 6, "opening": "door"}, "_is": "span 8, height 6, rake 6"},
	{"params": {"span": 4, "height": 5, "rake": 0, "fall": 4, "opening": "door"}, "_is": "plumb, fall 4"},
]

var _walk: CollisionObject3D
var _space: PhysicsDirectSpaceState3D
var _offset := Vector3.ZERO


func _ready() -> void:
	if OS.get_environment("CRITIC_SKIP_INTERIOR") == "":
		for fixture in FIXTURES:
			await _interior(fixture)
	for case in CASES:
		await _door_case(case)
	get_tree().quit()


func _load(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	return parsed as Dictionary if parsed is Dictionary else {}


func _spawn(layout: Dictionary) -> Node3D:
	var boat: Node3D = VesselSpawn.instantiate("hull_28x10", layout, "fishing_vessel")
	if boat == null:
		return null
	add_child(boat)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_walk = boat.call("get_walk_deck") as CollisionObject3D
	if _walk == null:
		return boat
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
		_offset = (_walk.global_transform * xf).origin - ((boxes[index] as Dictionary)["center"] as Vector3)
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


## Plan y of the first solid point above `from`, scanning to `to`.
func _first_solid_above(x: float, z: float, from: float, to: float) -> float:
	var y := from
	while y <= to:
		if _solid(Vector3(x, y, z)):
			return y
		y += 0.01
	return NAN


func _first_solid_below(x: float, z: float, from: float, to: float) -> float:
	var y := from
	while y >= to:
		if _solid(Vector3(x, y, z)):
			return y
		y -= 0.01
	return NAN


func _interior(fixture: Dictionary) -> void:
	var stem := str(fixture["path"]).get_file().get_basename()
	var layout := _load(str(fixture["path"]))
	var boat := await _spawn(layout)
	if _walk == null:
		print("[%s] NO WALK DECK" % stem)
		return
	print("\n[%s] interior stations" % stem)
	for station_variant in fixture["inside"] as Array:
		var s: Array = station_variant
		var x := float(s[0])
		var z := float(s[1])
		var floor_y := _first_solid_below(x, z, 0.30, -1.0)
		var base := (0.0 if is_nan(floor_y) else floor_y) + 0.06
		var ceil_y := _first_solid_above(x, z, base, 8.0)
		## Tallest standing capsule whose FEET are on the floor.
		var tallest := 0.0
		var h := 0.4
		while h <= 3.0:
			if _capsule_free(Vector3(x, base + h * 0.5, z), h):
				tallest = h
			h += 0.02
		## Horizontal enclosure at chest height.
		var walls := 0
		var dists := PackedStringArray()
		for k in 8:
			var a := TAU * float(k) / 8.0
			var dir := Vector3(cos(a), 0.0, sin(a))
			var d := 0.05
			var hit := -1.0
			while d <= 12.0:
				if _solid(Vector3(x, base + 1.0, z) + dir * d):
					hit = d
					break
				d += 0.05
			if hit > 0.0 and hit < 6.0:
				walls += 1
			dists.append("%.2f" % hit)
		print("  (%.1f, %.1f) floor %s · ceiling %s · standing column %.2f m · %d/8 rays hit within 6 m [%s]"
			% [x, z,
			   "none" if is_nan(floor_y) else "%.3f" % floor_y,
			   "OPEN SKY" if is_nan(ceil_y) else "%.3f" % ceil_y,
			   tallest, walls, ", ".join(dists)])
	boat.queue_free()
	await get_tree().physics_frame


func _door_case(case: Dictionary) -> void:
	var layout := _load("res://resources/data/structures/probe_piece_house.json")
	var params := (case["params"] as Dictionary).duplicate()
	layout["pieces"] = [{
		"id": 900, "piece": "wall_panel", "cell": [4, 0, 40], "facing": 90,
		"params": params, "color": "#e3e0d4", "_is": "critic probe wall",
	}]
	layout["items"] = []
	var boat := await _spawn(layout)
	if _walk == null:
		print("NO WALK DECK for %s" % str(params))
		return
	var plan := StructurePlan.from_dict(layout)
	var resolved := StructureBaker.resolved(plan)
	var wall: Dictionary = {}
	for item_variant in resolved.items:
		var item := item_variant as Dictionary
		if StructureBaker.item_primitive(item) == "plate":
			wall = item
			break
	if wall.is_empty():
		print("no plate resolved for %s" % str(params))
		boat.queue_free()
		return
	var props := StructurePlan.item_props(wall)
	var corners := StructureBaker._transformed(
		StructureBaker.plate_corners(props), resolved.item_transform(wall)
	)
	var ref := StructureBaker.plate_ref_lengths(corners)
	var openings := StructureBaker.plate_openings(props, ref)
	if openings.is_empty():
		print("no opening for %s" % str(params))
		boat.queue_free()
		return
	var opening := openings[0] as Dictionary
	var off := float(opening["off"])
	var width := float(opening["w"])
	var u := (off + width * 0.5) / ref.x
	var foot := StructureBaker.plate_point(corners, u, 0.0)
	## The DECK the wall stands on, found the way the interior probe finds it:
	## the wall's own foot is buried in the deck plate.
	var deck_top := foot.y
	var probe_y := foot.y + 0.40
	while probe_y > foot.y - 0.40:
		if _solid(Vector3(foot.x, probe_y, foot.z)):
			deck_top = probe_y
			break
		probe_y -= 0.005
	## The clear column IN PHYSICS, straight up the doorway's centre line, in the
	## plate's own mid-plane: the first solid point above the deck.
	var y := deck_top + 0.01
	var head := NAN
	while y <= foot.y + 3.5:
		var v := _v_at_height(corners, u, y)
		if v > 1.0:
			break
		if _solid(StructureBaker.plate_point(corners, u, v)):
			head = y
			break
		y += 0.005
	## Can a 1.8 m figure walk through it? Marched level, from 0.9 m outside to
	## 0.6 m inside, at 0.04 m steps.
	var normal := StructureBaker.plate_normal(corners)
	var flat := Vector3(normal.x, 0.0, normal.z).normalized()
	var centre := StructureBaker.plate_point(corners, u, 0.5)
	var stopped := ""
	var started_inside := false
	for i in 38:
		var at := centre + flat * (0.9 - 0.04 * float(i))
		at.y = deck_top + 0.03 + STAND_H * 0.5
		if not _capsule_free(at, STAND_H):
			if i == 0:
				started_inside = true
			else:
				stopped = "%.2f m out" % (0.9 - 0.04 * float(i))
				break
	## The tallest figure that gets through, to the centimetre.
	var tallest := 0.0
	var trial := 0.6
	while trial <= 2.4:
		var clear := true
		for i in 38:
			var at := centre + flat * (0.9 - 0.04 * float(i))
			at.y = deck_top + 0.03 + trial * 0.5
			if not _capsule_free(at, trial):
				clear = false
				break
		if clear:
			tallest = trial
		trial += 0.01
	print("[case] %-52s -> hole %.2f x %.2f m drawn · physics head %s · 1.8 m figure %s · tallest through %.2f m"
		% [str(case["_is"]), width, float(opening["h"]),
		   "none found" if is_nan(head) else "%.3f m" % (head - deck_top),
		   ("BLOCKED at " + stopped) if not stopped.is_empty()
		    else ("began inside" if started_inside else "WALKS THROUGH"),
		   tallest])
	boat.queue_free()
	await get_tree().physics_frame


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
