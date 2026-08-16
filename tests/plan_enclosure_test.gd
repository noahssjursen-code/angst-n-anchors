extends SceneTree

## Lane A. IS THIS DRAWING A CABIN? Run:
##   xvfb-run -a --server-args="-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy \
##     --script res://tests/plan_enclosure_test.gd
##
## `PlanOutfit.has_cabin` was `return false` for every plan ever drawn, on the
## argument that no primitive DECLARES enclosure since the room was deleted. It
## does not have to: a plan carries walls with positions and extents, decks with
## origins and sizes, and plates with four corners, and whether those close a
## volume is a question about the drawing. `PlanOutfit.enclosure` asks it. This
## file is the check that it answers correctly, and the bar is the one the old
## header set for whatever replaced it.
##
## ── What each section is for ────────────────────────────────────────────────
##
## 1. THE FOUR CASES THE OLD HEADER NAMED. A fence with a gate in it, a ring with
##    a side missing, a real deckhouse, an empty plan. Each is built here from
##    the same eight walls, so the difference between a pass and a fail is one
##    edit to the drawing and nothing else — the fence and the deckhouse differ
##    by ONE deck plate.
##
## 2. THE CLAUSES, one adversarial plan each. Every clause of the criterion is
##    load-bearing only if there is a drawing that fails on that clause alone,
##    and each of these was built to get a wrong `true` out of the reading:
##    a sealed crate (enclosed, no way in), a glazed box (sealed, no way in), a
##    funnel trunk with a scuttle, a crawl space (enclosed, 1.5 m), a locker
##    (enclosed, standable, 0.5 m²), a box hanging in the air with no floor under
##    it, and the same box with a sole added.
##
## 3. THE FLEET. Every shipped `structure_plan_v1` fixture — 18 of the 19 files
##    in `resources/data/structures/`, the nineteenth being `probe_edge_runs`,
##    which is a `structure_edge_runs_v1` document and not a plan at all. The
##    answer is held against an INDEPENDENT measurement rather than against
##    itself: `plan_interior_test`
##    and `piece_interior_test` march a 1.8 m capsule through five of these
##    deckhouses on the real `PhysicsServer3D` body and find floors and doors.
##    Those five must read as cabins here. The bulwark-only fixtures and the spar
##    kit draw no roof over anything and must not.
##
## 4. THE SEAM. `validate()` must publish what `enclosure()` measured, on the
##    PARTITIONED plan — a deckhouse in the sea is not accommodation on this
##    boat — and `has_cabin(null)` must still be false.
##
## Every check here has been shown RED against a deliberately broken
## `PlanOutfit`; the mutants and their scores are in the wave report.
##
## The check count is pinned because a script error aborts the enclosing
## function and lets `_initialize` carry on, so a broken PlanOutfit could report
## ALL PASS having asserted nothing.

const TestReport := preload("res://tests/support/test_report.gd")
const PO := preload("res://scripts/ship/plan_outfit.gd")
const HULL := "hull_28x10"
const EXPECTED_CHECKS := 76

## Fixtures a capsule has been walked through, on the real physics body, by
## `plan_interior_test` / `piece_interior_test`. If enclosure disagrees with
## those, one of the two is wrong and the disagreement is the finding.
const WALKED_INTERIORS: Array[String] = [
	"demo_workboat", "probe_trawler_bulwark", "probe_piece_house",
	"probe_piece_trawler", "probe_piece_tug",
]
## Fixtures that draw no roof over anything: two bulwark runs, a spar kit, six
## diagonal walls and a two-deck junction with no ring under either deck.
const NO_SHELTER: Array[String] = [
	"probe_sheer_bulwark", "probe_sheer_bulwark_flat", "probe_spar_kit",
	"diagonal_axes_probe", "probe_ao_junction",
]

var _t: RefCounted


