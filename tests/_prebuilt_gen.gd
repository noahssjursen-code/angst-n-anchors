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
## **THAT CONTROL IS SPENT, 2026-08-15 (later the same day).** It was a control on
## the CELL-INDEX parameterisation and it held for that. The deckhouse below has
## since been re-derived from the hull as well, so the three hull_28x10 files no
## longer match what that run emitted: 325 cells -> 1087 on the two coasters,
## 333 -> 1095 on the trawler, and the sjark holds at 271 with 46 cells changed
## in place. Do not read the sentence above as "this file is byte-stable against
## the repository"; it is byte-stable against ITSELF — re-running it twice in a
## row produces four identical md5s, which is the property that matters and is
## re-verified whenever it is run.
##
## Run:
##   xvfb-run -a --server-args="-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy --script res://tests/_prebuilt_gen.gd

const OUT_DIR := "res://resources/data/vessels/prebuilt"

const BIG := "hull_28x10"
const SMALL := "hull_15x5"

## ── THE DECKHOUSE'S PROPORTIONS — 2026-08-15 ────────────────────────────────
##
## Everything here is a fraction of the hull the house stands on, or an absolute
## HUMAN dimension. There is no metre constant standing in for a hull dimension,
## which is exactly what `_add_deckhouse(…, 6, 8, …)` was: one 3.0 x 4.0 m box,
## 2.5 m to the eaves, on a 15 m sjark and on a 28 m coaster alike. On the sjark
## that is 60% of the beam and 27% of the length and reads as a wheelhouse; on
## the 28 m hulls it is 30% and 14% and reads as a portacabin on a barge, with
## the 1.8 m figure's head at the eaves. Rendered and looked at:
## `screenshots/vessels/starter_28m/28_10_m__bow_quarter.png`.
##
## The pattern is `DeckFitout._catch_hold_berth`'s, including its lesson: the
## first version of that produced a 6.0 x 2.0 m hold that photographed as a low
## ledge, and an aspect cap went in because of a RENDER, not a number.
##
## Side decks are a person wide. A hull's own beam sets the rest, up to a ceiling
## so a beamy hull does not end up as all house.
const HOUSE_SIDE_DECK_M := 1.00
const HOUSE_MAX_BEAM_FRACTION := 0.80
## Deck to spare fore and aft of the house, so its after face is not the transom.
const HOUSE_END_MARGIN_M := 2.00
## The house's length as a fraction of the hull's. The sjark measures 0.267 and
## reads right; that is where this comes from.
const HOUSE_LOA_FRACTION := 0.27
##
## ── WHY HEIGHT IS QUANTISED AND WIDTH IS NOT ────────────────────────────────
##
## A deck's height is a HUMAN dimension: 2.5 m of headroom plus 0.5 m of deck
## structure, on a 15 m sjark and on a 300 m ship alike. Ships do not make their
## decks taller, they add more of them. So the house's height is a fraction of
## the hull ROUNDED TO A WHOLE NUMBER OF TIERS, and the tier itself never
## changes size. `HOUSE_TIER_LEVELS + 1` levels = 3.0 m moulded per tier.
##
## Measured: 15 m -> 15 x 0.17 / 3.0 = 0.85 -> 1 tier, eaves 2.5 m (the shipped
## sjark, unchanged). 28 m -> 28 x 0.17 / 3.0 = 1.59 -> 2 tiers, eaves 5.5 m.
const HOUSE_EAVES_LOA_FRACTION := 0.17
const HOUSE_TIER_LEVELS := 5
const HOUSE_MAX_TIERS := 3
## Each tier up steps in from the one below — a boat deck round the wheelhouse,
## which is where the mast is stepped and what stops the house being one slab.
const HOUSE_TIER_INSET_CELLS := 2
const HOUSE_TIER_SHORTEN_CELLS := 4

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


