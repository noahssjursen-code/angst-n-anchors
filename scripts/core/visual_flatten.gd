@tool
class_name VisualFlatten
extends RefCounted

## ONE flatten-and-stamp for every prototype cache in this project.
##
## A prototype cache builds an expensive tree once, FLATTENS it to a list of
## childless visuals at root-relative transforms, and then STAMPS cheap copies
## that share the baked `Mesh` / `Material` resources. `BuildingCache`,
## `ModelCache` and `LandDecorCache` all do exactly that, and until today each
## carried its own copy of the algorithm — three derivations of one thing, which
## is REALITY.md §3b at file scale rather than at function scale.
##
## ── WHY THAT MATTERED, MEASURED ─────────────────────────────────────────────
## The three copies were the same code and they were all WRONG the same way:
## each rebuilt `MeshInstance3D` and only that, and each recursed only PAST a
## mesh rather than through it. On `BuildingCache`'s inputs that cost, per
## stamped warehouse, one `Label3D` (the "WAREHOUSE" sign), eight `OmniLight3D`
## across the light bricks, the `building_lens_base_emission` metadata that lets
## `BuildingLighting` dim a lens, and **72 of 717 meshes** — both cargo doors'
## entire panelling, because `BrickCatalog._add_door_face` parents nine meshes to
## the `DoorLeaf` MESH. That was fixed in `BuildingCache` alone (42eb3d0); this
## file is where the fix stopped being a fix to one cache.
##
## ── WHAT THE OTHER TWO ACTUALLY LOST — NOTHING, AND SAY SO ──────────────────
## Surveyed before porting anything (`tests/_cache_survey.gd`, 2026-08-15).
## Producer census against stamped census, per class, over every model document
## `ModelCache` is asked for in production plus the two it is asked for in
## showcases, and over all eight `LandDecorCache` variants:
##
##     foghorn_building      MeshInstance3D  9 ->  9    nested-under-visual 0
##     lighthouse_building   MeshInstance3D  4 ->  4    nested-under-visual 0
##     container_cube        MeshInstance3D  1 ->  1    nested-under-visual 0
##     docking_bollard       MeshInstance3D  3 ->  3    nested-under-visual 0
##     fuel_station          MeshInstance3D  6 ->  6    nested-under-visual 0
##     bulk_crane            MeshInstance3D  3 ->  3    nested-under-visual 0
##     provision_crane       MeshInstance3D  8 ->  8    nested-under-visual 0
##     npc_character_study   MeshInstance3D 22 -> 22    nested-under-visual 0
##     house variants 0..7   MeshInstance3D  5 ->  5    nested-under-visual 0
##
## **Zero loss in either, on every input.** Not luck, and not the same claim in
## both cases:
##
##  - `ModelAssembler` can only emit `MeshTransformer` and nested
##    `ModelAssembler`, both plain `Node3D`, and a `MeshTransformer` hangs its
##    one `MeshInstance3D` off ITSELF, never off another mesh. So the shapes the
##    old filter dropped were not merely absent from today's data — that
##    producer cannot express them. Max visual nesting depth measured 1 on all
##    eight documents.
##  - `LandDecorCache` bakes its prototype fifteen lines above its own stamp:
##    five boxes merged by material into a flat row of `MeshInstance3D`. It has
##    no producer to change under it.
##
## So this is a merge, not a bug fix, in two of the three — and it is worth
## doing precisely because the reason those two were safe was a fact about a
## DIFFERENT file that nothing held in place. `model_cache.gd` stated its filter
## as a design ("MeshInstance3D children only"), which is the sentence that made
## the same drop invisible in buildings for as long as the blueprint existed.
##
## ── THE LINE IS `VisualInstance3D`, NOT `Node3D` ────────────────────────────
## Everything in Godot that puts pixels on the screen is a `VisualInstance3D` —
## meshes, labels, sprites, particles, decals, lights. Everything else in a
## baked tree is either a transform holder (`Node3D`, `Marker3D`) whose entire
## contribution IS the accumulated transform, or a behaviour node that a
## flatten-and-stamp cache cannot carry at all. Behaviour nodes are dropped ON
## PURPOSE and are named by their OWN cache at the call site rather than
## filtered out here in silence — see `BuildingCache._bake_prototype`
## (`BuildingLighting`, `BrickDoor`, `Marker3D` anchors). **A silent drop was the
## defect; a named drop is a decision.**
##
## `flatten` takes no flags and neither does `stamp`. That was checked rather
## than assumed: the three caches were compared for anything one must keep or
## drop that another must not, and there is nothing. The only candidate was
## `BuildingCache` skipping the `BuildingLighting` controller `BuildingFitout`
## parents to its root, and that is a `Node`, not a `Node3D` — it never reached
## the class test in the first place. A shared function with three flags would
## be worse than three functions; this one has none.


