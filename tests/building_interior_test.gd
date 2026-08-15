extends Node

## Lane B. CAN A PLAYER WALK INTO A BUILDING'S WALL, AND THROUGH ITS DOOR?
##
## Lane B because `BuildingCache` preloads `building_fitout.gd` ->
## `brick_door.gd`, and `brick_door.gd:96` names the `WorldGateway` autoload as a
## bare compile-time identifier. Under `--script` that is `Identifier not found`,
## the cascade reaches this file, and Godot loads and runs it anyway — a compile
## failure indistinguishable from an assertion failure in the results table
## (REALITY.md §4a, and `port_perf_cache_test`'s header records the same fix).
##
## THE FIRST BUILDING THE GAME HAS EVER HAD IS `warehouse.json`, and every check
## that existed for it before this file was about DATA: does the blueprint parse,
## does it round-trip through its editor, does the cache share its meshes, does
## the apron pad role resolve to it. `port_perf_cache_test` says so in its own
## header: *"every one of them is green on a building you can see straight
## through"*. None of them asked whether a body can occupy the same metre as a
## wall. That is what this file asks, and it asks it of `PhysicsServer3D`.
##
## THE PATH. `port_layout_graph_visualizer._stamp_apron_pads` is the only place
## in the game that builds a blueprint: it calls `find_for_pad(role, template)`
## and hands the result to `BuildingCache.instance(layout, true)`. So that is the
## call this file makes. It does NOT call `BuildingFitout.build`, which emits a
## collider per brick and which the catalogue path can never reach — `load_path`
## sets `blueprint_id` to the file's basename, and `BuildingCache.instance`
## routes every non-empty id through the prototype stamp instead. Asserting on
## `BuildingFitout` would be REALITY.md §3 exactly: the producer next to the one
## the game runs.
##
## WHAT IT MEASURES, ON THE SHIPPED WAREHOUSE, AT THE TIME OF WRITING:
## `PhysicsServer3D` holds **one** shape for 516 bricks — a 20 x 7 x 12 m box
## spanning **y 3.000..10.000** against a building drawn 0.250..6.750. It is not
## a solid warehouse. It is a slab of air 2.75 m over the roofline of nothing,
## and a 1.8 m capsule marched at all four walls walks through **206 of 206**
## stations, through both doorways, and falls through the floor at 25 of 25
## interior stations. The recorded guess this file was written to settle — "one
## collision box over the whole footprint, so the warehouse is solid to the
## player and its doors admit nobody" — has the first clause right and the
## second exactly backwards.
##
## SIX INSTRUMENT DECISIONS, each forced by a false or vacuous result while this
## file was being built.
##
##  - THE MARCHER IS PROVEN BEFORE IT IS BELIEVED. Every solidity claim here is
##    of the form "the capsule was stopped", and on this blueprint every one of
##    them currently reports "walked through". A sweep that cannot report
##    `blocked` would produce exactly that transcript, so a synthetic
##    `StaticBody3D` is planted well clear of the building and marched at, and
##    its stop distance is asserted against its own known face. Without that, a
##    broken query reads as a hollow building (REALITY.md §8 — the instrument
##    before the subject).
##
##  - THE SHELL IS MEASURED TWICE, BY TWO INSTRUMENTS, BECAUSE A CAPSULE CANNOT
##    SEE A SLOT IT DOES NOT FIT THROUGH. A 0.70 m capsule marched at a wall of
##    0.50 m bricks on a 1.00 m lattice is STOPPED — measured, on the per-brick
##    path — even though half that wall is open air. So the march answers "is a
##    player stopped" and a POINT scan along the same run answers "is the wall
##    continuous", and the two are separate checks with separate numbers. Only
##    the point scan can see the daylight, and only the march can see a player.
##
##  - THE INTERIOR DROP STARTS AT THE DECK, NOT AT THE ROOF. A probe released
##    from mid-height begins inside the footprint box this file exists to
##    measure — the box spans y 3.000..10.000 on a building drawn 0.25..6.75 —
##    and four `began inside` results would have buried the floor, headroom and
##    standing checks on the only fixture there is, the way `probe_piece_tug`'s
##    roof slab buried three checks in `piece_interior_test`. The drop starts
##    0.60 m over the pad, which is where a player enters from.
##
##  - THE DOORWAY IS JUDGED ON THE SILL AND THE HEAD SEPARATELY. "The head
##    clears 1.8 m" is true of this door (2.250 m) and it is not a door a player
##    can use, because its threshold stands 0.750 m off the ground — over the
##    player's 0.45 m step. One number for the opening would have averaged those
##    into a pass.
##
##  - A DOOR IS ASKED BOTH QUESTIONS, SHUT AND OPEN. The first form of the door
##    march demanded a capsule pass a CLOSED doorway, which is the opposite of
##    what `BrickDoor` is for — its `DoorLeafBody` collider is `disabled = open`
##    — so the check would have gone red the day the warehouse got working doors
##    and stayed green on the building that has none. It now marches shut, calls
##    `set_open(true)`, and marches again.
##
##  - THE DOORWAY'S HEAD COLUMNS ARE INSET BY THE PLAYER'S OWN RADIUS. Flush
##    with the declared opening they land on the JAMB POSTS `_add_brick_door`
##    stands 0.07 m inside each edge, and every doorway reported a 0.167 m head
##    — a jamb at ankle height, read as a lintel.
##
## AND ONE VACUITY TRAP THAT IS NAMED RATHER THAN AVOIDED. "An opened door
## admits a 1.8 m figure" PASSES on a building with no collision anywhere
## (REALITY.md §4c — green on the defect). What stops it being a lie is that it
## is never read alone: the door-node count, the shut-door march and the shell
## sweep beside it all go RED at the same time, and the physics head is held
## against the DRAWN head rather than against a bound, so an absent collider
## disagrees with the drawing as loudly as a low one does.

