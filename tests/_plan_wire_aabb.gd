extends SceneTree
## Scratch probe. Does the wire/catalog disagreement still bite the two OTHER
## readers of part_local_aabb — item_footprint_cells and max_stack_cells?
const DIR := "res://resources/data/structures/"
const PO := preload("res://scripts/ship/plan_outfit.gd")

func _init() -> void:
	for f in ["demo_workboat.json", "probe_trawler_bulwark.json"]:
		var plan := StructurePlan.from_dict(
			JSON.parse_string(FileAccess.get_file_as_string(DIR + f)) as Dictionary
		)
		var grid := HullRegistry.make_grid(plan.hull_id)
		var worst_wire := 0.0
		var worst_id := -1
		var drawn_top := 0.0
		for raw in plan.items:
			var item := raw as Dictionary
			if StructureBaker.item_primitive(item) != "wire":
				continue
			var box := PO.part_local_aabb(str(item.get("item_id", "")), StructurePlan.item_props(item))
			if not bool(box.get("ok", false)):
				continue
			var origin_y := plan.item_transform(item).origin.y
			var catalog_top: float = origin_y + (box["max"] as Vector3).y
			var real_top := origin_y
			for point in StructureBaker.spar_path(StructurePlan.item_props(item)):
				real_top = maxf(real_top, (plan.item_transform(item) * point).y)
			if catalog_top - real_top > worst_wire:
				worst_wire = catalog_top - real_top
				worst_id = int(item.get("id", -1))
				drawn_top = real_top
			var cells := PO.item_footprint_cells(plan, item, grid)
			var off := 0
			for cell in cells:
				if not grid.has_deck_cell(cell):
					off += 1
			if off > 0:
				print("  %s wire #%d claims %d footprint cells, %d of them off the deck"
					% [f, int(item.get("id", -1)), cells.size(), off])
		print("  %-28s max_stack overstate from a wire: %+.2f m (item #%d, drawn top %.2f m)"
			% [f, worst_wire, worst_id, drawn_top])
		print("  %-28s max_stack_cells reports %d cells = %.1f m"
			% [f, PO.max_stack_cells(plan, grid), PO.max_stack_cells(plan, grid) * 0.5])
	quit(0)
