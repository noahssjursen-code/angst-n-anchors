extends Node

## LANE B. DOES EVERY VISUAL THE FIT-OUT DREW SURVIVE THE CACHE?
##
## Lane B because `BuildingCache` preloads `building_fitout.gd` ->
## `brick_door.gd`, which names the `WorldGateway` autoload as a bare
## compile-time identifier. Under `--script` that is `Identifier not found`, the
## cascade reaches this file, and Godot runs it anyway — a compile failure
## indistinguishable from an assertion failure in the results table
## (REALITY.md §4a). `port_perf_cache_test` and `building_interior_test` record
## the same fix in their own headers.
##
## ── WHY THIS FILE EXISTS ────────────────────────────────────────────────────
## `BuildingCache._flatten_visuals` and `_stamp_node` reconstructed
## `MeshInstance3D` and only that. Everything else that draws was a `Node3D`,
## so it was recursed into, contributed no mesh children, and vanished without a
## word — the warehouse's "WAREHOUSE" sign was drawn on no building the game
## stamps, for as long as the blueprint has existed. Nothing in the gate had a
## check pointed at "a non-mesh visual survives the cache" (REALITY.md §4b: not
## a bad check — NO check), which is exactly why it sat invisible while
## `port_perf_cache_test` went green on mesh counts and resource sharing.
##
## ── IT ASSERTS ON THE STAMPED TREE, NOT ON `BuildingFitout` ─────────────────
## `BuildingFitout` is one layer ABOVE the defect and has always drawn the sign
## correctly; a test pointed there passes on a building with no lettering on it
## (REALITY.md §3 — assert against the path that can break). The production path
## is `port_layout_graph_visualizer._stamp_apron_pads` ->
## `BuildingCache.instance(layout, true)`, so that is the call every check below
## makes. `BuildingFitout.build` appears only as the REFERENCE the stamped tree
## is compared against.
##
## ── THE TRAP IN CONSTRUCTING A FIXTURE FOR THIS ─────────────────────────────
## `BuildingCache.instance` routes a layout with an EMPTY `blueprint_id`
## straight to `BuildingFitout.build` and never touches the prototype at all. A
## synthetic layout left with a blank id therefore compares the fit-out against
## itself and passes whatever the cache does — the vacuous pass of REALITY.md
## §4 wearing a fixture. Every synthetic layout here is given an id, and the
## cache is cleared between blueprints because the prototype dictionary is
## static and keyed on that id.
##
## ── WHAT IT MEASURED WHEN IT WAS WRITTEN (2026-08-15) ───────────────────────
## `warehouse.json`, `BuildingFitout` vs `BuildingCache`, by node class:
##
##     BuildingFitout   MeshInstance3D=717  Label3D=1  BrickDoor=2
##     BuildingCache    MeshInstance3D=645  Label3D=0  BrickDoor=0
##
## Two independent losses, and the second was not in the report this file was
## written from. The 72 missing meshes are the two cargo doors' entire
## panelling: `BrickCatalog._add_door_face` parents 9 meshes to the `DoorLeaf`
## MESH, twice per leaf, and the old flatten copied a `MeshInstance3D` without
## recursing into it. So "it reconstructs `MeshInstance3D`" was not true of
## meshes either. Both doors stamped as blank slabs.
##
## The `BrickDoor` loss is NOT asserted here — it is behaviour, not a visual,
## the cache cannot carry it, and `building_interior_test` already holds that
## ground with "every doorway carries a door a player can open".
##
## ── MUTATION VERIFICATION ───────────────────────────────────────────────────
## Control **PASS (34)**. Four mutations, all run through this same file:
##
##  1. `_flatten_visuals` + `_stamp_node` replaced by the mesh-only filter,
##     text taken byte-for-byte from `git show HEAD` and run BY THE GATE, not by
##     hand: **9/20 FAILED** — the sign, the eight synthetic labels, the eight
##     lights, the light metadata, the lens metadata, and 645 of 717 meshes.
##     (The check count drops from 34 to 20 because the sign-detail block early-
##     outs when there is no sign to detail.)
##  2. Only `_stamp_node` reverted, the bake left correct: **7/19**. The bake and
##     the stamp are covered separately; a prototype that keeps the sign and a
##     stamp that drops it is still a building with no sign on it.
##  3. `_copy_metadata` deleted from the mesh copy: **1/34** — the lens check
##     alone. THAT CHECK ONLY EXISTS BECAUSE THIS MUTATION PASSED FIRST TIME:
##     the light metadata rides on `duplicate()` and never touched the mesh
##     path, so nothing was pointed at the half `_copy_metadata` is for. A
##     mutation that passes is a blind check, not a safe one (REALITY.md §8).
##  4. The stamped `Label3D` turned 180°: **2/34** — the facing pair. A first
##     attempt at this mutation rotated inside `_copy_visual` and PASSED, which
##     was the MUTATION being wrong rather than the check: `_copy_visual` does
##     not own the transform, the caller assigns it immediately afterwards.
##
## Neighbouring units, measured both ways on the same box: `building_blueprint_test`
## 4/119 → 4/119, `building_interior_test` 15/37 → 15/37, `port_perf_cache_test`
## PASS (14) → PASS (14), `port_layout_brick_test` PASS (18) → PASS (18),
## `port_trade_profile_test` 1/130 → 1/130. Nothing else moved.

