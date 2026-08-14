extends SceneTree

## Scratch probe (leading underscore — not a gate unit).


func _initialize() -> void:
	for hull_id in ["hull_28x10", "hull_90x24", "hull_70x18"]:
		var g := HullRegistry.make_grid(hull_id)
		print("%s: w=%d l=%d bow_taper_cells=%d half_beam=%.2f half_loa=%.2f deck_y=%.2f cell=%.2f" % [
			hull_id, g.width, g.length, g.bow_taper_cells, g.half_beam, g.half_loa, g.deck_y, DeckGrid.CELL_M,
		])
		var full := 0
		for ix in range(g.width):
			for iz in range(g.length):
				if g.cell_shape(ix, iz) == DeckGrid.CellShape.FULL:
					full += 1
		print("   FULL cells=%d  budget=%s" % [full, str(VesselOutfit.budget_for_hull(hull_id))])
		print("   x=0 centre.x=%.3f   x=%d centre.x=%.3f" % [
			g.cell_center_local(Vector3i(0, 0, 10)).x,
			g.width - 1,
			g.cell_center_local(Vector3i(g.width - 1, 0, 10)).x,
		])
		var mid := g.length / 2
		var row := ""
		for ix in range(g.width):
			row += "1" if g.has_deck_cell(Vector3i(ix, 0, mid)) else "."
		print("   mid row: " + row)
		var col := ""
		for iz in range(g.length):
			col += "1" if g.has_deck_cell(Vector3i(g.width / 2, 0, iz)) else "."
		print("   centreline: " + col)
		var bowrow := ""
		for iz in range(g.length):
			var n := 0
			for ix in range(g.width):
				if g.has_deck_cell(Vector3i(ix, 0, iz)):
					n += 1
			bowrow += "%d " % n
		print("   width by z: " + bowrow)
	quit()
