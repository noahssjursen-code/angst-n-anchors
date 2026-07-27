class_name BrandMenuButton
extends Button

## Edge-menu action with one brass rule. Used by the title and pause menus.

func _init(text_value: String = "") -> void:
	theme = BrandTheme.shared()
	text = text_value


func _ready() -> void:
	theme_type_variation = &"BrandMenuButton"
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	focus_mode = Control.FOCUS_ALL
	custom_minimum_size = Vector2(320.0, BrandTokens.MIN_HIT_TARGET)
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)


func _draw() -> void:
	var active := is_hovered() or has_focus()
	var rule_color := BrandTokens.BRASS_LIGHT if active else BrandTokens.BRASS
	draw_rect(Rect2(0.0, 8.0, BrandTokens.RULE_WIDTH, maxf(size.y - 16.0, 16.0)), rule_color)