func _initialize() -> void:
	_t = TestReport.new("plan_enclosure_test")
	_test_the_four_named_cases()
	_test_every_clause_has_a_plan_that_breaks_it()
	_test_the_shipped_fleet()
	_test_a_room_with_no_way_in()
	_test_the_seam()
	if _t.check_count() != EXPECTED_CHECKS:
		_t.check(
			"ran %d checks, expected %d — a check aborted before asserting"
				% [_t.check_count(), EXPECTED_CHECKS],
			false,
		)
	_t.finish(self)


# ── 1. The four cases the old header named ──────────────────────────────────

func _test_the_four_named_cases() -> void:
	print("\n-- the four cases the deleted header named --")

	## THE FENCE. Eight walls, one with a door — the exact shape the brick-era
	## rule `door_n >= 1 or wall_n >= 8` sells as accommodation, and it fires on
	## both halves here.
	var fence := _fence()
	_t.equal("the fence really is eight walls", fence.walls.size(), 8)
	_t.equal("with a door in it", PO.door_count(fence), 1)
	_t.check("eight roofless walls with a gate are not a cabin", not PO.has_cabin(fence))
	_t.check(
		"and it is refused for having no volume, not for having no door: %s"
			% str(PO.enclosure(fence)["why"]),
		str(PO.enclosure(fence)["why"]).contains("closes a volume"),
	)

	## THE DECKHOUSE. The same eight walls and ONE deck plate over four of them.
	var house := _fence()
	house.add_deck(Vector3(1.0, 2.6, 6.0), Vector2(6.0, 6.0))
	_t.check("the same ring with a deck over it IS a cabin", PO.has_cabin(house))
	var report := PO.enclosure(house)
	_t.equal("one compartment, counted", int(report["cabins"]), 1)
	_t.check(
		"and it is the 6 x 6 m room, measured inside its plating (%.2f m2)"
			% float(report["area_m2"]),
		absf(float(report["area_m2"]) - 31.62) < 0.5,
	)
	_t.check("its floor is the deck plane", absf(float(report["floor_y"])) < 0.01)
	_t.check(
		"and its head is the underside of the plate (%.2f m)" % float(report["roof_y"]),
		absf(float(report["roof_y"]) - 2.45) < 0.05,
	)

	## THE MISSING SIDE. Roof and floor and a door, one wall of four deleted.
	var gapped := _fence()
	gapped.walls.remove_at(3)
	gapped.add_deck(Vector3(1.0, 2.6, 6.0), Vector2(6.0, 6.0))
	_t.equal("still seven walls and a roof", gapped.walls.size(), 7)
	_t.check("a ring with one side missing is not a cabin", not PO.has_cabin(gapped))

	## THE EMPTY PLAN — `plan_deployable_test` pins this through apply_plan too.
	_t.check("an empty plan has no cabin", not PO.has_cabin(StructurePlan.new()))
	_t.check("and says so plainly", str(PO.enclosure(StructurePlan.new())["why"]).contains("nothing"))


# ── 2. One adversarial plan per clause ──────────────────────────────────────

