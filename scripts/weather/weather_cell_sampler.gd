class_name WeatherCellSampler
extends RefCounted

## Stateless deterministic moving-cell sampler. The same seed, position and
## game-hour timestamp always select the same weighted component mix.

const COMPONENT_ORDER := [
	"sky", "precipitation", "wind", "fog", "sea", "convection",
]
const CELL_CACHE_LIMIT := 4096
static var _cell_cache: Dictionary = {}


static func sample(world_seed: int, world_pos: Vector3, game_hours: float) -> Dictionary:
	var profile := WeatherProfileCatalog.profile()
	if profile.is_empty():
		return {}
	var cell_size := float(profile.get("cell_size_m", 6000.0))
	var epoch_hours := float(profile.get("cell_epoch_hours", 18.0))
	var drift_values: Array = profile.get("drift_m_per_game_hour", [72.0, 26.0])
	var drift := Vector2(float(drift_values[0]), float(drift_values[1]))
	var advected := Vector2(world_pos.x, world_pos.z) - drift * game_hours
	var epoch := floori(game_hours / epoch_hours)
	var epoch_t := smoothstep(0.0, 1.0, fposmod(game_hours, epoch_hours) / epoch_hours)
	var a := _sample_epoch(world_seed, advected, cell_size, epoch)
	var b := _sample_epoch(world_seed, advected, cell_size, epoch + 1)
	var result := {}
	for key in ["cloud_cover", "precipitation", "fog_density", "wind_force", "sea_state", "convection_index", "humidity"]:
		result[key] = lerpf(float(a.get(key, 0.0)), float(b.get(key, 0.0)), epoch_t)
	result["component_ids"] = (
		(b.get("component_ids", {}) as Dictionary).duplicate()
		if epoch_t >= 0.5
		else (a.get("component_ids", {}) as Dictionary).duplicate()
	)
	result["weather_cell_id"] = str(b.get("weather_cell_id", "")) if epoch_t >= 0.5 \
		else str(a.get("weather_cell_id", ""))
	return result


static func sample_component_ids(world_seed: int, world_pos: Vector3, game_hours: float) -> Dictionary:
	return sample(world_seed, world_pos, game_hours).get("component_ids", {}) as Dictionary


static func _sample_epoch(seed: int, advected: Vector2, cell_size: float, epoch: int) -> Dictionary:
	var grid := advected / cell_size
	var base := Vector2i(floori(grid.x), floori(grid.y))
	var f := Vector2(fposmod(grid.x, 1.0), fposmod(grid.y, 1.0))
	# Keep cell interiors crisp. Only blend in a thin edge band so the chart
	# and voyage don't average every cell into the same mid-grey mush.
	const EDGE := 0.18
	var blend_x := 0.0
	if f.x < EDGE:
		blend_x = smoothstep(0.0, EDGE, f.x) - 1.0
	elif f.x > 1.0 - EDGE:
		blend_x = smoothstep(1.0 - EDGE, 1.0, f.x)
	var blend_z := 0.0
	if f.y < EDGE:
		blend_z = smoothstep(0.0, EDGE, f.y) - 1.0
	elif f.y > 1.0 - EDGE:
		blend_z = smoothstep(1.0 - EDGE, 1.0, f.y)
	var nearest := _cell_profile(seed, base.x, base.y, epoch)
	var result := {
		"cloud_cover": float(nearest["cloud_cover"]),
		"precipitation": float(nearest["precipitation"]),
		"fog_density": float(nearest["fog_density"]),
		"wind_force": float(nearest["wind_force"]),
		"sea_state": float(nearest["sea_state"]),
		"convection_index": float(nearest["convection_index"]),
		"humidity": float(nearest["humidity"]),
		"component_ids": (nearest["component_ids"] as Dictionary).duplicate(),
		"weather_cell_id": str(nearest["weather_cell_id"]),
	}
	if absf(blend_x) > 0.001:
		var nx := base.x + (1 if blend_x > 0.0 else -1)
		var neighbour := _cell_profile(seed, nx, base.y, epoch)
		var t := absf(blend_x)
		for key in ["cloud_cover", "precipitation", "fog_density", "wind_force", "sea_state", "convection_index", "humidity"]:
			result[key] = lerpf(float(result[key]), float(neighbour[key]), t)
	if absf(blend_z) > 0.001:
		var nz := base.y + (1 if blend_z > 0.0 else -1)
		var neighbour_z := _cell_profile(seed, base.x, nz, epoch)
		var tz := absf(blend_z)
		for key in ["cloud_cover", "precipitation", "fog_density", "wind_force", "sea_state", "convection_index", "humidity"]:
			result[key] = lerpf(float(result[key]), float(neighbour_z[key]), tz)
	return result


