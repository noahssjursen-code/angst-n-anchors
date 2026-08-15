class_name StructurePlan
extends RefCounted

## Parametric construction document shared by vessels and land buildings.
##
## Structure is DRAWN, not stacked: four primitives, each one part regardless
## of size, replace fields of voxel bricks:
##   walls  — {id, start:[x,y,z], axis:"x"|"z"|"+x+z"|"+x-z"|"-x+z"|"-x-z",
##             length, height, thickness,
##             color?, openings:[{type, offset, width, height, sill}]}
##   decks  — {id, origin:[x,y,z], size:[w,l], thickness, color?,
##             openings:[{type, offset:[dx,dz], size:[w,l]}]}
##   stairs — {id, start:[x,y,z], dir:"+x"|"-x"|"+z"|"-z", length, width,
##             height, color?}  start = footprint min corner at the LOW end's
##             base level; dir = climb direction; solid stepped run whose top
##             tread lands flush on start.y + height.
##   pieces — {id, piece:"<kit id>", cell:[cx,cy,cz], facing:0|90|180|270,
##             params:{<name>:<int|string off the declared set>}, color?:"#rrggbb"}
##             A PLACEMENT FROM THE STRUCTURAL PIECE KIT. Not geometry: a named
##             piece standing on a grid NODE, whose every parameter comes off a
##             finite declared set in `resources/data/parts/structure_pieces.json`.
##             `PieceKit.resolve_document` turns these into ordinary `items[]`
##             plates at bake time, so the baker never learns a new word.
##   items  — {id, item_id, at:[x,y,z], yaw, pitch?, roll?,
##             host?:{id, face?, anchor?}, props?:{...}}  (point fittings)
##   edges  — {id, primitive:"sheer_band"|"railing", path:[[x,y,z],…] | from_hull,
##             profile?|width+thickness, base_y?, closed?, material?, colour keys,
##             solid?}  (a cross-section swept along a polyline)
##
## There is deliberately NO box/room primitive. An axis-aligned box that expands
## to four walls, a floor and a ceiling can only ever draw a shed, and every
## deckhouse built out of one came out as a rectangle on a rectangle. Real
## superstructure is raked, tapered, stepped and set back, so the primitive that
## draws it is a sloped plate — not a box. Do not reintroduce the box.
##
## Coordinates are grid-corner points in metres. For vessels x/z match
## DeckGrid cell corners (0..width, 0..length) and y is metres above the deck
## plane.
##
## ── edges[]: the swept runs ──────────────────────────────────────────────────
##
## A wall is a straight plate of constant height; an edge is a CROSS-SECTION
## SWEPT ALONG A POLYLINE, and the two are not the same primitive. A bulwark
## whose cap rises toward the stem, a guardrail following a curved deck edge, a
## rubbing strake, a pipe run — none of them is a run of walls, and drawing them
## as one is how a vessel ends up reading as two parallel horizontal bars.
##
## `StructureEdge` owns the geometry. This file owns the DOCUMENT: an edge is a
## first-class plan entity with an id, so it counts, serialises, is addressable
## and — like a wall — can HOST a fitting. A cleat belongs on a bulwark cap, and
## a cleat that does not move when its bulwark moves is a trap for the builder.
##
## ── `from_hull`, and why an edge may not restate a curve ─────────────────────
##
## The one thing an edge must never do is write out a hull's sheer as a list of
## points. That curve is derived — `HullStations.sheer_cap_y_at` is freeboard
## times the hull form's own bow/stern keel rise — so a fixture that copied it
## would be stale the moment anyone retuned `fine_entry`. `from_hull` says "the
## deck edge of this hull, as a bulwark" and `edge_spec()` resolves it through
## `StructureEdge.sheer_bulwark_spec`. The only authored length is `height`, the
## cap AMIDSHIPS, which is a fall-barrier dimension set by the 1.8 m figure and
## is the same on a 28 m trawler and a 150 m freighter.
##
## ── The item placement model ─────────────────────────────────────────────────
##
## An item is a point fitting: a mast, a cleat, a fender, a stack, a railing
## post. It is NOT a brick, so it does not live in a cell:
##
##   at      float metres, not a cell index. A cleat 0.4 m inboard of a rail is
##           [x, y, z] with a .4 in it, and it stays there.
##   yaw     free degrees about the frame's +Y. Never quantised.
##   pitch   free degrees about the frame's +X — a raked mast, a sloped boom,
##           a raked windscreen post. OMITTED from the dict when exactly 0.
##   roll    free degrees about the frame's +Z — a fitting on a flared topside,
##           a canted davit. OMITTED from the dict when exactly 0.
##   host    optional attachment to another plan entity by id. When present,
##           `at` and the rotations are expressed in that entity's ATTACH FRAME
##           (below), so the fitting travels with its host. A cleat that does
##           not move when its bulwark moves is a trap for the builder.
##   props   optional per-instance bag: length, radius, colour region,
##           capacity, post pitch, sag. JSON values only. OMITTED when empty.
##
## Why three angles and not one, and not a full basis. Yaw alone cannot express
## a raked mast or a sloped derrick boom, and both appear on unrelated vessels
## and on land cranes — so rake is not a vessel feature, it is a spar feature.
## Roll is the third of the pair a builder needs to hang anything off a surface
## that is not level. A full Basis or quaternion would cover more and be worse:
## a builder types "rake 6", not nine floats, and a UI has to show SOMETHING.
## The cost is capped by omitting pitch/roll when zero, so the common fitting is
## still five keys. The rotation ORDER is fixed and shared by every consumer —
## yaw (Y), then pitch (X), then roll (Z), i.e. EULER_ORDER_YXZ — via
## `item_basis()`. Do not re-derive it anywhere else.
##
## ── Attach frames ────────────────────────────────────────────────────────────
##
## `host.id` names any wall / deck / stair / item in the same plan.
## `host.face` picks a surface, `host.anchor` picks where along it the origin
## sits ("start" | "center" | "end"). Every frame is right-handed with:
##   +x  along the host's run / width, from the anchor
##   +y  out of the face when the face is horizontal (a deck top), otherwise up
##   +z  the remaining axis — which on a VERTICAL face is the outward normal,
##       so `at.z` reads as "how far off the surface"; negative is inboard,
##       e.g. a cleat 0.4 m inboard of a bulwark is at.z = -0.4
## Faces: wall "front"|"back"; deck "top"|"bottom"; stair "run"; edge
## "cap"|"side"; item — none, the frame IS the host item's resolved transform, so
## fittings compose (a lamp on a mast on a wheelhouse).
##
## An EDGE host is the one whose run is not a straight line. `anchor` therefore
## walks ARC LENGTH along the polyline — "center" on a bulwark loop is halfway
## ROUND the loop, at the transom, not on a chord across the deck — and the frame
## is taken where it lands, so a fitting on a curved run is square to the curve
## where it stands. `at` is still a straight offset in that frame, as it is for
## every other host: the anchor picks the station, `at` is the local placement,
## and a fitting 30 m along a curved run wants its own anchor rather than a
## 30 m `at.x` that leaves the curve immediately.
##
## "cap" lifts the origin to the top of the swept section — a cleat asks for the
## cap, not for the cap's thickness — and "side" leaves it on the path line.
##
## An edge's frame is built exactly as a wall's, `+z = run x UP`, which is the
## LEFT HAND of the run. Which side of a vessel that lands on is decided by the
## TRAVERSAL, not here, so it is worth saying where it actually lands rather than
## leaving a builder to work it out: `StructureEdge.sheer_loop` goes starboard
## bow->stern, across the transom, then port stern->bow, and on every segment of
## it the left hand points INBOARD. So on a `from_hull` bulwark a cleat 0.4 m
## inboard of the cap is `at = (0, 0, +0.4)` — the opposite sign to the wall
## example above, because a wall's run direction is chosen by whoever drew it.
## `structure_plan_edges_test` measures the sign on all 182 segments of the loop
## rather than trusting this paragraph.
##
## `item_transform(item)` resolves the whole chain to plan space. Host cycles
## and chains deeper than ITEM_HOST_MAX_DEPTH are reported and fall back to the
## unhosted reading rather than hanging.
##
## ── What the geometry wave adds ──────────────────────────────────────────────
##
## Nothing in this file emits a triangle. A later wave adds the reader in
## StructureBaker; the call site is exactly:
##
##     for item_variant in plan.items:
##         var item := item_variant as Dictionary
##         var xform := plan.item_transform(item)              # plan space
##         var props := StructurePlan.item_props(item)         # per-instance
##         for part in ItemCatalog.parts(str(item["item_id"]), props):
##             emit_box(xform * (part["center"] as Vector3), ...,
##                 source_id = int(item["id"]))
##
## i.e. the baker asks the plan WHERE (one Transform3D) and the catalog WHAT
## (parts in item-local metres), and multiplies. No other placement logic.
##
## ── Plan frame vs DeckGrid cells ─────────────────────────────────────────────
##
## The two frames disagreed (STATE.md): plan is corner-based metres with y in
## metres; DeckGrid is cell-index based with a half-cell centre offset in x/z
## and y in cell units above `deck_y`. THE PLAN FRAME WINS, for three reasons:
##   1. sub-metre placement is the entire point of this model, and a cell index
##      cannot carry it — the grid frame is disqualified as storage;
##   2. hosts are plan entities, so an item and its host share a frame and the
##      attach seam needs no conversion at all;
##   3. plans also describe land buildings, which have no DeckGrid.
## Grid cells stay the frame for the cell-counting compliance rules, so the
## conversion is explicit and lives here: `plan_to_local` / `local_to_plan` /
## `plan_to_cell` / `cell_base_plan` / `cell_center_plan`. Only plan→cell is
## lossy (it floors), which is what a cell-counting rule wants.
##
## A wall `axis` names the DIRECTION of the run away from `start`, never a line:
## "x" and "z" run along +X and +Z, and each diagonal spells its signed step, so
## "+x-z" leaves `start` heading toward +X and -Z at 45°. `length` is measured
## ALONG the run in every case, so a diagonal covers length / sqrt(2) metres on
## each axis; `thickness` stays perpendicular to the run (centred on it) and
## `height` stays vertical. All four diagonals exist — two would cover the same
## two lines — so a perimeter can be traced run after run without back-solving a
## start corner for the ones that head toward -X or -Z.
##
## On a vessel the bow is -Z and port is -X. Every hull in the catalogue tapers
## at exactly 45° (bow_taper_m == beam_m * 0.5, and CatalogHullVessel.make_grid()
## hardcodes the same rule), so from the bow shoulder "+x-z" follows the port
## stem and "-x-z" the starboard stem, on every hull.

