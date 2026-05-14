class_name WeatherHUD
extends CanvasLayer

## Debug overlay showing the 2D weather compass (precipitation × wind) and fog slider.
## Toggle with Tab. Only active at runtime (not in editor).

const _GRID_SIZE  := 120.0
const _GRID_PAD   := 14.0
const _FOG_W      := 120.0
const _FOG_H      := 14.0
const _CORNER_PAD := 14.0

var _visible_hud := false
var _panel : Panel
var _label : Label
var _compass_rect : Control
var _fog_bar : Control


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	layer = 10
	_build_hud()
	_refresh()
	var w := _weather_lighting()
	if w != null:
		w.connect("state_changed", Callable(self, "_refresh"))


func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if event is InputEventKey:
		var ke := event as InputEventKey
		if ke.pressed and not ke.echo and ke.physical_keycode == KEY_TAB:
			_visible_hud = not _visible_hud
			_panel.visible = _visible_hud
			get_viewport().set_input_as_handled()


func _build_hud() -> void:
	var margin_x := _CORNER_PAD
	var margin_y := _CORNER_PAD
	var total_w  := _GRID_SIZE + _GRID_PAD * 2.0 + 4.0
	var label_h  := 80.0
	var total_h  := _GRID_SIZE + _GRID_PAD * 2.0 + _FOG_H + _GRID_PAD + label_h + 10.0

	_panel = Panel.new()
	_panel.visible = false
	_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_panel.offset_left   = margin_x
	_panel.offset_bottom = -margin_y
	_panel.offset_right  = margin_x + total_w
	_panel.offset_top    = -margin_y - total_h
	add_child(_panel)

	var style := StyleBoxFlat.new()
	style.bg_color         = Color(0.06, 0.06, 0.08, 0.82)
	style.corner_radius_top_left     = 6
	style.corner_radius_top_right    = 6
	style.corner_radius_bottom_left  = 6
	style.corner_radius_bottom_right = 6
	_panel.add_theme_stylebox_override("panel", style)

	# Compass draw area
	_compass_rect = Control.new()
	_compass_rect.position = Vector2(_GRID_PAD, _GRID_PAD)
	_compass_rect.size     = Vector2(_GRID_SIZE, _GRID_SIZE)
	_compass_rect.connect("draw", Callable(self, "_draw_compass"))
	_panel.add_child(_compass_rect)

	# Fog bar draw area
	_fog_bar = Control.new()
	_fog_bar.position = Vector2(_GRID_PAD, _GRID_PAD * 2 + _GRID_SIZE)
	_fog_bar.size     = Vector2(_FOG_W, _FOG_H)
	_fog_bar.connect("draw", Callable(self, "_draw_fog_bar"))
	_panel.add_child(_fog_bar)

	# Text label
	_label = Label.new()
	_label.position = Vector2(_GRID_PAD, _GRID_PAD * 3 + _GRID_SIZE + _FOG_H)
	_label.size     = Vector2(total_w - _GRID_PAD * 2, label_h)
	_label.add_theme_font_size_override("font_size", 11)
	_label.add_theme_color_override("font_color", Color(0.78, 0.82, 0.88))
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_panel.add_child(_label)


func _refresh() -> void:
	if not _panel:
		return
	_compass_rect.queue_redraw()
	_fog_bar.queue_redraw()
	_update_label()


