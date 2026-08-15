extends SceneTree

## Scratch probe (leading underscore — not a gate unit).
## Authors the starter vessels through the real BrickLayout API, validates
## each against VesselCompliance, and writes the prebuilt JSON only when the
## report says ok. Re-runnable: same input, same file.
##
## ── WHY THIS FILE IS THE AUTHORING PATH AND NOT A HAND-WRITTEN JSON ─────────
##
## A preset is a `cells` dictionary of ~300 entries keyed "x,y,z". Typing one
## is exactly REALITY.md §5 — the format is easy for an agent and impossible
## for a player — and, worse, it BYPASSES the only thing standing between a
## broken layout and a silent half-failure: `PrebuiltVesselCatalog` marks a
## non-compliant preset `is_draft` and merely `push_warning`s, so a hand-written
## mistake ships as a warning nobody reads. `_emit` refuses to write a file at
## all unless `VesselCompliance.validate()` returns ok, and prints the whole
## checklist either way.
##
## ── WHAT CHANGED 2026-08-15, AND THE PROPERTY IT BUYS ───────────────────────
##
## Every cell index here used to be a constant measured off hull_28x10's
## 20 × 56 grid: the deckhouse at `x0=7..12`, the aft house at `z0=40..47`, the
## mast at `x=9`, mooring at `z=14`. On hull_15x5 — 10 × 30 — every one of
## those is off the deck, and `BrickLayout.set_brick` did not take a grid, so
## it would have written bricks into the sea and reported success.
##
## The rule now, and it is checkable rather than hoped for:
##
##   **Every index is derived from `grid.width` / `grid.length` /
##   `grid.bow_taper_cells`, or from a placement already made; and every cell is
##   tested against the deck before it is written. A placement that would land
##   off the deck refuses the whole vessel.**
##
## THE TEST MOVED, 2026-08-15 (second edit that day). It was a private `_on_deck`
## predicate in this file — a second derivation of a rule three other files also
## carried. `BrickLayout.set_brick` now takes the grid and returns false, so the
## rule is asked once, in the setter. `_set_on_deck` is this file's POLICY on the
## answer (refuse the whole vessel); `_refusals` is that refusal. The three
## hull_28x10 presets re-emit BYTE-IDENTICAL under the derived formulas (md5
## unchanged), which is the control proving the parameterisation is faithful and
## not a redesign wearing the old numbers.
##
## Run:
##   xvfb-run -a --server-args="-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy --script res://tests/_prebuilt_gen.gd

const OUT_DIR := "res://resources/data/vessels/prebuilt"

const BIG := "hull_28x10"
const SMALL := "hull_15x5"

var _refusals := PackedStringArray()


func _initialize() -> void:
	var ok := true
	ok = _emit(_trawler(), {
		"id": "fishing_trawler",
		"name": "Coastal trawler",
		"registration_id": "fishing_vessel",
		"price_marks": 48000,
		"shaft_power_kw": 1871.0,
	}) and ok
	ok = _emit(_cargo(), {
		"id": "28_10_m",
		"name": "Coastal cargo vessel",
		"registration_id": "cargo_vessel",
		"price_marks": 52000,
		"shaft_power_kw": 1871.0,
	}) and ok
	ok = _emit(_bulk(), {
		"id": "bulk_small",
		"name": "Coastal bulk vessel",
		"registration_id": "bulk_vessel",
		"price_marks": 56000,
		"shaft_power_kw": 1871.0,
	}) and ok
	ok = _emit(_sjark(), {
		"id": "sjark_15m",
		"name": "Coastal sjark",
		"registration_id": "fishing_vessel",
		"price_marks": 19500,
		"shaft_power_kw": 280.0,
	}) and ok
	print("GEN %s" % ("OK" if ok else "REFUSED"))
	quit(0 if ok else 1)


# ── the grid is the only source of position ─────────────────────────────────


func _refuse(what: String) -> void:
	_refusals.append(what)


