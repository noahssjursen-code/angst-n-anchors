extends Node

## Lane B — it spawns real vessels through `CompanyService` / `VesselSpawn` and
## reads the meshes the fit-out actually builds, so it needs the autoloads and a
## live scene tree.
##
## ── THE CLAIM THIS UNIT HOLDS ───────────────────────────────────────────────
##
## Commit `3582276` rebuilt the starter vessel's deckhouse — a cantilevered brow,
## a hipped `roof_slope`/`roof_corner` cap, a full-width `block_windshield` band —
## and NOTHING in the gate could tell. Reverting the cap to `roof_flat` still
## emitted `GEN OK`, all four presets still certified, and 104 units still
## passed. CONVENTIONS §3 (a capture is paired with a machine-checkable claim)
## was unmet for that change.
##
## This unit is that claim. It asserts three SHAPE PROPERTIES of the wheelhouse
## on every shipped preset, measured off the triangles the spawned vessel draws.
##
## ── WHY PROPERTIES AND NOT A BRICK INVENTORY ────────────────────────────────
##
## `roof_slope == 22` is a restated number (REALITY.md §4a): it freezes today's
## house and fights the next improvement. Nothing below names a brick id or
## counts one. A house re-drawn with different bricks, at a different size, on a
## hull nobody has authored yet passes every check here as long as it is still a
## wheelhouse — and a house flattened back into a shoebox fails, whatever it is
## built from.
##
## ── WHAT LAYER THIS ASSERTS AT, AND WHAT THAT COSTS ─────────────────────────
##
## The spawned vessel, with `DeckFitout.skin_enabled` at its SHIPPING value.
## The previous wave concluded the geometry was not addressable there, because
## `VesselSkinBaker` merges every static brick into a handful of meshes and a
## per-brick node lookup finds nothing. That is true of NODES and false of
## GEOMETRY: the merged meshes still carry every vertex, and `surface_get_arrays`
## reads them. Nothing here needs `skin_enabled = false`, so nothing here is
## asserted against a configuration the game does not use.
##
## §4 holds that open rather than assuming it: it measures the same three
## properties with the merger off and requires the two to agree. The mechanism
## says they must — `_merge_generic_brick` appends a brick's own mesh under its
## placement transform, and the box path emits full-cell faces at exact cell
## coordinates, culling only faces BETWEEN two solid cells, which are interior by
## construction — but "the mechanism says so" is REALITY.md §6. Measured on the
## starter, re-measured 2026-08-15: merged 38384 triangles inside the house plan
## against 38780 unmerged, and every shape number below identical to four
## decimals. `masthead_above_roof_m` is in that parity list on purpose — it is
## the one number read off a LIVE NODE the baker is supposed to leave alone.
##
## ── THE FORMULATION THAT WAS TRIED AND IS BLIND (REALITY.md §8) ─────────────
##
## "The roof's top surface has more than one height" sounds like the property and
## is worthless. `roof_flat` draws a 0.18 m slab occupying part of its cell, so a
## dead-flat lid already presents TWO distinct vertex heights and the check goes
## green on the shoebox. (The two were +0.32 and +0.50 until 2026-08-16, when the
## slab was re-seated on the cell FLOOR — see `roof_seat_test` — and they are now
## −0.25 and −0.07. The count is what mattered and the count did not change; the
## numbers are corrected here because a stale one reads as a measurement.)
## §1 measures the FALL instead — how
## high the surface stands at the house's outer perimeter against how high it
## stands inboard — which is 0.5000 m on the hipped cap and 0.0000 m on a flat
## slab, because a slab is as tall at its edge as in its middle.
##
## ── WHAT THE 2026-08-15 HOUSE CHANGE FORCED, AND WHAT IT DID NOT ────────────
##
## The house is no longer one absolute 3.0 x 4.0 x 2.5 m box on every hull: it is
## derived from the hull's beam and length, so hull_28x10 now carries a two-tier
## 8.0 x 7.5 m house 6.0 m to the cap and hull_15x5 keeps the 3.0 x 4.0 m
## wheelhouse it already read as. Four checks moved with it, each named where it
## stands, and NONE of the thresholds below were lowered to fit — REALITY §4a.
##
##   §2b  was "the widest uninterrupted pane spans >= 25% of the front". A
##        `block_windshield` pane is 1.34 m at every house size, so a 6.0 m
##        wheelhouse front carries FOUR of them and each spans 22.3%: the check
##        reddened on a windscreen four panes wide, which is the thing it exists
##        to require. It now measures the WIDE GLASS on the best row — every pane
##        at least twice as wide as it is tall, summed — against the same 25%.
##        Strictly stronger, not weaker: it still fails a lone pane on a wide
##        house (16.8%) and it fails punched squares at 0.0% instead of 11.3%,
##        because a 0.34 x 0.34 m square is not wide glass at any house size.
##   §1   measured `inset` from the bounds of EVERY roof-tagged cell. On a tiered
##        house that is the boat deck — 8.0 m wide, against a 6.0 m cap standing
##        1.0 m inboard of it — so the fall was only ever sampled where the cap
##        happens to touch those bounds, which is its forward edge over the brow.
##        A cap flattened on its sides alone would have passed. `inset` is now
##        taken from the plan at the ROOF LEVEL, so all four falls are sampled.
##        (Measured: with the old bounds a fully flat lid still reddened —
##        0.0000 — so this is a narrowing found by reading, not by a mutation.)
##   §5   the after face. Nothing held it and STATE.md 5i says so; it was two
##        0.34 m punched squares beside the door on a 3.0 x 2.5 m field, which
##        under a hipped cap reads as a cottage gable.
##   §6   the side. "More than half the house's length in profile is unbroken
##        white" — the side band was three cells of an eight-cell house.
##   §7   the masthead light. On all three 28 m presets it stood at 1.75 m
##        against a 3.00 m roof, and on two of them dead on the centreline
##        forward of the house, so the lantern sat in the middle of the
##        windscreen at helm eye height. All four certified: `white_light_height`
##        is a `white_above_sidelights` rule and compares the white light's cell
##        against the SIDELIGHTS' cells only — it cannot see the superstructure,
##        so it is satisfiable by a light invisible from ahead. That is a
##        compliance defect in `VesselCompliance._white_height_delta`, recorded
##        here because this unit is the mechanism that CAN see the house.

