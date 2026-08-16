extends Node

## SCRATCH PROBE (leading underscore, not gate-scored). LANE B — needs a .tscn:
##
##   xvfb-run -a --server-args="-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy \
##     res://tests/_wave_walk_probe.tscn
##
## CAN A PERSON GET FROM THE STERN TO THE BOW ON THIS VESSEL?
##
## Not "is the deckhouse too big", which has no right answer, but the question
## underneath it, which does. A 1.8 m capsule — `scenes/shared/player.tscn`, the
## figure CONVENTIONS §3a sizes everything against — is placed on a 0.2 m lattice
## over the whole deck. A cell is STANDABLE when the capsule fits there without
## overlapping anything the vessel carries AND there is deck under its feet. The
## standable cells are then flood-filled 4-connected from the after end, and the
## claim is whether the fill reaches the forward end.
##
## Everything is asked of PhysicsServer3D on the real WalkDeck body of a vessel
## built by `VesselSpawn.instantiate` -> `DeckFitout.apply_plan`, for REALITY §3's
## reason: the walk-through-bulwark bug was in the consumer, not in the baker's
## dictionaries, and reverting it left a test on those dictionaries green.

const TestReport := preload("res://tests/support/test_report.gd")

## scenes/shared/player.tscn.
const CAPSULE_R := 0.35
const STAND_H := 1.8
## ⚠ AND 0.03 m WAS TOO LITTLE, AND THE SYMPTOM WAS THE MIRROR OF THE LAST ONE.
## With the vessel filter fixed, standing the capsule 0.03 m over the PLAN plane
## reported **0 of 4633 cells clear** on all three fixtures while the control was
## correctly blocked: the walk surface itself is a slab with thickness whose top
## sits above plan y = 0, so the capsule's feet were inside the deck. 0.25 m is
## under the player's own 0.45 m step height (`scenes/shared/player.tscn`), so
## nothing it clears is anything a player could not step onto.
const STAND_EPS := 0.25
## 0.2 m: a quarter of the capsule's diameter, so a lane the figure fits down
## cannot fall between two samples.
const STEP := 0.25
## How far under the feet the probe looks for deck. A hull's sheer means the deck
## is not dead level along its length.
const SUPPORT_REACH := 0.45
const PLAN_PREFIX := "BrickCol_plan_"
const NEIGHBOURS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
]

const CASES: Array[Dictionary] = [
	## ⚠ `inside` IS A POINT INSIDE THE WALL PLATING, AND THE FIRST CUT PUT IT IN
	## THE MIDDLE OF THE ROOM. A deckhouse is a hollow shell — that is what a
	## deckhouse is — so a capsule at the centre of the ferry saloon is standing in
	## open interior space and is CORRECTLY not blocked. That control went red on
	## critic_ferry and critic_barge and green on critic_yacht, whose coachroof is
	## narrow enough that the centreline clips a knuckle, and the pattern is the
	## giveaway: it was measuring how wide each house is, not whether the query
	## sees anything. Each point below is inside a wall run read off
	## `tests/_wave_trim_audit.gd`: ferry saloon side 4 x 1.00..1.29, yacht
	## coachroof side 4 x 3.00..3.28, barge casing side 5 x 2.00..2.25.
	{"path": "res://resources/data/structures/critic_ferry.json", "hull": "hull_28x10",
		"inside": [1.15, 14.0]},
	{"path": "res://resources/data/structures/critic_yacht.json", "hull": "hull_28x10",
		"inside": [3.14, 13.0]},
	{"path": "res://resources/data/structures/critic_barge.json", "hull": "hull_28x10",
		"inside": [2.12, 23.0]},
]

var _t: RefCounted
var _walk: CollisionObject3D
var _space: PhysicsDirectSpaceState3D
var _offset := Vector3.ZERO
var _boat: Node3D


func _ready() -> void:
	_t = TestReport.new("wave_walk_probe")
	for case in CASES:
		await _run_case(case)
	_t.finish(get_tree())


