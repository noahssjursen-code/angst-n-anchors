extends SceneTree

## Scratch probe (leading underscore — not a gate unit).


func _initialize() -> void:
	var layout := BuildingLayout.new()
	layout.blueprint_id = "roundtrip_house"
	layout.display_name = "Roundtrip House"
	layout.role = "decorative"
	layout.grid_size = Vector3i(8, 6, 8)
	var grid := layout.grid()
	print("foundation ", layout.place_footprint(Vector3i(1, 0, 1), "foundation", 0, grid))
	print("block yaw ", layout.place_footprint(Vector3i(1, 1, 1), "block", 90, grid))
	print("door ", layout.place_footprint(Vector3i(3, 0, 1), "block_door", 0, grid))
	print("count ", layout.count())
	print("painted ", layout.place_footprint(Vector3i(0, 0, 3), "block", 0, null, Color(0.7, 0.2, 0.15)))
	print("floor ", layout.place_footprint(Vector3i(0, 0, 4), "floor", 0))
	print("stack ", layout.place_footprint(Vector3i(0, 0, 4), "block", 0))
	print("erase ", layout.erase_footprint_at(Vector3i(0, 0, 4)))
	print("out-of-grid ", layout.place_footprint(Vector3i(9, 0, 0), "block", 0, grid))
	print("cells keys ", layout.cells.keys())
	var restored := BuildingLayout.from_dict(layout.to_dict())
	print("restored primaries ", restored.iter_primary_cells().size())
	for it in restored.iter_primary_cells():
		print("   ", it)
	print("yaw at 1,1,1 ", restored.get_brick(Vector3i(1, 1, 1)))
	var fit := BuildingFitout.build(restored)
	print("fitout children ", fit.get_child_count())
	for c in fit.get_children():
		print("   child ", c.name)
	fit.free()
	quit()
