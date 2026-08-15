extends Node

## SCRATCH PROBE (leading underscore — the gate must not discover it).
##
## THE STRIP TEST for catalogue fittings, REALITY.md §3d. A plan carrying one of
## every `PartCatalog` part is taken through the PRODUCTION path —
## `VesselSpawn.instantiate` -> `DeckFitout.apply_plan` -> a real scene tree and
## a real `PhysicsServer3D` — and what reaches a frame is counted against what
## `PlanOutfit` counted off the same document.
##
##   xvfb-run -a --server-args="-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy res://tests/_fitting_strip.tscn
##
## Three measurements, in order:
##   1. AS AUTHORED  — mesh instances, triangles, plan collider shapes on the
##      WalkDeck body, and the compliance verdict.
##   2. ITEMS DELETED — the same plan with `items[]` emptied. If the two agree,
##      the fittings contributed nothing (this is the piece-kit shape).
##   3. PER PART ID  — one plan per catalogue id, baked alone, so the finding is
##      a NUMBER: how many catalogue part ids draw nothing.

const HULL_ID := "hull_28x10"
const REGISTRATION := "general_vessel"
const PLAN_PREFIX := "BrickCol_plan_"

var _rows: Array = []


func _ready() -> void:
	PartCatalog.ensure_loaded()
	var ids := PartCatalog.ids()
	print("[strip] catalogue holds %d parts: %s" % [ids.size(), ", ".join(ids)])
	print("[strip] baker_supports: %s" % _supports_line())

	var authored := _fitted_plan(ids)
	var stripped := authored.duplicate(true)
	stripped["items"] = []

	print("\n[strip] ===== THE STRIP TEST =====")
	var a := await _measure("AS AUTHORED", authored)
	var b := await _measure("ITEMS DELETED", stripped)
	print("[strip] %-16s %3d items | %6d tris %4d meshes %4d plan shapes"
		% ["AS AUTHORED", int(a["items"]), int(a["tris"]), int(a["meshes"]), int(a["shapes"])])
	print("[strip] %-16s %3d items | %6d tris %4d meshes %4d plan shapes"
		% ["ITEMS DELETED", int(b["items"]), int(b["tris"]), int(b["meshes"]), int(b["shapes"])])
	print("[strip] DELTA from %d fittings: %+d tris  %+d meshes  %+d shapes"
		% [int(a["items"]), int(a["tris"]) - int(b["tris"]),
			int(a["meshes"]) - int(b["meshes"]), int(a["shapes"]) - int(b["shapes"])])
	print("[strip] PlanOutfit counted, on the SAME document:")
	print("[strip]   authored  brick_counts=%d tag_counts=%s registration_ok=%s"
		% [int(a["counted"]), str(a["tags"]), str(a["registration_ok"])])
	print("[strip]   stripped  brick_counts=%d tag_counts=%s registration_ok=%s"
		% [int(b["counted"]), str(b["tags"]), str(b["registration_ok"])])

	print("\n[strip] ===== PER PART ID, BAKED ALONE =====")
	var draws := 0
	var silent := PackedStringArray()
	for id_variant in ids:
		var id := str(id_variant)
		var one := _fitted_plan(PackedStringArray([id]))
		var m := await _measure("part:%s" % id, one, false)
		var aabb := PlanOutfit.part_local_aabb(id, {})
		var counted := bool(aabb.get("ok", false))
		if int(m["tris"]) > int(m["base_tris"]):
			draws += 1
		else:
			silent.append(id)
		print("[strip] %-20s measured=%-5s  drew %+d tris %+d meshes %+d shapes"
			% [id, str(counted), int(m["tris"]) - int(m["base_tris"]),
				int(m["meshes"]) - int(m["base_meshes"]),
				int(m["shapes"]) - int(m["base_shapes"])])
	print("[strip] OF %d CATALOGUE PART IDS, %d DRAW SOMETHING AND %d DRAW NOTHING"
		% [ids.size(), draws, silent.size()])
	print("[strip] silent: %s" % ", ".join(silent))

	get_tree().quit(0)


func _supports_line() -> String:
	var out := PackedStringArray()
	for prim in PartCatalog.PRIMITIVES.keys():
		out.append("%s=%s" % [str(prim), str(PartCatalog.baker_supports(str(prim)))])
	return ", ".join(out)


## A plan on the 28 m trawler carrying one of each named part, spread along the
## deck centreline so nothing is off the hull and nothing overlaps.
func _fitted_plan(ids: PackedStringArray) -> Dictionary:
	var plan := StructurePlan.new()
	plan.hull_id = HULL_ID
	## A deck to stand the fittings on, so the "stripped" control is not empty.
	plan.add_deck(Vector3(1.0, 0.0, 2.0), Vector2(8.0, 20.0))
	var z := 6.0
	for id_variant in ids:
		var id := str(id_variant)
		## Four bollards, because `general_vessel` wants four mooring points.
		var n := 4 if id == "bollard_pair" else 1
		for i in n:
			plan.add_item(id, Vector3(1.5 + float(i) * 1.5, 0.0, z))
		z += 1.0
	return plan.to_dict()


