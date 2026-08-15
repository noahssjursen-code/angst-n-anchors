class_name BuildingCache
extends RefCounted

## Bakes a voxel blueprint ONCE and stamps shared-resource copies of it —
## visuals, collision and doors.
##
## ── WHAT THIS CACHE USED TO COLLIDE AS, AND WHY IT IS GONE ──────────────────
## Until 2026-08-15 the header of this file read *"Collision is a single box per
## instance derived from the layout grid bounds"*, and that box was derived by a
## second function (`_measure_footprint`) from the CELL BOUNDS, while the
## drawing came cell by cell out of `BuildingFitout`. Two derivations of one
## building, which is REALITY.md §3b, and they had drifted:
##
##     PhysicsServer3D held  1 shape for 516 bricks
##     drawn        y 0.250 .. 6.750
##     collision    y 3.000 .. 10.000      <- 2.750 m of air under the box
##
## `col.position = center + Vector3(0, shape.size.y * 0.5 - 0.5, 0)` added half
## the height to a `center` that was already the midpoint. A 1.8 m capsule
## walked through 206 of 206 wall stations and fell through the floor at 25 of
## 25 interior stations: at head height the warehouse was a hologram, and what
## was solid was a slab of air over the roofline.
##
## Correcting that offset alone was measured and rejected — it makes the
## building one sealed monolith whose doorways admit nobody (12/37 in
## `building_interior_test`, the doorway going red at 0.000 m clear). A building
## is not a box; it is the bricks it draws.
##
## ── WHAT IT COLLIDES AS NOW: THE SAME DATA THE VISUAL IS BUILT FROM ─────────
## `_bake_prototype` builds the fit-out ONCE **with collision on** and harvests
## three prototypes out of that one tree:
##
##  - the flat visual list (`VisualFlatten`, unchanged);
##  - every `CollisionShape3D` `BuildingFitout` emitted, as `{shape, transform}`
##    with the `Shape3D` **resource shared** across every instance — 577 boxes
##    for the warehouse, 4 distinct sizes, so the server holds 4 shape RIDs and
##    not 577;
##  - each doorway's visual subtree, kept UNFLATTENED, because `BrickDoor`
##    finds its hinge and leaf by node path and a flattened tree has neither.
##
## There is no second derivation of the collision left in this file: the boxes
## are the boxes `BuildingFitout._add_collider` drew the bricks with, so when the
## open cell decision (STATE.md #1) lands, collision follows the drawing for
## free.
##
## ⚠ THE WALL IS STILL HALF DAYLIGHT AND THAT IS NOT THIS FILE'S TO CLOSE.
## `BuildingGrid.CELL_M` is 1.0 and `BrickCatalog.size_m("block")` draws 0.500 m
## — factor exactly 2.000 — so a per-brick collision shell has a 0.50 m gap at
## every join, and `building_interior_test`'s point scan measures it. A capsule
## is stopped (it does not fit a 0.50 m slot) and a bullet, a camera and daylight
## are not. Making the colliders bigger than the bricks would hide an open owner
## decision behind a green check; they are the size of the bricks.
##
## ── COST, AND WHY THE VESSEL FIX APPLIES HERE FOR FREE ──────────────────────
## `BoatBody.begin_walk_collider_batch/staging` exist because **Jolt rebuilds a
## body's whole compound shape on every `body_add_shape`, but only while the
## body is in a space** (STATE.md, and REALITY.md §4e). Measured again here, on
## a `StaticBody3D`, varying that one input and nothing else
## (`tests/_building_collision_cost_probe.gd`):
##
##      boxes    detached    in a space
##        128     0.54 ms       6.34 ms       x11.7
##        577     2.45 ms     109.25 ms       x44.5   <- this warehouse
##       2048     8.65 ms    1443.63 ms      x167.0
##
## Detached is linear in the box count (0.54 -> 8.65 over 16x); in a space it is
## quadratic. 577 is not a number this file chose — it is what `BuildingFitout`
## emits for `warehouse.json`, and the cache stamps exactly that.
##
## `instance()` needs no staging call to get that, because it assembles into a
## detached root and the CALLER adds it to the tree: every `body_add_shape` here
## happens out of any space. That is a property of this function's shape, so it
## is stated as a rule rather than left to be re-derived — **do not add the
## returned root, or the `Collision` body, to a tree before the shapes are on
## it.** Doing so is the whole 169x.

static var _visual_prototypes: Dictionary = {}  ## blueprint_id -> Node3D
static var _collider_prototypes: Dictionary = {}  ## blueprint_id -> Array[Dictionary]
static var _door_prototypes: Dictionary = {}  ## blueprint_id -> Array[Dictionary]


