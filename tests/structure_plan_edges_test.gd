extends SceneTree

## `edges[]` AS A FIRST-CLASS PART OF A PLAN.
##
## Run (SceneTree lane — StructurePlan, StructureBaker, StructureEdge,
## HullStations, HullFormProfile, HullCatalog and DeckGrid are all `class_name`
## scripts with no autoload dependency, and nothing here names a vessel script):
##
##   timeout 300 xvfb-run -a --server-args="-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy \
##     --script res://tests/structure_plan_edges_test.gd
##
## ── What this file is for ───────────────────────────────────────────────────
## `StructureEdge` could sweep a profile along a polyline, and
## `sheer_bulwark_spec` could assemble a whole sheered bulwark for a hull, and
## none of it could reach a vessel: `StructureBaker` did not read `edges[]`, so
## the sheer fixtures needed a throwaway capture rig of their own to be seen at
## all. That rig is gone. What replaced it is a seam, and a seam is exactly the
## thing that looks finished from either side while being broken in the middle.
##
## So the claims here are the seam's, not the primitive's — `structure_sheer_test`
## already owns the geometry:
##   • an edge COUNTS, SERIALISES, REHYDRATES and is ADDRESSABLE like every other
##     plan entity, and a plan carrying one still round-trips byte-stably;
##   • `from_hull` RESOLVES through `sheer_bulwark_spec`, so the curve is derived
##     per hull and a fixture never holds a copy of it;
##   • the resolved run arrives in the PLAN FRAME, standing on the deck, rather
##     than 5.72 m up in ship-local metres where `HullStations` speaks;
##   • `bake()` emits it into the SAME merged surfaces — no new draw call;
##   • `collect_colliders()` emits its colliders, and they COVER what was drawn,
##     which is the property that makes drawing and collision impossible to
##     drift apart;
##   • an edge can HOST a fitting, on a path that is not a straight line.
##
## Whether the result LOOKS like a boat is judged by looking, at
## screenshots/studio/probe_sheer_bulwark__*.png against
## screenshots/studio/probe_sheer_bulwark_flat__*.png. There is deliberately no
## silhouette metric here; one was written and binned for passing three vessels
## the owner had just called unrecognisable.
##
## MUTATION-VERIFIED. Every check below was watched going RED against a
## deliberately broken baker / plan; the mutants and both numbers are in the
## wave report.

const TestReport := preload("res://tests/support/test_report.gd")

const FIXTURE := "res://resources/data/structures/probe_sheer_bulwark.json"
const CONTROL := "res://resources/data/structures/probe_sheer_bulwark_flat.json"

var _t: RefCounted


func _initialize() -> void:
	_t = TestReport.new("structure_plan_edges_test")

	_test_an_edge_is_a_plan_entity()
	_test_from_hull_resolves_through_the_spec()
	_test_the_run_lands_in_the_plan_frame()
	_test_bake_emits_edges_into_the_same_surfaces()
	_test_colliders_are_the_drawing()
	_test_an_edge_can_host_a_fitting()

	_t.finish(self)


# ── 1. An edge is a plan entity ─────────────────────────────────────────────