const TestReport := preload("res://tests/support/test_report.gd")

const BLUEPRINT := "warehouse"

## scenes/shared/player.tscn — capsule 1.8 m tall, 0.35 m radius, 0.45 m step.
const CAPSULE_R := 0.35
const STAND_H := 1.8
const KNEE_H := 0.8
const STEP_H := 0.45
const STAND_EPS := 0.03

const MARCH_STEP := 0.04     ## << the 0.50 m a brick is drawn; cannot tunnel
const STATION_STEP := 0.25
const START_OUT := 0.80      ## clear of the drawn face before the march begins
const MARCH_LEN := 1.80
const DOOR_MARCH_LEN := 3.20
const DROP_FROM := 0.60
const DROP_LEN := 1.20
## A capsule centred within a radius of a corner legitimately overlaps the wall
## round the corner. Those stations belong to the other face.
const END_INSET := 0.60
## Shell stations stay this far off a doorway: a capsule straddling a jamb may
## legitimately pass or legitimately catch, and guessing turns a solidity sweep
## into a report about its own arithmetic.
const DOOR_CLEAR := CAPSULE_R + 0.25

const SCAN_STEP := 0.02
const HEAD_SCAN_LO := 0.05
const HEAD_SCAN_HI := 4.00
## How far the physics head may fall short of the drawn head before the two are
## called disagreeing. Float slack and the scan step, nothing more.
const HEAD_SLACK := 0.06

## The heights a standing player's body occupies, sampled where a hole would
## matter. 0.90 is deliberate: it is the mid-course of the brick lattice, and on
## the per-brick path it is a continuous open slot the full length of the wall.
const BODY_HEIGHTS := [0.35, 0.90, 1.50]

const INTERIOR_GRID := 5
const INTERIOR_INSET := 1.5

const CONTROL_AT := Vector3(0.0, 0.9, -60.0)
const CONTROL_SIZE := Vector3(2.0, 2.0, 2.0)

var _t: RefCounted
var _space: PhysicsDirectSpaceState3D
var _drawn := AABB()
var _faces: Array = []
var _doors: Array = []


func _ready() -> void:
	_t = TestReport.new("building_interior_test")
	_space = get_viewport().world_3d.direct_space_state
	await _control()

	var layout := BuildingBlueprintCatalog.by_id(BLUEPRINT)
	if not _t.check("the %s blueprint loads through the catalogue" % BLUEPRINT, layout != null):
		_t.finish(get_tree())
		return
	var bricks := layout.iter_primary_cells().size()
	## Guards every count below against an empty blueprint — `BuildingRules`
	## passes one of those, and a building with no bricks is trivially consistent
	## with every claim in this file.
	if not _t.check("the blueprint carries bricks (%d primary cells)" % bricks, bricks > 0):
		_t.finish(get_tree())
		return

	BuildingCache.clear()
	var building := BuildingCache.instance(layout, true)
	if not _t.check("BuildingCache stamps the blueprint", building != null):
		_t.finish(get_tree())
		return
	add_child(building)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var census := _census(building)
	_drawn = _drawn_bounds(building)
	print("  [stamp] drawn mesh union pos %s size %s" % [str(_drawn.position), str(_drawn.size)])
	print("  [stamp] %d CollisionObject3D, %d shapes on solid bodies, union pos %s size %s"
		% [int(census["objects"]), int(census["shapes"]),
			str((census["union"] as AABB).position), str((census["union"] as AABB).size)])

	await _check_bricks_reach_physics(layout, int(census["shapes"]))
	await _check_stamp_carries_the_fitouts_collision(layout, int(census["shapes"]))
	_check_collision_is_where_the_building_is(census)

	if not _t.check("the stamp draws geometry to measure the shell against (%d meshes)"
			% _drawn_mesh_count(building), _drawn.size.x > 1.0 and _drawn.size.z > 1.0):
		building.queue_free()
		_t.finish(get_tree())
		return
	_faces = _build_faces()
	_doors = _find_doors(layout)

	_check_shell_stops_a_player()
	_check_shell_is_continuous()
	## THE INTERIOR RUNS FIRST BECAUSE THE DOORWAY'S HEAD IS MEASURED OFF THE
	## FLOOR. Scanned from a fixed height instead, the head reads the SOLE
	## underfoot: measured on the per-brick path, every doorway reported a
	## 0.050 m head, which is the floor tile at the threshold and not a lintel.
	await _check_doors(building, _check_interior())

	building.queue_free()
	await get_tree().physics_frame
	_t.finish(get_tree())


# ── The instrument, proven before it is believed ─────────────────────────────

