extends SceneTree

## SCRATCH PROBE (leading underscore — the gate skips it in both lanes).
##
## Settles the hypothesis STATE.md left open when the door fix took
## `plan_interior_test` from 1/56 to 2/56.
##
## The critic measured DRAWN -> COLLIDER containment: 310,200 samples, deepest
## escape 4 µm. That does NOT answer this, because it is the other direction.
## "Every drawn point is inside some collider" is satisfied perfectly by a
## collider that is far too FAT — and a fat collider is exactly what makes a
## wall march start inside something, which is the regression.
##
## So: how much THICKER is the box the baker emits than the plate it is fitted
## to? `_plate_panel_colliders` dices a slab into cells and fits each cell a
## yaw-frame AABB of its four corners offset ±thickness/2. For a plumb plate that
## AABB is the plate. For a RAKED one it is not — a tilted quad's AABB exceeds
## the quad, which is the "staircase of cells" the critic named. That excess is
## real solid space a body can start inside, and it is not drawn anywhere.
##
## Reported per fixture as the worst excess over the slab's own thickness, and
## separately for casing members, since the casing is what the door fix added to
## the collider set and therefore what could have caused the regression.

const FIXTURES := [
	"res://resources/data/structures/demo_workboat.json",
	"res://resources/data/structures/probe_trawler_bulwark.json",
]


func _initialize() -> void:
	for path in FIXTURES:
		_survey(str(path))
	quit()


func _survey(path: String) -> void:
	var doc := JSON.parse_string(FileAccess.get_file_as_string(path)) as Dictionary
	if doc == null:
		print("%s: could not parse" % path)
		return
	var plan := StructurePlan.from_dict(doc)

	var worst_any := 0.0
	var worst_frame := 0.0
	var note_any := ""
	var note_frame := ""
	var boxes := 0
	var frame_boxes := 0

	for item_variant in plan.items:
		var item := item_variant as Dictionary
		if StructureBaker.item_primitive(item) != "plate":
			continue
		var props := StructurePlan.item_props(item)
		var note := str(props.get("__is", ""))
		var corners := StructureBaker.plate_corners(props)
		if corners.size() != 4:
			continue
		for slab_variant in StructureBaker.plate_slabs(props):
			var slab := slab_variant as Dictionary
			var thickness := float(slab["thickness"])
			var is_frame := bool(slab.get("frame", false))
			var cells: Array = StructureBaker._plate_panel_colliders(
				corners, thickness, Vector3.ZERO,
				float(slab["u0"]), float(slab["u1"]),
				float(slab["v0"]), float(slab["v1"]),
			)
			for cell_variant in cells:
				var size := (cell_variant as Dictionary)["size"] as Vector3
				## The thinnest axis of the box IS its thickness axis; anything
				## above the slab's own thickness is solid space nothing draws.
				var thinnest := minf(size.x, minf(size.y, size.z))
				var excess := thinnest - thickness
				boxes += 1
				if excess > worst_any:
					worst_any = excess
					note_any = note.substr(0, 44)
				if is_frame:
					frame_boxes += 1
					if excess > worst_frame:
						worst_frame = excess
						note_frame = note.substr(0, 44)

	print("%s" % path.get_file())
	print("   %d collider boxes (%d of them casing)" % [boxes, frame_boxes])
	print("   worst thickness EXCESS over what is drawn:")
	print("      any slab   %.4f m   on: %s" % [worst_any, note_any])
	print("      casing     %.4f m   on: %s" % [worst_frame, note_frame])
