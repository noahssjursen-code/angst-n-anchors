class_name BuildingLayout
extends RefCounted

const FORMAT_VERSION := 1

var blueprint_id: String = "untitled_building"
var display_name: String = "Untitled Building"
var role: String = "decorative"
## Apron pad template this blueprint fills (e.g. pad_2x2). Empty = freeform.
var pad_template_id: String = ""
var grid_size: Vector3i = Vector3i(32, 16, 32)
var cells: Dictionary = {}


static func cell_key(cell: Vector3i) -> String:
	return "%d,%d,%d" % [cell.x, cell.y, cell.z]


static func parse_cell_key(key: String) -> Vector3i:
	var parts := key.split(",")
	if parts.size() != 3:
		return Vector3i(-1, -1, -1)
	return Vector3i(int(parts[0]), int(parts[1]), int(parts[2]))


func grid() -> BuildingGrid:
	return BuildingGrid.create(grid_size)


static func is_surface_brick(brick_id: String) -> bool:
	return BrickCatalog.has_tag(brick_id, "surface") or BrickCatalog.has_tag(brick_id, "floor")


static func entry_is_surface_only(entry: Dictionary) -> bool:
	if entry.is_empty() or entry.has("occupied_by"):
		return false
	return is_surface_brick(str(entry.get("brick_id", ""))) and not entry.has("surface")


static func entry_has_content(entry: Dictionary) -> bool:
	if entry.is_empty() or entry.has("occupied_by"):
		return false
	return not is_surface_brick(str(entry.get("brick_id", "")))


func set_brick(cell: Vector3i, brick_id: String, yaw: int = 0, color: Variant = null) -> bool:
	if not grid().in_bounds(cell) or not BrickCatalog.has(brick_id):
		return false
	var entry := {
		"brick_id": brick_id,
		"yaw": norm_yaw(yaw, BrickCatalog.yaw_step_of(brick_id)),
	}
	var painted := color_to_array(color)
	if not painted.is_empty():
		entry["color"] = painted
	cells[cell_key(cell)] = entry
	return true


func place_footprint(
		origin: Vector3i,
		brick_id: String,
		yaw: int,
		_building_grid: BuildingGrid = null,
		color: Variant = null,
		props: Dictionary = {},
) -> bool:
	if not BrickCatalog.has(brick_id):
		return false
	if is_surface_brick(brick_id):
		return _place_surface(origin, brick_id, yaw, color)
	return _place_content(origin, brick_id, yaw, color, props)


func attach_sign(cell: Vector3i, sign_id: String, yaw: int, text: String) -> bool:
	## Mount a plaque on an existing brick without removing the host.
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
	e["sign_yaw"] = norm_yaw(yaw, BrickCatalog.yaw_step_of(sign_id))
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
	if not BrickCatalog.has_tag(str(e.get("brick_id", "")), "text"):
		e.erase("text")
	cells[cell_key(origin)] = e
	return true


func has_sign(cell: Vector3i) -> bool:
	var e := get_brick(primary_cell_of(cell))
	return not e.is_empty() and e.has("sign_id")


func _place_surface(origin: Vector3i, brick_id: String, yaw: int, color: Variant) -> bool:
	## Floors occupy the cell as a underlay — may share with walls/props.
	var fp := BrickCatalog.footprint_of(brick_id)
	var yaw_n := norm_yaw(yaw, BrickCatalog.yaw_step_of(brick_id))
	var yaw_steps := int(round(float(yaw_n) / 90.0)) % 4
	var tentative := grid().footprint_cells(origin, fp, yaw_steps)
	origin += ensure_fit_cells(tentative)
	var g := grid()
	var occupied := g.footprint_cells(origin, fp, yaw_steps)
	var painted := color_to_array(color)
	for c in occupied:
		if not g.in_bounds(c):
			return false
	for c in occupied:
		var key := cell_key(c)
		var existing := get_brick(c)
		var surface := {
			"brick_id": brick_id,
			"yaw": yaw_n,
		}
		if not painted.is_empty():
			surface["color"] = painted.duplicate()
		if existing.is_empty():
			set_brick(c, brick_id, yaw_n, color)
			continue
		if entry_is_surface_only(existing):
			set_brick(c, brick_id, yaw_n, color)
			continue
		## Content primary or multi-cell filler — keep it, attach underlay.
		existing["surface"] = surface
		cells[key] = existing
	return true