## ── THE MUTATION TABLE, 2026-08-15 (REALITY.md standing order 1) ────────────
##
## Every check below was shown RED against a deliberately broken generator, both
## numbers recorded. Each mutation is one edit to `tests/_prebuilt_gen.gd`,
## regenerated through `_emit` (so the vessel still had to CERTIFY) and re-run.
##
##   M1  flat lid instead of the hipped cap
##       roof fall 0.5000 -> 0.0000 m on all four            **4 / 91**
##   M2  every glazed run drawn as punched squares
##       pane 1.340 x 0.340 aspect 3.94 -> 0.340 x 0.340 aspect 1.00;
##       wide glass 89.3% (sjark) / 67.0% (28 m) -> 0.0%,
##       front and after face alike                          **16 / 91**
##   M3  wheelhouse side band back to three cells
##       sjark side span 63.1% -> 29.8% on both side checks; the coasters stay
##       green because their port-most glass is the accommodation row, which the
##       mutation never touches — which is why §6 is two checks   **2 / 91**
##   M4  after face back to two punched squares beside the door
##       after pane aspect 3.94 -> 1.00, after wide glass -> 0.0% **8 / 91**
##   M5  mast deck-stepped, sidelights left under the eaves
##       `_emit` REFUSED all four: `white_light_height` reports -7.0 / -1.0,
##       so this variant cannot be generated at all any more. That is the rule
##       working — and only because the two-tier house lifted the sidelights to
##       5.0 m. It says nothing about the rule's soundness; see M5b.
##   M5b the arrangement that ACTUALLY SHIPPED — sidelights back down on the
##       lower tier AND the mast deck-stepped forward of the house
##       `white_light_height` reports **ok, current=1.0** on all four and the
##       preset is written; masthead clearance +1.51 -> -1.49 m (sjark) and
##       -4.49 m (28 m), and 0 -> 4 / 28 fit-out triangles standing in the
##       helmsman's forward sightline                        **8 / 91**
##   M6  brow removed
##       brow proud 0.5000 -> 0.0000 m on all four            **4 / 91**
##   M7  the absolute 3.0 x 4.0 m box back on every hull
##       `GEN OK`, `white_light_height ok`, and every other check here still
##       green: beam fraction 80.0% -> 30.0%, LOA fraction 28.6% -> 16.1% on the
##       three 28 m presets, sjark untouched at 60.0% / 30.0%   **6 / 91**
##
## M5b and M7 are the two that matter most, because in both the vessel CERTIFIES.
## Compliance cannot see a house at all.

const TestReport := preload("res://tests/support/test_report.gd")

const CELL := 0.5

## Every preset that carries a wheelhouse. Run over ALL of them, not the one
## being worked on (REALITY.md §3c) — the same generator draws all four, and the
## 28 m boats are the ones nobody looks at.
const PRESETS := ["fishing_trawler", "28_10_m", "bulk_small"]

## ── The thresholds, and the argument for each ───────────────────────────────
##
## Every one is a floor on a shape, not a restatement of a dimension. The
## measured value on the shipped house and on the mutation each guards are in
## the section comments.

## §1. How far the roof falls from its inboard high point to the house's outer
## perimeter. A flat lid measures EXACTLY 0.0 — it is as tall at its edge as in
## its middle. 0.20 m over the 1.5 m half-span of a 3 m house is a 7.6° pitch,
## which is about the shallowest fall that still reads as a roof rather than as
## a slab with a tolerance. The hipped cap measures 0.5000.
const MIN_ROOF_FALL_M := 0.20

## §2a. The widest uninterrupted pane on the forward face, as a multiple of its
## own height. This is the difference between a windscreen and a grid of punched
## squares, and it is scale-free: it does not care how big the house is. A cell
## of `block_window` is a 0.34 x 0.34 m square — aspect 1.00, by construction,
## at any cell size. The `block_windshield` band measures 3.94.
const MIN_PANE_ASPECT := 2.0

## §2b. The WIDE GLASS on the best row — every pane at least `MIN_PANE_ASPECT`
## times as wide as it is tall, summed — as a fraction of the house's own beam.
## "Glazed ACROSS the front" rather than "has a wide window somewhere", and it
## says nothing about how the glass is divided, which is what makes it scale
## with the house: a windscreen is four 1.34 m panes on a 6 m wheelhouse and two
## on a 3 m one, and a pane does not grow with the ship in real life either.
##
## This replaced "the widest single pane spans >= 25% of the front", which is the
## same 25% pointed at one pane. That formulation cannot survive a house wider
## than four panes and it reddened on the new wheelhouse at 16.8%. Measured on
## both sides of every mutation in the header: sjark 89.3%, 28 m 67.0%, punched
## squares 0.0%, a lone windshield on an 8 m front 16.8%.
const MIN_WIDE_GLASS_FRACTION := 0.25

## §2c. Total glazed width on the best row, as a fraction of the house's beam.
## This one does NOT separate a windscreen from punched panes — 89.3% against
## 68.0%, and it is honest to say so. It guards a different regression: a house
## that loses its window band altogether, or falls back to the three slits the
## pre-2026-08-15 shoebox had. Verified by mutation, separately from §2a/§2b.
const MIN_GLAZED_FRACTION := 0.50

## §3. How far the top of the house stands proud of its base. The instrument's
## own noise here is 0.020 m — a window frame stands that far out of the wall
## plane it is set into, measured — so this floor is 7.5x the noise and less
## than a third of the 0.5 m cantilever it is holding. Shipped 0.500; a house
## with the brow removed measures 0.000.
const MIN_BROW_PROUD_M := 0.15

## §6. How much of the house's LENGTH the side glazing reaches across, first
## pane to last. Not "how much glass" — where it stops. The band used to be a
## single `block_windshield` three cells into an eight-cell house, so the after
## two thirds of both sides was a blank 2.5 m white field in every profile frame
## (STATE.md 5i). Measured on the outer tier: sjark 63.1%, 28 m 79.2%; and on the
## wheelhouse's own side, sjark 63.1% (one tier, so the same wall) and 28 m
## 92.0%. Reverting the band to three cells takes both sjark numbers to 29.8%
## and leaves the coasters green, because their port-most glass is the
## accommodation row — which is why there are two checks and not one.
const MIN_SIDE_GLASS_SPAN_FRACTION := 0.50

## §8. The house belongs to the hull it stands on. This is the headline defect
## of STATE.md 5i: `_add_deckhouse(…, 6, 8, …)` drew one absolute 3.0 x 4.0 m box
## 2.5 m to the eaves on a 15 m sjark and on a 28 m coaster alike — 60% of the
## beam on the first, where it reads as a wheelhouse, and 30% on the second,
## where it reads as a portacabin on a barge. Every other check here passes on
## that box, because at its own scale it is a perfectly good little wheelhouse:
## the roof falls, the front is glazed, the brow stands proud. Only its RELATION
## to the hull is wrong, so only a relation catches it.
##
## Measured: sjark 60.0% of beam / 30.0% of LOA; the 28 m presets 80.0% / 28.6%;
## the absolute box on hull_28x10 30.0% / 16.1%.
const MIN_HOUSE_BEAM_FRACTION := 0.45
const MIN_HOUSE_LOA_FRACTION := 0.22

