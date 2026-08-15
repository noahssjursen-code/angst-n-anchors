extends SceneTree

## Scratch probe (leading underscore — NOT a gate unit).
##
## ONE QUESTION: what fence around a hull refuses the 910 m slab and refuses
## nothing a real ship carries?
##
## Measured off the boxes `StructureBaker` really draws and really collides,
## entity by entity, because that is the geometry a player walks into.
##
## For every entity, two numbers against the deck RECTANGLE
## (x in [0, width*CELL_M], z in [0, length*CELL_M]):
##   near = the closest any corner of any box comes  (negative = over the deck)
##   far  = the furthest any corner of any box goes  (the whole entity's reach)
##
## An "any corner inside" rule keeps an entity when `near <= margin`.
## An "every corner inside" rule keeps it when `far <= margin`.
##
## Run: xvfb-run -a --server-args="-screen 0 1280x720x24" godot \
##        --rendering-driver opengl3 --audio-driver Dummy \
##        --script res://tests/_plan_fence_facts.gd

const DIR := "res://resources/data/structures/"

var _rows: Array = []


func _init() -> void:
	var names := PackedStringArray()
	var d := DirAccess.open(DIR)
	for f in d.get_files():
		if f.ends_with(".json"):
			names.append(f)
	names.sort()

	print("=== A. per fixture: entity reach against the deck rectangle ===")
	print(
		"  %-32s %-9s %5s %6s %8s %9s %9s"
		% ["fixture", "grid m", "ents", "boxes", "halfbeam", "worst near", "worst far"]
	)
	var total_ents := 0
	var total_boxes := 0
	for f in names:
		var row := _measure(DIR + f, f)
		if row.is_empty():
			continue
		total_ents += int(row["ents"])
		total_boxes += int(row["boxes"])
	print("  %d entities, %d boxes over %d fixtures" % [total_ents, total_boxes, names.size()])

	print("")
	print("=== B. every entity whose FAR corner leaves the deck rectangle, worst first ===")
	_rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["far"]) > float(b["far"]))
	var clear_far := 0
	var clear_near := 0
	for row_variant in _rows:
		var row := row_variant as Dictionary
		if float(row["far"]) > 0.0:
			clear_far += 1
		if float(row["near"]) > 0.0:
			clear_near += 1
	for i in mini(_rows.size(), 20):
		var row := _rows[i] as Dictionary
		print(
			"  far %+8.3f  near %+8.3f  margin %5.2f  %-28s %-5s #%-4d %-14s %s"
			% [row["far"], row["near"], row["margin"], row["file"], row["kind"],
				int(row["id"]), row["what"], row["is"]]
		)
	print("  %d entities have a corner outside the rectangle;" % clear_far)
	print("  %d entities lie ENTIRELY outside it" % clear_near)

	print("")
	print("=== C. how many shipped entities does each rule refuse? ===")
	print("  rule                                    refused of %d" % _rows.size())
	for spec in [
		["every corner within the rectangle", "far", 0.0, false],
		["any corner within the rectangle", "near", 0.0, false],
		["every corner within rect + half_beam", "far", 0.0, true],
		["any corner within rect + half_beam", "near", 0.0, true],
		["every corner within rect + 1 m", "far", 1.0, false],
		["every corner within rect + 2 m", "far", 2.0, false],
	]:
		var field := str(spec[1])
		var fixed := float(spec[2])
		var scaled := bool(spec[3])
		var n := 0
		for row_variant in _rows:
			var row := row_variant as Dictionary
			var margin := float(row["margin"]) if scaled else fixed
			if float(row[field]) > margin:
				n += 1
		print("  %-40s %d" % [str(spec[0]), n])

	print("")
	print("=== D. the deliberate off-hull plan, both rules ===")
	var grid := HullRegistry.make_grid("fishing_trawler_small")
	print("  grid %d x %d cells = %.1f x %.1f m, half_beam %.2f"
		% [grid.width, grid.length, float(grid.width) * 0.5, float(grid.length) * 0.5, grid.half_beam])
	var plan := StructurePlan.new()
	plan.hull_id = "fishing_trawler_small"
	plan.add_deck(Vector3(0.0, 3.0, 0.0), Vector2(4.0, 4.0))
	_report(plan, grid, "on-hull only")
	plan.add_wall(Vector3(900.0, 0.0, 900.0), "x", 10.0)
	plan.add_deck(Vector3(900.0, 0.0, 900.0), Vector2(10.0, 10.0))
	plan.add_stair(Vector3(900.0, 0.0, 900.0), "+x", 4.0)
	_report(plan, grid, "+ off-hull")

	print("")
	print("=== E. the plausible authoring error: one entity ANCHORED on deck ===")
	var reach := StructurePlan.new()
	reach.hull_id = "fishing_trawler_small"
	reach.add_deck(Vector3(0.0, 3.0, 0.0), Vector2(4.0, 4.0))
	reach.add_wall(Vector3(2.0, 0.0, 2.0), "x", 900.0)
	_report(reach, grid, "wall 900 m long")

	print("")
	print("=== F. which catalog parts fall in which band of PlanOutfit.validate ===")
	var bands := {}
	for part_id in PartCatalog.ids():
		var slot := PartCatalog.outfit_slot_of(part_id)
		var cargo := false
		for tag in ["cargo", "bulk_hold"]:
			if PartCatalog.has_tag(part_id, tag):
				cargo = true
		var band := "SILENT"
		if cargo:
			band = "ERROR (cargo)"
		elif slot in ["fishing", "helm", "crane", "tow"]:
			band = "WARNING (slot %s)" % slot
		if not bands.has(band):
			bands[band] = []
		(bands[band] as Array).append(part_id)
	for band in bands.keys():
		print("  %-22s %d parts: %s" % [band, (bands[band] as Array).size(), bands[band]])

	print("")
	print("=== G. compliance-counted parts, and which band they are in ===")
	for part_id in PartCatalog.ids():
		var compliance := PartCatalog.compliance_of(part_id)
		if compliance.is_empty() and PartCatalog.tags_of(part_id).is_empty():
			continue
		var tags := PartCatalog.tags_of(part_id)
		var interesting := false
		for tag in ["nav_white", "nav_port", "nav_stbd", "mooring", "helm", "light"]:
			if tags.has(tag):
				interesting = true
		if not interesting:
			continue
		print("  %-22s slot %-8s tags %s" % [part_id, PartCatalog.outfit_slot_of(part_id), tags])

	quit(0)


