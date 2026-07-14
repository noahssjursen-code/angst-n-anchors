class_name BrickLayout
extends RefCounted

## Sparse voxel fit-out. Cells keyed as "x,y,z" → { brick_id, yaw }.
## yaw is degrees in 90° steps (0, 90, 180, 270).
## Cargo is NOT per-cell bricks — it is one or more deck rectangles {a,b}.

var cells: Dictionary = {} ## String → Dictionary
var cargo_zones: Array = [] ## [{ "a": [x,y,z], "b": [x,y,z] }, …] inclusive corners
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
	cargo_zones.clear()


func is_empty() -> bool:
	return cells.is_empty() and cargo_zones.is_empty()


func count() -> int:
	return cells.size()


func get_brick(cell: Vector3i) -> Dictionary:
	var k := cell_key(cell)
	if not cells.has(k):
		return {}
	return (cells[k] as Dictionary).duplicate(true)


func has_cell(cell: Vector3i) -> bool:
	return cells.has(cell_key(cell))


func set_brick(cell: Vector3i, brick_id: String, yaw: int = 0, props: Dictionary = {}) -> void:
	var id := brick_id.strip_edges()
	var entry := {
		"brick_id": id,
		"yaw": norm_yaw_step(yaw, BrickCatalog.yaw_step_of(id)),
	}
	if props.has("text"):
		entry["text"] = str(props["text"])
	var painted := color_to_array(props.get("color", null))
	if not painted.is_empty():
		entry["color"] = painted
	## Preserve a mounted sign when replacing non-text bricks? No — full replace.
	cells[cell_key(cell)] = entry


func primary_cell_of(cell: Vector3i) -> Vector3i:
	## Walk occupied_by back to the footprint origin.
	var e := get_brick(cell)
	if e.is_empty():
		return cell
	if e.has("occupied_by"):
		return parse_key(str(e.get("occupied_by", cell_key(cell))))
	return cell


func attach_sign(cell: Vector3i, sign_id: String, yaw: int, text: String) -> bool:
	## Mount a sign on an existing brick without removing it (wall plaques, etc.).
	if not BrickCatalog.has_tag(sign_id, "text"):
		return false
	var origin := primary_cell_of(cell)
	var e := get_brick(origin)
	if e.is_empty():
		return false
	if BrickCatalog.has_tag(str(e.get("brick_id", "")), "text"):
		return false
	e = e.duplicate(true)
	e["sign_id"] = sign_id.strip_edges()
	e["sign_yaw"] = _norm_yaw(yaw)
	e["text"] = text
	cells[cell_key(origin)] = e
	return true


func clear_sign(cell: Vector3i) -> bool:
	var origin := primary_cell_of(cell)
	var e := get_brick(origin)
	if e.is_empty() or not e.has("sign_id"):
		return false
	e = e.duplicate(true)
	e.erase("sign_id")
	e.erase("sign_yaw")
	## Keep "text" only if the brick itself is a text brick.
	if not BrickCatalog.has_tag(str(e.get("brick_id", "")), "text"):
		e.erase("text")
	cells[cell_key(origin)] = e
	return true


func has_sign(cell: Vector3i) -> bool:
	var e := get_brick(primary_cell_of(cell))
	return not e.is_empty() and e.has("sign_id")


func attach_light(cell: Vector3i, light_id: String, yaw: int) -> bool:
	## Mount a fixture on an existing brick (wall / block) — same idea as wall text.
	if not BrickCatalog.has_tag(light_id, "light"):
		return false
	var origin := primary_cell_of(cell)
	var e := get_brick(origin)
	if e.is_empty():
		return false
	if BrickCatalog.has_tag(str(e.get("brick_id", "")), "light"):
		return false
	e = e.duplicate(true)
	e["light_id"] = light_id.strip_edges()
	e["light_yaw"] = norm_yaw_step(yaw, 45)
	cells[cell_key(origin)] = e
	return true


