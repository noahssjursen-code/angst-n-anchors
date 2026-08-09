extends SceneTree

const PC := preload("res://scripts/construction/part_catalog.gd")

func _initialize() -> void:
	print("part ids: ", PC.ids())
	print("brick ids n: ", BrickCatalog.ids().size())
	print("has light_nav_port brick: ", BrickCatalog.has("light_nav_port"))
	var g := HullRegistry.make_grid("hull_28x10")
	print("grid ", g.width, "x", g.length, " deck_y ", g.deck_y, " halfbeam ", g.half_beam, " halfloa ", g.half_loa)
	print("budget ", VesselOutfit.budget_for_hull("hull_28x10", {}))
	print("reg ids ", VesselRegistrationCatalog.ids())
	var specs := PC.expand("hold_coaming", {})
	for s in specs:
		print(s)
	print("entry hold_coaming params: ", PC.get_entry("hold_coaming").get("params"))
	print("entry bollard_pair: ", PC.get_entry("bollard_pair"))
	quit(0)
