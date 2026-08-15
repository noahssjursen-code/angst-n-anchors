extends Node

## Scratch probe (leading underscore — not a gate unit). Lane B scene, because
## DeckFitout preloads BrickDoor, which names the WorldGateway autoload bare.
##
## THE HEADLINE from STATE.md 2b, reproduced and then killed: a BrickLayout
## carrying every one of the eight bricks `general_vessel` requires, authored at
## 20 x 56 indices and written onto a 10 x 30 hull.
##
## MEASURED AT 9912ada, before this wave, with the same eight cells:
##
##     bricks stored 8, of which OFF-GRID 8 (in_bounds) / 8 (has_deck_cell)
##     VesselCompliance.validate   ok=true  errors []  warnings []  8/8 legal requirements
##     VesselOutfit.validate       ok=true  errors []
##     DeckFitout visuals drawn    0 of 8   (in-bounds control -> drawn)
##
## The layout is built through `_store_cell`, the deserialiser's raw path,
## because `set_brick` now refuses all eight — which is the first of the three
## fixes and is reported separately below. Building the bad vessel anyway is the
## point: it is what proves the compliance chain refuses it even when a save file
## smuggles it past the setter.
##
## Run: xvfb-run -a --server-args="-screen 0 1280x720x24" godot \
##        --rendering-driver opengl3 --audio-driver Dummy \
##        res://tests/_offgrid_headline.tscn

const CELLS := [
	[Vector3i(5, 1, 55), "helm"],
	[Vector3i(1, 2, 55), "light_nav_port"],
	[Vector3i(8, 2, 55), "light_nav_stbd"],
	[Vector3i(5, 3, 55), "light_nav_white"],
	[Vector3i(2, 0, 55), "bollard"],
	[Vector3i(3, 0, 55), "bollard"],
	[Vector3i(6, 0, 55), "bollard"],
	[Vector3i(7, 0, 55), "bollard"],
]


func _ready() -> void:
	var grid := DeckGrid.from_hull(15.0, 5.0, 0.0, 2.0)
	print("hull grid -> %d x %d  (bow taper %d)" % [grid.width, grid.length, grid.bow_taper_cells])

	## FIX 1 — the setter can refuse now.
	var refused := BrickLayout.new()
	var accepted := 0
	for row in CELLS:
		if refused.set_brick(grid, row[0] as Vector3i, str(row[1]), 0):
			accepted += 1
	print("set_brick accepted          %d of %d   (stored cells %d)" % [
		accepted, CELLS.size(), refused.count(),
	])

	## The same eight smuggled in through the deserialiser's raw path.
	var vc := BrickLayout.new()
	vc.hull_id = "fishing_trawler_small"
	for row in CELLS:
		vc._store_cell(row[0] as Vector3i, str(row[1]), 0)

	var off := 0
	var off_taper := 0
	for row in vc.iter_primary_cells():
		var c := row["cell"] as Vector3i
		if not grid.in_bounds(c):
			off += 1
		if not grid.has_deck_cell(c):
			off_taper += 1
	print("bricks stored %d, of which OFF-GRID %d (in_bounds) / %d (has_deck_cell)" % [
		vc.count(), off, off_taper,
	])

	var rep := VesselCompliance.validate(vc, "fishing_trawler_small", "general_vessel", grid)
	print("VesselCompliance.validate   ok=%s  %s  off_grid_bricks=%d" % [
		str(rep.get("ok")), VesselCompliance.checklist_summary(rep),
		int(rep.get("off_grid_bricks", -1)),
	])
	for e in rep.get("errors", PackedStringArray()):
		print("    ERROR   " + str(e))
	var vout := VesselOutfit.validate(vc, "fishing_trawler_small", grid, {})
	print("VesselOutfit.validate       ok=%s  errors %s" % [
		str(vout.get("ok")), str(vout.get("errors")),
	])
	print("capabilities has_helm=%s helms=%s" % [
		str((rep.get("capabilities", {}) as Dictionary).get("has_helm")),
		str((rep.get("capabilities", {}) as Dictionary).get("helms")),
	])

	var root := Node3D.new()
	add_child(root)
	var drawn := 0
	for row in vc.iter_primary_cells():
		if DeckFitout.create_item_visual(root, grid, row) != null:
			drawn += 1
	var ctrl := DeckFitout.create_item_visual(
		root, grid, {"cell": Vector3i(3, 0, 5), "brick_id": "block", "yaw": 0}
	)
	print("DeckFitout visuals drawn    %d of %d   (in-bounds control -> %s)" % [
		drawn, vc.count(), "drawn" if ctrl != null else "DROPPED",
	])
	print("DeckFitout.placement_faults ->")
	for line in DeckFitout.placement_faults(grid, vc):
		print("    " + str(line))
	root.queue_free()

	## FIX 3, the other half — the skin bake and the mounted-fixture path used to
	## draw an off-deck brick in full. `on_deck_items` is what both entry points
	## filter through now.
	var mixed: Array = [
		{"cell": Vector3i(3, 0, 5), "brick_id": "block", "yaw": 0},
		{"cell": Vector3i(19, 0, 55), "brick_id": "block", "yaw": 0},
	]
	var part := DeckFitout.on_deck_items(grid, mixed)
	print("on_deck_items               kept %d  faults %d" % [
		(part["kept"] as Array).size(), (part["faults"] as Array).size(),
	])
	var skin := DeckFitout.new_skin_session(grid)
	for item in part["kept"] as Array:
		skin.register_item(item as Dictionary)
	for item in part["kept"] as Array:
		skin.emit_item(item as Dictionary)
	skin.commit()
	print("skin bake through the filter  children=%d vertices=%d  (both items unfiltered -> 72)" % [
		skin.root.get_child_count(), _verts(skin.root),
	])
	skin.root.free()
	get_tree().quit()


func _verts(node: Node) -> int:
	var n := 0
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			for i in range(mi.mesh.get_surface_count()):
				n += mi.mesh.surface_get_array_len(i)
	for c in node.get_children():
		n += _verts(c)
	return n
