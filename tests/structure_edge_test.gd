extends SceneTree

## The two edge primitives: a railing run and a swept profile.
##
## Run (SceneTree lane — StructureEdge, StructureBaker, HullStations and
## HullFormProfile are all `class_name` scripts with no autoload dependency):
##
##   timeout 300 xvfb-run -a --server-args="-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy \
##     --script res://tests/structure_edge_test.gd
##
## It renders: the draw-call claims are measured with
## `RenderingServer.get_rendering_info(RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)`
## against a real frame, because a MeshInstance3D is not a draw call — one
## instance carrying twenty surfaces costs twenty, and a node count would report
## that as a win.
##
## MUTATION-VERIFIED. Every check in this file was watched going red against a
## deliberately broken StructureEdge; the mutants and their numbers are recorded
## in the wave report. A check that has never failed is a check that measures
## nothing.

const TestReport := preload("res://tests/support/test_report.gd")

const FIXTURE := "res://resources/data/structures/probe_edge_runs.json"

## The nine parts COMPONENTS.md lists separately and says one generalised
## primitive should absorb. If the library ever stops covering one of them the
## generalisation claim is no longer true and this test says so.
const ABSORBED_PARTS: Array[String] = [
	"rubbing_strake", "cap_rail", "sheer_strake", "boot_top", "d_fender",
	"spray_rail", "stringer_l", "chainplate", "pipe_run",
]

var _t: RefCounted
var _fixture: Dictionary = {}
var _runs: Dictionary = {}
var _hulls: Dictionary = {}
var _camera: Camera3D
var _draw_baseline := 0


func _initialize() -> void:
	_t = TestReport.new("structure_edge_test")
	if not _load_fixture():
		_t.finish(self)
		return

	_test_sweep_frames_are_rotations()
	_test_mitred_joints_are_filled()
	_test_profile_library_absorbs_nine_parts()
	_test_railing_geometry()
	_test_railing_blocks_the_edge()
	_test_sheer_comes_from_hull_stations()
	_test_lod_seam()
	await _test_draw_calls()

	print("---")
	_report_costs()
	_t.finish(self)


# ── 1. The sweep frame ──────────────────────────────────────────────────────

## Every box a sweep emits must be placed by a ROTATION. `Basis(right, up,
## tangent)` built the other way round has determinant −1, which is a
## reflection: `_append_box` would emit every face of every swept box with
## reversed winding, invisible in a box count and invisible in an AABB.
func _test_sweep_frames_are_rotations() -> void:
	var boxes: Array = []
	for id in _runs.keys():
		boxes.append_array(_boxes_for(str(id)))
	_t.check("fixture emits geometry (%d boxes over %d runs)" % [boxes.size(), _runs.size()], boxes.size() > 0)

	var worst_det := INF
	var worst_ortho := 0.0
	for box_variant in boxes:
		var basis := (box_variant as Dictionary).get("basis", Basis.IDENTITY) as Basis
		worst_det = minf(worst_det, basis.determinant())
		worst_ortho = maxf(worst_ortho, absf(basis.x.length() - 1.0))
		worst_ortho = maxf(worst_ortho, absf(basis.y.length() - 1.0))
		worst_ortho = maxf(worst_ortho, absf(basis.z.length() - 1.0))
		worst_ortho = maxf(worst_ortho, absf(basis.x.dot(basis.y)))
		worst_ortho = maxf(worst_ortho, absf(basis.y.dot(basis.z)))
		worst_ortho = maxf(worst_ortho, absf(basis.z.dot(basis.x)))
	_t.check(
		"every emitted basis is a rotation, not a reflection (min det %.6f)" % worst_det,
		worst_det > 0.999,
	)
	_t.check(
		"every emitted basis is orthonormal (worst deviation %.9f)" % worst_ortho,
		worst_ortho < 1e-5,
	)

	## A vertical run has no horizontal reference up: the frame must fall back
	## rather than normalise a zero vector into NaNs.
	var vertical := StructureEdge.sweep_boxes({
		"path": [Vector3(0, 0, 0), Vector3(0, 4, 0)],
		"width": 0.1, "thickness": 0.1, "material": "steel",
	})
	var finite := vertical.size() == 1
	if finite:
		var c := (vertical[0] as Dictionary)["center"] as Vector3
		finite = is_finite(c.x) and is_finite(c.y) and is_finite(c.z)
	_t.check("a purely vertical run emits one finite box", finite)


# ── 2. Joints ───────────────────────────────────────────────────────────────

