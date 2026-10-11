class_name Ui
extends RefCounted

## Component factory for the quayside UI.
##
## Screens compose these instead of styling Controls by hand. Visual rules
## live in the project theme (`UiThemeBuilder`); factories only pick the named
## variation and wire common behaviour. Tones: "", "signal", "info", "ok",
## "danger", "caution", "muted", "faint".

const P := preload("res://scripts/ui/kit/ui_palette.gd")


# ── Layout ───────────────────────────────────────────────────────────────────

static func vbox(gap: int = P.GAP_S) -> VBoxContainer:
	var b := VBoxContainer.new()
	b.add_theme_constant_override("separation", gap)
	return b


static func hbox(gap: int = P.GAP_S) -> HBoxContainer:
	var b := HBoxContainer.new()
	b.add_theme_constant_override("separation", gap)
	return b


static func grid(columns: int, h_gap: int = P.GAP_M, v_gap: int = P.GAP_S) -> GridContainer:
	var g := GridContainer.new()
	g.columns = columns
	g.add_theme_constant_override("h_separation", h_gap)
	g.add_theme_constant_override("v_separation", v_gap)
	return g


static func margin(all: int = P.GAP_L) -> MarginContainer:
	var m := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		m.add_theme_constant_override(side, all)
	return m


static func spacer(min_px: float = 0.0, expand: bool = true) -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.custom_minimum_size = Vector2(min_px, min_px)
	if expand:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c


static func scroll(child: Control = null, horizontal: bool = false) -> ScrollContainer:
	var s := ScrollContainer.new()
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO if horizontal \
		else ScrollContainer.SCROLL_MODE_DISABLED
	if child != null:
		child.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		s.add_child(child)
	return s


static func expand(c: Control, h: bool = true, v: bool = false) -> Control:
	if h:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if v:
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c


# ── Surfaces ─────────────────────────────────────────────────────────────────

static func surface(variation: String = "Sheet", min_size: Vector2 = Vector2.ZERO) -> PanelContainer:
	var p := PanelContainer.new()
	p.theme_type_variation = variation
	p.custom_minimum_size = min_size
	return p


static func sheet(min_size: Vector2 = Vector2.ZERO) -> PanelContainer:
	return surface("Sheet", min_size)


static func card(tone: String = "", min_size: Vector2 = Vector2.ZERO) -> PanelContainer:
	var variation := "Card"
	match tone:
		"signal": variation = "SignalCard"
		"info":   variation = "InfoCard"
		"ok":     variation = "OkCard"
		"danger": variation = "DangerCard"
		"caution": variation = "CautionCard"
	return surface(variation, min_size)


static func inset(min_size: Vector2 = Vector2.ZERO) -> PanelContainer:
	return surface("Inset", min_size)


static func plate(min_size: Vector2 = Vector2.ZERO) -> PanelContainer:
	return surface("Plate", min_size)


static func scrim() -> Panel:
	var s := Panel.new()
	s.theme_type_variation = "Scrim"
	s.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	s.mouse_filter = Control.MOUSE_FILTER_STOP
	return s


# ── Text ─────────────────────────────────────────────────────────────────────

static func text(value: String, variation: String = "Body", tone: String = "") -> Label:
	var l := Label.new()
	l.text = value
	l.theme_type_variation = variation
	if tone != "":
		l.add_theme_color_override("font_color", P.tone(tone))
	return l


static func hero(value: String) -> Label:
	return text(value.to_upper(), "Hero")


static func display(value: String) -> Label:
	return text(value.to_upper(), "Display")


static func heading(value: String) -> Label:
	return text(value.to_upper(), "Heading")


static func title(value: String) -> Label:
	return text(value, "Title")


static func lead(value: String) -> Label:
	return text(value, "Lead")


static func caption(value: String, tone: String = "") -> Label:
	return text(value, "Caption", tone)


static func eyebrow(value: String, tone: String = "signal") -> Label:
	return text(value.to_upper(), "Eyebrow", tone)


