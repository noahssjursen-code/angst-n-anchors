extends SceneTree

const GENERATOR := preload("res://scripts/world/world_layout_generator.gd")
const LAND_FIELD := preload("res://scripts/weather/land_field.gd")
const TestReport := preload("res://tests/support/test_report.gd")
const FIXED_SEED := 90210

## The three named samples, in one place because more than one sub-test now
## reasons about the SAME points and two copies of a coordinate is two chances
## to move one of them (REALITY 3b). `OPEN_OCEAN` is the original sample: it was
## moved 3 km west once to escape a failing distance bound and moved back.
const INSIDE_LAND := Vector3(15000.0, 0.0, 14500.0)
const OPEN_OCEAN := Vector3(-15000.0, 0.0, 14500.0)
const DEEP_OFFSHORE := Vector3(-18000.0, 0.0, 14500.0)

## This file used to keep its own PackedStringArray and print
## "LandField geography tests: all checks passed" — prose, no count, and a
## de-duplicating accumulator that hid repeat failures of the same label. The
## suite's verdict language is what the gate scores lane A by, and a unit that
## cannot say how many checks it ran cannot be audited for vacuity.
##
## That note used to end "Every bound below is untouched; only the bookkeeping
## changed", and on 2026-08-15 two of them were touched — the only two that were
## red, both of them underived numbers standing where a mechanism belonged. Each
## site says what it was, what it measured, and why the replacement is derived
## from a constant rather than chosen to go green; the file went 2/43 FAILED to
## PASS (53) and every new check is mutation-verified in place.
var _t := TestReport.new("land_field_geography_test")


func _initialize() -> void:
	var layout: WorldLayout = GENERATOR.generate(FIXED_SEED)
	LAND_FIELD.initialize(layout)
	_test_land_and_open_ocean(layout)
	_test_coast_and_split(layout)
	_test_fjord(layout)
	_test_skerry_and_fetch(layout)
	_test_texture_agreement(layout)
	_test_legacy_backend()
	_finish()