## §7. The masthead light must stand clear ABOVE the house it is seen over, not
## merely above the sidelights, which is all `white_light_height` asks. This is
## a floor on the clearance, not on the height — a fifth of what the shipped mast
## actually clears by, so it holds the SIGN of the difference without restating
## the mast. Measured +1.51 m on all four presets. With the sidelights back on
## the lower tier and the mast deck-stepped, which is the arrangement that
## SHIPPED, it is -1.49 m on the sjark and -4.49 m on the three 28 m presets —
## and `white_light_height` reports `ok, current=1.0` for all four while it does.
const MIN_MASTHEAD_ABOVE_ROOF_M := 0.30

var _t := TestReport.new("deckhouse_shape_test")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	await _check_the_boat_a_new_captain_is_given()
	for preset in PRESETS:
		await _check_preset(preset)
	await _check_the_merged_skin_draws_the_same_house()
	_t.finish(get_tree())


# ── 1 · the starter, through onboarding's own spawn path ────────────────────

func _check_the_boat_a_new_captain_is_given() -> void:
	## Not the catalogue entry: the record onboarding actually hands over. The
	## wheelhouse a player sees on their first boat is the subject of the commit
	## this unit exists for.
	var record := CompanyService.build_starter_vessel_record(CompanyContracts.DEFAULT_STARTER)
	if not _t.check("onboarding hands over a starter vessel record", not record.is_empty()):
		return
	var boat := VesselSpawn.instantiate_from_record(record)
	if not _t.check("the granted record spawns", boat != null):
		return
	boat.name = "GrantedStarter"
	boat.automatic_physics_lod = false
	boat.freeze = true
	add_child(boat)
	await get_tree().process_frame
	var hull_id := str(record.get("hull_id", ""))
	_assert_house(
		"the boat a new captain is given",
		boat,
		BrickLayout.from_dict(VesselSpawn.brick_layout_of(record)),
		HullRegistry.make_grid(hull_id),
	)
	boat.free()
	await get_tree().process_frame


# ── 2 · every other shipped preset carries the same wheelhouse ──────────────

func _check_preset(prebuilt_id: String) -> void:
	var entry := {}
	for candidate in PrebuiltVesselCatalog.catalog_entries():
		if str(candidate.get("prebuilt_id", "")) == prebuilt_id:
			entry = candidate
			break
	if not _t.check("the preset '%s' is in the catalogue" % prebuilt_id, not entry.is_empty()):
		return
	var hull_id := str(entry.get("hull_id", ""))
	var layout_dict := (entry.get("prebuilt_layout", {}) as Dictionary).duplicate(true)
	var boat := VesselSpawn.instantiate(
		hull_id, layout_dict, str(entry.get("registration_id", ""))
	)
	if not _t.check("'%s' spawns" % prebuilt_id, boat != null):
		return
	boat.name = "Preset_" + prebuilt_id
	boat.automatic_physics_lod = false
	boat.freeze = true
	add_child(boat)
	await get_tree().process_frame
	_assert_house(
		prebuilt_id, boat, BrickLayout.from_dict(layout_dict), HullRegistry.make_grid(hull_id)
	)
	boat.free()
	await get_tree().process_frame


# ── 3 · the seven properties ────────────────────────────────────────────────

