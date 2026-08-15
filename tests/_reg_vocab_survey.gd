extends SceneTree

## SCRATCH PROBE (leading underscore — the gate must not discover it).
##
## STATE.md 2f, step 1: what does EVERY rule of EVERY registration address, and
## can a plan-built boat satisfy it? Nothing is assumed; every answer is read off
## the catalogs.
##
##   xvfb-run -a --server-args="-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy --script res://tests/_reg_vocab_survey.gd

const Parts := preload("res://scripts/construction/part_catalog.gd")


func _init() -> void:
	Parts.ensure_loaded()
	var part_ids := Parts.ids()
	var part_tags := {}
	var part_slots := {}
	for raw in part_ids:
		var pid := str(raw)
		for tag in Parts.tags_of(pid):
			if not part_tags.has(str(tag)):
				part_tags[str(tag)] = []
			(part_tags[str(tag)] as Array).append(pid)
		var slot := Parts.outfit_slot_of(pid)
		if not slot.is_empty():
			if not part_slots.has(slot):
				part_slots[slot] = []
			(part_slots[slot] as Array).append(pid)

	print("=== WHAT A PLAN CAN OFFER ===")
	print("catalogue parts: %d  -> %s" % [part_ids.size(), ", ".join(part_ids)])
	print("part ids that are also BRICK ids: %s" % str(_brick_overlap(part_ids)))
	print("part tags: %s" % str(part_tags))
	print("part outfit slots: %s" % str(part_slots))
	var brick_tags := {}
	for bid in BrickCatalog.BRICKS.keys():
		for tag in (BrickCatalog.BRICKS[bid] as Dictionary).get("tags", []) as Array:
			brick_tags[str(tag)] = int(brick_tags.get(str(tag), 0)) + 1
	print("brick ids: %d   brick tags: %d distinct" % [BrickCatalog.BRICKS.size(), brick_tags.size()])
	print("brick tags: %s" % str(brick_tags.keys()))

	print("\n=== THE RULE SURVEY ===")
	var totals := {"plan": 0, "brick": 0, "both": 0, "neither": 0}
	var rows: Array = []
	for reg_id_raw in VesselRegistrationCatalog.ids():
		var reg_id := str(reg_id_raw)
		var reg := VesselRegistrationCatalog.resolved_registration(reg_id)
		print("\n-- %s (%s) — %d resolved rules"
			% [reg_id, str(reg.get("display", "")), (reg.get("rules", []) as Array).size()])
		for raw in reg.get("rules", []) as Array:
			var rule := raw as Dictionary
			var verdict := _verdict(rule, part_ids, part_tags, part_slots)
			totals[str(verdict["class"])] = int(totals[str(verdict["class"])]) + 1
			rows.append({"reg": reg_id, "rule": str(rule.get("id", "")), "v": verdict})
			print("   %-22s kind=%-22s addresses=%-28s plan=%-5s brick=%-5s  %s"
				% [
					str(rule.get("id", "")), str(rule.get("kind", "")),
					str(verdict["addresses"]), str(verdict["plan"]), str(verdict["brick"]),
					str(verdict["why"]),
				])
	print("\n=== TOTALS over resolved rules (general_vessel's 8 counted once per registration) ===")
	print(str(totals))
	var unsat := PackedStringArray()
	for row in rows:
		if not bool(((row as Dictionary)["v"] as Dictionary)["plan"]):
			unsat.append("%s/%s" % [str((row as Dictionary)["reg"]), str((row as Dictionary)["rule"])])
	print("RULES A PLAN CAN NEVER SATISFY (%d of %d): %s"
		% [unsat.size(), rows.size(), ", ".join(unsat)])
	var unsat_b := PackedStringArray()
	for row in rows:
		if not bool(((row as Dictionary)["v"] as Dictionary)["brick"]):
			unsat_b.append("%s/%s" % [str((row as Dictionary)["reg"]), str((row as Dictionary)["rule"])])
	print("RULES A BRICK LAYOUT CAN NEVER SATISFY (%d of %d): %s"
		% [unsat_b.size(), rows.size(), ", ".join(unsat_b)])
	quit(0)