func _test_every_clause_has_a_plan_that_breaks_it() -> void:
	print("\n-- a drawing built to defeat each clause --")

	## A WAY IN. A shipping container is enclosed, 2.39 m tall and 14 m² on the
	## floor. What it is not is somewhere you can get into.
	var crate := _fence()
	(crate.walls[0]["openings"] as Array).clear()
	crate.add_deck(Vector3(1.0, 2.6, 6.0), Vector2(6.0, 6.0))
	var crate_report := PO.enclosure(crate)
	_t.check("a sealed crate is not a cabin", not PO.has_cabin(crate))
	_t.check(
		"and the reading knows it is enclosed — it refuses on the way IN: %s"
			% str(crate_report["why"]),
		str(crate_report["why"]).contains("no door opens onto it"),
	)
	_t.check(
		"the enclosed floor is measured all the same (%.2f m2)"
			% float(crate_report["area_m2"]),
		float(crate_report["area_m2"]) > 30.0,
	)
	## ...and putting the door back is the only edit that turns it.
	(crate.walls[0]["openings"] as Array).append({
		"type": "door", "offset": 2.4, "width": 1.2, "height": 2.1, "sill": 0.0,
	})
	_t.check("cutting one door into the same crate makes it a cabin", PO.has_cabin(crate))

	## A WINDOW IS NOT A WAY IN, and it seals the envelope all the same. Both
	## halves matter and they are different questions (`_is_closure` against
	## `_is_way_in`): the glazing below closes the shell — so the compartment is
	## enclosed and says so — and it is not a door, so nobody gets in.
	var glazed := _fence()
	(glazed.walls[0]["openings"] as Array).clear()
	(glazed.walls[0]["openings"] as Array).append({
		"type": "window", "offset": 2.4, "width": 1.2, "height": 0.8, "sill": 1.0,
	})
	glazed.add_deck(Vector3(1.0, 2.6, 6.0), Vector2(6.0, 6.0))
	_t.check("a compartment you can only see into is not a cabin", not PO.has_cabin(glazed))
	_t.check(
		"...and the glazing still sealed it — the refusal is about the way IN: %s"
			% str(PO.enclosure(glazed)["why"]),
		str(PO.enclosure(glazed)["why"]).contains("no door opens onto it"),
	)

	## THE FUNNEL TRUNK that made that distinction necessary: 1.6 x 1.6 m and 5 m
	## tall with a 0.4 m scuttle punched in it. Enclosed, standable, over the
	## 1.2 m² bar — and a scuttle is not a doorway.
	var trunk := StructurePlan.new()
	trunk.hull_id = HULL
	var trunk_face := trunk.add_wall(Vector3(4.0, 0.0, 12.0), "x", 1.6, 5.0)
	trunk.add_wall(Vector3(4.0, 0.0, 13.6), "x", 1.6, 5.0)
	trunk.add_wall(Vector3(4.0, 0.0, 12.0), "z", 1.6, 5.0)
	trunk.add_wall(Vector3(5.6, 0.0, 12.0), "z", 1.6, 5.0)
	trunk.add_deck(Vector3(4.0, 5.0, 12.0), Vector2(1.6, 1.6))
	(trunk_face["openings"] as Array).append({
		"type": "window", "offset": 0.6, "width": 0.4, "height": 0.4, "sill": 1.3,
	})
	_t.check("a funnel trunk with a scuttle in it is not a cabin", not PO.has_cabin(trunk))
	(trunk_face["openings"] as Array)[0] = {
		"type": "door", "offset": 0.2, "width": 1.2, "height": 2.1, "sill": 0.0,
	}
	_t.check("the same trunk with a doorway in it is one", PO.has_cabin(trunk))

	## A HOLE IS NOT A CLOSURE. The same opening declared `hole` leaves the shell
	## open, so there is nothing enclosed to get into in the first place.
	var holed := _fence()
	(holed.walls[0]["openings"] as Array)[0]["type"] = "hole"
	(holed.walls[0]["openings"] as Array)[0]["width"] = 3.0
	holed.add_deck(Vector3(1.0, 2.6, 6.0), Vector2(6.0, 6.0))
	_t.check("a 3 m hole cut in the front is not a door", not PO.has_cabin(holed))

	## HEADROOM. A 1.5 m crawl space under a boat deck is enclosed, floored,
	## roofed and has a door, and nobody lives in it.
	var crawl := _fence()
	for wall in crawl.walls:
		(wall as Dictionary)["height"] = 1.5
	crawl.add_deck(Vector3(1.0, 1.5, 6.0), Vector2(6.0, 6.0))
	_t.check("a 1.5 m crawl space is not a cabin", not PO.has_cabin(crawl))
	_t.check(
		"the same space at 2.0 m is", PO.has_cabin(_room(2.0, 6.0))
	)

	## FLOOR AREA. A 0.7 x 0.7 m standable shaft is a locker, not a compartment.
	_t.check("a 0.7 m square shaft is not a cabin", not PO.has_cabin(_room(2.6, 0.7)))
	_t.check("a 1.6 m square one is", PO.has_cabin(_room(2.6, 1.6)))

	## A FLOOR UNDER IT. Walls and a roof three metres up in the air, with the
	## deck below them and nothing between: a room with no floor, which is the
	## "hole in the deck" a builder would report as a bug.
	var floating := _tier_at(3.0)
	_t.check("a box in the air with no sole under it is not a cabin", not PO.has_cabin(floating))
	var floored := _tier_at(3.0)
	floored.add_deck(Vector3(1.0, 3.0, 6.0), Vector2(6.0, 6.0))
	_t.check("laying a sole under the same box makes it one", PO.has_cabin(floored))
	_t.check(
		"and the compartment is reported at the upper tier, not on the deck",
		absf(float(PO.enclosure(floored)["floor_y"]) - 3.0) < 0.05,
	)

	## THE STATED RESOLUTION LIMIT, asserted rather than left to be discovered.
	## `CABIN_CELL_M` is 0.25 and a solid claims every cell it overlaps, so a slot
	## narrower than two cells reads as closed. This is the check that reddens if
	## anyone changes the constant without changing the header that states it.
	var one_metre_hole := _fence()
	(one_metre_hole.walls[1] as Dictionary)["length"] = 5.0
	one_metre_hole.add_deck(Vector3(1.0, 2.6, 6.0), Vector2(6.0, 6.0))
	_t.check("a 1.0 m hole in a wall leaves it open", not PO.has_cabin(one_metre_hole))
	var half_metre_hole := _fence()
	(half_metre_hole.walls[1] as Dictionary)["length"] = 5.5
	half_metre_hole.add_deck(Vector3(1.0, 2.6, 6.0), Vector2(6.0, 6.0))
	_t.check(
		"a 0.5 m hole does NOT — the documented limit of a %.2f m raster"
			% PO.CABIN_CELL_M,
		PO.has_cabin(half_metre_hole),
	)