## Counted, serialised, rehydrated, addressable, removable. Five verbs, and a
## primitive that only does four of them is the kind of half-landed seam that
## shows up as an editor bug a wave later.
func _test_an_edge_is_a_plan_entity() -> void:
	var plan := StructurePlan.new()
	_t.check("a fresh plan is empty", plan.is_empty() and plan.entity_count() == 0)

	var wall := plan.add_wall(Vector3.ZERO, "x", 4.0)
	var edge := plan.add_edge(
		[[0.0, 1.0, 0.0], [8.0, 1.0, 0.0], [8.0, 1.0, 6.0]],
		{"profile": "cap_rail", "material": "wood"}
	)
	var edge_id := int(edge["id"])
	_t.equal("an edge is counted alongside the wall", plan.entity_count(), 2)
	_t.check("a plan holding only an edge is not empty", not plan.is_empty())
	_t.check("ids are unique across collections", edge_id != int(wall["id"]))

	_t.equal("the edge is found by id", plan.entity_kind_by_id(edge_id), "edge")
	_t.equal(
		"entity_by_id returns the edge itself",
		int(plan.entity_by_id(edge_id).get("id", -1)), edge_id
	)

	var text := JSON.stringify(plan.to_dict())
	_t.check("edges survive serialisation", text.contains("\"edges\""))
	var reloaded := StructurePlan.from_dict(JSON.parse_string(text) as Dictionary)
	_t.equal("edges rehydrate", reloaded.edges.size(), 1)
	_t.equal("the rehydrated edge keeps its count", reloaded.entity_count(), 2)
	_t.equal(
		"the rehydrated edge keeps its id as an int",
		typeof((reloaded.edges[0] as Dictionary)["id"]), TYPE_INT
	)
	## JSON hands integers back as floats; a plan that re-serialises 1 as "1.0"
	## is not byte-stable and every diff of it is noise.
	_t.check(
		"a plan with an edge round-trips byte-stably",
		JSON.stringify(reloaded.to_dict())
		== JSON.stringify(StructurePlan.from_dict(reloaded.to_dict()).to_dict())
	)
	## An id allocated after a reload must not collide with the edge's.
	_t.check(
		"the id counter clears the edge",
		int(reloaded.add_wall(Vector3.ZERO, "x", 2.0)["id"]) > edge_id
	)

	_t.check("the edge is removable by id", plan.remove_entity(edge_id))
	_t.equal("removing it drops the count", plan.entity_count(), 1)
	_t.check("and it is gone from edges[]", plan.edges.is_empty())
	_t.equal("a removed edge has no kind", plan.entity_kind_by_id(edge_id), "")


# ── 2. from_hull resolves through sheer_bulwark_spec ────────────────────────

## The one thing a fixture may not do is write out a hull's sheer as a list of
## points: the curve is `freeboard x the form's own bow keel rise`, so a copy is
## stale the moment anyone retunes `fine_entry`.
##
## Two claims. The resolved spec must be the one `sheer_bulwark_spec` produces —
## checked by rebuilding it independently from the plan's own stations rather
## than by trusting the key. And the CONTROL, which differs by one boolean, must
## come out flat: without that, "the curve is carried" would pass on a resolver
## that ignored `follow_sheer` and drew the sheer for both.
func _test_from_hull_resolves_through_the_spec() -> void:
	var plan := _plan(FIXTURE)
	var control := _plan(CONTROL)
	if plan == null or control == null:
		return
	_t.equal("the fixture is a hull and one edge", plan.edges.size(), 1)

	var stations := plan.hull_stations()
	if not _t.check("the plan lofts its hull without a vessel script", stations != null):
		return
	_t.check(
		"the hull's own sheer is non-zero (%.3f m forward, %.3f m aft)"
		% [stations.sheer_forward_m, stations.sheer_aft_m],
		stations.sheer_forward_m > 0.0
	)

	var edge := plan.edges[0] as Dictionary
	var spec := plan.edge_spec(edge)
	if not _t.check("the from_hull edge resolves to a spec", not spec.is_empty()):
		return

	## Independently: the same call `structure_edge.gd` documents, brought into
	## the plan frame by the same public conversion.
	var grid := plan.hull_grid()
	var expected := StructureEdge.sheer_bulwark_spec(stations, edge)
	var wanted := PackedVector3Array()
	for point in (expected["path"] as PackedVector3Array):
		wanted.append(StructurePlan.local_to_plan(point, grid))
	_t.equal("the resolved path is sheer_bulwark_spec's", (spec["path"] as PackedVector3Array).size(), wanted.size())
	var worst := 0.0
	for i in wanted.size():
		worst = maxf(worst, (spec["path"] as PackedVector3Array)[i].distance_to(wanted[i]))
	_t.near("every resolved point matches it (worst %.6f m)" % worst, worst, 0.0, 1e-5)

	## The curve itself, off the drawn band rather than off the spec.
	var rise := _band_rise(plan)
	var flat := _band_rise(control)
	_t.check(
		"the drawn band carries the sheer (%.3f m of rise over its run)" % rise,
		rise > 0.5
	)
	_t.check("the control is flat (%.4f m of rise)" % flat, flat < 1e-3)

	## The band's highest point is the stem and its lowest is amidships, so the
	## rise it carries is the hull's FORWARD sheer — 0.896 m here, and DERIVED:
	## freeboard 2.8 m x `fine_entry`'s own bow keel rise 0.32. Nothing in the
	## fixture says 0.896, and retuning the form preset moves both sides of this.
	##
	## Exactly, on the resolved path, whose end sample sits on the stem:
	var lo := INF
	var hi := -INF
	for point in (spec["path"] as PackedVector3Array):
		lo = minf(lo, point.y)
		hi = maxf(hi, point.y)
	_t.near(
		"the resolved run rises by the hull's own forward sheer",
		hi - lo, stations.sheer_forward_m, 1e-4
	)

	## And on the DRAWN boxes, which is the claim that matters and which cannot
	## be exact — a box is measured at its centre and the curve is steepest at
	## the stem, so the last segment's centre is half a segment short of the peak.
	## That shortfall is a computable quantity, not a fudge: `sheer_rise_at` is
	## rise·(|z|/(L/2))², so its slope peaks at 2·rise/(L/2), and half a segment
	## of it is the most the measurement can lose.
	var segment := stations.length_m / float(int(spec.get("samples", 2)) - 1)
	var lost := (2.0 * stations.sheer_forward_m / (stations.length_m * 0.5)) * segment * 0.5
	_t.check(
		"the drawn cap rises by it too (%.4f m, sheer %.4f, at most %.4f lost to sampling)"
		% [rise, stations.sheer_forward_m, lost],
		absf(rise - stations.sheer_forward_m) <= lost + 1e-4
	)

	## An authored path is its own spec and must NOT be rewritten.
	var hand := StructurePlan.new()
	var hand_edge := hand.add_edge([[0.0, 0.0, 0.0], [4.0, 0.0, 0.0]], {"width": 0.2, "thickness": 0.1})
	_t.check(
		"an edge that writes its own path is passed through untouched",
		hand.edge_spec(hand_edge) == hand_edge
	)


