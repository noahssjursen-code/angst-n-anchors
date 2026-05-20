class_name MapWeatherView
extends RefCounted

## Weather rendering for the sea chart. Owns its own grid-sample cache
## so noise sampling work is reused across frames where the camera and
## game-time haven't moved much.
##
## Used by MapOverlay — it builds a per-frame context dict with the
## chart bounds, then calls `render(self, ctx)` from inside its `_draw`.
## The view writes back to `canvas.draw_*` against the passed canvas
## item, so all painting happens during MapOverlay's draw pass.

# ── Tuning ───────────────────────────────────────────────────────────────────
## Cells are sized in WORLD metres, not screen pixels — minimum size so fine
## zoom doesn't sample the same noise feature dozens of times. Snaps to a
## world-space lattice so wind arrows stay anchored while you pan.
const WX_MIN_CELL_M           : float = 2500.0
const WX_MAX_CELLS_X          : int   = 32
const WX_MAX_CELLS_Y          : int   = 22
## NxN sub-samples averaged per cell. The pressure field is already smooth
## at WX_MIN_CELL_M so 1 is enough — bumping to 2 just doubles cost for no
## visible smoothing benefit.
const WX_SUBSAMPLES           : int   = 1
const WX_PRESSURE_LO          : float = 990.0   ## hPa mapped to deep red
const WX_PRESSURE_HI          : float = 1030.0  ## hPa mapped to deep blue
## Skip resampling the noise field when the camera / game-time barely moved.
## ~3 s real-time at 1 min/game-hour.
const WX_CACHE_MAX_AGE_GAME_H : float = 0.05

# ── Cache ────────────────────────────────────────────────────────────────────
var _cache_time_h:  float = -INF
var _cache_wx0:     float = NAN
var _cache_wz0:     float = NAN
var _cache_cell_m:  float = -1.0
var _cache_cols:    int   = -1
var _cache_rows:    int   = -1
var _cache_pressure: PackedFloat32Array = PackedFloat32Array()
var _cache_wind_x:   PackedFloat32Array = PackedFloat32Array()
var _cache_wind_z:   PackedFloat32Array = PackedFloat32Array()


## Render all weather overlay layers onto `canvas`. `ctx` carries the
## chart bounds set in MapOverlay._draw:
##   cpx, cpy, cpw, cph : float   chart panel in screen space
##   wx_min, wx_max     : float   visible world X bounds
##   wz_min, wz_max     : float   visible world Z bounds
##   hover_pos          : Vector2 mouse position in canvas space, or NaN
##   hover_inside       : bool    whether the cursor is over the chart
func render(canvas: CanvasItem, ctx: Dictionary) -> void:
	if not WorldWeather.is_initialized():
		return
	var time_h := WeatherField.current_game_time()
	var g := _grid(ctx)
	_ensure_cache(time_h, g)
	_draw_pressure_field(canvas, g)
	_draw_wind_field(canvas, g)
	_draw_extrema(canvas, g)
	_draw_legend(canvas, ctx)
	_draw_season_banner(canvas, time_h, ctx)
	if bool(ctx.get("hover_inside", false)):
		_draw_hover(canvas, time_h, g, ctx)


# ── Grid description ─────────────────────────────────────────────────────────

func _grid(ctx: Dictionary) -> Dictionary:
	var wx_min : float = float(ctx["wx_min"])
	var wx_max : float = float(ctx["wx_max"])
	var wz_min : float = float(ctx["wz_min"])
	var wz_max : float = float(ctx["wz_max"])
	var cpw    : float = float(ctx["cpw"])
	var cph    : float = float(ctx["cph"])

	var span_x := wx_max - wx_min
	var span_z := wz_max - wz_min
	var cell_m := maxf(WX_MIN_CELL_M,
						maxf(span_x / float(WX_MAX_CELLS_X),
							 span_z / float(WX_MAX_CELLS_Y)))
	var wx0  : float = floorf(wx_min / cell_m) * cell_m
	var wz0  : float = floorf(wz_min / cell_m) * cell_m
	var cols : int   = int(ceilf((wx_max - wx0) / cell_m))
	var rows : int   = int(ceilf((wz_max - wz0) / cell_m))
	cols = clampi(cols, 1, WX_MAX_CELLS_X + 2)
	rows = clampi(rows, 1, WX_MAX_CELLS_Y + 2)
	return {
		"cell_m": cell_m,
		"cols":   cols,
		"rows":   rows,
		"wx0":    wx0,
		"wz0":    wz0,
		"wx_min": wx_min,
		"wz_min": wz_min,
		"cpx":    float(ctx["cpx"]),
		"cpy":    float(ctx["cpy"]),
		"cpw":    cpw,
		"cph":    cph,
		"ppu_x":  cpw / span_x,
		"ppu_z":  cph / span_z,
	}


