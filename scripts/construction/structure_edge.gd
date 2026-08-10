class_name StructureEdge
extends RefCounted

## The two primitives that shape a vessel's edges, as PURE FUNCTIONS returning
## the same box dictionaries StructureBaker already merges.
##
## Nothing here names a vessel. A railing is a polyline, a height and a rail
## count; a swept profile is a cross-section and a path. Both are used by a
## trawler, a ferry, a crane pedestal cage and a harbour wall without knowing
## which is which.
##
## ── What this file is, in one sentence ──────────────────────────────────────
## `sweep_boxes()` extrudes a rectangle list along an arbitrary 3D polyline, and
## everything else in the file is a caller of it.
##
## COMPONENTS.md's "honest summary" ranks the sheer band first of four
## under-generalisations, and says the fix is one change: stop describing it as
## a "deck-edge height curve" and describe it as a swept profile. That change is
## the whole of this file. One emitter absorbs, with no new code path:
##
##     rubbing strake · cap rail · sheer strake · boot top · D-fender ·
##     spray rail · stringer · chainplate · pipe run · toe board
##
## — see PROFILE_LIBRARY, which holds all ten and is asserted complete by
## `tests/structure_edge_test.gd`. A player adding an eleventh writes a rect
## list, not code.
##
## ── SCALE (CONVENTIONS §3a) ─────────────────────────────────────────────────
## One world unit is one metre; the player is 1.8 m. A guardrail is 1.1 m
## because a person is 1.8. A stanchion is 0.05 m — a twentieth of a metre, so
## a tenth of a deck cell: railing hardware is SUB-CELL and free-positioned,
## which is why every path here is float Vector3 and nothing snaps.
##
## ── THE CALL SITE (this file emits, StructureBaker merges) ──────────────────
## StructureBaker is owned elsewhere and is not edited by this file. Two static
## forwarders there flip `PartCatalog.baker_supports()` for both primitives,
## because PartCatalog probes the BAKER's method list by the names in
## PRIMITIVES[p].emitter:
##
##     static func railing_boxes(spec: Dictionary) -> Array:
##         return StructureEdge.railing_boxes(spec)
##
##     static func sheer_band_boxes(spec: Dictionary) -> Array:
##         return StructureEdge.sheer_band_boxes(spec)
##
## and inside `StructureBaker.bake()`, immediately after the `stairs` loop and
## before `for key in buckets.keys()`:
##
##     for spec_variant in expanded.get("edges", []) as Array:
##         var spec := spec_variant as Dictionary
##         var emitter := PartCatalog.emitter_method_for(str(spec["primitive"]))
##         for box_variant in StructureBaker.call(emitter, spec):
##             _bucket_layer(buckets, box_variant as Dictionary, offset, ghost)
##
## The box dictionary is exactly what `_bucket_layer` already consumes —
## {center, size, basis, color, material} — so no bucketing rule changes and the
## draw-call budget is untouched: every box this file emits carries a material
## name from StructureBaker.MATERIALS and its colour rides in the VERTEX stream.
## A hundred colours of trim still bake to at most MATERIALS.size() surfaces.
## Putting colour back in the bucket key is the regression the baker's own
## comment forbids, and `tests/structure_edge_test.gd` measures the consequence
## with RenderingServer's draw-call counter rather than trusting node counts.
##
## ── Why a rectangle list, and not an arbitrary polygon ──────────────────────
## Because the whole construction layer is box-native: `_append_box` emits 36
## unindexed verts, `collect_colliders` returns oriented boxes, and what you see
## is what you collide with. A profile that could not be expressed as boxes
## would draw geometry the player could walk through. Curved sections (a
## D-fender lobe, a pipe) are approximated by ROLLING rects about the tangent,
## which stays inside that contract and costs 2–3 boxes per segment.

const StructureBakerScript := preload("res://scripts/construction/structure_baker.gd")

## Minimum overlap between two consecutive swept segments. Same purpose as
## StructureBaker.SKIN_EPS: abutting solids must never share a plane, or the
## joint z-fights. A straight subdivision (deviation angle 0) gets exactly this
## and nothing more.
const JOINT_EPS := 0.005
## A mitre may not extend a segment further than this many times its own
## cross-section, however sharp the turn — a hairpin would otherwise run away.
const MAX_MITRE_FACTOR := 2.5
## Degenerate segments (a duplicated path point) are dropped, not divided by.
const MIN_SEGMENT_M := 0.001