# ── 3. The run lands in the plan frame ─────────────────────────────────────

## `HullStations` speaks SHIP-LOCAL metres and a plan speaks plan metres, and on
## this hull they are 5.72 m apart vertically and half a beam / half a length
## apart laterally. A bulwark resolved and not converted renders perfectly, in
## the sky, above a hull it is no longer attached to — and at capture resolution
## an object in the wrong place still looks like an object.
func _test_the_run_lands_in_the_plan_frame() -> void:
	var plan := _plan(FIXTURE)
	if plan == null:
		return
	var stations := plan.hull_stations()
	var spec := plan.edge_spec(plan.edges[0] as Dictionary)
	if spec.is_empty():
		return
	var path := spec["path"] as PackedVector3Array
	var edge := plan.edges[0] as Dictionary
	var height := float(edge.get("height", StructureEdge.DEFAULT_BULWARK_HEIGHT))

	var lo := Vector3.INF
	var hi := -Vector3.INF
	for point in path:
		lo = lo.min(point)
		hi = hi.max(point)
	## Plan space runs 0..beam and 0..loa from the grid's corner, and the band is
	## inset half its plating so its outboard face is flush with the shell.
	var inset := float(edge.get("plate_m", StructureEdge.DEFAULT_BULWARK_PLATE_M)) * 0.5
	_t.near("the run starts at the stem (z = 0)", lo.z, 0.0, 1e-3)
	_t.near("and ends at the transom (z = loa)", hi.z, stations.length_m, 1e-3)
	_t.near("port edge is inset half a plate", lo.x, inset, 1e-3)
	_t.near("starboard edge likewise", hi.x, stations.beam_m - inset, 1e-3)

	## The cap AMIDSHIPS is the one authored length, measured from the deck the
	## builder stands on — not from the keel and not from `HullStations.deck_y`.
	_t.near(
		"the cap amidships stands `height` above the build plane",
		lo.y, height - StructurePlan.BUILD_PLANE_M, 1e-3
	)
	_t.near(
		"and at the stem it stands `height` + the hull's forward sheer",
		hi.y, height + stations.sheer_forward_m - StructurePlan.BUILD_PLANE_M, 1e-3
	)
	## The plating stands on the shell top, which is BUILD_PLANE_M below plan
	## zero — so it runs up under the deck plate and leaves no slot to see the
	## sea through at its foot.
	_t.near("the plating stands on the shell, under the deck plate",
		float(spec["base_y"]), -StructurePlan.BUILD_PLANE_M, 1e-6)


