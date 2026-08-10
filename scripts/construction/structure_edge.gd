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
## ── THE SHEER BAND, and why it is the primitive that matters ────────────────
## Squinted, this project's vessels read as two parallel horizontal bars: the
## hull's top edge dead straight from stem to transom, and above it a bulwark of
## constant height the full length. A working boat reads by its SHEER — the deck
## edge sweeping up toward the bow — and that single curve is most of what says
## "boat" at a distance.
##
## The curve has existed, derived per hull, since `HullStations.sheer_ends` was
## written, and nothing has ever drawn it. It cannot come from the loft (the
## shell has zero headroom above `deck_y`, which is the floor of the deck plate,
## the DeckGrid, the walk colliders and the buoyancy sample — see the long note
## in `hull_stations.gd`). On a real boat the sheer line IS the bulwark cap, and
## a bulwark is drawn and collided by this layer. So it is drawn here.
##
## Drawing it needed one generalisation, and only one: a swept profile's rects
## had a FIXED cross-section, and a bulwark does not have one. Its plating is
## 1.1 m tall amidships and 2.0 m at the stem of the same run. The `to_base` rect
## key is that generalisation — THE PATH CARRIES THE HEIGHT — and everything
## else in the bulwark (`bulwark_profile`, `sheer_samples_for`,
## `sheer_bulwark_spec`, `sweep_collider_boxes`) is assembly around it.
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
## and inside `StructureBaker.bake()`, immediately after the `items` loop and
## before `for key in buckets.keys()`:
##
##     for edge_variant in plan.edges:
##         for box_variant in StructureEdge.sheer_band_boxes(
##             edge_spec(plan, edge_variant as Dictionary)
##         ):
##             _bucket_layer(buckets, box_variant as Dictionary, offset, ghost)
##
## and the matching three lines in `StructureBaker.collect_colliders()`, after
## the `plan.items` loop — `sweep_collider_boxes` already returns exactly the
## {center, size, yaw_deg} dictionary `_collider_of` consumes, so it is the same
## one-liner every other entity gets:
##
##     for edge_variant in plan.edges:
##         for box_variant in StructureEdge.sweep_collider_boxes(
##             edge_spec(plan, edge_variant as Dictionary)
##         ):
##             out.append(_collider_of(box_variant as Dictionary, offset))
##
## with one shared resolver, because an `edges[]` entry may name the HULL as the
## source of its path rather than writing the polyline out by hand — which is
## the whole point of the sheer band, and is what
## `resources/data/structures/probe_sheer_bulwark.json` does:
##
##     static func edge_spec(plan: StructurePlan, edge: Dictionary) -> Dictionary:
##         if not edge.has("from_hull"):
##             return edge
##         return StructureEdge.sheer_bulwark_spec(
##             HullRegistry.make_stations(plan.hull_id), edge
##         )
##
## Two things this needs that are NOT in this file and are named here so they do
## not get lost:
##   • `StructurePlan` has no `edges` field yet. It needs one in `from_dict`,
##     `to_dict` and `entity_count`, in the same three-line shape as `stairs`.
##   • `HullRegistry` has no `make_stations(hull_id)`. Today the only route to a
##     hull's HullStations is through a BoatBody — `HullPhysicsProfile.make_stations()`
##     off `CatalogHullVessel.make_physics_profile()` or
##     `FishingTrawlerSmall.make_physics_profile()` — which drags the autoload
##     identifiers a `--script` test cannot compile. A static registry lookup
##     alongside `make_grid()` is the missing seam, and it is why both fixtures
##     here restate their hull's numbers and why
##     `tests/structure_sheer_capture.gd` asserts the restatement against the
##     hull the game actually builds.
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
## A bulwark's cap AMIDSHIPS, above the deck. Same number as the rail height and
## for the same reason: it is a fall barrier, and a fall barrier is sized against
## a person, not against the ship. It is the ONLY authored length in a bulwark —
## everything that makes one hull's bulwark differ from another's is the sheer,
## and the sheer is derived (see `sheer_bulwark_spec`).
const DEFAULT_BULWARK_HEIGHT := 1.1
## Bulwark plating: 100 mm reads as steel plate with its stiffeners behind it.
const DEFAULT_BULWARK_PLATE_M := 0.10
## The capping rail over it. Wider than the plating on purpose — a cap rail
## overhangs both faces, and the outboard overhang is what throws the shadow
## line that makes the sheer legible on the topsides at a distance.
const DEFAULT_CAP_WIDTH_M := 0.22
const DEFAULT_CAP_THICKNESS_M := 0.06
const DEFAULT_POST_PITCH := 1.6       ## stanchion spacing; 1.5 m is the usual max.
const DEFAULT_RAIL_COUNT := 3
const DEFAULT_POST_WIDTH := 0.05      ## 50 mm stanchion — one tenth of a deck cell.
const DEFAULT_RAIL_WIDTH := 0.04      ## 40 mm tube, drawn square.
const DEFAULT_TOE_THICKNESS := 0.012
## No opening between courses may exceed this. With courses spread evenly over
## the clear height, `height / rails` is the gap, so this is a checkable
## property of the emitted geometry rather than a comment.
const MAX_RAIL_GAP_M := 0.38

