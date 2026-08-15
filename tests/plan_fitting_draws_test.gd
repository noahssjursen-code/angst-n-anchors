extends Node

## Lane B. Does a plan's CATALOGUE FITTING reach a frame?
##
## `plan_item_handoff_test` asks `PartCatalog` what a part expands to and
## `part_catalog_test` asks whether an emitter exists. Neither is where the bug
## was. The bug was that `StructureBaker._item_layers` returned `[]` for every
## `item_id` that was not `plate` / `spar` / `wire`, so a `bollard_pair` counted
## toward a registration and appeared in no frame — and every check pointed at
## the producer stayed green through all of it (REALITY.md §3).
##
## So this test never asks the catalog what it meant. It runs
## `VesselSpawn.instantiate` -> `DeckFitout.apply_plan` and then counts what is
## actually there: triangles on the committed `ArrayMesh` under the vessel's
## `DeckFitout` root, and shapes on the WalkDeck body as `PhysicsServer3D`
## holds them.
##
## THE STRIP TEST IS THE FIRST CHECK (REALITY.md §3d). Measured before the
## emitters landed, on this exact path:
##
##     AS AUTHORED     18 fittings | 12 triangles  1 mesh  1 plan collider
##     FITTINGS DELETED    0        | 12 triangles  1 mesh  1 plan collider
##
## Identical — the 12 triangles are the deck plate under them. All 15 catalogue
## part ids drew nothing. Reverting `_item_layers`' catalogue branch to `return
## []` reproduces exactly that and reddens this file.

const TestReport := preload("res://tests/support/test_report.gd")

const HULL_ID := "hull_28x10"
const REGISTRATION := "general_vessel"
## DeckFitout names its plan colliders "BrickCol_" + "plan_%d".
const PLAN_PREFIX := "BrickCol_plan_"
## A deck to stand the fittings on, so the stripped control is not an empty plan.
const DECK_AT := Vector3(1.0, 0.0, 2.0)
const DECK_SIZE := Vector2(8.0, 20.0)

var _t: RefCounted
var _boat: BoatBody
var _grid: DeckGrid


func _ready() -> void:
	_t = TestReport.new("plan_fitting_draws_test")
	var ids := PartCatalog.ids()
	if not _t.check("the part catalog loaded (%d parts)" % ids.size(), ids.size() >= 12):
		_t.finish(get_tree())
		return
	_grid = HullRegistry.make_grid(HULL_ID)

	var authored := _fitted_plan(ids)
	_boat = VesselSpawn.instantiate(HULL_ID, authored.to_dict(), REGISTRATION)
	if not _t.check("VesselSpawn.instantiate returned a vessel", _boat != null):
		_t.finish(get_tree())
		return
	add_child(_boat)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var fitted := _census()
	var stripped := await _reapply(_bare_plan())
	print("[draws] AS AUTHORED     %2d fittings | %5d tris %2d meshes %4d plan shapes"
		% [authored.items.size(), int(fitted["tris"]), int(fitted["meshes"]),
			int(fitted["shapes"])])
	print("[draws] FITTINGS DELETED  0          | %5d tris %2d meshes %4d plan shapes"
		% [int(stripped["tris"]), int(stripped["meshes"]), int(stripped["shapes"])])

	## THE STRIP TEST. Not "the fitted plan draws something" — that passes on the
	## deck plate alone, which is exactly how this went unnoticed.
	_t.check(
		"deleting the fittings removes triangles from the frame (%d -> %d)"
			% [int(fitted["tris"]), int(stripped["tris"])],
		int(fitted["tris"]) > int(stripped["tris"])
	)
	_t.check(
		"deleting the fittings removes shapes from the physics body (%d -> %d)"
			% [int(fitted["shapes"]), int(stripped["shapes"])],
		int(fitted["shapes"]) > int(stripped["shapes"])
	)

	await _check_every_part_draws(ids)
	_check_compliance_still_counts_them(authored)
	_check_a_wire_is_never_solid()
	_check_the_part_keeps_its_colour()
	_check_air_draught_is_the_drawn_top()
	_check_a_part_is_drawn_where_it_was_placed()
	_t.finish(get_tree())