## A polyline that turns leaves an unfilled wedge on the OUTSIDE of the corner
## unless each segment is extended into the joint. This is the difference
## between a cap rail and a cap rail with a notch cut out of every corner, and
## it is not visible in a triangle count.
func _test_mitred_joints_are_filled() -> void:
	var spec := {
		"path": [Vector3(-4, 2, -3), Vector3(4, 2, -3), Vector3(4, 2, 5)],
		"width": 0.22, "thickness": 0.06, "material": "wood",
	}
	## Outer corner of the right-angle turn, just inside the band's outer face.
	var probe := Vector3(4.0 + 0.09, 2.0, -3.0 - 0.09)

	var mitred := StructureEdge.sweep_boxes(spec)
	var butted := StructureEdge.sweep_boxes(_with(spec, {"mitre": false}))
	_t.check(
		"mitred and butted sweeps emit the same box count (%d)" % mitred.size(),
		mitred.size() == butted.size() and mitred.size() == 2,
	)
	_t.check(
		"the outer corner of a 90 degree turn is filled",
		StructureEdge.point_inside_any(mitred, probe),
	)
	_t.check(
		"...and is NOT filled without the mitre (so the check can fail)",
		not StructureEdge.point_inside_any(butted, probe),
	)

	## A straight subdivision deviates by 0 degrees, so its mitre is zero — but
	## two boxes that merely touch share a plane and z-fight. JOINT_EPS is the
	## floor for exactly the reason StructureBaker keeps SKIN_EPS.
	var straight := StructureEdge.sweep_boxes(_with(spec, {
		"path": [Vector3(0, 0, 0), Vector3(3, 0, 0), Vector3(6, 0, 0)],
	}))
	var overlap := 0.0
	if straight.size() == 2:
		var a := straight[0] as Dictionary
		var b := straight[1] as Dictionary
		var a_end := (a["center"] as Vector3).x + (a["size"] as Vector3).z * 0.5
		var b_start := (b["center"] as Vector3).x - (b["size"] as Vector3).z * 0.5
		overlap = a_end - b_start
	_t.check(
		"consecutive straight segments overlap rather than share a plane (%.4f m)" % overlap,
		overlap >= StructureEdge.JOINT_EPS - 1e-6,
	)

	## Mitres add length, never remove it: a swept band always covers its path.
	var length := StructureEdge.path_length_m(spec["path"])
	var swept := 0.0
	for box_variant in mitred:
		swept += ((box_variant as Dictionary)["size"] as Vector3).z
	_t.check(
		"swept length covers the path (%.3f m swept over %.3f m of path)" % [swept, length],
		swept >= length - 1e-6,
	)


# ── 3. One primitive, a dozen parts ─────────────────────────────────────────

func _test_profile_library_absorbs_nine_parts() -> void:
	var missing: Array[String] = []
	for part in ABSORBED_PARTS:
		if not StructureEdge.PROFILE_LIBRARY.has(part):
			missing.append(part)
	_t.check(
		"the profile library covers all nine parts COMPONENTS.md lists separately (missing %s)" % str(missing),
		missing.is_empty(),
	)

	var path := [Vector3(0, 1, 0), Vector3(6, 1, 0), Vector3(6, 1, 4)]
	var emitted_by: Dictionary = {}
	var all_drawn := true
	for name in StructureEdge.PROFILE_LIBRARY.keys():
		var rects: Array = StructureEdge.PROFILE_LIBRARY[name]
		var boxes := StructureEdge.sheer_band_boxes({
			"path": path, "profile": str(name), "material": "painted",
		})
		emitted_by[str(name)] = boxes.size()
		if boxes.size() != rects.size() * 2:
			all_drawn = false
			_t.fail("profile \"%s\": expected %d boxes, got %d" % [name, rects.size() * 2, boxes.size()])
	_t.check(
		"all %d profiles sweep the same 2-segment path through ONE emitter" % StructureEdge.PROFILE_LIBRARY.size(),
		all_drawn,
	)
	## The generalisation is only real if the multi-rect sections cost more than
	## the single-rect ones by exactly their rect count — no special casing.
	_t.equal("d_fender is 3 rects x 2 segments", int(emitted_by.get("d_fender", -1)), 6)
	_t.equal("pipe_run is 2 rects x 2 segments", int(emitted_by.get("pipe_run", -1)), 4)
	_t.equal("cap_rail is 1 rect x 2 segments", int(emitted_by.get("cap_rail", -1)), 2)

	## A rolled rect must actually roll — a `roll` that is read and dropped
	## produces the same axis-aligned box and nobody notices.
	var flat := StructureEdge.sweep_boxes({
		"path": [Vector3(0, 0, 0), Vector3(4, 0, 0)], "width": 0.3, "thickness": 0.02,
	})
	var rolled := StructureEdge.sweep_boxes({
		"path": [Vector3(0, 0, 0), Vector3(4, 0, 0)],
		"profile": [{"u": 0.0, "v": 0.0, "w": 0.3, "h": 0.02, "roll": 45.0}],
	})
	var flat_h := StructureEdge.boxes_aabb(flat).size.y
	var rolled_h := StructureEdge.boxes_aabb(rolled).size.y
	_t.check(
		"a 45 degree roll changes the section's world footprint (%.3f m -> %.3f m tall)" % [flat_h, rolled_h],
		rolled_h > flat_h * 3.0,
	)


