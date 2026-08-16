extends Node

## THE SURFACE A PLAYER CAN STAND ON DOES NOT EXTEND PAST THE HULL THE VESSEL
## DRAWS — AND IT DOES COVER IT.
##
## Lane B: this asks `PhysicsServer3D` on a vessel built by `VesselSpawn`, so it
## needs a real space and the autoload identifiers `--script` cannot compile.
##
## ── WHY THIS FILE EXISTS ────────────────────────────────────────────────────
##
## `BoatBody` publishes the player's floor on the `boat_walk` mask as two shapes
## on the `WalkDeck` body: `WalkDeckCollider` (the 0.14 m slab at deck level)
## and `WalkHullCollider` (the hull volume, 85% of depth). Until 2026-08-16 both
## were `hull_size.x` by `hull_size.z` RECTANGLES, on a fleet where eight hulls
## of nine draw a POINTED deck. Measured by driving `scenes/shared/player.tscn`'s
## own capsule (`tests/_walk_bow_body_drive.gd`), a player walked to ship-local
## (4.750, −13.950) on `hull_28x10` — **3.323 m outboard of the drawn deck** —
## and to (15.200, −74.925) on `hull_150x32` — **10.695 m outboard** — standing
## on invisible floor over open sea, then fell off the rectangle's forward face.
## `screenshots/studio/walk_bow__plan.png` is that frame; `walk_bow_fixed__plan`
## is the same walk on the shipped shape.
##
## ── WHERE THE OUTLINE COMES FROM, AND WHY NOT FROM `hull_size` ──────────────
##
## `grid_deck_outline_test`'s note lists the four planforms a hull publishes.
## This file asks the same one that file does — **the polygon in the
## `plate_args.ring` meta on `HullVisual/Deck`, which is literally the array
## `MeshBuilder.plan_plate_mesh` extrudes** — for the same reason: it is the
## surface the player SEES, and it is not a restatement of the thing under test.
##
## Reading it from `hull_size` instead would be the collider checking itself:
## `_walk_deck_box_size` IS `hull_size.x` by `hull_size.z`, so the comparison
## would be a number against a copy of itself and could not fail. That is not a
## worry, it is measured — mutation B below.
##
## Note the fix and this check now share the ring, which is deliberate (REALITY
## §3b, one derivation) and does bound what this file can see: it holds the
## walking surface to the DRAWN DECK, and it cannot see a drawn deck that is
## itself the wrong shape. `grid_deck_outline_test` guards the grid against the
## same ring; nothing guards the ring.
##
## ── TWO CLAIMS, AND THE SECOND IS WHY THE FIRST IS NOT VACUOUS ──────────────
##
##   1. NOTHING OUTSIDE. No sample more than `TOLERANCE_M` outside the drawn
##      ring finds anything on the `boat_walk` mask in a band around the deck
##      plane. The band reaches `PROBE_BELOW_M` down deliberately: the hull box
##      is the SAME rectangle and its top is 0.98 m (trawler) / 2.33 m
##      (freighter) below the slab, so a check that only swept the slab's own
##      millimetres would have reported the defect fixed while a player who
##      stepped off the trimmed slab landed on a second invisible floor one
##      metre lower. Measured with the slab disabled and the box left alone:
##      a capsule dropped 1.945 m outboard came to rest on `WalkHullCollider`.
##   2. EVERYTHING INSIDE. Every sample at least `INSIDE_MARGIN_M` inside the
##      ring MUST find floor AT THE DECK PLANE. Without this, deleting the walk
##      deck — or shipping a slab one centimetre wide — passes claim 1 perfectly.
##
##      "AT THE DECK PLANE" is not decoration, and it was added because the
##      claim without it PASSED its own mutation. Written as "finds anything on
##      the mask", the slab could be disabled outright and every inside sample
##      still found floor — `WalkHullCollider`, 0.98 m lower, answering a
##      question about the deck. A player would have fallen a metre through the
##      weather deck with this file green. See mutation C.
##
## ── MUTATION-VERIFIED, ALL THREE WAYS, 2026-08-16 ───────────────────────────
##
## Baseline, unmutated: **56 checks, 0 FAILED**, 102 055 samples over nine hulls.
##
##   A. `BoatBody._walk_plan_ring` returning empty, which drops BOTH walk shapes
##      back to the `hull_size` boxes they shipped with: **56 checks, 8 FAILED**.
##      Eight hulls of nine fail claim 1 — 250 samples on `hull_28x10` worst
##      **+3.536 m** at ship-local (−5.000, −14.000), 1508 on `hull_150x32`
##      worst **+11.314 m** at (−16.000, −75.000) — every one of them naming
##      `WalkDeckCollider` at +0.070 m off the deck plane. `hull_45x16_cat` is
##      the one that passes, because its bridge deck IS a rectangle: the walk
##      slab was the right shape for exactly one vessel in the fleet.
##      (+3.536 m is the perpendicular distance outside the 45 degree chamfer.
##      The furthest a driven player BODY actually stood is +3.323 m — see
##      `_walk_bow_body_drive` — because a capsule cannot put its centre on the
##      last 0.2 m of a corner.)
##   B. THE BLIND VERSION, and it is the argument for reading the ring. With
##      mutation A still in place, `_deck_ring` replaced by the rectangle
##      `hull_size.x` by `hull_size.z` — the collider's own source — the same
##      run comes back **56 checks, 0 FAILED: GREEN ON THE DEFECT**, on all
##      nine hulls. A check derived from `hull_size` cannot see a slab that is
##      `hull_size`.
##   C. THE SLAB NEVER ENABLED — `_enable_walk_deck_collision` leaving
##      `WalkDeckCollider.disabled = true`, nothing else touched: **56 checks,
##      9 FAILED**, every hull, every inside sample, worst drop 0.980 m
##      (trawler) to 2.330 m (freighter).
##
##      **C PASSED THE FIRST TIME IT WAS RUN, AND THAT IS WHY CLAIM 2 SAYS
##      "AT THE DECK PLANE".** Written as "finds anything on the mask", claim 2
##      was answered by `WalkHullCollider` a metre below — the check would have
##      stayed green while a player fell through the weather deck. A mutation
##      that passes is a finding (REALITY.md §4, standing order 8); this one
##      found a blind claim inside a file written to catch blind claims.

