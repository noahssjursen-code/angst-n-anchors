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
## THE ANSWER, so it is not buried below: yes, once the doors were made big
## enough. The shell collides as drawn, the WalkDeck slab is a floor 0.09 m above
## the plan's deck plane, and the doorways are holes a capsule walks through. The
## doors on both vessels were NOT big enough before this test measured them — see
## JAMB_MARGIN and `_door_column` for what a doorway in a raked plate is worth.
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
## Claims 1, 3 and 4 are run TWICE, by a standing figure and a kneeling one, and
## the second is the one that has teeth — see `_ready`.
##
## Four traps, all of which produced a false green in this file's own history:
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
##    the deck, (2) fails and says so. Measured: WalkDeckCollider tops out at
##    plan y 0.090 and WalkHullCollider at −0.960, so the hull box is not in the
##    way of anything at deck level.
##
##  - A wall whose plate is RAKED does not stand over its own foot. Every station
##    is solved for the v parameter at which the plate's own surface reaches the
##    figure's centre height, so a forward-raked wheelhouse front is met where it
##    actually is rather than where its foot is.
##
##  - A `PackedStringArray` held in a Dictionary is a VALUE: reading it back
##    hands you a copy, and appending to it appends to a temporary. This test
##    reported "0 walked through" on a vessel with its whole starboard side
##    deliberately hollowed out until the tallies were moved to `Array`.
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
## The same player, crouched — the figure that fits UNDER a window band.
const KNEE_H := 0.8

const MARCH_STEP := 0.02   ## << the 0.10 m plate thickness; cannot tunnel a wall
const STATION_STEP := 0.10 ## along a wall
const START_OUT := 0.60    ## how far outside the shell a march begins
const MARCH_LEN := 1.30    ## far enough to end a capsule-radius clear inside
const DROP_FROM := 0.50    ## how far above the deck the floor march begins
const DROP_LEN := 1.00

## How far clear of a DRAWN jamb the capsule has to be before the physics can be
## expected to agree with the drawing. It is not a fudge factor: a raked plate's
## collider is a STAIRCASE — `StructureBaker._plate_panel_colliders` cuts each
## panel into cells and gives each cell the bounding box of its own corners, so
## the box stands up to one PLATE_COLLIDER_STEP (0.15 m) proud of the leaning
## surface it wraps. Every opening in a raked plate is therefore that much
## narrower in collision than it is in the picture, and a doorway measured
## against the drawing alone reads wider than it walks. Measured on demo_workboat:
## with a 0.06 m margin the column came out 0.315 m and four of its own stations
## were then stopped by the staircase.
const JAMB_MARGIN := 0.16
## How many stations to plant across the walkable column of each doorway.
const DOOR_STATIONS := 9
## Heights at which a doorway's jambs are checked against the standing figure.
const COLUMN_SAMPLES := 9
const COLUMN_STEP := 0.01
## A doorway has to leave the figure this much lateral play, or it is a doorway
## in name only: a player who has to be within a centimetre of one line to get
## through a door will report the door as broken, and be right.
const DOOR_PLAY_MIN := 0.12
## And this much air over its head.
const HEAD_MARGIN := 0.05

const FIXTURES: Array[Dictionary] = [
	{
		"path": "res://resources/data/structures/demo_workboat.json",
		"hull": "hull_28x10",
		"registration": "cargo_vessel",
		## The lower-tier shell. The forward face is NOT swept: it stands over the
		## foredeck where the crane pedestal and the bulwark are, and a sweep that
		## has to skip the stations it cannot start cleanly is a sweep that can
		## hide a failure. It carries no door, so it costs the door claim nothing.
		"walls": [
			"lower tier, front", "lower tier, port side",
			"lower tier, starboard side", "lower tier, aft bulkhead",
		],
		"tier": ["lower tier,", "boat deck"],
		## Clear of the companionway (x 4.0-5.5, z 9.0-13.0) and of the walls.
		"inside": [[6.5, 11.0], [7.5, 14.0], [2.5, 14.5], [6.0, 15.0]],
	},
	{
		"path": "res://resources/data/structures/probe_trawler_bulwark.json",
		"hull": "hull_28x10",
		"registration": "fishing_vessel",
		## Named, not numbered — see `_plates_named`. The GLASS plates are excluded
		## from `walls` on purpose: a recessed pane is not the shell, and the sweep
		## has to be stopped by the plate around it, which is the whole claim.
		"walls": [
			"lower tier, raked front —",
			"lower tier, port side",
			"lower tier, starboard side",
			"lower tier, aft bulkhead",
		],
		"tier": ["lower tier,", "boat deck"],
		"inside": [[5.0, 19.5], [3.5, 22.0], [6.5, 22.0], [5.0, 23.8]],
	},
]

