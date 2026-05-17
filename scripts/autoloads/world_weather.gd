extends Node

## World-authoritative weather zones.
## Call initialize() once after world generation.
## Call get_state_at(position) from anywhere — same position always returns same result.

var _zones: Array[WeatherZone] = []
var _ambient: WeatherState
var _initialized: bool = false


func _ready() -> void:
	_ambient = WeatherState.new()
	_ambient.precipitation = 0.0
	_ambient.wind_force    = 0.10
	_ambient.visibility    = 1.0
	_ambient.cloud_cover   = 0.05


func initialize(seed: int, port_positions: Array[Vector3]) -> void:
	_zones.clear()
	if not port_positions.is_empty():
		_generate_zones(seed, port_positions)
	_initialized = true


func is_initialized() -> bool:
	return _initialized


func get_state_at(world_pos: Vector3) -> WeatherState:
	if not _initialized or _zones.is_empty():
		return _ambient

	var pos2d := Vector2(world_pos.x, world_pos.z)

	# Pass 1 — blend storm / fog / squall zones against ambient.
	var total_w := 0.0
	var sum_p   := 0.0
	var sum_wf  := 0.0
	var sum_v   := 0.0
	var sum_c   := 0.0
	for zone in _zones:
		if zone.zone_type == WeatherZone.ZoneType.PORT_CALM:
			continue
		var dist := pos2d.distance_to(zone.center)
		if dist >= zone.outer_radius:
			continue
		var w := smoothstep(zone.outer_radius, zone.inner_radius, dist)
		sum_p  += zone.state.precipitation * w
		sum_wf += zone.state.wind_force    * w
		sum_v  += zone.state.visibility    * w
		sum_c  += zone.state.cloud_cover   * w
		total_w += w

	var base: WeatherState
	if total_w < 0.001:
		base = _ambient
	else:
		var zs := WeatherState.new()
		zs.precipitation = sum_p  / total_w
		zs.wind_force    = sum_wf / total_w
		zs.visibility    = sum_v  / total_w
		zs.cloud_cover   = sum_c  / total_w
		base = WeatherState.lerp_states(_ambient, zs, clampf(total_w, 0.0, 1.0))

	# Pass 2 — port calm overrides the blended result.
	# Strongest nearby port calm wins; it is not averaged with other ports.
	var port_w      := 0.0
	var port_state  : WeatherState = null
	for zone in _zones:
		if zone.zone_type != WeatherZone.ZoneType.PORT_CALM:
			continue
		var dist := pos2d.distance_to(zone.center)
		if dist >= zone.outer_radius:
			continue
		var w := smoothstep(zone.outer_radius, zone.inner_radius, dist)
		if w > port_w:
			port_w     = w
			port_state = zone.state

	if port_w > 0.001 and port_state != null:
		return WeatherState.lerp_states(base, port_state, port_w)

	return base


func get_zones() -> Array[WeatherZone]:
	return _zones


## Returns 0–1: how much PORT_CALM influence exists at world_pos.
## Used by the tracker to lerp faster when approaching a port.
func get_port_calm_factor(world_pos: Vector3) -> float:
	var pos2d := Vector2(world_pos.x, world_pos.z)
	var total  := 0.0
	for zone in _zones:
		if zone.zone_type != WeatherZone.ZoneType.PORT_CALM:
			continue
		var dist := pos2d.distance_to(zone.center)
		if dist < zone.outer_radius:
			total += smoothstep(zone.outer_radius, zone.inner_radius, dist)
	return clampf(total, 0.0, 1.0)


func _generate_zones(seed: int, ports: Array[Vector3]) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed ^ 0xF00DBABE

	var port_2d: Array[Vector2] = []
	for p in ports:
		port_2d.append(Vector2(p.x, p.z))

	_place_port_calm_zones(port_2d)
	_place_storms(rng, port_2d, maxi(3, ports.size() / 5))
	_place_fog_banks(rng, port_2d, maxi(2, ports.size() / 8))
	_place_squalls(rng, port_2d, maxi(2, ports.size() / 10))