## Guardrail defaults, sized against the 1.8 m figure.
const DEFAULT_RAIL_HEIGHT := 1.1      ## SOLAS minimum is 1.0 m; 1.1 is typical.
const DEFAULT_POST_PITCH := 1.6       ## stanchion spacing; 1.5 m is the usual max.
const DEFAULT_RAIL_COUNT := 3
const DEFAULT_POST_WIDTH := 0.05      ## 50 mm stanchion — one tenth of a deck cell.
const DEFAULT_RAIL_WIDTH := 0.04      ## 40 mm tube, drawn square.
const DEFAULT_TOE_THICKNESS := 0.012
## No opening between courses may exceed this. With courses spread evenly over
## the clear height, `height / rails` is the gap, so this is a checkable
## property of the emitted geometry rather than a comment.
const MAX_RAIL_GAP_M := 0.38

## LOD. A harbour full of stanchions is the case the draw-call budget exists
## for, so the switch distance is DERIVED from when a stanchion stops resolving
## rather than picked: see `lod_switch_distance_m`.
const LOD_FULL := 0
const LOD_PANEL := 1
const LOD_CULLED := 2
const LOD_REFERENCE_FOV := 70.0
const LOD_REFERENCE_PX := 1280.0

## Ten cross-sections, each a list of rects in the sweep's local (u, v) frame:
##   u  lateral offset from the path, outboard positive
##   v  vertical offset from the path
##   w  lateral size,  h  vertical size
##   roll  degrees about the tangent, for sections that are not axis-aligned
##
## Every one of these is a part COMPONENTS.md lists separately. They share one
## emitter and one test. Adding the eleventh is data.
const PROFILE_LIBRARY: Dictionary = {
	## Bulwark cap band — the sheer line itself on a real boat. `v` puts its
	## UNDERSIDE on the path, not its centre: swept along `sheer_path`, whose Y
	## is `deck_y + rise`, that means no vertex of the cap can land below
	## `deck_y`. The loft has zero headroom above `deck_y` (STATE.md), so a cap
	## centred on the line would push 30 mm of geometry into the deck plate.
	"cap_rail": [{"u": 0.0, "v": 0.03, "w": 0.22, "h": 0.06}],
	## Half-round rubbing strake, drawn as a proud rectangle.
	"rubbing_strake": [{"u": 0.0, "v": 0.0, "w": 0.09, "h": 0.16}],
	## The topmost strake of plating, a band not a moulding.
	"sheer_strake": [{"u": 0.0, "v": 0.0, "w": 0.02, "h": 0.45}],
	## Paint only: 12 mm proud so it never z-fights the shell it sits on.
	"boot_top": [{"u": 0.0, "v": 0.0, "w": 0.012, "h": 0.30}],
	## D-section fender: three rolled rects make the lobe.
	"d_fender": [
		{"u": 0.02, "v": 0.0, "w": 0.05, "h": 0.24},
		{"u": 0.055, "v": 0.07, "w": 0.09, "h": 0.09, "roll": 45.0},
		{"u": 0.055, "v": -0.07, "w": 0.09, "h": 0.09, "roll": -45.0},
	],
	## Knuckle/spray deflector: a rect rolled down so it throws water clear.
	"spray_rail": [{"u": 0.0, "v": 0.0, "w": 0.16, "h": 0.03, "roll": -28.0}],
	## L-section stringer: web plus flange.
	"stringer_l": [
		{"u": 0.0, "v": 0.055, "w": 0.012, "h": 0.11},
		{"u": 0.03, "v": 0.0, "w": 0.07, "h": 0.012},
	],
	## Flat bar bolted to the topsides — a shroud lands on this.
	"chainplate": [{"u": 0.0, "v": 0.0, "w": 0.014, "h": 0.36}],
	## Octagonal approximation of a pipe: two rects at 45°.
	"pipe_run": [
		{"u": 0.0, "v": 0.0, "w": 0.09, "h": 0.09},
		{"u": 0.0, "v": 0.0, "w": 0.083, "h": 0.083, "roll": 45.0},
	],
	## Kick plate at the foot of a railing; stops a dropped tool going over.
	"toe_board": [{"u": 0.0, "v": 0.05, "w": 0.012, "h": 0.10}],
}


# ── The primitive: a cross-section swept along a 3D polyline ─────────────────