const TestReport := preload("res://tests/support/test_report.gd")
const CaptureSubject := preload("res://tests/support/capture_subject.gd")

## BoatBody.LAYER_BOAT_WALK. Named here rather than reached through the class so
## a mask typo in this file cannot be hidden by the file it is testing.
const LAYER_BOAT_WALK := 4

## Sample step over the hull's bounding rectangle — one deck-grid cell.
const SAMPLE_M := 0.5
## A second, finer pass hugging the OUTSIDE of every ring edge, so a sliver of
## overhang narrower than the lattice cannot slip between samples.
const EDGE_STEP_M := 0.10
const EDGE_OFFSET_M := 0.05

## How far outside the drawn ring a sample has to be before a hit is a defect.
## Argued from a measurement, not tuned: the shipped slab is cut from the ring
## itself, and the only thing that could put floor just outside it is Jolt's own
## convex margin. Measured on all nine hulls (the `mask reaches` number this
## file prints), that margin is **+0.000 m** — the mask does not reach past the
## ring anywhere in the fleet. So this is float grace on a polygon with 16 m
## edges, and it must stay UNDER `EDGE_OFFSET_M` or the fine edge pass below
## contributes no graded samples at all.
const TOLERANCE_M := 0.02
## How far INSIDE the ring a sample has to be before missing floor is a defect.
## Half the player capsule's width (0.35 m) plus the tolerance: a sample nearer
## the edge than that is under a figure that is half over the side anyway.
const INSIDE_MARGIN_M := 0.40

