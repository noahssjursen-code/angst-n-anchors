class_name WeatherEventClock
extends RefCounted

## Deterministic discrete weather events. Clients sharing seed, cell id and
## synchronized game time produce the same strike window and payload.

const STRIKE_WINDOW_HOURS := 0.05


static func window_at(game_hours: float) -> int:
	return floori(game_hours / STRIKE_WINDOW_HOURS)


static func lightning_for_window(
		world_seed: int,
		cell_id: String,
		window: int,
		convection_index: float,
) -> Dictionary:
	if convection_index < 0.22 or cell_id.is_empty():
		return {"occurs": false}
	var base := _hash(world_seed, cell_id, window, 0x51A7)
	var probability := pow(convection_index, 1.7) * 0.72
	if base > probability:
		return {"occurs": false}
	var intensity := lerpf(0.45, 1.0, _hash(world_seed, cell_id, window, 0xB017))
	var distance_m := lerpf(600.0, 7200.0, _hash(world_seed, cell_id, window, 0xD157))
	var bearing_deg := _hash(world_seed, cell_id, window, 0xBEA4) * 360.0
	return {
		"occurs": true,
		"intensity": intensity * convection_index,
		"distance_m": distance_m,
		"bearing_degrees": bearing_deg,
		"window": window,
	}


static func _hash(seed: int, cell_id: String, window: int, salt: int) -> float:
	var value := int((seed ^ window * 83492791 ^ salt) & 0x7fffffff)
	for byte in cell_id.to_utf8_buffer():
		value = int(((value ^ int(byte)) * 16777619) & 0x7fffffff)
	value = int(((value ^ (value >> 13)) * 1274126177) & 0x7fffffff)
	value = int((value ^ (value >> 16)) & 0x7fffffff)
	return float(value) / 2147483647.0
