class_name PlotBuildLayout
extends RefCounted

## One horizontal port surface. Records never contain a selectable Y layer.
## Foundations grow down; buildings grow up from the same sea-referenced plane.
const VERSION := 3
const GRID_XZ_M := 2.0
const DECK_HEIGHT_ABOVE_SEA_M := 2.0
const MIN_SUPPORT_DEPTH_M := DECK_HEIGHT_ABOVE_SEA_M + 2.0
const CATALOG_PATH := "res://resources/data/ports/plot_build_placeholders.json"
static var _catalog: Dictionary = {}
var plot: Dictionary = {}
var placements: Array[Dictionary] = []
var revision := 0
var _next_id := 1
const UNDO_LIMIT := 128
var _undo_stack: Array[Array] = []
var _edit: Array[Dictionary] = []
var _grouping := false

static func catalog() -> Array[Dictionary]:
	if _catalog.is_empty():
		_catalog = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
		for spec in _catalog.items:
			if str(spec.get("visual","")) in ["container_crane","bulk_crane"]:
				preload("res://scripts/port/building/plot_crane_layout.gd").configure(spec)
	var result: Array[Dictionary] = []
	for item in _catalog.items:
		result.append(item.duplicate(true))
	return result

static func item(id: String) -> Dictionary:
	for row in catalog():
		if str(row.id) == id:
			return row
	return {}

func configure(record: Dictionary) -> void:
	plot = record.duplicate(true)
	placements.clear()
	revision = 0
	_next_id = 1
	_clear_history()

func bounds() -> Rect2:
	return ChartPlotLayer.plot_rect(plot)

func cell_at(world: Vector2) -> Vector2i:
	return Vector2i(((world-bounds().position)/GRID_XZ_M).floor())

func centered_cell(item_id: String, world: Vector2, turns: int) -> Vector2i:
	return aligned_cell(item_id, world, turns, snap_origin(item_id, turns))

func snap_origin(item_id: String, turns: int) -> Vector2i:
	if item(item_id).has("snap_cells"):
		for row in placements:
			if is_platform(str(row.item_id)):
				return Vector2i(row.cell[0], row.cell[1])
	var size := footprint(item_id, Vector2i.ZERO, turns).size
	# Continue an existing tiled surface, including a mixed-size edge connection.
	for row in placements:
		if is_platform(item_id) != is_platform(str(row.item_id)): continue
		if footprint(str(row.item_id), Vector2i.ZERO, int(row.turns)).size == size:
			return Vector2i(row.cell[0], row.cell[1])
	return Vector2i.ZERO

func aligned_cell(item_id: String, world: Vector2, turns: int, origin: Vector2i) -> Vector2i:
	var size := snap_size(item_id, turns)
	if size.x <= 0 or size.y <= 0: return Vector2i(-1,-1)
	var local := (world-bounds().position)/GRID_XZ_M-Vector2(origin)
	# Large equipment follows the cursor by its centre while aligning to slabs.
	local -= (Vector2(footprint(item_id, Vector2i.ZERO, turns).size)-Vector2(size))*.5
	return origin + Vector2i((local/Vector2(size)).floor())*size

func snap_size(item_id: String, turns: int) -> Vector2i:
	var spec := item(item_id)
	if not spec.has("snap_cells"):
		return footprint(item_id, Vector2i.ZERO, turns).size
	var size := Vector2i(spec.snap_cells[0], spec.snap_cells[1])
	return Vector2i(size.y, size.x) if posmod(turns, 2)==1 else size

static func is_platform(item_id: String) -> bool:
	return item(item_id).get("anchor", "base") == "top"

func footprint(item_id: String, cell: Vector2i, turns: int) -> Rect2i:
	var spec := item(item_id)
	if spec.is_empty():
		return Rect2i()
	var size := Vector2i(int(spec.cells[0]), int(spec.cells[1]))
	if posmod(turns, 2) == 1:
		size = Vector2i(size.y, size.x)
	return Rect2i(cell, size)

func validate(item_id: String, cell: Vector2i, turns: int) -> String:
	var area := footprint(item_id, cell, turns)
	if not area.has_area():
		return "Choose a placeable."
	var cells := roundi(bounds().size.x/GRID_XZ_M)
	if not Rect2i(Vector2i.ZERO, Vector2i(cells,cells)).encloses(area):
		return "Outside your plot."
	for existing in placements:
		# A building and its foundation share XZ, meeting at the fixed plane.
		if is_platform(item_id) != is_platform(str(existing.item_id)):
			continue
		var occupied := footprint(str(existing.item_id), Vector2i(existing.cell[0], existing.cell[1]), int(existing.turns))
		if area.intersects(occupied):
			return "That space is occupied."
	if not _has_support(item_id, area):
		return "Build foundations beneath the whole equipment footprint."
	return ""

func _has_support(item_id: String, area: Rect2i, excluding_id := "") -> bool:
	var spec := item(item_id)
	if not bool(spec.get("requires_support", false)): return true
	var covered := {}
	for row in placements:
		if str(row.id)==excluding_id or not is_platform(str(row.item_id)): continue
		if spec.has("support_items") and not str(row.item_id) in spec.support_items: continue
		var overlap := area.intersection(footprint(str(row.item_id), Vector2i(row.cell[0],row.cell[1]), int(row.turns)))
		for z in range(overlap.position.y, overlap.end.y):
			for x in range(overlap.position.x, overlap.end.x):
				covered[Vector2i(x,z)] = true
	return covered.size()==area.size.x*area.size.y

