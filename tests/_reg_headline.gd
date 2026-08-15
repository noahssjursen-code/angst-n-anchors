extends Node

## SCRATCH PROBE (leading underscore — the gate must not discover it).
##
## STATE.md 2f headline, through the PRODUCTION path: `VesselSpawn.instantiate`
## -> `DeckFitout.apply_plan` -> the real scene tree. The verdict is read off the
## spawned boat's `vessel_outfit` meta, not off `PlanOutfit`'s return value.
##
##   xvfb-run -a --server-args="-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy res://tests/_reg_headline.tscn
##
## Prints, for each registration, the full checklist of a plan built to be legal
## and of the equivalent BRICK vessel (the four prebuilt presets), so the two
## vocabularies can be compared side by side on the same law.

const HULL_ID := "hull_28x10"
const PREBUILT_DIR := "res://resources/data/vessels/prebuilt"


func _ready() -> void:
	PartCatalog.ensure_loaded()
	for reg in ["general_vessel", "fishing_vessel", "passenger_vessel"]:
		await _plan_verdict(reg)
	print("\n===== BRICK PRESETS (the currently-certifying path) =====")
	_brick_verdicts()
	get_tree().quit(0)


func _plan_verdict(registration: String) -> void:
	var layout := _best_effort_plan(registration)
	var boat: BoatBody = VesselSpawn.instantiate(HULL_ID, layout, registration)
	add_child(boat)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var meta: Dictionary = boat.get_meta("vessel_outfit", {})
	var caps: Dictionary = boat.get_meta("brick_capabilities", {})
	remove_child(boat)
	boat.queue_free()

	## The checklist itself is not on the meta, so it is re-derived through the
	## same call `apply_plan` made — same plan, same hull, same registration.
	var plan := StructurePlan.from_dict(layout)
	var grid := HullRegistry.make_grid(HULL_ID)
	var report := PlanOutfit.compliance(plan, HULL_ID, registration, grid)
	var checklist: Array = report.get("checklist", [])
	var passed := 0
	for item in checklist:
		if bool((item as Dictionary).get("ok", false)):
			passed += 1
	print("\n===== PLAN vessel, registration %s =====" % registration)
	print("  %d items fitted, %d entities" % [
		(layout.get("items", []) as Array).size(), plan.entity_count()])
	print("  PRODUCTION PATH meta: registration_ok=%s  ok=%s  outfit_ok(caps)=%s" % [
		str(meta.get("registration_ok", "?")), str(meta.get("ok", "?")),
		str(caps.get("outfit_ok", "?"))])
	print("  re-derived report:   registration_ok=%s" % str(report.get("registration_ok", "?")))
	print("  CHECKLIST %d of %d met:" % [passed, checklist.size()])
	for item_raw in checklist:
		var item := item_raw as Dictionary
		print("    [%s] %-22s %-22s current=%s" % [
			"OK " if bool(item.get("ok", false)) else "FAIL",
			str(item.get("id", "")), str(item.get("kind", "")), str(item.get("current", ""))])
	print("  FAILS %d of %d" % [checklist.size() - passed, checklist.size()])


## Everything the catalogue can offer toward the declared registration. If a
## registration cannot be met with every relevant part in the catalogue fitted,
## it cannot be met at all.
func _best_effort_plan(registration: String) -> Dictionary:
	var plan := StructurePlan.new()
	plan.hull_id = HULL_ID
	plan.add_deck(Vector3(1.0, 0.0, 2.0), Vector2(8.0, 20.0))
	## Helm, white light, four mooring points — the general_vessel outfit.
	plan.add_item("helm_console", Vector3(5.0, 0.0, 6.0))
	plan.add_item("lantern_all_round", Vector3(5.0, 2.5, 8.0))
	for i in 4:
		plan.add_item("bollard_pair", Vector3(1.5 + float(i) * 1.5, 0.0, 3.0))
	## Every sidelight-shaped part the catalogue holds, if any ever lands.
	for id in ["lantern_sidelight_port"]:
		if PartCatalog.has(id):
			plan.add_item(id, Vector3(1.0, 1.2, 10.0))
	for id in ["lantern_sidelight_starboard"]:
		if PartCatalog.has(id):
			plan.add_item(id, Vector3(9.0, 1.2, 10.0))
	if registration == "fishing_vessel":
		plan.add_item("net_drum", Vector3(5.0, 0.0, 14.0))
	if registration == "passenger_vessel":
		for i in 3:
			plan.add_item("bench_seat", Vector3(3.0 + float(i) * 1.5, 0.0, 16.0))
		## A door opening, so `egress` has something to count.
		var wall := plan.add_wall(Vector3(3.0, 0.0, 12.0), "x", 4.0, 3.0, 0.2)
		(wall["openings"] as Array).append(
			{"type": StructurePlan.OPENING_DOOR, "offset": 1.0, "width": 1.0, "height": 2.0}
		)
	return plan.to_dict()


func _brick_verdicts() -> void:
	var dir := DirAccess.open(PREBUILT_DIR)
	if dir == null:
		printerr("no prebuilt dir")
		return
	for file in dir.get_files():
		if not file.ends_with(".json"):
			continue
		var text := FileAccess.get_file_as_string("%s/%s" % [PREBUILT_DIR, file])
		var parsed: Variant = JSON.parse_string(text)
		if not (parsed is Dictionary):
			continue
		var doc := parsed as Dictionary
		var hull := str(doc.get("hull_id", HULL_ID))
		var reg := str(doc.get("registration_id", "general_vessel"))
		var layout_dict: Variant = doc.get("brick_layout", doc)
		var layout := BrickLayout.from_dict(layout_dict as Dictionary)
		var report := VesselCompliance.validate(layout, hull, reg, null)
		var checklist: Array = report.get("checklist", [])
		var passed := 0
		var failed := PackedStringArray()
		for item in checklist:
			if bool((item as Dictionary).get("ok", false)):
				passed += 1
			else:
				failed.append(str((item as Dictionary).get("id", "")))
		print("  %-22s hull=%-14s reg=%-18s GEN %s  %d/%d  fails: %s" % [
			file, hull, reg,
			"OK " if bool(report.get("registration_ok", false)) else "NO ",
			passed, checklist.size(), ", ".join(failed)])