## How far below the WalkDeck body's origin a hit may be and still count as the
## DECK's floor. The slab's own top is 0.07 m above that origin and the hull box
## below it is 0.98 m (trawler) to 2.33 m (freighter) down, so this separates
## them by an order of magnitude at the tightest hull in the fleet.
const DECK_FLOOR_DROP_M := 0.25

## The ray band around the deck plane, relative to the WalkDeck body's origin.
const PROBE_ABOVE_M := 2.0
## Deep enough to reach `WalkHullCollider`'s top on the deepest hull in the
## fleet (`hull_150x32`, 2.33 m below the slab). Measured, not guessed: the box
## top is `0.85 * depth − deck_y`, so it moves with the hull.
const PROBE_BELOW_M := 4.0

var _t


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_t = TestReport.new("walk_deck_outline_test")

	var hull_ids := PackedStringArray()
	for entry in HullRegistry.catalog():
		hull_ids.append(str(entry.get("id", "")))
	_t.check("the fleet has hulls to test (%d)" % hull_ids.size(), hull_ids.size() >= 6)

	var total_samples := 0
	for hull_id in hull_ids:
		total_samples += await _test_hull(hull_id)

	## A run that probed nothing must not report green.
	_t.check(
		"the fleet was probed at %d points (>= 50 000)" % total_samples,
		total_samples >= 50000,
	)
	_t.finish(get_tree())


func _test_hull(hull_id: String) -> int:
	## The PRODUCTION path, and a BARE hull: `VesselSpawn.default_brick_layout`
	## is "bare deck — humans place every brick", so this is the vessel a player
	## has the moment they buy one, before any bulwark exists to fence them in.
	var boat: Node3D = VesselSpawn.instantiate(hull_id, {}, "")
	if not _t.check("%s: the hull spawns" % hull_id, boat != null):
		return 0
	add_child(boat)
	CaptureSubject.hold_still(boat)
	boat.position = Vector3.ZERO
	for i in range(10):
		await get_tree().physics_frame

	var walk := _walk_deck(boat)
	var ring := _deck_ring(boat)
	var hull_size: Vector3 = boat.get("hull_size")
	## `_t` is untyped (`TestReport` registers no global identifier), so
	## `check`'s bool return has no inferable type — say it here.
	var ok: bool = _t.check(
		"%s: the vessel publishes a WalkDeck body" % hull_id, walk != null
	)
	var ring_ok: bool = _t.check(
		"%s: the hull draws a weather deck with a plan ring (%d points)"
			% [hull_id, ring.size()],
		ring.size() >= 3,
	)
	ok = ok and ring_ok
	if not ok:
		_free(boat, walk)
		await get_tree().process_frame
		return 0

	var datum := (walk as Node3D).global_position.y
	var space := get_viewport().world_3d.direct_space_state

	var outside_hits := 0
	## The furthest outside the ring that anything on the mask is STILL found,
	## tolerance ignored. This is what sets `TOLERANCE_M` honestly: it is the
	## convex margin plus float residue when the shape is right, and metres when
	## it is not. Printed, never asserted — a number that sets a constant must
	## not also be graded by it.
	var reach := 0.0
	var worst_outside := 0.0
	var worst_at := Vector2.ZERO
	var worst_y := 0.0
	var worst_shape := ""
	var inside_misses := 0
	var first_miss := Vector2.ZERO
	var worst_drop := 0.0
	var inside_samples := 0
	var outside_samples := 0
	var samples := 0

	for point in _sample_points(ring, hull_size):
		samples += 1
		var outside := _outside_by(ring, point)
		var hit := _floor_at(space, point, datum)
		if outside > 0.0 and not hit.is_empty():
			reach = maxf(reach, outside)
		if outside > TOLERANCE_M:
			outside_samples += 1
			if not hit.is_empty():
				outside_hits += 1
				if outside > worst_outside:
					worst_outside = outside
					worst_at = point
					worst_y = (hit["position"] as Vector3).y - datum
					worst_shape = _shape_name(hit)
		elif outside <= 0.0 and _inside_by(ring, point) >= INSIDE_MARGIN_M:
			inside_samples += 1
			var drop := 1e18
			if not hit.is_empty():
				drop = datum - (hit["position"] as Vector3).y
			if drop > DECK_FLOOR_DROP_M:
				if inside_misses == 0:
					first_miss = point
				inside_misses += 1
				if drop < 1e17:
					worst_drop = maxf(worst_drop, drop)

	print(
		"  [walk] %-15s %6d samples · %5d outside / %5d inside · outside hits %d"
			% [hull_id, samples, outside_samples, inside_samples, outside_hits]
		+ " (worst %+.3f m at (%+.3f, %+.3f), %+.3f m off the deck plane, %s)"
			% [worst_outside, worst_at.x, worst_at.y, worst_y,
				worst_shape if not worst_shape.is_empty() else "-"]
		+ " · inside without deck floor %d (worst drop %.3f m)" % [inside_misses, worst_drop]
		+ " · mask reaches %+.3f m past the ring" % reach
	)

	## Both hull families must actually contribute samples of both kinds, or a
	## per-hull claim can pass by having nothing to check.
	_t.check(
		"%s: the probe found %d points inside the drawn deck to stand on"
			% [hull_id, inside_samples],
		inside_samples >= 100,
	)
	_t.check(
		(
			"%s: nothing on the boat_walk mask stands outside the deck the hull"
			+ " draws (%d of %d outside samples found floor, worst %+.3f m out at"
			+ " ship-local (%+.3f, %+.3f) on %s, allowed %.3f)"
		) % [
			hull_id, outside_hits, outside_samples, worst_outside,
			worst_at.x, worst_at.y,
			worst_shape if not worst_shape.is_empty() else "-", TOLERANCE_M,
		],
		outside_hits == 0,
	)
	_t.check(
		(
			"%s: every one of the %d samples at least %.2f m inside the drawn deck"
			+ " has floor under it AT THE DECK PLANE (%d without, first at"
			+ " (%+.3f, %+.3f), worst drop %.3f m, allowed %.2f)"
		) % [
			hull_id, inside_samples, INSIDE_MARGIN_M, inside_misses,
			first_miss.x, first_miss.y, worst_drop, DECK_FLOOR_DROP_M,
		],
		inside_misses == 0,
	)

	_free(boat, walk)
	await get_tree().process_frame
	return samples