func _assert_house(
	label: String, boat: Node3D, layout: BrickLayout, grid: DeckGrid
) -> Dictionary:
	var shape := measure(boat, layout, grid)
	if not _t.check(
		"%s — the fit-out draws a deckhouse to measure (%d triangles inside its plan)"
		% [label, int(shape.get("tri_n", 0))],
		int(shape.get("tri_n", 0)) > 0,
	):
		return shape

	## §1 — THE ROOF IS NOT A FLAT LID.
	## A roof that is lower at its own outer edge than it is inboard has a fall in
	## it, whichever way it is drawn — hipped, gabled, cambered, monopitch. A flat
	## slab is the same height everywhere and measures exactly zero. "Its own"
	## matters on a tiered house: the perimeter sampled is the plan at the ROOF
	## LEVEL, not the bounds of every roof-tagged cell, which on a two-tier house
	## is the boat deck 1.0 m outboard of the cap (see the header).
	_t.check(
		"%s — the roof falls %.4f m from inboard to the cap's own perimeter (>= %.2f)"
		% [label, float(shape["roof_fall_m"]), MIN_ROOF_FALL_M],
		float(shape["roof_fall_m"]) >= MIN_ROOF_FALL_M,
	)

	## §2 — THE FRONT IS GLAZED AS A BAND, NOT PUNCHED WITH SQUARES.
	if _t.check(
		"%s — there is glass on the forward face at all" % label,
		bool(shape.get("has_front_glass", false)),
	):
		_t.check(
			"%s — its widest uninterrupted pane is %.2fx as wide as it is tall (%.3f x %.3f m, >= %.1fx)"
			% [
				label, float(shape["pane_aspect"]), float(shape["pane_w_m"]),
				float(shape["pane_h_m"]), MIN_PANE_ASPECT,
			],
			float(shape["pane_aspect"]) >= MIN_PANE_ASPECT,
		)
		_t.check(
			"%s — wide glass covers %.1f%% of the %.2f m front (%.2f m of panes >= %.1fx wide, >= %.0f%%)"
			% [
				label, 100.0 * float(shape["wide_glass_fraction"]), float(shape["house_w_m"]),
				float(shape["wide_glass_w_m"]), MIN_PANE_ASPECT,
				100.0 * MIN_WIDE_GLASS_FRACTION,
			],
			float(shape["wide_glass_fraction"]) >= MIN_WIDE_GLASS_FRACTION,
		)
		_t.check(
			"%s — the front is glazed over %.1f%% of its width (>= %.0f%%)"
			% [
				label, 100.0 * float(shape["glazed_fraction"]),
				100.0 * MIN_GLAZED_FRACTION,
			],
			float(shape["glazed_fraction"]) >= MIN_GLAZED_FRACTION,
		)

	## §3 — THE BROW STANDS PROUD OF THE WALL BELOW IT.
	## The top of the house reaches further forward than its base does, so the
	## front breaks forward at the top instead of standing as one plumb plane.
	_t.check(
		"%s — the top of the house stands %.4f m proud of its base (>= %.2f); forward-most z by level: %s"
		% [
			label, float(shape["brow_proud_m"]), MIN_BROW_PROUD_M,
			str(shape.get("level_front_z", [])),
		],
		float(shape["brow_proud_m"]) >= MIN_BROW_PROUD_M,
	)

	## §8 — THE HOUSE IS SIZED TO ITS HULL, NOT TO A CONSTANT.
	_t.check(
		"%s — the house spans %.1f%% of the %.2f m beam (%.2f m, >= %.0f%%)"
		% [
			label, 100.0 * float(shape["house_beam_fraction"]),
			float(shape["vessel_beam_m"]), float(shape["house_w_m"]),
			100.0 * MIN_HOUSE_BEAM_FRACTION,
		],
		float(shape["house_beam_fraction"]) >= MIN_HOUSE_BEAM_FRACTION,
	)
	_t.check(
		"%s — the house spans %.1f%% of the %.2f m LOA (%.2f m, >= %.0f%%)"
		% [
			label, 100.0 * float(shape["house_loa_fraction"]),
			float(shape["vessel_loa_m"]), float(shape["house_l_m"]),
			100.0 * MIN_HOUSE_LOA_FRACTION,
		],
		float(shape["house_loa_fraction"]) >= MIN_HOUSE_LOA_FRACTION,
	)

	## §5 — THE AFTER FACE IS A WHEELHOUSE FACE, NOT A GABLE END.
	## Same instrument as §2, aimed astern at the top tier: a wheelhouse looks aft
	## over its own working deck and is glazed doing it. The face this measures is
	## the one a captain walks up to, and it was two 0.34 m punched squares beside
	## a domestic door with a hipped cap over it, which is a cottage gable.
	if _t.check(
		"%s — there is glass on the wheelhouse's after face at all" % label,
		bool(shape.get("has_aft_glass", false)),
	):
		_t.check(
			"%s — its widest after pane is %.2fx as wide as it is tall (%.3f x %.3f m, >= %.1fx)"
			% [
				label, float(shape["aft_pane_aspect"]), float(shape["aft_pane_w_m"]),
				float(shape["aft_pane_h_m"]), MIN_PANE_ASPECT,
			],
			float(shape["aft_pane_aspect"]) >= MIN_PANE_ASPECT,
		)
		_t.check(
			"%s — wide glass covers %.1f%% of the %.2f m after face (>= %.0f%%)"
			% [
				label, 100.0 * float(shape["aft_wide_glass_fraction"]),
				float(shape["house_w_m"]), 100.0 * MIN_WIDE_GLASS_FRACTION,
			],
			float(shape["aft_wide_glass_fraction"]) >= MIN_WIDE_GLASS_FRACTION,
		)

	## §6 — THE SIDE IS NOT A BLANK FIELD.
	## Where the glazing STOPS, not how much of it there is: first pane to last,
	## along the house's own length. A band that dies three cells in leaves the
	## after two thirds of the profile as one white rectangle, which is the single
	## loudest thing in a beam-on frame.
	_t.check(
		"%s — side glazing reaches over %.1f%% of the %.2f m house length (%.2f m, first pane to last, >= %.0f%%)"
		% [
			label, 100.0 * float(shape["side_glass_span_fraction"]),
			float(shape["house_l_m"]), float(shape["side_glass_span_m"]),
			100.0 * MIN_SIDE_GLASS_SPAN_FRACTION,
		],
		float(shape["side_glass_span_fraction"]) >= MIN_SIDE_GLASS_SPAN_FRACTION,
	)

	_t.check(
		"%s — the wheelhouse's own side glazing reaches over %.1f%% of its %.2f m length (%.2f m, >= %.0f%%)"
		% [
			label, 100.0 * float(shape["cap_side_glass_span_fraction"]),
			float(shape["cap_l_m"]), float(shape["cap_side_glass_span_m"]),
			100.0 * MIN_SIDE_GLASS_SPAN_FRACTION,
		],
		float(shape["cap_side_glass_span_fraction"]) >= MIN_SIDE_GLASS_SPAN_FRACTION,
	)

	## §7 — THE MASTHEAD LIGHT IS ABOVE THE HOUSE, AND OUT OF THE HELMSMAN'S EYE.
	## `white_light_height` asks only that the white light's cell is higher than
	## the sidelights' cells, and the sidelights are on the wheelhouse walls at
	## 1.25 m — so a lantern 1.75 m up on a deck-stepped mast, standing 4.25 m
	## BELOW the roof it is meant to be seen over and dead in the middle of the
	## windscreen, certified on all three 28 m presets. Both halves are checked:
	## the light stands clear above the drawn roof, and nothing at all is drawn in
	## the box forward of the windscreen at windscreen height.
	if _t.check(
		"%s — the fit-out draws a masthead (all-round white) light" % label,
		bool(shape.get("has_masthead", false)),
	):
		_t.check(
			"%s — the masthead light stands %.2f m above the roof (lantern base %.2f m, roof top %.2f m, >= %.2f)"
			% [
				label, float(shape["masthead_above_roof_m"]),
				float(shape["masthead_y_m"]), float(shape["roof_top_y_m"]),
				MIN_MASTHEAD_ABOVE_ROOF_M,
			],
			float(shape["masthead_above_roof_m"]) >= MIN_MASTHEAD_ABOVE_ROOF_M,
		)
	_t.check(
		"%s — nothing is drawn in the helmsman's forward sightline (%d fit-out triangles in the %.2f m x %.2f m box ahead of the windscreen)"
		% [
			label, int(shape.get("sightline_tri_n", -1)),
			float(shape.get("sightline_w_m", 0.0)), float(shape.get("sightline_h_m", 0.0)),
		],
		int(shape.get("sightline_tri_n", -1)) == 0,
	)
	return shape


# ── 4 · the merged skin draws the same house as the unmerged one ────────────

func _check_the_merged_skin_draws_the_same_house() -> void:
	## Everything above is measured with `skin_enabled` at its shipping value, so
	## this is not a licence to assert elsewhere — it is the check that the layer
	## above is honest. If the merger ever stops preserving the shape it bakes,
	## this reddens, and that is a much larger finding than a deckhouse.
	var entry := {}
	for candidate in PrebuiltVesselCatalog.catalog_entries():
		if str(candidate.get("prebuilt_id", "")) == "sjark_15m":
			entry = candidate
			break
	if not _t.check("the starter preset is in the catalogue", not entry.is_empty()):
		return
	var hull_id := str(entry.get("hull_id", ""))
	var layout_dict := (entry.get("prebuilt_layout", {}) as Dictionary).duplicate(true)
	var grid := HullRegistry.make_grid(hull_id)
	var layout := BrickLayout.from_dict(layout_dict)
	var shapes := {}
	for merged in [true, false]:
		var previous := DeckFitout.skin_enabled
		DeckFitout.skin_enabled = merged
		var boat := VesselSpawn.instantiate(
			hull_id, layout_dict.duplicate(true), str(entry.get("registration_id", ""))
		)
		DeckFitout.skin_enabled = previous
		if not _t.check("the starter spawns with skin_enabled=%s" % merged, boat != null):
			return
		boat.name = "SkinParity_%s" % merged
		boat.automatic_physics_lod = false
		boat.freeze = true
		add_child(boat)
		await get_tree().process_frame
		shapes[merged] = measure(boat, layout, grid)
		boat.free()
		await get_tree().process_frame

	var merged_shape: Dictionary = shapes[true]
	var loose_shape: Dictionary = shapes[false]
	## The merger's whole job is to draw fewer triangles. If these were equal the
	## comparison below would be comparing a configuration with itself (§4).
	_t.check(
		"the merger is actually doing something — %d triangles inside the house plan against %d unmerged"
		% [int(merged_shape["tri_n"]), int(loose_shape["tri_n"])],
		int(merged_shape["tri_n"]) < int(loose_shape["tri_n"]),
	)
	## Every number any check above reads, including the two added in 2026-08-15's
	## house change: `side_glass_span_fraction` because the side band is the face
	## the merger has most to lose on, and `masthead_above_roof_m` because that one
	## is measured off a LIVE NODE the merger is supposed to leave alone — if the
	## baker ever starts swallowing "light"-tagged bricks, this is where it shows.
	for key in [
		"roof_fall_m", "pane_w_m", "pane_h_m", "wide_glass_fraction", "glazed_fraction",
		"aft_pane_aspect", "aft_wide_glass_fraction", "side_glass_span_fraction",
		"cap_side_glass_span_fraction",
		"masthead_above_roof_m", "brow_proud_m",
	]:
		_t.near(
			"the merged skin draws the same '%s' as the unmerged fit-out" % key,
			float(merged_shape.get(key, -1.0)), float(loose_shape.get(key, -2.0)), 0.0005,
		)


