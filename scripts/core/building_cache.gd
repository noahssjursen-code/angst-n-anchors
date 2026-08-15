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
	return _stamp_node(proto)


static func _bake_prototype(blueprint_id: String, layout: BuildingLayout) -> void:
	var baked := BuildingFitout.build(layout, false)
	var root := Node3D.new()
	root.name = "BuildingPrototype"
	_flatten_visuals(baked, root, Transform3D.IDENTITY)
	baked.free()
	_visual_prototypes[blueprint_id] = root
	_footprint_cache[blueprint_id] = _measure_footprint(layout)


## Flattens the fit-out tree into a list of childless `VisualInstance3D` at
## world-relative transforms.
##
## ⚠ THIS USED TO REBUILD `MeshInstance3D` AND ONLY `MeshInstance3D`, and it lost
## two different things by doing so (measured 2026-08-15, `tests/_visual_survey.gd`):
##
##  1. EVERY NON-MESH VISUAL. A `Label3D` is a `Node3D`, so it was recursed into,
##     contributed no mesh children and vanished without a word — the warehouse's
##     "WAREHOUSE" sign was drawn on no building the game stamps. Four bricks emit
##     a `Label3D` (`deck_text`, `wall_text_sm`, `wall_text`, `wall_text_lg`) and
##     `BuildingFitout._add_brick_light` hangs an `OmniLight3D` off all eight
##     `light`-tagged bricks; all twelve were lost the same way. The root's
##     `BuildingLighting` was left driving nothing.
##  2. EVERY MESH PARENTED TO A MESH. The old code copied a `MeshInstance3D` and
##     did NOT recurse into it, so a mesh nested under another mesh was dropped
##     too — the claim "reconstructs MeshInstance3D" was not even true of meshes.
##     `BrickCatalog._add_door_face` parents 9 panel/stile/rail/handle meshes to
##     the `DoorLeaf` mesh, twice per leaf: **72 of the warehouse's 717 meshes**,
##     i.e. both cargo doors' entire panelling, leaving two blank slabs.
##
## THE LINE, and it is drawn at `VisualInstance3D` rather than at `Node3D`.
## Everything in Godot that puts pixels on the screen is a `VisualInstance3D` —
## meshes, labels, sprites, particles, decals, lights. Everything else in a
## fit-out tree is either a transform holder (`Node3D`, `Marker3D`) whose
## contribution IS the accumulated transform, or a behaviour node that a
## flatten-and-stamp cache cannot carry at all. Those are dropped ON PURPOSE, and
## they are named here rather than falling through a filter in silence:
##
##  - `BuildingLighting` — a controller, not a visual (it is a `Node`, so it
##    never passed the `Node3D` test either). `instance()` adds a FRESH one at
##    the stamped root, where it walks that instance's own lights; one carried
##    into the prototype would be copied per building and aimed at the prototype.
##  - `BrickDoor` — behaviour with no geometry of its own; its leaf and jamb
##    meshes are the tree it hangs beside, and they are kept. A stamped building
##    therefore has door geometry and no openable door. That loss is asserted
##    (red) by `building_interior_test`'s "every doorway carries a door a player
##    can open", and closing it means per-instance construction, not a filter.
##  - `Marker3D` anchors (`HelmEye`, `Emitter`) — attachment points for the ship
##    lighting path, which land buildings do not run.
static func _flatten_visuals(src: Node, dst_root: Node3D, parent_xform: Transform3D) -> void:
	for child in src.get_children():
		if child.name == "BuildingLighting":
			continue
		if not (child is Node3D):
			continue
		var node_3d := child as Node3D
		var xform := parent_xform * node_3d.transform
		if child is VisualInstance3D:
			var copy := _copy_visual(child as VisualInstance3D)
			copy.transform = xform
			dst_root.add_child(copy)
		## ALWAYS recurse, including through a visual: `_copy_visual` returns a
		## CHILDLESS copy, so the subtree is reached here exactly once whatever
		## its parent was. The old code recursed only past non-meshes, which is
		## how the door panels went missing.
		_flatten_visuals(child, dst_root, xform)


static func _stamp_node(prototype: Node3D) -> Node3D:
	## The prototype is flat and holds childless `VisualInstance3D` only, so this
	## is one pass with no recursion. The COPY ITSELF is `_copy_visual`, shared
	## with the bake above — the two used to carry the same five-field
	## `MeshInstance3D` copy written out twice, which is two places to forget the
	## same property in (REALITY.md §3b: delete the second derivation).
	var root := Node3D.new()
	for child in prototype.get_children():
		if not (child is VisualInstance3D):
			continue
		var src := child as VisualInstance3D
		var copy := _copy_visual(src)
		copy.transform = src.transform
		root.add_child(copy)
	return root


## One derivation for "copy this visual, share its resources, drop its children".
## The caller sets the transform, because the bake flattens to world-relative and
## the stamp copies verbatim.
##
## Meshes get an explicit field copy rather than `duplicate()` because this runs
## 717 times per stamped warehouse and `duplicate()` walks every property, signal
## and group; the resource-sharing that `port_perf_cache_test` asserts is what
## makes the cache a cache, and an explicit assignment shares by reference. Both
## paths carry metadata: `BuildingLighting` finds a lit fixture by
## `building_light_base_energy` on the light and dims its lens through
## `building_lens_base_emission` on the mesh, and a stamped building that has
## lost those metas has fixtures the day/night controller cannot see.
static func _copy_visual(src: VisualInstance3D) -> VisualInstance3D:
	if src is MeshInstance3D:
		var src_mi := src as MeshInstance3D
		var mi := MeshInstance3D.new()
		mi.name = src_mi.name
		mi.mesh = src_mi.mesh
		mi.material_override = src_mi.material_override
		mi.cast_shadow = src_mi.cast_shadow
		mi.gi_mode = src_mi.gi_mode
		_copy_metadata(src_mi, mi)
		return mi
	## Everything else that draws — `Label3D`, `Light3D`, `Sprite3D`, particles —
	## is duplicated rather than hand-copied field by field. A `Label3D` alone
	## carries text, font, font_size, pixel_size, modulate, outline colour and
	## size, both alignments, billboard mode, shaded, double_sided and
	## render_priority; writing that list out is a second derivation to forget a
	## property in (REALITY.md §3b). Measured in 4.6 (`tests/_visual_survey.gd`,
	## section D): `duplicate()` SHARES Resource references — the `Font` here, and
	## `Mesh` / `Material` elsewhere — and carries metadata, so it does not defeat
	## the cache. (`model_cache.gd` claims the opposite in a comment; it is wrong.)
	var copy := src.duplicate() as VisualInstance3D
	## Childless, so the caller's recursion owns the subtree exactly once.
	for child in copy.get_children():
		copy.remove_child(child)
		child.free()
	return copy


static func _copy_metadata(src: Node, dst: Node) -> void:
	for key in src.get_meta_list():
		dst.set_meta(key, src.get_meta(key))


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