## A downward ray on the player's own mask, through a band around the deck
## plane. `collide_with_areas` is off: an Area3D is not floor.
func _floor_at(
	space: PhysicsDirectSpaceState3D, point: Vector2, datum: float
) -> Dictionary:
	var from := Vector3(point.x, datum + PROBE_ABOVE_M, point.y)
	var to := Vector3(point.x, datum - PROBE_BELOW_M, point.y)
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = LAYER_BOAT_WALK
	query.collide_with_areas = false
	return space.intersect_ray(query)


func _shape_name(hit: Dictionary) -> String:
	var collider: Object = hit.get("collider")
	if collider is CollisionObject3D:
		var body := collider as CollisionObject3D
		var owner_id := body.shape_find_owner(int(hit.get("shape", 0)))
		var owner_node := body.shape_owner_get_owner(owner_id)
		if owner_node != null:
			return str(owner_node.name)
	return str(collider.name) if collider != null else "?"


## A lattice over the hull's bounding rectangle, plus a fine pass hugging the
## outside of every ring edge.
func _sample_points(ring: PackedVector2Array, hull_size: Vector3) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var half_x := hull_size.x * 0.5
	var half_z := hull_size.z * 0.5
	for p in ring:
		half_x = maxf(half_x, absf(p.x))
		half_z = maxf(half_z, absf(p.y))
	## A margin past the rectangle, so a slab that is LARGER than `hull_size`
	## is still swept rather than falling off the end of the lattice.
	half_x += 1.0
	half_z += 1.0
	var nx := int(ceil(half_x * 2.0 / SAMPLE_M))
	var nz := int(ceil(half_z * 2.0 / SAMPLE_M))
	for ix in range(nx + 1):
		var x := -half_x + float(ix) * SAMPLE_M
		for iz in range(nz + 1):
			out.append(Vector2(x, -half_z + float(iz) * SAMPLE_M))
	for i in range(ring.size()):
		var a := ring[i]
		var b := ring[(i + 1) % ring.size()]
		var edge := b - a
		var length := edge.length()
		if length < 1e-9:
			continue
		var normal := Vector2(edge.y, -edge.x) / length
		## Winding is not assumed: the outward side is the one further from the
		## ring's centroid.
		if normal.dot(a - _centroid(ring)) < 0.0:
			normal = -normal
		var steps := int(ceil(length / EDGE_STEP_M))
		for s in range(steps + 1):
			var along := a + edge * (float(s) / float(steps))
			out.append(along + normal * EDGE_OFFSET_M)
	return out


