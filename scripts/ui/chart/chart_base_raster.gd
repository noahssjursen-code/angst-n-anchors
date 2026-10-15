class_name ChartBaseRaster
extends RefCounted

## Shared immutable chart images. Cold bakes and cache I/O run off main.
## Fixed zoom bands reuse full-resolution detail during ordinary zoom/pan.
const SEA := Color(0.035, 0.075, 0.12, 1.0)
const LAND := Color(0.73, 0.70, 0.55, 1.0)
const COAST := Color(0.12, 0.16, 0.15, 1.0)
const MIN_RESOLUTION := 512
const MAX_RESOLUTION := 512
const DETAIL_RESOLUTION := 768
const PREVIEW_RESOLUTION := 64
const DETAIL_CACHE_LIMIT := 16
const WORLD_CACHE_LIMIT := 4

## The main thread may withdraw an obsolete camera request while the worker
## is sampling. Only this flag is shared concurrently; images/cache maps are
## still exchanged after joining the task.
class BakeRequest extends RefCounted:
	var _mutex := Mutex.new()
	var _cancelled := false

	func cancel() -> void:
		_mutex.lock()
		_cancelled = true
		_mutex.unlock()

	func is_cancelled() -> bool:
		_mutex.lock()
		var result := _cancelled
		_mutex.unlock()
		return result

static var _textures: Dictionary = {}
static var _world_order := PackedStringArray()
static var _pending_overviews: Dictionary = {}
static var _detail_textures: Dictionary = {}
static var _detail_rects: Dictionary = {}
static var _detail_order := PackedStringArray()
## One pending detail across charts prevents an obsolete-zoom task backlog.
static var _pending_detail: Dictionary = {}
static var _memory_hits := 0
static var _disk_hits := 0
static var _bakes := 0
static var _last_bake_usec := 0
static var _ready_revision := 0
static var _cancelled_jobs := 0

var texture: ImageTexture
var world_rect := Rect2()
var cache_key := ""
var build_usec := 0
var _resolution := MIN_RESOLUTION
var _layout: WorldLayout
var _overview_texture: ImageTexture
var _overview_rect := Rect2()
var _overview_resolution := MIN_RESOLUTION
var _detail_texture: ImageTexture
var _detail_rect := Rect2()
var _detail_resolution := DETAIL_RESOLUTION
var _detail_key := ""
var _detail_band := 0.0
var _drawn_revision := -1


static func resolution_for_half_extent(_half_m: float) -> int:
	return MAX_RESOLUTION


func prepare(layout: WorldLayout) -> void:
	if layout == null: return
	var started := Time.get_ticks_usec()
	_layout = layout
	var half := layout.half_extent_m
	var next_key := "%s:overview:%d" % [ChartRasterCache.world_key(layout), MAX_RESOLUTION]
	if next_key == cache_key and _overview_texture != null:
		_refresh_overview()
		_use_overview()
		return
	cache_key = next_key
	_overview_rect = Rect2(-half, -half, half * 2.0, half * 2.0)
	_detail_key = ""
	_detail_texture = null
	if _textures.has(cache_key):
		_memory_hits += 1
		_refresh_overview()
	else:
		# Temporary coarse chart on the first cold frame. Full production
		# resolution replaces it when the bake or disk read completes.
		_overview_resolution = PREVIEW_RESOLUTION
		_overview_texture = _bake_region(layout, _overview_rect, PREVIEW_RESOLUTION)
		if not _pending_overviews.has(cache_key):
			_pending_overviews[cache_key] = _start_job(layout, _overview_rect, MAX_RESOLUTION, cache_key)
	_use_overview()
	build_usec = Time.get_ticks_usec() - started


