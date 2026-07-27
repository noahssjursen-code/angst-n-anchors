class_name ChartRasterLayer
extends RefCounted

enum Kind { WEATHER, FISHING }

const COLS := 32
const ROWS := 24
const FISHING_RESOLUTION := 96
const WEATHER_MAX_AGE_H := 0.08
const WEATHER_OVERSCAN := 0.85

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
	var lod := _weather_lod(visible_world)
	var snapped := _snap_bounds(visible_world, lod.x, lod.y)
	var bucket := floori(game_hours / WEATHER_MAX_AGE_H)
	var next_key := "%d:%d:%d:%d:%d:%d:%d:%d" % [
		snapshot.world_seed,
		roundi(snapped.position.x),
		roundi(snapped.position.y),
		roundi(snapped.size.x),
		roundi(snapped.size.y),
		bucket,
		lod.x,
		lod.y,
	]
	if next_key == _view_key and texture != null:
		return false
	_view_key = next_key
	_time_bucket = bucket
	_raster_cols = lod.x
	_raster_rows = lod.y
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
	var step_x := maxi(3, _raster_cols / 8)
	var step_y := maxi(3, _raster_rows / 6)
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
					BrandTokens.alpha(BrandTokens.CHART_ZONE_WEATHER, 0.25 + sea * 0.35),
					1.0,
					true,
				)
			if wind.length_squared() < 0.0025:
				continue
			var direction := wind.normalized()
			var length := 11.0 + minf(wind.length(), 1.0) * 9.0
			var tail := center - direction * length * 0.5
			var head := center + direction * length * 0.5
			var color := BrandTokens.alpha(BrandTokens.INK_INVERSE, 0.78)
			canvas.draw_line(tail, head, color, 1.3, true)
			var side := Vector2(-direction.y, direction.x)
			canvas.draw_line(head, head - direction * 4.0 + side * 2.5, color, 1.3, true)
			canvas.draw_line(head, head - direction * 4.0 - side * 2.5, color, 1.3, true)


func sample_at(world: Vector2, game_hours: float) -> Dictionary:
	if kind == Kind.FISHING:
		return FishingField.sample_chart(Vector3(world.x, 0.0, world.y))
	var sample := WeatherComposer.sample_chart(Vector3(world.x, 0.0, world.y), game_hours)
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
	_wind.resize(_raster_cols * _raster_rows)
	_sea.resize(_raster_cols * _raster_rows)
	sample_count = 0
	var bytes := PackedByteArray()
	bytes.resize(_raster_cols * _raster_rows * 4)
	if kind == Kind.WEATHER:
		for y in range(_raster_rows):
			for x in range(_raster_cols):
				var world := Vector2(
					lerpf(world_rect.position.x, world_rect.end.x, (float(x) + 0.5) / _raster_cols),
					lerpf(world_rect.position.y, world_rect.end.y, (float(y) + 0.5) / _raster_rows),
				)
				var idx := y * _raster_cols + x
				var sample := WeatherComposer.sample_chart(
					Vector3(world.x, 0.0, world.y), game_hours
				)
				var color := _weather_color(sample)
				_write_rgba(bytes, idx, color)
				_wind[idx] = Vector2(sample.wind.x, sample.wind.z)
				_sea[idx] = sample.sea_state
				sample_count += 1
	else:
		var fishing_zones: Array[Dictionary] = []
		fishing_zones.resize(_raster_cols * _raster_rows)
		for y2 in range(_raster_rows):
			for x2 in range(_raster_cols):
				var world2 := Vector2(
					lerpf(world_rect.position.x, world_rect.end.x, (float(x2) + 0.5) / _raster_cols),
					lerpf(world_rect.position.y, world_rect.end.y, (float(y2) + 0.5) / _raster_rows),
				)
				var idx2 := y2 * _raster_cols + x2
				var zone := FishingField.sample_chart(Vector3(world2.x, 0.0, world2.y))
				fishing_zones[idx2] = zone
				_wind[idx2] = Vector2.ZERO
				_sea[idx2] = 0.0
				sample_count += 1
		for y3 in range(_raster_rows):
			for x3 in range(_raster_cols):
				var idx3 := y3 * _raster_cols + x3
				var zone3 := fishing_zones[idx3] as Dictionary
				var open := bool(zone3.get("open_water", false))
				var tier := str(zone3.get("tier_id", "normal"))
				var edge := false
				if open:
					for offset_raw in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
						var offset := offset_raw as Vector2i
						var nx: int = x3 + offset.x
						var ny: int = y3 + offset.y
						if nx < 0 or ny < 0 or nx >= _raster_cols or ny >= _raster_rows:
							edge = true
							continue
						var neighbour := fishing_zones[ny * _raster_cols + nx] as Dictionary
						if (
							not bool(neighbour.get("open_water", false))
							or str(neighbour.get("tier_id", "normal")) != tier
						):
							edge = true
				var color := Color.TRANSPARENT
				if edge and (x3 + y3) % 5 != 4:
					var strong := tier == "rich" or tier == "prolific"
					color = BrandTokens.alpha(
						BrandTokens.CHART_ZONE_FISH,
						0.58 if strong else 0.34
					)
				_write_rgba(bytes, idx3, color)
	var image := Image.create_from_data(
		_raster_cols, _raster_rows, false, Image.FORMAT_RGBA8, bytes
	)
	texture = ImageTexture.create_from_image(image)
	rebuild_count += 1
	last_build_usec = Time.get_ticks_usec() - started