## The house's plan and tier count on THIS hull, in cells. Nothing below is a
## size: they are all fractions of the hull's own beam and length, floored by a
## human margin and quantised to the glazing module.
##
## ── THE QUANTISATION, AND WHY IT IS NOT A FUDGE ─────────────────────────────
##
## `block_windshield` is a [3,1,1] brick — one uninterrupted 1.34 m pane behind a
## perimeter frame. A face that is a whole number of them is a windscreen; a face
## with a remainder gets a 0.34 m punched square at one end and reads as a
## mistake. So the TOP tier is derived first, snapped down to a whole number of
## windshields (and to an EVEN cell count, because `grid.width` is even and a
## house that is not centred on the beam is visible in a bow-on frame), and the
## tiers below are stepped back OUT from it.
##
## Measured rather than claimed: on both shipped hulls every UNINTERRUPTED glazed
## run divides exactly — the 28 m wheelhouse is 12 cells across (4 windshields)
## with a 9-cell side run (3), the sjark 6 across (2) with a 6-cell side run (2).
## The one remainder left is the sjark's after face at the lower glazing row,
## where the door splits a 6-cell run into 2 + 2 and each half falls back to
## `block_window`. That is the fallback doing its job on a face a door crosses,
## not a face that came out wrong, and the row above it is a clean 2-windshield
## band — but "no remainder anywhere" would have been a sentence nobody measured.
##
## Measured: hull_15x5 (10 x 30) -> 6 x 8 cells, 1 tier — the shipped sjark, to
## the cell. hull_28x10 (20 x 56) -> 16 x 15 cells, 2 tiers, with a 12 x 11
## wheelhouse on top: an 8.0 x 7.5 m house 5.5 m to the eaves, against the 3.0 x
## 4.0 x 2.5 m box it replaces.
func _house_plan(grid: DeckGrid) -> Dictionary:
	var cell := DeckGrid.CELL_M
	var beam_m := grid.half_beam * 2.0
	var loa_m := grid.half_loa * 2.0
	var span := BrickCatalog.footprint_of("block_windshield").x
	var module := HOUSE_TIER_LEVELS + 1

	var tiers := clampi(
		int(round(loa_m * HOUSE_EAVES_LOA_FRACTION / (float(module) * cell))),
		1, HOUSE_MAX_TIERS,
	)
	var w_max := mini(
		int(floor((beam_m - 2.0 * HOUSE_SIDE_DECK_M) / cell)),
		int(floor(beam_m * HOUSE_MAX_BEAM_FRACTION / cell)),
	)
	var l_max := mini(
		int(round(loa_m * HOUSE_LOA_FRACTION / cell)),
		grid.length - int(round(HOUSE_END_MARGIN_M / cell)) * 2,
	)
	## Shrink the tier count until the top tier still has a face worth glazing.
	## A hull too small for two tiers gets one; this is the only place the count
	## is allowed to disagree with the fraction above.
	while tiers > 1:
		var top_w := w_max - 2 * HOUSE_TIER_INSET_CELLS * (tiers - 1)
		var top_l := l_max - HOUSE_TIER_SHORTEN_CELLS * (tiers - 1)
		if top_w >= 2 * span and top_l >= span + 2:
			break
		tiers -= 1
	## The top tier, snapped to the glazing module: an even whole number of
	## windshields across, and a side run (corner to corner, less the two corner
	## cells) that is a whole number of them fore and aft.
	var step := 2 * span
	var top_w := maxi((w_max - 2 * HOUSE_TIER_INSET_CELLS * (tiers - 1)) / step, 1) * step
	var top_l := 2 + maxi(
		(l_max - HOUSE_TIER_SHORTEN_CELLS * (tiers - 1) - 2) / span, 1
	) * span
	return {
		"tiers": tiers,
		"w": top_w + 2 * HOUSE_TIER_INSET_CELLS * (tiers - 1),
		"l": top_l + HOUSE_TIER_SHORTEN_CELLS * (tiers - 1),
		"span": span,
		"module": module,
	}


