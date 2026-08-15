extends Node

## Lane B — it spawns real vessels through `CompanyService` / `VesselSpawn` and
## reads the meshes the fit-out actually builds, so it needs the autoloads and a
## live scene tree.
##
## ── THE CLAIM THIS UNIT HOLDS ───────────────────────────────────────────────
##
## Commit `3582276` rebuilt the starter vessel's deckhouse — a cantilevered brow,
## a hipped `roof_slope`/`roof_corner` cap, a full-width `block_windshield` band —
## and NOTHING in the gate could tell. Reverting the cap to `roof_flat` still
## emitted `GEN OK`, all four presets still certified, and 104 units still
## passed. CONVENTIONS §3 (a capture is paired with a machine-checkable claim)
## was unmet for that change.
##
## This unit is that claim. It asserts three SHAPE PROPERTIES of the wheelhouse
## on every shipped preset, measured off the triangles the spawned vessel draws.
##
## ── WHY PROPERTIES AND NOT A BRICK INVENTORY ────────────────────────────────
##
## `roof_slope == 22` is a restated number (REALITY.md §4a): it freezes today's
## house and fights the next improvement. Nothing below names a brick id or
## counts one. A house re-drawn with different bricks, at a different size, on a
## hull nobody has authored yet passes every check here as long as it is still a
## wheelhouse — and a house flattened back into a shoebox fails, whatever it is
## built from.
##
## ── WHAT LAYER THIS ASSERTS AT, AND WHAT THAT COSTS ─────────────────────────
##
## The spawned vessel, with `DeckFitout.skin_enabled` at its SHIPPING value.
## The previous wave concluded the geometry was not addressable there, because
## `VesselSkinBaker` merges every static brick into a handful of meshes and a
## per-brick node lookup finds nothing. That is true of NODES and false of
## GEOMETRY: the merged meshes still carry every vertex, and `surface_get_arrays`
## reads them. Nothing here needs `skin_enabled = false`, so nothing here is
## asserted against a configuration the game does not use.
##
## §4 holds that open rather than assuming it: it measures the same three
## properties with the merger off and requires the two to agree. The mechanism
## says they must — `_merge_generic_brick` appends a brick's own mesh under its
## placement transform, and the box path emits full-cell faces at exact cell
## coordinates, culling only faces BETWEEN two solid cells, which are interior by
## construction — but "the mechanism says so" is REALITY.md §6. Measured on the
## starter: merged 21908 triangles inside the house plan against 22460 unmerged,
## and every shape number below identical to four decimals.
##
## ── THE FORMULATION THAT WAS TRIED AND IS BLIND (REALITY.md §8) ─────────────
##
## "The roof's top surface has more than one height" sounds like the property and
## is worthless. `roof_flat` draws a 0.18 m slab at the top of its cell, so a
## dead-flat lid already presents TWO distinct vertex heights (+0.32 and +0.50)
## and the check goes green on the shoebox. §1 measures the FALL instead — how
## high the surface stands at the house's outer perimeter against how high it
## stands inboard — which is 0.5000 m on the hipped cap and 0.0000 m on a flat
## slab, because a slab is as tall at its edge as in its middle.

const TestReport := preload("res://tests/support/test_report.gd")

const CELL := 0.5

## Every preset that carries a wheelhouse. Run over ALL of them, not the one
## being worked on (REALITY.md §3c) — the same generator draws all four, and the
## 28 m boats are the ones nobody looks at.
const PRESETS := ["fishing_trawler", "28_10_m", "bulk_small"]

## ── The thresholds, and the argument for each ───────────────────────────────
##
## Every one is a floor on a shape, not a restatement of a dimension. The
## measured value on the shipped house and on the mutation each guards are in
## the section comments.

## §1. How far the roof falls from its inboard high point to the house's outer
## perimeter. A flat lid measures EXACTLY 0.0 — it is as tall at its edge as in
## its middle. 0.20 m over the 1.5 m half-span of a 3 m house is a 7.6° pitch,
## which is about the shallowest fall that still reads as a roof rather than as
## a slab with a tolerance. The hipped cap measures 0.5000.
const MIN_ROOF_FALL_M := 0.20

