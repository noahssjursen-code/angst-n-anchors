class_name BuildingGrid
extends RefCounted

## Authoring volume for portable building blueprints. Starts large and grows with
## the build — there is no gameplay size ceiling. Local origin is the footprint
## centre at ground level.

## ⚠ THIS DISAGREES WITH THE BRICK IT ADDRESSES, BY A FACTOR OF EXACTLY 2.000.
## Measured 2026-08-15: `cell_center_local` steps 1.0 m per cell, while
## `BrickCatalog.size_m("block")` — a 1×1×1 footprint — draws (0.5, 0.5, 0.5),
## because `size_m` is `footprint × DeckGrid.CELL_M` and `DeckGrid.CELL_M` is
## `WorldUnits.DECK_CELL_M` = 0.5. Every blueprint therefore lays half-size
## bricks on a full-size lattice and no blueprint data can produce a solid wall.
## Do NOT "fix" this by editing either constant on sight: whether the brick cell
## should be 0.5 or 1.0 is the open product decision recorded in CONVENTIONS.md
## §3a, and both constants have consumers outside this file.
const CELL_M := 1.0

var width: int = 32
var height: int = 16
var depth: int = 32


static func create(size: Vector3i) -> BuildingGrid:
	var grid := BuildingGrid.new()
	grid.width = maxi(size.x, 1)
	grid.height = maxi(size.y, 1)
	grid.depth = maxi(size.z, 1)
	return grid


func size() -> Vector3i:
	return Vector3i(width, height, depth)


func in_bounds(cell: Vector3i) -> bool:
	return cell.x >= 0 and cell.x < width \
		and cell.y >= 0 and cell.y < height \
		and cell.z >= 0 and cell.z < depth


func cell_center_local(cell: Vector3i) -> Vector3:
	return Vector3(
		(float(cell.x) + 0.5 - float(width) * 0.5) * CELL_M,
		(float(cell.y) + 0.5) * CELL_M,
		(float(cell.z) + 0.5 - float(depth) * 0.5) * CELL_M,
	)


func local_to_cell(local_position: Vector3) -> Vector3i:
	return Vector3i(
		int(floor(local_position.x / CELL_M + float(width) * 0.5)),
		int(floor(local_position.y / CELL_M)),
		int(floor(local_position.z / CELL_M + float(depth) * 0.5)),
	)


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


func footprint_size_m() -> Vector3:
	return Vector3(float(width) * CELL_M, float(height) * CELL_M, float(depth) * CELL_M)
