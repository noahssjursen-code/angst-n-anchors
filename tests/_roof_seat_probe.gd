extends Node3D

## SCRATCH PROBE (leading underscore — the gate must not discover it).
##
##   xvfb-run -a --server-args="-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy \
##     res://tests/_roof_seat_probe.tscn
##
## SCENE LANE, no `--script`. Two reasons, both measured on the first cut:
##  1. `--script` breaks the compile-time autoload identifiers, and
##     `BuildingFitout` -> `BrickDoor` names `WorldGateway`, so the whole
##     building fit-out failed to compile and never built.
##  2. Nodes added under `SceneTree.root` during `_initialize()` are not yet
##     inside the tree, so `global_transform` returned identity and EVERY
##     course was reported centred on y = 0 — with the land gap coming out as
##     -0.340 m and the vessel gaps negative. That is the exact instrument
##     failure REALITY.md §8 is about; the numbers looked like a finding.
##
## WHY. `STATE.md` records "the roof hovers 0.820 m above the walls" on the
## warehouse, diagnosed as `roof_flat*` drawing a 0.18 m plate pinned to the TOP
## of its cell PLUS `warehouse.json` putting the roof course a metre above the
## wall head. Two causes. This probe measures the geometry that is actually
## DRAWN, decomposes the gap, and asks the same question of the vessel side,
## where the lattice is 0.5 m and the same code runs.
##
## Everything below is read off `MeshInstance3D.global_transform * get_aabb()`
## after parenting into the live tree — a node outside the tree reports its
## LOCAL transform as global and silently centres every course on y = 0.

const ROOF_IDS: Array[String] = [
	"roof_flat", "roof_flat_2x2", "roof_flat_4x4",
	"roof_slope", "roof_slope_2x2x4", "roof_slope_1x2x4",
	"roof_slope_inv", "roof_slope_inv_2x2x4",
	"roof_corner", "roof_corner_4x2x4", "roof_corner_inv",
	"roof_corner_inner", "roof_corner_inner_4x2x4", "roof_corner_inner_inv",
]

var _host: Node3D


func _ready() -> void:
	_host = Node3D.new()
	add_child(_host)

	print("=========================================================")
	print("CONSTANTS")
	print("  BuildingGrid.CELL_M (land lattice pitch) = %.4f" % BuildingGrid.CELL_M)
	print("  DeckGrid.CELL_M     (vessel lattice AND brick unit) = %.4f" % DeckGrid.CELL_M)
	print("  BrickCatalog.size_m(\"block\") = %s" % str(BrickCatalog.size_m("block")))
	print("")

	_pin_census()
	_land_warehouse()
	_vessel_prebuilts()
	_piece_kit_side()

	_host.free()
	get_tree().quit(0)


## ── 1. WHERE DOES EACH ROOF BRICK SIT INSIDE ITS OWN LOCAL BOX? ────────────
##
## The brick's local box is `BrickCatalog.size_m(id)` centred on the node
## origin: y from -sz.y/2 to +sz.y/2. A brick that FILLS its box has its drawn
## bottom at -sz.y/2 (offset 0.000). A brick pinned to the TOP of its box has
## its drawn bottom at +sz.y/2 - thickness.
func _pin_census() -> void:
	print("ROOF BRICK PIN CENSUS — drawn extent inside the brick's own local box")
	print("  %-26s %8s %8s %8s %8s %8s"
		% ["brick_id", "box.y", "drawn_lo", "drawn_hi", "lift", "thick"])
	for id in ROOF_IDS:
		if not BrickCatalog.has(id):
			continue
		var sz := BrickCatalog.size_m(id)
		var visual := BrickCatalog.create_visual(id, {})
		_host.add_child(visual)
		var aabb := _bounds(visual)
		var lift := aabb.position.y - (-sz.y * 0.5)
		print("  %-26s %8.4f %8.4f %8.4f %8.4f %8.4f"
			% [id, sz.y, aabb.position.y, aabb.position.y + aabb.size.y,
				lift, aabb.size.y])
		_host.remove_child(visual)
		visual.free()
	print("")


