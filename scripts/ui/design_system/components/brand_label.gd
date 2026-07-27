class_name BrandLabel
extends Label

enum Role {
	DISPLAY_LARGE,
	DISPLAY_MEDIUM,
	DISPLAY_SMALL,
	BODY,
	BODY_MUTED,
	DATA,
	DATA_MUTED,
	MICRO_DATA,
	INVERSE_BODY,
	INVERSE_DATA,
	SECTION,
	STATUS_OK,
	STATUS_WARN,
	STATUS_ALERT,
}

@export var role: Role = Role.BODY:
	set(value):
		role = value
		_apply_role()


func _init(text_value: String = "", role_value: Role = Role.BODY) -> void:
	theme = BrandTheme.shared()
	text = text_value
	role = role_value


func _ready() -> void:
	_apply_role()


func _apply_role() -> void:
	theme_type_variation = _variation_for(role)


static func _variation_for(value: Role) -> StringName:
	match value:
		Role.DISPLAY_LARGE:
			return &"BrandDisplayLarge"
		Role.DISPLAY_MEDIUM:
			return &"BrandDisplayMedium"
		Role.DISPLAY_SMALL:
			return &"BrandDisplaySmall"
		Role.BODY_MUTED:
			return &"BrandBodyMuted"
		Role.DATA:
			return &"BrandData"
		Role.DATA_MUTED:
			return &"BrandDataMuted"
		Role.MICRO_DATA:
			return &"BrandMicroData"
		Role.INVERSE_BODY:
			return &"BrandInverseBody"
		Role.INVERSE_DATA:
			return &"BrandInverseData"
		Role.SECTION:
			return &"BrandSectionLabel"
		Role.STATUS_OK:
			return &"BrandStatusOk"
		Role.STATUS_WARN:
			return &"BrandStatusWarn"
		Role.STATUS_ALERT:
			return &"BrandStatusAlert"
	return &"BrandBody"