const FORMAT := "structure_plan_v1"
const DEFAULT_WALL_THICKNESS := 1.0 / 6.0
const DEFAULT_PLATE_THICKNESS := 0.15
## One storey: the default height of a drawn wall and the default rise of a stair.
const DEFAULT_WALL_HEIGHT := 3.0

const WALL_AXES := ["x", "z"]
const WALL_DIAGONAL_AXES := ["+x+z", "+x-z", "-x+z", "-x-z"]

const OPENING_DOOR := "door"
const OPENING_WINDOW := "window"
const OPENING_HOLE := "hole"
const OPENING_STAIRWELL := "stairwell"

## Item placement model.
const ITEM_HOST_MAX_DEPTH := 8
const ITEM_ANCHOR_START := "start"
const ITEM_ANCHOR_CENTER := "center"
const ITEM_ANCHOR_END := "end"
const ITEM_ANCHORS := [ITEM_ANCHOR_START, ITEM_ANCHOR_CENTER, ITEM_ANCHOR_END]
## Default face per host kind — the one a builder means when they say nothing.
const ITEM_FACES := {
	"wall": ["front", "back"],
	"deck": ["top", "bottom"],
	"stair": ["run"],
	"edge": ["cap", "side"],
	"item": [""],
	## A piece has one frame and it is the grid node it stands on, turned by its
	## facing. It is listed so that hosting a fitting on a piece resolves rather
	## than indexing an empty face list — see `_face_frame`.
	"piece": [""],
}

## Facings a placement may carry. Restated from `PieceKit.FACINGS` so the
## document object can normalise a placement without loading the kit; the two
## are held together by `piece_plan_roundtrip_test`.
const PIECE_FACINGS := [0, 90, 180, 270]

## Edge primitives, by the name `PartCatalog.PRIMITIVES` already gives them.
const EDGE_SHEER_BAND := "sheer_band"
const EDGE_RAILING := "railing"
const EDGE_PRIMITIVES := [EDGE_SHEER_BAND, EDGE_RAILING]