## `spec` keys (all optional unless noted):
##   path         Array/PackedVector3Array of >= 2 points          REQUIRED
##   closed       bool — join the last point back to the first
##   profile      String naming PROFILE_LIBRARY, or an Array of rect dicts.
##                Absent: one rect built from `width` x `thickness`.
##   width        lateral size of the fallback rect
##   thickness    vertical size of the fallback rect
##   offset       Vector3 added to every path point
##   up           reference up vector for the sweep frame (default Vector3.UP)
##   color        Color for every rect that does not override it
##   material     StructureBaker.MATERIALS key, likewise
##   mitre        bool, default true — extend segments into their joints
##
## Returns boxes {center, size, basis, color, material}. `size` is read in the
## box's OWN frame, exactly as StructureBaker.wall_boxes documents.
static func sweep_boxes(spec: Dictionary) -> Array:
	var path := _points_of(spec.get("path", []))
	var offset := _vec3_of(spec.get("offset", Vector3.ZERO))
	if not offset.is_zero_approx():
		var shifted := PackedVector3Array()
		for p in path:
			shifted.append(p + offset)
		path = shifted
	var closed := bool(spec.get("closed", false))
	var segments := _segments_of(path, closed)
	if segments.is_empty():
		return []

	var profile := resolve_profile(spec)
	if profile.is_empty():
		return []

	var up_ref := _vec3_of(spec.get("up", Vector3.UP))
	var mitre := bool(spec.get("mitre", true))
	var base_color := _color_of(spec.get("color", Color.WHITE))
	var base_material := str(spec.get("material", "painted"))

	var boxes: Array = []
	for rect_variant in profile:
		var rect := rect_variant as Dictionary
		var w := float(rect.get("w", 0.0))
		var h := float(rect.get("h", 0.0))
		if w <= 0.0 or h <= 0.0:
			continue
		var color := _color_of(rect.get("color", base_color))
		var material := str(rect.get("material", base_material))
		var roll := float(rect.get("roll", 0.0))
		var u := float(rect.get("u", 0.0))
		var v := float(rect.get("v", 0.0))
		for i in segments.size():
			var seg := segments[i] as Dictionary
			var a := seg["a"] as Vector3
			var length := float(seg["length"])
			var tangent := seg["tangent"] as Vector3
			var frame := _frame(tangent, up_ref, roll)
			var right := frame[0] as Vector3
			var up := frame[1] as Vector3
			var ext_start := 0.0
			var ext_end := 0.0
			if mitre:
				ext_start = _mitre_extension(segments, i, -1, w, h, right, up, length)
				ext_end = _mitre_extension(segments, i, 1, w, h, right, up, length)
			var centre_line := a + tangent * (length * 0.5 + (ext_end - ext_start) * 0.5)
			boxes.append({
				"center": centre_line + right * u + up * v,
				"size": Vector3(w, h, length + ext_start + ext_end),
				"basis": Basis(right, up, tangent),
				"color": color,
				"material": material,
			})
	return boxes


## The name PartCatalog.PRIMITIVES["sheer_band"].emitter resolves to. Identical
## to `sweep_boxes` — the sheer band IS the swept profile, which is the whole
## generalisation. Kept as a distinct entry point so the catalog's declared
## seam is real rather than aspirational.
static func sheer_band_boxes(spec: Dictionary) -> Array:
	return sweep_boxes(spec)


## The rect list a spec asks for: a library name, an inline list, or the
## width x thickness fallback the catalog's `sheer_band` fields already carry.
static func resolve_profile(spec: Dictionary) -> Array:
	var raw: Variant = spec.get("profile", null)
	if raw is String:
		var name := (raw as String).strip_edges()
		if not PROFILE_LIBRARY.has(name):
			push_error(
				"StructureEdge: no profile \"%s\" — the library holds %s"
				% [name, ", ".join(PackedStringArray(PROFILE_LIBRARY.keys()))]
			)
			return []
		return (PROFILE_LIBRARY[name] as Array).duplicate(true)
	if raw is Array:
		var out: Array = []
		for entry in raw as Array:
			if entry is Dictionary:
				out.append((entry as Dictionary).duplicate(true))
			else:
				push_error("StructureEdge: profile entries must be {u,v,w,h[,roll]} objects")
		return out
	var width := float(spec.get("width", 0.0))
	var thickness := float(spec.get("thickness", 0.0))
	if width <= 0.0 or thickness <= 0.0:
		push_error("StructureEdge: a sweep needs a profile, or a positive width and thickness")
		return []
	return [{"u": 0.0, "v": 0.0, "w": width, "h": thickness}]


# ── The primitive: a railing run ─────────────────────────────────────────────

## `spec` keys:
##   path         Array/PackedVector3Array of >= 2 points          REQUIRED
##                The DECK-EDGE line: posts rise from it, rails sit above it.
##   height       clear height of the top rail above the path      REQUIRED
##   post_pitch   maximum stanchion spacing (default 1.6 m)
##   rails        number of horizontal courses (default 3)
##   toe_height   solid kick plate from the path up to this (default 0 = none)
##   post_width   stanchion section (default 0.05 m, square)
##   rail_width   rail section (default 0.04 m, square)
##   closed / offset / up / color / material — as `sweep_boxes`
##
## Rails and the toe board ARE swept profiles: this function builds their rect
## list and calls `sweep_boxes`. Only the stanchions are emitted directly,
## because a stanchion is vertical in WORLD space even where the run slopes —
## a railing following a sheer curve leans its rails, never its posts.
static func railing_boxes(spec: Dictionary) -> Array:
	var path := _points_of(spec.get("path", []))
	var closed := bool(spec.get("closed", false))
	if _segments_of(path, closed).is_empty():
		return []
	var height := float(spec.get("height", DEFAULT_RAIL_HEIGHT))
	if height <= 0.0:
		push_error("StructureEdge: a railing needs a positive height")
		return []

	var boxes: Array = []
	var sweep := spec.duplicate(true)
	sweep["profile"] = railing_profile(spec)
	sweep.erase("width")
	sweep.erase("thickness")
	boxes.append_array(sweep_boxes(sweep))
	boxes.append_array(_post_boxes(spec))
	return boxes