func _measure(path: String, label: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		return {}
	var plan_in := StructurePlan.from_dict(parsed as Dictionary)
	if plan_in.context != "vessel" or plan_in.hull_id.is_empty():
		print("  %-32s (no hull — context \"%s\")" % [label, plan_in.context])
		return {}
	var grid := HullRegistry.make_grid(plan_in.hull_id)
	if grid == null:
		grid = plan_in.hull_grid()
	if grid == null:
		print("  %-32s NO GRID for hull %s" % [label, plan_in.hull_id])
		return {}
	var rows := _entity_boxes(plan_in)
	var boxes := 0
	var worst_near := -INF
	var worst_far := -INF
	for row_variant in rows:
		var row := row_variant as Dictionary
		var list := row["boxes"] as Array
		boxes += list.size()
		var pair := _reach(list, grid)
		worst_near = maxf(worst_near, pair.x)
		worst_far = maxf(worst_far, pair.y)
		_rows.append({
			"near": pair.x, "far": pair.y, "margin": grid.half_beam, "file": label,
			"kind": row["kind"], "id": row["id"], "what": row["what"], "is": row["is"],
		})
	print(
		"  %-32s %4.1fx%-5.1f %5d %6d %8.2f %+9.3f %+9.3f"
		% [label, float(grid.width) * 0.5, float(grid.length) * 0.5, rows.size(), boxes,
			grid.half_beam, worst_near, worst_far]
	)
	return {"ents": rows.size(), "boxes": boxes}


## Every box the plan really draws, grouped by the entity that drew it — the same
## loop `StructureBaker.collect_colliders` runs, in the same order.
static func _entity_boxes(plan_in: StructurePlan) -> Array:
	var plan := StructureBaker.resolved(plan_in)
	var expanded := StructureBaker.expand(plan)
	var out: Array = []
	for wall_variant in expanded["walls"] as Array:
		var wall := wall_variant as Dictionary
		out.append({
			"kind": "wall", "id": int(wall.get("source_id", -1)), "what": "",
			"is": str(wall.get("_is", "")), "boxes": StructureBaker.wall_boxes(wall),
		})
	for deck_variant in expanded["decks"] as Array:
		var deck := deck_variant as Dictionary
		out.append({
			"kind": "deck", "id": int(deck.get("source_id", -1)), "what": "",
			"is": str(deck.get("_is", "")), "boxes": StructureBaker.deck_boxes(deck),
		})
	for stair_variant in expanded["stairs"] as Array:
		var stair := stair_variant as Dictionary
		out.append({
			"kind": "stair", "id": int(stair.get("source_id", -1)), "what": "",
			"is": str(stair.get("_is", "")), "boxes": StructureBaker.stair_boxes(stair),
		})
	for item_variant in plan.items:
		var item := item_variant as Dictionary
		var props := StructurePlan.item_props(item)
		out.append({
			"kind": "item", "id": int(item.get("id", -1)),
			"what": str(item.get("item_id", "")),
			"is": str(props.get("_is", "")),
			"boxes": StructureBaker._item_colliders(plan, item, Vector3.ZERO),
		})
	for edge_variant in plan.edges:
		var edge := edge_variant as Dictionary
		out.append({
			"kind": "edge", "id": int(edge.get("id", -1)), "what": "",
			"is": str(edge.get("_is", "")), "boxes": StructureBaker.edge_collider_boxes(plan, edge),
		})
	return out


## Signed distance from a plan-space XZ point to the deck RECTANGLE.
static func _rect_sdf(grid: DeckGrid, x: float, z: float) -> float:
	var m := WorldUnits.DECK_CELL_M
	return maxf(maxf(-x, x - float(grid.width) * m), maxf(-z, z - float(grid.length) * m))


## Vector2(near, far) — closest and furthest corner of everything the entity draws.
static func _reach(boxes: Array, grid: DeckGrid) -> Vector2:
	var near := INF
	var far := -INF
	for box_variant in boxes:
		var box := box_variant as Dictionary
		var c: Vector3 = box["center"]
		var s: Vector3 = box["size"]
		var b := Basis(Vector3.UP, deg_to_rad(float(box.get("yaw_deg", 0.0))))
		for i in 4:
			var corner := c + b * Vector3(
				(s.x * 0.5) if (i & 1) != 0 else (-s.x * 0.5),
				0.0,
				(s.z * 0.5) if (i & 2) != 0 else (-s.z * 0.5),
			)
			var d := _rect_sdf(grid, corner.x, corner.z)
			near = minf(near, d)
			far = maxf(far, d)
	if not is_finite(near):
		return Vector2(-INF, -INF)
	return Vector2(near, far)


func _report(plan: StructurePlan, grid: DeckGrid, label: String) -> void:
	var rows := _entity_boxes(plan)
	var near_off := 0
	var far_off := 0
	for row_variant in rows:
		var pair := _reach((row_variant as Dictionary)["boxes"] as Array, grid)
		if pair.x > grid.half_beam:
			near_off += 1
		if pair.y > grid.half_beam:
			far_off += 1
	var node := StructureBaker.bake(plan)
	var aabb := _aabb_of(node)
	node.free()
	print(
		"  %-18s aabb %s | colliders %d | ents %d | any-rule refuses %d | every-rule refuses %d"
		% [label, aabb, StructureBaker.collect_colliders(plan).size(), rows.size(),
			near_off, far_off]
	)


func _aabb_of(node: Node) -> AABB:
	var out := AABB()
	var first := true
	for child in node.get_children():
		if child is MeshInstance3D:
			var mi := child as MeshInstance3D
			if mi.mesh != null:
				var a := mi.mesh.get_aabb()
				a.position += mi.position
				if first:
					out = a
					first = false
				else:
					out = out.merge(a)
		var sub := _aabb_of(child)
		if sub.size != Vector3.ZERO:
			if first:
				out = sub
				first = false
			else:
				out = out.merge(sub)
	return out
