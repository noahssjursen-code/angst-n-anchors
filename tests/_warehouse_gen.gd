extends SceneTree

## SCRATCH GENERATOR (leading underscore — not a gate unit). Writes
## `resources/data/buildings/warehouse.json`.
##
## Why a generator and not a hand-typed JSON. `resources/data/buildings/` held
## only `.gitkeep`, and the temptation is to type cell keys into a file. Cell
## keys are coordinates, and REALITY.md §5 is about exactly that: an agent typing
## coordinates has built a FORMAT, not a feature. Every brick below therefore
## goes through `BuildingLayout.place_footprint(cell, brick, yaw, null, colour)`
## — the same call `building_brick_editor.gd` makes on a mouse click, with the
## same `null` grid argument it passes — and the layout is written with
## `to_dict()` + a trailing newline, which is byte-for-byte what the editor's
## Save writes. So the file can be opened in the editor, edited and saved with no
## spurious diff.
##
## What it does NOT claim: that a player would have PLACED all 656 of these one
## click at a time. That is the honest gap and it belongs in the report — the
## editor has no fill/row tool, so a shed's worth of identical wall blocks is
## many clicks. The recipe's durable home is the editor itself (as `TUG_RECIPE`
## lives in `structure_studio.gd`), which this wave does not own.
##
## ── WHAT THIS BUILDS, AND WHAT IT LOOKS LIKE, WHICH ARE NOT THE SAME ───────
## 20 x 12 m on plan, six courses to the eaves: a concrete plinth, steel walls,
## clerestory windows on all four sides, two 4 m double doors and a name board on
## the quay face, and a flat roof of five by three 4x4 panels. Measured on the
## stamped building: 19.54 x 11.52 x 6.50 m.
##
## IT DOES NOT RENDER AS A SHED. `BuildingGrid.CELL_M` is 1.0 — the lattice these
## cells sit on, one metre apart — but `BrickCatalog.size_m` measures bricks in
## `DeckGrid.CELL_M`, which `a70bdbc` halved to 0.5 when it settled the VESSEL
## scale. So every 1x1x1 brick is drawn 0.5 m wide on a 1.0 m pitch, and every
## wall in every building is a checkerboard with 0.50 m of daylight in it. See
## `screenshots/buildings/warehouse__door.png`: you can see the sky through it.
##
## That is not this blueprint's defect and it is not fixable from here — the two
## constants are the open owner decision in STATE.md #1, and the choice between
## them moves either every building or every vessel. The cells below are authored
## for the 1 m lattice they are stored on, which is what the editor writes and
## what `BuildingGrid` means; they come out solid the moment a brick fills its
## cell.
##
## Run:
##   xvfb-run -a --server-args="-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy --script res://tests/_warehouse_gen.gd

const OUT_PATH := "res://resources/data/buildings/warehouse.json"

## The apron pad this fills. `PortApronPadCatalog.ROLES` gives
## `general_warehouse` the `pad_2x2` template, and the editor sets the authoring
## volume from the template (`_apply_pad_template_volume`), so the grid is the
## pad's own brick volume rather than a number chosen here.
const ROLE := "general_warehouse"
const PAD := "pad_2x2"

## The shed, in cells (1 cell = 1 m). Centred in the pad volume so the building
## stands in the middle of its pad — `BuildingGrid.cell_center_local` measures X
## and Z from the volume centre.
const WIDTH := 20
const DEPTH := 12
const WALL_TOP := 5 ## highest wall course; y 0 is the foundation course

const CONCRETE := Color(0.66, 0.65, 0.62)
const STEEL := Color(0.60, 0.65, 0.63)
const ROOF := Color(0.28, 0.30, 0.32)
const DOOR := Color(0.62, 0.36, 0.14)
const TRIM := Color(0.82, 0.83, 0.84)

var _layout: BuildingLayout
var _x0 := 0
var _z0 := 0
var _refused: PackedStringArray = []
## Cells the wall course must leave alone: doors, windows and the sign own them.
var _reserved: Dictionary = {}


func _initialize() -> void:
	var volume := PortApronPadCatalog.brick_volume(PAD)
	_layout = BuildingLayout.new()
	_layout.blueprint_id = "warehouse"
	_layout.display_name = "General warehouse"
	_layout.role = ROLE
	_layout.pad_template_id = PAD
	_layout.grid_size = volume
	_x0 = int((volume.x - WIDTH) / 2.0)
	_z0 = int((volume.z - DEPTH) / 2.0)

	_reserve_openings()
	_place_floor()
	_place_openings()
	_place_walls()
	_place_roof()

	var grew := _layout.grid_size != volume
	print("grid %s -> %s%s" % [str(volume), str(_layout.grid_size), " GREW" if grew else ""])
	print("cells %d, primaries %d, refused %d %s"
		% [_layout.count(), _layout.iter_primary_cells().size(), _refused.size(),
			"" if _refused.is_empty() else str(_refused.slice(0, 3))])
	var report := BuildingRules.validate(_layout)
	print("validate ok=%s errors=%s warnings=%s"
		% [str(report["ok"]), str(report["errors"]), str(report["warnings"])])

	if not bool(report["ok"]) or grew or not _refused.is_empty():
		print("NOT WRITTEN")
		quit(1)
		return
	var file := FileAccess.open(OUT_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(_layout.to_dict(), "\t") + "\n")
	file.close()
	print("wrote %s" % OUT_PATH)
	quit(0)


