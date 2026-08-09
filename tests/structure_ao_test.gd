extends SceneTree

## Contract test for StructureAO — bake-time ambient occlusion written into
## vertex colour. Run:
##   xvfb-run -a godot --rendering-driver opengl3 --audio-driver Dummy \
##     --script res://tests/structure_ao_test.gd
##
## Every check here has been shown to go RED against a deliberately broken
## solver (see the mutants listed in the wave report); a check with no failing
## control is not evidence.

const FERRY := "res://resources/data/structures/probe_ferry_catamaran.json"
const AO_RIG := "res://resources/data/structures/probe_ao_junction.json"

## Bake budget for the largest fixture. A builder re-bakes on every edit in the
## studio, so the solver has to disappear into the frame, not be waited on.
const FERRY_BUDGET_MS := 900.0

var _failures := 0


func _check(label: String, ok: bool) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		_failures += 1


func _initialize() -> void:
	_test_open_versus_junction()
	_test_removing_the_neighbour_lightens()
	_test_flush_neighbour_does_not_darken()
	_test_overhang_underside()
	_test_bulwark_inside()
	_test_range_and_determinism()
	_test_emitter_is_drop_in()
	_test_tessellation()
	_test_rig_fixture()
	_test_ferry_budget()
	print("---")
	print("structure_ao_test: %s" % ("ALL PASS" if _failures == 0 else "%d FAILURES" % _failures))
	quit(0 if _failures == 0 else 1)


# ── Fixtures built in code, so a mutation has nowhere to hide ────────────────

## A sole plate, a wall running along X at z=2, and a wall running along Z at
## x=2 that tees into it. The tee is the tight interior junction.
func _junction_boxes(with_neighbour: bool) -> Array:
	var boxes: Array = [
		{"center": Vector3(0, -0.1, 0), "size": Vector3(8, 0.2, 8)},
		{"center": Vector3(0, 1.5, 2), "size": Vector3(6, 3, 0.3)},
	]
	if with_neighbour:
		boxes.append({"center": Vector3(2, 1.5, 0), "size": Vector3(0.3, 3, 6)})
	return boxes


## On the -Z skin of the X wall (z = 2 - 0.15), half a metre up.
const OPEN_POINT := Vector3(-2.5, 1.5, 1.85)
const JUNCTION_POINT := Vector3(1.8, 0.5, 1.85)
const FACE_NORMAL := Vector3(0, 0, -1)


func _test_open_versus_junction() -> void:
	var ao := StructureAO.from_boxes(_junction_boxes(true))
	var open := ao.occlusion_at(OPEN_POINT, FACE_NORMAL)
	var tight := ao.occlusion_at(JUNCTION_POINT, FACE_NORMAL)
	print("  occlusion open-corner=%.4f tight-junction=%.4f (ao %.4f vs %.4f)"
		% [open, tight, ao.vertex_ao(OPEN_POINT, FACE_NORMAL), ao.vertex_ao(JUNCTION_POINT, FACE_NORMAL)])
	_check("open face is unoccluded", open < 0.02)
	_check("tight junction is occluded", tight > 0.25)
	_check("junction is darker than the open face by a visible margin", tight - open > 0.2)


func _test_removing_the_neighbour_lightens() -> void:
	var with_wall := StructureAO.from_boxes(_junction_boxes(true))
	var without := StructureAO.from_boxes(_junction_boxes(false))
	var before := with_wall.occlusion_at(JUNCTION_POINT, FACE_NORMAL)
	var after := without.occlusion_at(JUNCTION_POINT, FACE_NORMAL)
	print("  same vertex, neighbouring box removed: %.4f -> %.4f" % [before, after])
	_check("removing the neighbouring box lightens the junction", after < before - 0.2)
	_check("with the neighbour gone the junction is as light as open air", after < 0.02)


