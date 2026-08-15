class_name DeckGrid
extends RefCounted

## Deck brick grid in vessel-local metres.
##
## Cell edge = WorldUnits.DECK_CELL_M, which is **0.5 m — two cells per metre**.
## A cell count is a BUILD RESOLUTION, never a size: measured through
## `from_hull` (2026-08-15), a 30 × 24 m deck is **60 × 48 cells**, hull_28x10 is
## **56 × 20**, hull_70x18 is 140 × 36, hull_120x28 is 240 × 56, hull_150x32 is
## 300 × 64.
##
## This paragraph read *"Cell edge = WorldUnits.DECK_CELL_M (1.0 m). A 30×24 m
## deck is 30×24 cells; starter trawler 14×5 → 14×5 cells"* against a constant
## that is 0.5, i.e. every number in it was double. It is the doc lie that sat
## directly on top of the constant at the centre of REALITY.md §4d, and
## `ship_display_units_test` records what an assertion written from it does:
## `grid.length == 28` on a 28 m hull demands the halved value under a label
## forbidding exactly that shrinkage.
##
## Cell indices: ix ∈ [0, width), iz ∈ [0, length), iy ≥ 0 above deck.

const CELL_M := WorldUnits.DECK_CELL_M

var width: int = 1
var length: int = 1
var deck_y: float = 0.0
var half_beam: float = 0.5
var half_loa: float = 0.5
## Length of a 45-degree pointed bow in whole cells. Zero keeps a rectangular deck.
var bow_taper_cells: int = 0

enum CellShape {
	NONE,
	FULL,
	BOW_PORT_HALF,
	BOW_STARBOARD_HALF,
}


static func from_hull(
	loa_m: float,
	beam_m: float,
	deck_y_m: float,
	bow_taper_m: float = 0.0,
) -> DeckGrid:
	var g := DeckGrid.new()
	g.width = maxi(1, int(floor(beam_m / CELL_M)))
	g.length = maxi(1, int(floor(loa_m / CELL_M)))
	g.deck_y = deck_y_m
	g.half_beam = float(g.width) * CELL_M * 0.5
	g.half_loa = float(g.length) * CELL_M * 0.5
	g.bow_taper_cells = clampi(
		int(round(bow_taper_m / CELL_M)),
		0,
		mini(g.length, int(g.width / 2)),
	)
	return g


func cell_count_xz() -> int:
	return width * length


func in_bounds(cell: Vector3i) -> bool:
	return cell.y >= 0 and cell_shape(cell.x, cell.z) == CellShape.FULL


func has_deck_cell(cell: Vector3i) -> bool:
	return cell.y >= 0 and cell_shape(cell.x, cell.z) != CellShape.NONE


func is_partial_bow_cell(cell: Vector3i) -> bool:
	var shape := cell_shape(cell.x, cell.z)
	return cell.y >= 0 and (shape == CellShape.BOW_PORT_HALF or shape == CellShape.BOW_STARBOARD_HALF)


func cell_shape(ix: int, iz: int) -> CellShape:
	if ix < 0 or ix >= width or iz < 0 or iz >= length:
		return CellShape.NONE
	if bow_taper_cells <= 0 or iz >= bow_taper_cells:
		return CellShape.FULL
	var inset := bow_taper_cells - iz
	var first_full := inset
	var last_full := width - inset - 1
	if ix >= first_full and ix <= last_full:
		return CellShape.FULL
	if ix == first_full - 1:
		return CellShape.BOW_PORT_HALF
	if ix == last_full + 1:
		return CellShape.BOW_STARBOARD_HALF
	return CellShape.NONE


## Required yaw for wedge_45_plan's missing (+X,+Z) corner to face outside the bow.
func partial_bow_yaw_degrees(cell: Vector3i) -> int:
	match cell_shape(cell.x, cell.z):
		CellShape.BOW_PORT_HALF:
			return 180
		CellShape.BOW_STARBOARD_HALF:
			return 90
		_:
			return 0


func cell_center_local(cell: Vector3i) -> Vector3:
	return Vector3(
		-half_beam + (float(cell.x) + 0.5) * CELL_M,
		deck_y + (float(cell.y) + 0.5) * CELL_M,
		-half_loa + (float(cell.z) + 0.5) * CELL_M,
	)


func cell_base_local(cell: Vector3i) -> Vector3:
	## Bottom-centre of the cell (deck contact for iy=0).
	return Vector3(
		-half_beam + (float(cell.x) + 0.5) * CELL_M,
		deck_y + float(cell.y) * CELL_M,
		-half_loa + (float(cell.z) + 0.5) * CELL_M,
	)


func local_to_cell(local: Vector3) -> Vector3i:
	var ix := int(floor((local.x + half_beam) / CELL_M))
	var iz := int(floor((local.z + half_loa) / CELL_M))
	var iy := int(floor((local.y - deck_y) / CELL_M))
	return Vector3i(ix, maxi(iy, 0), iz)


func is_edge_cell(ix: int, iz: int) -> bool:
	if cell_shape(ix, iz) != CellShape.FULL:
		return false
	return cell_shape(ix - 1, iz) != CellShape.FULL \
		or cell_shape(ix + 1, iz) != CellShape.FULL \
		or cell_shape(ix, iz - 1) != CellShape.FULL \
		or cell_shape(ix, iz + 1) != CellShape.FULL


func footprint_touches_edge(origin: Vector3i, footprint: Vector3i, yaw_steps: int = 0) -> bool:
	for c in footprint_cells(origin, footprint, yaw_steps):
		if not in_bounds(c):
			return false
		if c.y == 0 and is_edge_cell(c.x, c.z):
			return true
	return false


## Yaw (degrees) that aims a brick's local −X outboard from the nearest hull edge.
func outboard_yaw_degrees(origin: Vector3i, footprint: Vector3i, yaw_steps: int = 0) -> int:
	var port := 0
	var stbd := 0
	var bow := 0
	var stern := 0
	for c in footprint_cells(origin, footprint, yaw_steps):
		if not in_bounds(c) or c.y != 0:
			continue
		if c.x == 0:
			port += 1
		if c.x == width - 1:
			stbd += 1
		if c.z == 0:
			bow += 1
		if c.z == length - 1:
			stern += 1
	var best := port
	var yaw := 0  # local −X → world −X (port)
	if stbd > best:
		best = stbd
		yaw = 180
	if stern > best:
		best = stern
		yaw = 90
	if bow > best:
		yaw = 270
	return yaw


func footprint_cells(origin: Vector3i, footprint: Vector3i, yaw_steps: int = 0) -> Array[Vector3i]:
	## yaw_steps: 0=+Z length, 1=+X, 2=-Z, 3=-X — swaps XZ for odd steps.
	var fw := footprint.x
	var fl := footprint.z
	var fh := footprint.y
	if yaw_steps % 2 != 0:
		var tmp := fw
		fw = fl
		fl = tmp
	var out: Array[Vector3i] = []
	for dy in range(fh):
		for dx in range(fw):
			for dz in range(fl):
				out.append(Vector3i(origin.x + dx, origin.y + dy, origin.z + dz))
	return out


func to_dict() -> Dictionary:
	return {
		"width": width,
		"length": length,
		"deck_y": deck_y,
		"cell_m": CELL_M,
		"bow_taper_cells": bow_taper_cells,
	}