func prepare_visible(visible_world: Rect2) -> void:
	poll_detail()
	_refresh_overview()
	if _layout == null or _overview_texture == null: return
	var clipped := visible_world.intersection(_overview_rect)
	var view_span := maxf(visible_world.size.x, visible_world.size.y)
	if clipped.size.x <= 1.0 or clipped.size.y <= 1.0 or view_span >= _overview_rect.size.x * 0.55:
		_use_overview()
		return
	var band := detail_band(view_span)
	_cancel_obsolete_detail(clipped, band)
	if _detail_texture != null and _detail_rect.encloses(clipped) and _detail_band <= band:
		_use_detail()
		return
	var tile := detail_bounds(clipped, band).intersection(_overview_rect)
	var next_key := "%s:detail:%d:%.0f:%.0f:%.0f:%.0f" % [
		ChartRasterCache.world_key(_layout), DETAIL_RESOLUTION,
		tile.position.x, tile.position.y, tile.size.x, tile.size.y,
	]
	if _detail_textures.has(next_key):
		_memory_hits += 1
		_detail_key = next_key
		_detail_rect = tile
		_detail_band = band
		_detail_texture = _detail_textures[next_key] as ImageTexture
		_touch_detail(next_key)
		_use_detail()
		return
	# Panning back can reuse another cached origin in this zoom band.
	for key in _detail_order:
		if not key.begins_with(ChartRasterCache.world_key(_layout) + ":detail:"): continue
		var record: Dictionary = _detail_rects[key]
		if float(record.band) <= band and (record.rect as Rect2).encloses(clipped):
			_detail_key = key
			_detail_rect = record.rect
			_detail_band = record.band
			_detail_texture = _detail_textures[key] as ImageTexture
			_memory_hits += 1
			_use_detail()
			return
	if _pending_detail.is_empty():
		_pending_detail = _start_job(_layout, tile, DETAIL_RESOLUTION, next_key, get_instance_id())
		_pending_detail["band"] = band
	# Keep the useful old detail while an adjacent tile loads. Overview is
	# drawn underneath so a partial intersection never leaves a blank strip.
	if _detail_texture != null and _detail_rect.intersects(clipped): _use_detail()
	else: _use_overview()


func _cancel_obsolete_detail(clipped: Rect2, band: float) -> void:
	if _pending_detail.is_empty() or int(_pending_detail.owner) != get_instance_id():
		return
	var pending_bounds: Rect2 = _pending_detail.rect
	if not str(_pending_detail.key).begins_with(ChartRasterCache.world_key(_layout) + ":detail:") \
			or not pending_bounds.encloses(clipped) or float(_pending_detail.band) > band * 1.2:
		# Keep the task ID until the worker actually stops. Its row-boundary
		# cancellation avoids making the latest view wait for an old bake.
		(_pending_detail.request as BakeRequest).cancel()


## Fixed square-root-of-two zoom bands and overlapping origins, independent of
## viewport aspect ratio. Small zoom changes never request another bake.
static func detail_band(view_span: float) -> float:
	return maxf(500.0, pow(2.0, ceilf(log(maxf(view_span, 1.0)) / log(2.0) * 2.0) * 0.5))


static func detail_bounds(bounds: Rect2, band: float) -> Rect2:
	var span := band * 1.5
	var snap := band * 0.25
	var center := bounds.get_center()
	var origin := Vector2(floorf((center.x - span * 0.5) / snap) * snap,
		floorf((center.y - span * 0.5) / snap) * snap)
	return Rect2(origin, Vector2.ONE * span)


static func _start_job(layout: WorldLayout, rect: Rect2, resolution: int, key: String,
		owner: int = 0) -> Dictionary:
	var state := {}
	var request := BakeRequest.new()
	var task := WorkerThreadPool.add_task(func() -> void:
		var started := Time.get_ticks_usec()
		var image := ChartRasterCache.read(key, resolution)
		state["disk_hit"] = image != null
		if image == null and not request.is_cancelled():
			image = _bake_region_image(layout, rect, resolution, request)
			if image != null and not request.is_cancelled():
				ChartRasterCache.write(key, image)
		state["image"] = image
		state["usec"] = Time.get_ticks_usec() - started
	)
	return {"key": key, "task": task, "state": state, "rect": rect,
		"started_msec": Time.get_ticks_msec(), "request": request, "owner": owner}