## REALITY.md §8. Every solidity claim below reads "stopped" or "walked
## through", and on this blueprint they all read "walked through". A marcher
## that could never report `blocked` produces the same transcript, so it is
## marched at a body whose face this test put there itself.
func _control() -> void:
	var body := StaticBody3D.new()
	body.name = "MarcherControl"
	var shape_node := CollisionShape3D.new()
	shape_node.name = "ControlBox"
	var box := BoxShape3D.new()
	box.size = CONTROL_SIZE
	shape_node.shape = box
	body.add_child(shape_node)
	body.position = CONTROL_AT
	add_child(body)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var from := CONTROL_AT - Vector3(0.0, 0.0, 3.0)
	var march := _march(from, Vector3(0.0, 0.0, 4.0), _figure(STAND_H))
	## The capsule's leading face meets the box's own −Z face at 3.0 − 1.0 − 0.35.
	var expected := 3.0 - CONTROL_SIZE.z * 0.5 - CAPSULE_R
	_t.check("the marcher reports a body it is walked into (stop %.3f m, expected %.3f)"
		% [float(march["stop_m"]), expected],
		bool(march["blocked"]) and not bool(march["started_inside"])
			and absf(float(march["stop_m"]) - expected) <= MARCH_STEP * 2.0)
	var clear := _march(from + Vector3(20.0, 0.0, 0.0), Vector3(0.0, 0.0, 4.0), _figure(STAND_H))
	_t.check("the marcher reports open air as free",
		not bool(clear["blocked"]) and not bool(clear["started_inside"]))
	## The point scan is the other instrument, and it gets the same treatment.
	_t.check("the point scan sees the control body",
		not _space.intersect_point(_point_at(CONTROL_AT), 1).is_empty())
	_t.check("the point scan sees open air as empty",
		_space.intersect_point(_point_at(CONTROL_AT + Vector3(20.0, 0.0, 0.0)), 1).is_empty())
	body.queue_free()
	await get_tree().physics_frame


# ── 0. Do the bricks reach the physics world at all? ─────────────────────────

## REALITY.md §3d, at the layer that matters. Stamp the blueprint through the
## production call, then stamp it again with every cell deleted, and count the
## shapes `PhysicsServer3D` holds either way. If the two agree, the 516 bricks
## are decoration and nothing below is a claim about the warehouse.
func _check_bricks_reach_physics(layout: BuildingLayout, full_shapes: int) -> void:
	var stripped := BuildingBlueprintCatalog.by_id(BLUEPRINT)
	if not _t.check("the stripped control blueprint loads", stripped != null):
		return
	stripped.cells.clear()
	BuildingCache.clear()
	var bare := BuildingCache.instance(stripped, true)
	add_child(bare)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var bare_shapes := int((_census(bare)["shapes"]) as int)
	bare.queue_free()
	await get_tree().physics_frame
	print("  [strip] shapes in the physics world: as shipped %d, cells deleted %d (+%d)"
		% [full_shapes, bare_shapes, full_shapes - bare_shapes])
	_t.check(
		"deleting every brick removes collision from the stamped building (%d -> %d)"
		% [full_shapes, bare_shapes],
		full_shapes - bare_shapes > 0,
	)
	## And the stronger form of the same property, stated so a single box cannot
	## satisfy it: a building assembled from parts collides as parts. One shape
	## for 516 bricks is one shape for a doorway too.
	##
	## ⚠ THIS CHECK IS BLIND ON ITS OWN AND THE ONE BELOW IT IS WHY IT STAYS.
	## Found by mutation, 2026-08-15 (REALITY.md §8): stub `BuildingCache`'s
	## collider harvest out entirely — no wall, no floor, no roof anywhere in
	## the physics world — and BOTH claims above still PASS, reading
	## `2 -> 0` and `2 shapes for 516 bricks`. The two shapes are the
	## `DoorLeafBody` slabs `BrickDoor` builds per instance, and they are enough
	## to satisfy "more than one" and "more than the empty control". A count of
	## shapes cannot tell a building from two doors hanging in the air. What
	## catches that is `_check_stamp_carries_the_fitouts_collision`.
	_t.check(
		"the stamped building collides as more than one volume (%d shapes for %d bricks)"
		% [full_shapes, layout.iter_primary_cells().size()],
		full_shapes > 1,
	)


## THE PROPERTY THE TWO COUNTS ABOVE WERE GROPING AT, and the only one of the
## three a mutation could not walk past: whatever the fit-out puts in the physics
## world for this blueprint, the CACHE's stamp of it puts there too.
##
## This is the collision twin of `building_cache_visual_test`'s claim, which
## holds the same cache to the same producer per `VisualInstance3D` class — and
## it is stated for the same reason. `BuildingCache` exists to be a cheaper
## `BuildingFitout`; the one thing it may not be is a DIFFERENT one. The single
## footprint box this file was written against was 1 shape where the fit-out
## draws 577.
##
## BOTH SIDES GO THROUGH `PhysicsServer3D` ON A BODY IN THE TREE, not through
## the fit-out's `CollisionShape3D` children — a node with a shape assigned and
## no owner is not collision, and counting nodes would report one (REALITY.md
## §3). The fit-out is therefore added to the tree, which is also the only way
## its `BrickDoor` children build their leaf bodies, so the two censuses are
## taken of the same kind of thing.
##
## WHAT IT CANNOT SEE, said rather than left to be discovered: a defect that
## lands in `BuildingFitout` itself moves both sides together and this stays
## green. That is the same limit `building_cache_visual_test` names, and it is
## why the marches below go at the DRAWN geometry instead of at either producer.
func _check_stamp_carries_the_fitouts_collision(layout: BuildingLayout, stamped: int) -> void:
	var fitout := BuildingFitout.build(layout, true)
	fitout.position = Vector3(0.0, 0.0, 400.0)
	add_child(fitout)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var built := int((_census(fitout)["shapes"]) as int)
	fitout.queue_free()
	await get_tree().physics_frame
	print("  [parity] PhysicsServer3D shapes: BuildingFitout %d, BuildingCache stamp %d"
		% [built, stamped])
	if not _t.check("the fit-out this cache stands in for emits collision at all (%d shapes)"
			% built, built > 0):
		return
	_t.check(
		"the stamp carries every collider the fit-out builds (%d of %d)" % [stamped, built],
		stamped >= built,
	)


# ── 1. What you collide with is where you see it ─────────────────────────────

