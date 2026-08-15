extends Node

## Lane B — it drives `CompanyService`, `VesselSpawn` and `BoatBody`, which name
## autoloads, and §5 needs a real physics space.
##
## THE CLAIM THIS UNIT HOLDS
##
## `hull_15x5` landed on 2026-08-15 and closed half of STATE.md item 5: the
## smallest hull in the game stopped being a 28 m coastal trader. The other half
## is the one a player experiences — **what a NEW CAPTAIN IS GIVEN**. That is a
## different question with a different answer, and it stayed "a 28 m coastal
## trader" for a day after the hull existed, because a preset that nothing
## selects is the piece kit that was never wired (REALITY.md §3d).
##
## So this unit does not ask whether a small hull exists. `starter_small_hull_test`
## asks that. This one runs onboarding — the real `create_company` command, the
## real prebuilt catalogue, the real spawn path — and asks what the captain ends
## up standing on.
##
## WHY THE SUBJECT IS MEASURED AND NOT NAMED
##
## REALITY.md §4a: assert the property, not the number. SUBJECT is resolved as
## the SHORTEST hull in `HullRegistry.catalog()`, and §1 then requires two things
## together: that the grant equals SUBJECT, and that SUBJECT is beginner-sized.
## Either alone is green on the defect. "The grant is the smallest hull" passes
## the instant `hull_15x5` is deleted (28 m becomes the smallest); "the smallest
## hull is 15 m" passes while onboarding hands out something else entirely. The
## conjunction is what the claim actually is.
##
## WHY §2 REACHES INTO A UI PANEL
##
## `CompanyContracts.DEFAULT_STARTER` is a constant, and a constant only the test
## reads is decoration (REALITY.md §3d). The panel is the game's caller: what a
## click-through captain gets is literally whatever `open_for_captain` leaves in
## `_selected_starter`. §2 opens the panel and reads it back, so restoring the
## old hardcoded "general_cargo" in the UI reddens this file even though every
## other section still passes.
##
## WHY §4 EXISTS WHEN §3 ALREADY SAYS "COMPLIANT"
##
## Because compliance never asks the grid. `VesselCompliance._measure` walks the
## layout's cells and counts tags; nothing in it consults `DeckGrid`. A preset
## authored with hull_28x10's 20 × 56 cell indices on a 10 × 30 hull is therefore
## FULLY COMPLIANT with its wheelhouse in the sea — helm, both sidelights and
## four mooring bits all present, all overboard. §4 is the only section that can
## see that, and the mutation that proves it (move one brick to x = 15) leaves
## §3 green.

const TestReport := preload("res://tests/support/test_report.gd")

## Same bound and same reasoning as `starter_small_hull_test`: the smallest of
## the owner's three reference vessels is ~15 m. Slack on purpose — a 14 m or
## 16 m redesign passes; what it forbids is the 28 m floor this was written in.
const BEGINNER_LOA_CEILING_M := 16.0
const OLD_STARTER_HULL := "hull_28x10"

## Rules `general_vessel` and its heirs must still be ASKING. A registration that
## quietly lost its inherited rules would leave a two-rule checklist that any
## bare deck passes, and §3's "every item ok" would go green on it.
const REQUIRED_RULE_IDS := [
	"helm", "port_light", "starboard_light", "white_light",
	"port_light_side", "starboard_light_side", "white_light_height",
	"mooring_points",
]

var _t := TestReport.new("starter_vessel_grant_test")
var _granted: Dictionary = {}
var _subject_hull := ""


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var granted := _check_a_new_captain_is_given_the_small_hull()
	_check_the_default_career_is_the_one_that_grants_it()
	## Independent of the grant on purpose: when a preset goes non-compliant the
	## catalogue marks it a draft and `build_starter_vessel_record` returns {},
	## so §1 fails with "onboarding failed" and the REASON is only in here.
	_check_the_preset_is_certified_not_a_draft()
	if granted:
		_check_every_brick_is_on_the_deck()
		await _check_it_spawns_and_the_fitout_is_not_decorative()
	_check_the_other_careers_are_unchanged()
	_t.finish(get_tree())


# ── 1 · onboarding, run for real, hands over the small hull ─────────────────

