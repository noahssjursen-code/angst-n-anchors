class_name CoastalBirdHabitat
extends RefCounted
## Version 1 cell layout is shared with the MP wildlife disturbance service.
const CELL := 256.0
const RANGE := 1100.0
const DETAIL_RANGE := 180.0
static func identity(cell: Vector2i) -> String:
	return "%d:%d" % [cell.x, cell.y]
static func anchor(cell: Vector2i) -> Vector3:
	return Vector3((cell.x + 0.5) * CELL, WaveSurface.WATER_LEVEL, (cell.y + 0.5) * CELL)
static func seed_for(cell: Vector2i, world_seed: int) -> int:
	return posmod(world_seed * 48271 + cell.x * 104729 + cell.y * 15485863, 2147483647)
static func record(cell: Vector2i, layout: WorldLayout, exclusions: Array) -> Dictionary:
	var at := anchor(cell)
	var xz := Vector2(at.x, at.z)
	if absf(at.x) > layout.half_extent_m - 100 or absf(at.z) > layout.half_extent_m - 100: return {}
	var distance := layout.sample_signed_distance(xz)
	if distance < 100.0 or distance > 650.0: return {}
	# Test the whole flight/rest envelope against fine skerries and harbour pads.
	for i in 16:
		var probe := xz + Vector2.from_angle(i * TAU / 16.0) * 85.0
		if layout.sample_signed_distance(probe) < 12 or layout.sample_height(probe) > WaveSurface.WATER_LEVEL - 1.0: return {}
	for zone in exclusions:
		if not zone is Dictionary: continue
		var bounds := WorldTerrainStreamer._zone_influence_bounds(zone)
		if bounds.grow(90.0).has_point(xz): return {}
	var seed := seed_for(cell, layout.seed)
	var species := "herring_gull"
	if CoastalBirdMotion.unit(seed,0,501) < 0.12: species = "white_tailed_eagle"
	elif CoastalBirdMotion.unit(seed,0,502) < 0.24: species = "arctic_tern"
	return {"id":identity(cell), "anchor":at, "seed":seed, "species":species,
		"count":1 if species == "white_tailed_eagle" else (6 + seed % 7 if species == "arctic_tern" else 8 + seed % 9)}