func _test_flush_neighbour_does_not_darken() -> void:
	## Two wall panels either side of a doorway share a plane. A solver that
	## samples along the surface would shade the seam between them; this one
	## only samples off the surface, so the seam stays flat.
	var boxes: Array = [
		{"center": Vector3(-1, 1.5, 0), "size": Vector3(2, 3, 0.3)},
		{"center": Vector3(1, 1.5, 0), "size": Vector3(2, 3, 0.3)},
	]
	var ao := StructureAO.from_boxes(boxes)
	var seam := ao.occlusion_at(Vector3(0, 1.5, -0.15), FACE_NORMAL)
	print("  coplanar seam occlusion=%.4f" % seam)
	_check("a flush coplanar neighbour casts nothing", seam < 0.001)


func _test_overhang_underside() -> void:
	var ao := StructureAO.from_boxes([{"center": Vector3(0, 1, 0), "size": Vector3(2, 2, 2)}])
	var under := ao.occlusion_at(Vector3(0, 0, 0), Vector3(0, -1, 0))
	var over := ao.occlusion_at(Vector3(0, 2, 0), Vector3(0, 1, 0))
	print("  lone box: underside=%.4f topside=%.4f" % [under, over])
	_check("an underside is dark with nothing under it", under >= StructureAO.DOWNFACE_BIAS - 0.001)
	_check("a top face in open air is untouched", over < 0.001)
	_check("underside is darker than topside", under - over > 0.2)


func _test_bulwark_inside() -> void:
	## Deck plate plus a 1.1 m bulwark along z = 3; the inboard face is -Z.
	var ao := StructureAO.from_boxes([
		{"center": Vector3(0, -0.1, 0), "size": Vector3(10, 0.2, 10)},
		{"center": Vector3(0, 0.55, 3), "size": Vector3(10, 1.1, 0.25)},
	])
	var low := ao.occlusion_at(Vector3(0, 0.10, 2.875), FACE_NORMAL)
	var high := ao.occlusion_at(Vector3(0, 0.90, 2.875), FACE_NORMAL)
	print("  bulwark inboard face: y=0.10 -> %.4f, y=0.90 -> %.4f" % [low, high])
	_check("inside of a bulwark darkens toward the sole", low - high > 0.15)
	_check("the top of the bulwark stays light", high < 0.02)


func _test_range_and_determinism() -> void:
	var plan := _load_plan(AO_RIG)
	if plan == null:
		_check("AO rig fixture loads", false)
		return
	var a := StructureAO.for_plan(plan)
	var b := StructureAO.for_plan(plan)
	var probes: Array[Vector3] = [
		Vector3(3.0, 0.4, 3.0), Vector3(12.9, 2.4, 12.6), Vector3(8.0, 3.0, 5.0),
		Vector3(0.3, 0.2, 8.0), Vector3(6.0, 1.5, 3.0), Vector3(4.0, 0.02, 4.0),
	]
	var normals: Array[Vector3] = [
		Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, -1, 0), Vector3(0, 0, -1),
	]
	var identical := true
	var in_range := true
	var repeat_stable := true
	for point in probes:
		for normal in normals:
			var left := a.occlusion_at(point, normal)
			var right := b.occlusion_at(point, normal)
			if left != right:
				identical = false
			## Second call comes out of the memo — it must not drift.
			if a.occlusion_at(point, normal) != left:
				repeat_stable = false
			var shade := a.vertex_ao(point, normal)
			if shade < StructureAO.MIN_AO - 1e-6 or shade > 1.0 + 1e-6:
				in_range = false
	_check("two independent solvers agree bit for bit", identical)
	_check("the memo returns the value it cached", repeat_stable)
	_check("every AO factor lands in [MIN_AO, 1]", in_range)


