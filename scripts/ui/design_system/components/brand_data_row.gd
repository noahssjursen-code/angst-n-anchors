class_name BrandDataRow
extends HBoxContainer

var key_label: BrandLabel
var value_label: BrandLabel


func _init(key_text: String = "", value_text: String = "") -> void:
	add_theme_constant_override(&"separation", BrandTokens.GROUP_GAP)
	key_label = BrandLabel.new(key_text, BrandLabel.Role.BODY_MUTED)
	key_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(key_label)
	value_label = BrandLabel.new(value_text, BrandLabel.Role.DATA)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(value_label)


func set_value(value: String, role: BrandLabel.Role = BrandLabel.Role.DATA) -> void:
	value_label.text = value
	value_label.role = role
