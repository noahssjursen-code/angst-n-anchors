extends SceneTree

const GENERATOR := preload("res://scripts/world/world_layout_generator.gd")
const LAND_FIELD := preload("res://scripts/weather/land_field.gd")
const FIXED_SEED := 90210

var _failures := PackedStringArray()


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
	var inside := Vector3(15000.0, 0.0, 14500.0)
	## The archipelago belt seeds island centres out to belt_x_min_m = -12 000 and
	## erodes them another kilometre west, so x = -15 000 is under 4 km from the
	## outermost skerries — never the 5 km of clearance this check is about.
	var open := Vector3(-18000.0, 0.0, 14500.0)
	_check(LAND_FIELD.get_layout() == layout, "layout is exposed read-only")
	_check(LAND_FIELD.distance_to_land(inside) < 0.0, "inside-land distance is negative")
	_check(is_zero_approx(LAND_FIELD.wave_shelter(inside)), "inside land has no waves")
	_check(is_zero_approx(LAND_FIELD.coastal_exposure(inside)), "inside land has no exposure")
	_check(
		layout.classify_region(Vector2(open.x, open.z)) == WorldLayout.Region.OPEN_WATER,
		"open-ocean sample sits west of the archipelago belt"
	)
	_check(LAND_FIELD.distance_to_land(open) > 5000.0, "open-ocean point is far from land")
	_check(LAND_FIELD.wave_shelter(open) > 0.999, "open ocean has full local waves")
	_check(LAND_FIELD.coastal_exposure(open) > 0.92, "open ocean has high exposure")


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
		_check(
			LAND_FIELD.shore_shelter(p) == LAND_FIELD.wave_shelter(p),
			"shore_shelter aliases wave_shelter"
		)
		_check(
			LAND_FIELD.shore_proximity(p) == 1.0 - LAND_FIELD.wave_shelter(p),
			"shore_proximity is inverse wave shelter"
		)
	_test_kilometre_band(layout)


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
	if not condition and not _failures.has(label):
		_failures.append(label)
	return condition


func _finish() -> void:
	if _failures.is_empty():
		print("LandField geography tests: all checks passed")
		quit()
		return
	for failure in _failures:
		push_error("LandField geography test: " + failure)
	quit(1)