## §2a. The widest uninterrupted pane on the forward face, as a multiple of its
## own height. This is the difference between a windscreen and a grid of punched
## squares, and it is scale-free: it does not care how big the house is. A cell
## of `block_window` is a 0.34 x 0.34 m square — aspect 1.00, by construction,
## at any cell size. The `block_windshield` band measures 3.94.
const MIN_PANE_ASPECT := 2.0

## §2b. That same pane as a fraction of the house's own beam — "glazed ACROSS
## the front" rather than "has a wide window somewhere". Scale-relative on
## purpose: a wider house needs a wider windscreen to read the same. Shipped
## 44.7%; punched panes 11.3%.
const MIN_PANE_SPAN_FRACTION := 0.25

## §2c. Total glazed width on the best row, as a fraction of the house's beam.
## This one does NOT separate a windscreen from punched panes — 89.3% against
## 68.0%, and it is honest to say so. It guards a different regression: a house
## that loses its window band altogether, or falls back to the three slits the
## pre-2026-08-15 shoebox had. Verified by mutation, separately from §2a/§2b.
const MIN_GLAZED_FRACTION := 0.50

## §3. How far the top of the house stands proud of its base. The instrument's
## own noise here is 0.020 m — a window frame stands that far out of the wall
## plane it is set into, measured — so this floor is 7.5x the noise and less
## than a third of the 0.5 m cantilever it is holding. Shipped 0.500; a house
## with the brow removed measures 0.000.
const MIN_BROW_PROUD_M := 0.15

var _t := TestReport.new("deckhouse_shape_test")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	await _check_the_boat_a_new_captain_is_given()
	for preset in PRESETS:
		await _check_preset(preset)
	await _check_the_merged_skin_draws_the_same_house()
	_t.finish(get_tree())


# ── 1 · the starter, through onboarding's own spawn path ────────────────────

func _check_the_boat_a_new_captain_is_given() -> void:
	## Not the catalogue entry: the record onboarding actually hands over. The
	## wheelhouse a player sees on their first boat is the subject of the commit
	## this unit exists for.
	var record := CompanyService.build_starter_vessel_record(CompanyContracts.DEFAULT_STARTER)
	if not _t.check("onboarding hands over a starter vessel record", not record.is_empty()):
		return
	var boat := VesselSpawn.instantiate_from_record(record)
	if not _t.check("the granted record spawns", boat != null):
		return
	boat.name = "GrantedStarter"
	boat.automatic_physics_lod = false
	boat.freeze = true
	add_child(boat)
	await get_tree().process_frame
	var hull_id := str(record.get("hull_id", ""))
	_assert_house(
		"the boat a new captain is given",
		boat,
		BrickLayout.from_dict(VesselSpawn.brick_layout_of(record)),
		HullRegistry.make_grid(hull_id),
	)
	boat.free()
	await get_tree().process_frame


# ── 2 · every other shipped preset carries the same wheelhouse ──────────────

func _check_preset(prebuilt_id: String) -> void:
	var entry := {}
	for candidate in PrebuiltVesselCatalog.catalog_entries():
		if str(candidate.get("prebuilt_id", "")) == prebuilt_id:
			entry = candidate
			break
	if not _t.check("the preset '%s' is in the catalogue" % prebuilt_id, not entry.is_empty()):
		return
	var hull_id := str(entry.get("hull_id", ""))
	var layout_dict := (entry.get("prebuilt_layout", {}) as Dictionary).duplicate(true)
	var boat := VesselSpawn.instantiate(
		hull_id, layout_dict, str(entry.get("registration_id", ""))
	)
	if not _t.check("'%s' spawns" % prebuilt_id, boat != null):
		return
	boat.name = "Preset_" + prebuilt_id
	boat.automatic_physics_lod = false
	boat.freeze = true
	add_child(boat)
	await get_tree().process_frame
	_assert_house(
		prebuilt_id, boat, BrickLayout.from_dict(layout_dict), HullRegistry.make_grid(hull_id)
	)
	boat.free()
	await get_tree().process_frame


# ── 3 · the three properties ────────────────────────────────────────────────