# ── 4. The railing run ──────────────────────────────────────────────────────

func _test_railing_geometry() -> void:
	var spec := _run("open_upper_deck_rail")
	var boxes := _boxes_for("open_upper_deck_rail")
	var height := float(spec["height"])
	var rails := int(spec["rails"])
	var toe := float(spec["toe_height"])
	var pitch := float(spec["post_pitch"])
	var deck_y := 6.0

	var length := StructureEdge.path_length_m(spec["path"], false)
	_t.near("open upper deck run is 46.2 m of railing", length, 46.2, 0.01)

	## Composition: rails + toe board come from the sweep, posts from
	## post_points. If those two ever disagree the box list has grown a source
	## nobody is counting.
	var profile := StructureEdge.railing_profile(spec)
	var posts := StructureEdge.post_points(spec)
	_t.equal("railing profile is %d rails + 1 toe board" % rails, profile.size(), rails + 1)
	_t.equal(
		"every box is accounted for (%d sweep + %d posts)" % [profile.size() * 3, posts.size()],
		boxes.size(),
		profile.size() * 3 + posts.size(),
	)

	## Openings. Three courses over a 1.0 m clear height give 0.333 m, and a
	## person does not fit through 0.333 m. This is the whole reason the
	## primitive is non-optional on a passenger vessel.
	var gap := StructureEdge.max_rail_gap_m(spec)
	_t.near("largest opening between courses", gap, (height - toe) / float(rails), 1e-6)
	_t.check(
		"no opening exceeds %.2f m (largest is %.3f m)" % [StructureEdge.MAX_RAIL_GAP_M, gap],
		gap <= StructureEdge.MAX_RAIL_GAP_M,
	)

	## The top course sits at the declared height, measured from the path.
	var top := -INF
	for rect_variant in profile:
		top = maxf(top, float((rect_variant as Dictionary)["v"]))
	_t.near("top course is at the declared height above the deck edge", top, height, 1e-6)

	## Posts are PLUMB. On a run that slopes — a railing following a sheer
	## curve — a frame-aligned post leans with the rail, which is wrong on every
	## real boat and looks deliberate.
	var sloped := _with(spec, {
		"path": [Vector3(0, 0, 0), Vector3(0, 1.4, 12.0)],
	})
	var worst_lean := 0.0
	var post_count := 0
	for box_variant in StructureEdge.railing_boxes(sloped):
		var box := box_variant as Dictionary
		var size := box["size"] as Vector3
		if not is_equal_approx(size.x, size.z):
			continue  ## a rail or toe board, not a post
		post_count += 1
		var local_up: Vector3 = (box.get("basis", Basis.IDENTITY) as Basis) * Vector3.UP
		worst_lean = maxf(worst_lean, local_up.angle_to(Vector3.UP))
	_t.check("the sloped run emitted posts (%d)" % post_count, post_count > 0)
	_t.check(
		"posts stay plumb on a 6.7 degree run (worst lean %.4f deg)" % rad_to_deg(worst_lean),
		worst_lean < 1e-5,
	)

	## Post spacing never exceeds the declared pitch, and there is a post at
	## every path vertex — a stanchion missing from a corner is where a railing
	## visibly sags.
	var worst_span := 0.0
	for i in range(1, posts.size()):
		worst_span = maxf(worst_span, posts[i - 1].distance_to(posts[i]))
	_t.check(
		"no post span exceeds the %.2f m pitch (worst %.3f m)" % [pitch, worst_span],
		worst_span <= pitch + 1e-6,
	)
	var vertices_covered := true
	for point_variant in spec["path"]:
		var vertex := StructureEdge._vec3_of(point_variant)
		var nearest := INF
		for p in posts:
			nearest = minf(nearest, p.distance_to(vertex))
		if nearest > 1e-6:
			vertices_covered = false
	_t.check("there is a stanchion on every path vertex, including both ends", vertices_covered)

	## Height above the deck: nothing in the railing may hang below the deck it
	## stands on, and the top must reach the declared clear height.
	var aabb := StructureEdge.boxes_aabb(boxes)
	_t.check(
		"nothing hangs below the deck (min y %.4f, deck %.2f)" % [aabb.position.y, deck_y],
		aabb.position.y >= deck_y - 1e-6,
	)
	_t.near(
		"railing top reaches the declared clear height",
		aabb.position.y + aabb.size.y,
		deck_y + height + float(spec.get("rail_width", StructureEdge.DEFAULT_RAIL_WIDTH)) * 0.5,
		1e-6,
	)

	## A closed loop closes: the wrap segment exists, so the box count is one
	## sweep segment per side rather than three.
	var closed_spec := _run("perimeter_rail_closed")
	var closed_profile := StructureEdge.railing_profile(closed_spec)
	var closed_boxes := _boxes_for("perimeter_rail_closed")
	var closed_posts := StructureEdge.post_points(closed_spec)
	_t.equal(
		"a closed 4-point loop sweeps 4 segments per rect, not 3",
		closed_boxes.size() - closed_posts.size(),
		closed_profile.size() * 4,
	)