## REALITY.md §3b. The drawing and the collision are computed by two different
## functions here — `BuildingFitout._add_brick_visual` places meshes cell by
## cell, `BuildingCache._measure_footprint` derives one box from the cell bounds
## — so this is the seam where they are held together. Stated as containment and
## as a shared ground line, never as a size: a box that matched the drawn AABB's
## SIZE while standing 3 m up would satisfy any dimension check.
func _check_collision_is_where_the_building_is(census: Dictionary) -> void:
	var union := census["union"] as AABB
	if not _t.check("the stamped building puts shapes in the physics world (%d)"
			% int(census["shapes"]), int(census["shapes"]) > 0):
		return
	var drawn_floor := _drawn.position.y
	var physics_floor := union.position.y
	var drawn_top := _drawn.position.y + _drawn.size.y
	var physics_top := union.position.y + union.size.y
	print("  [where] drawn y %.3f..%.3f · collision y %.3f..%.3f"
		% [drawn_floor, drawn_top, physics_floor, physics_top])
	_t.check(
		("the collision stands on the ground the building is drawn on "
			+ "(drawn floor %.3f m, collision floor %.3f m, %.3f m apart)")
		% [drawn_floor, physics_floor, absf(physics_floor - drawn_floor)],
		absf(physics_floor - drawn_floor) <= STEP_H,
	)
	_t.check(
		"the collision does not stand over the roof (drawn top %.3f m, collision top %.3f m)"
		% [drawn_top, physics_top],
		physics_top <= drawn_top + STEP_H,
	)


# ── 2. Is the shell solid to a player? ───────────────────────────────────────

func _check_shell_stops_a_player() -> void:
	for figure_variant in [
		{"name": "standing", "height": STAND_H},
		{"name": "kneeling", "height": KNEE_H},
	]:
		var figure := figure_variant as Dictionary
		var height := float(figure["height"])
		var query := _figure(height)
		var stations := 0
		var through := PackedStringArray()
		var stuck := PackedStringArray()
		var elsewhere := PackedStringArray()
		for face_variant in _faces:
			var face := face_variant as Dictionary
			for u in _stations(face):
				stations += 1
				var start := _face_point(face, u) + (face["normal"] as Vector3) * START_OUT
				start.y = STAND_EPS + height * 0.5
				var march := _march(start, -(face["normal"] as Vector3) * MARCH_LEN, query)
				var where := "%s@%.2f" % [str(face["name"]), u]
				if bool(march["started_inside"]):
					stuck.append("%s in %s" % [where, str(march["hit"])])
				elif not bool(march["blocked"]):
					through.append(where)
				elif absf(float(march["stop_m"]) - (START_OUT - CAPSULE_R)) > CAPSULE_R + MARCH_STEP:
					## Stopped, but not by the wall it was marched at — something
					## else stands in the way, and this claim is about the wall.
					elsewhere.append("%s at %.2f m by %s"
						% [where, float(march["stop_m"]), str(march["hit"])])
		print("  [shell] %s: %d stations, %d walked through, %d began inside, %d stopped elsewhere"
			% [str(figure["name"]), stations, through.size(), stuck.size(), elsewhere.size()])
		if not through.is_empty():
			print("  [shell] %s walked through: %s"
				% [str(figure["name"]), ", ".join(_first(through, 6))])
		if not elsewhere.is_empty():
			print("  [shell] %s stopped elsewhere: %s"
				% [str(figure["name"]), ", ".join(_first(elsewhere, 4))])
		_t.check("%s: the sweep covered the shell (%d stations over %d faces)"
			% [str(figure["name"]), stations, _faces.size()], stations >= 100)
		_t.equal("%s: no shell march begins inside a collider (%d)"
			% [str(figure["name"]), stuck.size()], stuck.size(), 0)
		_t.check("%s: a player is stopped by the warehouse wall (%d/%d walked through)"
			% [str(figure["name"]), through.size(), stations], through.is_empty())
		_t.check("%s: what stops the player is the wall itself (%d stopped elsewhere)"
			% [str(figure["name"]), elsewhere.size()], elsewhere.is_empty())


## THE SECOND INSTRUMENT. A 0.70 m capsule cannot fit a 0.50 m slot, so the
## march above is stopped by a wall that is half daylight — measured, on the
## per-brick path, where the point scan below reads a repeating
## `#####.....#####` at 1.00 m pitch. A wall is not "solid enough to stop a
## capsule"; it is either continuous or it is a fence.
func _check_shell_is_continuous() -> void:
	var samples := 0
	var open := 0
	var worst_run := 0.0
	var worst_where := ""
	for face_variant in _faces:
		var face := face_variant as Dictionary
		for height in BODY_HEIGHTS:
			var run := 0.0
			for u in _scan_stations(face):
				samples += 1
				var at := _face_point(face, u) - (face["normal"] as Vector3) * _wall_probe_depth()
				at.y = float(height)
				if _space.intersect_point(_point_at(at), 1).is_empty():
					open += 1
					run += SCAN_STEP
					if run > worst_run:
						worst_run = run
						worst_where = "%s@%.2f y=%.2f" % [str(face["name"]), u, float(height)]
				else:
					run = 0.0
	print("  [wall] %d point samples through the shell at %s m: %d open, longest gap %.3f m (%s)"
		% [samples, str(BODY_HEIGHTS), open, worst_run, worst_where])
	_t.check("the wall scan sampled the shell (%d points)" % samples, samples >= 400)
	_t.check(
		("the wall is continuous at the heights a standing player occupies "
			+ "(%d of %d samples are open air, longest run %.3f m at %s)")
		% [open, samples, worst_run, worst_where if open > 0 else "nowhere"],
		open == 0,
	)


# ── 3. Do the doors admit anyone? ────────────────────────────────────────────