func _assert_house(
	label: String, boat: Node3D, layout: BrickLayout, grid: DeckGrid
) -> Dictionary:
	var shape := measure(boat, layout, grid)
	if not _t.check(
		"%s — the fit-out draws a deckhouse to measure (%d triangles inside its plan)"
		% [label, int(shape.get("tri_n", 0))],
		int(shape.get("tri_n", 0)) > 0,
	):
		return shape

	## §1 — THE ROOF IS NOT A FLAT LID.
	## A roof that is lower at the house's outer edge than it is inboard has a
	## fall in it, whichever way it is drawn — hipped, gabled, cambered, monopitch.
	## A flat slab is the same height everywhere and measures exactly zero.
	_t.check(
		"%s — the roof falls %.4f m from inboard to the house's outer perimeter (>= %.2f)"
		% [label, float(shape["roof_fall_m"]), MIN_ROOF_FALL_M],
		float(shape["roof_fall_m"]) >= MIN_ROOF_FALL_M,
	)

	## §2 — THE FRONT IS GLAZED AS A BAND, NOT PUNCHED WITH SQUARES.
	if _t.check(
		"%s — there is glass on the forward face at all" % label,
		bool(shape.get("has_front_glass", false)),
	):
		_t.check(
			"%s — its widest uninterrupted pane is %.2fx as wide as it is tall (%.3f x %.3f m, >= %.1fx)"
			% [
				label, float(shape["pane_aspect"]), float(shape["pane_w_m"]),
				float(shape["pane_h_m"]), MIN_PANE_ASPECT,
			],
			float(shape["pane_aspect"]) >= MIN_PANE_ASPECT,
		)
		_t.check(
			"%s — that one pane spans %.1f%% of the %.2f m front (>= %.0f%%)"
			% [
				label, 100.0 * float(shape["pane_span_fraction"]), float(shape["house_w_m"]),
				100.0 * MIN_PANE_SPAN_FRACTION,
			],
			float(shape["pane_span_fraction"]) >= MIN_PANE_SPAN_FRACTION,
		)
		_t.check(
			"%s — the front is glazed over %.1f%% of its width (>= %.0f%%)"
			% [
				label, 100.0 * float(shape["glazed_fraction"]),
				100.0 * MIN_GLAZED_FRACTION,
			],
			float(shape["glazed_fraction"]) >= MIN_GLAZED_FRACTION,
		)

	## §3 — THE BROW STANDS PROUD OF THE WALL BELOW IT.
	## The top of the house reaches further forward than its base does, so the
	## front breaks forward at the top instead of standing as one plumb plane.
	_t.check(
		"%s — the top of the house stands %.4f m proud of its base (>= %.2f); forward-most z by level: %s"
		% [
			label, float(shape["brow_proud_m"]), MIN_BROW_PROUD_M,
			str(shape.get("level_front_z", [])),
		],
		float(shape["brow_proud_m"]) >= MIN_BROW_PROUD_M,
	)
	return shape


# ── 4 · the merged skin draws the same house as the unmerged one ────────────

func _check_the_merged_skin_draws_the_same_house() -> void:
	## Everything above is measured with `skin_enabled` at its shipping value, so
	## this is not a licence to assert elsewhere — it is the check that the layer
	## above is honest. If the merger ever stops preserving the shape it bakes,
	## this reddens, and that is a much larger finding than a deckhouse.
	var entry := {}
	for candidate in PrebuiltVesselCatalog.catalog_entries():
		if str(candidate.get("prebuilt_id", "")) == "sjark_15m":
			entry = candidate
			break
	if not _t.check("the starter preset is in the catalogue", not entry.is_empty()):
		return
	var hull_id := str(entry.get("hull_id", ""))
	var layout_dict := (entry.get("prebuilt_layout", {}) as Dictionary).duplicate(true)
	var grid := HullRegistry.make_grid(hull_id)
	var layout := BrickLayout.from_dict(layout_dict)
	var shapes := {}
	for merged in [true, false]:
		var previous := DeckFitout.skin_enabled
		DeckFitout.skin_enabled = merged
		var boat := VesselSpawn.instantiate(
			hull_id, layout_dict.duplicate(true), str(entry.get("registration_id", ""))
		)
		DeckFitout.skin_enabled = previous
		if not _t.check("the starter spawns with skin_enabled=%s" % merged, boat != null):
			return
		boat.name = "SkinParity_%s" % merged
		boat.automatic_physics_lod = false
		boat.freeze = true
		add_child(boat)
		await get_tree().process_frame
		shapes[merged] = measure(boat, layout, grid)
		boat.free()
		await get_tree().process_frame

	var merged_shape: Dictionary = shapes[true]
	var loose_shape: Dictionary = shapes[false]
	## The merger's whole job is to draw fewer triangles. If these were equal the
	## comparison below would be comparing a configuration with itself (§4).
	_t.check(
		"the merger is actually doing something — %d triangles inside the house plan against %d unmerged"
		% [int(merged_shape["tri_n"]), int(loose_shape["tri_n"])],
		int(merged_shape["tri_n"]) < int(loose_shape["tri_n"]),
	)
	for key in ["roof_fall_m", "pane_w_m", "pane_h_m", "glazed_fraction", "brow_proud_m"]:
		_t.near(
			"the merged skin draws the same '%s' as the unmerged fit-out" % key,
			float(merged_shape.get(key, -1.0)), float(loose_shape.get(key, -2.0)), 0.0005,
		)


