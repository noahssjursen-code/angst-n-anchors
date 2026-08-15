class_name VesselCompliance
extends RefCounted

## Final authority: physical outfit legality plus declared registration law.


static func validate(
	layout: BrickLayout,
	hull_id: String,
	registration_id: String,
	grid: DeckGrid = null,
) -> Dictionary:
	var id := HullRegistry.resolve_network_hull_id(hull_id)
	var g := grid if grid != null else HullRegistry.make_grid(id)
	var registration := VesselRegistrationCatalog.resolved_registration(registration_id)
	var caps: Dictionary = registration.get("budget_caps", {})
	var outfit := VesselOutfit.validate(layout, id, g, caps)
	var checklist: Array[Dictionary] = []
	var errors: PackedStringArray = outfit.get("errors", PackedStringArray()).duplicate()
	var warnings: PackedStringArray = outfit.get("warnings", PackedStringArray()).duplicate()
	if registration.is_empty():
		errors.append("Choose a vessel registration before building.")
		return _result(outfit, registration_id, false, checklist, errors, warnings)

	var metrics := _measure(layout, g, outfit)
	for raw in registration.get("rules", []) as Array:
		if not raw is Dictionary:
			continue
		var item := _evaluate_rule(raw as Dictionary, metrics, outfit)
		checklist.append(item)
		if not bool(item.get("ok", false)):
			errors.append(str(item.get("message", item.get("label", "Registration requirement failed"))))
	var registration_ok := true
	for item in checklist:
		if not bool(item.get("ok", false)):
			registration_ok = false
			break
	return _result(outfit, registration_id, registration_ok, checklist, errors, warnings)


static func checklist_summary(report: Dictionary) -> String:
	var passed := 0
	var checklist: Array = report.get("checklist", [])
	for item in checklist:
		if item is Dictionary and bool((item as Dictionary).get("ok", false)):
			passed += 1
	return "%d/%d legal requirements" % [passed, checklist.size()]


## Outfit budget slot gated by registration (`fishing`, `helm`, `crane`, `tow`), or "".
static func outfit_slot_for_brick(brick_id: String) -> String:
	if BrickCatalog.has_tag(brick_id, "fishing") or BrickCatalog.has_tag(brick_id, "trommel"):
		return "fishing"
	if BrickCatalog.has_tag(brick_id, "helm"):
		return "helm"
	if BrickCatalog.has_tag(brick_id, "crane"):
		return "crane"
	if BrickCatalog.has_tag(brick_id, "tow"):
		return "tow"
	return ""


## Empty string means the brick is legal to place under this registration.
static func brick_placement_denied_reason(
	registration_id: String,
	hull_id: String,
	brick_id: String,
	layout: BrickLayout = null,
	replace_cells: Array = [],
) -> String:
	var slot := outfit_slot_for_brick(brick_id)
	if slot.is_empty():
		return ""
	var reg_id := registration_id.strip_edges()
	if reg_id.is_empty():
		return "Choose a legal vessel registration before building"
	var registration := VesselRegistrationCatalog.resolved_registration(reg_id)
	if registration.is_empty():
		return "Unknown vessel registration"
	var budget := VesselOutfit.budget_for_hull(hull_id, registration.get("budget_caps", {}) as Dictionary)
	var max_n := int(budget.get(slot, 0))
	var display := VesselRegistrationCatalog.display_name(reg_id)
	if max_n <= 0:
		return "%s is not legal for %s" % [BrickCatalog.display_name(brick_id), display]
	if layout == null:
		return ""
	var replace := {}
	for raw in replace_cells:
		if not raw is Vector3i:
			continue
		var cell: Vector3i = raw
		replace[cell] = true
		if layout.has_cell(cell):
			replace[layout.primary_cell_of(cell)] = true
	var used := 0
	for item in layout.iter_primary_cells():
		var cell: Vector3i = item["cell"]
		if replace.has(cell):
			continue
		if outfit_slot_for_brick(str(item.get("brick_id", ""))) == slot:
			used += 1
	if used >= max_n:
		return "%s budget full (%d / %d) for %s" % [slot.capitalize(), used, max_n, display]
	return ""


static func brick_allowed_for_registration(
	registration_id: String,
	hull_id: String,
	brick_id: String,
) -> bool:
	return brick_placement_denied_reason(registration_id, hull_id, brick_id).is_empty()


