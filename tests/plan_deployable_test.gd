extends Node

## Lane B. Can a ship drawn as a `structure_plan_v1` plan be CERTIFIED, SAVED
## and RESPAWNED — the seam the whole economy sits on?
##
## Run:
##   xvfb-run -a --server-args="-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy res://tests/plan_deployable_test.tscn
##
## Lane B because persistence needs the autoloads (`PlayerSaveStore`,
## `LocalCaptainStore`, `VesselArchive`) by bare name.
##
## ── What was broken ─────────────────────────────────────────────────────────
##
## Three separate places, one root cause: nobody asked what SHAPE the layout was.
##
##   1. `DeckFitout.apply_any` dropped `registration_id` on the plan branch, so a
##      plan reached the compliance pass holding no licence at all.
##   2. `DeckFitout.apply_plan` returned a hardcoded `{"outfit_ok": true}` and
##      called no validator — every plan was "legal", including an empty one.
##   3. `PlayerSession.persist_vessel_configuration` and
##      `VesselSpawn.resolve_deployable_record` both ran `BrickLayout.from_dict`
##      on whatever dictionary they held. Handed a plan that yields an EMPTY
##      layout, which fails the helm rule, so a Structure Studio ship could be
##      neither saved nor spawned.
##
## §1 pins (3) as a permanent fact about `BrickLayout`, not as a thing that got
## fixed: reading a plan as bricks still gives nothing, which is exactly why the
## shape has to be detected before the reader is chosen.
##
## ── The limit that WAS honest, and is now closed (STATE.md 2f) ──────────────
##
## This header used to read *"a plan still cannot pass `general_vessel`, and no
## wiring can change that"* — because the two sidelight rules named brick ids no
## catalogue part carried, so the ceiling for a plan was 3/8. That is fixed: the
## rules are tag-addressed and the kit carries two sidelight parts. §4 now pins
## BOTH halves — an unlit plan is still refused by those same five rules, and a
## lit one certifies under the real `general_vessel`.
##
## §5's injected registration is KEPT even so, and not out of inertia: its four
## controls are about the deploy/save seam choosing the right reader, and they
## want a licence whose requirements are stated in this file rather than one
## whose content can move underneath them. It
## injects a test-only registration into `VesselRegistrationCatalog._cache`
## whose three requirements a plan CAN meet. (It carried a fourth, an enclosed-
## accommodation rule, until deleting the room primitive took the only thing a
## plan had to declare enclosure with.) It names no vessel type — it is a
## minimum-equipment licence, the same shape as the real rows — and the cache is
## restored afterwards. Everything downstream of it (`apply_plan`,
## `resolve_deployable_record`, `persist_vessel_configuration`) is production
## code running unmodified.
##
## §5 carries four CONTROLS against the two ways this seam fails silently.
## "Plans are waved through": an empty plan on the same licence must still be
## refused a spawn and a save. "The shape test is dropped and everything is read
## as a plan": that one is NOT caught by a refusal — an empty brick layout
## misread as an empty plan is refused too, and the mutant passed 62/62 until
## the controls started asserting WHICH reader answered.

const TestReport := preload("res://tests/support/test_report.gd")
const SESSION_SCRIPT := preload("res://scripts/player/player_session.gd")
const PO := preload("res://scripts/ship/plan_outfit.gd")

const HULL := "hull_28x10"
const TEST_ROOT := "user://automated_tests/plan_deployable"
## A licence a plan can actually satisfy: helm, mooring, enclosure, a way out.
## Nothing here names a vessel type — it is the general form of a minimum
## equipment list, which is what every row in the real catalog is.
const HARNESS_REGISTRATION := "harness_minimum"
## A script error aborts the enclosing function and lets `_run` carry on, so a
## broken seam could report PASS having asserted a third of what it claims.
## Pinned for exactly that reason — the count itself is a check.
const EXPECTED_CHECKS := 64

