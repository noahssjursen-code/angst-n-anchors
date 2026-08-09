class_name StructurePlan
extends RefCounted

## Parametric construction document shared by vessels and land buildings.
##
## Structure is DRAWN, not stacked: five primitives, each one part regardless
## of size, replace fields of voxel bricks:
##   walls  — {id, start:[x,y,z], axis:"x"|"z"|"+x+z"|"+x-z"|"-x+z"|"-x-z",
##             length, height, thickness,
##             color?, openings:[{type, offset, width, height, sill}]}
##   decks  — {id, origin:[x,y,z], size:[w,l], thickness, color?,
##             openings:[{type, offset:[dx,dz], size:[w,l]}]}
##   rooms  — {id, origin:[x,y,z], size:[w,h,l], wall_thickness, color?,
##             open_faces?:["n"|"s"|"e"|"w"], — faces with NO wall (corridor
##                        ends, lean-tos); a corridor is a room with both
##                        ends open.
##             openings:[{face:"n"|"s"|"e"|"w"|"floor"|"ceiling", type,
##                        offset, width, height, sill}]}
##   stairs — {id, start:[x,y,z], dir:"+x"|"-x"|"+z"|"-z", length, width,
##             height, color?}  start = footprint min corner at the LOW end's
##             base level; dir = climb direction; solid stepped run whose top
##             tread lands flush on start.y + height.
##   items  — {id, item_id, at:[x,y,z], yaw, pitch?, roll?,
##             host?:{id, face?, anchor?}, props?:{...}}  (point fittings)
##
## Coordinates are grid-corner points in metres. For vessels x/z match
## DeckGrid cell corners (0..width, 0..length) and y is metres above the deck
## plane. Rooms expand into walls + floor + ceiling plates at bake time —
## see StructureBaker.expand_room().
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
## `host.id` names any wall / deck / room / stair / item in the same plan.
## `host.face` picks a surface, `host.anchor` picks where along it the origin
## sits ("start" | "center" | "end"). Every frame is right-handed with:
##   +x  along the host's run / width, from the anchor
##   +y  out of the face when the face is horizontal (deck top, room floor),
##       otherwise up
##   +z  the remaining axis — which on a VERTICAL face is the outward normal,
##       so `at.z` reads as "how far off the surface"; negative is inboard,
##       e.g. a cleat 0.4 m inboard of a bulwark is at.z = -0.4
## Faces: wall "front"|"back"; deck "top"|"bottom"; room "n"|"s"|"e"|"w"|
## "floor"|"ceiling"; stair "run"; item — none, the frame IS the host item's
## resolved transform, so fittings compose (a lamp on a mast on a wheelhouse).
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
const DEFAULT_ROOM_HEIGHT := 3.0

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
	"room": ["n", "s", "e", "w", "floor", "ceiling"],
	"stair": ["run"],
	"item": [""],
}

var context := "vessel" ## "vessel" | "building"
var hull_id := ""
var walls: Array = []
var decks: Array = []
var rooms: Array = []
var stairs: Array = []
var items: Array = []
var palette: Dictionary = {}
var _next_id := 1


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


func add_wall(start: Vector3, axis: String, length: float, height := DEFAULT_ROOM_HEIGHT, thickness := DEFAULT_WALL_THICKNESS) -> Dictionary:
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


func add_room(origin: Vector3, size: Vector3) -> Dictionary:
	var room := {
		"id": allocate_id(),
		"origin": [origin.x, origin.y, origin.z],
		"size": [maxf(size.x, 2.0), maxf(size.y, 2.0), maxf(size.z, 2.0)],
		"wall_thickness": DEFAULT_WALL_THICKNESS,
		"openings": [],
	}
	rooms.append(room)
	return room


func add_stair(start: Vector3, dir: String, length: float, width := 1.0, height := DEFAULT_ROOM_HEIGHT) -> Dictionary:
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
		"room":
			return _room_face_frame(entity, picked)
		"stair":
			var start_s := vec3_of(entity.get("start"))
			var dir := stair_run(str(entity.get("dir", "+x")))
			var length_s := float(entity.get("length", 1.0))
			return {
				"basis": _frame_basis(dir, Vector3.UP, dir.cross(Vector3.UP)),
				"origin": start_s,
				"span": length_s,
			}
	return {"basis": Basis.IDENTITY, "origin": Vector3.ZERO, "span": 0.0}