## The plan's y = 0 plane, in metres above `HullStations.deck_y`.
##
## NOT a new number and not a choice made here: it is the same 0.12 every vessel
## script passes to `DeckGrid.from_hull(LOA_M, BEAM_M, DEPTH_M + 0.12, …)`, and
## `hull_stations.gd`'s own sheer note names it — "the build plane
## `DeckGrid.deck_y` = deck_y + 0.12, and every StructurePlan wall, plate strip
## and box collider sits on it". It is written down here because a `from_hull`
## edge is the first plan entity whose geometry arrives in SHIP-LOCAL metres and
## has to be brought into the plan frame; `hull_grid()` is that conversion.
##
## A restated constant is worth exactly what checks it: `vessel_render_capture`
## asserts `hull_grid()` against the DeckGrid the game actually builds for the
## hull, so a vessel script that moved its build plane fails there rather than
## silently floating every bulwark.
const BUILD_PLANE_M := 0.12

## Sea water, matching HullPhysicsProfile's own default. Sheer is a function of
## freeboard and form, so this never touches the curve — it only keeps
## `HullStations.from_form` on the same footing as the vessel scripts.
const WATER_DENSITY := 1025.0

var context := "vessel" ## "vessel" | "building"
var hull_id := ""
## Optional restatement of the hull's catalog numbers, for hulls that are NOT in
## `HullCatalog` (the two hand-authored ones live in vessel scripts whose
## dependency chain reaches autoload identifiers — CONVENTIONS §2 — so the
## `--script` lane cannot name them). Keys mirror the catalog: loa_m, beam_m,
## depth_m, draft_m, displacement_t, form, bow_taper_m | bow_taper_fraction,
## station_count. Held against the real hull by `vessel_render_capture`.
var hull: Dictionary = {}
var walls: Array = []
var decks: Array = []
var stairs: Array = []
var items: Array = []
var edges: Array = []
## Piece-kit placements. See the header and `add_piece`.
var pieces: Array = []
var palette: Dictionary = {}
var _next_id := 1
## Derived per hull id, memoised per plan. Both are pure functions of the hull's
## catalog numbers, so caching them changes no result — it stops a fixture with
## four edges lofting the same hull four times.
var _stations_cache: Dictionary = {}
var _grid_cache: Dictionary = {}


static func is_plan(data: Dictionary) -> bool:
	return str(data.get("format", "")) == FORMAT


func allocate_id() -> int:
	var id := _next_id
	_next_id += 1
	return id


## Unit run direction for a wall axis. Unknown names are a mis-authored plan and
## say so — silently baking them along +X is how a bulwark ends up somewhere
## nobody drew it.
static func wall_run(axis: String) -> Vector3:
	match axis:
		"x":
			return Vector3(1, 0, 0)
		"z":
			return Vector3(0, 0, 1)
		"+x+z":
			return Vector3(1, 0, 1).normalized()
		"+x-z":
			return Vector3(1, 0, -1).normalized()
		"-x+z":
			return Vector3(-1, 0, 1).normalized()
		"-x-z":
			return Vector3(-1, 0, -1).normalized()
	push_error(
		"StructurePlan: unknown wall axis \"%s\" — expected one of %s"
		% [axis, WALL_AXES + WALL_DIAGONAL_AXES]
	)
	return Vector3(1, 0, 0)


static func is_diagonal_axis(axis: String) -> bool:
	return WALL_DIAGONAL_AXES.has(axis)


func add_wall(start: Vector3, axis: String, length: float, height := DEFAULT_WALL_HEIGHT, thickness := DEFAULT_WALL_THICKNESS) -> Dictionary:
	var wall := {
		"id": allocate_id(),
		"start": [start.x, start.y, start.z],
		"axis": axis if (axis == "z" or is_diagonal_axis(axis)) else "x",
		"length": maxf(length, 1.0),
		"height": maxf(height, 0.5),
		"thickness": clampf(thickness, 0.05, 1.0),
		"openings": [],
	}
	walls.append(wall)
	return wall


func add_deck(origin: Vector3, size: Vector2, thickness := DEFAULT_PLATE_THICKNESS) -> Dictionary:
	var deck := {
		"id": allocate_id(),
		"origin": [origin.x, origin.y, origin.z],
		"size": [maxf(size.x, 1.0), maxf(size.y, 1.0)],
		"thickness": clampf(thickness, 0.05, 1.0),
		"openings": [],
	}
	decks.append(deck)
	return deck


func add_stair(start: Vector3, dir: String, length: float, width := 1.0, height := DEFAULT_WALL_HEIGHT) -> Dictionary:
	var stair := {
		"id": allocate_id(),
		"start": [start.x, start.y, start.z],
		"dir": dir if dir in ["+x", "-x", "+z", "-z"] else "+x",
		"length": maxf(length, 1.0),
		"width": maxf(width, 0.5),
		"height": clampf(height, 0.5, 12.0),
	}
	stairs.append(stair)
	return stair


## A placement from the structural piece kit, on a grid NODE.
##
## Nothing here validates the piece id or the parameter values: that is
## `PieceKit.resolve_placement`'s job and it is where the refusal messages live.
## This is the DOCUMENT's job — allocate an id, pin the canonical shape, keep the
## placement addressable by every other seam (`entity_by_id`, `remove_entity`,
## `entity_count`) exactly as a wall is. A placement whose parameters are wrong
## is a placement that refuses to resolve, and it still saves and loads.
func add_piece(
	piece_id: String, cell: Vector3i, facing := 0, params: Dictionary = {}, color := ""
) -> Dictionary:
	var placement := normalize_piece({
		"id": allocate_id(),
		"piece": piece_id,
		"cell": [cell.x, cell.y, cell.z],
		"facing": facing,
		"params": params,
		"color": color,
	})
	pieces.append(placement)
	return placement


