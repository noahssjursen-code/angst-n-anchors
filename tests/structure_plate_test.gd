extends SceneTree

## Lane A. THE SLOPED PLATE — the primitive that replaced the room.
##
## Run:
##   xvfb-run -a --server-args="-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy \
##     --script res://tests/structure_plate_test.gd
##
## A room was an axis-aligned box that expanded to four walls, a floor and a
## ceiling, so every deckhouse it drew was a shed. The replacement is a quad with
## FOUR INDEPENDENT 3D CORNERS and a thickness. Six things are defended here, in
## rising order of how easy they are to fake:
##
## 1. BREADTH, not special cases. `probe_plate_deckhouse.json` builds eighteen
##    unrelated things from ONE plate definition — a deckhouse tapered in plan and
##    tumbled home, a raked front, a set-back upper tier, a raked windscreen, a
##    sloped roof, a funnel taper, a bulwark knuckle, a transom rake — differing
##    only in `props`. §A asserts a single triangle formula
##    (4·su·sv + 4·(su+sv) per panel) predicts every one of them.
##
## 2. THE CORNERS ARE INDEPENDENT. §B shows the drawn surface passing exactly
##    through all four authored corners, including a corner moved off the plane of
##    the other three — the case a box cannot express at all — and shows the
##    result is watertight.
##
## 3. OPENINGS WORK ON IT. A deckhouse side with no windows is not a deckhouse.
##    §B checks the holes are real in the geometry and §F checks every one of the
##    fixture's twenty-four is real in the PHYSICS WORLD too.
##
## 4. DEGENERATE INPUT FAILS LOUDLY. §C. Coplanar corners are the normal case;
##    collinear ones, a coincident pair, a bow tie, a non-finite corner and a
##    non-positive thickness are each named and each draw nothing.
##
## 5. COST. §D measures DRAW CALLS off
##    `RenderingServer.get_rendering_info(RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)`
##    — not mesh-instance count, because one instance carrying twenty surfaces
##    costs twenty. Eighteen plates in six colours must cost exactly what one
##    plate costs.
##
## 6. COLLISION, against the PHYSICS WORLD, not against dictionaries — the shape
##    of `plan_collision_physics_test`. §E/§F build a real StaticBody3D from
##    `collect_colliders` and march a player-sized capsule at it. `cast_motion` is
##    never used: it returns a clean 1.0 for a shape that STARTS overlapping,
##    which reads as "walked straight through". Every march steps explicitly and
##    calls `intersect_shape` at each station, and reports `started_inside`
##    separately, so a blocked-at-step-zero march is scored VACUOUS and never as a
##    pass.
##
## The collision half is where a raked plate is easiest to get wrong, so every
## claim there is PAIRED with its opposite from the same marcher: the raked front
## stops a player FURTHER FORWARD at head height than at knee height (a de-raked
## box gives the same answer at both); the sloped roof is solid at 4.82 m forward
## and open air at 4.82 m aft; a door is walked through and the bulkhead beside it
## is not.

const TestReport := preload("res://tests/support/test_report.gd")

const FIXTURE := "res://resources/data/structures/probe_plate_deckhouse.json"

## A person, and the same marcher constants plan_collision_physics_test uses.
const CAPSULE_RADIUS := 0.3
const CAPSULE_HEIGHT := 0.8 ## total, hemispheres included
const MARCH_STEP := 0.02

## Fixture ids, so the assertions below read as the thing they are about.
const ID_FRONT := 100        ## lower tier, raked front — 0.45 m over 2.4 m
const ID_PORT := 101         ## lower tier, port side — tapered and tumbled home
const ID_AFT := 103          ## lower tier, aft bulkhead — carries the deck door
const ID_BOATDECK := 104
const ID_SCREEN := 105       ## wheelhouse windscreen — 0.85 m of forward rake
const ID_ROOF := 109         ## wheelhouse roof — 0.25 m down from stem to aft
const ID_TRANSOM := 117

var _t: RefCounted
var _plan: StructurePlan
var _layout: Dictionary = {}
var _body: StaticBody3D
var _space: PhysicsDirectSpaceState3D


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_t = TestReport.new("structure_plate_test")
	_layout = _load(FIXTURE)
	if not _t.check("fixture parses as a structure plan", StructurePlan.is_plan(_layout)):
		_t.finish(self)
		return
	_plan = StructurePlan.from_dict(_layout)

	_check_wall_panels_did_not_move()
	_check_breadth()
	_check_geometry()
	_check_degenerate()
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

func _solo(item: Dictionary) -> StructurePlan:
	var plan := StructurePlan.new()
	plan.items = [item]
	return plan


func _item(id: int) -> Dictionary:
	for item_variant in _plan.items:
		if int((item_variant as Dictionary).get("id", -1)) == id:
			return item_variant as Dictionary
	return {}


func _props(id: int) -> Dictionary:
	return StructurePlan.item_props(_item(id))


## The plate's corners in PLAN space — the item's own frame applied, which is
## what the baker draws and what the colliders are fitted to.
func _corners(id: int) -> PackedVector3Array:
	var item := _item(id)
	var xform := _plan.item_transform(item)
	var out := PackedVector3Array()
	for point in StructureBaker.plate_corners(StructurePlan.item_props(item)):
		out.append(xform * point)
	return out