func _run_case(case: Dictionary) -> void:
	var path := str(case["path"])
	var stem := path.get_file().get_basename()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		_t.fail("%s: not a plan" % stem)
		return
	var layout := parsed as Dictionary
	var plan := StructurePlan.from_dict(layout)
	var grid := HullRegistry.make_grid(str(case["hull"]))
	var beam := grid.half_beam * 2.0
	var loa := grid.half_loa * 2.0

	var boat: Node3D = VesselSpawn.instantiate(str(case["hull"]), layout, "general_vessel")
	if not _t.check("%s: vessel spawns" % stem, boat != null):
		return
	_boat = boat
	add_child(boat)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_walk = boat.call("get_walk_deck") as CollisionObject3D
	if not _t.check("%s: vessel has a WalkDeck" % stem, _walk != null):
		boat.queue_free()
		return
	_space = _walk.get_world_3d().direct_space_state

	## The plan->world offset, read off the shapes the body is holding rather
	## than recomputed — piece_interior_test's method, same reason.
	var boxes := StructureBaker.collect_colliders(plan)
	var rid := _walk.get_rid()
	var found := false
	for i in PhysicsServer3D.body_get_shape_count(rid):
		var owner: Node = _walk.shape_owner_get_owner(_walk.shape_find_owner(i)) as Node
		if owner == null or not str(owner.name).begins_with(PLAN_PREFIX):
			continue
		var index := int(str(owner.name).substr(PLAN_PREFIX.length()))
		if index < 0 or index >= boxes.size():
			continue
		var xf: Transform3D = PhysicsServer3D.body_get_shape_transform(rid, i)
		_offset = (_walk.global_transform * xf).origin - ((boxes[index] as Dictionary)["center"] as Vector3)
		found = true
		break
	if not _t.check("%s: the plan's shapes are on the body" % stem, found):
		boat.queue_free()
		return

	var capsule := CapsuleShape3D.new()
	capsule.radius = CAPSULE_R
	capsule.height = STAND_H
	var stand := PhysicsShapeQueryParameters3D.new()
	stand.shape = capsule
	stand.collide_with_bodies = true
	stand.collide_with_areas = false

	## THE CONTROL. A point the vessel's own geometry certainly occupies, so a
	## filter that matches nothing cannot report an open deck.
	var inside := case["inside"] as Array
	var blocked_control := _hits_vessel_shape(
		stand,
		Vector3(float(inside[0]), STAND_H * 0.5 + STAND_EPS, float(inside[1])) + _offset
	)
	_t.check(
		"%s: CONTROL — a capsule inside the deckhouse PLATING at plan (%.2f, %.1f) is stopped"
			% [stem, float(inside[0]), float(inside[1])],
		blocked_control,
	)

	var nx := int(floor(beam / STEP)) + 1
	var nz := int(floor(loa / STEP)) + 1
	var standable := {}
	var clear_count := 0
	var supported_count := 0
	for iz in nz:
		if iz % 20 == 0:
			print("    [row] %s z=%.1f m  standable so far %d" % [stem, float(iz) * STEP, standable.size()])
		for ix in nx:
			var here := Vector3(float(ix) * STEP, 0.0, float(iz) * STEP)
			var centre := here + Vector3(0.0, STAND_H * 0.5 + STAND_EPS, 0.0) + _offset
			stand.transform = Transform3D(Basis.IDENTITY, centre)
			if _hits_vessel_shape(stand, centre):
				continue
			clear_count += 1
			if not _supported(here):
				continue
			supported_count += 1
			standable[iz * nx + ix] = true

	## Flood the after 1.0 m of deck forward.
	var reached := {}
	var queue: Array[int] = []
	for iz in range(maxi(0, nz - 6), nz):
		for ix in nx:
			var key := iz * nx + ix
			if standable.has(key) and not reached.has(key):
				reached[key] = true
				queue.append(key)
	var head := 0
	while head < queue.size():
		var key: int = queue[head]
		head += 1
		var ix := key % nx
		var iz := key / nx
		for d_variant in NEIGHBOURS:
			var d := d_variant as Vector2i
			var jx: int = ix + d.x
			var jz: int = iz + d.y
			if jx < 0 or jx >= nx or jz < 0 or jz >= nz:
				continue
			var next: int = jz * nx + jx
			if standable.has(next) and not reached.has(next):
				reached[next] = true
				queue.append(next)

	var bow_reached := 0
	var bow_standable := 0
	for iz in range(0, 6):
		for ix in nx:
			var key := iz * nx + ix
			if standable.has(key):
				bow_standable += 1
				if reached.has(key):
					bow_reached += 1

	## The narrowest fore-aft station the route has to pass, reported so a pass
	## that squeaks through reads differently from a pass with a real side deck.
	var narrowest := 999
	var narrowest_z := -1.0
	for iz in nz:
		var widest := 0
		var run := 0
		for ix in nx:
			if reached.has(iz * nx + ix):
				run += 1
				widest = maxi(widest, run)
			else:
				run = 0
		if widest > 0 and widest < narrowest:
			narrowest = widest
			narrowest_z = float(iz) * STEP
	print("  [walk] %s  standable %d of %d sampled (%d clear of geometry, %d over deck)"
		% [stem, standable.size(), nx * nz, clear_count, supported_count])
	print("  [walk] %s  reached from aft: %d cells; forward band standable %d, reached %d"
		% [stem, reached.size(), bow_standable, bow_reached])
	print("  [walk] %s  narrowest reached lane %.2f m at z = %.1f m"
		% [stem, float(narrowest) * STEP, narrowest_z])

	_t.check(
		"%s: there is standable deck at the bow at all (%d cells)" % [stem, bow_standable],
		bow_standable > 0,
	)
	_t.check(
		"%s: a 1.8 m figure can walk from the stern to the bow (%d of %d forward cells reached)"
			% [stem, bow_reached, bow_standable],
		bow_reached > 0,
	)

	boat.queue_free()
	await get_tree().physics_frame