## Canonical placement dictionary, and the fixed point of the JSON round-trip.
##
## Three things a raw JSON read gets wrong and this pins:
##   • integers come back as floats, so a cell reads [5.0, 0.0, 35.0] and
##     re-serialises with the ".0" — the same defect `from_dict` already fixes for
##     entity ids, one level deeper;
##   • numeric parameters are GRID COUNTS, never floats. A `span` of 4.0 is the
##     same defect and it is what a stepper would write back after one save;
##   • parameter key order is the author's, so two documents describing the same
##     placement compare unequal. Sorted here, which is canonical without this
##     file having to know what any parameter MEANS.
## `color` and `_is` are carried only when they say something, so the shape stays
## a pure function of the values.
static func normalize_piece(raw: Dictionary) -> Dictionary:
	var cell := raw.get("cell", []) as Array if raw.get("cell") is Array else []
	var facing := int(round(float(raw.get("facing", 0))))
	var out := {
		"id": int(raw.get("id", 0)),
		"piece": str(raw.get("piece", "")),
		"cell": [
			int(round(float(cell[0]))) if cell.size() > 0 else 0,
			int(round(float(cell[1]))) if cell.size() > 1 else 0,
			int(round(float(cell[2]))) if cell.size() > 2 else 0,
		],
		"facing": facing,
	}
	var params := raw.get("params", {}) as Dictionary if raw.get("params") is Dictionary else {}
	var keys := PackedStringArray()
	for key in params.keys():
		keys.append(str(key))
	keys.sort()
	var canonical: Dictionary = {}
	for key in keys:
		var value: Variant = params[key]
		if value is bool:
			## Not a unit the kit has. Dropped loudly rather than silently coerced.
			push_error("StructurePlan: piece parameter \"%s\" is a bool — dropped" % key)
			continue
		if value is int or value is float:
			canonical[key] = int(round(float(value)))
		else:
			canonical[key] = str(value)
	out["params"] = canonical
	var color := str(raw.get("color", "")).strip_edges()
	if not color.is_empty():
		out["color"] = color
	var note := str(raw.get("_is", "")).strip_edges()
	if not note.is_empty():
		out["_is"] = note
	return out


static func normalize_pieces(raw_pieces: Array) -> Array:
	var out: Array = []
	for raw in raw_pieces:
		if raw is Dictionary:
			out.append(normalize_piece(raw as Dictionary))
	return out


## Plan-space metres of the grid NODE a placement stands on.
##
## Deliberately NOT `cell_base_plan`, which returns a cell CENTRE: cells are
## volumes and pieces stand on the LINES between them, so a centre would put
## every wall panel half a cell out. It is the same arithmetic as
## `PieceKit.node_plan` and it is restated here — rather than called — so this
## file keeps no dependency on the kit, and `piece_plan_roundtrip_test` holds the
## two against each other on every node a fixture uses.
static func piece_node_plan(cell: Vector3i) -> Vector3:
	var m := WorldUnits.DECK_CELL_M
	return Vector3(float(cell.x) * m, float(cell.y) * m, float(cell.z) * m)


static func piece_cell(placement: Dictionary) -> Vector3i:
	var raw: Variant = placement.get("cell", null)
	if not (raw is Array) or (raw as Array).size() != 3:
		return Vector3i.ZERO
	var list := raw as Array
	return Vector3i(
		int(round(float(list[0]))), int(round(float(list[1]))), int(round(float(list[2])))
	)


## A swept run along an explicit polyline, in PLAN metres. `spec` is passed
## through to `StructureEdge` untouched — profile, width/thickness, base_y,
## closed, colour, material, solid — because the edge dict IS the sweep spec.
func add_edge(path: Array, spec: Dictionary = {}, primitive := EDGE_SHEER_BAND) -> Dictionary:
	var edge := spec.duplicate(true)
	edge["id"] = allocate_id()
	edge["primitive"] = primitive if EDGE_PRIMITIVES.has(primitive) else EDGE_SHEER_BAND
	edge["path"] = path.duplicate(true)
	edges.append(edge)
	return edge


## A sheered bulwark on this plan's hull. The curve is not written down: `opts`
## carries the section and the amidships cap height, and everything that differs
## between one hull and the next is derived — see `edge_spec`.
func add_hull_edge(opts: Dictionary = {}, from_hull := "") -> Dictionary:
	var edge := opts.duplicate(true)
	edge["id"] = allocate_id()
	edge["primitive"] = EDGE_SHEER_BAND
	edge["from_hull"] = from_hull if not from_hull.is_empty() else hull_id
	edges.append(edge)
	return edge


static func edge_primitive(edge: Dictionary) -> String:
	var primitive := str(edge.get("primitive", EDGE_SHEER_BAND))
	if EDGE_PRIMITIVES.has(primitive):
		return primitive
	push_error(
		"StructurePlan: unknown edge primitive \"%s\" — expected one of %s"
		% [primitive, EDGE_PRIMITIVES]
	)
	return EDGE_SHEER_BAND


## The `StructureEdge` sweep spec one `edges[]` entry resolves to, in PLAN
## metres.
##
## An edge that writes its own `path` IS its spec and is returned unchanged. An
## edge that says `from_hull` is resolved through
## `StructureEdge.sheer_bulwark_spec` against this hull's `HullStations` — the
## whole point of the key, and the reason a fixture can ask for "a sheered
## bulwark on this hull" without holding a copy of a curve it cannot keep in
## sync.
##
## The resolved spec comes back in SHIP-LOCAL metres, because that is the frame
## `HullStations` speaks. It is translated into the plan frame here, once, so an
## edge composes with the walls, plates and hosted items around it. The
## translation is `local_to_plan` — the conversion this file has always owned —
## and it is a pure translation, so no point is approximated by it.
func edge_spec(edge: Dictionary) -> Dictionary:
	if not edge.has("from_hull"):
		return edge
	var id := str(edge["from_hull"]).strip_edges()
	if id.is_empty() or id == "true":
		id = hull_id
	var stations := hull_stations(id)
	if stations == null:
		return {}
	var spec := StructureEdge.sheer_bulwark_spec(stations, edge)
	if spec.is_empty():
		return {}
	var grid := hull_grid(id)
	if grid == null:
		return {}
	var path := PackedVector3Array()
	for point in (spec["path"] as PackedVector3Array):
		path.append(local_to_plan(point, grid))
	spec["path"] = path
	spec["base_y"] = float(spec.get("base_y", stations.deck_y)) - grid.deck_y
	return spec


## `HullStations` for a hull id, without naming a vessel script.
##
## Two sources, in order, and neither of them is a per-hull table:
##   1. the plan's own `hull` block, for the two hand-authored hulls that live in
##      BoatBody subclasses — see `hull`;
##   2. `HullCatalog`, which is where every data-driven hull already is.
## Both feed `HullStations.from_form`, which is the same call
## `HullPhysicsProfile.make_stations()` makes, so the sheer that comes out is
## the sheer the game builds rather than a second derivation of it.
func hull_stations(id := "") -> HullStations:
	var key := id if not id.is_empty() else hull_id
	if _stations_cache.has(key):
		return _stations_cache[key] as HullStations
	var built := make_hull_stations(key, hull if key == hull_id else {})
	_stations_cache[key] = built
	return built


