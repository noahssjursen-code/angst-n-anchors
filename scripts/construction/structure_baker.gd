class_name StructureBaker
extends RefCounted

## Pure StructurePlan -> geometry. One merged surface per MATERIAL for visuals
## — colour rides in the vertex stream, not in the bucket key, so a plan may use
## unlimited colours and still bake to at most four surfaces (one per entry in
## MATERIALS). The SAME panel decomposition drives collision boxes,
## so what you see is exactly what you collide with (door and stairwell
## openings are genuinely passable). No gameplay dependencies: reusable by
## DeckFitout, the Structure Studio editor, and headless services.
##
## Geometry conventions (chosen to kill z-fighting by construction):
##  - Walls with inside/outside colors split into two half-thickness skins.
##  - Every wall opening gets a proud frame (jambs + lintel + sill) in a
##    darkened tone — cuts read as depth from any angle and any lighting.
##
## Diagonal walls are the same box emitter under a yaw. Everything that
## decomposes a wall already works in run-space (u along the run, v vertical),
## so a 45° wall needs no new decomposition — only a rotated frame to emit into:
## panels, openings, opening frames and two-sided skins all follow for free.
## Axis-aligned walls keep the identity basis and their existing extent order,
## so no geometry, collider or bound that exists today moves by a float.

const DEFAULT_WALL_COLOR := Color(0.82, 0.84, 0.86)
const DEFAULT_DECK_COLOR := Color(0.36, 0.34, 0.31)
const DEFAULT_INTERIOR_COLOR := Color(0.78, 0.70, 0.58) ## warm timber
const MIN_PANEL := 0.02
const RAISED_SOLE := 0.02 ## plates at y<=0 sit just proud of the host deck
const FRAME_PROUD := 0.09 ## opening frames overhang the wall skin
const FRAME_WIDTH := 0.1
## Anti-coplanarity margin: abutting solids overlap by this much so every
## internal face is buried inside neighbouring geometry instead of sharing a
## plane with it.
const SKIN_EPS := 0.01
## Stairs aim for this riser height; the run divides evenly so the top tread
## always lands flush on start.y + height.
const STEP_RISE_TARGET := 0.22
const MAX_STEPS := 64

## ── Swept-tube primitives (spar, wire) ───────────────────────────────────────
const SPAR_DEFAULT_SIDES := 8
const SPAR_MIN_SIDES := 3
const SPAR_MAX_SIDES := 32
const SPAR_DEFAULT_RADIUS := 0.06
const SPAR_MIN_RADIUS := 0.0005
const DEFAULT_SPAR_COLOR := Color(0.72, 0.73, 0.75)
const WIRE_DEFAULT_SIDES := 4
const WIRE_DEFAULT_RADIUS := 0.02
const WIRE_DEFAULT_SPAN_STEPS := 10
const WIRE_MAX_SPAN_STEPS := 64
const DEFAULT_WIRE_COLOR := Color(0.22, 0.23, 0.25)
## A bend sharper than this (cos of the turn's bisector against the incoming run)
## gets a butt ring instead of a mitred one: the mitre's 1/cos blows up as the
## run folds back on itself, and a 20 m spike is a worse artefact than the small
## crease a butt joint leaves inside a 160-degree fold.
const SPAR_MITRE_MIN_DOT := 0.25
## Two runs closer than this are one run — a duplicated polyline node has no
## direction and would divide by zero.
const PATH_EPS := 1e-6
## A run whose direction is within this of straight up (or of level) is treated
## as exactly vertical (or exactly horizontal) by the collider emitter.
const AXIS_TOL := 0.001
## Sloped spar runs are approximated by a staircase of axis-aligned boxes no
## longer than this. See collect_colliders().
const SPAR_COLLIDER_STEP := 0.25
## Thinner than this and a spar emits no collider at all: a 40 mm obstruction the
## player cannot see stopping them dead reads as a bug, not as a fitting.
const SPAR_COLLIDER_MIN_RADIUS := 0.02

## Material library: name -> surface response. Extend freely; unknown names
## fall back to "painted".
const MATERIALS := {
	"painted": {"roughness": 0.80, "metallic": 0.00},
	"metal": {"roughness": 0.45, "metallic": 0.60},
	"wood": {"roughness": 0.90, "metallic": 0.00},
	"steel": {"roughness": 0.55, "metallic": 0.35},
}


# ── edges[]: swept runs ──────────────────────────────────────────────────────
#
# The bulwark, the guardrail, the rubbing strake. `StructureEdge` owns the
# geometry and `StructurePlan.edge_spec` owns the resolution (including
# `from_hull`, which lofts the hull's own sheer rather than letting a fixture
# restate a curve). What lives here is the two-line hand-off, and one property
# worth naming because it is the whole reason these three functions are so thin:
#
#   THE COLLIDERS ARE THE DRAWING. `StructureEdge.sweep_collider_boxes` calls
#   `sweep_boxes` and bounds the boxes that come back — there is no second
#   derivation of the geometry to keep in step. Both of this project's
#   walk-through bugs were a drawing and a collision computed separately, one of
#   which was later edited. So `edge_boxes` and `edge_collider_boxes` must go on
#   resolving the SAME spec through StructureEdge and must never grow their own
#   idea of where the run is. A "cheap" variant that re-lofted the path for
#   collision would look identical in every count this project measures.
#
# A railing is the documented exception and it is StructureEdge's exception, not
# a new one: `railing_collider_boxes` emits ONE barrier per segment rather than
# one collider per rail and post, because a body must not be able to pass
# BETWEEN the courses. See the note on that function.


## The `StructureEdge` sweep spec for one `edges[]` entry, in plan metres. The
## shared resolver — the same call in `bake` and in `collect_colliders`, so the
## two cannot photograph different vessels.
static func edge_spec(plan: StructurePlan, edge: Dictionary) -> Dictionary:
	return plan.edge_spec(edge)


static func edge_boxes(plan: StructurePlan, edge: Dictionary) -> Array:
	var spec := edge_spec(plan, edge)
	if spec.is_empty():
		return []
	if StructurePlan.edge_primitive(edge) == StructurePlan.EDGE_RAILING:
		return StructureEdge.railing_boxes(spec)
	return StructureEdge.sheer_band_boxes(spec)


static func edge_collider_boxes(plan: StructurePlan, edge: Dictionary) -> Array:
	var spec := edge_spec(plan, edge)
	if spec.is_empty():
		return []
	if StructurePlan.edge_primitive(edge) == StructurePlan.EDGE_RAILING:
		return StructureEdge.railing_collider_boxes(spec)
	return StructureEdge.sweep_collider_boxes(spec)


## Collects the plan's walls, decks and stairs for baking. Every element carries
## `source_id` so editors can map geometry back to the plan entity that owns it.
## A plan with its piece-kit placements turned into the `items[]` this file
## already bakes. Returns the plan UNCHANGED when it carries no `pieces[]`, so
## the common path allocates nothing.
##
## ── Why this exists, and why it is at the baker and not at each caller ──────
## `pieces[]` is the AUTHORING layer: a placement is a named piece on a grid
## node, and `PieceKit.resolve_document` turns it into plates. Everything that
## draws or collides a plan has to go through that resolution, and for a while
## nothing did.
##
## Measured on `probe_piece_house.json` — 57 placements, 0 items, 0 walls, 0
## decks — by baking it as shipped and again with every placement deleted:
##
##     AS SHIPPED          57 pieces  0 items | 3432 triangles  38 colliders
##     PLACEMENTS DELETED   0 pieces  0 items | 3432 triangles  38 colliders
##
## Identical. The placements contributed **zero** geometry and **zero**
## collision. A player would have built a deckhouse, seen nothing, and walked
## through where it should have been. All 3432 triangles were the four
## `edges[]` sheer-band runs.
##
## Every green render of a piece-built vessel came from `tests/piece_kit_capture.gd`,
## which resolves placements into a `user://` copy BEFORE building the plan —
## a path that existed only in the test rig. That is REALITY.md §3, the layer
## trap: the fixtures were correct, the resolver was correct, the captures were
## honest, and the game had none of it.
##
## Putting it at the two PUBLIC entries rather than in each caller is the §3b
## rule — one derivation. `bake` and `collect_colliders` each open with
## `resolved(plan)`, so what is drawn and what is collided come from one
## resolution and cannot drift.
##
## `expand()` deliberately does NOT resolve. It is called by `bake` and
## `collect_colliders` on the already-resolved plan, and resolving again there
## would do the work twice on every bake. A caller reaching past those two
## entries into `expand` directly gets walls, decks and stairs only — which is
## all `expand` has ever returned, since placements resolve to `items[]`.
## Measured after wiring, on `probe_piece_house.json`:
##
##     AS SHIPPED          57 pieces | 4692 triangles  241 colliders
##     PLACEMENTS DELETED   0 pieces | 3432 triangles   38 colliders
##
## i.e. the placements now contribute 1260 triangles and 203 colliders where
## they contributed nothing.
##
## RE-MEASURED 2026-08-15 (`tests/_doc_claim_audit.gd`), because the fixture
## gained a placement and PLATE_COLLIDER_SLOP tightened from 0.15 to 0.05 after
## the run above — the numbers moved, the property did not:
##
##                            pieces  triangles  colliders
##     probe_piece_house          58       4704        554   (stripped: 3432 / 38)
##     probe_piece_trawler        49       7388       2026   (stripped: 6224 / 1540)
##     probe_piece_tug            34       5544        423   (stripped: 4344 / 46)
##
## Note the collider column more than doubled against the 241 above while the
## triangle column barely moved: that is the SLOP constant, not this file. A
## quoted count is only true of the constants it was taken at — re-run the strip
## test rather than reading these three rows as current.
static func resolved(plan: StructurePlan) -> StructurePlan:
	if plan == null or plan.pieces.is_empty():
		return plan
	var result := PieceKit.resolve_document(plan.to_dict())
	for error in result["errors"] as PackedStringArray:
		## A placement that refuses to resolve contributes no geometry, which is
		## correct — but silently is not. It is the difference between "the kit
		## refused this" and "the superstructure vanished".
		push_error("StructureBaker: %s" % error)
	return StructurePlan.from_dict(result["doc"] as Dictionary)


static func expand(plan: StructurePlan) -> Dictionary:
	var walls: Array = []
	var decks: Array = []
	var stairs: Array = []
	for wall_variant in plan.walls:
		var wall := (wall_variant as Dictionary).duplicate(true)
		wall["source_id"] = int(wall.get("id", -1))
		walls.append(wall)
	for deck_variant in plan.decks:
		var deck := (deck_variant as Dictionary).duplicate(true)
		deck["source_id"] = int(deck.get("id", -1))
		decks.append(deck)
	for stair_variant in plan.stairs:
		var stair := (stair_variant as Dictionary).duplicate(true)
		stair["source_id"] = int(stair.get("id", -1))
		stairs.append(stair)
	return {"walls": walls, "decks": decks, "stairs": stairs}



# ── Panel decomposition ──────────────────────────────────────────────────────

## Rectangles {u0,u1,v0,v1} covering the wall span minus its openings.
static func wall_panels(wall: Dictionary) -> Array:
	return _panels_between(
		float(wall.get("length", 1.0)), float(wall.get("height", 3.0)), _parsed_openings(wall)
	)


## The opening subtraction, in run-space (u along the run, v vertical). Shared
## by walls and by sloped plates: a plate does the same subtraction in the METRE
## lengths of its own edges and then normalises, so MIN_PANEL keeps meaning
## "two centimetres" on both primitives instead of meaning "2% of the plate".
## `openings` entries are {off, w, sill, h}, already clamped and sorted.
static func _panels_between(length: float, height: float, openings: Array) -> Array:
	var panels: Array = []
	var cursor := 0.0
	for opening in openings:
		var off := float(opening["off"])
		var width := float(opening["w"])
		var sill := float(opening["sill"])
		var top := sill + float(opening["h"])
		if off - cursor > MIN_PANEL:
			panels.append({"u0": cursor, "u1": off, "v0": 0.0, "v1": height})
		if sill > MIN_PANEL:
			panels.append({"u0": off, "u1": off + width, "v0": 0.0, "v1": sill})
		if height - top > MIN_PANEL:
			panels.append({"u0": off, "u1": off + width, "v0": top, "v1": height})
		cursor = maxf(cursor, off + width)
	if length - cursor > MIN_PANEL:
		panels.append({"u0": cursor, "u1": length, "v0": 0.0, "v1": height})
	return panels


