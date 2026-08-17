extends Node

## Lane B (a sibling `.tscn` exists): `HarbourController`, `VesselSpawn` and the
## compliance chain reach autoloads by bare identifier, so `--script` cannot run
## this file. Running it in lane A produces `Identifier not found: WorldGateway`,
## which was once read as a defect in the test and was not (STATE.md, "CORRECTION
## to commit e9de76a"). Check the lane before diagnosing the failure.
##
## ── Why this now reports through TestReport ─────────────────────────────────
## Rewritten 2026-08-14. It kept its own `_failures` array and, on success,
## printed one sentence:
##
##     Vessel registration: legal code, checklists, and lifecycle gates passed
##
## No unit name, no check count, no `NO CHECKS RAN` floor. Two things followed
## from that, and the second is the one that matters:
##
## 1. It spoke a private dialect. The gate matches a verdict by regex and only
##    caught this one on the bare word "passed"; nothing in the log said how much
##    had actually been asserted, so the unit could not be read at a glance next
##    to the rest of the suite.
##
## 2. FOUR of its eight sub-tests began `if entry.is_empty(): return` and
##    contributed ZERO checks when the prebuilt catalogue was empty — and the
##    verdict line did not change shape by one character. That is REALITY.md §4
##    verbatim ("early return on a missing fixture ... then reporting success").
##    Measured against the empty catalogue on 2026-08-10 this file emitted two
##    failures; it should have emitted two failures AND said that four whole
##    sub-tests never ran.
##
## Every early return is now a recorded failure that names the fixture it wanted,
## so a missing fixture is red rather than silent, and the check count moves when
## coverage moves. No assertion was removed or loosened in the rewrite.

const TestReport := preload("res://tests/support/test_report.gd")

## ── THE PREBUILT CATALOGUE IS A DIRECTORY LISTING (REALITY.md §4f) ──────────
##
## `PrebuiltVesselCatalog.catalog_entries()` is `DirAccess` over
## `resources/data/vessels/prebuilt`, and three loops in this file walk what it
## returns. A preset that leaves that directory therefore fails nothing — it
## DELETES the checks that were pointed at it, and the verdict line does not
## change shape by one character.
##
## MEASURED 2026-08-17, not inferred: `bulk_small.json` moved out of that
## directory took this unit from **93 checks to 91, PASS both times**. The
## `for_sale` loop below already had a population floor (`not
## for_sale.is_empty()`) and it did not fire, because a floor sees a collection
## go EMPTY and this one merely got SMALLER — the eighth confirmation of that in
## this repo.
##
## Shape 1 of §4f is the fix here rather than a frozen budget, because the
## per-preset check count moves with any deck edit while the MEMBERSHIP is four
## authored presets and changes almost never: the population is DECLARED below
## and COMPARED against the discovered one, so a failure NAMES the preset that
## went missing instead of reporting that a number moved.
##
## Compared, never iterated in place of the real list. Walking this literal
## instead of the catalogue would be §4c — a lookup that substitutes a default
## for an unknown id would measure one preset twice and stay green.
const PREBUILT_PRESETS := ["28_10_m", "bulk_small", "fishing_trawler", "sjark_15m"]

var _t: TestReport


func _ready() -> void:
	_t = TestReport.new("vessel_registration_test")
	_test_prebuilt_catalogue_population()
	_test_catalog_and_inheritance()
	_test_every_rule_is_answerable_by_both_vocabularies()
	_test_official_fishing_registration()
	_test_fishing_berth_deployment_filter()
	_test_official_starter_catalog()
	_test_stricter_registration_budget()
	_test_nav_light_placement()
	_test_seeded_registration_types()
	_test_deployment_gate()
	_test_off_deck_bricks_are_not_equipment()
	_test_setter_refuses_off_deck()
	_test_loader_trusts_the_record_and_the_grid_pass_catches_it()
	_t.finish(get_tree())


## STATE.md 2b's headline, as a check. Measured at 9912ada, before the fix:
##
##     bricks stored 8, of which OFF-GRID 8
##     VesselCompliance.validate  ok=true  errors []  8/8 legal requirements
##
## A General Vessel with no helm, no navigation lights and no mooring points
## anywhere on it, certified green.
##
## THE CONTROL IS THE HALF THAT MATTERS. These eight cells are legal — they were
## authored for hull_28x10's 20 x 56 deck and are in bounds there — so the same
## eight bricks are asserted to CERTIFY on that hull in the same sub-test. Without
## it this would pass just as well for a rule that refuses helms, or bollards, or
## anything at z=55, and REALITY.md §2's warning about a check that agrees with
## you applies directly: the property is "these bricks are not on THIS deck", not
## "these bricks are bad".
const HEADLINE_CELLS := [
	[Vector3i(5, 1, 55), "helm"],
	[Vector3i(1, 2, 55), "light_nav_port"],
	[Vector3i(8, 2, 55), "light_nav_stbd"],
	[Vector3i(5, 3, 55), "light_nav_white"],
	[Vector3i(2, 0, 55), "bollard"],
	[Vector3i(3, 0, 55), "bollard"],
	[Vector3i(6, 0, 55), "bollard"],
	[Vector3i(7, 0, 55), "bollard"],
]


