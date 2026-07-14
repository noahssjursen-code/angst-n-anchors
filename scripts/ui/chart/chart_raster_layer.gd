class_name ChartRasterLayer
extends RefCounted

enum Kind { WEATHER, FISHING }

const COLS := 32
const ROWS := 24
const FISHING_RESOLUTION := 256
const WEATHER_MAX_AGE_H := 0.05

var kind := Kind.WEATHER
var texture: ImageTexture
var world_rect := Rect2()
var rebuild_count := 0
var sample_count := 0
var last_build_usec := 0
var _time_bucket := -9223372036854775808
var _view_key := ""
var _wind: PackedVector2Array = PackedVector2Array()
var _sea: PackedFloat32Array = PackedFloat32Array()
var _raster_cols := COLS
var _raster_rows := ROWS


func _init(layer_kind: int = Kind.WEATHER) -> void:
	kind = layer_kind


func invalidate() -> void:
	_view_key = ""
	_time_bucket = -9223372036854775808


func prepare(snapshot, visible_world: Rect2, game_hours: float) -> bool:
	if snapshot == null or not snapshot.is_valid():
		return false
	if kind == Kind.FISHING:
		var fishing_key := "%d:%s" % [snapshot.world_seed, snapshot.layout_checksum]
		if fishing_key == _view_key and texture != null:
			return false
		_view_key = fishing_key
		_time_bucket = 0
		_raster_cols = FISHING_RESOLUTION
		_raster_rows = FISHING_RESOLUTION
		var half := float(snapshot.layout.half_extent_m)
		world_rect = Rect2(-half, -half, half * 2.0, half * 2.0)
		_build(snapshot, game_hours)
		return true
	var snapped := _snap_bounds(visible_world)
	var bucket := floori(game_hours / WEATHER_MAX_AGE_H)
	var next_key := "%d:%d:%d:%d:%d:%d" % [
		snapshot.world_seed,
		roundi(snapped.position.x),
		roundi(snapped.position.y),
		roundi(snapped.size.x),
		roundi(snapped.size.y),
		bucket,
	]
	if next_key == _view_key and texture != null:
		return false
	_view_key = next_key
	_time_bucket = bucket
	_raster_cols = COLS
	_raster_rows = ROWS
	world_rect = snapped
	_build(snapshot, game_hours)
	return true


func draw(canvas: CanvasItem, chart_rect: Rect2, visible_world: Rect2) -> void:
	if texture == null:
		return
	var clipped := visible_world.intersection(world_rect)
	if clipped.size.x <= 0.0 or clipped.size.y <= 0.0:
		return
	var dest := _world_rect_to_screen(clipped, chart_rect, visible_world)
	var source := Rect2(
		Vector2(
			(clipped.position.x - world_rect.position.x) / world_rect.size.x * _raster_cols,
			(clipped.position.y - world_rect.position.y) / world_rect.size.y * _raster_rows,
		),
		Vector2(
			clipped.size.x / world_rect.size.x * _raster_cols,
			clipped.size.y / world_rect.size.y * _raster_rows,
		),
	)
	canvas.draw_texture_rect_region(texture, dest, source)


func draw_wind(canvas: CanvasItem, chart_rect: Rect2, visible_world: Rect2) -> void:
	if kind != Kind.WEATHER or _wind.is_empty():
		return
	var step_x := 4
	var step_y := 4
	for y in range(2, _raster_rows, step_y):
		for x in range(2, _raster_cols, step_x):
			var idx := y * _raster_cols + x
			var wind := _wind[idx]
			var world := Vector2(
				lerpf(world_rect.position.x, world_rect.end.x, (float(x) + 0.5) / _raster_cols),
				lerpf(world_rect.position.y, world_rect.end.y, (float(y) + 0.5) / _raster_rows),
			)
			if not visible_world.has_point(world):
				continue
			var center := _world_to_screen(world, chart_rect, visible_world)
			var sea := _sea[idx] if idx < _sea.size() else 0.0
			if sea > 0.32:
				canvas.draw_arc(
					center,
					3.0 + sea * 4.0,
					0.0,
					TAU,
					12,
					Color(0.34, 0.78, 0.94, 0.25 + sea * 0.35),
					1.0,
					true,
				)
			if wind.length_squared() < 0.0025:
				continue
			var direction := wind.normalized()
			var length := 11.0 + minf(wind.length(), 1.0) * 9.0
			var tail := center - direction * length * 0.5
			var head := center + direction * length * 0.5
			var color := Color(0.95, 0.98, 1.0, 0.78)
			canvas.draw_line(tail, head, color, 1.3, true)
			var side := Vector2(-direction.y, direction.x)
			canvas.draw_line(head, head - direction * 4.0 + side * 2.5, color, 1.3, true)
			canvas.draw_line(head, head - direction * 4.0 - side * 2.5, color, 1.3, true)