# ── the instrument ──────────────────────────────────────────────────────────
#
# Public so a probe can drive it against a mutated tree without a second
# derivation of any of it (REALITY.md §3b).

## Which component of a Vector3 a face is measured ALONG. A fore/aft face is a
## plane of constant z rasterised across x; a side face is a plane of constant x
## rasterised along z. One function serves all three (REALITY.md §3b).
const AXIS_X := 0
const AXIS_Z := 2

## The occupancy bin the glazing is rasterised onto, in metres.
const GLASS_BIN := 0.01


static func measure(boat: Node3D, layout: BrickLayout, grid: DeckGrid) -> Dictionary:
	var house := _house_bounds(layout, grid)
	if int(house["roof_y"]) < 0:
		return {"tri_n": 0}
	var all_tris := _collect(boat)
	var tris := _in_house(all_tris, house)
	var house_w := float(house["x_max"]) - float(house["x_min"])
	var house_l := float(house["z_max"]) - float(house["z_min"])
	var out := {
		"tri_n": (tris["tri"] as Array).size(),
		"house_w_m": house_w,
		"house_l_m": house_l,
		"vessel_beam_m": grid.half_beam * 2.0,
		"vessel_loa_m": grid.half_loa * 2.0,
		"house_beam_fraction": house_w / maxf(grid.half_beam * 2.0, 0.001),
		"house_loa_fraction": house_l / maxf(grid.half_loa * 2.0, 0.001),
	}
	out.merge(_roof(tris, house))

	## The forward face: the foremost glass anywhere on the house.
	var front := _face_glass(
		tris, AXIS_Z, false, -1e9, float(house["x_min"]), house_w
	)
	out["has_front_glass"] = bool(front["found"])
	for key in ["pane_w_m", "pane_h_m", "pane_aspect", "wide_glass_w_m",
			"wide_glass_fraction", "glazed_fraction"]:
		out[key] = front[key]

	## The after face OF THE TOP TIER. Taking the aftmost glass on the whole house
	## would measure the accommodation block's windows on a two-tier house and the
	## wheelhouse's on a one-tier one — two different claims wearing one name. The
	## cap's own z bound is where the wheelhouse ends, so that is the limit.
	var aft := _face_glass(
		tris, AXIS_Z, true, float(house["cap_z_max"]), float(house["x_min"]), house_w
	)
	out["has_aft_glass"] = bool(aft["found"])
	out["aft_pane_w_m"] = aft["pane_w_m"]
	out["aft_pane_h_m"] = aft["pane_h_m"]
	out["aft_pane_aspect"] = aft["pane_aspect"]
	out["aft_wide_glass_fraction"] = aft["wide_glass_fraction"]

	## The port face, over the whole house — the outermost tier is the one that
	## fills a beam-on frame, and it is the one that was blank.
	var side := _face_glass(
		tris, AXIS_X, false, -1e9, float(house["z_min"]), house_l
	)
	out["side_glass_span_m"] = side["span_m"]
	out["side_glass_span_fraction"] = side["span_fraction"]

	## And the WHEELHOUSE's own side, which on a two-tier house is a different
	## wall a metre inboard of that one. Measured only on the outer tier, reverting
	## the wheelhouse band to the three cells it used to be reddens the sjark and
	## nothing else — the coasters' port-most glass is the accommodation row, which
	## the mutation never touches. Two faces, two checks.
	var cap_side := _face_glass(
		tris, AXIS_X, false, float(house["cap_x_min"]),
		float(house["cap_z_min"]), float(house["cap_z_max"]) - float(house["cap_z_min"])
	)
	out["cap_l_m"] = float(house["cap_z_max"]) - float(house["cap_z_min"])
	out["cap_side_glass_span_m"] = cap_side["span_m"]
	out["cap_side_glass_span_fraction"] = cap_side["span_fraction"]

	out.merge(_brow(tris, house))
	out.merge(_masthead(
		boat, layout, grid,
		float(house["y_roof0"]) + float(out.get("roof_inner_top_m", 0.0))
	))
	out.merge(_sightline(all_tris, house, front))
	return out


## The house's plan and roof level, taken from the bounds of every cell whose
## brick carries the catalogue's "roof" tag. This is ADDRESSING, not the
## assertion: it says where to look, and every check above is then made against
## the geometry found there. A cap re-drawn with different roof bricks is found
## the same way; a house with no roof at all returns roof_y = -1 and fails the
## "there is a deckhouse to measure" check rather than passing vacuously.
##
## TWO plans come back, and the difference is the 2026-08-15 tiered house. The
## OUTER plan is every roof-tagged cell — on a two-tier house that is the boat
## deck, 8.0 m across, and it is the right bound for "how wide is this house"
## and for finding the side that faces a beam-on camera. The CAP plan is the
## roof level alone — 6.0 m across, standing 1.0 m inboard of the boat deck —
## and it is the right bound for anything about the wheelhouse: the roof's own
## fall (§1), the after face that belongs to it (§5), the sightline out of it.
## Using the outer plan for §1 left the fall sampled only where the cap happens
## to reach it, which is its forward edge over the brow.
static func _house_bounds(layout: BrickLayout, grid: DeckGrid) -> Dictionary:
	var ix0 := 1 << 30
	var ix1 := -(1 << 30)
	var iz0 := 1 << 30
	var iz1 := -(1 << 30)
	var roof_y := -1
	var roof_cells: Array[Vector3i] = []
	for item in layout.iter_primary_cells():
		if not BrickCatalog.has_tag(str(item.get("brick_id", "")), "roof"):
			continue
		var c: Vector3i = item["cell"]
		roof_cells.append(c)
		ix0 = mini(ix0, c.x)
		ix1 = maxi(ix1, c.x)
		iz0 = mini(iz0, c.z)
		iz1 = maxi(iz1, c.z)
		roof_y = maxi(roof_y, c.y)
	if roof_y < 0:
		return {"roof_y": -1}
	var cx0 := 1 << 30
	var cx1 := -(1 << 30)
	var cz0 := 1 << 30
	var cz1 := -(1 << 30)
	for c in roof_cells:
		if c.y != roof_y:
			continue
		cx0 = mini(cx0, c.x)
		cx1 = maxi(cx1, c.x)
		cz0 = mini(cz0, c.z)
		cz1 = maxi(cz1, c.z)
	return {
		"roof_y": roof_y,
		"x_min": -grid.half_beam + float(ix0) * CELL,
		"x_max": -grid.half_beam + float(ix1 + 1) * CELL,
		"z_min": -grid.half_loa + float(iz0) * CELL,
		"z_max": -grid.half_loa + float(iz1 + 1) * CELL,
		"cap_x_min": -grid.half_beam + float(cx0) * CELL,
		"cap_x_max": -grid.half_beam + float(cx1 + 1) * CELL,
		"cap_z_min": -grid.half_loa + float(cz0) * CELL,
		"cap_z_max": -grid.half_loa + float(cz1 + 1) * CELL,
		"y_roof0": grid.deck_y + float(roof_y) * CELL,
		"y_roof1": grid.deck_y + float(roof_y + 1) * CELL,
		"deck_y": grid.deck_y,
	}


