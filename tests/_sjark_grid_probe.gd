extends SceneTree

## Scratch probe (leading underscore — NOT a gate unit). Lane A.
## Prints the deck-cell map of hull_15x5 so a house design is drawn against the
## deck that exists rather than against one assumed from `width` and `length`.

func _initialize() -> void:
	for hull_id in ["hull_15x5", "hull_28x10"]:
		var grid := HullRegistry.make_grid(hull_id)
		print("\n%s  width=%d length=%d bow_taper_cells=%d half_beam=%.3f half_loa=%.3f deck_y=%.3f" % [
			hull_id, grid.width, grid.length, grid.bow_taper_cells,
			grid.half_beam, grid.half_loa, grid.deck_y,
		])
		print("  legend: # FULL   / . not full   (rows are z, bow at top)")
		var header := "      x:"
		for x in grid.width:
			header += str(x % 10)
		print(header)
		for z in grid.length:
			var row := ""
			for x in grid.width:
				row += "#" if grid.cell_shape(x, z) == DeckGrid.CellShape.FULL else "."
			print("  z=%2d  %s" % [z, row])
	quit(0)