func clear_light(cell: Vector3i) -> bool:
	var origin := primary_cell_of(cell)
	var e := get_brick(origin)
	if e.is_empty() or not e.has("light_id"):
		return false
	e = e.duplicate(true)
	e.erase("light_id")
	e.erase("light_yaw")
	cells[cell_key(origin)] = e
	return true


func has_light(cell: Vector3i) -> bool:
	var e := get_brick(primary_cell_of(cell))
	return not e.is_empty() and e.has("light_id")


func erase_cell(cell: Vector3i) -> void:
	cells.erase(cell_key(cell))


func place_footprint(
	origin: Vector3i,
	brick_id: String,
	yaw: int,
	grid: DeckGrid,
	props: Dictionary = {},
) -> bool:
	var fp := BrickCatalog.footprint_of(brick_id)
	var step := BrickCatalog.yaw_step_of(brick_id)
	var yaw_n := norm_yaw_step(yaw, step)
	## Footprint occupancy still uses 90° cardinals (grid cells don't rotate at 45°).
	var yaw_steps := int(round(float(yaw_n) / 90.0)) % 4
	var occupied := grid.footprint_cells(origin, fp, yaw_steps)
	var allow_on_cargo := BrickCatalog.has_tag(brick_id, "text")
	for c in occupied:
		if grid.is_partial_bow_cell(c):
			if (
				not BrickCatalog.has_tag(brick_id, "diagonal_plan")
				or occupied.size() != 1
				or yaw_n != grid.partial_bow_yaw_degrees(c)
			):
				return false
		elif not grid.in_bounds(c):
			return false
		if has_cell(c):
			return false
		if not allow_on_cargo and cargo_contains(c):
			return false
	# Primary cell stores brick; extras marked as occupied-by.
	var primary := true
	var painted := color_to_array(props.get("color", null))
	for c in occupied:
		if primary:
			set_brick(c, brick_id, yaw_n, props)
			primary = false
		else:
			var filler := {
				"brick_id": brick_id.strip_edges(),
				"yaw": yaw_n,
				"occupied_by": cell_key(origin),
			}
			if not painted.is_empty():
				filler["color"] = painted.duplicate()
			cells[cell_key(c)] = filler
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
	var to_remove: Array[String] = []
	for k in cells.keys():
		var e: Dictionary = cells[k]
		if str(e.get("occupied_by", "")) == origin_key or k == origin_key:
			to_remove.append(str(k))
		elif str(e.get("brick_id", "")) == brick_id and parse_key(str(k)) == origin:
			to_remove.append(str(k))
	if to_remove.is_empty():
		erase_cell(cell)
		return
	for k in to_remove:
		cells.erase(k)
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


# ── Cargo zones (inclusive corner rects on the deck) ─────────────────────────

static func normalize_cargo_rect(a: Vector3i, b: Vector3i) -> Dictionary:
	var min_x := mini(a.x, b.x)
	var max_x := maxi(a.x, b.x)
	var min_z := mini(a.z, b.z)
	var max_z := maxi(a.z, b.z)
	var y := 0
	return {
		"a": [min_x, y, min_z],
		"b": [max_x, y, max_z],
	}


static func zone_min(zone: Dictionary) -> Vector3i:
	var a: Array = zone.get("a", [0, 0, 0]) as Array
	var b: Array = zone.get("b", [0, 0, 0]) as Array
	return Vector3i(
		mini(int(a[0]), int(b[0])),
		0,
		mini(int(a[2]) if a.size() > 2 else 0, int(b[2]) if b.size() > 2 else 0),
	)


static func zone_max(zone: Dictionary) -> Vector3i:
	var a: Array = zone.get("a", [0, 0, 0]) as Array
	var b: Array = zone.get("b", [0, 0, 0]) as Array
	return Vector3i(
		maxi(int(a[0]), int(b[0])),
		0,
		maxi(int(a[2]) if a.size() > 2 else 0, int(b[2]) if b.size() > 2 else 0),
	)


static func zone_cell_count(zone: Dictionary) -> int:
	var mn := zone_min(zone)
	var mx := zone_max(zone)
	return (mx.x - mn.x + 1) * (mx.z - mn.z + 1)