# ── 5. Collision: the reason a railing is not decoration ────────────────────

func _test_railing_blocks_the_edge() -> void:
	var spec := _run("open_upper_deck_rail")
	var colliders := StructureEdge.railing_collider_boxes(spec)
	_t.equal("one barrier collider per run segment", colliders.size(), 3)

	## Rebuild the colliders as oriented boxes so the point test honours yaw,
	## exactly as StructureBaker.collect_colliders' contract requires.
	var oriented: Array = []
	for c_variant in colliders:
		var c := c_variant as Dictionary
		oriented.append({
			"center": c["center"],
			"size": c["size"],
			"basis": Basis(Vector3.UP, deg_to_rad(float(c["yaw_deg"]))),
		})

	## Chest height, on the deck edge, mid-span: a body moving outboard hits it.
	var chest := Vector3(14.25, 6.0 + 1.0, 24.0)
	_t.check(
		"a body at chest height on the deck edge is blocked",
		StructureEdge.point_inside_any(oriented, chest),
	)
	## Knee height too — the barrier is solid, so nobody slides between courses.
	_t.check(
		"...and at knee height, so nothing passes between the courses",
		StructureEdge.point_inside_any(oriented, Vector3(14.25, 6.0 + 0.3, 24.0)),
	)
	## But it is a rail at the edge, not a wall across the deck.
	_t.check(
		"the middle of the deck is still walkable",
		not StructureEdge.point_inside_any(oriented, Vector3(8.0, 6.0 + 1.0, 24.0)),
	)
	var top := -INF
	for c_variant in colliders:
		var c := c_variant as Dictionary
		top = maxf(top, (c["center"] as Vector3).y + (c["size"] as Vector3).y * 0.5)
	_t.near("barrier top matches the railing height", top, 6.0 + float(spec["height"]), 1e-6)


# ── 6. The sheer curve, consumed ────────────────────────────────────────────