# ── the instrument ──────────────────────────────────────────────────────────
#
# Public so a probe can drive it against a mutated tree without a second
# derivation of any of it (REALITY.md §3b).


static func measure(boat: Node3D, layout: BrickLayout, grid: DeckGrid) -> Dictionary:
	var house := _house_bounds(layout, grid)
	if int(house["roof_y"]) < 0:
		return {"tri_n": 0}
	var tris := _in_house(_collect(boat), house)
	var out := {
		"tri_n": (tris["tri"] as Array).size(),
		"house_w_m": float(house["x_max"]) - float(house["x_min"]),
	}
	out.merge(_roof(tris, house))
	out.merge(_glass(tris, house))
	out.merge(_brow(tris, house))
	return out


## The house's plan and roof level, taken from the bounds of every cell whose
## brick carries the catalogue's "roof" tag. This is ADDRESSING, not the
## assertion: it says where to look, and every check above is then made against
## the geometry found there. A cap re-drawn with different roof bricks is found
## the same way; a house with no roof at all returns roof_y = -1 and fails the
## "there is a deckhouse to measure" check rather than passing vacuously.
static func _house_bounds(layout: BrickLayout, grid: DeckGrid) -> Dictionary:
	var ix0 := 1 << 30
	var ix1 := -(1 << 30)
	var iz0 := 1 << 30
	var iz1 := -(1 << 30)
	var roof_y := -1
	for item in layout.iter_primary_cells():
		if not BrickCatalog.has_tag(str(item.get("brick_id", "")), "roof"):
			continue
		var c: Vector3i = item["cell"]
		ix0 = mini(ix0, c.x)
		ix1 = maxi(ix1, c.x)
		iz0 = mini(iz0, c.z)
		iz1 = maxi(iz1, c.z)
		roof_y = maxi(roof_y, c.y)
	if roof_y < 0:
		return {"roof_y": -1}
	return {
		"roof_y": roof_y,
		"x_min": -grid.half_beam + float(ix0) * CELL,
		"x_max": -grid.half_beam + float(ix1 + 1) * CELL,
		"z_min": -grid.half_loa + float(iz0) * CELL,
		"z_max": -grid.half_loa + float(iz1 + 1) * CELL,
		"y_roof0": grid.deck_y + float(roof_y) * CELL,
		"y_roof1": grid.deck_y + float(roof_y + 1) * CELL,
		"deck_y": grid.deck_y,
	}


## Every triangle the FIT-OUT draws, in boat-local metres, with a glass flag.
##
## The hull's own meshes are excluded deliberately: the deck plate spans the
## whole vessel, so it is present at every (x, z) inside the house plan and
## would answer "how far forward does the house reach" with the plan's own
## bounds at every level.
##
## Glass is identified by its MATERIAL — an albedo alpha below 1 — not by the
## brick that drew it. That is what survives the merge: `_merge_generic_brick`
## buckets by material, so every pane on the vessel lands in one mesh and no
## per-brick node is needed to tell glass from cladding.
static func _collect(boat: Node3D) -> Dictionary:
	var out_tri: Array = []
	var out_glass: Array = []
	var root := boat.get_node_or_null("DeckFitout")
	if root == null:
		return {"tri": out_tri, "glass": out_glass}
	var to_boat := boat.global_transform.affine_inverse()
	var stack: Array = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.append(child)
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var xform := to_boat * mi.global_transform
		for s in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(s)
			var is_glass := (
				mat is StandardMaterial3D
				and (mat as StandardMaterial3D).albedo_color.a < 0.999
			)
			var arrays := mi.mesh.surface_get_arrays(s)
			if arrays.size() <= Mesh.ARRAY_VERTEX or arrays[Mesh.ARRAY_VERTEX] == null:
				continue
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var idx := PackedInt32Array()
			if arrays.size() > Mesh.ARRAY_INDEX and arrays[Mesh.ARRAY_INDEX] != null:
				idx = arrays[Mesh.ARRAY_INDEX]
			if idx.is_empty():
				idx = PackedInt32Array(range(verts.size()))
			var i := 0
			while i + 2 < idx.size():
				out_tri.append([
					xform * verts[idx[i]], xform * verts[idx[i + 1]], xform * verts[idx[i + 2]],
				])
				out_glass.append(is_glass)
				i += 3
	return {"tri": out_tri, "glass": out_glass}