## A DOOR IS NOT A HOLE, AND THE FIRST FORM OF THIS CHECK ASKED FOR ONE.
## It marched a capsule at the closed doorway and demanded it pass — which is
## the OPPOSITE of what a working door does. `BrickDoor` builds a `DoorLeafBody`
## whose collider is `disabled = open`, so a shut door SHOULD stop a player, and
## the check as written would have gone red the day the warehouse got working
## doors and green on the building that has none (REALITY.md §4c, the check that
## passes because something is broken). So the claim is stated as the pair a
## door actually makes: shut, it stops you; opened, it admits you. Neither half
## can be satisfied by a building whose doors are painted on — that building has
## no `BrickDoor` to open, which is the check above them both.
func _check_doors(building: Node, floor_y: float) -> void:
	if not _t.check("the blueprint carries doorways (%d)" % _doors.size(), _doors.size() >= 1):
		return
	var nodes := _door_nodes(building)
	## `BuildingCache._flatten_visuals` copies MESHES and recurses past
	## everything else, so a stamped building keeps the door's leaf and jamb
	## geometry and loses the `BrickDoor` that owns them — along with its
	## interact areas and its collider. Measured: 0 nodes for 2 doorways.
	_t.check("every doorway carries a door a player can open (%d BrickDoor nodes for %d doorways)"
		% [nodes.size(), _doors.size()], nodes.size() >= _doors.size())
	var scan_from := (0.0 if is_nan(floor_y) else floor_y) + HEAD_SCAN_LO
	var plant := (0.0 if is_nan(floor_y) else floor_y) + STAND_EPS + STAND_H * 0.5
	var shut := _door_marches(plant)
	for node in nodes:
		node.call("set_open", true)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var opened := _door_marches(plant)
	print("  [door] marched shut: %d of %d doorways stopped a player · marched open: %d of %d"
		% [shut.size(), _doors.size(), _doors.size() - opened.size(), _doors.size()])
	if not shut.is_empty():
		print("  [door] shut, stopped by: %s" % ", ".join(shut))
	if not opened.is_empty():
		print("  [door] OPEN and still obstructed: %s" % ", ".join(opened))
	_t.check("a shut door stops a player (%d of %d doorways blocked)"
		% [shut.size(), _doors.size()], shut.size() == _doors.size())
	_t.check("an opened door admits a %.2f m figure (%d still obstructed: %s)"
		% [STAND_H, opened.size(), "none" if opened.is_empty() else ", ".join(opened)],
		opened.is_empty())

	var low_head := PackedStringArray()
	var high_sill := PackedStringArray()
	var disagree := PackedStringArray()
	var narrow := PackedStringArray()
	for door_variant in _doors:
		var door := door_variant as Dictionary
		var drawn_sill := float(door["sill"])
		var drawn_head := float(door["head"])
		var opening := drawn_head - drawn_sill
		var physics_head := _physics_head(door, scan_from)
		var physics_width := _physics_clear_width(door)
		print("  [door] %s: drawn sill %.3f m, drawn head %.3f m (opening %.3f m tall, %.3f m wide)"
			% [str(door["name"]), drawn_sill, drawn_head, opening, float(door["width"])])
		print("  [door] %s: physics head %.3f m, physics clear width %.3f m"
			% [str(door["name"]), physics_head, physics_width])
		## THE THRESHOLD. A doorway whose sill stands over the player's step is a
		## window, whatever its head says.
		if drawn_sill > STEP_H:
			high_sill.append("%s sill %.3f m over a %.2f m step"
				% [str(door["name"]), drawn_sill, STEP_H])
		## THE OPENING, sill to head, against the figure everything is sized
		## against. `block_door_double` declares 4 x 3 x 1 CELLS.
		if opening < STAND_H:
			low_head.append("%s opening %.3f m for a %.2f m figure"
				% [str(door["name"]), opening, STAND_H])
		## REALITY.md §4a — the drawing and the physics held against each other,
		## so an ABSENT collider disagrees as loudly as a low one.
		if absf(physics_head - drawn_head) > HEAD_SLACK:
			disagree.append("%s draws its head at %.3f m, physics says %.3f m"
				% [str(door["name"]), drawn_head, physics_head])
		if physics_width < CAPSULE_R * 2.0:
			narrow.append("%s only %.3f m clear" % [str(door["name"]), physics_width])
	_t.check("the doorway's threshold is at the floor (%d too high: %s)"
		% [high_sill.size(), "none" if high_sill.is_empty() else ", ".join(high_sill)],
		high_sill.is_empty())
	_t.check("the doorway admits a %.2f m figure (%d too short: %s)"
		% [STAND_H, low_head.size(), "none" if low_head.is_empty() else ", ".join(low_head)],
		low_head.is_empty())
	_t.check("the doorway's head in physics is the head it draws (%d disagree: %s)"
		% [disagree.size(), "none" if disagree.is_empty() else ", ".join(disagree)],
		disagree.is_empty())
	_t.check("the doorway is wide enough in physics for a player (%d pinched: %s)"
		% [narrow.size(), "none" if narrow.is_empty() else ", ".join(narrow)],
		narrow.is_empty())


## Every `BrickDoor` under the stamp. Found by class rather than by node name:
## `BuildingFitout` names the node "BrickDoor" today, and a name is not a
## guarantee.
func _door_nodes(node: Node) -> Array:
	var out: Array = []
	if node is BrickDoor:
		out.append(node)
	for child in node.get_children():
		out.append_array(_door_nodes(child))
	return out


