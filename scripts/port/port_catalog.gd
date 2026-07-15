extends Node

## Autoload — live port directory for chart, proximity, spawn, and HUDs.
## Replaces ContractRegistry's non-trade jobs. No contracts, stock, or pay.

## port_id -> { id, display_name, position, spawn_pos, ... }
var _ports: Dictionary = {}


func register_port(
		port_id: String,
		display_name: String,
		world_pos: Vector3,
		spawn_pos: Vector3 = Vector3(INF, INF, INF),
		commodity_export: String = "",
		commodity_imports: Array = [],
		island_width: float = 0.0,
		plot_depth: float = 140.0,
		layout_seed: int = 0,
		population: int = 0,
		features: Array = [],
		rotation_y: float = -INF,
		berth_count: int = 0,
		size: int = -1,
) -> void:
	if port_id.is_empty():
		return
	var already_known := _ports.has(port_id)
	var entry := {
		"id": port_id,
		"display_name": display_name,
		"position": world_pos,
		"spawn_pos": spawn_pos if spawn_pos != Vector3(INF, INF, INF) else world_pos,
		"commodity_export": commodity_export,
		"commodity_imports": commodity_imports.duplicate(),
		"island_width": island_width,
		"plot_depth": plot_depth,
		"layout_seed": layout_seed,
		"population": population,
		"features": features.duplicate(),
		"rotation_y": rotation_y if rotation_y != -INF else 0.0,
		"berth_count": berth_count if berth_count > 0 else 1,
		"size": size if size >= 0 else 1,
	}
	if already_known:
		var prev := _ports[port_id] as Dictionary
		if island_width == 0.0:
			entry["island_width"] = prev.get("island_width", 0.0)
			entry["plot_depth"] = prev.get("plot_depth", 140.0)
			entry["layout_seed"] = prev.get("layout_seed", 0)
		if commodity_export.is_empty():
			entry["commodity_export"] = prev.get("commodity_export", "")
		if commodity_imports.is_empty():
			entry["commodity_imports"] = prev.get("commodity_imports", [])
		if population == 0:
			entry["population"] = prev.get("population", 0)
		if features.is_empty():
			entry["features"] = prev.get("features", [])
		if rotation_y == -INF:
			entry["rotation_y"] = prev.get("rotation_y", 0.0)
		if berth_count == 0:
			entry["berth_count"] = prev.get("berth_count", 1)
		if size < 0:
			entry["size"] = prev.get("size", 1)
		if spawn_pos == Vector3(INF, INF, INF):
			entry["spawn_pos"] = prev.get("spawn_pos", world_pos)
	_ports[port_id] = entry


func unregister_port(port_id: String) -> void:
	_ports.erase(port_id)


func clear() -> void:
	_ports.clear()


func get_port_ids() -> Array[String]:
	var ids: Array[String] = []
	for key in _ports.keys():
		ids.append(str(key))
	ids.sort()
	return ids


func get_port_info(port_id: String) -> Dictionary:
	return (_ports.get(port_id, {}) as Dictionary).duplicate(true)


func get_port_display_name(port_id: String) -> String:
	var info := _ports.get(port_id, {}) as Dictionary
	return str(info.get("display_name", port_id))


func get_port_position(port_id: String) -> Vector3:
	var info := _ports.get(port_id, {}) as Dictionary
	return info.get("position", Vector3(INF, INF, INF)) as Vector3


func get_port_spawn_position(port_id: String) -> Vector3:
	var info := _ports.get(port_id, {}) as Dictionary
	return info.get("spawn_pos", info.get("position", Vector3(INF, INF, INF))) as Vector3


func nearest_port_id(xz: Vector2, max_radius_m: float = INF) -> String:
	var best_id := ""
	var best_d := max_radius_m
	for port_id in _ports.keys():
		var info := _ports[port_id] as Dictionary
		var pos := info.get("position", Vector3.ZERO) as Vector3
		var d := xz.distance_to(Vector2(pos.x, pos.z))
		if d < best_d:
			best_d = d
			best_id = str(port_id)
	return best_id
