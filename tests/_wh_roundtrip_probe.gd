extends SceneTree
func _initialize() -> void:
	var path := "res://resources/data/buildings/warehouse.json"
	var on_disk := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(on_disk)
	var layout := BuildingLayout.from_dict(parsed as Dictionary)
	layout.blueprint_id = "warehouse"
	var again := JSON.stringify(layout.to_dict(), "\t") + "\n"
	print("same: %s (disk %d chars, again %d chars)" % [str(again == on_disk), on_disk.length(), again.length()])
	for i in mini(on_disk.length(), again.length()):
		if on_disk[i] != again[i]:
			print("first diff at %d: disk %s | again %s" % [i, on_disk.substr(maxi(0, i - 60), 120), again.substr(maxi(0, i - 60), 120)])
			break
	quit(0)