# ── 4. bake() emits edges, into the same surfaces ──────────────────────────

## Colour is free and a MATERIAL is a draw call. A 76 m bulwark loop in two
## colours on one material must add geometry to a bucket the plan already had,
## never a bucket of its own — that is the whole reason `_bucket_layer` keys on
## material alone, and the easiest place in the codebase to forget it.
func _test_bake_emits_edges_into_the_same_surfaces() -> void:
	var plan := _plan(FIXTURE)
	if plan == null:
		return
	var edge := (plan.edges[0] as Dictionary).duplicate(true)
	var boxes := StructureBaker.edge_boxes(plan, edge)
	if not _t.check("the edge draws (%d boxes)" % boxes.size(), boxes.size() > 0):
		return

	var baked := StructureBaker.bake(plan)
	var surfaces := _meshes(baked)
	_t.equal("a hull-and-bulwark plan bakes to one surface", surfaces.size(), 1)
	var drawn := 0
	for mesh in surfaces:
		drawn += _triangles(mesh)
	_t.equal(
		"and every triangle of the edge is in it",
		drawn, StructureEdge.triangle_count(boxes)
	)
	baked.free()

	## Same plan with the edge removed: the surface disappears entirely, which is
	## the honest form of "the edge is what put geometry there".
	var bare := _plan(FIXTURE)
	bare.edges.clear()
	var bare_baked := StructureBaker.bake(bare)
	_t.equal("without the edge the plan bakes to nothing", _meshes(bare_baked).size(), 0)
	bare_baked.free()

	## A second edge on the SAME material adds triangles and no surface.
	var twin := _plan(FIXTURE)
	twin.edges.append(_recoloured(edge, twin.allocate_id()))
	var twin_baked := StructureBaker.bake(twin)
	var twin_surfaces := _meshes(twin_baked)
	_t.equal("a second edge in another colour is still one surface", twin_surfaces.size(), 1)
	var twin_drawn := 0
	for mesh in twin_surfaces:
		twin_drawn += _triangles(mesh)
	_t.equal("carrying both runs' triangles", twin_drawn, drawn * 2)
	twin_baked.free()

	## A second edge in another MATERIAL costs exactly one more surface. The
	## check above cannot tell "colour is free" from "nothing is ever added",
	## and this is the difference.
	var steel := _plan(FIXTURE)
	var second := _recoloured(edge, steel.allocate_id())
	second["material"] = "steel"
	steel.edges.append(second)
	var steel_baked := StructureBaker.bake(steel)
	_t.equal("a second MATERIAL costs one surface", _meshes(steel_baked).size(), 2)
	steel_baked.free()


# ── 5. The colliders are the drawing ───────────────────────────────────────

