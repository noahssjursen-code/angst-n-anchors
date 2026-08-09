extends Node

## Lane B. Does the PRODUCTION path put the boxes the baker drew into the
## PHYSICS WORLD, rotated?
##
## `plan_collision_test` (lane A) checks the PRODUCER: that
## `StructureBaker.collect_colliders()` emits boxes carrying the right yaw. That
## is not where the walk-through-bulwark bug lived. The bug was in the CONSUMER
## — `DeckFitout.apply_plan` handed `0.0` to `BoatBody.add_walk_brick_collider`
## instead of `box["yaw_deg"]` — and reverting that one argument leaves lane A
## entirely green, because the dictionary it reads is still correct. Measured.
##
## So this test never asks the baker what it meant. It runs
## `VesselSpawn.instantiate` -> `DeckFitout.apply_plan` ->
## `BoatBody.add_walk_brick_collider`, then interrogates PhysicsServer3D about
## the shapes actually attached to the real WalkDeck body:
##
##   1. every plan shape's half-extents and Y rotation, read back out of
##      `PhysicsServer3D.shape_get_data` / `body_get_shape_transform`, match the
##      box the baker emitted, and every shape shares one plan->world offset;
##   2. points inside the DRAWN diagonal panels report SOLID;
##   3. points inside those panels' AXIS-ALIGNED bounding boxes but outside the
##      drawn panel — and outside every other plan collider — report EMPTY. This
##      is the half that proves the shapes are ROTATED rather than merely
##      fattened: a fix that widened the box to swallow the diagonal would pass
##      (2) and fail here;
##   4. a player-sized capsule marched outboard across either bow stem is
##      stopped before it gets out over the water.
##
## Two traps, both of which produced false results in the probe this test grew
## out of, and both of which are defended against here:
##
## - `cast_motion()` returns a clean 1.0 for a shape that STARTS overlapping
##   something. That reads as "walked straight through" when the truth is "began
##   inside a wall". Never used: §4 marches in explicit MARCH_STEP increments
##   and calls `intersect_shape` at every station, and separately reports
##   `started_inside`, which is asserted to be zero so a blocked-at-step-0 march
##   can never be scored as a pass.
##
## - The WalkDeck also carries `WalkHullCollider`, a full-beam axis-aligned box
##   over the whole hull, which is solid over open water outboard of the tapered
##   bow. Every unfiltered point query and every capsule march near the stems
##   hits it, which silently turned the probe's stem sweep into a vacuous check
##   (242/242 stations "started inside solid", so nothing could ever be scored
##   as walking through). Every query here is filtered to shapes whose owning
##   CollisionShape3D is named `BrickCol_plan_*`, i.e. to the colliders
##   `apply_plan` built, and the filter is itself controlled: an open-air march
##   must come back free, and the axis-aligned port bulwark must still block.

const TestReport := preload("res://tests/support/test_report.gd")

const FIXTURE := "res://resources/data/structures/probe_trawler_bow_bulwark.json"
const HULL_ID := "hull_28x10"
const REGISTRATION := "fishing_vessel"
## DeckFitout names its plan colliders "BrickCol_" + "plan_%d", indexed in
## StructureBaker.collect_colliders() order.
const PLAN_PREFIX := "BrickCol_plan_"

## A person, below the cap rail, so it is the BULWARK that has to stop them.
const CAPSULE_RADIUS := 0.3
const CAPSULE_HEIGHT := 0.8
const CAPSULE_Y := 0.55
const MARCH_STEP := 0.02 ## << bulwark thickness 0.2 + 2 * radius; cannot tunnel
const STATION_STEP := 0.05
const STEM_HEAD := Vector3(5.0, 0.0, 0.0) ## bow_taper_m = beam_m * 0.5 = 5
const STEM_FROM := 0.6
const STEM_TO := 6.6
const START_INBOARD := 0.75 ## clear of the bulwark, whose inboard face is 0.3 in
const MARCH_LEN := 1.6