## The OFF-DECK guard used to live here, as a private `_on_deck` predicate
## (`cell.y >= 0 and grid.cell_shape(...) == FULL`) that this file applied before
## calling a `set_brick` which could not refuse. It was a SECOND derivation of a
## rule that `place_footprint` and `DeckFitout._item_is_valid` each also carried,
## and it covered four files — this generator, and nothing a player touches.
##
## It is deleted. `BrickLayout.set_brick` takes the grid and returns false, so
## the rule is asked once, in the setter, by everything (REALITY.md §3b). What
## stays here is this generator's own POLICY, which is not the same thing as the
## rule: a refusal fails the whole vessel and no JSON is written.
##
## The deleted predicate and the surviving one are not identical, and the
## difference is a widening, not a loosening: `_on_deck` was `== FULL` flat, so it
## would have refused a `diagonal_plan` brick on a correctly-yawed bow half cell —
## the exact placement those bricks exist for. No preset here places one, so the
## four emitted files are unaffected (verified byte-identical, md5 unchanged).
func _set_on_deck(
	layout: BrickLayout, grid: DeckGrid, cell: Vector3i, brick_id: String, yaw: int = 0
) -> void:
	if not layout.set_brick(grid, cell, brick_id, yaw):
		_refuse(BrickLayout.off_grid_reason(grid, cell, brick_id))


# ── shared hull furniture ───────────────────────────────────────────────────


## The yaw that turns a railing's run OUTBOARD on this cell.
##
## `railing` draws its run spanning local X on the local −Z face — "outboard when
## yaw matches", says `_add_railing_visual`. Nothing was matching it: every
## preset placed every railing at yaw 0, so the runs along the SIDES lay
## athwartships, and the port and starboard deck edges rendered as a row of
## little gates standing across the deck instead of a rail along the side. It is
## plainly visible in `screenshots/vessels/starter/starter__bow_quarter.png`
## before this changed, and it was on all four presets.
##
## The four values are MEASURED, not derived from the rotation convention:
## `tests/_railing_yaw_probe.gd` places one railing on port-edge cell (0,0,20) of
## hull_15x5 at each yaw and reports the drawn AABB —
##   yaw   0 -> x span 0.57 m, z span 0.09 m at z−  (run across the deck, fwd face)
##   yaw  90 -> x span 0.09 m at x −2.47, z span 0.57 m  (run along the PORT face)
##   yaw 180 -> run across the deck on the after face
##   yaw 270 -> run along the +X face  (STARBOARD)
##
## A corner cell is an edge on two faces and can hold one brick, so the side wins:
## a break in a long side run reads far worse than a notch at a transom corner.
func _railing_yaw(grid: DeckGrid, ix: int, iz: int) -> int:
	if grid.cell_shape(ix - 1, iz) != DeckGrid.CellShape.FULL:
		return 90
	if grid.cell_shape(ix + 1, iz) != DeckGrid.CellShape.FULL:
		return 270
	if grid.cell_shape(ix, iz - 1) != DeckGrid.CellShape.FULL:
		return 0
	return 180


func _base(hull_id: String, grid: DeckGrid) -> BrickLayout:
	var layout := BrickLayout.new()
	layout.hull_id = hull_id
	## Deck-edge railing all round, the same mechanism `_paint_edge_railings`
	## uses — one railing per edge cell, so it follows the bow taper exactly.
	for ix in range(grid.width):
		for iz in range(grid.length):
			if not grid.is_edge_cell(ix, iz):
				continue
			_set_on_deck(layout, grid, Vector3i(ix, 0, iz), "railing", _railing_yaw(grid, ix, iz))
	return layout


## Four mooring points, two a side, fore and aft — the general-vessel minimum.
## Fore is a quarter of the way aft, but never inside the bow taper, where the
## outboard cells are half cells and a mooring bit would hang over the water.
func _add_mooring(layout: BrickLayout, grid: DeckGrid) -> void:
	for z in [maxi(grid.bow_taper_cells + 2, grid.length / 4), grid.length - 4]:
		for x in [0, grid.width - 1]:
			_set_on_deck(
				layout, grid, Vector3i(x, 0, z), "railing_mooring", _railing_yaw(grid, x, z)
			)


