class_name MenuActionButton
extends Button

## Title CTA — no heavy card chrome. Left copper tick + foam label;
## signal orange on hover. Reads as harbour-board lettering, not a dialog button.

var _tick: ColorRect


func _ready() -> void:
	flat = true
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	focus_mode = Control.FOCUS_ALL
	custom_minimum_size = Vector2(280, 44)
	HudStyle.apply_body_font(self, 18, HudStyle.C_TEXT, true)
	_apply_style(false)
	mouse_entered.connect(func() -> void: _apply_style(true))
	mouse_exited.connect(func() -> void: _apply_style(false))
	resized.connect(_layout_tick)
	_tick = ColorRect.new()
	_tick.color = HudStyle.C_COPPER
	_tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_tick)
	_layout_tick()


func _layout_tick() -> void:
	if _tick == null:
		return
	_tick.position = Vector2(0, 10)
	_tick.size = Vector2(3, maxf(size.y - 20.0, 12.0))


func _apply_style(hovered: bool) -> void:
	var empty := StyleBoxEmpty.new()
	empty.content_margin_left = 16
	empty.content_margin_right = 8
	empty.content_margin_top = 8
	empty.content_margin_bottom = 8
	add_theme_stylebox_override("normal", empty)
	add_theme_stylebox_override("hover", empty)
	add_theme_stylebox_override("pressed", empty)
	add_theme_stylebox_override("focus", empty)
	add_theme_stylebox_override("disabled", empty)
	var color := HudStyle.C_AMBER if hovered else HudStyle.C_TEXT
	add_theme_color_override("font_color", color)
	add_theme_color_override("font_hover_color", HudStyle.C_AMBER)
	add_theme_color_override("font_pressed_color", HudStyle.C_AMBER)
	add_theme_color_override("font_disabled_color", HudStyle.C_LABEL)
	if _tick != null:
		_tick.color = HudStyle.C_AMBER if hovered else HudStyle.C_COPPER
