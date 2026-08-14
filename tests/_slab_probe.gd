extends SceneTree

## SCRATCH PROBE — not a test. How a plate's collider boxes split between panels
## and opening casings, and what the whole deckhouse costs.

const FIXTURE := "res://resources/data/structures/probe_plate_deckhouse.json"


func _init() -> void:
	var doc := JSON.parse_string(FileAccess.get_file_as_string(FIXTURE)) as Dictionary
	var plan := StructurePlan.from_dict(doc)
	var total := 0
	var frames := 0
	for item_variant in plan.items:
		var item := item_variant as Dictionary
		if StructureBaker.item_primitive(item) != "plate":
			continue
		var spec := StructurePlan.item_props(item)
		var corners := StructureBaker._transformed(
			StructureBaker.plate_corners(spec), plan.item_transform(item)
		)
		var panel_boxes := 0
		var frame_boxes := 0
		for slab_variant in StructureBaker.plate_slabs(spec):
			var slab := slab_variant as Dictionary
			var n: int = StructureBaker._plate_panel_colliders(
				corners, float(slab["thickness"]), Vector3.ZERO,
				float(slab["u0"]), float(slab["u1"]), float(slab["v0"]), float(slab["v1"])
			).size()
			if bool(slab["frame"]):
				frame_boxes += n
			else:
				panel_boxes += n
		total += panel_boxes + frame_boxes
		frames += frame_boxes
		print("item %4d  panels %3d  casings %3d  total %3d"
			% [int(item.get("id", -1)), panel_boxes, frame_boxes, panel_boxes + frame_boxes])
	print("PLAN total %d boxes (%d panels, %d casings); collect_colliders %d"
		% [total, total - frames, frames, StructureBaker.collect_colliders(plan).size()])
	quit()
