class_name BrickLayout
extends RefCounted

## Sparse voxel fit-out. Cells keyed as "x,y,z" → { brick_id, yaw }.
## yaw is degrees in 90° steps (0, 90, 180, 270).

var cells: Dictionary = {} ## String → Dictionary
var hull_id: String = "workboat"


static func cell_key(cell: Vector3i) -> String:
	return "%d,%d,%d" % [cell.x, cell.y, cell.z]


static func parse_key(key: String) -> Vector3i:
	var parts := key.split(",")
	if parts.size() != 3:
		return Vector3i(-1, -1, -1)
	return Vector3i(int(parts[0]), int(parts[1]), int(parts[2]))


func clear() -> void:
	cells.clear()


func is_empty() -> bool:
	return cells.is_empty()


func count() -> int:
	return cells.size()


func get_brick(cell: Vector3i) -> Dictionary:
	var k := cell_key(cell)
	if not cells.has(k):
		return {}
	return (cells[k] as Dictionary).duplicate(true)


func has_cell(cell: Vector3i) -> bool:
	return cells.has(cell_key(cell))


func set_brick(cell: Vector3i, brick_id: String, yaw: int = 0) -> void:
	cells[cell_key(cell)] = {
		"brick_id": brick_id.strip_edges(),
		"yaw": _norm_yaw(yaw),
	}


func erase_cell(cell: Vector3i) -> void:
	cells.erase(cell_key(cell))


func place_footprint(origin: Vector3i, brick_id: String, yaw: int, grid: DeckGrid) -> bool:
	var fp := BrickCatalog.footprint_of(brick_id)
	var yaw_steps := int(round(float(_norm_yaw(yaw)) / 90.0)) % 4
	var occupied := grid.footprint_cells(origin, fp, yaw_steps)
	for c in occupied:
		if not grid.in_bounds(c):
			return false
		if has_cell(c):
			return false
	# Primary cell stores brick; extras marked as occupied-by.
	var primary := true
	for c in occupied:
		if primary:
			set_brick(c, brick_id, yaw)
			primary = false
		else:
			cells[cell_key(c)] = {
				"brick_id": brick_id.strip_edges(),
				"yaw": _norm_yaw(yaw),
				"occupied_by": cell_key(origin),
			}
	return true


func erase_footprint_at(cell: Vector3i) -> void:
	var entry := get_brick(cell)
	if entry.is_empty():
		return
	var origin_key := str(entry.get("occupied_by", cell_key(cell)))
	var origin := parse_key(origin_key)
	var brick_id := str(entry.get("brick_id", ""))
	var yaw := int(entry.get("yaw", 0))
	var fp := BrickCatalog.footprint_of(brick_id)
	var yaw_steps := int(round(float(_norm_yaw(yaw)) / 90.0)) % 4
	# Approximate erase: remove all cells sharing occupied_by or matching primary.
	var to_remove: Array[String] = []
	for k in cells.keys():
		var e: Dictionary = cells[k]
		if str(e.get("occupied_by", "")) == origin_key or k == origin_key:
			to_remove.append(str(k))
		elif str(e.get("brick_id", "")) == brick_id and parse_key(str(k)) == origin:
			to_remove.append(str(k))
	if to_remove.is_empty():
		# Fallback single cell
		erase_cell(cell)
		return
	for k in to_remove:
		cells.erase(k)
	# Also wipe footprint from origin if grid unknown — scan neighbors of origin.
	if origin.x >= 0:
		for dx in range(maxi(fp.x, fp.z) + 1):
			for dy in range(fp.y + 1):
				for dz in range(maxi(fp.x, fp.z) + 1):
					var c := Vector3i(origin.x + dx, origin.y + dy, origin.z + dz)
					var e2 := get_brick(c)
					if e2.is_empty():
						continue
					if str(e2.get("occupied_by", "")) == origin_key or str(e2.get("brick_id", "")) == brick_id:
						if cell_key(c) == origin_key or str(e2.get("occupied_by", "")) == origin_key:
							erase_cell(c)


