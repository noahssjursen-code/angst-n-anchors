class_name ChartBaseRaster
extends RefCounted

## One overview raster per immutable layout, plus optional zoom tiles for the
## visible region. Camera movement never loads terrain meshes.

static var SEA := BrandTokens.CHART_SEA
static var LAND := BrandTokens.CHART_LAND
static var COAST := BrandTokens.CHART_CONTOUR
const MIN_RESOLUTION := 256
const MAX_RESOLUTION := 512
const DETAIL_RESOLUTION := 256
## When overview metres/pixel exceed this, bake a viewport tile instead.
const DETAIL_MPP_THRESHOLD := 90.0
const DETAIL_CACHE_LIMIT := 8

static var _textures: Dictionary = {}
static var _detail_textures: Dictionary = {}
static var _detail_order: PackedStringArray = PackedStringArray()

var texture: ImageTexture
var world_rect := Rect2()
var cache_key := ""
var build_usec := 0
var _resolution: int = MIN_RESOLUTION
var _layout: WorldLayout
var _overview_texture: ImageTexture
var _overview_rect := Rect2()
var _overview_resolution: int = MIN_RESOLUTION
var _detail_texture: ImageTexture
var _detail_rect := Rect2()
var _detail_resolution: int = DETAIL_RESOLUTION
var _detail_key := ""


## Overview raster scales with world half-extent (cap 512) — chart never loads terrain meshes.
static func resolution_for_half_extent(half_m: float) -> int:
	var res := int(round(float(MIN_RESOLUTION) * maxf(half_m, 1.0) / 20000.0))
	res = clampi(res, MIN_RESOLUTION, MAX_RESOLUTION)
	if res % 2 == 1:
		res += 1
	return res


func prepare(layout: WorldLayout) -> void:
	if layout == null:
		return
	_layout = layout
	var half := float(layout.half_extent_m)
	var res := resolution_for_half_extent(half)
	var next_key := "%s:%d" % [str(layout.layout_checksum), res]
	if next_key.is_empty() or str(layout.layout_checksum).is_empty():
		next_key = "%d:%d" % [layout.get_instance_id(), res]
	if next_key == cache_key and _overview_texture != null:
		texture = _overview_texture
		world_rect = _overview_rect
		_resolution = _overview_resolution
		return
	cache_key = next_key
	_overview_resolution = res
	_overview_rect = Rect2(-half, -half, half * 2.0, half * 2.0)
	if _textures.has(cache_key):
		_overview_texture = _textures[cache_key] as ImageTexture
	else:
		var started := Time.get_ticks_usec()
		_overview_texture = _bake_region(layout, _overview_rect, _overview_resolution)
		_textures[cache_key] = _overview_texture
		build_usec = Time.get_ticks_usec() - started
	texture = _overview_texture
	world_rect = _overview_rect
	_resolution = _overview_resolution
	_detail_texture = null
	_detail_key = ""