func _headline_layout(hull_id: String) -> BrickLayout:
	## Written through the deserialiser's raw path, because `set_brick` refuses
	## these cells on the small hull now — which is the point of the other
	## sub-test. A save file can still carry them, so the compliance chain has to
	## refuse them on its own.
	var layout := BrickLayout.new()
	layout.hull_id = hull_id
	for row in HEADLINE_CELLS:
		layout._store_cell(row[0] as Vector3i, str(row[1]), 0)
	return layout


func _test_off_deck_bricks_are_not_equipment() -> void:
	var small := DeckGrid.from_hull(15.0, 5.0, 0.0, 2.0)
	_check(
		small.width == 10 and small.length == 30,
		"the headline's small hull is 10 x 30 cells (got %d x %d)" % [small.width, small.length],
	)
	var layout := _headline_layout("fishing_trawler_small")
	_check(layout.count() == 8, "the headline layout carries all eight required bricks")
	var off := 0
	for row in layout.iter_primary_cells():
		if not small.in_bounds(row["cell"] as Vector3i):
			off += 1
	_check(off == 8, "all eight are off the 10 x 30 deck (%d of 8)" % off)

	var report := VesselCompliance.validate(
		layout, "fishing_trawler_small", "general_vessel", small
	)
	_check(not bool(report.get("ok", true)), "a vessel whose whole outfit is off the deck is refused")
	_check(
		int(report.get("off_grid_bricks", 0)) == 8,
		"the report counts the off-deck bricks (%d)" % int(report.get("off_grid_bricks", -1)),
	)
	## Not counted, so the checklist reads as MISSING rather than as satisfied.
	var passed := 0
	for raw in report.get("checklist", []) as Array:
		if raw is Dictionary and bool((raw as Dictionary).get("ok", false)):
			passed += 1
	_check(
		passed == 0,
		"no legal requirement is met by a brick off the deck (%s)"
		% VesselCompliance.checklist_summary(report),
	)
	_check(
		not bool((report.get("capabilities", {}) as Dictionary).get("has_helm", true)),
		"a helm off the deck is not the vessel's helm",
	)
	## Reported, so the player is told WHY the helm they bought is missing. An
	## off-deck brick is not the same as an absent one and must not read the same.
	var named := false
	for e in report.get("errors", PackedStringArray()):
		if "off the 10 x 30 deck" in str(e) and "Helm" in str(e):
			named = true
	_check(named, "the refusal names the brick, the cell and the deck it missed")

	## THE CONTROL, in two halves.
	##
	## First: the same eight CELLS, unchanged, on hull_28x10's 20 x 56 deck. Zero
	## off-grid there — so what the small hull refused was the deck, not the cells.
	var big_grid := HullRegistry.make_grid("hull_28x10")
	var same_cells := _headline_layout("hull_28x10")
	var same_report := VesselCompliance.validate(
		same_cells, "hull_28x10", "general_vessel", big_grid
	)
	_check(
		int(same_report.get("off_grid_bricks", -1)) == 0,
		"the same eight cells are ON hull_28x10's %d x %d deck" % [big_grid.width, big_grid.length],
	)

	## Second, and this is the half that holds the check in the ACCEPTING
	## direction: the same eight BRICKS, laid out for the wider deck, must
	## certify. They do not certify at the cells above and that is not an
	## off-deck fault — `light_nav_stbd` at x=8 is PORT of centre on a 20-wide
	## hull, so the side rule refuses it. Two different refusals that would
	## otherwise be indistinguishable in one assertion (REALITY.md §4a).
	var legal := BrickLayout.new()
	legal.hull_id = "hull_28x10"
	var mid := big_grid.width / 2
	var stbd := big_grid.width - 2
	for row in [
		[Vector3i(mid, 1, 55), "helm"],
		[Vector3i(1, 2, 55), "light_nav_port"],
		[Vector3i(stbd, 2, 55), "light_nav_stbd"],
		[Vector3i(mid, 3, 55), "light_nav_white"],
		[Vector3i(2, 0, 55), "bollard"],
		[Vector3i(3, 0, 55), "bollard"],
		[Vector3i(stbd - 1, 0, 55), "bollard"],
		[Vector3i(stbd, 0, 55), "bollard"],
	]:
		_check(
			legal.set_brick(big_grid, row[0] as Vector3i, str(row[1]), 0),
			"control fixture places %s on the wide deck" % str(row[1]),
		)
	var legal_report := VesselCompliance.validate(legal, "hull_28x10", "general_vessel", big_grid)
	_check(
		bool(legal_report.get("ok", false)),
		"the same eight bricks certify as a General Vessel when they are on the deck "
		+ "(errors: %s)" % str(legal_report.get("errors")),
	)