static func clear() -> void:
	for key in _visual_prototypes.keys():
		var proto: Node3D = _visual_prototypes[key] as Node3D
		if proto != null and is_instance_valid(proto):
			proto.free()
	for key in _door_prototypes.keys():
		for entry_variant in (_door_prototypes[key] as Array):
			var node: Node3D = (entry_variant as Dictionary).get("node") as Node3D
			if node != null and is_instance_valid(node):
				node.free()
	_visual_prototypes.clear()
	_collider_prototypes.clear()
	_door_prototypes.clear()


static func instance(
		layout: BuildingLayout,
		collision_enabled: bool = true,
) -> Node3D:
	if layout == null:
		return Node3D.new()
	var blueprint_id := layout.blueprint_id.strip_edges()
	if blueprint_id.is_empty():
		return BuildingFitout.build(layout, collision_enabled)

	_ensure_prototype(blueprint_id, layout)

	var root := Node3D.new()
	root.name = BuildingFitout.ROOT_NAME
	root.set_meta("building_blueprint_id", blueprint_id)

	var visual := VisualFlatten.stamp(_visual_prototypes[blueprint_id] as Node3D)
	visual.name = "Visual"
	root.add_child(visual)
	_stamp_doors(visual, blueprint_id)

	var lighting := BuildingLighting.new()
	lighting.name = "BuildingLighting"
	root.add_child(lighting)

	if collision_enabled:
		var body := StaticBody3D.new()
		body.name = "Collision"
		root.add_child(body)
		_stamp_collision(body, blueprint_id)

	return root


## Flattens the fit-out tree into a list of childless `VisualInstance3D` at
## world-relative transforms, then stamps copies of that — both through
## `VisualFlatten`, which is the ONE implementation the three prototype caches in
## this project share (REALITY.md §3b). Read its header for what the old
## mesh-only version lost and where the line is drawn.
##
## ⚠ WHAT THIS CACHE USED TO LOSE, kept here because it is this cache's history:
## `_flatten_visuals` rebuilt `MeshInstance3D` and only that, and recursed only
## PAST a mesh. Per stamped warehouse that cost the `Label3D` sign, the
## `OmniLight3D` off every `light`-tagged brick, the
## `building_lens_base_emission` metadata `BuildingLighting` dims a lens through,
## and **72 of 717 meshes** — `BrickCatalog._add_door_face` parents nine
## panel/stile/rail/handle meshes to the `DoorLeaf` MESH, twice per leaf, so both
## cargo doors stamped as blank slabs.
##
## ── THE DELIBERATE DROPS, NAMED HERE RATHER THAN FILTERED IN SILENCE ────────
## `VisualFlatten` keeps every `VisualInstance3D` and nothing else. What that
## costs a BUILDING specifically, and why each is right:
##
##  - `BuildingLighting` — a controller, not a visual. `BuildingFitout.build`
##    parents one to its own root, and `VisualFlatten` drops it because it
##    `extends Node`, not `Node3D`. `instance()` adds a FRESH one at the stamped
##    root, where it walks that instance's own lights; one carried into the
##    prototype would be copied per building and aimed at the prototype.
##
##    The old code named this drop as `if child.name == "BuildingLighting":
##    continue`. That line is gone, and it went on evidence rather than on
##    tidiness: deleting it is `building_cache_visual_test` **PASS (34) ->
##    PASS (34)**, because a `Node` never reached the class test in the first
##    place. Two mechanisms for one drop is the duplication this refactor
##    exists to remove (REALITY.md §3b), and a mutation that changes nothing is
##    a mechanism that holds nothing (§4e). What holds the drop now is
##    `VisualFlatten`'s `Node3D` filter, mutation-verified in
##    `visual_stamp_cache_test` ("the behaviour controller is not carried into
##    the prototype", red under a loosened filter).
##  - `BrickDoor` — behaviour, and no longer a LOSS. The prototype's door node
##    is freed here, and `_stamp_doors` builds a fresh, configured one per
##    instance over a duplicated (not flattened) door subtree. See
##    `_harvest_doors`.
##  - `Marker3D` anchors (`HelmEye`, `Emitter`) — attachment points for the ship
##    lighting path, which land buildings do not run.
static func _ensure_prototype(blueprint_id: String, layout: BuildingLayout) -> void:
	if _visual_prototypes.has(blueprint_id):
		return
	_bake_prototype(blueprint_id, layout)


static func _bake_prototype(blueprint_id: String, layout: BuildingLayout) -> void:
	## COLLISION ON, always, whatever the caller asked for: this is where the
	## colliders are harvested from, and a prototype baked without them would
	## have to be re-baked the first time anyone asked for a solid building.
	var baked := BuildingFitout.build(layout, true)
	## Doors come out FIRST — their subtrees must not reach `VisualFlatten`, or
	## the leaf would be drawn twice: once flat and once under the openable copy.
	_door_prototypes[blueprint_id] = _harvest_doors(baked)
	_collider_prototypes[blueprint_id] = _harvest_colliders(baked)
	var root := Node3D.new()
	root.name = "BuildingPrototype"
	VisualFlatten.flatten(baked, root)
	baked.free()
	_visual_prototypes[blueprint_id] = root


