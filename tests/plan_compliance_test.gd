extends SceneTree

## Lane A contract test for PlanOutfit — measuring a StructurePlan for
## VesselCompliance. Run:
##   xvfb-run -a --server-args="-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy \
##     --script res://tests/plan_compliance_test.gd
##
## Two jobs, in this order:
##
## 1. PIN TODAY'S TRUTH. An empty plan is outfit-legal and registration-ILLEGAL:
##    it fails every one of general_vessel's eight requirements. That is the
##    fact `DeckFitout.apply_plan`'s hardcoded `{"outfit_ok": true}` currently
##    contradicts, and it is why a Structure Studio ship cannot be saved,
##    spawned, crewed or sold.
##
## 2. Prove each rule KIND can be satisfied by a plan that provides the right
##    items — driven through the real `VesselCompliance._evaluate_rule`, never
##    a copy of it.
##
## Every check here has been shown to go RED against a deliberately broken
## PlanOutfit; the mutants and their scores are in the wave report. A check
## with no failing control is not evidence.
##
## A script error aborts the enclosing function and lets _initialize carry on,
## so a broken PlanOutfit could report "ALL PASS" having asserted nothing.
## The check count is pinned for exactly that reason.

const PO := preload("res://scripts/ship/plan_outfit.gd")
const Parts := preload("res://scripts/construction/part_catalog.gd")
const HULL := "hull_28x10"
const EXPECTED_CHECKS := 127

var _failures := 0
var _checks := 0


