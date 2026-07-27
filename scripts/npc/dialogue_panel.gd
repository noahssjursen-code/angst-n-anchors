class_name DialoguePanel
extends CanvasLayer

## Shared NPC conversation surface. The paper speech band sits on the
## waterline, leaving the NPC and world visible; numbered choices stack above.

const DEFAULT_SIZE := Vector2(720.0, 500.0)
const BAND_HEIGHT := 184.0
const PORTRAIT_WIDTH := 184.0
const SAFE_EDGE := 32.0
const BRAND_MARK := preload("res://resources/ui/brand/anchor-mark-paper.svg")

var _root: Control
var _band: BrandPanel
var _choices_panel: BrandPanel
var _speech: VBoxContainer
var _choices: VBoxContainer
var _choices_scroll: ScrollContainer
var _title_label: BrandLabel
var _panel_size := DEFAULT_SIZE
var _viewport_fit_fraction := -1.0
var _viewport_fit_aspect := 16.0 / 9.0
var _first_option: Control
var _option_number := 0
var _option_buttons: Array[Button] = []


func _init(title_text: String = "", panel_size: Vector2 = DEFAULT_SIZE) -> void:
	name = "DialoguePanel"
	layer = 30
	_panel_size = panel_size

	_root = Control.new()
	_root.name = "DialogueRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = BrandTheme.shared()
	_root.visible = false
	add_child(_root)

	_build_band(title_text)
	_build_choices()
	_apply_panel_size(panel_size)


func _build_band(title_text: String) -> void:
	_band = BrandPanel.new(BrandPanel.Variant.RULED)
	_band.name = "SpeechBand"
	_band.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_band.offset_top = -BAND_HEIGHT
	_band.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(_band)

	var band_row := HBoxContainer.new()
	band_row.add_theme_constant_override(&"separation", BrandTokens.SPACE_XL)
	_band.add_child(band_row)

	var portrait := BrandPanel.new(BrandPanel.Variant.DARK)
	portrait.custom_minimum_size.x = PORTRAIT_WIDTH
	band_row.add_child(portrait)
	var mark := TextureRect.new()
	mark.texture = BRAND_MARK
	mark.custom_minimum_size = Vector2(104.0, 104.0)
	mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.add_child(mark)

	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.add_theme_constant_override(&"separation", BrandTokens.SPACE_SM)
	band_row.add_child(copy)

	var identity := HBoxContainer.new()
	identity.add_theme_constant_override(&"separation", BrandTokens.SPACE_LG)
	copy.add_child(identity)
	_title_label = BrandLabel.new(title_text.to_upper(), BrandLabel.Role.DISPLAY_SMALL)
	identity.add_child(_title_label)
	var meta := BrandLabel.new(tr("QUAYSIDE OFFICE"), BrandLabel.Role.DATA_MUTED)
	meta.size_flags_vertical = Control.SIZE_SHRINK_END
	identity.add_child(meta)

	var speech_scroll := ScrollContainer.new()
	speech_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	speech_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	copy.add_child(speech_scroll)
	_speech = VBoxContainer.new()
	_speech.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_speech.add_theme_constant_override(&"separation", BrandTokens.SPACE_XS)
	speech_scroll.add_child(_speech)

	var footer := HBoxContainer.new()
	copy.add_child(footer)
	var hint := BrandLabel.new(
		tr("CHOOSE AN OPTION · 1–9 / CLICK · ESC CLOSE"),
		BrandLabel.Role.MICRO_DATA
	)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(hint)
	var caret := BrandLabel.new("▼", BrandLabel.Role.DATA)
	caret.add_theme_color_override(&"font_color", BrandTokens.BRASS)
	footer.add_child(caret)


func _build_choices() -> void:
	_choices_panel = BrandPanel.new(BrandPanel.Variant.PAPER)
	_choices_panel.name = "Choices"
	_choices_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(_choices_panel)

	_choices_scroll = ScrollContainer.new()
	_choices_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_choices_panel.add_child(_choices_scroll)
	_choices = VBoxContainer.new()
	_choices.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_choices.add_theme_constant_override(&"separation", BrandTokens.SPACE_SM)
	_choices_scroll.add_child(_choices)


func _ready() -> void:
	var viewport := get_viewport()
	if viewport != null and not viewport.size_changed.is_connected(_on_viewport_size_changed):
		viewport.size_changed.connect(_on_viewport_size_changed)


func show_panel() -> void:
	fit_viewport_if_configured()
	_root.visible = true
	BrandMotion.panel_in(_band, Vector2(0.0, 16.0))
	BrandMotion.panel_in(_choices_panel, Vector2(12.0, 0.0))
	if _first_option != null:
		_first_option.call_deferred("grab_focus")


func hide_panel() -> void:
	if _root != null:
		_root.visible = false


func is_open() -> bool:
	return _root != null and _root.visible


func set_title(text: String) -> void:
	if _title_label != null:
		_title_label.text = text.to_upper()


