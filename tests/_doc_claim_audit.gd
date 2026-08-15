extends SceneTree

## SCRATCH PROBE (leading underscore -> skipped by tools/gate.sh discovery).
## Measures the doc claims audited in the REALITY.md §4d wave. Prints numbers
## only; it asserts nothing and is not a test.

const StructurePlanScript := preload("res://scripts/construction/structure_plan.gd")
const StructureBakerScript := preload("res://scripts/construction/structure_baker.gd")
const PieceKitScript := preload("res://scripts/construction/piece_kit.gd")

const FIXTURES := "res://resources/data/structures/"


func _initialize() -> void:
	_c1_cell_constants()
	_c2_deck_grid_doc()
	_c3_building_vs_deck()
	_c4_colour_is_free()
	_c5_piece_cell_coupling()
	_c6_strip_test()
	_c7_id_space()
	_c8_plate_cost_table()
	_c9_display_scale()
	_c10_has_cabin()
	_c11_surfacetool_keeps_vertices()
	quit(0)


# ── C9 ───────────────────────────────────────────────────────────────────────
func _c9_display_scale() -> void:
	print("\n=== C9  'Nothing is double-scale' (CONVENTIONS.md 3a) ===")
	print("ShipClass.METRIC_SCALE        = ", ShipClass.METRIC_SCALE)
	print("ShipClass.DISPLAY_METRE_SCALE = ", ShipClass.DISPLAY_METRE_SCALE)
	print("format_display_dimensions(28, 10) = \"", ShipClass.format_display_dimensions(28.0, 10.0), "\"")
	print("HullRegistry hull_28x10 loa_m/beam_m/display:")
	var reg := HullRegistry.get_by_id("hull_28x10")
	print("   loa_m=", reg.get("loa_m"), " beam_m=", reg.get("beam_m"), " display=\"", reg.get("display"), "\"")
	print("HullCatalog player-facing labels (entry[\"display\"] is OVERWRITTEN at load):")
	HullCatalog.ensure_loaded()
	for id in HullCatalog.all_ids():
		var e := HullCatalog.get_by_id(id)
		print("   %-14s loa_m=%6.1f beam_m=%5.1f   display=\"%s\""
			% [id, float(e.get("loa_m", 0.0)), float(e.get("beam_m", 0.0)), str(e.get("display", ""))])


# ── C10 ──────────────────────────────────────────────────────────────────────
func _c10_has_cabin() -> void:
	print("\n=== C10  AGENTS.md: 'has_cabin is false for every plan' ===")
	var dir := DirAccess.open(FIXTURES)
	if dir == null:
		return
	var any_true := 0
	var total := 0
	for name in dir.get_files():
		if not name.ends_with(".json"):
			continue
		var doc := _load(name)
		if doc.is_empty() or not StructurePlanScript.is_plan(doc):
			continue
		var plan := StructurePlanScript.from_dict(doc)
		total += 1
		if PlanOutfit.has_cabin(plan):
			any_true += 1
			print("   %-30s has_cabin = TRUE" % name)
	print("   %d plans examined, %d with has_cabin true" % [total, any_true])


# ── C11 ──────────────────────────────────────────────────────────────────────
func _c11_surfacetool_keeps_vertices() -> void:
	print("\n=== C11  vessel_skin_baker.gd:117 'SurfaceTool keeps its vertices after commit()' ===")
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 3:
		st.set_color(Color.WHITE)
		st.add_vertex(Vector3(float(i), 0.0, 0.0))
	var first := st.commit()
	var before: int = first.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()
	for i in 3:
		st.set_color(Color.WHITE)
		st.add_vertex(Vector3(float(i), 1.0, 0.0))
	var second := st.commit()
	var after: int = second.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()
	print("   3 vertices -> commit() -> ", before, " vertices; +3 more -> commit() -> ", after,
		" vertices  (accumulates == kept)")


