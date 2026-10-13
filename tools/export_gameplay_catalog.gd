extends Node

## Export the game's authored capacity inputs for the headless authority.
## Run tools/export_gameplay_catalog.tscn with -- --shipyard-playtest.
func _ready() -> void:
	assert(ShipyardPlaytestMode.active())
	var catalog := {"version": 1, "hulls": {}, "parts": {}, "stock": {}}
	for id: String in ImportedHullCatalog.ENTRIES:
		var hull: Dictionary = ImportedHullCatalog.ENTRIES[id]
		catalog.hulls[id] = {"depth_m": hull.depth_m, "container_beds": hull.get("container_beds", {})}
	for id: String in BrickCatalog.imported_entries():
		catalog.parts[id] = {}
	for id in ["container_bed_20ft", "cargo_securing_bed_4m"]:
		var part := BrickCatalog.create_visual(id)
		var socket := part.find_child("CargoDatum", true, false) as Node3D
		assert(socket != null)
		var relative := socket.transform
		var parent := socket.get_parent()
		while parent != part:
			relative = (parent as Node3D).transform * relative
			parent = parent.get_parent()
		catalog.parts[id]["cargo_datum"] = [relative.origin.x, relative.origin.y, relative.origin.z]
		part.free()
	for id in ["28_10_m", "fishing_hook_line", "bulk_small", "coastal_coaster", "container_feeder_40"]:
		var stock: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://resources/data/vessels/prebuilt/%s.json" % id))
		catalog.stock[id] = {"name": stock.name, "price_nok": int(stock.price_marks), "layout": stock.brick_layout}
	var path := "res://resources/data/vessels/gameplay_catalog.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(catalog, "\t", true) + "\n")
	file.close()
	print("Gameplay catalog exported: ", catalog.parts.size(), " parts; sha256=", FileAccess.get_sha256(path))
	# Stock/prices have their own export so adding offers does not change the
	# construction catalog hash or invalidate existing published vessels.
	var offers := {}
	for entry in PrebuiltVesselCatalog.for_sale_entries():
		offers[str(entry.prebuilt_id)] = {"name":entry.prebuilt_name, "price_nok":int(entry.price_marks), "layout":entry.prebuilt_layout}
	var stock_file := FileAccess.open("res://resources/data/vessels/shipwright_stock.json", FileAccess.WRITE)
	stock_file.store_string(JSON.stringify(offers, "\t", true) + "\n")
	stock_file.close()
	get_tree().quit()