## The `DeckGrid` a hull's vessel script builds — `DeckGrid.from_hull` over the
## same three numbers, with the build plane at `stations.deck_y + BUILD_PLANE_M`.
## This is the plan frame's definition, so it is what `plan_to_local` /
## `local_to_plan` are fed when a plan has no grid handed to it.
##
## Only three fields of it are load-bearing here and only those three are
## checked: `half_beam`, `half_loa` and `deck_y` are the whole of the frame
## conversion. `bow_taper_cells` is passed the catalogue's universal 45° rule
## (taper = half the beam — CONVENTIONS §3a) and is not used by any conversion,
## so do not read this grid for cell shapes; ask the vessel for that one.
func hull_grid(id := "") -> DeckGrid:
	var key := id if not id.is_empty() else hull_id
	if _grid_cache.has(key):
		return _grid_cache[key] as DeckGrid
	var stations := hull_stations(key)
	var built: DeckGrid = null
	if stations != null:
		built = DeckGrid.from_hull(
			stations.length_m,
			stations.beam_m,
			stations.deck_y + BUILD_PLANE_M,
			stations.beam_m * 0.5,
		)
	_grid_cache[key] = built
	return built


static func make_hull_stations(id: String, restated: Dictionary = {}) -> HullStations:
	var cfg := restated
	if cfg.is_empty() and HullCatalog.has_id(id):
		cfg = HullCatalog.get_by_id(id)
	if cfg.is_empty():
		push_error(
			"StructurePlan: no hull numbers for \"%s\" — it is not in HullCatalog "
			% id
			+ "and the plan carries no `hull` block to loft it from"
		)
		return null
	var loa := float(cfg.get("loa_m", 0.0))
	var beam := float(cfg.get("beam_m", 0.0))
	var depth := float(cfg.get("depth_m", 0.0))
	if loa <= 0.0 or beam <= 0.0 or depth <= 0.0:
		push_error("StructurePlan: hull \"%s\" has no positive loa/beam/depth" % id)
		return null
	var draft := float(cfg.get("draft_m", depth * 0.5))
	## Displacement sets the underwater widths and has no bearing on sheer, which
	## is a function of freeboard and form alone. The catalog omits it, so
	## CatalogHullVessel's own fallback is used rather than inventing a hull.
	var displacement := float(cfg.get("displacement_t", loa * beam * draft * 0.52))
	var form := HullFormProfile.resolve(str(cfg.get("form", HullFormProfile.DEFAULT_ID)))
	## Every hull in the catalogue tapers at exactly 45° in plan, so the taper is
	## half the beam unless the entry says otherwise.
	var taper := beam * 0.5
	if cfg.has("bow_taper_m"):
		taper = float(cfg["bow_taper_m"])
	elif cfg.has("bow_taper_fraction"):
		taper = loa * float(cfg["bow_taper_fraction"])
	var count := clampi(int(round(loa / 8.0)), 8, 16)
	if cfg.has("station_count"):
		count = int(cfg["station_count"])
	return HullStations.from_form(
		loa, beam, depth, draft, displacement, form, WATER_DENSITY, taper, count
	)


## Free-floating fitting at a float position in PLAN metres.
func add_item(item_id: String, at: Vector3, yaw := 0.0, props: Dictionary = {}) -> Dictionary:
	var item := normalize_item({
		"id": allocate_id(),
		"item_id": item_id,
		"at": [at.x, at.y, at.z],
		"yaw": yaw,
		"props": props,
	})
	items.append(item)
	return item


## Fitting attached to another plan entity. `offset` is in the host's attach
## frame: +x along the host run from `anchor`, +y up, +z out of `face`. Moving
## the host moves this fitting — that is the whole point of hosting.
func add_hosted_item(
	item_id: String,
	host_id: int,
	offset: Vector3,
	yaw := 0.0,
	face := "",
	anchor := ITEM_ANCHOR_START,
	props: Dictionary = {},
) -> Dictionary:
	var item := normalize_item({
		"id": allocate_id(),
		"item_id": item_id,
		"at": [offset.x, offset.y, offset.z],
		"yaw": yaw,
		"host": {"id": host_id, "face": face, "anchor": anchor},
		"props": props,
	})
	items.append(item)
	return item


## Cell-addressed convenience for callers that still think in grid cells (the
## old `add_item` signature). It resolves to the cell's BASE CENTRE in plan
## metres and stores a float position — the cell is an input, never storage.
func add_item_at_cell(item_id: String, cell: Vector3i, yaw := 0.0) -> Dictionary:
	return add_item(item_id, cell_base_plan(cell), yaw)


## Writes yaw/pitch/roll in degrees, dropping the zero axes so a plain fitting
## never carries keys it does not use.
static func set_item_rotation(item: Dictionary, yaw: float, pitch := 0.0, roll := 0.0) -> void:
	item["yaw"] = _f(yaw)
	item.erase("pitch")
	item.erase("roll")
	if not is_zero_approx(pitch):
		item["pitch"] = _f(pitch)
	if not is_zero_approx(roll):
		item["roll"] = _f(roll)


static func item_at(item: Dictionary) -> Vector3:
	return vec3_of(item.get("at"))


static func item_props(item: Dictionary) -> Dictionary:
	return (item.get("props", {}) as Dictionary)


static func item_prop(item: Dictionary, key: String, fallback: Variant) -> Variant:
	return item_props(item).get(key, fallback)


static func item_host_id(item: Dictionary) -> int:
	if not (item.get("host") is Dictionary):
		return -1
	return int((item["host"] as Dictionary).get("id", -1))


## The one rotation order in the codebase: yaw (Y), then pitch (X), then roll
## (Z). Degrees in the dict, radians in the basis.
static func item_basis(item: Dictionary) -> Basis:
	return Basis.from_euler(
		Vector3(
			deg_to_rad(_f(item.get("pitch", 0.0))),
			deg_to_rad(_f(item.get("yaw", 0.0))),
			deg_to_rad(_f(item.get("roll", 0.0))),
		),
		EULER_ORDER_YXZ
	)


## Resolves an item (and its whole host chain) to a transform in PLAN space.
func item_transform(item: Dictionary) -> Transform3D:
	return _item_transform(item, {}, 0)


