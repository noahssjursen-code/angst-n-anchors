class_name BrandButton
extends Button

enum Variant {
	PRIMARY,
	SECONDARY,
	LOUD,
	QUIET,
	DANGER,
	CHIP,
}

@export var variant: Variant = Variant.SECONDARY:
	set(value):
		variant = value
		_apply_variant()


func _init(text_value: String = "", variant_value: Variant = Variant.SECONDARY) -> void:
	theme = BrandTheme.shared()
	text = text_value
	variant = variant_value
	custom_minimum_size.y = BrandTokens.MIN_HIT_TARGET
	focus_mode = Control.FOCUS_ALL


func _ready() -> void:
	custom_minimum_size.y = maxf(custom_minimum_size.y, BrandTokens.MIN_HIT_TARGET)
	_apply_variant()


func _apply_variant() -> void:
	match variant:
		Variant.PRIMARY:
			theme_type_variation = &"BrandPrimaryButton"
		Variant.LOUD:
			theme_type_variation = &"BrandLoudButton"
		Variant.QUIET:
			theme_type_variation = &"BrandQuietButton"
		Variant.DANGER:
			theme_type_variation = &"BrandDangerButton"
		Variant.CHIP:
			theme_type_variation = &"BrandChipButton"
		_:
			theme_type_variation = &"BrandSecondaryButton"