func _instances(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for child in root.get_children():
		if child is MeshInstance3D:
			out.append(child as MeshInstance3D)
	return out


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


## Triangles a plate spec must bake to. Panels and frame members are the same
## emitter; only the panels carry the subdivision.
func _expected_triangles(spec: Dictionary) -> int:
	var s := StructureBaker.plate_segments(spec)
	var per_panel := 4 * s * s + 4 * (s + s)
	return StructureBaker.plate_panels(spec).size() * per_panel \
		+ StructureBaker.plate_frames(spec).size() * 12


## A plate item, built RAW rather than through `StructurePlan.normalize_item`.
## That is deliberate: `normalize_item` runs every prop through `_f()`, which
## rewrites a non-finite float to 0.0, so a NaN corner is silently repaired
## before the baker ever sees it. Going raw is the only way to ask whether the
## BAKER refuses degenerate input, which is what §C is about.
func _plate_item(spec: Dictionary, id := 1) -> Dictionary:
	return {"id": id, "item_id": "plate", "at": [0, 0, 0], "yaw": 0.0, "props": spec}


func _bake_spec(spec: Dictionary) -> Node3D:
	return StructureBaker.bake(_solo(_plate_item(spec)))


# ── 0. The refactor this primitive needed, pinned ──────────────────────────
#
# Plates reuse the WALL opening subtraction rather than growing a second one:
# `wall_panels` became a thin wrapper over `_panels_between`, and `plate_panels`
# calls the same routine in the metre lengths of its own edges. That is a change
# to load-bearing code every wall in the game runs through, so its output is
# pinned here against rectangles worked out by hand — not against the function
# itself. Every in-tree consumer (plan_collision_test, plan_collision_physics_
# test, structure_circulation_test, structure_bake_budget_test) also stayed green
# across it; this is the assertion that says WHY.

func _check_wall_panels_did_not_move() -> void:
	## A 6 m x 3 m wall with a door (offset 1, width 0.9, sill 0, height 2.2) and
	## a window (offset 3.5, width 1.2, sill 1, height 1.2). By hand: the run
	## splits at 0..1, the door column contributes only its header 2.2..3, the gap
	## 1.9..3.5, the window contributes 0..1 under it and 2.2..3 over it, and the
	## tail runs 4.7..6.
	var wall := {
		"start": [0, 0, 0], "axis": "x", "length": 6.0, "height": 3.0, "thickness": 0.2,
		"openings": [
			{"type": "door", "offset": 1.0, "width": 0.9, "sill": 0.0, "height": 2.2},
			{"type": "window", "offset": 3.5, "width": 1.2, "sill": 1.0, "height": 1.2},
		],
	}
	var expected := [
		{"u0": 0.0, "u1": 1.0, "v0": 0.0, "v1": 3.0},
		{"u0": 1.0, "u1": 1.9, "v0": 2.2, "v1": 3.0},
		{"u0": 1.9, "u1": 3.5, "v0": 0.0, "v1": 3.0},
		{"u0": 3.5, "u1": 4.7, "v0": 0.0, "v1": 1.0},
		{"u0": 3.5, "u1": 4.7, "v0": 2.2, "v1": 3.0},
		{"u0": 4.7, "u1": 6.0, "v0": 0.0, "v1": 3.0},
	]
	var got := StructureBaker.wall_panels(wall)
	_t.equal("wall_panels still returns the same six rectangles", got.size(), expected.size())
	var worst := 0.0
	for index in mini(got.size(), expected.size()):
		for key in ["u0", "u1", "v0", "v1"]:
			worst = maxf(worst, absf(
				float((got[index] as Dictionary)[key]) - float((expected[index] as Dictionary)[key])))
	_t.check("...at the same coordinates, worked out by hand (worst %.9f)" % worst, worst < 1e-9)
	## And the plate does the SAME subtraction, normalised — a window half way
	## along a 6 m plate comes back at u 0.5, not at u 3.
	var plate := {
		"corners": [[0, 0, 0], [6, 0, 0], [6, 3, 0], [0, 3, 0]], "thickness": 0.2,
		"openings": [{"type": "window", "offset": 2.4, "width": 1.2, "sill": 1.0, "height": 1.2}],
	}
	var panels := StructureBaker.plate_panels(plate)
	_t.equal("a plate with one window decomposes into four panels", panels.size(), 4)
	if panels.size() == 4:
		_t.near("...whose first ends at the window, in NORMALISED u",
			float((panels[0] as Dictionary)["u1"]), 0.4, 1e-9)
		_t.near("...and whose under-sill panel tops out at the sill, normalised",
			float((panels[1] as Dictionary)["v1"]), 1.0 / 3.0, 1e-9)


# ── A. Breadth: eighteen unrelated things, one formula ──────────────────────

func _check_breadth() -> void:
	var primitives: Dictionary = {}
	for item_variant in _plan.items:
		primitives[StructureBaker.item_primitive(item_variant as Dictionary)] = true
	var names: Array = primitives.keys()
	names.sort()
	print("[breadth] %d items, primitives used: %s" % [_plan.items.size(), str(names)])
	_t.check("the deckhouse is broad enough to be evidence (%d plates)" % _plan.items.size(),
		_plan.items.size() >= 15)
	_t.equal("every part of the deckhouse is ONE primitive", names, ["plate"])

	var openings := 0
	var raked := 0
	var tapered := 0
	for item_variant in _plan.items:
		var spec := StructurePlan.item_props(item_variant as Dictionary)
		openings += (spec.get("openings", []) as Array).size()
		var c := StructureBaker.plate_corners(spec)
		if c.size() == 4:
			## Raked: the two v-edges are not vertical. Tapered: the two u-edges
			## differ in length. Neither is expressible as a box.
			var up0 := (c[3] - c[0]).normalized()
			if absf(up0.dot(Vector3.UP)) < 0.999 and absf(up0.dot(Vector3.UP)) > 0.001:
				raked += 1
			if absf(c[0].distance_to(c[1]) - c[3].distance_to(c[2])) > 0.02:
				tapered += 1
	print("[breadth] %d openings, %d plates raked, %d plates tapered" % [openings, raked, tapered])
	_t.check("the deckhouse carries real openings (%d)" % openings, openings >= 20)
	_t.check("plates are actually RAKED, not upright boxes (%d)" % raked, raked >= 6)
	_t.check("plates are actually TAPERED, not rectangles (%d)" % tapered, tapered >= 6)

	## The formula. Nothing is allowed its own emitter.
	var mismatched: Array = []
	var total := 0
	for item_variant in _plan.items:
		var item := item_variant as Dictionary
		var spec := StructurePlan.item_props(item)
		var expected := _expected_triangles(spec)
		var root := StructureBaker.bake(_solo(item))
		var got := _triangles(root)
		root.free()
		total += got
		if got != expected:
			mismatched.append("id %d wanted %d got %d" % [int(item["id"]), expected, got])
	print("[breadth] whole deckhouse = %d triangles" % total)
	_t.check("ONE formula (4·su·sv + 4·(su+sv) per panel) predicts every plate (%d wrong: %s)"
		% [mismatched.size(), "none" if mismatched.is_empty() else str(mismatched[0])],
		mismatched.is_empty())

	## ... including at a subdivision the fixture never uses, so the formula is
	## not a coincidence of segments == 1.
	var flat := {"corners": [[0, 0, 0], [4, 0, 0], [4, 3, 0], [0, 3, 0]], "thickness": 0.1}
	var one := _bake_spec(flat)
	_t.equal("a plain plate is 12 triangles — exactly a box, which is what a flat plate is",
		_triangles(one), 12)
	one.free()
	for segments in [2, 3, 4]:
		var spec := flat.duplicate(true)
		spec["segments"] = segments
		var root := _bake_spec(spec)
		var got := _triangles(root)
		root.free()
		_t.equal("segments %d bakes to 4·s² + 8·s triangles" % segments,
			got, 4 * segments * segments + 8 * segments)


# ── B. Geometry: four independent corners, watertight, genuinely holed ──────

func _check_geometry() -> void:
	## B1. The drawn surface passes through the authored corners. Measured on the
	## boat deck, which has no openings, so its single panel IS the whole plate.
	var deck_spec := _props(ID_BOATDECK)
	var deck_corners := _corners(ID_BOATDECK)
	var thickness := StructureBaker.plate_thickness(deck_spec)
	var normal := StructureBaker.plate_normal(deck_corners)
	var root := StructureBaker.bake(_solo(_item(ID_BOATDECK)))
	var verts := _vertices(root)
	root.free()
	var worst := 0.0
	for index in 4:
		for side in [1.0, -1.0]:
			var wanted: Vector3 = deck_corners[index] + normal * (thickness * 0.5 * float(side))
			var nearest := INF
			for vertex in verts:
				nearest = minf(nearest, vertex.distance_to(wanted))
			worst = maxf(worst, nearest)
	print("[plate] boat deck: worst distance from an authored corner to a baked vertex %.9f m"
		% worst)
	## Bound, not zero: mesh vertices are float32 and this plate sits at z = 24 m,
	## where one ulp is already 1.9e-6 m.
	_t.check("every authored corner appears in the baked geometry, both skins (worst %.9f m)"
		% worst, worst < 4e-6)

	## B2. FOUR INDEPENDENT CORNERS. Move one corner off the plane of the other
	## three — the case an axis-aligned box cannot express at all — and the drawn
	## surface still passes through all four and stays closed.
	var twisted := {
		"corners": [[0, 0, 0], [4, 0, 0], [4.3, 2.6, -0.7], [0, 3, 0]],
		"thickness": 0.08, "segments": 3,
	}
	var twisted_corners := StructureBaker.plate_corners(twisted)
	var plane_normal := (twisted_corners[1] - twisted_corners[0]).cross(
		twisted_corners[3] - twisted_corners[0]).normalized()
	var out_of_plane := absf((twisted_corners[2] - twisted_corners[0]).dot(plane_normal))
	_t.check("the twisted plate really is non-planar (%.3f m out of plane)" % out_of_plane,
		out_of_plane > 0.3)
	_t.equal("a non-planar quad is accepted, not refused", StructureBaker.plate_problem(twisted), "")
	var twisted_root := _bake_spec(twisted)
	var twisted_verts := _vertices(twisted_root)
	twisted_root.free()
	## The offset direction is the quad's own area normal, re-derived here so the
	## assertion does not borrow the function it is judging.
	var twisted_normal := (twisted_corners[2] - twisted_corners[0]).cross(
		twisted_corners[3] - twisted_corners[1]).normalized()
	var twist_worst := 0.0
	for corner in twisted_corners:
		for side in [1.0, -1.0]:
			var wanted: Vector3 = corner + twisted_normal * (0.04 * float(side))
			var nearest := INF
			for vertex in twisted_verts:
				nearest = minf(nearest, vertex.distance_to(wanted))
			twist_worst = maxf(twist_worst, nearest)
	_t.check("a twisted plate is drawn through all four of its corners, both skins (worst %.6f m)"
		% twist_worst, twist_worst < 1e-5)
	_t.equal("a twisted plate is closed — no boundary edges", _boundary_edges(twisted), 0)

	## B3. Watertight, everywhere in the fixture. An opening that left a panel's
	## skirt off, or a mitre that missed, shows up as an edge used once.
	var leaky: Array = []
	for item_variant in _plan.items:
		var item := item_variant as Dictionary
		var open_edges := _boundary_edges(StructurePlan.item_props(item))
		if open_edges != 0:
			leaky.append("id %d has %d boundary edges" % [int(item["id"]), open_edges])
	_t.check("every plate in the deckhouse is closed (%d leaky: %s)"
		% [leaky.size(), "none" if leaky.is_empty() else str(leaky[0])], leaky.is_empty())

	## B4. Openings are HOLES, not decals — and the probe is a RAY through the
	## surface, not a search for nearby vertices. A vertex search passes on a
	## plate that ignores openings entirely: at one segment a panel carries
	## vertices only at its own corners, so a full-plate panel has none inside the
	## window it failed to cut. Measured — that mutant left this check green.
	##
	## Each probe is a 0.24 m segment along the plate normal through a point on
	## the mid-surface. Inside a clear opening it must hit NOTHING; a jamb-width
	## plus a margin to the side of it, it must hit the plate.
	var filled := 0
	var missing := 0
	var checked := 0
	var probes := 0
	for id in [ID_FRONT, ID_PORT, ID_AFT, ID_SCREEN]:
		var spec := _props(id)
		var corners := _corners(id)
		var ref := StructureBaker.plate_ref_lengths(StructureBaker.plate_corners(spec))
		var face := (corners[2] - corners[0]).cross(corners[3] - corners[1]).normalized()
		## Baked through the ITEM, so the triangles are in plan space like the
		## probe points. Baking the bare spec puts them in the item's own frame,
		## 5 m off the centreline — which silently made every probe miss, and the
		## "nothing inside an opening" half read green because of it. That is why
		## the "beside it IS drawn" half below exists.
		var tris := _triangle_list_of(_item(id))
		var openings := StructureBaker.plate_openings(spec, ref)
		for opening in openings:
			checked += 1
			## Held clear of the jamb frames, which straddle the cut edge by half
			## of PLATE_FRAME_WIDTH and are supposed to be there.
			var inset := StructureBaker.PLATE_FRAME_WIDTH * 0.5 + 0.05
			var u0 := (float(opening["off"]) + inset) / ref.x
			var u1 := (float(opening["off"]) + float(opening["w"]) - inset) / ref.x
			var v0 := (float(opening["sill"]) + inset) / ref.y
			var v1 := (float(opening["sill"]) + float(opening["h"]) - inset) / ref.y
			for iu in 5:
				for iv in 5:
					probes += 1
					var point := StructureBaker.plate_point(
						corners, lerpf(u0, u1, iu / 4.0), lerpf(v0, v1, iv / 4.0))
					if _surface_at(tris, point, face):
						filled += 1
			## The paired half, so "no surface here" cannot be passing because
			## the plate was never drawn at all.
			var side_u := float(opening["off"]) + float(opening["w"]) + inset + 0.12
			if side_u > ref.x - 0.05 or _in_an_opening(openings, side_u):
				side_u = float(opening["off"]) - inset - 0.12
			if side_u < 0.05 or _in_an_opening(openings, side_u):
				continue
			var v_mid := float(opening["sill"]) + float(opening["h"]) * 0.5
			if not _surface_at(tris, StructureBaker.plate_point(
					corners, side_u / ref.x, v_mid / ref.y), face):
				missing += 1
	print("[plate] %d openings, %d rays through their clear area hit geometry %d times; %d sides bare"
		% [checked, probes, filled, missing])
	_t.check("the fixture supplied openings to check (%d)" % checked, checked >= 10)
	_t.equal("nothing is drawn inside a clear opening — they are holes", filled, 0)
	_t.equal("...and the plate beside each opening IS drawn, so the probe can see plating",
		missing, 0)


## Every triangle of one plate item's bake, in PLAN space, as [a, b, c] triples.
func _triangle_list_of(item: Dictionary) -> Array:
	var root := StructureBaker.bake(_solo(item))
	var verts := _vertices(root)
	root.free()
	var out: Array = []
	for tri in verts.size() / 3:
		out.append([verts[tri * 3], verts[tri * 3 + 1], verts[tri * 3 + 2]])
	return out


## Is any drawn triangle within 0.12 m of `point` along `normal`? A segment probe
## rather than a vertex search — see B4.
func _surface_at(tris: Array, point: Vector3, normal: Vector3) -> bool:
	var from := point - normal * 0.12
	var to := point + normal * 0.12
	for tri_variant in tris:
		var tri := tri_variant as Array
		if Geometry3D.segment_intersects_triangle(
				from, to, tri[0] as Vector3, tri[1] as Vector3, tri[2] as Vector3) != null:
			return true
	return false


## Edges used an odd number of times over one plate spec's whole bake.
func _boundary_edges(spec: Dictionary) -> int:
	var root := _bake_spec(spec)
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
	return "%.5f,%.5f,%.5f" % [v.x, v.y, v.z]


func _edge(a: String, b: String) -> String:
	return a + "|" + b if a < b else b + "|" + a


# ── C. Degenerate input fails loudly ────────────────────────────────────────

func _check_degenerate() -> void:
	## Each case: the reason plate_problem gives, the substring that reason must
	## contain, and — the part that matters — the bake emitting NOTHING.
	var cases := [
		[{"corners": [[0, 0, 0], [1, 0, 0], [1, 1, 0]]}, "4 corners", "three corners"],
		[{"corners": [[0, 0, 0], [1, 0, 0], [2, 0, 0], [3, 0, 0]]}, "collinear",
			"four corners on one line"],
		[{"corners": [[0, 0, 0], [3, 0, 0], [1, 0, 0], [2, 0, 0]]}, "collinear",
			"four collinear corners out of order"],
		[{"corners": [[0, 0, 0], [1, 0, 0], [0, 1, 0], [1, 1, 0]]}, "self-crossing",
			"a bow tie made by swapping the last two corners"],
		[{"corners": [[0, 0, 0], [2, 0, 0], [0, 1, 0], [1, 1, 0]]}, "self-crossing",
			"a bow tie whose diagonals are not parallel"],
		[{"corners": [[0, 0, 0], [1, 0, 0], [1, 0, 0.00001], [0, 1, 0]]}, "coincide",
			"a coincident corner pair"],
		[{"corners": [[0, 0, 0], [1, 0, 0], [1, 1, 0], [0, 1, NAN]]}, "not finite",
			"a non-finite corner"],
		[{"corners": [[0, 0, 0], [1, 0, 0], [1, 1, 0], [0, 1, 0]], "thickness": 0.0},
			"thickness", "zero thickness"],
		[{"corners": [[0, 0, 0], [0.004, 0, 0], [0.004, 0.004, 0], [0, 0.004, 0]]}, "zero area",
			"a 4 mm square — under the area floor"],
	]
	for case_variant in cases:
		var case := case_variant as Array
		var spec := case[0] as Dictionary
		var wanted: String = str(case[1])
		var label: String = str(case[2])
		var problem := StructureBaker.plate_problem(spec)
		_t.check("%s is refused, and the reason says so (\"%s\")" % [label, problem],
			problem.containsn(wanted))
		var root := _bake_spec(spec)
		var tris := _triangles(root)
		root.free()
		_t.equal("%s draws nothing at all" % label, tris, 0)
		_t.equal("%s emits no collider either" % label,
			StructureBaker.collect_colliders(_solo(_plate_item(spec))).size(), 0)

	## The control: the same quad in ring order is accepted and drawn, so the
	## refusals above are about the input and not about the checker saying no to
	## everything.
	var good := {"corners": [[0, 0, 0], [1, 0, 0], [1, 1, 0], [0, 1, 0]], "thickness": 0.05}
	_t.equal("a well-formed quad has no problem", StructureBaker.plate_problem(good), "")
	var good_root := _bake_spec(good)
	var good_tris := _triangles(good_root)
	good_root.free()
	_t.equal("...and it draws", good_tris, 12)
	## Coplanar is the NORMAL case, not a defect — this is the whole fixture.
	_t.equal("a flat plate is accepted (coplanar corners are not degenerate)",
		StructureBaker.plate_problem(_props(ID_TRANSOM)), "")


# ── D. Cost: draw calls off the renderer's own counter ─────────────────────

func _check_cost() -> void:
	var colors: Dictionary = {}
	var materials: Dictionary = {}
	for item_variant in _plan.items:
		var spec := StructurePlan.item_props(item_variant as Dictionary)
		colors[str(spec.get("color", []))] = true
		materials[str(spec.get("material", "painted"))] = true
	print("[cost] the deckhouse uses %d distinct colours across %d materials"
		% [colors.size(), materials.size()])
	_t.check("the deckhouse spends colour freely (%d distinct)" % colors.size(),
		colors.size() >= 5)

	var full := StructureBaker.bake(_plan)
	var full_instances := _instances(full).size()
	print("[cost] whole fixture: %d mesh instances, %d triangles"
		% [full_instances, _triangles(full)])
	_t.check("the deckhouse bakes to at most one instance per material (%d of %d)"
		% [full_instances, StructureBaker.MATERIALS.size()],
		full_instances <= StructureBaker.MATERIALS.size())

	## THE measurement. A MeshInstance3D is not a draw call — one instance
	## carrying twenty surfaces costs twenty — so this asks the renderer.
	##
	## The baseline is ONE plate carrying ONE opening, which is every material
	## bucket the full deckhouse can reach: plate skins are "painted" and opening
	## frames are "steel". Eighteen plates, twenty-four openings and six colours
	## must therefore cost exactly what that one plate costs. Putting colour back
	## into the bucket key — the regression this exists to prevent — takes the
	## delta from 0 to 5.
	var baseline_layout := _layout.duplicate(true)
	baseline_layout["items"] = [_item(ID_AFT).duplicate(true)]
	var baseline_plan := StructurePlan.from_dict(baseline_layout)
	var baseline := StructureBaker.bake(baseline_plan)

	var camera := Camera3D.new()
	root.add_child(camera)
	camera.current = true
	camera.position = Vector3(5.0, 9.0, 46.0)
	camera.look_at(Vector3(5.0, 2.5, 18.0), Vector3.UP)

	root.add_child(baseline)
	var before := await _draw_calls()
	root.remove_child(baseline)
	root.add_child(full)
	var after := await _draw_calls()
	root.remove_child(full)

	print("[cost] draw calls: %d with one plate, %d with all %d (delta %d)"
		% [before, after, _plan.items.size(), after - before])
	_t.check("the baseline frame actually drew something (%d draw calls)" % before, before > 0)
	_t.equal("%d plates in %d colours add ZERO draw calls over one plate"
		% [_plan.items.size(), colors.size()], after - before, 0)
	_t.check("and they did add geometry — %d triangles over the baseline's %d"
		% [_triangles(full) - _triangles(baseline), _triangles(baseline)],
		_triangles(full) - _triangles(baseline) > 1500)
	baseline.free()
	full.free()
	camera.queue_free()


func _draw_calls() -> int:
	for _i in 5:
		await process_frame
	return RenderingServer.get_rendering_info(
		RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)


# ── E. Collision, against the physics world ────────────────────────────────

func _check_collision() -> void:
	## E1. An upright axis-aligned plate is ONE box, exactly. The staircase must
	## cost nothing when there is nothing to step — this is the claim that stops
	## the rake handling from being paid for by every flat plate in the game.
	var upright := {"corners": [[0, 0, 0], [6, 0, 0], [6, 2.5, 0], [0, 2.5, 0]], "thickness": 0.2}
	var upright_boxes := StructureBaker.collect_colliders(_solo(_plate_item(upright)))
	_t.equal("an upright rectangular plate is exactly ONE collider", upright_boxes.size(), 1)
	if upright_boxes.size() == 1:
		var box := upright_boxes[0] as Dictionary
		_t.check("...whose size is the drawn slab (%s)" % str(box["size"]),
			(box["size"] as Vector3).is_equal_approx(Vector3(6.0, 2.5, 0.2)))
		_t.check("...centred on it (%s)" % str(box["center"]),
			(box["center"] as Vector3).is_equal_approx(Vector3(3.0, 1.25, 0.0)))
	## Level and at an arbitrary heading is still one box — that is what the yaw
	## in the collider contract is for.
	var yawed := {"corners": [[0, 0, 0], [4, 0, 3], [4, 2.5, 3], [0, 2.5, 0]], "thickness": 0.2}
	var yawed_boxes := StructureBaker.collect_colliders(_solo(_plate_item(yawed)))
	_t.equal("a plate at an arbitrary heading is still one box", yawed_boxes.size(), 1)
	if yawed_boxes.size() == 1:
		_t.check("...carrying the run's yaw (%.2f deg)"
			% float((yawed_boxes[0] as Dictionary)["yaw_deg"]),
			absf(float((yawed_boxes[0] as Dictionary)["yaw_deg"]) + 36.87) < 0.05)
	## A 45 degree plate — a bow bulwark — is the case the yaw exists for, and the
	## cost of losing it is stated as a NUMBER rather than as a phantom: every box
	## here is the exact bounding box in ITS OWN frame, so a de-yawed emitter still
	## contains the geometry. What it does instead is shred one exact box into
	## thirty-two padded ones. Measured: dropping the yaw takes this from 1 to 32.
	var diagonal := {
		"corners": [[0, 0, 0], [6, 0, 6], [6, 2.5, 6], [0, 2.5, 0]], "thickness": 0.2,
	}
	var diagonal_boxes := StructureBaker.collect_colliders(_solo(_plate_item(diagonal)))
	_t.equal("a 45 degree plate is ONE box, not a staircase", diagonal_boxes.size(), 1)
	if diagonal_boxes.size() == 1:
		var diag := diagonal_boxes[0] as Dictionary
		_t.near("...carrying -45 deg of yaw", float(diag["yaw_deg"]), -45.0, 0.01)
		_t.check("...and sized as the drawn slab, not as its bounding box (%s)"
			% str(diag["size"]),
			(diag["size"] as Vector3).is_equal_approx(Vector3(sqrt(72.0), 2.5, 0.2)))

	## Cost. Colliders are shapes on a real physics body, so the staircase has to
	## stay affordable for a whole deckhouse, not only for one plate.
	var plan_boxes := StructureBaker.collect_colliders(_plan).size()
	print("[collide] the whole deckhouse is %d collider boxes for %d plates"
		% [plan_boxes, _plan.items.size()])
	_t.check("the whole deckhouse stays under 400 collider boxes (%d)" % plan_boxes,
		plan_boxes < 400)

	## E2. A raked plate is STEPPED, and the step count tracks the rake rather
	## than the size. Both bounds measured, not asserted from the constant.
	var screen_boxes := StructureBaker.collect_colliders(_solo(_item(ID_SCREEN)))
	var roof_boxes := StructureBaker.collect_colliders(_solo(_item(ID_ROOF)))
	print("[collide] windscreen -> %d boxes, sloped roof -> %d boxes, upright control -> 1"
		% [screen_boxes.size(), roof_boxes.size()])
	## The step count is tied to the rake and to PLATE_COLLIDER_STEP, stated on a
	## plate with NO openings so the number cannot be coming from the panel
	## decomposition: 0.9 m of rake over a 0.15 m step is six boxes.
	var bare_rake := {
		"corners": [[0, 0, 0], [4, 0, 0], [4, 2.4, -0.9], [0, 2.4, -0.9]], "thickness": 0.09,
	}
	var bare_boxes := StructureBaker.collect_colliders(_solo(_plate_item(bare_rake)))
	_t.equal("0.9 m of rake at a %.2f m step is exactly %d boxes"
		% [StructureBaker.PLATE_COLLIDER_STEP, 6], bare_boxes.size(), 6)
	_t.check("the raked windscreen is stepped, not one unrotated box (%d)" % screen_boxes.size(),
		screen_boxes.size() >= 10)
	_t.check("the sloped roof is stepped too (%d)" % roof_boxes.size(), roof_boxes.size() >= 2)
	_t.check("stepping stays bounded (%d boxes for a 4 x 2.4 m windscreen)" % screen_boxes.size(),
		screen_boxes.size() <= 60)

	## E3. Containment, over EVERY plate: the collider never under-covers the
	## geometry. Sampled on the drawn surface and on both skins, because that is
	## what the convex-hull argument in plate_colliders() claims.
	var all_boxes := StructureBaker.collect_colliders(_plan)
	var uncovered := 0
	var sampled := 0
	var uncovered_at := Vector3.INF
	## Per PANEL, with the PANEL's own normal. Several of these plates are
	## genuinely non-planar — the lower tier tapers differently at deck level and
	## at the boat deck, which twists both sides — so the whole plate's normal is
	## not the direction any one panel is extruded along. Sampling with it tests
	## points the baker never draws (measured: 73 false uncovered).
	for item_variant in _plan.items:
		var item := item_variant as Dictionary
		var spec := StructurePlan.item_props(item)
		var corners := _corners(int(item["id"]))
		var thickness := StructureBaker.plate_thickness(spec)
		for panel_variant in StructureBaker.plate_panels(spec):
			var panel := panel_variant as Dictionary
			var quad := StructureBaker.plate_subquad(
				corners, float(panel["u0"]), float(panel["u1"]),
				float(panel["v0"]), float(panel["v1"]))
			var half := (quad[2] - quad[0]).cross(quad[3] - quad[1]).normalized() * thickness * 0.5
			for iu in 7:
				for iv in 7:
					var mid := StructureBaker.plate_point(quad, iu / 6.0, iv / 6.0)
					for side in [half, -half, Vector3.ZERO]:
						sampled += 1
						if _in_any_box(all_boxes, mid + (side as Vector3)):
							continue
						uncovered += 1
						if uncovered_at == Vector3.INF:
							uncovered_at = mid + (side as Vector3)
	print("[collide] %d/%d sampled surface points lie outside every emitted collider"
		% [uncovered, sampled])
	_t.check("the containment sweep sampled the whole deckhouse (%d points)" % sampled,
		sampled > 5000)
	_t.check("no drawn point of any plate is outside its colliders (%d/%d, first %s)"
		% [uncovered, sampled, "none" if uncovered_at == Vector3.INF else str(uncovered_at)],
		uncovered == 0)

	## ── Into the physics world ──
	_body = StaticBody3D.new()
	_body.name = "PlateColliders"
	for index in all_boxes.size():
		var box := all_boxes[index] as Dictionary
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
		PhysicsServer3D.body_get_shape_count(_body.get_rid()), all_boxes.size())

	## Control: the marcher must be able to say "free".
	var air := _march(Vector3(5.0, 12.0, 10.0), Vector3(0, 0, 1) * 4.0)
	_t.check("an open-air march is reported free",
		not bool(air["blocked"]) and not bool(air["started_inside"]))

	_check_open_deck_is_open()
	_check_rake_is_where_it_is_drawn()
	_check_no_phantom_under_the_overhang()
	_check_slope_is_followed()
	_check_openings_are_holes()

	_body.queue_free()