func _item_transform(item: Dictionary, seen: Dictionary, depth: int) -> Transform3D:
	var local := Transform3D(item_basis(item), item_at(item))
	var host_id := item_host_id(item)
	if host_id < 0:
		return local
	if depth >= ITEM_HOST_MAX_DEPTH:
		push_error(
			"StructurePlan: item %d host chain deeper than %d — placing unhosted"
			% [int(item.get("id", -1)), ITEM_HOST_MAX_DEPTH]
		)
		return local
	if seen.has(host_id):
		push_error(
			"StructurePlan: item %d host cycle through entity %d — placing unhosted"
			% [int(item.get("id", -1)), host_id]
		)
		return local
	seen[host_id] = true
	var host := item["host"] as Dictionary
	var frame := _host_frame(
		host_id, str(host.get("face", "")), str(host.get("anchor", ITEM_ANCHOR_START)), seen, depth
	)
	return frame * local


## Attach frame of a host entity, in plan space. Right-handed, +z out of the
## face, origin at `anchor` along the host's run.
func _host_frame(
	host_id: int, face: String, anchor: String, seen: Dictionary, depth: int
) -> Transform3D:
	var kind := entity_kind_by_id(host_id)
	var entity := entity_by_id(host_id)
	if kind.is_empty():
		push_error("StructurePlan: item host %d not found in plan" % host_id)
		return Transform3D.IDENTITY
	if kind == "item":
		return _item_transform(entity, seen, depth + 1)
	## An edge's run is a polyline, so its anchor slides along ARC LENGTH and its
	## frame is taken where it lands. Sliding a straight `basis.x` out of the
	## start point — what every other host does, correctly, because every other
	## host IS straight — would put the "end" anchor of a closed bulwark loop
	## 70 m off the bow.
	if kind == "edge":
		return _edge_frame(entity, face, anchor)
	var frame := _face_frame(kind, entity, face)
	var basis := frame["basis"] as Basis
	var origin := frame["origin"] as Vector3
	var span := float(frame["span"])
	var slide := 0.0
	match anchor:
		ITEM_ANCHOR_CENTER:
			slide = span * 0.5
		ITEM_ANCHOR_END:
			slide = span
		ITEM_ANCHOR_START:
			slide = 0.0
		_:
			push_error(
				"StructurePlan: unknown item anchor \"%s\" — expected one of %s"
				% [anchor, ITEM_ANCHORS]
			)
	return Transform3D(basis, origin + basis.x * slide)


## Per-kind face table. `span` is the run length along the frame's local +x, so
## the "end" anchor lands on the far end of whatever the host actually is.
func _face_frame(kind: String, entity: Dictionary, face: String) -> Dictionary:
	var allowed: Array = ITEM_FACES.get(kind, []) as Array
	var picked := face
	if picked.is_empty():
		picked = str(allowed[0])
	elif not allowed.has(picked):
		push_error(
			"StructurePlan: %s host has no face \"%s\" — expected one of %s"
			% [kind, face, allowed]
		)
		picked = str(allowed[0])
	match kind:
		"wall":
			var start := vec3_of(entity.get("start"))
			var run := wall_run(str(entity.get("axis", "x")))
			var length := float(entity.get("length", 1.0))
			var out := run.cross(Vector3.UP)
			if picked == "back":
				return {
					"basis": _frame_basis(-run, Vector3.UP, -out),
					"origin": start + run * length,
					"span": length,
				}
			return {"basis": _frame_basis(run, Vector3.UP, out), "origin": start, "span": length}
		"deck":
			var origin := vec3_of(entity.get("origin"))
			var size := entity.get("size", [1.0, 1.0]) as Array
			var w := float(size[0]) if size.size() > 0 else 1.0
			var thickness := float(entity.get("thickness", DEFAULT_PLATE_THICKNESS))
			if picked == "bottom":
				return {
					"basis": _frame_basis(Vector3.RIGHT, Vector3.DOWN, Vector3.BACK),
					"origin": origin - Vector3(0.0, thickness, 0.0),
					"span": w,
				}
			return {
				"basis": _frame_basis(Vector3.RIGHT, Vector3.UP, Vector3.BACK),
				"origin": origin,
				"span": w,
			}
		"stair":
			var start_s := vec3_of(entity.get("start"))
			var dir := stair_run(str(entity.get("dir", "+x")))
			var length_s := float(entity.get("length", 1.0))
			return {
				"basis": _frame_basis(dir, Vector3.UP, dir.cross(Vector3.UP)),
				"origin": start_s,
				"span": length_s,
			}
		"piece":
			## The piece-local frame, verbatim: +x along the run, +y up, the outward
			## face toward -z, turned by `facing`. `span` is 0 because the run length
			## is a KIT parameter and this file holds no kit knowledge, so every
			## anchor lands on the node — honest rather than approximately right.
			var yaw := deg_to_rad(float(int(round(float(entity.get("facing", 0))))))
			return {
				"basis": Basis(Vector3.UP, yaw),
				"origin": piece_node_plan(piece_cell(entity)),
				"span": 0.0,
			}
	return {"basis": Basis.IDENTITY, "origin": Vector3.ZERO, "span": 0.0}


## Attach frame on a swept run. Right-handed and built exactly as a wall's is —
## +x along the run, +y up, +z = run x UP — so a fitting authored against a
## bulwark reads the same way as one authored against a wall.
##
## "cap" lifts the origin to the TOP of the swept section, so `at` on a cap is
## measured from the surface a cleat is bolted to rather than from the path line
## buried inside the plating. The lift is read off the profile the run is
## actually drawn with, so a cap rail, a top rail and a bare band each put it
## where their own geometry ends.
func _edge_frame(edge: Dictionary, face: String, anchor: String) -> Transform3D:
	var allowed: Array = ITEM_FACES["edge"] as Array
	var picked := face
	if picked.is_empty():
		picked = str(allowed[0])
	elif not allowed.has(picked):
		push_error(
			"StructurePlan: edge host has no face \"%s\" — expected one of %s"
			% [face, allowed]
		)
		picked = str(allowed[0])
	var spec := edge_spec(edge)
	var points := _path_points(spec)
	if points.size() < 2:
		push_error("StructurePlan: edge %d has no run to host on" % int(edge.get("id", -1)))
		return Transform3D.IDENTITY
	if bool(spec.get("closed", false)):
		points.append(points[0])
	var span := 0.0
	for i in range(points.size() - 1):
		span += points[i].distance_to(points[i + 1])
	var slide := 0.0
	match anchor:
		ITEM_ANCHOR_CENTER:
			slide = span * 0.5
		ITEM_ANCHOR_END:
			slide = span
		ITEM_ANCHOR_START:
			slide = 0.0
		_:
			push_error(
				"StructurePlan: unknown item anchor \"%s\" — expected one of %s"
				% [anchor, ITEM_ANCHORS]
			)
	var walked := 0.0
	var origin: Vector3 = points[0]
	var tangent: Vector3 = points[1] - points[0]
	for i in range(points.size() - 1):
		var a: Vector3 = points[i]
		var b: Vector3 = points[i + 1]
		var step := a.distance_to(b)
		if step <= 0.0:
			continue
		tangent = b - a
		origin = a
		if walked + step >= slide or i == points.size() - 2:
			origin = a.lerp(b, clampf((slide - walked) / step, 0.0, 1.0))
			break
		walked += step
	if picked == "cap":
		origin += Vector3(0.0, _section_top(edge, spec), 0.0)
	## A stanchion is plumb and so is an attach frame: the run's HEADING is what
	## the fitting follows, never its slope. A cleat on a sheered cap sits square
	## to the deck, not raked back by the 7° the cap is climbing at the stem.
	var run := Vector3(tangent.x, 0.0, tangent.z)
	if run.length_squared() < 1e-12:
		run = Vector3(1, 0, 0)
	run = run.normalized()
	return Transform3D(_frame_basis(run, Vector3.UP, run.cross(Vector3.UP)), origin)