func _brick_overlap(part_ids: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	for raw in part_ids:
		if BrickCatalog.BRICKS.has(str(raw)):
			out.append(str(raw))
	return out


## Can each path produce a non-zero / satisfying value for this rule at all?
func _verdict(
	rule: Dictionary, part_ids: PackedStringArray, part_tags: Dictionary, part_slots: Dictionary
) -> Dictionary:
	var kind := str(rule.get("kind", ""))
	var addresses := "?"
	var plan := false
	var brick := false
	var why := ""
	match kind:
		"brick_count", "brick_side":
			var bid := str(rule.get("brick_id", ""))
			addresses = "brick id %s" % bid
			plan = part_ids.has(bid)
			brick = BrickCatalog.BRICKS.has(bid)
			why = "no catalogue part carries this id" if not plan else ""
		"tag_count":
			var tag := str(rule.get("tag", ""))
			addresses = "tag %s" % tag
			plan = part_tags.has(tag)
			brick = _brick_has_tag(tag)
			if not plan:
				why = "no catalogue part carries this tag"
		"equipment_rating_max":
			var tag := str(rule.get("tag", ""))
			addresses = "tag %s rating ceiling" % tag
			## A ceiling rule: absence satisfies it (0 <= max). Both paths pass.
			plan = true
			brick = true
			if not part_tags.has(tag):
				why = "no catalogue part carries this tag, so a plan passes it vacuously"
		"slot_count":
			var slot := str(rule.get("slot", ""))
			addresses = "outfit slot %s" % slot
			plan = part_slots.has(slot)
			brick = _brick_slot(slot)
			if not plan:
				why = "no catalogue part fills this slot"
		"white_above_sidelights":
			addresses = "brick ids light_nav_white|light_mast_white vs light_nav_port|light_nav_stbd"
			plan = (
				part_ids.has("light_nav_white") or part_ids.has("light_mast_white")
			) and part_ids.has("light_nav_port") and part_ids.has("light_nav_stbd")
			brick = true
			if not plan:
				why = "evaluator reads positions[] by hardcoded BRICK ids"
		"cargo_cells":
			addresses = "measured usage.accepted_cargo_cells"
			plan = true
			brick = true
		"metric_range":
			addresses = "capability %s" % str(rule.get("metric", ""))
			plan = true
			brick = true
			if str(rule.get("metric", "")) == "doors":
				why = "plan counts door openings + door-tagged parts"
		"capacity":
			addresses = "capacity field %s" % str(rule.get("field", ""))
			plan = _any_part_capacity(part_ids, str(rule.get("field", "")))
			brick = true
			if not plan:
				why = "no catalogue part declares this capacity"
		"capability":
			addresses = "capability %s" % str(rule.get("capability", ""))
			var cap := str(rule.get("capability", ""))
			plan = not (cap == "has_cabin")
			brick = true
			if cap == "has_cabin":
				why = "PlanOutfit.has_cabin() is hardcoded false (room primitive deleted)"
		_:
			addresses = "UNKNOWN KIND"
	var cls := "neither"
	if plan and brick:
		cls = "both"
	elif plan:
		cls = "plan"
	elif brick:
		cls = "brick"
	return {"addresses": addresses, "plan": plan, "brick": brick, "why": why, "class": cls}


func _brick_has_tag(tag: String) -> bool:
	for bid in BrickCatalog.BRICKS.keys():
		if ((BrickCatalog.BRICKS[bid] as Dictionary).get("tags", []) as Array).has(tag):
			return true
	return false


func _brick_slot(slot: String) -> bool:
	for bid in BrickCatalog.BRICKS.keys():
		if VesselCompliance.outfit_slot_for_brick(str(bid)) == slot:
			return true
	return false


func _any_part_capacity(part_ids: PackedStringArray, field: String) -> bool:
	for raw in part_ids:
		if int(Parts.compliance_of(str(raw)).get(field, 0)) != 0:
			return true
	return false