## The rect list for one railing's rails plus its toe board — i.e. everything in
## a railing that is a swept section. Exposed because it is also the honest
## answer to "what is a railing made of": courses at even heights.
##
## Courses are spread evenly over the CLEAR height (above any toe board), so
## the opening between courses is `clear / rails` and grows only if a caller
## asks for fewer rails on a taller run. `max_rail_gap_m` reports it.
static func railing_profile(spec: Dictionary) -> Array:
	var height := float(spec.get("height", DEFAULT_RAIL_HEIGHT))
	var rails := maxi(int(spec.get("rails", DEFAULT_RAIL_COUNT)), 1)
	var toe := maxf(float(spec.get("toe_height", 0.0)), 0.0)
	var rail_w := maxf(float(spec.get("rail_width", DEFAULT_RAIL_WIDTH)), 0.001)
	var out: Array = []
	if toe > 0.0:
		out.append({
			"u": 0.0, "v": toe * 0.5,
			"w": maxf(float(spec.get("toe_thickness", DEFAULT_TOE_THICKNESS)), 0.001),
			"h": toe,
		})
	var base := minf(toe, height)
	var clear := maxf(height - base, 0.0)
	for j in range(1, rails + 1):
		out.append({
			"u": 0.0,
			"v": base + clear * float(j) / float(rails),
			"w": rail_w, "h": rail_w,
		})
	return out


## Largest opening between courses, in metres. A railing whose gap exceeds
## MAX_RAIL_GAP_M lets a person through it, which is the entire reason the
## primitive is non-optional on a passenger vessel.
static func max_rail_gap_m(spec: Dictionary) -> float:
	var height := float(spec.get("height", DEFAULT_RAIL_HEIGHT))
	var rails := maxi(int(spec.get("rails", DEFAULT_RAIL_COUNT)), 1)
	var toe := maxf(float(spec.get("toe_height", 0.0)), 0.0)
	return maxf(height - minf(toe, height), 0.0) / float(rails)


## Stanchion positions along the run: one at every path vertex, and enough
## between them that no span exceeds `post_pitch`. Returned as world points on
## the path, so a caller can hang something else off them (a gate, a light).
static func post_points(spec: Dictionary) -> PackedVector3Array:
	var path := _points_of(spec.get("path", []))
	var offset := _vec3_of(spec.get("offset", Vector3.ZERO))
	var closed := bool(spec.get("closed", false))
	var segments := _segments_of(path, closed)
	var pitch := maxf(float(spec.get("post_pitch", DEFAULT_POST_PITCH)), 0.05)
	var out := PackedVector3Array()
	for i in segments.size():
		var seg := segments[i] as Dictionary
		var a := (seg["a"] as Vector3) + offset
		var b := (seg["b"] as Vector3) + offset
		var count := maxi(int(ceil(float(seg["length"]) / pitch)), 1)
		var last := count if (i == segments.size() - 1 and not closed) else count - 1
		for k in range(0, last + 1):
			out.append(a.lerp(b, float(k) / float(count)))
	return out


static func _post_boxes(spec: Dictionary) -> Array:
	var height := float(spec.get("height", DEFAULT_RAIL_HEIGHT))
	var width := maxf(float(spec.get("post_width", DEFAULT_POST_WIDTH)), 0.001)
	var color := _color_of(spec.get("color", Color.WHITE))
	var material := str(spec.get("material", "painted"))
	var path := _points_of(spec.get("path", []))
	var closed := bool(spec.get("closed", false))
	var segments := _segments_of(path, closed)
	var offset := _vec3_of(spec.get("offset", Vector3.ZERO))
	var out: Array = []
	for i in segments.size():
		var seg := segments[i] as Dictionary
		var count := maxi(
			int(ceil(float(seg["length"]) / maxf(float(spec.get("post_pitch", DEFAULT_POST_PITCH)), 0.05))),
			1
		)
		var last := count if (i == segments.size() - 1 and not closed) else count - 1
		## Posts stand vertical in WORLD space. Yaw follows the run's plan
		## direction so a post on a diagonal is square to the rail; pitch and
		## roll are deliberately dropped, because a stanchion on a sheer-swept
		## rail is plumb, not normal to the rail.
		var yaw_basis := _yaw_basis(seg["tangent"] as Vector3)
		var a := (seg["a"] as Vector3) + offset
		var b := (seg["b"] as Vector3) + offset
		for k in range(0, last + 1):
			var foot := a.lerp(b, float(k) / float(count))
			out.append({
				"center": foot + Vector3(0.0, height * 0.5, 0.0),
				"size": Vector3(width, height, width),
				"basis": yaw_basis,
				"color": color,
				"material": material,
			})
	return out


