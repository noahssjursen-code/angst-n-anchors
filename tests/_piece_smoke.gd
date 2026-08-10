extends SceneTree

func _initialize() -> void:
	PieceKit.reload()
	print("errors:")
	for e in PieceKit.load_errors():
		print("  ", e)
	print("warnings:")
	for w in PieceKit.load_warnings():
		print("  ", w)
	print("ids: ", PieceKit.ids())
	for id in PieceKit.ids():
		print("--- ", id, " footprint=", PieceKit.footprint_cells(id))
		var r := PieceKit.resolve(id)
		print("    specs=", (r["specs"] as Array).size(), " errors=", r["errors"])
		for s in r["specs"] as Array:
			print("      ", (s as Dictionary).get("corners"), " t=", (s as Dictionary).get("thickness"))
	quit(0)