## E3b. Nothing the deckhouse emits may reach the open working deck. This is the
## general form of the phantom check and it is what catches a collider that lost
## its YAW: the bulwark knuckle is a 21.5 m plate running fore-and-aft, so
## de-yawing its box turns it into a 21.5 m slab lying ACROSS the hull at
## knee-to-chest height over the whole working deck. Measured: dropping the yaw
## fills 3 465 of the samples below, and leaves every other check in this file
## green except the one-box count.
func _check_open_deck_is_open() -> void:
	var solid := 0
	var sampled := 0
	var first := Vector3.INF
	for ix in 21:
		for iy in 15:
			for iz in 21:
				## Forward working deck: clear of the house (z >= 14.5), of both
				## bulwarks and their knuckles (x <= 0.5 and x >= 9.5), and of the
				## transom. Nothing in this plan may be solid here.
				var point := Vector3(
					lerpf(1.5, 8.5, ix / 20.0),
					lerpf(0.3, 2.0, iy / 14.0),
					lerpf(6.0, 13.5, iz / 20.0),
				)
				sampled += 1
				if not _solid(point):
					continue
				solid += 1
				if first == Vector3.INF:
					first = point
	print("[deck] %d/%d open-deck samples are wrongly solid (first %s)"
		% [solid, sampled, "none" if first == Vector3.INF else str(first)])
	_t.check("the open-deck sweep sampled real space (%d points)" % sampled, sampled > 5000)
	_t.equal("no part of the deckhouse reaches the open working deck", solid, 0)


