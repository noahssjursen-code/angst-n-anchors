extends Node3D

## SCRATCH PROBE (leading underscore). One Structure Studio rebake on the
## 617-entity container feeder, and the three costs the checklist decision turns
## on — all in ONE process, because run-to-run variance on this box is ~5 % and
## comparing two separate runs of a 340 ms number cannot see a 20 ms effect.
##
##   rebake        `_rebake()` as shipped: two bakes, bounds, ONE compliance pass
##   compliance    what that one pass costs
##   fence         what `off_hull_entities` alone costs — the c531076 behaviour
##
## before = rebake - compliance + fence   (the studio at c531076)
## naive  = rebake + fence                (a panel that takes its own partition)

const PO := preload("res://scripts/ship/plan_outfit.gd")
const REPS := 9


func _ready() -> void:
	var studio: Node = load("res://scenes/apps/structure_studio.tscn").instantiate()
	add_child(studio)
	await get_tree().process_frame
	studio.call("_load_plan", "res://resources/data/structures/probe_container_feeder.json")
	await get_tree().process_frame
	var plan = studio.get("_plan")
	var grid = studio.get("_deck_grid")
	var hull := str(studio.get("_hull_id"))
	print("hull=%s grid=%dx%d off_hull=%d" % [
		hull, grid.width, grid.length, (studio.get("_off_hull") as Array).size()
	])

	var rebake := 0
	for _i in REPS:
		var t0 := Time.get_ticks_usec()
		studio.call("_rebake")
		rebake += Time.get_ticks_usec() - t0
	var compliance := 0
	for _i in REPS:
		var t0 := Time.get_ticks_usec()
		var _r := PO.compliance(plan, hull, "general_vessel", grid)
		compliance += Time.get_ticks_usec() - t0
	var fence := 0
	for _i in REPS:
		var t0 := Time.get_ticks_usec()
		var _o := PO.off_hull_entities(StructureBaker.resolved(plan), grid)
		fence += Time.get_ticks_usec() - t0

	var ms := func(total: int) -> float: return float(total) / float(REPS) / 1000.0
	var after: float = ms.call(rebake)
	var comp: float = ms.call(compliance)
	var fen: float = ms.call(fence)
	print("entities=%d reps=%d" % [plan.entity_count(), REPS])
	print("  compliance      %7.2f ms" % comp)
	print("  fence alone     %7.2f ms" % fen)
	print("  verdict half    %7.2f ms" % (comp - fen))
	print("  BEFORE rebake   %7.2f ms  (c531076: fence only)" % (after - comp + fen))
	print("  AFTER  rebake   %7.2f ms  (+%.2f ms, +%.1f %%)" % [
		after, comp - fen, (comp - fen) / (after - comp + fen) * 100.0
	])
	print("  NAIVE  rebake   %7.2f ms  (+%.2f ms, +%.1f %%)" % [
		after + fen, comp, comp / (after - comp + fen) * 100.0
	])
	get_tree().quit(0)