func _check_a_new_captain_is_given_the_small_hull() -> bool:
	var entries := HullRegistry.catalog()
	if not _t.check("HullRegistry.catalog() returns hulls", not entries.is_empty()):
		return false
	var smallest := {}
	for entry in entries:
		if smallest.is_empty() or float(entry.get("loa_m", 1e9)) < float(smallest.get("loa_m", 1e9)):
			smallest = entry
	_subject_hull = str(smallest.get("id", ""))
	var subject_loa := float(smallest.get("loa_m", 0.0))
	## Half of the claim. Without it, deleting the small hull makes the 28 m
	## trader "the smallest" and the grant check below would agree with itself.
	_t.check(
		"the shortest hull in the registry is beginner-sized — %s at %.1f m, must be <= %.1f m"
		% [_subject_hull, subject_loa, BEGINNER_LOA_CEILING_M],
		subject_loa <= BEGINNER_LOA_CEILING_M,
	)

	var starter_id := CompanyContracts.DEFAULT_STARTER
	if not _t.check(
		"the default career '%s' is a real starter option" % starter_id,
		CompanyContracts.STARTER_VESSELS.has(starter_id),
	):
		return false

	## The production command, not `build_starter_vessel_record` on its own:
	## `create_company` is what the menu calls, and it rolls the whole grant back
	## if the starter SKU is missing, which would leave zero vessels rather than
	## a wrong one.
	var player := PlayerData.new()
	player.account_id = "captain-grant-test"
	player.display_name = "Ada"
	player.home_port_id = "port-test"
	var service := CompanyService.new()
	service.bind(player)
	var result := service.create_company({
		"request_id": "grant-test",
		"company_id": "company-grant-test",
		"company_name": "North Star Fisheries",
		"brand_color": "2f7f83",
		"starter_vessel": starter_id,
		"timestamp_unix": 1000,
	})
	if not _t.check(
		"onboarding on the default career succeeds (%s)"
		% str(result.get("message", result.get("error", "ok"))),
		bool(result.get("ok", false)),
	):
		return false
	if not _t.check("onboarding granted exactly one vessel", player.owned_vessels.size() == 1):
		return false
	_granted = (player.owned_vessels[0] as Dictionary).duplicate(true)
	var granted_hull := str(_granted.get("hull_id", ""))

	## THE claim.
	_t.equal(
		"a new captain is given the shortest hull in the registry",
		granted_hull, _subject_hull,
	)
	_t.not_equal(
		"a new captain is NOT given the 28 m coastal trader any more",
		granted_hull, OLD_STARTER_HULL,
	)
	## The active vessel is what the player spawns aboard; a grant that lands in
	## the fleet list but not in the active slot is not a boat you start on.
	_t.equal(
		"the granted vessel is the active vessel",
		str(player.active_vessel.get("uid", "")), str(_granted.get("uid", "")),
	)
	return not granted_hull.is_empty()


# ── 2 · the default career is what the panel actually opens on ──────────────

func _check_the_default_career_is_the_one_that_grants_it() -> void:
	var panel := CompanySetupPanel.new()
	add_child(panel)
	panel.open_for_captain("Ada")
	_t.equal(
		"CompanySetupPanel opens on the default career, so a captain who changes nothing gets it",
		str(panel.get("_selected_starter")), CompanyContracts.DEFAULT_STARTER,
	)
	panel.queue_free()


# ── 3 · the preset is certified stock, not a draft the catalogue warns about ─