static func _write_rgba(bytes: PackedByteArray, pixel_index: int, color: Color) -> void:
	var i := pixel_index * 4
	bytes[i] = int(clampf(color.r * 255.0, 0.0, 255.0))
	bytes[i + 1] = int(clampf(color.g * 255.0, 0.0, 255.0))
	bytes[i + 2] = int(clampf(color.b * 255.0, 0.0, 255.0))
	bytes[i + 3] = int(clampf(color.a * 255.0, 0.0, 255.0))


static func _weather_lod(visible_world: Rect2) -> Vector2i:
	var span := maxf(visible_world.size.x, visible_world.size.y)
	if span >= 28000.0:
		return Vector2i(16, 12)
	if span >= 12000.0:
		return Vector2i(24, 18)
	return Vector2i(COLS, ROWS)


func _snap_bounds(bounds: Rect2, cols: int, rows: int) -> Rect2:
	## Large overscan so typical pans reuse the last weather texture.
	var grown := bounds.grow(maxf(bounds.size.x, bounds.size.y) * WEATHER_OVERSCAN)
	var cell := maxf(grown.size.x / float(cols), grown.size.y / float(rows))
	## Coarse snap — avoids rebuilds for small camera nudges.
	cell = maxf(cell, 250.0)
	var origin := Vector2(
		floorf(grown.position.x / cell) * cell,
		floorf(grown.position.y / cell) * cell,
	)
	return Rect2(origin, Vector2(cell * float(cols), cell * float(rows)))


static func _weather_color(sample: WeatherSample) -> Color:
	var clear := BrandTokens.alpha(BrandTokens.CHART_ZONE_WEATHER, 0.22)
	var overcast := BrandTokens.alpha(BrandTokens.CLOUD_DARK, 0.48)
	var rain := BrandTokens.alpha(BrandTokens.RAIN, 0.62)
	var storm := BrandTokens.alpha(BrandTokens.ALERT, 0.72)
	var fog := BrandTokens.alpha(BrandTokens.FOG, 0.58)
	var color := clear.lerp(overcast, sample.cloud_cover)
	color = color.lerp(rain, smoothstep(0.12, 0.75, sample.precipitation))
	color = color.lerp(storm, smoothstep(0.35, 0.9, sample.convection_index))
	color = color.lerp(fog, smoothstep(0.12, 0.7, sample.fog_density))
	color = color.lerp(
		BrandTokens.alpha(BrandTokens.WATER_MID, 0.70),
		smoothstep(0.25, 0.85, sample.sea_state) * 0.55
	)
	color.a = clampf(color.a, 0.18, 0.78)
	return color


static func _fishing_color(zone: Dictionary) -> Color:
	if not bool(zone.get("open_water", false)):
		return Color.TRANSPARENT
	var strong := str(zone.get("tier_id", "normal")) in ["rich", "prolific"]
	return BrandTokens.alpha(BrandTokens.CHART_ZONE_FISH, 0.16 if strong else 0.08)


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
