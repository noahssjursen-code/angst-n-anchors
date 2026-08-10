extends Node

## Lane B. CAN A PLAYER WALK AROUND INSIDE A DECKHOUSE?
##
## Nobody had checked. Plates emit colliders and a punched opening is a genuine
## hole in `plate_panels`, so the shell "should" be solid and a door "should" be
## passable — and "should work" is the claim that has been wrong twice on this
## project already. This test runs the PRODUCTION path — VesselSpawn.instantiate
## -> DeckFitout.apply_plan -> BoatBody.add_walk_brick_collider — and then asks
## PhysicsServer3D, on the real WalkDeck body, by marching a PLAYER-SIZED capsule
## (scenes/shared/player.tscn: radius 0.35, height 1.8) through it.
##
## Four claims, and the last two exist so the first two cannot be satisfied by a
## vessel that emits no colliders at all:
##
##   1. a capsule standing on the open deck walks THROUGH a door opening and
##      ends up inside the deckhouse;
##   2. inside, the FLOOR holds it up — a capsule dropped from 0.5 m above the
##      deck stops with its feet on the deck plane, not through it;
##   3. the shell is SOLID everywhere a door is not. The same sweep that finds
##      the door free finds every other station along the same wall blocked, so
##      "the door is passable" cannot be passing because nothing collides;
##   4. a WINDOW BAND is not a doorway. The window stations are a named subset of
##      (3) and are counted separately, because that is the specific question:
##      the glass band added on 2026-08-10 must not have opened a hole a player
##      can step through.
##
## Three traps, all of which have produced false green on this project before:
##
##  - `cast_motion()` returns a clean 1.0 for a shape that STARTS overlapping
##    something, which reads as "walked straight through" when the truth is
##    "began inside a wall". Never used. Every march steps in explicit MARCH_STEP
##    increments and calls `intersect_shape` at each station, and reports
##    `started_inside` separately. A march that begins stuck is scored VACUOUS —
##    never as a pass — and the count of them is asserted to be zero, so a sweep
##    cannot quietly become a tautology.
##
##  - The floor is NOT a plan collider. It is `WalkHullCollider` / the WalkDeck
##    slab, which BoatBody builds. So these queries are UNFILTERED: they ask what
##    the player's capsule would actually hit, which is the question. The price
##    is that a hull box solid at deck level would block everything and make the
##    sweep meaningless — so the standing height is DERIVED by marching down onto
##    the floor first, and every horizontal march then starts one capsule-height
##    above the surface it found. If that surface were not there, or were above
##    the deck, (2) fails and says so.
##
##  - A wall whose plate is RAKED does not stand over its own foot. Every station
##    is solved for the v parameter at which the plate's own surface reaches the
##    capsule's centre height, so a forward-raked wheelhouse front is met where
##    it actually is rather than where its foot is.
##
## The vessels are the two the owner looked at. Both were rebuilt on the same day
## the window treatment landed, and both carry doors on three sides.

const TestReport := preload("res://tests/support/test_report.gd")

## scenes/shared/player.tscn — the figure every capture is sized against.
const CAPSULE_R := 0.35
const CAPSULE_H := 1.8
## Clearance between the capsule's feet and the floor it stands on. Touching is
## not overlapping, but a query at exactly zero separation is a coin toss.
const STAND_EPS := 0.03

const MARCH_STEP := 0.02   ## << the 0.10 m plate thickness; cannot tunnel a wall
const STATION_STEP := 0.10 ## along a wall
const START_OUT := 0.60    ## how far outside the shell a march begins
const MARCH_LEN := 1.30    ## far enough to end a capsule-radius clear inside
const DROP_FROM := 0.50    ## how far above the deck the floor march begins
const DROP_LEN := 1.00

## A station only counts as "in the clear part of a door" when the whole capsule
## fits between the jambs, with this much to spare.
const JAMB_MARGIN := 0.06
## How many stations to plant across the clear part of each doorway.
const DOOR_STATIONS := 9

