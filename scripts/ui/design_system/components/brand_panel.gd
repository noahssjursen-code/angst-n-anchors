class_name BrandPanel
extends PanelContainer

enum Variant {
	PAPER,
	RAISED,
	RULED,
	DARK,
	DARK_RULED,
	BAND,
	TOOLBAR,
}

@export var variant: Variant = Variant.PAPER:
	set(value):
		variant = value
		_apply_variant()


func _init(variant_value: Variant = Variant.PAPER) -> void:
	theme = BrandTheme.shared()
	variant = variant_value


func _ready() -> void:
	_apply_variant()


func _apply_variant() -> void:
	match variant:
		Variant.RAISED:
			theme_type_variation = &"BrandRaisedPanel"
		Variant.RULED:
			theme_type_variation = &"BrandRuledPanel"
		Variant.DARK:
			theme_type_variation = &"BrandDarkPanel"
		Variant.DARK_RULED:
			theme_type_variation = &"BrandDarkRuledPanel"
		Variant.BAND:
			theme_type_variation = &"BrandBand"
		Variant.TOOLBAR:
			theme_type_variation = &"BrandToolbarPanel"
		_:
			theme_type_variation = &"BrandSurfacePanel"