const TestReport := preload("res://tests/support/test_report.gd")

## Bricks whose fit-out visual is not (only) a mesh. Named from the measured
## survey in `tests/_visual_survey.gd`, so a brick that starts emitting
## something new is caught by the class sweep below rather than by this list.
const SIGN_TEXT := "WAREHOUSE"

var _t: TestReport


func _ready() -> void:
	_t = TestReport.new("building_cache_visual_test")

	## 1. Every shipped blueprint, not the one being worked on (REALITY.md §3c).
	var blueprint_ids := BuildingBlueprintCatalog.ids()
	_t.check("the building catalogue ships blueprints to check (%d)" % blueprint_ids.size(),
		blueprint_ids.size() > 0)
	for blueprint_id in blueprint_ids:
		var layout := BuildingBlueprintCatalog.by_id(blueprint_id)
		if layout == null:
			_t.fail("blueprint %s must load" % blueprint_id)
			continue
		_check_layout("blueprint %s" % blueprint_id, layout, true)

	## 2. A synthetic layout carrying one of EVERY brick that draws something
	##    other than a mesh — so a brick nobody has put in a blueprint yet is
	##    still covered, and so the sweep is not hostage to what warehouse.json
	##    happens to contain.
	_check_layout("synthetic all-non-mesh-visual layout", _non_mesh_layout(), true)

	## 3. The sign specifically: it is a Label3D, it has a facing and a billboard
	##    mode, and "a Label3D exists in the tree" is not the same claim as "it
	##    reads as a sign on the wall".
	_check_the_sign()

	## 4. The cache must still be a cache after all that.
	_check_still_shares()

	_t.finish(get_tree())


## ── THE PROPERTY ────────────────────────────────────────────────────────────
## Not "the stamped tree has 1 Label3D" — that restates the fixture and goes
## stale the moment a blueprint gains a second sign (REALITY.md §4a). The
## property is that the CACHE LOSES NOTHING THAT DRAWS: for every
## `VisualInstance3D` class the fit-out emitted, the stamped tree emits at least
## as many. It is stated per class rather than as a total so that 72 doorleaf
## meshes cannot be cancelled out by anything, and it holds for a class this
## file has never heard of.
func _check_layout(label: String, layout: BuildingLayout, expect_non_mesh: bool) -> void:
	var fitout := BuildingFitout.build(layout, false)
	var want := _visual_census(fitout)
	fitout.free()

	BuildingCache.clear()
	var cached := BuildingCache.instance(layout, true)
	var got := _visual_census(cached)
	cached.free()
	BuildingCache.clear()

	## Guard against a vacuous pass: a layout that draws nothing satisfies
	## "loses nothing" for free, and an empty universe is REALITY.md §4's
	## favourite way to report success.
	var mesh_count := int(want.get("MeshInstance3D", 0))
	_t.check("%s: the fit-out draws meshes at all (%d)" % [label, mesh_count], mesh_count > 0)
	if expect_non_mesh:
		var non_mesh := 0
		for cls in want:
			if cls != "MeshInstance3D":
				non_mesh += int(want[cls])
		_t.check("%s: the fit-out draws a visual that is NOT a mesh (%d, %s)"
			% [label, non_mesh, _fmt(want)], non_mesh > 0)

	var keys := want.keys()
	keys.sort()
	for cls in keys:
		var before := int(want[cls])
		var after := int(got.get(cls, 0))
		_t.check(
			"%s: the stamped building keeps every %s the fit-out drew (%d of %d)"
			% [label, str(cls), after, before],
			after >= before,
		)


