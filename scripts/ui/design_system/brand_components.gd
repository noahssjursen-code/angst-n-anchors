class_name BrandComponents
extends RefCounted

## Composition helpers for common branded fragments. Stateful controls remain
## typed components; these factories only reduce repetitive layout plumbing.

static func panel(
		min_size: Vector2 = Vector2.ZERO,
		variant: BrandPanel.Variant = BrandPanel.Variant.RULED
	) -> BrandPanel:
	var result := BrandPanel.new(variant)
	result.custom_minimum_size = min_size
	return result


static func inner_panel(min_size: Vector2 = Vector2.ZERO) -> BrandPanel:
	return panel(min_size, BrandPanel.Variant.RAISED)


static func toolbar_panel(min_size: Vector2 = Vector2.ZERO) -> BrandPanel:
	return panel(min_size, BrandPanel.Variant.TOOLBAR)


static func title_label(text: String, size: int = BrandTokens.DISPLAY_S) -> BrandLabel:
	var role := BrandLabel.Role.DISPLAY_SMALL
	if size >= BrandTokens.DISPLAY_L:
		role = BrandLabel.Role.DISPLAY_LARGE
	elif size >= BrandTokens.DISPLAY_M:
		role = BrandLabel.Role.DISPLAY_MEDIUM
	var result := BrandLabel.new(text, role)
	result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return result


static func subtitle_label(text: String, _size: int = BrandTokens.LABEL_MONO) -> BrandLabel:
	var result := BrandLabel.new(text, BrandLabel.Role.DATA_MUTED)
	result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return result


static func section_header(text: String) -> BrandLabel:
	return BrandLabel.new(text.to_upper(), BrandLabel.Role.SECTION)


static func body_label(text: String, _size: int = BrandTokens.BODY) -> BrandLabel:
	return BrandLabel.new(text, BrandLabel.Role.BODY)


static func key_value_row(
		label: String,
		value: String,
		value_color: Color = BrandTokens.INK
	) -> BrandDataRow:
	var row := BrandDataRow.new(label, value)
	row.value_label.add_theme_color_override(&"font_color", value_color)
	return row


static func button(text: String, min_size: Vector2 = Vector2(264, 44)) -> BrandButton:
	var result := BrandButton.new(text, BrandButton.Variant.SECONDARY)
	result.custom_minimum_size = Vector2(min_size.x, maxf(min_size.y, BrandTokens.MIN_HIT_TARGET))
	return result


static func primary_button(text: String, min_size: Vector2 = Vector2(264, 44)) -> BrandButton:
	var result := BrandButton.new(text, BrandButton.Variant.PRIMARY)
	result.custom_minimum_size = Vector2(min_size.x, maxf(min_size.y, BrandTokens.MIN_HIT_TARGET))
	return result


static func loud_button(text: String, min_size: Vector2 = Vector2(264, 44)) -> BrandButton:
	var result := BrandButton.new(text, BrandButton.Variant.LOUD)
	result.custom_minimum_size = Vector2(min_size.x, maxf(min_size.y, BrandTokens.MIN_HIT_TARGET))
	return result


static func danger_button(text: String, min_size: Vector2 = Vector2(264, 44)) -> BrandButton:
	var result := BrandButton.new(text, BrandButton.Variant.DANGER)
	result.custom_minimum_size = Vector2(min_size.x, maxf(min_size.y, BrandTokens.MIN_HIT_TARGET))
	return result


static func compact_button(text: String, min_width: float = 0.0) -> BrandButton:
	var result := BrandButton.new(text, BrandButton.Variant.SECONDARY)
	result.custom_minimum_size = Vector2(min_width, BrandTokens.MIN_HIT_TARGET)
	return result


static func tool_button(text: String, min_width: float = 78.0) -> BrandButton:
	var result := BrandButton.new(text, BrandButton.Variant.CHIP)
	result.custom_minimum_size = Vector2(min_width, BrandTokens.MIN_HIT_TARGET)
	result.toggle_mode = true
	return result


static func separator() -> HSeparator:
	return HSeparator.new()


static func screen_margin(padding: int = BrandTokens.SPACE_XL) -> MarginContainer:
	var result := MarginContainer.new()
	result.add_theme_constant_override(&"margin_left", padding)
	result.add_theme_constant_override(&"margin_right", padding)
	result.add_theme_constant_override(&"margin_top", padding)
	result.add_theme_constant_override(&"margin_bottom", padding)
	return result