## Collision. A swept run thinner than this LATERALLY is a surface treatment on
## something that already collides — paint, plating, a strap — and emits no
## collider. 50 mm is not picked: it is DEFAULT_POST_WIDTH, the thinnest section
## in this file a person can walk into, and it sorts PROFILE_LIBRARY exactly
## along the line a shipwright would draw. Solid: cap rail (220 mm), bulwark
## plate (100), rubbing strake (90), pipe run (90), D-fender, spray rail,
## stringer. Not solid: boot top (12 mm of paint), sheer strake (20 mm of
## plating flush with the shell), chainplate (14), toe board (12, and the
## railing's own barrier already covers it).
const SWEEP_COLLIDER_MIN_M := 0.05
## Consecutive collider boxes on the same heading merge while the merge
## over-covers by no more than this. It buys ~4x fewer static shapes on a
## finely-sampled sheer run, and it over-covers UPWARD at hip height by at most
## 60 mm, which is a seventh of the player's 0.45 m step height and below
## anything a body can report. Set it to 0 for one collider per drawn segment.
const COLLIDER_MERGE_M := 0.06
## Floor on sheer sampling. A hull whose sheer is dead flat still has a curved
## deck edge in PLAN, and a two-point path would draw its bow taper as a
## straight line from stem to transom. One sample per metre keeps the plan error
## inside a 0.5 m deck cell on every hull in the catalog.
const PLAN_SAMPLE_M := 1.0

## LOD. A harbour full of stanchions is the case the draw-call budget exists
## for, so the switch distance is DERIVED from when a stanchion stops resolving
## rather than picked: see `lod_switch_distance_m`.
const LOD_FULL := 0
const LOD_PANEL := 1
const LOD_CULLED := 2
const LOD_REFERENCE_FOV := 70.0
const LOD_REFERENCE_PX := 1280.0

## Ten constant cross-sections, each a list of rects in the sweep's local
## (u, v) frame:
##   u  lateral offset from the path, outboard positive
##   v  vertical offset from the path
##   w  lateral size,  h  vertical size
##   roll  degrees about the tangent, for sections that are not axis-aligned
##   to_base  bool — THE PATH CARRIES THIS RECT'S HEIGHT. See below.
##
## ── `to_base`: the per-station height that makes a bulwark a bulwark ────────
## A rect without it has a fixed `h` and rides the tangent: swept along a rising
## path it stays the same size and simply tilts. That is right for a cap rail, a
## rubbing strake, a pipe — everything whose section is genuinely constant.
##
## It is WRONG for plating, and plating is the load-bearing case. A bulwark is
## not a constant-height band that happens to be lifted at the bow; it is a
## sheet of steel standing on the deck whose TOP EDGE is the sheer and whose
## bottom edge is the flat deck. Its height is 1.1 m amidships and 2.0 m at the
## stem of the same run. There is no cross-section to sweep, because the section
## is different at every station.
##
## `to_base` says so: the rect spans from the spec's `base_y` plane up to the
## path, and the path's Y is the height. That is the whole generalisation
## COMPONENTS.md asked for — "a cross-section extruded along a path, with the
## path carrying per-station height" — and it is one key.
##
## Such a rect is also PLUMB: it stands vertical in world space and takes only
## the run's yaw, exactly as a stanchion does, because plating stands up from a
## deck rather than normal to the rail above it. Its `h` and `roll` are ignored;
## its height per segment is taken at the segment's HIGHER end, so the band can
## over-run into the cap above it but can never leave a slot under it.
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