func _test_setter_refuses_off_deck() -> void:
	var small := DeckGrid.from_hull(15.0, 5.0, 0.0, 2.0)
	var layout := BrickLayout.new()
	_check(
		layout.set_brick(small, Vector3i(3, 0, 20), "bollard", 0),
		"set_brick accepts a cell on the deck",
	)
	_check(
		not layout.set_brick(small, Vector3i(19, 0, 55), "bollard", 0),
		"set_brick refuses a cell off the deck",
	)
	_check(
		not layout.set_brick(small, Vector3i(-4, 0, -9), "bollard", 0),
		"set_brick refuses a negative cell",
	)
	_check(
		not layout.set_brick(null, Vector3i(3, 0, 21), "bollard", 0),
		"set_brick refuses when no deck is named at all",
	)
	_check(layout.count() == 1, "a refused set_brick stores nothing (%d cells)" % layout.count())

	## `in_bounds` vs `has_deck_cell`, stated as the property that picks between
	## them: a bow HALF cell carries a diagonal aimed outboard and nothing else.
	## `in_bounds` alone would refuse the first; `has_deck_cell` alone would accept
	## the second, which draws a whole cube over the water.
	var half := Vector3i(-1, 0, 0)
	for iz in range(small.length):
		for ix in range(small.width):
			if small.is_partial_bow_cell(Vector3i(ix, 0, iz)):
				half = Vector3i(ix, 0, iz)
				break
		if half.x >= 0:
			break
	_check(half.x >= 0, "the tapered hull has a bow half cell to test against")
	if half.x >= 0:
		var bow := BrickLayout.new()
		_check(
			bow.set_brick(small, half, "block_45", small.partial_bow_yaw_degrees(half)),
			"a diagonal brick aimed outboard is accepted on a bow half cell",
		)
		_check(
			not bow.set_brick(small, half, "block", 0),
			"a square block is refused on the same bow half cell",
		)
		_check(
			not bow.set_brick(small, half, "block_45", small.partial_bow_yaw_degrees(half) + 90),
			"a diagonal aimed the wrong way is refused on the same cell",
		)

	## THE SAME QUESTION ASKED OF THE OTHER SETTER ON THIS CLASS. `add_container_pad`
	## read `if grid != null and not grid.has_deck_cell(c)`, so a null grid skipped
	## its deck check outright and wrote the pad anyway. Nothing in the gate called
	## it at all — the three tests that mention container pads all assign
	## `layout.container_pads` directly — so the hole was invisible from both ends.
	var pads := BrickLayout.new()
	var span := ContainerUnit.DEFAULT_FOOTPRINT
	_check(
		pads.add_container_pad(
			Vector3i(2, 0, 12), Vector3i(2 + span.x - 1, 0, 12 + span.y - 1), small
		),
		"add_container_pad accepts a span on the deck",
	)
	_check(
		not pads.add_container_pad(
			Vector3i(2, 0, 40), Vector3i(2 + span.x - 1, 0, 40 + span.y - 1), small
		),
		"add_container_pad refuses a span off the deck",
	)
	_check(
		not pads.add_container_pad(
			Vector3i(2, 0, 40), Vector3i(2 + span.x - 1, 0, 40 + span.y - 1), null
		),
		"add_container_pad refuses when no deck is named at all",
	)
	_check(
		pads.container_pads.size() == 1,
		"only the on-deck pad was stored (%d pads)" % pads.container_pads.size(),
	)