const FIXTURES: Array[Dictionary] = [
	{
		"path": "res://resources/data/structures/demo_workboat.json",
		"hull": "hull_28x10",
		"registration": "cargo_vessel",
		## The lower-tier shell. The forward face is NOT swept: it stands over the
		## foredeck where the crane pedestal and the bulwark are, and a sweep that
		## has to skip the stations it cannot start cleanly is a sweep that can
		## hide a failure. It carries no door, so it costs the door claim nothing.
		"walls": [301, 302, 303],
		"tier": [300, 301, 302, 303],
		## Clear of the companionway (x 4.0-5.5, z 9.0-13.0) and of the walls.
		"inside": [[6.5, 11.0], [7.5, 14.0], [2.5, 14.5], [6.0, 15.0]],
	},
	{
		"path": "res://resources/data/structures/probe_trawler_bulwark.json",
		"hull": "hull_28x10",
		"registration": "fishing_vessel",
		"walls": [101, 102, 103],
		"tier": [100, 101, 102, 103],
		"inside": [[5.0, 19.5], [3.5, 22.0], [6.5, 22.0], [5.0, 23.8]],
	},
]

var _t: RefCounted
var _walk: CollisionObject3D
var _space: PhysicsDirectSpaceState3D
var _capsule: CapsuleShape3D
var _query: PhysicsShapeQueryParameters3D
var _offset := Vector3.ZERO
var _boxes: Array = []


func _ready() -> void:
	_t = TestReport.new("plan_interior_test")
	_capsule = CapsuleShape3D.new()
	_capsule.radius = CAPSULE_R
	_capsule.height = CAPSULE_H
	_query = PhysicsShapeQueryParameters3D.new()
	_query.shape = _capsule
	_query.collide_with_bodies = true
	_query.collide_with_areas = false
	_query.collision_mask = 0xFFFFFFFF
	for fixture in FIXTURES:
		await _run_fixture(fixture)
	_t.finish(get_tree())


func _run_fixture(fixture: Dictionary) -> void:
	var stem := str(fixture["path"]).get_file().get_basename()
	print("[%s] ─────────────────────────────────────────────" % stem)
	var layout := _load(str(fixture["path"]))
	if not _t.check("%s: fixture parses as a structure plan" % stem, StructurePlan.is_plan(layout)):
		return
	var plan := StructurePlan.from_dict(layout)
	var boat: Node3D = VesselSpawn.instantiate(
		str(fixture["hull"]), layout, str(fixture["registration"])
	)
	if not _t.check("%s: VesselSpawn.instantiate returned a vessel" % stem, boat != null):
		return
	add_child(boat)
	## One frame for the deferred WalkDeck re-parent and collision enable, one
	## for the physics server to be holding the shapes.
	await get_tree().physics_frame
	await get_tree().physics_frame

	_walk = boat.call("get_walk_deck") as CollisionObject3D
	if not _t.check("%s: the vessel has a WalkDeck body" % stem, _walk != null):
		boat.queue_free()
		return
	_space = _walk.get_world_3d().direct_space_state
	if not _measure_offset(plan, stem):
		boat.queue_free()
		return
	_report_body(stem)

	var floor_y := _check_floor(plan, fixture, stem)
	if not is_nan(floor_y):
		_check_walls(plan, fixture, stem, floor_y)
	_check_controls(stem, floor_y)
	boat.queue_free()
	await get_tree().physics_frame


## A collider's name turned into something a reader can act on: which baked box
## it is, where that box sits in PLAN space, and how big it is.
func _describe(hit_name: String) -> String:
	if not hit_name.begins_with("BrickCol_plan_"):
		return hit_name
	var index := int(hit_name.substr("BrickCol_plan_".length()))
	if index < 0 or index >= _boxes.size():
		return hit_name
	var box := _boxes[index] as Dictionary
	var c: Vector3 = box["center"]
	var h: Vector3 = (box["size"] as Vector3) * 0.5
	return "%s plan centre (%.3f, %.3f, %.3f) half %s yaw %.1f (y %.3f..%.3f)" % [
		hit_name, c.x, c.y, c.z, str(h), float(box["yaw_deg"]), c.y - h.y, c.y + h.y
	]


