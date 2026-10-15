class_name CharacterAppearanceControls
extends VBoxContainer

signal appearance_changed(appearance: CharacterAppearance)
signal motion_changed(motion: StringName)
signal playback_speed_changed(speed: float)
var appearance := CharacterAppearance.default_appearance()
var _updating := false

func _ready() -> void:
	add_theme_constant_override("separation", 10)
	refresh()

func refresh() -> void:
	_updating = true
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_heading("BODY & FACE")
	# Shape and wardrobe choices return only when authored on the new base.
	# Existing saved values remain in CharacterAppearance for compatibility.
	var swatches := HBoxContainer.new()
	add_child(swatches)
	for tone in [Color("f2cbb0"), Color("d3a17c"), Color("ad7651"), Color("825035"), Color("573524"), Color("34231d")]:
		var button := Button.new()
		button.text = "●"
		button.add_theme_color_override("font_color", tone)
		button.add_theme_font_size_override("font_size", 28)
		button.tooltip_text = "Skin tone"
		button.pressed.connect(func() -> void:
			appearance.skin_color = tone
			appearance_changed.emit(appearance)
			refresh())
		swatches.add_child(button)
	_color("Skin colour", "skin_color")
	_heading("RIG PREVIEW")
	var motions := OptionButton.new()
	for title in ["Idle", "Walk", "Run", "Seated"]: motions.add_item(title)
	var clips := [&"idle", &"walk", &"run", &"seated"]
	motions.item_selected.connect(func(index: int) -> void: motion_changed.emit(clips[index]))
	add_child(motions)
	var speed := HSlider.new()
	speed.min_value = 0.0
	speed.max_value = 1.5
	speed.step = .05
	speed.value = 1.0
	var speed_label := Label.new()
	speed_label.text = "Playback 1.00× · 0 pauses"
	add_child(speed_label)
	speed.value_changed.connect(func(value: float) -> void:
		speed_label.text = "Playback %.2f× · 0 pauses" % value
		playback_speed_changed.emit(value))
	add_child(speed)
	_updating = false

func set_appearance(value: CharacterAppearance) -> void:
	appearance = value.duplicate()
	if is_node_ready(): refresh()

func _heading(text: String) -> void:
	add_child(Ui.eyebrow(text))

func _row(title: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = title
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	add_child(row)
	return row

func _slider(title: String, property: String, low: float, high: float, step: float) -> void:
	var row := _row(title)
	var value := Label.new()
	value.text = str(int(appearance.get(property))) if property == "age" else "%d%%" % (float(appearance.get(property)) * 100)
	row.add_child(value)
	var slider := HSlider.new()
	slider.min_value = low
	slider.max_value = high
	slider.step = step
	slider.value = appearance.get(property)
	slider.value_changed.connect(func(v: float) -> void:
		appearance.set(property, v)
		value.text = str(int(v)) if property == "age" else "%d%%" % (v * 100)
		if not _updating: appearance_changed.emit(appearance))
	add_child(slider)

func _choice(title: String, property: String, ids: Array, labels: Array) -> void:
	var select := OptionButton.new()
	for label in labels: select.add_item(label)
	select.selected = maxi(0, ids.find(appearance.get(property)))
	select.item_selected.connect(func(index: int) -> void:
		appearance.set(property, ids[index])
		if not _updating: appearance_changed.emit(appearance))
	_row(title).add_child(select)

func _color(title: String, property: String) -> void:
	var picker := ColorPickerButton.new()
	picker.custom_minimum_size = Vector2(75, 24)
	picker.edit_alpha = false
	picker.color = appearance.get(property)
	picker.color_changed.connect(func(color: Color) -> void:
		appearance.set(property, color)
		if not _updating: appearance_changed.emit(appearance))
	_row(title).add_child(picker)