## How far outside the drawn panel a phantom sample has to sit before it counts.
const PANEL_MARGIN := 0.15
## Slack when asking whether some OTHER plan collider legitimately fills a point.
const COVER_MARGIN := 0.05

var _t: RefCounted
var _walk: CollisionObject3D
var _space: PhysicsDirectSpaceState3D
var _plan_shapes: Dictionary = {} ## body shape index -> plan collider index
var _boxes: Array = []
var _offset := Vector3.ZERO


func _ready() -> void:
	_t = TestReport.new("plan_collision_physics_test")
	var layout := _load_layout()
	if not _t.check("fixture parses as a structure plan", StructurePlan.is_plan(layout)):
		_t.finish(get_tree())
		return
	var plan := StructurePlan.from_dict(layout)
	_boxes = StructureBaker.collect_colliders(plan)
	if not _t.check("the plan bakes to collider boxes (%d)" % _boxes.size(), _boxes.size() > 8):
		_t.finish(get_tree())
		return

	var boat: Node3D = VesselSpawn.instantiate(HULL_ID, layout, REGISTRATION)
	if not _t.check("VesselSpawn.instantiate returned a vessel", boat != null):
		_t.finish(get_tree())
		return
	add_child(boat)
	## Two frames: one for the deferred WalkDeck re-parent / collision enable,
	## one for the physics server to have the shapes.
	await get_tree().physics_frame
	await get_tree().physics_frame

	_walk = boat.call("get_walk_deck") as CollisionObject3D
	if not _t.check("the vessel has a WalkDeck body", _walk != null):
		_t.finish(get_tree())
		return
	_space = _walk.get_world_3d().direct_space_state
	_t.check("the WalkDeck is unrotated, so a shape's local yaw is its world yaw",
		_walk.global_transform.basis.is_equal_approx(Basis.IDENTITY))

	if _check_shapes():
		_check_drawn_panels_are_solid()
		_check_no_phantom_outside_the_panels()
		_check_capsule_cannot_cross_a_stem()
		_check_controls()
	_t.finish(get_tree())


func _load_layout() -> Dictionary:
	var text := FileAccess.get_file_as_string(FIXTURE)
	if text.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(text)
	return parsed as Dictionary if parsed is Dictionary else {}


# ── 1. The shapes on the body, as the physics server holds them ──────────────

## Reads every shape off the WalkDeck's body RID via PhysicsServer3D, keeps the
## ones whose owning CollisionShape3D is a plan collider, and compares each
## against the box the baker emitted. Returns false if the set is unusable.
func _check_shapes() -> bool:
	var rid := _walk.get_rid()
	var count := PhysicsServer3D.body_get_shape_count(rid)
	var size_bad := 0
	var yaw_bad := 0
	var type_bad := 0
	var worst_yaw := 0.0
	var worst_yaw_at := -1
	var offsets: Array = []
	var first_size_bad := ""
	for i in count:
		var owner: Node = _walk.shape_owner_get_owner(_walk.shape_find_owner(i)) as Node
		if owner == null:
			continue
		var owner_name := str(owner.name)
		if not owner_name.begins_with(PLAN_PREFIX):
			continue
		var index := int(owner_name.substr(PLAN_PREFIX.length()))
		_plan_shapes[i] = index
		if index < 0 or index >= _boxes.size():
			continue
		var box := _boxes[index] as Dictionary
		var shape_rid := PhysicsServer3D.body_get_shape(rid, i)
		if PhysicsServer3D.shape_get_type(shape_rid) != PhysicsServer3D.SHAPE_BOX:
			type_bad += 1
			continue
		## SHAPE_BOX data is the half-extents.
		var half: Vector3 = PhysicsServer3D.shape_get_data(shape_rid)
		var expected_half := (box["size"] as Vector3) * 0.5
		if not half.is_equal_approx(expected_half):
			size_bad += 1
			if first_size_bad.is_empty():
				first_size_bad = "plan_%d wanted %s got %s" % [index, str(expected_half), str(half)]
			continue
		var xf: Transform3D = PhysicsServer3D.body_get_shape_transform(rid, i)
		var delta := absf(rad_to_deg(angle_difference(
			deg_to_rad(_basis_yaw_deg(xf.basis)), deg_to_rad(float(box["yaw_deg"]))
		)))
		if delta > 0.01:
			yaw_bad += 1
		if delta > worst_yaw:
			worst_yaw = delta
			worst_yaw_at = index
		offsets.append((_walk.global_transform * xf).origin - (box["center"] as Vector3))

	print("[shapes] body has %d shapes, %d of them plan colliders, baker emitted %d boxes"
		% [count, _plan_shapes.size(), _boxes.size()])
	_t.equal("every baked box became a shape on the WalkDeck body",
		_plan_shapes.size(), _boxes.size())
	_t.equal("every plan shape on the physics server is a box", type_bad, 0)
	_t.check("every plan shape's half-extents are the baked size (%d wrong; %s)"
		% [size_bad, "none" if first_size_bad.is_empty() else first_size_bad], size_bad == 0)
	_t.check("every plan shape carries the baked yaw (%d wrong, worst %.4f deg on plan_%d)"
		% [yaw_bad, worst_yaw, worst_yaw_at], yaw_bad == 0)
	if not _t.check("shape transforms were readable", not offsets.is_empty()):
		return false
	_offset = offsets[0] as Vector3
	var spread := 0.0
	for o in offsets:
		spread = maxf(spread, (o as Vector3).distance_to(_offset))
	print("[shapes] plan->world offset %s (spread %.6f m)" % [str(_offset), spread])
	return _t.check("all plan shapes share one plan->world offset (spread %.6f m)" % spread,
		spread < 0.001)