# ── 3. The shipped fleet ────────────────────────────────────────────────────

func _test_the_shipped_fleet() -> void:
	print("\n-- every fixture in resources/data/structures --")
	var plans := _fixtures()
	if not _t.check("the fixtures loaded (%d)" % plans.size(), plans.size() >= 18):
		return
	for name in WALKED_INTERIORS:
		if not _t.check("%s is in the fleet" % name, plans.has(name)):
			continue
		var report := PO.enclosure(plans[name] as StructurePlan)
		_t.check(
			"%s: a capsule has been walked through this deckhouse, so it is a cabin (%s)"
				% [name, str(report["why"])],
			bool(report["cabin"]),
		)
		_t.check(
			"%s: and its compartment is standable floor, not a sliver (%.1f m2)"
				% [name, float(report["area_m2"])],
			float(report["area_m2"]) >= 25.0,
		)
	for name in NO_SHELTER:
		if not _t.check("%s is in the fleet" % name, plans.has(name)):
			continue
		_t.check(
			"%s draws no roof over anything and is not a cabin" % name,
			not PO.has_cabin(plans[name] as StructurePlan),
		)


# ── 4a. A room nobody can get into, and a room somebody can ─────────────────
#
# THE FINDING THIS SECTION EXISTS TO HOLD, measured 2026-08-16 and true of the
# tree as it stands: **nothing in the pipeline refuses a sealed room.**
# `critic_barge` draws 25.8 m² of enclosed, standable floor with NO door
# anywhere in the plan, and `PlanOutfit.validate` returns `ok = true` with zero
# errors and zero warnings. The single place the case is visible at all is the
# capability dictionary — `has_cabin = false` beside `cabin_area_m2 = 25.8` —
# and the single consumer of that pair is the `passenger_vessel` licence, which
# is the only rule in `registrations/catalog.json` that names `has_cabin`. Any
# other registration certifies the vessel. So a room a player can see into and
# never enter is a shipping-legal vessel, and these checks pin the ONE thing
# that would otherwise be free to quietly stop being true: that the reading
# still reports the sealed floor as a measurement instead of rounding it off to
# "not a cabin" and dropping the number. If `cabin_area_m2` goes to 0.0 here,
# `structure_studio._capability_advice` silently swaps to the wrong sentence —
# it decides between "draw walls and roof them" and "cut a door" on that number.
#
# `critic_coaster` is the other side of the same coin and is in this file
# because it is the fixture built to prove the kit CAN make a room: the same
# 28 × 10 m hull, a door in the house side onto the port side deck and a second
# into the wheelhouse off the boat deck.
func _test_a_room_with_no_way_in() -> void:
	print("\n-- enclosed air with no way in, and the fixture that fixes it --")
	var plans := _fixtures()

	if _t.check("critic_barge is in the fleet", plans.has("critic_barge")):
		var barge := plans["critic_barge"] as StructurePlan
		var sealed := PO.enclosure(barge)
		_t.equal("critic_barge draws no door at all", PO.door_count(barge), 0)
		_t.check(
			"and it is therefore not a cabin, whatever it encloses",
			not bool(sealed["cabin"]),
		)
		_t.check(
			"but the enclosed floor is MEASURED and published, not dropped (%.1f m2)"
				% float(sealed["area_m2"]),
			float(sealed["area_m2"]) > 20.0,
		)
		_t.check(
			"and the reason says which clause refused it: %s" % str(sealed["why"]),
			str(sealed["why"]).contains("no door opens onto it"),
		)
		## THE SEAM, because the studio's advice is chosen on this number and not
		## on the sentence above it.
		var caps: Dictionary = PO.validate(barge, barge.hull_id)["capabilities"]
		_t.check(
			"validate publishes the sealed area beside has_cabin=false (%.1f m2)"
				% float(caps.get("cabin_area_m2", 0.0)),
			not bool(caps.get("has_cabin", true))
				and float(caps.get("cabin_area_m2", 0.0)) > 20.0,
		)

	if _t.check("critic_coaster is in the fleet", plans.has("critic_coaster")):
		var coaster := plans["critic_coaster"] as StructurePlan
		var report := PO.enclosure(coaster)
		_t.check(
			"critic_coaster IS a cabin — the kit built a room with a way in (%s)"
				% str(report["why"]),
			bool(report["cabin"]),
		)
		_t.equal("house-and-casing plus wheelhouse, two compartments",
			int(report["cabins"]), 2)
		_t.check(
			"and the house is a room, not a locker (%.1f m2)"
				% float(report["area_m2"]),
			float(report["area_m2"]) > 60.0,
		)