## The bulwark — the section the silhouette turns on — is deliberately NOT in
## the library above, and the reason is the whole point of `to_base`: every
## entry up there is a CONSTANT cross-section, and a bulwark does not have one.
## Its plating is 1.1 m tall amidships and 2.0 m at the stem of the same run.
## What is constant is its recipe, so the recipe is a function.
##
## The plate's top sits `overlap` above the path and the cap's underside sits ON
## the path, so the plating always runs into the cap: two abutting solids may
## not share a plane (JOINT_EPS, SKIN_EPS) and, more importantly, the plating's
## per-segment step then has somewhere to hide. `sheer_samples_for` sizes the
## sampling against the remaining headroom so the step never breaks back out
## through the cap's top face.
static func bulwark_profile(
	plate_m: float = DEFAULT_BULWARK_PLATE_M,
	cap_w: float = DEFAULT_CAP_WIDTH_M,
	cap_h: float = DEFAULT_CAP_THICKNESS_M,
	overlap: float = NAN,
) -> Array:
	var into_cap := (cap_h / 3.0) if is_nan(overlap) else overlap
	return [
		{"u": 0.0, "v": into_cap, "w": maxf(plate_m, 0.001), "to_base": true},
		{"u": 0.0, "v": cap_h * 0.5, "w": maxf(cap_w, plate_m), "h": maxf(cap_h, 0.001)},
	]


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
##   base_y       world Y of the plane a `to_base` rect stands on. REQUIRED as
##                soon as any rect in the profile sets `to_base`; without it a
##                bulwark would be built from the wrong deck.
##   solid        bool, default true — read by `sweep_collider_boxes` only
##
## Returns boxes {center, size, basis, color, material, segment}. `size` is read
## in the box's OWN frame, exactly as StructureBaker.wall_boxes documents.
## `segment` is the index of the path segment the box was emitted for; it is
## what lets `sweep_collider_boxes` collide EXACTLY the geometry this drew
## rather than a second, separately-derived approximation of it.
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

	var plan_segments: Array = []
	var boxes: Array = []
	for rect_variant in profile:
		var rect := rect_variant as Dictionary
		var w := float(rect.get("w", 0.0))
		var h := float(rect.get("h", 0.0))
		var color := _color_of(rect.get("color", base_color))
		var material := str(rect.get("material", base_material))
		if bool(rect.get("to_base", false)):
			if not spec.has("base_y"):
				push_error(
					"StructureEdge: a `to_base` rect takes its height from the path "
					+ "down to `base_y`, and this spec has no base_y"
				)
				continue
			if plan_segments.is_empty():
				plan_segments = _plan_segments(segments)
			boxes.append_array(_plumb_boxes(
				rect, segments, plan_segments, float(spec["base_y"]), mitre, closed, color, material
			))
			continue
		if w <= 0.0 or h <= 0.0:
			continue
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
				ext_start = _mitre_extension(segments, i, -1, w, h, right, up, length, closed)
				ext_end = _mitre_extension(segments, i, 1, w, h, right, up, length, closed)
			var centre_line := a + tangent * (length * 0.5 + (ext_end - ext_start) * 0.5)
			boxes.append({
				"center": centre_line + right * u + up * v,
				"size": Vector3(w, h, length + ext_start + ext_end),
				"basis": Basis(right, up, tangent),
				"color": color,
				"material": material,
				"segment": i,
			})
	return boxes