## Deckhouse — a WHEELHOUSE, not a shoebox. `width_cells` / `length_cells` are
## the intent and the beam is the limit — two clear cells a side, always, so the
## side decks survive on a 10-cell beam. `z_frac` places the forward face along
## the hull. Five levels is 2.5 m of headroom at the 0.5 m cell (CONVENTIONS §3a).
##
## ── WHAT THIS USED TO DRAW, AND WHY IT CHANGED — 2026-08-15 ────────────────
##
## Five levels of `block`, a `block_window` wherever the band crossed, and a
## solid slab of `roof_flat` on top. Four brick ids out of the catalogue's 64.
## The result is in `screenshots/vessels/starter/starter__profile_port_ortho.png`
## as it shipped: a plain white rectangle with a dead-flat top, dead-vertical
## ends, and three pale slits that read as holes punched through to the sky
## rather than as glass. It is the loudest thing in the starter's silhouette and
## the weakest element in it.
##
## Nothing had to be built to fix that. `BrickCatalog` already carries
## `roof_slope`, `roof_corner`, `block_45`, `block_windshield` and the rest —
## the shoebox was a limit of what this generator ASKED FOR, not of the
## vocabulary it was asking. Three changes, each using a brick that was already
## in the palette a player can click:
##
##   BROW    the top level's front ROW is cantilevered one cell proud of the
##           window band and the roof follows it out, so the front breaks
##           forward at the top the way a wheelhouse front rakes. Tried first
##           with `ledge_45`: a 45° wedge is a RAMP, widest at its base at every
##           yaw (measured in `tests/_wedge_yaw_probe.gd`), so it can flare a
##           foot but it cannot soffit an overhang, and the front came out as a
##           notch with a loose block in it. A cantilevered row is simpler and
##           is how the real thing is built.
##   ROOF    a hipped cap — `roof_slope` all round the perimeter falling
##           outboard, `roof_corner` mitring the four corners, `roof_flat` only
##           inside. The flat white lid is gone and the roof has a fall you can
##           see from every angle. Deliberately NOT carried out past the walls
##           as an eave: `roof_slope` fills its whole cell, so an eave presents
##           a 0.5 m grey band across the wall top in profile AND lands its
##           underside exactly on the wall top plane, which z-fights — compare
##           `screenshots/vessels/iter_house/v9__house_profile_ortho.png` (a
##           jagged white sawtooth the full length of the house) with
##           `v6__house_profile_ortho.png` (none). `roof_flat` never had that
##           problem because it draws a 0.18 m slab at the TOP of its cell.
##   GLASS   `block_windshield` — three cells of ONE 1.34 m pane behind a
##           perimeter frame — instead of `block_window`, which is a 0.34 m pane
##           in a frame of its own. Six of those in a row is the grid of punched
##           squares; two windshields is a windscreen. Plus two aft-facing
##           windows either side of the door, because the after face is the one
##           a captain stands in front of on the working deck and it was 3.0 x
##           2.5 m of unbroken white.
##
## Tried and REJECTED by looking, not by argument: chamfering the plan corners
## with `block_45` (the brick equivalent of the piece kit's `corner_45`). It
## works and it is the right instinct, but a 6-cell front with both corners
## chamfered leaves a 4-cell straight run, and 4 is not a whole number of 3-cell
## windshields — so the chamfer costs the full-width windscreen and buys a 0.5 m
## cut that reads as a lighting artefact at this scale. `v7__house_quarter.png`
## against `v6__house_quarter.png` is the comparison.
##
## NOT FIXED, and named rather than worked around: `block_door` is a [2,3,1]
## footprint, which at the 0.5 m cell is 1.0 x 1.5 x 0.5 m — its own comment
## claims "2 m wide x 3 m tall". A 1.8 m player does not fit through it, and
## there is no taller door in the catalogue. That is downstream of the open
## owner decision on `DeckGrid.CELL_M` (CONVENTIONS §3a) and is not settled here.
func _add_deckhouse(
	layout: BrickLayout, grid: DeckGrid, width_cells: int, length_cells: int, z_frac: float
) -> Dictionary:
	var house_w := mini(width_cells, grid.width - 4)
	var house_l := mini(length_cells, grid.length - 6)
	var x0 := (grid.width - house_w) / 2
	var x1 := x0 + house_w - 1
	var z0 := clampi(
		int(round(float(grid.length) * z_frac)),
		grid.bow_taper_cells + 1,
		grid.length - house_l - 2,
	)
	var z1 := z0 + house_l - 1
	## The brow stands one cell forward of the house front. Clamped rather than
	## assumed: on a hull whose bow taper reaches the house there is no cell
	## there, and a brow written into the sea would certify anyway (`_measure`
	## never asks the grid) — which is the whole reason `_set_on_deck` exists.
	var z_brow := maxi(z0 - 1, grid.bow_taper_cells)
	var door_cells := {}
	for dx in range(2):
		for dy in range(3):
			door_cells[Vector3i(x0 + 2 + dx, dy, z1)] = true
	for x in range(x0, x1 + 1):
		for z in range(z0, z1 + 1):
			var on_edge := x == x0 or x == x1 or z == z0 or z == z1
			if not on_edge:
				continue
			for y in range(5):
				var c := Vector3i(x, y, z)
				if door_cells.has(c):
					continue
				_set_on_deck(layout, grid, c, "block")
	_glaze_deckhouse(layout, grid, x0, x1, z0, z1)
	if z_brow < z0:
		for x in range(x0, x1 + 1):
			_set_on_deck(layout, grid, Vector3i(x, 4, z_brow), "block")
	_cap_deckhouse(layout, grid, x0, x1, z_brow, z1, 5)
	if not layout.place_footprint(Vector3i(x0 + 2, 0, z1), "block_door", 0, grid):
		_refuse("deckhouse door at %v" % Vector3i(x0 + 2, 0, z1))
	return {
		"x0": x0, "x1": x1, "z0": z0, "z1": z1, "z_brow": z_brow,
		"roof_y": 5,
		## The sidelights ride on the SOLID wall just abaft the window band. On
		## a glazed cell `attach_light` silently walks to the windshield's
		## primary cell three cells forward, which still satisfies `brick_side`
		## but puts the light somewhere nobody chose.
		"port_wall": Vector3i(x0, 2, z0 + 4),
		"stbd_wall": Vector3i(x1, 2, z0 + 4),
	}