## PINS A DELIBERATE HOLE RATHER THAN CLOSING IT, and says which hole.
##
## `BrickLayout.set_brick` refuses an off-deck cell; `BrickLayout.from_dict` does
## not, takes no grid, and is documented as trusting the record on purpose —
## dropping a player's bricks on load destroys their vessel to repair a file, and
## the loader runs before anyone has said which hull the layout is going onto.
## That reasoning is sound and this sub-test does not argue with it.
##
## What it does is stop the hole being REDISCOVERED as a surprise. Three sentences,
## in the order a maintainer meets them:
##
##   1. the loader keeps every cell, including the ones the setter refuses;
##   2. a `from_dict` -> `to_dict` round trip with nothing in between re-saves them
##      unchanged — so a tool that loads, edits and saves never learns the record
##      is wrong, and the fault first surfaces at fit-out, on a different day;
##   3. the check that REPLACES the loader's is `VesselCompliance.validate` against
##      the grid the layout is actually being put on, plus
##      `DeckFitout.placement_faults` for the engine-log half.
##
## Sentence 2 is the defect. It is pinned, not fixed, so that anyone who decides
## the loader should refuse after all has to come here and rewrite this paragraph
## instead of quietly turning a green check red — and anyone who assumed the round
## trip was already validated finds out here rather than from a player.
##
## MUTATION-VERIFIED, AND THE FIRST ATTEMPT WAS A NO-OP — which is a finding
## about the subject, not about the check (REALITY.md §8). Making `from_dict`
## filter its cells through `HullRegistry.make_grid(layout.hull_id)` — the obvious
## "let the loader judge" fix — left this file at PASS (93), because the record's
## own `hull_id` resolves to a 20 x 56 deck on which all eight of these cells are
## in bounds. A loader that consults the layout's own claim about which hull it is
## for would not have caught the headline vessel either; that is the same argument
## `BrickLayout.set_brick`'s header makes for taking the grid as a parameter, and
## it is asserted below rather than left as prose.
##
## The two that do redden, both on the shape the pin is about — a layer silently
## judging a cell between load and save:
##
##   `from_dict` sanitises against a 10 x 30 grid   11 of 87 red
##   `to_dict` drops everything above y=0 on save    1 of 93 red
##
## The first takes the file's check COUNT down as well as its verdict: four
## sub-tests run off shipped fixtures that would stop loading, and this file
## records an absent fixture as a failure rather than a silent skip.
func _test_loader_trusts_the_record_and_the_grid_pass_catches_it() -> void:
	var small := DeckGrid.from_hull(15.0, 5.0, 0.0, 2.0)
	var cells := {}
	for row in HEADLINE_CELLS:
		cells[BrickLayout.cell_key(row[0] as Vector3i)] = {
			"brick_id": str(row[1]), "yaw": 0,
		}
	var record := {"hull_id": "fishing_trawler_small", "cells": cells}

	var authored := BrickLayout.new()
	var accepted := 0
	for row in HEADLINE_CELLS:
		if authored.set_brick(small, row[0] as Vector3i, str(row[1]), 0):
			accepted += 1
	_check(
		accepted == 0,
		"the setter refuses every cell in this record (%d of %d accepted)"
		% [accepted, HEADLINE_CELLS.size()],
	)

	var loaded := BrickLayout.from_dict(record)
	_check(
		loaded.count() == HEADLINE_CELLS.size(),
		"the LOADER keeps all %d of them — it takes no grid and judges nothing (%d kept)"
		% [HEADLINE_CELLS.size(), loaded.count()],
	)
	## The round trip, stated cell by cell rather than by comparing two
	## dictionaries: a save that survives a load unchanged is what makes the hole
	## reachable, and "the sizes matched" would not have said that.
	var round_tripped := (BrickLayout.from_dict(loaded.to_dict())).to_dict()
	var re_saved: Dictionary = round_tripped.get("cells", {})
	var identical := re_saved.size() == cells.size()
	for key in cells.keys():
		var was: Dictionary = cells[key]
		var now: Dictionary = re_saved.get(key, {})
		if str(now.get("brick_id", "")) != str(was.get("brick_id", "")):
			identical = false
		if int(now.get("yaw", -1)) != int(was.get("yaw", 0)):
			identical = false
	_check(
		identical,
		"and a from_dict -> to_dict round trip re-saves all %d unchanged: NOTHING between load and save judges a cell (%d cells came back)"
		% [cells.size(), re_saved.size()],
	)

	## What does judge, and it needs the grid the caller names, not the one the
	## record claims: `record.hull_id` resolves to a 20 x 56 deck on which every
	## one of these cells IS in bounds.
	var claimed := HullRegistry.make_grid(str(record["hull_id"]))
	var on_claimed := 0
	for row in HEADLINE_CELLS:
		if claimed.in_bounds(row[0] as Vector3i):
			on_claimed += 1
	_check(
		on_claimed == HEADLINE_CELLS.size(),
		"the record's OWN hull_id would have cleared every cell (%d of %d) — which is why the caller states the deck"
		% [on_claimed, HEADLINE_CELLS.size()],
	)
	var report := VesselCompliance.validate(
		loaded, "fishing_trawler_small", "general_vessel", small
	)
	_check(
		int(report.get("off_grid_bricks", 0)) == HEADLINE_CELLS.size(),
		"the compliance pass against the REAL deck catches all %d (%d)"
		% [HEADLINE_CELLS.size(), int(report.get("off_grid_bricks", -1))],
	)
	_check(
		DeckFitout.placement_faults(small, loaded).size() == HEADLINE_CELLS.size(),
		"and the fit-out names all %d in the engine log (%d)"
		% [HEADLINE_CELLS.size(), DeckFitout.placement_faults(small, loaded).size()],
	)


## The fixture four sub-tests are built on. Returning it silently when it is
## missing is what let those sub-tests evaporate; every caller now records a
## failure naming itself, so an absent trawler costs four visible checks rather
## than four invisible skips.
func _require_trawler(who: String) -> Dictionary:
	var entry := _official_trawler()
	_check(
		not entry.is_empty(),
		"%s has the official trawler fixture to run against" % who,
	)
	return entry


