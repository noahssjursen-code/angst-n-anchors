class_name UiQuayRule
extends Control

## Dashed divider, like the centre line painted along the quay roads.

@export var color: Color = UiPalette.KERB_STRONG
@export var dash: float = 18.0
@export var gap: float = 10.0
@export var thickness: float = 2.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(0.0, 6.0)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _ready() -> void:
	resized.connect(queue_redraw)


func _draw() -> void:
	var y := size.y * 0.5 - thickness * 0.5
	var x := 0.0
	while x < size.x:
		draw_rect(Rect2(x, y, minf(dash, size.x - x), thickness), color)
		x += dash + gap