## The window band. A run gets `block_windshield` (footprint [3,1,1] — one
## 1.34 m pane, perimeter frame only) wherever it is a whole number of them, and
## `block_window` for the remainder. Rows 2 and 3 put the glass between 1.0 m
## and 2.0 m above the deck, which brackets the 1.6 m eye height of the figure
## everything here is sized against.
func _glaze_deckhouse(
	layout: BrickLayout, grid: DeckGrid, x0: int, x1: int, z0: int, z1: int
) -> void:
	var span := BrickCatalog.footprint_of("block_windshield").x
	for y in [2, 3]:
		## Forward face, corner to corner.
		var x := x0
		while x <= x1:
			if x1 - x + 1 >= span:
				for dx in range(span):
					layout.erase_cell(Vector3i(x + dx, y, z0))
				if layout.place_footprint(
					Vector3i(x, y, z0), "block_windshield", 0, grid
				):
					x += span
					continue
				_refuse("front windshield at %v" % Vector3i(x, y, z0))
			layout.erase_cell(Vector3i(x, y, z0))
			_set_on_deck(layout, grid, Vector3i(x, y, z0), "block_window", 0)
			x += 1
		## Each side, the forward `span` cells abaft the corner. Glass is on the
		## brick's local −Z face, so yaw aims it outboard: 90 to port, 270 to
		## starboard, 180 aft. Measured in `tests/_wedge_yaw_probe.gd`, not
		## derived from the rotation convention — deriving it is how every
		## railing on all four presets ended up running athwartships.
		for side in [[x0, 90], [x1, 270]]:
			var sx: int = side[0]
			var yaw: int = side[1]
			for dz in range(span):
				layout.erase_cell(Vector3i(sx, y, z0 + 1 + dz))
			if not layout.place_footprint(
				Vector3i(sx, y, z0 + 1), "block_windshield", yaw, grid
			):
				_refuse("side windshield at %v yaw %d" % [Vector3i(sx, y, z0 + 1), yaw])
				for dz in range(span):
					_set_on_deck(
						layout, grid, Vector3i(sx, y, z0 + 1 + dz), "block_window", yaw
					)
		## Aft face, either side of the door.
		for x_aft in [x0 + 1, x1 - 1]:
			layout.erase_cell(Vector3i(x_aft, y, z1))
			_set_on_deck(layout, grid, Vector3i(x_aft, y, z1), "block_window", 180)