## E4. THE RAKE. The lower tier's front leans 0.45 m forward over its 2.4 m, so a
## player walking aft is stopped FURTHER FORWARD at head height than at knee
## height. One unrotated box round the plate — the thing this staircase exists to
## avoid — gives the identical answer at both heights, and this check is the one
## that goes red for it.
func _check_rake_is_where_it_is_drawn() -> void:
	var start_z := 13.0
	var run := 3.0
	## x = 5.0 is the full-height column between the front's two windows.
	var low := _march(Vector3(5.0, 0.55, start_z), Vector3(0, 0, 1) * run)
	var high := _march(Vector3(5.0, 1.95, start_z), Vector3(0, 0, 1) * run)
	print("[rake] knee-height march stopped at z=%.3f, head-height at z=%.3f (rake 0.45 m over 2.4 m)"
		% [start_z + float(low["stop_m"]), start_z + float(high["stop_m"])])
	if bool(low["started_inside"]) or bool(high["started_inside"]):
		_t.fail("the rake marches are VACUOUS — one began inside a collider")
		return
	_t.check("a player is stopped by the raked front at knee height", bool(low["blocked"]))
	_t.check("a player is stopped by the raked front at head height", bool(high["blocked"]))
	var lead := float(low["stop_m"]) - float(high["stop_m"])
	_t.check(
		"the head-height march is stopped %.3f m FURTHER FORWARD — the collider follows the rake"
		% lead, lead > 0.10 and lead < 0.45
	)