## One plumb, per-station-height band — the `to_base` case, and the reason a
## bulwark is not a bar. Vertical in WORLD space and carrying only the run's
## yaw, so it maps 1:1 onto the yaw-only collider contract with nothing
## approximated: what is drawn here IS what `sweep_collider_boxes` hands the
## physics server.
##
## Height per segment is taken at the segment's HIGHER end. The other two
## choices are both wrong and it is worth naming why, because the cheap one
## looks right in a triangle count: the lower end leaves a slot of exactly the
## segment's rise between the plating and the cap — a bulwark you can see the
## sea through — and the midpoint leaves half of one. Over-running into the cap
## is invisible; a slot is not.
static func _plumb_boxes(
	rect: Dictionary,
	segments: Array,
	plan_segments: Array,
	base_y: float,
	mitre: bool,
	closed: bool,
	color: Color,
	material: String,
) -> Array:
	var w := float(rect.get("w", 0.0))
	if w <= 0.0:
		return []
	var u := float(rect.get("u", 0.0))
	var v := float(rect.get("v", 0.0))
	var out: Array = []
	for i in segments.size():
		var plan := plan_segments[i] as Dictionary
		## A purely vertical segment has no plan run to stand a plate along.
		if not plan.has("tangent"):
			continue
		var seg := segments[i] as Dictionary
		var top := maxf((seg["a"] as Vector3).y, (seg["b"] as Vector3).y) + v
		var height := top - base_y
		if height <= 0.0:
			continue
		var tangent := plan["tangent"] as Vector3
		var length := float(plan["length"])
		var right := _frame(tangent, Vector3.UP)[0] as Vector3
		var ext_start := 0.0
		var ext_end := 0.0
		if mitre:
			## The turn is in the horizontal plane, so the section's reach into
			## the joint is its lateral half-width and its height contributes
			## nothing — pass 0 for `h` rather than let a 2 m tall plate mitre
			## itself a metre past the corner.
			ext_start = _mitre_extension(plan_segments, i, -1, w, 0.0, right, Vector3.UP, length, closed)
			ext_end = _mitre_extension(plan_segments, i, 1, w, 0.0, right, Vector3.UP, length, closed)
		var mid := (plan["a"] as Vector3) + tangent * (length * 0.5 + (ext_end - ext_start) * 0.5)
		out.append({
			"center": Vector3(mid.x, base_y + height * 0.5, mid.z) + right * u,
			"size": Vector3(w, height, length + ext_start + ext_end),
			"basis": _yaw_basis(tangent),
			"color": color,
			"material": material,
			"segment": i,
		})
	return out


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
				## Same tag `sweep_boxes` puts on its output, and for the same
				## consumer: `railing_collider_boxes` groups the drawn boxes by
				## segment and bounds each group, so a stanchion has to say
				## which segment it stands on or it would be drawn outside
				## every barrier.
				"segment": i,
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
##
## ── Why this bounds the drawn boxes instead of re-deriving the run ──────────
## It used to compute the barrier straight from the spec: `post_width` thick,
## spanning the segment's endpoints, `height` tall. Every one of those three
## terms was subtly wrong, and each was wrong for its own reason:
##
##   • `height` is the CLEAR height — the CENTRELINE of the top course, not its
##     top face. `railing_profile` draws that course as a `rail_width` square
##     straddling the centreline, so the rail reaches `height + rail_width/2`
##     and the top 20 mm of every railing in the project was un-collided.
##   • `post_width` is the widest section only because of the DEFAULTS. A spec
##     asking for 60 mm tube on 50 mm stanchions draws outside its own barrier.
##   • The segment endpoints are the PATH, but a mitred joint deliberately
##     overshoots the vertex to fill the wedge, by up to `MAX_MITRE_FACTOR`
##     times the section's reach. Every corner of every closed run leaked there.
##
## The first was found by the capture rig's corner-containment check on the
## container feeder (92 loose corners, drift exactly rail_width/2) and had been
## held in place by a unit test asserting the collider top EQUALLED `height`
## while the test twenty lines above it asserted the drawn top equalled
## `height + rail_width/2`. Fixing only that one exposed the third: 148 loose
## corners at the mitres, which no amount of care with the spec would have
## found, because the overshoot is not in the spec.
##
## That is the shape of the whole class, so the derivation is gone. This groups
## the boxes the run ACTUALLY DRAWS by their `segment` tag and takes the
## yaw-frame bounding box of each group — the identical mechanism, and now the
## identical code path, as `sweep_collider_boxes`. There is no second formula
## to keep in step, which is the mechanism behind both walk-through bugs this
## project has already fixed. Change what a railing looks like and the barrier
## changes with it.
##
## What stays deliberate is the GROUPING: one box per segment, spanning from
## the toe board's underside to the top rail's top face in one solid piece,
## rather than one collider per course. A body must not pass BETWEEN the
## courses, and 3 barriers are cheaper than 43 boxes.
static func railing_collider_boxes(spec: Dictionary) -> Array:
	if not bool(spec.get("solid", true)):
		return []
	var boxes := railing_boxes(spec)
	if boxes.is_empty():
		return []

	var groups: Dictionary = {}
	for box_variant in boxes:
		var box := box_variant as Dictionary
		var index := int(box.get("segment", 0))
		if not groups.has(index):
			groups[index] = []
		(groups[index] as Array).append(box)
	var order: Array = groups.keys()
	order.sort()

	var out: Array = []
	for index in order:
		var group := groups[index] as Array
		var yaw := _yaw_of((group[0] as Dictionary).get("basis", Basis.IDENTITY) as Basis)
		var frame := Basis(Vector3.UP, yaw)
		var inverse := frame.transposed()
		var low := Vector3.ZERO
		var high := Vector3.ZERO
		var first := true
		for box_variant in group:
			for corner in _corners(box_variant as Dictionary):
				var local: Vector3 = inverse * corner
				if first:
					low = local
					high = local
					first = false
				else:
					low = low.min(local)
					high = high.max(local)
		out.append({
			"center": frame * ((low + high) * 0.5),
			"size": high - low,
			"yaw_deg": rad_to_deg(yaw),
		})
	return out