# ── 4. The seam ─────────────────────────────────────────────────────────────

func _test_the_seam() -> void:
	print("\n-- what validate() publishes --")
	## `vessel_registration_test` pins this too; it is here because this is the
	## file that owns the function.
	_t.check("has_cabin(null) is false", not PO.has_cabin(null))
	_t.equal("and enclosure(null) says why", str(PO.enclosure(null)["why"]), "no plan")

	var house := _fence()
	house.add_deck(Vector3(1.0, 2.6, 6.0), Vector2(6.0, 6.0))
	house.hull_id = HULL
	var caps: Dictionary = PO.validate(house, HULL)["capabilities"]
	_t.check("validate publishes the cabin", bool(caps.get("has_cabin", false)))
	_t.equal("and its count", int(caps.get("cabins", -1)), 1)
	_t.check(
		"and the area it measured (%.1f m2)" % float(caps.get("cabin_area_m2", 0.0)),
		float(caps.get("cabin_area_m2", 0.0)) > 30.0,
	)

	## THE FENCE, THROUGH THE SAME SEAM — `plan_compliance_test` asserts this
	## capability too, and the two must not be able to drift apart.
	var fence_caps: Dictionary = PO.validate(_fence(), HULL)["capabilities"]
	_t.check("the fence gets no cabin from validate", not bool(fence_caps.get("has_cabin", true)))
	_t.equal("and no cabin count", int(fence_caps.get("cabins", -1)), 0)

	## OFF THE HULL. The same deckhouse, drawn 900 m off the bow. The fence in
	## `off_hull_entities` refuses every entity of it, so nothing is built and
	## there is no cabin — this reads `judged`, not the authored plan.
	var adrift := StructurePlan.new()
	adrift.hull_id = HULL
	for wall in _fence().walls:
		var moved := (wall as Dictionary).duplicate(true)
		var start: Array = moved["start"]
		start[2] = float(start[2]) + 900.0
		adrift.walls.append(moved)
	adrift.add_deck(Vector3(1.0, 2.6, 906.0), Vector2(6.0, 6.0))
	_t.check("the plan on its own draws a cabin", PO.has_cabin(adrift))
	var adrift_caps: Dictionary = PO.validate(adrift, HULL)["capabilities"]
	_t.check(
		"but a deckhouse 900 m off the bow is not accommodation on this boat",
		not bool(adrift_caps.get("has_cabin", true)),
	)


