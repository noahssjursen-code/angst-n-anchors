extends SceneTree

## LANE A. DOES EVERY VISUAL THE PRODUCER DREW SURVIVE THE STAMP — IN THE TWO
## CACHES THAT WERE NEVER FIXED, AND IN THE ONE IMPLEMENTATION ALL THREE NOW USE?
##
## ── WHY THIS FILE EXISTS ────────────────────────────────────────────────────
## `BuildingCache` carried a flatten/stamp pair that rebuilt `MeshInstance3D` and
## only that, and recursed only PAST a mesh rather than through it. Per stamped
## warehouse it lost the `Label3D` sign, an `OmniLight3D` per light brick, the
## `building_lens_base_emission` metadata `BuildingLighting` dims a lens through,
## and 72 of 717 meshes. It was fixed in `42eb3d0` and is guarded by
## `tests/building_cache_visual_test.gd`.
##
## `scripts/core/model_cache.gd` and `scripts/port/land_decor_cache.gd` carried
## the same pair, essentially byte-for-byte, and NOTHING was pointed at either
## (REALITY.md §4b — not a bad check, NO check). Both are now `VisualFlatten`,
## and this file holds all three to the property.
##
## ── WHAT THE SURVEY MEASURED, BEFORE ANYTHING WAS CHANGED (2026-08-15) ──────
## `tests/_cache_survey.gd`, producer census against stamped census, per class:
##
##     ModelCache        foghorn 9->9  lighthouse 4->4  container 1->1
##                       bollard 3->3  fuel_station 6->6  bulk_crane 3->3
##                       provision_crane 8->8  npc_character_study 22->22
##     LandDecorCache    variants 0..7, 5->5 each
##
## **Zero loss in either.** The honest outcome for these two was "this one is
## fine, here is the measurement" — no defect was manufactured to match the
## buildings template. What they were is LATENT, and latent on a fact about a
## different file: `ModelAssembler` emits only `MeshTransformer` and nested
## `ModelAssembler` (both plain `Node3D`) and hangs each `MeshInstance3D` off a
## `MeshTransformer`, never off another mesh, so it cannot express the shapes the
## old filter dropped. Nothing held that in place. Section 2 does now.
##
## ── SO WHAT THE CHECKS BELOW ARE FOR ────────────────────────────────────────
## Sections 2 and 3 are regression guards over real inputs, and on their own they
## would be weak: their fixtures contain no non-mesh visual and no nested mesh,
## so a mesh-only filter passes them. Section 1 is where the property is stated
## against a fixture that DOES carry every shape the defect dropped, and it
## exercises `VisualFlatten` — the code all three caches run — not a tree
## assembled one layer above it. The two together are the claim; either alone is
## not. Section 1's fixture says so itself, in checks, rather than in this note.
##
## ── MUTATION VERIFICATION ───────────────────────────────────────────────────
## Control **PASS (104)**. Ten mutations, each applied to `VisualFlatten` and run
## through this same file by the same invocation. Each patch was applied by exact
## text match with an abort on no-match, because **a mutation that silently fails
## to apply reports as a PASS and is indistinguishable from a blind check** — the
## first pass here had two "passes" that had to be re-checked for exactly that:
##
##  | mutation                                             | result   |
##  |------------------------------------------------------|----------|
##  | `flatten` recurses only PAST a visual (the old code)  | 5/102    |
##  | `flatten`/`stamp` filter on `MeshInstance3D` (old)    | 8/90     |
##  | `copy_metadata` emptied                               | 2/104    |
##  | `mi.gi_mode` not copied                               | 2/104    |
##  | transform not accumulated down the chain              | 2/104    |
##  | `mi.name` not copied                                  | 3/89     |
##  | `stamp` copies via plain `duplicate()`                | **PASS** |
##  | filter loosened to keep every node                    | 4/104    |
##  | `copy_visual` keeps the duplicated children           | 2/104    |
##  | `flatten` does not recurse at all                     | 17/87    |
##  | `mi.mesh = src.mesh.duplicate()` (breaks sharing)     | 3/104    |
##
## TWO OF THOSE PASSED FIRST TIME AND BOTH ARE FINDINGS, NOT RELIEFS
## (REALITY.md §8):
##
##  - **`copy_visual` keeping its duplicated children was green**, because the
##    only visual with children in the fixture was the outer MESH — and a mesh
##    takes `copy_visual`'s explicit-field branch, which never calls
##    `duplicate()`. The `duplicate()` branch's child strip had NOTHING pointed
##    at it. Fixed by giving the `Label3D` a backing mesh; it now reddens 2/104,
##    on the childless check and on an OVER-count of meshes.
##  - **`stamp` copying via plain `duplicate()` still passes, and that is
##    correct behaviour, not a hole.** `duplicate()` shares `Mesh`, `Material`
##    and `Font` by reference and carries metadata, and a flattened prototype is
##    childless, so at the STAMP layer the two are behaviourally identical. The
##    explicit field copy is a COST decision and nothing here holds it — measured
##    rather than assumed (`tests/_stamp_cost_probe.gd`, best of 3 × 500):
##    house 0.0435 -> 0.1570 ms/stamp, foghorn 0.0816 -> 0.2934, i.e. **3.6×**.
##    Recorded rather than asserted: a wall-clock threshold on a llvmpipe box is
##    a test that fails for the weather.
##
## A twelfth mutation was run against `building_cache_visual_test` instead:
## deleting `BuildingCache`'s explicit `BuildingLighting` skip is **PASS (34) ->
## PASS (34)**, which is why that line is gone (see `building_cache.gd`).