var _t: TestReport = null
var _spawned: Array[Node] = []
var _catalog_backup: Dictionary = {}


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_t = TestReport.new("plan_deployable_test")
	_test_reading_a_plan_as_bricks_yields_nothing()
	_test_apply_any_threads_the_registration()
	_test_apply_plan_reports_a_real_verdict()
	_test_a_plan_can_meet_general_vessel()
	_test_a_passing_plan_deploys_and_survives_a_save()
	_cleanup()
	var ran := _t.check_count()
	_t.equal("every check in this file ran to completion", ran, EXPECTED_CHECKS)
	_t.finish(get_tree())


# ── Fixtures ────────────────────────────────────────────────────────────────

func _grid() -> DeckGrid:
	return HullRegistry.make_grid(HULL)


## A small kit-built vessel drawn as a plan: a wall with a door cut into it, a
## helm, four mooring points and an all-round white light. Parts, not a boat
## model. The wheelhouse this used to carry was a ROOM and went with the room
## primitive (2026-08-10); the wall the door was cut into is what survives, and
## the door is what the egress rule actually measures.
func _outfitted_plan() -> StructurePlan:
	var plan := StructurePlan.new()
	plan.hull_id = HULL
	var front := plan.add_wall(Vector3(3.0, 0.0, 26.0), "x", 4.0, 2.6)
	(front["openings"] as Array).append({
		"type": "door", "offset": 1.2, "width": 0.9, "height": 2.0, "sill": 0.0,
	})
	plan.add_item("helm_console", Vector3(4.6, 0.0, 24.0))
	for i in 4:
		plan.add_item("bollard_pair", Vector3(1.0 + float(i) * 0.6, 0.0, 4.0 + float(i) * 2.0))
	plan.add_item("lantern_all_round", Vector3(5.0, 6.0, 23.0))
	return plan


## The same vessel with its navigation lights fitted — a red one to port, a green
## one to starboard, under the all-round white light 6 m up. Port is −x in
## `DeckGrid.cell_center_local` and this hull is 10 m in the beam, so x = 1.0 is
## to port and x = 9.0 to starboard.
func _lit_plan() -> StructurePlan:
	var plan := _outfitted_plan()
	plan.add_item("lantern_sidelight_port", Vector3(1.0, 1.2, 20.0))
	plan.add_item("lantern_sidelight_starboard", Vector3(9.0, 1.2, 20.0))
	return plan


func _empty_plan() -> StructurePlan:
	var plan := StructurePlan.new()
	plan.hull_id = HULL
	return plan


## A bare hull with no registration meta, so the value under test is the
## argument `apply_any` was handed and nothing else.
func _bare_boat() -> BoatBody:
	var boat := HullRegistry.build_hull(HULL)
	if boat == null:
		return null
	add_child(boat)
	_spawned.append(boat)
	if boat.has_meta("registration_id"):
		boat.remove_meta("registration_id")
	return boat


func _record(uid: String, layout: Dictionary, registration_id: String) -> Dictionary:
	return {
		"uid": uid,
		"hull_id": HULL,
		"registration_id": registration_id,
		"name": "Plan Deployable Fixture",
		"brick_layout": layout,
	}