func _room_face_frame(room: Dictionary, face: String) -> Dictionary:
	var origin := vec3_of(room.get("origin"))
	var size := vec3_of(room.get("size"), Vector3(2, 2, 2))
	var w := size.x
	var h := size.y
	var l := size.z
	## Outward normal per face; local +x = up.cross(normal) keeps it right-handed
	## and sweeps the face from its own origin corner.
	match face:
		"n": ## -Z face
			return {
				"basis": _frame_basis(Vector3.LEFT, Vector3.UP, Vector3.FORWARD),
				"origin": origin + Vector3(w, 0.0, 0.0),
				"span": w,
			}
		"s": ## +Z face
			return {
				"basis": _frame_basis(Vector3.RIGHT, Vector3.UP, Vector3.BACK),
				"origin": origin + Vector3(0.0, 0.0, l),
				"span": w,
			}
		"w": ## -X face
			return {
				"basis": _frame_basis(Vector3.BACK, Vector3.UP, Vector3.LEFT),
				"origin": origin,
				"span": l,
			}
		"e": ## +X face
			return {
				"basis": _frame_basis(Vector3.FORWARD, Vector3.UP, Vector3.RIGHT),
				"origin": origin + Vector3(w, 0.0, l),
				"span": l,
			}
		"ceiling":
			return {
				"basis": _frame_basis(Vector3.RIGHT, Vector3.DOWN, Vector3.FORWARD),
				"origin": origin + Vector3(0.0, h, 0.0),
				"span": w,
			}
	## "floor"
	return {
		"basis": _frame_basis(Vector3.RIGHT, Vector3.UP, Vector3.BACK),
		"origin": origin,
		"span": w,
	}


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


func entity_kind_by_id(id: int) -> String:
	var kinds := ["wall", "deck", "room", "stair", "item"]
	var collections := [walls, decks, rooms, stairs, items]
	for index in collections.size():
		for entity in (collections[index] as Array):
			if int((entity as Dictionary).get("id", -1)) == id:
				return str(kinds[index])
	return ""


func entity_by_id(id: int) -> Dictionary:
	for collection in [walls, decks, rooms, stairs, items]:
		for entity in collection:
			if int((entity as Dictionary).get("id", -1)) == id:
				return entity
	return {}


func remove_entity(id: int) -> bool:
	for collection in [walls, decks, rooms, stairs, items]:
		for index in (collection as Array).size():
			if int(((collection as Array)[index] as Dictionary).get("id", -1)) == id:
				(collection as Array).remove_at(index)
				return true
	return false


func is_empty() -> bool:
	return walls.is_empty() and decks.is_empty() and rooms.is_empty() and stairs.is_empty() and items.is_empty()


func entity_count() -> int:
	return walls.size() + decks.size() + rooms.size() + stairs.size() + items.size()


func to_dict() -> Dictionary:
	return {
		"format": FORMAT,
		"context": context,
		"hull_id": hull_id,
		"palette": palette.duplicate(true),
		"walls": walls.duplicate(true),
		"decks": decks.duplicate(true),
		"rooms": rooms.duplicate(true),
		"stairs": stairs.duplicate(true),
		## Items are re-normalised on the way out so an editor that pokes a raw
		## dictionary cannot break the round-trip's fixed point.
		"items": normalize_items(items),
	}


static func from_dict(data: Dictionary) -> StructurePlan:
	var plan := StructurePlan.new()
	plan.context = str(data.get("context", "vessel"))
	plan.hull_id = str(data.get("hull_id", ""))
	plan.palette = (data.get("palette", {}) as Dictionary).duplicate(true)
	plan.walls = (data.get("walls", []) as Array).duplicate(true)
	plan.decks = (data.get("decks", []) as Array).duplicate(true)
	plan.rooms = (data.get("rooms", []) as Array).duplicate(true)
	plan.stairs = (data.get("stairs", []) as Array).duplicate(true)
	## Migrates the legacy cell form and pins the canonical shape.
	plan.items = normalize_items(data.get("items", []) as Array)
	var highest := 0
	for collection in [plan.walls, plan.decks, plan.rooms, plan.stairs, plan.items]:
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
