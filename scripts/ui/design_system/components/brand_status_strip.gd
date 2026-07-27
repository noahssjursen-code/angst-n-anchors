class_name BrandStatusStrip
extends BrandPanel

var _row: HBoxContainer
var _right: BrandLabel


func _init() -> void:
	variant = Variant.BAND
	custom_minimum_size.y = 36.0
	_row = HBoxContainer.new()
	_row.add_theme_constant_override(&"separation", BrandTokens.SPACE_XL)
	add_child(_row)


func add_metric(label_text: String, value_text: String, value_role := BrandLabel.Role.INVERSE_DATA) -> BrandLabel:
	var group := HBoxContainer.new()
	group.add_theme_constant_override(&"separation", BrandTokens.SPACE_SM)
	_row.add_child(group)
	var label := BrandLabel.new(label_text.to_upper(), BrandLabel.Role.MICRO_DATA)
	label.add_theme_color_override(&"font_color", BrandTokens.INK_INVERSE)
	group.add_child(label)
	var value := BrandLabel.new(value_text, value_role)
	group.add_child(value)
	return value


func add_flexible_spacer() -> Control:
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_row.add_child(spacer)
	return spacer


func add_trailing(text_value: String) -> BrandLabel:
	_right = BrandLabel.new(text_value, BrandLabel.Role.MICRO_DATA)
	_right.add_theme_color_override(&"font_color", BrandTokens.INK_INVERSE_DIM)
	_row.add_child(_right)
	return _right