## Both of this project's walk-through bugs were a drawing and a collision
## computed separately, one of which was later edited.
## `StructureEdge.sweep_collider_boxes` calls `sweep_boxes` and bounds the boxes
## that come back, so there is no second derivation to keep in step — and this
## holds the BAKER to that property rather than to a box count, because a count
## is exactly what a second derivation would still satisfy.
func _test_colliders_are_the_drawing() -> void:
	var plan := _plan(FIXTURE)
	if plan == null:
		return
	var edge := plan.edges[0] as Dictionary
	var boxes := StructureBaker.edge_boxes(plan, edge)
	var colliders := StructureBaker.collect_colliders(plan)
	if not _t.check("the plan's colliders include the edge (%d)" % colliders.size(),
		colliders.size() > 0):
		return
	_t.equal(
		"and they are exactly the edge's",
		colliders.size(), StructureBaker.edge_collider_boxes(plan, edge).size()
	)

	var outside := 0
	var first := Vector3.ZERO
	var corners := 0
	for box_variant in boxes:
		for corner in _corners(box_variant as Dictionary):
			corners += 1
			if _inside_any(colliders, corner):
				continue
			if outside == 0:
				first = corner
			outside += 1
	_t.check(
		"every one of %d drawn corners is inside a collider (%d loose, first %v)"
		% [corners, outside, first],
		outside == 0
	)

	## Conservative in the right direction is not the same as unbounded. The
	## colliders may over-cover the drawing — a pitched cap rail has no field to
	## put its pitch in — but not by an amount a body could feel: 0.45 m is the
	## player's step height, so a collider growing past that would be a phantom
	## step in the middle of the deck.
	var drawn_aabb := StructureEdge.boxes_aabb(boxes)
	var solid_aabb := AABB()
	var started := false
	for collider_variant in colliders:
		var collider := collider_variant as Dictionary
		var box := _collider_aabb(collider)
		if started:
			solid_aabb = solid_aabb.merge(box)
		else:
			solid_aabb = box
			started = true
	var slop := (solid_aabb.size - drawn_aabb.size)
	_t.check(
		"the colliders over-cover the drawing by at most 0.1 m per axis (%v)" % slop,
		slop.x <= 0.1 and slop.y <= 0.1 and slop.z <= 0.1
		and slop.x >= -1e-4 and slop.y >= -1e-4 and slop.z >= -1e-4
	)

	## `solid: false` is a real opt-out — paint, a boot top, a sheer strake flush
	## with the shell — and it must reach the baker, or every stripe on a hull
	## becomes a wall.
	var paint := _plan(FIXTURE)
	(paint.edges[0] as Dictionary)["solid"] = false
	_t.check(
		"a `solid: false` run still draws",
		StructureBaker.edge_boxes(paint, paint.edges[0] as Dictionary).size() > 0
	)
	_t.equal(
		"and collides with nothing",
		StructureBaker.collect_colliders(paint).size(), 0
	)


# ── 6. An edge can host a fitting ──────────────────────────────────────────

