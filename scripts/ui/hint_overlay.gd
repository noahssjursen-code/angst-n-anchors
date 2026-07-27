class_name HintOverlay
extends Control

## Tutorial hints use the same toast component as the rest of the interface.
## New hints replace the visible one, preserving the original queue semantics.

var _toast: BrandToast


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	z_index = 6
	_toast = BrandToast.new()
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.offset_left = -320.0
	_toast.offset_right = 320.0
	_toast.offset_top = BrandTokens.SPACE_HUGE
	_toast.custom_minimum_size.y = 64.0
	add_child(_toast)
	var tutorial := get_node_or_null("/root/Tutorial")
	if tutorial != null and tutorial.has_signal("hint_requested"):
		tutorial.hint_requested.connect(_on_hint_requested)


func _on_hint_requested(message: String, duration_seconds: float) -> void:
	_toast.show_message(message, duration_seconds)