# ── Every catalogue part, one at a time, through the production path ─────────

## The number that WAS the finding: how many catalogue part ids draw nothing.
## It was 15 of 15. A part that expands to geometry and reaches no frame is the
## piece-kit defect, and it is not detectable from the catalog side.
func _check_every_part_draws(ids: PackedStringArray) -> void:
	var base := await _reapply(_bare_plan())
	var silent := PackedStringArray()
	var no_collide := PackedStringArray()
	for id_variant in ids:
		var id := str(id_variant)
		var one := await _reapply(_fitted_plan(PackedStringArray([id])))
		if int(one["tris"]) <= int(base["tris"]):
			silent.append(id)
		if int(one["shapes"]) <= int(base["shapes"]):
			no_collide.append(id)
		print("[draws] %-20s %+5d tris %+5d plan shapes"
			% [id, int(one["tris"]) - int(base["tris"]),
				int(one["shapes"]) - int(base["shapes"])])
	_t.check(
		"every catalogue part draws triangles through apply_plan (silent: %s)"
			% ("none" if silent.is_empty() else ", ".join(silent)),
		silent.is_empty()
	)
	## Not every part is an obstruction — a wire is never solid, and that is a
	## policy, not an omission. So this states the ones that MUST stop a player,
	## by name, rather than demanding colliders from all of them.
	for id in ["bollard_pair", "helm_console", "hold_coaming", "mast_with_platform"]:
		_t.check(
			"a %s the player can see is a %s the player cannot walk through" % [id, id],
			not no_collide.has(id)
		)


# ── The half that must NOT be "fixed" by counting less ───────────────────────

## A fitting that draws must still certify. The tempting cheap fix for "counted
## but not drawn" is to stop counting, and that trades an invisible bollard for
## a boat that cannot be registered — a worse bug than the one being fixed.
func _check_compliance_still_counts_them(plan: StructurePlan) -> void:
	var report := PlanOutfit.compliance(plan, HULL_ID, REGISTRATION, _grid)
	var metrics := PlanOutfit.measure(plan, _grid, report)
	var tags := metrics["tag_counts"] as Dictionary
	print("[draws] tag_counts %s" % str(tags))
	_t.check("four bollard pairs still count four mooring points",
		int(tags.get("mooring", 0)) == 4)
	_t.check("an all-round lantern still counts a white light",
		int(tags.get("nav_white", 0)) == 1)
	_t.check("a helm console still fills the helm slot",
		int(((report.get("accepted_slots", {}) as Dictionary).get("helm", []) as Array).size()) == 1)

	## And the other half of "counted": a RAW PRIMITIVE is not an unknown fitting.
	## It is measured as geometry and carries no compliance identity, which is a
	## different thing from "the catalog has never heard of it" — 916 of the
	## shipped fleet's items are `spar` and `wire`, and reporting each of them as
	## un-measurable is 916 lines of noise in the builder's own panel.
	var raw := _bare_plan()
	raw.add_item("spar", Vector3(4.0, 0.0, 9.0), 0.0, {
		"primitive": "spar", "from": [0, 0, 0], "to": [0, 3, 0], "radius": 0.1,
	})
	raw.add_item("nothing_of_the_sort", Vector3(4.0, 0.0, 11.0))
	var raw_report := PlanOutfit.compliance(raw, HULL_ID, REGISTRATION, _grid)
	var unknown := PackedStringArray()
	for message in raw_report.get("warnings", PackedStringArray()) as PackedStringArray:
		if str(message).contains("not measured"):
			unknown.append(str(message))
	print("[draws] unknown-part warnings: %s" % str(unknown))
	_t.check("a raw primitive is not reported as an unknown fitting (%d warnings)"
		% unknown.size(), unknown.size() == 1)
	_t.check("but a genuinely unknown fitting still is, by name",
		unknown.size() == 1 and unknown[0].contains("nothing_of_the_sort"))