func sample_at(world: Vector2, game_hours: float) -> Dictionary:
	if kind == Kind.FISHING:
		return FishingField.sample_chart(Vector3(world.x, 0.0, world.y))
	var sample := _canonical_weather_sample(Vector3(world.x, 0.0, world.y), game_hours)
	return {
		"pressure": sample.pressure,
		"wind": sample.wind,
		"wind_speed_ms": sample.wind_speed_ms,
		"cloud_cover": sample.cloud_cover,
		"precipitation": sample.precipitation,
		"visibility": sample.visibility,
		"temperature": sample.temperature,
		"sea_state": sample.sea_state,
		"significant_wave_height_m": sample.significant_wave_height_m,
		"convection_index": sample.convection_index,
		"component_ids": sample.component_ids.duplicate(),
		"weather_cell_id": sample.weather_cell_id,
	}


func debug_stats() -> Dictionary:
	return {
		"cache_cells": _raster_cols * _raster_rows if texture != null else 0,
		"cache_rebuilds": rebuild_count,
		"samples": sample_count,
		"build_usec": last_build_usec,
	}


func _build(snapshot, game_hours: float) -> void:
	var started := Time.get_ticks_usec()
	WeatherField.world_seed = snapshot.world_seed
	if kind == Kind.FISHING and FishingField.world_seed != snapshot.world_seed:
		FishingField.initialize(snapshot.world_seed)
	var image := Image.create(_raster_cols, _raster_rows, false, Image.FORMAT_RGBA8)
	_wind.resize(_raster_cols * _raster_rows)
	_sea.resize(_raster_cols * _raster_rows)
	var weather_samples: Array[WeatherSample] = []
	if kind == Kind.WEATHER:
		var positions := PackedVector3Array()
		positions.resize(_raster_cols * _raster_rows)
		for sample_y in range(_raster_rows):
			for sample_x in range(_raster_cols):
				var sample_world := Vector2(
					lerpf(world_rect.position.x, world_rect.end.x, (float(sample_x) + 0.5) / _raster_cols),
					lerpf(world_rect.position.y, world_rect.end.y, (float(sample_y) + 0.5) / _raster_rows),
				)
				positions[sample_y * _raster_cols + sample_x] = Vector3(sample_world.x, 0.0, sample_world.y)
		weather_samples = _canonical_weather_batch(positions, game_hours)
	sample_count = 0
	for y in range(_raster_rows):
		for x in range(_raster_cols):
			var world := Vector2(
				lerpf(world_rect.position.x, world_rect.end.x, (float(x) + 0.5) / _raster_cols),
				lerpf(world_rect.position.y, world_rect.end.y, (float(y) + 0.5) / _raster_rows),
			)
			var idx := y * _raster_cols + x
			if kind == Kind.WEATHER:
				var sample := weather_samples[idx]
				image.set_pixel(x, y, _weather_color(sample))
				_wind[idx] = Vector2(sample.wind.x, sample.wind.z)
				_sea[idx] = sample.sea_state
			else:
				var zone := FishingField.sample_chart(Vector3(world.x, 0.0, world.y))
				image.set_pixel(x, y, _fishing_color(zone))
				_wind[idx] = Vector2.ZERO
				_sea[idx] = 0.0
			sample_count += 1
	texture = ImageTexture.create_from_image(image)
	rebuild_count += 1
	last_build_usec = Time.get_ticks_usec() - started


