class_name BrickLayout
extends RefCounted

## Sparse voxel fit-out. Cells keyed as "x,y,z" → { brick_id, yaw }.
## yaw is degrees in 90° steps (0, 90, 180, 270).
## Bulk holds are deck rectangles {a,b,brick_id,yaw} outside the cell map.

var cells: Dictionary = {} ## String → Dictionary
var bulk_holds: Array = [] ## [{ "a", "b", "brick_id", "yaw" }, …] fixed-size bulk holds
var container_pads: Array = [] ## [{ "a": [x,y,z], "b": [x,y,z] }, …] inclusive corners
var hull_id: String = "fishing_trawler_small"


static func cell_key(cell: Vector3i) -> String:
	return "%d,%d,%d" % [cell.x, cell.y, cell.z]


static func parse_key(key: String) -> Vector3i:
	var parts := key.split(",")
	if parts.size() != 3:
		return Vector3i(-1, -1, -1)
	return Vector3i(int(parts[0]), int(parts[1]), int(parts[2]))


func clear() -> void:
	cells.clear()
	bulk_holds.clear()
	container_pads.clear()


func is_empty() -> bool:
	return cells.is_empty() and bulk_holds.is_empty() and container_pads.is_empty()


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
	var fp := grid.part_footprint(brick_id)
	if not grid.fits_size(origin, BrickCatalog.size_m(brick_id), yaw):
		return false
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
		if not allow_on_cargo and deck_reserved_contains(c):
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


# ── Deck rectangles (bulk holds) ─────────────────────────────────────────────

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
		mini(int(a[1]) if a.size() > 1 else 0, int(b[1]) if b.size() > 1 else 0),
		mini(int(a[2]) if a.size() > 2 else 0, int(b[2]) if b.size() > 2 else 0),
	)