func _place_content(
		origin: Vector3i,
		brick_id: String,
		yaw: int,
		color: Variant,
		props: Dictionary = {},
) -> bool:
	var fp := BrickCatalog.footprint_of(brick_id)
	var yaw_n := norm_yaw(yaw, BrickCatalog.yaw_step_of(brick_id))
	var yaw_steps := int(round(float(yaw_n) / 90.0)) % 4
	var tentative := grid().footprint_cells(origin, fp, yaw_steps)
	origin += ensure_fit_cells(tentative)
	var g := grid()
	var occupied := g.footprint_cells(origin, fp, yaw_steps)
	## Gather any floor underlays we should preserve, then require no other content.
	var preserved_surfaces: Dictionary = {} ## cell_key → surface dict
	for c in occupied:
		if not g.in_bounds(c):
			return false
		var existing := get_brick(c)
		if existing.is_empty():
			continue
		if existing.has("occupied_by"):
			return false
		if entry_is_surface_only(existing):
			preserved_surfaces[cell_key(c)] = _surface_dict_from_floor_entry(existing)
			continue
		if entry_has_content(existing):
			return false
	var painted := color_to_array(color)
	var primary := true
	for c in occupied:
		var key := cell_key(c)
		if primary:
			var entry := {
				"brick_id": brick_id,
				"yaw": yaw_n,
			}
			if not painted.is_empty():
				entry["color"] = painted.duplicate()
			if props.has("text"):
				entry["text"] = str(props["text"])
			if preserved_surfaces.has(key):
				entry["surface"] = (preserved_surfaces[key] as Dictionary).duplicate(true)
			cells[key] = entry
			primary = false
		else:
			var filler := {
				"brick_id": brick_id.strip_edges(),
				"yaw": yaw_n,
				"occupied_by": cell_key(origin),
			}
			if not painted.is_empty():
				filler["color"] = painted.duplicate()
			if preserved_surfaces.has(key):
				filler["surface"] = (preserved_surfaces[key] as Dictionary).duplicate(true)
			cells[key] = filler
	return true


func _surface_dict_from_floor_entry(entry: Dictionary) -> Dictionary:
	var surface := {
		"brick_id": str(entry.get("brick_id", "floor")),
		"yaw": int(entry.get("yaw", 0)),
	}
	var painted := color_to_array(entry.get("color", null))
	if not painted.is_empty():
		surface["color"] = painted
	return surface


## Grow the authoring volume so every cell fits. Expands symmetrically on X/Z so
## existing brick world positions stay put (centred grid). Returns the index
## shift applied to existing cells (add this to any in-flight place origins).
func ensure_fit_cells(needed: Array[Vector3i]) -> Vector3i:
	if needed.is_empty():
		return Vector3i.ZERO
	var min_c := needed[0]
	var max_c := needed[0]
	for c in needed:
		min_c = Vector3i(mini(min_c.x, c.x), mini(min_c.y, c.y), mini(min_c.z, c.z))
		max_c = Vector3i(maxi(max_c.x, c.x), maxi(max_c.y, c.y), maxi(max_c.z, c.z))
	var dx_neg := maxi(0, -min_c.x)
	var dz_neg := maxi(0, -min_c.z)
	var dx_pos := maxi(0, max_c.x - (grid_size.x - 1))
	var dy_pos := maxi(0, max_c.y - (grid_size.y - 1))
	var dz_pos := maxi(0, max_c.z - (grid_size.z - 1))
	var dx := maxi(dx_neg, dx_pos)
	var dz := maxi(dz_neg, dz_pos)
	if dx == 0 and dy_pos == 0 and dz == 0:
		return Vector3i.ZERO
	var shift := Vector3i(dx, 0, dz)
	_remap_cells(shift)
	grid_size = Vector3i(
		grid_size.x + dx * 2,
		grid_size.y + dy_pos,
		grid_size.z + dz * 2,
	)
	return shift


func _remap_cells(offset: Vector3i) -> void:
	if offset == Vector3i.ZERO:
		return
	var remapped: Dictionary = {}
	for key in cells.keys():
		var cell := parse_cell_key(str(key))
		var entry: Dictionary = (cells[key] as Dictionary).duplicate(true)
		var new_cell := cell + offset
		if entry.has("occupied_by"):
			var origin := parse_cell_key(str(entry.get("occupied_by", "")))
			entry["occupied_by"] = cell_key(origin + offset)
		remapped[cell_key(new_cell)] = entry
	cells = remapped


func erase_brick(cell: Vector3i) -> bool:
	return erase_footprint_at(cell)


func erase_footprint_at(cell: Vector3i) -> bool:
	var entry := get_brick(cell)
	if entry.is_empty():
		return false
	## Floor-only cell: remove the underlay.
	if entry_is_surface_only(entry):
		return cells.erase(cell_key(cell))
	## Content (primary or filler): strip content first and leave any floors behind.
	return _strip_content_keep_surfaces(cell)


func _strip_content_keep_surfaces(cell: Vector3i) -> bool:
	var entry := get_brick(cell)
	var origin_key := str(entry.get("occupied_by", cell_key(cell)))
	var kept: Dictionary = {} ## key → surface
	var to_clear: Array[String] = []
	for key in cells.keys():
		var e: Dictionary = cells[key]
		if str(e.get("occupied_by", "")) == origin_key or str(key) == origin_key:
			to_clear.append(str(key))
			if e.has("surface"):
				kept[str(key)] = (e["surface"] as Dictionary).duplicate(true)
			elif entry_is_surface_only(e):
				kept[str(key)] = _surface_dict_from_floor_entry(e)
	if to_clear.is_empty():
		return false
	for key in to_clear:
		cells.erase(key)
	for key in kept.keys():
		var surface: Dictionary = kept[key]
		var floor_entry := {
			"brick_id": str(surface.get("brick_id", "floor")),
			"yaw": int(surface.get("yaw", 0)),
		}
		if surface.has("color"):
			floor_entry["color"] = (surface["color"] as Array).duplicate()
		cells[key] = floor_entry
	return true