## ── 2. THE WAREHOUSE, AS THE GAME DRAWS IT ─────────────────────────────────
func _land_warehouse() -> void:
	var src := BuildingBlueprintCatalog.by_id("warehouse")
	if src == null:
		print("LAND: warehouse blueprint did not load")
		return
	var layout := BuildingLayout.from_dict(src.to_dict())
	var grid := layout.grid()
	var fitout := BuildingFitout.build(layout, true)
	_host.add_child(fitout)

	var g := BuildingGrid.CELL_M
	print("=========================================================")
	print("LAND — %s, lattice %.3f m" % [layout.blueprint_id, g])

	## Per-brick-family drawn vertical extent, plus the LATTICE extent of the
	## cells those bricks were placed in. The difference between the two is the
	## brick-cell factor; the difference inside the lattice cell is the pin.
	var drawn_lo: Dictionary = {}
	var drawn_hi: Dictionary = {}
	var cell_lo: Dictionary = {}
	var cell_hi: Dictionary = {}
	for child in fitout.get_children():
		if not (child is Node3D) or child.name == "Collision":
			continue
		var raw := str(child.name)
		var cut := raw.rfind("_")
		var brick_id := raw.substr(0, cut) if cut > 0 else raw
		if brick_id.contains(","):
			continue
		var key := raw.substr(cut + 1)
		var parts := key.split(",")
		if parts.size() != 3:
			continue
		var cy := int(parts[1])
		var aabb := _bounds(child)
		if aabb.size == Vector3.ZERO:
			continue
		_accum(drawn_lo, drawn_hi, brick_id, aabb.position.y, aabb.position.y + aabb.size.y)
		_accum(cell_lo, cell_hi, brick_id, float(cy) * g, float(cy + 1) * g)

	var ids := drawn_lo.keys()
	ids.sort()
	print("  %-22s %9s %9s | %9s %9s"
		% ["brick_id", "drawn_lo", "drawn_hi", "cells_lo", "cells_hi"])
	for id_v in ids:
		var id := str(id_v)
		print("  %-22s %9.4f %9.4f | %9.4f %9.4f"
			% [id, drawn_lo[id], drawn_hi[id], cell_lo[id], cell_hi[id]])

	if drawn_hi.has("block") and drawn_lo.has("roof_flat_4x4"):
		var wall_top: float = drawn_hi["block"]
		var roof_bot: float = drawn_lo["roof_flat_4x4"]
		var wall_cell_top: float = cell_hi["block"]
		var roof_cell_bot: float = cell_lo["roof_flat_4x4"]
		print("")
		print("  THE GAP, DECOMPOSED")
		print("    wall head, DRAWN               %9.4f" % wall_top)
		print("    wall head, LATTICE (cell top)  %9.4f" % wall_cell_top)
		print("    roof course LATTICE floor      %9.4f" % roof_cell_bot)
		print("    roof plate UNDERSIDE, DRAWN    %9.4f" % roof_bot)
		print("    ------------------------------------------")
		print("    (a) brick-cell shortfall at the wall head   %9.4f  [wall lattice top - wall drawn top]"
			% (wall_cell_top - wall_top))
		print("    (b) blueprint course offset                 %9.4f  [roof lattice floor - wall lattice top]"
			% (roof_cell_bot - wall_cell_top))
		print("    (c) roof plate lift inside its own course   %9.4f  [roof drawn bottom - roof lattice floor]"
			% (roof_bot - roof_cell_bot))
		print("    TOTAL DAYLIGHT                              %9.4f" % (roof_bot - wall_top))
		print("    prediction  g - 0.18 = %.4f" % (g - 0.18))

	## Colliders — the second derivation of the same roof.
	var body := fitout.get_node_or_null("Collision")
	if body != null:
		var clo := INF
		var chi := -INF
		var n := 0
		for c in body.get_children():
			if not (c is CollisionShape3D):
				continue
			if not str(c.name).contains("roof"):
				continue
			var shp := (c as CollisionShape3D).shape as BoxShape3D
			if shp == null:
				continue
			var cy := (c as CollisionShape3D).position.y
			clo = minf(clo, cy - shp.size.y * 0.5)
			chi = maxf(chi, cy + shp.size.y * 0.5)
			n += 1
		if n > 0:
			print("")
			print("  ROOF COLLIDERS (%d): y %.4f .. %.4f" % [n, clo, chi])
			print("    drawn plate:            y %.4f .. %.4f"
				% [drawn_lo.get("roof_flat_4x4", NAN), drawn_hi.get("roof_flat_4x4", NAN)])

	_host.remove_child(fitout)
	fitout.free()
	print("")