## `collect_colliders()` argues at length that a wire is never solid: standing
## rigging crosses a working deck everywhere and a shroud that stops a player is
## an invisible wall at head height. Now that a `wire_run` DRAWS, the policy has
## somewhere to be got wrong, so it is pinned.
func _check_a_wire_is_never_solid() -> void:
	var plan := _fitted_plan(PackedStringArray(["wire_run"]))
	var drawn := 0
	var node := StructureBaker.bake(plan)
	drawn = _triangles(node)
	node.free()
	var item_boxes := 0
	for row_variant in StructureBaker.entity_colliders(plan):
		var row := row_variant as Dictionary
		if str(row["kind"]) == "item":
			item_boxes += (row["boxes"] as Array).size()
	_t.check("a wire_run draws (%d triangles)" % drawn, drawn > 0)
	_t.check("and collides with nothing (%d boxes)" % item_boxes, item_boxes == 0)


## A part declares a colour and the catalog parses it into a `Color`; a plan
## writes colour as `[r, g, b]` because that is what survives JSON. Both reach
## the same layer, and `StructureBaker._color_of` handled only the array — so a
## #4d5257 bollard and a #f2efe4 lantern lens both came out the one spar grey.
## Colour rides in the VERTEX STREAM here (that is why a plan may use unlimited
## colours for no draw calls), so this reads the vertices.
func _check_the_part_keeps_its_colour() -> void:
	var wanted := PartCatalog.color_of("lantern_all_round")
	var plan := _fitted_plan(PackedStringArray(["lantern_all_round"]))
	var node := StructureBaker.bake(plan)
	var found := false
	var distinct := {}
	for color in _vertex_colors(node):
		distinct[color] = true
		if color.is_equal_approx(wanted):
			found = true
	node.free()
	_t.check(
		"a part's declared colour reaches the vertex stream (%s among %d distinct)"
			% [wanted.to_html(false), distinct.size()],
		found
	)


## The plan's reported air draught is the top of what it DRAWS. It used to be
## the top of what the CATALOG would have drawn: `max_stack_cells` asked
## `part_local_aabb` about every item, and `spar` was a catalog id, so 844
## shipped spars were measured with the part's default 6.0 m length stacked on
## wherever they stood. A boom lying flat on the deck reported 6.0 m of air
## draught.
##
## Asserted as the PROPERTY rather than as a cell count: the reported cells floor
## the drawn top, which survives any change to the geometry.
##
## THE FIRST VERSION OF THIS CHECK WAS BLIND, and the mutation said so on the
## first try (REALITY.md standing order 8). It used only a boom lying FLAT, which
## catches an OVERSTATEMENT — the pre-rename defect, where `spar` was a catalog id
## and the reading came back with the part's 6.0 m default length. Reverting the
## fix left it green, because after the rename `part_local_aabb("spar")` finds no
## such part, answers `ok=false`, and the old code then contributed nothing at
## all. The failure mode had inverted from over to UNDER and the check only
## looked one way.
##
## So the plan below carries three items whose drawn tops are all different, and
## the assertion is equality with the floor of the tallest.
func _check_air_draught_is_the_drawn_top() -> void:
	var plan := _bare_plan()
	## A boom lying flat, 6 m along +X at deck level. Nothing about it is tall.
	plan.add_item("spar", Vector3(2.0, 0.0, 8.0), 0.0, {
		"primitive": "spar", "from": [0, 0, 0], "to": [6, 0, 0], "radius": 0.08,
	})
	## An upright post 3 m tall. This is the one that catches an understatement.
	plan.add_item("spar", Vector3(5.0, 0.0, 12.0), 0.0, {
		"primitive": "spar", "from": [0, 0, 0], "to": [0, 3, 0], "radius": 0.1,
	})
	## And the tallest thing on the plan is a PLATE, an item the old reading could
	## not measure at all — it asked the catalog about the id "plate" and there is
	## no such part, so it answered `ok=false` and a plate contributed nothing.
	## 836 of the shipped fleet's items are spelled this way.
	plan.add_item("plate", Vector3(3.0, 0.0, 16.0), 0.0, {
		"primitive": "plate", "thickness": 0.05,
		"corners": [[0, 0, 0], [2, 0, 0], [2, 5.2, 0], [0, 5.2, 0]],
	})
	var node := StructureBaker.bake(plan)
	var drawn_top := _drawn_top(node)
	node.free()
	var cell := WorldUnits.DECK_CELL_M
	var cells := PlanOutfit.max_stack_cells(plan, _grid)
	var reported := float(cells) * cell
	print("[draws] air draught: %d cells = %.3f m against a drawn top of %.3f m"
		% [cells, reported, drawn_top])
	_t.check("the plan's air draught does not exceed what it draws (%.3f m vs %.3f m)"
		% [reported, drawn_top], reported <= drawn_top + 1e-3)
	_t.check("and it floors that top to within one cell (%.3f m vs %.3f m)"
		% [reported, drawn_top], reported > drawn_top - cell - 1e-3)

	## And the same plan with the plate removed must report LESS. A reading that
	## measures spars but ignores plates would satisfy both bounds above on a plan
	## where a spar happened to be tallest, which is how the first version of this
	## check went green against its own mutation.
	var without := _bare_plan()
	without.add_item("spar", Vector3(5.0, 0.0, 12.0), 0.0, {
		"primitive": "spar", "from": [0, 0, 0], "to": [0, 3, 0], "radius": 0.1,
	})
	var lower := PlanOutfit.max_stack_cells(without, _grid)
	_t.check("the plate is what sets it: removing it lowers the air draught (%d -> %d cells)"
		% [cells, lower], cells > lower)