## E5. ... and the space the rake's overhang adds is NOT solid. The forward-raked
## front overhangs the deck; one unrotated box would fill the wedge of air under
## the overhang and stop a player a quarter-metre short of a wall they can see
## they have not reached. Sampled only where the drawn plate demonstrably is not.
func _check_no_phantom_under_the_overhang() -> void:
	## The front is planar: z = 15.0 - 0.1875·y in plan space, half-thickness
	## 0.046 m in z. Everything forward of that by a clear margin is open deck.
	## MARGIN. The staircase over-covers on purpose, by at most
	## PLATE_COLLIDER_STEP (0.15 m) plus the plate's own half-thickness in z
	## (0.046 m) — see plate_colliders(). 0.22 m clears that and nothing more, so
	## this sweep still fails the moment the steps get coarser than they claim.
	var margin := 0.22
	var phantom := 0
	var checked := 0
	var phantom_at := Vector3.INF
	for ix in 25:
		var x := lerpf(3.2, 6.8, ix / 24.0)
		for iy in 31:
			var y := lerpf(0.1, 2.3, iy / 30.0)
			var surface_z := 15.0 - 0.1875 * y
			for iz in 11:
				var z := lerpf(14.50, surface_z - margin, iz / 10.0)
				if z >= surface_z - margin:
					continue
				checked += 1
				if not _solid(Vector3(x, y, z)):
					continue
				phantom += 1
				if phantom_at == Vector3.INF:
					phantom_at = Vector3(x, y, z)
	print("[phantom] %d/%d points forward of the raked front are wrongly solid (first %s)"
		% [phantom, checked, "none" if phantom_at == Vector3.INF else str(phantom_at)])
	_t.check("the phantom sweep sampled the wedge the overhang adds (%d points)" % checked,
		checked > 1500)
	_t.equal("no point forward of the drawn raked front is solid", phantom, 0)


