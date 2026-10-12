class_name SonarDisplay
extends Control
## Conventional blue-palette echogram. Only measured returns add colour.
## Render-rate scrolling moves a cached texture; it does no habitat work.
const WIDTH := 560.0
const HEIGHT := 306.0
const VIEW_HIDDEN := 0
const VIEW_FULL := 1
const VIEW_COMPACT := 2
## Same width as the helm chart. Height keeps the echogram's proportions.
const COMPACT_WIDTH := 300.0
const PINGS := 90
const SAMPLES_PER_PING := 4
const COLUMNS := PINGS * SAMPLES_PER_PING
const ROWS := 294
const PLOT := Rect2(5, 5, 550, 296)
const WATER := Color("0800ff")
const FONT: Font = preload("res://resources/fonts/IBMPlexSans-SemiBold.ttf")
const PALETTE: Array[Color] = [Color("0800ff"), Color("003cff"), Color("00aaff"), Color("00ffff"), Color("65ff5a"), Color("ffff00"), Color("ffb000"), Color("ff2800"), Color("bd0000"), Color("800000")]
var _history: Array = []
var _active := true
var _age := 0.0
var _interval := .5
var _stamp := -1
var _range := 50.0
var _texture: ImageTexture
var _raster: Image
var _rendered_stamp := -2
var _stream_id := -1
static var _font: FontFile

static func scale_for(view: int) -> float:
	return COMPACT_WIDTH / WIDTH if view == VIEW_COMPACT else 1.0

static func layout_size(view: int) -> Vector2:
	return Vector2(WIDTH, HEIGHT) * scale_for(view)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	if _font == null:
		_font = FONT.duplicate()
		_font.multichannel_signed_distance_field = true
		_font.msdf_size = 64

func present(data: Dictionary) -> void:
	var stream_id := int(data.get("stream_id", 0))
	if stream_id != _stream_id:
		_stream_id = stream_id
		_stamp = -2
		_rendered_stamp = -2
		_raster = null
	_active = bool(data.get("sounder", true))
	_interval = maxf(.1, float(data.get("ping_interval_s", .5)))
	_age = clampf(float(data.get("ping_age_s", 0)), 0, _interval)
	var history: Array = data.get("history", [])
	var stamp := -1
	if not history.is_empty():
		stamp = int(history[-1].sequence) if history[-1].has("sequence") else hash(history)
	if stamp != _stamp:
		_stamp = stamp
		_history = history
		_rebuild()
	queue_redraw()

func _process(delta: float) -> void:
	if not is_visible_in_tree(): return
	if _active: _age = minf(_interval, _age + delta)
	queue_redraw()

func _signals(ping: Dictionary) -> PackedFloat32Array:
	var bins := PackedFloat32Array()
	bins.resize(ROWS)
	for target: Dictionary in ping.get("targets", ping.get("echoes", [])):
		var center := float(target.get("range_m", target.depth_m)) / _range * (ROWS - 1)
		var spread := maxf(.65, float(target.get("thickness_m", .5)) / _range * ROWS)
		for row in range(maxi(0, floori(center - spread * 3)), mini(ROWS, ceili(center + spread * 3) + 1)):
			var strength := float(target.strength) * exp(-pow((row - center) / spread, 2) * .65)
			bins[row] = maxf(bins[row], strength)
	return bins

func _grain(x: int, y: int, salt: int) -> float:
	# Stable speckle within measured returns, never independent false fish.
	var bits := (x * 73856093) ^ (y * 19349663) ^ (salt * 83492791)
	bits = (bits ^ (bits >> 13)) * 1274126177
	return float(bits & 65535) / 65535.0

func _colour(strength: float) -> Color:
	if strength < .035: return WATER
	return PALETTE[clampi(ceili(strength * 9), 1, 9)]

