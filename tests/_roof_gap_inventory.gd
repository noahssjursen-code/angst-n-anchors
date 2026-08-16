extends SceneTree

## SCRATCH PROBE (leading underscore — not a gate unit).
##
##   xvfb-run -a --server-args="-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy \
##     --script res://tests/_roof_gap_inventory.gd
##
## Every roof gap `PlanOutfit.roof_gaps` finds in the shipped fleet, with the
## cost of the reading, and then ONE MUTATION THE FIXTURES CANNOT HAVE BEEN
## AUTHORED AROUND: `critic_coaster` is clean today, so its wheelhouse roof tile
## is pulled one cell inboard here and the reading must fire. A check that only
## reproduces historical defects has not been shown to catch a new one.

const PO := preload("res://scripts/ship/plan_outfit.gd")


func _initialize() -> void:
	PieceKit.ensure_loaded()
	var dir := DirAccess.open("res://resources/data/structures")
	var names := dir.get_files()
	names.sort()
	var total := 0
	for name in names:
		if not name.ends_with(".json"):
			continue
		var doc := _doc(name.get_basename())
		if doc.is_empty():
			continue
		var plan := StructurePlan.from_dict(doc)
		var t0 := Time.get_ticks_usec()
		var gaps := PO.roof_gaps(plan)
		var ms := float(Time.get_ticks_usec() - t0) / 1000.0
		total += gaps.size()
		print("%-30s %2d gaps  %8.1f ms" % [name.get_basename(), gaps.size(), ms])
		for gap_variant in gaps:
			var gap := gap_variant as Dictionary
			print("      %-12s #%-5s rake %+3d  short %.3f m  %d stations  at %s" % [
				str(gap["piece"]), str(gap["id"]), int(gap["rake"]),
				float(gap["short_m"]), int(gap["stations"]), str(gap["at"]),
			])
	print("%d gaps across the fleet." % total)

	## THE FRESH REGRESSION, and the first attempt at it was a MUTATION THAT
	## PASSED — which is a finding, not a relief (REALITY standing order 8).
	## Shrinking `critic_coaster`'s big roof tiles by a cell all round changed
	## nothing, because the coaster does not seal its raked walls with an eave at
	## all: it works FLUSH. Its front walls rake +4 — exactly 0.500 m, exactly one
	## node — and pieces 12 and 34 are one-cell strips laid AT the raked top, which
	## its own `_is` lines say in those words. That is why the fixture is clean and
	## why "rake 2 was blocked" when it was authored: at rake 2 the head lands
	## 0.250 m off the lattice and no strip can be laid on it.
	##
	## So the mutation that bites is deleting those two strips — the eave that is
	## not an eave.
	print("")
	var doc := _doc("critic_coaster")
	var clean := PO.roof_gaps(StructurePlan.from_dict(doc))
	var kept: Array = []
	var dropped := PackedStringArray()
	for placement_variant in doc["pieces"] as Array:
		var placement := placement_variant as Dictionary
		if [12, 34].has(int(placement.get("id", -1))):
			dropped.append("#%d" % int(placement["id"]))
			continue
		kept.append(placement)
	doc["pieces"] = kept
	var dirty := PO.roof_gaps(StructurePlan.from_dict(doc))
	print("critic_coaster: %d gaps as shipped; with the flush strips %s deleted, %d gaps"
		% [clean.size(), " and ".join(dropped), dirty.size()])
	for gap_variant in dirty:
		var gap := gap_variant as Dictionary
		print("      %-12s #%-5s rake %+3d  short %.3f m  %d stations" % [
			str(gap["piece"]), str(gap["id"]), int(gap["rake"]),
			float(gap["short_m"]), int(gap["stations"]),
		])
	## WAS RAKE 2 EVER BLOCKED? `critic_coaster`'s wheelhouse front is rake +4 and
	## the note on record says it is +4 BECAUSE +2 was blocked. Its roof strips
	## overhang the node line by a whole cell, so they cover a head that lands
	## anywhere inside that cell — which is every rake from 1 to 4. Re-rake its two
	## fronts and their knuckles and measure.
	print("")
	for rake in [1, 2, 3, 4, 5, 6, 8]:
		var raked := _doc("critic_coaster")
		for placement_variant in raked["pieces"] as Array:
			var placement := placement_variant as Dictionary
			var params: Dictionary = placement.get("params", {}) as Dictionary
			for key in ["rake", "rake_a", "rake_b"]:
				if params.has(key) and int(params[key]) == 4:
					params[key] = rake
		var gaps := PO.roof_gaps(StructurePlan.from_dict(raked))
		var worst := 0.0
		for gap_variant in gaps:
			worst = maxf(worst, float((gap_variant as Dictionary)["short_m"]))
		print("critic_coaster with every +4 rake set to +%d: %d gaps, worst %.3f m"
			% [rake, gaps.size(), worst])
	quit(0)


static func _doc(stem: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(
		"res://resources/data/structures/%s.json" % stem
	))
	if not (parsed is Dictionary) or not StructurePlan.is_plan(parsed as Dictionary):
		return {}
	return parsed as Dictionary