## ── 3. THE VESSEL SIDE — same bricks, 0.5 m lattice ────────────────────────
##
## The prebuilts carry `roof_flat*` / `roof_slope` / `roof_corner` on a DeckGrid
## whose pitch and brick unit are the SAME constant, so the brick-cell factor
## cannot contribute here. Anything left is the pin.
func _vessel_prebuilts() -> void:
	print("=========================================================")
	print("VESSEL — DeckGrid lattice %.3f m (pitch == brick unit)" % DeckGrid.CELL_M)
	for stem in ["28_10_m", "fishing_trawler", "sjark_15m", "bulk_small"]:
		var path := "res://resources/data/vessels/prebuilt/%s.json" % stem
		if not FileAccess.file_exists(path):
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not (parsed is Dictionary):
			continue
		var doc := parsed as Dictionary
		var layout := BrickLayout.from_dict(doc.get("brick_layout", {}) as Dictionary)
		var grid := HullRegistry.make_grid(str(doc.get("hull_id", "")))
		_vessel_one(stem, layout, grid)
	print("")


func _vessel_one(stem: String, layout: BrickLayout, grid: DeckGrid) -> void:
	var root := Node3D.new()
	_host.add_child(root)
	var g := DeckGrid.CELL_M

	## cell key -> brick id, so a roof's supporting course can be looked up.
	var by_cell: Dictionary = {}
	for item in layout.iter_primary_cells():
		by_cell[item["cell"]] = str(item.get("brick_id", ""))

	var worst := -INF
	var worst_desc := ""
	var pairs := 0
	var total := 0.0
	var histogram: Dictionary = {}

	for item in layout.iter_primary_cells():
		var brick_id := str(item.get("brick_id", ""))
		if not brick_id.begins_with("roof"):
			continue
		var cell: Vector3i = item["cell"]
		var below := Vector3i(cell.x, cell.y - 1, cell.z)
		if not by_cell.has(below):
			continue
		var below_id := str(by_cell[below])
		if below_id.begins_with("roof") or not BrickCatalog.has_tag(below_id, "solid"):
			continue

		var roof_v := DeckFitout.create_item_visual(root, grid, item)
		var wall_item := {"cell": below, "brick_id": below_id, "yaw": 0}
		var wall_v := DeckFitout.create_item_visual(root, grid, wall_item)
		if roof_v == null or wall_v == null:
			continue
		var roof_aabb := _bounds(roof_v)
		var wall_aabb := _bounds(wall_v)
		if roof_aabb.size == Vector3.ZERO or wall_aabb.size == Vector3.ZERO:
			continue
		var gap := roof_aabb.position.y - (wall_aabb.position.y + wall_aabb.size.y)
		pairs += 1
		total += gap
		var bucket := "%.3f" % gap
		histogram[bucket] = int(histogram.get(bucket, 0)) + 1
		if gap > worst:
			worst = gap
			worst_desc = "%s on %s at cell %s" % [brick_id, below_id, str(cell)]
		root.remove_child(roof_v)
		roof_v.free()
		root.remove_child(wall_v)
		wall_v.free()

	if pairs == 0:
		print("  %-18s no roof-on-wall pairs" % stem)
	else:
		print("  %-18s %4d roof-on-wall pairs   mean gap %.4f m   worst %.4f m  (%s)"
			% [stem, pairs, total / float(pairs), worst, worst_desc])
		print("  %-18s gap histogram %s" % ["", str(histogram)])
		print("  %-18s prediction for a flat plate: g - 0.18 = %.4f"
			% ["", g - 0.18])
	_host.remove_child(root)
	root.free()