func _centroid(ring: PackedVector2Array) -> Vector2:
	var sum := Vector2.ZERO
	for p in ring:
		sum += p
	return sum / float(maxi(ring.size(), 1))


## The weather deck's own plan polygon, in SHIP-LOCAL metres — the array the
## drawn mesh was extruded from. See the header for why it is not `hull_size`.
func _deck_ring(boat: Node) -> PackedVector2Array:
	var mi := boat.get_node_or_null("HullVisual/Deck") as MeshInstance3D
	if mi == null or not mi.has_meta("plate_args"):
		return PackedVector2Array()
	var args: Dictionary = mi.get_meta("plate_args")
	var raw: PackedVector2Array = args.get("ring", PackedVector2Array())
	var shift := Vector2(mi.position.x, mi.position.z)
	var out := PackedVector2Array()
	for point in raw:
		out.append(point + shift)
	return out


func _walk_deck(boat: Node) -> Node:
	var parent := boat.get_parent()
	var walk: Node = null
	if parent != null:
		walk = parent.get_node_or_null("WalkDeck")
	if walk == null:
		walk = boat.get_node_or_null("WalkDeck")
	return walk


func _free(boat: Node, walk: Node) -> void:
	if boat != null and is_instance_valid(boat):
		remove_child(boat)
		boat.queue_free()
	if walk != null and is_instance_valid(walk) and walk.get_parent() != null:
		walk.get_parent().remove_child(walk)
		walk.queue_free()


## How far outside the ring the point is, in metres; 0.0 when it is inside.
## The fleet's rings are convex, so the distance to the outside of the nearest
## violated edge is the excursion. Winding is taken from the ring itself.
func _outside_by(ring: PackedVector2Array, point: Vector2) -> float:
	return maxf(-_signed_clearance(ring, point), 0.0)


## How far INSIDE the ring the point is; 0.0 when it is outside.
func _inside_by(ring: PackedVector2Array, point: Vector2) -> float:
	return maxf(_signed_clearance(ring, point), 0.0)


func _signed_clearance(ring: PackedVector2Array, point: Vector2) -> float:
	var n := ring.size()
	if n < 3:
		return 0.0
	var area := 0.0
	for i in range(n):
		var a := ring[i]
		var b := ring[(i + 1) % n]
		area += a.x * b.y - b.x * a.y
	var sign := 1.0 if area >= 0.0 else -1.0
	var worst := 1e18
	for i in range(n):
		var a := ring[i]
		var b := ring[(i + 1) % n]
		var edge := b - a
		var length := edge.length()
		if length < 1e-9:
			continue
		## Positive when the point is on the INSIDE of this edge.
		worst = minf(
			worst,
			(edge.x * (point.y - a.y) - edge.y * (point.x - a.x)) * sign / length,
		)
	return worst