func _test_catalog_and_inheritance() -> void:
	var ids := VesselRegistrationCatalog.ids()
	for required in [
		"general_vessel", "fishing_vessel", "cargo_vessel", "passenger_vessel"
	]:
		_check(ids.has(required), required + " exists")
	var general := VesselRegistrationCatalog.resolved_registration("general_vessel")
	var fishing := VesselRegistrationCatalog.resolved_registration("fishing_vessel")
	_check(
		(fishing.get("rules", []) as Array).size() > (general.get("rules", []) as Array).size(),
		"fishing inherits general-vessel legal code",
	)
	_check(
		HarbourDeploy.terminal_families_for_registration("fishing_vessel") \
				== PackedStringArray(["fishing"]),
		"fishing vessels deploy only at fishing berths",
	)


## STATE.md 2f, as a standing property rather than a count.
##
## A vessel a player owns arrives by one of TWO paths — bricks stacked in the
## shipyard, or a `structure_plan_v1` document drawn in Structure Studio — and
## both end at the same registration. So a rule that only ONE of them can
## address is a rule that certifies one kind of boat and refuses the other
## whatever is fitted to it. That is what `port_light` was: `brick_count
## light_nav_port` names a brick id, no catalogue part carried it, and a plan
## failed five of `general_vessel`'s eight rules no matter how it was outfitted.
##
## Nothing in the gate asked the question, which is why it sat. This asks it of
## EVERY rule of EVERY registration, and the control below is the half that
## matters: a made-up tag must be reported unanswerable, or this loop is only
## saying that dictionaries have keys.
func _test_every_rule_is_answerable_by_both_vocabularies() -> void:
	var reg_ids := VesselRegistrationCatalog.ids()
	_check(reg_ids.size() >= 5, "there are registrations to survey (%d)" % reg_ids.size())
	var rules := 0
	var one_sided := PackedStringArray()
	var why: Dictionary = {}
	for reg_id_raw in reg_ids:
		var reg_id := str(reg_id_raw)
		for raw in VesselRegistrationCatalog.resolved_registration(reg_id).get("rules", []) as Array:
			if not (raw is Dictionary):
				continue
			rules += 1
			var answer := _answerable(raw as Dictionary)
			if not (bool(answer["brick"]) and bool(answer["plan"])):
				var name := "%s/%s" % [reg_id, str((raw as Dictionary).get("id", ""))]
				one_sided.append(name)
				why[name] = str(answer["why"])
	one_sided.sort()
	_check(rules >= 51, "every resolved rule was surveyed (%d)" % rules)
	## NO SHIPPED RULE IS ONE-SIDED. It was `passenger_vessel/cabin` until
	## 2026-08-16: `PlanOutfit.has_cabin` was `return false` for every plan, so a
	## licence the owner's premise depends on — players build their own ships —
	## was closed to every ship a player could draw. It is measured off the
	## geometry now (`PlanOutfit.enclosure`), and the equality below is what makes
	## this check able to catch the NEXT one: an empty set reddens the moment a
	## rule joins it, where "at most one" would absorb it.
	_check(
		one_sided.is_empty(),
		"no shipped rule is answerable by only one build path: %s" % (
			"none" if one_sided.is_empty() else " · ".join(one_sided)
		)
	)
	## The pin that outlived the gap. A null plan is not a drawing, so it draws no
	## cabin — the one thing about `has_cabin` that was true before the reading
	## existed and is still true after it.
	_check(
		not PlanOutfit.has_cabin(null),
		"and has_cabin(null) is still false — nothing draws a cabin out of nothing",
	)
	## The half that has teeth: a plan that DOES draw one says so, so the line
	## above is not passing because the answer is hardcoded again.
	var cabin_plan := StructurePlan.new()
	cabin_plan.hull_id = "hull_28x10"
	var cabin_front := cabin_plan.add_wall(Vector3(1.0, 0.0, 6.0), "x", 6.0, 2.6)
	cabin_plan.add_wall(Vector3(1.0, 0.0, 12.0), "x", 6.0, 2.6)
	cabin_plan.add_wall(Vector3(1.0, 0.0, 6.0), "z", 6.0, 2.6)
	cabin_plan.add_wall(Vector3(7.0, 0.0, 6.0), "z", 6.0, 2.6)
	cabin_plan.add_deck(Vector3(1.0, 2.6, 6.0), Vector2(6.0, 6.0))
	(cabin_front["openings"] as Array).append({
		"type": "door", "offset": 2.4, "width": 1.2, "height": 2.1, "sill": 0.0,
	})
	_check(
		PlanOutfit.has_cabin(cabin_plan),
		"...and a drawn deckhouse with a door in it does report one",
	)
	## THE CONTROL. Three rules that really are one-sided or unanswerable, so the
	## loop above is known to be capable of saying no.
	_check(
		not bool(_answerable({"kind": "tag_count", "tag": "tag_of_the_gods"})["plan"]),
		"control: a tag nothing carries is unanswerable by a plan",
	)
	_check(
		not bool(_answerable({"kind": "tag_count", "tag": "tag_of_the_gods"})["brick"]),
		"control: and unanswerable by a brick layout",
	)
	_check(
		not bool(_answerable({"kind": "brick_count", "brick_id": "light_nav_port"})["plan"]),
		"control: the OLD sidelight rule is still one-sided if anyone writes it again",
	)
	_check(
		bool(_answerable({"kind": "brick_count", "brick_id": "light_nav_port"})["brick"]),
		"control: ...and the brick path still answers it, which is why it looked fine",
	)