static func zone_contains_cell(zone: Dictionary, cell: Vector3i) -> bool:
	if cell.y != 0:
		return false
	var mn := zone_min(zone)
	var mx := zone_max(zone)
	return cell.x >= mn.x and cell.x <= mx.x and cell.z >= mn.z and cell.z <= mx.z


func cargo_contains(cell: Vector3i) -> bool:
	return cargo_zone_index_at(cell) >= 0


func cargo_zone_index_at(cell: Vector3i) -> int:
	for i in range(cargo_zones.size()):
		if zone_contains_cell(cargo_zones[i] as Dictionary, cell):
			return i
	return -1


func add_cargo_zone(a: Vector3i, b: Vector3i) -> bool:
	## Replaces any overlapping zones. Fails if brick cells sit inside the rect.
	var zone := normalize_cargo_rect(a, b)
	var mn := zone_min(zone)
	var mx := zone_max(zone)
	for ix in range(mn.x, mx.x + 1):
		for iz in range(mn.z, mx.z + 1):
			if has_cell(Vector3i(ix, 0, iz)):
				return false
	# Drop overlapping zones so one click-drag region stays a single pad.
	var keep: Array = []
	for z in cargo_zones:
		var zd := z as Dictionary
		if _zones_overlap(zd, zone):
			continue
		keep.append(zd)
	keep.append(zone)
	cargo_zones = keep
	return true


func erase_cargo_zone_at(cell: Vector3i) -> bool:
	var idx := cargo_zone_index_at(cell)
	if idx < 0:
		return false
	cargo_zones.remove_at(idx)
	return true


func cargo_cell_count() -> int:
	var n := 0
	for z in cargo_zones:
		n += zone_cell_count(z as Dictionary)
	return n


func iter_cargo_zones() -> Array:
	return cargo_zones.duplicate(true)


static func _zones_overlap(a: Dictionary, b: Dictionary) -> bool:
	var amn := zone_min(a)
	var amx := zone_max(a)
	var bmn := zone_min(b)
	var bmx := zone_max(b)
	return not (amx.x < bmn.x or bmx.x < amn.x or amx.z < bmn.z or bmx.z < amn.z)


func iter_primary_cells() -> Array:
	## Returns [{ cell, brick_id, yaw }, …] skipping occupied-by filler cells.
	## Cargo zones are separate — not listed here.
	var out: Array = []
	for k in cells.keys():
		var e: Dictionary = cells[k]
		if e.has("occupied_by"):
			continue
		var brick_id := str(e.get("brick_id", ""))
		# Legacy cargo_tile cells are migrated on load; skip if any remain.
		if brick_id == "cargo_tile" or brick_id == "cargo_zone":
			continue
		var row := {
			"cell": parse_key(str(k)),
			"brick_id": brick_id,
			"yaw": int(e.get("yaw", 0)),
			"text": str(e.get("text", "")),
		}
		if e.has("sign_id"):
			row["sign_id"] = str(e.get("sign_id", ""))
			row["sign_yaw"] = int(e.get("sign_yaw", 0))
		if e.has("light_id"):
			row["light_id"] = str(e.get("light_id", ""))
			row["light_yaw"] = int(e.get("light_yaw", 0))
		out.append(row)
	return out


func count_brick(brick_id: String) -> int:
	var n := 0
	for item in iter_primary_cells():
		if str(item.get("brick_id", "")) == brick_id:
			n += 1
	return n


func count_tag(tag: String) -> int:
	if tag == "cargo":
		return cargo_cell_count()
	var n := 0
	for item in iter_primary_cells():
		if BrickCatalog.has_tag(str(item.get("brick_id", "")), tag):
			n += 1
	return n


func to_dict() -> Dictionary:
	return {
		"hull_id": hull_id,
		"cells": cells.duplicate(true),
		"cargo_zones": cargo_zones.duplicate(true),
	}