func _test_sheer_comes_from_hull_stations() -> void:
	var stations := _hull("trawler_ref")
	if not _t.check("trawler_ref hull builds", stations != null and not stations.stations.is_empty()):
		return

	## The derivation is HullStations' and is held by hull_sheer_test. What is
	## checked here is CONSUMPTION: that the drawn band's Y is that curve and
	## nothing else.
	_t.near("sheer forward is freeboard x bow_keel_rise", stations.sheer_forward_m, 2.8 * 0.32, 1e-4)

	var path := StructureEdge.sheer_path(stations, 1.0, 15, 0.03, 0.0)
	var worst := 0.0
	for p in path:
		worst = maxf(worst, absf(p.y - stations.sheer_cap_y_at(p.z)))
	_t.check(
		"every path sample sits exactly on sheer_cap_y_at (worst error %.9f m)" % worst,
		worst < 1e-6,
	)

	var bow := path[0]
	var stern := path[path.size() - 1]
	var mid := Vector3.ZERO
	var mid_error := INF
	for p in path:
		if absf(p.z) < mid_error:
			mid_error = absf(p.z)
			mid = p
	_t.near("the bow end rises by the derived forward sheer", bow.y - stations.deck_y, stations.sheer_forward_m, 1e-4)
	_t.near("the transom rises by the derived aft sheer", stern.y - stations.deck_y, stations.sheer_aft_m, 1e-4)
	_t.near("amidships the curve is flat on the deck", mid.y, stations.deck_y, 1e-3)
	_t.check(
		"the bow is higher than the transom (%.3f m vs %.3f m of rise)"
		% [bow.y - stations.deck_y, stern.y - stations.deck_y],
		bow.y > stern.y,
	)
	## The line is a CURVE, not two ramps: Y must fall monotonically from the
	## bow to amidships and rise monotonically to the transom.
	var monotone := true
	for i in range(1, path.size()):
		var a := path[i - 1]
		var b := path[i]
		if b.z <= 0.0 and b.y > a.y + 1e-9:
			monotone = false
		if a.z >= 0.0 and b.y < a.y - 1e-9:
			monotone = false
	_t.check("the sheer falls to amidships and rises again, without a kink", monotone)

	## The path tapers with the hull: the deck edge at the stem is inboard of
	## the deck edge amidships, or the band flies off the bow.
	_t.check(
		"the deck-edge path narrows toward the stem (%.2f m vs %.2f m half-beam)" % [bow.x, mid.x],
		bow.x < mid.x - 0.5,
	)

	## Nothing the cap emits may enter the deck plate (deck_y .. deck_y+0.1) or
	## sit under the build plane (deck_y+0.12): `deck_y` is the floor of four
	## other systems and the loft has zero headroom above it (STATE.md). The
	## bulwark's own height is the caller's to supply — `sheer_cap_y_at` is
	## deck_y + rise, and rise is zero amidships.
	var cap := _boxes_for("bulwark_cap")
	var cap_aabb := StructureEdge.boxes_aabb(cap)
	var build_plane := stations.deck_y + 0.12
	_t.check(
		"the bulwark cap clears the deck plate and the build plane (min y %.4f, plane %.2f)"
		% [cap_aabb.position.y, build_plane],
		cap_aabb.position.y >= build_plane,
	)
	## And it must actually CARRY the curve: the band's own vertical span is the
	## derived sheer rise plus its section, not a flat ribbon.
	var drawn_rise := cap_aabb.size.y - 0.06
	_t.near(
		"the cap's vertical span is the derived forward sheer (%.3f m drawn)" % drawn_rise,
		drawn_rise,
		stations.sheer_forward_m,
		0.01,
	)

	## follow_sheer false is the boot top: parallel to the waterline while the
	## cap above it curves. If the flag is ignored, this Y range is 0.896 m.
	var flat := StructureEdge.sheer_path(stations, 1.0, 15, 0.0, -2.75, false)
	var flat_range := StructureEdge.boxes_aabb(_boxes_for("boot_top")).size.y
	var flat_span := 0.0
	var flat_min := INF
	var flat_max := -INF
	for p in flat:
		flat_min = minf(flat_min, p.y)
		flat_max = maxf(flat_max, p.y)
	flat_span = flat_max - flat_min
	_t.near("a waterline band is held flat, not swept with the sheer", flat_span, 0.0, 1e-9)
	_t.check(
		"the boot top's whole band is thinner than the sheer rise (%.3f m)" % flat_range,
		flat_range < stations.sheer_forward_m,
	)

	## The half-beam is read at the BAND's height, so a strake low on a flared
	## hull hugs the narrower section instead of standing off it.
	var at_deck := StructureEdge.deck_half_beam_at(stations, 0.0, stations.deck_y)
	var at_strake := StructureEdge.deck_half_beam_at(stations, 0.0, stations.deck_y - 1.15)
	_t.check(
		"half-beam is sampled at the band's own height (%.3f m at deck, %.3f m 1.15 m down)"
		% [at_deck, at_strake],
		at_strake < at_deck - 1e-4,
	)
	## ...and sheer_path must actually USE it. The check above calls
	## deck_half_beam_at directly, so it cannot see a sheer_path that passes
	## deck_y for every band — a mutant doing exactly that survived the whole
	## suite until this check was added. A band near the waterline has to come
	## out narrower than the deck edge above it.
	var cap_widest := 0.0
	for p in StructureEdge.sheer_path(stations, 1.0, 15, 0.0, 0.0):
		cap_widest = maxf(cap_widest, absf(p.x))
	var boot_widest := 0.0
	for p in flat:
		boot_widest = maxf(boot_widest, absf(p.x))
	_t.check(
		"a waterline band is drawn narrower than the deck edge (%.3f m vs %.3f m half-beam)"
		% [boot_widest, cap_widest],
		boot_widest < cap_widest - 0.1,
	)


# ── 7. LOD ──────────────────────────────────────────────────────────────────