func _test_emitter_is_drop_in() -> void:
	## Empty occluder set: AO is 1 everywhere, so only geometry is compared.
	var ao := StructureAO.from_boxes([])
	var mine := SurfaceTool.new()
	mine.begin(Mesh.PRIMITIVE_TRIANGLES)
	var triangles := ao.append_box(mine, Vector3(1, 2, 3), Vector3(0.3, 0.4, 0.5))
	_check("a sub-TESSEL box still costs 12 triangles", triangles == 12)
	var mesh := mine.commit()
	var arrays: Array = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	_check("the emitter carries a vertex colour channel", colors.size() == verts.size())
	## Intrinsic winding check, independent of the baker: Godot front faces wind
	## CLOCKWISE, so the right-hand cross of the vertex order is MINUS the
	## outward normal (tests/winding_probe.gd).
	var winding_ok := verts.size() > 0
	for tri in verts.size() / 3:
		var p0 := verts[tri * 3]
		var p1 := verts[tri * 3 + 1]
		var p2 := verts[tri * 3 + 2]
		var rh := (p1 - p0).cross(p2 - p0).normalized()
		if rh.dot(norms[tri * 3]) > -0.99:
			winding_ok = false
	_check("clockwise-front winding is preserved on every triangle", winding_ok)
	## Exact equivalence with the baker's own emitter, when it is reachable.
	if _baker_has("_append_box"):
		var theirs := SurfaceTool.new()
		theirs.begin(Mesh.PRIMITIVE_TRIANGLES)
		StructureBaker._append_box(theirs, Vector3(1, 2, 3), Vector3(0.3, 0.4, 0.5), Basis.IDENTITY)
		var ref_arrays: Array = theirs.commit().surface_get_arrays(0)
		var ref_verts: PackedVector3Array = ref_arrays[Mesh.ARRAY_VERTEX]
		var ref_norms: PackedVector3Array = ref_arrays[Mesh.ARRAY_NORMAL]
		var same := ref_verts.size() == verts.size()
		if same:
			for i in verts.size():
				if verts[i] != ref_verts[i] or norms[i] != ref_norms[i]:
					same = false
					break
		_check("append_box reproduces StructureBaker._append_box vertex for vertex", same)
	else:
		_check("StructureBaker._append_box is still reachable for the drop-in comparison", false)


func _test_tessellation() -> void:
	## A 6 m plate against a wall: the plate's top face has to carry a gradient,
	## which it cannot do with four vertices.
	var boxes: Array = [
		{"center": Vector3(0, -0.1, 0), "size": Vector3(6, 0.2, 6)},
		{"center": Vector3(0, 1.5, 3.15), "size": Vector3(6, 3, 0.3)},
	]
	var ao := StructureAO.from_boxes(boxes)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var triangles := ao.append_box(st, Vector3(0, -0.1, 0), Vector3(6, 0.2, 6))
	_check("a plate face wider than TESSEL is subdivided", triangles > 12)
	var arrays: Array = st.commit().surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var top_min := 1.0
	var top_max := 0.0
	for i in verts.size():
		if absf(verts[i].y - 0.0) > 1e-4:
			continue
		top_min = minf(top_min, colors[i].r)
		top_max = maxf(top_max, colors[i].r)
	print("  plate top face: %d triangles, AO %.4f .. %.4f" % [triangles, top_min, top_max])
	_check("the plate top face carries an AO gradient", top_max - top_min > 0.05)
	_check("the far end of the plate is unshaded", top_max > 0.999)


func _test_rig_fixture() -> void:
	var plan := _load_plan(AO_RIG)
	if plan == null:
		_check("probe_ao_junction.json parses as a plan", false)
		return
	_check("probe_ao_junction.json parses as a plan", plan.walls.size() == 6 and plan.decks.size() == 2)
	var ao := StructureAO.for_plan(plan)
	## The free-standing post: an upper corner of its +X face, in clear air.
	var post_corner := ao.occlusion_at(Vector3(13.5, 2.3, 12.1), Vector3(1, 0, 0))
	## The inside of the L, on wall 11's +X skin right where wall 10 tees in.
	var tee := ao.occlusion_at(Vector3(3.125, 0.6, 3.5), Vector3(1, 0, 0))
	## The overhang underside, out where only the sky term reaches it.
	var overhang := ao.occlusion_at(Vector3(11.0, 3.0, 5.0), Vector3(0, -1, 0))
	print("  rig: open post corner=%.4f  L-junction=%.4f  overhang underside=%.4f"
		% [post_corner, tee, overhang])
	_check("rig: the free-standing post corner is open", post_corner < 0.02)
	_check("rig: the L junction is the darkest of the three", tee > overhang and tee > post_corner)
	_check("rig: the overhang underside is darker than an open corner", overhang > post_corner + 0.2)