## A part is drawn WHERE IT WAS PUT, and turning it turns the geometry. The
## catalog resolves a part in its own frame; the item carries the placement, and
## the baker multiplies. Without this, dropping the transform would still pass
## every count above — the triangles would all be there, stacked at the origin,
## and the strip test cannot see the difference.
func _check_a_part_is_drawn_where_it_was_placed() -> void:
	var here := _one_item_bounds("bollard_pair", Vector3(3.0, 0.0, 6.0), 0.0)
	var there := _one_item_bounds("bollard_pair", Vector3(3.0, 0.0, 16.0), 0.0)
	var moved := there.get_center().z - here.get_center().z
	print("[draws] the same bollard 10 m aft draws %.2f m aft" % moved)
	_t.check("moving an item 10 m moves what it draws 10 m (%.2f m)" % moved,
		absf(moved - 10.0) < 0.05)
	## A bollard pair is two posts 1.2 m apart on its own +X. Turned 90 degrees
	## that separation is along Z, so the drawn box swaps its long axis — a
	## placement that dropped the rotation and kept the position would pass the
	## check above and fail this one.
	var flat := _one_item_bounds("bollard_pair", Vector3(3.0, 0.0, 6.0), 0.0)
	var turned := _one_item_bounds("bollard_pair", Vector3(3.0, 0.0, 6.0), 90.0)
	print("[draws] unturned %.2f x %.2f m, turned 90 deg %.2f x %.2f m"
		% [flat.size.x, flat.size.z, turned.size.x, turned.size.z])
	_t.check(
		"yawing an item 90 degrees swaps the axes of what it draws",
		flat.size.x > flat.size.z + 0.5 and turned.size.z > turned.size.x + 0.5
	)


## The bake AABB of a plan holding exactly one item and nothing else.
func _one_item_bounds(part_id: String, at: Vector3, yaw: float) -> AABB:
	var plan := StructurePlan.new()
	plan.hull_id = HULL_ID
	plan.add_item(part_id, at, yaw)
	var node := StructureBaker.bake(plan)
	var box := AABB()
	var first := true
	var stack: Array = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var local := (n as MeshInstance3D).mesh.get_aabb()
			box = local if first else box.merge(local)
			first = false
		for child in n.get_children():
			stack.append(child)
	node.free()
	return box