## ── 4. THE PIECE KIT — the OTHER ship roof, and a different subsystem ──────
func _piece_kit_side() -> void:
	print("=========================================================")
	print("PIECE KIT — measured, not assumed. For every deck plate, the vertical")
	print("daylight down to the head of the tallest wall it stands over.")
	## A piece resolves into `items[]` carrying an explicit plate polygon, so the
	## drawn extent is read off the resolved corners plus the placement node.
	## THE DIRECT EXPERIMENT: a 4-cell wall standing at cell y=0 with a deck
	## laid at cell y=4 directly on its head. If pieces pinned to cell ceilings
	## the way `roof_flat*` did, this would show `cell - thickness` of daylight.
	_piece_pair("wall_panel", {"span": 4, "height": 4, "head": 0}, Vector3i(0, 0, 0),
		"deck_tile", {"span": 4, "depth": 4}, Vector3i(0, 4, 0))
	_piece_pair("wall_panel", {"span": 4, "height": 6, "head": 0}, Vector3i(0, 0, 0),
		"roof_slope", {"span": 4, "depth": 4, "rise": 2}, Vector3i(0, 6, 0))

	## And over the shipped fixtures: the whole span of every resolved piece
	## plate, so a pin anywhere in the kit would show as a family of plates
	## sitting `cell - thickness` above their own node level.
	print("")
	print("  Resolved plate offsets from their own placement node, over every")
	print("  shipped structure fixture. A pinned plate would sit at +%.3f."
		% (DeckGrid.CELL_M - 0.18))
	var dir := DirAccess.open("res://resources/data/structures")
	var stems: Array[String] = []
	if dir != null:
		for f in dir.get_files():
			if f.ends_with(".json"):
				stems.append(f.get_basename())
	stems.sort()
	var by_piece: Dictionary = {}
	for stem in stems:
		var path := "res://resources/data/structures/%s.json" % stem
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not (parsed is Dictionary):
			continue
		var doc := (parsed as Dictionary).duplicate(true)
		if not doc.has("pieces"):
			continue
		var result := PieceKit.resolve_document(doc)
		for item_v in (result["doc"] as Dictionary).get("items", []) as Array:
			var item := item_v as Dictionary
			var props := item.get("props", {}) as Dictionary
			var piece := str(props.get("__piece", "")).split(" ")[0]
			if not (piece == "deck_tile" or piece == "roof_slope"):
				continue
			var lo := INF
			for c_v in props.get("corners", []) as Array:
				var c := c_v as Array
				lo = minf(lo, float(c[1]))
			if lo == INF:
				continue
			if not by_piece.has(piece):
				by_piece[piece] = {}
			var bucket := "%.3f" % lo
			var counts := by_piece[piece] as Dictionary
			counts[bucket] = int(counts.get(bucket, 0)) + 1
	for piece_v in by_piece.keys():
		print("  %-12s lowest corner y, relative to its own node: %s"
			% [str(piece_v), str(by_piece[piece_v])])
	print("")
	print("  Mechanism, for the record: `PieceKit.node_plan` is `cell x")
	print("  DECK_CELL_M` — pieces stand on grid NODES, not in cell volumes —")
	print("  and `StructureBaker._plate_span` hangs a plate DOWNWARD from its")
	print("  own level (top = origin.y, bottom = top - thickness). There is no")
	print("  cell ceiling to pin to, so the brick defect cannot reach the kit.")
	print("  The kit's roof problem is the HORIZONTAL one held by")
	print("  plan_roof_seal_test: a raked wall head landing outboard of the")
	print("  tile edge. Different axis, different law, already covered.")
	print("")


func _accum(lo: Dictionary, hi: Dictionary, key: String, a: float, b: float) -> void:
	if not lo.has(key):
		lo[key] = a
		hi[key] = b
	else:
		lo[key] = minf(float(lo[key]), a)
		hi[key] = maxf(float(hi[key]), b)


func _bounds(node: Node) -> AABB:
	var out := AABB()
	var first := true
	for mi in _meshes(node):
		var aabb: AABB = mi.global_transform * mi.get_aabb()
		if first:
			out = aabb
			first = false
		else:
			out = out.merge(aabb)
	return out


func _meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for child in node.get_children():
		out.append_array(_meshes(child))
	return out


## One wall piece and one roof-ish piece placed on top of it, resolved through
## the kit's own resolver, measured off the resolved plate corners.
func _piece_pair(
		wall_id: String, wall_params: Dictionary, wall_cell: Vector3i,
		roof_id: String, roof_params: Dictionary, roof_cell: Vector3i,
) -> void:
	var doc := {
		"format_version": 1, "id": "_probe", "hull_id": "hull_28x10",
		"pieces": [
			{"id": 1, "piece": wall_id, "cell": [wall_cell.x, wall_cell.y, wall_cell.z],
				"facing": 0, "params": wall_params},
			{"id": 2, "piece": roof_id, "cell": [roof_cell.x, roof_cell.y, roof_cell.z],
				"facing": 0, "params": roof_params},
		],
	}
	var result := PieceKit.resolve_document(doc)
	for e in result["errors"] as PackedStringArray:
		print("  [resolve] %s" % e)
	var wall_top := -INF
	var roof_bottom := INF
	for item_v in (result["doc"] as Dictionary).get("items", []) as Array:
		var item := item_v as Dictionary
		var at: Array = item.get("at", [0.0, 0.0, 0.0])
		var props := item.get("props", {}) as Dictionary
		var piece := str(props.get("__piece", "")).split(" ")[0]
		for c_v in props.get("corners", []) as Array:
			var y := float(at[1]) + float((c_v as Array)[1])
			if piece == wall_id:
				wall_top = maxf(wall_top, y)
			elif piece == roof_id:
				roof_bottom = minf(roof_bottom, y)
	print("  %s(%s) at cell y%d  +  %s at cell y%d:  wall head %.4f, roof underside %.4f, DAYLIGHT %.4f m"
		% [wall_id, str(wall_params), wall_cell.y, roof_id, roof_cell.y,
			wall_top, roof_bottom, roof_bottom - wall_top])