const TestReport := preload("res://tests/support/test_report.gd")

## Model documents `ModelCache` is asked for. Discovered by walking the model
## directories rather than listed, so a model added tomorrow is covered without
## editing this file; the two props that live under `meshes/` are named because
## that directory is mostly single-mesh documents `ModelAssembler` never sees.
const MODEL_DIRS := [
	"res://resources/data/models/buildings",
	"res://resources/data/models/cargo",
	"res://resources/data/models/dockyard",
]
const EXTRA_MODELS := [
	"res://resources/data/meshes/docks/docking_bollard.json",
	"res://resources/data/meshes/props/fuel_station.json",
]

var _t: TestReport


func _initialize() -> void:
	_t = TestReport.new("visual_stamp_cache_test")

	_check_flatten_keeps_everything_that_draws()
	_check_shared_stamp()
	_check_duplicate_still_shares_resources()
	_check_model_cache()
	_check_land_decor_cache()

	_t.finish(self)


## ── 1. THE SHARED DERIVATION ────────────────────────────────────────────────
## `VisualFlatten` is the code inside all three caches, so it is what the checks
## point at. The fixture carries, deliberately, every shape the buildings defect
## dropped: a mesh under a mesh, a label under a mesh, a bare label, a light with
## metadata, and two non-visual nodes that must NOT survive.
func _check_flatten_keeps_everything_that_draws() -> void:
	var src := _defect_shaped_tree()

	## Vacuity guards first. "The stamp loses nothing" is free against a tree
	## that draws nothing, and an empty universe is REALITY.md §4's favourite way
	## to report success. These state what the fixture must contain for anything
	## below it to mean something.
	var want := _visual_census(src)
	_t.equal("fixture: three meshes — one under a MESH, one under a LABEL",
		int(want.get("MeshInstance3D", 0)), 3)
	_t.equal("fixture: two labels, one of them parented to a MESH",
		int(want.get("Label3D", 0)), 2)
	_t.equal("fixture: one light", int(want.get("OmniLight3D", 0)), 1)
	_t.equal("fixture: three visuals are nested under another visual",
		_nested_visuals(src), 3)
	_t.equal("fixture: the nesting is two visuals deep, so recursion is exercised",
		_max_visual_depth(src, 0), 2)

	var flat := Node3D.new()
	VisualFlatten.flatten(src, flat)
	var got := _visual_census(flat)

	## THE PROPERTY, per class rather than as a total, so a surplus of one class
	## cannot cancel a loss in another — which is exactly how 72 doorleaf meshes
	## would have hidden behind a healthy total (REALITY.md §4a).
	var keys := want.keys()
	keys.sort()
	for cls in keys:
		_t.equal("flatten keeps every %s (%d of %d)"
			% [str(cls), int(got.get(cls, 0)), int(want[cls])],
			int(got.get(cls, 0)), int(want[cls]))

	## Flat and childless: the contract `stamp` relies on. If `flatten` left a
	## subtree hanging, `stamp`'s single non-recursive pass would drop it and the
	## defect would come back one layer over.
	var childless := true
	var direct := true
	for child in flat.get_children():
		if child.get_child_count() > 0:
			childless = false
		if not (child is VisualInstance3D):
			direct = false
	_t.check("every flattened node is childless", childless)
	_t.check("the flattened root holds visuals and nothing else", direct)
	_t.equal("nothing that draws was left behind (%d nodes)" % flat.get_child_count(),
		flat.get_child_count(), 6)

	## Behaviour and physics nodes are dropped ON PURPOSE. Named, so the drop is
	## a decision rather than a silence — which is the whole distinction the
	## buildings fix turned on.
	_t.equal("the behaviour controller is not carried into the prototype",
		_count_named(flat, "Controller"), 0)
	_t.equal("the collision shape is not carried into the prototype",
		_count_named(flat, "Collider"), 0)

	## The transform is the entire point of flattening: the tree is collapsed and
	## the accumulated pose has to survive it. Asserted on the DEEPEST node, two
	## parents down, because a flatten that forgets to accumulate still gets the
	## shallow ones right.
	var inner := _find_named(flat, "InnerMesh") as Node3D
	if _t.check("the twice-nested mesh survives the flatten", inner != null):
		_t.check("its pose is the accumulated chain, not its own (%s)"
			% str(inner.transform.origin.snapped(Vector3.ONE * 0.0001)),
			inner.transform.origin.distance_to(Vector3(1.0, 2.0, 3.0)) < 0.0001)
	var nested_label := _find_named(flat, "NestedLabel") as Label3D
	if _t.check("the label parented to a MESH survives the flatten",
			nested_label != null):
		_t.check("its pose is the accumulated chain too (%s)"
			% str(nested_label.transform.origin.snapped(Vector3.ONE * 0.0001)),
			nested_label.transform.origin.distance_to(Vector3(1.0, 5.0, 1.0)) < 0.0001)

	## Metadata is how `BuildingLighting` finds a fixture and its lens. A visual
	## that survives without it is present in the tree and invisible to the
	## day/night controller.
	var lamp := _find_named(flat, "Lamp") as OmniLight3D
	if _t.check("the light survives the flatten", lamp != null):
		_t.check("the light keeps the metadata its controller finds it by",
			lamp.has_meta("building_light_base_energy"))
	var src_outer := _find_named(src, "OuterMesh") as MeshInstance3D
	var outer := _find_named(flat, "OuterMesh") as MeshInstance3D
	if _t.check("the outer mesh survives the flatten", outer != null and src_outer != null):
		_t.check("the MESH keeps its metadata too — the half `duplicate()` does not do",
			outer.has_meta("building_lens_base_emission"))
		## ANCHORED ON THE SOURCE, NOT ON THE FLATTENED COPY. Stating a field
		## property as "prototype == stamp" compares two outputs of the SAME copy
		## routine, so a field the routine drops matches itself at the default and
		## the check is green on the bug (REALITY.md §3 — assert against the path
		## that breaks, not the artefact next to it). Found here by mutation:
		## deleting `mi.gi_mode = src_mi.gi_mode` left the prototype-vs-stamp
		## comparison PASSING and was caught only by the guard beside it.
		_t.equal("the flattened mesh keeps the SOURCE's GI mode",
			outer.gi_mode, src_outer.gi_mode)
		_t.not_equal("...and the fixture's GI mode is not the value a dropped field falls back to",
			src_outer.gi_mode, GeometryInstance3D.GI_MODE_STATIC)
		_t.equal("the flattened mesh keeps the SOURCE's shadow setting",
			outer.cast_shadow, src_outer.cast_shadow)
		_t.not_equal("...and the fixture's shadow setting is not the default either",
			src_outer.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_ON)
		_t.check("the flattened mesh SHARES the source's Mesh rather than copying it",
			outer.mesh != null and outer.mesh == src_outer.mesh)
		_t.check("the flattened mesh SHARES the source's Material",
			outer.material_override != null
				and outer.material_override == src_outer.material_override)

	## A `Label3D` carries a dozen properties a hand-written field list drops
	## first; without them the lettering is white-on-pale with no outline, i.e.
	## present in the tree and invisible on the wall.
	var sign_src := _find_named(src, "Sign") as Label3D
	var sign_out := _find_named(flat, "Sign") as Label3D
	if _t.check("the bare label survives the flatten", sign_out != null and sign_src != null):
		_t.equal("the label keeps its text", sign_out.text, sign_src.text)
		_t.equal("the label keeps its paint colour", sign_out.modulate, sign_src.modulate)
		_t.equal("the label keeps the outline that makes it read",
			sign_out.outline_size, sign_src.outline_size)
		_t.equal("the label keeps its outline colour",
			sign_out.outline_modulate, sign_src.outline_modulate)
		_t.check("the label SHARES its font rather than deep-copying it",
			sign_out.font != null and sign_out.font == sign_src.font)

	flat.free()
	src.free()