## E6. THE SLOPE. The wheelhouse roof falls 0.25 m from stem to aft, so one
## height is roof forward and open air aft. A single slab makes both solid.
func _check_slope_is_followed() -> void:
	var forward := Vector3(5.0, 4.82, 18.0)
	var aft := Vector3(5.0, 4.82, 21.6)
	var under_aft := Vector3(5.0, 4.60, 21.6)
	print("[slope] at y=4.82: forward solid=%s, aft solid=%s; at y=4.60 aft solid=%s"
		% [str(_solid(forward)), str(_solid(aft)), str(_solid(under_aft))])
	_t.check("4.82 m above the deck is INSIDE the roof at its forward end", _solid(forward))
	_t.check("the same height is OPEN AIR aft, because the roof slopes away", not _solid(aft))
	_t.check("...and 0.22 m lower, aft, is inside the roof again", _solid(under_aft))


## E7. Every opening is a genuine hole in COLLISION, not only in the picture, and
## the plate beside it is not. Both halves from the same probe.
func _check_openings_are_holes() -> void:
	var open_solid := 0
	var open_total := 0
	var wall_solid := 0
	var wall_total := 0
	var first_blocked := Vector3.INF
	for item_variant in _plan.items:
		var item := item_variant as Dictionary
		var spec := StructurePlan.item_props(item)
		var corners := _corners(int(item["id"]))
		var ref := StructureBaker.plate_ref_lengths(StructureBaker.plate_corners(spec))
		var openings := StructureBaker.plate_openings(spec, ref)
		for opening in openings:
			var u := float(opening["off"]) + float(opening["w"]) * 0.5
			var v := float(opening["sill"]) + float(opening["h"]) * 0.5
			open_total += 1
			var centre := StructureBaker.plate_point(corners, u / ref.x, v / ref.y)
			if _solid(centre):
				open_solid += 1
				if first_blocked == Vector3.INF:
					first_blocked = centre
			## The paired half: the same height, one jamb-width plus a margin to
			## the side, where the plate is supposed to be solid. Skipped when
			## that lands off the plate or inside a neighbouring opening.
			var beside := u + float(opening["w"]) * 0.5 + 0.28
			if beside > ref.x - 0.05 or _in_an_opening(openings, beside):
				beside = u - float(opening["w"]) * 0.5 - 0.28
			if beside < 0.05 or beside > ref.x - 0.05 or _in_an_opening(openings, beside):
				continue
			wall_total += 1
			if _solid(StructureBaker.plate_point(corners, beside / ref.x, v / ref.y)):
				wall_solid += 1
	print("[openings] %d/%d opening centres are solid; %d/%d points beside them are solid"
		% [open_solid, open_total, wall_solid, wall_total])
	_t.check("the fixture supplied openings to probe (%d)" % open_total, open_total >= 20)
	_t.equal("every opening is a genuine hole in collision (%d blocked, first %s)"
		% [open_solid, "none" if first_blocked == Vector3.INF else str(first_blocked)],
		open_solid, 0)
	## Without this the check above passes on a plate that emits no colliders at
	## all, which is the cheapest possible way to fake "the doors are open".
	_t.check("the plate BESIDE each opening is solid (%d/%d) — the holes are cut, not missing"
		% [wall_solid, wall_total], wall_total >= 15 and wall_solid == wall_total)

	## And a person actually walks through the deck door: 1.10 m wide, 1.95 m
	## tall, in the lower tier's aft bulkhead.
	var door_x := _door_centre_x()
	var through := _march(Vector3(door_x, 0.55, 25.6), Vector3(0, 0, -1) * 2.4)
	var beside_door := _march(Vector3(door_x - 1.6, 0.55, 25.6), Vector3(0, 0, -1) * 2.4)
	print("[door] centre x=%.3f: through blocked=%s (start inside %s); beside blocked=%s"
		% [door_x, str(through["blocked"]), str(through["started_inside"]),
			str(beside_door["blocked"])])
	if bool(through["started_inside"]) or bool(beside_door["started_inside"]):
		_t.fail("the door marches are VACUOUS — one began inside a collider")
		return
	_t.check("a player walks through the deck door", not bool(through["blocked"]))
	_t.check("...and is stopped by the bulkhead 1.6 m to port of it", bool(beside_door["blocked"]))