func _test_lod_seam() -> void:
	var spec := _run("open_upper_deck_rail")
	var post := float(spec.get("post_width", StructureEdge.DEFAULT_POST_WIDTH))

	## The switch distance is derived from when a stanchion stops resolving, so
	## it must round-trip: at that distance the post is exactly one pixel.
	var switch := StructureEdge.lod_switch_distance_m(post, 1280.0, 70.0, 1.0)
	var rad_per_px := deg_to_rad(70.0) / 1280.0
	_t.near("a 0.05 m stanchion goes sub-pixel at 52.4 m", switch, 52.4, 0.1)
	_t.near("...and subtends exactly 1 px there", post / (switch * rad_per_px), 1.0, 1e-6)
	_t.check(
		"a wider feature survives further out",
		StructureEdge.lod_switch_distance_m(0.2, 1280.0, 70.0, 1.0) > switch * 3.9,
	)

	_t.equal("near: full detail", StructureEdge.railing_lod_for_distance(spec, 10.0), StructureEdge.LOD_FULL)
	_t.equal("mid: solid panel", StructureEdge.railing_lod_for_distance(spec, 200.0), StructureEdge.LOD_PANEL)
	_t.equal("far: culled", StructureEdge.railing_lod_for_distance(spec, 900.0), StructureEdge.LOD_CULLED)

	var full := StructureEdge.railing_lod_boxes(spec, StructureEdge.LOD_FULL)
	var panel := StructureEdge.railing_lod_boxes(spec, StructureEdge.LOD_PANEL)
	var culled := StructureEdge.railing_lod_boxes(spec, StructureEdge.LOD_CULLED)
	_t.check("LOD_CULLED emits nothing", culled.is_empty())
	_t.equal("the panel is one swept band per segment", panel.size(), 3)
	_t.check(
		"the panel is at least 4x cheaper (%d tris -> %d tris)"
		% [StructureEdge.triangle_count(full), StructureEdge.triangle_count(panel)],
		StructureEdge.triangle_count(panel) * 4 <= StructureEdge.triangle_count(full),
	)

	## The seam is only safe if the switch changes DENSITY and not silhouette.
	## Both bounds are checked, because a panel that is right in Y and wrong in
	## X pops sideways and a panel that is right in X and wrong in Y pops up.
	var full_aabb := StructureEdge.boxes_aabb(full)
	var panel_aabb := StructureEdge.boxes_aabb(panel)
	_t.near(
		"the panel's top is the top rail's top — no vertical pop",
		panel_aabb.position.y + panel_aabb.size.y,
		full_aabb.position.y + full_aabb.size.y,
		1e-6,
	)
	_t.check(
		"the panel is no wider than the railing in X (%.3f vs %.3f)" % [panel_aabb.size.x, full_aabb.size.x],
		panel_aabb.size.x <= full_aabb.size.x + 1e-6,
	)
	_t.check(
		"the panel is no longer than the railing in Z (%.3f vs %.3f)" % [panel_aabb.size.z, full_aabb.size.z],
		panel_aabb.size.z <= full_aabb.size.z + 1e-6,
	)
	_t.check(
		"the panel reaches the deck (min y %.4f vs %.4f)" % [panel_aabb.position.y, full_aabb.position.y],
		panel_aabb.position.y <= full_aabb.position.y + 1e-6,
	)


# ── 8. Draw calls, from the renderer ────────────────────────────────────────