func _test_land_and_open_ocean(layout: WorldLayout) -> void:
	var inside := INSIDE_LAND
	var open := OPEN_OCEAN
	var far_open := DEEP_OFFSHORE
	var open_distance := LAND_FIELD.distance_to_land(open)
	var far_distance := LAND_FIELD.distance_to_land(far_open)
	_check(LAND_FIELD.get_layout() == layout, "layout is exposed read-only")
	_check(LAND_FIELD.distance_to_land(inside) < 0.0, "inside-land distance is negative")
	_check(is_zero_approx(LAND_FIELD.wave_shelter(inside)), "inside land has no waves")
	_check(is_zero_approx(LAND_FIELD.coastal_exposure(inside)), "inside land has no exposure")
	_check(
		layout.classify_region(Vector2(open.x, open.z)) == WorldLayout.Region.OPEN_WATER,
		"open-ocean sample sits west of the archipelago belt"
	)
	## WAS: `distance_to_land(open) > 5000.0`, "open-ocean point is far from land".
	##
	## It measures 3779.9 m and has been red on every honest run since the first
	## recorded one (20260809-133513). **It was NOT written against an imagined
	## world** — that was the first thing checked and it was wrong. Bisected by
	## restoring c584530's generator and world data into a scratch tree and running
	## the old file against all four combinations:
	##
	##   day-one generator + day-one norway_coast.json  -> PASS (43)
	##   today's generator + day-one norway_coast.json  -> 1/43 (this check)
	##   day-one generator + today's norway_coast.json  -> this check
	##   today's generator + today's norway_coast.json  -> 2/43 (the baseline)
	##
	## So the bound was TRUE of the world as first shipped, and EITHER world change
	## breaks it on its own: `lobes_min/max` went 2-4 to 3-5 and `coast_amplitude_m`
	## 1850 to 2800, and the archipelago reached west. The check was a world-SHAPE
	## invariant nobody restated when the world was deliberately re-shaped, and it
	## has sat in the known-red list as "an owner decision about world constants"
	## ever since. What it reported was real; what it asserted was a number with no
	## consumer — 5000 is not a length anything in this field uses, and no code
	## outside tests/ asks how much sea room open water has.
	##
	## The length it does use is COASTAL_DISTANCE_M. Past it `coastal_opening` is
	## exactly 1.0 and distance stops modulating any output — only fetch is left.
	## That is what "far from land" has to mean HERE, because this check is the
	## premise of the two below it: shelter and exposure may be asserted at their
	## open-ocean values only where no proximity falloff is still acting. Derived
	## from the falloff, so it moves when the falloff does.
	##
	## Mutation-measured against the world rather than against its own arithmetic,
	## by growing the archipelago westward and reading this number back:
	## `belt_x_min_m` -12000 (as shipped) 3779.9 m; -16000 2066.8; -17000 2327.6;
	## -19000 3411.2 — the belt is seeded at random z, so pushing its west edge out
	## does not monotonically close on one sample. It reddens when islands actually
	## arrive: `belt_x_min_m` -15000 with `radius_max_m` 780 -> 4000 puts this
	## sample INSIDE land at -82.9 m, and the open-ocean shelter and exposure
	## claims below go with it.
	##
	## What it is NOT is a promise carried by the label. `Region.OPEN_WATER` is a
	## bare longitude cut (`x <= open_water_x_m`) drawn without reference to where
	## the islands landed, and NOTHING outside tests/ reads it: `classify_region`'s
	## only production caller is CoastalPortPlacer, which branches on
	## MAINLAND/FJORD/ARCHIPELAGO and folds everything else to MAINLAND. The whole
	## of what the label promises is checked in _test_open_water_is_offshore, over
	## every cell that carries it instead of at one hand-picked point.
	##
	## AND IF THE OWNER DOES WANT OPEN WATER TO MEAN SEA ROOM, that is one line,
	## not this one: raise the minimum-clearance bound in that function from one
	## raster cell to the distance wanted. It is a population claim, so it holds
	## the whole label rather than one coordinate, and at 5000 m it goes red today
	## (32.1% of open-water cells are inside 5 km). Deciding it needs a picture,
	## and there is one: `screenshots/decisions/open_water_promise__*`. The plan
	## view shows the cut is a straight longitude line drawn without reference to
	## where the islands landed, and the two eye-level frames show that this sample
	## at 3779.9 m and the deep one at 6368.5 m — the one that PASSED the old bound
	## — are the same picture, land as an 8-13 px strip on the horizon against an
	## 84 px 1.8 m figure at 10 m.
	_check(
		open_distance > LAND_FIELD.COASTAL_DISTANCE_M,
		"open-ocean sample is past every distance-driven falloff (%.1f m > %.1f m)" % [
			open_distance, LAND_FIELD.COASTAL_DISTANCE_M,
		]
	)
	_check(LAND_FIELD.wave_shelter(open) > 0.999, "open ocean has full local waves")
	_check(LAND_FIELD.coastal_exposure(open) > 0.92, "open ocean has high exposure")
	## Three kilometres further west. The a-fortiori claim is now stated as an
	## ORDERING rather than a second copy of a threshold: going west must go
	## further offshore. That reddens on a belt that grew past the outer sample
	## even in worlds where both samples still clear the falloff, which a repeated
	## threshold cannot do, and it carries the premise across transitively.
	_check(
		layout.classify_region(Vector2(far_open.x, far_open.z)) == WorldLayout.Region.OPEN_WATER,
		"the deep-offshore sample is open water too"
	)
	_check(
		far_distance > open_distance,
		"deep offshore is further from land than the inner sample (%.1f m > %.1f m)" % [
			far_distance, open_distance,
		]
	)
	_check(LAND_FIELD.wave_shelter(far_open) > 0.999, "deep offshore has full local waves")
	_check(LAND_FIELD.coastal_exposure(far_open) > 0.92, "deep offshore has high exposure")
	_test_open_water_is_offshore(layout)


