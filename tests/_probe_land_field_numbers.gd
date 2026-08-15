extends SceneTree

## Scratch probe (not a test). Measures the numbers the owner decision on
## land_field_geography_test rests on. Delete when the decision is recorded.

const GENERATOR := preload("res://scripts/world/world_layout_generator.gd")
const LAND_FIELD := preload("res://scripts/weather/land_field.gd")
const FIXED_SEED := 90210


func _initialize() -> void:
	var layout: WorldLayout = GENERATOR.generate(FIXED_SEED)
	LAND_FIELD.initialize(layout)
	print("world_size_m=%.1f half=%.1f res=%d cell=%.3f" % [
		layout.world_size_m, layout.half_extent_m,
		layout.raster_resolution, layout.cell_size_m,
	])

	print("--- SDF along the z=14500 westward transect ---")
	for x in [-12000, -13000, -14000, -15000, -16000, -17000, -18000, -19000, -19900]:
		var p := Vector2(float(x), 14500.0)
		print("  x=%6d  sdf=%9.1f  region=%d  shelter=%.4f  exposure=%.4f" % [
			x, layout.sample_signed_distance(p), int(layout.classify_region(p)),
			LAND_FIELD.wave_shelter(Vector3(p.x, 0.0, p.y)),
			LAND_FIELD.coastal_exposure(Vector3(p.x, 0.0, p.y)),
		])

	print("--- global SDF maximum over the whole macro map (250 m scan) ---")
	var best := -1.0e30
	var best_at := Vector2.ZERO
	var over_5000 := 0
	var water := 0
	for z in range(-20000, 20001, 250):
		for x in range(-20000, 20001, 250):
			var p := Vector2(float(x), float(z))
			var d := layout.sample_signed_distance(p)
			if d > 0.0:
				water += 1
			if d > 5000.0:
				over_5000 += 1
			if d > best:
				best = d
				best_at = p
	print("  max sdf = %.1f m at (%.0f, %.0f)" % [best, best_at.x, best_at.y])
	print("  water samples = %d ; samples with sdf > 5000 = %d" % [water, over_5000])

	print("--- OPEN_WATER region: how far from land does it actually get? ---")
	var ow_best := -1.0e30
	var ow_at := Vector2.ZERO
	var ow_count := 0
	for z in range(-20000, 20001, 250):
		for x in range(-20000, 20001, 250):
			var p := Vector2(float(x), float(z))
			if layout.classify_region(p) != WorldLayout.Region.OPEN_WATER:
				continue
			ow_count += 1
			var d := layout.sample_signed_distance(p)
			if d > ow_best:
				ow_best = d
				ow_at = p
	print("  OPEN_WATER samples = %d ; max sdf within them = %.1f m at (%.0f, %.0f)" % [
		ow_count, ow_best, ow_at.x, ow_at.y,
	])

	print("--- the first kilometre-scale ARCHIPELAGO sample in scan order ---")
	var found := Vector2.INF
	for z in range(-15000, 15001, 125):
		for x in range(-15000, 15001, 125):
			var p := Vector2(float(x), float(z))
			var d := layout.sample_signed_distance(p)
			if d < 650.0 or d > 1400.0:
				continue
			if layout.classify_region(p) != WorldLayout.Region.ARCHIPELAGO:
				continue
			found = p
			break
		if found != Vector2.INF:
			break
	if found != Vector2.INF:
		var w := Vector3(found.x, 0.0, found.y)
		print("  first hit (%.0f, %.0f) sdf=%.1f shelter=%.4f exposure=%.4f" % [
			found.x, found.y, layout.sample_signed_distance(found),
			LAND_FIELD.wave_shelter(w), LAND_FIELD.coastal_exposure(w),
		])

	print("--- the whole 650-1400 m ARCHIPELAGO band (250 m scan) ---")
	var exposures := PackedFloat32Array()
	var min_shelter := 1.0
	for z in range(-15000, 15001, 250):
		for x in range(-15000, 15001, 250):
			var p := Vector2(float(x), float(z))
			var d := layout.sample_signed_distance(p)
			if d < 650.0 or d > 1400.0:
				continue
			if layout.classify_region(p) != WorldLayout.Region.ARCHIPELAGO:
				continue
			var w := Vector3(p.x, 0.0, p.y)
			min_shelter = minf(min_shelter, LAND_FIELD.wave_shelter(w))
			exposures.append(LAND_FIELD.coastal_exposure(w))
	exposures.sort()
	if exposures.size() > 0:
		print("  n=%d  min_shelter=%.4f" % [exposures.size(), min_shelter])
		for q in [0, 50, 75, 90, 95, 99, 100]:
			var i := clampi((exposures.size() * q) / 100, 0, exposures.size() - 1)
			print("    p%02d = %.4f" % [q, exposures[i]])
	quit()