## ── DOES IT READ AS A SIGN? ────────────────────────────────────────────────
## Four separate claims, because a `Label3D` that exists satisfies none of them
## on its own: it has to carry the authored text, stand where the fit-out put
## it, face out of the wall rather than into it, and not be a billboard (a
## billboarded label ignores its own transform, which would make the facing
## check meaningless — REALITY.md §8, check the instrument).
func _check_the_sign() -> void:
	var layout := BuildingBlueprintCatalog.by_id("warehouse")
	if not _t.check("the warehouse blueprint must load", layout != null):
		return

	var fitout := BuildingFitout.build(layout, false)
	var reference := _labels(fitout)
	_t.check("the warehouse fit-out draws lettering (%d Label3D)" % reference.size(),
		reference.size() > 0)

	BuildingCache.clear()
	var cached := BuildingCache.instance(layout, true)
	var stamped := _labels(cached)
	_t.equal("the stamped warehouse draws the same lettering the fit-out did",
		stamped.size(), reference.size())

	if not stamped.is_empty() and not reference.is_empty():
		var want := reference[0]
		var got := stamped[0]
		_t.equal("the stamped sign shows what the fit-out drew", got.text, want.text)
		## Read out of the BLUEPRINT, not restated as a constant here: a literal
		## would go red the day somebody renames the building and would say
		## nothing about whether the text travelled (REALITY.md §4a).
		var authored := _authored_sign_text(layout)
		_t.check("the sign shows the text the blueprint authored (%s / %s)"
			% [got.text, authored],
			not authored.is_empty() and got.text.to_upper() == authored.to_upper())
		_t.check("the sign carries a font (%s)"
			% ("null" if got.font == null else got.font.get_class()), got.font != null)
		## The properties a hand-written field list drops first, and the reason
		## the fix duplicates a non-mesh visual instead of copying it field by
		## field: without them the lettering is white-on-pale with no outline,
		## i.e. present in the tree and invisible on the wall.
		_t.equal("the sign keeps its paint colour", got.modulate, want.modulate)
		_t.equal("the sign keeps the dark outline that makes it read on cladding",
			got.outline_size, want.outline_size)
		_t.equal("the sign keeps its outline colour",
			got.outline_modulate, want.outline_modulate)
		## Letter height in metres, not font_size in points: the second is a
		## number the fixture already states, the first is what a player sees
		## beside a 1.8 m figure. `pixel_size * font_size` is the cap height.
		var letter_h := got.pixel_size * float(got.font_size)
		_t.check("the letters are legible at building scale (%.3f m tall)" % letter_h,
			letter_h >= 0.35 and letter_h <= 4.0)
		## Same place, same orientation as the fit-out drew it. The transform is
		## the whole flatten step, so this is where a mis-accumulated parent
		## transform would show up.
		##
		## MEASURED RELATIVE TO EACH TREE'S OWN ROOT, not with
		## `global_transform`. Neither tree is inside the SceneTree here, and for
		## a detached node `Node3D.global_transform` is its LOCAL transform —
		## which silently reported every course at y = 0 the first time
		## `_q1_cell_shot.gd` ran. The instrument, before the subject
		## (REALITY.md §8).
		var want_x := _relative_xform(want, fitout)
		var got_x := _relative_xform(got, cached)
		_t.check("the sign stands where the fit-out put it (fitout %s, cached %s)"
			% [str(want_x.origin.snapped(Vector3.ONE * 0.001)),
				str(got_x.origin.snapped(Vector3.ONE * 0.001))],
			want_x.origin.distance_to(got_x.origin) < 0.001)
		_t.check("the sign is turned the way the fit-out turned it",
			want_x.basis.z.distance_to(got_x.basis.z) < 0.001)
		## A Label3D's face normal is its local +Z. "Outward" is measured against
		## the building's own footprint centre, so this survives any yaw and does
		## not restate the 180° in `BrickCatalog`.
		var bounds := _mesh_bounds(cached)
		var centre := bounds.get_center()
		var outward := got_x.origin - Vector3(centre.x, got_x.origin.y, centre.z)
		_t.check("the sign faces out of the wall, not into the building (dot %.3f)"
			% got_x.basis.z.dot(outward.normalized()),
			outward.length() > 0.01 and got_x.basis.z.dot(outward.normalized()) > 0.5)
		_t.equal("the sign is not a billboard, so its facing is its transform",
			got.billboard, BaseMaterial3D.BILLBOARD_DISABLED)
		## The sign is ON the wall, not floating over the roof or under the slab.
		_t.check("the sign sits within the building's own height (%.2f m, walls %.2f..%.2f)"
			% [got_x.origin.y, bounds.position.y, bounds.position.y + bounds.size.y],
			got_x.origin.y >= bounds.position.y
				and got_x.origin.y <= bounds.position.y + bounds.size.y)

	fitout.free()
	cached.free()
	BuildingCache.clear()

	## The day/night controller finds a fixture by metadata, so a stamped light
	## that has lost its metadata is a light `BuildingLighting` cannot dim. The
	## light bricks are not in warehouse.json, so this is asked of a synthetic
	## layout — but through the CACHE, like everything else here.
	var lit := BuildingLayout.new()
	lit.blueprint_id = "test_lit_building"
	lit.grid_size = Vector3i(8, 8, 8)
	lit.place_footprint(Vector3i(2, 0, 2), "block", 0)
	var lit_ok := lit.place_footprint(Vector3i(4, 0, 4), "light_ceiling", 0)
	if _t.check("light_ceiling can be placed in a blueprint", lit_ok):
		## The fit-out's own count, so the claim below is "the cache kept them"
		## and not "there is at least one", which any building satisfies.
		var lit_fitout := BuildingFitout.build(lit, false)
		var want_lenses := _tagged_count(lit_fitout, "MeshInstance3D",
			"building_lens_base_emission")
		lit_fitout.free()
		BuildingCache.clear()
		var lit_building := BuildingCache.instance(lit, false)
		var lights := _nodes_of_class(lit_building, "Light3D")
		_t.check("a stamped building keeps its light fixtures (%d)" % lights.size(),
			lights.size() > 0)
		var tagged := 0
		for node in lights:
			if node.has_meta("building_light_base_energy"):
				tagged += 1
		_t.check(
			"BuildingLighting can find every stamped fixture by its metadata (%d of %d)"
			% [tagged, lights.size()],
			lights.size() > 0 and tagged == lights.size(),
		)
		## The other half of what `BuildingLighting` dims, and the half that goes
		## through the MESH copy rather than through `duplicate()`. Added because
		## deleting the mesh metadata copy left this file GREEN on the first
		## attempt — a mutation that passes is a blind check, not a safe one
		## (REALITY.md §8). A lens whose meta is gone keeps its emissive material
		## and stops following the weather, on every stamped building.
		var got_lenses := _tagged_count(lit_building, "MeshInstance3D",
			"building_lens_base_emission")
		_t.check(
			"the stamped fixture's lens still follows the weather (%d of %d dimmable)"
			% [got_lenses, want_lenses],
			want_lenses > 0 and got_lenses == want_lenses,
		)
		var controller := lit_building.get_node_or_null("BuildingLighting")
		_t.check("the stamped building still carries its day/night controller",
			controller != null)
		lit_building.free()
		BuildingCache.clear()