## A cleat belongs on a bulwark cap, and a cleat that does not move when its
## bulwark moves is a trap for the builder. The edge is the first host whose run
## is NOT a straight line, so the anchor walks arc length: sliding a straight
## `basis.x` out of the start point — correct for every other host, because
## every other host is straight — puts "end" 70 m off the bow.
func _test_an_edge_can_host_a_fitting() -> void:
	var plan := _plan(FIXTURE)
	if plan == null:
		return
	var edge := plan.edges[0] as Dictionary
	var edge_id := int(edge["id"])
	var spec := plan.edge_spec(edge)
	var path := spec["path"] as PackedVector3Array
	var cap_h := float(edge.get("cap_h", StructureEdge.DEFAULT_CAP_THICKNESS_M))

	var start := plan.add_hosted_item("cleat", edge_id, Vector3.ZERO, 0.0, "side", "start")
	var at_start := plan.item_transform(start).origin
	_t.near("the start anchor sits on the first path point (x)", at_start.x, path[0].x, 1e-4)
	_t.near("… (y)", at_start.y, path[0].y, 1e-4)
	_t.near("… (z)", at_start.z, path[0].z, 1e-4)

	## Every point of the run is ON the run, which a straight-chord slide is not:
	## the chord from the stem to the half-way point cuts across the deck.
	var half := plan.add_hosted_item("cleat", edge_id, Vector3.ZERO, 0.0, "side", "center")
	var at_half := plan.item_transform(half).origin
	_t.check(
		"the center anchor is ON the polyline, not on a chord across it (%v)" % at_half,
		_distance_to_path(path, at_half) < 1e-3
	)
	## …and half way ROUND a 76 m loop is the transom, not the middle of a side.
	var walked := 0.0
	for i in range(path.size() - 1):
		walked += path[i].distance_to(path[i + 1])
	walked += path[path.size() - 1].distance_to(path[0])
	_t.near(
		"half way round the loop is half its length from the stem",
		_arc_length_to(path, at_half), walked * 0.5, 0.05
	)

	## "cap" lands on the surface a cleat is bolted to, not on the path line
	## buried inside the plating below it.
	var capped := plan.add_hosted_item("cleat", edge_id, Vector3.ZERO, 0.0, "cap", "start")
	_t.near(
		"the cap face lifts the frame to the top of the section",
		plan.item_transform(capped).origin.y, path[0].y + cap_h, 1e-4
	)

	## +z is `run x UP` — the LEFT HAND of the run, exactly as a wall's is. Which
	## side of the vessel that lands on is decided by the TRAVERSAL, not by this
	## file, so it is measured rather than asserted from a comment: `sheer_loop`
	## goes starboard bow->stern, across the transom, then port stern->bow, and on
	## every one of its segments the left hand points toward the centreline.
	##
	## This is checked over the whole path, not at the three anchors, because the
	## three anchors of a CLOSED run are two distinct points and a property that
	## holds at two points is not a property.
	var centre := Vector2(
		plan.hull_stations().beam_m * 0.5, plan.hull_stations().length_m * 0.5
	)
	var outboard := 0
	var worst_dot := INF
	for i in range(path.size()):
		var a := path[i]
		var b := path[(i + 1) % path.size()]
		var tangent := Vector3(b.x - a.x, 0.0, b.z - a.z)
		if tangent.length_squared() < 1e-10:
			continue
		var left := tangent.normalized().cross(Vector3.UP)
		var mid := Vector2((a.x + b.x) * 0.5, (a.z + b.z) * 0.5)
		var inward := (centre - mid).normalized()
		var dot := Vector2(left.x, left.z).dot(inward)
		worst_dot = minf(worst_dot, dot)
		if dot <= 0.0:
			outboard += 1
	_t.check(
		"run x UP points inboard on all %d segments of the loop (%d outboard, worst dot %.3f)"
		% [path.size(), outboard, worst_dot],
		outboard == 0
	)
	## And the HOST FRAME is that same normal, so a builder authoring `at.z` on a
	## bulwark is authoring against the run's left hand and not against something
	## the frame decided separately.
	for anchor in [StructurePlan.ITEM_ANCHOR_START, StructurePlan.ITEM_ANCHOR_CENTER]:
		var probe := plan.add_hosted_item("cleat", edge_id, Vector3.ZERO, 0.0, "cap", anchor)
		var frame := plan.item_transform(probe)
		var here := Vector2(frame.origin.x, frame.origin.z)
		var normal := Vector2(frame.basis.z.x, frame.basis.z.z).normalized()
		_t.check(
			"the \"%s\" anchor's +z points inboard (dot %.3f)"
			% [anchor, normal.dot((centre - here).normalized())],
			normal.dot((centre - here).normalized()) > 0.0
		)
		plan.remove_entity(int(probe["id"]))

	## And hosting is hosting: move the bulwark and the cleat moves with it.
	var before := plan.item_transform(capped).origin
	edge["height"] = float(edge.get("height", StructureEdge.DEFAULT_BULWARK_HEIGHT)) + 0.5
	var after := plan.item_transform(capped).origin
	_t.near(
		"raising the bulwark raises its cleat by the same amount",
		after.y - before.y, 0.5, 1e-4
	)


# ── Helpers ─────────────────────────────────────────────────────────────────

func _plan(path: String) -> StructurePlan:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		_t.fail("cannot read %s" % path)
		return null
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		_t.fail("%s is not a JSON object" % path)
		return null
	return StructurePlan.from_dict(parsed as Dictionary)


