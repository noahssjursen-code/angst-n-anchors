extends SceneTree

## Scratch probe (not a test). Third pass on owner decisions #3 and #4.
## Q1: is `coastal_exposure < 0.80` at a kilometre ACTUALLY impossible, or only
##     impossible at the sample the scan happens to pick?
## Q2: what does the OPEN_WATER label guarantee, on the generator's own terms,
##     across seeds — measured on the raster, not on a bilinear resample.

const GENERATOR := preload("res://scripts/world/world_layout_generator.gd")
const LAND_FIELD := preload("res://scripts/weather/land_field.gd")
const FIXED_SEED := 90210
const SEEDS := [90210, 1, 7, 12345, 777, 20260815, 424242, 31337]


func _initialize() -> void:
	var layout: WorldLayout = GENERATOR.generate(FIXED_SEED)
	LAND_FIELD.initialize(layout)
	print("== layout: size=%.0f res=%d cell=%.3f ==" % [
		layout.world_size_m, layout.raster_resolution, layout.cell_size_m,
	])

	_exposure_ceiling()
	_band(layout)
	_open_water_promise(layout)
	_multi_seed()
	quit()


## ---- Q1: the exposure ceiling, derived rather than quoted -------------------
func _exposure_ceiling() -> void:
	print("\n== exposure ramp ==")
	var c := LAND_FIELD.COASTAL_DISTANCE_M
	# Invert smoothstep(80, C, d) = 0.80 by bisection on t.
	var lo := 0.0
	var hi := 1.0
	for _i in range(80):
		var mid := (lo + hi) * 0.5
		if mid * mid * (3.0 - 2.0 * mid) < 0.80:
			lo = mid
		else:
			hi = mid
	var t := (lo + hi) * 0.5
	var d_star := 80.0 + t * (c - 80.0)
	print("  COASTAL_DISTANCE_M = %.1f" % c)
	print("  smoothstep(80, C, d) = 0.80 at t=%.6f -> d = %.1f m" % [t, d_star])
	print("  check: smoothstep(80,C,%.1f) = %.4f" % [d_star, smoothstep(80.0, c, d_star)])
	for d in [650.0, 1000.0, 1306.0, 1383.4, 1400.0, 1800.0]:
		print("    d=%7.1f  ceiling=%.4f  fetch needed for exposure<0.80: mean_fetch < %.4f" % [
			d, smoothstep(80.0, c, d),
			pow(minf(0.80 / maxf(smoothstep(80.0, c, d), 0.0001), 1.0), 1.0 / 0.65),
		])


