extends SceneTree

## Scratch probe (leading underscore — not a gate unit). Can `BuildingRules`'
## "sits outside the stored grid_size" warning fire at all, and through which route?


func _init() -> void:
	print("=== route A: place_footprint far outside the declared volume ===")
	var a := BuildingLayout.new()
	a.grid_size = Vector3i(8, 6, 8)
	print("  placed=%s  grid_size=%s  warn=%s" % [
		str(a.place_footprint(Vector3i(40, 0, 40), "block", 0, null)),
		str(a.grid_size), str(_warns(a)),
	])

	print("=== route B: set_brick out of bounds ===")
	var b := BuildingLayout.new()
	b.grid_size = Vector3i(8, 6, 8)
	print("  set=%s  grid_size=%s  warn=%s" % [
		str(b.set_brick(Vector3i(40, 0, 40), "block", 0)), str(b.grid_size), str(_warns(b)),
	])

	print("=== route C: from_dict, positive index outside grid_size ===")
	var c := BuildingLayout.from_dict({
		"grid_size": [8, 6, 8],
		"cells": {"40,0,40": {"brick_id": "block", "yaw": 0}},
	})
	print("  cells=%s  grid_size=%s  warn=%s" % [str(c.cells.keys()), str(c.grid_size), str(_warns(c))])

	print("=== route D: from_dict, NEGATIVE Y (no growth route handles it) ===")
	var d := BuildingLayout.from_dict({
		"grid_size": [8, 6, 8],
		"cells": {"1,-2,1": {"brick_id": "block", "yaw": 0}, "1,0,1": {"brick_id": "block", "yaw": 0}},
	})
	print("  cells=%s  grid_size=%s" % [str(d.cells.keys()), str(d.grid_size)])
	var rd := BuildingRules.validate(d)
	print("  ok=%s warn=%s" % [str(rd.get("ok")), str(rd.get("warnings"))])

	print("=== shipped blueprints ===")
	var dir := DirAccess.open("res://resources/data/buildings")
	if dir != null:
		for name in dir.get_files():
			if not name.ends_with(".json"):
				continue
			var layout := BuildingBlueprintCatalog.load_path(
				"res://resources/data/buildings/%s" % name
			)
			if layout == null:
				print("  %-24s DID NOT LOAD" % name)
				continue
			var neg := 0
			var oob := 0
			var g := layout.grid()
			for key in layout.cells.keys():
				var cell := BuildingLayout.parse_cell_key(str(key))
				if cell.y < 0:
					neg += 1
				if not g.in_bounds(cell):
					oob += 1
			print("  %-24s cells %4d  grid %s  negative-y %d  out of bounds %d  warn=%s" % [
				name, layout.cells.size(), str(layout.grid_size), neg, oob, str(_warns(layout)),
			])
	quit()


func _warns(layout: BuildingLayout) -> PackedStringArray:
	var out := PackedStringArray()
	for w in BuildingRules.validate(layout).get("warnings", PackedStringArray()):
		if str(w).contains("outside the stored grid_size"):
			out.append(str(w))
	return out