## A hipped cap instead of a flat slab: the perimeter falls outboard on
## `roof_slope`, the corners are mitred with `roof_corner`, and `roof_flat` fills
## only what is left. Every yaw below is the measured one — a `roof_slope`'s HIGH
## edge is at local −Z at yaw 0, and a `roof_corner`'s peak is at (−X,−Z).
func _cap_deckhouse(
	layout: BrickLayout, grid: DeckGrid, x0: int, x1: int, z0: int, z1: int, roof_y: int
) -> void:
	for x in range(x0, x1 + 1):
		for z in range(z0, z1 + 1):
			var c := Vector3i(x, roof_y, z)
			var on_x := x == x0 or x == x1
			var on_z := z == z0 or z == z1
			if on_x and on_z:
				## Hip corner — peak INBOARD, so both falls run away from it.
				var yaw := 270
				if x == x0 and z == z0:
					yaw = 180
				elif x == x1 and z == z0:
					yaw = 90
				elif x == x1 and z == z1:
					yaw = 0
				_set_on_deck(layout, grid, c, "roof_corner", yaw)
			elif on_z:
				_set_on_deck(layout, grid, c, "roof_slope", 180 if z == z0 else 0)
			elif on_x:
				_set_on_deck(layout, grid, c, "roof_slope", 270 if x == x0 else 90)
			else:
				_set_on_deck(layout, grid, c, "roof_flat")


## Sidelights ride on the deckhouse walls as MOUNTED lights, which is what makes
## `brick_side` measurable: the host cell is the light's position, and the port
## light is on a cell whose local x is negative.
func _add_nav_lights(layout: BrickLayout, house: Dictionary, mast_top: Vector3i) -> void:
	if not layout.attach_light(house["port_wall"] as Vector3i, "light_nav_port", 270):
		_refuse("port sidelight has no wall to mount on at %v" % house["port_wall"])
	if not layout.attach_light(house["stbd_wall"] as Vector3i, "light_nav_stbd", 90):
		_refuse("starboard sidelight has no wall to mount on at %v" % house["stbd_wall"])
	if not layout.attach_light(mast_top, "light_mast_white", 0):
		_refuse("masthead light has no mast to mount on at %v" % mast_top)


## Mast: a tabernacle base and three pole segments on the 2×2 column that
## `mast_base` / `mast_pole` share, centred on the beam. `y0` is the deck level
## it stands on — 0 for a deck-stepped mast, the roof level + 1 for a mast on
## the wheelhouse top. The masthead light sits on the top segment, which is what
## puts it above the sidelights.
func _add_mast(layout: BrickLayout, grid: DeckGrid, z: int, y0: int = 0) -> Vector3i:
	var x := (grid.width - 2) / 2
	if not layout.place_footprint(Vector3i(x, y0, z), "mast_base", 0, grid):
		_refuse("mast base at %v" % Vector3i(x, y0, z))
	for y in range(y0 + 1, y0 + 4):
		if not layout.place_footprint(Vector3i(x, y, z), "mast_pole", 0, grid):
			_refuse("mast pole at %v" % Vector3i(x, y, z))
	return Vector3i(x, y0 + 3, z)