## What the OPEN_WATER label actually promises, quantified over every cell that
## carries it rather than sampled at one point. The generator's rule is
## `x <= open_water_x_m` — a straight longitude cut, drawn with no reference to
## where the island lobes ended up — so the one guarantee available is that the
## cut clears the belt. A cell whose signed distance is inside one raster cell of
## zero cannot be told from land by the raster that produced it, so one cell is
## the margin; it is not a tuned number and it moves with `raster_resolution`.
##
## Measured 2026-08-15 on this seed: 10794 open-water cells, 0 of them land,
## minimum clearance 1386.0 m against a 156.25 m cell. Across eight seeds
## (`tests/_probe_land_field_q34.gd`) the minimum clearance ranges 1180.7 —
## 2828.8 m and no seed puts land in open water. This check only runs the seed
## the file fixes, because a WorldLayout costs 8-11 s to generate and a 21 s unit
## should not become a minute; the cross-seed sweep is the probe's job.
##
## HAZARD, latent, for the owner and NOT asserted here because it did not occur
## in any seed measured: the config does not guarantee this by arithmetic. An
## island cluster may be seeded at `belt_x_min_m` = -12000 with `radius_max_m` =
## 780, a lobe offset up to 0.72 x radius and a lobe radius up to 0.92 x radius,
## and `_eroded_island_distance` scales a lobe by up to 1.44. Worst case the land
## edge reaches x = -12000 - 561.6 - (717.6 x 1.44) = -13594.9, which is 94.9 m
## WEST of the -13500 cut. The realised westernmost land over eight seeds is
## -12343.8, so the theoretical corner needs four independent draws at once. If
## it ever lands, this check is what reports it.
func _test_open_water_is_offshore(layout: WorldLayout) -> void:
	var distances := layout.get_signed_distance_raster()
	var regions := layout.get_region_raster()
	var open_cells := 0
	var land_cells := 0
	var minimum := INF
	for i in range(regions.size()):
		if int(regions[i]) != int(WorldLayout.Region.OPEN_WATER):
			continue
		open_cells += 1
		minimum = minf(minimum, distances[i])
		if distances[i] < 0.0:
			land_cells += 1
	if not _check(
		open_cells > 1000,
		"the layout carries an open-water region to measure (%d cells)" % open_cells
	):
		return
	_check(
		land_cells == 0,
		"no cell labelled OPEN_WATER is land (%d of %d)" % [land_cells, open_cells]
	)
	_check(
		minimum > layout.cell_size_m,
		"every OPEN_WATER cell clears the coast by more than one raster cell (%.1f m > %.1f m)" % [
			minimum, layout.cell_size_m,
		]
	)