## The Y rotation baked into a basis. A +Y rotation of theta sends +X to
## (cos theta, 0, -sin theta), and basis.x is that transformed axis.
func _basis_yaw_deg(b: Basis) -> float:
	return rad_to_deg(atan2(-b.x.z, b.x.x))


# ── Physics queries, filtered to the colliders apply_plan built ──────────────

## True when a plan collider — not the hull shell, not the deck slab — contains
## the point. `world` is in world space.
func _solid(world: Vector3) -> bool:
	var q := PhysicsPointQueryParameters3D.new()
	q.position = world
	q.collide_with_bodies = true
	q.collide_with_areas = false
	q.collision_mask = 0xFFFFFFFF
	for hit_variant in _space.intersect_point(q, 16):
		var hit := hit_variant as Dictionary
		if hit.get("collider") == _walk and _plan_shapes.has(int(hit.get("shape", -1))):
			return true
	return false


func _capsule_overlaps(centre: Vector3, shape: CapsuleShape3D, q: PhysicsShapeQueryParameters3D) -> bool:
	q.shape = shape
	q.transform = Transform3D(Basis.IDENTITY, centre)
	for hit_variant in _space.intersect_shape(q, 16):
		var hit := hit_variant as Dictionary
		if hit.get("collider") == _walk and _plan_shapes.has(int(hit.get("shape", -1))):
			return true
	return false


## Marches a capsule from `from` along `motion` in MARCH_STEP increments,
## asking the physics server for overlaps at every station.
## Returns {started_inside, blocked, stop_m}.
func _march(from: Vector3, motion: Vector3) -> Dictionary:
	var capsule := CapsuleShape3D.new()
	capsule.radius = CAPSULE_RADIUS
	capsule.height = CAPSULE_HEIGHT
	var q := PhysicsShapeQueryParameters3D.new()
	q.collide_with_bodies = true
	q.collide_with_areas = false
	q.collision_mask = 0xFFFFFFFF
	var length := motion.length()
	var steps := maxi(2, int(ceil(length / MARCH_STEP)))
	var out := {"started_inside": false, "blocked": false, "stop_m": length}
	for i in steps + 1:
		var f := float(i) / float(steps)
		if not _capsule_overlaps(from + motion * f, capsule, q):
			continue
		if i == 0:
			out["started_inside"] = true
			continue
		out["blocked"] = true
		out["stop_m"] = f * length
		break
	return out