func removal_problem(id: String) -> String:
	for row in placements:
		if str(row.id)!=id or not is_platform(str(row.item_id)): continue
		for equipment in placements:
			var area := footprint(str(equipment.item_id), Vector2i(equipment.cell[0],equipment.cell[1]), int(equipment.turns))
			if not _has_support(str(equipment.item_id), area, id):
				return "Remove the equipment before its foundation."
	return ""

func place(item_id: String, cell: Vector2i, turns: int, support_depth_m := MIN_SUPPORT_DEPTH_M) -> Dictionary:
	var problem := validate(item_id, cell, turns)
	if not problem.is_empty():
		return {"ok": false, "message": problem}
	if not is_finite(support_depth_m) or support_depth_m < MIN_SUPPORT_DEPTH_M:
		return {"ok": false, "message": "Invalid foundation depth."}
	var row := {"id": "block-%d" % _next_id, "item_id": item_id,
		"cell": [cell.x, cell.y], "turns": posmod(turns,4)}
	if is_platform(item_id):
		row.support_depth_m = support_depth_m
	_next_id += 1
	placements.append(row)
	_record_edit("place", row, placements.size()-1)
	revision += 1
	return {"ok": true, "placement": row.duplicate(true)}

func remove_id(id: String) -> Dictionary:
	if not removal_problem(id).is_empty(): return {}
	for i in placements.size():
		if str(placements[i].id)==id:
			var removed := placements[i]
			placements.remove_at(i)
			_record_edit("remove", removed, i)
			revision += 1
			return removed
	return {}

func begin_edit() -> void:
	end_edit()
	_grouping = true

func end_edit() -> void:
	if not _edit.is_empty():
		_undo_stack.append(_edit)
		if _undo_stack.size() > UNDO_LIMIT: _undo_stack.pop_front()
	_edit = []
	_grouping = false

func _record_edit(kind: String, row: Dictionary, index: int) -> void:
	_edit.append({"kind":kind, "row":row.duplicate(true), "index":index})
	if not _grouping: end_edit()

func undo() -> Dictionary:
	end_edit()
	if _undo_stack.is_empty(): return {}
	var changes: Array = _undo_stack.pop_back()
	var result := {"removed":[], "restored":[]}
	for i in range(changes.size()-1,-1,-1):
		var change: Dictionary = changes[i]
		var row: Dictionary = change.row
		if str(change.kind)=="place":
			for j in placements.size():
				if str(placements[j].id)==str(row.id):
					placements.remove_at(j)
					result.removed.append(row.duplicate(true))
					break
		else:
			placements.insert(mini(int(change.index),placements.size()),row.duplicate(true))
			result.restored.append(row.duplicate(true))
	revision += 1
	return result

func _clear_history() -> void:
	_undo_stack.clear()
	_edit = []
	_grouping = false

func position_for(row: Dictionary) -> Vector3:
	var cell := Vector2i(row.cell[0],row.cell[1])
	var area := footprint(str(row.item_id), cell, int(row.turns))
	var center := bounds().position + (Vector2(cell) + Vector2(area.size)*0.5)*GRID_XZ_M
	return Vector3(center.x, grid_world_y(), center.y)

func grid_world_y() -> float:
	return WaveSurface.WATER_LEVEL + DECK_HEIGHT_ABOVE_SEA_M

func to_dict() -> Dictionary:
	return {"version": VERSION, "plot": plot.duplicate(true), "grid_step_m": GRID_XZ_M,
		"deck_height_above_sea_m": DECK_HEIGHT_ABOVE_SEA_M, "sea_level_world_y": WaveSurface.WATER_LEVEL,
		"revision": revision, "next_placement_id": _next_id, "placements": placements.duplicate(true)}

static func from_dict(raw: Dictionary) -> PlotBuildLayout:
	var result := PlotBuildLayout.new()
	if int(raw.get("version", 0)) != VERSION:
		return result
	if not is_equal_approx(float(raw.get("deck_height_above_sea_m", -INF)), DECK_HEIGHT_ABOVE_SEA_M):
		return result
	result.configure(raw.get("plot", {}))
	var ids := {}
	for row in raw.get("placements", []):
		if not row is Dictionary or not row.get("cell", []) is Array or row.cell.size()!=2:
			continue
		var id := str(row.get("id", ""))
		if id.is_empty() or ids.has(id):
			continue
		var accepted := result.place(str(row.get("item_id","")), Vector2i(row.cell[0],row.cell[1]),
			int(row.get("turns",0)), float(row.get("support_depth_m", MIN_SUPPORT_DEPTH_M)))
		if bool(accepted.ok):
			result.placements[-1].id = id
			ids[id] = true
			result._next_id = maxi(result._next_id, id.trim_prefix("block-").to_int()+1)
	result.revision = int(raw.get("revision", result.revision))
	result._next_id = maxi(result._next_id, int(raw.get("next_placement_id",result._next_id)))
	result._clear_history() # Loading a document is not an undoable building action.
	return result