## Sharing is the reason this class exists; a fix that copied resources per
## instance would be a regression wearing a green sign. `port_perf_cache_test`
## asserts it for meshes — this asserts it for the non-mesh visuals the fix
## added, which are the ones `duplicate()` could plausibly have deep-copied.
func _check_still_shares() -> void:
	var layout := BuildingBlueprintCatalog.by_id("warehouse")
	if layout == null:
		return
	BuildingCache.clear()
	var a := BuildingCache.instance(layout, false)
	var b := BuildingCache.instance(layout, false)
	var labels_a := _labels(a)
	var labels_b := _labels(b)
	if _t.check("both stamps carry lettering (%d / %d)" % [labels_a.size(), labels_b.size()],
			labels_a.size() > 0 and labels_a.size() == labels_b.size()):
		_t.check("the two stamps are separate Label3D nodes, not one shared node",
			labels_a[0] != labels_b[0])
		_t.check("the two stamps SHARE the font resource rather than copying it",
			labels_a[0].font != null and labels_a[0].font == labels_b[0].font)
	a.free()
	b.free()
	BuildingCache.clear()


## ── FIXTURE ─────────────────────────────────────────────────────────────────
## One placement of every brick whose fit-out emits something other than a mesh,
## discovered by ASKING the catalogue rather than by listing ids here: a brick
## added tomorrow is covered without editing this file.
func _non_mesh_layout() -> BuildingLayout:
	var layout := BuildingLayout.new()
	layout.blueprint_id = "test_non_mesh_visuals"
	layout.grid_size = Vector3i(64, 12, 64)
	var x := 2
	var placed := 0
	for brick_id in BrickCatalog.ids():
		var probe := BuildingFitout.build(_single_brick_layout(brick_id), false)
		var census := _visual_census(probe)
		probe.free()
		var non_mesh := 0
		for cls in census:
			if cls != "MeshInstance3D":
				non_mesh += int(census[cls])
		if non_mesh == 0:
			continue
		var props: Dictionary = {}
		if BrickCatalog.has_tag(brick_id, "text"):
			props["text"] = SIGN_TEXT
		if layout.place_footprint(Vector3i(x, 0, 2), brick_id, 0, null, null, props):
			placed += 1
		x += 8
	_t.check("the synthetic layout carries every non-mesh-visual brick (%d placed)" % placed,
		placed > 0)
	return layout


