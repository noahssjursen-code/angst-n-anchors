extends Node

## Lane B. IS A PIECE-BUILT DECKHOUSE SOLID AND WALKABLE, THROUGH THE PATH THE
## GAME ACTUALLY RUNS?
##
## The piece kit was built over three waves and wired into nothing. Measured by
## strip test on `probe_piece_house.json` — bake as shipped, bake again with
## every placement deleted — the two were IDENTICAL: 3432 triangles, 38
## colliders either way. 57 placements contributed no geometry and no collision,
## and every green render came from `tests/piece_kit_capture.gd` resolving
## placements into a `user://` copy before building the plan, which is a path
## that existed only in the test rig. `StructureBaker.resolved()` now opens both
## `bake()` and `collect_colliders()`, so the placements reach the baker.
##
## THAT IS A BAKE-LEVEL CLAIM AND THIS FILE DOES NOT REPEAT IT. REALITY.md §3:
## the walk-through-bulwark bug was never in the producer, it was in the CONSUMER
## passing 0.0 where a yaw belonged, and a test asserting on the baker's
## dictionaries left the gate green while the bug shipped. So every claim below
## runs `VesselSpawn.instantiate` -> `DeckFitout.apply_plan` ->
## `BoatBody.add_walk_brick_collider` and then interrogates PhysicsServer3D
## about the shapes on the real WalkDeck body, with real capsule casts.
##
## THE CLAIMS
##
##   0. The placements reach the physics world. The SAME strip test, moved to
##      the production path: spawn the vessel as shipped, spawn it again with
##      `pieces[]` deleted, and count the shapes PhysicsServer3D is holding.
##      This is standing order 3d done at the layer that matters.
##   1. The shell is solid. A player-sized capsule marched inward at every
##      station along every wall plate of the tier is STOPPED BY THAT PLATE.
##   2. The inside is walkable. A capsule dropped inside lands on a floor at the
##      deck plane, and a 1.8 m figure standing on that floor is not inside
##      anything.
##   3. Doors pass, windows do not. A door station is free of EVERYTHING on the
##      vessel; a recessed pane and the plating under a punched window are not.
##   4. What you collide with is what you see. Every corner of every drawn slab
##      of every piece-resolved plate lies inside some collider the baker emits.
##
## FOUR INSTRUMENT DECISIONS, all of which were forced by a false result during
## this file's own construction.
##
##  - A SHELL MARCH IS FILTERED TO THE PLATE UNDER TEST. The claim is "this wall
##    stops a player", so only this wall's colliders are asked. Filtering here
##    makes the claim STRICTER, not looser: another body can only ever stop the
##    capsule sooner. It is also the only way to get a usable answer — measured
##    on `probe_trawler_bulwark`, an unfiltered sweep of the raked front reported
##    50 stations "began inside a collider", and eight of those were the vessel's
##    MAST, a real obstruction standing 0.55 m off the wall on the centreline.
##    An unfiltered sweep cannot tell "the wall is missing" from "something else
##    is in the way", and this one has to.
##
##  - A DOOR MARCH IS NOT FILTERED. "A player walks through this door" is a claim
##    about the whole vessel, so it is asked of the whole vessel.
##
##  - A MARCH STARTS CLEAR OF THE PLATE'S OWN 3D EXTENT, not START_OUT from the
##    plate's surface at the figure's centre height. A RAKED wall does not stand
##    over its foot — `wall_panel`'s whole purpose includes raking up to 1.0 m —
##    so a start point measured from the surface at chest height is still under
##    the overhang at head height. Measured on `probe_trawler_bulwark`'s raked
##    front (0.55 m of overhang): 34 of the 50 stuck stations began inside THE
##    VERY PLATE BEING MARCHED, at heights 1.64..2.20 m. Every station here is
##    pushed out past the furthest point the plate reaches over the figure's own
##    height band, so the start is outside the wall by construction.
##
##  - EVERY PLATE IS SWEPT AT THE HEIGHTS IT OCCUPIES. `wall_glazed` resolves to
##    a coaming, a recessed pane, a header and mullions, and they are separate
##    plate items at separate heights. A standing capsule spans the whole window
##    band, so a sweep that lets the PANE do the stopping proves nothing about
##    the plating — measured on demo_workboat, hollowing a whole side plate left
##    that sweep entirely green. Here a figure is only planted on a plate whose
##    own height range overlaps it, and the kneeling figure — which is what
##    covers the plating course — is asserted to have been planted ONLY on
##    plates that start at the deck.

const TestReport := preload("res://tests/support/test_report.gd")

## scenes/shared/player.tscn — the figure every capture is sized against.
const CAPSULE_R := 0.35
const STAND_H := 1.8
const KNEE_H := 0.8
const STAND_EPS := 0.03

const MARCH_STEP := 0.04   ## << plate thickness 0.1 + 2 * radius; cannot tunnel
const STATION_STEP := 0.20
const START_OUT := 0.55    ## clear of the plate's own extent, not of its surface
const MARCH_LEN := 1.20
const DROP_FROM := 0.60
const DROP_LEN := 1.20
## A capsule centred within a radius of a plate's end legitimately overlaps the
## plate next door, which is a fact about corners and not about the wall. Those
## stations are not planted; the neighbouring plate covers the same metre.
const END_INSET := 0.40
## Runs shorter than this carry no station: a 0.10 m mullion cannot stop a
## 0.70 m capsule on its own, and asking it to would be a check about arithmetic.
const MIN_RUN := 1.00
## A plate has to share this much height with a figure before it is asked to
## stop it.
const BAND_OVERLAP_MIN := 0.15

const DOOR_STATIONS := 7
const COLUMN_SAMPLES := 9
const COLUMN_STEP := 0.01
const DOOR_PLAY_MIN := 0.12
const HEAD_MARGIN := 0.05
## See plan_interior_test: a raked plate's collider is a staircase of cells, so
## every opening is that much narrower in collision than in the drawing.
const JAMB_MARGIN := 0.16
## How much narrower the PHYSICS WORLD is allowed to be than the drawing at a
## doorway. Not a fudge: 0.01 m is the SKIN_EPS the casing laps into the reveal
## at each jamb and 0.01 m is the scan step, so the floor is 0.04 m and the
## measured loss on all five piece-built doorways is exactly that. It is set at
## 0.06 rather than at the measurement so a float does not decide the verdict —
## and it is far under the 0.09 m a casing centred ON the cut edge would cost,
## which is the thing this check exists to catch coming back.
const DOOR_PHYSICS_SLACK := 0.06
const DOOR_SCAN_STEP := 0.01