func _test_coast_and_split(layout: WorldLayout) -> void:
	var immediate := _find_water(layout, WorldLayout.Region.MAINLAND, 20.0, 220.0)
	var coastal := _find_water(layout, WorldLayout.Region.ARCHIPELAGO, 650.0, 1400.0)
	if coastal == Vector2.INF:
		coastal = _find_water(layout, -1, 650.0, 1400.0)
	_check(immediate != Vector2.INF, "deterministic immediate-coast sample exists")
	_check(coastal != Vector2.INF, "deterministic kilometre-scale coastal sample exists")
	if immediate != Vector2.INF:
		var p := Vector3(immediate.x, 0.0, immediate.y)
		_check(LAND_FIELD.wave_shelter(p) < 0.55, "immediate coast attenuates waves")
		_check(LAND_FIELD.coastal_exposure(p) < 0.12, "immediate coast has low exposure")
	if coastal != Vector2.INF:
		var p := Vector3(coastal.x, 0.0, coastal.y)
		## The aggregate band below is a better formulation and stays, but it does
		## not get to stand in for this: the first kilometre-scale sample is a claim
		## in its own right. What changed is WHICH claim.
		_check(LAND_FIELD.wave_shelter(p) > 0.99, "local waves recover within hundreds of metres")
		## WAS: `coastal_exposure(p) < 0.80`, "coastal exposure remains kilometre-scale".
		##
		## 0.80 is a property of the BAND — p90 over 2148 samples is 0.7402 — and it
		## was being asked of whichever sample `_find_water` happens to reach first
		## in raster order. That is (-12500, -15000), the south-west fringe of the
		## belt at 1383.4 m out, and it sits at **p99.7** of the very band the 0.80
		## came from. The comment on `_test_kilometre_band` below already said why
		## this happens — "the first hit lands on the seaward fringe of the belt,
		## which is the most exposed water in the band" — while this line went on
		## holding that sample to the band's ninetieth percentile.
		##
		## The history shows it tracking the scan rather than the field. Same seed,
		## same bound, it PASSED on 2026-08-09 (run 20260809-133513), and the
		## four-way bisect above pins what moved it: with today's generator and
		## day-one world data it PASSES; only the current combination fails. Its
		## sibling on the same `_find_water` instrument, "fjord has low coastal
		## exposure", was failing in that same 2026-08-09 run and passes now — the
		## two swapped colour across world changes that neither of them mentions.
		## That is the instrument talking, not the subject (REALITY 7).
		##
		## It is worth being exact about WHY it cannot pass, because "arithmetically
		## impossible" overstates it: exposure is `coastal_opening(d) * fetch^0.65`,
		## the ramp alone allows 0.8524 at 1383.4 m, and 0.80 therefore needs
		## mean_fetch < 0.9070 while this sample measures 0.9481. Elsewhere in the
		## band it IS reachable past the ramp's 1306.1 m crossing — 308 of the 338
		## samples beyond it read under 0.80, the deepest at 1399.8 m — because
		## their horizon is blocked. So the bound is not impossible for the band, it
		## is impossible for the point the scan picks, which is the same defect.
		##
		## What a single sample can carry is its OWN ceiling. Proximity caps how
		## exposed a point may read whatever its fetch, and at a kilometre that cap
		## is strictly under the open-ocean value because d < COASTAL_DISTANCE_M.
		## Both halves come from the field's constants through the one function that
		## defines the ramp, so the claim survives whichever sample it is handed —
		## and it deliberately does NOT adjudicate the VALUE of COASTAL_DISTANCE_M,
		## which is a sea-state taste question no check settles.
		_test_coastal_ramp_shape()
		var distance := LAND_FIELD.distance_to_land(p)
		var ceiling := LAND_FIELD.coastal_opening(distance)
		var exposure := LAND_FIELD.coastal_exposure(p)
		_check(
			distance < LAND_FIELD.COASTAL_DISTANCE_M and ceiling < 1.0,
			"the kilometre sample is inside the coastal ramp (%.1f m < %.1f m, ceiling %.4f)" % [
				distance, LAND_FIELD.COASTAL_DISTANCE_M, ceiling,
			]
		)
		_check(
			exposure <= ceiling,
			"coastal exposure stays under its proximity ceiling (%.4f <= %.4f)" % [
				exposure, ceiling,
			]
		)
		## The split the file is named for, stated with no constant at all: against
		## the open-ocean sample the local wave field has SATURATED (the two agree)
		## while the exposure field has not (this one is lower). A field that
		## stopped reading proximity reddens here even though it would still sit
		## under a ceiling computed from its own output.
		_check(
			is_equal_approx(LAND_FIELD.wave_shelter(p), LAND_FIELD.wave_shelter(OPEN_OCEAN))
			and exposure < LAND_FIELD.coastal_exposure(OPEN_OCEAN),
			"at a kilometre the wave field has saturated and the exposure field has not (%.4f < %.4f)" % [
				exposure, LAND_FIELD.coastal_exposure(OPEN_OCEAN),
			]
		)
		_check(
			LAND_FIELD.shore_shelter(p) == LAND_FIELD.wave_shelter(p),
			"shore_shelter aliases wave_shelter"
		)
		_check(
			LAND_FIELD.shore_proximity(p) == 1.0 - LAND_FIELD.wave_shelter(p),
			"shore_proximity is inverse wave shelter"
		)
	_test_kilometre_band(layout)