# ── LOD: a harbour full of stanchions ───────────────────────────────────────

## Distance at which a feature of `feature_m` stops resolving.
##
## A pinhole camera of `fov_deg` across `viewport_px` gives
## `fov / px` radians per pixel; a feature subtends `min_px` pixels at
##     d = feature / (rad_per_px * min_px).
## For the shipped defaults (0.05 m stanchion, 1280 px, 70°, 1 px) that is
## 52.4 m — beyond it the posts are literally sub-pixel and the 31 boxes
## drawing them are paying for nothing.
static func lod_switch_distance_m(
	feature_m: float,
	viewport_px: float = LOD_REFERENCE_PX,
	fov_deg: float = LOD_REFERENCE_FOV,
	min_px: float = 1.0,
) -> float:
	var rad_per_px := deg_to_rad(maxf(fov_deg, 0.01)) / maxf(viewport_px, 1.0)
	return maxf(feature_m, 0.0) / maxf(rad_per_px * min_px, 1e-9)


## LOD_FULL / LOD_PANEL / LOD_CULLED for one railing seen from `distance_m`.
## Two thresholds, both derived: the posts stop resolving (switch to the panel)
## and then the whole rail stops resolving at two pixels (cull it).
static func railing_lod_for_distance(
	spec: Dictionary,
	distance_m: float,
	viewport_px: float = LOD_REFERENCE_PX,
	fov_deg: float = LOD_REFERENCE_FOV,
) -> int:
	var post := maxf(float(spec.get("post_width", DEFAULT_POST_WIDTH)), 0.001)
	var height := maxf(float(spec.get("height", DEFAULT_RAIL_HEIGHT)), 0.001)
	if distance_m < lod_switch_distance_m(post, viewport_px, fov_deg, 1.0):
		return LOD_FULL
	if distance_m < lod_switch_distance_m(height, viewport_px, fov_deg, 2.0):
		return LOD_PANEL
	return LOD_CULLED


## Geometry for one railing at one level of detail.
##
## LOD_PANEL collapses posts, rails and toe board into ONE swept band. Its top
## face is placed at exactly the top rail's top face and its lateral extent is
## the stanchion width, so the switch changes density and never silhouette:
## nothing moves sideways and nothing moves up. That is the property that makes
## the seam safe to flip at any distance, and it is asserted rather than
## asserted-to-be-obvious.
static func railing_lod_boxes(spec: Dictionary, lod: int) -> Array:
	match lod:
		LOD_FULL:
			return railing_boxes(spec)
		LOD_PANEL:
			var height := float(spec.get("height", DEFAULT_RAIL_HEIGHT))
			var rail_w := maxf(float(spec.get("rail_width", DEFAULT_RAIL_WIDTH)), 0.001)
			var top := float(spec.get("lod_panel_top", height + rail_w * 0.5))
			var base := float(spec.get("lod_panel_base", 0.0))
			var span := maxf(top - base, 0.001)
			var sweep := spec.duplicate(true)
			sweep.erase("width")
			sweep.erase("thickness")
			sweep["profile"] = [{
				"u": 0.0, "v": base + span * 0.5,
				"w": maxf(float(spec.get("post_width", DEFAULT_POST_WIDTH)), 0.001),
				"h": span,
			}]
			return sweep_boxes(sweep)
		_:
			return []


# ── Collision: the reason a railing is not decoration ───────────────────────

## One barrier box per run segment, in the {center, size, yaw_deg} shape
## `StructureBaker.collect_colliders` already returns.
##
## Deliberately NOT one collider per rail and post: a body must not be able to
## pass BETWEEN the courses, and 3 barriers are cheaper than 43 boxes. The box
## spans the full height of the railing over the segment, and on a sloping run
## it spans from the lower end's foot to the higher end's top — conservative in
## Y, which is the correct direction to err for a fall barrier.
static func railing_collider_boxes(spec: Dictionary) -> Array:
	var path := _points_of(spec.get("path", []))
	var offset := _vec3_of(spec.get("offset", Vector3.ZERO))
	var closed := bool(spec.get("closed", false))
	var height := float(spec.get("height", DEFAULT_RAIL_HEIGHT))
	var thickness := maxf(float(spec.get("post_width", DEFAULT_POST_WIDTH)), 0.001)
	var out: Array = []
	for seg_variant in _segments_of(path, closed):
		var seg := seg_variant as Dictionary
		var a := (seg["a"] as Vector3) + offset
		var b := (seg["b"] as Vector3) + offset
		var y_low := minf(a.y, b.y)
		var y_high := maxf(a.y, b.y) + height
		var plan_length := Vector2(b.x - a.x, b.z - a.z).length()
		if plan_length < MIN_SEGMENT_M:
			continue
		out.append({
			"center": Vector3((a.x + b.x) * 0.5, (y_low + y_high) * 0.5, (a.z + b.z) * 0.5),
			"size": Vector3(thickness, y_high - y_low, plan_length),
			"yaw_deg": rad_to_deg(atan2(b.x - a.x, b.z - a.z)),
		})
	return out