## Colliders for ANY swept run, in the {center, size, yaw_deg} shape
## `StructureBaker.collect_colliders` already returns.
##
## ── Why this cannot drift from what is drawn ────────────────────────────────
## It calls `sweep_boxes` and colides the boxes that come back. There is no
## second derivation of the geometry to keep in step, which is the mechanism
## behind both of the walk-through bugs this project has already fixed: the
## drawing and the collision were computed separately and one of them was
## edited. Here, changing what a bulwark looks like changes what it feels like,
## because they are the same array.
##
## ── What a sloping cap emits, and why that is honest ────────────────────────
## The collider contract carries a YAW AND NO PITCH. A bulwark has two kinds of
## box in it and they land differently:
##
##   • the plating is PLUMB and yaw-only already, so its collider is EXACT — the
##     box handed to the physics server is the box that was drawn, to the last
##     millimetre. That is the part a body actually walks into.
##   • the cap rail rides the tangent and is therefore PITCHED by the sheer
##     angle (7.3° at the stem of hull_28x10, and under 1° over most of the
##     run). It has no field to put that pitch in.
##
## So each segment's collider is the YAW-FRAME BOUNDING BOX of every box drawn
## on that segment. For the plating that is an identity. For the pitched cap it
## grows the box by the pitch bulge — half the segment's rise, 16 mm at the
## worst segment on the trawler — and it grows it OUTWARD in every axis. The
## approximation is therefore strictly conservative: a point inside anything
## drawn is inside the collider, and the test asserts exactly that over every
## corner of every emitted box rather than trusting this paragraph.
##
## Emitting one un-rotated box around a pitched run is the alternative and it is
## the defect `plan_collision_physics_test` exists to catch: it puts a phantom
## slab out over the open deck. Bounding the pitch is the version that
## over-covers by millimetres instead of by metres.
##
## `solid: false` opts a run out entirely, and a section thinner than
## SWEEP_COLLIDER_MIN_M laterally opts itself out — see that constant for the
## line it draws through PROFILE_LIBRARY.
static func sweep_collider_boxes(spec: Dictionary) -> Array:
	if not bool(spec.get("solid", true)):
		return []
	var boxes := sweep_boxes(spec)
	if boxes.is_empty():
		return []

	var groups: Dictionary = {}
	for box_variant in boxes:
		var box := box_variant as Dictionary
		var index := int(box.get("segment", 0))
		if not groups.has(index):
			groups[index] = []
		(groups[index] as Array).append(box)
	var order: Array = groups.keys()
	order.sort()

	var raw: Array = []
	var widest := 0.0
	for index in order:
		var group := groups[index] as Array
		var yaw := _yaw_of((group[0] as Dictionary).get("basis", Basis.IDENTITY) as Basis)
		var frame := Basis(Vector3.UP, yaw)
		var inverse := frame.transposed()
		var low := Vector3.ZERO
		var high := Vector3.ZERO
		var first := true
		for box_variant in group:
			for corner in _corners(box_variant as Dictionary):
				var local: Vector3 = inverse * corner
				if first:
					low = local
					high = local
					first = false
				else:
					low = low.min(local)
					high = high.max(local)
		var size := high - low
		widest = maxf(widest, size.x)
		raw.append({
			"center": frame * ((low + high) * 0.5),
			"size": size,
			"yaw_deg": rad_to_deg(yaw),
		})
	if widest < SWEEP_COLLIDER_MIN_M:
		return []
	return _merge_colliders(raw, float(spec.get("collider_merge_m", COLLIDER_MERGE_M)))