func _measure(tag: String, layout: Dictionary, verbose := true) -> Dictionary:
	var boat: BoatBody = VesselSpawn.instantiate(HULL_ID, layout, REGISTRATION)
	if boat == null:
		printerr("[strip] %s: VesselSpawn returned null" % tag)
		return {}
	add_child(boat)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var meshes := 0
	var tris := 0
	var census := _mesh_census(boat)
	meshes = int(census["meshes"])
	tris = int(census["tris"])

	var shapes := 0
	var walk := boat.call("get_walk_deck") as CollisionObject3D
	if walk != null:
		var rid := walk.get_rid()
		for i in PhysicsServer3D.body_get_shape_count(rid):
			var owner: Node = walk.shape_owner_get_owner(walk.shape_find_owner(i)) as Node
			if owner != null and str(owner.name).begins_with(PLAN_PREFIX):
				shapes += 1

	var plan := StructurePlan.from_dict(layout)
	var grid := HullRegistry.make_grid(HULL_ID)
	var off_hull := PlanOutfit.off_hull_entities(StructureBaker.resolved(plan), grid)
	if not off_hull.is_empty():
		printerr("[strip] %s: %d entities OFF HULL — the strip test is confounded"
			% [tag, off_hull.size()])
	var report := PlanOutfit.compliance(plan, HULL_ID, REGISTRATION, grid)
	var metrics := PlanOutfit.measure(plan, grid, report)
	var counted := 0
	for key in (metrics["brick_counts"] as Dictionary).keys():
		counted += int((metrics["brick_counts"] as Dictionary)[key])

	## The control: the same hull and the same plan with no items at all, so a
	## per-part delta is against ITS OWN baseline rather than a remembered one.
	var base := {"tris": 0, "meshes": 0, "shapes": 0}
	if not verbose:
		base = _bare_baseline()

	remove_child(boat)
	boat.queue_free()
	if verbose:
		print("[strip] %s: %d meshes, %d triangles, %d plan shapes"
			% [tag, meshes, tris, shapes])
	return {
		"items": (layout.get("items", []) as Array).size(),
		"meshes": meshes, "tris": tris, "shapes": shapes,
		"counted": counted, "tags": metrics["tag_counts"],
		"registration_ok": report.get("registration_ok", false),
		"base_tris": int(base["tris"]), "base_meshes": int(base["meshes"]),
		"base_shapes": int(base["shapes"]),
	}


var _baseline: Dictionary = {}


func _bare_baseline() -> Dictionary:
	if not _baseline.is_empty():
		return _baseline
	var plan := StructurePlan.new()
	plan.hull_id = HULL_ID
	plan.add_deck(Vector3(1.0, 0.0, 2.0), Vector2(8.0, 20.0))
	var boat: BoatBody = VesselSpawn.instantiate(HULL_ID, plan.to_dict(), REGISTRATION)
	add_child(boat)
	var census := _mesh_census(boat)
	var shapes := 0
	var walk := boat.call("get_walk_deck") as CollisionObject3D
	if walk != null:
		var rid := walk.get_rid()
		for i in PhysicsServer3D.body_get_shape_count(rid):
			var owner: Node = walk.shape_owner_get_owner(walk.shape_find_owner(i)) as Node
			if owner != null and str(owner.name).begins_with(PLAN_PREFIX):
				shapes += 1
	remove_child(boat)
	boat.queue_free()
	_baseline = {"tris": int(census["tris"]), "meshes": int(census["meshes"]), "shapes": shapes}
	print("[strip] bare baseline (deck only): %d meshes %d tris %d shapes"
		% [int(_baseline["meshes"]), int(_baseline["tris"]), shapes])
	return _baseline


## Every MeshInstance3D under the FITOUT root, and the triangles its mesh
## actually holds — read off the ArrayMesh, not off a count the baker returned.
func _mesh_census(root: Node) -> Dictionary:
	var fitout := _find_fitout(root)
	var meshes := 0
	var tris := 0
	var stack: Array = [fitout if fitout != null else root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node == null:
			continue
		if node is MeshInstance3D:
			var mi := node as MeshInstance3D
			if mi.mesh != null:
				meshes += 1
				for s in mi.mesh.get_surface_count():
					var arrays := mi.mesh.surface_get_arrays(s)
					var raw_idx: Variant = arrays[Mesh.ARRAY_INDEX]
					if raw_idx is PackedInt32Array and (raw_idx as PackedInt32Array).size() > 0:
						tris += (raw_idx as PackedInt32Array).size() / 3
					else:
						var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
						tris += verts.size() / 3
		for child in node.get_children():
			stack.append(child)
	return {"meshes": meshes, "tris": tris}


func _find_fitout(root: Node) -> Node:
	var stack: Array = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if str(node.name) == "Fitout" or str(node.name) == DeckFitout.FITOUT_ROOT:
			return node
		for child in node.get_children():
			stack.append(child)
	return null
