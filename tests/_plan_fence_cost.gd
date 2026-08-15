extends SceneTree

## Scratch probe (leading underscore — NOT a gate unit).
## What does the hull fence COST on the biggest shipped plan? `apply_plan` runs
## it once; `PlanOutfit.compliance` runs it twice more (validate + measure).

const DIR := "res://resources/data/structures/"
const PO := preload("res://scripts/ship/plan_outfit.gd")


func _init() -> void:
	for f in ["probe_container_feeder.json", "probe_piece_trawler.json", "demo_workboat.json"]:
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DIR + f))
		var plan := StructurePlan.from_dict(parsed as Dictionary)
		var grid := HullRegistry.make_grid(plan.hull_id)
		var t0 := Time.get_ticks_usec()
		var boxes := StructureBaker.collect_colliders(plan).size()
		var t1 := Time.get_ticks_usec()
		var off := PO.off_hull_entities(plan, grid).size()
		var t2 := Time.get_ticks_usec()
		var built := PO.on_hull_plan(plan, grid)
		var t3 := Time.get_ticks_usec()
		var report := PO.compliance(plan, plan.hull_id, "general_vessel", grid)
		var t4 := Time.get_ticks_usec()
		print(
			"  %-28s boxes %5d  collect %6.1f ms | off_hull %6.1f ms | on_hull_plan %6.1f ms"
			% [f, boxes, (t1 - t0) / 1000.0, (t2 - t1) / 1000.0, (t3 - t2) / 1000.0]
			+ " | compliance %6.1f ms | refused %d, kept %d entities, ok %s"
			% [(t4 - t3) / 1000.0, off, built.entity_count(), report.get("ok")]
		)
	quit(0)
