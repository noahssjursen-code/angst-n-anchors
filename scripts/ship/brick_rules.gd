class_name BrickRules
extends RefCounted

## Free-build: no placement legality. Only derives gameplay capabilities from the layout.


static func validate(layout: BrickLayout, grid: DeckGrid, _max_height: int = 0, _max_bricks: int = 0) -> Dictionary:
	## Always ok. Returns { ok, errors, warnings, capabilities }.
	var errors: PackedStringArray = []
	var warnings: PackedStringArray = []
	if layout == null:
		return _result(true, errors, warnings, {})

	var brick_n := layout.count()
	var max_y := 0
	var crane_n := 0
	var crane_base_n := 0
	var door_n := 0
	var wall_n := 0
	var window_n := 0
	var cargo_n := 0

	for item in layout.iter_primary_cells():
		var cell: Vector3i = item["cell"]
		var brick_id := str(item.get("brick_id", ""))
		if not BrickCatalog.has(brick_id):
			continue
		max_y = maxi(max_y, cell.y + BrickCatalog.footprint_of(brick_id).y - 1)
		if BrickCatalog.has_tag(brick_id, "crane"):
			crane_n += 1
		if BrickCatalog.has_tag(brick_id, "crane_base"):
			crane_base_n += 1
		if BrickCatalog.has_tag(brick_id, "door"):
			door_n += 1
		if BrickCatalog.has_tag(brick_id, "wall") or BrickCatalog.has_tag(brick_id, "solid"):
			wall_n += 1
		if BrickCatalog.has_tag(brick_id, "window"):
			window_n += 1
		if BrickCatalog.has_tag(brick_id, "cargo"):
			cargo_n += 1
		if grid != null and not grid.in_bounds(cell):
			# Still free-build — just skip counting wild cells.
			pass

	var caps := {
		"cargo_cells": cargo_n,
		"has_cabin": door_n >= 1 or wall_n >= 8,
		"has_crane": crane_n >= 1,
		"doors": door_n,
		"windows": window_n,
		"brick_count": brick_n,
		"max_stack_y": max_y,
	}
	return _result(true, errors, warnings, caps)


static func _result(ok: bool, errors: PackedStringArray, warnings: PackedStringArray, caps: Dictionary) -> Dictionary:
	return {
		"ok": ok,
		"errors": errors,
		"warnings": warnings,
		"capabilities": caps,
	}