## Counts what the vessel actually carries. Every count is now conditional on the
## brick being ON the deck — and the answer is not re-derived here: `off_grid` is
## the set `VesselOutfit.validate` already refused, threaded through `outfit`
## (REALITY.md §3b, one derivation).
##
## AN OFF-DECK BRICK IS NOT A MISSING BRICK, and the two must not read the same,
## which is why the fix is split across two places rather than doubled in one:
##
##   • Here it is NOT COUNTED, so the checklist says what is missing — "One
##     working helm — at least 1 (current: 0)". Without this a helm floating in
##     the sea satisfies the helm rule; the side rules are worse, because
##     `_correct_side_count` reads `cell_center_local(cell).x`, which is
##     arithmetic on an index and returns a sign for any integer, 12 m off the bow
##     as readily as on the foredeck. That is how the headline layout scored 8/8.
##   • `VesselOutfit` raises ONE error naming the cells, and it arrives in this
##     report's `errors` (line ~19). Without that the player is told to fit a
##     helm they can see they already bought.
##
## Neither half is sufficient, and that is measured rather than argued. Mutation
## M3 — keep the error, drop this skip — leaves `vessel_registration_test` at
## **7 of 8 legal requirements met by bricks in the sea** (1/74 red): only the
## helm rule falls, because the helm slot is filtered at its source, while both
## nav-light side rules, the white-above-side rule and the four-mooring minimum
## are all satisfied by equipment 12 m off the bow. A 7/8 checklist printed beside
## a refusal is the two-green-tests-disagreeing shape of REALITY.md §4a.
static func _measure(layout: BrickLayout, grid: DeckGrid, outfit: Dictionary) -> Dictionary:
	var brick_counts := {}
	var tag_counts := {}
	var positions := {}
	var capacity := {}
	var max_ratings := {}
	var off_grid: Array = outfit.get("off_grid", [])
	var off_grid_cells := {}
	for raw in off_grid:
		off_grid_cells[(raw as Dictionary).get("cell", Vector3i.ZERO)] = true
	if layout != null:
		for item in layout.iter_primary_cells():
			var cell: Vector3i = item.get("cell", Vector3i.ZERO)
			var brick_id := str(item.get("brick_id", ""))
			if off_grid_cells.has(cell):
				continue
			_measure_equipment(brick_id, cell, brick_counts, tag_counts, positions, capacity, max_ratings)
			var mounted_light := str(item.get("light_id", ""))
			if not mounted_light.is_empty():
				_measure_equipment(
					mounted_light, cell, brick_counts, tag_counts, positions, capacity, max_ratings
				)
		## Bulk holds live outside the brick cell map — count them for registration rules.
		var bulk_n := layout.count_tag("bulk_hold")
		if bulk_n > 0:
			tag_counts["bulk_hold"] = bulk_n
		for hold_raw in layout.iter_bulk_holds():
			var hold := hold_raw as Dictionary
			var hold_brick := str(hold.get("brick_id", "bulk_hold_6x12"))
			brick_counts[hold_brick] = int(brick_counts.get(hold_brick, 0)) + 1
			tag_counts["cargo"] = int(tag_counts.get("cargo", 0)) + BrickLayout.zone_cell_count(hold)
	var usage: Dictionary = outfit.get("usage", {}).duplicate(true)
	var capabilities: Dictionary = outfit.get("capabilities", {}).duplicate(true)
	for field in capacity.keys():
		usage[field] = int(capacity[field])
	return {
		"brick_counts": brick_counts,
		"tag_counts": tag_counts,
		"positions": positions,
		"capacity": capacity,
		"max_ratings": max_ratings,
		"usage": usage,
		"capabilities": capabilities,
		"accepted_slots": outfit.get("accepted_slots", {}),
		"off_grid": off_grid,
		"grid": grid,
	}


static func _measure_equipment(
	brick_id: String,
	cell: Vector3i,
	brick_counts: Dictionary,
	tag_counts: Dictionary,
	positions: Dictionary,
	capacity: Dictionary,
	max_ratings: Dictionary,
) -> void:
	if not BrickCatalog.has(brick_id):
		return
	brick_counts[brick_id] = int(brick_counts.get(brick_id, 0)) + 1
	if not positions.has(brick_id):
		positions[brick_id] = []
	(positions[brick_id] as Array).append(cell)
	var entry := BrickCatalog.get_entry(brick_id)
	for tag in entry.get("tags", []) as Array:
		var key := str(tag)
		tag_counts[key] = int(tag_counts.get(key, 0)) + 1
		max_ratings[key] = maxi(
			int(max_ratings.get(key, 0)),
			int(entry.get("equipment_rating", 0))
		)
	for field in ["passenger_capacity"]:
		if entry.has(field):
			capacity[field] = int(capacity.get(field, 0)) + int(entry[field])


