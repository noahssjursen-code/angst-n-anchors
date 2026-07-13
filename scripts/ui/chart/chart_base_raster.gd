class_name ChartBaseRaster
extends RefCounted

## One raster per immutable layout. Camera movement only changes the source
## rectangle; it never re-samples land or scans coastline segments.

const RESOLUTION := 256
const SEA := Color(0.035, 0.075, 0.12, 1.0)
const LAND := Color(0.73, 0.70, 0.55, 1.0)
const COAST := Color(0.12, 0.16, 0.15, 1.0)

static var _textures: Dictionary = {}

var texture: ImageTexture
var world_rect := Rect2()
var cache_key := ""
var build_usec := 0


func prepare(layout: WorldLayout) -> void:
	if layout == null:
		return
	var next_key := str(layout.layout_checksum)
	if next_key.is_empty():
		next_key = str(layout.get_instance_id())
	if next_key == cache_key and texture != null:
		return
	cache_key = next_key
	var half := float(layout.half_extent_m)
	world_rect = Rect2(-half, -half, half * 2.0, half * 2.0)
	if _textures.has(cache_key):
		texture = _textures[cache_key] as ImageTexture
		return
	var started := Time.get_ticks_usec()
	var land_mask := PackedByteArray()
	land_mask.resize(RESOLUTION * RESOLUTION)
	for y in range(RESOLUTION):
		for x in range(RESOLUTION):
			var world := Vector2(
				lerpf(world_rect.position.x, world_rect.end.x, (float(x) + 0.5) / RESOLUTION),
				lerpf(world_rect.position.y, world_rect.end.y, (float(y) + 0.5) / RESOLUTION),
			)
			land_mask[y * RESOLUTION + x] = 1 if layout.is_land(world) else 0
	var image := Image.create(RESOLUTION, RESOLUTION, false, Image.FORMAT_RGBA8)
	for y in range(RESOLUTION):
		for x in range(RESOLUTION):
			var idx := y * RESOLUTION + x
			var land := land_mask[idx] == 1
			var edge := false
			if land:
				for offset_raw in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
					var offset := offset_raw as Vector2i
					var nx: int = x + offset.x
					var ny: int = y + offset.y
					if nx < 0 or ny < 0 or nx >= RESOLUTION or ny >= RESOLUTION:
						continue
					if land_mask[ny * RESOLUTION + nx] == 0:
						edge = true
						break
			image.set_pixel(x, y, COAST if edge else (LAND if land else SEA))
	texture = ImageTexture.create_from_image(image)
	_textures[cache_key] = texture
	build_usec = Time.get_ticks_usec() - started


func draw(canvas: CanvasItem, chart_rect: Rect2, visible_world: Rect2) -> void:
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
			(clipped.position.x - world_rect.position.x) / world_rect.size.x * RESOLUTION,
			(clipped.position.y - world_rect.position.y) / world_rect.size.y * RESOLUTION,
		),
		Vector2(
			clipped.size.x / world_rect.size.x * RESOLUTION,
			clipped.size.y / world_rect.size.y * RESOLUTION,
		),
	)
	canvas.draw_texture_rect_region(texture, Rect2(dest_position, dest_size), source)