static func _parsed_openings(wall: Dictionary) -> Array:
	var length := float(wall.get("length", 1.0))
	var height := float(wall.get("height", 3.0))
	var openings: Array = []
	for opening_variant in wall.get("openings", []) as Array:
		var opening := opening_variant as Dictionary
		var off := clampf(float(opening.get("offset", 0.0)), 0.0, length)
		var width := clampf(float(opening.get("width", 1.0)), 0.0, length - off)
		var type := str(opening.get("type", StructurePlan.OPENING_DOOR))
		var sill := float(opening.get("sill", 1.0 if type == StructurePlan.OPENING_WINDOW else 0.0))
		var opening_height := clampf(float(opening.get("height", 2.2 if type == StructurePlan.OPENING_DOOR else 1.2)), 0.1, height - sill)
		if width > MIN_PANEL:
			openings.append({"off": off, "w": width, "sill": sill, "h": opening_height})
	openings.sort_custom(func(a, b): return float(a["off"]) < float(b["off"]))
	return openings


## Yaw in DEGREES about +Y that turns a wall box onto its run. Zero for "x" and
## "z" — those keep their historical extent order (x-walls carry the run in
## size.x, z-walls in size.z) instead of rotating, so every existing box is
## bit-for-bit what it was. Only the four diagonals are rotated, and for those
## the run is always size.x and the thickness always size.z.
static func wall_yaw_deg(wall: Dictionary) -> float:
	var axis := str(wall.get("axis", "x"))
	if not StructurePlan.is_diagonal_axis(axis):
		return 0.0
	var run := StructurePlan.wall_run(axis)
	## A +Y rotation of θ takes +X to (cos θ, 0, -sin θ).
	return rad_to_deg(atan2(-run.z, run.x))


static func wall_basis(wall: Dictionary) -> Basis:
	var yaw := wall_yaw_deg(wall)
	if is_zero_approx(yaw):
		return Basis.IDENTITY
	return Basis(Vector3.UP, deg_to_rad(yaw))


## Boxes {center: Vector3, size: Vector3, yaw_deg: float} for one wall in plan
## space. `size` is in the box's OWN frame: a non-zero `yaw_deg` must be applied
## about its centre or the box is not the box that was drawn.
static func wall_boxes(wall: Dictionary) -> Array:
	var start := StructurePlan.vec3_of(wall.get("start"))
	var axis := str(wall.get("axis", "x"))
	var thickness := float(wall.get("thickness", StructurePlan.DEFAULT_WALL_THICKNESS))
	var run := StructurePlan.wall_run(axis)
	var yaw := wall_yaw_deg(wall)
	var boxes: Array = []
	for panel_variant in wall_panels(wall):
		var panel := panel_variant as Dictionary
		var u_mid := (float(panel["u0"]) + float(panel["u1"])) * 0.5
		var u_len := float(panel["u1"]) - float(panel["u0"])
		var v_mid := (float(panel["v0"]) + float(panel["v1"])) * 0.5
		var v_len := float(panel["v1"]) - float(panel["v0"])
		boxes.append({
			"center": start + run * u_mid + Vector3(0.0, v_mid, 0.0),
			"size": (
				Vector3(thickness, v_len, u_len) if axis == "z"
				else Vector3(u_len, v_len, thickness)
			),
			"yaw_deg": yaw,
		})
	return boxes


## Scanline strips {x0,x1,z0,z1} covering the plate minus its holes.
static func deck_strips(deck: Dictionary) -> Array:
	var size_list: Array = deck.get("size", [1.0, 1.0])
	var w := float(size_list[0])
	var l := float(size_list[1]) if size_list.size() > 1 else 1.0
	var holes: Array = []
	for opening_variant in deck.get("openings", []) as Array:
		var opening := opening_variant as Dictionary
		var off: Array = opening.get("offset", [0.0, 0.0])
		var hole_size: Array = opening.get("size", [1.0, 1.0])
		var hx0 := clampf(float(off[0]), 0.0, w)
		var hz0 := clampf(float(off[1]) if off.size() > 1 else 0.0, 0.0, l)
		var hx1 := clampf(hx0 + float(hole_size[0]), 0.0, w)
		var hz1 := clampf(hz0 + (float(hole_size[1]) if hole_size.size() > 1 else 1.0), 0.0, l)
		if hx1 - hx0 > MIN_PANEL and hz1 - hz0 > MIN_PANEL:
			holes.append({"x0": hx0, "x1": hx1, "z0": hz0, "z1": hz1})
	var z_cuts: Array[float] = [0.0, l]
	for hole in holes:
		z_cuts.append(float(hole["z0"]))
		z_cuts.append(float(hole["z1"]))
	z_cuts.sort()
	var strips: Array = []
	for index in z_cuts.size() - 1:
		var z0 := z_cuts[index]
		var z1 := z_cuts[index + 1]
		if z1 - z0 <= MIN_PANEL:
			continue
		var z_mid := (z0 + z1) * 0.5
		var strip_holes: Array = []
		for hole in holes:
			if float(hole["z0"]) <= z_mid and z_mid <= float(hole["z1"]):
				strip_holes.append(hole)
		strip_holes.sort_custom(func(a, b): return float(a["x0"]) < float(b["x0"]))
		var cursor := 0.0
		for hole in strip_holes:
			if float(hole["x0"]) - cursor > MIN_PANEL:
				strips.append({"x0": cursor, "x1": float(hole["x0"]), "z0": z0, "z1": z1})
			cursor = maxf(cursor, float(hole["x1"]))
		if w - cursor > MIN_PANEL:
			strips.append({"x0": cursor, "x1": w, "z0": z0, "z1": z1})
	return strips


## Vertical span [bottom, top] of a plate. A plate at deck level is lifted just
## proud of its host deck so the two never share a plane.
static func _plate_span(deck: Dictionary) -> Vector2:
	var origin := StructurePlan.vec3_of(deck.get("origin"))
	var thickness := float(deck.get("thickness", StructurePlan.DEFAULT_PLATE_THICKNESS))
	var top_y := origin.y if origin.y > 0.001 else RAISED_SOLE
	return Vector2(top_y - thickness, top_y)


static func deck_boxes(deck: Dictionary) -> Array:
	var origin := StructurePlan.vec3_of(deck.get("origin"))
	var span := _plate_span(deck)
	var boxes: Array = []
	for strip_variant in deck_strips(deck):
		var strip := strip_variant as Dictionary
		var x_mid := (float(strip["x0"]) + float(strip["x1"])) * 0.5
		var x_len := float(strip["x1"]) - float(strip["x0"])
		var z_mid := (float(strip["z0"]) + float(strip["z1"])) * 0.5
		var z_len := float(strip["z1"]) - float(strip["z0"])
		boxes.append({
			"center": Vector3(origin.x + x_mid, (span.x + span.y) * 0.5, origin.z + z_mid),
			"size": Vector3(x_len, span.y - span.x, z_len),
		})
	return boxes


# ── Stairs ───────────────────────────────────────────────────────────────────

## Number of risers for a stair run: divide the climb into equal risers as
## close to STEP_RISE_TARGET as possible, so the top tread lands EXACTLY on
## start.y + height.
static func stair_step_count(stair: Dictionary) -> int:
	var height := float(stair.get("height", StructurePlan.DEFAULT_WALL_HEIGHT))
	return clampi(int(ceilf(height / STEP_RISE_TARGET)), 2, MAX_STEPS)


## Solid stepped run as boxes {center, size} in plan space — the SAME boxes
## drive visuals and collision, so the stair is walkable exactly as rendered
## (axis-aligned steps suit character step-up; no rotated colliders needed).
## Anti-coplanarity: every step is extended SKIN_EPS into the NEXT (uphill)
## step so riser planes are buried, and all bottoms sink SKIN_EPS below the
## base level so they bury into the deck plate the stair stands on.
static func stair_boxes(stair: Dictionary) -> Array:
	var start := StructurePlan.vec3_of(stair.get("start"))
	var dir := str(stair.get("dir", "+x"))
	var length := maxf(float(stair.get("length", 3.0)), 0.5)
	var width := maxf(float(stair.get("width", 1.0)), 0.5)
	var height := float(stair.get("height", StructurePlan.DEFAULT_WALL_HEIGHT))
	var steps := stair_step_count(stair)
	var tread := length / float(steps)
	var rise := height / float(steps)
	var along_x := dir in ["+x", "-x"]
	var ascending := dir in ["+x", "+z"]
	var boxes: Array = []
	for index in steps:
		## u = distance from the LOW end of the run, along the climb axis.
		var u0 := tread * float(index)
		var u1 := tread * float(index + 1) + (SKIN_EPS if index < steps - 1 else 0.0)
		var top := start.y + rise * float(index + 1)
		var bottom := start.y - SKIN_EPS
		## Low end sits at the footprint edge the climb starts from.
		var a0 := u0 if ascending else length - u1
		var a1 := u1 if ascending else length - u0
		var center: Vector3
		var size: Vector3
		if along_x:
			center = Vector3(start.x + (a0 + a1) * 0.5, (bottom + top) * 0.5, start.z + width * 0.5)
			size = Vector3(a1 - a0, top - bottom, width)
		else:
			center = Vector3(start.x + width * 0.5, (bottom + top) * 0.5, start.z + (a0 + a1) * 0.5)
			size = Vector3(width, top - bottom, a1 - a0)
		boxes.append({"center": center, "size": size})
	return boxes


static func _stair_layers(stair: Dictionary, fallback: Color) -> Array:
	var color := _color_of(stair.get("color", null), fallback)
	var material := str(stair.get("material", "painted"))
	var layers: Array = []
	for box_variant in stair_boxes(stair):
		var box := box_variant as Dictionary
		layers.append({
			"center": box["center"], "size": box["size"],
			"color": color, "material": material,
		})
	return layers


# ── Surface layers (color + material per side) ───────────────────────────────

static func _color_of(value: Variant, fallback: Color) -> Color:
	if value is Array and (value as Array).size() >= 3:
		var list := value as Array
		return Color(float(list[0]), float(list[1]), float(list[2]))
	return fallback


## Renderable layers for one wall: either a single skin, or inner + outer
## half-thickness skins when the wall declares two-sided identity. Opening
## frames ride along in a darkened tone.
static func _wall_layers(wall: Dictionary, fallback: Color) -> Array:
	var base := _color_of(wall.get("color", wall.get("color_out", null)), fallback)
	var two_sided := wall.has("color_in") or wall.has("material_in")
	var color_out := _color_of(wall.get("color_out", wall.get("color", null)), fallback)
	var color_in := _color_of(wall.get("color_in", null), DEFAULT_INTERIOR_COLOR)
	var material_out := str(wall.get("material_out", wall.get("material", "painted")))
	var material_in := str(wall.get("material_in", "wood"))
	var axis_z := str(wall.get("axis", "x")) == "z"
	## The thickness direction is local +X for a z-wall and local +Z otherwise;
	## the basis turns that into plan space and is the identity unless diagonal.
	var basis := wall_basis(wall)
	var layers: Array = []
	for box_variant in wall_boxes(wall):
		var box := box_variant as Dictionary
		var center := box["center"] as Vector3
		var size := box["size"] as Vector3
		if not two_sided:
			layers.append({
				"center": center, "size": size, "basis": basis,
				"color": base, "material": material_out,
			})
			continue
		var t := size.x if axis_z else size.z
		var quarter := t * 0.25
		var normal := basis * (Vector3(1, 0, 0) if axis_z else Vector3(0, 0, 1))
		## Skins are slightly over half thickness so they interpenetrate at
		## the centerline — their meeting faces are buried, never coplanar.
		var skin := t * 0.5 + SKIN_EPS * 2.0
		var half_size := Vector3(skin, size.y, size.z) if axis_z else Vector3(size.x, size.y, skin)
		layers.append({
			"center": center + normal * quarter,
			"size": half_size, "basis": basis,
			"color": color_out, "material": material_out,
		})
		layers.append({
			"center": center - normal * quarter,
			"size": half_size, "basis": basis,
			"color": color_in, "material": material_in,
		})
	var frame_color := base.darkened(0.45)
	for frame_variant in _opening_frames(wall):
		var frame := frame_variant as Dictionary
		layers.append({
			"center": frame["center"], "size": frame["size"], "basis": basis,
			"color": frame_color, "material": "steel",
		})
	return layers