## How far above the path the swept section reaches — the cap's top face on a
## bulwark, the top rail on a railing. Zero when the profile cannot be resolved,
## which puts the frame on the path line rather than guessing.
func _section_top(edge: Dictionary, spec: Dictionary) -> float:
	var profile: Array = []
	if edge_primitive(edge) == EDGE_RAILING:
		profile = StructureEdge.railing_profile(spec)
	elif spec.has("profile") or (spec.has("width") and spec.has("thickness")):
		profile = StructureEdge.resolve_profile(spec)
	var top := 0.0
	for rect_variant in profile:
		var rect := rect_variant as Dictionary
		var v := float(rect.get("v", 0.0))
		## A `to_base` rect hangs DOWN from the path to `base_y`; its `h` is the
		## path's own height and says nothing about how far above the line it
		## reaches, which is `v` and only `v`.
		if bool(rect.get("to_base", false)):
			top = maxf(top, v)
			continue
		top = maxf(top, v + float(rect.get("h", 0.0)) * 0.5)
	return top


## An edge's path, however it was written: a resolved `PackedVector3Array` from
## `sheer_bulwark_spec`, or the `[[x,y,z], …]` an authored edge carries in JSON.
static func _path_points(spec: Dictionary) -> PackedVector3Array:
	var raw: Variant = spec.get("path", [])
	if raw is PackedVector3Array:
		return raw as PackedVector3Array
	var out := PackedVector3Array()
	if raw is Array:
		for entry in (raw as Array):
			out.append(entry if entry is Vector3 else vec3_of(entry))
	return out


static func _frame_basis(x_axis: Vector3, y_axis: Vector3, z_axis: Vector3) -> Basis:
	return Basis(x_axis.normalized(), y_axis.normalized(), z_axis.normalized())


## Unit climb direction for a stair `dir`, mirroring wall_run's contract.
static func stair_run(dir: String) -> Vector3:
	match dir:
		"+x":
			return Vector3(1, 0, 0)
		"-x":
			return Vector3(-1, 0, 0)
		"+z":
			return Vector3(0, 0, 1)
		"-z":
			return Vector3(0, 0, -1)
	push_error("StructurePlan: unknown stair dir \"%s\"" % dir)
	return Vector3(1, 0, 0)


## ── Item schema normalisation and migration ─────────────────────────────────
##
## `normalize_item` is the single writer of item shape. It is IDEMPOTENT — the
## fixed point is what `to_dict` emits and what survives JSON — and it is where
## the legacy `cell:[ix,iy,iz]` form is migrated.


## True for the pre-float item form: an integer cell and no float position.
static func is_legacy_item(raw: Dictionary) -> bool:
	return raw.has("cell") and not raw.has("at")


## Canonical item dictionary. Key order is fixed; pitch/roll/host/props are
## present iff they carry information, which keeps the shape a pure function of
## the values and so keeps to_dict/from_dict byte-stable.
static func normalize_item(raw: Dictionary) -> Dictionary:
	var at := Vector3.ZERO
	if is_legacy_item(raw):
		## MIGRATION. A cell-addressed fitting stood on the deck at the middle
		## of its cell, so it migrates to the cell's BASE CENTRE: half a cell in
		## x/z (corner -> centre) and cell units -> metres in y. That is exactly
		## the plan/DeckGrid discrepancy STATE.md recorded, paid once, here.
		var cell := raw.get("cell", []) as Array
		at = cell_base_plan(
			Vector3i(
				int(cell[0]) if cell.size() > 0 else 0,
				int(cell[1]) if cell.size() > 1 else 0,
				int(cell[2]) if cell.size() > 2 else 0,
			)
		)
	else:
		at = vec3_of(raw.get("at"))
	var item := {
		"id": int(raw.get("id", 0)),
		"item_id": str(raw.get("item_id", "")),
		"at": [_f(at.x), _f(at.y), _f(at.z)],
		"yaw": _f(raw.get("yaw", 0.0)),
	}
	var pitch := _f(raw.get("pitch", 0.0))
	if not is_zero_approx(pitch):
		item["pitch"] = pitch
	var roll := _f(raw.get("roll", 0.0))
	if not is_zero_approx(roll):
		item["roll"] = roll
	if raw.get("host") is Dictionary:
		var raw_host := raw["host"] as Dictionary
		var host_id := int(raw_host.get("id", -1))
		if host_id >= 0:
			var host := {"id": host_id}
			var face := str(raw_host.get("face", ""))
			if not face.is_empty():
				host["face"] = face
			var anchor := str(raw_host.get("anchor", ITEM_ANCHOR_START))
			if anchor != ITEM_ANCHOR_START:
				host["anchor"] = anchor
			item["host"] = host
	if raw.get("props") is Dictionary:
		var props := _canonical_props(raw["props"] as Dictionary)
		if not props.is_empty():
			item["props"] = props
	return item


static func normalize_items(raw_items: Array) -> Array:
	var out: Array = []
	for raw in raw_items:
		if raw is Dictionary:
			out.append(normalize_item(raw as Dictionary))
	return out


## Props are a JSON bag. Integers are canonicalised to floats because that is
## what a JSON round-trip returns anyway — canonicalising on write makes the
## first save the fixed point instead of the second. Non-JSON values are an
## authoring bug and are dropped loudly rather than silently corrupted.
static func _canonical_props(props: Dictionary) -> Dictionary:
	var out := {}
	for key in props:
		var value: Variant = _canonical_value(props[key], str(key))
		if value != null or props[key] == null:
			out[str(key)] = value
	return out