var _t: RefCounted
var _walk: CollisionObject3D
var _space: PhysicsDirectSpaceState3D
var _figures: Array[Dictionary] = []
var _offset := Vector3.ZERO
var _boxes: Array = []


func _ready() -> void:
	_t = TestReport.new("plan_interior_test")
	## Two figures, and the second is not decoration. A STANDING capsule spans the
	## whole window band, so at a window station it is stopped by the recessed
	## glass pane whether or not the SHELL PLATE around it collides at all —
	## measured: hollowing demo_workboat's whole starboard plate (`solid: false`,
	## 312 collider boxes down to 290) left this sweep entirely green, because the
	## pane and the two corner walls between them covered every station the
	## standing figure could reach. A KNEELING capsule passes under the pane and
	## has nothing but the plating below the sill to stop it, so it is the one
	## that can tell a solid wall from a hole with a window hung in front of it.
	for figure in [
		{"name": "standing", "height": CAPSULE_H, "lift": STAND_EPS + CAPSULE_H * 0.5},
		{"name": "kneeling", "height": KNEE_H, "lift": STAND_EPS + KNEE_H * 0.5},
	]:
		var shape := CapsuleShape3D.new()
		shape.radius = CAPSULE_R
		shape.height = float(figure["height"])
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = shape
		query.collide_with_bodies = true
		query.collide_with_areas = false
		query.collision_mask = 0xFFFFFFFF
		figure["query"] = query
		_figures.append(figure)
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
func _hit(centre: Vector3, query: PhysicsShapeQueryParameters3D) -> String:
	query.transform = Transform3D(Basis.IDENTITY, centre)
	for hit_variant in _space.intersect_shape(query, 4):
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
func _march(from: Vector3, motion: Vector3, query: PhysicsShapeQueryParameters3D) -> Dictionary:
	var length := motion.length()
	var steps := maxi(2, int(ceil(length / MARCH_STEP)))
	var out := {"started_inside": false, "blocked": false, "stop_m": length, "hit": ""}
	for i in steps + 1:
		var f := float(i) / float(steps)
		var name := _hit(from + motion * f, query)
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
		var drop := _march(from, Vector3.DOWN * DROP_LEN, _figures[0]["query"])
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
	var tier := _plates_named(plan, fixture["tier"] as Array)
	if not _t.check("%s: the fixture supplies a deckhouse tier (%d plates)" % [stem, tier.size()],
			tier.size() >= 3):
		return
	var inside := _tier_centre(tier)
	var doors := 0
	var doors_narrow := PackedStringArray()
	var doors_low := PackedStringArray()
	var stuck := PackedStringArray()
	var ambiguous := 0
	## Per figure: {free, stations, blocked[], solid, through[], windows, window_through[], stoppers}
	var tally: Dictionary = {}
	for figure in _figures:
		## Array, NOT PackedStringArray. A Packed* array is a VALUE type: reading
		## one back out of a Dictionary hands you a COPY, so `row["through"].append(x)`
		## appends to a temporary and throws it away. That is not a hypothetical —
		## it is what this test did on its first two-figure run, and it reported
		## "0 walked through" for a vessel whose whole starboard side had been
		## deliberately hollowed out. Arrays are reference types and append in place.
		tally[figure["name"]] = {
			"free": 0, "stations": 0, "blocked": [],
			"solid": 0, "through": [],
			"windows": 0, "window_through": [], "stoppers": {},
		}

	for wall_spec_variant in _named_plate_specs(plan, fixture["walls"] as Array):
		var named := wall_spec_variant as Dictionary
		var wall_id := str(named["name"])
		var corners := named["corners"] as PackedVector3Array
		var ref := StructureBaker.plate_ref_lengths(corners)
		var normal := _outward(corners, inside)
		var openings := StructureBaker.plate_openings(spec, ref)

		## ── the doors, one at a time ────────────────────────────────────────
		for opening_variant in openings:
			var opening := opening_variant as Dictionary
			if float(opening["sill"]) > 0.05:
				continue
			doors += 1
			var head := _door_head_y(corners, ref, opening)
			var need := floor_y + CAPSULE_H + HEAD_MARGIN
			if head < need:
				doors_low.append("%s@%.2f head at plan y %.3f, a 1.8 m figure needs %.3f"
					% [wall_id, float(opening["off"]), head, need])
			var column := _door_column(corners, ref, opening, floor_y)
			var width := float(column["width"])
			print("  [door] %s@%.2f nominal %.2f m · walkable column %.3f m of play · head %.3f m"
				% [wall_id, float(opening["off"]), float(opening["w"]), width, head - floor_y])
			if width < DOOR_PLAY_MIN:
				doors_narrow.append("%s@%.2f only %.3f m of play"
					% [wall_id, float(opening["off"]), width])
				continue
			for i in DOOR_STATIONS:
				var u := lerpf(float(column["lo"]), float(column["hi"]),
					float(i) / float(DOOR_STATIONS - 1))
				for figure in _figures:
					var row: Dictionary = tally[figure["name"]]
					var at := _wall_point_at_height(
						corners, u / ref.x, floor_y + float(figure["lift"]))
					var march := _march(at + normal * START_OUT + _offset,
						-normal * MARCH_LEN, figure["query"])
					var where := "%s %s@%.2f" % [figure["name"], wall_id, u]
					if bool(march["started_inside"]):
						stuck.append("%s in %s" % [where, march["hit"]])
						continue
					row["stations"] = int(row["stations"]) + 1
					if bool(march["blocked"]):
						(row["blocked"] as Array).append(
							"%s stopped at %.2f m by %s"
							% [where, march["stop_m"], _describe(str(march["hit"]))])
					else:
						row["free"] = int(row["free"]) + 1

		## ── and the rest of the wall ────────────────────────────────────────
		for u_variant in _stations(ref.x):
			var u := float(u_variant)
			var kind := _station_kind(openings, u)
			if kind == "door" or kind == "jamb":
				ambiguous += 1
				continue
			for figure in _figures:
				var row: Dictionary = tally[figure["name"]]
				var at := _wall_point_at_height(corners, u / ref.x, floor_y + float(figure["lift"]))
				var march := _march(at + normal * START_OUT + _offset,
					-normal * MARCH_LEN, figure["query"])
				var where := "%s %s@%.2f" % [figure["name"], wall_id, u]
				if bool(march["started_inside"]):
					stuck.append("%s in %s" % [where, march["hit"]])
					continue
				row["solid"] = int(row["solid"]) + 1
				if kind == "window":
					row["windows"] = int(row["windows"]) + 1
				if not bool(march["blocked"]):
					(row["through"] as Array).append(where)
					if kind == "window":
						(row["window_through"] as Array).append(where)
				else:
					var stoppers: Dictionary = row["stoppers"]
					var name := str(march["hit"])
					stoppers[name] = int(stoppers.get(name, 0)) + 1

	for figure in _figures:
		var row: Dictionary = tally[figure["name"]]
		var fig := str(figure["name"])
		print("  [walk] %s: doors %d/%d free · shell %d stations, %d through · windows %d"
			% [fig, int(row["free"]), int(row["stations"]), int(row["solid"]),
			   (row["through"] as Array).size(), int(row["windows"])])
		## Which colliders are doing the stopping. A sweep that comes back green
		## because ONE unexpected shape covers the whole side of the vessel proves
		## nothing about the shell, and this line is how you see that happening.
		var stoppers: Dictionary = row["stoppers"]
		var names := stoppers.keys()
		names.sort_custom(func(a, b): return int(stoppers[a]) > int(stoppers[b]))
		var top := PackedStringArray()
		for i in mini(6, names.size()):
			top.append("%s x%d" % [_describe(str(names[i])), int(stoppers[names[i]])])
		print("  [walk] %s: stopped by %s" % [fig, ", ".join(top)])
	if not stuck.is_empty():
		print("  [walk] began inside a collider: %s" % ", ".join(stuck))

	## Not decoration. A run of "began inside" verdicts would hollow every claim
	## below into a tautology, so it is the first thing asserted.
	_t.equal("%s: no wall march begins inside a collider (%d)" % [stem, stuck.size()],
		stuck.size(), 0)
	## The two GEOMETRIC halves of "the door admits a player", stated against the
	## 1.8 m figure and separately from the physics. A door can fail either way and
	## the two failures need different fixes, so they are two checks.
	_t.check("%s: every doorway is tall enough for the 1.8 m figure (%d of %d too low: %s)"
		% [stem, doors_low.size(), doors, "none" if doors_low.is_empty() else ", ".join(doors_low)],
		doors_low.is_empty())
	_t.check("%s: every doorway leaves a walkable column for the figure (%d of %d too narrow: %s)"
		% [stem, doors_narrow.size(), doors,
		   "none" if doors_narrow.is_empty() else ", ".join(doors_narrow)],
		doors_narrow.is_empty())

	for figure in _figures:
		var fig := str(figure["name"])
		var row: Dictionary = tally[fig]
		var blocked: Array = row["blocked"]
		var through: Array = row["through"]
		var window_through: Array = row["window_through"]
		_t.check("%s: the %s sweep found door stations to walk through (%d)"
			% [stem, fig, int(row["stations"])], int(row["stations"]) >= doors * DOOR_STATIONS)
		_t.check("%s: a %s player on the open deck walks through a door into the deckhouse (%d/%d, %s)"
			% [stem, fig, int(row["free"]), int(row["stations"]),
			   "none blocked" if blocked.is_empty() else ", ".join(PackedStringArray(blocked))],
			int(row["free"]) == int(row["stations"]))
		_t.check("%s: the %s sweep covered the shell densely (%d stations)"
			% [stem, fig, int(row["solid"])], int(row["solid"]) >= 100)
		_t.check("%s: the shell stops a %s player everywhere a door is not (%d/%d through, e.g. %s)"
			% [stem, fig, through.size(), int(row["solid"]),
			   "none" if through.is_empty() else str(through[0])],
			through.is_empty())
		_t.check("%s: the %s sweep crossed the window bands (%d stations)"
			% [stem, fig, int(row["windows"])], int(row["windows"]) >= 20)
		_t.check("%s: a window band is not a doorway for a %s player (%d/%d through, e.g. %s)"
			% [stem, fig, window_through.size(), int(row["windows"]),
			   "none" if window_through.is_empty() else str(window_through[0])],
			window_through.is_empty())