# ── Fixtures ────────────────────────────────────────────────────────────────

## Eight walls with a door in one of them: four round a 6 x 6 m square at
## x 1..7, z 6..12, and four more in a line beside it so the brick-era
## `wall_n >= 8` fires as well as `door_n >= 1`. NO roof.
func _fence() -> StructurePlan:
	var plan := StructurePlan.new()
	plan.hull_id = HULL
	var front := plan.add_wall(Vector3(1.0, 0.0, 6.0), "x", 6.0, 2.6)
	plan.add_wall(Vector3(1.0, 0.0, 12.0), "x", 6.0, 2.6)
	plan.add_wall(Vector3(1.0, 0.0, 6.0), "z", 6.0, 2.6)
	plan.add_wall(Vector3(7.0, 0.0, 6.0), "z", 6.0, 2.6)
	for i in 4:
		plan.add_wall(Vector3(9.0, 0.0, 6.0 + float(i) * 2.0), "x", 2.0, 2.6)
	(front["openings"] as Array).append({
		"type": "door", "offset": 2.4, "width": 1.2, "height": 2.1, "sill": 0.0,
	})
	return plan


## A square room `side` metres across and `height` tall, with a door and a roof,
## standing on the deck plane.
func _room(height: float, side: float) -> StructurePlan:
	var plan := StructurePlan.new()
	plan.hull_id = HULL
	var front := plan.add_wall(Vector3(1.0, 0.0, 6.0), "x", side, height)
	plan.add_wall(Vector3(1.0, 0.0, 6.0 + side), "x", side, height)
	plan.add_wall(Vector3(1.0, 0.0, 6.0), "z", side, height)
	plan.add_wall(Vector3(1.0 + side, 0.0, 6.0), "z", side, height)
	plan.add_deck(Vector3(1.0, height, 6.0), Vector2(side, side))
	(front["openings"] as Array).append({
		"type": "door", "offset": maxf(side * 0.5 - 0.6, 0.0), "width": minf(1.2, side * 0.6),
		"height": minf(2.1, height - 0.3), "sill": 0.0,
	})
	return plan


## A 6 x 6 m walled box with a door and a roof, standing `base` metres up with
## nothing under it.
func _tier_at(base: float) -> StructurePlan:
	var plan := StructurePlan.new()
	plan.hull_id = HULL
	var front := plan.add_wall(Vector3(1.0, base, 6.0), "x", 6.0, 2.6)
	plan.add_wall(Vector3(1.0, base, 12.0), "x", 6.0, 2.6)
	plan.add_wall(Vector3(1.0, base, 6.0), "z", 6.0, 2.6)
	plan.add_wall(Vector3(7.0, base, 6.0), "z", 6.0, 2.6)
	plan.add_deck(Vector3(1.0, base + 2.6, 6.0), Vector2(6.0, 6.0))
	(front["openings"] as Array).append({
		"type": "door", "offset": 2.4, "width": 1.2, "height": 2.1, "sill": 0.0,
	})
	return plan


func _fixtures() -> Dictionary:
	var out := {}
	var dir := DirAccess.open("res://resources/data/structures/")
	if dir == null:
		return out
	for name in dir.get_files():
		if not name.ends_with(".json"):
			continue
		var file := FileAccess.open("res://resources/data/structures/" + name, FileAccess.READ)
		if file == null:
			continue
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		if not (parsed is Dictionary) or not StructurePlan.is_plan(parsed as Dictionary):
			continue
		out[name.trim_suffix(".json")] = StructurePlan.from_dict(parsed as Dictionary)
	return out
