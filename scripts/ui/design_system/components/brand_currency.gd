class_name BrandCurrency
extends HBoxContainer

const MARK_TEXTURE := preload("res://resources/ui/brand/mark-glyph.svg")
const MARK_TEXTURE_INVERSE := preload("res://resources/ui/brand/mark-glyph-brass.svg")

var value_label: BrandLabel


func _init(amount: int = 0, inverse: bool = false) -> void:
	theme = BrandTheme.shared()
	add_theme_constant_override(&"separation", BrandTokens.SPACE_SM)
	var mark := TextureRect.new()
	mark.texture = MARK_TEXTURE_INVERSE if inverse else MARK_TEXTURE
	mark.custom_minimum_size = Vector2(BrandTokens.MIN_ICON_BOX, BrandTokens.MIN_ICON_BOX)
	mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	add_child(mark)
	value_label = BrandLabel.new(
		BrandFormat.money(amount),
		BrandLabel.Role.INVERSE_DATA if inverse else BrandLabel.Role.DATA
	)
	add_child(value_label)


func set_amount(amount: int) -> void:
	value_label.text = BrandFormat.money(amount)
