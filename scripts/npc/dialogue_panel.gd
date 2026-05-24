class_name DialoguePanel
extends CanvasLayer

## Reusable dialogue / shop panel for NPC interactions.
##
## Owns the boilerplate every NPC used to copy/paste: CanvasLayer + Panel +
## centered title + ScrollContainer + content VBox + a small library of
## row-builder helpers (quote, option, disabled option, separator, back/close).
##
## Typical flow:
##     var dialogue := DialoguePanel.new("HARBOUR MASTER")
##     add_child(dialogue)
##     ...
##     dialogue.clear()
##     dialogue.add_quote("Good day, Captain.")
##     dialogue.add_option("Berth me.", _show_berth)
##     dialogue.show_panel()
##
## NPCs still own their own dialogue state machine (which screen they're on,
## what action a button triggers) — this just removes the UI plumbing.

## Default size unless caller overrides via panel_size in _init.
const DEFAULT_SIZE := Vector2(600.0, 440.0)

var _panel:        Panel
var _body:         VBoxContainer
var _scroll:       ScrollContainer
var _title_label:  Label
var _viewport_fit_fraction: float = -1.0
var _viewport_fit_aspect: float = 16.0 / 9.0


func _init(title_text: String = "", panel_size: Vector2 = DEFAULT_SIZE) -> void:
	name = "DialoguePanel"
	_panel               = Panel.new()
	_panel.name          = "Panel"
	_panel.visible       = false
	_panel.theme         = HudStyle.make_theme()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.offset_left   = -panel_size.x * 0.5
	_panel.offset_right  =  panel_size.x * 0.5
	_panel.offset_top    = -panel_size.y * 0.5
	_panel.offset_bottom =  panel_size.y * 0.5
	add_child(_panel)

	_title_label                       = Label.new()
	_title_label.text                  = title_text
	_title_label.horizontal_alignment  = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 15)
	_title_label.add_theme_color_override("font_color", HudStyle.C_AMBER)
	_title_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_title_label.offset_top    = 10.0
	_title_label.offset_bottom = 40.0
	_panel.add_child(_title_label)

	_scroll                       = ScrollContainer.new()
	_scroll.name                  = "Scroll"
	_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scroll.offset_top    = 48.0
	_scroll.offset_bottom = -8.0
	_panel.add_child(_scroll)

	_body                       = VBoxContainer.new()
	_body.name                  = "Body"
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_body)


# ── Visibility ────────────────────────────────────────────────────────────────

func show_panel() -> void:
	fit_viewport_if_configured()
	_panel.visible = true


func hide_panel() -> void:
	_panel.visible = false


func is_open() -> bool:
	return _panel != null and _panel.visible


func set_title(text: String) -> void:
	if _title_label != null:
		_title_label.text = text


func set_panel_size(panel_size: Vector2) -> void:
	_viewport_fit_fraction = -1.0
	_apply_panel_size(panel_size)


## Size a 16:9 (or custom aspect) panel to fit within `fraction` of the viewport.
func fit_viewport(fraction: float = 0.75, aspect: float = 16.0 / 9.0) -> void:
	_viewport_fit_fraction = fraction
	_viewport_fit_aspect = aspect
	var vp := get_viewport()
	if vp == null:
		return
	_apply_panel_size(_viewport_panel_size(vp.get_visible_rect().size, fraction, aspect))


func fit_viewport_if_configured() -> void:
	if _viewport_fit_fraction > 0.0:
		fit_viewport(_viewport_fit_fraction, _viewport_fit_aspect)


func _apply_panel_size(panel_size: Vector2) -> void:
	if _panel == null:
		return
	_panel.offset_left = -panel_size.x * 0.5
	_panel.offset_right = panel_size.x * 0.5
	_panel.offset_top = -panel_size.y * 0.5
	_panel.offset_bottom = panel_size.y * 0.5


static func viewport_panel_size(
	viewport_size: Vector2, fraction: float, aspect: float = 16.0 / 9.0
) -> Vector2:
	return _viewport_panel_size(viewport_size, fraction, aspect)


static func _viewport_panel_size(
	viewport_size: Vector2, fraction: float, aspect: float
) -> Vector2:
	var max_w := viewport_size.x * fraction
	var max_h := viewport_size.y * fraction
	var w := max_w
	var h := w / aspect
	if h > max_h:
		h = max_h
		w = h * aspect
	return Vector2(w, h)


func _ready() -> void:
	var vp := get_viewport()
	if vp != null and not vp.size_changed.is_connected(_on_viewport_size_changed):
		vp.size_changed.connect(_on_viewport_size_changed)


func _on_viewport_size_changed() -> void:
	if _viewport_fit_fraction > 0.0 and is_open():
		fit_viewport(_viewport_fit_fraction, _viewport_fit_aspect)


# ── Content ───────────────────────────────────────────────────────────────────

func clear() -> void:
	for child in _body.get_children():
		child.queue_free()


## Multi-line quote text (autowrap, amber). Returns the Label so caller can
## tweak font / colour for special lines (headers, warnings).
func add_quote(text: String) -> Label:
	var lbl                   := Label.new()
	lbl.text                  = text
	lbl.autowrap_mode         = TextServer.AUTOWRAP_WORD
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.add_theme_font_size_override("font_size", 15)
	_body.add_child(lbl)
	_body.add_child(HSeparator.new())
	return lbl


## Plain label row (no separator after). Smaller font than add_quote.
func add_label(text: String, font_size: int = 13) -> Label:
	var lbl                   := Label.new()
	lbl.text                  = text
	lbl.autowrap_mode         = TextServer.AUTOWRAP_WORD
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.add_theme_font_size_override("font_size", font_size)
	_body.add_child(lbl)
	return lbl


## Clickable option button. Returns the Button so caller can style further.
func add_option(text: String, callback: Callable) -> Button:
	var btn                   := Button.new()
	btn.text                  = text
	btn.alignment             = HORIZONTAL_ALIGNMENT_LEFT
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.pressed.connect(callback)
	_body.add_child(btn)
	return btn


## Greyed-out option (informational — "Reserved", "Out of stock", etc.).
func add_disabled_option(text: String) -> Button:
	var btn                   := Button.new()
	btn.text                  = text
	btn.alignment             = HORIZONTAL_ALIGNMENT_LEFT
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.disabled              = true
	_body.add_child(btn)
	return btn


func add_separator() -> void:
	_body.add_child(HSeparator.new())


## Convenience: separator + "← Back" option. NPCs use this at the bottom of
## sub-screens to return to a previous screen.
func add_back_button(callback: Callable, label: String = "← Back") -> Button:
	add_separator()
	return add_option(label, callback)


## For shop-style screens (ContractNpc) that build custom multi-row widgets.
## Lets callers add anything (HBoxContainer, ColorRect, etc.) without going
## through the quote/option helpers.
func add_custom(control: Control) -> void:
	_body.add_child(control)


## Read-only access for callers that need to anchor a fixed footer (e.g. a
## persistent Close button at the bottom of the panel) outside the scroll.
func get_panel() -> Panel:
	return _panel
