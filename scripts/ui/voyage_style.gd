class_name VoyageStyle
extends RefCounted

const INK := Color("292e2a")
const PAPER := Color("eeeae1")
const MUTED := Color("66685e")
const ACCENT := Color("52624d")
const DARK := Color("292c28")
const LIGHT := Color("f3eee1")

static func box(color: Color, margin: int = 16) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(5)
	style.content_margin_left = margin
	style.content_margin_right = margin
	style.content_margin_top = margin
	style.content_margin_bottom = margin
	return style


static func theme() -> Theme:
	var result := Theme.new()
	result.default_font = load("res://resources/fonts/IBMPlexSans-Regular.ttf")
	result.default_font_size = 22
	result.set_color("font_color", "Label", INK)
	for type in ["Button", "OptionButton"]:
		result.set_color("font_color",type,INK)
		result.set_color("font_hover_color",type,INK)
		result.set_color("font_pressed_color",type,LIGHT)
		result.set_color("font_disabled_color",type,MUTED)
		result.set_stylebox("normal",type,box(Color("e0e5df"),12))
		result.set_stylebox("hover",type,box(Color("d1dbd4"),12))
		result.set_stylebox("pressed",type,box(ACCENT,12))
		result.set_stylebox("disabled",type,box(Color("e9e9e0"),12))
		var focus := box(Color.TRANSPARENT,12)
		focus.set_border_width_all(2)
		focus.border_color = ACCENT
		result.set_stylebox("focus",type,focus)
	result.set_stylebox("normal","LineEdit",box(Color.WHITE,12))
	result.set_color("font_color","LineEdit",INK)
	result.set_color("caret_color","LineEdit",ACCENT)
	result.set_color("font_placeholder_color","LineEdit",MUTED)
	result.set_constant("separation","VBoxContainer",14)
	result.set_constant("separation","HBoxContainer",16)
	return result


static func label(text: String, size: int = 22, color: Color = INK) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size",size)
	node.add_theme_color_override("font_color",color)
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node


static func button(text: String, callback: Callable, primary: bool = false) -> Button:
	var node := Button.new()
	node.text = text
	node.custom_minimum_size.y = 48
	node.pressed.connect(callback)
	if primary:
		node.add_theme_stylebox_override("normal",box(ACCENT,12))
		node.add_theme_stylebox_override("hover",box(ACCENT.lightened(.12),12))
		node.add_theme_color_override("font_color",LIGHT)
		node.add_theme_color_override("font_hover_color",LIGHT)
	return node


static func row(parent: Control, title: String, value: String) -> void:
	var line := HBoxContainer.new()
	parent.add_child(line)
	var key := label(title,20,MUTED)
	key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(key)
	var display := label(value,22)
	display.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	display.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(display)


static func clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()