## Texture upload/cache mutation stays on main. Existing entry point also
## drains overview completions; renderers redraw only when this returns true.
static func poll_detail() -> bool:
	var changed := false
	for key in _pending_overviews.keys():
		var job: Dictionary = _pending_overviews[key]
		if not WorkerThreadPool.is_task_completed(int(job.task)): continue
		WorkerThreadPool.wait_for_task_completion(int(job.task))
		_complete_overview(key, job)
		changed = true
	if not _pending_detail.is_empty() and WorkerThreadPool.is_task_completed(int(_pending_detail.task)):
		WorkerThreadPool.wait_for_task_completion(int(_pending_detail.task))
		_complete_detail()
		changed = true
	return changed


static func _complete_overview(key: String, job: Dictionary) -> void:
	_ready_revision += 1
	_record_job(job)
	_textures[key] = ImageTexture.create_from_image(job.state.image)
	_world_order.append(key)
	_pending_overviews.erase(key)
	while _world_order.size() > WORLD_CACHE_LIMIT:
		_textures.erase(_world_order[0])
		_world_order.remove_at(0)


static func _complete_detail() -> void:
	if (_pending_detail.request as BakeRequest).is_cancelled():
		_cancelled_jobs += 1
		# Wake every retained canvas, including the requester, so the latest
		# view can schedule its replacement even if another map polled first.
		_ready_revision += 1
		_pending_detail = {}
		return
	_ready_revision += 1
	var key: String = _pending_detail.key
	_record_job(_pending_detail)
	_detail_textures[key] = ImageTexture.create_from_image(_pending_detail.state.image)
	_detail_rects[key] = {"rect": _pending_detail.rect, "band": _pending_detail.band}
	_touch_detail(key)
	while _detail_order.size() > DETAIL_CACHE_LIMIT:
		_detail_textures.erase(_detail_order[0])
		_detail_rects.erase(_detail_order[0])
		_detail_order.remove_at(0)
	_pending_detail = {}


static func _record_job(job: Dictionary) -> void:
	if bool(job.state.disk_hit): _disk_hits += 1
	else: _bakes += 1
	_last_bake_usec = int(job.state.usec)


static func _touch_detail(key: String) -> void:
	var index := _detail_order.find(key)
	if index >= 0: _detail_order.remove_at(index)
	_detail_order.append(key)


## Join only final scene/engine teardown. Closing the map keeps jobs alive.
static func finish_pending_detail() -> void:
	for key in _pending_overviews.keys():
		var job: Dictionary = _pending_overviews[key]
		WorkerThreadPool.wait_for_task_completion(int(job.task))
		_complete_overview(key, job)
	if not _pending_detail.is_empty():
		WorkerThreadPool.wait_for_task_completion(int(_pending_detail.task))
		_complete_detail()


static func clear_memory_cache() -> void:
	finish_pending_detail()
	_textures.clear()
	_world_order.clear()
	_detail_textures.clear()
	_detail_rects.clear()
	_detail_order.clear()
	_memory_hits = 0
	_disk_hits = 0
	_bakes = 0
	_last_bake_usec = 0
	_cancelled_jobs = 0


func debug_stats() -> Dictionary:
	return {"key": cache_key, "prepare_usec": build_usec,
		"overview_ready": _textures.has(cache_key), "memory_hits": _memory_hits,
		"disk_hits": _disk_hits, "bakes": _bakes, "last_bake_usec": _last_bake_usec,
		"overview_count": _textures.size(), "detail_count": _detail_textures.size(),
		"pending": _pending_overviews.size() + (0 if _pending_detail.is_empty() else 1),
		"detail_key": _detail_key, "resolution": _resolution,
		"pending_detail_age_ms": 0 if _pending_detail.is_empty() else Time.get_ticks_msec() - int(_pending_detail.started_msec),
		"cancelled_jobs": _cancelled_jobs,
		"ready_revision": _ready_revision, "drawn_revision": _drawn_revision}