func _test_ferry_budget() -> void:
	var plan := _load_plan(FERRY)
	if plan == null:
		_check("ferry fixture loads", false)
		return
	var start := Time.get_ticks_usec()
	var ao := StructureAO.for_plan(plan)
	var built := Time.get_ticks_usec()
	var result := _shade_plan(plan, ao)
	var done := Time.get_ticks_usec()
	var stats := ao.stats()
	print("  ferry: %d occluder boxes, %d grid cells, %d render boxes, %d triangles"
		% [int(stats["boxes"]), int(stats["cells"]), int(result["boxes"]), int(result["triangles"])])
	print("  ferry: %d AO queries (%d solved, %d memoised) via %s"
		% [int(stats["queries"]), int(stats["solved"]), int(stats["queries"]) - int(stats["solved"]), result["path"]])
	print("  ferry: solver build %.1f ms, shaded emission %.1f ms, total %.1f ms"
		% [(built - start) / 1000.0, (done - built) / 1000.0, (done - start) / 1000.0])
	_check("ferry AO bake stays inside the studio budget", float(done - start) / 1000.0 < FERRY_BUDGET_MS)
	_check("ferry shading actually ran", int(result["triangles"]) > 1000 and int(stats["solved"]) > 1000)


# ── Helpers ──────────────────────────────────────────────────────────────────

func _load_plan(path: String) -> StructurePlan:
	if not FileAccess.file_exists(path):
		return null
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary) or not StructurePlan.is_plan(parsed as Dictionary):
		return null
	return StructurePlan.from_dict(parsed as Dictionary)


func _baker_has(method: String) -> bool:
	for entry in (StructureBaker as GDScript).get_script_method_list():
		if str((entry as Dictionary).get("name", "")) == method:
			return true
	return false


## Emits every render box of the plan through the AO emitter, the way the baker
## will once the call site lands. Prefers the baker's own layer decomposition
## (two-sided skins and opening frames included); falls back to the solid box
## set if those statics are ever renamed, and says which path it took.
func _shade_plan(plan: StructurePlan, ao: StructureAO) -> Dictionary:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var expanded := StructureBaker.expand(plan)
	var boxes := 0
	var triangles := 0
	var layered := _baker_has("_wall_layers") and _baker_has("_plate_layers") and _baker_has("_stair_layers")
	if layered:
		var wall_default := StructureBaker.DEFAULT_WALL_COLOR
		var deck_default := StructureBaker.DEFAULT_DECK_COLOR
		for wall_variant in expanded["walls"] as Array:
			for layer_variant in StructureBaker._wall_layers(wall_variant as Dictionary, wall_default):
				var layer := layer_variant as Dictionary
				boxes += 1
				triangles += ao.append_box(
					st, layer["center"] as Vector3, layer["size"] as Vector3,
					layer.get("basis", Basis.IDENTITY) as Basis,
				)
		for deck_variant in expanded["decks"] as Array:
			for layer_variant in StructureBaker._plate_layers(deck_variant as Dictionary, wall_default, deck_default):
				var layer := layer_variant as Dictionary
				boxes += 1
				triangles += ao.append_box(st, layer["center"] as Vector3, layer["size"] as Vector3)
		for stair_variant in expanded["stairs"] as Array:
			for layer_variant in StructureBaker._stair_layers(stair_variant as Dictionary, deck_default):
				var layer := layer_variant as Dictionary
				boxes += 1
				triangles += ao.append_box(st, layer["center"] as Vector3, layer["size"] as Vector3)
	else:
		for box_variant in StructureBaker.collect_colliders(plan):
			var box := box_variant as Dictionary
			boxes += 1
			triangles += ao.append_box(
				st, box["center"] as Vector3, box["size"] as Vector3,
				Basis(Vector3.UP, deg_to_rad(float(box.get("yaw_deg", 0.0)))),
			)
	return {"boxes": boxes, "triangles": triangles, "path": "layers" if layered else "colliders"}