## Fold consecutive same-heading colliders together while the fold over-covers
## by no more than `tolerance` in Y. A 90-segment sheer run down one side of a
## hull is one heading for most of its length and its rise over that length is
## tiny, so this is where the static-shape count comes back down; at the bow,
## where every segment turns, nothing merges and nothing needs to.
##
## The bound is on the WHOLE accumulated run, not on the last pair. Comparing
## pairwise lets a run of 0.03 m steps drift arbitrarily far from the geometry
## it is supposed to hug, one acceptable step at a time.
static func _merge_colliders(raw: Array, tolerance: float) -> Array:
	if tolerance <= 0.0 or raw.size() < 2:
		return raw
	var out: Array = []
	var tight_low := 0.0
	var tight_high := 0.0
	for box_variant in raw:
		var box := box_variant as Dictionary
		var centre := box["center"] as Vector3
		var size := box["size"] as Vector3
		var low := centre.y - size.y * 0.5
		var high := centre.y + size.y * 0.5
		if not out.is_empty():
			var last := out[out.size() - 1] as Dictionary
			if absf(float(last["yaw_deg"]) - float(box["yaw_deg"])) < 1e-4:
				var merged := _union_in_yaw(last, box)
				var merged_centre := merged["center"] as Vector3
				var merged_size := merged["size"] as Vector3
				var slack := (
					(maxf(tight_low, low) - (merged_centre.y - merged_size.y * 0.5))
					+ ((merged_centre.y + merged_size.y * 0.5) - minf(tight_high, high))
				)
				if slack <= tolerance:
					out[out.size() - 1] = merged
					tight_low = maxf(tight_low, low)
					tight_high = minf(tight_high, high)
					continue
		out.append(box)
		tight_low = low
		tight_high = high
	return out


## Bounding box of two same-yaw colliders, expressed in their shared frame.
static func _union_in_yaw(a: Dictionary, b: Dictionary) -> Dictionary:
	var yaw := deg_to_rad(float(a["yaw_deg"]))
	var frame := Basis(Vector3.UP, yaw)
	var inverse := frame.transposed()
	var low := Vector3.INF
	var high := -Vector3.INF
	for box in [a, b]:
		var centre: Vector3 = inverse * ((box as Dictionary)["center"] as Vector3)
		var half: Vector3 = ((box as Dictionary)["size"] as Vector3) * 0.5
		low = low.min(centre - half)
		high = high.max(centre + half)
	return {
		"center": frame * ((low + high) * 0.5),
		"size": high - low,
		"yaw_deg": float(a["yaw_deg"]),
	}


## The eight world-space corners of one emitted box.
static func _corners(box: Dictionary) -> Array:
	var centre := box["center"] as Vector3
	var half := (box["size"] as Vector3) * 0.5
	var basis := box.get("basis", Basis.IDENTITY) as Basis
	var out: Array = []
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				out.append(centre + basis * Vector3(half.x * sx, half.y * sy, half.z * sz))
	return out