## Triangles inside the house's plan footprint and above the deck, each carried
## with its own AABB so a level is a BAND INTERSECTION rather than a vertex test.
## That distinction is not pedantry: a `block` fills its cell exactly, so all of
## its vertices sit ON the level planes and a vertex-in-band filter reads a solid
## wall as an empty level. The first version of this instrument did exactly that
## and reported the wheelhouse's forward face as 0.5 m ABAFT where it is drawn.
static func _in_house(all_tris: Dictionary, h: Dictionary) -> Dictionary:
	var tri: Array = []
	var mins: Array = []
	var maxs: Array = []
	var glass: Array = []
	var src: Array = all_tris["tri"]
	var src_glass: Array = all_tris["glass"]
	for i in src.size():
		var t: Array = src[i]
		var mn := Vector3(1e9, 1e9, 1e9)
		var mx := Vector3(-1e9, -1e9, -1e9)
		for p_variant in t:
			var p: Vector3 = p_variant
			mn = Vector3(minf(mn.x, p.x), minf(mn.y, p.y), minf(mn.z, p.z))
			mx = Vector3(maxf(mx.x, p.x), maxf(mx.y, p.y), maxf(mx.z, p.z))
		if mx.y < float(h["deck_y"]) - 0.01:
			continue
		if mn.x < float(h["x_min"]) - 0.05 or mx.x > float(h["x_max"]) + 0.05:
			continue
		if mn.z < float(h["z_min"]) - 0.05 or mx.z > float(h["z_max"]) + 0.05:
			continue
		tri.append(t)
		mins.append(mn)
		maxs.append(mx)
		glass.append(src_glass[i])
	return {"tri": tri, "min": mins, "max": maxs, "glass": glass}


## §1's measurement. Inside the roof level's own 0.5 m band, how high does the
## drawn surface stand at the house's outer perimeter, and how high inboard?
static func _roof(tris: Dictionary, h: Dictionary) -> Dictionary:
	var y0: float = h["y_roof0"]
	var y1: float = h["y_roof1"]
	var edge_top := y0
	var inner_top := y0
	for t in tris["tri"] as Array:
		for p_variant in t as Array:
			var p: Vector3 = p_variant
			if p.y < y0 - 0.02 or p.y > y1 + 0.02:
				continue
			var inset: float = minf(
				minf(p.x - float(h["x_min"]), float(h["x_max"]) - p.x),
				minf(p.z - float(h["z_min"]), float(h["z_max"]) - p.z),
			)
			if inset <= 0.02:
				edge_top = maxf(edge_top, p.y)
			if inset >= CELL - 0.05:
				inner_top = maxf(inner_top, p.y)
	return {
		"roof_edge_top_m": edge_top - y0,
		"roof_inner_top_m": inner_top - y0,
		"roof_fall_m": inner_top - edge_top,
	}