## ---- the 650-1400 m ARCHIPELAGO band ---------------------------------------
func _band(layout: WorldLayout) -> void:
	print("\n== 650-1400 m ARCHIPELAGO band (250 m scan) ==")
	var scan_first := Vector2.INF
	for z in range(-15000, 15001, 125):
		for x in range(-15000, 15001, 125):
			var p := Vector2(float(x), float(z))
			var d := layout.sample_signed_distance(p)
			if d < 650.0 or d > 1400.0:
				continue
			if layout.classify_region(p) != WorldLayout.Region.ARCHIPELAGO:
				continue
			scan_first = p
			break
		if scan_first != Vector2.INF:
			break

	var exposures := PackedFloat32Array()
	var min_shelter := 1.0
	var below_080 := 0
	var below_080_far := 0  # below 0.80 while ALSO past the ceiling distance
	var far := 0
	var deepest_below := -1.0
	var deepest_at := Vector2.ZERO
	var deepest_exposure := 0.0
	var worst_ratio := 0.0
	var worst_at := Vector2.ZERO
	var scan_first_exposure := -1.0
	var scan_first_distance := -1.0
	var scan_first_rank := -1
	var c := LAND_FIELD.COASTAL_DISTANCE_M
	var points := PackedVector2Array()
	for z in range(-15000, 15001, 250):
		for x in range(-15000, 15001, 250):
			var p := Vector2(float(x), float(z))
			var d := layout.sample_signed_distance(p)
			if d < 650.0 or d > 1400.0:
				continue
			if layout.classify_region(p) != WorldLayout.Region.ARCHIPELAGO:
				continue
			var w := Vector3(p.x, 0.0, p.y)
			var e := LAND_FIELD.coastal_exposure(w)
			min_shelter = minf(min_shelter, LAND_FIELD.wave_shelter(w))
			exposures.append(e)
			points.append(p)
			var ceiling := smoothstep(80.0, c, d)
			var ratio := e / maxf(ceiling, 0.0001)
			if ratio > worst_ratio:
				worst_ratio = ratio
				worst_at = p
			if e < 0.80:
				below_080 += 1
				if d > 1306.5:
					below_080_far += 1
					if d > deepest_below:
						deepest_below = d
						deepest_at = p
						deepest_exposure = e
			if d > 1306.5:
				far += 1
	print("  n=%d  min_shelter=%.4f" % [exposures.size(), min_shelter])
	print("  samples with exposure < 0.80: %d (%.1f%%)" % [
		below_080, 100.0 * float(below_080) / float(maxi(exposures.size(), 1)),
	])
	print("  samples deeper than the 1306.5 m ceiling distance: %d" % far)
	print("    ...of those, exposure < 0.80 anyway (fetch-blocked): %d" % below_080_far)
	if deepest_below > 0.0:
		print("    deepest such sample: (%.0f, %.0f) d=%.1f exposure=%.4f" % [
			deepest_at.x, deepest_at.y, deepest_below, deepest_exposure,
		])
	print("  worst exposure/ceiling ratio in band: %.4f at (%.0f, %.0f)" % [
		worst_ratio, worst_at.x, worst_at.y,
	])
	var sorted_e := exposures.duplicate()
	sorted_e.sort()
	# where does the scan-order sample sit in that distribution?
	if scan_first != Vector2.INF:
		var w := Vector3(scan_first.x, 0.0, scan_first.y)
		scan_first_exposure = LAND_FIELD.coastal_exposure(w)
		scan_first_distance = layout.sample_signed_distance(scan_first)
		var below := 0
		for e in sorted_e:
			if e < scan_first_exposure:
				below += 1
		scan_first_rank = below
		print("  SCAN-ORDER SAMPLE (what the test checks): (%.0f, %.0f)" % [
			scan_first.x, scan_first.y,
		])
		print("    d=%.1f  exposure=%.4f  ceiling=%.4f  mean_fetch=%.4f" % [
			scan_first_distance, scan_first_exposure,
			smoothstep(80.0, c, scan_first_distance),
			pow(scan_first_exposure / maxf(smoothstep(80.0, c, scan_first_distance), 0.0001), 1.0 / 0.65),
		])
		print("    percentile within the band: p%.1f (%d of %d below it)" % [
			100.0 * float(scan_first_rank) / float(maxi(sorted_e.size(), 1)),
			scan_first_rank, sorted_e.size(),
		])
	for q in [0, 50, 75, 90, 95, 99, 100]:
		var i := clampi((sorted_e.size() * q) / 100, 0, sorted_e.size() - 1)
		print("    p%03d = %.4f" % [q, sorted_e[i]])