## The ramp itself, and it exists because ONE DERIVATION CUTS BOTH WAYS. The
## kilometre check below bounds exposure by `coastal_opening(d)` rather than by a
## number somebody picked, which is what makes it survive a change to the
## constants — and it also means a broken ramp moves the bound with it. Measured:
## flooring `coastal_opening` at 0.95 (near-shore water reads nearly open) leaves
## that check GREEN at 0.9176 <= 0.9500, because both sides moved together.
##
## So the ramp is pinned by its shape, which is not self-referential: zero at the
## foot, saturated at the top, monotone between, and actually rising somewhere in
## the middle rather than a constant. Nothing here is a tuned threshold — every
## number is one of the two constants that define the ramp.
func _test_coastal_ramp_shape() -> void:
	var foot := LAND_FIELD.COASTAL_RAMP_FOOT_M
	var top := LAND_FIELD.COASTAL_DISTANCE_M
	_check(foot < top, "the coastal ramp has a positive span (%.1f m -> %.1f m)" % [foot, top])
	_check(
		is_zero_approx(LAND_FIELD.coastal_opening(foot)),
		"proximity opening is zero at the ramp foot (%.4f)" % LAND_FIELD.coastal_opening(foot)
	)
	_check(
		is_equal_approx(LAND_FIELD.coastal_opening(top), 1.0),
		"proximity opening saturates at COASTAL_DISTANCE_M (%.4f)" % LAND_FIELD.coastal_opening(top)
	)
	var monotone := true
	var rises := false
	var previous := LAND_FIELD.coastal_opening(0.0)
	for step in range(1, 201):
		var value := LAND_FIELD.coastal_opening(top * 1.5 * float(step) / 200.0)
		if value < previous - 0.000001:
			monotone = false
		if value > previous + 0.000001:
			rises = true
		previous = value
	_check(monotone, "proximity opening never decreases with distance from land")
	_check(rises, "proximity opening actually rises across the ramp")


## The split this file is named for: by a kilometre the local wave field has
## saturated while the kilometre-scale exposure field has not. One scan-order
## sample cannot carry that claim — the first hit lands on the seaward fringe of
## the belt, which is the most exposed water in the band — so quantify over the
## whole band instead.
func _test_kilometre_band(layout: WorldLayout) -> void:
	var exposures := PackedFloat32Array()
	var minimum_shelter := 1.0
	for z in range(-15000, 15001, 250):
		for x in range(-15000, 15001, 250):
			var point := Vector2(float(x), float(z))
			var distance := layout.sample_signed_distance(point)
			if distance < 650.0 or distance > 1400.0:
				continue
			if layout.classify_region(point) != WorldLayout.Region.ARCHIPELAGO:
				continue
			var world := Vector3(point.x, 0.0, point.y)
			minimum_shelter = minf(minimum_shelter, LAND_FIELD.wave_shelter(world))
			exposures.append(LAND_FIELD.coastal_exposure(world))
	if not _check(exposures.size() > 500, "kilometre band has a population to measure"):
		return
	exposures.sort()
	_check(minimum_shelter > 0.99, "local waves recover within hundreds of metres, everywhere in the band")
	_check(
		exposures[exposures.size() - 1] < 0.92,
		"kilometre-scale exposure never reaches the open-ocean floor"
	)
	_check(
		exposures[(exposures.size() * 9) / 10] < 0.80,
		"nine in ten kilometre-scale samples stay coastal"
	)


func _test_fjord(layout: WorldLayout) -> void:
	var fjord := _find_water(layout, WorldLayout.Region.FJORD, 120.0, 1100.0)
	_check(fjord != Vector2.INF, "deterministic fjord sample exists")
	if fjord == Vector2.INF:
		return
	var p := Vector3(fjord.x, 0.0, fjord.y)
	_check(LAND_FIELD.coastal_exposure(p) < 0.55, "fjord has low coastal exposure")
	_check(LAND_FIELD.coastal_exposure(p) < LAND_FIELD.wave_shelter(p), "fjord separates fetch from local waves")


