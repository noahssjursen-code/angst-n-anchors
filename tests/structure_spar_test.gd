extends SceneTree

## Lane A. The two swept-tube primitives: SPAR (polyline + radius + taper) and
## WIRE (polyline + catenary sag + radius).
##
## Run:
##   xvfb-run -a --server-args="-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy \
##     --script res://tests/structure_spar_test.gd
##
## Four things are being defended, in rising order of how easy they are to fake:
##
## 1. BREADTH, not special cases. `probe_spar_kit.json` builds fourteen unrelated
##    fittings — mast, boom, raked derrick, two gallows legs, curved davit,
##    exhaust stack, goose-neck vent, stanchion, jackstaff, antenna whip, crane
##    pedestal, three-bend pipe run, wrapped handrail — from ONE `spar`
##    definition, differing only in `props`, plus five wires from one `wire`.
##    §A asserts a single triangle formula (2 * sides * nodes) predicts every one
##    of the nineteen. A part that had been special-cased would stop matching it.
##
## 2. SAG REACHES EXACTLY ZERO. Standing rigging drawn with mooring-line droop
##    reads as broken. §C asserts a zero-sag wire's path is the authored polyline
##    IDENTICALLY (`==`, not `is_equal_approx`) and that its drawn axis deviates
##    from the chord by exactly 0.0 m — and it also asserts the curve at non-zero
##    sag is a catenary and NOT a parabola, against a cosh re-derived here by a
##    bisection this file owns, so swapping in the cheap parabola goes red.
##
## 3. COST. §D measures DRAW CALLS off
##    `RenderingServer.get_rendering_info(RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)`
##    — not mesh-instance count, because one instance carrying twenty surfaces
##    costs twenty. Nineteen fittings are added to a rendered frame and the
##    counter must not move by one.
##
## 4. COLLISION, against the PHYSICS WORLD, not against dictionaries — the shape
##    of `plan_collision_physics_test`. §E builds a real StaticBody3D from
##    `collect_colliders` and marches a player-sized capsule at it. `cast_motion`
##    is never used: it returns a clean 1.0 for a shape that STARTS overlapping,
##    which reads as "walked straight through". Every march steps explicitly and
##    calls `intersect_shape` at each station, and reports `started_inside`
##    separately so a blocked-at-step-zero march can never be scored as a pass.
##
## Every "free" verdict in §E is paired with a "blocked" verdict from the same
## marcher, so neither half can be hollow: the antenna whip (under the collider
## radius floor) must be walked through while the stanchion 14 mm thicker must
## not, and the wires must be walked through while the boom above them must not.

const TestReport := preload("res://tests/support/test_report.gd")

const FIXTURE := "res://resources/data/structures/probe_spar_kit.json"

## A person, and the same marcher constants plan_collision_physics_test uses.
const CAPSULE_RADIUS := 0.3
const CAPSULE_HEIGHT := 0.8 ## total, hemispheres included
const MARCH_STEP := 0.02

## The canonical rig the triangle budget is stated against: mast, boom, two
## shrouds, a forestay and a topping lift.
const RIG_BUDGET := 500

var _t: RefCounted
var _plan: StructurePlan
var _layout: Dictionary = {}
var _body: StaticBody3D
var _space: PhysicsDirectSpaceState3D


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_t = TestReport.new("structure_spar_test")
	_layout = _load(FIXTURE)
	if not _t.check("fixture parses as a structure plan", StructurePlan.is_plan(_layout)):
		_t.finish(self)
		return
	_plan = StructurePlan.from_dict(_layout)

	_check_breadth()
	_check_spar_geometry()
	_check_wire()
	await _check_cost()
	await _check_collision()
	_t.finish(self)


