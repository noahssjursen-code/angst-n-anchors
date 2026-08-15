extends Node

## Scratch probe (leading underscore — not a gate unit). Lane B scene, because
## DeckFitout preloads BrickDoor, which names the WorldGateway autoload bare.
##
## The measurements this wave's decisions rest on. A-D were taken BEFORE any fix
## and their numbers are quoted in the code they justify; E-G after.
##   A. every shipped prebuilt vessel, cells vs `in_bounds` vs `has_deck_cell`
##      -> 1254 cells, 0 off by EITHER bound, 0 on a bow half cell. A guard added
##         here rejects nothing that ships.
##   B. does the merged SKIN bake draw an off-deck brick? (the survey only
##      measured `create_item_visual`, which is the LIVE-node path)
##      -> YES: on-deck 36 vertices, OFF-DECK 36 vertices. Identical.
##   C. does `create_cell_mounts` draw a sign/light on an off-deck cell?  -> YES.
##   D. is any shipped cell a bow HALF cell — i.e. does the choice between
##      `in_bounds` and `has_deck_cell` reject anything that ships today? -> no.
##   E. the two dormant `vessel_skin_showcase` demos: 122 refused cells between
##      them, every one an UNCATALOGUED BRICK ID, not one off-deck cell.
##   F. `staged_vessel_visual_demo`'s big layout: 3760 cells, 0 off the deck.
##   G. THE SEAM THIS WAVE DID NOT CLOSE. `BrickShellClassifier.classify` splits
##      the filtered item list correctly (57 exterior / 1 interior either way),
##      but builds its occupancy field and bounding box from `layout.cells`
##      directly and ignores its own `_grid` argument. One smuggled cell at
##      (-40, 0, -40) takes `exterior_air_count` from **121 to 28600** — a 236x
##      flood fill, on the staged fit-out's critical path.
##
## Run: xvfb-run -a --server-args="-screen 0 1280x720x24" godot \
##        --rendering-driver opengl3 --audio-driver Dummy \
##        res://tests/_offgrid_facts.tscn

const PREBUILT_DIR := "res://resources/data/vessels/prebuilt"