static func _evaluate_rule(
	rule: Dictionary,
	metrics: Dictionary,
	outfit: Dictionary,
) -> Dictionary:
	var kind := str(rule.get("kind", ""))
	var current: Variant = 0
	var ok := false
	match kind:
		"slot_count":
			var slot := str(rule.get("slot", ""))
			current = (metrics.get("accepted_slots", {}).get(slot, []) as Array).size()
			ok = _within(int(current), rule)
		"brick_count":
			current = int(metrics.get("brick_counts", {}).get(str(rule.get("brick_id", "")), 0))
			ok = _within(int(current), rule)
		"tag_count":
			current = int(metrics.get("tag_counts", {}).get(str(rule.get("tag", "")), 0))
			ok = _within(int(current), rule)
		"cargo_cells":
			current = int(outfit.get("usage", {}).get("accepted_cargo_cells", 0))
			ok = _within(int(current), rule)
		"metric_range":
			current = int(metrics.get("capabilities", {}).get(str(rule.get("metric", "")), 0))
			ok = _within(int(current), rule)
		"capacity":
			current = int(metrics.get("capacity", {}).get(str(rule.get("field", "")), 0))
			ok = _within(int(current), rule)
		"capability":
			current = bool(metrics.get("capabilities", {}).get(
				str(rule.get("capability", "")), false
			))
			ok = bool(current) == bool(rule.get("required", true))
		"equipment_rating_max":
			current = int(metrics.get("max_ratings", {}).get(str(rule.get("tag", "")), 0))
			ok = int(current) <= int(rule.get("max_rating", 0))
		"brick_side":
			current = _correct_side_count(rule, metrics)
			var total := int(metrics.get("brick_counts", {}).get(str(rule.get("brick_id", "")), 0))
			ok = total > 0 and int(current) == total
		"white_above_sidelights":
			current = _white_height_delta(metrics)
			ok = float(current) > 0.0
		_:
			current = "unknown rule"
			ok = false
	var label := str(rule.get("label", rule.get("id", "Requirement")))
	var requirement := _requirement_text(rule)
	return {
		"id": str(rule.get("id", "")),
		"label": label,
		"kind": kind,
		"ok": ok,
		"current": current,
		"requirement": requirement,
		"message": "%s: %s (current: %s)" % [label, requirement, str(current)],
	}


static func _within(value: int, rule: Dictionary) -> bool:
	if rule.has("min") and value < int(rule["min"]):
		return false
	if rule.has("max") and value > int(rule["max"]):
		return false
	return true


static func _correct_side_count(rule: Dictionary, metrics: Dictionary) -> int:
	var cells: Array = metrics.get("positions", {}).get(str(rule.get("brick_id", "")), [])
	var grid := metrics.get("grid", null) as DeckGrid
	if grid == null:
		return 0
	var n := 0
	var side := str(rule.get("side", ""))
	for raw in cells:
		var cell := raw as Vector3i
		var local_x := grid.cell_center_local(cell).x
		if (side == "port" and local_x < 0.0) or (side == "starboard" and local_x > 0.0):
			n += 1
	return n


static func _white_height_delta(metrics: Dictionary) -> float:
	var positions: Dictionary = metrics.get("positions", {})
	var whites: Array = []
	whites.append_array(positions.get("light_nav_white", []) as Array)
	whites.append_array(positions.get("light_mast_white", []) as Array)
	var ports: Array = positions.get("light_nav_port", [])
	var stbd: Array = positions.get("light_nav_stbd", [])
	if whites.is_empty() or ports.is_empty() or stbd.is_empty():
		return -1.0
	var white_y := -99999
	for raw in whites:
		white_y = maxi(white_y, (raw as Vector3i).y)
	var side_y := -99999
	for raw in ports + stbd:
		side_y = maxi(side_y, (raw as Vector3i).y)
	return float(white_y - side_y)


static func _requirement_text(rule: Dictionary) -> String:
	match str(rule.get("kind", "")):
		"equipment_rating_max":
			return "rating ≤ %d" % int(rule.get("max_rating", 0))
		"brick_side":
			return "all on %s side" % str(rule.get("side", "correct"))
		"white_above_sidelights":
			return "white light above side lights"
		"capability":
			return "required" if bool(rule.get("required", true)) else "forbidden"
	if rule.has("min") and rule.has("max"):
		return "%d–%d" % [int(rule["min"]), int(rule["max"])]
	if rule.has("min"):
		return "at least %d" % int(rule["min"])
	if rule.has("max"):
		return "at most %d" % int(rule["max"])
	return "required"


## SIGNATURE IS LOAD-BEARING BEYOND THIS FILE. `PlanOutfit.compliance` calls this
## twice (plan_outfit.gd:317, :330) so the plan path and the brick path emit the
## same report shape. An earlier attempt at this same wave added a `metrics`
## parameter here and did not update those two calls: both
## `vessel_registration_test` and `deck_fitout_staging_test` went NOTRUN on parse
## errors, and every other unit in the family ran with 20–26 script errors.
##
## `off_grid_bricks` therefore comes off `outfit`, which this already receives —
## no new parameter, and it is correct for the plan path too, where the key is
## absent and the count is 0.
static func _result(
	outfit: Dictionary,
	registration_id: String,
	registration_ok: bool,
	checklist: Array[Dictionary],
	errors: PackedStringArray,
	warnings: PackedStringArray,
) -> Dictionary:
	return {
		"off_grid_bricks": (outfit.get("off_grid", []) as Array).size(),
		"ok": bool(outfit.get("ok", false)) and registration_ok and errors.is_empty(),
		"outfit_ok": bool(outfit.get("ok", false)),
		"registration_ok": registration_ok,
		"registration_id": registration_id,
		"catalog_version": VesselRegistrationCatalog.catalog_version(),
		"checklist": checklist,
		"errors": errors,
		"warnings": warnings,
		"effective_budget": outfit.get("budget", {}),
		"budget": outfit.get("budget", {}),
		"usage": outfit.get("usage", {}),
		"accepted_slots": outfit.get("accepted_slots", {}),
		"capabilities": outfit.get("capabilities", {}),
	}
