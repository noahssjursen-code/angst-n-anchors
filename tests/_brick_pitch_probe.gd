extends SceneTree

## SCRATCH. Two constants, side by side, because the warehouse capture shows
## daylight between every pair of neighbouring bricks.
func _initialize() -> void:
	print("BuildingGrid.CELL_M (layout pitch) = %s" % str(BuildingGrid.CELL_M))
	print("DeckGrid.CELL_M (drawn brick unit) = %s" % str(DeckGrid.CELL_M))
	for id in ["block", "foundation", "floor", "roof_flat_4x4", "block_door_double"]:
		print("%-18s footprint %s -> drawn %s m"
			% [id, str(BrickCatalog.footprint_of(id)), str(BrickCatalog.size_m(id))])
	var g := BuildingGrid.create(Vector3i(44, 16, 44))
	print("cell centres 1 cell apart: %s -> %s"
		% [str(g.cell_center_local(Vector3i(12, 0, 16))), str(g.cell_center_local(Vector3i(13, 0, 16)))])
	quit(0)