## THE QUERY IS RESTRICTED TO THE VESSEL, AND THE FIRST CUT WAS NOT.
##
## `intersect_shape` with no filter answers about the whole world, and the world
## here contains the sea: the first run reported **0 of 4633 cells clear on all
## three fixtures**, which is not "the deck is unwalkable", it is "the probe was
## standing in the ocean's collider". A measurement that says every square metre
## of every vessel is blocked is not a finding, it is a broken instrument, and
## REALITY §8's rule applies — suspect the instrument before the subject.
func _hits_vessel_shape(query: PhysicsShapeQueryParameters3D, centre: Vector3) -> bool:
	query.transform = Transform3D(Basis.IDENTITY, centre)
	for hit_variant in _space.intersect_shape(query, 12):
		var body := (hit_variant as Dictionary).get("collider") as Node
		if _is_vessel(body):
			return true
	return false


## ⚠ AND THE FIRST FILTER WAS `body == _boat or _boat.is_ancestor_of(body)`, AND
## IT MATCHED NOTHING. `BoatBody` re-parents its WalkDeck out of itself so the
## walk surface does not inherit the hull's motion, so the body carrying every
## plan collider — every saloon wall, every bulwark — is NOT a descendant of the
## vessel node. The run that followed reported **4633 of 4633 cells clear of
## geometry** on all three fixtures and every check went GREEN, including
## "a 1.8 m figure can walk from the stern to the bow" on a ferry whose saloon
## the capsule was standing straight through. REALITY §4: a check that passes
## first time is a finding. `_control_is_blocked` below exists so that this
## cannot happen quietly again — it plants a capsule in the middle of the
## deckhouse and demands to be stopped.
func _is_vessel(body: Node) -> bool:
	if body == null:
		return false
	return (
		body == _boat or _boat.is_ancestor_of(body)
		or body == _walk or _walk.is_ancestor_of(body)
	)


## Is there deck under this plan point? A point query walked down from the sole.
func _supported(here: Vector3) -> bool:
	var query := PhysicsPointQueryParameters3D.new()
	query.collide_with_bodies = true
	query.collide_with_areas = false
	var y := 0.0
	while y <= SUPPORT_REACH:
		query.position = here + Vector3(0.0, -y, 0.0) + _offset
		for hit_variant in _space.intersect_point(query, 12):
			if _is_vessel((hit_variant as Dictionary).get("collider") as Node):
				return true
		y += 0.05
	return false
