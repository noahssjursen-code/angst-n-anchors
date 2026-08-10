extends SceneTree

## Scratch probe (leading underscore — not a gate unit).


func _initialize() -> void:
	var ids := BrickCatalog.ids()
	print("brick ids: %d" % ids.size())
	for want in [
		"block", "block_door", "helm", "foundation", "roof_flat", "roof_slope_inv",
		"floor", "trommel_small", "railing", "railing_45", "railing_mooring",
		"mast_base", "mast_pole", "light_nav_port", "light_nav_stbd",
		"light_nav_white", "light_mast_white", "passenger_seat", "container_pad",
		"bulk_hold_6x12", "bollard", "bench", "table", "window",
	]:
		print("  %-20s has=%s fp=%s tags=%s" % [
			want,
			str(BrickCatalog.has(want)),
			str(BrickCatalog.footprint_of(want)),
			str(BrickCatalog.get_entry(want).get("tags", [])),
		])
	for probe in ["railing", "railing_45", "mast_base", "mast_pole"]:
		var v := BrickCatalog.create_visual(probe)
		print("  visual %-12s children=%d" % [probe, v.get_child_count()])
		if probe == "railing":
			print("    child0.z=%f" % (v.get_child(0) as Node3D).position.z)
		if probe == "railing_45":
			print("    child0.yaw=%f" % (v.get_child(0) as Node3D).rotation_degrees.y)
		v.free()
	quit()
