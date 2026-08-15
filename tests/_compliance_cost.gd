extends SceneTree

## SCRATCH PROBE (leading underscore — the gate must not discover this).
##
## What does it cost to tell a builder whether the plan certifies?
##
## Measures, on the 617-entity `probe_container_feeder` and on the small fixtures,
## the three candidate shapes:
##
##   A  fence only          — what `structure_studio._recompute_off_hull` pays today
##   B  compliance()        — the whole verdict, which takes its OWN fence
##   C  A + B               — the naive "add a panel" cost: the fence twice
##
## The argument this settles: is B - A (the measure + evaluate half) small? If it
## is, one shared fence pass buys the panel almost for nothing, and the studio
## should call `compliance` and read the off-hull rows OFF THAT REPORT rather than
## computing the same partition twice.

const PO := preload("res://scripts/ship/plan_outfit.gd")
const DIR := "res://resources/data/structures"

const REPS := 5


func _initialize() -> void:
	for name in ["probe_container_feeder", "demo_workboat", "probe_piece_trawler"]:
		_measure(name)
	quit(0)


func _measure(fixture: String) -> void:
	var path := "%s/%s.json" % [DIR, fixture]
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		print("MISSING %s" % path)
		return
	var doc: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not (doc is Dictionary):
		print("UNPARSEABLE %s" % path)
		return
	var plan := StructurePlan.from_dict(doc as Dictionary)
	var hull_id := plan.hull_id if not plan.hull_id.is_empty() else "hull_28x10"
	var grid := HullRegistry.make_grid(HullRegistry.resolve_network_hull_id(hull_id))

	## Warm every cache the first call would pay for (catalog load, class
	## resolution), so the numbers below are steady-state and not a first-touch.
	var _warm := PO.compliance(plan, hull_id, "general_vessel", grid)
	var _warm2 := PO.off_hull_entities(StructureBaker.resolved(plan), grid)

	var fence_us := 0
	for _i in REPS:
		var t0 := Time.get_ticks_usec()
		var resolved := StructureBaker.resolved(plan)
		var off := PO.off_hull_entities(resolved, grid)
		fence_us += Time.get_ticks_usec() - t0
		if off.size() < 0:
			print("impossible")

	var compliance_us := 0
	var checklist_n := 0
	var met := 0
	for _i in REPS:
		var t0 := Time.get_ticks_usec()
		var report := PO.compliance(plan, hull_id, "general_vessel", grid)
		compliance_us += Time.get_ticks_usec() - t0
		checklist_n = (report.get("checklist", []) as Array).size()
		met = 0
		for raw in report.get("checklist", []) as Array:
			if bool((raw as Dictionary).get("ok", false)):
				met += 1

	## What a full studio rebake pays today, for scale: the bake itself.
	var bake_us := 0
	for _i in REPS:
		var t0 := Time.get_ticks_usec()
		var baked := StructureBaker.bake(StructureBaker.resolved(plan), Vector3.ZERO)
		bake_us += Time.get_ticks_usec() - t0
		baked.free()

	var fence_ms := float(fence_us) / float(REPS) / 1000.0
	var compliance_ms := float(compliance_us) / float(REPS) / 1000.0
	var bake_ms := float(bake_us) / float(REPS) / 1000.0
	print(
		"%-26s entities=%4d  fence=%7.2f ms  compliance=%7.2f ms  (delta %6.2f ms)  bake=%7.2f ms  |  naive A+B=%7.2f ms  shared=%7.2f ms  |  %d/%d met"
		% [
			fixture, plan.entity_count(), fence_ms, compliance_ms,
			compliance_ms - fence_ms, bake_ms,
			fence_ms + compliance_ms, compliance_ms,
			met, checklist_n,
		]
	)