## Plan heading of a box's own frame. Both emitters put the run's tangent on the
## basis's Z, so this reads the same heading off a plumb band and off a pitched
## cap swept over the same segment — which is what lets the two share one
## collider.
static func _yaw_of(basis: Basis) -> float:
	var forward := basis.z
	if Vector2(forward.x, forward.z).length_squared() < 1e-12:
		return 0.0
	return atan2(forward.x, forward.z)


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


# ── The bulwark: the sheer curve, drawn and collided ────────────────────────

## How finely a hull's sheer must be sampled for a plumb band to hide its own
## steps under a cap `cap_headroom_m` thick.
##
## DERIVED, and this is the point. `sheer_rise_at` is rise·(|z|/(L/2))², so
##     |d(rise)/dz| = 2·rise_end·|z| / (L/2)²    which peaks at 2·rise_end/(L/2)
## at the very ends of the hull. A segment of length `dz` therefore rises by at
## most `slope·dz`, and the plumb band's step — the amount it over-runs the true
## curve at the low end of its own segment — is exactly that. Keep it under the
## cap's headroom and the step is buried inside the cap on every hull, at every
## size, with nobody choosing a sample count.
##
## Floored at PLAN_SAMPLE_M so a flat-sheer hull still resolves its bow taper.
static func sheer_samples_for(stations: HullStations, cap_headroom_m: float) -> int:
	if stations == null or stations.length_m <= 0.0:
		return 2
	var plan_floor := int(ceil(stations.length_m / PLAN_SAMPLE_M)) + 1
	var rise := maxf(stations.sheer_forward_m, stations.sheer_aft_m)
	var headroom := maxf(cap_headroom_m, 1e-4)
	if rise <= 0.0:
		return maxi(plan_floor, 2)
	var slope := 2.0 * rise / maxf(stations.length_m * 0.5, 0.001)
	var step := headroom / slope
	return maxi(maxi(int(ceil(stations.length_m / step)) + 1, plan_floor), 2)