# ── 2. Every point of a drawn diagonal panel is solid ────────────────────────

func _diagonals() -> Array:
	var out: Array = []
	for box_variant in _boxes:
		var box := box_variant as Dictionary
		if not is_zero_approx(float(box["yaw_deg"])):
			out.append(box)
	return out


func _check_drawn_panels_are_solid() -> void:
	var diagonals := _diagonals()
	if not _t.check("the fixture supplies diagonal panels to test (%d)" % diagonals.size(),
			diagonals.size() >= 4):
		return
	var total := 0
	var solid := 0
	var first_hole := Vector3.INF
	for box_variant in diagonals:
		var box := box_variant as Dictionary
		var basis := Basis(Vector3.UP, deg_to_rad(float(box["yaw_deg"])))
		var half := (box["size"] as Vector3) * 0.5
		## Lattice in the box's OWN frame, held a centimetre off every face so a
		## sample never lands on a boundary.
		for iu in 40:
			for iv in 3:
				for iw in 3:
					var local := Vector3(
						lerpf(-half.x + 0.01, half.x - 0.01, float(iu) / 39.0),
						lerpf(-half.y + 0.01, half.y - 0.01, float(iv) / 2.0),
						lerpf(-half.z + 0.005, half.z - 0.005, float(iw) / 2.0),
					)
					total += 1
					if _solid((box["center"] as Vector3) + basis * local + _offset):
						solid += 1
					elif first_hole == Vector3.INF:
						first_hole = (box["center"] as Vector3) + basis * local
	print("[drawn] %d/%d sampled points inside the drawn diagonals are solid" % [solid, total])
	_t.check("every sampled point inside a drawn diagonal panel is solid (%d/%d, first hole %s)"
		% [solid, total, "none" if first_hole == Vector3.INF else str(first_hole)], solid == total)


# ── 3. ... and the space its bounding box adds is NOT ────────────────────────

## True when some plan collider (read from the baker, with its true yaw) covers
## the plan-space point. Used only to EXCLUDE samples another wall legitimately
## fills — it is never the assertion.
func _covered_by_a_plan_box(plan_point: Vector3) -> bool:
	for box_variant in _boxes:
		var box := box_variant as Dictionary
		var inv := Basis(Vector3.UP, deg_to_rad(float(box["yaw_deg"]))).transposed()
		var q := (inv * (plan_point - (box["center"] as Vector3))).abs()
		var half := (box["size"] as Vector3) * 0.5
		if q.x < half.x + COVER_MARGIN and q.y < half.y + COVER_MARGIN and q.z < half.z + COVER_MARGIN:
			return true
	return false


func _check_no_phantom_outside_the_panels() -> void:
	var phantom := 0
	var checked := 0
	var phantom_at := Vector3.INF
	for box_variant in _diagonals():
		var box := box_variant as Dictionary
		var basis := Basis(Vector3.UP, deg_to_rad(float(box["yaw_deg"])))
		var half := (box["size"] as Vector3) * 0.5
		## Half-extents of the panel's AXIS-ALIGNED bounding box: exactly the
		## space an un-rotated box of the same `size` would wrongly occupy.
		var extent := basis.x.abs() * half.x + basis.y.abs() * half.y + basis.z.abs() * half.z
		for iu in 21:
			for iw in 21:
				var away := Vector3(
					lerpf(-extent.x, extent.x, float(iu) / 20.0),
					0.0,
					lerpf(-extent.z, extent.z, float(iw) / 20.0),
				)
				## Only points the DRAWN panel does not contain, by a margin ...
				var local := (basis.transposed() * away).abs()
				if local.x < half.x + PANEL_MARGIN and local.z < half.z + PANEL_MARGIN:
					continue
				var plan_point := (box["center"] as Vector3) + away
				## ... and that no other plan collider legitimately fills.
				if _covered_by_a_plan_box(plan_point):
					continue
				checked += 1
				if _solid(plan_point + _offset):
					phantom += 1
					if phantom_at == Vector3.INF:
						phantom_at = plan_point
	print("[phantom] %d/%d sampled points in the diagonals' bounding boxes are wrongly solid"
		% [phantom, checked])
	_t.check("the phantom sweep actually sampled the bounding-box surplus (%d points)" % checked,
		checked > 200)
	_t.check("no point outside a drawn diagonal but inside its bounding box is solid (%d/%d, e.g. %s)"
		% [phantom, checked, "none" if phantom_at == Vector3.INF else str(phantom_at)], phantom == 0)