func _in_an_opening(openings: Array, u: float) -> bool:
	for opening in openings:
		if u > float(opening["off"]) - 0.1 and u < float(opening["off"]) + float(opening["w"]) + 0.1:
			return true
	return false


## Plan-space x of the deck door's centre, read off the plate rather than typed.
func _door_centre_x() -> float:
	var spec := _props(ID_AFT)
	var corners := _corners(ID_AFT)
	var ref := StructureBaker.plate_ref_lengths(StructureBaker.plate_corners(spec))
	var opening := StructureBaker.plate_openings(spec, ref)[0] as Dictionary
	var u := float(opening["off"]) + float(opening["w"]) * 0.5
	return StructureBaker.plate_point(corners, u / ref.x, 0.3 / ref.y).x


# ── Physics probes. cast_motion() is never used — see the header ────────────

func _in_any_box(boxes: Array, point: Vector3) -> bool:
	for box_variant in boxes:
		var box := box_variant as Dictionary
		var delta := point - (box["center"] as Vector3)
		var yaw := deg_to_rad(float(box.get("yaw_deg", 0.0)))
		if not is_zero_approx(yaw):
			delta = delta.rotated(Vector3.UP, -yaw)
		var half := (box["size"] as Vector3) * 0.5 + Vector3.ONE * 1e-4
		if absf(delta.x) <= half.x and absf(delta.y) <= half.y and absf(delta.z) <= half.z:
			return true
	return false


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