func _rebuild() -> void:
	var deepest := 10.0
	for ping: Dictionary in _history: deepest = maxf(deepest, float(ping.depth_m))
	var step := 5.0 if deepest < 35 else (10.0 if deepest < 90 else (25.0 if deepest < 240 else 50.0))
	var next_range: float = ceil(deepest * 1.22 / step) * step
	var append_only := _raster != null and is_equal_approx(next_range, _range) and _stamp == _rendered_stamp + 1
	_range = next_range
	if append_only:
		# Copy in native code; only the four new columns run the echo renderer.
		var retained := _raster.get_region(Rect2i(SAMPLES_PER_PING, 0, COLUMNS - SAMPLES_PER_PING, ROWS))
		_raster.blit_rect(retained, Rect2i(0, 0, retained.get_width(), ROWS), Vector2i.ZERO)
	else:
		_raster = Image.create(COLUMNS, ROWS, false, Image.FORMAT_RGB8)
		_raster.fill(WATER)
	var start := _history.size() - 1 if append_only else maxi(0, _history.size() - PINGS)
	var previous_bins := PackedFloat32Array()
	for index in range(start, _history.size()):
		var ping: Dictionary = _history[index]
		var before: Dictionary = _history[maxi(0, index - 1)]
		var bins := _signals(ping)
		if previous_bins.is_empty(): previous_bins = _signals(before)
		var rock: bool = ping.get("substrate", "") == "rock"
		var thickness := 5.5 if rock else 3.2
		for sub in SAMPLES_PER_PING:
			var x := (PINGS - _history.size() + index) * SAMPLES_PER_PING + sub
			var fraction := float(sub + 1) / SAMPLES_PER_PING
			var bottom := lerpf(float(before.depth_m), float(ping.depth_m), fraction) / _range * (ROWS - 1)
			var salt := int(ping.get("sequence", index))
			for row in ROWS:
				var fish := lerpf(previous_bins[row], bins[row], fraction)
				var below := row - bottom
				if fish < .01 and (below <= -2.0 or below >= thickness * 5):
					if append_only: _raster.set_pixel(x, row, WATER)
					continue
				var grain := _grain(sub, row, salt)
				var strength := fish * lerpf(.6, 1.0, grain)
				# Red core, yellow edge and weaker cyan trailing scatter. The
				# water below the bottom echo stays blue, not a solid land fill.
				if below > -2.0 and below < thickness * 5:
					var bottom_signal := 0.0
					if below < 0:
						bottom_signal = (1.0 + below / 2.0) * .65
					elif below < thickness:
						bottom_signal = lerpf(.84, 1.0, grain)
					else:
						var tail := exp(-(below - thickness) / (thickness * .9))
						bottom_signal = tail * lerpf(.05, .75, grain)
					strength = maxf(strength, bottom_signal)
				_raster.set_pixel(x, row, _colour(strength))
		previous_bins = bins
	if _texture == null: _texture = ImageTexture.create_from_image(_raster)
	else: _texture.update(_raster)
	_rendered_stamp = _stamp

func _text(at: Vector2, value: String, size_px: int) -> void:
	draw_string(_font, at, value, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, Color.WHITE)

func _draw() -> void:
	draw_rect(Rect2(0, 0, WIDTH, HEIGHT), Color("171717"))
	draw_rect(PLOT, WATER)
	var phase := clampf(_age / _interval, 0, 1)
	var source_shift := phase * SAMPLES_PER_PING
	var shift := source_shift * PLOT.size.x / COLUMNS
	if _texture != null:
		draw_texture_rect_region(_texture, Rect2(PLOT.position, Vector2(PLOT.size.x - shift, PLOT.size.y)), Rect2(source_shift, 0, COLUMNS - source_shift, ROWS))
		if shift > 0:
			draw_texture_rect_region(_texture, Rect2(PLOT.end.x - shift, PLOT.position.y, shift, PLOT.size.y), Rect2(COLUMNS - 1, 0, 1, ROWS))
	draw_line(PLOT.position, Vector2(PLOT.end.x, PLOT.position.y), Color("ffe100"), 1)
	var last: Dictionary = _history[-1] if not _history.is_empty() else {}
	var depth := "%.0f" % float(last.depth_m) if not last.is_empty() else "--"
	_text(Vector2(8, 53), depth, 58)
	var number_width := FONT.get_string_size(depth, HORIZONTAL_ALIGNMENT_LEFT, -1, 58).x
	_text(Vector2(8 + number_width, 53), "m", 32)
	# Echo arcs measure slant range. Give anglers the real vertical depth of
	# current returns as well, so the edges of a deep arch don't mislead bait depth.
	var fish_depths := PackedStringArray()
	if _active:
		for echo: Dictionary in last.get("echoes", []):
			if fish_depths.size() < 3: fish_depths.append("%.0f" % float(echo.depth_m))
	if not fish_depths.is_empty(): _text(Vector2(9, 76), "Fish " + " / ".join(fish_depths) + " m", 19)
	# Numbers overlay the water. No grid obscures the returns.
	var tick_step := 10.0 if _range <= 40 else (25.0 if _range <= 100 else (50.0 if _range <= 250 else 100.0))
	for i in range(int(_range / tick_step) + 1):
		var tick_depth := i * tick_step
		if tick_depth > _range - tick_step * .35: continue
		_depth_label(tick_depth)
	_depth_label(_range)
	if not _active: _text(Vector2(12, HEIGHT - 14), "PAUSED", 16)

func _depth_label(depth: float) -> void:
	var label := "%.0f" % depth
	var width := FONT.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
	var y := clampf(PLOT.position.y + depth / _range * PLOT.size.y + 6, 21, HEIGHT - 9)
	_text(Vector2(PLOT.end.x - width - 3, y), label, 17)
