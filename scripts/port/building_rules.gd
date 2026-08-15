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
	for item in layout.iter_primary_cells():
		var cell := item["cell"] as Vector3i
		var brick_id := str(item.get("brick_id", ""))
		var yaw := int(item.get("yaw", 0))
		if not BrickCatalog.has(brick_id):
			errors.append("Unknown brick '%s'." % brick_id)
			continue
		if BrickCatalog.has_tag(brick_id, "ship_only"):
			errors.append("Ship-only brick '%s' cannot be used in buildings." % brick_id)
		var fp := BrickCatalog.footprint_of(brick_id)
		var yaw_steps := int(round(float(yaw) / 90.0)) % 4
		for occupied in grid.footprint_cells(cell, fp, yaw_steps):
			if not grid.in_bounds(occupied):
				## WHAT THIS CAN ACTUALLY CATCH, measured 2026-08-15
				## (`tests/_building_bounds_probe.gd`, pinned by
				## `building_blueprint_test._check_grid_size_warning_is_a_loader_check`):
				## exactly one shape — a cell BELOW the ground plane in a loaded
				## record. `place_footprint` grows the volume through
				## `ensure_fit_cells` before this ever looks, `set_brick` refuses
				## out of bounds outright, and `from_dict`'s
				## `refit_volume_to_content` grows and remaps a positive index
				## (a record's "40,0,40" comes back as "73,0,73"). But
				## `ensure_fit_cells` shifts by `Vector3i(dx, 0, dz)` and grows Y
				## upward only, so a negative y is the one thing no route repairs.
				## Soft on purpose: a stale record is repaired, not refused.
				warnings.append(
					"Brick '%s' at %s sits outside the stored grid_size."
					% [brick_id, BuildingLayout.cell_key(cell)]
				)
				break
		if BrickCatalog.has_tag(brick_id, "door"):
			door_count += 1
	if layout.role != "decorative" and door_count == 0:
		warnings.append("Service building has no door brick.")
	return _result(errors, warnings)


static func _result(errors: PackedStringArray, warnings: PackedStringArray) -> Dictionary:
	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"warnings": warnings,
	}