static func zone_max(zone: Dictionary) -> Vector3i:
	var a: Array = zone.get("a", [0, 0, 0]) as Array
	var b: Array = zone.get("b", [0, 0, 0]) as Array
	return Vector3i(
		maxi(int(a[0]), int(b[0])),
		maxi(int(a[1]) if a.size() > 1 else 0, int(b[1]) if b.size() > 1 else 0),
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


func bulk_hold_contains(cell: Vector3i) -> bool:
	return bulk_hold_index_at(cell) >= 0


func container_pad_contains(cell: Vector3i) -> bool:
	return container_pad_index_at(cell) >= 0


func container_pad_index_at(cell: Vector3i) -> int:
	for i in range(container_pads.size()):
		if zone_contains_cell(container_pads[i] as Dictionary, cell):
			return i
	return -1


func deck_reserved_contains(cell: Vector3i) -> bool:
	return bulk_hold_contains(cell) or container_pad_contains(cell)


func bulk_hold_index_at(cell: Vector3i) -> int:
	for i in range(bulk_holds.size()):
		if zone_contains_cell(bulk_holds[i] as Dictionary, cell):
			return i
	return -1


static func zone_from_cells(cells: Array) -> Dictionary:
	var min_x := 999999
	var max_x := -999999
	var min_z := 999999
	var max_z := -999999
	for raw in cells:
		if raw is not Vector3i:
			continue
		var c := raw as Vector3i
		min_x = mini(min_x, c.x)
		max_x = maxi(max_x, c.x)
		min_z = mini(min_z, c.z)
		max_z = maxi(max_z, c.z)
	return normalize_cargo_rect(Vector3i(min_x, 0, min_z), Vector3i(max_x, 0, max_z))


func add_bulk_hold(origin: Vector3i, brick_id: String, yaw: int, grid: DeckGrid) -> bool:
	var id := brick_id.strip_edges()
	if not BrickCatalog.has(id):
		return false
	var fp := BrickCatalog.footprint_of(id)
	var yaw_n := norm_yaw_step(yaw, BrickCatalog.yaw_step_of(id))
	var yaw_steps := int(round(float(yaw_n) / 90.0)) % 4
	var occupied := grid.footprint_cells(origin, fp, yaw_steps)
	if occupied.is_empty():
		return false
	for c in occupied:
		if not grid.in_bounds(c):
			return false
		if has_cell(c):
			return false
		if deck_reserved_contains(c):
			return false
	var zone := zone_from_cells(occupied)
	zone["brick_id"] = id
	zone["yaw"] = yaw_n
	var keep: Array = []
	for h in bulk_holds:
		var hd := h as Dictionary
		if _zones_overlap(hd, zone):
			continue
		keep.append(hd)
	keep.append(zone)
	bulk_holds = keep
	return true


func erase_bulk_hold_at(cell: Vector3i) -> bool:
	var idx := bulk_hold_index_at(cell)
	if idx < 0:
		return false
	bulk_holds.remove_at(idx)
	return true


func bulk_cell_count() -> int:
	var n := 0
	for h in bulk_holds:
		n += zone_cell_count(h as Dictionary)
	return n


func iter_bulk_holds() -> Array:
	return bulk_holds.duplicate(true)


func container_pad_cell_count() -> int:
	var n := 0
	for p in container_pads:
		n += zone_cell_count(p as Dictionary)
	return n


func iter_container_pads() -> Array:
	return container_pads.duplicate(true)


func add_container_pad(a: Vector3i, b: Vector3i, grid: DeckGrid) -> bool:
	var zone := normalize_cargo_rect(a, b)
	var mn := zone_min(zone)
	var mx := zone_max(zone)
	## Prefer spans that tile the default container footprint cleanly.
	var fp := ContainerUnit.DEFAULT_FOOTPRINT
	var span_x := mx.x - mn.x + 1
	var span_z := mx.z - mn.z + 1
	if (span_x % fp.x) != 0 or (span_z % fp.y) != 0:
		return false
	for ix in range(mn.x, mx.x + 1):
		for iz in range(mn.z, mx.z + 1):
			var c := Vector3i(ix, 0, iz)
			if grid != null and not grid.has_deck_cell(c):
				return false
			if has_cell(c):
				return false
			if bulk_hold_contains(c):
				return false
	var keep: Array = []
	for p in container_pads:
		var pd := p as Dictionary
		if _zones_overlap(pd, zone):
			continue
		keep.append(pd)
	keep.append(zone)
	container_pads = keep
	return true


func erase_container_pad_at(cell: Vector3i) -> bool:
	var idx := container_pad_index_at(cell)
	if idx < 0:
		return false
	container_pads.remove_at(idx)
	return true


func deck_cargo_cell_count() -> int:
	return bulk_cell_count() + container_pad_cell_count()


static func _zones_overlap(a: Dictionary, b: Dictionary) -> bool:
	var amn := zone_min(a)
	var amx := zone_max(a)
	var bmn := zone_min(b)
	var bmx := zone_max(b)
	return not (amx.x < bmn.x or bmx.x < amn.x or amx.z < bmn.z or bmx.z < amn.z)


func iter_primary_cells() -> Array:
	## Returns [{ cell, brick_id, yaw }, …] skipping occupied-by filler cells.
	## Bulk holds are separate — not listed here.
	var out: Array = []
	for k in cells.keys():
		var e: Dictionary = cells[k]
		if e.has("occupied_by"):
			continue
		var brick_id := str(e.get("brick_id", ""))
		## Drop purged packing bricks if an old save still has them.
		if brick_id == "cargo_tile" or brick_id == "cargo_zone":
			continue
		var row := {
			"cell": parse_key(str(k)),
			"brick_id": brick_id,
			"yaw": int(e.get("yaw", 0)),
			"text": str(e.get("text", "")),
		}
		if e.has("color"):
			row["color"] = (e.get("color", []) as Array).duplicate()
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
		return deck_cargo_cell_count()
	if tag == "bulk_hold":
		return bulk_holds.size()
	if tag == "container_pad":
		return container_pads.size()
	var n := 0
	for item in iter_primary_cells():
		if BrickCatalog.has_tag(str(item.get("brick_id", "")), tag):
			n += 1
	return n


func to_dict() -> Dictionary:
	return {
		"hull_id": hull_id,
		"cells": cells.duplicate(true),
		"cargo_zones": [],
		"container_pads": container_pads.duplicate(true),
		"bulk_holds": bulk_holds.duplicate(true),
	}


static func from_dict(d: Dictionary) -> BrickLayout:
	var layout := BrickLayout.new()
	layout.hull_id = str(d.get("hull_id", "fishing_trawler_small"))
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
	## Migrate legacy cargo_zones → container_pads once.
	var pads_raw: Variant = d.get("container_pads", null)
	if pads_raw == null:
		pads_raw = d.get("cargo_zones", [])
	if typeof(pads_raw) == TYPE_ARRAY:
		for p in pads_raw as Array:
			if typeof(p) != TYPE_DICTIONARY:
				continue
			var pd := p as Dictionary
			var pa: Variant = pd.get("a", null)
			var pb: Variant = pd.get("b", null)
			if pa is Array and pb is Array:
				var paa: Array = pa
				var pbb: Array = pb
				var pax := int(paa[0])
				var paz := int(paa[2]) if paa.size() > 2 else 0
				var pbx := int(pbb[0])
				var pbz := int(pbb[2]) if pbb.size() > 2 else 0
				layout.container_pads.append(normalize_cargo_rect(
					Vector3i(pax, 0, paz),
					Vector3i(pbx, 0, pbz),
				))
	var holds_raw: Variant = d.get("bulk_holds", [])
	if typeof(holds_raw) == TYPE_ARRAY:
		for h in holds_raw as Array:
			if typeof(h) != TYPE_DICTIONARY:
				continue
			var hd := h as Dictionary
			var ha: Variant = hd.get("a", null)
			var hb: Variant = hd.get("b", null)
			if ha is Array and hb is Array:
				var haa: Array = ha
				var hbb: Array = hb
				var hax := int(haa[0])
				var hay := int(haa[1]) if haa.size() > 1 else 0
				var haz := int(haa[2]) if haa.size() > 2 else 0
				var hbx := int(hbb[0])
				var hby := int(hbb[1]) if hbb.size() > 1 else 0
				var hbz := int(hbb[2]) if hbb.size() > 2 else 0
				layout.bulk_holds.append({
					"a": [mini(hax, hbx), mini(hay, hby), mini(haz, hbz)],
					"b": [maxi(hax, hbx), maxi(hay, hby), maxi(haz, hbz)],
					"brick_id": str(hd.get("brick_id", "bulk_hold_6x12")),
					"yaw": int(hd.get("yaw", 0)),
				})
	layout._strip_legacy_cargo_tiles()
	return layout


func _strip_legacy_cargo_tiles() -> void:
	var kill: Array[String] = []
	for k in cells.keys():
		var e: Dictionary = cells[k]
		var id := str(e.get("brick_id", ""))
		if id == "cargo_tile" or id == "cargo_zone":
			kill.append(str(k))
	for k in kill:
		cells.erase(k)


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


static func _paint_edge_railings(layout: BrickLayout, grid: DeckGrid) -> void:
	for ix in range(grid.width):
		for iz in range(grid.length):
			if not grid.is_edge_cell(ix, iz):
				continue
			var c := Vector3i(ix, 0, iz)
			if layout.has_cell(c):
				continue
			if layout.deck_reserved_contains(c):
				continue
			layout.set_brick(c, "railing", 0)