func _check_the_preset_is_certified_not_a_draft() -> void:
	var def := CompanyContracts.STARTER_VESSELS[CompanyContracts.DEFAULT_STARTER] as Dictionary
	var prebuilt_id := str(def.get("prebuilt_id", ""))
	var entry := {}
	for candidate in PrebuiltVesselCatalog.catalog_entries():
		if str(candidate.get("prebuilt_id", "")) == prebuilt_id:
			entry = candidate
			break
	if not _t.check("the starter preset '%s' is in the catalogue" % prebuilt_id, not entry.is_empty()):
		return

	## A draft preset is not refused — it is loaded, flagged, and `push_warning`ed
	## once per catalog load, and `build_starter_vessel_record` then returns {}.
	## The verdict is asserted here rather than eyeballed in the JSON.
	_t.check(
		"the preset is not a draft (errors: %s)"
		% " · ".join(entry.get("compliance_errors", PackedStringArray())),
		not bool(entry.get("is_draft", true)),
	)
	_t.check("the preset's compliance verdict is ok", bool(entry.get("compliance_ok", false)))
	_t.equal(
		"the preset carries no compliance errors",
		(entry.get("compliance_errors", PackedStringArray()) as PackedStringArray).size(), 0,
	)
	## Certified stock is what the Shipwright is allowed to sell; a draft is
	## filtered out of `for_sale_entries` and the boat becomes unbuyable too.
	var for_sale := false
	for candidate in PrebuiltVesselCatalog.for_sale_entries():
		if str(candidate.get("prebuilt_id", "")) == prebuilt_id:
			for_sale = true
			break
	_t.check("the starter preset is also certified yard stock", for_sale)

	## Re-run the verdict against the LAYOUT, item by item, so a failure names the
	## rule instead of saying "not ok".
	var hull_id := str(entry.get("hull_id", ""))
	var report := VesselCompliance.validate(
		BrickLayout.from_dict(entry.get("prebuilt_layout", {}) as Dictionary),
		hull_id,
		str(entry.get("registration_id", "")),
		HullRegistry.make_grid(hull_id),
	)
	var seen_rule_ids := {}
	for raw in report.get("checklist", []) as Array:
		var item := raw as Dictionary
		seen_rule_ids[str(item.get("id", ""))] = true
		_t.check(
			"registration rule '%s' passes on the %d-cell beam — %s (current %s)"
			% [
				str(item.get("id", "")), HullRegistry.make_grid(hull_id).width,
				str(item.get("requirement", "")), str(item.get("current", "")),
			],
			bool(item.get("ok", false)),
		)
	## …and that the checklist still CONTAINS the general-vessel law. An empty or
	## truncated rule list passes the loop above vacuously (REALITY.md §4).
	for rule_id in REQUIRED_RULE_IDS:
		_t.check(
			"the starter's registration still asks for '%s'" % rule_id,
			seen_rule_ids.has(rule_id),
		)
	_t.check(
		"the outfit half of the verdict is ok too (%s)"
		% " · ".join(report.get("errors", PackedStringArray())),
		bool(report.get("outfit_ok", false)) and bool(report.get("ok", false)),
	)


# ── 4 · every brick is on the deck of the hull it was authored for ──────────

func _check_every_brick_is_on_the_deck() -> void:
	var hull_id := str(_granted.get("hull_id", ""))
	var grid := HullRegistry.make_grid(hull_id)
	var layout := BrickLayout.from_dict(VesselSpawn.brick_layout_of(_granted))
	var cells := layout.iter_primary_cells()
	if not _t.check("the granted layout has bricks in it (%d)" % cells.size(), cells.size() >= 8):
		return
	var overboard := 0
	var worst := ""
	for item in cells:
		var cell: Vector3i = item["cell"]
		if not grid.has_deck_cell(cell):
			overboard += 1
			if worst.is_empty():
				worst = "%s at %v" % [str(item.get("brick_id", "")), cell]
	_t.equal(
		"every brick in the starter layout stands on the %d x %d deck (first stray: %s)"
		% [grid.width, grid.length, worst if not worst.is_empty() else "none"],
		overboard, 0,
	)
	## Mooring bits, sidelights and the helm are the fittings the registration
	## counts; if any of THOSE is overboard the vessel is certified on furniture
	## that is not on the boat.
	var fittings_overboard := 0
	for item in cells:
		var cell: Vector3i = item["cell"]
		var brick_id := str(item.get("brick_id", ""))
		var counted := (
			BrickCatalog.has_tag(brick_id, "mooring")
			or BrickCatalog.has_tag(brick_id, "helm")
			or not str(item.get("light_id", "")).is_empty()
		)
		if counted and not grid.has_deck_cell(cell):
			fittings_overboard += 1
	_t.equal("no compliance-counted fitting is overboard", fittings_overboard, 0)


# ── 5 · it spawns through the production path, and the fit-out is real ──────