func _vertex_colors(node: Node) -> Array[Color]:
	var out: Array[Color] = []
	if node is MeshInstance3D:
		var mesh := (node as MeshInstance3D).mesh
		if mesh != null:
			for surface in mesh.get_surface_count():
				var raw: Variant = mesh.surface_get_arrays(surface)[Mesh.ARRAY_COLOR]
				if raw is PackedColorArray:
					for color in raw as PackedColorArray:
						out.append(color)
	for child in node.get_children():
		out.append_array(_vertex_colors(child))
	return out


func _drawn_top(node: Node) -> float:
	var top := -INF
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var box := (node as MeshInstance3D).mesh.get_aabb()
		top = box.position.y + box.size.y
	for child in node.get_children():
		top = maxf(top, _drawn_top(child))
	return top


# ── Plans, and the census ────────────────────────────────────────────────────

func _bare_plan() -> StructurePlan:
	var plan := StructurePlan.new()
	plan.hull_id = HULL_ID
	plan.add_deck(DECK_AT, DECK_SIZE)
	return plan


## Every named part on the deck centreline, spaced so nothing leaves the hull
## envelope — an off-hull entity is REFUSED before it draws, which would confound
## the strip test rather than fail it.
func _fitted_plan(ids: PackedStringArray) -> StructurePlan:
	var plan := _bare_plan()
	var z := 6.0
	for id_variant in ids:
		var id := str(id_variant)
		## Four bollards, because `general_vessel` wants four mooring points.
		var n := 4 if id == "bollard_pair" else 1
		for i in n:
			plan.add_item(id, Vector3(1.5 + float(i) * 1.5, 0.0, z))
		z += 1.0
	return plan


func _reapply(plan: StructurePlan) -> Dictionary:
	DeckFitout.apply_plan(_boat, plan, _grid, REGISTRATION)
	await get_tree().physics_frame
	await get_tree().physics_frame
	return _census()


## What is in the world: triangles on the committed meshes under the vessel's
## own DeckFitout root, and plan shapes on the WalkDeck body as the physics
## server holds them.
func _census() -> Dictionary:
	var root := _boat.get_node_or_null(DeckFitout.FITOUT_ROOT)
	var meshes := 0
	var tris := 0
	if root != null:
		meshes = _mesh_instances(root)
		tris = _triangles(root)
	var shapes := 0
	var walk := _boat.call("get_walk_deck") as CollisionObject3D
	if walk != null:
		var rid := walk.get_rid()
		for i in PhysicsServer3D.body_get_shape_count(rid):
			var owner: Node = walk.shape_owner_get_owner(walk.shape_find_owner(i)) as Node
			if owner != null and str(owner.name).begins_with(PLAN_PREFIX):
				shapes += 1
	return {"meshes": meshes, "tris": tris, "shapes": shapes}


func _mesh_instances(node: Node) -> int:
	var n := 1 if (node is MeshInstance3D and (node as MeshInstance3D).mesh != null) else 0
	for child in node.get_children():
		n += _mesh_instances(child)
	return n


func _triangles(node: Node) -> int:
	var total := 0
	if node is MeshInstance3D:
		var mesh := (node as MeshInstance3D).mesh
		if mesh != null:
			for surface in mesh.get_surface_count():
				var arrays := mesh.surface_get_arrays(surface)
				var idx: Variant = arrays[Mesh.ARRAY_INDEX]
				if idx is PackedInt32Array and (idx as PackedInt32Array).size() > 0:
					total += (idx as PackedInt32Array).size() / 3
					continue
				var verts: Variant = arrays[Mesh.ARRAY_VERTEX]
				if verts is PackedVector3Array:
					total += (verts as PackedVector3Array).size() / 3
	for child in node.get_children():
		total += _triangles(child)
	return total
