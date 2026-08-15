class_name BuildingCache
extends RefCounted

## Bakes voxel blueprint visuals once and stamps shared-mesh copies.
## Collision is a single box per instance derived from the layout grid bounds.

static var _visual_prototypes: Dictionary = {}  ## blueprint_id -> Node3D
static var _footprint_cache: Dictionary = {}  ## blueprint_id -> {size, center}


static func clear() -> void:
	for key in _visual_prototypes.keys():
		var proto: Node3D = _visual_prototypes[key] as Node3D
		if proto != null and is_instance_valid(proto):
			proto.free()
	_visual_prototypes.clear()
	_footprint_cache.clear()


static func instance(
		layout: BuildingLayout,
		collision_enabled: bool = true,
) -> Node3D:
	if layout == null:
		return Node3D.new()
	var blueprint_id := layout.blueprint_id.strip_edges()
	if blueprint_id.is_empty():
		return BuildingFitout.build(layout, collision_enabled)

	var root := Node3D.new()
	root.name = BuildingFitout.ROOT_NAME
	root.set_meta("building_blueprint_id", blueprint_id)

	var visual := _stamp_visual(blueprint_id, layout)
	visual.name = "Visual"
	root.add_child(visual)

	var lighting := BuildingLighting.new()
	lighting.name = "BuildingLighting"
	root.add_child(lighting)

	if collision_enabled:
		var body := StaticBody3D.new()
		body.name = "Collision"
		root.add_child(body)
		_add_footprint_collision(body, blueprint_id, layout)

	return root


static func _stamp_visual(blueprint_id: String, layout: BuildingLayout) -> Node3D:
	if not _visual_prototypes.has(blueprint_id):
		_bake_prototype(blueprint_id, layout)
	var proto: Node3D = _visual_prototypes[blueprint_id] as Node3D
	return VisualFlatten.stamp(proto)


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
##  - `BrickDoor` — behaviour with no geometry of its own; its leaf and jamb
##    meshes are the tree it hangs beside, and they are kept. A stamped building
##    therefore has door geometry and no openable door. That loss is asserted
##    (red) by `building_interior_test`'s "every doorway carries a door a player
##    can open", and closing it means per-instance construction, not a filter.
##  - `Marker3D` anchors (`HelmEye`, `Emitter`) — attachment points for the ship
##    lighting path, which land buildings do not run.
static func _bake_prototype(blueprint_id: String, layout: BuildingLayout) -> void:
	var baked := BuildingFitout.build(layout, false)
	var root := Node3D.new()
	root.name = "BuildingPrototype"
	VisualFlatten.flatten(baked, root)
	baked.free()
	_visual_prototypes[blueprint_id] = root
	_footprint_cache[blueprint_id] = _measure_footprint(layout)


static func _measure_footprint(layout: BuildingLayout) -> Dictionary:
	var grid := layout.grid()
	var min_cell := Vector3i(999999, 999999, 999999)
	var max_cell := Vector3i(-999999, -999999, -999999)
	var found := false
	for item in layout.iter_primary_cells():
		if BuildingLayout.entry_is_surface_only(item):
			continue
		found = true
		var cell := item["cell"] as Vector3i
		min_cell = Vector3i(mini(min_cell.x, cell.x), mini(min_cell.y, cell.y), mini(min_cell.z, cell.z))
		max_cell = Vector3i(maxi(max_cell.x, cell.x), maxi(max_cell.y, cell.y), maxi(max_cell.z, cell.z))
	if not found:
		return {"size": Vector3(8.0, 6.0, 8.0), "center": Vector3.ZERO}
	var min_p := grid.cell_center_local(min_cell)
	var max_p := grid.cell_center_local(max_cell)
	var size := max_p - min_p + Vector3.ONE
	return {"size": size, "center": (min_p + max_p) * 0.5}


static func _add_footprint_collision(body: StaticBody3D, blueprint_id: String, layout: BuildingLayout) -> void:
	if not _footprint_cache.has(blueprint_id):
		_footprint_cache[blueprint_id] = _measure_footprint(layout)
	var fp: Dictionary = _footprint_cache[blueprint_id]
	var size: Vector3 = fp.get("size", Vector3(8.0, 6.0, 8.0))
	var center: Vector3 = fp.get("center", Vector3.ZERO)
	var col := CollisionShape3D.new()
	col.name = "Footprint"
	var shape := BoxShape3D.new()
	shape.size = Vector3(maxf(size.x, 1.0), maxf(size.y, 2.5), maxf(size.z, 1.0))
	col.shape = shape
	col.position = center + Vector3(0.0, shape.size.y * 0.5 - 0.5, 0.0)
	body.add_child(col)
