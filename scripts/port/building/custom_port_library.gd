extends PanelContainer
## Browse the same definitions used by placement and authority validation.
## Filtering never changes the equipped piece or the port document.
signal asset_selected(asset_id: String)
signal paint_requested(colour: Color)
signal build_requested

const CLADDING_COLOURS := [
	["Red", "a84b3f"], ["Ivory", "d6d2bc"], ["Charcoal", "38434a"],
	["Blue", "486d80"], ["Green", "536d58"], ["Ochre", "b68b43"]
]

var search: LineEdit
var category: OptionButton
var selected_name: Label
var selected_details: Label
var _catalog: Dictionary = {}
var _buttons: Dictionary = {}
var _headings: Dictionary = {}
var _groups: Dictionary = {}
var _empty: Label
var _selected := ""
var paint_button: Button
var paint_palette: GridContainer
var cladding_colour := Color("a84b3f")
var _paint_buttons: Array[Button] = []
var _controls: Label
var _build_name := ""
var _build_details := ""
var thumbnails: Dictionary = {}
var _grids: Dictionary = {}
var thumbnail_renderer: Node
const BUILD_CONTROLS := "LMB Place · RMB Remove · MMB Move\nR Rotate · Ctrl+Z Undo · Tab Mouse\nWASD Fly · Q/E Height · Shift Fast"
const THUMBNAILS = preload("res://scripts/port/building/custom_port_thumbnails.gd")


func configure(definitions: Dictionary, selected_id: String) -> void:
	_catalog = definitions.duplicate(true)
	theme_type_variation = "Sheet"
	custom_minimum_size = Vector2(356, 0)
	var column := Ui.vbox(7)
	add_child(column)
	column.add_child(Ui.eyebrow("BUILD LIBRARY"))
	column.add_child(Ui.caption("Deck · 2 m above sea level"))
	search = LineEdit.new()
	search.placeholder_text = "Search pieces…"
	search.clear_button_enabled = true
	search.custom_minimum_size.y = 36
	column.add_child(search)
	category = OptionButton.new()
	category.custom_minimum_size.y = 36
	category.add_item("All categories")
	column.add_child(category)
	var choices := Ui.vbox(6)
	var scroll := Ui.scroll(choices)
	column.add_child(scroll)
	for id in _catalog:
		var spec: Dictionary = _catalog[id]
		if not bool(spec.get("build_library_visible", true)): continue
		var group := str(spec.get("category", "Other"))
		if not _groups.has(group):
			_groups[group] = []
			category.add_item(group)
		_groups[group].append(str(id))
	for group in _groups:
		var heading := Ui.eyebrow(group)
		_headings[group] = heading
		choices.add_child(heading)
		var grid := GridContainer.new()
		grid.columns = 2
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_theme_constant_override("h_separation", 6)
		grid.add_theme_constant_override("v_separation", 6)
		choices.add_child(grid)
		_grids[group] = grid
		for id in _groups[group]:
			var spec: Dictionary = _catalog[id]
			var button := Ui.button("", "secondary", _choose.bind(id))
			button.custom_minimum_size = Vector2(150, 140)
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			button.toggle_mode = true
			button.tooltip_text = str(spec.get("name", id)) + "\n" + dimensions(spec)
			grid.add_child(button)
			var card := VBoxContainer.new()
			card.mouse_filter = Control.MOUSE_FILTER_IGNORE
			button.add_child(card)
			card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			card.offset_left = 5; card.offset_right = -5
			card.offset_top = 5; card.offset_bottom = -5
			card.add_theme_constant_override("separation", 2)
			var picture := TextureRect.new()
			picture.custom_minimum_size.y = 86
			picture.size_flags_vertical = Control.SIZE_EXPAND_FILL
			picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
			card.add_child(picture)
			thumbnails[id] = picture
			var title := Ui.caption(str(spec.get("name", id)))
			title.add_theme_font_size_override("font_size", 13)
			title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			title.mouse_filter = Control.MOUSE_FILTER_IGNORE
			card.add_child(title)
			var measurements := Ui.caption(dimensions(spec).trim_suffix(" footprint"))
			measurements.add_theme_font_size_override("font_size", 11)
			measurements.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			measurements.mouse_filter = Control.MOUSE_FILTER_IGNORE
			card.add_child(measurements)
			_buttons[id] = button
	_empty = Ui.caption("No matching pieces.")
	choices.add_child(_empty)
	column.add_child(HSeparator.new())
	selected_name = Ui.caption("")
	selected_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(selected_name)
	selected_details = Ui.caption("")
	selected_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(selected_details)
	paint_button = Ui.button("Paint cladding", "secondary", _toggle_paint)
	paint_button.toggle_mode = true
	paint_button.custom_minimum_size.y = 34
	column.add_child(paint_button)
	paint_palette = GridContainer.new()
	paint_palette.columns = 3
	paint_palette.add_theme_constant_override("h_separation", 4)
	paint_palette.add_theme_constant_override("v_separation", 4)
	column.add_child(paint_palette)
	for swatch in CLADDING_COLOURS:
		var colour := Color(str(swatch[1]))
		var button := Ui.button(str(swatch[0]), "secondary", _choose_paint.bind(colour))
		button.toggle_mode = true
		button.custom_minimum_size = Vector2(82, 32)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 13)
		button.add_theme_stylebox_override("normal", VoyageStyle.box(colour, 4))
		button.add_theme_stylebox_override("hover", VoyageStyle.box(colour.lightened(.12), 4))
		var pressed := VoyageStyle.box(colour, 4)
		pressed.border_color = Color("a1e2cc")
		pressed.set_border_width_all(2)
		button.add_theme_stylebox_override("pressed", pressed)
		var ink := Color("18252b") if colour.get_luminance() > .4 else Color("f2f1e9")
		for variation in ["font_color", "font_hover_color", "font_pressed_color"]:
			button.add_theme_color_override(variation, ink)
		button.tooltip_text = str(swatch[0]) + " painted timber · keeps grain and trim"
		paint_palette.add_child(button)
		_paint_buttons.append(button)
	paint_palette.hide()
	_controls = Ui.caption(BUILD_CONTROLS)
	_controls.add_theme_font_size_override("font_size", 12)
	column.add_child(_controls)
	search.text_changed.connect(func(_text: String): _filter())
	category.item_selected.connect(func(_index: int): _filter())
	search.text_submitted.connect(func(_text: String):
		var matches := visible_asset_ids()
		if matches.size() == 1: _choose(matches[0]))
	set_selected(selected_id)
	thumbnail_renderer = THUMBNAILS.new()
	add_child(thumbnail_renderer)
	thumbnail_renderer.configure(_catalog, thumbnails)
	_filter()