## Where the shell sweep stands: a uniform run along the whole wall. Doors are
## walked separately, against the column measured below, and their stations are
## excluded here.
func _stations(length: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var u := STATION_STEP
	while u < length - STATION_STEP:
		out.append(u)
		u += STATION_STEP
	return out


## ── What a doorway in a RAKED wall is actually worth ────────────────────────
##
## A deckhouse side is not a rectangle standing on the deck. It rakes, it flares
## and it tapers in plan, so a "0.90 m door" is a slot that LEANS: its jambs are
## in one place at the player's feet and up to a quarter of a metre along the
## wall at their head. A player is a vertical capsule and has to clear the jambs
## at EVERY height at once, so what the door is worth is the intersection of its
## own width over the figure's height — and on the workboat's flared side that
## turned 0.90 m of nominal opening into 0.67 m of column, which a 0.70 m player
## does not fit through. That was measured here, on the first run of this test,
## and it is why the fixtures' doors were widened rather than the check relaxed.
##
## Returns {lo, hi, width}: the interval of wall parameter (in the plate's own
## metres) where the capsule's CENTRE may stand, and how wide that interval is.
## `width` is the lateral play the player has; it is zero for a door they cannot
## get through at all.
func _door_column(corners: PackedVector3Array, ref: Vector2, opening: Dictionary,
		floor_y: float) -> Dictionary:
	var off := float(opening["off"])
	var width := float(opening["w"])
	var run := _wall_run(corners)
	## Heights the capsule occupies, as plate parameters.
	var vs := PackedFloat32Array()
	for i in COLUMN_SAMPLES:
		var y := floor_y + STAND_EPS + CAPSULE_H * float(i) / float(COLUMN_SAMPLES - 1)
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
	## Report the play in METRES on the wall, not in the plate's parameter.
	var a := StructureBaker.plate_point(corners, lo / ref.x, vs[0])
	var b := StructureBaker.plate_point(corners, hi / ref.x, vs[0])
	return {"lo": lo, "hi": hi, "width": absf((b - a).dot(run))}


## True when a capsule centred on the wall at parameter `u` clears BOTH jambs, by
## CAPSULE_R plus a margin, at every height it occupies. Distances are measured
## along the wall's horizontal run: a jamb that moves along the NORMAL as it
## rises (rake) does not narrow the doorway, only one that moves along the run
## (taper, flare in plan) does.
func _clears_jambs(corners: PackedVector3Array, ref: Vector2, off: float, width: float,
		u: float, vs: PackedFloat32Array, run: Vector3) -> bool:
	var here := StructureBaker.plate_point(corners, u / ref.x, vs[0])
	for v in vs:
		var jamb_a := StructureBaker.plate_point(corners, off / ref.x, v)
		var jamb_b := StructureBaker.plate_point(corners, (off + width) / ref.x, v)
		var da := (here - jamb_a).dot(run)
		var db := (jamb_b - here).dot(run)
		if minf(da, db) < CAPSULE_R + JAMB_MARGIN:
			return false
	return true


## Horizontal unit vector along the wall's u run.
func _wall_run(corners: PackedVector3Array) -> Vector3:
	var d := StructureBaker.plate_point(corners, 1.0, 0.0) - StructureBaker.plate_point(corners, 0.0, 0.0)
	var flat := Vector3(d.x, 0.0, d.z)
	return Vector3.RIGHT if flat.length() < 0.001 else flat.normalized()


## The LOWEST point of a doorway's head, in plan y — the height a player has to
## duck under. Sampled across the door because a raked head is not level.
func _door_head_y(corners: PackedVector3Array, ref: Vector2, opening: Dictionary) -> float:
	var off := float(opening["off"])
	var width := float(opening["w"])
	var v := (float(opening["sill"]) + float(opening["h"])) / ref.y
	var lowest := INF
	for i in 9:
		var u := lerpf(off, off + width, float(i) / 8.0)
		lowest = minf(lowest, StructureBaker.plate_point(corners, u / ref.x, v).y)
	return lowest


## The plate parameter v at which the plate's own surface reaches height `y`,
## at parameter `u`.
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
## A raked wall does not stand over its foot; solving for v on the plate's own
## bilinear patch meets it where it actually is.
func _wall_point_at_height(corners: PackedVector3Array, u: float, y: float) -> Vector3:
	return StructureBaker.plate_point(corners, u, _v_at_height(corners, u, y))


## Plates whose `__is` note starts with any of `prefixes`.
##
## This used to take a list of item IDS, and it broke the hour the fixtures were
## renumbered to give their entities unique ids: `[100, 101, 102, 103]` selected
## nothing and the fixture reported "supplies a deckhouse tier (0 plates)". An id
## is an ADDRESS, not a description, and an address is allowed to move — the same
## defect, in the same hour, also silently made `gen_piece_fixtures.py` pick the
## wrong 50 items out of this very fixture. REALITY.md §4b's corollary.
##
## Selecting on what a plate SAYS IT IS survives renumbering, and it reads as the
## thing the test means: "the walls of the lower tier", not "items 100 to 103".
## Same selection as `_plates_named`, but keeping each plate's note so a failure
## names the wall a reader can find ("lower tier, port side") rather than an id
## that may since have moved.
func _named_plate_specs(plan: StructurePlan, prefixes: Array) -> Array:
	var out: Array = []
	for item_variant in plan.items:
		var item := item_variant as Dictionary
		if StructureBaker.item_primitive(item) != "plate":
			continue
		var props := item.get("props", {}) as Dictionary
		var note := str(props.get("__is", ""))
		## The recessed pane shares its wall's prefix — "lower tier, port side"
		## names both the plate and the GLASS in it. The id list this replaced
		## separated them by accident, because they happened to be numbered
		## apart; here it is stated. A pane is not the shell, and the claim under
		## test is that the sweep is stopped by the plate AROUND the window: a
		## standing capsule spans the whole band, so a glass plate in `walls`
		## would pass the sweep whether or not the shell collides at all.
		if note.contains("GLASS"):
			continue
		for prefix_variant in prefixes:
			if note.begins_with(str(prefix_variant)):
				out.append({
					"name": note.substr(0, 44),
					"corners": StructureBaker.plate_corners(props),
					"props": props,
				})
				break
	return out


func _plates_named(plan: StructurePlan, prefixes: Array) -> Array:
	var out: Array = []
	for item_variant in plan.items:
		var item := item_variant as Dictionary
		if StructureBaker.item_primitive(item) != "plate":
			continue
		var note := str((item.get("props", {}) as Dictionary).get("__is", ""))
		for prefix_variant in prefixes:
			if note.begins_with(str(prefix_variant)):
				out.append(StructureBaker.plate_corners(item["props"] as Dictionary))
				break
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
	var air := _march(Vector3(5.0, 22.0, 14.0) + _offset, Vector3.RIGHT * 3.0,
		_figures[0]["query"])
	_t.check("%s: an open-air march is reported free" % stem,
		not bool(air["blocked"]) and not bool(air["started_inside"]))
	if is_nan(floor_y):
		return
	## ... and a march straight down through the open deck outside the deckhouse
	## must be STOPPED, so "the floor held" is not a verdict this rig hands out
	## for free.
	var over := Vector3(5.0, floor_y + DROP_FROM + CAPSULE_H * 0.5, 3.0) + _offset
	var drop := _march(over, Vector3.DOWN * DROP_LEN, _figures[0]["query"])
	_t.check("%s: the open deck also stops a falling capsule (control)" % stem,
		bool(drop["blocked"]) and not bool(drop["started_inside"]))
