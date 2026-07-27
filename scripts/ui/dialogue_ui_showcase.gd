extends Control

## F6 visual check for the full conversation composition.
## Keys 1–3 exercise the real numbered options; R restores the sample.

var _dialogue: DialoguePanel


func _ready() -> void:
	theme = BrandTheme.shared()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_world_plate()
	_dialogue = DialoguePanel.new("HARBOUR MASTER", Vector2(720, 560))
	add_child(_dialogue)
	_populate()
	_dialogue.show_panel()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R:
		_populate()
		_dialogue.show_panel()


func _build_world_plate() -> void:
	var sky := ColorRect.new()
	sky.color = BrandTokens.CLOUD_DARK
	sky.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(sky)

	var water := ColorRect.new()
	water.color = BrandTokens.WATER_MID
	water.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	water.anchor_top = 0.42
	add_child(water)

	var quay := ColorRect.new()
	quay.color = BrandTokens.QUAY
	quay.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	quay.offset_top = -310
	add_child(quay)

	var waterline := ColorRect.new()
	waterline.color = BrandTokens.BRASS
	waterline.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	waterline.offset_top = -315
	waterline.offset_bottom = -310
	add_child(waterline)

	var note := BrandLabel.new(
		"DIALOGUE COMPOSITION / R RESET / 1–3 CHOOSE",
		BrandLabel.Role.INVERSE_DATA
	)
	note.position = Vector2(BrandTokens.SPACE_XL, BrandTokens.SPACE_XL)
	add_child(note)


func _populate() -> void:
	_dialogue.clear()
	_dialogue.add_quote(
		"Good day, Captain. Berth two is clear until the ferry turns up. "
		+ "It usually turns up."
	)
	_dialogue.add_label("PORT AUTHORITY / ØSTERVIK / 14:42", BrandTokens.LABEL_MONO)
	_dialogue.add_option("Request berth two", func() -> void:
		_show_result("Berth two is yours for forty minutes. Make the lines fast.")
	)
	_dialogue.add_option("Ask about local cargo", func() -> void:
		_show_result("The cold store wants herring. The chandlery wants machine parts.")
	)
	_dialogue.add_disabled_option("Review company standing / REQUIRES REPUTATION 2")


func _show_result(message: String) -> void:
	_dialogue.clear()
	_dialogue.add_quote(message)
	_dialogue.add_back_button(func() -> void: _populate(), "← RETURN")