# ── 4. A person cannot walk out through a stem ───────────────────────────────

func _check_capsule_cannot_cross_a_stem() -> void:
	var stations := 0
	var through := 0
	var started_inside := 0
	var through_at := Vector3.INF
	var deepest := 0.0
	for side in 2:
		## Port stem is the line x + z = 5, starboard x - z = 5; both run aft
		## and inboard from the stem head at (5, 0).
		var along := (Vector3(-1.0, 0.0, 1.0) if side == 0 else Vector3(1.0, 0.0, 1.0)).normalized()
		var outboard := (Vector3(-1.0, 0.0, -1.0) if side == 0 else Vector3(1.0, 0.0, -1.0)).normalized()
		var u := STEM_FROM
		while u <= STEM_TO:
			var on_stem := STEM_HEAD + along * u
			var from := on_stem - outboard * START_INBOARD + Vector3(0.0, CAPSULE_Y, 0.0) + _offset
			var march := _march(from, outboard * MARCH_LEN)
			stations += 1
			if bool(march["started_inside"]):
				started_inside += 1
			elif not bool(march["blocked"]):
				through += 1
				if through_at == Vector3.INF:
					through_at = from - _offset
			else:
				deepest = maxf(deepest, float(march["stop_m"]))
			u += STATION_STEP
	print("[stems] %d stations, %d walked through, %d started inside a plan collider, "
		% [stations, through, started_inside]
		+ "furthest a blocked capsule reached %.3f m of %.2f m" % [deepest, MARCH_LEN])
	_t.check("the stem sweep covered both stems densely (%d stations)" % stations, stations >= 200)
	## Not decoration: a march that begins overlapping proves nothing about
	## walking through, so a run of "started inside" verdicts would hollow the
	## check below out into a tautology.
	_t.equal("no stem march begins inside a plan collider", started_inside, 0)
	_t.check("no player capsule marches out through a bow stem (%d/%d free, first at %s)"
		% [through, stations, "none" if through_at == Vector3.INF else str(through_at)],
		through == 0)


# ── Controls: the filtered march must be able to say "free" and "blocked" ────

func _check_controls() -> void:
	## Open air well above the deck: nothing must stop this, or "blocked"
	## everywhere else means nothing.
	var air := _march(Vector3(5.0, 8.0, 12.0) + _offset, Vector3(1.0, 0.0, 0.0) * 3.0)
	print("[control] open-air march blocked=%s started_inside=%s"
		% [str(air["blocked"]), str(air["started_inside"])])
	_t.check("an open-air march is reported free",
		not bool(air["blocked"]) and not bool(air["started_inside"]))

	## The axis-aligned port bulwark (wall 1, x = 0.2, thickness 0.2) must still
	## stop a capsule — threading yaw through must not have broken yaw 0.
	var straight_stations := 0
	var straight_free := 0
	var z := 7.0
	while z <= 24.0:
		var from := Vector3(1.0, CAPSULE_Y, z) + _offset
		var march := _march(from, Vector3(-1.0, 0.0, 0.0) * 2.0)
		straight_stations += 1
		if not bool(march["blocked"]) and not bool(march["started_inside"]):
			straight_free += 1
		z += 0.25
	_t.check("the axis-aligned port bulwark still stops the capsule (%d/%d free of %d stations)"
		% [straight_free, straight_stations, straight_stations], straight_free == 0)
	_t.check("the straight-wall control ran (%d stations)" % straight_stations,
		straight_stations >= 60)