func _single_brick_layout(brick_id: String) -> BuildingLayout:
	var layout := BuildingLayout.new()
	layout.blueprint_id = "probe_%s" % brick_id
	layout.grid_size = Vector3i(24, 12, 24)
	var props: Dictionary = {}
	if BrickCatalog.has_tag(brick_id, "text"):
		props["text"] = SIGN_TEXT
	layout.place_footprint(Vector3i(4, 0, 4), brick_id, 0, null, null, props)
	return layout


## ── INSTRUMENTS ─────────────────────────────────────────────────────────────
## Counts things that DRAW. `VisualInstance3D` is the engine's own line for that
## and it is the line the fix draws: meshes, labels, sprites, particles, decals
## and lights are all VisualInstance3D; a `Node3D`, a `Marker3D` or a behaviour
## script is not, and the cache carries their contribution as a transform or not
## at all.
func _visual_census(node: Node, out: Dictionary = {}) -> Dictionary:
	for child in node.get_children():
		if child is VisualInstance3D:
			var cls := child.get_class()
			out[cls] = int(out.get(cls, 0)) + 1
		_visual_census(child, out)
	return out


func _labels(node: Node) -> Array[Label3D]:
	var out: Array[Label3D] = []
	if node is Label3D:
		out.append(node as Label3D)
	for child in node.get_children():
		out.append_array(_labels(child))
	return out


func _nodes_of_class(node: Node, cls: String) -> Array[Node]:
	var out: Array[Node] = []
	for child in node.get_children():
		if child.is_class(cls):
			out.append(child)
		out.append_array(_nodes_of_class(child, cls))
	return out


## Transform of `node` in `root`'s frame, walked by hand. See the note beside
## the sign's position check: `global_transform` lies for a detached tree.
func _relative_xform(node: Node3D, root: Node) -> Transform3D:
	var out := Transform3D.IDENTITY
	var walk: Node = node
	while walk != null and walk != root:
		if walk is Node3D:
			out = (walk as Node3D).transform * out
		walk = walk.get_parent()
	return out


func _authored_sign_text(layout: BuildingLayout) -> String:
	for entry in layout.iter_primary_cells():
		var brick_id := str(entry.get("brick_id", ""))
		if BrickCatalog.has_tag(brick_id, "text") and entry.has("text"):
			return str(entry["text"])
		if entry.has("sign_id") and entry.has("text"):
			return str(entry["text"])
	return ""


func _tagged_count(root: Node, cls: String, meta_key: String) -> int:
	var count := 0
	for node in _nodes_of_class(root, cls):
		if node.has_meta(meta_key):
			count += 1
	return count


func _mesh_bounds(root: Node) -> AABB:
	var out := AABB()
	var first := true
	for mi in _nodes_of_class(root, "MeshInstance3D"):
		var mesh_node := mi as MeshInstance3D
		if mesh_node.mesh == null:
			continue
		var aabb := _relative_xform(mesh_node, root) * mesh_node.get_aabb()
		if first:
			out = aabb
			first = false
		else:
			out = out.merge(aabb)
	return out


func _fmt(kinds: Dictionary) -> String:
	var keys := kinds.keys()
	keys.sort()
	var parts: PackedStringArray = []
	for k in keys:
		parts.append("%s=%d" % [str(k), int(kinds[k])])
	return ", ".join(parts)