func _ensure_cache(time_h: float, g: Dictionary) -> void:
	var cell_m : float = g["cell_m"]
	var cols   : int   = g["cols"]
	var rows   : int   = g["rows"]
	var wx0    : float = g["wx0"]
	var wz0    : float = g["wz0"]
	var view_unchanged := (
		_cache_cell_m == cell_m
		and _cache_cols == cols
		and _cache_rows == rows
		and is_equal_approx(_cache_wx0, wx0)
		and is_equal_approx(_cache_wz0, wz0)
	)
	if view_unchanged and absf(time_h - _cache_time_h) < WX_CACHE_MAX_AGE_GAME_H:
		return
	_cache_time_h = time_h
	_cache_wx0    = wx0
	_cache_wz0    = wz0
	_cache_cell_m = cell_m
	_cache_cols   = cols
	_cache_rows   = rows
	var n := cols * rows
	_cache_pressure.resize(n)
	_cache_wind_x.resize(n)
	_cache_wind_z.resize(n)
	for j in range(rows):
		for i in range(cols):
			var s := _cell_avg_sample(time_h, wx0 + float(i) * cell_m,
											  wz0 + float(j) * cell_m, cell_m)
			var idx := j * cols + i
			_cache_pressure[idx] = float(s["pressure"])
			var w : Vector3 = s["wind"]
			_cache_wind_x[idx] = w.x
			_cache_wind_z[idx] = w.z


static func _cell_avg_sample(time_h: float, wx0: float, wz0: float, cell_m: float) -> Dictionary:
	var step := cell_m / float(WX_SUBSAMPLES)
	var p_sum := 0.0
	var w_sum := Vector3.ZERO
	for j in range(WX_SUBSAMPLES):
		var wz := wz0 + (float(j) + 0.5) * step
		for i in range(WX_SUBSAMPLES):
			var wx := wx0 + (float(i) + 0.5) * step
			p_sum += WeatherField.pressure_at(Vector3(wx, 0.0, wz), time_h)
			w_sum += WeatherField.sample_wind(Vector3(wx, 0.0, wz), time_h)
	var n := float(WX_SUBSAMPLES * WX_SUBSAMPLES)
	return {"pressure": p_sum / n, "wind": w_sum / n}


static func _wx_to_sx(wx: float, g: Dictionary) -> float:
	return float(g["cpx"]) + (wx - float(g["wx_min"])) * float(g["ppu_x"])

static func _wz_to_sy(wz: float, g: Dictionary) -> float:
	return float(g["cpy"]) + (wz - float(g["wz_min"])) * float(g["ppu_z"])


# ── Layers ───────────────────────────────────────────────────────────────────

func _draw_pressure_field(canvas: CanvasItem, g: Dictionary) -> void:
	var cell_m : float = g["cell_m"]
	var cell_w : float = cell_m * float(g["ppu_x"])
	var cell_h : float = cell_m * float(g["ppu_z"])
	var cols   : int   = g["cols"]
	var rows   : int   = g["rows"]
	for j in range(rows):
		var wz0 : float = float(g["wz0"]) + float(j) * cell_m
		var sy  : float = _wz_to_sy(wz0, g)
		for i in range(cols):
			var wx0 : float = float(g["wx0"]) + float(i) * cell_m
			var sx  : float = _wx_to_sx(wx0, g)
			canvas.draw_rect(Rect2(sx, sy, cell_w + 1.0, cell_h + 1.0),
							 _pressure_color(_cache_pressure[j * cols + i]), true)


func _draw_wind_field(canvas: CanvasItem, g: Dictionary) -> void:
	var cell_m : float = g["cell_m"]
	var cell_w : float = cell_m * float(g["ppu_x"])
	var cell_h : float = cell_m * float(g["ppu_z"])
	var cols   : int   = g["cols"]
	var rows   : int   = g["rows"]
	var arrow_len := minf(cell_w, cell_h) * 0.78
	for j in range(rows):
		var wz0 : float = float(g["wz0"]) + float(j) * cell_m
		for i in range(cols):
			var wx0 : float = float(g["wx0"]) + float(i) * cell_m
			var idx := j * cols + i
			var wx_v : float = _cache_wind_x[idx]
			var wz_v : float = _cache_wind_z[idx]
			var mag := sqrt(wx_v * wx_v + wz_v * wz_v)
			if mag < 0.05:
				continue
			mag = minf(mag, 1.0)
			var screen_dir := Vector2(wx_v, -wz_v) / maxf(sqrt(wx_v*wx_v + wz_v*wz_v), 1e-4)
			var cx := _wx_to_sx(wx0 + cell_m * 0.5, g)
			var cy := _wz_to_sy(wz0 + cell_m * 0.5, g)
			var tail := Vector2(cx, cy) - screen_dir * arrow_len * 0.5
			var head := Vector2(cx, cy) + screen_dir * arrow_len * 0.5
			var col  := Color(0.95, 0.95, 1.00, 0.35 + 0.55 * mag)
			canvas.draw_line(tail, head, col, 1.4, true)
			var perp := Vector2(-screen_dir.y, screen_dir.x)
			canvas.draw_line(head, head - screen_dir * 4.0 + perp * 2.6, col, 1.4, true)
			canvas.draw_line(head, head - screen_dir * 4.0 - perp * 2.6, col, 1.4, true)