## Every triangle the FIT-OUT draws, in boat-local metres, with a glass flag.
##
## The hull's own meshes are excluded deliberately: the deck plate spans the
## whole vessel, so it is present at every (x, z) inside the house plan and
## would answer "how far forward does the house reach" with the plan's own
## bounds at every level.
##
## Glass is identified by its MATERIAL — an albedo alpha below 1 — not by the
## brick that drew it. That is what survives the merge: `_merge_generic_brick`
## buckets by material, so every pane on the vessel lands in one mesh and no
## per-brick node is needed to tell glass from cladding.
static func _collect(boat: Node3D) -> Dictionary:
	var out_tri: Array = []
	var out_glass: Array = []
	var root := boat.get_node_or_null("DeckFitout")
	if root == null:
		return {"tri": out_tri, "glass": out_glass}
	var to_boat := boat.global_transform.affine_inverse()
	var stack: Array = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.append(child)
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var xform := to_boat * mi.global_transform
		for s in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(s)
			var is_glass := (
				mat is StandardMaterial3D
				and (mat as StandardMaterial3D).albedo_color.a < 0.999
			)
			var arrays := mi.mesh.surface_get_arrays(s)
			if arrays.size() <= Mesh.ARRAY_VERTEX or arrays[Mesh.ARRAY_VERTEX] == null:
				continue
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var idx := PackedInt32Array()
			if arrays.size() > Mesh.ARRAY_INDEX and arrays[Mesh.ARRAY_INDEX] != null:
				idx = arrays[Mesh.ARRAY_INDEX]
			if idx.is_empty():
				idx = PackedInt32Array(range(verts.size()))
			var i := 0
			while i + 2 < idx.size():
				out_tri.append([
					xform * verts[idx[i]], xform * verts[idx[i + 1]], xform * verts[idx[i + 2]],
				])
				out_glass.append(is_glass)
				i += 3
	return {"tri": out_tri, "glass": out_glass}


## Triangles inside the house's plan footprint and above the deck, each carried
## with its own AABB so a level is a BAND INTERSECTION rather than a vertex test.
## That distinction is not pedantry: a `block` fills its cell exactly, so all of
## its vertices sit ON the level planes and a vertex-in-band filter reads a solid
## wall as an empty level. The first version of this instrument did exactly that
## and reported the wheelhouse's forward face as 0.5 m ABAFT where it is drawn.
static func _in_house(all_tris: Dictionary, h: Dictionary) -> Dictionary:
	var tri: Array = []
	var mins: Array = []
	var maxs: Array = []
	var glass: Array = []
	var src: Array = all_tris["tri"]
	var src_glass: Array = all_tris["glass"]
	for i in src.size():
		var t: Array = src[i]
		var mn := Vector3(1e9, 1e9, 1e9)
		var mx := Vector3(-1e9, -1e9, -1e9)
		for p_variant in t:
			var p: Vector3 = p_variant
			mn = Vector3(minf(mn.x, p.x), minf(mn.y, p.y), minf(mn.z, p.z))
			mx = Vector3(maxf(mx.x, p.x), maxf(mx.y, p.y), maxf(mx.z, p.z))
		if mx.y < float(h["deck_y"]) - 0.01:
			continue
		if mn.x < float(h["x_min"]) - 0.05 or mx.x > float(h["x_max"]) + 0.05:
			continue
		if mn.z < float(h["z_min"]) - 0.05 or mx.z > float(h["z_max"]) + 0.05:
			continue
		tri.append(t)
		mins.append(mn)
		maxs.append(mx)
		glass.append(src_glass[i])
	return {"tri": tri, "min": mins, "max": maxs, "glass": glass}


## §1's measurement. Inside the roof level's own 0.5 m band, how high does the
## drawn surface stand at the CAP's outer perimeter, and how high inboard?
##
## The perimeter is the cap's own plan, not the house's (see `_house_bounds`).
## On the one-tier sjark the two are the same rectangle and this changes nothing;
## on a two-tier house the cap stands a tier-inset inboard of the boat deck, and
## measuring `inset` from the boat deck's bounds means no cap vertex is ever
## within 0.02 m of them except where the brow reaches forward — so three of the
## four falls were unsampled.
static func _roof(tris: Dictionary, h: Dictionary) -> Dictionary:
	var y0: float = h["y_roof0"]
	var y1: float = h["y_roof1"]
	var edge_top := y0
	var inner_top := y0
	for t in tris["tri"] as Array:
		for p_variant in t as Array:
			var p: Vector3 = p_variant
			if p.y < y0 - 0.02 or p.y > y1 + 0.02:
				continue
			var inset: float = minf(
				minf(p.x - float(h["cap_x_min"]), float(h["cap_x_max"]) - p.x),
				minf(p.z - float(h["cap_z_min"]), float(h["cap_z_max"]) - p.z),
			)
			if absf(inset) <= 0.02:
				edge_top = maxf(edge_top, p.y)
			if inset >= CELL - 0.05:
				inner_top = maxf(inner_top, p.y)
	return {
		"roof_edge_top_m": edge_top - y0,
		"roof_inner_top_m": inner_top - y0,
		"roof_fall_m": inner_top - edge_top,
	}