func _add_helm(layout: BrickLayout, grid: DeckGrid, house: Dictionary) -> void:
	_set_on_deck(
		layout, grid, Vector3i((grid.width - 2) / 2, 0, int(house["z0"]) + 2), "helm"
	)


# ── the four starters ───────────────────────────────────────────────────────


func _trawler() -> Dictionary:
	var grid := HullRegistry.make_grid(BIG)
	var layout := _base(BIG, grid)
	_add_mooring(layout, grid)
	## Wheelhouse forward, open working deck aft — the sjark arrangement.
	var house := _add_deckhouse(layout, grid, 6, 8, 2.0 / 7.0)
	_add_helm(layout, grid, house)
	var mast_top := _add_mast(layout, grid, int(house["z1"]) + 3)
	_add_nav_lights(layout, house, mast_top)
	## Net drum on the working deck aft of the house.
	_add_trommel(layout, grid, int(house["z1"]) + 11)
	return {"hull_id": BIG, "layout": layout}


func _cargo() -> Dictionary:
	var grid := HullRegistry.make_grid(BIG)
	var layout := _base(BIG, grid)
	_add_mooring(layout, grid)
	## Superstructure aft, clear cargo deck forward — the coaster arrangement.
	var house := _add_deckhouse(layout, grid, 6, 8, 5.0 / 7.0)
	_add_helm(layout, grid, house)
	var mast_top := _add_mast(layout, grid, int(house["z0"]) - 4)
	_add_nav_lights(layout, house, mast_top)
	## Two container pads on the open deck. Spans tile the container footprint,
	## which `add_container_pad` refuses otherwise. The pad is NOT centred on the
	## beam — it starts a fifth of the way across, which is where this preset was
	## authored, and re-deriving it as centred would move a shipped vessel.
	var pad_w := ContainerUnit.DEFAULT_FOOTPRINT.x * 2
	var pad_x0 := int(round(float(grid.width) * 0.2))
	var pad_z0 := maxi(grid.bow_taper_cells + 4, grid.length / 4)
	if not layout.add_container_pad(
		Vector3i(pad_x0, 0, pad_z0),
		Vector3i(pad_x0 + pad_w - 1, 0, pad_z0 + pad_w - 1),
		grid,
	):
		_refuse("forward container pad at z%d" % pad_z0)
	if not layout.add_container_pad(
		Vector3i(pad_x0, 0, pad_z0 + pad_w),
		Vector3i(pad_x0 + pad_w - 1, 0, pad_z0 + pad_w * 2 - 1),
		grid,
	):
		_refuse("after container pad at z%d" % (pad_z0 + pad_w))
	return {"hull_id": BIG, "layout": layout}


func _bulk() -> Dictionary:
	var grid := HullRegistry.make_grid(BIG)
	var layout := _base(BIG, grid)
	_add_mooring(layout, grid)
	var house := _add_deckhouse(layout, grid, 6, 8, 5.0 / 7.0)
	_add_helm(layout, grid, house)
	var mast_top := _add_mast(layout, grid, int(house["z0"]) - 4)
	_add_nav_lights(layout, house, mast_top)
	## One hold amidships. `add_bulk_hold` registers the zone, which is what
	## `count_tag("bulk_hold")` reads — a placed brick would not count.
	var hold_fp := BrickCatalog.footprint_of("bulk_hold_6x12")
	var hold_x0 := (grid.width - hold_fp.x) / 2
	var hold_z0 := maxi(grid.bow_taper_cells + 6, grid.length / 4 + 2)
	if not layout.add_bulk_hold(Vector3i(hold_x0, 0, hold_z0), "bulk_hold_6x12", 0, grid):
		_refuse("bulk hold at %v" % Vector3i(hold_x0, 0, hold_z0))
	return {"hull_id": BIG, "layout": layout}