## A MeshInstance3D is not a draw call. Every claim below is read off
## RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME after a real frame, with an empty
## scene measured first so the engine's own overhead is subtracted rather than
## guessed.
func _test_draw_calls() -> void:
	_camera = Camera3D.new()
	_camera.far = 40000.0
	root.add_child(_camera)
	_camera.current = true
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50.0, 35.0, 0.0)
	root.add_child(light)

	_draw_baseline = await _draw_calls_now()
	_t.check("an empty scene has a measurable draw-call baseline (%d)" % _draw_baseline, _draw_baseline > 0)

	## (a) One railing, one material: ONE surface, ONE draw call.
	var rail_boxes := _boxes_for("open_upper_deck_rail")
	var rail_node := StructureEdge.bake_boxes(rail_boxes)
	root.add_child(rail_node)
	var rail_calls := await _draw_calls_for(rail_node)
	_t.equal(
		"a 46.2 m railing costs exactly one draw call (baseline %d)" % _draw_baseline,
		rail_calls - _draw_baseline,
		1,
	)
	_t.equal("...carried by one MeshInstance3D", rail_node.get_child_count(), 1)
	var rail_surfaces := _surface_count(rail_node)
	_t.equal("...holding exactly one surface (a node is not a draw call)", rail_surfaces, 1)
	_t.equal(
		"...whose triangles are the box count x 12 (%d boxes)" % rail_boxes.size(),
		_triangles(rail_node),
		StructureEdge.triangle_count(rail_boxes),
	)

	## (b) Colour is free. A second railing in a different colour, same
	## material, must still merge into the SAME single surface.
	var recoloured := StructureEdge.railing_boxes(_with(_run("open_upper_deck_rail"), {
		"color": "#c02020",
		"path": [Vector3(20.0, 6.0, 16.0), Vector3(20.0, 6.0, 32.85)],
	}))
	var two_colour := StructureEdge.bake_boxes(rail_boxes + recoloured)
	root.remove_child(rail_node)
	root.add_child(two_colour)
	var two_colour_calls := await _draw_calls_for(two_colour)
	_t.equal(
		"two colours on one material still cost one draw call",
		two_colour_calls - _draw_baseline,
		1,
	)
	_t.check("...and that one surface really carries both colours", _distinct_colours(two_colour) >= 2)
	root.remove_child(two_colour)
	two_colour.free()

	## (c) The whole fixture: seven runs, four materials, four draw calls.
	## Bound by MATERIALS, never by run count, colour count or path length.
	var all_boxes: Array = []
	var materials: Dictionary = {}
	for id in _runs.keys():
		var boxes := _boxes_for(str(id))
		all_boxes.append_array(boxes)
		for box_variant in boxes:
			materials[str((box_variant as Dictionary)["material"])] = true
	var all_node := StructureEdge.bake_boxes(all_boxes)
	root.add_child(all_node)
	var all_calls := await _draw_calls_for(all_node)
	_t.equal(
		"%d runs over %d materials cost one draw call per material" % [_runs.size(), materials.size()],
		all_calls - _draw_baseline,
		materials.size(),
	)
	_t.check(
		"...which is within the MATERIALS bound (%d of %d)" % [materials.size(), StructureBaker.MATERIALS.size()],
		materials.size() <= StructureBaker.MATERIALS.size(),
	)
	_t.equal(
		"...and every surface is accounted for by a draw call",
		_surface_count(all_node),
		all_calls - _draw_baseline,
	)
	_t.equal(
		"total triangles match the box count (%d boxes)" % all_boxes.size(),
		_triangles(all_node),
		StructureEdge.triangle_count(all_boxes),
	)
	root.remove_child(all_node)
	all_node.free()

	## (d) The LOD payoff, measured the same way: a harbour of 24 railings.
	var spec := _run("open_upper_deck_rail")
	var far_boxes: Array = []
	var near_boxes: Array = []
	for i in 24:
		var moved := _with(spec, {"offset": Vector3(float(i) * 40.0, 0.0, 0.0)})
		near_boxes.append_array(StructureEdge.railing_lod_boxes(moved, StructureEdge.LOD_FULL))
		far_boxes.append_array(StructureEdge.railing_lod_boxes(moved, StructureEdge.LOD_PANEL))
	var far_node := StructureEdge.bake_boxes(far_boxes)
	root.add_child(far_node)
	var far_calls := await _draw_calls_for(far_node)
	_t.equal("24 railings at panel LOD are still one draw call", far_calls - _draw_baseline, 1)
	_t.check(
		"...for %d triangles instead of %d (%.1fx)"
		% [
			StructureEdge.triangle_count(far_boxes),
			StructureEdge.triangle_count(near_boxes),
			float(near_boxes.size()) / maxf(float(far_boxes.size()), 1.0),
		],
		far_boxes.size() * 4 <= near_boxes.size(),
	)
	root.remove_child(far_node)
	far_node.free()
	rail_node.free()


## Frame `node` so its whole AABB is inside the frustum, then count. A
## draw-call measurement on geometry the camera cannot see reports zero, which
## looks exactly like a merge that worked.
func _draw_calls_for(node: Node3D) -> int:
	var bounds := AABB()
	var first := true
	for child in node.get_children():
		if child is MeshInstance3D:
			var box: AABB = (child as MeshInstance3D).get_aabb()
			bounds = box if first else bounds.merge(box)
			first = false
	if first:
		_t.fail("nothing to frame — the node holds no MeshInstance3D")
		return await _draw_calls_now()
	var centre := bounds.get_center()
	var distance := maxf(bounds.size.length(), 1.0) * 1.6
	_camera.position = centre + Vector3(0.35, 0.45, -1.0).normalized() * distance
	_camera.look_at(centre, Vector3.UP)
	var calls := await _draw_calls_now()
	## A frame that drew nothing beyond the baseline cannot prove a merge.
	_t.check(
		"the camera actually sees the geometry it is counting (%d > %d)" % [calls, _draw_baseline],
		calls > _draw_baseline,
	)
	return calls


func _draw_calls_now() -> int:
	for i in 2:
		await process_frame
		await RenderingServer.frame_post_draw
	return int(RenderingServer.get_rendering_info(
		RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME
	))


# ── Cost report ─────────────────────────────────────────────────────────────

func _report_costs() -> void:
	print("cost table — boxes, triangles, run length")
	for id in _runs.keys():
		var spec := _run(str(id))
		var boxes := _boxes_for(str(id))
		var length := 0.0
		if spec.has("path"):
			length = StructureEdge.path_length_m(spec["path"], bool(spec.get("closed", false)))
		elif spec.has("_resolved_path"):
			length = StructureEdge.path_length_m(spec["_resolved_path"], bool(spec.get("closed", false)))
		print("  %-24s %4d boxes  %5d tris  %6.2f m  %s" % [
			id, boxes.size(), StructureEdge.triangle_count(boxes), length,
			str(spec.get("material", "painted")),
		])