## Which doorways stop a 1.8 m figure walked at them from outside, planted on
## the floor the interior probe found. Unfiltered: "a player gets through this
## door" is a claim about the whole building, not about one brick.
func _door_marches(plant_y: float) -> PackedStringArray:
	var out := PackedStringArray()
	for door_variant in _doors:
		var door := door_variant as Dictionary
		var face := door["face"] as Dictionary
		var normal := face["normal"] as Vector3
		var start := _face_point(face, float(door["u"])) + normal * START_OUT
		start.y = plant_y
		var march := _march(start, -normal * DOOR_MARCH_LEN, _figure(STAND_H))
		if bool(march["started_inside"]):
			out.append("%s began inside %s" % [str(door["name"]), str(march["hit"])])
		elif bool(march["blocked"]):
			out.append("%s stopped at %.3f m by %s"
				% [str(door["name"]), float(march["stop_m"]), str(march["hit"])])
	return out


## The lowest occupied point over the doorway's walkable column, asked of the
## space state and of nothing else. Walked along the path a player takes through
## the wall, because a lintel is not over the threshold.
##
## THE COLUMNS ARE INSET BY THE PLAYER'S OWN RADIUS. Flush with the declared
## opening they land on the door's JAMB POSTS — `_add_brick_door` stands them
## 0.07 m inside each edge — and every doorway reported a 0.167 m head, which is
## a jamb at ankle height and not a lintel. A player walks between the jambs.
func _physics_head(door: Dictionary, scan_from: float) -> float:
	var face := door["face"] as Dictionary
	var normal := face["normal"] as Vector3
	var lowest := HEAD_SCAN_HI
	var lo := float(door["u_lo"]) + CAPSULE_R
	var hi := float(door["u_hi"]) - CAPSULE_R
	for i in 5:
		var u := lerpf(lo, hi, float(i) / 4.0)
		var base := _face_point(face, u)
		var t := -0.4
		while t <= 1.2:
			var here := base - normal * t
			var y := scan_from
			while y < lowest:
				if not _space.intersect_point(_point_at(Vector3(here.x, y, here.z)), 1).is_empty():
					lowest = y
					break
				y += SCAN_STEP
			t += SCAN_STEP * 5.0
	return lowest


## The widest run of the doorway, along the face's own axis, at which a POINT in
## the wall's mid-plane is in nothing at all. A point rather than a shape: a
## shape's radius would have to be subtracted back out, and this is the one
## measurement that must not carry an arithmetic correction.
func _physics_clear_width(door: Dictionary) -> float:
	var face := door["face"] as Dictionary
	var narrowest := INF
	for band in [0.25, 0.5, 0.75, 0.9]:
		var y := lerpf(float(door["sill"]), float(door["head"]), float(band))
		var best := 0.0
		var run := 0.0
		var u := float(door["u_lo"]) - 0.30
		while u <= float(door["u_hi"]) + 0.30:
			var at := _face_point(face, u) - (face["normal"] as Vector3) * _wall_probe_depth()
			at.y = y
			if _space.intersect_point(_point_at(at), 1).is_empty():
				run += SCAN_STEP
				best = maxf(best, run)
			else:
				run = 0.0
			u += SCAN_STEP
		narrowest = minf(narrowest, best)
	return narrowest


# ── 4. Is the inside enterable and standable? ────────────────────────────────

## Returns the floor the rest of the file measures from, or NAN when there is no
## floor to find. The doorway's head is read off it.
func _check_interior() -> float:
	var stations := _interior_stations()
	if not _t.check("the interior offers stations to probe (%d)" % stations.size(),
			stations.size() >= 16):
		return NAN
	var query := _figure(KNEE_H)
	var surfaces: Array[float] = []
	var landed := 0
	var fell := 0
	var missing := PackedStringArray()
	var stuck := PackedStringArray()
	for station_variant in stations:
		var station := station_variant as Vector3
		var from := Vector3(station.x, DROP_FROM + KNEE_H * 0.5, station.z)
		var drop := _march(from, Vector3.DOWN * DROP_LEN, query)
		if bool(drop["started_inside"]):
			stuck.append("(%.1f, %.1f) in %s" % [station.x, station.z, str(drop["hit"])])
			continue
		if not bool(drop["blocked"]):
			fell += 1
			continue
		landed += 1
		## THE SURFACE IS READ WITH A POINT, NOT WITH THE CAPSULE. A 0.35 m
		## capsule reports the first step at which it OVERLAPS, which on a 0.12 m
		## floor tile is 0.28 m too low, and every clearance downstream would
		## carry that error. A point has no radius — but it also has no width, so
		## it falls between floor tiles where the capsule bridges them, and that
		## difference is a measurement of the floor rather than a fault in it.
		var surface := _point_floor_y(station, DROP_FROM - float(drop["stop_m"]) + MARCH_STEP * 2.0)
		if is_nan(surface):
			missing.append("(%.1f, %.1f)" % [station.x, station.z])
			continue
		surfaces.append(surface)
	print("  [floor] %d stations: %d landed, %d fell through, %d began inside, %d landed with nothing underfoot"
		% [stations.size(), landed, fell, stuck.size(), missing.size()])
	_t.equal("no interior floor probe begins in a collider (%d: %s)"
		% [stuck.size(), "none" if stuck.is_empty() else ", ".join(_first(stuck, 4))],
		stuck.size(), 0)
	## STATED SO THAT "NOBODY GOT AS FAR AS FALLING" CANNOT PASS IT. `fell == 0`
	## alone is green on a run where every probe began inside a collider — which
	## is exactly what the footprint box produces when it is moved down onto the
	## ground, measured.
	_t.check("a player dropped inside the warehouse lands on a floor (%d of %d landed, %d fell through)"
		% [landed, stations.size(), fell], landed == stations.size() and fell == 0)
	## THE FLOOR'S OWN CONTINUITY, and it is the same property the wall scan
	## states about the shell. A capsule bridges a hole narrower than itself, so
	## the drop above cannot see one; a point directly under the figure's feet
	## can. A floor with holes is a floor you can see the pad through.
	## COUNTED FORWARD, not as an absence. `missing.is_empty()` is green on a run
	## where nothing landed and nothing was ever probed — measured, on the
	## shipped stamp, where 25 of 25 fell through and this printed `0 found
	## nothing` and PASSED (REALITY.md §4, the negative against an empty
	## universe).
	_t.check("there is floor directly under every interior station (%d of %d, %d landed on nothing: %s)"
		% [surfaces.size(), stations.size(), missing.size(),
			"none" if missing.is_empty() else ", ".join(_first(missing, 6))],
		surfaces.size() == stations.size())
	if surfaces.is_empty():
		_t.check("the warehouse floor could be measured", false)
		return NAN
	var lo := surfaces[0]
	var hi := surfaces[0]
	for s in surfaces:
		lo = minf(lo, s)
		hi = maxf(hi, s)
	print("  [floor] surface stands at y %.3f..%.3f m over %d probes" % [lo, hi, surfaces.size()])
	_t.check("the floor is the pad the building stands on (y %.3f..%.3f)" % [lo, hi],
		lo > -0.10 and hi < STEP_H)
	_t.check("the floor is level across the warehouse (%.3f m of step)" % (hi - lo),
		hi - lo < 0.10)
	var stand := _figure(STAND_H)
	var obstructed := PackedStringArray()
	for station_variant in stations:
		var station := station_variant as Vector3
		var at := Vector3(station.x, hi + STAND_EPS + STAND_H * 0.5, station.z)
		var name := _hit(at, stand)
		if not name.is_empty():
			obstructed.append("(%.1f, %.1f) in %s" % [station.x, station.z, name])
	_t.check("a %.2f m figure stands inside the warehouse (%d of %d obstructed: %s)"
		% [STAND_H, obstructed.size(), stations.size(),
			"none" if obstructed.is_empty() else ", ".join(_first(obstructed, 4))],
		obstructed.is_empty())
	return hi


