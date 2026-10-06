extends Node

var failures := PackedStringArray()


func _ready() -> void:
	await _validate_character_page()
	await _validate_company_page()
	if failures.is_empty():
		print("Captain onboarding test: all checks passed")
		get_tree().quit()
		return
	for failure in failures:
		push_error("Captain onboarding test: " + failure)
	get_tree().quit(1)


func _validate_character_page() -> void:
	var panel := CharacterCreatorPanel.new()
	add_child(panel)
	await get_tree().process_frame
	panel.open_with_existing(null)
	await get_tree().process_frame
	_check(panel.visible, "character page opens")
	_check(_covers_viewport(panel), "character page covers the full screen")
	_check(not panel.find_children("*", "OptionButton", true, false).is_empty(), "Blender clothing options are selectable")
	var appearance := panel.get("_appearance") as CharacterAppearance
	_check(CharacterAppearance.from_json_string(appearance.to_json_string()).to_dict() == appearance.to_dict(), "appearance data still round-trips")
	_check((panel.get("_confirm") as Button).disabled, "empty captain name cannot continue")
	(panel.get("_name_field") as LineEdit).text = "Maren Vik"
	(panel.get("_name_field") as LineEdit).text_changed.emit("Maren Vik")
	_check(not (panel.get("_confirm") as Button).disabled, "named captain can continue without a model")
	panel.queue_free()
	await get_tree().process_frame


func _validate_company_page() -> void:
	var panel := CompanySetupPanel.new()
	add_child(panel)
	await get_tree().process_frame
	panel.open_for_captain("Maren Vik")
	await get_tree().process_frame
	_check(panel.visible, "company page opens")
	_check(_covers_viewport(panel), "company page covers the full screen")
	_check(str(panel.get("_selected_starter")) == "general_cargo", "general cargo is the default starter")
	var starter_buttons := panel.get("_starter_buttons") as Dictionary
	_check(starter_buttons.size() == CompanyContracts.starter_options().size(), "every starter vessel has a card")
	for starter_id in starter_buttons:
		var button := starter_buttons[starter_id] as Button
		var expected := str(starter_id) == "general_cargo"
		_check(button.button_pressed == expected, "%s selection state is correct" % starter_id)
	var name_field := panel.get("_name_field") as LineEdit
	_check(name_field.text == "Maren Vik Maritime", "company name is seeded from the captain")
	_check(not (panel.get("_confirm") as Button).disabled, "company page can continue with valid defaults")
	var args := OS.get_cmdline_user_args()
	var capture := args.find("--capture")
	if capture >= 0:
		for i in 8: await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(args[capture+1])
	panel.queue_free()
	await get_tree().process_frame


func _covers_viewport(panel: Control) -> bool:
	var viewport_size := get_viewport().get_visible_rect().size
	var covered_size := panel.size * panel.scale
	return covered_size.distance_to(viewport_size) < 2.0


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