## The whole bulwark for one hull, as a `sweep_boxes` spec. Feed it to
## `sheer_band_boxes` to draw and to `sweep_collider_boxes` to collide.
##
## ── What is authored and what is derived ────────────────────────────────────
## Authored: `height`, the cap height amidships, which is a fall-barrier
## dimension set by the 1.8 m figure and is the same on a 28 m trawler and a
## 150 m freighter. Plus the section — plate 100 mm, cap 220 x 60 — which is
## what steel plate and a capping rail measure.
##
## Derived per hull, from catalog fields, with no per-hull number anywhere:
##   • the sheer curve itself — `HullStations.sheer_cap_y_at`, which is
##     freeboard × the form's own bow/stern keel rise. Retune `fine_entry` and
##     every fine-entry hull's sheer moves with it. A full-bodied freighter
##     (0.18/0.05) stays nearly flat and a trawler (0.32/0.10) gets a marked
##     curve, which is what those ships look like.
##   • the deck-edge plan line — `deck_half_beam_at`, read at the BAND's own
##     height so a flared hull's bulwark follows the section it stands on.
##   • the sampling — `sheer_samples_for`, from the hull's own sheer slope.
##   • the plating's inset — half its thickness, so its outboard face is flush
##     with the shell and hull and bulwark read as one body. The cap then
##     overhangs both faces by 60 mm, as a capping rail does.
##
## `opts` keys, all optional: height, plate_m, cap_w, cap_h, side
## ("loop" | "port" | "starboard"), material, plate_color, cap_color, base_y,
## follow_sheer, solid, samples.
##
## `follow_sheer: false` is the CONTROL, not a style: it holds the cap at a
## constant height and produces exactly the bar the silhouette reads as today.
## It exists so the difference can be photographed side by side rather than
## argued about.
static func sheer_bulwark_spec(stations: HullStations, opts: Dictionary = {}) -> Dictionary:
	if stations == null or stations.stations.is_empty():
		push_error("StructureEdge.sheer_bulwark_spec: no stations")
		return {}
	var height := float(opts.get("height", DEFAULT_BULWARK_HEIGHT))
	var plate := maxf(float(opts.get("plate_m", DEFAULT_BULWARK_PLATE_M)), 0.001)
	var cap_w := maxf(float(opts.get("cap_w", DEFAULT_CAP_WIDTH_M)), plate)
	var cap_h := maxf(float(opts.get("cap_h", DEFAULT_CAP_THICKNESS_M)), 0.001)
	var follow := bool(opts.get("follow_sheer", true))
	var base_y := float(opts.get("base_y", stations.deck_y))
	var material := str(opts.get("material", "painted"))

	## The plating runs a third of the cap's thickness into it, leaving two
	## thirds as the headroom the sampling is then solved against.
	var overlap := cap_h / 3.0
	var samples := int(opts.get("samples", sheer_samples_for(stations, cap_h - overlap)))

	var profile := bulwark_profile(plate, cap_w, cap_h, overlap)
	## Colour is FREE — it rides in the vertex stream and the bake buckets on
	## material alone. Spend it here: plating in the topsides colour and the cap
	## in a contrasting one means the eye reads hull and bulwark as ONE body
	## whose top edge is the sheer, instead of as a hull with a pale bar sitting
	## on it. That is a colour decision doing silhouette work, and it costs
	## nothing but two vertex attributes.
	(profile[0] as Dictionary)["color"] = _color_of(
		opts.get("plate_color", Color(0.13, 0.15, 0.18))
	)
	(profile[1] as Dictionary)["color"] = _color_of(
		opts.get("cap_color", Color(0.86, 0.87, 0.88))
	)

	var side := str(opts.get("side", "loop"))
	var inset := plate * 0.5
	var path: PackedVector3Array
	var closed := false
	match side:
		"port":
			path = sheer_path(stations, -1.0, samples, inset, height, follow)
		"starboard":
			path = sheer_path(stations, 1.0, samples, inset, height, follow)
		_:
			path = sheer_loop(stations, samples, inset, height, follow)
			closed = true

	return {
		"path": path,
		"closed": closed,
		"profile": profile,
		"base_y": base_y,
		"material": material,
		"solid": bool(opts.get("solid", true)),
		"samples": samples,
	}


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


## The same segments flattened onto the deck plane — the frame a plumb band
## stands in. Index-parallel to `_segments_of`'s output so a caller can walk
## both together; a segment with no plan run (a vertical riser) becomes an EMPTY
## dictionary rather than disappearing, which would silently shift every index
## after it and mis-mitre the rest of the run.
static func _plan_segments(segments: Array) -> Array:
	var out: Array = []
	for seg_variant in segments:
		var seg := seg_variant as Dictionary
		var a := seg["a"] as Vector3
		var b := seg["b"] as Vector3
		var flat_a := Vector3(a.x, 0.0, a.z)
		var delta := Vector3(b.x - a.x, 0.0, b.z - a.z)
		var length := delta.length()
		if length < MIN_SEGMENT_M:
			out.append({})
			continue
		out.append({
			"a": flat_a,
			"b": Vector3(b.x, 0.0, b.z),
			"tangent": delta / length,
			"length": length,
		})
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
	closed: bool = false,
) -> float:
	var count := segments.size()
	if count < 2:
		return 0.0
	var neighbour := i - 1 if direction < 0 else i + 1
	if closed:
		## A closed run has no outer ends, so its SEAM is a corner like any
		## other and must be mitred like one. Leaving it butted left a notch at
		## the stem head of every bulwark loop — the point where the starboard
		## run and the port run meet — which the column probe found as two empty
		## samples of 146 216, at the apex, right under the cap.
		neighbour = wrapi(neighbour, 0, count)
	if neighbour < 0 or neighbour >= count:
		## An open run's outer ends are butt ends: nothing to mitre into.
		return 0.0
	## Plan-projected runs (see `_plan_segments`) can carry an empty entry where
	## a segment is purely vertical. There is no direction to mitre against, so
	## the joint gets the overlap floor and nothing more.
	if not (segments[i] as Dictionary).has("tangent"):
		return 0.0
	if not (segments[neighbour] as Dictionary).has("tangent"):
		return JOINT_EPS
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
