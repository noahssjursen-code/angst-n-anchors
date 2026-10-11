class_name BuildingRules
extends RefCounted

## Structural checks are intentionally small and deterministic. Authoring stays
## flexible, while malformed or floating blueprints cannot enter the catalog.


static func validate(layout: BuildingLayout) -> Dictionary:
	var errors: PackedStringArray = []
	var warnings: PackedStringArray = []
	if layout == null:
		errors.append("Layout is missing.")
		return _result(errors, warnings)
	# Blueprint id is the JSON filename stem — assigned at save/load, not typed.
	if layout.cells.is_empty():
		warnings.append("Building contains no bricks.")

	var grid := layout.grid()
	var door_count := 0
	var invalid_bricks: Dictionary = {}
	for item in layout.iter_primary_cells():
		var cell := item["cell"] as Vector3i
		var brick_id := str(item.get("brick_id", ""))
		var yaw := int(item.get("yaw", 0))
		if not BrickCatalog.has(brick_id):
			var reason := "Unknown brick '%s'" % brick_id
			invalid_bricks[reason] = int(invalid_bricks.get(reason, 0)) + 1
			continue
		if BrickCatalog.has_tag(brick_id, "ship_only"):
			var reason := "Ship-only brick '%s' cannot be used in buildings" % brick_id
			invalid_bricks[reason] = int(invalid_bricks.get(reason, 0)) + 1
		var fp := BrickCatalog.footprint_of(brick_id)
		var yaw_steps := int(round(float(yaw) / 90.0)) % 4
		for occupied in grid.footprint_cells(cell, fp, yaw_steps):
			if not grid.in_bounds(occupied):
				# Volume should have grown with the build; treat as a soft warn.
				warnings.append(
					"Brick '%s' at %s sits outside the stored grid_size."
					% [brick_id, BuildingLayout.cell_key(cell)]
				)
				break
		if BrickCatalog.has_tag(brick_id, "door"):
			door_count += 1
	# Thousands of cells can reference the same missing asset. Keep validation
	# strict, but report each problem once with its affected placement count.
	var reasons := invalid_bricks.keys()
	reasons.sort()
	for reason in reasons:
		errors.append("%s (%d placements)." % [reason, invalid_bricks[reason]])
	if layout.role != "decorative" and door_count == 0:
		warnings.append("Service building has no door brick.")
	return _result(errors, warnings)


static func _result(errors: PackedStringArray, warnings: PackedStringArray) -> Dictionary:
	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"warnings": warnings,
	}