static func _cell_profile(seed: int, cell_x: int, cell_z: int, epoch: int) -> Dictionary:
	var cache_key := "%d:%d:%d:%d" % [seed, epoch, cell_x, cell_z]
	if _cell_cache.has(cache_key):
		return _cell_cache[cache_key] as Dictionary
	var result := _build_cell_profile(seed, cell_x, cell_z, epoch)
	if _cell_cache.size() >= CELL_CACHE_LIMIT:
		_cell_cache.clear()
	_cell_cache[cache_key] = result
	return result


static func _build_cell_profile(seed: int, cell_x: int, cell_z: int, epoch: int) -> Dictionary:
	var selected := {}
	var values := {}
	for dimension in COMPONENT_ORDER:
		var entry := _weighted_band(seed, cell_x, cell_z, epoch, dimension, selected)
		var band_id := str(entry.get("id", ""))
		selected[dimension] = band_id
		var unit := _unit_hash(seed, cell_x, cell_z, epoch, _salt(dimension) + 97)
		values[dimension] = WeatherProfileCatalog.value_for_band(dimension, band_id, unit)

	## Humidity is an independent diagnostic derived from the selected moist
	## components, not a hidden driver that collapses them back together.
	var humidity := clampf(
		0.28
		+ float(values["fog"]) * 0.48
		+ float(values["precipitation"]) * 0.22
		+ float(values["sky"]) * 0.14,
		0.0,
		1.0,
	)
	return {
		"cloud_cover": values["sky"],
		"precipitation": values["precipitation"],
		"fog_density": values["fog"],
		"wind_force": values["wind"],
		"sea_state": values["sea"],
		"convection_index": values["convection"],
		"humidity": humidity,
		"component_ids": selected,
		"weather_cell_id": "%d:%d:%d" % [epoch, cell_x, cell_z],
	}


static func clear_cache() -> void:
	_cell_cache.clear()


static func _weighted_band(
		seed: int,
		cell_x: int,
		cell_z: int,
		epoch: int,
		dimension: String,
		selected: Dictionary,
) -> Dictionary:
	var entries := WeatherProfileCatalog.bands(dimension)
	if entries.is_empty():
		return {}
	var weights := PackedFloat32Array()
	var total := 0.0
	for raw in entries:
		var entry := raw as Dictionary
		var weight := float(entry.get("weight", 1.0))
		var candidate_id := str(entry.get("id", ""))
		for prior_dimension in selected.keys():
			weight *= WeatherProfileCatalog.compatibility(
				str(prior_dimension),
				str(selected[prior_dimension]),
				dimension,
				candidate_id,
			)
		weights.append(maxf(weight, 0.0))
		total += maxf(weight, 0.0)
	if total <= 0.000001:
		return entries[0] as Dictionary
	var target := _unit_hash(seed, cell_x, cell_z, epoch, _salt(dimension)) * total
	var cursor := 0.0
	for i in range(entries.size()):
		cursor += weights[i]
		if target <= cursor:
			return entries[i] as Dictionary
	return entries.back() as Dictionary


static func _unit_hash(seed: int, x: int, z: int, epoch: int, salt: int) -> float:
	var value := seed
	value = int((value ^ (x * 73856093)) & 0x7fffffff)
	value = int((value ^ (z * 19349663)) & 0x7fffffff)
	value = int((value ^ (epoch * 83492791)) & 0x7fffffff)
	value = int((value ^ salt) & 0x7fffffff)
	value = int(((value ^ (value >> 13)) * 1274126177) & 0x7fffffff)
	value = int((value ^ (value >> 16)) & 0x7fffffff)
	return float(value) / 2147483647.0


static func _salt(value: String) -> int:
	var result := 2166136261
	for byte in value.to_utf8_buffer():
		result = int(((result ^ int(byte)) * 16777619) & 0x7fffffff)
	return result