## §2, §5 and §6's shared measurement: ONE face of the house, rasterised onto a
## 1 cm occupancy grid, so a merged mesh holding every pane in one surface and a
## tree of per-brick nodes are read by the same code. Panes are axis-aligned
## quads, so a triangle's AABB IS its footprint on that plane.
##
##   `axis`      AXIS_Z for a fore/aft face (rasterised across x), AXIS_X for a
##               side face (rasterised along z).
##   `take_max`  false picks the LOWEST plane on that axis (forward face, port
##               side), true picks the HIGHEST (after face).
##   `limit`     ignore glass beyond this plane coordinate before choosing the
##               extreme. −1e9 / +1e9 means "the whole house"; §5 passes the
##               cap's own z so the after face it finds is the wheelhouse's.
##
## What comes back, and which check reads which:
##   pane_w/h/aspect        the widest uninterrupted run and the tallest block of
##                          rows fully covering it            (§2a, §5)
##   wide_glass_w/fraction  on the best row, the total width of runs at least
##                          `MIN_PANE_ASPECT` as wide as they are tall (§2b, §5)
##   glazed_fraction        the most-glazed row's total width  (§2c)
##   span_m/span_fraction   first pane to last, along the face (§6)
static func _face_glass(
	tris: Dictionary, axis: int, take_max: bool, limit: float,
	face_origin: float, face_w: float
) -> Dictionary:
	var glass: Array = tris["glass"]
	var mins: Array = tris["min"]
	var maxs: Array = tris["max"]
	var none := {
		"found": false, "pane_w_m": 0.0, "pane_h_m": 0.0, "pane_aspect": 0.0,
		"wide_glass_w_m": 0.0, "wide_glass_fraction": 0.0, "glazed_fraction": 0.0,
		"span_m": 0.0, "span_fraction": 0.0, "y_lo": 0.0, "y_hi": 0.0, "plane": 0.0,
	}
	if face_w <= 0.0:
		return none
	var plane := -1e9 if take_max else 1e9
	for i in glass.size():
		if not bool(glass[i]) or not _faces(mins[i], maxs[i], axis):
			continue
		var lo := _axis_of(mins[i], axis)
		var hi := _axis_of(maxs[i], axis)
		if take_max:
			if hi > limit + 0.05:
				continue
			plane = maxf(plane, hi)
		else:
			if lo < limit - 0.05:
				continue
			plane = minf(plane, lo)
	if absf(plane) > 1e8:
		return none
	## One face is a 0.05 m slice — the pane's own 0.04 m thickness and nothing
	## more. It was 0.10, which is still less than the half-cell to the next run
	## of glazing and still looked safe, and it quietly swallowed the EDGE of the
	## pane on the face round the corner: the forward windscreen's glass is set
	## 0.08 m inboard of the house's port bound, so its port edge — a 0.04 x 0.34 m
	## sliver — landed in the port face's own slice and dragged the sjark's side
	## span from 63.1% to 88.9%. Two slivers, one at each end, and between them
	## they reported a band that reached the full length of a house it did not.
	var sel: Array = []
	var y_lo := 1e9
	var y_hi := -1e9
	for i in glass.size():
		if not bool(glass[i]) or not _faces(mins[i], maxs[i], axis):
			continue
		var lo := _axis_of(mins[i], axis)
		var hi := _axis_of(maxs[i], axis)
		if take_max:
			if hi < plane - 0.05:
				continue
		elif lo > plane + 0.05:
			continue
		sel.append(i)
		y_lo = minf(y_lo, (mins[i] as Vector3).y)
		y_hi = maxf(y_hi, (maxs[i] as Vector3).y)
	if sel.is_empty():
		return none
	var u_axis := AXIS_X if axis == AXIS_Z else AXIS_Z
	var nx := int(ceil(face_w / GLASS_BIN)) + 2
	var ny := int(ceil((y_hi - y_lo) / GLASS_BIN)) + 2
	var occ := PackedByteArray()
	occ.resize(nx * ny)
	for i in sel:
		var mn: Vector3 = mins[i]
		var mx: Vector3 = maxs[i]
		var cx0 := clampi(int(round((_axis_of(mn, u_axis) - face_origin) / GLASS_BIN)), 0, nx - 1)
		var cx1 := clampi(int(round((_axis_of(mx, u_axis) - face_origin) / GLASS_BIN)), 0, nx)
		var cy0 := clampi(int(round((mn.y - y_lo) / GLASS_BIN)), 0, ny - 1)
		var cy1 := clampi(int(round((mx.y - y_lo) / GLASS_BIN)), 0, ny)
		for r in range(cy0, cy1):
			for c in range(cx0, cx1):
				occ[r * nx + c] = 1

	## Every maximal horizontal run, bucketed by (start, width) so its HEIGHT is
	## solved once per distinct pane rather than once per row. The height that
	## matters is the tallest CONTIGUOUS block of rows covering the whole run:
	## counting every occupied row instead adds the second row of a two-row band
	## to the first pane's height, which turned a 3.94 aspect into 1.97 — a hair
	## above the 2.0 floor it feeds. Caught by predicting the number before
	## reading it (REALITY.md §8).
	var rows_of := {}
	var runs_in_row: Array = []
	for r in ny:
		var here: Array = []
		var c := 0
		while c < nx:
			if occ[r * nx + c] != 1:
				c += 1
				continue
			var c0 := c
			while c < nx and occ[r * nx + c] == 1:
				c += 1
			here.append([c0, c - c0])
			var key := "%d:%d" % [c0, c - c0]
			if not rows_of.has(key):
				rows_of[key] = PackedInt32Array()
			var rows: PackedInt32Array = rows_of[key]
			rows.append(r)
			rows_of[key] = rows
		runs_in_row.append(here)
	var height_of := {}
	for key in rows_of.keys():
		var rows: PackedInt32Array = rows_of[key]
		var best := 0
		var streak := 0
		var previous := -99
		for r in rows:
			streak = streak + 1 if r == previous + 1 else 1
			previous = r
			best = maxi(best, streak)
		height_of[key] = best

	var pane_w := 0
	var pane_h := 1
	var wide_best := 0
	var glazed_best := 0
	var u_lo := nx
	var u_hi := 0
	for r in ny:
		var wide_here := 0
		var total_here := 0
		for entry in runs_in_row[r] as Array:
			var c0: int = entry[0]
			var w: int = entry[1]
			var key := "%d:%d" % [c0, w]
			var hgt: int = maxi(int(height_of[key]), 1)
			total_here += w
			u_lo = mini(u_lo, c0)
			u_hi = maxi(u_hi, c0 + w)
			if w > pane_w:
				pane_w = w
				pane_h = hgt
			if float(w) / float(hgt) >= MIN_PANE_ASPECT:
				wide_here += w
		wide_best = maxi(wide_best, wide_here)
		glazed_best = maxi(glazed_best, total_here)
	if pane_w <= 0:
		return none
	var span := maxi(u_hi - u_lo, 0)
	return {
		"found": true,
		"pane_w_m": float(pane_w) * GLASS_BIN,
		"pane_h_m": float(pane_h) * GLASS_BIN,
		"pane_aspect": float(pane_w) / float(pane_h),
		"wide_glass_w_m": float(wide_best) * GLASS_BIN,
		"wide_glass_fraction": float(wide_best) * GLASS_BIN / face_w,
		"glazed_fraction": float(glazed_best) * GLASS_BIN / face_w,
		"span_m": float(span) * GLASS_BIN,
		"span_fraction": float(span) * GLASS_BIN / face_w,
		"y_lo": y_lo,
		"y_hi": y_hi,
		"plane": plane,
	}


