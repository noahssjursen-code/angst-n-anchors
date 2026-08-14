extends SceneTree

## SCRATCH PROBE — not a test. Names the collider boxes plan_interior_test's
## stuck marches begin inside, on probe_trawler_bulwark.

const FIXTURE := "res://resources/data/structures/probe_trawler_bulwark.json"
const WANTED := [8, 10, 13, 19, 26, 29, 499, 502]


func _init() -> void:
	var text := FileAccess.get_file_as_string(FIXTURE)
	var plan := StructurePlan.from_dict(JSON.parse_string(text) as Dictionary)
	var boxes := StructureBaker.collect_colliders(plan)
	print("colliders: %d" % boxes.size())
	## Provenance: collect_colliders appends walls, decks, stairs, items, edges,
	## in that order, and each entity's boxes come from the same emitter this
	## calls. No second derivation.
	var owner_of: Dictionary = {}
	var index := 0
	var expanded := StructureBaker.expand(plan)
	for key in ["walls", "decks", "stairs"]:
		for entity_variant in expanded[key] as Array:
			var entity := entity_variant as Dictionary
			var n := 0
			match key:
				"walls": n = StructureBaker.wall_boxes(entity).size()
				"decks": n = StructureBaker.deck_boxes(entity).size()
				"stairs": n = StructureBaker.stair_boxes(entity).size()
			for _i in n:
				owner_of[index] = "%s #%d" % [key, int(entity.get("source_id", -1))]
				index += 1
	for item_variant in plan.items:
		var item := item_variant as Dictionary
		var n := StructureBaker._item_colliders(plan, item, Vector3.ZERO).size()
		var props := StructurePlan.item_props(item)
		var label := str(props.get("__is", props.get("__piece", StructureBaker.item_primitive(item))))
		for _i in n:
			owner_of[index] = "item %d %s" % [int(item.get("id", -1)), label.substr(0, 60)]
			index += 1
	for edge_variant in plan.edges:
		var edge := edge_variant as Dictionary
		for _i in StructureBaker.edge_collider_boxes(plan, edge).size():
			owner_of[index] = "edge %d %s" % [int(edge.get("id", -1)),
				str(edge.get("_is", "")).substr(0, 50)]
			index += 1
	print("attributed %d of %d" % [owner_of.size(), boxes.size()])
	for i in WANTED:
		if i >= boxes.size():
			continue
		var b := boxes[i] as Dictionary
		var c: Vector3 = b["center"]
		var h: Vector3 = (b["size"] as Vector3) * 0.5
		print("  plan_%-4d %-58s c (%.2f, %.2f, %.2f) half (%.2f, %.2f, %.2f) yaw %.1f" % [
			i, str(owner_of.get(i, "?")), c.x, c.y, c.z, h.x, h.y, h.z, float(b["yaw_deg"])])
	quit()