# ── Physics ──────────────────────────────────────────────────────────────────

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


func _point_at(position: Vector3) -> PhysicsPointQueryParameters3D:
	var query := PhysicsPointQueryParameters3D.new()
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.collision_mask = 0xFFFFFFFF
	query.position = position
	return query


func _hit(centre: Vector3, query: PhysicsShapeQueryParameters3D) -> String:
	query.transform = Transform3D(Basis.IDENTITY, centre)
	for hit_variant in _space.intersect_shape(query, 8):
		var hit := hit_variant as Dictionary
		var body := hit.get("collider") as CollisionObject3D
		if body == null:
			continue
		var owner: Node = body.shape_owner_get_owner(
			body.shape_find_owner(int(hit.get("shape", -1)))
		) as Node
		return "%s/%s" % [body.name, "?" if owner == null else str(owner.name)]
	return ""


func _march(from: Vector3, motion: Vector3, query: PhysicsShapeQueryParameters3D) -> Dictionary:
	var length := motion.length()
	var steps := maxi(2, int(ceil(length / MARCH_STEP)))
	var out := {"started_inside": false, "blocked": false, "stop_m": length, "hit": ""}
	for i in steps + 1:
		var name := _hit(from + motion * (float(i) / float(steps)), query)
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


## The top of whatever is underfoot, walked DOWN with a POINT from a height the
## capsule drop has already shown to be clear. A point carries no radius and no
## step, so this errs LOW by at most SCAN_STEP — every clearance measured off it
## is pessimistic, never generous. The capsule march cannot do better than its
## own radius: on a 0.12 m floor tile it reports the surface 0.28 m too low.
## NAN, not `from_y`, when the scan reaches the pad without meeting anything.
## Returning the start height would invent a floor at whatever height the drop
## happened to stop at, and the two stations that did that on the per-brick path
## reported a 0.232 m step in a floor that is flat.
func _point_floor_y(station: Vector3, from_y: float) -> float:
	var y := from_y
	while y > -0.40:
		if not _space.intersect_point(_point_at(Vector3(station.x, y, station.z)), 1).is_empty():
			return y
		y -= SCAN_STEP
	return NAN


# ── Geometry, read off the stamp rather than authored here ───────────────────

func _census(root: Node) -> Dictionary:
	var found: Array = []
	_collision_objects(root, found)
	var shapes := 0
	var union := AABB()
	var first := true
	for object_variant in found:
		var object := object_variant as CollisionObject3D
		if not (object is PhysicsBody3D):
			## An Area3D is a trigger, not a wall. `BrickDoor` hangs two of them
			## on every door and counting them as collision would report a
			## doorway as solid.
			continue
		var rid := object.get_rid()
		var count := PhysicsServer3D.body_get_shape_count(rid)
		shapes += count
		for i in count:
			var data: Variant = PhysicsServer3D.shape_get_data(
				PhysicsServer3D.body_get_shape(rid, i)
			)
			var extent := Vector3.ONE
			if data is Vector3:
				extent = (data as Vector3) * 2.0
			var xf: Transform3D = object.global_transform \
				* PhysicsServer3D.body_get_shape_transform(rid, i)
			var box := AABB(xf.origin - extent * 0.5, extent)
			union = box if first else union.merge(box)
			first = false
	return {"objects": found.size(), "shapes": shapes, "union": union}


func _collision_objects(node: Node, out: Array) -> void:
	if node is CollisionObject3D:
		out.append(node)
	for child in node.get_children():
		_collision_objects(child, out)


func _drawn_bounds(node: Node) -> AABB:
	var out := AABB()
	var first := true
	for mi in _meshes(node):
		var aabb: AABB = mi.global_transform * mi.get_aabb()
		out = aabb if first else out.merge(aabb)
		first = false
	return out