func _ready() -> void:
	print("=== A. shipped prebuilt vessels vs their own hull grid ===")
	var total := 0
	var total_off_full := 0
	var total_off_deck := 0
	var total_half := 0
	for name in _prebuilt_files():
		var doc := _read_json("%s/%s" % [PREBUILT_DIR, name])
		var hull_id := str(doc.get("hull_id", ""))
		var grid := HullRegistry.make_grid(hull_id)
		var layout := BrickLayout.from_dict(doc.get("brick_layout", {}) as Dictionary)
		var cells := (layout.to_dict().get("cells", {}) as Dictionary)
		var off_full := 0
		var off_deck := 0
		var half := 0
		for key in cells.keys():
			var c := BrickLayout.parse_key(str(key))
			if not grid.in_bounds(c):
				off_full += 1
			if not grid.has_deck_cell(c):
				off_deck += 1
			if grid.is_partial_bow_cell(c):
				half += 1
		total += cells.size()
		total_off_full += off_full
		total_off_deck += off_deck
		total_half += half
		print("  %-22s hull=%-12s grid %dx%d taper %d  cells %4d  off(in_bounds) %d  off(has_deck_cell) %d  on bow HALF cells %d" % [
			name, hull_id, grid.width, grid.length, grid.bow_taper_cells,
			cells.size(), off_full, off_deck, half,
		])
	print("  TOTAL cells %d  off(in_bounds) %d  off(has_deck_cell) %d  half-cell %d" % [
		total, total_off_full, total_off_deck, total_half,
	])

	print("=== B. does the merged SKIN bake draw an off-deck brick? ===")
	var grid_small := DeckGrid.from_hull(15.0, 5.0, 0.0, 2.0)
	print("  probe grid %d x %d taper %d" % [grid_small.width, grid_small.length, grid_small.bow_taper_cells])
	print("  is_baked_brick block=%s helm=%s bollard=%s light_nav_port=%s railing=%s" % [
		str(VesselSkinBaker.is_baked_brick("block")),
		str(VesselSkinBaker.is_baked_brick("helm")),
		str(VesselSkinBaker.is_baked_brick("bollard")),
		str(VesselSkinBaker.is_baked_brick("light_nav_port")),
		str(VesselSkinBaker.is_baked_brick("railing")),
	])
	for row in [["on-deck  (3,0,5)", Vector3i(3, 0, 5)], ["OFF-DECK (19,0,55)", Vector3i(19, 0, 55)]]:
		var item := {"cell": row[1] as Vector3i, "brick_id": "block", "yaw": 0}
		var s := DeckFitout.new_skin_session(grid_small)
		var reg: bool = s.register_item(item)
		var emit: bool = s.emit_item(item)
		s.commit()
		print("    %-20s register=%s emit=%s  skin children=%d vertices=%d" % [
			str(row[0]), str(reg), str(emit), s.root.get_child_count(), _verts(s.root),
		])
		s.root.free()

	print("=== C. does create_cell_mounts draw a fixture on an off-deck cell? ===")
	var root := Node3D.new()
	add_child(root)
	DeckFitout.create_cell_mounts(root, grid_small, {
		"cell": Vector3i(19, 0, 55), "brick_id": "block", "yaw": 0,
		"light_id": "light_nav_port", "light_yaw": 0,
	})
	print("    off-deck block with a mounted nav light -> %d node(s) created" % root.get_child_count())
	root.queue_free()

	print("=== D. bow-taper reach on every shipped hull ===")
	for hull_id in ["hull_15x5", "hull_28x10", "hull_70x18", "hull_120x28", "hull_150x32"]:
		var g := HullRegistry.make_grid(hull_id)
		var full := 0
		var half := 0
		for ix in range(g.width):
			for iz in range(g.length):
				match g.cell_shape(ix, iz):
					DeckGrid.CellShape.FULL:
						full += 1
					DeckGrid.CellShape.BOW_PORT_HALF, DeckGrid.CellShape.BOW_STARBOARD_HALF:
						half += 1
		print("    %-12s %dx%d taper %d -> FULL %d  HALF %d  NONE %d" % [
			hull_id, g.width, g.length, g.bow_taper_cells, full, half,
			g.width * g.length - full - half,
		])

	print("=== E. the two dormant vessel_skin_showcase demos vs hull_28x10 ===")
	var showcase: Node3D = load("res://scripts/ship/vessel_skin_showcase.gd").new()
	for demo in ["_demo_workboat", "_demo_sampler"]:
		var record: Dictionary = showcase.call(demo)
		var layout := BrickLayout.from_dict(record.get("brick_layout", {}) as Dictionary)
		## The demo clears `_refused` itself via `_report_refusals`, which emits
		## the whole list as one engine WARNING — that is where the refusal detail
		## is. Only the kept count is readable from here.
		print("    %-16s KEPT %3d cells (refusals are in the WARNING above)" % [
			demo, layout.count(),
		])
	showcase.free()

	print("=== F. staged_vessel_visual_demo's >1000-brick layout ===")
	var demo: Node3D = load("res://scenes/showcases/staged_vessel_visual_demo.gd").new()
	var big: BrickLayout = demo.call("_make_large_layout")
	var demo_grid := HullRegistry.make_grid("hull_120x28")
	var big_off := 0
	for row in big.iter_primary_cells():
		if not demo_grid.in_bounds(row["cell"] as Vector3i):
			big_off += 1
	print("    cells %d (threshold %d) · off the %d x %d deck: %d" % [
		big.count(), DeckFitout.LARGE_LAYOUT_THRESHOLD,
		demo_grid.width, demo_grid.length, big_off,
	])
	demo.free()

	print("=== G. BrickShellClassifier — the one seam still fed unfiltered ===")
	## `classify(layout, _grid, known_primary_items)`: the ITEM list it splits is
	## filtered by `apply_staged`, but its occupancy field and bounding box are
	## built by walking `layout.cells` directly, and its `_grid` parameter is
	## unused (it is named with a leading underscore). One off-deck cell therefore
	## still stretches the flood-fill volume.
	var hull := "hull_90x24"
	var hg := HullRegistry.make_grid(hull)
	var origin := Vector3i(20, 0, 60)
	var cabin := BrickLayout.new()
	cabin.hull_id = hull
	for y in range(3):
		for x in range(5):
			for z in range(5):
				if x == 0 or x == 4 or z == 0 or z == 4 or y == 2:
					cabin.set_brick(hg, Vector3i(origin.x + x, origin.y + y, origin.z + z), "block", 0)
	cabin.set_brick(hg, Vector3i(origin.x + 2, origin.y + 1, origin.z + 2), "block", 0)
	var classifier := load("res://scripts/ship/brick_shell_classifier.gd")
	var kept := DeckFitout.on_deck_items(hg, cabin.iter_primary_cells())["kept"] as Array
	var base: Dictionary = classifier.classify(cabin, hg, kept)
	var dirty := BrickLayout.from_dict(cabin.to_dict())
	dirty._store_cell(Vector3i(-40, 0, -40), "block", 0)
	var kept2 := DeckFitout.on_deck_items(hg, dirty.iter_primary_cells())["kept"] as Array
	var after: Dictionary = classifier.classify(dirty, hg, kept2)
	print("    clean     exterior %d  interior %d  exterior_air %d" % [
		(base.get("exterior", []) as Array).size(),
		(base.get("interior", []) as Array).size(),
		int(base.get("exterior_air_count", -1)),
	])
	print("    +1 off-deck cell at (-40,0,-40) (filtered OUT of the item list):")
	print("              exterior %d  interior %d  exterior_air %d" % [
		(after.get("exterior", []) as Array).size(),
		(after.get("interior", []) as Array).size(),
		int(after.get("exterior_air_count", -1)),
	])

	get_tree().quit()


func _prebuilt_files() -> Array:
	var out: Array = []
	var d := DirAccess.open(PREBUILT_DIR)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".json"):
			out.append(f)
	out.sort()
	return out


func _read_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed as Dictionary if parsed is Dictionary else {}


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