## Slack on the drawn-vs-collided containment test. Float epsilon and nothing
## more — a hand's breadth of grace would let a collider miss the geometry.
const COVER_SLACK := 1e-4

const PLAN_PREFIX := "BrickCol_plan_"
## The piece ids whose plates are the SHELL of a deckhouse. A deck tile, a trim
## band and a roof slope are floors, rubbing strakes and visors; they are not
## what a player walks into, and a sweep aimed at them would be aimed at the
## wrong claim.
const WALL_PIECES := ["wall_panel", "wall_glazed", "corner_45"]

## `tier` is the plan-space box the deckhouse under test stands in. It is a
## SELECTOR, not a measurement: `probe_piece_house` also carries a free-standing
## three-facet diagonal wall run out on the foredeck and a funnel on the boat
## deck, both built from the same pieces, and a sweep that swallowed them would
## be marching at walls that enclose nothing. Every number below is read off the
## fixture's own resolved geometry (tests/_piece_geom_probe.gd), not chosen.
const FIXTURES: Array[Dictionary] = [
	{
		"path": "res://resources/data/structures/probe_piece_house.json",
		"hull": "hull_28x10",
		"registration": "fishing_vessel",
		"what": "the strict fixture — 58 placements, zero hand-authored plates",
		## Lower tier: x 2.50..7.50, z 17.00..25.25, y 0..2.75.
		"tier": [2.0, 8.0, 16.5, 25.5, -0.2, 2.4],
		"inside": [[5.0, 21.0], [3.6, 19.0], [6.4, 23.0], [5.0, 24.2]],
	},
	{
		"path": "res://resources/data/structures/UNUSED_trawler.json",
		"hull": "hull_28x10",
		"registration": "fishing_vessel",
		"what": "the same deckhouse on a fully dressed trawler — spars, wires, gallows",
		"tier": [2.0, 8.0, 16.5, 25.5, -0.2, 2.4],
		"inside": [[5.0, 21.0], [3.6, 19.0], [6.4, 23.0], [5.0, 24.2]],
	},
	{
		"path": "res://resources/data/structures/UNUSED_tug.json",
		"hull": "hull_28x10",
		"registration": "fishing_vessel",
		"what": "built through the studio's piece tool, 33 placements",
		## Pilot-house casing: x 2.50..7.50, z 8.25..16.00, y 0..2.00.
		"tier": [2.0, 8.0, 8.0, 16.5, -0.2, 1.9],
		"inside": [[5.0, 12.0], [3.6, 10.5], [6.4, 14.5], [5.0, 15.2]],
	},
]

var _t: RefCounted
var _walk: CollisionObject3D
var _space: PhysicsDirectSpaceState3D
var _boxes: Array = []
var _owner_of: Dictionary = {}      ## collider index -> item id (plates only)
var _indices_of: Dictionary = {}    ## item id -> Dictionary of collider indices
var _offset := Vector3.ZERO
## Run-level pane tallies. A per-fixture coverage check is honest but VACUOUS on
## a fixture that carries no glazing in its tier, so the suite states once that
## the pane sweep met glass somewhere. Without this, glazing could stop being
## selected everywhere and every fixture would still report "0 of 0 swept".
var _pane_plates := 0
var _pane_stations := 0


func _ready() -> void:
	_t = TestReport.new("_critic_copy")
	for fixture in FIXTURES:
		await _run_fixture(fixture)
	print("\n[pane] across the run: %d glazed plates swept, %d stations"
		% [_pane_plates, _pane_stations])
	_t.check("the pane sweep met glazing somewhere in the run (%d plates, %d stations)"
		% [_pane_plates, _pane_stations], _pane_plates >= 9 and _pane_stations >= 40)
	_t.finish(get_tree())


