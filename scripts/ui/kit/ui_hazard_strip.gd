class_name UiHazardStrip
extends Control

## Diagonal hazard chevrons, as painted on crane legs and quay edges.
## Use sparingly: warnings, destructive confirmations, the title band.

@export var stripe_a: Color = UiPalette.CRANE
@export var stripe_b: Color = UiPalette.ON_CRANE
@export var stripe_width: float = 14.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true


func _ready() -> void:
	resized.connect(queue_redraw)


func _draw() -> void:
	var w := size.x
	var h := size.y
	draw_rect(Rect2(Vector2.ZERO, size), stripe_b)
	var step := stripe_width * 2.0
	var x := -h
	while x < w + h:
		var poly := PackedVector2Array([
			Vector2(x, h), Vector2(x + stripe_width, h),
			Vector2(x + stripe_width + h, 0.0), Vector2(x + h, 0.0)])
		draw_colored_polygon(poly, stripe_a)
		x += step
