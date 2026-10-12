class_name ChartBaseRaster
extends RefCounted

## One overview raster per immutable layout, plus optional zoom tiles for the
## visible region. Camera movement never loads terrain meshes.

const SEA := Color(0.035, 0.075, 0.12, 1.0)
const LAND := Color(0.73, 0.70, 0.55, 1.0)
const COAST := Color(0.12, 0.16, 0.15, 1.0)
const MIN_RESOLUTION := 512
const MAX_RESOLUTION := 512
const DETAIL_RESOLUTION := 512
const DETAIL_CACHE_LIMIT := 8

static var _textures: Dictionary = {}
static var _detail_textures: Dictionary = {}
static var _detail_order: PackedStringArray = PackedStringArray()
## At most one pending detail bake across charts. Worker owns only immutable
## layout data and an Image; texture upload and cache mutation stay on main.
static var _pending_detail: Dictionary = {}

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
	var next_key := "%s:%d:bed%d" % [str(layout.layout_checksum), res, WorldLayout.SEABED_VERSION]
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
	poll_detail()
	if _layout == null or _overview_texture == null:
		return
	var clipped := visible_world.intersection(_overview_rect)
	if clipped.size.x <= 1.0 or clipped.size.y <= 1.0:
		_use_overview()
		return
	var overview_mpp := _overview_rect.size.x / float(_overview_resolution)
	var view_span := maxf(clipped.size.x, clipped.size.y)
	if overview_mpp <= view_span * 1.36 / float(DETAIL_RESOLUTION) * 1.5 or view_span >= _overview_rect.size.x * 0.55:
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
	if not _detail_textures.has(next_key):
		if _pending_detail.is_empty():
			var state := {}
			var immutable_layout := _layout
			var resolution := DETAIL_RESOLUTION
			var task := WorkerThreadPool.add_task(func():
				var started := Time.get_ticks_usec()
				state["image"] = _bake_region_image(immutable_layout,tile,resolution)
				state["usec"] = Time.get_ticks_usec()-started
			)
			_pending_detail = {"key":next_key,"task":task,"state":state}
		# Keep the overview available while panning into an uncached region.
		_use_overview()
		return
	_detail_key = next_key
	_detail_rect = tile
	_detail_resolution = DETAIL_RESOLUTION
	_detail_texture = _detail_textures[next_key] as ImageTexture
	texture = _detail_texture
	world_rect = _detail_rect
	_resolution = _detail_resolution


## Called by the chart process loop even when it otherwise needs no redraw.
static func poll_detail() -> bool:
	if _pending_detail.is_empty(): return false
	var task: int = _pending_detail.task
	if not WorkerThreadPool.is_task_completed(task): return false
	WorkerThreadPool.wait_for_task_completion(task)
	var key: String = _pending_detail.key
	_detail_textures[key] = ImageTexture.create_from_image(_pending_detail.state.image)
	_detail_order.append(key)
	while _detail_order.size() > DETAIL_CACHE_LIMIT:
		_detail_textures.erase(_detail_order[0])
		_detail_order.remove_at(0)
	_pending_detail = {}
	return true


## Join before chart teardown / engine shutdown. Hiding the map does not tear
## it down; normal pan/zoom never waits for the worker.
static func finish_pending_detail() -> void:
	if _pending_detail.is_empty(): return
	WorkerThreadPool.wait_for_task_completion(int(_pending_detail.task))
	_pending_detail = {}


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
	return ImageTexture.create_from_image(_bake_region_image(layout,rect,resolution))


static func _bake_region_image(layout: WorldLayout, rect: Rect2, resolution: int) -> Image:
	var depths := PackedFloat32Array()
	depths.resize(resolution * resolution)
	var land_mask := PackedByteArray()
	land_mask.resize(resolution * resolution)
	for y in range(resolution):
		for x in range(resolution):
			var world := Vector2(
				lerpf(rect.position.x, rect.end.x, (float(x) + 0.5) / float(resolution)),
				lerpf(rect.position.y, rect.end.y, (float(y) + 0.5) / float(resolution)),
			)
			var depth := layout.sample_water_depth(world, WaveSurface.WATER_LEVEL)
			# Shared elevation already determines dry land. Avoid doing a second
			# polygon query per pixel when baking zoom tiles.
			land_mask[y * resolution + x] = 1 if depth <= 0.0 else 0
			depths[y * resolution + x] = depth
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
			image.set_pixel(x, y, COAST if edge else (LAND if land else depth_colour(depths[idx])))
	return image


static func depth_colour(depth_m: float) -> Color:
	if depth_m < 10.0: return Color("7da6ac")
	if depth_m < 25.0: return Color("547f91")
	if depth_m < 50.0: return Color("365e77")
	if depth_m < 100.0: return Color("26455e")
	if depth_m < 200.0: return Color("1b334b")
	return SEA