## Walks `src` and appends a childless copy of every `VisualInstance3D` it finds
## to `dst_root`, at a transform accumulated from `parent_xform` down.
##
## ALWAYS recurses, including through a visual: `copy_visual` returns a CHILDLESS
## copy, so each subtree is reached here exactly once whatever its parent was.
## Recursing only past non-visuals is how the door panels went missing.
static func flatten(src: Node, dst_root: Node3D, parent_xform: Transform3D = Transform3D.IDENTITY) -> void:
	for child in src.get_children():
		if not (child is Node3D):
			continue
		var node_3d := child as Node3D
		var xform := parent_xform * node_3d.transform
		if child is VisualInstance3D:
			var copy := copy_visual(child as VisualInstance3D)
			copy.transform = xform
			dst_root.add_child(copy)
		flatten(child, dst_root, xform)


## Copies a flattened prototype into a fresh unnamed root. The prototype is flat
## and holds childless `VisualInstance3D` only, so this is one pass with no
## recursion, and the COPY ITSELF is `copy_visual` — shared with `flatten` above,
## because the two used to carry the same five-field `MeshInstance3D` copy
## written out twice in each of three files: six places to forget the same
## property in.
static func stamp(prototype: Node3D) -> Node3D:
	var root := Node3D.new()
	for child in prototype.get_children():
		if not (child is VisualInstance3D):
			continue
		var src := child as VisualInstance3D
		var copy := copy_visual(src)
		copy.transform = src.transform
		root.add_child(copy)
	return root


## One derivation for "copy this visual, share its resources, drop its children".
## The caller sets the transform, because `flatten` flattens to root-relative and
## `stamp` copies verbatim.
##
## Meshes get an explicit field copy rather than `duplicate()`, and the reason is
## COST ONLY — stated that way because it was measured, and because a mutation
## replacing this whole branch with `duplicate()` inside `stamp` passes
## `visual_stamp_cache_test` 104/104. It is not a correctness requirement at the
## stamp layer: `duplicate()` shares the same resources and carries the same
## metadata, and a flattened prototype is childless so there is no subtree to
## copy. What it costs is **3.6×** (`tests/_stamp_cost_probe.gd`, best of 3 × 500
## stamps): a house 0.0435 -> 0.1570 ms, a nine-mesh foghorn 0.0816 -> 0.2934.
## At 717 meshes per stamped warehouse that is the difference between a cache and
## a rebuild. Nothing in the gate holds it — a wall-clock threshold on a llvmpipe
## box fails for the weather — so it is written here instead.
##
## Both paths carry metadata: `BuildingLighting` finds a lit fixture by
## `building_light_base_energy` on the light and dims its lens through
## `building_lens_base_emission` on the mesh, and a stamped building that has
## lost those metas has fixtures the day/night controller cannot see. The
## resource sharing `port_perf_cache_test` asserts is what makes a cache a cache,
## and an explicit assignment shares by reference.
static func copy_visual(src: VisualInstance3D) -> VisualInstance3D:
	if src is MeshInstance3D:
		var src_mi := src as MeshInstance3D
		var mi := MeshInstance3D.new()
		mi.name = src_mi.name
		mi.mesh = src_mi.mesh
		mi.material_override = src_mi.material_override
		mi.cast_shadow = src_mi.cast_shadow
		mi.gi_mode = src_mi.gi_mode
		copy_metadata(src_mi, mi)
		return mi
	## Everything else that draws — `Label3D`, `Light3D`, `Sprite3D`, particles —
	## is duplicated rather than hand-copied field by field. A `Label3D` alone
	## carries text, font, font_size, pixel_size, modulate, outline colour and
	## size, both alignments, billboard mode, shaded, double_sided and
	## render_priority; writing that list out is a second derivation to forget a
	## property in (REALITY.md §3b).
	##
	## `model_cache.gd` justified ITS hand-written stamp with the claim
	## "Node.duplicate deep-copies Resources by default". **Measured false in
	## 4.6**, twice now and independently the second time
	## (`tests/_cache_survey.gd` section C, and asserted in
	## `tests/visual_stamp_cache_test.gd` so it stops being a comment):
	##
	##     MeshInstance3D.duplicate()  mesh SHARED=true  material SHARED=true
	##                                 meta carried=true  layers carried
	##     Label3D.duplicate()         font SHARED=true   meta carried=true
	##     OmniLight3D.duplicate()     meta carried=true
	##     duplicate() also carries CHILDREN — which is why they come off below.
	##
	## `duplicate()` shares Resource references, so it does not defeat the cache.
	## What it does do is copy the subtree, and the caller's recursion owns that.
	var copy := src.duplicate() as VisualInstance3D
	for child in copy.get_children():
		copy.remove_child(child)
		child.free()
	return copy


static func copy_metadata(src: Node, dst: Node) -> void:
	for key in src.get_meta_list():
		dst.set_meta(key, src.get_meta(key))