func _snap_bounds(bounds: Rect2) -> Rect2:
	# Overscan by one quarter-view. The texture remains useful while panning;
	# rebuilding happens after input settles, never on pointer motion.
	var grown := bounds.grow(maxf(bounds.size.x, bounds.size.y) * 0.25)
	var cell := maxf(grown.size.x / COLS, grown.size.y / ROWS)
	var origin := Vector2(
		floorf(grown.position.x / cell) * cell,
		floorf(grown.position.y / cell) * cell,
	)
	return Rect2(origin, Vector2(cell * COLS, cell * ROWS))


static func _weather_color(sample: WeatherSample) -> Color:
	# High-contrast chart grade so cells read as distinct weather, not one blue wash.
	var clear := Color(0.18, 0.62, 0.92, 0.22)
	var overcast := Color(0.42, 0.45, 0.50, 0.48)
	var rain := Color(0.16, 0.34, 0.28, 0.62)
	var storm := Color(0.52, 0.18, 0.22, 0.72)
	var fog := Color(0.86, 0.88, 0.90, 0.58)
	var color := clear.lerp(overcast, sample.cloud_cover)
	color = color.lerp(rain, smoothstep(0.12, 0.75, sample.precipitation))
	color = color.lerp(storm, smoothstep(0.35, 0.9, sample.convection_index))
	color = color.lerp(fog, smoothstep(0.12, 0.7, sample.fog_density))
	# Sea state darkens/teals the tint so high swell is visible even under clear sky.
	color = color.lerp(Color(0.05, 0.28, 0.42, 0.70), smoothstep(0.25, 0.85, sample.sea_state) * 0.55)
	color.a = clampf(color.a, 0.18, 0.78)
	return color


static func _canonical_weather_sample(world_pos: Vector3, game_hours: float) -> WeatherSample:
	var loop := Engine.get_main_loop() as SceneTree
	var world_weather := loop.root.get_node_or_null("WorldWeather") if loop != null else null
	if world_weather != null and bool(world_weather.call("is_initialized")):
		return world_weather.call("sample_at", world_pos, game_hours) as WeatherSample
	return WeatherComposer.sample(world_pos, game_hours)


static func _canonical_weather_batch(
		positions: PackedVector3Array,
		game_hours: float,
) -> Array[WeatherSample]:
	var loop := Engine.get_main_loop() as SceneTree
	var world_weather := loop.root.get_node_or_null("WorldWeather") if loop != null else null
	if world_weather != null and bool(world_weather.call("is_initialized")):
		var canonical: Array[WeatherSample] = []
		for item in world_weather.call("sample_batch", positions, game_hours):
			canonical.append(item as WeatherSample)
		return canonical
	var result: Array[WeatherSample] = []
	result.resize(positions.size())
	for i in range(positions.size()):
		result[i] = WeatherComposer.sample(positions[i], game_hours)
	return result


static func _fishing_color(zone: Dictionary) -> Color:
	if not bool(zone.get("open_water", false)):
		return Color(0.0, 0.0, 0.0, 0.0)
	var color := FishingField.tier_color(str(zone.get("tier_id", "normal")))
	color.a = minf(color.a, 0.58)
	return color


static func _world_rect_to_screen(
	world: Rect2,
	chart: Rect2,
	visible: Rect2,
) -> Rect2:
	var a := _world_to_screen(world.position, chart, visible)
	var b := _world_to_screen(world.end, chart, visible)
	return Rect2(a.min(b), (b - a).abs())


static func _world_to_screen(world: Vector2, chart: Rect2, visible: Rect2) -> Vector2:
	return chart.position + Vector2(
		(world.x - visible.position.x) / visible.size.x * chart.size.x,
		(world.y - visible.position.y) / visible.size.y * chart.size.y,
	)