## Proper casing (dørkarm/vindusramme) around every wall opening, slightly
## proud of the skin. Joinery rules:
##  - Jambs STRADDLE the cut edges — half buried in the wall panel, so no
##    face can plane against the cut.
##  - Lintel (and window sill) runs the FULL width across the jamb ends —
##    closed corners like real casing.
##  - Members interpenetrate by SKIN_EPS so no coplanar contact survives.
##
## Members come back in the wall's own frame — a diagonal wall's frames need the
## same basis its panels get.
static func _opening_frames(wall: Dictionary) -> Array:
	var start := StructurePlan.vec3_of(wall.get("start"))
	var axis := str(wall.get("axis", "x"))
	var axis_z := axis == "z"
	var run := StructurePlan.wall_run(axis)
	var thickness := float(wall.get("thickness", StructurePlan.DEFAULT_WALL_THICKNESS))
	var frames: Array = []
	var depth := thickness + FRAME_PROUD
	var half_w := FRAME_WIDTH * 0.5
	for opening in _parsed_openings(wall):
		var off := float(opening["off"])
		var width := float(opening["w"])
		var sill := float(opening["sill"])
		var height := float(opening["h"])
		var has_sill := sill > 0.05
		var head_v := sill + height ## top of the clear opening
		## Jambs run between sill member and lintel, overlapping each by eps.
		var jamb_bottom := (sill + half_w - SKIN_EPS) if has_sill else 0.0
		var jamb_top := head_v - half_w + SKIN_EPS
		var jamb_length := maxf(jamb_top - jamb_bottom, 0.1)
		var jamb_mid := (jamb_top + jamb_bottom) * 0.5
		var full_span := width + FRAME_WIDTH * 2.0 ## lintel/sill across jamb ends
		var members := [
			{"u": off, "v": jamb_mid, "ul": FRAME_WIDTH, "vl": jamb_length},
			{"u": off + width, "v": jamb_mid, "ul": FRAME_WIDTH, "vl": jamb_length},
			{"u": off + width * 0.5, "v": head_v, "ul": full_span, "vl": FRAME_WIDTH},
		]
		if has_sill:
			members.append({"u": off + width * 0.5, "v": sill, "ul": full_span, "vl": FRAME_WIDTH})
		for member in members:
			var u := float(member["u"])
			var v := float(member["v"])
			var center := start + run * u + Vector3(0.0, v, 0.0)
			if axis_z:
				frames.append({
					"center": center,
					"size": Vector3(depth, float(member["vl"]), float(member["ul"])),
				})
			else:
				frames.append({
					"center": center,
					"size": Vector3(float(member["ul"]), float(member["vl"]), depth),
				})
	return frames


## Renderable layers for a plate: one skin, coloured from the plate's own
## colour or from the palette slot it names.
static func _plate_layers(deck: Dictionary, wall_fallback: Color, deck_fallback: Color) -> Array:
	var slot_default := wall_fallback if str(deck.get("palette_slot", "")) == "wall" else deck_fallback
	var base := _color_of(deck.get("color", deck.get("color_out", null)), slot_default)
	var material := str(deck.get("material_out", deck.get("material", "painted")))
	var layers: Array = []
	for box_variant in deck_boxes(deck):
		var box := box_variant as Dictionary
		layers.append({
			"center": box["center"] as Vector3,
			"size": box["size"] as Vector3,
			"color": base,
			"material": material,
		})
	return layers


# ── Spar and wire: one swept tube on a polyline ──────────────────────────────
##
## SPAR is a tube swept along a POLYLINE with a radius that may taper along the
## run. WIRE is the same tube with catenary sag applied to the path first. They
## are ONE emitter with two front doors, and neither one knows what it is being
## used for: mast, post, boom, derrick, gallows leg, davit, stanchion, exhaust
## stack, vent, jackstaff, antenna, crane pedestal, pipe run and wrapped handrail
## are all `spar` with different numbers in `props`. If a change here needs an
## `if part_id == …` it is the wrong change.
##
## Two endpoints was the earlier spelling and it cannot draw a pipe run with
## three bends, a goose-neck vent (a pipe folded 180 degrees at the top), a cowl,
## a curved davit arm, a ladder stringer stepped around an obstruction, or a
## handrail that follows a deckhouse round a corner. Each of those becomes 3-10
## separate fittings under a two-endpoint spar, for no gain. `from`/`to` is still
## accepted and is exactly the two-node polyline, so nothing regresses.
##
## COST. A tube of `sides` sides over `rings` polyline nodes is
##   sides quads per gap   -> 2 * sides * (rings - 1) triangles
##   one fan cap per end   ->     sides * 2           triangles
##   = 2 * sides * rings triangles, exactly, for every spar ever emitted.
## An 8-sided two-node mast is 32. That one formula is the breadth claim: if any
## part were special-cased its triangle count would stop matching.


## Points of a polyline. Accepts `[[x,y,z], …]` (what survives JSON), `[Vector3,
## …]` (what a caller already holding vectors has) and PackedVector3Array (what
## one of these functions hands to the next — a Packed array is NOT an `Array`,
## and forgetting that silently drew every wire as nothing at all).
static func polyline_of(value: Variant) -> PackedVector3Array:
	var out := PackedVector3Array()
	if value is PackedVector3Array:
		return value as PackedVector3Array
	if not (value is Array):
		return out
	for entry in value as Array:
		if entry is Vector3:
			out.append(entry as Vector3)
		elif entry is Array and (entry as Array).size() >= 3:
			var list := entry as Array
			out.append(Vector3(float(list[0]), float(list[1]), float(list[2])))
	return out


static func _point_of(value: Variant) -> Vector3:
	if value is Vector3:
		return value as Vector3
	return StructurePlan.vec3_of(value)


