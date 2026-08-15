extends SceneTree

## Scratch probe (leading underscore — NOT a gate unit).
## WHICH shipped entities does `PlanOutfit.off_hull_entities` refuse, and by how
## much do they miss? Run after any change to the fence.

const DIR := "res://resources/data/structures/"
const PO := preload("res://scripts/ship/plan_outfit.gd")


func _init() -> void:
	var names := PackedStringArray()
	var d := DirAccess.open(DIR)
	for f in d.get_files():
		if f.ends_with(".json"):
			names.append(f)
	names.sort()
	var total := 0
	for f in names:
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DIR + f))
		if not (parsed is Dictionary):
			continue
		var plan := StructurePlan.from_dict(parsed as Dictionary)
		if plan.context != "vessel" or plan.hull_id.is_empty():
			continue
		var grid := HullRegistry.make_grid(plan.hull_id)
		if grid == null:
			continue
		var resolved := StructureBaker.resolved(plan)
		var by_kind := {
			"wall": resolved.walls, "deck": resolved.decks, "stair": resolved.stairs,
			"item": resolved.items, "edge": resolved.edges,
		}
		for row_variant in StructureBaker.entity_colliders(resolved):
			var row := row_variant as Dictionary
			var kind := str(row["kind"])
			var index := int(row["index"])
			var collection := by_kind.get(kind, []) as Array
			var entity: Dictionary = (
				collection[index] as Dictionary if index < collection.size() else {}
			)
			var points := PO.hull_test_points(resolved, kind, entity, row["boxes"] as Array)
			if PO.on_hull_points(points, grid):
				continue
			total += 1
			var worst := -INF
			var worst_at := Vector2.ZERO
			for point in points:
				var out := maxf(
					maxf(-point.x, point.x - float(grid.width) * 0.5),
					maxf(-point.y, point.y - float(grid.length) * 0.5)
				)
				if out > worst:
					worst = out
					worst_at = point
			print(
				"  %-30s %-5s #%-4d %-18s boxes %3d  worst corner %+7.2f m out "
				% [f, kind, int(row["id"]), str(entity.get("item_id", "")),
					(row["boxes"] as Array).size(), worst]
				+ "at (%.2f, %.2f), margin %.2f  props %s"
				% [worst_at.x, worst_at.y, grid.half_beam,
					StructurePlan.item_props(entity)]
			)
	print("  %d refused" % total)
	quit(0)