static func field_label(value: String) -> Label:
	return text(value.to_upper(), "FieldLabel")


static func paragraph(value: String, variation: String = "Muted", min_width: float = 0.0) -> Label:
	var l := text(value, variation)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if min_width > 0.0:
		l.custom_minimum_size.x = min_width
	return l


## Eyebrow + heading + optional subtitle stack used at the top of screens.
static func header(eyebrow_text: String, heading_text: String, subtitle: String = "") -> VBoxContainer:
	var b := vbox(2)
	if eyebrow_text != "":
		b.add_child(eyebrow(eyebrow_text))
	b.add_child(heading(heading_text))
	if subtitle != "":
		b.add_child(paragraph(subtitle))
	return b


# ── Data display ─────────────────────────────────────────────────────────────

## Label left, value right. The value Label is stored as meta "value".
static func row(label_text: String, value_text: String = "", tone: String = "") -> HBoxContainer:
	var r := hbox(P.GAP_M)
	var l := text(label_text, "Muted")
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.clip_text = true
	var v := text(value_text, "Value", tone)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	r.add_child(l)
	r.add_child(v)
	r.set_meta("label", l)
	r.set_meta("value", v)
	return r


static func row_value(r: Control) -> Label:
	return r.get_meta("value") as Label if r != null and r.has_meta("value") else null


## Field caption above a value — the stencilled-label look on cargo and kit.
static func field(label_text: String, value_text: String = "", tone: String = "",
		variation: String = "Value") -> VBoxContainer:
	var b := vbox(1)
	b.add_child(field_label(label_text))
	var v := text(value_text, variation, tone)
	b.add_child(v)
	b.set_meta("value", v)
	return b


## Instrument readout: small caption, large mono figure, optional unit.
static func metric(label_text: String, value_text: String = "—", unit: String = "",
		tone: String = "") -> VBoxContainer:
	var b := vbox(0)
	b.add_child(field_label(label_text))
	var line := hbox(P.GAP_XS)
	var v := text(value_text, "Metric", tone)
	line.add_child(v)
	if unit != "":
		var u := text(unit, "Caption")
		u.size_flags_vertical = Control.SIZE_SHRINK_END
		line.add_child(u)
	b.add_child(line)
	b.set_meta("value", v)
	return b


static func badge(value: String, tone: String = "") -> Label:
	var l := text(value.to_upper(), "Badge")
	var c := P.tone(tone) if tone != "" else P.PAINT_MUTED
	l.add_theme_color_override("font_color", c)
	var sb := UiThemeBuilder.box(P.with_alpha(c, 0.12), P.with_alpha(c, 0.7), 1, 7.0, 1.0)
	l.add_theme_stylebox_override("normal", sb)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	return l


static func keycap(key: String) -> Label:
	var l := text(key.to_upper(), "Keycap")
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size.x = 24.0
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l


static func key_hint(key: String, action: String, variation: String = "Caption") -> HBoxContainer:
	var b := hbox(6)
	b.add_child(keycap(key))
	var t := text(action, variation)
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.add_child(t)
	return b


static func bar(fraction: float = 0.0, tone: String = "signal", height: float = 6.0) -> ProgressBar:
	var p := ProgressBar.new()
	p.min_value = 0.0
	p.max_value = 1.0
	p.step = 0.0
	p.value = clampf(fraction, 0.0, 1.0)
	p.show_percentage = false
	p.custom_minimum_size = Vector2(0.0, height)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	set_bar_tone(p, tone)
	return p


static func set_bar_tone(p: ProgressBar, tone: String) -> void:
	p.add_theme_stylebox_override("fill",
		UiThemeBuilder.box(P.tone(tone), Color(0, 0, 0, 0), 0, 0.0, 0.0))


static func rule(dashed: bool = false) -> Control:
	if dashed:
		return UiQuayRule.new()
	var s := HSeparator.new()
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return s


