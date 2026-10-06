class_name DeckGrid
extends RefCounted

## Deck brick grid in vessel-local metres.
## Cell edge = WorldUnits.DECK_CELL_M (1.0 m). A 30×24 m deck is 30×24 cells;
## starter trawler 14×5 → 14×5 cells.
## Cell indices: ix ∈ [0, width), iz ∈ [0, length), iy ≥ 0 above deck.

const CELL_M := WorldUnits.DECK_CELL_M

var cell_m: float = CELL_M
var width: int = 1
var length: int = 1
var deck_y: float = 0.0
var half_beam: float = 0.5
var half_loa: float = 0.5
## Length of a 45-degree pointed bow in whole cells. Zero keeps a rectangular deck.
var bow_taper_cells: int = 0
## Imported hulls provide the actual deck boundary in local X/Z metres.
var deck_polygon := PackedVector2Array()
var deck_openings: Array[PackedVector2Array] = []

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
	snap_m: float = CELL_M,
) -> DeckGrid:
	var g := DeckGrid.new()
	g.cell_m = maxf(snap_m, 0.01)
	g.width = maxi(1, int(floor(beam_m / g.cell_m)))
	g.length = maxi(1, int(floor(loa_m / g.cell_m)))
	g.deck_y = deck_y_m
	g.half_beam = float(g.width) * g.cell_m * 0.5
	g.half_loa = float(g.length) * g.cell_m * 0.5
	g.bow_taper_cells = clampi(
		int(round(bow_taper_m / g.cell_m)),
		0,
		mini(g.length, int(g.width / 2)),
	)
	return g


func cell_count_xz() -> int:
	return width * length


func part_footprint(brick_id: String) -> Vector3i:
	var size := BrickCatalog.size_m(brick_id)
	return Vector3i(ceili(size.x / cell_m), ceili(size.y / cell_m), ceili(size.z / cell_m))


func fits_size(origin: Vector3i, size: Vector3, yaw: int = 0) -> bool:
	if origin.y < 0:
		return false
	if deck_polygon.is_empty():
		return true # Legacy grids retain cell-shape validation.
	var span := Vector2(size.x, size.z)
	if posmod(roundi(float(yaw) / 90.0), 2) == 1:
		span = Vector2(span.y, span.x)
	var corner := Vector2(-half_beam + origin.x * cell_m, -half_loa + origin.z * cell_m)
	var footprint := PackedVector2Array([corner, corner + Vector2(span.x, 0), corner + span, corner + Vector2(0, span.y)])
	return Geometry2D.clip_polygons(footprint, deck_polygon).is_empty()


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
	if not deck_polygon.is_empty():
		var center := Vector2(-half_beam + (ix + 0.5) * cell_m, -half_loa + (iz + 0.5) * cell_m)
		return CellShape.FULL if Geometry2D.is_point_in_polygon(center, deck_polygon) else CellShape.NONE
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
		-half_beam + (float(cell.x) + 0.5) * cell_m,
		deck_y + (float(cell.y) + 0.5) * cell_m,
		-half_loa + (float(cell.z) + 0.5) * cell_m,
	)


func cell_base_local(cell: Vector3i) -> Vector3:
	## Bottom-centre of the cell (deck contact for iy=0).
	return Vector3(
		-half_beam + (float(cell.x) + 0.5) * cell_m,
		deck_y + float(cell.y) * cell_m,
		-half_loa + (float(cell.z) + 0.5) * cell_m,
	)


func local_to_cell(local: Vector3) -> Vector3i:
	var ix := int(floor((local.x + half_beam) / cell_m))
	var iz := int(floor((local.z + half_loa) / cell_m))
	var iy := int(floor((local.y - deck_y) / cell_m))
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
		"cell_m": cell_m,
		"bow_taper_cells": bow_taper_cells,
	}