## Every `CollisionShape3D` the fit-out put on its `Collision` body, as
## `{shape, transform, name}`. The `Shape3D` RESOURCE is kept, not copied: two
## bricks of the same size share one `BoxShape3D`, so `PhysicsServer3D` holds a
## handful of shape RIDs for hundreds of boxes, and every stamped instance
## shares those same RIDs again. Measured on the warehouse: 577 boxes, **4**
## distinct sizes.
static func _harvest_colliders(baked: Node3D) -> Array:
	var out: Array = []
	var body := baked.get_node_or_null("Collision") as StaticBody3D
	if body == null:
		return out
	## Deduplicates by value so identical boxes converge on one resource. The
	## fit-out makes a fresh `BoxShape3D` per brick; the cache does not have to
	## keep 577 of them alive.
	var by_size: Dictionary = {}
	for child in body.get_children():
		var col := child as CollisionShape3D
		if col == null or col.shape == null:
			continue
		var shape := col.shape
		if shape is BoxShape3D:
			var key := str((shape as BoxShape3D).size)
			if by_size.has(key):
				shape = by_size[key] as Shape3D
			else:
				by_size[key] = shape
		out.append({"shape": shape, "transform": col.transform, "name": col.name})
	return out


## ⚠ NOT IN A TREE WHEN THIS RUNS, AND THAT IS THE PERFORMANCE FIX.
## See the header: shapes added to a body that is in no physics space cost
## nothing to add; in a space each add rebuilds the whole compound.
static func _stamp_collision(body: StaticBody3D, blueprint_id: String) -> void:
	for entry_variant in (_collider_prototypes.get(blueprint_id, []) as Array):
		var entry := entry_variant as Dictionary
		var col := CollisionShape3D.new()
		col.name = str(entry["name"])
		col.shape = entry["shape"] as Shape3D
		col.transform = entry["transform"] as Transform3D
		body.add_child(col)


## Lifts each doorway's visual subtree OUT of the baked tree and returns it as a
## prototype, with the arguments `BuildingFitout` configured its `BrickDoor`
## with.
##
## WHY A DOORWAY CANNOT BE FLATTENED. `BrickDoor._ready` resolves
## `parent/DoorHinge/DoorLeaf` by node path and hangs its interact areas and its
## closed-leaf collider off them, then swings the hinge. `VisualFlatten` returns
## childless visuals at accumulated transforms — correct for a wall, and it
## destroys exactly the structure a door is. So the door brick keeps its shape
## and is `duplicate()`d per instance, which still SHARES its `Mesh` and
## `Material` resources (measured in `visual_flatten.gd`'s header), so the cache
## is still a cache. It costs 72 of the warehouse's 717 meshes being copied as
## nodes rather than stamped flat, for two doors that open.
##
## The prototype's own `BrickDoor` is freed rather than duplicated: it never
## entered a tree, so it never ran `_ready`, and its configuration lives in
## `var`s that `duplicate()` would not carry anyway. A per-instance door is a
## per-instance node.
static func _harvest_doors(baked: Node3D) -> Array:
	var doors: Array = []
	_find_doors(baked, doors)
	var out: Array = []
	for door_variant in doors:
		var door := door_variant as BrickDoor
		var brick := door.get_parent() as Node3D
		if brick == null:
			continue
		var xform := brick.transform
		var walk := brick.get_parent() as Node3D
		while walk != null and walk != baked:
			xform = walk.transform * xform
			walk = walk.get_parent() as Node3D
		out.append({
			"node": brick,
			"transform": xform,
			"yaw_deg": float(door.get_meta("brick_door_yaw_deg", 0.0)),
			"leaf_size": door.get_meta("brick_door_leaf_size", Vector3(1.8, 2.8, 0.1)) as Vector3,
		})
		brick.remove_child(door)
		door.free()
		var brick_parent := brick.get_parent()
		if brick_parent != null:
			brick_parent.remove_child(brick)
	return out


static func _stamp_doors(visual: Node3D, blueprint_id: String) -> void:
	for entry_variant in (_door_prototypes.get(blueprint_id, []) as Array):
		var entry := entry_variant as Dictionary
		var proto := entry["node"] as Node3D
		if proto == null or not is_instance_valid(proto):
			continue
		var brick := proto.duplicate() as Node3D
		brick.transform = entry["transform"] as Transform3D
		visual.add_child(brick)
		var door := BrickDoor.new()
		door.name = "BrickDoor"
		door.configure(null, Vector3.ZERO, float(entry["yaw_deg"]), entry["leaf_size"] as Vector3)
		brick.add_child(door)


static func _find_doors(node: Node, out: Array) -> void:
	if node is BrickDoor:
		out.append(node)
	for child in node.get_children():
		_find_doors(child, out)