func iter_primary_cells() -> Array:
	## Returns [{ cell, brick_id, yaw }, …] skipping occupied-by filler cells.
	var out: Array = []
	for k in cells.keys():
		var e: Dictionary = cells[k]
		if e.has("occupied_by"):
			continue
		out.append({
			"cell": parse_key(str(k)),
			"brick_id": str(e.get("brick_id", "")),
			"yaw": int(e.get("yaw", 0)),
		})
	return out


func count_brick(brick_id: String) -> int:
	var n := 0
	for item in iter_primary_cells():
		if str(item.get("brick_id", "")) == brick_id:
			n += 1
	return n


func count_tag(tag: String) -> int:
	var n := 0
	for item in iter_primary_cells():
		if BrickCatalog.has_tag(str(item.get("brick_id", "")), tag):
			n += 1
	return n


func to_dict() -> Dictionary:
	return {
		"hull_id": hull_id,
		"cells": cells.duplicate(true),
	}


static func from_dict(d: Dictionary) -> BrickLayout:
	var layout := BrickLayout.new()
	layout.hull_id = str(d.get("hull_id", "workboat"))
	var raw: Variant = d.get("cells", {})
	if typeof(raw) == TYPE_DICTIONARY:
		layout.cells = (raw as Dictionary).duplicate(true)
	elif typeof(raw) == TYPE_ARRAY:
		# Alternate array form [{x,y,z,brick_id,yaw}, …]
		for item in raw as Array:
			if typeof(item) != TYPE_DICTIONARY:
				continue
			var e := item as Dictionary
			var cell := Vector3i(int(e.get("x", 0)), int(e.get("y", 0)), int(e.get("z", 0)))
			layout.set_brick(cell, str(e.get("brick_id", "block")), int(e.get("yaw", 0)))
	return layout


static func _norm_yaw(yaw: int) -> int:
	var y := yaw % 360
	if y < 0:
		y += 360
	return int(round(float(y) / 90.0) * 90.0) % 360


## Pre-painted legal starters so players aren't facing an empty 30×24 deck.
static func starter_cargo(hull_id: String, grid: DeckGrid) -> BrickLayout:
	var layout := BrickLayout.new()
	layout.hull_id = hull_id
	_paint_cabin(layout, grid, int(grid.length * 0.65))
	_paint_cargo_mid(layout, grid)
	_paint_edge_railings(layout, grid)
	return layout


static func starter_fishing(hull_id: String, grid: DeckGrid) -> BrickLayout:
	var layout := starter_cargo(hull_id, grid)
	# Stern-ish free of cargo for future fishing bricks; leave open.
	return layout


static func _paint_cabin(layout: BrickLayout, grid: DeckGrid, z0: int) -> void:
	# ~3×2.5 m cabin shell in 1 m cells (solid blocks only — door/window placed by hand).
	var cabin_w := mini(3, grid.width - 2)
	var cabin_l := mini(3, grid.length - 2)
	var x0 := (grid.width - cabin_w) / 2
	var z_start := clampi(z0, 1, grid.length - cabin_l - 1)
	for ix in range(x0, x0 + cabin_w):
		for iz in range(z_start, z_start + cabin_l):
			var on_edge := ix == x0 or ix == x0 + cabin_w - 1 or iz == z_start or iz == z_start + cabin_l - 1
			if on_edge:
				for iy in range(2):
					layout.set_brick(Vector3i(ix, iy, iz), "block", 0)
			else:
				layout.set_brick(Vector3i(ix, 2, iz), "block", 0)


static func _paint_cargo_mid(layout: BrickLayout, grid: DeckGrid) -> void:
	var x0 := 2
	var x1 := grid.width - 3
	var z0 := 2
	var z1 := int(grid.length * 0.55)
	for ix in range(x0, x1 + 1):
		for iz in range(z0, z1 + 1):
			if layout.has_cell(Vector3i(ix, 0, iz)):
				continue
			layout.set_brick(Vector3i(ix, 0, iz), "cargo_tile", 0)


static func _paint_edge_railings(layout: BrickLayout, grid: DeckGrid) -> void:
	for ix in range(grid.width):
		for iz in range(grid.length):
			if not grid.is_edge_cell(ix, iz):
				continue
			var c := Vector3i(ix, 0, iz)
			if layout.has_cell(c):
				continue
			layout.set_brick(c, "railing", 0)