static func from_dict(d: Dictionary) -> BrickLayout:
	var layout := BrickLayout.new()
	layout.hull_id = str(d.get("hull_id", "workboat"))
	var raw: Variant = d.get("cells", {})
	if typeof(raw) == TYPE_DICTIONARY:
		layout.cells = (raw as Dictionary).duplicate(true)
	elif typeof(raw) == TYPE_ARRAY:
		for item in raw as Array:
			if typeof(item) != TYPE_DICTIONARY:
				continue
			var e := item as Dictionary
			var cell := Vector3i(int(e.get("x", 0)), int(e.get("y", 0)), int(e.get("z", 0)))
			layout.set_brick(cell, str(e.get("brick_id", "block")), int(e.get("yaw", 0)))
	var zones_raw: Variant = d.get("cargo_zones", [])
	if typeof(zones_raw) == TYPE_ARRAY:
		for z in zones_raw as Array:
			if typeof(z) != TYPE_DICTIONARY:
				continue
			var zd := z as Dictionary
			var a_raw: Variant = zd.get("a", null)
			var b_raw: Variant = zd.get("b", null)
			if a_raw is Array and b_raw is Array:
				var aa: Array = a_raw
				var bb: Array = b_raw
				layout.cargo_zones.append(normalize_cargo_rect(
					Vector3i(int(aa[0]), 0, int(aa[2]) if aa.size() > 2 else 0),
					Vector3i(int(bb[0]), 0, int(bb[2]) if bb.size() > 2 else 0),
				))
	layout._migrate_legacy_cargo_tiles()
	return layout


func _migrate_legacy_cargo_tiles() -> void:
	## Old saves painted cargo_tile per cell — fold into one AABB zone.
	var min_x := 999999
	var max_x := -999999
	var min_z := 999999
	var max_z := -999999
	var found := false
	var kill: Array[String] = []
	for k in cells.keys():
		var e: Dictionary = cells[k]
		var id := str(e.get("brick_id", ""))
		if id != "cargo_tile" and id != "cargo_zone":
			continue
		found = true
		var c := parse_key(str(k))
		min_x = mini(min_x, c.x)
		max_x = maxi(max_x, c.x)
		min_z = mini(min_z, c.z)
		max_z = maxi(max_z, c.z)
		kill.append(str(k))
	for k in kill:
		cells.erase(k)
	if found and cargo_zones.is_empty():
		cargo_zones.append(normalize_cargo_rect(
			Vector3i(min_x, 0, min_z),
			Vector3i(max_x, 0, max_z),
		))


static func _norm_yaw(yaw: int) -> int:
	return norm_yaw_step(yaw, 90)


static func color_to_array(color: Variant) -> Array:
	if color == null:
		return []
	if color is Color:
		var c := color as Color
		return [c.r, c.g, c.b]
	if color is Array:
		var arr := color as Array
		if arr.size() >= 3:
			return [float(arr[0]), float(arr[1]), float(arr[2])]
	return []


static func color_from_entry(entry: Dictionary, brick_id: String = "") -> Color:
	var painted := color_to_array(entry.get("color", null))
	if painted.size() >= 3:
		return Color(float(painted[0]), float(painted[1]), float(painted[2]))
	var id := brick_id if not brick_id.is_empty() else str(entry.get("brick_id", ""))
	return BrickCatalog.get_entry(id).get("color", Color(0.7, 0.7, 0.7)) as Color


static func norm_yaw_step(yaw: int, step: int = 90) -> int:
	var s := maxi(step, 1)
	var y := yaw % 360
	if y < 0:
		y += 360
	return int(round(float(y) / float(s)) * float(s)) % 360


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
	return layout


static func _paint_cabin(layout: BrickLayout, grid: DeckGrid, z0: int) -> void:
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
	layout.add_cargo_zone(Vector3i(x0, 0, z0), Vector3i(x1, 0, z1))


static func _paint_edge_railings(layout: BrickLayout, grid: DeckGrid) -> void:
	for ix in range(grid.width):
		for iz in range(grid.length):
			if not grid.is_edge_cell(ix, iz):
				continue
			var c := Vector3i(ix, 0, iz)
			if layout.has_cell(c):
				continue
			if layout.cargo_contains(c):
				continue
			layout.set_brick(c, "railing", 0)