## ---- Q2: what does OPEN_WATER promise? -------------------------------------
func _open_water_promise(layout: WorldLayout) -> void:
	print("\n== OPEN_WATER, measured on the raster itself ==")
	var stats := _raster_stats(layout)
	print("  cells=%d  open_water=%d" % [stats["cells"], stats["ow_cells"]])
	print("  westernmost LAND cell x = %.1f" % stats["west_land_x"])
	print("  min SDF over OPEN_WATER cells = %.1f m at (%.0f, %.0f)" % [
		stats["ow_min_sdf"], stats["ow_min_at"].x, stats["ow_min_at"].y,
	])
	print("  OPEN_WATER cells that are LAND (sdf<0): %d" % stats["ow_land_cells"])
	print("  max SDF anywhere on the map = %.1f m at (%.0f, %.0f)" % [
		stats["max_sdf"], stats["max_at"].x, stats["max_at"].y,
	])
	print("  max SDF among OPEN_WATER cells = %.1f" % stats["ow_max_sdf"])
	var open := Vector3(-15000.0, 0.0, 14500.0)
	var far_open := Vector3(-18000.0, 0.0, 14500.0)
	for p in [open, far_open]:
		print("  sample (%.0f, %.0f): sdf=%.1f shelter=%.4f exposure=%.4f region=%d" % [
			p.x, p.z, LAND_FIELD.distance_to_land(p),
			LAND_FIELD.wave_shelter(p), LAND_FIELD.coastal_exposure(p),
			int(layout.classify_region(Vector2(p.x, p.z))),
		])
	# How much of OPEN_WATER is still on the coastal ramp?
	var on_ramp := 0
	var raster := layout.get_signed_distance_raster()
	var regions := layout.get_region_raster()
	for i in range(regions.size()):
		if regions[i] != WorldLayout.Region.OPEN_WATER:
			continue
		if raster[i] < LAND_FIELD.COASTAL_DISTANCE_M:
			on_ramp += 1
	print("  OPEN_WATER cells still inside COASTAL_DISTANCE_M (%.0f m): %d (%.1f%%)" % [
		LAND_FIELD.COASTAL_DISTANCE_M, on_ramp,
		100.0 * float(on_ramp) / float(maxi(int(stats["ow_cells"]), 1)),
	])
	var under_5k := 0
	for i in range(regions.size()):
		if regions[i] != WorldLayout.Region.OPEN_WATER:
			continue
		if raster[i] < 5000.0:
			under_5k += 1
	print("  OPEN_WATER cells inside 5000 m: %d (%.1f%%)" % [
		under_5k, 100.0 * float(under_5k) / float(maxi(int(stats["ow_cells"]), 1)),
	])


func _raster_stats(layout: WorldLayout) -> Dictionary:
	var raster := layout.get_signed_distance_raster()
	var regions := layout.get_region_raster()
	var res := layout.raster_resolution
	var half := layout.half_extent_m
	var cell := layout.cell_size_m
	var west_land_x := 1.0e30
	var ow_min := 1.0e30
	var ow_max := -1.0e30
	var ow_min_at := Vector2.ZERO
	var max_at := Vector2.ZERO
	var max_sdf := -1.0e30
	var ow_cells := 0
	var ow_land := 0
	for zi in range(res):
		var z := -half + float(zi) * cell
		for xi in range(res):
			var x := -half + float(xi) * cell
			var i := zi * res + xi
			var d := raster[i]
			if d < 0.0 and x < west_land_x:
				west_land_x = x
			if d > max_sdf:
				max_sdf = d
				max_at = Vector2(x, z)
			if regions[i] != WorldLayout.Region.OPEN_WATER:
				continue
			ow_cells += 1
			if d < 0.0:
				ow_land += 1
			if d < ow_min:
				ow_min = d
				ow_min_at = Vector2(x, z)
			if d > ow_max:
				ow_max = d
	return {
		"cells": raster.size(),
		"ow_cells": ow_cells,
		"ow_land_cells": ow_land,
		"west_land_x": west_land_x,
		"ow_min_sdf": ow_min,
		"ow_min_at": ow_min_at,
		"ow_max_sdf": ow_max,
		"max_sdf": max_sdf,
		"max_at": max_at,
	}


func _multi_seed() -> void:
	print("\n== across seeds: does the OPEN_WATER cut hold? ==")
	print("  seed        west_land_x   ow_min_sdf   ow_land_cells   max_sdf   ow_max_sdf")
	for s in SEEDS:
		var l: WorldLayout = GENERATOR.generate(int(s))
		var st := _raster_stats(l)
		print("  %-10d  %10.1f   %10.1f   %13d   %7.1f   %10.1f" % [
			int(s), st["west_land_x"], st["ow_min_sdf"], st["ow_land_cells"],
			st["max_sdf"], st["ow_max_sdf"],
		])