func _failed_ids(report: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for raw in report.get("checklist", []) as Array:
		var item := raw as Dictionary
		if not bool(item.get("ok", false)):
			out.append(str(item.get("id", "")))
	out.sort()
	return out


func _outfit_meta(boat: BoatBody) -> Dictionary:
	return boat.get_meta("vessel_outfit", {}) as Dictionary


# ── 1. Why the record's shape has to be detected at all ─────────────────────

## Not a regression test — a standing fact about BrickLayout. A plan read as
## bricks is nothing, so any caller that guesses wrong condemns the vessel.
func _test_reading_a_plan_as_bricks_yields_nothing() -> void:
	var plan := _outfitted_plan()
	var plan_dict := plan.to_dict()
	_t.check(
		"the fixture really is a plan document",
		StructurePlan.is_plan(plan_dict)
	)
	_t.check(
		"and it really carries a helm the rules can find",
		int(PO.validate(plan, HULL, _grid())["capabilities"]["helms"]) == 1
	)

	var as_bricks := BrickLayout.from_dict(plan_dict)
	_t.check("read as a BrickLayout, a plan is EMPTY", as_bricks.is_empty())
	var brick_verdict := VesselCompliance.validate(
		as_bricks, HULL, "general_vessel", _grid()
	)
	_t.check(
		"so the brick reader fails the helm rule on a plan that has a helm",
		_failed_ids(brick_verdict).has("helm")
	)
	_t.check(
		"while the plan reader passes it on the same document",
		bool(PO.compliance(plan, HULL, "general_vessel", _grid())["registration_ok"]) == false
			and not _failed_ids(
				PO.compliance(plan, HULL, "general_vessel", _grid())
			).has("helm")
	)


# ── 2. apply_any must not drop the licence ──────────────────────────────────

func _test_apply_any_threads_the_registration() -> void:
	var boat := _bare_boat()
	if not _t.check("a bare hull is available", boat != null):
		return
	DeckFitout.apply_any(boat, _outfitted_plan().to_dict(), _grid(), "general_vessel")
	var outfit := _outfit_meta(boat)
	_t.check(
		"apply_any threads the declared registration into the plan branch",
		str(outfit.get("registration_id", "")) == "general_vessel"
	)
	## The tell for a dropped registration: the empty-licence error, which is
	## what an unthreaded plan came back with.
	var caps := DeckFitout.capabilities_of(boat)
	_t.check(
		"and the verdict is a judged one, not an unlicensed refusal",
		int(caps.get("helms", 0)) == 1
	)

	## The boat's own meta is the fallback the vessel scripts rely on:
	## `apply_brick_layout` calls apply_any with no registration at all.
	var meta_boat := _bare_boat()
	if not _t.check("a second bare hull is available", meta_boat != null):
		return
	meta_boat.set_meta("registration_id", "general_vessel")
	DeckFitout.apply_any(meta_boat, _outfitted_plan().to_dict(), _grid())
	_t.check(
		"an undeclared call falls back to the boat's registration meta",
		str(_outfit_meta(meta_boat).get("registration_id", "")) == "general_vessel"
	)


# ── 3. apply_plan must measure, not assert ──────────────────────────────────

func _test_apply_plan_reports_a_real_verdict() -> void:
	var boat := _bare_boat()
	if not _t.check("a hull for the empty plan is available", boat != null):
		return
	var caps := DeckFitout.apply_plan(boat, _empty_plan(), _grid(), "general_vessel")

	## THE HARDCODE. This was `true` for every plan ever drawn.
	_t.check("an empty plan is NOT outfit_ok", not bool(caps.get("outfit_ok", true)))
	_t.check("it is still flagged as plan-built", bool(caps.get("structure_plan", false)))
	_t.equal("an empty plan has no entities", int(caps.get("plan_entities", -1)), 0)

	## Capabilities are measured now, so they are present and they are FALSE.
	_t.check("capabilities carry a measured helm flag", caps.has("has_helm"))
	_t.check("an empty plan has no helm", not bool(caps.get("has_helm", true)))
	_t.check("an empty plan has no cabin", not bool(caps.get("has_cabin", true)))
	_t.equal("an empty plan has no doors", int(caps.get("doors", -1)), 0)
	_t.equal(
		"the hull's exposed deck is measured all the same",
		int(caps.get("exposed_deck_cells", 0)),
		1010,
	)
	var outfit := _outfit_meta(boat)
	_t.check("apply_plan publishes a vessel_outfit record", not outfit.is_empty())
	_t.check("its registration verdict is a refusal", not bool(outfit.get("registration_ok", true)))
	_t.check("and the overall verdict is a refusal", not bool(outfit.get("ok", true)))

	## The same call on a plan that IS outfitted measures the gear.
	var built := _bare_boat()
	if not _t.check("a hull for the outfitted plan is available", built != null):
		return
	var built_caps := DeckFitout.apply_plan(built, _outfitted_plan(), _grid(), "general_vessel")
	_t.check("an outfitted plan reports its helm", bool(built_caps.get("has_helm", false)))
	## No plan can report a cabin since the room primitive was deleted: nothing
	## that survives it declares enclosure, and inferring one from loose walls is
	## the "fence sold as accommodation" bug plan_compliance_test still pins.
	_t.check("no plan reports a cabin any more", not bool(built_caps.get("has_cabin", true)))
	_t.equal("an outfitted plan reports its door", int(built_caps.get("doors", -1)), 1)
	_t.check(
		"seven entities: a wall, a helm, four bollards and a lantern",
		int(built_caps.get("plan_entities", -1)) == 7
	)


# ── 4. The ceiling, and whose fault it is ───────────────────────────────────

## THE CEILING IS GONE — STATE.md 2f, closed 2026-08-15.
##
## This sub-test was `_test_the_ceiling_is_the_part_catalog` and it pinned a
## number: a plan could reach 3/8 on `general_vessel` and no further, because
## the two sidelight rules named the brick ids `light_nav_port` /
## `light_nav_stbd` and `white_above_sidelights` hardcoded four more, and no
## catalogue part could carry any of them. The rules are tag-addressed now and
## the kit carries `lantern_sidelight_port` / `lantern_sidelight_starboard`.
##
## THE LAW DID NOT MOVE, and this keeps both halves so that cannot be misread:
## an unlit plan is still refused by exactly those five rules, and the same plan
## with lights on it certifies under the REAL `general_vessel`.
func _test_a_plan_can_meet_general_vessel() -> void:
	var unlit := PO.compliance(_outfitted_plan(), HULL, "general_vessel", _grid())
	_t.check("a well-built plan breaks no OUTFIT budget", bool(unlit.get("outfit_ok", false)))
	_t.check("but with no navigation lights it is refused", not bool(unlit.get("ok", true)))
	_t.check(
		"the five failures are exactly the navigation-light rules",
		_failed_ids(unlit) == PackedStringArray([
			"port_light", "port_light_side", "starboard_light",
			"starboard_light_side", "white_light_height",
		])
	)

	var lit := PO.compliance(_lit_plan(), HULL, "general_vessel", _grid())
	_t.check("fitting the two sidelights certifies the same plan", bool(lit.get("ok", false)))
	_t.check("and the registration verdict says so", bool(lit.get("registration_ok", false)))
	_t.check("nothing on its checklist fails", _failed_ids(lit).is_empty())
	## The rule SEES the lights — it did not stop asking. The kit still carries
	## none of the brick ids those rules used to name.
	var brick_ids := PackedStringArray()
	for id in ["light_nav_port", "light_nav_stbd", "light_nav_white", "light_mast_white"]:
		if PartCatalog.has(id):
			brick_ids.append(id)
	_t.equal("and it did so by TAG — the kit carries none of the brick ids", brick_ids.size(), 0)

	## Not one licence is left behind: they all inherit general_vessel, so the
	## lights that certify here must certify there.
	for registration_id in ["fishing_vessel", "cargo_vessel", "bulk_vessel", "passenger_vessel"]:
		_t.check(
			"%s no longer fails on the lights" % registration_id,
			not _failed_ids(
				PO.compliance(_lit_plan(), HULL, registration_id, _grid())
			).has("port_light")
		)


# ── 5. End to end, on a licence a plan can meet ─────────────────────────────

func _test_a_passing_plan_deploys_and_survives_a_save() -> void:
	_install_harness_registration()
	var plan := _outfitted_plan()
	var plan_dict := plan.to_dict()

	## a) The fitout verdict itself.
	var boat := _bare_boat()
	if not _t.check("a hull for the certified plan is available", boat != null):
		_restore_registration_catalog()
		return
	var caps := DeckFitout.apply_plan(boat, plan, _grid(), HARNESS_REGISTRATION)
	_t.check("a compliant plan IS outfit_ok", bool(caps.get("outfit_ok", false)))
	_t.check(
		"and its registration verdict says so",
		bool(_outfit_meta(boat).get("registration_ok", false))
	)

	## b) Deployment. The control matters more than the pass: an empty plan on
	## the same licence must still be refused, or this seam is a rubber stamp.
	var uid := "plan-deployable-fixture"
	var record := _record(uid, plan_dict, HARNESS_REGISTRATION)
	var deployable := VesselSpawn.resolve_deployable_record(record)
	_t.check("a compliant plan record resolves as deployable", not deployable.is_empty())
	_t.check(
		"and the plan survives the resolve unmangled",
		PlayerData.json_equivalent(VesselSpawn.brick_layout_of(deployable), plan_dict)
	)
	_t.check(
		"CONTROL: an empty plan on the same licence is still refused",
		VesselSpawn.resolve_deployable_record(
			_record(uid + "-empty", _empty_plan().to_dict(), HARNESS_REGISTRATION)
		).is_empty()
	)
	## CONTROL against the OTHER way to break this seam: drop the shape test and
	## read everything as a plan. A refusal proves nothing here — an empty brick
	## layout misread as an empty plan is refused too (measured: that mutant
	## passed 60/60 before these three checks existed). What proves it is WHICH
	## reader answered, and only PlanOutfit stamps `structure_plan` onto its
	## capabilities and `cargo_item_ids` onto its accepted slots.
	var brick_report := DeckFitout.compliance_for_layout(
		{"hull_id": HULL, "cells": {}}, HULL, "general_vessel", _grid()
	)
	_t.check(
		"CONTROL: a brick layout is answered by the BRICK reader",
		not (brick_report.get("capabilities", {}) as Dictionary).has("structure_plan")
			and not (brick_report.get("accepted_slots", {}) as Dictionary).has("cargo_item_ids")
	)
	_t.check(
		"CONTROL: and a plan is answered by the PLAN reader",
		(DeckFitout.compliance_for_layout(
			plan_dict, HULL, HARNESS_REGISTRATION, _grid()
		).get("capabilities", {}) as Dictionary).has("structure_plan")
	)
	_t.check(
		"CONTROL: an empty BRICK layout is still refused a spawn",
		VesselSpawn.resolve_deployable_record(
			_record(uid + "-bricks", {"hull_id": HULL, "cells": {}}, "general_vessel")
		).is_empty()
	)

	## c) Respawn: the record actually builds a vessel with the plan on it.
	var respawned := VesselSpawn.instantiate_from_record(deployable)
	if _t.check("a deployable plan record instantiates a vessel", respawned != null):
		add_child(respawned)
		_spawned.append(respawned)
		var respawned_caps := DeckFitout.capabilities_of(respawned)
		_t.check(
			"the respawned vessel is plan-built",
			bool(respawned_caps.get("structure_plan", false))
		)
		_t.equal(
			"with every entity of the plan on it",
			int(respawned_caps.get("plan_entities", -1)),
			plan.entity_count(),
		)
		_t.check(
			"and it certifies as it stands",
			bool(respawned_caps.get("outfit_ok", false))
		)
		_t.check(
			"its fitout root exists",
			respawned.get_node_or_null(DeckFitout.FITOUT_ROOT) != null
		)

	## d) Persistence: the write path that refused every plan ship.
	LocalCaptainStore.root_override = TEST_ROOT
	_t.check("pre-test wipe succeeds", PlayerSaveStore.wipe_all_local_data())
	var session := SESSION_SCRIPT.new()
	session.allow_test_persistent_io = true
	get_tree().root.add_child(session)
	session.begin_new_captain("Plan Deployable Captain", CharacterAppearance.default_appearance())
	var account := str(session.data.account_id)
	_t.check("captain slot is created", LocalCaptainStore.create_slot(account))
	_t.check("onboarding save succeeds", session.save_now())

	_t.check(
		"a plan-built vessel can be persisted",
		session.persist_vessel_configuration(record, true)
	)
	var disk := PlayerSaveStore.load_player()
	var stored: Dictionary = disk.find_owned_vessel(uid)
	_t.check("the plan-built vessel is on disk", not stored.is_empty())
	_t.check(
		"and the plan document survived the disk round-trip",
		PlayerData.json_equivalent(VesselSpawn.brick_layout_of(stored), plan_dict)
	)
	_t.check(
		"the record read back off disk is still deployable",
		not VesselSpawn.resolve_deployable_record(stored).is_empty()
	)

	## The write path's own gate is intact: an uncertified plan is still refused.
	_t.check(
		"CONTROL: an empty plan is refused a save",
		not session.persist_vessel_configuration(
			_record(uid + "-empty", _empty_plan().to_dict(), HARNESS_REGISTRATION), false
		)
	)
	_t.check(
		"CONTROL: and the refused vessel never reached the ledger",
		disk.find_owned_vessel(uid + "-empty").is_empty()
	)

	get_tree().root.remove_child(session)
	session.free()
	_restore_registration_catalog()


# ── Registration injection ──────────────────────────────────────────────────

## Adds one row to the LOADED catalog and leaves the five real ones untouched.
## `_cache` is the same dictionary `raw_catalog()` returns when it is warm, so
## every reader downstream — resolution, inheritance, the evaluator — runs
## exactly as it does in the game.
func _install_harness_registration() -> void:
	var catalog := VesselRegistrationCatalog.raw_catalog()
	if not _t.check("the real registration catalog loads", not catalog.is_empty()):
		return
	_catalog_backup = catalog.duplicate(true)
	var rows: Array = (catalog.get("registrations", []) as Array).duplicate(true)
	rows.append({
		"id": HARNESS_REGISTRATION,
		"display": "Harness minimum",
		"description": "Test-only minimum equipment licence. Not shipped content.",
		"budget_caps": {"fishing": 0, "crane": 0, "tow": 0, "cargo_cells": 600},
		"rules": [
			{"id": "helm", "label": "One working helm",
				"kind": "slot_count", "slot": "helm", "min": 1, "max": 1},
			{"id": "mooring_points", "label": "At least four mooring points",
				"kind": "tag_count", "tag": "mooring", "min": 4},
			{"id": "egress", "label": "At least one marked door",
				"kind": "metric_range", "metric": "doors", "min": 1},
		],
	})
	catalog["registrations"] = rows
	VesselRegistrationCatalog._cache = catalog
	_t.check(
		"the harness licence is visible to the catalog",
		VesselRegistrationCatalog.has(HARNESS_REGISTRATION)
	)
	_t.check(
		"and the five shipped registrations are untouched",
		VesselRegistrationCatalog.ids().size() == 6
			and VesselRegistrationCatalog.has("general_vessel")
	)


func _restore_registration_catalog() -> void:
	if _catalog_backup.is_empty():
		VesselRegistrationCatalog.reload()
		return
	VesselRegistrationCatalog._cache = _catalog_backup.duplicate(true)
	_catalog_backup = {}


func _cleanup() -> void:
	_restore_registration_catalog()
	for node in _spawned:
		if node != null and is_instance_valid(node):
			if node.get_parent() != null:
				node.get_parent().remove_child(node)
			node.queue_free()
	_spawned.clear()
	PlayerSaveStore.wipe_all_local_data()
	LocalCaptainStore.clear_active()
	LocalCaptainStore.root_override = ""