func get_brick(cell: Vector3i) -> Dictionary:
	return (cells.get(cell_key(cell), {}) as Dictionary).duplicate(true)


func has_cell(cell: Vector3i) -> bool:
	return cells.has(cell_key(cell))


func has_blocking_content(cell: Vector3i) -> bool:
	var entry := get_brick(cell)
	if entry.is_empty():
		return false
	if entry.has("occupied_by"):
		return true
	return entry_has_content(entry)


func clear() -> void:
	cells.clear()


func count() -> int:
	return cells.size()


func primary_cell_of(cell: Vector3i) -> Vector3i:
	var e := get_brick(cell)
	if e.is_empty():
		return cell
	if e.has("occupied_by"):
		return parse_cell_key(str(e.get("occupied_by", cell_key(cell))))
	return cell


func iter_primary_cells() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for key in cells:
		var entry := (cells[key] as Dictionary).duplicate(true)
		if entry.has("occupied_by"):
			continue
		entry["cell"] = parse_cell_key(str(key))
		result.append(entry)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ca := a["cell"] as Vector3i
		var cb := b["cell"] as Vector3i
		if ca.y != cb.y:
			return ca.y < cb.y
		if ca.z != cb.z:
			return ca.z < cb.z
		return ca.x < cb.x
	)
	return result


func iter_cells() -> Array[Dictionary]:
	## Includes occupied filler cells — prefer iter_primary_cells for assembly.
	var result: Array[Dictionary] = []
	for key in cells:
		var entry := (cells[key] as Dictionary).duplicate(true)
		entry["cell"] = parse_cell_key(str(key))
		result.append(entry)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ca := a["cell"] as Vector3i
		var cb := b["cell"] as Vector3i
		if ca.y != cb.y:
			return ca.y < cb.y
		if ca.z != cb.z:
			return ca.z < cb.z
		return ca.x < cb.x
	)
	return result


func to_dict() -> Dictionary:
	var out := {
		"format_version": FORMAT_VERSION,
		"id": blueprint_id,
		"display_name": display_name,
		"role": role,
		"grid_size": [grid_size.x, grid_size.y, grid_size.z],
		"cells": cells.duplicate(true),
	}
	if not pad_template_id.is_empty():
		out["pad_template_id"] = pad_template_id
	return out


static func from_dict(data: Dictionary) -> BuildingLayout:
	var layout := BuildingLayout.new()
	layout.blueprint_id = str(data.get("id", "untitled_building"))
	layout.display_name = str(data.get("display_name", layout.blueprint_id.capitalize()))
	layout.role = str(data.get("role", "decorative"))
	layout.pad_template_id = str(data.get("pad_template_id", ""))
	var raw_size := data.get("grid_size", [32, 16, 32]) as Array
	if raw_size.size() >= 3:
		layout.grid_size = Vector3i(
			maxi(int(raw_size[0]), 1),
			maxi(int(raw_size[1]), 1),
			maxi(int(raw_size[2]), 1),
		)
	var raw_cells: Variant = data.get("cells", {})
	if raw_cells is Dictionary:
		layout.cells = (raw_cells as Dictionary).duplicate(true)
	layout.refit_volume_to_content()
	return layout


## Expand the volume so every stored cell is in-bounds (used on load).
func refit_volume_to_content() -> void:
	if cells.is_empty():
		return
	var needed: Array[Vector3i] = []
	for key in cells.keys():
		needed.append(parse_cell_key(str(key)))
	ensure_fit_cells(needed)


static func norm_yaw(yaw: int, step: int = 90) -> int:
	var s := maxi(step, 1)
	var y := yaw % 360
	if y < 0:
		y += 360
	return int(round(float(y) / float(s)) * float(s)) % 360


static func color_to_array(color: Variant) -> Array:
	if color == null:
		return []
	if color is Color:
		var c := color as Color
		return [snappedf(c.r, 0.001), snappedf(c.g, 0.001), snappedf(c.b, 0.001)]
	if color is Array:
		var arr := color as Array
		if arr.size() >= 3:
			return [float(arr[0]), float(arr[1]), float(arr[2])]
	return []


static func color_from_entry(entry: Dictionary, brick_id: String = "") -> Color:
	var painted := color_to_array(entry.get("color", null))
	if painted.size() >= 3:
		return Color(float(painted[0]), float(painted[1]), float(painted[2]))
	var id := brick_id if not brick_id.is_empty() else str(entry.get("brick_id", "block"))
	return BrickCatalog.get_entry(id).get("color", Color(0.7, 0.7, 0.7)) as Color