## Rise of the CAP along the run, measured off the drawn boxes rather than off
## the spec — the spec could carry a curve the emitter ignored.
##
## Per METRE of length, not over the whole box list, and that distinction is the
## difference between a measurement and a coincidence: a bulwark is two rects at
## every station (plating running a third of the way into the cap, and the cap
## itself), so max-minus-min over every box top reads 0.04 m — the cap's own
## thickness less the overlap — on a band with no sheer at all. Taking the
## HIGHEST top in each 1 m station and ranging those reads the cap line and
## nothing else, and is exactly 0 on the flat control.
func _band_rise(plan: StructurePlan) -> float:
	var boxes := StructureBaker.edge_boxes(plan, plan.edges[0] as Dictionary)
	if boxes.is_empty():
		return 0.0
	var per_station: Dictionary = {}
	for box_variant in boxes:
		var box := box_variant as Dictionary
		var centre := box["center"] as Vector3
		var top := centre.y + (box["size"] as Vector3).y * 0.5
		var station := int(round(centre.z))
		per_station[station] = maxf(float(per_station.get(station, -INF)), top)
	var lo := INF
	var hi := -INF
	for station in per_station:
		lo = minf(lo, float(per_station[station]))
		hi = maxf(hi, float(per_station[station]))
	return hi - lo


func _recoloured(edge: Dictionary, id: int) -> Dictionary:
	var copy := edge.duplicate(true)
	copy["id"] = id
	copy["plate_color"] = [0.9, 0.2, 0.1]
	copy["cap_color"] = [0.1, 0.9, 0.2]
	return copy


func _meshes(node: Node) -> Array:
	var out: Array = []
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		out.append((node as MeshInstance3D).mesh)
	for child in node.get_children():
		out.append_array(_meshes(child))
	return out


func _triangles(mesh: Mesh) -> int:
	var total := 0
	for surface in mesh.get_surface_count():
		total += mesh.surface_get_array_len(surface) / 3
	return total


func _corners(box: Dictionary) -> Array:
	var centre := box["center"] as Vector3
	var half := (box["size"] as Vector3) * 0.5
	var basis := box.get("basis", Basis.IDENTITY) as Basis
	var out: Array = []
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				out.append(centre + basis * Vector3(half.x * sx, half.y * sy, half.z * sz))
	return out


func _inside_any(colliders: Array, point: Vector3, slack := 1e-4) -> bool:
	for collider_variant in colliders:
		var collider := collider_variant as Dictionary
		var delta := point - (collider["center"] as Vector3)
		var yaw := deg_to_rad(float(collider.get("yaw_deg", 0.0)))
		if not is_zero_approx(yaw):
			delta = delta.rotated(Vector3.UP, -yaw)
		var half := (collider["size"] as Vector3) * 0.5 + Vector3.ONE * slack
		if absf(delta.x) <= half.x and absf(delta.y) <= half.y and absf(delta.z) <= half.z:
			return true
	return false


func _collider_aabb(collider: Dictionary) -> AABB:
	var centre := collider["center"] as Vector3
	var half := (collider["size"] as Vector3) * 0.5
	var yaw := deg_to_rad(float(collider.get("yaw_deg", 0.0)))
	var basis := Basis(Vector3.UP, yaw)
	var out := AABB(centre + basis * Vector3(-half.x, -half.y, -half.z), Vector3.ZERO)
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				out = out.expand(centre + basis * Vector3(half.x * sx, half.y * sy, half.z * sz))
	return out


func _closest_on_path(path: PackedVector3Array, point: Vector3) -> Vector3:
	var best := path[0]
	var best_d := INF
	for i in range(path.size()):
		var a := path[i]
		var b := path[(i + 1) % path.size()]
		var here := Geometry3D.get_closest_point_to_segment(point, a, b)
		var d := here.distance_to(point)
		if d < best_d:
			best_d = d
			best = here
	return best


func _distance_to_path(path: PackedVector3Array, point: Vector3) -> float:
	return _closest_on_path(path, point).distance_to(point)


## Arc length from the first path point to the closest point on the run.
func _arc_length_to(path: PackedVector3Array, point: Vector3) -> float:
	var walked := 0.0
	var best := INF
	var answer := 0.0
	for i in range(path.size()):
		var a := path[i]
		var b := path[(i + 1) % path.size()]
		var here := Geometry3D.get_closest_point_to_segment(point, a, b)
		var d := here.distance_to(point)
		if d < best:
			best = d
			answer = walked + a.distance_to(here)
		walked += a.distance_to(b)
	return answer