func set_selected(id: String) -> void:
	if not _catalog.has(id): return
	set_paint_active(false)
	_selected = id
	for key in _buttons: _buttons[key].set_pressed_no_signal(key == id)
	var spec: Dictionary = _catalog[id]
	selected_name.text = str(spec.get("name", id))
	selected_details.text = dimensions(spec)
	if str(spec.get("factory", "")) == "fish_landing_plant":
		selected_details.text += "\nHose reach %s m · empty refrigerated store included" % _metres(float(spec.get("reach_max_m", 0)))
	elif str(spec.get("kind", "")) == "crane":
		selected_details.text += "\nReach %s m · empty yard included" % _metres(float(spec.get("reach_max_m", 0)))
	elif str(spec.get("placement_kind", "")) == "edge" or str(spec.get("kind", "")) == "bollard":
		selected_details.text += "\nSnaps to the quay edge"
	elif str(spec.get("kind", "")) == "platform":
		selected_details.text += "\nTiles to its own size"
	_build_name = selected_name.text
	_build_details = selected_details.text


func set_paint_active(active: bool) -> void:
	if not is_instance_valid(paint_button): return
	paint_button.set_pressed_no_signal(active)
	paint_palette.visible = active
	paint_button.text = "Painting cladding · click to build" if active else "Paint cladding"
	selected_name.text = "Painted timber" if active else _build_name
	selected_details.text = "Existing walls, windows and doors.\nTrim and glass keep their finish." if active else _build_details
	if is_instance_valid(_controls):
		_controls.text = "Hold LMB · Paint a stroke\nRMB · Return to building\nCtrl+Z · Undo entire stroke\nWASD · Fly   Q / E · Height\nTab · Choose colour / aim" if active else BUILD_CONTROLS
	for index in _paint_buttons.size():
		_paint_buttons[index].set_pressed_no_signal(cladding_colour.to_html(false) == str(CLADDING_COLOURS[index][1]))


func _toggle_paint() -> void:
	set_paint_active(paint_button.button_pressed)
	if paint_button.button_pressed: paint_requested.emit(cladding_colour)
	else: build_requested.emit()


func _choose_paint(colour: Color) -> void:
	cladding_colour = colour
	set_paint_active(true)
	paint_requested.emit(colour)


func visible_asset_ids() -> Array[String]:
	var result: Array[String] = []
	for id in _buttons:
		if _buttons[id].visible: result.append(str(id))
	return result


func _choose(id: String) -> void:
	if not _buttons.has(id): return
	set_selected(id)
	search.release_focus()
	asset_selected.emit(id)


func _filter() -> void:
	var query := search.text.strip_edges().to_lower()
	var group_filter := category.get_item_text(category.selected) if category.selected > 0 else ""
	var count := 0
	for group in _groups:
		var any_visible := false
		for id in _groups[group]:
			var spec: Dictionary = _catalog[id]
			var haystack: String = (str(spec.get("name", id)) + " " + str(group) + " " + dimensions(spec)).to_lower()
			var matches: bool = group_filter.is_empty() or group_filter == str(group)
			for word in query.split(" ", false):
				matches = matches and haystack.contains(word)
			_buttons[id].visible = matches
			any_visible = any_visible or matches
			if matches: count += 1
		_headings[group].visible = any_visible
		_grids[group].visible = any_visible
	_empty.visible = count == 0
	if is_instance_valid(thumbnail_renderer): thumbnail_renderer.prioritize(visible_asset_ids())


static func dimensions(spec: Dictionary) -> String:
	var footprint: Array = spec.get("footprint_m", [0, 0])
	return "%s × %s m footprint" % [_metres(float(footprint[0])), _metres(float(footprint[1]))]


static func _metres(value: float) -> String:
	return ("%.2f" % value).trim_suffix("0").trim_suffix("0").trim_suffix(".")