func _place_storms(rng: RandomNumberGenerator, ports: Array[Vector2], count: int) -> void:
	var placed := 0
	var tries  := 0
	while placed < count and tries < count * 8:
		tries += 1
		var idx_a := rng.randi() % ports.size()
		var idx_b := rng.randi() % ports.size()
		if idx_b == idx_a:
			continue
		var mid   := (ports[idx_a] + ports[idx_b]) * 0.5
		var angle := rng.randf() * TAU
		mid += Vector2(cos(angle), sin(angle)) * rng.randf_range(80.0, 350.0)
		if _near_port(mid, ports, 180.0):
			continue
		var z             := WeatherZone.new()
		z.center          = mid
		z.inner_radius    = rng.randf_range(350.0, 650.0)
		z.outer_radius    = z.inner_radius * rng.randf_range(2.2, 3.5)
		z.zone_type       = WeatherZone.ZoneType.STORM
		z.state           = WeatherState.new()
		z.state.precipitation = rng.randf_range(0.45, 0.95)
		z.state.wind_force    = rng.randf_range(0.50, 1.00)
		z.state.visibility    = rng.randf_range(0.35, 0.70)
		z.state.cloud_cover   = rng.randf_range(0.65, 1.00)
		_zones.append(z)
		placed += 1


func _place_fog_banks(rng: RandomNumberGenerator, ports: Array[Vector2], count: int) -> void:
	for _i in range(count):
		var base   := ports[rng.randi() % ports.size()]
		var angle  := rng.randf() * TAU
		var center := base + Vector2(cos(angle), sin(angle)) * rng.randf_range(120.0, 450.0)
		var z             := WeatherZone.new()
		z.center          = center
		z.inner_radius    = rng.randf_range(150.0, 320.0)
		z.outer_radius    = z.inner_radius * rng.randf_range(1.8, 2.8)
		z.zone_type       = WeatherZone.ZoneType.FOG
		z.state           = WeatherState.new()
		z.state.precipitation = rng.randf_range(0.00, 0.18)
		z.state.wind_force    = rng.randf_range(0.00, 0.20)
		z.state.visibility    = rng.randf_range(0.30, 0.60)
		z.state.cloud_cover   = rng.randf_range(0.35, 0.70)
		_zones.append(z)


func _place_squalls(rng: RandomNumberGenerator, ports: Array[Vector2], count: int) -> void:
	for _i in range(count):
		var base   := ports[rng.randi() % ports.size()]
		var angle  := rng.randf() * TAU
		var center := base + Vector2(cos(angle), sin(angle)) * rng.randf_range(250.0, 700.0)
		var z             := WeatherZone.new()
		z.center          = center
		z.inner_radius    = rng.randf_range(280.0, 550.0)
		z.outer_radius    = z.inner_radius * rng.randf_range(2.0, 3.0)
		z.zone_type       = WeatherZone.ZoneType.SQUALL
		z.state           = WeatherState.new()
		z.state.precipitation = rng.randf_range(0.10, 0.40)
		z.state.wind_force    = rng.randf_range(0.30, 0.58)
		z.state.visibility    = rng.randf_range(0.55, 0.90)
		z.state.cloud_cover   = rng.randf_range(0.40, 0.80)
		_zones.append(z)


func _place_port_calm_zones(ports: Array[Vector2]) -> void:
	for p in ports:
		var z             := WeatherZone.new()
		z.center          = p
		z.inner_radius    = 180.0
		z.outer_radius    = 600.0
		z.zone_type       = WeatherZone.ZoneType.PORT_CALM
		z.state           = WeatherState.new()
		z.state.precipitation = 0.0
		z.state.wind_force    = 0.04
		z.state.visibility    = 0.92
		z.state.cloud_cover   = 0.05
		_zones.append(z)


func _near_port(pos: Vector2, ports: Array[Vector2], min_dist: float) -> bool:
	for p in ports:
		if pos.distance_to(p) < min_dist:
			return true
	return false