## Deckhouse — a WHEELHOUSE, not a shoebox, and one that belongs to its hull.
## `z_frac` places the forward face along the hull; everything else comes from
## `_house_plan` above. Five levels is 2.5 m of headroom at the 0.5 m cell
## (CONVENTIONS §3a).
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
## ── WHAT CHANGED AGAIN, 2026-08-15 (the tiers), AND WHY ─────────────────────
##
## Three of the four defects `screenshots/vessels/starter_28m/` showed are here.
##
##   SIZE    the plan and the tier count come from `_house_plan`, off the hull.
##   AFT     the after face was two 0.34 m punched squares beside the door — the
##           windscreen change in `3582276` reached the front and forward sides
##           only, so with the hipped cap above it read as a cottage gable. Every
##           face of the wheelhouse tier is now glazed by the same run-filler,
##           the after one included, and the accommodation tier below carries a
##           regular row of windows on all four faces.
##   SIDES   the side band was `span` cells (3 of an 8-cell house), so more than
##           half the profile was unbroken white. It now runs corner to corner.
##
## The fourth (the masthead light below the roof) is in `_add_mast`'s callers.
func _add_deckhouse(
	layout: BrickLayout, grid: DeckGrid, z_frac: float
) -> Dictionary:
	var plan := _house_plan(grid)
	var tiers := int(plan["tiers"])
	var span := int(plan["span"])
	var module := int(plan["module"])
	var house_w := int(plan["w"])
	var house_l := int(plan["l"])
	var x0 := (grid.width - house_w) / 2
	var x1 := x0 + house_w - 1
	var z0 := clampi(
		int(round(float(grid.length) * z_frac)),
		grid.bow_taper_cells + 1,
		grid.length - house_l - int(round(HOUSE_END_MARGIN_M / DeckGrid.CELL_M)),
	)
	var z1 := z0 + house_l - 1
	## The door is centred on the after face of the BOTTOM tier, which is the
	## face a captain walks up to off the working deck.
	##
	## NOT FIXED, and named rather than worked around: `block_door` is a [2,3,1]
	## footprint, which at the 0.5 m cell is 1.0 x 1.5 x 0.5 m — its own comment
	## claims "2 m wide x 3 m tall". Measured with the leaf actually driven open,
	## the tallest capsule that passes is 1.25 m against a 1.80 m player
	## (STATE.md 5h). That is downstream of the open owner decision on
	## `DeckGrid.CELL_M` (CONVENTIONS §3a) and is not settled here.
	var door_x0 := x0 + (house_w - 2) / 2
	var door_cells := {}
	for dx in range(2):
		for dy in range(3):
			door_cells[Vector3i(door_x0 + dx, dy, z1)] = true

	var top := {}
	for t in range(tiers):
		var tx0 := x0 + t * HOUSE_TIER_INSET_CELLS
		var tx1 := x1 - t * HOUSE_TIER_INSET_CELLS
		var tz1 := z1 - t * HOUSE_TIER_SHORTEN_CELLS
		var y0 := t * module
		for x in range(tx0, tx1 + 1):
			for z in range(z0, tz1 + 1):
				if not (x == tx0 or x == tx1 or z == z0 or z == tz1):
					continue
				for dy in range(HOUSE_TIER_LEVELS):
					var c := Vector3i(x, y0 + dy, z)
					if door_cells.has(c):
						continue
					_set_on_deck(layout, grid, c, "block")
		if t < tiers - 1:
			## A flat boat deck over the whole tier, which is what the tier above
			## stands on and what a person walks round it on.
			_glaze_accommodation(layout, grid, tx0, tx1, z0, tz1, y0, door_cells)
			_deck_slab(layout, grid, tx0, tx1, z0, tz1, y0 + HOUSE_TIER_LEVELS)
			## A boat deck 3 m above the working deck with nothing round its edge
			## is a fall, and it reads as a bare shelf. Same brick and the same
			## outboard-yaw rule as the deck edge below.
			for x in range(tx0, tx1 + 1):
				for z in range(z0, tz1 + 1):
					if not (x == tx0 or x == tx1 or z == z0 or z == tz1):
						continue
					_set_on_deck(
						layout, grid, Vector3i(x, y0 + HOUSE_TIER_LEVELS + 1, z),
						"railing", _perimeter_yaw(tx0, tx1, z0, tz1, x, z),
					)
			continue
		## The top tier is the wheelhouse: glazed on every face, a brow, a cap.
		_glaze_wheelhouse(layout, grid, tx0, tx1, z0, tz1, y0, span, door_cells)
		## The brow stands one cell forward of the house front. Clamped rather
		## than assumed: on a hull whose bow taper reaches the house there is no
		## cell there, and a brow written into the sea would certify anyway
		## (`_measure` never asks the grid) — the whole reason `_set_on_deck`
		## exists.
		var z_brow := maxi(z0 - 1, grid.bow_taper_cells)
		if z_brow < z0:
			for x in range(tx0, tx1 + 1):
				_set_on_deck(
					layout, grid, Vector3i(x, y0 + HOUSE_TIER_LEVELS - 1, z_brow), "block"
				)
		_cap_deckhouse(layout, grid, tx0, tx1, z_brow, tz1, y0 + HOUSE_TIER_LEVELS)
		top = {
			"top_x0": tx0, "top_x1": tx1, "top_z0": z0, "top_z1": tz1,
			"top_y0": y0, "z_brow": z_brow, "roof_y": y0 + HOUSE_TIER_LEVELS,
			## The sidelights ride on the SOLID wall band just under the eaves,
			## outboard, which is where a wheelhouse carries them. On a glazed
			## cell `attach_light` silently walks to the windshield's primary
			## cell, which still satisfies `brick_side` but puts the light
			## somewhere nobody chose — and every side cell in the window band is
			## glazed now, so this may not be one of them.
			"port_wall": Vector3i(tx0, y0 + HOUSE_TIER_LEVELS - 1, z0 + 2),
			"stbd_wall": Vector3i(tx1, y0 + HOUSE_TIER_LEVELS - 1, z0 + 2),
		}

	if not layout.place_footprint(Vector3i(door_x0, 0, z1), "block_door", 0, grid):
		_refuse("deckhouse door at %v" % Vector3i(door_x0, 0, z1))
	var house := {"x0": x0, "x1": x1, "z0": z0, "z1": z1, "tiers": tiers}
	house.merge(top)
	return house