static func hazard(height: float = 6.0) -> UiHazardStrip:
	var h := UiHazardStrip.new()
	h.custom_minimum_size = Vector2(0.0, height)
	h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.stripe_width = maxf(height * 1.2, 6.0)
	return h


## Coloured square chip, e.g. company livery or a commodity colour.
static func swatch(color: Color, side: float = 14.0) -> ColorRect:
	var c := ColorRect.new()
	c.color = color
	c.custom_minimum_size = Vector2(side, side)
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func empty_state(title_text: String, body: String = "") -> PanelContainer:
	var c := inset()
	var b := vbox(4)
	b.alignment = BoxContainer.ALIGNMENT_CENTER
	var t := text(title_text, "Lead", "muted")
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.add_child(t)
	if body != "":
		var p := paragraph(body, "Caption")
		p.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.add_child(p)
	c.add_child(b)
	return c


# ── Actions ──────────────────────────────────────────────────────────────────

## kinds: "secondary" (default), "primary", "ghost", "danger", "row", "tab", "chip"
static func button(label_text: String, kind: String = "secondary",
		on_pressed: Callable = Callable()) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	match kind:
		"primary":
			b.theme_type_variation = "PrimaryButton"
			b.text = label_text.to_upper()
			b.custom_minimum_size = Vector2(0.0, 44.0)
		"ghost":
			b.theme_type_variation = "GhostButton"
			b.text = label_text
		"danger":
			b.theme_type_variation = "DangerButton"
			b.text = label_text
		"row":
			b.theme_type_variation = "RowButton"
			b.text = label_text.to_upper()
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		"tab":
			b.theme_type_variation = "TabButton"
			b.text = label_text.to_upper()
			b.toggle_mode = true
		"chip":
			b.theme_type_variation = "ChipButton"
			b.text = label_text
			b.toggle_mode = true
		_:
			b.text = label_text
			b.custom_minimum_size = Vector2(0.0, 36.0)
	if on_pressed.is_valid():
		b.pressed.connect(on_pressed)
	return b


## Row of toggle tabs sharing one ButtonGroup. Calls on_select(index).
static func tabs(names: Array, on_select: Callable = Callable(), kind: String = "tab") -> HBoxContainer:
	var strip := hbox(0 if kind == "tab" else P.GAP_XS)
	var group := ButtonGroup.new()
	for i in names.size():
		var b := button(String(names[i]), kind)
		b.button_group = group
		if on_select.is_valid():
			b.pressed.connect(on_select.bind(i))
		strip.add_child(b)
	if strip.get_child_count() > 0:
		(strip.get_child(0) as Button).button_pressed = true
	strip.set_meta("group", group)
	return strip


static func select_tab(strip: Control, index: int) -> void:
	if strip == null or index < 0 or index >= strip.get_child_count():
		return
	var b := strip.get_child(index) as Button
	if b != null:
		b.set_pressed_no_signal(true)


static func line_edit(placeholder: String = "", value: String = "") -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.text = value
	e.custom_minimum_size = Vector2(0.0, 36.0)
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return e


static func option(items: Array, selected: int = 0) -> OptionButton:
	var o := OptionButton.new()
	for item in items:
		o.add_item(String(item))
	if selected >= 0 and selected < items.size():
		o.select(selected)
	o.custom_minimum_size = Vector2(0.0, 36.0)
	return o


static func slider(min_v: float, max_v: float, value: float, step: float = 0.01) -> HSlider:
	var s := HSlider.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = step
	s.value = value
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.custom_minimum_size = Vector2(160.0, 20.0)
	return s


static func toggle(label_text: String, on: bool = false) -> CheckButton:
	var c := CheckButton.new()
	c.text = label_text
	c.button_pressed = on
	return c


# ── Helpers ──────────────────────────────────────────────────────────────────

static func money(amount: int) -> String:
	return PlayerData.format_money(amount)


static func clear(node: Node) -> void:
	if node == null:
		return
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()


static func full_rect(c: Control) -> Control:
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return c


static func centered(child: Control) -> CenterContainer:
	var c := CenterContainer.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(child)
	return c