func _draw_extrema(canvas: CanvasItem, g: Dictionary) -> void:
	var cell_m : float = g["cell_m"]
	var cols   : int   = g["cols"]
	var rows   : int   = g["rows"]
	if cols < 3 or rows < 3:
		return
	var font := ThemeDB.fallback_font
	for j in range(1, rows - 1):
		for i in range(1, cols - 1):
			var p := _cache_pressure[j * cols + i]
			var is_low  := p < WX_PRESSURE_LO + 5.0
			var is_high := p > WX_PRESSURE_HI - 5.0
			if not (is_low or is_high):
				continue
			var min_ok := true
			var max_ok := true
			for dj in [-1, 0, 1]:
				for di in [-1, 0, 1]:
					if di == 0 and dj == 0:
						continue
					var nb := _cache_pressure[(j + dj) * cols + (i + di)]
					if nb <= p: min_ok = false
					if nb >= p: max_ok = false
			if is_low and min_ok:
				var sx := _wx_to_sx(float(g["wx0"]) + (float(i) + 0.5) * cell_m, g)
				var sy := _wz_to_sy(float(g["wz0"]) + (float(j) + 0.5) * cell_m, g)
				canvas.draw_string(font, Vector2(sx - 5.0, sy + 5.0),
								   "L", HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
								   Color(1.00, 0.45, 0.35, 0.95))
			elif is_high and max_ok:
				var sx2 := _wx_to_sx(float(g["wx0"]) + (float(i) + 0.5) * cell_m, g)
				var sy2 := _wz_to_sy(float(g["wz0"]) + (float(j) + 0.5) * cell_m, g)
				canvas.draw_string(font, Vector2(sx2 - 5.0, sy2 + 5.0),
								   "H", HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
								   Color(0.55, 0.78, 1.00, 0.95))


func _draw_legend(canvas: CanvasItem, ctx: Dictionary) -> void:
	var w := 130.0
	var h := 9.0
	var x : float = float(ctx["cpx"]) + 10.0
	var y : float = float(ctx["cpy"]) + float(ctx["cph"]) - 26.0
	var font := ThemeDB.fallback_font
	canvas.draw_string(font, Vector2(x, y - 4.0),
					   "Pressure (hPa)", HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
					   Color(0.82, 0.86, 0.92, 0.80))
	var stops := 18
	var stop_w := w / float(stops)
	for i in range(stops):
		var hpa := lerpf(WX_PRESSURE_LO, WX_PRESSURE_HI, float(i) / float(stops - 1))
		var col := _pressure_color(hpa)
		col.a = 0.85
		canvas.draw_rect(Rect2(x + float(i) * stop_w, y + 4.0, stop_w + 0.5, h), col, true)
	canvas.draw_string(font, Vector2(x - 2.0, y + 4.0 + h + 9.0),
					   "%d  Low" % int(WX_PRESSURE_LO), HORIZONTAL_ALIGNMENT_LEFT, -1, 9,
					   Color(1.0, 0.65, 0.55, 0.88))
	canvas.draw_string(font, Vector2(x + w - 36.0, y + 4.0 + h + 9.0),
					   "High  %d" % int(WX_PRESSURE_HI), HORIZONTAL_ALIGNMENT_LEFT, -1, 9,
					   Color(0.65, 0.82, 1.0, 0.88))


func _draw_season_banner(canvas: CanvasItem, time_h: float, ctx: Dictionary) -> void:
	var season_name := Season.current_name(time_h)
	var progress    := Season.progress_within_current(time_h)
	var label := "%s  (%d%%)" % [season_name, int(progress * 100.0)]
	var font  := ThemeDB.fallback_font
	var tw    := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	var pos   := Vector2(float(ctx["cpx"]) + float(ctx["cpw"]) - tw - 8.0,
						 float(ctx["cpy"]) + 14.0)
	canvas.draw_rect(Rect2(pos.x - 4.0, pos.y - 11.0, tw + 8.0, 14.0),
					 Color(0.0, 0.0, 0.0, 0.40), true)
	canvas.draw_string(font, pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
					   Color(0.96, 0.92, 0.78, 0.92))