## A flat deck slab over a rectangle, tiled with the LARGEST flat roof brick
## that fits at each free cell — `roof_flat_4x4`, then `roof_flat_2x2`, then
## `roof_flat`. Same drawn surface either way; what changes is the primary count.
##
## ── WHY THIS IS NOT A MICRO-OPTIMISATION ────────────────────────────────────
##
## `DeckFitout.apply` sends any layout over `LARGE_LAYOUT_THRESHOLD` (1000)
## PRIMARY cells down `apply_staged`, which builds the vessel a few items per
## frame and leaves it at `READINESS_HULL` until the job finishes. A 16 x 15 boat
## deck laid in 1 x 1 cells is 240 primaries on its own, and it pushed all three
## 28 m presets from 968 to 1014 — over the line. Measured, not reasoned about:
## every capture of the v2 house came back as a BARE HULL, because the shot rig
## photographs four frames after spawning and the staged job had built nothing
## yet. Tiled, the same deck is 36 primaries and the presets sit at ~810.
##
## The saving is real beyond the threshold: one `roof_flat_4x4` is one merged
## mesh contribution and one walk collider where sixteen `roof_flat` are sixteen.
func _deck_slab(
	layout: BrickLayout, grid: DeckGrid, x0: int, x1: int, z0: int, z1: int, y: int
) -> void:
	var taken := {}
	for step in [4, 2, 1]:
		var brick_id := "roof_flat_%dx%d" % [step, step] if step > 1 else "roof_flat"
		for z in range(z0, z1 + 1):
			for x in range(x0, x1 + 1):
				if x + step - 1 > x1 or z + step - 1 > z1:
					continue
				var free := true
				for dx in range(step):
					for dz in range(step):
						if taken.has(Vector2i(x + dx, z + dz)):
							free = false
				if not free:
					continue
				if step == 1:
					_set_on_deck(layout, grid, Vector3i(x, y, z), brick_id)
				elif not layout.place_footprint(Vector3i(x, y, z), brick_id, 0, grid):
					_refuse("deck slab %s at %v" % [brick_id, Vector3i(x, y, z)])
					continue
				for dx in range(step):
					for dz in range(step):
						taken[Vector2i(x + dx, z + dz)] = true