# ── Consuming HullStations: the sheer curve, applied at last ────────────────

## Deck-edge half-beam at ship-local `z`, linearly interpolated between the two
## bracketing stations. `HullStations.half_beam_at` is per-station; a swept band
## needs it per-point.
static func deck_half_beam_at(stations: HullStations, z: float, y_local: float = NAN) -> float:
	if stations == null or stations.stations.is_empty():
		return 0.0
	var y := stations.deck_y if is_nan(y_local) else y_local
	var count: int = stations.stations.size()
	if count == 1:
		return stations.half_beam_at(0, y)
	var first := float((stations.stations[0] as Dictionary)["z"])
	var last := float((stations.stations[count - 1] as Dictionary)["z"])
	if z <= first:
		return stations.half_beam_at(0, y)
	if z >= last:
		return stations.half_beam_at(count - 1, y)
	for i in range(count - 1):
		var z0 := float((stations.stations[i] as Dictionary)["z"])
		var z1 := float((stations.stations[i + 1] as Dictionary)["z"])
		if z >= z0 and z <= z1 and z1 - z0 > 1e-6:
			var t := (z - z0) / (z1 - z0)
			return lerpf(stations.half_beam_at(i, y), stations.half_beam_at(i + 1, y), t)
	return stations.half_beam_at(count - 1, y)


## The deck-edge polyline down ONE side, with Y taken from the hull's own sheer
## curve. `side` is +1 starboard, -1 port. Bow is −Z.
##
## This is the consumption STATE.md says is missing. `HullStations.sheer_ends`,
## `sheer_rise_at` and `sheer_cap_y_at` have derived the curve per hull all
## along and nothing has drawn it, because the LOFT may not draw it: `deck_y` is
## the floor of four other systems and the shell has zero headroom above it. The
## curve therefore belongs to whatever can also collide it — this layer — and it
## enters the world as a bulwark cap, which is what it is on a real boat.
##
## Every point is at or ABOVE `deck_y` by construction (`sheer_cap_y_at` is
## `deck_y + rise`, and rise is non-negative), so a band swept along it can
## never intrude into the deck plate, the plan's colliders or the loft.
## `y_offset` moves the band off the cap: 0 is the cap itself, −1.2 is a rubbing
## strake a metre and a bit down the topsides. The half-beam is read at the
## band's OWN height, not at the deck, so a band low on a flared hull follows
## the narrower section it actually sits on.
##
## `follow_sheer` false holds the band at a constant Y (`deck_y + y_offset`),
## which is what a boot top or an anti-fouling line does — those are parallel to
## the WATERLINE, not to the sheer. One flag, two real behaviours; a boot top
## drawn with sheer would be wrong in the same way a cap rail drawn flat is.
static func sheer_path(
	stations: HullStations,
	side: float = 1.0,
	samples: int = 15,
	inset_m: float = 0.0,
	y_offset: float = 0.0,
	follow_sheer: bool = true,
	z_from: float = NAN,
	z_to: float = NAN,
) -> PackedVector3Array:
	var out := PackedVector3Array()
	if stations == null or stations.stations.is_empty():
		push_error("StructureEdge.sheer_path: no stations")
		return out
	var half := stations.length_m * 0.5
	var a := -half if is_nan(z_from) else z_from
	var b := half if is_nan(z_to) else z_to
	var n := maxi(samples, 2)
	var sign := 1.0 if side >= 0.0 else -1.0
	for i in range(n):
		var z := lerpf(a, b, float(i) / float(n - 1))
		var y := (stations.sheer_cap_y_at(z) if follow_sheer else stations.deck_y) + y_offset
		var x := maxf(deck_half_beam_at(stations, z, y) - inset_m, 0.0) * sign
		out.append(Vector3(x, y, z))
	return _dedupe(out)


## The full closed deck-edge loop: starboard bow→stern, then port stern→bow.
## This is the path a bulwark cap, a perimeter railing or a rubbing strake runs
## along, and it is the only path most vessels need.
static func sheer_loop(
	stations: HullStations,
	samples: int = 15,
	inset_m: float = 0.0,
	y_offset: float = 0.0,
	follow_sheer: bool = true,
) -> PackedVector3Array:
	var starboard := sheer_path(stations, 1.0, samples, inset_m, y_offset, follow_sheer)
	var port := sheer_path(stations, -1.0, samples, inset_m, y_offset, follow_sheer)
	var out := PackedVector3Array(starboard)
	for i in range(port.size() - 1, -1, -1):
		out.append(port[i])
	return _dedupe(out)