func _load(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(text)
	return parsed as Dictionary if parsed is Dictionary else {}


# ── Where plan space landed in the world ─────────────────────────────────────

## `DeckFitout.apply_plan` shifts every collider by (-half_beam, deck_y, -half_loa)
## and `add_walk_brick_collider` puts it on the body; rather than restate that
## arithmetic — which is how a test ends up asserting its own copy of the code —
## the offset is MEASURED, by comparing a baked box against the shape the physics
## server is actually holding for it.
func _measure_offset(plan: StructurePlan, stem: String) -> bool:
	var boxes := StructureBaker.collect_colliders(plan)
	_boxes = boxes
	if not _t.check("%s: the plan bakes to collider boxes (%d)" % [stem, boxes.size()],
			boxes.size() > 8):
		return false
	var rid := _walk.get_rid()
	var offsets: Array[Vector3] = []
	for i in PhysicsServer3D.body_get_shape_count(rid):
		var owner: Node = _walk.shape_owner_get_owner(_walk.shape_find_owner(i)) as Node
		if owner == null or not str(owner.name).begins_with("BrickCol_plan_"):
			continue
		var index := int(str(owner.name).substr("BrickCol_plan_".length()))
		if index < 0 or index >= boxes.size():
			continue
		var xf: Transform3D = PhysicsServer3D.body_get_shape_transform(rid, i)
		offsets.append((_walk.global_transform * xf).origin - ((boxes[index] as Dictionary)["center"] as Vector3))
	if not _t.check("%s: the WalkDeck carries the plan's colliders (%d of %d)"
			% [stem, offsets.size(), boxes.size()], offsets.size() == boxes.size()):
		return false
	_offset = offsets[0]
	var spread := 0.0
	for o in offsets:
		spread = maxf(spread, o.distance_to(_offset))
	print("  [space] plan->world offset %s (spread %.6f m)" % [str(_offset), spread])
	return _t.check("%s: all plan shapes share one plan->world offset (spread %.6f m)"
		% [stem, spread], spread < 0.001)


## Not asserted — printed. Which shapes a WalkDeck carries besides the plan's is
## the first thing anyone reading a failure here will want to know.
func _report_body(stem: String) -> void:
	var rid := _walk.get_rid()
	var others := PackedStringArray()
	var plan_shapes := 0
	for i in PhysicsServer3D.body_get_shape_count(rid):
		var owner: Node = _walk.shape_owner_get_owner(_walk.shape_find_owner(i)) as Node
		var owner_name := "" if owner == null else str(owner.name)
		if owner_name.begins_with("BrickCol_plan_"):
			plan_shapes += 1
			continue
		var xf: Transform3D = PhysicsServer3D.body_get_shape_transform(rid, i)
		var data: Variant = PhysicsServer3D.shape_get_data(PhysicsServer3D.body_get_shape(rid, i))
		var top := "?"
		if data is Vector3:
			top = "%.3f" % ((_walk.global_transform * xf).origin.y + (data as Vector3).y - _offset.y)
		others.append("%s top(plan y)=%s" % [owner_name, top])
	print("  [body] %d plan shapes + %d others: %s"
		% [plan_shapes, others.size(), ", ".join(others)])


# ── Marching ─────────────────────────────────────────────────────────────────

## "" when nothing overlaps, otherwise the NAME of a shape that does. The name is
## carried through the march because "blocked at 0.32 m" is not a diagnosis and
## "blocked by BrickCol_plan_412" is: it names the collider, which names the
## baked box, which names the plate.
func _hit(centre: Vector3) -> String:
	_query.transform = Transform3D(Basis.IDENTITY, centre)
	for hit_variant in _space.intersect_shape(_query, 4):
		var hit := hit_variant as Dictionary
		var body := hit.get("collider") as CollisionObject3D
		if body == null:
			return "?"
		if body != _walk:
			return str((body as Node).name)
		var owner: Node = body.shape_owner_get_owner(
			body.shape_find_owner(int(hit.get("shape", -1)))
		) as Node
		return "?" if owner == null else str(owner.name)
	return ""


## Steps a player capsule from `from` along `motion`, asking the physics server
## at every station. Returns {started_inside, blocked, stop_m, hit}.
func _march(from: Vector3, motion: Vector3) -> Dictionary:
	var length := motion.length()
	var steps := maxi(2, int(ceil(length / MARCH_STEP)))
	var out := {"started_inside": false, "blocked": false, "stop_m": length, "hit": ""}
	for i in steps + 1:
		var f := float(i) / float(steps)
		var name := _hit(from + motion * f)
		if name.is_empty():
			continue
		if i == 0:
			out["started_inside"] = true
			out["hit"] = name
			continue
		out["blocked"] = true
		out["stop_m"] = f * length
		out["hit"] = name
		break
	return out


# ── 2. The floor holds a player up ───────────────────────────────────────────
#
# Runs FIRST because everything else needs the height a player stands at, and
# deriving it beats restating it: BoatBody's walk slab, the hull box and the
# plan's own deck plates are three different surfaces and the top one wins.

func _check_floor(_plan: StructurePlan, fixture: Dictionary, stem: String) -> float:
	var stations: Array = fixture["inside"]
	var surfaces: Array[float] = []
	var fell := 0
	var stuck := 0
	for station_variant in stations:
		var station: Array = station_variant
		var here := Vector3(float(station[0]), 0.0, float(station[1]))
		## Feet DROP_FROM above the plan's deck plane, so the capsule centre is a
		## capsule-half higher again.
		var from := here + Vector3(0.0, DROP_FROM + CAPSULE_H * 0.5, 0.0) + _offset
		var drop := _march(from, Vector3.DOWN * DROP_LEN)
		if bool(drop["started_inside"]):
			stuck += 1
			continue
		if not bool(drop["blocked"]):
			fell += 1
			continue
		## Where the capsule's FEET came to rest, in plan y.
		surfaces.append(DROP_FROM - float(drop["stop_m"]))
	print("  [floor] %d stations: %d stood, %d fell through, %d began inside something"
		% [stations.size(), surfaces.size(), fell, stuck])
	_t.equal("%s: no floor probe begins inside a collider" % stem, stuck, 0)
	_t.equal("%s: a player dropped inside the deckhouse lands on a floor (%d/%d fell through)"
		% [stem, fell, stations.size()], fell, 0)
	if surfaces.is_empty():
		_t.check("%s: the deckhouse floor could be measured" % stem, false)
		return NAN
	var lo := surfaces[0]
	var hi := surfaces[0]
	for s in surfaces:
		lo = minf(lo, s)
		hi = maxf(hi, s)
	print("  [floor] surface stands at plan y %.3f..%.3f m" % [lo, hi])
	## The plan builds its deckhouse on y = 0 and puts a person 1.8 m tall in it.
	## A floor half a metre out either way is not a floor a deckhouse can be
	## drawn against, whatever it is holding up.
	_t.check("%s: the floor is the deck plane the plan drew on (plan y %.3f..%.3f m)"
		% [stem, lo, hi], lo > -0.10 and hi < 0.20)
	_t.check("%s: the floor is level across the deckhouse (%.3f m of step)" % [stem, hi - lo],
		hi - lo < 0.10)
	return hi


# ── 1, 3 and 4. Doors pass, everything else stops ────────────────────────────

func _check_walls(plan: StructurePlan, fixture: Dictionary, stem: String, floor_y: float) -> void:
	var centre_y := floor_y + STAND_EPS + CAPSULE_H * 0.5
	var tier := _tier_plates(plan, fixture["tier"] as Array)
	if not _t.check("%s: the fixture supplies a deckhouse tier (%d plates)" % [stem, tier.size()],
			tier.size() >= 3):
		return
	var inside := _tier_centre(tier)
	var doors_free := 0
	var doors_stations := 0
	var doors_blocked := PackedStringArray()
	var solid_stations := 0
	var solid_through := PackedStringArray()
	var window_stations := 0
	var window_through := PackedStringArray()
	var stuck := PackedStringArray()
	var ambiguous := 0

	for wall_id_variant in fixture["walls"] as Array:
		var wall_id := int(wall_id_variant)
		var spec := _plate_props(plan, wall_id)
		if spec.is_empty():
			_t.check("%s: wall %d is in the plan" % [stem, wall_id], false)
			continue
		var corners := StructureBaker.plate_corners(spec)
		var ref := StructureBaker.plate_ref_lengths(corners)
		var normal := _outward(corners, inside)
		var openings := StructureBaker.plate_openings(spec, ref)
		for u_variant in _stations(openings, ref.x):
			var u := float(u_variant)
			var kind := _station_kind(openings, u)
			if kind == "jamb":
				ambiguous += 1
				continue
			var on_wall := _wall_point_at_height(corners, u / ref.x, centre_y)
			var from := on_wall + normal * START_OUT + _offset
			var march := _march(from, -normal * MARCH_LEN)
			var where := "%d@%.2f" % [wall_id, u]
			if bool(march["started_inside"]):
				stuck.append("%s in %s" % [where, march["hit"]])
				continue
			match kind:
				"door":
					doors_stations += 1
					if bool(march["blocked"]):
						doors_blocked.append("%s stopped at %.2f m by %s"
							% [where, march["stop_m"], _describe(str(march["hit"]))])
					else:
						doors_free += 1
				"window":
					window_stations += 1
					solid_stations += 1
					if not bool(march["blocked"]):
						window_through.append(where)
						solid_through.append(where)
				_:
					solid_stations += 1
					if not bool(march["blocked"]):
						solid_through.append(where)

	print("  [walk] doors %d/%d free · shell %d stations, %d walked through · windows %d · jambs %d skipped"
		% [doors_free, doors_stations, solid_stations, solid_through.size(),
		   window_stations, ambiguous])
	if not stuck.is_empty():
		print("  [walk] began inside a collider: %s" % ", ".join(stuck))

	## Not decoration. A run of "began inside" verdicts would hollow every claim
	## below into a tautology, so it is the first thing asserted.
	_t.equal("%s: no wall march begins inside a collider (%d)" % [stem, stuck.size()],
		stuck.size(), 0)
	_t.check("%s: the sweep found door stations to walk through (%d)" % [stem, doors_stations],
		doors_stations >= 6)
	_t.check("%s: a player on the open deck walks through a door into the deckhouse (%d/%d, %s)"
		% [stem, doors_free, doors_stations,
		   "none blocked" if doors_blocked.is_empty() else ", ".join(doors_blocked)],
		doors_free == doors_stations)
	_t.check("%s: the sweep covered the shell densely (%d stations)" % [stem, solid_stations],
		solid_stations >= 100)
	_t.check("%s: the shell is solid everywhere a door is not (%d/%d through, e.g. %s)"
		% [stem, solid_through.size(), solid_stations,
		   "none" if solid_through.is_empty() else solid_through[0]],
		solid_through.is_empty())
	_t.check("%s: the sweep crossed the window bands (%d stations)" % [stem, window_stations],
		window_stations >= 20)
	_t.check("%s: a window band is not a doorway (%d/%d walked through, e.g. %s)"
		% [stem, window_through.size(), window_stations,
		   "none" if window_through.is_empty() else window_through[0]],
		window_through.is_empty())


## Where the sweep stands. A uniform run along the whole wall, PLUS a dense run
## across the clear part of every door — because that clear part is small by
## construction (a 0.85 m door minus a 0.70 m player leaves 0.15 m of lateral
## play) and a uniform sweep coarse enough to be affordable lands one station in
## it, or none. One station is not a sweep.
func _stations(openings: Array, length: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var u := STATION_STEP
	while u < length - STATION_STEP:
		out.append(u)
		u += STATION_STEP
	for opening_variant in openings:
		var opening := opening_variant as Dictionary
		if float(opening["sill"]) > 0.05:
			continue
		var lo := float(opening["off"]) + CAPSULE_R + JAMB_MARGIN
		var hi := float(opening["off"]) + float(opening["w"]) - CAPSULE_R - JAMB_MARGIN
		if hi <= lo:
			continue
		for i in DOOR_STATIONS:
			out.append(lerpf(lo, hi, float(i) / float(DOOR_STATIONS - 1)))
	return out


## Which of {door, jamb, window, blank} a station at `u` metres along the wall
## sits in, judged against the capsule's WIDTH rather than its centre line:
##
##  - `door`  — the whole capsule clears both jambs with JAMB_MARGIN to spare.
##              Must be free.
##  - `jamb`  — the capsule overlaps a doorway but is not clear of its jambs.
##              Neither claim applies: it may legitimately pass or legitimately
##              catch. EXCLUDED from scoring and counted, because guessing here
##              is how a wall-solidity sweep starts reporting failures that are
##              really the sweep's own arithmetic.
##  - `window`— the capsule sits inside a window band's run. Must be blocked; the
##              plate under the sill is what does it.
##  - `blank` — plating. Must be blocked.
func _station_kind(openings: Array, u: float) -> String:
	var kind := "blank"
	for opening_variant in openings:
		var opening := opening_variant as Dictionary
		var off := float(opening["off"])
		var width := float(opening["w"])
		if float(opening["sill"]) > 0.05:
			## A window: only claimed when the capsule is wholly inside its run,
			## so the claim is about the band and not about the plate beside it.
			if u - CAPSULE_R >= off and u + CAPSULE_R <= off + width:
				kind = "window"
			continue
		if u + CAPSULE_R <= off or u - CAPSULE_R >= off + width:
			continue
		if u >= off + CAPSULE_R + JAMB_MARGIN and u <= off + width - CAPSULE_R - JAMB_MARGIN:
			return "door"
		return "jamb"
	return kind


## The point on the plate's own surface, at parameter `u`, whose height is `y`.
## A raked wall does not stand over its foot; bisecting on the plate's bilinear
## patch meets it where it actually is.
func _wall_point_at_height(corners: PackedVector3Array, u: float, y: float) -> Vector3:
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
	return StructureBaker.plate_point(corners, u, (lo + hi) * 0.5)


func _tier_plates(plan: StructurePlan, ids: Array) -> Array:
	var out: Array = []
	for id_variant in ids:
		var spec := _plate_props(plan, int(id_variant))
		if not spec.is_empty():
			out.append(StructureBaker.plate_corners(spec))
	return out


func _plate_props(plan: StructurePlan, item_id: int) -> Dictionary:
	for item_variant in plan.items:
		var item := item_variant as Dictionary
		if int(item.get("id", -1)) != item_id:
			continue
		if StructureBaker.item_primitive(item) != "plate":
			continue
		return StructurePlan.item_props(item)
	return {}


func _tier_centre(tier: Array) -> Vector3:
	var sum := Vector3.ZERO
	var n := 0
	for corners_variant in tier:
		for point in corners_variant as PackedVector3Array:
			sum += point
			n += 1
	return sum / maxf(float(n), 1.0)


## The plate normal that points away from the tier it encloses, flattened to the
## horizontal: a player walks in level, and a raked wall's true normal has a
## vertical component that would march the capsule into the deck or the roof.
func _outward(corners: PackedVector3Array, inside: Vector3) -> Vector3:
	var n := StructureBaker.plate_normal(corners)
	var flat := Vector3(n.x, 0.0, n.z)
	if flat.length() < 0.001:
		flat = Vector3(1.0, 0.0, 0.0)
	flat = flat.normalized()
	var mid := StructureBaker.plate_point(corners, 0.5, 0.5)
	return flat if flat.dot(mid - inside) > 0.0 else -flat


# ── Controls: the march must be able to say both words ───────────────────────

func _check_controls(stem: String, floor_y: float) -> void:
	## Open air well above the rig. Nothing may stop this, or "blocked" anywhere
	## else means nothing.
	var air := _march(Vector3(5.0, 22.0, 14.0) + _offset, Vector3.RIGHT * 3.0)
	_t.check("%s: an open-air march is reported free" % stem,
		not bool(air["blocked"]) and not bool(air["started_inside"]))
	if is_nan(floor_y):
		return
	## ... and a march straight down through the open deck outside the deckhouse
	## must be STOPPED, so "the floor held" is not a verdict this rig hands out
	## for free.
	var over := Vector3(5.0, floor_y + DROP_FROM + CAPSULE_H * 0.5, 3.0) + _offset
	var drop := _march(over, Vector3.DOWN * DROP_LEN)
	_t.check("%s: the open deck also stops a falling capsule (control)" % stem,
		bool(drop["blocked"]) and not bool(drop["started_inside"]))