## ── 2. THE STAMP, AND THAT IT IS STILL A CACHE ──────────────────────────────
## `port_perf_cache_test` asserts resource sharing for `BuildingCache`'s meshes
## and is the reason the copy is an explicit field assignment rather than a
## `duplicate()`. The same claim has to hold for every class, in the shared
## implementation, or the fix that added them would be a per-instance rebuild
## wearing a green sign.
func _check_shared_stamp() -> void:
	var src := _defect_shaped_tree()
	var proto := Node3D.new()
	VisualFlatten.flatten(src, proto)
	var want := _visual_census(proto)

	var a := VisualFlatten.stamp(proto)
	var b := VisualFlatten.stamp(proto)
	var got_a := _visual_census(a)
	var got_b := _visual_census(b)
	var keys := want.keys()
	keys.sort()
	for cls in keys:
		_t.equal("the stamp keeps every %s the prototype held (%d of %d)"
			% [str(cls), int(got_a.get(cls, 0)), int(want[cls])],
			int(got_a.get(cls, 0)), int(want[cls]))
	_t.equal("stamping twice draws the same census", got_b, got_a)

	var p_mesh := _find_named(proto, "OuterMesh") as MeshInstance3D
	var a_mesh := _find_named(a, "OuterMesh") as MeshInstance3D
	var b_mesh := _find_named(b, "OuterMesh") as MeshInstance3D
	if _t.check("the mesh is reachable in both stamps",
			p_mesh != null and a_mesh != null and b_mesh != null):
		_t.check("the two stamps are separate nodes, not one shared node",
			a_mesh != b_mesh)
		## Resource IDENTITY, not equality: a rebuilt mesh with identical
		## vertices compares equal by content and still means the bake ran twice.
		_t.check("both stamps SHARE the prototype's Mesh rather than copying it",
			a_mesh.mesh != null and a_mesh.mesh == p_mesh.mesh
				and b_mesh.mesh == p_mesh.mesh)
		_t.check("both stamps SHARE the prototype's Material",
			a_mesh.material_override != null
				and a_mesh.material_override == p_mesh.material_override)
		_t.check("the stamped mesh keeps its lens metadata",
			a_mesh.has_meta("building_lens_base_emission"))
		## The fixture's own values, restated from nothing: these are the two
		## fields a hand-written mesh copy drops first, and both are set to a
		## NON-default in `_defect_shaped_tree` precisely so that dropping them
		## cannot land on a matching default at both ends (see the note in
		## section 1 — the prototype-vs-stamp form of this check was green under
		## exactly that mutation).
		_t.equal("the stamped mesh keeps the fixture's shadow setting",
			a_mesh.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
		_t.equal("the stamped mesh keeps the fixture's GI mode",
			a_mesh.gi_mode, GeometryInstance3D.GI_MODE_DISABLED)
		_t.check("the stamped mesh stands where the prototype put it",
			a_mesh.transform.origin.distance_to(p_mesh.transform.origin) < 0.0001)

	var p_label := _find_named(proto, "Sign") as Label3D
	var a_label := _find_named(a, "Sign") as Label3D
	var b_label := _find_named(b, "Sign") as Label3D
	if _t.check("the label is reachable in both stamps",
			p_label != null and a_label != null and b_label != null):
		_t.check("the two stamped labels are separate nodes", a_label != b_label)
		_t.check("both stamped labels SHARE the font resource",
			a_label.font != null and a_label.font == p_label.font
				and b_label.font == p_label.font)
		_t.equal("the stamped label keeps its text", a_label.text, p_label.text)
		_t.check("the stamped label stands where the prototype put it",
			a_label.transform.origin.distance_to(p_label.transform.origin) < 0.0001)

	var a_lamp := _find_named(a, "Lamp") as OmniLight3D
	if _t.check("the light is reachable in the stamp", a_lamp != null):
		_t.check("the stamped light keeps the metadata its controller finds it by",
			a_lamp.has_meta("building_light_base_energy"))

	a.free()
	b.free()
	proto.free()
	src.free()


## ── 3. THE PREMISE THE OLD CODE RESTED ON ───────────────────────────────────
## `model_cache.gd:97` justified its hand-written stamp with "Node.duplicate
## deep-copies Resources by default". It is FALSE in 4.6, and the code it
## justified is gone — but a measurement that lives only in a deleted comment is
## a measurement that comes back wrong, so it is asserted here. If a future Godot
## ever does deep-copy, `VisualFlatten.copy_visual`'s non-mesh branch stops being
## a cache and this goes red at the reason rather than at a symptom.
func _check_duplicate_still_shares_resources() -> void:
	var st := SurfaceTool.new()
	st.create_from(BoxMesh.new(), 0)
	var mesh := st.commit()
	var material := StandardMaterial3D.new()

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.set_meta("building_lens_base_emission", 3.5)
	var mi_copy := mi.duplicate() as MeshInstance3D
	_t.check("duplicate() SHARES the Mesh by reference", mi_copy.mesh == mesh)
	_t.check("duplicate() SHARES the Material by reference",
		mi_copy.material_override == material)
	_t.check("duplicate() carries metadata",
		mi_copy.has_meta("building_lens_base_emission"))

	var label := Label3D.new()
	var font := SystemFont.new()
	label.font = font
	label.text = "WAREHOUSE"
	var label_copy := label.duplicate() as Label3D
	_t.check("duplicate() SHARES the Font by reference", label_copy.font == font)
	_t.equal("duplicate() carries the text", label_copy.text, "WAREHOUSE")

	## And the half that makes `copy_visual` strip children: `duplicate()` copies
	## the subtree, so without the strip the flatten would emit each nested
	## visual twice — once inside its parent's copy and once on its own.
	var parent := MeshInstance3D.new()
	var kid := MeshInstance3D.new()
	parent.add_child(kid)
	var parent_copy := parent.duplicate() as MeshInstance3D
	_t.equal("duplicate() also carries CHILDREN, which is why copy_visual strips them",
		parent_copy.get_child_count(), 1)
	var stripped := VisualFlatten.copy_visual(parent)
	_t.equal("copy_visual returns a childless copy", stripped.get_child_count(), 0)

	mi.free()
	mi_copy.free()
	label.free()
	label_copy.free()
	parent.free()
	parent_copy.free()
	stripped.free()


## ── 4. ModelCache, END TO END, OVER EVERY MODEL THE GAME LOADS ──────────────
## Asserts on the tree `ModelCache.instance()` RETURNS, never on the
## `ModelAssembler` above it — that producer is where the buildings defect hid
## twice, and it has always been correct (REALITY.md §3). The assembler appears
## only as the REFERENCE, built with the same two settings `_bake` uses.
func _check_model_cache() -> void:
	var paths := _model_paths()
	_t.check("there are model documents to check (%d)" % paths.size(), paths.size() > 0)

	var total_meshes := 0
	var checked := 0
	for path in paths:
		var assembler := ModelAssembler.new()
		assembler.build_part_colliders = false
		assembler.absolute_scale = 1.0
		assembler.model_data_path = path
		assembler.rebuild()
		var want := _visual_census(assembler)
		var nested := _nested_visuals(assembler)
		assembler.free()

		ModelCache.clear()
		var stamped := ModelCache.instance(path, 1.0)
		var got := _visual_census(stamped)
		stamped.free()
		ModelCache.clear()

		var name := path.get_file()
		## Per-document vacuity guard: a model that draws nothing satisfies
		## "loses nothing" for free.
		var meshes := int(want.get("MeshInstance3D", 0))
		_t.check("%s draws meshes at all (%d)" % [name, meshes], meshes > 0)
		total_meshes += meshes
		checked += 1

		var keys := want.keys()
		keys.sort()
		for cls in keys:
			_t.equal("%s: the stamp keeps every %s (%d of %d)"
				% [name, str(cls), int(got.get(cls, 0)), int(want[cls])],
				int(got.get(cls, 0)), int(want[cls]))
		if nested > 0:
			_t.equal("%s: the %d visual(s) nested under a visual survive"
				% [name, nested], _nested_visuals(stamped), 0)

	_t.check("the model sweep drew something across %d documents (%d meshes)"
		% [checked, total_meshes], total_meshes > 0)

	## THE PREMISE, ASSERTED. `ModelCache`'s old mesh-only filter was harmless
	## only because `ModelAssembler` cannot emit a non-mesh visual or a mesh
	## under a mesh. That was a fact about a DIFFERENT file with nothing holding
	## it, and it is the fact that made "this cache is fine" true. It is stated
	## here so that the day somebody adds a `Label3D` or a light part type, the
	## gate says so at the seam instead of a sign going quietly missing.
	##
	## It is not a REQUIREMENT that models stay flat — `VisualFlatten` handles
	## both shapes now, which is the point of the merge. This check is a
	## tripwire on the survey's own assumption (REALITY.md §4d).
	var deepest := 0
	var non_mesh := 0
	for path in paths:
		var assembler := ModelAssembler.new()
		assembler.build_part_colliders = false
		assembler.model_data_path = path
		assembler.rebuild()
		deepest = maxi(deepest, _max_visual_depth(assembler, 0))
		for cls in _visual_census(assembler):
			if cls != "MeshInstance3D":
				non_mesh += 1
		assembler.free()
	_t.check("survey premise: no ModelAssembler document nests a visual under a visual (depth %d)"
		% deepest, deepest <= 1)
	_t.check("survey premise: no ModelAssembler document emits a non-mesh visual (%d)"
		% non_mesh, non_mesh == 0)


## ── 5. LandDecorCache, END TO END, EVERY VARIANT ────────────────────────────
## Asserts on the tree `house_instance()` RETURNS against the prototype the cache
## actually stamps from — `_house_prototypes[variant]`, not a fresh `_bake_house`
## call. That distinction bit the survey: comparing a stamp against a re-bake
## reports the meshes as UNSHARED, because they are two different bakes. The
## instrument, before the subject (REALITY.md §8).
func _check_land_decor_cache() -> void:
	LandDecorCache.clear()
	LandDecorCache._ensure_baked()
	_t.equal("the decor cache bakes every variant",
		LandDecorCache._house_prototypes.size(), LandDecorCache.VARIANT_COUNT)

	var total := 0
	for variant in range(LandDecorCache.VARIANT_COUNT):
		var proto: Node3D = LandDecorCache._house_prototypes[variant] as Node3D
		var want := _visual_census(proto)
		var meshes := int(want.get("MeshInstance3D", 0))
		_t.check("house variant %d draws meshes at all (%d)" % [variant, meshes], meshes > 0)
		total += meshes

		var stamped := LandDecorCache.house_instance(variant, 0.0, 0.0)
		var got := _visual_census(stamped)
		var keys := want.keys()
		keys.sort()
		for cls in keys:
			_t.equal("house variant %d: the stamp keeps every %s (%d of %d)"
				% [variant, str(cls), int(got.get(cls, 0)), int(want[cls])],
				int(got.get(cls, 0)), int(want[cls]))
		stamped.free()
	_t.check("the house sweep drew something (%d meshes)" % total, total > 0)

	## Still a cache. `ImpostorWarmup` bakes all eight variants at boot and
	## `PortLayoutGraphVisualizer` places a house per village cell, so a stamp
	## that rebuilt its meshes would be a per-house bake nothing would notice.
	var a := LandDecorCache.house_instance(3, 0.0, 0.0)
	var b := LandDecorCache.house_instance(3, 0.0, 0.0)
	var shared := 0
	var pairs := mini(a.get_child_count(), b.get_child_count())
	for i in range(pairs):
		var ma := a.get_child(i) as MeshInstance3D
		var mb := b.get_child(i) as MeshInstance3D
		if ma != null and mb != null and ma.mesh != null and ma.mesh == mb.mesh:
			shared += 1
	_t.check("two house stamps have the same shape (%d / %d)"
		% [a.get_child_count(), b.get_child_count()],
		pairs > 0 and a.get_child_count() == b.get_child_count())
	_t.equal("the second house stamp SHARES the baked meshes (%d of %d)" % [shared, pairs],
		shared, pairs)
	_t.check("the two stamps are separate nodes", a.get_child(0) != b.get_child(0))
	a.free()
	b.free()

	## Per-stamp cost, printed as evidence rather than asserted as a bound: this
	## cache stamps per house, not per blueprint, so the buildings trade (+11.2%
	## nodes for door panelling that should always have been there) is not
	## automatically the right trade here. Measured both sides of the change.
	var t0 := Time.get_ticks_usec()
	for i in range(200):
		var h := LandDecorCache.house_instance(3, 0.0, 0.0)
		h.free()
	var per_stamp := float(Time.get_ticks_usec() - t0) / 200.0
	print("  COST  LandDecorCache: %.4f ms/stamp over 200 stamps" % (per_stamp / 1000.0))

	ModelCache.clear()
	var m0 := Time.get_ticks_usec()
	for i in range(200):
		var n := ModelCache.instance("res://resources/data/models/buildings/foghorn_building.json", 1.0)
		n.free()
	var per_model := float(Time.get_ticks_usec() - m0) / 200.0
	print("  COST  ModelCache (foghorn, 9 meshes): %.4f ms/stamp over 200 stamps"
		% (per_model / 1000.0))
	ModelCache.clear()
	LandDecorCache.clear()


## ── FIXTURE ─────────────────────────────────────────────────────────────────
## Every shape the buildings defect dropped, in one tree, plus two nodes that
## must not survive. Built by hand because no producer in the project emits all
## of them — `BuildingFitout` is the closest and it is `building_cache_visual_test`'s
## subject, not this file's.
func _defect_shaped_tree() -> Node3D:
	var st := SurfaceTool.new()
	st.create_from(BoxMesh.new(), 0)
	var mesh := st.commit()
	var material := StandardMaterial3D.new()

	var root := Node3D.new()
	root.name = "Source"

	var holder := Node3D.new()
	holder.name = "Holder"
	holder.transform.origin = Vector3(1.0, 0.0, 0.0)
	root.add_child(holder)

	var outer := MeshInstance3D.new()
	outer.name = "OuterMesh"
	outer.mesh = mesh
	outer.material_override = material
	outer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	## Deliberately NOT the default — see the gi_mode note in `_check_shared_stamp`.
	outer.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	outer.set_meta("building_lens_base_emission", 3.5)
	outer.transform.origin = Vector3(0.0, 2.0, 0.0)
	holder.add_child(outer)

	## A mesh parented to a MESH — 72 of the warehouse's 717 were exactly this.
	var inner := MeshInstance3D.new()
	inner.name = "InnerMesh"
	inner.mesh = mesh
	inner.material_override = material
	inner.transform.origin = Vector3(0.0, 0.0, 3.0)
	outer.add_child(inner)

	## And a NON-mesh visual parented to a mesh, which is both defects at once.
	var nested_label := Label3D.new()
	nested_label.name = "NestedLabel"
	nested_label.text = "DOOR"
	nested_label.transform.origin = Vector3(0.0, 3.0, 1.0)
	outer.add_child(nested_label)

	var sign := Label3D.new()
	sign.name = "Sign"
	sign.text = "WAREHOUSE"
	sign.font = SystemFont.new()
	sign.modulate = Color(0.9, 0.85, 0.7)
	sign.outline_size = 14
	sign.outline_modulate = Color(0.05, 0.05, 0.05)
	sign.transform.origin = Vector3(4.0, 5.0, 6.0)
	root.add_child(sign)

	## A mesh under a NON-mesh visual. Present because without it the check
	## "every flattened node is childless" could not go red: the only visual with
	## children was the outer MESH, which takes `copy_visual`'s explicit-field
	## branch and never calls `duplicate()` at all — so deleting the child strip
	## from the `duplicate()` branch was GREEN on the first attempt. A mutation
	## that passes is a blind check, not a safe one (REALITY.md §8). `Label3D`
	## backing plates are exactly this shape in `BrickCatalog`.
	var backing := MeshInstance3D.new()
	backing.name = "SignBacking"
	backing.mesh = mesh
	backing.material_override = material
	backing.transform.origin = Vector3(0.0, 0.0, -0.1)
	sign.add_child(backing)

	var lamp := OmniLight3D.new()
	lamp.name = "Lamp"
	lamp.set_meta("building_light_base_energy", 2.0)
	root.add_child(lamp)

	## Must NOT survive: behaviour, and physics.
	var controller := Node.new()
	controller.name = "Controller"
	root.add_child(controller)
	var collider := CollisionShape3D.new()
	collider.name = "Collider"
	root.add_child(collider)

	return root


func _model_paths() -> PackedStringArray:
	var out: PackedStringArray = []
	for dir_path in MODEL_DIRS:
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		for file_name in dir.get_files():
			if file_name.ends_with(".json"):
				out.append(dir_path.path_join(file_name))
	for extra in EXTRA_MODELS:
		if FileAccess.file_exists(extra):
			out.append(extra)
	out.sort()
	return out


## ── INSTRUMENTS ─────────────────────────────────────────────────────────────
## Counts things that DRAW. `VisualInstance3D` is the engine's own line for that
## and it is the line `VisualFlatten` draws.
func _visual_census(node: Node, out: Dictionary = {}) -> Dictionary:
	for child in node.get_children():
		if child is VisualInstance3D:
			var cls := child.get_class()
			out[cls] = int(out.get(cls, 0)) + 1
		_visual_census(child, out)
	return out


## Visuals that have a `VisualInstance3D` ancestor — the meshes the buildings
## defect dropped, counted directly rather than inferred from a total.
func _nested_visuals(root: Node, under_visual: bool = false, count: int = 0) -> int:
	for child in root.get_children():
		var is_vis := child is VisualInstance3D
		if is_vis and under_visual:
			count += 1
		count = _nested_visuals(child, under_visual or is_vis, count)
	return count


func _max_visual_depth(root: Node, depth: int) -> int:
	var best := depth
	for child in root.get_children():
		var d := depth + (1 if child is VisualInstance3D else 0)
		best = maxi(best, _max_visual_depth(child, d))
	return best


func _find_named(root: Node, node_name: String) -> Node:
	for child in root.get_children():
		if child.name == node_name:
			return child
		var found := _find_named(child, node_name)
		if found != null:
			return found
	return null


func _count_named(root: Node, node_name: String, count: int = 0) -> int:
	for child in root.get_children():
		if child.name == node_name:
			count += 1
		count = _count_named(child, node_name, count)
	return count