## A different map/minimap can publish a shared worker completion first.
## Each retained canvas still needs its own redraw to adopt that texture.
func needs_redraw() -> bool:
	return _drawn_revision != _ready_revision


func draw(canvas: CanvasItem, chart_rect: Rect2, visible_world: Rect2, allow_detail: bool = true) -> void:
	_refresh_overview()
	if allow_detail: prepare_visible(visible_world)
	elif _detail_texture != null and _detail_rect.intersects(visible_world): _use_detail()
	else: _use_overview()
	canvas.draw_rect(chart_rect, SEA)
	_draw_region(canvas, _overview_texture, _overview_rect, _overview_resolution, chart_rect, visible_world)
	if texture != _overview_texture:
		_draw_region(canvas, texture, world_rect, _resolution, chart_rect, visible_world)
	_drawn_revision = _ready_revision


static func _draw_region(canvas: CanvasItem, image_texture: ImageTexture, region: Rect2,
		resolution: int, chart: Rect2, visible: Rect2) -> void:
	if image_texture == null or region.size.x <= 0.0: return
	var clipped := visible.intersection(region)
	if clipped.size.x <= 0.0 or clipped.size.y <= 0.0: return
	var dest := Rect2(chart.position + (clipped.position - visible.position) / visible.size * chart.size,
		clipped.size / visible.size * chart.size)
	var source := Rect2((clipped.position - region.position) / region.size * float(resolution),
		clipped.size / region.size * float(resolution))
	canvas.draw_texture_rect_region(image_texture, dest, source)


func _refresh_overview() -> void:
	if _textures.has(cache_key):
		_overview_texture = _textures[cache_key] as ImageTexture
		_overview_resolution = MAX_RESOLUTION


func _use_overview() -> void:
	texture = _overview_texture
	world_rect = _overview_rect
	_resolution = _overview_resolution


func _use_detail() -> void:
	texture = _detail_texture
	world_rect = _detail_rect
	_resolution = _detail_resolution


static func _bake_region(layout: WorldLayout, rect: Rect2, resolution: int) -> ImageTexture:
	return ImageTexture.create_from_image(_bake_region_image(layout,rect,resolution))


static func _bake_region_image(layout: WorldLayout, rect: Rect2, resolution: int,
		request: BakeRequest = null) -> Image:
	var depths := PackedFloat32Array()
	depths.resize(resolution * resolution)
	var land_mask := PackedByteArray()
	land_mask.resize(resolution * resolution)
	for y in range(resolution):
		if request != null and request.is_cancelled(): return null
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
	var bytes := PackedByteArray()
	bytes.resize(resolution * resolution * 4)
	for y in range(resolution):
		if request != null and request.is_cancelled(): return null
		for x in range(resolution):
			var idx := y * resolution + x
			var land := land_mask[idx] == 1
			var edge := land and ((x > 0 and land_mask[idx - 1] == 0)
				or (x < resolution - 1 and land_mask[idx + 1] == 0)
				or (y > 0 and land_mask[idx - resolution] == 0)
				or (y < resolution - 1 and land_mask[idx + resolution] == 0))
			var colour := COAST if edge else (LAND if land else depth_colour(depths[idx]))
			bytes[idx * 4] = roundi(colour.r * 255.0)
			bytes[idx * 4 + 1] = roundi(colour.g * 255.0)
			bytes[idx * 4 + 2] = roundi(colour.b * 255.0)
			bytes[idx * 4 + 3] = 255
	var image := Image.create_from_data(resolution, resolution, false, Image.FORMAT_RGBA8, bytes)
	image.generate_mipmaps()
	return image


static func depth_colour(depth_m: float) -> Color:
	if depth_m < 10.0: return Color("7da6ac")
	if depth_m < 25.0: return Color("547f91")
	if depth_m < 50.0: return Color("365e77")
	if depth_m < 100.0: return Color("26455e")
	if depth_m < 200.0: return Color("1b334b")
	return SEA