func _drawn_mesh_count(node: Node) -> int:
	return _meshes(node).size()


func _meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for child in node.get_children():
		out.append_array(_meshes(child))
	return out


## The four vertical faces of what the building DRAWS. Read off the stamped
## meshes, not off the grid: the claim is "you cannot walk into the wall you can
## see", and the wall you can see is where the meshes are.
func _build_faces() -> Array:
	var lo := _drawn.position
	var hi := _drawn.position + _drawn.size
	return [
		{"name": "-Z", "normal": Vector3(0, 0, -1), "plane": lo.z, "axis": "x",
			"lo": lo.x, "hi": hi.x},
		{"name": "+Z", "normal": Vector3(0, 0, 1), "plane": hi.z, "axis": "x",
			"lo": lo.x, "hi": hi.x},
		{"name": "-X", "normal": Vector3(-1, 0, 0), "plane": lo.x, "axis": "z",
			"lo": lo.z, "hi": hi.z},
		{"name": "+X", "normal": Vector3(1, 0, 0), "plane": hi.x, "axis": "z",
			"lo": lo.z, "hi": hi.z},
	]


func _face_point(face: Dictionary, u: float) -> Vector3:
	if str(face["axis"]) == "x":
		return Vector3(u, 0.0, float(face["plane"]))
	return Vector3(float(face["plane"]), 0.0, u)


## How far inboard of the drawn face the wall's own mid-plane sits. Half a
## brick, read from the catalogue rather than written down here, so the answer
## follows whichever way the cell/size question is settled.
func _wall_probe_depth() -> float:
	return BrickCatalog.size_m("block").z * 0.5


func _stations(face: Dictionary) -> Array[float]:
	var out: Array[float] = []
	var u := float(face["lo"]) + END_INSET
	while u <= float(face["hi"]) - END_INSET:
		if not _near_door(face, u, DOOR_CLEAR):
			out.append(u)
		u += STATION_STEP
	return out


func _scan_stations(face: Dictionary) -> Array[float]:
	var out: Array[float] = []
	var u := float(face["lo"]) + END_INSET
	while u <= float(face["hi"]) - END_INSET:
		if not _near_door(face, u, 0.02):
			out.append(u)
		u += SCAN_STEP
	return out


func _near_door(face: Dictionary, u: float, margin: float) -> bool:
	for door_variant in _doors:
		var door := door_variant as Dictionary
		if str((door["face"] as Dictionary)["name"]) != str(face["name"]):
			continue
		if u >= float(door["u_lo"]) - margin and u <= float(door["u_hi"]) + margin:
			return true
	return false


## Every doorway the blueprint declares, placed by the same call the fitout uses
## so the test cannot disagree with the builder about where a door is
## (REALITY.md §3b). Its EXTENT is the drawn brick, which is the hole a player
## sees.
func _find_doors(layout: BuildingLayout) -> Array:
	var grid := layout.grid()
	var out: Array = []
	for item_variant in layout.iter_primary_cells():
		var item := item_variant as Dictionary
		var brick_id := str(item.get("brick_id", ""))
		if not BrickCatalog.has_tag(brick_id, "door"):
			continue
		var cell := item["cell"] as Vector3i
		var yaw := int(item.get("yaw", 0))
		var centre := BuildingFitout.footprint_center_local(grid, cell, brick_id, yaw)
		var size := BrickCatalog.size_m(brick_id)
		var basis := Basis.from_euler(Vector3(0.0, deg_to_rad(float(yaw)), 0.0))
		var half := (basis * size).abs() * 0.5
		var face := _nearest_face(centre)
		if face.is_empty():
			continue
		var u := centre.x if str(face["axis"]) == "x" else centre.z
		var span := half.x if str(face["axis"]) == "x" else half.z
		out.append({
			"name": "%s %s" % [brick_id, BuildingLayout.cell_key(cell)],
			"face": face,
			"u": u,
			"u_lo": u - span,
			"u_hi": u + span,
			"width": span * 2.0,
			"sill": centre.y - half.y,
			"head": centre.y + half.y,
		})
	return out


func _nearest_face(point: Vector3) -> Dictionary:
	var best: Dictionary = {}
	var closest := INF
	for face_variant in _faces:
		var face := face_variant as Dictionary
		var value := point.x if str(face["axis"]) == "z" else point.z
		var distance := absf(value - float(face["plane"]))
		if distance < closest:
			closest = distance
			best = face
	return best


## A grid spanning the drawn footprint, inset far enough that a station is not
## standing in the wall. Read off the stamp rather than hand-picked, so a change
## to the building moves them with it — and there are 25 of them because four
## were decided by where the floor's own lattice happened to fall: on a floor of
## 0.50 m tiles at 1.00 m pitch, all four landed in gaps and the run reported a
## floor it could not find.
func _interior_stations() -> Array:
	var out: Array = []
	var lo := _drawn.position + Vector3(INTERIOR_INSET, 0.0, INTERIOR_INSET)
	var hi := _drawn.position + _drawn.size - Vector3(INTERIOR_INSET, 0.0, INTERIOR_INSET)
	for i in INTERIOR_GRID:
		for j in INTERIOR_GRID:
			out.append(Vector3(
				lerpf(lo.x, hi.x, float(i) / float(INTERIOR_GRID - 1)),
				0.0,
				lerpf(lo.z, hi.z, float(j) / float(INTERIOR_GRID - 1)),
			))
	return out


func _first(items: PackedStringArray, count: int) -> PackedStringArray:
	var out := PackedStringArray()
	for i in mini(count, items.size()):
		out.append(items[i])
	return out
