class_name UiModal
extends Control

## Full-screen modal frame: dimmed scrim, centred sheet with a crane-yellow
## top edge (or hazard chevrons when `warning`), signage header, body and an
## optional footer action bar. Screens fill `body` / `footer`.

signal close_requested

var body: VBoxContainer
var footer: HBoxContainer
var header_box: HBoxContainer
var title_label: Label
var eyebrow_label: Label
var sheet: PanelContainer
var close_button: Button

var _footer_panel: PanelContainer


func _init(title_text: String = "", eyebrow_text: String = "",
		sheet_size: Vector2 = Vector2(760, 520), warning: bool = false,
		closable: bool = true) -> void:
	name = "Modal"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(Ui.scrim())

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	sheet = Ui.surface("Rail", sheet_size)
	center.add_child(sheet)
	var stack := Ui.vbox(0)
	sheet.add_child(stack)

	if warning:
		stack.add_child(Ui.hazard(8.0))
	else:
		var edge := ColorRect.new()
		edge.color = UiPalette.CRANE
		edge.custom_minimum_size = Vector2(0, UiPalette.EDGE)
		stack.add_child(edge)

	var head := Ui.surface("SheetHeader")
	stack.add_child(head)
	header_box = Ui.hbox(UiPalette.GAP_M)
	head.add_child(header_box)
	var titles := Ui.vbox(0)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	eyebrow_label = Ui.eyebrow(eyebrow_text)
	eyebrow_label.visible = eyebrow_text != ""
	titles.add_child(eyebrow_label)
	title_label = Ui.heading(title_text)
	titles.add_child(title_label)
	header_box.add_child(titles)
	if closable:
		close_button = Ui.button("Close", "ghost", func(): close_requested.emit())
		close_button.icon = null
		var esc := Ui.key_hint("Esc", "")
		esc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var close_row := Ui.hbox(4)
		close_row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		close_row.add_child(esc)
		close_row.add_child(close_button)
		header_box.add_child(close_row)

	var pad := MarginContainer.new()
	pad.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pad.add_theme_constant_override("margin_left", 28)
	pad.add_theme_constant_override("margin_right", 28)
	pad.add_theme_constant_override("margin_top", 20)
	pad.add_theme_constant_override("margin_bottom", 20)
	stack.add_child(pad)
	body = Ui.vbox(UiPalette.GAP_M)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pad.add_child(body)

	_footer_panel = Ui.surface("SheetHeader")
	_footer_panel.visible = false
	stack.add_child(_footer_panel)
	footer = Ui.hbox(UiPalette.GAP_S)
	footer.alignment = BoxContainer.ALIGNMENT_END
	_footer_panel.add_child(footer)


func set_title(title_text: String, eyebrow_text: String = "") -> void:
	title_label.text = title_text.to_upper()
	eyebrow_label.text = eyebrow_text.to_upper()
	eyebrow_label.visible = eyebrow_text != ""


## Adds a footer action and reveals the footer bar.
func add_action(label_text: String, kind: String = "secondary",
		on_pressed: Callable = Callable()) -> Button:
	_footer_panel.visible = true
	var b := Ui.button(label_text, kind, on_pressed)
	footer.add_child(b)
	return b


func footer_note(text_value: String) -> Label:
	_footer_panel.visible = true
	var l := Ui.caption(text_value)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(l)
	footer.move_child(l, 0)
	return l


func _unhandled_input(event: InputEvent) -> void:
	if visible and close_button != null and event.is_action_pressed("ui_cancel"):
		close_requested.emit()
		get_viewport().set_input_as_handled()
