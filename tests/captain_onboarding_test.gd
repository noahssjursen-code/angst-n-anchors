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
	for section in range(3):
		panel.select_editor_section(section)
		_check((panel.get("_tabs") as TabContainer).current_tab == section, "character editor section %d is selectable" % section)
	for preset_id in ["harbour_captain", "company_ship_officer", "warehouse_forklift", "office_dispatcher"]:
		panel.select_working_look(preset_id)
		var appearance := panel.get("_appearance") as CharacterAppearance
		var round_trip := CharacterAppearance.from_json_string(appearance.to_json_string()) if appearance != null else null
		_check(round_trip != null and round_trip.to_dict() == appearance.to_dict(), "%s produces a serializable captain" % preset_id)
	_check((panel.get("_selectors") as Dictionary).has("eyewear_id"), "glasses are available during captain creation")
	_check((panel.get("_selectors") as Dictionary).has("face_accessory_id"), "face accessories are available during captain creation")
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
	panel.queue_free()
	await get_tree().process_frame


func _covers_viewport(panel: Control) -> bool:
	var viewport_size := get_viewport().get_visible_rect().size
	var covered_size := panel.size * panel.scale
	return covered_size.distance_to(viewport_size) < 2.0


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