func _check_it_spawns_and_the_fitout_is_not_decorative() -> void:
	## `resolve_deployable_record` is the gate every owned vessel passes before it
	## may exist in the world: it re-runs compliance and returns {} on failure. A
	## starter that cannot clear it is granted and then refused a spawn.
	_t.check(
		"the granted record is deployable",
		not VesselSpawn.resolve_deployable_record(_granted).is_empty(),
	)
	var fitted := VesselSpawn.instantiate_from_record(_granted)
	if not _t.check("the granted record spawns a vessel", fitted != null):
		return
	fitted.name = "GrantedStarter"
	fitted.automatic_physics_lod = false
	fitted.freeze = true
	add_child(fitted)
	await get_tree().physics_frame
	await get_tree().physics_frame
	## Measured off the BODY, not read back out of the record — `VesselSpawn`
	## falls back to the 28 m trawler whenever a hull fails to build, and a
	## record-to-record comparison is a tautology that cannot see that (§4).
	var hull_entry := HullRegistry.get_by_id(str(_granted.get("hull_id", "")))
	_t.near(
		"the spawned body is as long as the record's hull declares (%.1f m)" % fitted.length_m,
		fitted.length_m, float(hull_entry.get("loa_m", 0.0)), 0.01,
	)
	_t.near(
		"the spawned body is as wide as the record's hull declares (%.1f m)" % fitted.beam_m,
		fitted.beam_m, float(hull_entry.get("beam_m", 0.0)), 0.01,
	)
	var fitted_meshes := _mesh_count(fitted)
	var fitted_shapes := _walk_shape_count(fitted)

	## THE STRIP TEST (REALITY.md §3d). Same hull, same registration, layout
	## deleted. If the granted layout contributes no geometry and no collision,
	## these two are equal — which is exactly what the piece kit measured as
	## "identical" while looking finished.
	var bare := VesselSpawn.instantiate(
		str(_granted.get("hull_id", "")),
		{"hull_id": str(_granted.get("hull_id", "")), "cells": {}},
		str(_granted.get("registration_id", "")),
	)
	if not _t.check("the bare control hull builds", bare != null):
		fitted.free()
		return
	bare.name = "BareControl"
	bare.automatic_physics_lod = false
	bare.freeze = true
	bare.position = Vector3(200.0, 0.0, 0.0)
	add_child(bare)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var bare_meshes := _mesh_count(bare)
	var bare_shapes := _walk_shape_count(bare)

	_t.check(
		"the starter's fit-out draws geometry the bare hull does not (%d vs %d mesh instances)"
		% [fitted_meshes, bare_meshes],
		fitted_meshes > bare_meshes,
	)
	## Through PhysicsServer3D on the body the player actually walks on, not the
	## baker's dictionaries (REALITY.md §3).
	_t.check(
		"the starter's fit-out adds walk collision the bare hull does not (%d vs %d shapes)"
		% [fitted_shapes, bare_shapes],
		fitted_shapes > bare_shapes,
	)
	fitted.free()
	bare.free()
	await get_tree().process_frame


func _mesh_count(node: Node) -> int:
	var n := 1 if node is MeshInstance3D else 0
	for child in node.get_children():
		n += _mesh_count(child)
	return n


func _walk_shape_count(boat: BoatBody) -> int:
	var walk := boat.call("get_walk_deck") as CollisionObject3D
	if walk == null:
		return 0
	return PhysicsServer3D.body_get_shape_count(walk.get_rid())


# ── 6 · the blast radius: the other careers are where they were ─────────────

func _check_the_other_careers_are_unchanged() -> void:
	## Moving the beginner onto a 15 m hull must not quietly re-hull the cargo and
	## bulk careers, and a future wave that repoints one of them should have to
	## come here and say so.
	for starter_id in ["general_cargo", "bulk"]:
		if not _t.check(
			"'%s' is still a starter career" % starter_id,
			CompanyContracts.STARTER_VESSELS.has(starter_id),
		):
			continue
		var record := CompanyService.build_starter_vessel_record(starter_id, "uid-%s" % starter_id)
		if not _t.check("'%s' still grants a vessel" % starter_id, not record.is_empty()):
			continue
		_t.equal(
			"'%s' is unchanged — still %s" % [starter_id, OLD_STARTER_HULL],
			str(record.get("hull_id", "")), OLD_STARTER_HULL,
		)
