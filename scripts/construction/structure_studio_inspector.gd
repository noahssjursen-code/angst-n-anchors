class_name StructureStudioInspector
extends RefCounted

## Builds Structure Studio inspector rows without owning plan state.
## Callers supply Callables for spin commits and actions.


static func spin_row(
	label_text: String,
	value: float,
	min_value: float,
	max_value: float,
	step: float,
	on_change: Callable,
) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var label := Label.new()
	label.text = label_text.capitalize()
	label.custom_minimum_size = Vector2(84, 0)
	HudStyle.apply_body_font(label, 12, HudStyle.C_LABEL)
	row.add_child(label)
	var spin := SpinBox.new()
	spin.min_value = min_value
	spin.max_value = max_value
	spin.step = step
	spin.value = value
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin.value_changed.connect(on_change)
	row.add_child(spin)
	return row


static func header(kind: String, entity_id: int) -> Label:
	var label := Label.new()
	label.text = "%s  #%d" % [kind.to_upper(), entity_id]
	HudStyle.apply_body_font(label, 13, HudStyle.C_AMBER, true)
	return label


static func empty_guidance() -> String:
	return "Nothing selected.\n\nDraw with Wall / Room / Deck, or switch to Select and click a piece.\n\nArm Outside/Inside above, then paint materials onto the selection."