func _test_skerry_and_fetch(layout: WorldLayout) -> void:
	var skerry_water := _find_water(layout, WorldLayout.Region.ARCHIPELAGO, 180.0, 850.0)
	_check(skerry_water != Vector2.INF, "deterministic skerry-water sample exists")
	if skerry_water == Vector2.INF:
		return
	var p := Vector3(skerry_water.x, 0.0, skerry_water.y)
	var minimum := 1.0
	var maximum := 0.0
	for i in range(16):
		var angle := TAU * float(i) / 16.0
		var fetch := LAND_FIELD.directional_fetch(p, Vector2(cos(angle), sin(angle)))
		minimum = minf(minimum, fetch)
		maximum = maxf(maximum, fetch)
	_check(minimum < 0.30, "skerry blocks at least one fetch direction")
	_check(maximum > minimum + 0.25, "directional fetch distinguishes blocked and open water")
	_check(LAND_FIELD.coastal_exposure(p) < 0.65, "skerries reduce coastal exposure")


func _test_texture_agreement(layout: WorldLayout) -> void:
	_check(LAND_FIELD.get_baked_shelter_texture() != null, "wave-shelter texture is baked")
	_check(
		LAND_FIELD.get_baked_world_origin().is_equal_approx(
			Vector2(-layout.half_extent_m, -layout.half_extent_m)
		),
		"texture starts at macro-map origin"
	)
	_check(is_equal_approx(LAND_FIELD.get_baked_world_size(), layout.world_size_m), "texture spans macro map")
	var step := layout.world_size_m / float(LAND_FIELD.BAKE_RESOLUTION)
	for texel in [Vector2i(12, 12), Vector2i(181, 96), Vector2i(310, 220), Vector2i(490, 460)]:
		var point := LAND_FIELD.get_baked_world_origin() + (
			Vector2(texel.x, texel.y) + Vector2(0.5, 0.5)
		) * step
		var world := Vector3(point.x, 0.0, point.y)
		_check(
			absf(LAND_FIELD.sample_baked_shelter(world) - LAND_FIELD.wave_shelter(world)) < 0.0001,
			"texture and CPU wave shelter agree at texel %s" % texel
		)


func _test_legacy_backend() -> void:
	LAND_FIELD.initialize([{
		"center": Vector3.ZERO,
		"half_x": 250.0,
		"half_z": 500.0,
		"rotation_y": 0.0,
	}])
	_check(LAND_FIELD.get_layout() == null, "legacy initialization clears layout backend")
	_check(LAND_FIELD.get_island_count() == 1, "legacy island initialization remains available")
	_check(LAND_FIELD.distance_to_land(Vector3.ZERO) < 0.0, "legacy signed distance remains negative on land")
	var old_coastal := LAND_FIELD.wave_shelter(Vector3(1250.0, 0.0, 0.0))
	_check(old_coastal > 0.0 and old_coastal < 0.5, "legacy shelter falloff is preserved")
	_check(LAND_FIELD.wave_shelter(Vector3(3800.0, 0.0, 0.0)) > 0.99, "legacy offshore behavior is preserved")


func _find_water(layout: WorldLayout, region: int, min_distance: float, max_distance: float) -> Vector2:
	for z in range(-15000, 15001, 125):
		for x in range(-15000, 15001, 125):
			var point := Vector2(float(x), float(z))
			var distance := layout.sample_signed_distance(point)
			if distance < min_distance or distance > max_distance:
				continue
			if region >= 0 and int(layout.classify_region(point)) != region:
				continue
			return point
	return Vector2.INF


func _check(condition: bool, label: String) -> bool:
	return _t.check(label, condition)


func _finish() -> void:
	_t.finish(self)