func prepare_visible(visible_world: Rect2) -> void:
	if _layout == null or _overview_texture == null:
		return
	var clipped := visible_world.intersection(_overview_rect)
	if clipped.size.x <= 1.0 or clipped.size.y <= 1.0:
		_use_overview()
		return
	var overview_mpp := _overview_rect.size.x / float(_overview_resolution)
	var view_span := maxf(clipped.size.x, clipped.size.y)
	if overview_mpp <= DETAIL_MPP_THRESHOLD or view_span >= _overview_rect.size.x * 0.55:
		_use_overview()
		return
	## Pad so pan/zoom does not rebuild every pixel.
	var pad := view_span * 0.18
	var tile := Rect2(clipped.position - Vector2(pad, pad), clipped.size + Vector2(pad, pad) * 2.0)
	tile = tile.intersection(_overview_rect)
	if tile.size.x <= 1.0 or tile.size.y <= 1.0:
		_use_overview()
		return
	## Snap tile corners so nearby pans share one cache entry.
	var snap := maxf(250.0, view_span * 0.25)
	tile.position.x = floorf(tile.position.x / snap) * snap
	tile.position.y = floorf(tile.position.y / snap) * snap
	tile.size.x = ceilf(tile.size.x / snap) * snap
	tile.size.y = ceilf(tile.size.y / snap) * snap
	tile = tile.intersection(_overview_rect)
	var next_key := "%s:%.0f:%.0f:%.0f:%.0f" % [
		cache_key,
		tile.position.x,
		tile.position.y,
		tile.size.x,
		tile.size.y,
	]
	if next_key == _detail_key and _detail_texture != null:
		texture = _detail_texture
		world_rect = _detail_rect
		_resolution = _detail_resolution
		return
	_detail_key = next_key
	_detail_rect = tile
	_detail_resolution = DETAIL_RESOLUTION
	if _detail_textures.has(next_key):
		_detail_texture = _detail_textures[next_key] as ImageTexture
	else:
		var started := Time.get_ticks_usec()
		_detail_texture = _bake_region(_layout, tile, _detail_resolution)
		_detail_textures[next_key] = _detail_texture
		_detail_order.append(next_key)
		while _detail_order.size() > DETAIL_CACHE_LIMIT:
			var old := _detail_order[0]
			_detail_order.remove_at(0)
			_detail_textures.erase(old)
		build_usec = Time.get_ticks_usec() - started
	texture = _detail_texture
	world_rect = _detail_rect
	_resolution = _detail_resolution


func draw(
	canvas: CanvasItem,
	chart_rect: Rect2,
	visible_world: Rect2,
	allow_detail: bool = true,
) -> void:
	if allow_detail:
		prepare_visible(visible_world)
	else:
		_use_overview()
	if texture == null or world_rect.size.x <= 0.0:
		canvas.draw_rect(chart_rect, SEA)
		return
	canvas.draw_rect(chart_rect, SEA)
	var clipped := visible_world.intersection(world_rect)
	if clipped.size.x <= 0.0 or clipped.size.y <= 0.0:
		return
	var dest_position := chart_rect.position + Vector2(
		(clipped.position.x - visible_world.position.x) / visible_world.size.x * chart_rect.size.x,
		(clipped.position.y - visible_world.position.y) / visible_world.size.y * chart_rect.size.y,
	)
	var dest_size := Vector2(
		clipped.size.x / visible_world.size.x * chart_rect.size.x,
		clipped.size.y / visible_world.size.y * chart_rect.size.y,
	)
	var source := Rect2(
		Vector2(
			(clipped.position.x - world_rect.position.x) / world_rect.size.x * float(_resolution),
			(clipped.position.y - world_rect.position.y) / world_rect.size.y * float(_resolution),
		),
		Vector2(
			clipped.size.x / world_rect.size.x * float(_resolution),
			clipped.size.y / world_rect.size.y * float(_resolution),
		),
	)
	canvas.draw_texture_rect_region(texture, Rect2(dest_position, dest_size), source)


func _use_overview() -> void:
	texture = _overview_texture
	world_rect = _overview_rect
	_resolution = _overview_resolution


static func _bake_region(layout: WorldLayout, rect: Rect2, resolution: int) -> ImageTexture:
	var land_mask := PackedByteArray()
	land_mask.resize(resolution * resolution)
	for y in range(resolution):
		for x in range(resolution):
			var world := Vector2(
				lerpf(rect.position.x, rect.end.x, (float(x) + 0.5) / float(resolution)),
				lerpf(rect.position.y, rect.end.y, (float(y) + 0.5) / float(resolution)),
			)
			land_mask[y * resolution + x] = 1 if layout.is_land(world) else 0
	var image := Image.create(resolution, resolution, false, Image.FORMAT_RGBA8)
	for y in range(resolution):
		for x in range(resolution):
			var idx := y * resolution + x
			var land := land_mask[idx] == 1
			var edge := false
			if land:
				for offset_raw in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
					var offset := offset_raw as Vector2i
					var nx: int = x + offset.x
					var ny: int = y + offset.y
					if nx < 0 or ny < 0 or nx >= resolution or ny >= resolution:
						continue
					if land_mask[ny * resolution + nx] == 0:
						edge = true
						break
			image.set_pixel(x, y, COAST if edge else (LAND if land else SEA))
	return ImageTexture.create_from_image(image)