## Drops repeated nodes. A zero-length run has no direction, and one duplicated
## point in an authored polyline would otherwise divide by zero in the frame.
static func _dedup_path(path: PackedVector3Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	for point in path:
		if out.is_empty() or out[out.size() - 1].distance_to(point) > PATH_EPS:
			out.append(point)
	return out


## The spar's path, in whatever frame the spec was written in. `points` (or its
## alias `path`) is the contract; `from`/`to` is the two-node degenerate case, so
## a caller holding only two endpoints needs no different call.
static func spar_path(spec: Dictionary) -> PackedVector3Array:
	var raw := polyline_of(spec.get("points", spec.get("path", null)))
	if raw.size() < 2 and spec.has("from") and spec.has("to"):
		raw = PackedVector3Array([_point_of(spec["from"]), _point_of(spec["to"])])
	return _dedup_path(raw)


## Radius at every node. `radii` (one per node) wins outright — that is the
## per-node taper. Otherwise `radius` tapers to `radius * taper` distributed by
## ARC LENGTH, so a run whose nodes bunch up around a bend still tapers evenly in
## metres instead of evenly per node.
static func spar_radii(spec: Dictionary, path: PackedVector3Array, fallback := SPAR_DEFAULT_RADIUS) -> PackedFloat32Array:
	var count := path.size()
	var out := PackedFloat32Array()
	var explicit: Variant = spec.get("radii", null)
	if explicit is Array and (explicit as Array).size() == count:
		for value in explicit as Array:
			out.append(maxf(float(value), SPAR_MIN_RADIUS))
		return out
	var base := maxf(float(spec.get("radius", fallback)), SPAR_MIN_RADIUS)
	var taper := maxf(float(spec.get("taper", 1.0)), 0.0)
	var travelled := PackedFloat32Array([0.0])
	var total := 0.0
	for index in range(1, count):
		total += path[index].distance_to(path[index - 1])
		travelled.append(total)
	for index in count:
		var t := 0.0 if total <= 0.0 else travelled[index] / total
		out.append(maxf(lerpf(base, base * taper, t), SPAR_MIN_RADIUS))
	return out


static func spar_sides(spec: Dictionary, fallback := SPAR_DEFAULT_SIDES) -> int:
	return clampi(int(spec.get("sides", fallback)), SPAR_MIN_SIDES, SPAR_MAX_SIDES)


## Some unit vector perpendicular to `dir`, chosen off the world axis `dir` is
## least aligned with so the cross is never degenerate.
static func _perp_to(dir: Vector3) -> Vector3:
	var axis := Vector3.UP
	if absf(dir.dot(Vector3.UP)) > 0.9:
		axis = Vector3.RIGHT
	return dir.cross(axis).normalized()


## The minimal rotation carrying `from` onto `to`, applied to `v`. This is the
## parallel transport that keeps a bent tube from twisting about its own run — a
## fixed world reference vector would spin the cross-section as the run turns,
## and on a goose-neck it shears the pipe visibly.
static func _transport(v: Vector3, from: Vector3, to: Vector3) -> Vector3:
	var axis := from.cross(to)
	if axis.length() < 1e-9:
		return v if from.dot(to) > 0.0 else -v
	return v.rotated(axis.normalized(), from.angle_to(to))


## One ring of `sides` points per polyline node, in order. Interior nodes are
## MITRED onto the bisector plane of the two runs meeting there, so the tube is
## continuous through a bend — the two runs share one ring, which is what makes a
## bent spar watertight instead of two butted stubs with a wedge missing.
static func tube_rings(path: PackedVector3Array, radii: PackedFloat32Array, sides: int) -> Array:
	var count := path.size()
	if count < 2 or radii.size() != count or sides < SPAR_MIN_SIDES:
		return []
	var runs: Array[Vector3] = []
	for index in range(count - 1):
		runs.append((path[index + 1] - path[index]).normalized())
	var rings: Array = []
	var u := _perp_to(runs[0])
	for index in count:
		## `u` is perpendicular to the run ARRIVING at this node, by construction.
		var arriving := runs[maxi(index - 1, 0)]
		var normal := arriving
		if index > 0 and index < count - 1:
			var leaving := runs[index]
			var bisector := arriving + leaving
			if bisector.length() > 1e-6:
				normal = bisector.normalized()
		rings.append(_ring(path[index], arriving, u, normal, radii[index], sides))
		if index < count - 1 and index > 0:
			u = _transport(u, arriving, runs[index])
	return rings


static func _ring(
	center: Vector3, run: Vector3, u: Vector3, normal: Vector3, radius: float, sides: int
) -> PackedVector3Array:
	## (u, v, run) is right-handed: run x u = v, u x v = run.
	var v := run.cross(u).normalized()
	var denom := normal.dot(run)
	var mitre := denom > SPAR_MITRE_MIN_DOT
	var points := PackedVector3Array()
	for k in sides:
		var angle := TAU * float(k) / float(sides)
		var offset := (u * cos(angle) + v * sin(angle)) * radius
		if mitre:
			## Slide along the run until the point lands on the bisector plane:
			## (offset + s*run) . normal == 0.
			offset += run * (-offset.dot(normal) / denom)
		points.append(center + offset)
	return points


## ── Wire: the same tube, with the path sagged first ─────────────────────────
##
## `sag` is the maximum droop below the chord, in metres, applied per polyline
## span. IT REACHES EXACTLY ZERO and that is a hard requirement, not a nicety: a
## shroud or a stay drawn with mooring-line droop reads as broken rigging, which
## is worse than no rigging at all. At sag 0 this function returns the authored
## points UNTOUCHED — not resampled, not re-lerped, not rounded — so a standing
## stay is bit-for-bit the straight line the builder drew.
##
## CHAIN IS NOT WIRE, and is not solved here. Anchor cable, lashing chain and
## gripes read as chain because of the LINKS. This emitter gets chain's shape
## right and its material wrong, so a chain drawn with it looks like a thick
## smooth rope. That needs either a segmented variant or a shading treatment;
## COMPONENTS.md flags it as unsolved and nothing below pretends otherwise.
##
## Sag is applied in the frame the path is already in, and the baker transforms a
## wire's points to PLAN space BEFORE sagging — a line hangs down under gravity
## no matter which way its fitting is yawed, pitched or rolled.


## Solves the catenary shape parameter for a span. With u = span / (2a), the
## ratio sag/span is (cosh u - 1) / (2u), which is strictly increasing on u > 0,
## so a bisection is exact to float precision and needs no derivative and no
## initial guess. Returns u; a is span / (2u).
static func catenary_u(span: float, sag: float) -> float:
	if span <= 0.0 or sag <= 0.0:
		return 0.0
	var target := sag / span
	var low := 1e-6
	var high := 30.0 ## cosh(30)/60 ~ 8.9e10: a sag 10^10 times the span
	if (cosh(high) - 1.0) / (2.0 * high) < target:
		return high
	for _i in 80:
		var mid := (low + high) * 0.5
		if (cosh(mid) - 1.0) / (2.0 * mid) < target:
			low = mid
		else:
			high = mid
	return (low + high) * 0.5


## Droop below the chord at parameter `t` in [0,1] across a span whose horizontal
## extent is `span` and whose midspan droop is `sag`. Zero at both ends, `sag` at
## t = 0.5, and identically zero for sag <= 0.
static func wire_droop(t: float, span: float, sag: float) -> float:
	if sag <= 0.0 or span <= 0.0:
		return 0.0
	var u := catenary_u(span, sag)
	if u <= 0.0:
		return 0.0
	var a := span / (2.0 * u)
	return a * (cosh(u) - cosh(u * (2.0 * t - 1.0)))


## The wire's drawn path: the authored polyline with catenary droop added to
## every span. Straight-through at sag 0 — see the note above.
static func wire_path(spec: Dictionary) -> PackedVector3Array:
	var path := spar_path(spec)
	var sag := float(spec.get("sag", 0.0))
	if path.size() < 2 or sag <= 0.0:
		return path
	var steps := clampi(int(spec.get("span_steps", WIRE_DEFAULT_SPAN_STEPS)), 2, WIRE_MAX_SPAN_STEPS)
	var out := PackedVector3Array([path[0]])
	for index in range(path.size() - 1):
		var a := path[index]
		var b := path[index + 1]
		## Horizontal extent: a line hanging between two points on the same
		## vertical has no catenary to draw, it is simply straight down.
		var span := Vector2(b.x - a.x, b.z - a.z).length()
		for step in range(1, steps + 1):
			var t := float(step) / float(steps)
			out.append(a.lerp(b, t) - Vector3.UP * wire_droop(t, span, sag))
	return out


## ── The sloped plate: four free corners and a thickness ─────────────────────
##
## THIS IS THE PRIMITIVE THAT REPLACES THE ROOM. A room was an axis-aligned box
## that expanded to four walls, a floor and a ceiling, so every deckhouse it drew
## was a shed. Nothing on a working vessel is a shed. A plate is FOUR ARBITRARY
## 3D CORNERS plus a thickness, which is the smallest thing that can draw what a
## room could not: a raked deckhouse front, tapered sides, a sloped roof, a
## set-back upper tier, a raked windscreen, a chine facet, a knuckle, a transom
## rake, a funnel taper. Every one of those is `plate` with different numbers in
## `props`; if a change here needs an `if part_id == …` it is the wrong change.
##
## FRAME. Corners are a RING — c0, c1, c2, c3 — and the surface between them is
## the BILINEAR patch
##     P(u,v) = (1-v)·[(1-u)·c0 + u·c1] + v·[(1-u)·c3 + u·c2]
## so u runs c0→c1 along the "bottom" edge and v runs c0→c3 "up". Bilinear, not
## two triangles, because the four corners need not be coplanar — a topside panel
## with a twist in it is one plate, and a patch is closed under restriction to a
## sub-rectangle, which is what lets openings, subdivision and colliders all cut
## the same surface without any of them re-deriving it.
##
## The corners are ordered COUNTER-CLOCKWISE SEEN FROM OUTSIDE. That single
## convention fixes the outward normal (`plate_normal`), which fixes which way
## the thickness is split, which side an opening frame stands proud of, and the
## triangle winding. Reverse the ring and you get the same plate facing the other
## way, which is a legitimate thing to author and not an error.
##
## OPENINGS are authored in METRES on the plate's own surface — offset/width
## along u, sill/height along v — and normalised against the mean length of the
## two opposing edges. On a tapered plate that is what a builder means: a window
## 1.2 m wide half way along stays half way along, and the cut follows the taper
## instead of ignoring it.
##
## COST. A panel emits front and back grids plus four skirts:
##     4·su·sv + 4·(su + sv) triangles
## which is 12 for the default single segment — exactly a box, because a box is
## what a flat plate degenerates to. Openings add one panel per rectangle and one
## frame member per jamb/lintel/sill, each 12. That one formula is the breadth
## claim: a part that had been special-cased would stop matching it.
##
## MATERIAL. A plate goes into the SAME material buckets as everything else and
## introduces none of its own, so a whole deckhouse costs zero draw calls.

const PLATE_DEFAULT_THICKNESS := 0.09
const DEFAULT_PLATE_COLOR := Color(0.85, 0.86, 0.88)
## Below this the quad has no surface to draw and every derived direction is
## noise. 1 cm² — smaller than any plate anyone means.
const PLATE_MIN_AREA := 1e-4
## Two corners closer than this are one corner: the ring is then a triangle or a
## line, the bilinear patch collapses, and the opening decomposition divides by a
## zero edge length. Authored as a defect, reported as one.
const PLATE_MIN_EDGE := 1e-4
const PLATE_FRAME_WIDTH := 0.09
const PLATE_FRAME_PROUD := 0.05
const PLATE_MAX_SEGMENTS := 16
## HOW FAR A PLATE'S COLLIDER MAY STAND PROUD OF THE PLATE — see plate_colliders().
## A cell is split until the box fitted to it exceeds the slab it wraps by less
## than this along every frame axis, so the constant IS the phantom: the distance
## a player can be stopped short of a raked wall they can see.
##
## It was 0.15 m, and the name it carried (`PLATE_COLLIDER_STEP`) described the
## grid rather than the error, which is how nobody noticed that 0.15 m is ONE AND
## A HALF TIMES the 0.10 m plating. Measured on the shipped fixtures at 0.15:
## demo_workboat 0.1249 m, probe_trawler_bulwark 0.1478 m, critic_ferry 0.1528 m
## of solid air in front of every raked wall in the game.
##
## 0.05 m is half the plating and just over the 0.045 m half-thickness of the
## plate itself. (This paragraph said "0.03 m is a third of the plating" against
## a constant that has always been 0.05 — a comment disagreeing with the value
## beside it. CONVENTIONS.md 7: documentation drift is a defect.)
##
## ── WHAT IT COSTS, MEASURED, AND WHY THE VALUE IS AN OWNER DECISION ─────────
##
## The curve, from `tests/_plate_cost_probe.gd`, as collect_colliders() boxes and
## the worst box PROUD of its slab. "grid" is the pre-65b6a0a fixed nu x nv grid
## at its 0.15 m step; every other column is this adaptive dice.
##
##                       grid    0.15    0.10    0.08    0.05
##   demo_workboat        359     357     436     500     675   boxes
##   trawler_bulwark      760     612     876    1137    2118
##   container_feeder    2448    2467    2608    2735    3086
##   worst proud        0.150   0.126   0.086   0.075   0.050  m
##
## Three things that curve says and a single before/after pair does not:
##
##  - THE ALGORITHM IS FREE AND THE CONSTANT IS WHAT COSTS. At the SAME 0.15 m
##    the adaptive dice is 612 boxes to the grid's 760 on the trawler and level
##    everywhere else. Every box above the "grid" column is bought by the
##    constant, not by the rewrite.
##  - THE 150 M HULL IS NOT THE WORST CASE. `probe_container_feeder` is 1.26x at
##    0.05 where the 28 m trawler is 2.79x, because 251 of its containers are one
##    axis-aligned plate each and dice to one box whatever this says. Plate-heavy
##    superstructure is what this constant prices, not length.
##  - THE KNEE IS AROUND 0.08. Trawler: 0.15 -> 0.08 removes 58% of the phantom
##    for 1.9x the boxes; 0.08 -> 0.05 removes another 13 points for another
##    1.9x.
##
## The cost is superlinear in the box count and that is not this file's doing:
## putting boxes on a body is O(n^2) in Godot, through the scene tree AND through
## PhysicsServer3D.body_add_shape (`tests/_collider_build_probe.gd`: 500 boxes
## 79 ms, 2000 boxes 1432 ms, 8000 boxes 33.8 s). The feeder's collision costs
## 2109 ms to build at the grid and 3673 ms at 0.05; the trawler's, 204 and 1849.
##
## THE ALTERNATIVE THIS CONSTANT EXISTS INSTEAD OF is an oriented box — yaw AND
## pitch — which is EXACT for a planar quad and needs no dice at all. Measured
## ceiling, by disabling the split: 100 plate boxes on the trawler against 1913,
## 364 on the feeder against 1217, and zero phantom rather than 0.05 m. It is not
## free: `_collider_of`'s contract is yaw-only and `yaw_deg` is read at 121 sites
## under scripts/ and 53 under tests/, `BoatBody.add_walk_brick_collider` sets
## `rotation_degrees = Vector3(0, yaw, 0)`, and a WARPED plate (a corner off the
## plane of the other three — structure_plate_test section B builds one) is still
## not one box, so the dice has to survive alongside it.
const PLATE_COLLIDER_SLOP := 0.05
## Cells one slab may be cut into, whatever the slop asks for — the ceiling the
## old 32 x 32 grid had, kept so a pathological quad cannot spend the physics
## budget on its own. The budget is divided among a split's children, so it is a
## hard total and not a per-level limit.
const PLATE_MAX_COLLIDER_CELLS := 1024


static func plate_corners(spec: Dictionary) -> PackedVector3Array:
	return polyline_of(spec.get("corners", spec.get("quad", null)))


static func plate_thickness(spec: Dictionary) -> float:
	return float(spec.get("thickness", PLATE_DEFAULT_THICKNESS))


static func plate_segments(spec: Dictionary) -> int:
	return clampi(int(spec.get("segments", 1)), 1, PLATE_MAX_SEGMENTS)


## The quad's area vector: half the cross of its diagonals, which for a planar
## quad is exactly area × outward normal. Robust for a non-planar ring too — it
## is Newell's normal for four points, up to the factor.
static func plate_area_vector(c: PackedVector3Array) -> Vector3:
	if c.size() != 4:
		return Vector3.ZERO
	return (c[2] - c[0]).cross(c[3] - c[1]) * 0.5


static func plate_normal(c: PackedVector3Array) -> Vector3:
	var area := plate_area_vector(c)
	return Vector3.UP if area.length() < 1e-12 else area.normalized()


## A point on the plate's mid-surface at parameter (u, v) in [0,1]².
static func plate_point(c: PackedVector3Array, u: float, v: float) -> Vector3:
	if c.size() != 4:
		return Vector3.ZERO
	return c[0].lerp(c[1], u).lerp(c[3].lerp(c[2], u), v)


## The four corners of the sub-patch [u0,u1]×[v0,v1], in ring order. A bilinear
## patch restricted to a sub-rectangle is the bilinear patch on these four
## points, so panels, segments and collider cells all cut the SAME surface.
static func plate_subquad(c: PackedVector3Array, u0: float, u1: float, v0: float, v1: float) -> PackedVector3Array:
	return PackedVector3Array([
		plate_point(c, u0, v0), plate_point(c, u1, v0),
		plate_point(c, u1, v1), plate_point(c, u0, v1),
	])


## Mean length of the two u-edges and of the two v-edges, in metres. Openings are
## authored against these, so a window keeps its metre width on a tapered plate.
static func plate_ref_lengths(c: PackedVector3Array) -> Vector2:
	if c.size() != 4:
		return Vector2.ZERO
	return Vector2(
		(c[0].distance_to(c[1]) + c[3].distance_to(c[2])) * 0.5,
		(c[0].distance_to(c[3]) + c[1].distance_to(c[2])) * 0.5,
	)


## "" when the spec draws a plate, otherwise WHY IT DOES NOT. Degenerate input
## has to fail loudly: a zero-area quad emits a surface with no normal, a
## self-crossing ring emits a bow tie whose two halves face opposite ways and
## whose collider covers a region the eye never sees, and both of those look like
## a rendering bug rather than like a mis-authored plan. Callers push_error and
## draw nothing.
##
## COPLANAR corners are NOT degenerate — they are the normal case, and almost
## every plate anyone authors is flat. The degenerate cousin is COLLINEAR, which
## is what "zero area" below means.
##
## Order matters. The bow tie is checked BEFORE the area, because the commonest
## bow tie of all — a rectangle's last two corners swapped — has diagonals that
## are exactly PARALLEL, so its area vector vanishes and an area-first test
## reports "collinear" about four corners that are nothing of the sort.
static func plate_problem(spec: Dictionary) -> String:
	var c := plate_corners(spec)
	if c.size() != 4:
		return "needs exactly 4 corners, got %d" % c.size()
	for index in 4:
		var p := c[index]
		if not (is_finite(p.x) and is_finite(p.y) and is_finite(p.z)):
			return "corner %d is not finite (%s)" % [index, str(p)]
	for a in 4:
		for b in range(a + 1, 4):
			if c[a].distance_to(c[b]) < PLATE_MIN_EDGE:
				return "corners %d and %d coincide (%.6f m apart)" % [a, b, c[a].distance_to(c[b])]
	if _plate_self_crosses(c):
		return "self-crossing quad — the corners are not in ring order"
	var area := plate_area_vector(c).length()
	if area < PLATE_MIN_AREA:
		return "zero area (%.9f m2) — the four corners are collinear" % area
	if plate_thickness(spec) <= 0.0:
		return "thickness must be positive, got %.4f" % plate_thickness(spec)
	return ""


## A ring is simple exactly when neither pair of NON-ADJACENT edges meets. Tested
## in the plane the quad is most nearly parallel to. The dropped axis is the one
## the area vector is largest along — that projection keeps at least 1/sqrt(3) of
## the area — falling back to the axis the CORNERS are least spread along when
## the area vector is degenerate, which is exactly the swapped-corner bow tie
## this check exists for.
static func _plate_self_crosses(c: PackedVector3Array) -> bool:
	var normal := plate_area_vector(c).abs()
	if normal.length() < PLATE_MIN_AREA:
		var lo := c[0]
		var hi := c[0]
		for point in c:
			lo = Vector3(minf(lo.x, point.x), minf(lo.y, point.y), minf(lo.z, point.z))
			hi = Vector3(maxf(hi.x, point.x), maxf(hi.y, point.y), maxf(hi.z, point.z))
		## Least spread == the axis the ring is flattest along, so 1/x is the
		## dominance the code below is looking for.
		var spread := hi - lo
		normal = Vector3(
			1.0 / maxf(spread.x, 1e-9), 1.0 / maxf(spread.y, 1e-9), 1.0 / maxf(spread.z, 1e-9)
		)
	var axis := 0
	if normal.y >= normal.x and normal.y >= normal.z:
		axis = 1
	elif normal.z >= normal.x and normal.z >= normal.y:
		axis = 2
	var flat: Array[Vector2] = []
	for point in c:
		flat.append(_drop_axis(point, axis))
	var crossed: Variant = Geometry2D.segment_intersects_segment(flat[0], flat[1], flat[2], flat[3])
	if crossed != null:
		return true
	return Geometry2D.segment_intersects_segment(flat[1], flat[2], flat[3], flat[0]) != null


static func _drop_axis(v: Vector3, axis: int) -> Vector2:
	match axis:
		0:
			return Vector2(v.y, v.z)
		1:
			return Vector2(v.z, v.x)
	return Vector2(v.x, v.y)


## Openings in METRES on the plate surface: {off, w, sill, h} along the mean u
## and v edge lengths. Same shape and same defaults as a wall's, so a door is a
## door on either primitive.
static func plate_openings(spec: Dictionary, ref: Vector2) -> Array:
	var openings: Array = []
	for opening_variant in spec.get("openings", []) as Array:
		var opening := opening_variant as Dictionary
		var off := clampf(float(opening.get("offset", 0.0)), 0.0, ref.x)
		var width := clampf(float(opening.get("width", 1.0)), 0.0, ref.x - off)
		var type := str(opening.get("type", StructurePlan.OPENING_DOOR))
		var sill := clampf(
			float(opening.get("sill", 1.0 if type == StructurePlan.OPENING_WINDOW else 0.0)),
			0.0, ref.y
		)
		var height := clampf(
			float(opening.get("height", 2.2 if type == StructurePlan.OPENING_DOOR else 1.2)),
			0.1, ref.y - sill
		)
		if width > MIN_PANEL:
			openings.append({"off": off, "w": width, "sill": sill, "h": height})
	openings.sort_custom(func(a, b): return float(a["off"]) < float(b["off"]))
	return openings


## Panels {u0,u1,v0,v1} in NORMALISED parameter space, covering the plate minus
## its openings. The subtraction runs in metres — the same routine walls use, so
## MIN_PANEL means two centimetres here too — and is normalised on the way out.
static func plate_panels(spec: Dictionary) -> Array:
	var c := plate_corners(spec)
	if c.size() != 4:
		return []
	var ref := plate_ref_lengths(c)
	if ref.x <= 0.0 or ref.y <= 0.0:
		return []
	var out: Array = []
	for panel_variant in _panels_between(ref.x, ref.y, plate_openings(spec, ref)):
		var panel := panel_variant as Dictionary
		out.append({
			"u0": float(panel["u0"]) / ref.x, "u1": float(panel["u1"]) / ref.x,
			"v0": float(panel["v0"]) / ref.y, "v1": float(panel["v1"]) / ref.y,
		})
	return out


## Casing round every opening: a jamb up each side, a lintel across the head, a
## sill under a window — the same joinery a wall opening gets, in the plate's own
## parameter space and proud of BOTH faces. A deckhouse side with flush-cut holes
## reads as a cardboard cut-out; the proud frame is what makes a window read as a
## window from any angle.
##
## ── The casing stands AROUND the hole, never across it ──────────────────────
##
## Each member laps the PLATING by PLATE_FRAME_WIDTH - SKIN_EPS and the clear
## opening by SKIN_EPS, so the joint is still buried and `width`/`height` still
## mean what the author typed. They did not always: the jambs used to be centred
## ON the cut edges and the lintel ON the head, which quietly took
## PLATE_FRAME_WIDTH/2 off each side of every doorway and off its head. That cost
## nothing while the casing was drawn and not collided — and the moment it was
## collided (which it now is, because a drawn thing the body walks through is the
## drift this project keeps fixing) it would have taken 0.09 m off the shoulders
## and 0.045 m off the head of every door in the game, against a player capsule
## that already has to be measured to the centimetre to get through one.
static func plate_frames(spec: Dictionary) -> Array:
	var c := plate_corners(spec)
	if c.size() != 4:
		return []
	var ref := plate_ref_lengths(c)
	if ref.x <= 0.0 or ref.y <= 0.0:
		return []
	var w := PLATE_FRAME_WIDTH
	var out: Array = []
	for opening in plate_openings(spec, ref):
		var off := float(opening["off"])
		var width := float(opening["w"])
		var sill := float(opening["sill"])
		var head := sill + float(opening["h"])
		var has_sill := sill > 0.05
		var jamb_lo := (sill - SKIN_EPS) if has_sill else 0.0
		var jamb_hi := head + SKIN_EPS
		var jamb_mid := (jamb_hi + jamb_lo) * 0.5
		var jamb_len := maxf(jamb_hi - jamb_lo, 0.1)
		var span := width + w * 2.0
		var members := [
			{"u": off - w * 0.5 + SKIN_EPS, "v": jamb_mid, "ul": w, "vl": jamb_len},
			{"u": off + width + w * 0.5 - SKIN_EPS, "v": jamb_mid, "ul": w, "vl": jamb_len},
			{"u": off + width * 0.5, "v": head + w * 0.5 - SKIN_EPS, "ul": span, "vl": w},
		]
		if has_sill:
			members.append(
				{"u": off + width * 0.5, "v": sill - w * 0.5 + SKIN_EPS, "ul": span, "vl": w}
			)
		for member in members:
			var u := float(member["u"])
			var v := float(member["v"])
			var ul := float(member["ul"]) * 0.5
			var vl := float(member["vl"]) * 0.5
			var u0 := clampf(u - ul, 0.0, ref.x)
			var u1 := clampf(u + ul, 0.0, ref.x)
			var v0 := clampf(v - vl, 0.0, ref.y)
			var v1 := clampf(v + vl, 0.0, ref.y)
			## An opening flush with the plate's own edge clamps its outer jamb to
			## a sliver. MIN_PANEL is the same two centimetres the panel
			## decomposition drops, and it is applied here for the same reason: a
			## slab that thin is a z-fighting artefact and a physics shape nobody
			## asked for.
			if u1 - u0 < MIN_PANEL or v1 - v0 < MIN_PANEL:
				continue
			out.append({
				"u0": u0 / ref.x, "u1": u1 / ref.x, "v0": v0 / ref.y, "v1": v1 / ref.y,
			})
	return out


## EVERY slab one plate draws: its panels (the plate minus its openings) and the
## casing round each opening, as {u0,u1,v0,v1,thickness,frame} in the plate's own
## normalised parameter space.
##
## ONE list, and it is the only decomposition of a plate that exists — `plate_layers`
## draws it and `plate_colliders` collides it. REALITY.md §3b: where geometry and
## collision are computed separately they drift, and this project has now deleted
## the second derivation four times. The casing was the fourth. It was drawn
## PLATE_FRAME_PROUD past both faces while `plate_colliders` walked `plate_panels`
## alone, so 44 of the 72 casing corners on `probe_piece_house` — and 200 of 240 on
## `probe_piece_tug` — stood outside every box the baker emitted: a door frame you
## can see, and put your shoulder through.
static func plate_slabs(spec: Dictionary) -> Array:
	var thickness := plate_thickness(spec)
	var out: Array = []
	for panel_variant in plate_panels(spec):
		var panel := (panel_variant as Dictionary).duplicate()
		panel["thickness"] = thickness
		panel["frame"] = false
		out.append(panel)
	for frame_variant in plate_frames(spec):
		var frame := (frame_variant as Dictionary).duplicate()
		## Proud of BOTH faces, so the casing reads as depth from inside and out —
		## same trick, same reason, as a wall's opening frame.
		frame["thickness"] = thickness + PLATE_FRAME_PROUD * 2.0
		frame["frame"] = true
		out.append(frame)
	return out


## Renderable layers for one plate spec whose corners are ALREADY in plan space.
## Walks `plate_slabs` — the same list `plate_colliders` walks.
static func plate_layers(spec: Dictionary, corners: PackedVector3Array, source_id := -1) -> Array:
	var segments := plate_segments(spec)
	var color := _color_of(spec.get("color", null), DEFAULT_PLATE_COLOR)
	var material := str(spec.get("material", "painted"))
	var frame_color := _color_of(spec.get("frame_color", null), color.darkened(0.45))
	var frame_material := str(spec.get("frame_material", "steel"))
	var out: Array = []
	for slab_variant in plate_slabs(spec):
		var slab := slab_variant as Dictionary
		var is_frame := bool(slab["frame"])
		out.append({
			"kind": "slab",
			"quad": plate_subquad(
				corners, float(slab["u0"]), float(slab["u1"]),
				float(slab["v0"]), float(slab["v1"])
			),
			"thickness": float(slab["thickness"]),
			"segments": 1 if is_frame else segments,
			"color": frame_color if is_frame else color,
			"material": frame_material if is_frame else material,
			"source_id": source_id,
		})
	return out


## ── What a raked plate emits into the physics world ─────────────────────────
##
## The collider contract carries a YAW ONLY (see collect_colliders). An upright
## plate at any heading is exactly one yawed box and that is what it emits. A
## RAKED one — a wheelhouse front leaning 0.85 m forward over its 2.4 m, a sloped
## roof, a chine facet — is not spellable as one yawed box, and the two wrong
## answers are both worse than the geometry deserves:
##
##  - one box round the whole plate puts a PHANTOM WEDGE out over the open deck:
##    the front of a forward-raked wheelhouse overhangs, so the box fills the
##    triangle of air under the overhang and a player is stopped a quarter-metre
##    short of a wall they can see they have not reached. Not a hypothetical —
##    forcing the step count to 1 fills 2 465 of `structure_plate_test`'s phantom
##    samples and makes the sloped roof solid where it is open air;
##  - a pitched box cannot be expressed at all — every consumer reads yaw_deg and
##    would silently flatten it.
##
## What the YAW itself buys here is TIGHTNESS AND COUNT, not containment, and it
## is worth being exact about that because the wall and spar emitters are
## different: those place a box of known size and would leave a phantom without
## the yaw, whereas every box below is the exact bounding box in whatever frame
## it is given, so a de-yawed emitter still contains its geometry. It simply
## shreds it. Measured on a 45 degree plate — a bow bulwark — one exact box
## becomes thirty-two padded ones.
##
## So a raked plate is STEPPED, the same answer a sloped spar gets. Each panel is
## cut into cells and each cell emits the exact bounding box of its eight slab
## corners IN THE PANEL'S OWN YAW FRAME. Two properties make that honest:
##
##  1. It never under-covers. A bilinear patch lies inside the convex hull of its
##     four corners, so the cell's drawn surface — and its two offset skins — lie
##     inside the hull of the eight points the box is fitted to.
##  2. It costs nothing when there is nothing to step. The step count per
##     direction is driven by the cell's OFF-AXIS EXCURSION: of the three spans a
##     parametric direction covers in the yaw frame, the box's own dimensions
##     already account for the largest, so the error is the sum of the other two.
##     For an upright rectangular plate that sum is 0 and the answer is ONE box,
##     bit-exact. For the 0.85 m rake above it is 0.85 m, which is six steps.
##
## Openings come through plate_slabs(), so a door is a genuine hole in collision
## exactly as it is in the geometry — the two read the same decomposition, casing
## and all.
static func plate_colliders(spec: Dictionary, corners: PackedVector3Array, offset: Vector3) -> Array:
	if corners.size() != 4 or not bool(spec.get("solid", true)):
		return []
	var out: Array = []
	for slab_variant in plate_slabs(spec):
		var slab := slab_variant as Dictionary
		out.append_array(_plate_panel_colliders(
			corners, float(slab["thickness"]), offset,
			float(slab["u0"]), float(slab["u1"]), float(slab["v0"]), float(slab["v1"])
		))
	return out


static func _plate_panel_colliders(
	corners: PackedVector3Array, thickness: float, offset: Vector3,
	u0: float, u1: float, v0: float, v1: float,
) -> Array:
	## The half-offset is the PANEL's normal, not each cell's, because that is the
	## vector `_append_slab` offsets the drawn skins along. Re-deriving it per cell
	## would be a second derivation of the same quantity (REALITY.md §3b) and on a
	## warped quad the two disagree — which is precisely how a drawn face escapes
	## the box that is supposed to contain it.
	var half := plate_normal(plate_subquad(corners, u0, u1, v0, v1)) * (thickness * 0.5)
	var out: Array = []
	_dice_panel(corners, half, offset, u0, u1, v0, v1, PLATE_MAX_COLLIDER_CELLS, out)
	return out


## One cell: cut across the parametric direction whose box would stand furthest
## proud of the slab, until neither direction is over PLATE_COLLIDER_SLOP, then
## emitted as the exact bounding box of its own eight offset corners in its own
## yaw frame.
##
## `proud` is stated per DIRECTION, and the discount is the point: of the three
## spans a direction covers in the yaw frame, the box spends one of its
## dimensions on the LARGEST, so only the other two are error. An upright
## rectangular plate scores zero in both directions and is ONE box, bit-exact.
##
## Two things this does that the fixed nu x nv grid it replaces could not, and
## both are why the slop could be cut fivefold while the box count FELL:
##
##  - IT CUTS ONE DIRECTION AT A TIME, and re-measures. The grid computed nu and
##    nv up front in the panel's frame and emitted their PRODUCT, so a plate that
##    needed dicing up its rake paid for dicing along its length as well.
##  - EACH CELL CARRIES ITS OWN YAW. A bow bulwark's u-run swings round the stem
##    and its two u-edges are 5 degrees apart, so one panel yaw is wrong for every
##    cell but one; the grid could only answer that residual by dicing in u too.
##    Cut the rake first and each strip's own yaw fits it, so the u error falls
##    out with the v cuts instead of demanding cuts of its own. Measured on
##    probe_trawler_bulwark's worst slab: 5 x 10 = 50 boxes at 0.15 m of slop
##    became 48 boxes at 0.03 m — a fifth of the phantom for fewer boxes.
##
## The box is fitted to the cell's four corners offset by ±half along the PANEL's
## normal, which is the vector `_append_slab` offsets the drawn skins along; a
## bilinear patch lies inside the convex hull of its four corners, so the drawn
## cell lies inside its box and the one-derivation property holds cell by cell.
static func _dice_panel(
	corners: PackedVector3Array, half: Vector3, offset: Vector3,
	u0: float, u1: float, v0: float, v1: float, budget: int, out: Array,
) -> void:
	var cell := plate_subquad(corners, u0, u1, v0, v1)
	var yaw := _plate_yaw(cell)
	var basis := Basis(Vector3.UP, deg_to_rad(yaw))
	var inv := basis.transposed()
	var local: Array[Vector3] = []
	for point in cell:
		local.append(inv * point)
	var proud_u := _off_axis(_max_abs(local[1] - local[0], local[2] - local[3]))
	var proud_v := _off_axis(_max_abs(local[3] - local[0], local[2] - local[1]))
	var worst := maxf(proud_u, proud_v)
	if worst > PLATE_COLLIDER_SLOP and budget >= 2:
		var pieces := mini(int(ceil(worst / PLATE_COLLIDER_SLOP)), budget)
		## Integer division, so the children's budgets can only sum to less than
		## this one's — the total is bounded by the root's and cannot creep.
		var share: int = budget / pieces
		var cut_u := proud_u >= proud_v
		for k in pieces:
			var a := float(k) / float(pieces)
			var b := float(k + 1) / float(pieces)
			if cut_u:
				_dice_panel(corners, half, offset,
					lerpf(u0, u1, a), lerpf(u0, u1, b), v0, v1, share, out)
			else:
				_dice_panel(corners, half, offset,
					u0, u1, lerpf(v0, v1, a), lerpf(v0, v1, b), share, out)
		return
	var lo := Vector3.INF
	var hi := -Vector3.INF
	for point in cell:
		for sign in [1.0, -1.0]:
			var p := inv * (point + half * float(sign))
			lo = Vector3(minf(lo.x, p.x), minf(lo.y, p.y), minf(lo.z, p.z))
			hi = Vector3(maxf(hi.x, p.x), maxf(hi.y, p.y), maxf(hi.z, p.z))
	out.append({
		"center": basis * ((lo + hi) * 0.5) + offset,
		"size": hi - lo,
		"yaw_deg": yaw,
	})


## Heading of the panel's u run, as a yaw. Falls back to the v run for a plate
## whose u direction is vertical (a chine facet authored bottom-up), and to zero
## for one that is horizontal in neither — where the yaw of a level slab does not
## matter anyway.
static func _plate_yaw(quad: PackedVector3Array) -> float:
	for run in [
		(quad[1] + quad[2]) - (quad[0] + quad[3]),
		(quad[3] + quad[2]) - (quad[0] + quad[1]),
	]:
		var flat := Vector3((run as Vector3).x, 0.0, (run as Vector3).z)
		if flat.length() > AXIS_TOL:
			return rad_to_deg(atan2(-flat.z, flat.x))
	return 0.0


static func _max_abs(a: Vector3, b: Vector3) -> Vector3:
	return Vector3(
		maxf(absf(a.x), absf(b.x)), maxf(absf(a.y), absf(b.y)), maxf(absf(a.z), absf(b.z))
	)


## How far a single box round `span` stands proud of the run it wraps. The box
## spends one of its three dimensions on the LARGEST component, so the error is
## the sum of the other two. Zero for a run that lies along a frame axis, which
## is why an upright rectangular plate is still exactly one box.
static func _off_axis(span: Vector3) -> float:
	var sorted := [absf(span.x), absf(span.y), absf(span.z)]
	sorted.sort()
	return float(sorted[0]) + float(sorted[1])


## ── Item reading: where a plan's fittings become geometry ───────────────────
##
## `items[]` was declared, serialised and counted by StructurePlan and read by
## nothing. These are its first two readers. An item is a spar or a wire when its
## `props.primitive` says so, or failing that when its `item_id` does — so a
## catalog part may keep its own name and still resolve to a primitive.


static func item_primitive(item: Dictionary) -> String:
	var props := StructurePlan.item_props(item)
	return str(props.get("primitive", item.get("item_id", "")))


## Renderable layers for one item. Empty for anything this baker cannot draw yet
## — an unknown fitting costs nothing and is not silently turned into a box.
static func _item_layers(plan: StructurePlan, item: Dictionary) -> Array:
	var primitive := item_primitive(item)
	if primitive == "plate":
		var spec := StructurePlan.item_props(item)
		var problem := plate_problem(spec)
		if not problem.is_empty():
			push_error(
				"StructureBaker: item %d is a degenerate plate — %s. Nothing drawn."
				% [int(item.get("id", -1)), problem]
			)
			return []
		return plate_layers(
			spec,
			_transformed(plate_corners(spec), plan.item_transform(item)),
			int(item.get("id", -1)),
		)
	if primitive != "spar" and primitive != "wire":
		return []
	var props := StructurePlan.item_props(item)
	var xform := plan.item_transform(item)
	var wire := primitive == "wire"
	var path := PackedVector3Array()
	if wire:
		## Transform FIRST, sag SECOND: gravity is not in the fitting's frame.
		path = wire_path(_respec(props, _transformed(spar_path(props), xform)))
	else:
		path = _transformed(spar_path(props), xform)
	if path.size() < 2:
		return []
	var sides := spar_sides(props, WIRE_DEFAULT_SIDES if wire else SPAR_DEFAULT_SIDES)
	var radii := spar_radii(props, path, WIRE_DEFAULT_RADIUS if wire else SPAR_DEFAULT_RADIUS)
	return [{
		"kind": "tube",
		"points": path,
		"radii": radii,
		"sides": sides,
		"capped": bool(props.get("capped", true)),
		"color": _color_of(props.get("color", null), DEFAULT_WIRE_COLOR if wire else DEFAULT_SPAR_COLOR),
		"material": str(props.get("material", "steel" if wire else "metal")),
		"source_id": int(item.get("id", -1)),
	}]


static func _transformed(path: PackedVector3Array, xform: Transform3D) -> PackedVector3Array:
	var out := PackedVector3Array()
	for point in path:
		out.append(xform * point)
	return out


## A copy of `props` whose path is `path` — used to hand an already-transformed
## polyline back into wire_path() without mutating the plan's own dictionary.
static func _respec(props: Dictionary, path: PackedVector3Array) -> Dictionary:
	var spec := props.duplicate()
	spec.erase("from")
	spec.erase("to")
	spec.erase("path")
	spec["points"] = path
	return spec


## Colliders for one item, in plan space. See collect_colliders() for the whole
## argument; the short version is that a spar is an obstruction and a wire is
## not, and that a sloped run cannot be spelled in a yaw-only collider.
static func _item_colliders(plan: StructurePlan, item: Dictionary, offset: Vector3) -> Array:
	var primitive := item_primitive(item)
	if primitive == "plate":
		var spec := StructurePlan.item_props(item)
		## A plate that was refused for the eye is refused for the body too: a
		## collider with no geometry behind it is an invisible wall.
		if not plate_problem(spec).is_empty():
			return []
		return plate_colliders(
			spec, _transformed(plate_corners(spec), plan.item_transform(item)), offset
		)
	if primitive != "spar":
		return []
	var props := StructurePlan.item_props(item)
	if not bool(props.get("solid", true)):
		return []
	var path := _transformed(spar_path(props), plan.item_transform(item))
	if path.size() < 2:
		return []
	var radii := spar_radii(props, path, SPAR_DEFAULT_RADIUS)
	var out: Array = []
	for index in range(path.size() - 1):
		var a := path[index]
		var b := path[index + 1]
		var radius := maxf(radii[index], radii[index + 1])
		if radius < SPAR_COLLIDER_MIN_RADIUS:
			continue
		out.append_array(_run_colliders(a, b, radius, offset))
	return out


static func _run_colliders(a: Vector3, b: Vector3, radius: float, offset: Vector3) -> Array:
	var delta := b - a
	var length := delta.length()
	if length < PATH_EPS:
		return []
	var dir := delta / length
	var girth := radius * 2.0
	var mid := (a + b) * 0.5 + offset
	if absf(dir.y) >= 1.0 - AXIS_TOL:
		## Vertical: exact, one box, and the yaw of a circle does not matter.
		return [{"center": mid, "size": Vector3(girth, length, girth), "yaw_deg": 0.0}]
	if absf(dir.y) <= AXIS_TOL:
		## Level: exact at ANY heading, because the collider contract carries a
		## yaw. Same convention as wall_yaw_deg — a +Y rotation of theta takes +X
		## to (cos theta, 0, -sin theta).
		return [{
			"center": mid,
			"size": Vector3(length, girth, girth),
			"yaw_deg": rad_to_deg(atan2(-dir.z, dir.x)),
		}]
	## Sloped. The collider contract is yaw-only (see collect_colliders), so a
	## raked mast or a curved davit arm cannot be one rotated box: an unrotated
	## box round it would be a phantom slab standing out over the open deck, and
	## a pitched box would be silently flattened by every consumer. Step it
	## instead — a staircase of axis-aligned boxes, each the sub-run's own
	## bounding box grown by the tube radius, which OVER-approximates by at most
	## about half a step and never under-approximates. Over is the safe side: the
	## player is stopped a few centimetres early rather than walking through a
	## boom.
	var steps := maxi(1, int(ceil(length / SPAR_COLLIDER_STEP)))
	var out: Array = []
	for index in steps:
		var p0 := a.lerp(b, float(index) / float(steps))
		var p1 := a.lerp(b, float(index + 1) / float(steps))
		var span := (p1 - p0).abs()
		out.append({
			"center": (p0 + p1) * 0.5 + offset,
			"size": Vector3(span.x + girth, span.y + girth, span.z + girth),
			"yaw_deg": 0.0,
		})
	return out


# ── Bake outputs ─────────────────────────────────────────────────────────────

## All collision boxes for the plan, offset into host-local space, as
## {center, size, yaw_deg}. Decks, stairs and axis-aligned walls report
## yaw_deg 0.0; a diagonal wall reports the yaw its geometry was drawn with.
## `size` is measured in the box's own frame, so a caller that builds a shape
## from center + size alone has NOT built the box that was drawn — it has built
## the axis-aligned one, which on a 45 degree bulwark leaves a wall the player
## walks straight through and a phantom solid out over the open deck.
##
## Every in-tree consumer honours the yaw today — this is a roster, not a wish,
## and a new consumer joins it rather than being the first to keep it:
##
## - `DeckFitout.apply_plan` (scripts/ship/deck_fitout.gd) — the only production
##   consumer. Passes yaw_deg to `BoatBody.add_walk_brick_collider`, which
##   applies it as the shape's Y rotation on the PhysicsServer3D body.
## - `plan_collision_test` (tests/) — rebuilds each box's frame with
##   `Basis(Vector3.UP, deg_to_rad(yaw)).transposed()` for its ray intervals and
##   its signed-distance union, and asserts the yaw equals the one the PLAN's
##   run direction demands (derived independently of `wall_yaw_deg`).
## - `structure_circulation_test` (tests/) — same inverse-yaw transform in its
##   `_contains` probe, covered by a diagonal case whose two probes swap
##   verdicts the moment the yaw is dropped.
##
## So: apply yaw_deg about the box's own centre, or do not use this list.
##
## ── What a spar and a wire emit, and why ────────────────────────────────────
##
## A SPAR IS SOLID. Not because you can stand on it — you cannot stand on a mast
## — but because a spar is the one fitting a walking player runs into: a boom or
## a derrick at head height is an obstruction, a gallows leg is a thing you walk
## around, a stanchion is a thing you bruise a shin on. A box per run, tight to
## the tube, does exactly that and nothing more: the box spans the spar's girth
## only, so a player whose head clears a boom still walks under it. `solid: false`
## opts a purely decorative spar out, and a run thinner than
## SPAR_COLLIDER_MIN_RADIUS emits nothing regardless — being stopped by a 40 mm
## whip antenna the eye cannot resolve reads as a bug, not as a fitting.
##
## A WIRE IS NEVER SOLID, and there is no opt-in. Standing and running rigging
## crosses a working deck everywhere; a shroud that stops a player is an
## invisible wall at head height in the middle of the deck. You duck under a stay
## and you step over a mooring line. A sagged wire would also need dozens of tiny
## boxes to follow its own curve, which is a lot of physics to buy a defect.
##
## The sloped case is the interesting one. This list carries a YAW ONLY. A level
## run is exact at any heading (that is what yaw is for) and a vertical run is
## exact trivially, but a raked mast, a sloped boom or a curved davit arm is
## neither, and there is no field to put its pitch in. Emitting one unrotated box
## around it would put a phantom slab out over the open deck — the exact defect
## `plan_collision_physics_test` exists to catch on diagonal bulwarks. So a
## sloped run is STEPPED into a staircase of short axis-aligned boxes instead,
## each the sub-run's bounding box grown by the tube radius. That over-covers by
## roughly half a step and never under-covers.
static func collect_colliders(plan_in: StructurePlan, offset := Vector3.ZERO) -> Array:
	var plan := resolved(plan_in)
	var expanded := expand(plan)
	var out: Array = []
	for wall_variant in expanded["walls"] as Array:
		for box_variant in wall_boxes(wall_variant as Dictionary):
			out.append(_collider_of(box_variant as Dictionary, offset))
	for deck_variant in expanded["decks"] as Array:
		for box_variant in deck_boxes(deck_variant as Dictionary):
			out.append(_collider_of(box_variant as Dictionary, offset))
	for stair_variant in expanded["stairs"] as Array:
		for box_variant in stair_boxes(stair_variant as Dictionary):
			out.append(_collider_of(box_variant as Dictionary, offset))
	for item_variant in plan.items:
		out.append_array(_item_colliders(plan, item_variant as Dictionary, offset))
	## `sweep_collider_boxes` already returns exactly the {center, size, yaw_deg}
	## dictionary `_collider_of` consumes, so an edge gets the same one-liner
	## every other entity gets — no edge-specific collider shape exists.
	for edge_variant in plan.edges:
		for box_variant in edge_collider_boxes(plan, edge_variant as Dictionary):
			out.append(_collider_of(box_variant as Dictionary, offset))
	return out


static func _collider_of(box: Dictionary, offset: Vector3) -> Dictionary:
	return {
		"center": (box["center"] as Vector3) + offset,
		"size": box["size"],
		"yaw_deg": float(box.get("yaw_deg", 0.0)),
	}


## Merged visual bake: one MeshInstance3D per MATERIAL. Layer colour is written
## per vertex and the material reads it as albedo, so the draw-call count is
## bounded by MATERIALS.size() (4) no matter how many colours a plan uses.
##
## `ghost` renders the whole bake as translucent shadowless x-ray, and is the
## ONE case that still keeps colour in the bucket key. Alpha blending is
## order-dependent, and Godot depth-sorts transparent geometry per OBJECT, never
## within one: merging two colours into a single translucent surface composites
## them in submission order instead of by depth. Measured on demo_workboat, that
## moved 15 070 pixels by up to 47/255 in the studio's x-ray — while reversing
## the legacy draw order (either across objects or within a bucket) moved zero,
## because a one-colour bucket blends the same in any order. The ghost is one
## editor overlay, not a harbour full of vessels, so it pays the extra draw calls
## and keeps its picture; the solid bake — everything that ships in the world —
## merges on material alone.
static func bake(plan_in: StructurePlan, offset := Vector3.ZERO, ghost := false) -> Node3D:
	var plan := resolved(plan_in)
	var root := Node3D.new()
	root.name = "StructureBake"
	var buckets: Dictionary = {}
	var expanded := expand(plan)
	var wall_default := _palette_color(plan, "wall", DEFAULT_WALL_COLOR)
	var deck_default := _palette_color(plan, "deck", DEFAULT_DECK_COLOR)
	for wall_variant in expanded["walls"] as Array:
		for layer_variant in _wall_layers(wall_variant as Dictionary, wall_default):
			_bucket_layer(buckets, layer_variant as Dictionary, offset, ghost)
	for deck_variant in expanded["decks"] as Array:
		for layer_variant in _plate_layers(deck_variant as Dictionary, wall_default, deck_default):
			_bucket_layer(buckets, layer_variant as Dictionary, offset, ghost)
	for stair_variant in expanded["stairs"] as Array:
		for layer_variant in _stair_layers(stair_variant as Dictionary, deck_default):
			_bucket_layer(buckets, layer_variant as Dictionary, offset, ghost)
	## Spars and wires bucket by the SAME key as every box, so a whole rig — mast,
	## boom, stack, davits, stays, mooring lines — merges into the surfaces the
	## hull already draws and buys ZERO extra draw calls.
	for item_variant in plan.items:
		for layer_variant in _item_layers(plan, item_variant as Dictionary):
			_bucket_layer(buckets, layer_variant as Dictionary, offset, ghost)
	## A swept run goes into the SAME buckets. Every box StructureEdge emits
	## carries a material name from MATERIALS and its colour rides in the vertex
	## stream, so a 70 m bulwark in two colours is one more surface at most — and
	## on a plan that already paints something "painted", none.
	for edge_variant in plan.edges:
		for box_variant in edge_boxes(plan, edge_variant as Dictionary):
			_bucket_layer(buckets, box_variant as Dictionary, offset, ghost)
	for key in buckets.keys():
		var bucket := buckets[key] as Dictionary
		var st := bucket["st"] as SurfaceTool
		var material := StandardMaterial3D.new()
		## White albedo is the identity for the per-vertex multiply: the shader
		## uses albedo_color * vertex_color, so the colour the layer asked for is
		## exactly what lands (to 8-bit vertex precision — measured equal to the
		## old per-bucket albedo within one LSB).
		material.albedo_color = Color.WHITE
		material.vertex_color_use_as_albedo = true
		var response: Dictionary = MATERIALS.get(str(bucket["material"]), MATERIALS["painted"])
		material.roughness = float(response["roughness"])
		material.metallic = float(response["metallic"])
		if ghost:
			## One colour per translucent surface: read it off the material and
			## ignore the (still present, still correct) vertex colours.
			material.albedo_color = Color(bucket["color"] as Color, 0.13)
			material.vertex_color_use_as_albedo = false
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		st.set_material(material)
		var mesh := st.commit()
		if mesh != null and mesh.get_surface_count() > 0:
			var instance := MeshInstance3D.new()
			instance.name = "Structure_%s" % str(key)
			instance.mesh = mesh
			if ghost:
				instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(instance)
	return root


static func _palette_color(plan: StructurePlan, slot: String, fallback: Color) -> Color:
	var raw: Variant = plan.palette.get(slot, null)
	return _color_of(raw, fallback)


## Buckets key on MATERIAL ALONE. Colour is a vertex attribute, so adding a
## colour to a plan costs vertices, never a draw call: the bucket count is
## bounded by MATERIALS.size() forever. Putting colour back in the key is the
## regression this exists to prevent — a 12-colour plan would go from 4 mesh
## instances to 12+, which is the whole draw-call budget for a harbour.
##
## MEASURED 2026-08-15 on the renderer's own counter, one fixed camera pose,
## `demo_workboat` repainted in place (`tests/_colour_drawcall_probe.tscn`):
##
##     22 distinct colours -> 3 mesh instances, 11 draw calls, 30224 primitives
##     64 distinct colours -> 3 mesh instances, 11 draw calls, 30224 primitives
##
## Zero delta on all three, at three times the colour count the claim is usually
## stated at. Note it is THREE instances, not four: MATERIALS.size() is the
## bound, not the count — `demo_workboat` uses painted/steel/wood and never
## touches "metal". Quote the bound, not "it bakes to 4".
##
## The `keyed_by_color` branch below is the same measurement run as the
## mutation: it IS "put colour back in the key", live in production for the
## ghost, and on that same fixture at 64 colours it costs **112 mesh instances
## and 112 draw calls**. That is the regression, priced.
##
## `keyed_by_color` is the translucent-ghost exception documented on bake(): a
## blended surface may only carry one colour, or the composite depends on
## submission order.
static func _bucket_layer(buckets: Dictionary, layer: Dictionary, offset: Vector3, keyed_by_color := false) -> void:
	var color := layer["color"] as Color
	var material := str(layer["material"])
	var key := material
	if keyed_by_color:
		key = "%s_%02x%02x%02x" % [material, int(color.r * 255.0), int(color.g * 255.0), int(color.b * 255.0)]
	if not buckets.has(key):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		buckets[key] = {"color": color, "material": material, "st": st}
	var tool := (buckets[key] as Dictionary)["st"] as SurfaceTool
	## A tube goes into the same SurfaceTool as a box. It is a different emitter,
	## not a different surface — that is the whole reason a rig is free.
	if str(layer.get("kind", "box")) == "slab":
		_append_slab(
			tool,
			_offset_path(layer["quad"] as PackedVector3Array, offset),
			float(layer["thickness"]),
			int(layer.get("segments", 1)),
			color,
		)
		return
	if str(layer.get("kind", "box")) == "tube":
		_append_tube(
			tool,
			_offset_path(layer["points"] as PackedVector3Array, offset),
			layer["radii"] as PackedFloat32Array,
			int(layer["sides"]),
			bool(layer.get("capped", true)),
			color,
		)
		return
	_append_box(
		tool,
		(layer["center"] as Vector3) + offset,
		layer["size"] as Vector3,
		layer.get("basis", Basis.IDENTITY) as Basis,
		color,
	)


static func _offset_path(path: PackedVector3Array, offset: Vector3) -> PackedVector3Array:
	if offset == Vector3.ZERO:
		return path
	var out := PackedVector3Array()
	for point in path:
		out.append(point + offset)
	return out


## Box of `size` centred on `center`, 12 triangles, clockwise-front winding
## (Godot convention: right-hand cross of vertex order = MINUS the outward
## normal).
##
## "verified in tests/winding_probe.gd" used to end that sentence. It was not a
## verification: that file inspects a built-in `BoxMesh`, PRINTS the convention
## it finds and calls `quit(0)` unconditionally — no `TestReport`, no assertion,
## no way to go red — and, lacking a leading underscore, the gate discovered it
## and scored it `PASS` (6 s) alongside real units.
##
## Closed 2026-08-15. That file is now `tests/_winding_probe.gd` (underscored,
## so the gate skips it) and the check this comment said did not exist is
## `tests/box_winding_test.gd`: it commits a box through THIS function and
## asserts, on the emitted mesh, that every stored normal points away from the
## box centre and that every triangle's right-hand cross opposes it. Mutation
## verified by reversing a face's vertex order and by flipping a face normal.
##
## `basis` rotates the box about its own centre; `size` is then read in that
## rotated frame. A rotation has determinant +1, so it carries vertex order and
## normals together and the winding convention survives untouched — the identity
## default reproduces the axis-aligned box exactly (1*x + 0*y + 0*z == x).
##
## `color` is written on EVERY vertex this box emits, which is safe because no
## vertex is ever shared: the emitter walks 6 faces x 2 triangles x 3 corners and
## calls add_vertex 36 times, so a box's 8 geometric corners appear as 24 distinct
## vertices (3 per corner, one per adjoining face — required anyway, since each
## face carries its own flat normal) and SurfaceTool.commit() is left unindexed.
## Two differently-coloured boxes therefore cannot share a vertex and cannot
## bleed into each other; measured 36 verts/box before and after this change.
static func _append_box(
	st: SurfaceTool,
	center: Vector3,
	size: Vector3,
	basis := Basis.IDENTITY,
	color := Color.WHITE,
) -> void:
	var h := size * 0.5
	var corners := [
		center + basis * Vector3(-h.x, -h.y, -h.z), center + basis * Vector3(h.x, -h.y, -h.z),
		center + basis * Vector3(h.x, -h.y, h.z), center + basis * Vector3(-h.x, -h.y, h.z),
		center + basis * Vector3(-h.x, h.y, -h.z), center + basis * Vector3(h.x, h.y, -h.z),
		center + basis * Vector3(h.x, h.y, h.z), center + basis * Vector3(-h.x, h.y, h.z),
	]
	var faces := [
		[[0, 1, 5, 4], Vector3(0, 0, -1)],
		[[2, 3, 7, 6], Vector3(0, 0, 1)],
		[[1, 2, 6, 5], Vector3(1, 0, 0)],
		[[3, 0, 4, 7], Vector3(-1, 0, 0)],
		[[4, 5, 6, 7], Vector3(0, 1, 0)],
		[[3, 2, 1, 0], Vector3(0, -1, 0)],
	]
	for face in faces:
		var idx: Array = face[0]
		var normal: Vector3 = basis * (face[1] as Vector3)
		for tri in [[0, 1, 2], [0, 2, 3]]:
			for k in tri:
				st.set_color(color)
				st.set_normal(normal)
				st.add_vertex(corners[idx[k]])


## Closed slab over the bilinear patch on `quad`, `thickness` thick, split into
## `segments`² cells so a twisted plate shades as a twisted plate rather than as
## two flat triangles.
##
## Winding matches _append_box and _append_tube exactly — Godot's clockwise-front
## convention, so the right-hand cross of the vertex order is MINUS the outward
## normal. Derived rather than guessed, from the one convention the corner ring
## fixes: with corners counter-clockwise seen from outside, the front cell
## (a,b,c,d) is counter-clockwise about +n, so it emits as (a,d,c) + (a,c,b); the
## back cell faces -n and emits in its own order; and walking the boundary in the
## same counter-clockwise sense puts the exterior on the RIGHT, so a skirt quad
## (front p, front q, back q, back p) has cross = -(edge × n) = -outward for
## free. Getting this backwards renders the plate inside-out, which under
## backface culling looks like a hole rather than like a mistake.
##
## Normals are FLAT per face — +n on the front grid, -n on the back, and the
## edge's own outward for each skirt — which is what a plate is: a folded sheet,
## not a smooth surface. Colour is written on every vertex; as with boxes and
## tubes no vertex is shared, so two differently-coloured plates in one surface
## cannot bleed into each other.
##
## Triangle count is exactly 4·su·sv + 4·(su + sv) — 12 for one segment, which
## is a box, which is what a flat plate is.
static func _append_slab(
	st: SurfaceTool,
	quad: PackedVector3Array,
	thickness: float,
	segments: int,
	color: Color,
) -> void:
	if quad.size() != 4:
		return
	var normal := plate_normal(quad)
	var half := normal * (thickness * 0.5)
	var n := maxi(segments, 1)
	## (n+1)² mid-surface samples; front is +half off each, back is -half.
	var mid: Array[Vector3] = []
	for j in n + 1:
		for i in n + 1:
			mid.append(plate_point(quad, float(i) / float(n), float(j) / float(n)))
	for j in n:
		for i in n:
			var a := mid[j * (n + 1) + i]
			var b := mid[j * (n + 1) + i + 1]
			var c := mid[(j + 1) * (n + 1) + i + 1]
			var d := mid[(j + 1) * (n + 1) + i]
			_tri(st, color, a + half, normal, d + half, normal, c + half, normal)
			_tri(st, color, a + half, normal, c + half, normal, b + half, normal)
			_tri(st, color, a - half, -normal, b - half, -normal, c - half, -normal)
			_tri(st, color, a - half, -normal, c - half, -normal, d - half, -normal)
	## The boundary, counter-clockwise about +n: v=0 rising in u, u=1 rising in v,
	## v=1 falling in u, u=0 falling in v.
	var ring: Array[Vector3] = []
	for i in n:
		ring.append(mid[i])
	for j in n:
		ring.append(mid[j * (n + 1) + n])
	for i in n:
		ring.append(mid[n * (n + 1) + (n - i)])
	for j in n:
		ring.append(mid[(n - j) * (n + 1)])
	for index in ring.size():
		var p := ring[index]
		var q := ring[(index + 1) % ring.size()]
		var edge := q - p
		if edge.length() < PATH_EPS:
			continue
		var outward := edge.cross(normal).normalized()
		_tri(st, color, p + half, outward, q + half, outward, q - half, outward)
		_tri(st, color, p + half, outward, q - half, outward, p - half, outward)


## Tube of `sides` sides swept along `path`, radius `radii[i]` at node i.
##
## Winding matches _append_box exactly — Godot's clockwise-front convention, so
## the right-hand cross of the vertex order is MINUS the outward normal. Derived,
## not guessed: for the side quads the cross of the two edge vectors works out to
## -e (the outward radial) times a positive scalar, and each fan cap is ordered
## to give -(+/-run). Getting this backwards renders the spar inside-out, which
## under backface culling looks like a hole rather than like a mistake.
##
## Normals are RADIAL per vertex around the circumference, so an 8-sided mast
## shades as a round mast rather than as an octagonal prism, and FLAT on the two
## caps. Colour is written on every vertex; as with boxes no vertex is shared, so
## two differently-coloured spars in one surface cannot bleed into each other.
##
## Triangle count is exactly 2 * sides * rings when capped (2 * sides *
## (rings - 1) when not) — see the header of the spar section.
static func _append_tube(
	st: SurfaceTool,
	path: PackedVector3Array,
	radii: PackedFloat32Array,
	sides: int,
	capped: bool,
	color: Color,
) -> void:
	var rings := tube_rings(path, radii, sides)
	if rings.size() < 2:
		return
	for index in rings.size() - 1:
		var a := rings[index] as PackedVector3Array
		var b := rings[index + 1] as PackedVector3Array
		var centre_a := path[index]
		var centre_b := path[index + 1]
		for k in sides:
			var k2 := (k + 1) % sides
			var na := (a[k] - centre_a).normalized()
			var na2 := (a[k2] - centre_a).normalized()
			var nb := (b[k] - centre_b).normalized()
			var nb2 := (b[k2] - centre_b).normalized()
			_tri(st, color, a[k], na, b[k], nb, b[k2], nb2)
			_tri(st, color, a[k], na, b[k2], nb2, a[k2], na2)
	if not capped:
		return
	var first := rings[0] as PackedVector3Array
	var start_normal := (path[0] - path[1]).normalized()
	for k in sides:
		var k2 := (k + 1) % sides
		_tri(st, color, path[0], start_normal, first[k], start_normal, first[k2], start_normal)
	var last := rings[rings.size() - 1] as PackedVector3Array
	var end_centre := path[path.size() - 1]
	var end_normal := (end_centre - path[path.size() - 2]).normalized()
	for k in sides:
		var k2 := (k + 1) % sides
		_tri(st, color, end_centre, end_normal, last[k2], end_normal, last[k], end_normal)


static func _tri(
	st: SurfaceTool, color: Color,
	p0: Vector3, n0: Vector3, p1: Vector3, n1: Vector3, p2: Vector3, n2: Vector3,
) -> void:
	st.set_color(color)
	st.set_normal(n0)
	st.add_vertex(p0)
	st.set_color(color)
	st.set_normal(n1)
	st.add_vertex(p1)
	st.set_color(color)
	st.set_normal(n2)
	st.add_vertex(p2)
