class_name CaptainOnboardingShowcase
extends Node

## F6 entry point for the exact captain page used by the title flow.

var creator: CharacterCreatorPanel
var company: CompanySetupPanel


func _ready() -> void:
	creator = CharacterCreatorPanel.new()
	creator.confirmed.connect(func(display_name: String, appearance: CharacterAppearance) -> void:
		print("captain_onboarding_showcase: %s / %s" % [display_name, appearance.eyewear_id])
		_show_company(display_name)
	)
	creator.cancelled.connect(func() -> void: creator.open_with_existing(null))
	add_child(creator)
	company = CompanySetupPanel.new()
	company.visible = false
	company.confirmed.connect(func(company_name: String, _brand: Color, vessel: String) -> void:
		print("captain_onboarding_showcase: %s / %s" % [company_name, vessel])
		_show_creator()
	)
	company.cancelled.connect(_show_creator)
	add_child(company)
	if "--capture-company-onboarding" in OS.get_cmdline_user_args():
		_show_company("Maren Vik")
	else:
		_show_creator()
		_apply_capture_options()
	if "--capture-captain-onboarding" in OS.get_cmdline_user_args():
		call_deferred("_capture_review_frame")
	elif "--capture-company-onboarding" in OS.get_cmdline_user_args():
		call_deferred("_capture_review_frame")


func _show_creator() -> void:
	if company != null:
		company.visible = false
	creator.visible = true
	creator.open_with_existing(null)


func _show_company(captain_name := "Maren Vik") -> void:
	creator.visible = false
	company.visible = true
	company.open_for_captain(captain_name)


func _apply_capture_options() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-onboarding-preset="):
			creator.select_working_look(argument.trim_prefix("--capture-onboarding-preset="))
		elif argument.begins_with("--capture-onboarding-tab="):
			creator.select_editor_section(int(argument.trim_prefix("--capture-onboarding-tab=")))


func _capture_review_frame() -> void:
	for frame in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	print("CAPTAIN_ONBOARDING_VIEWPORT=%s CREATOR=%s WINDOW=%s" % [
		str(get_viewport().get_visible_rect().size), str(creator.size), str(DisplayServer.window_get_size()),
	])
	var image := get_viewport().get_texture().get_image()
	var suffix := "company" if company.visible else "captain"
	var path := "user://%s_onboarding_review.png" % suffix
	var error := image.save_png(path)
	print("CAPTAIN_ONBOARDING_CAPTURE=%s ERROR=%d" % [ProjectSettings.globalize_path(path), error])
	get_tree().quit(0 if error == OK else 1)