## Can each build path produce equipment that ADDRESSES this rule at all? This
## is not "does the rule pass" — it is "is there anything in this vocabulary the
## rule could be talking about".
##
## A `max`-only ceiling (`equipment_rating_max`) and the measured kinds
## (`cargo_cells`, `metric_range`, `capability`) are answered off geometry both
## paths produce, so they are answerable by construction.
func _answerable(rule: Dictionary) -> Dictionary:
	var kind := str(rule.get("kind", ""))
	match kind:
		"brick_count", "brick_side":
			var bid := str(rule.get("brick_id", ""))
			return {
				"brick": BrickCatalog.has(bid), "plan": PartCatalog.has(bid),
				"why": "brick id \"%s\"" % bid,
			}
		"tag_count", "tag_side":
			var tag := str(rule.get("tag", ""))
			return {
				"brick": _any_brick_tagged(tag), "plan": _any_part_tagged(tag),
				"why": "tag \"%s\"" % tag,
			}
		"slot_count":
			var slot := str(rule.get("slot", ""))
			return {
				"brick": _any_brick_in_slot(slot), "plan": _any_part_in_slot(slot),
				"why": "outfit slot \"%s\"" % slot,
			}
		"capacity":
			var field := str(rule.get("field", ""))
			return {
				"brick": _any_brick_with_capacity(field), "plan": _any_part_with_capacity(field),
				"why": "capacity field \"%s\"" % field,
			}
		"white_above_sidelights":
			## Three tags, and every one of them has to be carriable on both sides
			## or the height can never be measured.
			var brick_ok := true
			var plan_ok := true
			for tag in ["nav_white", "nav_port", "nav_stbd"]:
				brick_ok = brick_ok and _any_brick_tagged(tag)
				plan_ok = plan_ok and _any_part_tagged(tag)
			return {"brick": brick_ok, "plan": plan_ok, "why": "nav_white/nav_port/nav_stbd"}
		"capability":
			var cap := str(rule.get("capability", ""))
			## Every capability the evaluator reads is measured off geometry both
			## paths produce. `has_cabin` was the exception until 2026-08-16 —
			## hardcoded false on the plan side — and was excluded here by name;
			## `PlanOutfit.enclosure` measures it now, so the exception is gone
			## rather than moved.
			return {
				"brick": true, "plan": true,
				"why": "capability \"%s\" (measured off geometry on both paths)" % cap,
			}
	return {"brick": true, "plan": true, "why": "measured off geometry"}


func _any_brick_tagged(tag: String) -> bool:
	for brick_id in BrickCatalog.BRICKS.keys():
		if BrickCatalog.has_tag(str(brick_id), tag):
			return true
	return false


func _any_part_tagged(tag: String) -> bool:
	for part_id in PartCatalog.ids():
		if PartCatalog.has_tag(str(part_id), tag):
			return true
	return false


func _any_brick_in_slot(slot: String) -> bool:
	for brick_id in BrickCatalog.BRICKS.keys():
		if VesselCompliance.outfit_slot_for_brick(str(brick_id)) == slot:
			return true
	return false


func _any_part_in_slot(slot: String) -> bool:
	for part_id in PartCatalog.ids():
		if PartCatalog.outfit_slot_of(str(part_id)) == slot:
			return true
	return false


func _any_brick_with_capacity(field: String) -> bool:
	for brick_id in BrickCatalog.BRICKS.keys():
		if int((BrickCatalog.BRICKS[brick_id] as Dictionary).get(field, 0)) != 0:
			return true
	return false


func _any_part_with_capacity(field: String) -> bool:
	for part_id in PartCatalog.ids():
		if int(PartCatalog.compliance_of(str(part_id)).get(field, 0)) != 0:
			return true
	return false


func _official_trawler() -> Dictionary:
	for entry in PrebuiltVesselCatalog.catalog_entries():
		if str(entry.get("prebuilt_id", "")) == "fishing_trawler":
			return entry
	return {}