static func _canonical_value(value: Variant, key: String) -> Variant:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_STRING, TYPE_STRING_NAME:
			return str(value) if typeof(value) == TYPE_STRING_NAME else value
		TYPE_INT, TYPE_FLOAT:
			return _f(value)
		TYPE_ARRAY:
			var list: Array = []
			for entry in (value as Array):
				list.append(_canonical_value(entry, key))
			return list
		TYPE_DICTIONARY:
			return _canonical_props(value as Dictionary)
	push_error(
		"StructurePlan: item prop \"%s\" is not JSON data (type %d) — dropped"
		% [key, typeof(value)]
	)
	return null


## Non-finite floats would make a plan unloadable; a fitting at NaN is a bug
## upstream and zero is the only value that still round-trips.
static func _f(value: Variant) -> float:
	var number := float(value)
	return number if is_finite(number) else 0.0


## ── Plan frame <-> DeckGrid frame ───────────────────────────────────────────
##
## Plan space is corner-based metres from the grid's (0,0) corner, y in metres
## above the deck plane. DeckGrid local space is vessel-centred metres with the
## deck plane at `deck_y`. Only plan->cell loses information (it floors).


static func plan_to_local(point: Vector3, grid: DeckGrid) -> Vector3:
	return Vector3(
		point.x - grid.half_beam,
		grid.deck_y + point.y,
		point.z - grid.half_loa,
	)


static func local_to_plan(local: Vector3, grid: DeckGrid) -> Vector3:
	return Vector3(
		local.x + grid.half_beam,
		local.y - grid.deck_y,
		local.z + grid.half_loa,
	)


## Cell containing a plan point. Matches DeckGrid.local_to_cell by construction,
## including its clamp of iy at 0.
static func plan_to_cell(point: Vector3, grid: DeckGrid) -> Vector3i:
	return grid.local_to_cell(plan_to_local(point, grid))


## Bottom-centre of a cell, in plan metres: half a cell inboard in x/z, cell
## units scaled to metres in y. Grid-free — a cell address means the same thing
## on every hull.
static func cell_base_plan(cell: Vector3i) -> Vector3:
	var m := WorldUnits.DECK_CELL_M
	return Vector3((float(cell.x) + 0.5) * m, float(cell.y) * m, (float(cell.z) + 0.5) * m)


## Centre of a cell, in plan metres.
static func cell_center_plan(cell: Vector3i) -> Vector3:
	return cell_base_plan(cell) + Vector3(0.0, WorldUnits.DECK_CELL_M * 0.5, 0.0)


## The four drawn collections plus items, in the order every lookup walks them.
## One list, so adding a primitive cannot be half-done: an edge that counted but
## could not be found by id, or could be found but not removed, is exactly the
## sort of gap that only shows up in an editor a wave later.
func _collections() -> Array:
	return [walls, decks, stairs, edges, items, pieces]


const ENTITY_KINDS := ["wall", "deck", "stair", "edge", "item", "piece"]


func entity_kind_by_id(id: int) -> String:
	var collections := _collections()
	for index in collections.size():
		for entity in (collections[index] as Array):
			if int((entity as Dictionary).get("id", -1)) == id:
				return str(ENTITY_KINDS[index])
	return ""


func entity_by_id(id: int) -> Dictionary:
	for collection in _collections():
		for entity in collection:
			if int((entity as Dictionary).get("id", -1)) == id:
				return entity
	return {}


func remove_entity(id: int) -> bool:
	for collection in _collections():
		for index in (collection as Array).size():
			if int(((collection as Array)[index] as Dictionary).get("id", -1)) == id:
				(collection as Array).remove_at(index)
				return true
	return false


func is_empty() -> bool:
	for collection in _collections():
		if not (collection as Array).is_empty():
			return false
	return true


func entity_count() -> int:
	var total := 0
	for collection in _collections():
		total += (collection as Array).size()
	return total


func to_dict() -> Dictionary:
	return {
		"format": FORMAT,
		"context": context,
		"hull_id": hull_id,
		"hull": hull.duplicate(true),
		"palette": palette.duplicate(true),
		"walls": walls.duplicate(true),
		"decks": decks.duplicate(true),
		"stairs": stairs.duplicate(true),
		"edges": edges.duplicate(true),
		## Placements are re-normalised for the same reason items are, and they go
		## out BEFORE items because that is the order the shipped piece fixtures
		## are written in — a key order that moves makes two saves of one plan
		## diff for no reason.
		"pieces": normalize_pieces(pieces),
		## Items are re-normalised on the way out so an editor that pokes a raw
		## dictionary cannot break the round-trip's fixed point.
		"items": normalize_items(items),
	}


static func from_dict(data: Dictionary) -> StructurePlan:
	var plan := StructurePlan.new()
	plan.context = str(data.get("context", "vessel"))
	plan.hull_id = str(data.get("hull_id", ""))
	plan.hull = (data.get("hull", {}) as Dictionary).duplicate(true)
	plan.palette = (data.get("palette", {}) as Dictionary).duplicate(true)
	plan.walls = (data.get("walls", []) as Array).duplicate(true)
	plan.decks = (data.get("decks", []) as Array).duplicate(true)
	plan.stairs = (data.get("stairs", []) as Array).duplicate(true)
	plan.edges = (data.get("edges", []) as Array).duplicate(true)
	## Migrates the legacy cell form and pins the canonical shape.
	plan.items = normalize_items(data.get("items", []) as Array)
	plan.pieces = normalize_pieces(data.get("pieces", []) as Array)
	var highest := 0
	for collection in [plan.walls, plan.decks, plan.stairs, plan.edges, plan.items, plan.pieces]:
		for entity in collection:
			var entity_dict := entity as Dictionary
			var id := int(entity_dict.get("id", 0))
			## JSON hands integers back as floats, so an id survives a save/load
			## as 4.0 and re-serialises as "4.0". Pinning it to int here is what
			## makes a whole plan byte-stable across a round-trip, not just its
			## items. Every reader already goes through int().
			if entity_dict.has("id"):
				entity_dict["id"] = id
			highest = maxi(highest, id)
	plan._next_id = highest + 1
	return plan


static func vec3_of(value: Variant, fallback := Vector3.ZERO) -> Vector3:
	if value is Array and (value as Array).size() >= 3:
		var list := value as Array
		return Vector3(float(list[0]), float(list[1]), float(list[2]))
	return fallback