# ── Measurement ─────────────────────────────────────────────────────────────

## 12 triangles per box — `StructureBaker._append_box` emits 6 faces x 2 tris,
## unindexed, 36 verts. Reported so a plan's cost is knowable before it bakes.
static func triangle_count(boxes: Array) -> int:
	return boxes.size() * 12


## Total swept length of a path, in metres. Reported alongside triangle counts
## so "1300 triangles over 45 m" is a ratio anyone can re-derive.
static func path_length_m(path: Variant, closed: bool = false) -> float:
	var points := _points_of(path)
	var total := 0.0
	for seg_variant in _segments_of(points, closed):
		total += float((seg_variant as Dictionary)["length"])
	return total


## World-space AABB of a box list, honouring each box's own basis.
static func boxes_aabb(boxes: Array) -> AABB:
	var out := AABB()
	var first := true
	for box_variant in boxes:
		var box := box_variant as Dictionary
		var centre := box["center"] as Vector3
		var half := (box["size"] as Vector3) * 0.5
		var basis := box.get("basis", Basis.IDENTITY) as Basis
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					var corner: Vector3 = centre + basis * Vector3(
						half.x * sx, half.y * sy, half.z * sz
					)
					if first:
						out = AABB(corner, Vector3.ZERO)
						first = false
					else:
						out = out.expand(corner)
	return out


## True when `point` lies inside any emitted box. Used to prove joints are
## filled and that a railing actually blocks the space a body would fall
## through — a claim about coverage cannot be made from a box count.
static func point_inside_any(boxes: Array, point: Vector3, slack: float = 0.0) -> bool:
	for box_variant in boxes:
		var box := box_variant as Dictionary
		var basis := box.get("basis", Basis.IDENTITY) as Basis
		var local: Vector3 = basis.transposed() * (point - (box["center"] as Vector3))
		var half := (box["size"] as Vector3) * 0.5 + Vector3.ONE * slack
		if absf(local.x) <= half.x and absf(local.y) <= half.y and absf(local.z) <= half.z:
			return true
	return false


# ── Merging: boxes -> Node3D, through StructureBaker's own bucketing ────────

## Build the merged visual for a standalone box list.
##
## This exists for the LOD path, which rebuilds a railing's geometry at runtime
## without re-baking the plan it came from, and for tests that must count real
## draw calls. It does NOT re-implement the bucketing rule: it calls
## `StructureBaker._bucket_layer`, so the key is MATERIAL ALONE here for exactly
## the reason it is there, and a change to that rule cannot silently diverge.
##
## (The underscore is the baker's, not a claim of privacy from GDScript. When
## the baker's owner promotes it to a public `bucket_layer()`, this call moves
## with it and nothing else changes.)
static func bake_boxes(boxes: Array, offset: Vector3 = Vector3.ZERO) -> Node3D:
	var root := Node3D.new()
	root.name = "StructureEdgeBake"
	var buckets: Dictionary = {}
	for box_variant in boxes:
		StructureBakerScript._bucket_layer(buckets, box_variant as Dictionary, offset)
	for key in buckets.keys():
		var bucket := buckets[key] as Dictionary
		var st := bucket["st"] as SurfaceTool
		var material := StandardMaterial3D.new()
		material.albedo_color = Color.WHITE
		material.vertex_color_use_as_albedo = true
		var response: Dictionary = StructureBakerScript.MATERIALS.get(
			str(bucket["material"]), StructureBakerScript.MATERIALS["painted"]
		)
		material.roughness = float(response["roughness"])
		material.metallic = float(response["metallic"])
		st.set_material(material)
		var mesh := st.commit()
		if mesh != null and mesh.get_surface_count() > 0:
			var instance := MeshInstance3D.new()
			instance.name = "Edge_%s" % str(key)
			instance.mesh = mesh
			root.add_child(instance)
	return root


# ── Internals ───────────────────────────────────────────────────────────────

## Segments as {a, b, tangent, length}. Degenerate (duplicated) points drop out
## here so no downstream code divides by a zero length.
static func _segments_of(path: PackedVector3Array, closed: bool) -> Array:
	var out: Array = []
	var n := path.size()
	if n < 2:
		return out
	var count := n if closed else n - 1
	for i in range(count):
		var a := path[i]
		var b := path[(i + 1) % n]
		var delta := b - a
		var length := delta.length()
		if length < MIN_SEGMENT_M:
			continue
		out.append({"a": a, "b": b, "tangent": delta / length, "length": length})
	return out