func _test_official_fishing_registration() -> void:
	var entry := _official_trawler()
	_check(not entry.is_empty(), "official trawler survives catalog compliance gate")
	if entry.is_empty():
		_check(false, "official fishing registration ran its remaining seven checks")
		return
	_check(not bool(entry.get("is_draft", true)), "certified trawler is not a draft")
	var hull_id := str(entry.get("hull_id", ""))
	var report := VesselCompliance.validate(
		BrickLayout.from_dict(entry.get("prebuilt_layout", {}) as Dictionary),
		hull_id,
		str(entry.get("registration_id", "")),
		HullRegistry.make_grid(hull_id),
	)
	_check(bool(report.get("ok", false)), "official trawler is certified fishing vessel")
	_check((report.get("checklist", []) as Array).size() >= 10, "inherited checklist is visible")
	var bollard_item := {}
	for raw in report.get("checklist", []) as Array:
		if raw is Dictionary and str((raw as Dictionary).get("id", "")) == "mooring_points":
			bollard_item = raw
			break
	_check(not bollard_item.is_empty(), "general code requires mooring points")
	_check(bool(bollard_item.get("ok", false)), "official trawler meets the four-mooring minimum")
	_check(BrickCatalog.has("railing_mooring"), "railing with mooring bit exists")
	_check(
		BrickCatalog.has_tag("railing_mooring", "railing")
		and BrickCatalog.has_tag("railing_mooring", "mooring"),
		"railing_mooring is both railing and mooring gear",
	)


func _test_fishing_berth_deployment_filter() -> void:
	var record := _require_trawler("the fishing-berth deployment filter")
	if record.is_empty():
		return
	var harbour := HarbourController.new()
	harbour.setup("test-port")
	var cargo := QuayBerthSlot.new()
	cargo.setup("berth:cargo", "cargo", "general", PackedStringArray(["provisions"]), 100.0, 20.0)
	var fishing := QuayBerthSlot.new()
	fishing.setup("berth:fishing", "fishing", "fishing", PackedStringArray(["fresh_groundfish"]), 100.0, 20.0)
	harbour.register_berth(cargo)
	harbour.register_berth(fishing)
	var slots := HarbourDeploy.free_slots_for(harbour, record)
	_check(slots.size() == 1, "trawler has exactly one compatible berth")
	_check(not slots.is_empty() and slots[0] == fishing, "trawler rejects a general-cargo quay")
	harbour.unregister_all()
	cargo.free()
	fishing.free()
	harbour.free()

## The declared population, compared against the discovered one. See
## `PREBUILT_PRESETS` for why this is a comparison and not a budget.
##
## BOTH DIRECTIONS, because either one silences checks: a preset that leaves the
## directory takes its `for_sale` pair and any per-entry checks with it, and a
## preset that arrives brings checks nobody declared. The sale list is asserted
## separately from the catalogue because `for_sale_entries()` is
## `catalog_entries(false)` — flipping `draft` to true in an authored JSON drops
## a preset out of the sale loop while leaving it in the directory, which the
## catalogue comparison alone would not see.
func _test_prebuilt_catalogue_population() -> void:
	var catalogued := PackedStringArray()
	for entry in PrebuiltVesselCatalog.catalog_entries():
		catalogued.append(str(entry.get("prebuilt_id", "")))
	var for_sale := PackedStringArray()
	for entry in PrebuiltVesselCatalog.for_sale_entries():
		for_sale.append(str(entry.get("prebuilt_id", "")))
	for declared_raw in PREBUILT_PRESETS:
		var declared := str(declared_raw)
		_check(
			catalogued.has(declared),
			"prebuilt preset '%s' is still in the catalogue — the loops in this" % declared
			+ " file walk a directory listing, so its absence DELETES checks"
			+ " rather than failing them (%d found: %s)"
			% [catalogued.size(), ", ".join(catalogued)],
		)
		_check(
			for_sale.has(declared),
			"prebuilt preset '%s' is still on the Shipwright's sale list, so the" % declared
			+ " two checks this file runs over each sale entry still run"
			+ " (%d for sale: %s)" % [for_sale.size(), ", ".join(for_sale)],
		)
	var undeclared := PackedStringArray()
	for found in catalogued:
		if not PREBUILT_PRESETS.has(str(found)):
			undeclared.append(str(found))
	_check(
		undeclared.is_empty(),
		"every preset on disk is named in PREBUILT_PRESETS, so a new one arrives"
		+ " with its coverage declared instead of silently unwalked (%d undeclared: %s)"
		% [undeclared.size(), ", ".join(undeclared)],
	)


func _test_official_starter_catalog() -> void:
	var found_starter := false
	for entry in PrebuiltVesselCatalog.catalog_entries():
		if str(entry.get("prebuilt_id", "")) != "28_10_m":
			continue
		found_starter = true
		_check(not bool(entry.get("is_draft", true)), "28×10 m cargo starter is certified")
		_check(bool(entry.get("compliance_ok", false)), "28×10 m cargo starter passes compliance")
		_check(not entry.get("prebuilt_layout", {}).is_empty(), "starter keeps its brick layout")
		break
	_check(found_starter, "28×10 m starter stays in the authoring catalog")
	## The loop below contributes nothing over an empty sale list, and an empty
	## sale list is exactly the state STATE.md calls "no starter vessel for any
	## new player" — so the emptiness is asserted, not iterated over (REALITY.md
	## §4, "negatives against an empty universe").
	var for_sale := PrebuiltVesselCatalog.for_sale_entries()
	_check(not for_sale.is_empty(), "the Shipwright has something to sell")
	for sale in for_sale:
		_check(
			not bool(sale.get("is_draft", false)),
			"Shipwright sale list excludes drafts",
		)
		_check(
			bool(sale.get("compliance_ok", false)),
			"Shipwright sale list is compliance-certified",
		)