## §2's measurement. The forward-facing glazing rasterised onto a 1 cm
## occupancy grid on the front plane, so a merged mesh holding every pane in one
## surface and a tree of per-brick nodes are read by the same code. Panes are
## axis-aligned quads, so a triangle's AABB IS its footprint on that plane.
static func _glass(tris: Dictionary, h: Dictionary) -> Dictionary:
	var glass: Array = tris["glass"]
	var mins: Array = tris["min"]
	var maxs: Array = tris["max"]
	var house_w: float = float(h["x_max"]) - float(h["x_min"])
	var none := {
		"has_front_glass": false, "pane_w_m": 0.0, "pane_h_m": 0.0,
		"pane_aspect": 0.0, "pane_span_fraction": 0.0, "glazed_fraction": 0.0,
	}
	var zg := 1e9
	for i in glass.size():
		if bool(glass[i]):
			zg = minf(zg, (mins[i] as Vector3).z)
	if zg > 1e8:
		return none
	## Forward-facing panes only. The side windshields are set a whole cell
	## abaft this plane, so a 0.10 m slice takes the front and nothing else.
	var sel: Array = []
	var y_lo := 1e9
	var y_hi := -1e9
	for i in glass.size():
		if not bool(glass[i]) or (mins[i] as Vector3).z > zg + 0.10:
			continue
		sel.append(i)
		y_lo = minf(y_lo, (mins[i] as Vector3).y)
		y_hi = maxf(y_hi, (maxs[i] as Vector3).y)
	if sel.is_empty():
		return none
	var bin := 0.01
	var nx := int(ceil(house_w / bin)) + 2
	var ny := int(ceil((y_hi - y_lo) / bin)) + 2
	var occ := PackedByteArray()
	occ.resize(nx * ny)
	for i in sel:
		var mn: Vector3 = mins[i]
		var mx: Vector3 = maxs[i]
		var cx0 := clampi(int(round((mn.x - float(h["x_min"])) / bin)), 0, nx - 1)
		var cx1 := clampi(int(round((mx.x - float(h["x_min"])) / bin)), 0, nx)
		var cy0 := clampi(int(round((mn.y - y_lo) / bin)), 0, ny - 1)
		var cy1 := clampi(int(round((mx.y - y_lo) / bin)), 0, ny)
		for r in range(cy0, cy1):
			for c in range(cx0, cx1):
				occ[r * nx + c] = 1
	var best_w := 0
	var best_c0 := 0
	var widest_row := 0
	for r in ny:
		var run := 0
		var total := 0
		for c in nx:
			if occ[r * nx + c] == 1:
				run += 1
				total += 1
				if run > best_w:
					best_w = run
					best_c0 = c - run + 1
			else:
				run = 0
		widest_row = maxi(widest_row, total)
	if best_w <= 0:
		return none
	## The tallest CONTIGUOUS stack of rows over that run. Counting every row in
	## the grid that happens to be occupied there instead adds the SECOND row of
	## glazing to the first pane's height — it read 0.69 m for a 0.34 m pane and
	## turned an aspect of 3.94 into 1.97, a hair above the 2.0 floor it feeds.
	## Caught by predicting the number before reading it (REALITY.md §8).
	var tall := 0
	var run_rows := 0
	for r in ny:
		var covered := true
		for c in range(best_c0, best_c0 + best_w):
			if occ[r * nx + c] != 1:
				covered = false
				break
		if covered:
			run_rows += 1
			tall = maxi(tall, run_rows)
		else:
			run_rows = 0
	var pane_w := float(best_w) * bin
	var pane_h := float(tall) * bin
	return {
		"has_front_glass": true,
		"pane_w_m": pane_w,
		"pane_h_m": pane_h,
		"pane_aspect": pane_w / maxf(pane_h, bin),
		"pane_span_fraction": pane_w / house_w,
		"glazed_fraction": float(widest_row) * bin / house_w,
	}


## §3's measurement. How far forward the house reaches at each of its levels,
## and the step between the level under the roof and the level on the deck.
static func _brow(tris: Dictionary, h: Dictionary) -> Dictionary:
	var deck_y: float = h["deck_y"]
	var mins: Array = tris["min"]
	var maxs: Array = tris["max"]
	var fronts: Array = []
	for level in range(int(h["roof_y"]) + 1):
		var y_mid := deck_y + (float(level) + 0.5) * CELL
		var min_z := 1e9
		for i in mins.size():
			if (mins[i] as Vector3).y > y_mid or (maxs[i] as Vector3).y < y_mid:
				continue
			min_z = minf(min_z, (mins[i] as Vector3).z)
		fronts.append(snappedf(min_z, 0.001) if min_z < 1e8 else INF)
	var base: float = fronts[0] if not fronts.is_empty() else INF
	var top: float = fronts[maxi(fronts.size() - 2, 0)] if fronts.size() >= 2 else INF
	var proud := 0.0
	if is_finite(base) and is_finite(top):
		proud = base - top
	return {"brow_proud_m": proud, "level_front_z": fronts}