func _draw_compass() -> void:
	var w := _weather_lighting()
	var precip := 0.0
	var wind   := 0.0
	if w != null:
		precip = float(w.get("precipitation"))
		wind   = float(w.get("wind_force"))

	var sz := _compass_rect.size

	# Background grid
	_compass_rect.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.12, 0.12, 0.16, 1.0))

	# Quadrant shading — TOP = calm, BOTTOM = gale, LEFT = clear, RIGHT = rain
	var mid := sz * 0.5
	_compass_rect.draw_rect(Rect2(Vector2.ZERO,              mid), Color(0.18, 0.38, 0.55, 0.18))  # top-left:  calm-clear
	_compass_rect.draw_rect(Rect2(Vector2(mid.x, 0),         mid), Color(0.18, 0.22, 0.38, 0.18))  # top-right: grey drizzle
	_compass_rect.draw_rect(Rect2(Vector2(0, mid.y),         mid), Color(0.30, 0.30, 0.18, 0.18))  # bot-left:  dry squall
	_compass_rect.draw_rect(Rect2(mid,                       mid), Color(0.30, 0.18, 0.18, 0.18))  # bot-right: full storm

	# Grid lines
	var line_col := Color(0.30, 0.30, 0.34, 0.6)
	_compass_rect.draw_line(Vector2(mid.x, 0), Vector2(mid.x, sz.y), line_col, 1.0)
	_compass_rect.draw_line(Vector2(0, mid.y), Vector2(sz.x, mid.y), line_col, 1.0)
	_compass_rect.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.30, 0.30, 0.34, 0.6), false, 1.0)

	# Corner labels (TOP = calm)
	var lc := Color(0.55, 0.58, 0.65, 0.9)
	var fs := 9
	_compass_rect.draw_string(ThemeDB.fallback_font, Vector2(3, 12),             "CALM-CLEAR",    HORIZONTAL_ALIGNMENT_LEFT, -1, fs, lc)
	_compass_rect.draw_string(ThemeDB.fallback_font, Vector2(3, sz.y - 4),       "DRY SQUALL",    HORIZONTAL_ALIGNMENT_LEFT, -1, fs, lc)
	_compass_rect.draw_string(ThemeDB.fallback_font, Vector2(mid.x + 3, 12),     "GREY DRIZZLE",  HORIZONTAL_ALIGNMENT_LEFT, -1, fs, lc)
	_compass_rect.draw_string(ThemeDB.fallback_font, Vector2(mid.x + 3, sz.y - 4), "FULL STORM",  HORIZONTAL_ALIGNMENT_LEFT, -1, fs, lc)

	# Axis arrows
	var ax_col := Color(0.70, 0.72, 0.78, 0.8)
	_compass_rect.draw_string(ThemeDB.fallback_font, Vector2(sz.x / 2 - 24, sz.y - 2), "← RAIN →",  HORIZONTAL_ALIGNMENT_LEFT, -1, 9, ax_col)
	_compass_rect.draw_string(ThemeDB.fallback_font, Vector2(2, mid.y - 2),             "↑ CALM",    HORIZONTAL_ALIGNMENT_LEFT, -1, 9, ax_col)

	# Current position dot — wind=0 (calm) at top, wind=1 (gale) at bottom
	var dot := Vector2(precip * sz.x, wind * sz.y)
	_compass_rect.draw_circle(dot, 7.0, Color(1.0, 0.90, 0.30, 0.95))
	_compass_rect.draw_arc(dot, 7.0, 0.0, TAU, 24, Color(0.0, 0.0, 0.0, 0.6), 1.5)


func _draw_fog_bar() -> void:
	var w := _weather_lighting()
	var vis := 1.0
	if w != null:
		vis = float(w.get("visibility"))

	var sz := _fog_bar.size

	# Track
	_fog_bar.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.12, 0.12, 0.16))

	# Fill — visibility fills left, fog fills right
	var fill_x := vis * sz.x
	_fog_bar.draw_rect(Rect2(Vector2.ZERO, Vector2(fill_x, sz.y)), Color(0.50, 0.65, 0.80, 0.7))
	_fog_bar.draw_rect(Rect2(Vector2(fill_x, 0), Vector2(sz.x - fill_x, sz.y)), Color(0.55, 0.58, 0.62, 0.4))

	# Border
	_fog_bar.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.30, 0.30, 0.34, 0.7), false, 1.0)

	# Labels
	var lc := Color(0.78, 0.82, 0.88, 0.9)
	_fog_bar.draw_string(ThemeDB.fallback_font, Vector2(2, sz.y - 2), "CLEAR", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, lc)
	_fog_bar.draw_string(ThemeDB.fallback_font, Vector2(sz.x - 30, sz.y - 2), "FOG", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, lc)


func _update_label() -> void:
	if _label == null:
		return
	var w := _weather_lighting()
	if w == null:
		_label.text = "(no WeatherLighting autoload)"
		return
	var precip := float(w.get("precipitation"))
	var wind   := float(w.get("wind_force"))
	var vis    := float(w.get("visibility"))
	var tod    := float(w.get("time_of_day"))
	var cloud  := float(w.get("cloud_cover"))
	_label.text = (
		"Rain %d%%  Wind %d%%  Cloud %d%%\nFog  %d%%  Time %.2f\n"
		% [int(precip * 100), int(wind * 100), int(cloud * 100), int((1.0 - vis) * 100), tod]
		+ "← → Rain    ↑ Calm / ↓ Gale\nShift+←→ Time  Shift+↑↓ Fog\nCtrl+←→ Clouds  Ctrl+↑↓ Waves"
	)


func _weather_lighting() -> Node:
	return get_node_or_null("/root/WeatherLighting")
