extends SceneTree

## Scratch probe (not a test). Second pass: how far from land does the
## OPEN_WATER label actually guarantee, and where is the westernmost land?

const GENERATOR := preload("res://scripts/world/world_layout_generator.gd")
const LAND_FIELD := preload("res://scripts/weather/land_field.gd")
const FIXED_SEED := 90210


func _initialize() -> void:
	var layout: WorldLayout = GENERATOR.generate(FIXED_SEED)
	LAND_FIELD.initialize(layout)

	var ow := PackedFloat32Array()
	var westmost_land := 1.0e30
	var westmost_at := Vector2.ZERO
	for z in range(-20000, 20001, 125):
		for x in range(-20000, 20001, 125):
			var p := Vector2(float(x), float(z))
			var d := layout.sample_signed_distance(p)
			if d < 0.0 and p.x < westmost_land:
				westmost_land = p.x
				westmost_at = p
			if layout.classify_region(p) == WorldLayout.Region.OPEN_WATER:
				ow.append(d)
	ow.sort()
	print("westernmost land sample x=%.0f at (%.0f, %.0f)" % [
		westmost_land, westmost_at.x, westmost_at.y,
	])
	print("OPEN_WATER samples n=%d" % ow.size())
	for q in [0, 1, 5, 10, 25, 50, 90, 100]:
		var i := clampi((ow.size() * q) / 100, 0, ow.size() - 1)
		print("  p%03d sdf = %.1f m" % [q, ow[i]])
	var under5k := 0
	var negative := 0
	for d in ow:
		if d < 5000.0:
			under5k += 1
		if d < 0.0:
			negative += 1
	print("  OPEN_WATER samples closer than 5000 m to land: %d (%.1f%%)" % [
		under5k, 100.0 * float(under5k) / float(ow.size()),
	])
	print("  OPEN_WATER samples that are LAND: %d" % negative)

	print("--- exposure ramp: smoothstep(80, COASTAL_DISTANCE_M, d) ---")
	for d in [650.0, 900.0, 1200.0, 1306.0, 1383.4, 1400.0, 1800.0]:
		print("  d=%7.1f  coastal_opening=%.4f" % [
			d, smoothstep(80.0, LAND_FIELD.COASTAL_DISTANCE_M, d),
		])
	quit()