## The yaw that turns a railing's run outboard on the edge of a RECTANGLE that
## is not the deck — `_railing_yaw` asks the grid, which knows nothing about a
## boat deck three metres up. A corner belongs to the long side, for the same
## reason it does down on deck: a break in a side run reads worse than a notch.
func _perimeter_yaw(x0: int, x1: int, z0: int, z1: int, x: int, z: int) -> int:
	if x == x0:
		return 90
	if x == x1:
		return 270
	if z == z0:
		return 0
	return 180


## One straight run of glazing, `n` cells long from `start` along `axis`, filled
## with the widest glass that fits: whole `block_windshield` panes (footprint
## [3,1,1] — one 1.34 m pane behind a perimeter frame) wherever `span` cells
## remain, `block_window` for anything left over, and nothing at all on a cell
## the door owns.
##
## `_house_plan` sizes every face so that there IS no remainder on either shipped
## hull; the remainder path is the honest fallback for a hull nobody has authored
## yet, not the normal case.
##
## Glass is on the brick's local −Z face, so yaw aims it outboard: 0 forward, 90
## to port, 180 aft, 270 to starboard. Measured in `tests/_wedge_yaw_probe.gd`,
## not derived from the rotation convention — deriving it is how every railing on
## all four presets ended up running athwartships.
func _glaze_run(
	layout: BrickLayout, grid: DeckGrid, start: Vector3i, axis: Vector3i,
	n: int, yaw: int, span: int, skip: Dictionary
) -> void:
	var i := 0
	while i < n:
		var free_run := 0
		while i + free_run < n and not skip.has(start + axis * (i + free_run)):
			free_run += 1
		if free_run == 0:
			i += 1
			continue
		if free_run >= span:
			for k in range(span):
				layout.erase_cell(start + axis * (i + k))
			if layout.place_footprint(start + axis * i, "block_windshield", yaw, grid):
				i += span
				continue
			_refuse("windshield at %v yaw %d" % [start + axis * i, yaw])
			for k in range(span):
				_set_on_deck(layout, grid, start + axis * (i + k), "block_window", yaw)
			i += span
			continue
		var c := start + axis * i
		layout.erase_cell(c)
		_set_on_deck(layout, grid, c, "block_window", yaw)
		i += 1


## The wheelhouse band — every face, corner to corner. Rows 2 and 3 of the tier
## put the glass between 1.0 m and 2.0 m above that tier's own floor, which
## brackets the 1.6 m eye height of the figure everything here is sized against.
##
## The corner cells belong to the fore-and-aft faces; the side runs start one
## cell in, so a run never fights a run.
func _glaze_wheelhouse(
	layout: BrickLayout, grid: DeckGrid, x0: int, x1: int, z0: int, z1: int,
	y0: int, span: int, skip: Dictionary
) -> void:
	for dy: int in [2, 3]:
		var y: int = y0 + dy
		_glaze_run(layout, grid, Vector3i(x0, y, z0), Vector3i(1, 0, 0), x1 - x0 + 1, 0, span, skip)
		_glaze_run(layout, grid, Vector3i(x0, y, z1), Vector3i(1, 0, 0), x1 - x0 + 1, 180, span, skip)
		for side in [[x0, 90], [x1, 270]]:
			var sx: int = side[0]
			_glaze_run(
				layout, grid, Vector3i(sx, y, z0 + 1), Vector3i(0, 0, 1),
				z1 - z0 - 1, int(side[1]), span, skip
			)


