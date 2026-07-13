class_name WeatherFrontField
extends RefCounted

## Small deterministic set of broad moving fronts. Sampling is O(FRONT_COUNT)
## with no replication, simulation nodes, or per-frame mutation.

const FRONT_COUNT := 6
const WORLD_HALF_EXTENT_M := 24000.0
const MIN_RADIUS_M := 4200.0
const MAX_RADIUS_M := 9000.0

static var world_seed: int = 0
static var _fronts: Array[WeatherFront] = []
static var _cached_seed := 0x7FFFFFFF


static func initialize(seed: int) -> void:
	world_seed = seed
	_ensure_fronts()


static func active_fronts(game_hours: float = -1.0) -> Array[WeatherFront]:
	_ensure_fronts()
	if game_hours < 0.0:
		game_hours = WeatherField.current_game_time()
	var active: Array[WeatherFront] = []
	for front in _fronts:
		if front.activity_at(game_hours) > 0.025:
			active.append(front)
	return active


static func sample_at(world_pos: Vector3, game_hours: float = -1.0) -> Dictionary:
	_ensure_fronts()
	if game_hours < 0.0:
		game_hours = WeatherField.current_game_time()
	var point := Vector2(world_pos.x, world_pos.z)
	var strongest := 0.0
	var strongest_front: WeatherFront
	for front in _fronts:
		var activity := front.activity_at(game_hours)
		if activity <= 0.001:
			continue
		var center := front.center_at(game_hours, WORLD_HALF_EXTENT_M)
		var delta := _wrapped_delta(point, center)
		var normalized_distance := delta.length() / maxf(front.radius_m, 1.0)
		var radial := 1.0 - smoothstep(0.28, 1.0, normalized_distance)
		var contribution := activity * radial
		if contribution > strongest:
			strongest = contribution
			strongest_front = front
	return {
		"intensity": clampf(strongest, 0.0, 1.0),
		"front": strongest_front,
		"label": strongest_front.kind_label() if strongest_front != null else "",
	}


static func fronts_in_bounds(bounds: Rect2, game_hours: float = -1.0) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for front in active_fronts(game_hours):
		var center := front.center_at(game_hours, WORLD_HALF_EXTENT_M)
		var nearest := Vector2(
			clampf(center.x, bounds.position.x, bounds.end.x),
			clampf(center.y, bounds.position.y, bounds.end.y),
		)
		if nearest.distance_squared_to(center) > front.radius_m * front.radius_m:
			continue
		rows.append({
			"id": front.id,
			"kind": front.kind,
			"label": front.kind_label(),
			"center": center,
			"velocity": front.velocity_m_per_game_hour,
			"radius_m": front.radius_m,
			"intensity": front.activity_at(game_hours),
		})
	return rows


static func _ensure_fronts() -> void:
	if _cached_seed == world_seed and _fronts.size() == FRONT_COUNT:
		return
	_cached_seed = world_seed
	_fronts.clear()
	for i in range(FRONT_COUNT):
		var front := WeatherFront.new()
		front.id = i
		front.kind = i % 3 as WeatherFront.Kind
		var hx := _hash01(world_seed, i, 11)
		var hz := _hash01(world_seed, i, 29)
		var hv := _hash01(world_seed, i, 47)
		var hs := _hash01(world_seed, i, 71)
		front.origin_xz = Vector2(
			lerpf(-WORLD_HALF_EXTENT_M, WORLD_HALF_EXTENT_M, hx),
			lerpf(-WORLD_HALF_EXTENT_M, WORLD_HALF_EXTENT_M, hz)
		)
		var angle := hv * TAU
		var speed := lerpf(35.0, 105.0, hs)
		front.velocity_m_per_game_hour = Vector2(cos(angle), sin(angle)) * speed
		front.radius_m = lerpf(MIN_RADIUS_M, MAX_RADIUS_M, _hash01(world_seed, i, 97))
		front.intensity = lerpf(0.48, 1.0, _hash01(world_seed, i, 131))
		front.phase_offset = _hash01(world_seed, i, 173) * TAU
		_fronts.append(front)


static func _wrapped_delta(a: Vector2, b: Vector2) -> Vector2:
	var span := WORLD_HALF_EXTENT_M * 2.0
	var d := a - b
	d.x = fposmod(d.x + WORLD_HALF_EXTENT_M, span) - WORLD_HALF_EXTENT_M
	d.y = fposmod(d.y + WORLD_HALF_EXTENT_M, span) - WORLD_HALF_EXTENT_M
	return d


static func _hash01(seed: int, index: int, salt: int) -> float:
	var x := int(seed) ^ (index * 0x45D9F3B) ^ salt
	x = ((x >> 16) ^ x) * 0x45D9F3B
	x = ((x >> 16) ^ x) * 0x45D9F3B
	x = (x >> 16) ^ x
	return float(x & 0x7FFFFFFF) / float(0x7FFFFFFF)