func _load(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(text)
	return parsed as Dictionary if parsed is Dictionary else {}


func _run_fixture(fixture: Dictionary) -> void:
	var stem := str(fixture["path"]).get_file().get_basename()
	print("\n[%s] %s" % [stem, str(fixture["what"])])
	var layout := _load(str(fixture["path"]))
	if not _t.check("%s: fixture parses as a structure plan" % stem, StructurePlan.is_plan(layout)):
		return
	var plan := StructurePlan.from_dict(layout)
	if not _t.check("%s: the fixture is piece-built (%d placements)" % [stem, plan.pieces.size()],
			plan.pieces.size() >= 30):
		return

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

	var resolved := StructureBaker.resolved(plan)
	_boxes = StructureBaker.collect_colliders(plan)
	_map_provenance(resolved)
	var carried := _measure_offset(stem)

	await _check_placements_reach_physics(fixture, stem, carried)

	if carried:
		var walls := _tier_walls(resolved, fixture["tier"] as Array)
		var floor_y := _check_floor(fixture, stem)
		if not is_nan(floor_y):
			_check_headroom(fixture, stem, floor_y)
			_check_shell(walls, stem, floor_y)
			_check_openings(walls, stem, floor_y)
		_check_panes(walls, stem)
		_check_drawn_is_collided(resolved, stem)
		_check_controls(stem, floor_y)

	boat.queue_free()
	await get_tree().physics_frame


# ── Provenance: which plate emitted which collider ───────────────────────────
#
# `collect_colliders` appends walls, decks, stairs, items and edges in that
# order, and each entity's boxes come from the same emitter this calls — the
# baker's own, not a second copy of it (REALITY.md §3b). `_item_colliders` is
# spelled with a leading underscore; calling it is deliberate, because
# re-deriving a plate's collider count here is exactly the drift that rule
# exists to forbid.

func _map_provenance(plan: StructurePlan) -> void:
	_owner_of = {}
	_indices_of = {}
	var index := 0
	var expanded := StructureBaker.expand(plan)
	for entity_variant in expanded["walls"] as Array:
		index += StructureBaker.wall_boxes(entity_variant as Dictionary).size()
	for entity_variant in expanded["decks"] as Array:
		index += StructureBaker.deck_boxes(entity_variant as Dictionary).size()
	for entity_variant in expanded["stairs"] as Array:
		index += StructureBaker.stair_boxes(entity_variant as Dictionary).size()
	for item_variant in plan.items:
		var item := item_variant as Dictionary
		var id := int(item.get("id", -1))
		var count: int = StructureBaker._item_colliders(plan, item, Vector3.ZERO).size()
		var set: Dictionary = {}
		for _i in count:
			_owner_of[index] = id
			set[index] = true
			index += 1
		if not set.is_empty():
			_indices_of[id] = set


## Every wall plate of the tier, as {id, name, corners (plan space), props,
## y_lo, y_hi, run}. Selected on the PIECE the plate came from and on where it
## stands, never on an id: an id is an address and an address is allowed to
## move (REALITY.md §4b).
func _tier_walls(plan: StructurePlan, tier: Array) -> Array:
	var out: Array = []
	for item_variant in plan.items:
		var item := item_variant as Dictionary
		if StructureBaker.item_primitive(item) != "plate":
			continue
		var props := StructurePlan.item_props(item)
		var piece := str(props.get("__piece", ""))
		var kind := piece.split(" ")[0]
		if not WALL_PIECES.has(kind):
			continue
		var corners := StructureBaker._transformed(
			StructureBaker.plate_corners(props), plan.item_transform(item)
		)
		if corners.size() != 4:
			continue
		var lo := corners[0]
		var hi := corners[0]
		for c in corners:
			lo = Vector3(minf(lo.x, c.x), minf(lo.y, c.y), minf(lo.z, c.z))
			hi = Vector3(maxf(hi.x, c.x), maxf(hi.y, c.y), maxf(hi.z, c.z))
		var mid := (lo + hi) * 0.5
		if mid.x < float(tier[0]) or mid.x > float(tier[1]):
			continue
		if mid.z < float(tier[2]) or mid.z > float(tier[3]):
			continue
		if mid.y < float(tier[4]) or mid.y > float(tier[5]):
			continue
		out.append({
			"id": int(item.get("id", -1)),
			"kind": kind,
			"name": piece.substr(0, 56),
			"corners": corners,
			"props": props,
			"y_lo": lo.y,
			"y_hi": hi.y,
			"ref": StructureBaker.plate_ref_lengths(corners),
		})
	return out


# ── 0. The placements reach the physics world ────────────────────────────────

func _measure_offset(stem: String) -> bool:
	if not _t.check("%s: the plan bakes to collider boxes (%d)" % [stem, _boxes.size()],
			_boxes.size() > 40):
		return false
	var rid := _walk.get_rid()
	var offsets: Array[Vector3] = []
	for i in PhysicsServer3D.body_get_shape_count(rid):
		var owner: Node = _walk.shape_owner_get_owner(_walk.shape_find_owner(i)) as Node
		if owner == null or not str(owner.name).begins_with(PLAN_PREFIX):
			continue
		var index := int(str(owner.name).substr(PLAN_PREFIX.length()))
		if index < 0 or index >= _boxes.size():
			continue
		var xf: Transform3D = PhysicsServer3D.body_get_shape_transform(rid, i)
		offsets.append(
			(_walk.global_transform * xf).origin - ((_boxes[index] as Dictionary)["center"] as Vector3)
		)
	if not _t.check("%s: the WalkDeck carries every baked collider (%d of %d)"
			% [stem, offsets.size(), _boxes.size()], offsets.size() == _boxes.size()):
		return false
	_offset = offsets[0]
	var spread := 0.0
	for o in offsets:
		spread = maxf(spread, o.distance_to(_offset))
	print("  [space] plan->world offset %s (spread %.6f m), %d shapes"
		% [str(_offset), spread, offsets.size()])
	return _t.check("%s: all plan shapes share one plan->world offset (%.6f m)" % [stem, spread],
		spread < 0.001)


## The strip test, moved off the baker and onto the body. Spawn the vessel with
## `pieces[]` deleted and count the shapes the physics server holds. If the two
## counts match, the placements are decoration and everything below is a test of
## the hull.
func _check_placements_reach_physics(fixture: Dictionary, stem: String, carried: bool) -> void:
	var stripped := _load(str(fixture["path"]))
	stripped.erase("pieces")
	var bare: Node3D = VesselSpawn.instantiate(
		str(fixture["hull"]), stripped, str(fixture["registration"])
	)
	if not _t.check("%s: the stripped plan also spawns" % stem, bare != null):
		return
	add_child(bare)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var bare_walk := bare.call("get_walk_deck") as CollisionObject3D
	var bare_shapes := 0
	if bare_walk != null:
		var rid := bare_walk.get_rid()
		for i in PhysicsServer3D.body_get_shape_count(rid):
			var owner: Node = bare_walk.shape_owner_get_owner(bare_walk.shape_find_owner(i)) as Node
			if owner != null and str(owner.name).begins_with(PLAN_PREFIX):
				bare_shapes += 1
	var full_shapes := 0
	if carried:
		full_shapes = _boxes.size()
	else:
		var rid := _walk.get_rid()
		for i in PhysicsServer3D.body_get_shape_count(rid):
			var owner: Node = _walk.shape_owner_get_owner(_walk.shape_find_owner(i)) as Node
			if owner != null and str(owner.name).begins_with(PLAN_PREFIX):
				full_shapes += 1
	print("  [strip] plan shapes on the WalkDeck: as shipped %d, placements deleted %d (+%d)"
		% [full_shapes, bare_shapes, full_shapes - bare_shapes])
	_t.check("%s: deleting pieces[] removes collision from the real body (%d -> %d)"
		% [stem, full_shapes, bare_shapes], full_shapes - bare_shapes >= 100)
	bare.queue_free()
	await get_tree().physics_frame


# ── Physics ──────────────────────────────────────────────────────────────────

## "" when nothing the query cares about overlaps, otherwise the NAME of a shape
## that does. `only` empty means ask the whole vessel; otherwise only the plan
## colliders whose index is a key of `only` count as a hit.
func _hit(centre: Vector3, query: PhysicsShapeQueryParameters3D, only: Dictionary) -> String:
	query.transform = Transform3D(Basis.IDENTITY, centre)
	for hit_variant in _space.intersect_shape(query, 8):
		var hit := hit_variant as Dictionary
		var body := hit.get("collider") as CollisionObject3D
		if body == null:
			continue
		if body != _walk:
			if only.is_empty():
				return str((body as Node).name)
			continue
		var owner: Node = body.shape_owner_get_owner(
			body.shape_find_owner(int(hit.get("shape", -1)))
		) as Node
		var name := "?" if owner == null else str(owner.name)
		if only.is_empty():
			return name
		if not name.begins_with(PLAN_PREFIX):
			continue
		if only.has(int(name.substr(PLAN_PREFIX.length()))):
			return name
	return ""


func _march(from: Vector3, motion: Vector3, query: PhysicsShapeQueryParameters3D,
		only: Dictionary) -> Dictionary:
	var length := motion.length()
	var steps := maxi(2, int(ceil(length / MARCH_STEP)))
	var out := {"started_inside": false, "blocked": false, "stop_m": length, "hit": ""}
	for i in steps + 1:
		var name := _hit(from + motion * (float(i) / float(steps)), query, only)
		if name.is_empty():
			continue
		if i == 0:
			out["started_inside"] = true
			out["hit"] = name
			continue
		out["blocked"] = true
		out["stop_m"] = (float(i) / float(steps)) * length
		out["hit"] = name
		break
	return out


func _figure(height: float) -> PhysicsShapeQueryParameters3D:
	var shape := CapsuleShape3D.new()
	shape.radius = CAPSULE_R
	shape.height = height
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.collision_mask = 0xFFFFFFFF
	return query


# ── 2. The inside is walkable ────────────────────────────────────────────────

## THE DROP IS MADE BY THE KNEELING FIGURE, and that is an instrument decision
## with a measurement behind it (REALITY.md §8 — suspect the camera before the
## subject). The claim here is WHERE THE FLOOR IS, and the capsule's bottom is at
## `DROP_FROM` above the deck whatever height the capsule is, so the answer this
## returns does not depend on the figure at all — measured, the house and the
## trawler report the same 0.058 m either way. What DOES depend on it is whether
## the probe starts clear: a standing figure dropped from 0.60 m has its head at
## 2.40 m, and `probe_piece_tug`'s pilot-house casing is 2.00 m tall with its roof
## slab at 1.93..2.07. All four of its stations began INSIDE that roof, the floor
## could not be measured at all, and the three checks that need a floor — headroom,
## the shell sweep and the doors — were skipped on a whole fixture. The figure was
## standing in the ceiling.
##
## The standing figure is not let off: `_check_headroom` plants a full 1.8 m
## capsule ON the floor this finds and asserts nothing overlaps it, which is the
## claim "a player can stand up in here" stated where it belongs.
func _check_floor(fixture: Dictionary, stem: String) -> float:
	var query := _figure(KNEE_H)
	var surfaces: Array[float] = []
	var fell := 0
	var stuck := 0
	for station_variant in fixture["inside"] as Array:
		var station: Array = station_variant
		var here := Vector3(float(station[0]), 0.0, float(station[1]))
		var from := here + Vector3(0.0, DROP_FROM + KNEE_H * 0.5, 0.0) + _offset
		var drop := _march(from, Vector3.DOWN * DROP_LEN, query, {})
		if bool(drop["started_inside"]):
			stuck += 1
			print("  [floor] (%.1f, %.1f) began inside %s" % [here.x, here.z, str(drop["hit"])])
			continue
		if not bool(drop["blocked"]):
			fell += 1
			continue
		surfaces.append(DROP_FROM - float(drop["stop_m"]))
	print("  [floor] %d stations: %d stood, %d fell through, %d began inside something"
		% [(fixture["inside"] as Array).size(), surfaces.size(), fell, stuck])
	_t.equal("%s: no floor probe inside the deckhouse begins in a collider" % stem, stuck, 0)
	_t.equal("%s: a player dropped inside the deckhouse lands on a floor (%d fell through)"
		% [stem, fell], fell, 0)
	if surfaces.is_empty():
		_t.check("%s: the deckhouse floor could be measured" % stem, false)
		return NAN
	var lo := surfaces[0]
	var hi := surfaces[0]
	for s in surfaces:
		lo = minf(lo, s)
		hi = maxf(hi, s)
	print("  [floor] surface stands at plan y %.3f..%.3f m" % [lo, hi])
	_t.check("%s: the floor is the deck plane the placements stand on (plan y %.3f..%.3f)"
		% [stem, lo, hi], lo > -0.10 and hi < 0.20)
	_t.check("%s: the floor is level across the deckhouse (%.3f m of step)" % [stem, hi - lo],
		hi - lo < 0.10)
	return hi


## A march that begins stuck is VACUOUS, and a deckhouse a 1.8 m figure cannot
## STAND UP IN is not walkable however solid its walls are. Asked of the whole
## vessel, because the thing a player's head hits is not required to be a plate.
func _check_headroom(fixture: Dictionary, stem: String, floor_y: float) -> void:
	var query := _figure(STAND_H)
	var blocked := PackedStringArray()
	for station_variant in fixture["inside"] as Array:
		var station: Array = station_variant
		var at := Vector3(float(station[0]), floor_y + STAND_EPS + STAND_H * 0.5,
			float(station[1])) + _offset
		var name := _hit(at, query, {})
		print("  [CRITIC] station (%.1f, %.1f) floor_y %.4f feet %.4f centre %v -> hit \"%s\" · raw %d"
			% [float(station[0]), float(station[1]), floor_y, floor_y + STAND_EPS, at, name,
			   _raw_hits(at, query)])
		if not name.is_empty():
			blocked.append("(%.1f, %.1f) in %s"
				% [float(station[0]), float(station[1]), _describe(name)])
	print("  [head] %d of %d stations clear for a 1.8 m figure"
		% [(fixture["inside"] as Array).size() - blocked.size(),
		   (fixture["inside"] as Array).size()])
	_t.check("%s: a 1.8 m figure stands inside the deckhouse with headroom (%d obstructed: %s)"
		% [stem, blocked.size(), "none" if blocked.is_empty() else ", ".join(blocked)],
		blocked.is_empty())


# ── 1. The shell is solid ────────────────────────────────────────────────────

func _raw_hits(centre: Vector3, query: PhysicsShapeQueryParameters3D) -> int:
	query.transform = Transform3D(Basis.IDENTITY, centre)
	var hits := _space.intersect_shape(query, 8)
	for h in hits:
		var b := h.get("collider") as CollisionObject3D
		print("     [CRITIC] raw hit body %s (is _walk: %s) shape %d"
			% [str((b as Node).name), str(b == _walk), int(h.get("shape", -1))])
	return hits.size()


func _check_shell(walls: Array, stem: String, floor_y: float) -> void:
	if not _t.check("%s: the tier supplies wall plates to sweep (%d)" % [stem, walls.size()],
			walls.size() >= 8):
		return
	var inside := _tier_centre(walls)
	for figure in [
		{"name": "standing", "height": STAND_H},
		{"name": "kneeling", "height": KNEE_H},
	]:
		var height := float(figure["height"])
		var query := _figure(height)
		var band_lo := floor_y + STAND_EPS
		var band_hi := band_lo + height
		var stations := 0
		var stuck := PackedStringArray()
		var through := PackedStringArray()
		var swept: Array = []
		var highest_foot := -INF
		for wall_variant in walls:
			var wall := wall_variant as Dictionary
			if minf(band_hi, float(wall["y_hi"])) - maxf(band_lo, float(wall["y_lo"])) \
					< BAND_OVERLAP_MIN:
				continue
			var ref := wall["ref"] as Vector2
			if ref.x < MIN_RUN:
				continue
			swept.append(str(wall["name"]))
			highest_foot = maxf(highest_foot, float(wall["y_lo"]))
			var corners := wall["corners"] as PackedVector3Array
			var normal := _outward(corners, inside)
			var only: Dictionary = _indices_of.get(int(wall["id"]), {})
			var openings := StructureBaker.plate_openings(wall["props"] as Dictionary, ref)
			var u := END_INSET
			while u <= ref.x - END_INSET:
				if _station_kind(openings, u, band_lo, band_hi) != "shell":
					u += STATION_STEP
					continue
				stations += 1
				var march := _march(
					_march_start(corners, ref, u, band_lo, band_hi, normal),
					-normal * MARCH_LEN, query, only
				)
				var where := "%s @%.2f" % [str(wall["name"]), u]
				if bool(march["started_inside"]):
					stuck.append("%s in %s" % [where, _describe(str(march["hit"]))])
				elif not bool(march["blocked"]):
					through.append(where)
				u += STATION_STEP
		print("  [shell] %s: %d stations over %d plates, %d walked through, %d began inside"
			% [str(figure["name"]), stations, swept.size(), through.size(), stuck.size()])
		if not stuck.is_empty():
			print("  [shell] %s began inside: %s" % [str(figure["name"]), ", ".join(stuck)])
		if not through.is_empty():
			print("  [shell] %s walked through: %s" % [str(figure["name"]), ", ".join(through)])
		_t.check("%s: the %s sweep covered the shell (%d stations, %d plates)"
			% [stem, str(figure["name"]), stations, swept.size()], stations >= 40)
		## First, because a run of these would hollow the claim below into a
		## tautology — and because "began inside the plate it is marching at" is
		## the raked-wall instrument bug this file was written around.
		_t.equal("%s: no %s shell march begins inside the plate it is marching at (%d)"
			% [stem, str(figure["name"]), stuck.size()], stuck.size(), 0)
		_t.check("%s: a %s player is stopped by every piece-built wall plate (%d/%d through, e.g. %s)"
			% [stem, str(figure["name"]), through.size(), stations,
			   "none" if through.is_empty() else str(through[0])], through.is_empty())
		if str(figure["name"]) == "kneeling":
			## THE ANTI-VACUITY GUARD. The kneeling figure is what covers the
			## plating course of a glazed wall, and its answer is only worth
			## anything if it never met the glass. Every plate it was planted on
			## has its foot on the deck, so the pane — which starts at the sill,
			## a metre up — was not in the band.
			print("  [shell] kneeling swept: %s" % ", ".join(PackedStringArray(swept)))
			_t.check(
				"%s: every plate the kneeling figure met is plating standing on the deck "
				% stem + "(highest foot plan y %.3f, band %.3f..%.3f)"
				% [highest_foot, band_lo, band_hi],
				highest_foot < floor_y + 0.2
			)


## Where a march starts, so that it starts OUTSIDE the wall. A raked plate leans
## over its own foot, so the surface point at the figure's centre height is not
## the furthest the plate reaches over the figure's height: the start is pushed
## out past the furthest point the plate reaches ANYWHERE in the band, plus
## START_OUT. Getting this wrong is not hypothetical — see the header.
func _march_start(corners: PackedVector3Array, ref: Vector2, u: float,
		band_lo: float, band_hi: float, normal: Vector3) -> Vector3:
	var furthest := -INF
	var at := Vector3.ZERO
	for i in COLUMN_SAMPLES:
		var y := lerpf(band_lo, band_hi, float(i) / float(COLUMN_SAMPLES - 1))
		var p := _wall_point_at_height(corners, u / ref.x, y)
		var reach := p.dot(normal)
		if reach > furthest:
			furthest = reach
		if i == 0:
			at = p
	## Keep the station's own height (the capsule centre walks level) and slide
	## along the normal to clear the whole plate.
	var centre := _wall_point_at_height(corners, u / ref.x, (band_lo + band_hi) * 0.5)
	return centre + normal * (furthest - centre.dot(normal) + START_OUT) + _offset


# ── 3. Doors pass, windows do not ────────────────────────────────────────────

func _check_openings(walls: Array, stem: String, floor_y: float) -> void:
	var inside := _tier_centre(walls)
	var doors := 0
	var doors_low := PackedStringArray()
	var doors_narrow := PackedStringArray()
	var doors_pinched := PackedStringArray()
	var stations := 0
	var stuck := PackedStringArray()
	var blocked := PackedStringArray()
	var window_stations := 0
	var window_through := PackedStringArray()
	for wall_variant in walls:
		var wall := wall_variant as Dictionary
		var ref := wall["ref"] as Vector2
		var corners := wall["corners"] as PackedVector3Array
		var normal := _outward(corners, inside)
		for opening_variant in StructureBaker.plate_openings(wall["props"] as Dictionary, ref):
			var opening := opening_variant as Dictionary
			if float(opening["sill"]) > 0.05:
				## A punched window or a scuttle. Its claim is that the plating
				## UNDER it stops a standing player, which is the shell sweep's
				## job; counted here so the two numbers can be compared.
				window_stations += 1
				continue
			doors += 1
			var head := _door_head_y(corners, ref, opening)
			var need := floor_y + STAND_H + HEAD_MARGIN
			if head < need:
				doors_low.append("%s@%.2f head at plan y %.3f, a 1.8 m figure needs %.3f"
					% [str(wall["name"]), float(opening["off"]), head, need])
			var band_lo := floor_y + STAND_EPS
			var clear := _physics_clear_width(corners, ref, opening)
			if clear < float(opening["w"]) - DOOR_PHYSICS_SLACK:
				doors_pinched.append("%s@%.2f drawn %.3f m, open %.3f m in physics"
					% [str(wall["name"]), float(opening["off"]), float(opening["w"]), clear])
			var column := _door_column(corners, ref, opening, band_lo)
			var width := float(column["width"])
			print("  [door] %s@%.2f nominal %.2f m · open %.3f m in physics · walkable column %.3f m · head %.3f m"
				% [str(wall["name"]), float(opening["off"]), float(opening["w"]), clear, width,
				   head - floor_y])
			if width < DOOR_PLAY_MIN:
				doors_narrow.append("%s@%.2f only %.3f m of play"
					% [str(wall["name"]), float(opening["off"]), width])
				continue
			for i in DOOR_STATIONS:
				var u := lerpf(float(column["lo"]), float(column["hi"]),
					float(i) / float(DOOR_STATIONS - 1))
				for figure in [
					{"name": "standing", "height": STAND_H},
					{"name": "kneeling", "height": KNEE_H},
				]:
					var height := float(figure["height"])
					var query := _figure(height)
					var hi := band_lo + height
					## NOT filtered: "a player walks through this door" is a
					## claim about the whole vessel, not about one plate.
					var march := _march(
						_march_start(corners, ref, u, band_lo, hi, normal),
						-normal * MARCH_LEN, query, {}
					)
					var where := "%s %s@%.2f" % [str(figure["name"]), str(wall["name"]), u]
					if bool(march["started_inside"]):
						stuck.append("%s in %s" % [where, _describe(str(march["hit"]))])
						continue
					stations += 1
					if bool(march["blocked"]):
						blocked.append("%s stopped at %.2f m by %s"
							% [where, float(march["stop_m"]), _describe(str(march["hit"]))])
	print("  [door] %d doorways, %d stations, %d blocked, %d began inside · %d punched windows"
		% [doors, stations, blocked.size(), stuck.size(), window_stations])
	_t.check("%s: the tier carries doorways to walk through (%d)" % [stem, doors], doors >= 1)
	_t.equal("%s: no door march begins inside a collider (%d)" % [stem, stuck.size()],
		stuck.size(), 0)
	_t.check("%s: every doorway is tall enough for the 1.8 m figure (%d too low: %s)"
		% [stem, doors_low.size(), "none" if doors_low.is_empty() else ", ".join(doors_low)],
		doors_low.is_empty())
	_t.check("%s: every doorway leaves a walkable column (%d too narrow: %s)"
		% [stem, doors_narrow.size(),
		   "none" if doors_narrow.is_empty() else ", ".join(doors_narrow)],
		doors_narrow.is_empty())
	## THE DRAWING AND THE PHYSICS AGREE ABOUT THE HOLE. Every check above reads
	## the DRAWN opening — `plate_openings` on the plate's own props — so all of
	## them would go on passing while the collider quietly closed the doorway in.
	## That is not hypothetical: the opening casing is drawn PLATE_FRAME_WIDTH
	## wide, it now emits colliders (it did not, and 44 of 72 of its corners stood
	## outside every box), and centred ON the cut edge it would take 0.045 m off
	## each jamb and off the head of every door in the game — with nothing here
	## measuring it. This asks the space state directly, point by point along the
	## run at the door's own mid-height.
	_t.check("%s: every doorway is as wide in physics as it is drawn (%d pinched: %s)"
		% [stem, doors_pinched.size(),
		   "none" if doors_pinched.is_empty() else ", ".join(doors_pinched)],
		doors_pinched.is_empty())
	_t.check("%s: the door sweep planted stations (%d)" % [stem, stations],
		stations >= doors * DOOR_STATIONS)
	_t.check("%s: a player on deck walks through a piece-built door (%d/%d blocked, e.g. %s)"
		% [stem, blocked.size(), stations, "none" if blocked.is_empty() else str(blocked[0])],
		blocked.is_empty())
	_t.check("%s: the fixture punches windows as well as doors (%d)" % [stem, window_stations],
		window_stations >= 0)


## The widest run of the doorway, along the plate's own u, at which a POINT in
## the plate's mid-plane is in nothing at all. A point rather than a shape,
## because a shape's radius would have to be subtracted back out and this is the
## one measurement that must not carry an arithmetic correction. Asked of the
## whole vessel, unfiltered: a strake, a stanchion or a neighbouring plate
## standing in the doorway narrows it exactly as the door's own casing does.
func _physics_clear_width(corners: PackedVector3Array, ref: Vector2, opening: Dictionary) -> float:
	var query := PhysicsPointQueryParameters3D.new()
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.collision_mask = 0xFFFFFFFF
	var off := float(opening["off"])
	var width := float(opening["w"])
	var sill := float(opening["sill"])
	var height := float(opening["h"])
	var narrowest := INF
	## Three heights, and the answer is the WORST of them: a doorway is an
	## aperture, not a line. A rubbing strake laid across the bulkhead at 0.50 m
	## leaves the mid-height scan reading a full 1.18 m and shuts the door at the
	## shins — measured, on this fixture, before the strake was stopped either
	## side of the casing.
	for band in [0.25, 0.5, 0.75]:
		## `band` comes out of an untyped array literal as a Variant, so the
		## division cannot infer — hence the explicit float. (This line is where
		## the wave that wrote this function was killed mid-edit.)
		var v := (sill + height * float(band)) / ref.y
		var best := 0.0
		var run_lo := NAN
		var u := off - 0.10
		while u <= off + width + 0.10:
			query.position = (
				StructureBaker.plate_point(corners, clampf(u / ref.x, 0.0, 1.0), v) + _offset
			)
			if _space.intersect_point(query, 1).is_empty():
				if is_nan(run_lo):
					run_lo = u
				best = maxf(best, u - run_lo)
			else:
				run_lo = NAN
			u += DOOR_SCAN_STEP
		narrowest = minf(narrowest, best)
	return narrowest


## 4-and-a-bit: a recessed pane is not a way through. Every glazed plate that
## the floor-level sweep did NOT reach — the pane, the header — is asked to stop
## a figure sized to its own band. The pane is set 90 mm into the reveal and is
## the only thing there, so this is a claim about the glass and nothing else.
func _check_panes(walls: Array, stem: String) -> void:
	var inside := _tier_centre(walls)
	var stations := 0
	var through := PackedStringArray()
	var stuck := PackedStringArray()
	var panes := 0
	var glazed := 0
	for wall_variant in walls:
		var wall := wall_variant as Dictionary
		if str(wall["kind"]) != "wall_glazed":
			continue
		var ref := wall["ref"] as Vector2
		if ref.x < MIN_RUN:
			## A MULLION. `wall_glazed` resolves to a coaming, a pane, a header and
			## `lights - 1` mullions, and a mullion is 0.10 m wide — it is not a run
			## and cannot be asked to stop anything on its own (see MIN_RUN).
			continue
		glazed += 1
		var span := float(wall["y_hi"]) - float(wall["y_lo"])
		if span < 0.45:
			continue
		var height := clampf(span - 0.30, 0.20, 1.00)
		var band_lo := float(wall["y_lo"]) + (span - height) * 0.5
		var band_hi := band_lo + height
		panes += 1
		var query := _figure(height)
		var corners := wall["corners"] as PackedVector3Array
		var normal := _outward(corners, inside)
		var only: Dictionary = _indices_of.get(int(wall["id"]), {})
		var u := END_INSET
		while u <= ref.x - END_INSET:
			stations += 1
			var march := _march(
				_march_start(corners, ref, u, band_lo, band_hi, normal),
				-normal * MARCH_LEN, query, only
			)
			var where := "%s @%.2f (y %.2f..%.2f)" % [str(wall["name"]), u, band_lo, band_hi]
			if bool(march["started_inside"]):
				stuck.append(where)
			elif not bool(march["blocked"]):
				through.append(where)
			u += STATION_STEP
	_pane_plates += panes
	_pane_stations += stations
	print("  [pane] %d glazed runs in the tier, %d swept, %d stations, %d walked through, %d began inside"
		% [glazed, panes, stations, through.size(), stuck.size()])
	if not through.is_empty():
		print("  [pane] walked through: %s" % ", ".join(through))
	## COVERAGE, stated against what the tier actually carries rather than against
	## a number. `probe_piece_tug`'s pilot-house casing is plated with PUNCHED
	## windows and its ribbon glazing is all in the wheelhouse above the tier, so
	## it has none here — and the old form of this check (`stations >= 20`) failed
	## a fixture for a shape it never claimed to have. What must not be allowed is
	## a glazed RUN whose glass is quietly not swept: the only thing the sweep is
	## permitted to skip is a plate under 0.45 m in its own height band, so a pane
	## band shrunk below that turns this red rather than silently going unasked.
	## The run-level guard in `_ready` is what stops "0 of 0" being the whole
	## suite's answer.
	_t.equal("%s: every glazed run in the tier was swept (%d of %d)" % [stem, panes, glazed],
		panes, glazed)
	_t.check("%s: ...and each swept pane carries stations (%d over %d plates)"
		% [stem, stations, panes], panes == 0 or stations >= panes * 4)
	_t.equal("%s: no pane march begins inside the plate it is marching at (%d)"
		% [stem, stuck.size()], stuck.size(), 0)
	_t.check("%s: a window band is not a doorway (%d/%d through, e.g. %s)"
		% [stem, through.size(), stations, "none" if through.is_empty() else str(through[0])],
		through.is_empty())


# ── 4. What you collide with is what you see ─────────────────────────────────
#
# The check `vessel_render_capture` runs on swept edge runs, pointed at
# piece-resolved plates: every corner of every drawn slab must lie inside some
# collider the baker emits. It is a coverage claim, not a count — a count is
# what a re-derivation would still satisfy.
#
# Panels and opening CASINGS are counted apart on purpose. A panel is the wall;
# a casing is the proud joinery round a hole, PLATE_FRAME_PROUD past both faces.
# If the casings are loose, the two numbers say so separately instead of
# averaging into one verdict nobody can act on. They WERE loose — 44 of 72 on the
# house, 200 of 240 on the tug — because `plate_colliders` walked `plate_panels`
# and `plate_layers` walked panels AND frames. Both now walk `plate_slabs`.

func _check_drawn_is_collided(plan: StructurePlan, stem: String) -> void:
	var panel_corners := 0
	var panel_loose := 0
	var frame_corners := 0
	var frame_loose := 0
	var first_panel := Vector3.INF
	var first_frame := Vector3.INF
	for item_variant in plan.items:
		var item := item_variant as Dictionary
		if StructureBaker.item_primitive(item) != "plate":
			continue
		var props := StructurePlan.item_props(item)
		if not str(props.get("__piece", "")).begins_with("wall") \
				and not str(props.get("__piece", "")).begins_with("corner") \
				and not str(props.get("__piece", "")).begins_with("deck") \
				and not str(props.get("__piece", "")).begins_with("roof") \
				and not str(props.get("__piece", "")).begins_with("trim"):
			continue
		var corners := StructureBaker._transformed(
			StructureBaker.plate_corners(props), plan.item_transform(item)
		)
		var base := StructureBaker.plate_thickness(props)
		for layer_variant in StructureBaker.plate_layers(props, corners, int(item.get("id", -1))):
			var layer := layer_variant as Dictionary
			if str(layer.get("kind", "")) != "slab":
				continue
			var is_frame := float(layer["thickness"]) > base + 1e-4
			for point in _slab_corners(layer):
				if is_frame:
					frame_corners += 1
				else:
					panel_corners += 1
				if _covered(point):
					continue
				if is_frame:
					frame_loose += 1
					if first_frame == Vector3.INF:
						first_frame = point
				else:
					panel_loose += 1
					if first_panel == Vector3.INF:
						first_panel = point
	print("  [drawn] plate panels: %d/%d corners loose · opening casings: %d/%d loose"
		% [panel_loose, panel_corners, frame_loose, frame_corners])
	_t.check("%s: the drawn-vs-collided sweep sampled the piece geometry (%d corners)"
		% [stem, panel_corners], panel_corners > 400)
	_t.check("%s: every corner of every drawn piece panel is inside a collider (%d loose, first %v)"
		% [stem, panel_loose, first_panel], panel_loose == 0)
	_t.check("%s: every corner of every drawn opening casing is inside a collider (%d/%d loose, first %v)"
		% [stem, frame_loose, frame_corners, first_frame], frame_loose == 0)


func _slab_corners(layer: Dictionary) -> Array:
	var quad := layer["quad"] as PackedVector3Array
	if quad.size() != 4:
		return []
	var half := StructureBaker.plate_normal(quad) * (float(layer["thickness"]) * 0.5)
	var out: Array = []
	for point in quad:
		out.append(point + half)
		out.append(point - half)
	return out


func _covered(point: Vector3) -> bool:
	for box_variant in _boxes:
		var box := box_variant as Dictionary
		var inv := Basis(Vector3.UP, deg_to_rad(float(box["yaw_deg"]))).transposed()
		var q := (inv * (point - (box["center"] as Vector3))).abs()
		var half := (box["size"] as Vector3) * 0.5 + Vector3.ONE * COVER_SLACK
		if q.x <= half.x and q.y <= half.y and q.z <= half.z:
			return true
	return false


# ── Controls ─────────────────────────────────────────────────────────────────

func _check_controls(stem: String, floor_y: float) -> void:
	var query := _figure(STAND_H)
	var air := _march(Vector3(5.0, 30.0, 14.0) + _offset, Vector3.RIGHT * 3.0, query, {})
	_t.check("%s: an open-air march is reported free" % stem,
		not bool(air["blocked"]) and not bool(air["started_inside"]))
	if is_nan(floor_y):
		return
	## The filter must be able to say "blocked" as well as "free": marched at a
	## wall with that wall's own colliders allowed, it stops; the same march with
	## an EMPTY-but-not-absent filter set cannot stop, which is the failure mode
	## an "only" dictionary has.
	var bogus: Dictionary = {-1: true}
	var never := _march(Vector3(5.0, floor_y + 1.0, 5.0) + _offset, Vector3.FORWARD * 3.0,
		query, bogus)
	_t.check("%s: a march filtered to a collider that does not exist is never blocked" % stem,
		not bool(never["blocked"]) and not bool(never["started_inside"]))


# ── Geometry helpers ─────────────────────────────────────────────────────────

func _describe(hit_name: String) -> String:
	if not hit_name.begins_with(PLAN_PREFIX):
		return hit_name
	var index := int(hit_name.substr(PLAN_PREFIX.length()))
	if index < 0 or index >= _boxes.size():
		return hit_name
	var box := _boxes[index] as Dictionary
	var c: Vector3 = box["center"]
	var h: Vector3 = (box["size"] as Vector3) * 0.5
	return "%s item %s centre (%.2f, %.2f, %.2f) half (%.2f, %.2f, %.2f) y %.2f..%.2f" % [
		hit_name, str(_owner_of.get(index, "?")), c.x, c.y, c.z, h.x, h.y, h.z,
		c.y - h.y, c.y + h.y
	]


func _tier_centre(walls: Array) -> Vector3:
	var sum := Vector3.ZERO
	var n := 0
	for wall_variant in walls:
		for point in (wall_variant as Dictionary)["corners"] as PackedVector3Array:
			sum += point
			n += 1
	return sum / maxf(float(n), 1.0)


## The plate normal that points away from the tier it encloses, flattened: a
## player walks in level, and a raked wall's true normal has a vertical
## component that would march the capsule into the deck or the roof.
func _outward(corners: PackedVector3Array, inside: Vector3) -> Vector3:
	var n := StructureBaker.plate_normal(corners)
	var flat := Vector3(n.x, 0.0, n.z)
	if flat.length() < 0.001:
		flat = Vector3(1.0, 0.0, 0.0)
	flat = flat.normalized()
	var mid := StructureBaker.plate_point(corners, 0.5, 0.5)
	return flat if flat.dot(mid - inside) > 0.0 else -flat


## The plate parameter v at which the plate's own surface reaches height `y`.
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


func _wall_point_at_height(corners: PackedVector3Array, u: float, y: float) -> Vector3:
	return StructureBaker.plate_point(corners, u, _v_at_height(corners, u, y))


func _wall_run(corners: PackedVector3Array) -> Vector3:
	var d := StructureBaker.plate_point(corners, 1.0, 0.0) \
		- StructureBaker.plate_point(corners, 0.0, 0.0)
	var flat := Vector3(d.x, 0.0, d.z)
	return Vector3.RIGHT if flat.length() < 0.001 else flat.normalized()


## Which of {door, jamb, window, shell} a station at `u` metres along the wall
## sits in, judged against the capsule's WIDTH rather than its centre line.
## `jamb` is excluded from scoring in both directions: a capsule that overlaps a
## doorway but does not clear its jambs may legitimately pass or legitimately
## catch, and guessing is how a solidity sweep starts reporting its own
## arithmetic as a failure.
func _station_kind(openings: Array, u: float, band_lo: float, band_hi: float) -> String:
	for opening_variant in openings:
		var opening := opening_variant as Dictionary
		var off := float(opening["off"])
		var width := float(opening["w"])
		if u + CAPSULE_R <= off or u - CAPSULE_R >= off + width:
			continue
		if float(opening["sill"]) > 0.05:
			## A punched window. It is a genuine hole, and the claim about it is
			## that the plating BELOW its sill stops the figure — so the station
			## is scored as shell whenever the figure's band reaches under the
			## sill, and skipped when the figure sits wholly inside the hole.
			if band_lo < float(opening["sill"]) - 0.05:
				continue
			return "jamb"
		if band_lo > float(opening["sill"]) + float(opening["h"]):
			continue
		return "door" if (u >= off + CAPSULE_R + JAMB_MARGIN
			and u <= off + width - CAPSULE_R - JAMB_MARGIN) else "jamb"
	return "shell"


## The LOWEST point of a doorway's head, in plan y — the height a player has to
## duck under. Sampled across the door because a raked head is not level.
func _door_head_y(corners: PackedVector3Array, ref: Vector2, opening: Dictionary) -> float:
	var v := (float(opening["sill"]) + float(opening["h"])) / ref.y
	var lowest := INF
	for i in 9:
		var u := lerpf(float(opening["off"]), float(opening["off"]) + float(opening["w"]),
			float(i) / 8.0)
		lowest = minf(lowest, StructureBaker.plate_point(corners, u / ref.x, v).y)
	return lowest


## What a doorway in a RAKED wall is actually worth: the interval of wall
## parameter where a vertical capsule clears BOTH jambs at EVERY height it
## occupies. A "0.85 m door" in a leaning wall is a slot whose jambs are in one
## place at the player's feet and elsewhere at their head.
func _door_column(corners: PackedVector3Array, ref: Vector2, opening: Dictionary,
		band_lo: float) -> Dictionary:
	var off := float(opening["off"])
	var width := float(opening["w"])
	var run := _wall_run(corners)
	var vs := PackedFloat32Array()
	for i in COLUMN_SAMPLES:
		var y := band_lo + STAND_H * float(i) / float(COLUMN_SAMPLES - 1)
		vs.append(_v_at_height(corners, (off + width * 0.5) / ref.x, y))
	var lo := INF
	var hi := -INF
	var u := off
	while u <= off + width:
		if _clears_jambs(corners, ref, off, width, u, vs, run):
			lo = minf(lo, u)
			hi = maxf(hi, u)
		u += COLUMN_STEP
	if lo > hi:
		return {"lo": off + width * 0.5, "hi": off + width * 0.5, "width": 0.0}
	var a := StructureBaker.plate_point(corners, lo / ref.x, vs[0])
	var b := StructureBaker.plate_point(corners, hi / ref.x, vs[0])
	return {"lo": lo, "hi": hi, "width": absf((b - a).dot(run))}


func _clears_jambs(corners: PackedVector3Array, ref: Vector2, off: float, width: float,
		u: float, vs: PackedFloat32Array, run: Vector3) -> bool:
	var here := StructureBaker.plate_point(corners, u / ref.x, vs[0])
	for v in vs:
		var jamb_a := StructureBaker.plate_point(corners, off / ref.x, v)
		var jamb_b := StructureBaker.plate_point(corners, (off + width) / ref.x, v)
		if minf((here - jamb_a).dot(run), (jamb_b - here).dot(run)) < CAPSULE_R + JAMB_MARGIN:
			return false
	return true