# ── Fixture plumbing ────────────────────────────────────────────────────────

func _load_fixture() -> bool:
	var file := FileAccess.open(FIXTURE, FileAccess.READ)
	if not _t.check("fixture %s opens" % FIXTURE, file != null):
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not _t.check("fixture parses as an object", parsed is Dictionary):
		return false
	_fixture = parsed as Dictionary
	_hulls = _fixture.get("hulls", {}) as Dictionary
	for raw in _fixture.get("runs", []) as Array:
		var run := (raw as Dictionary).duplicate(true)
		var id := str(run.get("id", ""))
		if run.has("path_source"):
			run["_resolved_path"] = _resolve_path_source(run["path_source"] as Dictionary)
			run["path"] = run["_resolved_path"]
			run["closed"] = str((run["path_source"] as Dictionary).get("kind", "")) == "sheer_loop"
		_runs[id] = run
	return _t.equal("fixture declares 7 edge runs", _runs.size(), 7)


## `path_source` is the fixture's way of saying "this polyline comes from the
## hull, not from my hand". Resolved through StructureEdge, so what the test
## draws is what a baker would draw.
func _resolve_path_source(src: Dictionary) -> PackedVector3Array:
	var stations := _hull(str(src.get("hull", "")))
	if stations == null:
		return PackedVector3Array()
	var samples := int(src.get("samples", 15))
	var inset := float(src.get("inset_m", 0.0))
	var y_offset := float(src.get("y_offset", 0.0))
	var follow := bool(src.get("follow_sheer", true))
	match str(src.get("kind", "sheer_loop")):
		"sheer_loop":
			return StructureEdge.sheer_loop(stations, samples, inset, y_offset, follow)
		"sheer_path_starboard":
			return StructureEdge.sheer_path(stations, 1.0, samples, inset, y_offset, follow)
		"sheer_path_port":
			return StructureEdge.sheer_path(stations, -1.0, samples, inset, y_offset, follow)
	_t.fail("unknown path_source kind \"%s\"" % str(src.get("kind", "")))
	return PackedVector3Array()


func _hull(id: String) -> HullStations:
	if not _hulls.has(id):
		return null
	var cfg := _hulls[id] as Dictionary
	return HullStations.from_form(
		float(cfg["loa_m"]),
		float(cfg["beam_m"]),
		float(cfg["depth_m"]),
		float(cfg["draft_m"]),
		float(cfg["displacement_t"]),
		HullFormProfile.resolve(str(cfg.get("form", "fine_entry"))),
		1025.0,
		float(cfg["loa_m"]) * float(cfg.get("bow_taper_fraction", 0.0)),
		int(cfg.get("station_count", 12)),
	)


func _run(id: String) -> Dictionary:
	return (_runs.get(id, {}) as Dictionary).duplicate(true)


func _boxes_for(id: String) -> Array:
	var spec := _run(id)
	match str(spec.get("primitive", "")):
		"railing":
			return StructureEdge.railing_boxes(spec)
		"sheer_band":
			return StructureEdge.sheer_band_boxes(spec)
	return []


func _with(base: Dictionary, overrides: Dictionary) -> Dictionary:
	var out := base.duplicate(true)
	for key in overrides.keys():
		out[key] = overrides[key]
	return out


func _surface_count(node: Node) -> int:
	var total := 0
	for child in node.get_children():
		if child is MeshInstance3D:
			var mesh := (child as MeshInstance3D).mesh
			if mesh != null:
				total += mesh.get_surface_count()
	return total


func _triangles(node: Node) -> int:
	var total := 0
	for child in node.get_children():
		if child is MeshInstance3D:
			var mesh := (child as MeshInstance3D).mesh as ArrayMesh
			if mesh == null:
				continue
			for s in mesh.get_surface_count():
				var verts: Variant = mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
				if verts != null:
					total += (verts as PackedVector3Array).size() / 3
	return total


func _distinct_colours(node: Node) -> int:
	var seen: Dictionary = {}
	for child in node.get_children():
		if child is MeshInstance3D:
			var mesh := (child as MeshInstance3D).mesh as ArrayMesh
			if mesh == null:
				continue
			for s in mesh.get_surface_count():
				var colours: Variant = mesh.surface_get_arrays(s)[Mesh.ARRAY_COLOR]
				if colours != null:
					for c in colours as PackedColorArray:
						seen[c.to_rgba32()] = true
	return seen.size()