func set_panel_size(panel_size: Vector2) -> void:
	_viewport_fit_fraction = -1.0
	_panel_size = panel_size
	_apply_panel_size(panel_size)


func fit_viewport(fraction: float = 0.78, aspect: float = 16.0 / 9.0) -> void:
	_viewport_fit_fraction = fraction
	_viewport_fit_aspect = aspect
	var viewport := get_viewport()
	if viewport == null:
		return
	_panel_size = _viewport_panel_size(viewport.get_visible_rect().size, fraction, aspect)
	_apply_panel_size(_panel_size)


func fit_viewport_if_configured() -> void:
	if _viewport_fit_fraction > 0.0:
		fit_viewport(_viewport_fit_fraction, _viewport_fit_aspect)
	else:
		_apply_panel_size(_panel_size)


func _apply_panel_size(panel_size: Vector2) -> void:
	if _choices_panel == null:
		return
	var viewport_size := (
		get_viewport().get_visible_rect().size
		if get_viewport() != null
		else Vector2(1920.0, 1080.0)
	)
	var width := minf(maxf(panel_size.x, 420.0), viewport_size.x - SAFE_EDGE * 2.0)
	var requested_height := maxf(panel_size.y - BAND_HEIGHT, 176.0)
	var height := minf(requested_height, viewport_size.y - BAND_HEIGHT - SAFE_EDGE * 2.0)
	_choices_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_choices_panel.offset_left = -width - SAFE_EDGE
	_choices_panel.offset_right = -SAFE_EDGE
	_choices_panel.offset_top = -BAND_HEIGHT - height - BrandTokens.SPACE_LG
	_choices_panel.offset_bottom = -BAND_HEIGHT - BrandTokens.SPACE_LG


static func viewport_panel_size(
		viewport_size: Vector2,
		fraction: float,
		aspect: float = 16.0 / 9.0
	) -> Vector2:
	return _viewport_panel_size(viewport_size, fraction, aspect)


static func _viewport_panel_size(
		viewport_size: Vector2,
		fraction: float,
		aspect: float
	) -> Vector2:
	var max_width := viewport_size.x * fraction
	var max_height := viewport_size.y * fraction
	var width := max_width
	var height := width / aspect
	if height > max_height:
		height = max_height
		width = height * aspect
	return Vector2(width, height)


func _on_viewport_size_changed() -> void:
	if _viewport_fit_fraction > 0.0 and is_open():
		fit_viewport(_viewport_fit_fraction, _viewport_fit_aspect)
	elif is_open():
		_apply_panel_size(_panel_size)


func clear() -> void:
	_first_option = null
	_option_number = 0
	_option_buttons.clear()
	_clear_container(_speech)
	_clear_container(_choices)
	_choices_scroll.scroll_vertical = 0


func _clear_container(container: Container) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()


func add_quote(text: String) -> Label:
	var label := BrandLabel.new(text, BrandLabel.Role.BODY)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override(&"font_size", 21)
	_speech.add_child(label)
	return label


func add_label(text: String, font_size: int = BrandTokens.BODY) -> Label:
	var label := BrandLabel.new(text, BrandLabel.Role.BODY_MUTED)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if font_size != BrandTokens.BODY:
		label.add_theme_font_size_override(&"font_size", font_size)
	_choices.add_child(label)
	return label


func add_option(text: String, callback: Callable) -> Button:
	_option_number += 1
	var prefix := "%d  " % _option_number if _option_number <= 9 else ""
	var button := BrandButton.new(prefix + text, BrandButton.Variant.SECONDARY)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(callback)
	_choices.add_child(button)
	_option_buttons.append(button)
	if _first_option == null:
		_first_option = button
	return button


func add_disabled_option(text: String) -> Button:
	_option_number += 1
	var prefix := "%d  " % _option_number if _option_number <= 9 else ""
	var button := BrandButton.new(prefix + text, BrandButton.Variant.QUIET)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.disabled = true
	_choices.add_child(button)
	_option_buttons.append(button)
	return button


func add_separator() -> void:
	_choices.add_child(HSeparator.new())


func add_back_button(callback: Callable, label: String = "← Back") -> Button:
	add_separator()
	var button := BrandButton.new(label, BrandButton.Variant.QUIET)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.pressed.connect(callback)
	_choices.add_child(button)
	if _first_option == null:
		_first_option = button
	return button


func add_custom(control: Control) -> void:
	_choices.add_child(control)


func get_panel() -> Control:
	return _band


func _unhandled_input(event: InputEvent) -> void:
	if not is_open() or not event is InputEventKey:
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	var index := -1
	if key.keycode >= KEY_1 and key.keycode <= KEY_9:
		index = key.keycode - KEY_1
	if index < 0 or index >= _option_buttons.size():
		return
	var button := _option_buttons[index]
	if not button.disabled:
		button.pressed.emit()
		get_viewport().set_input_as_handled()