## An accommodation tier is not a wheelhouse: it gets ONE row of square windows
## at regular spacing on all four faces, at 1.5–2.0 m above its own floor. A
## continuous band here reads as a ferry lounge; nothing at all is the 2.5 m
## white field this whole change exists to remove.
##
## ── a1 -> a2: THE COMMENT ABOVE SAID "ONE ROW" AND THE CODE DREW TWO ─────────
##
## Iteration a1 glazed rows 2 AND 3 at a 2-cell pitch. Two vertically adjacent
## `block_window` cells merge their frames, so the after face of the 28 m house
## came out as a 7 x 2 grid of identical framed squares on an 8.0 x 2.5 m white
## field — `screenshots/vessels/iter_house28/a1__bulk_small__on_deck.png`, and it
## reads as an office block, which is the same complaint as the portacabin one
## rank higher. A tier here is 2.5 m of headroom: ONE deck, so ONE row of
## windows, and the pitch went 2 cells (1.0 m) to 3 (1.5 m) so 8 m of face
## carries five windows instead of seven. Compare a2 against a1 on that frame.
##
## ── a2 -> a3: THE ROW SAT TOO HIGH ON ITS OWN TIER ──────────────────────────
##
## Row 3 puts the glass 1.5–2.0 m above that tier's floor, which leaves a 1.5 m
## unbroken white band the full 7.5 m under it — the largest remaining white
## field in `a2__fishing_trawler__house_profile_ortho.png`, and above the eye of
## the 1.8 m figure standing inside it (eye 1.6 m, so you would look UNDER the
## sill). Row 2 is 1.0–1.5 m: a human sill, and it centres the row on the 2.5 m
## tier instead of hanging it under the deckhead.
const HOUSE_ACCOM_WINDOW_ROW := 2
const HOUSE_ACCOM_WINDOW_PITCH := 3


## Window positions along a face, at `pitch` intervals, CENTRED on the run so a
## face is not lopsided — `range(lo, hi, pitch)` leaves the remainder all at one
## end, which on a 16-cell face is a 1-cell margin forward and a 3-cell margin
## aft and is visible in a bow-on ortho.
func _window_stations(lo: int, hi: int, pitch: int) -> Array[int]:
	var out: Array[int] = []
	if hi < lo:
		return out
	var n := (hi - lo) / pitch + 1
	var start := lo + (hi - lo - (n - 1) * pitch) / 2
	for i in range(n):
		out.append(start + i * pitch)
	return out


func _glaze_accommodation(
	layout: BrickLayout, grid: DeckGrid, x0: int, x1: int, z0: int, z1: int,
	y0: int, skip: Dictionary
) -> void:
	var cells: Array[Array] = []
	var y := y0 + HOUSE_ACCOM_WINDOW_ROW
	for x in _window_stations(x0 + 1, x1 - 1, HOUSE_ACCOM_WINDOW_PITCH):
		cells.append([Vector3i(x, y, z0), 0])
		cells.append([Vector3i(x, y, z1), 180])
	for z in _window_stations(z0 + 1, z1 - 1, HOUSE_ACCOM_WINDOW_PITCH):
		cells.append([Vector3i(x0, y, z), 90])
		cells.append([Vector3i(x1, y, z), 270])
	for entry in cells:
		var c: Vector3i = entry[0]
		if skip.has(c):
			continue
		layout.erase_cell(c)
		_set_on_deck(layout, grid, c, "block_window", int(entry[1]))


