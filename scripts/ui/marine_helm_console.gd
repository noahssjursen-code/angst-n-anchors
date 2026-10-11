class_name MarineHelmConsole
extends Control

## Presentation only. FI-70 reference family: black instrument housings,
## recessed high-contrast LCD faces, compact bold numerals and fine scale rules.
## Uses the existing voyage snapshot; never issues or invents a vessel command.
const BODY := preload("res://resources/fonts/ui/Barlow-Medium.ttf")
const DIGITS := preload("res://resources/fonts/ui/BarlowCondensed-Bold.ttf")
const INK := Color("182126")
const FACE := Color("e2e8e7")
const LEGEND := Color("aab2b5")
const RED := Color("bd594b")
const GREEN := Color("558a6c")
const AMBER := Color("dbc58a")
const WIDTH := 838.0
const HEIGHT := 240.0
var state: Dictionary = {}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(WIDTH, HEIGHT)

func present(snapshot: Dictionary) -> void:
	state = snapshot.duplicate()
	queue_redraw()

func _box(rect: Rect2, fill: Color, edge: Color, radius: int = 4, width: int = 1) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = edge
	style.set_border_width_all(width)
	style.set_corner_radius_all(radius)
	draw_style_box(style, rect)

func _text(at: Vector2, value: String, font: Font, font_size: int, color: Color, width := -1.0, align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	draw_string(font, at, value, align, width, font_size, color)

func _case(x: float, width: float, label: String) -> Rect2:
	var outer := Rect2(x, 0, width, 192)
	_box(Rect2(outer.position + Vector2(0, 4), outer.size), Color(0, 0, 0, .45), Color.TRANSPARENT, 8, 0)
	_box(outer, Color("131719"), Color("616a6c"), 7)
	_box(outer.grow(-2), Color("202629"), Color("090c0e"), 5)
	# Bevel above the flush display, quiet printed label below it.
	draw_line(Vector2(x + 9, 4), Vector2(x + width - 9, 4), Color("596063"), 1, true)
	var screen := Rect2(x + 20, 24, width - 40, 130)
	_box(screen.grow(2), Color("080c0e"), Color("323a3d"), 2)
	_box(screen, FACE, Color("081114"), 0)
	_text(Vector2(x + 12, 179), label, BODY, 16, LEGEND, width - 24, HORIZONTAL_ALIGNMENT_CENTER)
	return screen

func _draw() -> void:
	_draw_motion()
	_draw_rudder()
	_draw_engine()
	_draw_fuel()
	_draw_mooring()

func _draw_motion() -> void:
	var screen := _case(0, 198, "MOTION")
	var x := screen.position.x
	var speed := float(state.get("ahead_kn", 0))
	_text(Vector2(x + 9, 43), "SPEED", BODY, 16, INK)
	_text(Vector2(x + 9, 96), "%.1f" % absf(speed), DIGITS, 62, INK)
	_text(Vector2(x + 125, 92), "kn", BODY, 19, INK)
	draw_line(Vector2(x, 101), Vector2(x + screen.size.x, 101), Color("a1aeaf"), 1, true)
	_text(Vector2(x + 9, 120), "HDG", BODY, 16, INK)
	_text(Vector2(x + 49, 146), "%03.0f°" % fposmod(float(state.get("heading", 0)), 360), DIGITS, 36, INK, 101, HORIZONTAL_ALIGNMENT_RIGHT)
	_text(Vector2(x + 9, 146), "ASTERN" if speed < -.05 else "AHEAD", BODY, 14, Color("556366"))

func _draw_rudder() -> void:
	var screen := _case(208, 222, "RUDDER ANGLE")
	var center := Vector2(screen.get_center().x, 24)
	var radius := 125.0
	# A lower quadrant scale mirrors marine rudder repeaters; port left/red.
	var arc_start := deg_to_rad(48)
	var arc_end := deg_to_rad(132)
	draw_arc(center, radius, arc_start, arc_end, 72, Color("506065"), 1, true)
	draw_arc(center, radius - 8, arc_start, PI / 2, 36, GREEN, 5, true)
	draw_arc(center, radius - 8, PI / 2, arc_end, 36, RED, 5, true)
	for degrees in range(-40, 41, 5):
		var direction := Vector2.from_angle(deg_to_rad(90 - degrees))
		var major := degrees % 10 == 0
		draw_line(center + direction * (radius - (16 if major else 11)), center + direction * (radius - 2), INK, 1.5 if major else 1.0, true)
		if degrees % 20 == 0:
			var at := center + direction * (radius - 26)
			_text(at + Vector2(-14, 5), str(absi(degrees)), DIGITS, 16, INK, 28, HORIZONTAL_ALIGNMENT_CENTER)
	var angle := float(state.get("rudder", 0))
	var direction := Vector2.from_angle(deg_to_rad(90 - clampf(angle, -40, 40)))
	var across := direction.orthogonal() * 3
	draw_colored_polygon(PackedVector2Array([center + direction * 76 - across, center + direction * 76 + across, center + direction * 123]), Color("a52d27"))
	var readout := "0°" if absf(angle) < .5 else "%s%.0f°" % ["P" if angle < 0 else "S", absf(angle)]
	_text(Vector2(screen.position.x, 44), "Rudder", BODY, 16, INK, screen.size.x, HORIZONTAL_ALIGNMENT_CENTER)
	_text(Vector2(screen.position.x, 86), readout, DIGITS, 56, INK, screen.size.x, HORIZONTAL_ALIGNMENT_CENTER)

func _draw_engine() -> void:
	var screen := _case(440, 280, "PROPULSION CONTROL")
	var x := screen.position.x
	var running := bool(state.get("engine_running", false))
	_text(Vector2(x + 11, 43), "RUNNING · I STOP" if running else "ENGINE OFF · I START", BODY, 14, INK)
	var order := str(state.get("order", "STOP"))
	_text(Vector2(x + 10, 84), order, DIGITS, 35, INK, screen.size.x - 20, HORIZONTAL_ALIGNMENT_CENTER)
	draw_line(Vector2(x, 98), Vector2(screen.end.x, 98), Color("a1aeaf"), 1, true)
	var automatic := bool(state.get("autopilot", false))
	_indicator(Vector2(x + 15, 116), automatic, GREEN)
	_text(Vector2(x + 29, 123), "AUTO" if automatic else "MANUAL", BODY, 18, INK)
	_text(Vector2(x + 11, 147), "THRUSTER", BODY, 16, INK)
	_text(Vector2(x + 110, 147), str(state.get("thruster", "Off")).to_upper(), BODY, 18, INK, 118, HORIZONTAL_ALIGNMENT_RIGHT)

func _draw_fuel() -> void:
	var screen := _case(730, 108, "FUEL")
	var value := clampf(float(state.get("fuel", 0)), 0, 1)
	var x := screen.position.x
	_text(Vector2(x + 3, 49), "%.0f" % (value * 100), DIGITS, 34, INK, 46, HORIZONTAL_ALIGNMENT_RIGHT)
	_text(Vector2(x + 50, 48), "%", BODY, 15, INK)
	for step in range(10):
		var on := value * 10 >= 10 - step
		var color := INK if on else Color("c7d0d0")
		if on and value < .2: color = RED
		draw_rect(Rect2(x + 23, 57 + step * 8, 37, 5), color)
	_text(Vector2(x + 6, 66), "F", BODY, 12, INK)
	_text(Vector2(x + 6, 135), "E", BODY, 12, INK)

func _indicator(at: Vector2, active: bool, color: Color) -> void:
	draw_circle(at, 5, Color("050a0b"))
	draw_circle(at, 3, color if active else Color("4a5252"))
	if active: draw_circle(at + Vector2(-1, -1), 1, color.lightened(.3))

func _draw_mooring() -> void:
	_box(Rect2(0, 200, WIDTH, 40), Color("1a2124"), Color("485256"), 3)
	_indicator(Vector2(16, 220), bool(state.get("bow", false)), AMBER)
	_text(Vector2(28, 226), "BOW " + ("SECURED" if state.get("bow", false) else "FREE"), BODY, 17, FACE)
	_indicator(Vector2(174, 220), bool(state.get("stern", false)), AMBER)
	_text(Vector2(186, 226), "STERN " + ("SECURED" if state.get("stern", false) else "FREE"), BODY, 17, FACE)
	var drift := float(state.get("side_kn", 0))
	_text(Vector2(350, 226), "DRIFT %.1f kn %s" % [absf(drift), "P" if drift < 0 else "S"], BODY, 17, FACE)
	_text(Vector2(510, 226), str(state.get("mooring_reason", "")), BODY, 17, AMBER, WIDTH - 522)
