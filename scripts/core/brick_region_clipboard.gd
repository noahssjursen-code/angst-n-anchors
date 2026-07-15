class_name BrickRegionClipboard
extends RefCounted

## Copy/paste helpers for sparse brick layouts (ships and buildings).
## Stores cells relative to the mark's min corner so paste can stamp elsewhere.


static func bounds_from_corners(a: Vector3i, b: Vector3i) -> Dictionary:
	return {
		"min": Vector3i(mini(a.x, b.x), mini(a.y, b.y), mini(a.z, b.z)),
		"max": Vector3i(maxi(a.x, b.x), maxi(a.y, b.y), maxi(a.z, b.z)),
	}


static func cell_in_bounds(cell: Vector3i, min_c: Vector3i, max_c: Vector3i) -> bool:
	return (
		cell.x >= min_c.x and cell.x <= max_c.x
		and cell.y >= min_c.y and cell.y <= max_c.y
		and cell.z >= min_c.z and cell.z <= max_c.z
	)


static func parse_key(key: String) -> Vector3i:
	var parts := key.split(",")
	if parts.size() != 3:
		return Vector3i(-1, -1, -1)
	return Vector3i(int(parts[0]), int(parts[1]), int(parts[2]))


static func cell_key(cell: Vector3i) -> String:
	return "%d,%d,%d" % [cell.x, cell.y, cell.z]


static func extract_region(cells: Dictionary, min_c: Vector3i, max_c: Vector3i) -> Dictionary:
	var extracted: Dictionary = {}
	for key in cells.keys():
		var cell := parse_key(str(key))
		if not cell_in_bounds(cell, min_c, max_c):
			continue
		var rel := cell - min_c
		var entry := (cells[key] as Dictionary).duplicate(true)
		if entry.has("occupied_by"):
			var origin := parse_key(str(entry["occupied_by"]))
			entry["occupied_by"] = cell_key(origin - min_c)
		extracted[cell_key(rel)] = entry
	return {
		"min": min_c,
		"max": max_c,
		"cells": extracted,
		"cell_count": extracted.size(),
	}


static func can_paste(
	clipboard: Dictionary,
	dest_anchor: Vector3i,
	existing_cells: Dictionary,
	cell_allowed: Callable,
) -> bool:
	var clip_cells: Dictionary = clipboard.get("cells", {})
	if clip_cells.is_empty():
		return false
	for rel_key in clip_cells.keys():
		var rel := parse_key(str(rel_key))
		if rel.x < 0:
			return false
		var dest := dest_anchor + rel
		if not bool(cell_allowed.call(dest)):
			return false
		if existing_cells.has(cell_key(dest)):
			return false
	return true


static func paste_region(
	clipboard: Dictionary,
	dest_anchor: Vector3i,
	cells: Dictionary,
) -> Dictionary:
	var merged := cells.duplicate(true)
	var clip_cells: Dictionary = clipboard.get("cells", {})
	for rel_key in clip_cells.keys():
		var rel := parse_key(str(rel_key))
		if rel.x < 0:
			continue
		var dest := dest_anchor + rel
		merged[cell_key(dest)] = (clip_cells[rel_key] as Dictionary).duplicate(true)
	return merged


static func size_cells(clipboard: Dictionary) -> Vector3i:
	var min_c: Vector3i = clipboard.get("min", Vector3i.ZERO)
	var max_c: Vector3i = clipboard.get("max", Vector3i.ZERO)
	return Vector3i(
		maxi(max_c.x - min_c.x + 1, 0),
		maxi(max_c.y - min_c.y + 1, 0),
		maxi(max_c.z - min_c.z + 1, 0),
	)


static func iter_dest_cells(clipboard: Dictionary, dest_anchor: Vector3i) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	var clip_cells: Dictionary = clipboard.get("cells", {})
	for rel_key in clip_cells.keys():
		var rel := parse_key(str(rel_key))
		if rel.x < 0:
			continue
		out.append(dest_anchor + rel)
	return out