static func _axis_of(v: Vector3, axis: int) -> float:
	return v.x if axis == AXIS_X else v.z


## Does this triangle belong to a face whose normal runs along `axis`? A pane is
## a flat quad, so the test is its own thickness: a forward-facing pane is 0.02 m
## deep in z and 1.34 m wide in x, and a side pane is the other way round.
##
## Without this, "the port-most glass" also caught the corner pane of the FORWARD
## windscreen, whose minimum x IS the house's port bound on a house one tier
## wide. Rasterised along z that pane is two bins at the very forward end of the
## face and it dragged the sjark's side-glazing span from 63% to 88.9% — a number
## that looked like a comfortable pass and was measuring the wrong wall.
static func _faces(mn: Vector3, mx: Vector3, axis: int) -> bool:
	return _axis_of(mx, axis) - _axis_of(mn, axis) <= 0.05


## §3's measurement. How far forward the house reaches at each of its levels,
## and the step between the level under the roof and the level on the deck.
static func _brow(tris: Dictionary, h: Dictionary) -> Dictionary:
	var deck_y: float = h["deck_y"]
	var mins: Array = tris["min"]
	var maxs: Array = tris["max"]
	var fronts: Array = []
	for level in range(int(h["roof_y"]) + 1):
		var y_mid := deck_y + (float(level) + 0.5) * CELL
		var min_z := 1e9
		for i in mins.size():
			if (mins[i] as Vector3).y > y_mid or (maxs[i] as Vector3).y < y_mid:
				continue
			min_z = minf(min_z, (mins[i] as Vector3).z)
		fronts.append(snappedf(min_z, 0.001) if min_z < 1e8 else INF)
	var base: float = fronts[0] if not fronts.is_empty() else INF
	var top: float = fronts[maxi(fronts.size() - 2, 0)] if fronts.size() >= 2 else INF
	var proud := 0.0
	if is_finite(base) and is_finite(top):
		proud = base - top
	return {"brow_proud_m": proud, "level_front_z": fronts}


## §7's first measurement. The masthead lantern the FIT-OUT DREW, against the
## roof the fit-out drew — not two cell indices out of the layout, which is the
## layer `white_light_height` already asserts at and the layer that certified a
## lantern standing 4.25 m below the wheelhouse.
##
## The light is addressed by TAG (`nav_white`), not by brick id: `light_nav_white`
## and `light_mast_white` are both all-round white lights and either one is the
## masthead light on some vessel. `VesselSkinBaker` keeps every "light"-tagged
## brick as a live node rather than merging it, so `Light_<cell>` is reachable at
## the shipping configuration — verified by §4's parity section, which measures
## this with the merger both on and off.
static func _masthead(
	boat: Node3D, layout: BrickLayout, grid: DeckGrid, roof_top_y: float
) -> Dictionary:
	var out := {
		"has_masthead": false, "masthead_y_m": 0.0,
		"roof_top_y_m": roof_top_y, "masthead_above_roof_m": -999.0,
	}
	var root := boat.get_node_or_null("DeckFitout")
	if root == null:
		return out
	var to_boat := boat.global_transform.affine_inverse()
	var lantern_y := 1e9
	for item in layout.iter_primary_cells():
		var light_id := str(item.get("light_id", ""))
		if light_id.is_empty() or not BrickCatalog.has_tag(light_id, "nav_white"):
			continue
		var cell: Vector3i = item["cell"]
		var node := root.get_node_or_null(
			"Light_%d_%d_%d" % [cell.x, cell.y, cell.z]
		) as Node3D
		if node == null:
			continue
		var stack: Array = [node]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			for child in n.get_children():
				stack.append(child)
			var mi := n as MeshInstance3D
			if mi == null or mi.mesh == null:
				continue
			var aabb := mi.mesh.get_aabb()
			var xform := to_boat * mi.global_transform
			for corner in 8:
				lantern_y = minf(lantern_y, (xform * aabb.get_endpoint(corner)).y)
	if lantern_y > 1e8:
		return out
	out["has_masthead"] = true
	out["masthead_y_m"] = lantern_y
	out["masthead_above_roof_m"] = lantern_y - roof_top_y
	return out


## §7's second measurement, and the one that states the defect exactly. The
## helmsman's forward view is the box directly ahead of the windscreen, as wide
## as the wheelhouse and as tall as its glass. Anything the FIT-OUT draws in it
## is standing in that view: on `28_10_m` and `bulk_small` as shipped, that was
## the mast column and the masthead lantern itself, four cells forward on the
## centreline (`screenshots/vessels/starter_28m/bulk_small__bow_on_ortho.png`).
##
## The hull is not counted — `_collect` walks the fit-out only — and neither is
## anything at the windscreen plane itself, so the window frames and the brow
## above them are outside the box by construction: the brow sits a whole cell
## above `y_hi`, and the frames straddle the plane rather than standing clear
## forward of it.
static func _sightline(all_tris: Dictionary, h: Dictionary, front: Dictionary) -> Dictionary:
	var x0: float = float(h["cap_x_min"]) + 0.02
	var x1: float = float(h["cap_x_max"]) - 0.02
	var y0: float = float(front.get("y_lo", 0.0))
	var y1: float = float(front.get("y_hi", 0.0))
	var z1: float = float(front.get("plane", 0.0)) - 0.05
	var out := {
		"sightline_tri_n": -1,
		"sightline_w_m": maxf(x1 - x0, 0.0),
		"sightline_h_m": maxf(y1 - y0, 0.0),
	}
	if not bool(front.get("found", false)):
		return out
	var n := 0
	var src: Array = all_tris["tri"]
	for t_variant in src:
		var t: Array = t_variant
		var mn := Vector3(1e9, 1e9, 1e9)
		var mx := Vector3(-1e9, -1e9, -1e9)
		for p_variant in t:
			var p: Vector3 = p_variant
			mn = Vector3(minf(mn.x, p.x), minf(mn.y, p.y), minf(mn.z, p.z))
			mx = Vector3(maxf(mx.x, p.x), maxf(mx.y, p.y), maxf(mx.z, p.z))
		if mx.z > z1:
			continue
		if minf(mx.x, x1) - maxf(mn.x, x0) <= 0.02:
			continue
		if minf(mx.y, y1) - maxf(mn.y, y0) <= 0.02:
			continue
		n += 1
	out["sightline_tri_n"] = n
	return out