func _load(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(text)
	return parsed as Dictionary if parsed is Dictionary else {}


# ── Shared helpers ───────────────────────────────────────────────────────────

## A plan holding one item and nothing else, so a single fitting's geometry can
## be measured on its own through the real bake path.
func _solo(item: Dictionary) -> StructurePlan:
	var plan := StructurePlan.new()
	plan.items = [item]
	return plan


func _instances(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for child in root.get_children():
		if child is MeshInstance3D:
			out.append(child as MeshInstance3D)
	return out


## Every baked vertex, in submission order — three per triangle, unindexed.
func _vertices(root: Node) -> PackedVector3Array:
	var out := PackedVector3Array()
	for instance in _instances(root):
		var mesh := instance.mesh as ArrayMesh
		for surface in mesh.get_surface_count():
			var arrays: Array = mesh.surface_get_arrays(surface)
			var verts: Variant = arrays[Mesh.ARRAY_VERTEX]
			if verts != null:
				out.append_array(verts as PackedVector3Array)
	return out


func _triangles(root: Node) -> int:
	return _vertices(root).size() / 3


## The item's drawn path in PLAN space, through the baker's own public entry
## points. Mirrors what _item_layers does: transform, THEN sag.
func _drawn_path(item: Dictionary) -> PackedVector3Array:
	var props := StructurePlan.item_props(item)
	var xform := _plan.item_transform(item)
	var world := PackedVector3Array()
	for point in StructureBaker.spar_path(props):
		world.append(xform * point)
	if StructureBaker.item_primitive(item) != "wire":
		return world
	var spec := props.duplicate()
	spec.erase("from")
	spec.erase("to")
	spec["points"] = world
	return StructureBaker.wire_path(spec)


func _items_of(primitive: String) -> Array:
	var out: Array = []
	for item_variant in _plan.items:
		var item := item_variant as Dictionary
		if StructureBaker.item_primitive(item) == primitive:
			out.append(item)
	return out


func _item(id: int) -> Dictionary:
	for item_variant in _plan.items:
		if int((item_variant as Dictionary).get("id", -1)) == id:
			return item_variant as Dictionary
	return {}


# ── A. Breadth: one definition, nineteen fittings, one formula ───────────────

func _check_breadth() -> void:
	var primitives: Dictionary = {}
	for item_variant in _plan.items:
		primitives[StructureBaker.item_primitive(item_variant as Dictionary)] = true
	var names: Array = primitives.keys()
	names.sort()
	print("[breadth] %d items, primitives used: %s" % [_plan.items.size(), str(names)])
	_t.check("the kit is broad enough to be evidence (%d fittings)" % _plan.items.size(),
		_plan.items.size() >= 19)
	_t.equal("every fitting in the kit is one of exactly two primitives", names, ["spar", "wire"])
	_t.check("the kit builds at least fourteen unrelated things from ONE spar definition (%d)"
		% _items_of("spar").size(), _items_of("spar").size() >= 14)

	## The formula. 2 * sides * rings triangles, capped, for every fitting —
	## sides quads per gap is 2 * sides * (rings - 1), plus a sides-triangle fan
	## at each end. Nothing is allowed its own emitter.
	var mismatched: Array = []
	var total := 0
	var per_part: Array = []
	for item_variant in _plan.items:
		var item := item_variant as Dictionary
		var props := StructurePlan.item_props(item)
		var wire := StructureBaker.item_primitive(item) == "wire"
		var sides := StructureBaker.spar_sides(
			props,
			StructureBaker.WIRE_DEFAULT_SIDES if wire else StructureBaker.SPAR_DEFAULT_SIDES
		)
		var rings := _drawn_path(item).size()
		var expected := 2 * sides * rings
		var root := StructureBaker.bake(_solo(item))
		var got := _triangles(root)
		root.free()
		total += got
		per_part.append("%d:%s=%d" % [int(item["id"]), str(props.get("__is", "?")).split(" ")[0], got])
		if got != expected:
			mismatched.append("id %d wanted %d (%d sides x %d rings) got %d"
				% [int(item["id"]), expected, sides, rings, got])
	print("[breadth] per-fitting triangles: %s" % ", ".join(PackedStringArray(per_part)))
	print("[breadth] whole kit = %d triangles" % total)
	_t.check("ONE formula (2 x sides x rings) predicts every fitting's triangle count (%d wrong: %s)"
		% [mismatched.size(), "none" if mismatched.is_empty() else str(mismatched[0])],
		mismatched.is_empty())

	## The headline number the budget was stated against.
	var mast := StructureBaker.bake(_solo(_item(20)))
	var mast_tris := _triangles(mast)
	mast.free()
	_t.equal("an 8-sided two-node mast is 32 triangles", mast_tris, 32)


# ── B. Spar geometry ────────────────────────────────────────────────────────

func _check_spar_geometry() -> void:
	## B1. Radius means radius. The gallows leg is straight and untapered, so
	## every side vertex sits exactly `radius` off the axis.
	var leg := _item(23)
	var leg_props := StructurePlan.item_props(leg)
	var radius := float(leg_props["radius"])
	var axis_x := float((leg["at"] as Array)[0])
	var axis_z := float((leg["at"] as Array)[2])
	var root := StructureBaker.bake(_solo(leg))
	var worst := 0.0
	var on_axis := 0
	for vertex in _vertices(root):
		var offset := Vector2(vertex.x - axis_x, vertex.z - axis_z).length()
		if offset < 1e-6:
			on_axis += 1 ## the two cap-fan centres
			continue
		worst = maxf(worst, absf(offset - radius))
	root.free()
	print("[spar] straight untapered leg: worst radial error %.9f m, %d cap-centre vertices"
		% [worst, on_axis])
	## Bound, not zero: mesh vertices are float32, and this leg stands at z = 22 m
	## where one ulp is already 1.9e-6 m. The error must stay inside that.
	_t.check("every side vertex of a straight untapered spar is `radius` off the axis to float32 precision (worst %.9f m)"
		% worst, worst < 4e-6)
	_t.check("both cap fans are drawn (%d centre vertices for 2 x 8 fan triangles)" % on_axis,
		on_axis == 16)

	## B2. Taper. The mast is radius 0.11 tapering to x0.55.
	var mast := _item(20)
	var mast_props := StructurePlan.item_props(mast)
	var path := StructureBaker.spar_path(mast_props)
	var radii := StructureBaker.spar_radii(mast_props, path)
	_t.near("a tapered spar starts at `radius`", radii[0], 0.11, 1e-6)
	_t.near("a tapered spar ends at `radius * taper`", radii[radii.size() - 1], 0.11 * 0.55, 1e-6)

	## B3. Taper is distributed by ARC LENGTH, not per node. A polyline whose
	## nodes bunch at one end must still taper evenly in metres: this spec's
	## middle node is 1 m along a 10 m run, so it must read 10% of the way down
	## the taper (0.9), not 50% (0.5).
	var bunched := {"points": [[0, 0, 0], [0, 1, 0], [0, 10, 0]], "radius": 1.0, "taper": 0.0}
	var bunched_path := StructureBaker.spar_path(bunched)
	var bunched_radii := StructureBaker.spar_radii(bunched, bunched_path)
	print("[spar] arc-length taper over nodes at 0 / 1 / 10 m: %s" % str(bunched_radii))
	_t.near("taper follows arc length, not node index", bunched_radii[1], 0.9, 1e-5)

	## B4. Watertight. A bent tube whose mitre left a gap, or which lost a cap,
	## has boundary edges — edges used by exactly one triangle. Every fitting in
	## the kit must have none.
	var leaky: Array = []
	for item_variant in _plan.items:
		var item := item_variant as Dictionary
		var open_edges := _boundary_edges(item)
		if open_edges != 0:
			leaky.append("id %d has %d boundary edges" % [int(item["id"]), open_edges])
	_t.check("every drawn tube is closed — no boundary edges anywhere in the kit (%d leaky: %s)"
		% [leaky.size(), "none" if leaky.is_empty() else str(leaky[0])], leaky.is_empty())

	## B5. No twist through a bend. Parallel transport keeps the cross-section
	## from spinning as the run turns; a fixed world reference vector shears it.
	## Ring vertex k on the davit must stay opposite ring vertex k on the next
	## ring — never further apart than the nodes themselves are, plus the mitre.
	var davit := _item(25)
	var davit_props := StructurePlan.item_props(davit)
	var davit_path := StructureBaker.spar_path(davit_props)
	var davit_rings := StructureBaker.tube_rings(
		davit_path,
		StructureBaker.spar_radii(davit_props, davit_path),
		StructureBaker.spar_sides(davit_props)
	)
	var worst_shear := 0.0
	for index in davit_rings.size() - 1:
		var a := davit_rings[index] as PackedVector3Array
		var b := davit_rings[index + 1] as PackedVector3Array
		var gap := davit_path[index].distance_to(davit_path[index + 1])
		for k in a.size():
			worst_shear = maxf(worst_shear, a[k].distance_to(b[k]) / maxf(gap, 1e-6))
	print("[spar] curved davit: worst ring-to-ring stretch %.4f x the node spacing" % worst_shear)
	_t.check("a curved spar's rings track its run (worst stretch %.4f x)" % worst_shear,
		worst_shear < 1.25)

	## B5b. The SHARP twist check, and it exists because the one above is blind:
	## the davit is planar, and on a planar curve "pick a perpendicular off the
	## nearest world axis" returns the constant plane normal — exactly what
	## parallel transport returns. Replacing the transport with a fixed reference
	## left the davit bit-identical and every check above green. Measured.
	##
	## So this drives a NON-PLANAR run — a helix, which is what torsion means —
	## and states the property directly: a parallel-transported frame accumulates
	## ZERO roll about its own run over the whole path. The reference frame below
	## is transported by this file's own rotation, independently of the baker's.
	var helix := PackedVector3Array()
	for step in 17:
		var angle := TAU * float(step) / 16.0
		helix.append(Vector3(1.5 * cos(angle), 4.0 * float(step) / 16.0, 1.5 * sin(angle)))
	var helix_spec := {"points": helix, "radius": 0.12, "sides": 8}
	var helix_radii := StructureBaker.spar_radii(helix_spec, helix)
	var helix_rings := StructureBaker.tube_rings(helix, helix_radii, 8)
	var expected_dir := (
		(helix_rings[0] as PackedVector3Array)[0] - helix[0]
	).normalized()
	for index in range(helix.size() - 2):
		expected_dir = _roll_free(
			expected_dir,
			(helix[index + 1] - helix[index]).normalized(),
			(helix[index + 2] - helix[index + 1]).normalized(),
		)
	var last := helix.size() - 1
	var last_run := (helix[last] - helix[last - 1]).normalized()
	var actual_dir := (helix_rings[last] as PackedVector3Array)[0] - helix[last]
	actual_dir = (actual_dir - last_run * actual_dir.dot(last_run)).normalized()
	var drift := rad_to_deg(expected_dir.angle_to(actual_dir))
	print("[spar] helix (non-planar, one full turn, 17 nodes): frame roll drift %.4f deg" % drift)
	_t.check("a non-planar spar's cross-section is parallel-transported — no roll accumulates over a full turn (%.4f deg)"
		% drift, drift < 1.0)


	## B5c. The MITRE. At an interior node both runs share one ring, and that ring
	## sits in the BISECTOR plane of the two runs. That is what keeps a bend at
	## full girth: a ring left perpendicular to the arriving run only is still
	## closed (so §B4 cannot see it) but reads as an ellipse to the outgoing run,
	## and the tube visibly pinches at every corner. Checked on the handrail,
	## whose corners are a full 90 degrees.
	var rail := _item(33)
	var rail_props := StructurePlan.item_props(rail)
	var rail_path := StructureBaker.spar_path(rail_props)
	var rail_rings := StructureBaker.tube_rings(
		rail_path,
		StructureBaker.spar_radii(rail_props, rail_path),
		StructureBaker.spar_sides(rail_props)
	)
	var off_plane := 0.0
	var corners := 0
	for index in range(1, rail_path.size() - 1):
		var arriving := (rail_path[index] - rail_path[index - 1]).normalized()
		var leaving := (rail_path[index + 1] - rail_path[index]).normalized()
		var bisector := (arriving + leaving).normalized()
		corners += 1
		for point in rail_rings[index] as PackedVector3Array:
			off_plane = maxf(off_plane, absf((point - rail_path[index]).dot(bisector)))
	print("[spar] wrapped handrail: %d corners, worst ring departure from the bisector plane %.9f m"
		% [corners, off_plane])
	_t.check("the handrail has corners to mitre (%d)" % corners, corners >= 2)
	_t.check("a bend's shared ring lies in the bisector plane, so the tube keeps its girth (%.9f m)"
		% off_plane, off_plane < 1e-6)

	## B6. Degenerate input is refused, not drawn wrong.
	_t.equal("a repeated polyline node is dropped",
		StructureBaker.spar_path({"points": [[0, 0, 0], [0, 0, 0], [0, 3, 0]]}).size(), 2)
	_t.equal("a one-node polyline draws nothing",
		StructureBaker.tube_rings(
			PackedVector3Array([Vector3.ZERO]), PackedFloat32Array([0.1]), 8).size(), 0)
	_t.equal("from/to is accepted as the two-node polyline",
		StructureBaker.spar_path({"from": [0, 0, 0], "to": [0, 4, 0]}).size(), 2)


## The minimal rotation carrying `from` onto `to`, applied to `v` — the defining
## property of parallel transport, written here so the assertion above does not
## borrow the implementation it is judging.
func _roll_free(v: Vector3, from: Vector3, to: Vector3) -> Vector3:
	var axis := from.cross(to)
	if axis.length() < 1e-9:
		return v if from.dot(to) > 0.0 else -v
	return v.rotated(axis.normalized(), from.angle_to(to))


## Edges used by an odd number of triangles, over the whole of one item's bake.
## Positions are quantised to a micrometre so two vertices that coincide compare
## equal despite float arithmetic.
func _boundary_edges(item: Dictionary) -> int:
	var root := StructureBaker.bake(_solo(item))
	var verts := _vertices(root)
	root.free()
	var counts: Dictionary = {}
	for tri in verts.size() / 3:
		var a := _key(verts[tri * 3])
		var b := _key(verts[tri * 3 + 1])
		var c := _key(verts[tri * 3 + 2])
		for edge in [_edge(a, b), _edge(b, c), _edge(c, a)]:
			counts[edge] = int(counts.get(edge, 0)) + 1
	var open_edges := 0
	for key in counts:
		if int(counts[key]) % 2 != 0:
			open_edges += 1
	return open_edges


func _key(v: Vector3) -> String:
	return "%.6f,%.6f,%.6f" % [v.x, v.y, v.z]


func _edge(a: String, b: String) -> String:
	return a + "|" + b if a < b else b + "|" + a


# ── C. Wire: sag, and the exact zero ────────────────────────────────────────

func _check_wire() -> void:
	## C1. THE requirement. A zero-sag wire is the authored polyline, untouched.
	var stay := _item(40)
	var stay_props := StructurePlan.item_props(stay)
	var authored := StructureBaker.spar_path(stay_props)
	var sagged := StructureBaker.wire_path(stay_props)
	## Guard first: both of the next two checks are satisfied by two EMPTY arrays,
	## and that is exactly how a `PackedVector3Array is Array` slip once made them
	## pass while every wire in the kit drew nothing.
	_t.check("the standing stay has an authored polyline to compare (%d nodes)" % authored.size(),
		authored.size() >= 2)
	_t.check("a zero-sag wire's path IS the authored polyline, identically",
		sagged == authored)
	_t.equal("a zero-sag wire adds no nodes", sagged.size(), authored.size())

	## ... and it lands that way in the drawn geometry, measured off the plan-space
	## path the baker actually sweeps: every node exactly on the chord.
	var drawn := _drawn_path(stay)
	if not _t.check("the standing stay is actually drawn (%d nodes in plan space)" % drawn.size(),
			drawn.size() >= 2):
		return ## everything below indexes into it; fail cleanly, not out of bounds
	var worst := 0.0
	for point in drawn:
		worst = maxf(worst, _distance_to_segment(point, drawn[0], drawn[drawn.size() - 1]))
	print("[wire] standing stay: %d nodes, worst deviation from the chord %.17f m"
		% [drawn.size(), worst])
	_t.check("standing rigging is dead straight — deviation from the chord is exactly 0.0 (%.17f)"
		% worst, worst == 0.0)

	## Zero must be reachable from BOTH directions: an absent sag key and an
	## explicit 0.0 are the same wire.
	_t.check("an absent `sag` is the same as sag 0.0",
		StructureBaker.wire_path({"points": [[0, 0, 0], [6, 0, 0]]})
			== StructureBaker.wire_path({"points": [[0, 0, 0], [6, 0, 0]], "sag": 0.0}))
	_t.equal("droop is identically zero at sag 0", StructureBaker.wire_droop(0.5, 6.0, 0.0), 0.0)

	## C2. Non-zero sag hits its number, and only in the middle.
	var mooring := _item(44)
	var mooring_props := StructurePlan.item_props(mooring)
	var sag := float(mooring_props["sag"])
	var moored := _drawn_path(mooring)
	var chord_a := moored[0]
	var chord_b := moored[moored.size() - 1]
	var deepest := 0.0
	for index in moored.size():
		var t := float(index) / float(moored.size() - 1)
		deepest = maxf(deepest, chord_a.lerp(chord_b, t).y - moored[index].y)
	print("[wire] mooring line: %d nodes, requested sag %.3f m, measured %.6f m"
		% [moored.size(), sag, deepest])
	_t.near("a slack wire droops by exactly the sag it asked for", deepest, sag, 1e-4)
	_t.check("the ends of a sagged wire are pinned to the authored endpoints",
		moored[0].is_equal_approx(chord_a) and moored[moored.size() - 1].is_equal_approx(chord_b))
	_t.equal("droop is zero at both ends",
		[StructureBaker.wire_droop(0.0, 6.0, 1.1), StructureBaker.wire_droop(1.0, 6.0, 1.1)],
		[0.0, 0.0])

	## C3. It is a CATENARY, and it is not a parabola. The reference cosh below
	## is re-derived here by this file's own bisection — nothing calls
	## StructureBaker.catenary_u — so an emitter that switched to the cheap
	## parabola fails against it. A deep span separates the two curves: at
	## sag == span they differ by 7% of the sag a quarter of the way across, well
	## outside any float tolerance.
	var span := 6.0
	var deep := 6.0
	var steps := 12
	var deep_spec := {
		"points": [[0, 0, 0], [span, 0, 0]],
		"sag": deep, "span_steps": steps, "radius": 0.02,
	}
	var curve := StructureBaker.wire_path(deep_spec)
	var worst_cat := 0.0
	var worst_par := 0.0
	for index in curve.size():
		var t := float(index) / float(steps)
		worst_cat = maxf(worst_cat, absf(-curve[index].y - _reference_catenary(t, span, deep)))
		worst_par = maxf(worst_par, absf(-curve[index].y - 4.0 * deep * t * (1.0 - t)))
	print("[wire] deep span: max error vs an independent cosh %.9f m; distance from a parabola %.4f m"
		% [worst_cat, worst_par])
	_t.check("the sag curve matches an independently solved catenary (max error %.9f m)" % worst_cat,
		worst_cat < 1e-5)
	_t.check("the sag curve is NOT a parabola (differs by %.4f m, > 0.2)" % worst_par,
		worst_par > 0.2)

	## C4. Gravity is not in the fitting's frame. A wire on an item pitched 90
	## degrees must still hang DOWN — otherwise a rotated fitting's mooring line
	## sags sideways.
	var pitched := StructurePlan.normalize_item({
		"id": 1, "item_id": "wire", "at": [0, 5, 0], "yaw": 0.0, "pitch": 90.0,
		"props": {"points": [[0, 0, 0], [6, 0, 0]], "sag": 1.0, "span_steps": 8, "radius": 0.02},
	})
	var plan := StructurePlan.new()
	plan.items = [pitched]
	var world := PackedVector3Array()
	for point in StructureBaker.spar_path(StructurePlan.item_props(pitched)):
		world.append(plan.item_transform(pitched) * point)
	var spec := (StructurePlan.item_props(pitched) as Dictionary).duplicate()
	spec["points"] = world
	var hung := StructureBaker.wire_path(spec)
	var mid := hung[hung.size() / 2]
	var chord_mid := world[0].lerp(world[1], 0.5)
	print("[wire] pitched item: chord midpoint %s, hung midpoint %s" % [str(chord_mid), str(mid)])
	_t.near("a wire on a pitched fitting still hangs straight down", chord_mid.y - mid.y, 1.0, 1e-4)
	_t.check("a wire's sag adds nothing sideways",
		absf(mid.x - chord_mid.x) < 1e-9 and absf(mid.z - chord_mid.z) < 1e-9)


## Catenary droop below the chord at t, solved here, independently of the baker.
func _reference_catenary(t: float, span: float, sag: float) -> float:
	if sag <= 0.0 or span <= 0.0:
		return 0.0
	var target := sag / span
	var low := 1e-9
	var high := 40.0
	for _i in 200:
		var mid := (low + high) * 0.5
		if (cosh(mid) - 1.0) / (2.0 * mid) < target:
			low = mid
		else:
			high = mid
	var u := (low + high) * 0.5
	var a := span / (2.0 * u)
	return a * (cosh(u) - cosh(u * (2.0 * t - 1.0)))


func _distance_to_segment(point: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var denom := ab.length_squared()
	if denom <= 0.0:
		return point.distance_to(a)
	var t := clampf((point - a).dot(ab) / denom, 0.0, 1.0)
	return point.distance_to(a + ab * t)


# ── D. Cost: draw calls off the renderer's own counter ──────────────────────

func _check_cost() -> void:
	## Mesh instances first — necessary, not sufficient.
	var full := StructureBaker.bake(_plan)
	var kit_tris := _triangles(full)
	var kit_instances := _instances(full).size()
	print("[cost] whole fixture: %d mesh instances, %d triangles"
		% [kit_instances, kit_tris])
	_t.check("the kit still bakes to at most one instance per material (%d of %d)"
		% [kit_instances, StructureBaker.MATERIALS.size()],
		kit_instances <= StructureBaker.MATERIALS.size())

	## The rig budget, on a rig: mast, boom, forestay, two shrouds, topping lift.
	var rig := StructurePlan.new()
	for id in [20, 21, 40, 41, 42, 43]:
		rig.items.append(_item(id))
	var rig_root := StructureBaker.bake(rig)
	var rig_tris := _triangles(rig_root)
	var rig_instances := _instances(rig_root).size()
	rig_root.free()
	print("[cost] rig (mast + boom + forestay + 2 shrouds + topping lift): %d triangles in %d instances"
		% [rig_tris, rig_instances])
	_t.check("a whole rig stays under %d triangles merged (%d)" % [RIG_BUDGET, rig_tris],
		rig_tris < RIG_BUDGET)

	## THE measurement. A MeshInstance3D is not a draw call — one instance
	## carrying twenty surfaces costs twenty — so this asks the renderer.
	var baseline_layout := _layout.duplicate(true)
	baseline_layout["items"] = []
	var baseline_plan := StructurePlan.from_dict(baseline_layout)
	var baseline := StructureBaker.bake(baseline_plan)

	var camera := Camera3D.new()
	root.add_child(camera)
	camera.current = true
	camera.position = Vector3(5.0, 8.0, 45.0)
	camera.look_at(Vector3(5.0, 4.0, 15.0), Vector3.UP)

	root.add_child(baseline)
	var before := await _draw_calls()
	root.remove_child(baseline)
	root.add_child(full)
	var after := await _draw_calls()
	var visible_tris := _triangles(full)
	root.remove_child(full)

	print("[cost] draw calls: %d without the %d fittings, %d with them (delta %d)"
		% [before, _plan.items.size(), after, after - before])
	_t.check("the baseline frame actually drew something (%d draw calls)" % before, before > 0)
	_t.equal("%d spars and wires add ZERO draw calls" % _plan.items.size(), after - before, 0)
	_t.check("and they did add geometry — %d triangles over the baseline's %d"
		% [visible_tris - _triangles(baseline), _triangles(baseline)],
		visible_tris - _triangles(baseline) > 700)

	baseline.free()
	full.free()
	camera.queue_free()


func _draw_calls() -> int:
	for _i in 5:
		await process_frame
	return RenderingServer.get_rendering_info(
		RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)


# ── E. Collision, against the physics world ─────────────────────────────────

func _check_collision() -> void:
	var boxes := StructureBaker.collect_colliders(_plan)
	var structure_only := StructurePlan.from_dict(_layout)
	structure_only.items = []
	var structure_boxes := StructureBaker.collect_colliders(structure_only).size()
	var item_boxes := boxes.size() - structure_boxes
	print("[collide] %d colliders total, %d from the plan's structure, %d from fittings"
		% [boxes.size(), structure_boxes, item_boxes])
	_t.check("the fittings contribute colliders (%d)" % item_boxes, item_boxes > 0)

	## Wires contribute none, ever, and neither does an opted-out spar or one
	## under the radius floor. Counted from the plan, then proved in the physics
	## world by the marches below.
	var wire_only := StructurePlan.new()
	wire_only.items = _items_of("wire")
	_t.equal("a plan of nothing but wires emits no colliders at all",
		StructureBaker.collect_colliders(wire_only).size(), 0)
	_t.check("the wire-only plan was not empty (%d wires)" % wire_only.items.size(),
		wire_only.items.size() >= 5)
	_t.equal("`solid: false` opts a decorative spar out",
		StructureBaker.collect_colliders(_solo(_item(32))).size(), 0)
	_t.equal("a spar under the collider radius floor emits nothing",
		StructureBaker.collect_colliders(_solo(_item(30))).size(), 0)
	_t.check("a spar just over the floor still emits (%d)"
		% StructureBaker.collect_colliders(_solo(_item(28))).size(),
		StructureBaker.collect_colliders(_solo(_item(28))).size() > 0)

	## The sloped derrick is the case the yaw-only contract cannot spell, so it
	## is stepped. Bounded, and the bound is measured, not asserted from the
	## constant.
	var derrick_boxes := StructureBaker.collect_colliders(_solo(_item(22)))
	print("[collide] the raked derrick steps into %d axis-aligned boxes" % derrick_boxes.size())
	_t.check("a sloped spar is stepped rather than emitted as one unrotated box (%d boxes)"
		% derrick_boxes.size(), derrick_boxes.size() >= 8)
	_t.check("the stepped boxes stay bounded (%d for a 6.0 m run)" % derrick_boxes.size(),
		derrick_boxes.size() <= 40)
	## A level run at an arbitrary heading IS exact — one box carrying a yaw.
	var boom_boxes := StructureBaker.collect_colliders(_solo(_item(21)))
	_t.equal("a level spar at any heading is one box", boom_boxes.size(), 1)
	_t.check("...carrying the run's yaw (%.3f deg)" % float((boom_boxes[0] as Dictionary)["yaw_deg"]),
		absf(float((boom_boxes[0] as Dictionary)["yaw_deg"])) > 1.0)
	var mast_boxes := StructureBaker.collect_colliders(_solo(_item(20)))
	_t.equal("a vertical spar is one box", mast_boxes.size(), 1)

	## ── Into the physics world ──
	_body = StaticBody3D.new()
	_body.name = "SparColliders"
	for index in boxes.size():
		var box := boxes[index] as Dictionary
		var shape := BoxShape3D.new()
		shape.size = box["size"] as Vector3
		var node := CollisionShape3D.new()
		node.name = "PlanCol_%d" % index
		node.shape = shape
		node.transform = Transform3D(
			Basis(Vector3.UP, deg_to_rad(float(box["yaw_deg"]))), box["center"] as Vector3
		)
		_body.add_child(node)
	root.add_child(_body)
	await physics_frame
	await physics_frame
	_space = root.world_3d.direct_space_state
	_t.equal("every collider the baker emitted is a shape on the physics body",
		PhysicsServer3D.body_get_shape_count(_body.get_rid()), boxes.size())

	## Controls first: the marcher must be able to say both words.
	var air := _march(Vector3(5.0, 20.0, 14.0), Vector3(1, 0, 0) * 3.0)
	_t.check("an open-air march is reported free",
		not bool(air["blocked"]) and not bool(air["started_inside"]))

	## A boom at head height is an obstruction; the same boom is walked under.
	## Boom runs (5.0, 2.2, 14.4) -> (7.6, 2.2, 19.8); march across it.
	var along := Vector3(2.6, 0.0, 5.4).normalized()
	var across := Vector3(along.z, 0.0, -along.x)
	var boom_mid := Vector3(6.3, 0.0, 17.1)
	var under := _march(boom_mid + Vector3(0, 1.2, 0) - across * 1.2, across * 2.4)
	var into := _march(boom_mid + Vector3(0, 2.2, 0) - across * 1.2, across * 2.4)
	print("[collide] boom: under it blocked=%s, at its height blocked=%s (started_inside %s/%s)"
		% [str(under["blocked"]), str(into["blocked"]),
			str(under["started_inside"]), str(into["started_inside"])])
	_t.check("a player walks UNDER a boom at 2.2 m", not bool(under["blocked"]))
	_t.check("...and the march that walks under it did not merely start stuck",
		not bool(under["started_inside"]))
	_t.check("a player is STOPPED by that same boom at head height", bool(into["blocked"]))
	_t.check("...and was not stuck before it moved", not bool(into["started_inside"]))

	_blocked("a mast stops a player", Vector3(3.0, 1.5, 14.0), Vector3(1, 0, 0) * 2.5)
	_blocked("a raked derrick stops a player where it actually is",
		Vector3(2.6, 3.4, 11.9), Vector3(1, 0, 0) * 3.0)
	_blocked("a 22 mm stanchion is an obstruction",
		Vector3(0.25, 1.75, 7.0), Vector3(0, 0, 1) * 2.0)

	_free("a 8 mm antenna whip is not — it is under the radius floor",
		Vector3(3.8, 10.2, 14.0), Vector3(1, 0, 0) * 2.4)
	_free("a decorative pipe run with `solid: false` is walked through",
		Vector3(8.7, 0.35, 10.0), Vector3(0, 0, 1) * 2.0)
	_free("a shroud is walked through — you duck under standing rigging",
		Vector3(1.9, 4.8, 15.0), Vector3(1, 0, 0) * 2.0)
	_free("a slack mooring line is stepped over, not walked into",
		Vector3(0.6, 1.6, 16.0), Vector3(0, 0, 1) * 4.0)

	## The wire marches are only worth anything if the wires are DRAWN where the
	## capsule passed. Otherwise "free" is free for the wrong reason.
	var shroud := _drawn_path(_item(41))
	var crossed := 999.0
	## Against the SEGMENTS, not the nodes: a zero-sag wire is two nodes eight
	## metres apart and the march crosses it in between them.
	for index in range(shroud.size() - 1):
		crossed = minf(crossed,
			_distance_to_segment(Vector3(2.9, 4.8, 15.0), shroud[index], shroud[index + 1]))
	print("[collide] nearest drawn point of the port shroud to the free march: %.3f m" % crossed)
	_t.check("the shroud really is drawn across the march that passed through it (%.3f m)" % crossed,
		crossed < CAPSULE_RADIUS)

	## No phantom: the spars must not fill the deck they stand on. Swept at SEVERAL
	## heights on purpose — a single-height sweep at 4.5 m left a de-yawed boom
	## collider (a 6 m slab lying across the deck at 2.2 m) completely undetected.
	## Measured: with the yaw dropped, one height caught 0 phantom points and this
	## band catches 27.
	var phantom := 0
	var sampled := 0
	var phantom_at := Vector3.INF
	var segments := _spar_segments()
	_t.check("the sweep knows where the spars are (%d drawn runs)" % segments.size(),
		segments.size() >= 25)
	for height in [1.6, 2.2, 3.0, 4.5, 6.0]:
		for ix in 21:
			for iz in 41:
				var point := Vector3(lerpf(0.5, 9.5, float(ix) / 20.0), float(height),
					lerpf(4.5, 25.5, float(iz) / 40.0))
				if _near_any(point, segments, 0.9):
					continue
				sampled += 1
				if _solid(point):
					phantom += 1
					if phantom_at == Vector3.INF:
						phantom_at = point
	print("[collide] %d/%d open-air samples clear of every spar are wrongly solid (first %s)"
		% [phantom, sampled, "none" if phantom_at == Vector3.INF else str(phantom_at)])
	_t.check("the phantom sweep sampled real open space (%d points)" % sampled, sampled > 3000)
	_t.equal("no point clear of every spar is solid", phantom, 0)

	_body.queue_free()


## Every drawn run of every fitting, resolved once. Recomputing the paths inside
## the sweep made it quadratic and put the sweep beyond a sane runtime.
func _spar_segments() -> Array:
	var out: Array = []
	for item_variant in _plan.items:
		var path := _drawn_path(item_variant as Dictionary)
		for index in range(path.size() - 1):
			out.append([path[index], path[index + 1]])
	return out


func _near_any(point: Vector3, segments: Array, margin: float) -> bool:
	for pair_variant in segments:
		var pair := pair_variant as Array
		if _distance_to_segment(point, pair[0] as Vector3, pair[1] as Vector3) < margin:
			return true
	return false


func _blocked(label: String, from: Vector3, motion: Vector3) -> void:
	var march := _march(from, motion)
	if bool(march["started_inside"]):
		_t.fail("%s — VACUOUS: the march began inside a collider" % label)
		return
	_t.check("%s (stopped at %.2f m of %.2f)" % [label, float(march["stop_m"]), motion.length()],
		bool(march["blocked"]))


func _free(label: String, from: Vector3, motion: Vector3) -> void:
	var march := _march(from, motion)
	if bool(march["started_inside"]):
		_t.fail("%s — VACUOUS: the march began inside a collider" % label)
		return
	_t.check("%s (walked the full %.2f m)" % [label, motion.length()], not bool(march["blocked"]))


func _solid(point: Vector3) -> bool:
	var query := PhysicsPointQueryParameters3D.new()
	query.position = point
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.collision_mask = 0xFFFFFFFF
	for hit_variant in _space.intersect_point(query, 8):
		if (hit_variant as Dictionary).get("collider") == _body:
			return true
	return false


## Explicit march. cast_motion() is never used here: it returns 1.0 for a shape
## that STARTS overlapping, which scores "began inside a mast" as "walked
## straight through it".
func _march(from: Vector3, motion: Vector3) -> Dictionary:
	var capsule := CapsuleShape3D.new()
	capsule.radius = CAPSULE_RADIUS
	capsule.height = CAPSULE_HEIGHT
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.collision_mask = 0xFFFFFFFF
	var length := motion.length()
	var steps := maxi(2, int(ceil(length / MARCH_STEP)))
	var out := {"started_inside": false, "blocked": false, "stop_m": length}
	for index in steps + 1:
		var f := float(index) / float(steps)
		query.transform = Transform3D(Basis.IDENTITY, from + motion * f)
		var overlapped := false
		for hit_variant in _space.intersect_shape(query, 8):
			if (hit_variant as Dictionary).get("collider") == _body:
				overlapped = true
				break
		if not overlapped:
			continue
		if index == 0:
			out["started_inside"] = true
			continue
		out["blocked"] = true
		out["stop_m"] = f * length
		break
	return out