func _draw_hover(canvas: CanvasItem, time_h: float, g: Dictionary, ctx: Dictionary) -> void:
	var hover_pos: Vector2 = ctx["hover_pos"]
	var cell_m : float = g["cell_m"]
	var cols   : int   = g["cols"]
	var rows   : int   = g["rows"]
	var cpx    : float = float(ctx["cpx"])
	var cpy    : float = float(ctx["cpy"])
	var cpw    : float = float(ctx["cpw"])
	var cph    : float = float(ctx["cph"])
	var wx_min : float = float(ctx["wx_min"])
	var wz_min : float = float(ctx["wz_min"])
	var wx : float = wx_min + (hover_pos.x - cpx) / float(g["ppu_x"])
	var wz : float = wz_min + (hover_pos.y - cpy) / float(g["ppu_z"])
	var i := int(floorf((wx - float(g["wx0"])) / cell_m))
	var j := int(floorf((wz - float(g["wz0"])) / cell_m))
	if i < 0 or j < 0 or i >= cols or j >= rows:
		return
	var cell_wx : float = float(g["wx0"]) + (float(i) + 0.5) * cell_m
	var cell_wz : float = float(g["wz0"]) + (float(j) + 0.5) * cell_m
	var s := WeatherField.sample(Vector3(cell_wx, 0.0, cell_wz), time_h)

	var pressure_label := "Normal"
	if s.pressure < 1000.0:
		pressure_label = "Low (stormy)"
	elif s.pressure > 1020.0:
		pressure_label = "High (clear)"
	var wind_kts := s.wind_force * 50.0
	var wind_dir_label := _compass_label_for(s.wind)
	var precip_pct := int(s.precipitation * 100.0)
	var cloud_pct  := int(s.cloud_cover * 100.0)
	var vis_pct    := int(s.visibility * 100.0)

	var lines : Array[String] = [
		"Position:  %d, %d  m"      % [int(cell_wx), int(cell_wz)],
		"Pressure:  %.1f hPa  (%s)" % [s.pressure, pressure_label],
		"Wind:      %s  %.0f kts"   % [wind_dir_label, wind_kts],
		"Cloud:     %d %%"          % cloud_pct,
		"Precip:    %d %%"          % precip_pct,
		"Visibility:%d %%"          % vis_pct,
		"Temp:      %.1f °C"        % s.temperature,
	]
	var font := ThemeDB.fallback_font
	var line_h := 13
	var pad := 6.0
	var w := 0.0
	for ln in lines:
		w = maxf(w, font.get_string_size(ln, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x)
	w += pad * 2.0
	var h := float(lines.size()) * float(line_h) + pad * 2.0
	var bx := hover_pos.x + 14.0
	var by := hover_pos.y + 14.0
	if bx + w > cpx + cpw: bx = hover_pos.x - 14.0 - w
	if by + h > cpy + cph: by = hover_pos.y - 14.0 - h
	canvas.draw_rect(Rect2(bx, by, w, h), Color(0.05, 0.07, 0.11, 0.92), true)
	canvas.draw_rect(Rect2(bx, by, w, h), Color(0.38, 0.50, 0.72, 0.72), false)
	for k in range(lines.size()):
		canvas.draw_string(font, Vector2(bx + pad, by + pad + float(k + 1) * float(line_h) - 3.0),
						   lines[k], HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
						   Color(0.92, 0.94, 0.98, 0.96))


# ── Helpers ──────────────────────────────────────────────────────────────────

static func _pressure_color(hpa: float) -> Color:
	var t := clampf(inverse_lerp(WX_PRESSURE_LO, WX_PRESSURE_HI, hpa), 0.0, 1.0)
	var r := lerpf(0.80, 0.18, t)
	var g := lerpf(0.18, 0.34, smoothstep(0.0, 1.0, t))
	var b := lerpf(0.08, 0.78, t)
	return Color(r, g, b, 0.13)


static func _compass_label_for(wind: Vector3) -> String:
	if wind.length() < 0.04:
		return "calm"
	var ang := rad_to_deg(atan2(-wind.x, -wind.z))
	if ang < 0.0: ang += 360.0
	var dirs := ["N","NE","E","SE","S","SW","W","NW"]
	var idx := int(round(ang / 45.0)) % 8
	return dirs[idx]