## The 15 m sjark — the beginner's boat. Same vocabulary as the trawler above
## on a hull less than half its length: wheelhouse forward of amidships, mast
## STEPPED ON THE WHEELHOUSE ROOF (a 2 m deck-stepped mast on a 2.5 m house puts
## the masthead light below the roof it is supposed to be seen over), open
## working deck aft with the net drum.
func _sjark() -> Dictionary:
	var grid := HullRegistry.make_grid(SMALL)
	var layout := _base(SMALL, grid)
	_add_mooring(layout, grid)
	var house := _add_deckhouse(layout, grid, 6, 8, 0.30)
	_add_helm(layout, grid, house)
	var mast_top := _add_mast(
		layout, grid, int(house["z0"]) + 2, int(house["roof_y"]) + 1
	)
	_add_nav_lights(layout, house, mast_top)
	_add_trommel(layout, grid, int(house["z1"]) + 3)
	return {"hull_id": SMALL, "layout": layout}


## Net drum on the centreline, `z0` cells aft. Clamped so its 4-cell run always
## lands on deck rather than hanging off the transom.
func _add_trommel(layout: BrickLayout, grid: DeckGrid, z0: int) -> void:
	var fp := BrickCatalog.footprint_of("trommel_small")
	var x := (grid.width - fp.x) / 2
	var z := mini(z0, grid.length - fp.z - 1)
	if not layout.place_footprint(Vector3i(x, 0, z), "trommel_small", 0, grid):
		_refuse("trommel at %v" % Vector3i(x, 0, z))


# ── emit ────────────────────────────────────────────────────────────────────


func _emit(built: Dictionary, meta: Dictionary) -> bool:
	var layout: BrickLayout = built["layout"]
	var hull_id := str(built["hull_id"])
	var registration_id := str(meta["registration_id"])
	var grid := HullRegistry.make_grid(hull_id)
	var report := VesselCompliance.validate(layout, hull_id, registration_id, grid)
	var cells_n := (layout.to_dict().get("cells", {}) as Dictionary).size()
	print("--- %s  hull=%s (%dx%d cells, %d-cell bow)  %s  cells=%d primaries=%d" % [
		meta["id"], hull_id, grid.width, grid.length, grid.bow_taper_cells,
		registration_id, cells_n, layout.iter_primary_cells().size(),
	])
	for raw in report.get("checklist", []) as Array:
		var item := raw as Dictionary
		print("    %-24s %s  current=%s" % [
			str(item.get("id", "")), "ok " if bool(item.get("ok", false)) else "RED", str(item.get("current", "")),
		])
	for e in report.get("errors", PackedStringArray()):
		print("    ERR " + str(e))
	## Off-deck placements are a REFUSAL, not a warning: a brick written into the
	## sea still counts for compliance (`_measure` never asks the grid), so the
	## catalogue would certify a vessel with furniture overboard.
	for r in _refusals:
		print("    OFF-DECK " + str(r))
	var clean := _refusals.is_empty()
	_refusals = PackedStringArray()
	if not bool(report.get("ok", false)) or not clean:
		return false
	var preset := {
		"format_version": 2,
		"id": str(meta["id"]),
		"name": str(meta["name"]),
		"hull_id": hull_id,
		"registration_id": registration_id,
		"price_marks": int(meta["price_marks"]),
		"shaft_power_kw": float(meta["shaft_power_kw"]),
		"draft": false,
		"brick_layout": layout.to_dict(),
	}
	var path := "%s/%s.json" % [OUT_DIR, meta["id"]]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		print("    CANNOT WRITE " + path)
		return false
	f.store_string(JSON.stringify(preset, "  ", true) + "\n")
	f.close()
	print("    wrote " + path)
	return true