# ── C8 ───────────────────────────────────────────────────────────────────────
func _c8_plate_cost_table() -> void:
	print("\n=== C8  the plate-collider cost table in structure_baker.gd ===")
	print("PLATE_COLLIDER_SLOP = ", StructureBakerScript.PLATE_COLLIDER_SLOP)
	print("(the header's 0.05 column reads: demo_workboat 675, trawler_bulwark 2118, container_feeder 3086)")
	for name in ["demo_workboat.json", "probe_trawler_bulwark.json", "probe_container_feeder.json"]:
		var doc := _load(name)
		if doc.is_empty():
			print("  ", name, ": MISSING")
			continue
		var plan := StructurePlanScript.from_dict(doc)
		var boxes: Array = StructureBakerScript.collect_colliders(plan)
		print("  %-30s collect_colliders() -> %5d boxes" % [name, boxes.size()])


func _load(name: String) -> Dictionary:
	var f := FileAccess.open(FIXTURES + name, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	return parsed as Dictionary if parsed is Dictionary else {}


# ── C1 ───────────────────────────────────────────────────────────────────────
func _c1_cell_constants() -> void:
	print("\n=== C1  cell constants ===")
	print("WorldUnits.DECK_CELL_M      = ", WorldUnits.DECK_CELL_M)
	print("DeckGrid.CELL_M             = ", DeckGrid.CELL_M)
	print("BuildingGrid.CELL_M         = ", BuildingGrid.CELL_M)
	print("BuildingGrid/DeckGrid ratio = ", BuildingGrid.CELL_M / DeckGrid.CELL_M)
	print("WorldUnits.PLAYER_HEIGHT_M  = ", WorldUnits.PLAYER_HEIGHT_M)
	print("PieceKit kit cell_m guard   = errors if kit cell_m != DECK_CELL_M")


# ── C2 ───────────────────────────────────────────────────────────────────────
func _c2_deck_grid_doc() -> void:
	print("\n=== C2  DeckGrid.from_hull, against the header's own examples ===")
	for pair in [[30.0, 24.0], [14.0, 5.0], [28.0, 10.0], [70.0, 18.0], [120.0, 28.0], [150.0, 32.0]]:
		var g := DeckGrid.from_hull(float(pair[0]), float(pair[1]), 0.0)
		print("  loa %6.1f  beam %5.1f  ->  length %4d cells   width %3d cells   half_loa %.3f m  half_beam %.3f m"
			% [pair[0], pair[1], g.length, g.width, g.half_loa, g.half_beam])


# ── C3 ───────────────────────────────────────────────────────────────────────
func _c3_building_vs_deck() -> void:
	print("\n=== C3  BuildingGrid cell vs the brick drawn in it ===")
	var ids: PackedStringArray = BrickCatalog.ids()
	print("BrickCatalog.ids().size() = ", ids.size())
	var shown := 0
	for id in ids:
		var fp := BrickCatalog.footprint_of(id)
		var sz := BrickCatalog.size_m(id)
		print("  %-18s footprint %s  size_m %s  (BuildingGrid cell is %.2f m)"
			% [id, str(fp), str(sz), BuildingGrid.CELL_M])
		shown += 1
		if shown >= 12:
			break
	var bc := BuildingGrid.create(Vector3i(4, 3, 4))
	print("BuildingGrid(4,3,4).cell_center_local(0,0,0) = ", bc.cell_center_local(Vector3i(0, 0, 0)))
	print("BuildingGrid(4,3,4).cell_center_local(1,0,0) = ", bc.cell_center_local(Vector3i(1, 0, 0)))
	print("  -> building cell pitch = ", bc.cell_center_local(Vector3i(1, 0, 0)).x - bc.cell_center_local(Vector3i(0, 0, 0)).x, " m")
	print("  -> a 1x1x1-footprint brick draws ", BrickCatalog.size_m("block"), " m")


# ── C4 ───────────────────────────────────────────────────────────────────────
func _count_bake(root: Node3D) -> Dictionary:
	var instances := 0
	var surfaces := 0
	var tris := 0
	for child in root.get_children():
		if child is MeshInstance3D:
			instances += 1
			var mesh := (child as MeshInstance3D).mesh
			if mesh != null:
				surfaces += mesh.get_surface_count()
				for s in mesh.get_surface_count():
					var arrays := mesh.surface_get_arrays(s)
					var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
					tris += v.size() / 3
	return {"instances": instances, "surfaces": surfaces, "triangles": tris}


func _distinct_colours(doc: Dictionary) -> int:
	var seen: Dictionary = {}
	var stack: Array = [doc]
	while not stack.is_empty():
		var top = stack.pop_back()
		if top is Dictionary:
			for k in (top as Dictionary).keys():
				var v = (top as Dictionary)[k]
				if str(k) == "color" and v is Array:
					seen[str(v)] = true
				else:
					stack.append(v)
		elif top is Array:
			for v in top as Array:
				stack.append(v)
	return seen.size()


func _repaint(doc: Dictionary, n: int) -> Dictionary:
	## Give every `color` field in the document its own distinct RGB.
	var out := doc.duplicate(true)
	var counter := [0]
	_repaint_walk(out, counter, n)
	return out


func _repaint_walk(node: Variant, counter: Array, n: int) -> void:
	if node is Dictionary:
		var d := node as Dictionary
		for k in d.keys():
			if str(k) == "color" and d[k] is Array:
				var i: int = counter[0]
				counter[0] = i + 1
				d[k] = [
					float((i * 37) % n) / float(n),
					float((i * 61) % n) / float(n),
					float((i * 17) % n) / float(n),
				]
			else:
				_repaint_walk(d[k], counter, n)
	elif node is Array:
		for v in node as Array:
			_repaint_walk(v, counter, n)


func _c4_colour_is_free() -> void:
	print("\n=== C4  'colour is free' — bucket count vs colour count ===")
	print("MATERIALS.size() = ", StructureBakerScript.MATERIALS.size(),
		"  keys = ", str(StructureBakerScript.MATERIALS.keys()))
	for name in ["demo_workboat.json", "probe_piece_house.json", "probe_trawler_bulwark.json", "critic_ferry.json"]:
		var doc := _load(name)
		if doc.is_empty():
			print("  ", name, ": MISSING")
			continue
		var plan := StructurePlanScript.from_dict(doc)
		var baked := StructureBakerScript.bake(plan) as Node3D
		var base := _count_bake(baked)
		baked.free()

		var many := _repaint(doc, 64)
		var many_plan := StructurePlanScript.from_dict(many)
		var many_baked := StructureBakerScript.bake(many_plan) as Node3D
		var loud := _count_bake(many_baked)
		many_baked.free()

		var ghost_baked := StructureBakerScript.bake(many_plan, Vector3.ZERO, true) as Node3D
		var ghost := _count_bake(ghost_baked)
		ghost_baked.free()

		print("  %-28s colours as-shipped %3d -> %3d meshes/%3d surfaces | repainted to %3d colours -> %3d meshes/%3d surfaces | ghost -> %3d meshes"
			% [name, _distinct_colours(doc), base["instances"], base["surfaces"],
				_distinct_colours(many), loud["instances"], loud["surfaces"], ghost["instances"]])
		print("      triangles  as-shipped %d   repainted %d" % [base["triangles"], loud["triangles"]])


# ── C5 ───────────────────────────────────────────────────────────────────────
func _c5_piece_cell_coupling() -> void:
	print("\n=== C5  does DECK_CELL_M move structure-plan geometry? ===")
	print("StructurePlan.piece_node_plan(4,2,6) = ", StructurePlanScript.piece_node_plan(Vector3i(4, 2, 6)),
		"   (== cell * DECK_CELL_M)")
	print("PieceKit.node_plan(4,2,6)            = ", PieceKitScript.node_plan(Vector3i(4, 2, 6)))
	print("StructurePlan.cell_base_plan(4,2,6)  = ", StructurePlanScript.cell_base_plan(Vector3i(4, 2, 6)))

	## The kit refuses to load at all if its cell_m disagrees with the constant.
	var kit_file := FileAccess.open(PieceKitScript.KIT_PATH, FileAccess.READ)
	if kit_file != null:
		var kit_doc = JSON.parse_string(kit_file.get_as_text())
		if kit_doc is Dictionary:
			var real := PieceKitScript.parse_document(kit_doc as Dictionary)
			print("kit as shipped: cell_m=", (kit_doc as Dictionary).get("cell_m"),
				"  pieces=", (real["pieces"] as Dictionary).size(),
				"  errors=", (real["errors"] as PackedStringArray).size())
			var doctored := (kit_doc as Dictionary).duplicate(true)
			doctored["cell_m"] = 1.0
			var broken := PieceKitScript.parse_document(doctored)
			print("kit at cell_m=1.0 (i.e. if DECK_CELL_M went back to 1.0 without editing the kit):")
			print("   pieces=", (broken["pieces"] as Dictionary).size(),
				"  errors=", (broken["errors"] as PackedStringArray).size())
			for e in broken["errors"] as PackedStringArray:
				print("     ! ", e)

	## Placement offsets are the product cell x DECK_CELL_M, so doubling the cell
	## indices is arithmetically identical to doubling the constant.
	var house := _load("probe_piece_house.json")
	if not house.is_empty():
		var a := PieceKitScript.resolve_document(house)
		print("probe_piece_house as shipped: placed=", a["placed"], " items=", a["items"])
		print("   resolved item AABB = ", _doc_item_aabb(a["doc"] as Dictionary))
		var doubled := house.duplicate(true)
		for p in (doubled.get("pieces", []) as Array):
			if p is Dictionary and (p as Dictionary).get("cell") is Array:
				var c := (p as Dictionary)["cell"] as Array
				(p as Dictionary)["cell"] = [float(c[0]) * 2.0, float(c[1]) * 2.0, float(c[2]) * 2.0]
		var b := PieceKitScript.resolve_document(doubled)
		print("same doc with every placement cell x2 (== DECK_CELL_M x2 for the node term):")
		print("   resolved item AABB = ", _doc_item_aabb(b["doc"] as Dictionary))


func _doc_item_aabb(doc: Dictionary) -> AABB:
	var first := true
	var box := AABB()
	for item_v in doc.get("items", []) as Array:
		if not (item_v is Dictionary):
			continue
		var at = (item_v as Dictionary).get("at", null)
		if not (at is Array) or (at as Array).size() != 3:
			continue
		var p := Vector3(float(at[0]), float(at[1]), float(at[2]))
		if first:
			box = AABB(p, Vector3.ZERO)
			first = false
		else:
			box = box.expand(p)
	return box


# ── C6 ───────────────────────────────────────────────────────────────────────
func _c6_strip_test() -> void:
	print("\n=== C6  strip test: do pieces reach the game path? ===")
	for name in ["probe_piece_house.json", "probe_piece_trawler.json", "probe_piece_tug.json"]:
		var doc := _load(name)
		if doc.is_empty():
			print("  ", name, ": MISSING")
			continue
		var shipped := StructurePlanScript.from_dict(doc)
		var shipped_bake := StructureBakerScript.bake(shipped) as Node3D
		var shipped_counts := _count_bake(shipped_bake)
		shipped_bake.free()
		var shipped_cols: Array = StructureBakerScript.collect_colliders(shipped)

		var stripped_doc := doc.duplicate(true)
		var placements: int = (stripped_doc.get("pieces", []) as Array).size()
		stripped_doc["pieces"] = []
		var stripped := StructurePlanScript.from_dict(stripped_doc)
		var stripped_bake := StructureBakerScript.bake(stripped) as Node3D
		var stripped_counts := _count_bake(stripped_bake)
		stripped_bake.free()
		var stripped_cols: Array = StructureBakerScript.collect_colliders(stripped)

		print("  %-26s AS SHIPPED %3d pieces | %6d tris %5d colliders   PLACEMENTS DELETED | %6d tris %5d colliders"
			% [name, placements, shipped_counts["triangles"], shipped_cols.size(),
				stripped_counts["triangles"], stripped_cols.size()])


# ── C7 ───────────────────────────────────────────────────────────────────────
func _c7_id_space() -> void:
	print("\n=== C7  plan id space (REALITY.md 4b) ===")
	var dir := DirAccess.open(FIXTURES)
	if dir == null:
		return
	for name in dir.get_files():
		if not name.ends_with(".json"):
			continue
		var doc := _load(name)
		if doc.is_empty():
			continue
		var seen: Dictionary = {}
		var dupes := 0
		var total := 0
		for key in ["walls", "decks", "stairs", "edges", "items", "pieces"]:
			for e in doc.get(key, []) as Array:
				if not (e is Dictionary) or not (e as Dictionary).has("id"):
					continue
				total += 1
				var id = (e as Dictionary)["id"]
				if seen.has(str(id)):
					dupes += 1
				seen[str(id)] = true
		var pieces: int = (doc.get("pieces", []) as Array).size()
		if dupes > 0:
			print("  %-30s %3d entities, %3d DUPLICATE ids, %3d pieces" % [name, total, dupes, pieces])
	print("  (only fixtures with duplicates listed)")
