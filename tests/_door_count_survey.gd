extends SceneTree

## SCRATCH PROBE (leading underscore — not a gate unit).
##
##   xvfb-run -a --server-args="-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy \
##     --script res://tests/_door_count_survey.gd
##
## What `PlanOutfit.opening_count` counting item plates COSTS, fixture by fixture
## and verdict by verdict. Two things changed and they are separated here rather
## than reported as one number:
##
##   OLD    walls[] + decks[] of the plan AS HANDED IN (what shipped)
##   RES    the same two collections, on the RESOLVED plan — isolates the
##          "resolve the placements first" half
##   NEW    walls[] + decks[] + item plates, resolved — the fix
##
## Then every fixture against every registration in the catalogue, so the claim
## "only `passenger_vessel/egress` reads `doors`" is measured and not read off
## the JSON.

const PO := preload("res://scripts/ship/plan_outfit.gd")


func _initialize() -> void:
	PieceKit.ensure_loaded()
	var stems := _stems()
	print("=== doors and windows, per fixture ===")
	print("%-30s %5s %5s %5s | %7s %7s %7s | %s" % [
		"fixture", "dOLD", "dRES", "dNEW", "wOLD", "wRES", "wNEW", "has_cabin",
	])
	var moved := 0
	for stem in stems:
		var plan := _plan(stem)
		if plan == null:
			continue
		var resolved := StructureBaker.resolved(plan)
		var d_old := _legacy_count(plan, StructurePlan.OPENING_DOOR)
		var d_res := _legacy_count(resolved, StructurePlan.OPENING_DOOR)
		var d_new := PO.opening_count(plan, StructurePlan.OPENING_DOOR)
		var w_old := _legacy_count(plan, StructurePlan.OPENING_WINDOW)
		var w_res := _legacy_count(resolved, StructurePlan.OPENING_WINDOW)
		var w_new := PO.opening_count(plan, StructurePlan.OPENING_WINDOW)
		if d_old != d_new or w_old != w_new:
			moved += 1
		print("%-30s %5d %5d %5d | %7d %7d %7d | %s" % [
			stem, d_old, d_res, d_new, w_old, w_res, w_new,
			str(PO.has_cabin(plan)),
		])
	print("%d of %d fixtures move." % [moved, stems.size()])

	print("")
	print("=== every fixture against every registration: does a VERDICT move? ===")
	print("A verdict can only move where `doors` is read, and the only rule that")
	print("reads it is passenger_vessel/egress. Printed: ok, then the rules that fail.")
	var registrations := VesselRegistrationCatalog.ids()
	for stem in stems:
		var plan := _plan(stem)
		if plan == null:
			continue
		for registration in registrations:
			var report := PO.compliance(plan, plan.hull_id, str(registration))
			var failed := PackedStringArray()
			var egress_now := -1
			for item_variant in report.get("checklist", []) as Array:
				var item := item_variant as Dictionary
				if str(item.get("id", "")) == "egress":
					var current: Variant = item.get("current", 0)
					egress_now = int(current) if not (current is String) else -1
				if not bool(item.get("ok", false)):
					failed.append(str(item.get("id", "?")))
			var d_old := _legacy_count(plan, StructurePlan.OPENING_DOOR)
			## Would this verdict have been different before? Only if egress is the
			## rule that moved AND nothing else fails.
			var flips := (
				egress_now >= 1 and d_old == 0
				and failed.size() == 0
			)
			if str(registration) != "passenger_vessel" and not flips:
				continue
			print("  %-28s %-18s ok=%-5s egress current=%d  failing: %s%s" % [
				stem, str(registration), str(bool(report.get("ok", false))),
				egress_now, ", ".join(failed) if not failed.is_empty() else "(none)",
				"   <<< VERDICT FLIPS false -> true" if flips else "",
			])
	quit(0)


## `opening_count` as it shipped: walls and decks only, on whatever it was handed.
static func _legacy_count(plan: StructurePlan, type: String) -> int:
	if plan == null:
		return 0
	var n := 0
	for collection in [plan.walls, plan.decks]:
		for raw in collection as Array:
			if not (raw is Dictionary):
				continue
			var openings: Variant = (raw as Dictionary).get("openings", [])
			if not (openings is Array):
				continue
			for opening_raw in openings as Array:
				if not (opening_raw is Dictionary):
					continue
				if str((opening_raw as Dictionary).get("type", "")) == type:
					n += 1
	return n


static func _stems() -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open("res://resources/data/structures")
	var names := dir.get_files()
	names.sort()
	for name in names:
		if name.ends_with(".json"):
			out.append(name.get_basename())
	return out


static func _plan(stem: String) -> StructurePlan:
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(
			"res://resources/data/structures/%s.json" % stem
		)
	)
	if not (parsed is Dictionary) or not StructurePlan.is_plan(parsed as Dictionary):
		return null
	return StructurePlan.from_dict(parsed as Dictionary)