func _test_stricter_registration_budget() -> void:
	var hull_budget := VesselOutfit.budget_for_hull("hull_90x24")
	var registration := VesselRegistrationCatalog.resolved_registration("cargo_vessel")
	var effective := VesselOutfit.budget_for_hull(
		"hull_90x24", registration.get("budget_caps", {}) as Dictionary
	)
	_check(
		int(effective.get("cargo_cells", 0)) == 600
			and int(hull_budget.get("cargo_cells", 0)) > int(effective.get("cargo_cells", 0)),
		"registration cargo maximum tightens a larger physical hull",
	)
	_check(int(effective.get("fishing", -1)) == 0, "cargo registration forbids fishing gear")
	_check(
		not VesselCompliance.brick_allowed_for_registration(
			"cargo_vessel", "hull_90x24", "trommel_small"
		),
		"trommel is not placeable on a cargo vessel",
	)
	_check(
		VesselCompliance.brick_allowed_for_registration(
			"fishing_vessel", "hull_90x24", "trommel_small"
		),
		"trommel remains placeable on a fishing vessel",
	)


func _test_nav_light_placement() -> void:
	var entry := _require_trawler("the port/starboard nav-light check")
	if entry.is_empty():
		return
	var layout_dict := (entry.get("prebuilt_layout", {}) as Dictionary).duplicate(true)
	var cells := layout_dict.get("cells", {}) as Dictionary
	for key in cells.keys():
		var item := cells[key] as Dictionary
		var light_id := str(item.get("light_id", ""))
		if light_id == "light_nav_port":
			item["light_id"] = "light_nav_stbd"
		elif light_id == "light_nav_stbd":
			item["light_id"] = "light_nav_port"
	var report := VesselCompliance.validate(
		BrickLayout.from_dict(layout_dict),
		str(entry.get("hull_id", "")),
		"fishing_vessel",
		HullRegistry.make_grid(str(entry.get("hull_id", ""))),
	)
	_check(not bool(report.get("ok", true)), "swapped port/starboard lights fail registration")


func _test_seeded_registration_types() -> void:
	var entry := _require_trawler("the seeded registration-type checks")
	if entry.is_empty():
		return
	var hull_id := str(entry.get("hull_id", ""))
	var original := entry.get("prebuilt_layout", {}) as Dictionary
	for registration_id in ["general_vessel", "cargo_vessel"]:
		var report := VesselCompliance.validate(
			BrickLayout.from_dict(original), hull_id, registration_id, HullRegistry.make_grid(hull_id)
		)
		_check(
			not bool(report.get("ok", true)),
			registration_id + " rejects fishing gear on a trawler layout",
		)
	var passenger := BrickLayout.from_dict(original)
	passenger.container_pads.clear()
	var fishing_cells: Array[Vector3i] = []
	for item in passenger.iter_primary_cells():
		var brick_id := str(item.get("brick_id", ""))
		if VesselCompliance.outfit_slot_for_brick(brick_id) == "fishing":
			fishing_cells.append(item["cell"] as Vector3i)
	for cell in fishing_cells:
		passenger.erase_footprint_at(cell)
	var passenger_grid := HullRegistry.make_grid(hull_id)
	for i in range(4):
		_check(
			passenger.set_brick(passenger_grid, Vector3i(2 + i, 2, 10), "passenger_seat", 0),
			"passenger seat %d lands on the deck" % (i + 1),
		)
	var passenger_report := VesselCompliance.validate(
		passenger, hull_id, "passenger_vessel", HullRegistry.make_grid(hull_id)
	)
	_check(bool(passenger_report.get("ok", false)), "passenger registration uses explicit seat capacity")


func _test_deployment_gate() -> void:
	var entry := _require_trawler("the deployment gate")
	if entry.is_empty():
		return
	var record := {
		"uid": "registration_test",
		"hull_id": entry.get("hull_id", ""),
		"registration_id": entry.get("registration_id", ""),
		"brick_layout": entry.get("prebuilt_layout", {}),
	}
	_check(
		not VesselSpawn.resolve_deployable_record(record).is_empty(),
		"certified vessel is deployable",
	)
	record["registration_id"] = "review_required"
	_check(
		VesselSpawn.resolve_deployable_record(record).is_empty(),
		"legacy review-required vessel is blocked from deployment",
	)


func _check(condition: bool, message: String) -> void:
	_t.check(message, condition)