func _place(cell: Vector3i, brick: String, yaw: int, color: Color, props: Dictionary = {}) -> void:
	if not _layout.place_footprint(cell, brick, yaw, null, color, props):
		_refused.append("%s at %s" % [brick, str(cell)])


## Doors and the sign are placed BEFORE the wall course and their cells are held
## back from it, because `_place_content` refuses a cell that already carries
## content — a wall block laid first would simply eat the door.
func _reserve_openings() -> void:
	for entry in _openings():
		var cell := entry[0] as Vector3i
		var size := entry[3] as Vector3i
		for dx in size.x:
			for dy in size.y:
				for dz in size.z:
					_reserved[BuildingLayout.cell_key(cell + Vector3i(dx, dy, dz))] = true


## [cell, brick, yaw, footprint, colour, text]. The footprint is restated so the
## reservation can be computed before anything is placed; every entry is checked
## against `BrickCatalog.footprint_of` when it is placed.
func _openings() -> Array:
	var out: Array = []
	## Two 4 m double doors in the quay-facing wall (local -Z, the face the
	## apron's inland axis points away from), standing on the ground.
	for dx in [3, 13]:
		out.append([
			Vector3i(_x0 + dx, 0, _z0), "block_door_double", 0, Vector3i(4, 3, 1), DOOR, "",
		])
	## The name board, above the doors on the same face.
	out.append([
		Vector3i(_x0 + 7, 3, _z0), "wall_text_lg", 0, Vector3i(6, 3, 1), TRIM, "WAREHOUSE",
	])
	## Clerestory windows: one course below the eaves, both long faces and both
	## ends, so the shed is not a blank box from any approach.
	for dx in range(2, WIDTH - 1, 3):
		out.append([Vector3i(_x0 + dx, 4, _z0 + DEPTH - 1), "block_window", 180, Vector3i(1, 1, 1), TRIM, ""])
	for dz in range(2, DEPTH - 1, 3):
		out.append([Vector3i(_x0, 4, _z0 + dz), "block_window", 90, Vector3i(1, 1, 1), TRIM, ""])
		out.append([Vector3i(_x0 + WIDTH - 1, 4, _z0 + dz), "block_window", 270, Vector3i(1, 1, 1), TRIM, ""])
	return out


func _place_openings() -> void:
	for entry in _openings():
		var brick := str(entry[1])
		var declared := entry[3] as Vector3i
		if BrickCatalog.footprint_of(brick) != declared:
			_refused.append("%s footprint %s, reserved %s"
				% [brick, str(BrickCatalog.footprint_of(brick)), str(declared)])
			continue
		var text := str(entry[5])
		_place(entry[0] as Vector3i, brick, int(entry[2]), entry[4] as Color,
			{} if text.is_empty() else {"text": text})


func _place_floor() -> void:
	for x in range(_x0, _x0 + WIDTH):
		for z in range(_z0, _z0 + DEPTH):
			_place(Vector3i(x, 0, z), "floor", 0, CONCRETE)


## A concrete plinth course at y 0 and steel above it, all the way round.
func _place_walls() -> void:
	for y in range(0, WALL_TOP + 1):
		var brick := "foundation" if y == 0 else "block"
		var color := CONCRETE if y == 0 else STEEL
		for x in range(_x0, _x0 + WIDTH):
			for z in [_z0, _z0 + DEPTH - 1]:
				_wall_cell(Vector3i(x, y, z), brick, color)
		for z in range(_z0 + 1, _z0 + DEPTH - 1):
			for x in [_x0, _x0 + WIDTH - 1]:
				_wall_cell(Vector3i(x, y, z), brick, color)


func _wall_cell(cell: Vector3i, brick: String, color: Color) -> void:
	if _reserved.has(BuildingLayout.cell_key(cell)):
		return
	_place(cell, brick, 0, color)


## 4x4 roof panels, which tile 20 x 12 exactly. One brick per 16 cells rather
## than 240 `roof_flat`s: the vocabulary has the big panel, and a roof laid out of
## unit tiles is 225 more mesh instances for the same silhouette.
func _place_roof() -> void:
	for x in range(_x0, _x0 + WIDTH, 4):
		for z in range(_z0, _z0 + DEPTH, 4):
			_place(Vector3i(x, WALL_TOP + 1, z), "roof_flat_4x4", 0, ROOF)