func _check(label: String, ok: bool) -> void:
	_checks += 1
	print("%s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		_failures += 1


func _initialize() -> void:
	_test_empty_plan_fails_general_vessel()
	_test_empty_plan_measures_nothing()
	_test_a_fence_is_not_a_cabin()
	_test_doors_come_from_openings()
	_test_rule_kinds_are_satisfiable()
	_test_sidelight_rules_are_tag_addressed()
	_test_general_vessel_scoreboard()
	_test_a_lit_plan_certifies()
	_test_fishing_vessel_scoreboard()
	_test_budgets_are_enforced()
	_test_cargo_is_a_union_of_deck_cells()
	_test_removing_one_item_reddens_one_rule()
	print("---")
	if _checks != EXPECTED_CHECKS:
		print(
			"FAIL ran %d checks, expected %d — a check aborted before asserting"
			% [_checks, EXPECTED_CHECKS]
		)
		_failures += 1
	print(
		"plan_compliance_test: %d checks, %s"
		% [_checks, "ALL PASS" if _failures == 0 else "%d FAILURES" % _failures]
	)
	quit(0 if _failures == 0 else 1)


# ── Fixtures ────────────────────────────────────────────────────────────────

func _grid() -> DeckGrid:
	return HullRegistry.make_grid(HULL)


## A complete little vessel drawn as a plan: a wheelhouse with a door, a helm,
## four mooring points, an all-round white light aloft, two benches, a hold, and
## optionally fishing gear. Nothing here names a ship type — it is a kit build.
func _outfitted_plan(with_fishing: bool, helms: int = 1) -> StructurePlan:
	var plan := StructurePlan.new()
	plan.hull_id = HULL
	## The wheelhouse this plan used to carry was a room and went with the room
	## primitive. What is left is the wall the door was cut into — the door is
	## what `egress` measures, and a door is a wall opening.
	var front := plan.add_wall(Vector3(3.0, 0.0, 26.0), "x", 4.0, 2.6)
	(front["openings"] as Array).append({
		"type": "door", "offset": 1.2, "width": 0.9, "height": 2.0, "sill": 0.0,
	})
	for i in helms:
		plan.add_item("helm_console", Vector3(4.6 + float(i) * 0.8, 0.0, 24.0))
	## All four on the port side, so `brick_side` has something true to measure.
	for i in 4:
		plan.add_item("bollard_pair", Vector3(1.0 + float(i) * 0.6, 0.0, 4.0 + float(i) * 2.0))
	plan.add_item("lantern_all_round", Vector3(5.0, 6.0, 23.0))
	plan.add_item("bench_seat", Vector3(3.5, 0.0, 26.0))
	plan.add_item("bench_seat", Vector3(6.5, 0.0, 26.0))
	plan.add_item("hold_coaming", Vector3(5.0, 0.0, 14.0), 0.0, {"length": 8.0, "width": 4.0})
	if with_fishing:
		plan.add_item("net_drum", Vector3(5.0, 0.0, 18.0))
	return plan


## The same vessel with its navigation lights fitted: a red one to port, a green
## one to starboard, each 1.2 m up, under the all-round white light `_outfitted_plan`
## already carries 6.0 m up. `white_y` moves the white one so the height rule can
## be shown biting rather than merely passing.
##
## Port is −x in `DeckGrid.cell_center_local`, and the deck is 10 m wide, so
## x = 1.0 is to port and x = 9.0 is to starboard on this hull.
func _lit_plan(with_fishing: bool, white_y := 6.0) -> StructurePlan:
	var plan := _outfitted_plan(with_fishing)
	if not is_equal_approx(white_y, 6.0):
		var lantern := plan.items[_index_of_part(plan, "lantern_all_round")] as Dictionary
		lantern["at"] = [5.0, white_y, 23.0]
	plan.add_item("lantern_sidelight_port", Vector3(1.0, 1.2, 20.0))
	plan.add_item("lantern_sidelight_starboard", Vector3(9.0, 1.2, 20.0))
	return plan


func _index_of_part(plan: StructurePlan, part_id: String) -> int:
	for i in plan.items.size():
		if str((plan.items[i] as Dictionary).get("item_id", "")) == part_id:
			return i
	return -1


func _failed_ids(report: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for raw in report.get("checklist", []) as Array:
		var item := raw as Dictionary
		if not bool(item.get("ok", false)):
			out.append(str(item.get("id", "")))
	out.sort()
	return out


func _rule(report: Dictionary, rule_id: String) -> Dictionary:
	for raw in report.get("checklist", []) as Array:
		if str((raw as Dictionary).get("id", "")) == rule_id:
			return raw as Dictionary
	return {}


func _errors_mention(report: Dictionary, needle: String) -> bool:
	var blob := " | ".join(report.get("errors", PackedStringArray()) as PackedStringArray)
	if blob.contains(needle):
		return true
	print("    missing \"%s\" in: %s" % [needle, blob])
	return false


## Evaluates one hand-written rule through the production evaluator.
func _evaluate(rule: Dictionary, metrics: Dictionary, outfit: Dictionary) -> Dictionary:
	return VesselCompliance._evaluate_rule(rule, metrics, outfit)


# ── 1. Today's truth ────────────────────────────────────────────────────────

func _test_empty_plan_fails_general_vessel() -> void:
	var plan := StructurePlan.new()
	plan.hull_id = HULL
	var report := PO.compliance(plan, HULL, "general_vessel", _grid())

	_check("an empty plan is not legal", not bool(report.get("ok", true)))
	_check("an empty plan breaks no OUTFIT budget", bool(report.get("outfit_ok", false)))
	_check("an empty plan fails its registration", not bool(report.get("registration_ok", true)))
	_check(
		"general_vessel puts eight requirements on the checklist",
		(report.get("checklist", []) as Array).size() == 8
	)
	_check(
		"an empty plan passes none of them",
		VesselCompliance.checklist_summary(report) == "0/8 legal requirements"
	)
	var expected := PackedStringArray([
		"helm", "mooring_points", "port_light", "port_light_side", "starboard_light",
		"starboard_light_side", "white_light", "white_light_height",
	])
	_check("every requirement is named and failing", _failed_ids(report) == expected)
	_check(
		"the helm failure names the helm rule, not a generic error",
		_errors_mention(report, "One working helm: 1–1 (current: 0)")
	)
	_check(
		"the mooring failure carries its own count",
		_errors_mention(report, "At least four mooring points: at least 4 (current: 0)")
	)
	## The report shape is VesselCompliance's, not a lookalike.
	for key in ["ok", "outfit_ok", "registration_ok", "registration_id", "catalog_version",
			"checklist", "errors", "warnings", "budget", "usage", "accepted_slots",
			"capabilities"]:
		_check("report carries \"%s\"" % key, report.has(key))
	_check("the report names the registration it judged", str(report.get("registration_id", "")) == "general_vessel")


func _test_empty_plan_measures_nothing() -> void:
	var plan := StructurePlan.new()
	plan.hull_id = HULL
	var grid := _grid()
	var outfit := PO.validate(plan, HULL, grid)
	var metrics := PO.measure(plan, grid, outfit)
	for key in ["brick_counts", "tag_counts", "positions", "capacity", "max_ratings"]:
		_check("%s is empty for an empty plan" % key, (metrics[key] as Dictionary).is_empty())
	_check("metrics carry the grid the cell rules need", metrics.get("grid", null) is DeckGrid)
	var caps: Dictionary = metrics["capabilities"]
	_check("an empty plan has no cabin", not bool(caps.get("has_cabin", true)))
	_check("no doors without openings", int(caps.get("doors", -1)) == 0)
	_check(
		"the hull's exposed deck is still measured",
		int(caps.get("exposed_deck_cells", 0)) == 1010
	)
	_check("no cargo is accepted", int((outfit["usage"] as Dictionary)["accepted_cargo_cells"]) == 0)


# ── 2. Enclosure from geometry, no items at all ─────────────────────────────

## Enclosure used to be read off the room primitive: a room WAS the plan's
## declaration of a cabin. The room primitive was deleted, nothing that survives
## it declares enclosure, and `has_cabin` is false for every plan until the
## sloped-plate primitive lands (see PlanOutfit's header). The room legs of this
## test went with it.
##
## What must NOT go with it is the regression below. It is the reason the room
## reading existed at all, and it is the exact shape a future wave will be
## tempted to reintroduce when a licence needs a cabin and no primitive declares
## one. It stays, and it stays as an assertion about walls.
func _test_a_fence_is_not_a_cabin() -> void:
	## THE REGRESSION: the brick-era rule was
	## `door_n >= 1 or wall_n >= 8`, so eight roofless walls — and a fence with a
	## gate in it — reported an enclosed cabin.
	var fence := StructurePlan.new()
	fence.hull_id = HULL
	for i in 8:
		fence.add_wall(Vector3(1.0 + float(i), 0.0, 6.0), "x", 2.0, 2.6)
	(fence.walls[0]["openings"] as Array).append({
		"type": "door", "offset": 0.4, "width": 0.9, "height": 2.0, "sill": 0.0,
	})
	var fence_caps: Dictionary = PO.validate(fence, HULL)["capabilities"]
	_check("eight roofless walls are not a cabin", not bool(fence_caps["has_cabin"]))
	_check("and no plan claims a cabin count", int(fence_caps["cabins"]) == 0)
	_check("a gate in a fence is still a door", int(fence_caps["doors"]) == 1)
	_check("the fence is still counted as structure", int(fence_caps["brick_count"]) == 8)


func _test_doors_come_from_openings() -> void:
	var plan := StructurePlan.new()
	plan.hull_id = HULL
	var wall := plan.add_wall(Vector3(1.0, 0.0, 4.0), "x", 6.0, 2.6)
	(wall["openings"] as Array).append({"type": "door", "offset": 1.0, "width": 0.9, "height": 2.0})
	(wall["openings"] as Array).append({"type": "window", "offset": 3.0, "width": 1.2, "height": 0.8})
	(wall["openings"] as Array).append({"type": "hole", "offset": 4.5, "width": 0.4, "height": 0.4})
	var second := plan.add_wall(Vector3(3.0, 0.0, 10.0), "z", 4.0, 2.6)
	(second["openings"] as Array).append({"type": "door", "offset": 1.0, "width": 0.9, "height": 2.0})
	(second["openings"] as Array).append({"type": "window", "offset": 2.2, "width": 1.0, "height": 0.9})
	var deck := plan.add_deck(Vector3(2.0, 3.0, 10.0), Vector2(4.0, 4.0))
	(deck["openings"] as Array).append({"type": "stairwell", "offset": [1.0, 1.0], "size": [1.0, 2.0]})

	var caps: Dictionary = PO.validate(plan, HULL)["capabilities"]
	_check("doors count on every wall that carries one", int(caps["doors"]) == 2)
	_check("windows are counted separately", int(caps["windows"]) == 2)
	_check("a stairwell is not a door", int(caps["doors"]) != 3)


# ── 3. Every rule kind, satisfied by a plan ─────────────────────────────────

func _test_rule_kinds_are_satisfiable() -> void:
	var grid := _grid()
	var plan := _outfitted_plan(true)
	var outfit := PO.validate(plan, HULL, grid)
	var metrics := PO.measure(plan, grid, outfit)

	_check("a fully outfitted plan breaks no budget", bool(outfit["ok"]))
	_check(
		"no warning about a fitting hanging off the deck",
		(outfit["warnings"] as PackedStringArray).is_empty()
	)

	## slot_count — accepted mounts, capped by the hull budget.
	_check("slot_count: one working helm", bool(_evaluate(
		{"kind": "slot_count", "slot": "helm", "min": 1, "max": 1}, metrics, outfit
	)["ok"]))
	_check("slot_count: one working fishing system", bool(_evaluate(
		{"kind": "slot_count", "slot": "fishing", "min": 1, "max": 1}, metrics, outfit
	)["ok"]))

	## brick_count — a plan's item_id IS the part id the rule names.
	var by_id := _evaluate(
		{"kind": "brick_count", "brick_id": "helm_console", "min": 1, "max": 1}, metrics, outfit
	)
	_check("brick_count: counts items by part id", bool(by_id["ok"]) and int(by_id["current"]) == 1)
	_check("brick_count: a part nobody placed counts zero", not bool(_evaluate(
		{"kind": "brick_count", "brick_id": "funnel_tapered", "min": 1}, metrics, outfit
	)["ok"]))

	## tag_count — catalog compliance tags, one per placed item.
	var moorings := _evaluate({"kind": "tag_count", "tag": "mooring", "min": 4}, metrics, outfit)
	_check("tag_count: four mooring points", bool(moorings["ok"]) and int(moorings["current"]) == 4)
	_check("tag_count: one all-round white light", bool(_evaluate(
		{"kind": "tag_count", "tag": "nav_white", "min": 1, "max": 2}, metrics, outfit
	)["ok"]))

	## cargo_cells — deck area the accepted hold covers, in cells.
	var cargo := _evaluate({"kind": "cargo_cells", "min": 8, "max": 600}, metrics, outfit)
	_check(
		"cargo_cells: the hold's own footprint, measured in deck cells",
		bool(cargo["ok"]) and int(cargo["current"]) == 128
	)

	## metric_range — a capability read as a number.
	_check("metric_range: at least one door", bool(_evaluate(
		{"kind": "metric_range", "metric": "doors", "min": 1}, metrics, outfit
	)["ok"]))
	_check("metric_range: an exposed working deck", bool(_evaluate(
		{"kind": "metric_range", "metric": "exposed_deck_cells", "min": 4}, metrics, outfit
	)["ok"]))

	## capacity — summed numeric attributes off the catalog.
	var seats := _evaluate(
		{"kind": "capacity", "field": "passenger_capacity", "min": 4}, metrics, outfit
	)
	_check("capacity: two benches seat six", bool(seats["ok"]) and int(seats["current"]) == 6)

	## capability — a boolean. The satisfiable case used to be has_cabin; that
	## capability died with the room primitive and is now false for every plan,
	## so the rule KIND is proved on one a plan can still meet, and the licence
	## that demands a cabin is pinned as unmeetable rather than quietly dropped.
	_check("capability: a required capability the plan has", bool(_evaluate(
		{"kind": "capability", "capability": "has_helm", "required": true}, metrics, outfit
	)["ok"]))
	_check("capability: no plan can meet a required cabin", not bool(_evaluate(
		{"kind": "capability", "capability": "has_cabin", "required": true}, metrics, outfit
	)["ok"]))
	_check("capability: a forbidden capability is absent", bool(_evaluate(
		{"kind": "capability", "capability": "has_crane", "required": false}, metrics, outfit
	)["ok"]))

	## equipment_rating_max — the highest rating carried by any item of a tag.
	var rating_ok := _evaluate(
		{"kind": "equipment_rating_max", "tag": "fishing", "max_rating": 2}, metrics, outfit
	)
	_check(
		"equipment_rating_max: gear inside the licence rating",
		bool(rating_ok["ok"]) and int(rating_ok["current"]) == 2
	)
	_check("equipment_rating_max: gear above it fails", not bool(_evaluate(
		{"kind": "equipment_rating_max", "tag": "fishing", "max_rating": 1}, metrics, outfit
	)["ok"]))

	## brick_side — needs real positions in grid cells.
	_check("brick_side: all mooring points are to port", bool(_evaluate(
		{"kind": "brick_side", "brick_id": "bollard_pair", "side": "port"}, metrics, outfit
	)["ok"]))
	_check("brick_side: they are not to starboard", not bool(_evaluate(
		{"kind": "brick_side", "brick_id": "bollard_pair", "side": "starboard"}, metrics, outfit
	)["ok"]))

	## Positions are real cells, not placeholders: the light aloft is measured
	## twelve half-metre cells above the deck it was drawn 6 m above.
	var lantern_cells: Array = (metrics["positions"] as Dictionary)["lantern_all_round"]
	_check(
		"positions: an item aloft measures its height in cells",
		lantern_cells.size() == 1 and (lantern_cells[0] as Vector3i).y == 12
	)


## The sidelight rules are TAG-addressed, and that is the whole of STATE.md 2f.
##
## They used to name the brick ids `light_nav_port` / `light_nav_stbd`, and
## `white_above_sidelights` hardcoded four brick ids of its own, so a plan failed
## FIVE of `general_vessel`'s eight rules regardless of what was fitted — the
## paragraph that stood here called that "a CATALOG gap" and pinned it. It is
## gone, and what replaces it is the property rather than the count: the same
## legal object is addressable from the plan side and the brick side by the same
## word.
func _test_sidelight_rules_are_tag_addressed() -> void:
	var grid := _grid()
	var plan := _lit_plan(true)
	var outfit := PO.validate(plan, HULL, grid)
	var metrics := PO.measure(plan, grid, outfit)

	## Both vocabularies carry the tags, and neither carries the other's ids.
	_check(
		"a catalogue part carries nav_port",
		Parts.has_tag("lantern_sidelight_port", "nav_port")
	)
	_check(
		"a catalogue part carries nav_stbd",
		Parts.has_tag("lantern_sidelight_starboard", "nav_stbd")
	)
	_check("a brick carries nav_port", BrickCatalog.has_tag("light_nav_port", "nav_port"))
	_check("a brick carries nav_stbd", BrickCatalog.has_tag("light_nav_stbd", "nav_stbd"))
	_check(
		"and the kit still carries none of the brick IDS — the tag is the address",
		not Parts.has("light_nav_port") and not Parts.has("light_nav_stbd")
	)

	## `tag_side` locates equipment the plan really carries.
	var port_side := _evaluate(
		{"kind": "tag_side", "tag": "nav_port", "side": "port"}, metrics, outfit
	)
	_check("tag_side: the red light is to port", bool(port_side["ok"]))
	_check(
		"tag_side: the same light is not to starboard",
		not bool(_evaluate(
			{"kind": "tag_side", "tag": "nav_stbd", "side": "port"}, metrics, outfit
		)["ok"])
	)
	_check(
		"tag_side: a tag nothing carries locates nothing and fails",
		not bool(_evaluate(
			{"kind": "tag_side", "tag": "nav_white_of_the_gods", "side": "port"}, metrics, outfit
		)["ok"])
	)

	## `white_above_sidelights` measures a real height difference now, and the
	## number is the property: the lantern is 6.0 m up and the sidelights 1.2 m,
	## which is 12 cells against 2, so the delta is 10 half-metre cells.
	var verdict := _evaluate({"kind": "white_above_sidelights"}, metrics, outfit)
	_check("white_above_sidelights passes on a lit plan", bool(verdict["ok"]))
	_check(
		"and it is the real cell delta, not a token",
		is_equal_approx(float(verdict["current"]), 10.0)
	)

	## Drop the white light BELOW the sidelights and the rule must bite. This is
	## the half that proves the law was not weakened to let a plan through.
	var low := _lit_plan(true, 0.4)
	var low_outfit := PO.validate(low, HULL, grid)
	var low_metrics := PO.measure(low, grid, low_outfit)
	var low_verdict := _evaluate({"kind": "white_above_sidelights"}, low_metrics, low_outfit)
	_check("a white light below the sidelights fails", not bool(low_verdict["ok"]))
	_check(
		"and it fails on the measurement, not on absence",
		float(low_verdict["current"]) <= 0.0 and not is_equal_approx(float(low_verdict["current"]), -1.0)
	)


# ── 4. Scoreboards ──────────────────────────────────────────────────────────

## AN UNLIT PLAN IS REFUSED, and by exactly the five rules that ask for lights.
## This was written as "today's numbers, meant to move"; the numbers have not
## moved, because they were never about the catalogue's reach. They are about
## the law biting a boat with no navigation lights on it, which it must go on
## doing — see `_test_a_lit_plan_certifies` for the other half.
func _test_general_vessel_scoreboard() -> void:
	## A full plan minus fishing gear (general_vessel caps fishing at 0), and
	## with no navigation lights except the all-round white one.
	var report := PO.compliance(_outfitted_plan(false), HULL, "general_vessel", _grid())
	_check("a well-built plan still breaks no budget", bool(report["outfit_ok"]))
	_check(
		"three of general_vessel's eight requirements pass",
		VesselCompliance.checklist_summary(report) == "3/8 legal requirements"
	)
	_check(
		"the five failures are exactly the navigation-light rules",
		_failed_ids(report) == PackedStringArray([
			"port_light", "port_light_side", "starboard_light",
			"starboard_light_side", "white_light_height",
		])
	)
	_check("the helm requirement passes", bool(_rule(report, "helm")["ok"]))
	_check("the mooring requirement passes", bool(_rule(report, "mooring_points")["ok"]))
	_check("the white-light requirement passes", bool(_rule(report, "white_light")["ok"]))
	_check("so the plan is still refused", not bool(report["ok"]))


## THE OTHER HALF, and the one STATE.md 2f is about: fit the lights and the
## same plan is certified — through `PlanOutfit.compliance`, which is what
## `DeckFitout.apply_plan` calls.
func _test_a_lit_plan_certifies() -> void:
	var report := PO.compliance(_lit_plan(false), HULL, "general_vessel", _grid())
	_check(
		"a lit plan meets all eight of general_vessel's requirements",
		VesselCompliance.checklist_summary(report) == "8/8 legal requirements"
	)
	_check("nothing on the checklist fails", _failed_ids(report).is_empty())
	_check("so the registration verdict is yes", bool(report["registration_ok"]))
	_check("and the whole report is ok", bool(report["ok"]))

	## Remove ONE light and the boat stops being legal — the rule sees the
	## equipment, it does not merely stop asking.
	var one_eyed := _lit_plan(false)
	one_eyed.items.remove_at(_index_of_part(one_eyed, "lantern_sidelight_port"))
	var dark := PO.compliance(one_eyed, HULL, "general_vessel", _grid())
	_check("pulling the port sidelight refuses the vessel", not bool(dark["registration_ok"]))
	_check(
		"and it names the port rules, not a generic failure",
		_failed_ids(dark) == PackedStringArray([
			"port_light", "port_light_side", "white_light_height",
		])
	)

	## A second port light is one too many — `max` still holds under a tag.
	var doubled := _lit_plan(false)
	doubled.add_item("lantern_sidelight_port", Vector3(1.0, 1.2, 12.0))
	var over := PO.compliance(doubled, HULL, "general_vessel", _grid())
	_check("two port sidelights breaks the 1..1 bound", not bool(over["registration_ok"]))
	_check(
		"and it is the count rule that says so",
		int(_rule(over, "port_light")["current"]) == 2
	)


func _test_fishing_vessel_scoreboard() -> void:
	var report := PO.compliance(_outfitted_plan(true), HULL, "fishing_vessel", _grid())
	_check("fishing_vessel inherits general_vessel's eight and adds two",
		(report["checklist"] as Array).size() == 10)
	_check(
		"five of ten pass",
		VesselCompliance.checklist_summary(report) == "5/10 legal requirements"
	)
	_check(
		"and a LIT fishing plan meets all ten",
		VesselCompliance.checklist_summary(
			PO.compliance(_lit_plan(true), HULL, "fishing_vessel", _grid())
		) == "10/10 legal requirements"
	)
	_check("the fishing gear requirement passes", bool(_rule(report, "fishing_gear")["ok"]))
	_check("the catch deck requirement passes", bool(_rule(report, "catch_deck")["ok"]))
	_check("the tighter cargo cap is honoured", bool(report["outfit_ok"]))
	_check(
		"and the tighter cap is the registration's, not the hull's",
		int((report["budget"] as Dictionary)["cargo_cells"]) == 140
	)


# ── 5. Budgets ──────────────────────────────────────────────────────────────

func _test_budgets_are_enforced() -> void:
	var grid := _grid()
	var plan := _outfitted_plan(false, 2)
	var outfit := PO.validate(plan, HULL, grid)
	_check("a second helm is over budget", not bool(outfit["ok"]))
	_check(
		"and says so in the same words the brick path uses",
		" | ".join(outfit["errors"] as PackedStringArray).contains(
			"Helm exceeds hull budget (2 / 1). Remove extras — only accepted mounts go live."
		)
	)
	var accepted: Dictionary = outfit["accepted_slots"]
	_check("only one helm is accepted", (accepted["helm"] as Array).size() == 1)
	_check(
		"accepted slots are plan item ids, so a mount can be found again",
		(accepted["helm"] as Array)[0] == int((plan.items[0] as Dictionary)["id"])
	)
	var metrics := PO.measure(plan, grid, outfit)
	_check(
		"the surplus helm does not make the checklist lie",
		bool(_evaluate(
			{"kind": "slot_count", "slot": "helm", "min": 1, "max": 1}, metrics, outfit
		)["ok"])
	)
	var report := PO.compliance(plan, HULL, "general_vessel", grid)
	_check("but the vessel is refused all the same", not bool(report["ok"]))
	_check("because the OUTFIT is illegal", not bool(report["outfit_ok"]))

	## An unknown part is never measured silently.
	var stray := StructurePlan.new()
	stray.hull_id = HULL
	stray.add_item("winch_of_the_gods", Vector3(5.0, 0.0, 10.0))
	var stray_outfit := PO.validate(stray, HULL, grid)
	_check(
		"an unknown part is reported, not skipped in silence",
		" | ".join(stray_outfit["warnings"] as PackedStringArray).contains("winch_of_the_gods")
	)
	_check("and it does not fail the outfit", bool(stray_outfit["ok"]))

	## A fitting placed off the ship is called out — and there are now TWO bands,
	## which this pair pins apart.
	##
	## This check used to put the helm at x = 40 on a 10 m beam and assert a
	## WARNING. That coordinate is 30 m outboard: it is not a fitting overhanging
	## the sheer, it is a fitting that belongs to no hull this boat has, and
	## `PlanOutfit`'s hull fence now refuses it as an ERROR and does not build it
	## (`plan_hull_bounds_test`). Keeping the old assertion would have demanded
	## that the worse case be reported more gently than the milder one, so the
	## case was split rather than moved: the mild one still warns, the gross one
	## errors, and neither can quietly become the other.
	var outboard := StructurePlan.new()
	outboard.hull_id = HULL
	outboard.add_item("helm_console", Vector3(10.4, 0.0, 10.0))
	var outboard_outfit := PO.validate(outboard, HULL, grid)
	_check(
		"a helm 0.4 m outboard of the deck edge is reported as a warning",
		" | ".join(outboard_outfit["warnings"] as PackedStringArray)
			.contains("not over the vessel's deck")
	)
	_check("and a fitting on the boat does not refuse the vessel", bool(outboard_outfit["ok"]))

	var overboard := StructurePlan.new()
	overboard.hull_id = HULL
	overboard.add_item("helm_console", Vector3(40.0, 0.0, 10.0))
	var overboard_outfit := PO.validate(overboard, HULL, grid)
	_check(
		"a helm 30 m off the side is an ERROR naming the hull it missed",
		" | ".join(overboard_outfit["errors"] as PackedStringArray)
			.contains("is not on the 10.0 x 28.0 m hull")
	)
	_check("and that one does refuse the vessel", not bool(overboard_outfit["ok"]))


func _test_cargo_is_a_union_of_deck_cells() -> void:
	var grid := _grid()

	## Two identical holds in the same place buy no capacity. The brick path's
	## per-zone sum would report 256 here.
	var stacked := StructurePlan.new()
	stacked.hull_id = HULL
	stacked.add_item("hold_coaming", Vector3(5.0, 0.0, 14.0), 0.0, {"length": 8.0, "width": 4.0})
	stacked.add_item("hold_coaming", Vector3(5.0, 2.0, 14.0), 0.0, {"length": 8.0, "width": 4.0})
	var stacked_outfit := PO.validate(stacked, HULL, grid)
	_check("overlapping holds are counted once", int(
		(stacked_outfit["usage"] as Dictionary)["accepted_cargo_cells"]
	) == 128)
	_check("both are still accepted", (
		stacked_outfit["accepted_slots"]["cargo_item_ids"] as Array
	).size() == 2)

	## A hold that will not fit the hull's cargo budget is rejected by name.
	var greedy := StructurePlan.new()
	greedy.hull_id = HULL
	greedy.add_item("hold_coaming", Vector3(5.0, 0.0, 16.0), 0.0, {"length": 20.0, "width": 8.0})
	var greedy_outfit := PO.validate(greedy, HULL, grid)
	_check("a hold larger than the budget is refused", not bool(greedy_outfit["ok"]))
	_check(
		"and the message counts cells, not holds",
		" | ".join(greedy_outfit["errors"] as PackedStringArray).contains(
			"Cargo exceeds hull budget (640 / 555 cells)"
		)
	)
	_check("nothing is accepted", int(
		(greedy_outfit["usage"] as Dictionary)["accepted_cargo_cells"]
	) == 0)

	## A hold hanging over the bow taper is not deck.
	var overhang := StructurePlan.new()
	overhang.hull_id = HULL
	overhang.add_item("hold_coaming", Vector3(5.0, 0.0, 3.0), 0.0, {"length": 8.0, "width": 4.0})
	_check(
		"a hold off the exposed deck is refused",
		" | ".join(PO.validate(overhang, HULL, grid)["errors"] as PackedStringArray)
			.contains("outside the exposed deck")
	)

	## The footprint is the part's OWN geometry: a bigger hold covers more.
	var big := PO.item_footprint_cells(
		greedy, greedy.items[0] as Dictionary, grid
	)
	_check("footprint cells follow the part's parameters", big.size() == 640)


# ── 6. Mutation lane: one item out, one rule red ────────────────────────────

func _test_removing_one_item_reddens_one_rule() -> void:
	var grid := _grid()
	var plan := _outfitted_plan(false)
	var before := PO.compliance(plan, HULL, "general_vessel", grid)
	_check("baseline: helm passes", bool(_rule(before, "helm")["ok"]))
	_check("baseline: mooring passes", bool(_rule(before, "mooring_points")["ok"]))
	_check("baseline: white light passes", bool(_rule(before, "white_light")["ok"]))

	## Remove the helm console — nothing else.
	var helm_id := int((plan.items[0] as Dictionary)["id"])
	_check("the item removed is the helm", str((plan.items[0] as Dictionary)["item_id"]) == "helm_console")
	_check("the plan gave it up", plan.remove_entity(helm_id))
	var after := PO.compliance(plan, HULL, "general_vessel", grid)
	_check("the helm rule goes red", not bool(_rule(after, "helm")["ok"]))
	_check(
		"and it is that rule, named, not a generic failure",
		_errors_mention(after, "One working helm: 1–1 (current: 0)")
	)
	_check("mooring stays green", bool(_rule(after, "mooring_points")["ok"]))
	_check("the white light stays green", bool(_rule(after, "white_light")["ok"]))
	_check(
		"exactly one more requirement fails than before",
		_failed_ids(after).size() == _failed_ids(before).size() + 1
	)
	_check("the outfit is still legal — it is the LAW that failed",
		bool(after["outfit_ok"]))

	## And the mirror: pull one mooring point, the mooring rule alone reddens.
	var trimmed := _outfitted_plan(false)
	var bollard_id := -1
	for raw in trimmed.items:
		if str((raw as Dictionary)["item_id"]) == "bollard_pair":
			bollard_id = int((raw as Dictionary)["id"])
			break
	_check("a mooring point was found to remove", trimmed.remove_entity(bollard_id))
	var short := PO.compliance(trimmed, HULL, "general_vessel", grid)
	_check("three mooring points is not four", not bool(_rule(short, "mooring_points")["ok"]))
	_check(
		"and the message carries the count",
		_errors_mention(short, "At least four mooring points: at least 4 (current: 3)")
	)
	_check("the helm is untouched", bool(_rule(short, "helm")["ok"]))
