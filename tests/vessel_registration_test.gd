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

var _t: TestReport


func _ready() -> void:
	_t = TestReport.new("vessel_registration_test")
	_test_catalog_and_inheritance()
	_test_official_fishing_registration()
	_test_fishing_berth_deployment_filter()
	_test_official_starter_catalog()
	_test_stricter_registration_budget()
	_test_nav_light_placement()
	_test_seeded_registration_types()
	_test_deployment_gate()
	_test_off_deck_bricks_are_not_equipment()
	_test_setter_refuses_off_deck()
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