## Mitre extension at one end of segment `i`. `direction` is -1 for the start
## end, +1 for the finish end.
##
## Two bands of half-extent `reach` meeting with a deviation angle δ leave an
## unfilled wedge on the outside of the turn; extending each by `reach·tan(δ/2)`
## fills it. δ = 0 (a straight subdivision) therefore extends by nothing, which
## would leave two coplanar internal faces — so JOINT_EPS is the floor, for the
## same reason StructureBaker keeps SKIN_EPS.
##
## `reach` is the section's half-extent MEASURED IN THE PLANE OF THE TURN, not
## half its largest dimension. Those are wildly different for a tall thin
## section: a 0.05 x 1.12 m LOD panel turning a corner in plan needs 25 mm of
## mitre, and half-of-largest would give it 560 mm — a corner sticking half a
## metre out past the railing it replaced. Measured: that error alone made the
## panel's footprint 13.62 m across a 12.55 m railing.
static func _mitre_extension(
	segments: Array,
	i: int,
	direction: int,
	w: float,
	h: float,
	right: Vector3,
	up: Vector3,
	length: float,
) -> float:
	var count := segments.size()
	if count < 2:
		return 0.0
	var neighbour := i - 1 if direction < 0 else i + 1
	if neighbour < 0 or neighbour >= count:
		## An open run's outer ends are butt ends: nothing to mitre into.
		return 0.0
	var here := (segments[i] as Dictionary)["tangent"] as Vector3
	var there := (segments[neighbour] as Dictionary)["tangent"] as Vector3
	var deviation := acos(clampf(here.dot(there), -1.0, 1.0))
	var bend := here.cross(there)
	var reach := 0.5 * maxf(w, h)
	if bend.length_squared() > 1e-12:
		## `outward` is perpendicular to this segment and lies in the bend
		## plane — the exact direction the unfilled wedge opens toward.
		var outward := bend.normalized().cross(here).normalized()
		reach = absf(right.dot(outward)) * w * 0.5 + absf(up.dot(outward)) * h * 0.5
	var extension := maxf(reach * tan(deviation * 0.5), JOINT_EPS)
	extension = minf(extension, maxf(reach, JOINT_EPS) * MAX_MITRE_FACTOR)
	extension = minf(extension, length * 0.5)
	extension = minf(extension, float((segments[neighbour] as Dictionary)["length"]) * 0.5)
	return extension


## Orthonormal, right-handed [right, up] for a tangent.
##
## `right = up_ref x tangent` and `up = tangent x right` give det(right, up,
## tangent) = +1. The other order gives −1, which is a REFLECTION: it would
## invert `_append_box`'s winding and turn every face of every swept box
## inside out while looking perfectly plausible in a box count.
static func _frame(tangent: Vector3, up_ref: Vector3, roll_deg: float = 0.0) -> Array:
	var reference := up_ref.normalized()
	if reference.length_squared() < 0.5 or absf(tangent.dot(reference)) > 0.999:
		reference = Vector3.FORWARD if absf(tangent.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var right := reference.cross(tangent).normalized()
	var up := tangent.cross(right).normalized()
	if not is_zero_approx(roll_deg):
		var rot := Basis(tangent, deg_to_rad(roll_deg))
		right = (rot * right).normalized()
		up = (rot * up).normalized()
	return [right, up]


## Yaw-only basis whose Z is the tangent's plan direction — the frame a
## stanchion stands in. Degenerates to identity for a purely vertical run.
static func _yaw_basis(tangent: Vector3) -> Basis:
	var plan := Vector2(tangent.x, tangent.z)
	if plan.length_squared() < 1e-8:
		return Basis.IDENTITY
	return Basis(Vector3.UP, atan2(plan.x, plan.y))


static func _dedupe(path: PackedVector3Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	for p in path:
		if out.size() > 0 and out[out.size() - 1].distance_to(p) < MIN_SEGMENT_M:
			continue
		out.append(p)
	return out


static func _points_of(value: Variant) -> PackedVector3Array:
	if value is PackedVector3Array:
		return value as PackedVector3Array
	var out := PackedVector3Array()
	if not (value is Array):
		return out
	for entry in value as Array:
		out.append(_vec3_of(entry))
	return out


static func _vec3_of(value: Variant) -> Vector3:
	if value is Vector3:
		return value as Vector3
	if value is Array and (value as Array).size() >= 3:
		var list := value as Array
		return Vector3(float(list[0]), float(list[1]), float(list[2]))
	return Vector3.ZERO


static func _color_of(value: Variant) -> Color:
	if value is Color:
		return value as Color
	if value is String and Color.html_is_valid(value as String):
		return Color(value as String)
	if value is Array and (value as Array).size() >= 3:
		var list := value as Array
		return Color(float(list[0]), float(list[1]), float(list[2]))
	return Color.WHITE