## A hipped cap instead of a flat slab: the perimeter falls outboard on
## `roof_slope`, the corners are mitred with `roof_corner`, and `roof_flat` fills
## only what is left. Every yaw below is the measured one — a `roof_slope`'s HIGH
## edge is at local −Z at yaw 0, and a `roof_corner`'s peak is at (−X,−Z).
func _cap_deckhouse(
	layout: BrickLayout, grid: DeckGrid, x0: int, x1: int, z0: int, z1: int, roof_y: int
) -> void:
	## The flat middle is one tiled slab (see `_deck_slab`); only the falling
	## perimeter has to be laid a cell at a time.
	if x1 - x0 >= 2 and z1 - z0 >= 2:
		_deck_slab(layout, grid, x0 + 1, x1 - 1, z0 + 1, z1 - 1, roof_y)
	for x in range(x0, x1 + 1):
		for z in range(z0, z1 + 1):
			var c := Vector3i(x, roof_y, z)
			var on_x := x == x0 or x == x1
			var on_z := z == z0 or z == z1
			if not (on_x or on_z):
				continue
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
			else:
				_set_on_deck(layout, grid, c, "roof_slope", 270 if x == x0 else 90)


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
## it stands on. The masthead light sits on the top segment.
##
## ── EVERY MAST IS NOW STEPPED ON THE WHEELHOUSE ROOF — 2026-08-15 ───────────
##
## The sjark already was, and its own comment said why: *"a 2 m deck-stepped mast
## on a 2.5 m house puts the masthead light below the roof it is supposed to be
## seen over"*. The other three were left deck-stepped, so on all three 28 m
## presets the masthead light stood at 1.75 m against a 3.00 m roof — BELOW the
## wheelhouse — and on `28_10_m` and `bulk_small` the mast was dead on the
## centreline four cells forward of the house, which put the lantern in the
## middle of the windscreen at helm eye height
## (`screenshots/vessels/starter_28m/bulk_small__bow_on_ortho.png`).
##
## All four certified, because `white_light_height` is a `white_above_sidelights`
## rule and asks only that the white light's CELL is higher than the sidelights'.
## It measured 1.0 — one cell, 0.5 m — on all three. The rule cannot see the
## superstructure at all; see `tests/deckhouse_shape_test.gd` §5, which does.
func _add_mast(layout: BrickLayout, grid: DeckGrid, z: int, y0: int = 0) -> Vector3i:
	var x := (grid.width - 2) / 2
	if not layout.place_footprint(Vector3i(x, y0, z), "mast_base", 0, grid):
		_refuse("mast base at %v" % Vector3i(x, y0, z))
	for y in range(y0 + 1, y0 + 4):
		if not layout.place_footprint(Vector3i(x, y, z), "mast_pole", 0, grid):
			_refuse("mast pole at %v" % Vector3i(x, y, z))
	return Vector3i(x, y0 + 3, z)


## The helm stands on the WHEELHOUSE floor — the top tier's own bottom level —
## not on the main deck. On a one-tier house those are the same cell, so the
## sjark is unchanged; on a two-tier house the old formula put the wheel in the
## accommodation space under the bridge.
func _add_helm(layout: BrickLayout, grid: DeckGrid, house: Dictionary) -> void:
	_set_on_deck(
		layout, grid,
		Vector3i((grid.width - 2) / 2, int(house["top_y0"]), int(house["top_z0"]) + 2),
		"helm",
	)


## The mast is stepped on the wheelhouse roof, on the centreline, just abaft the
## windscreen — so the masthead light stands above every part of the house and
## nothing stands in the helmsman's sightline.
func _add_house_mast(layout: BrickLayout, grid: DeckGrid, house: Dictionary) -> Vector3i:
	return _add_mast(
		layout, grid, int(house["top_z0"]) + 2, int(house["roof_y"]) + 1
	)


# ── the four starters ───────────────────────────────────────────────────────


func _trawler() -> Dictionary:
	var grid := HullRegistry.make_grid(BIG)
	var layout := _base(BIG, grid)
	_add_mooring(layout, grid)
	## Wheelhouse forward, open working deck aft — the sjark arrangement.
	var house := _add_deckhouse(layout, grid, 2.0 / 7.0)
	_add_helm(layout, grid, house)
	var mast_top := _add_house_mast(layout, grid, house)
	_add_nav_lights(layout, house, mast_top)
	## Net drum on the working deck aft of the house.
	_add_trommel(layout, grid, int(house["z1"]) + 11)
	return {"hull_id": BIG, "layout": layout}


func _cargo() -> Dictionary:
	var grid := HullRegistry.make_grid(BIG)
	var layout := _base(BIG, grid)
	_add_mooring(layout, grid)
	## Superstructure aft, clear cargo deck forward — the coaster arrangement.
	var house := _add_deckhouse(layout, grid, 5.0 / 7.0)
	_add_helm(layout, grid, house)
	var mast_top := _add_house_mast(layout, grid, house)
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
	var house := _add_deckhouse(layout, grid, 5.0 / 7.0)
	_add_helm(layout, grid, house)
	var mast_top := _add_house_mast(layout, grid, house)
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
	var house := _add_deckhouse(layout, grid, 0.30)
	_add_helm(layout, grid, house)
	var mast_top := _add_house_mast(layout, grid, house)
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
