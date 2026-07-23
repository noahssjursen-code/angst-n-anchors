class_name CharacterCustomizationShowcase
extends Node3D

const CHARACTER_CATALOG := preload("res://scripts/character/character_catalog.gd")
const CHARACTER_VISUAL := preload("res://scripts/character/character_visual.gd")
const COMPLEXIONS := [
	Color("e0b997"), Color("d4a37f"), Color("b98262"),
	Color("9e684c"), Color("7c513d"), Color("5d3c2e"),
]

var appearance := CharacterAppearance.default_appearance()
var visual: CharacterVisual
var pivot: Node3D
var json_edit: TextEdit
var status_label: Label
var outfit_selector: OptionButton
var selectors: Dictionary = {}
var preset_ids := PackedStringArray()
var spinning := false
var spin_toggle: CheckButton
var decorated := true
var dragging := false
var last_mouse_x := 0.0
var active_preset_index := 0


func _ready() -> void:
	var game_menu := get_node_or_null("/root/GameMenu")
	if game_menu != null and game_menu.has_method("set_gameplay_hud_visible"):
		game_menu.set_gameplay_hud_visible(false)
	_apply_outfit_preset("harbour_captain")
	_build_stage()
	_build_interface()
	_apply()
	_sync_controls()
	(get_node("Camera3D") as Camera3D).look_at(Vector3(0.0, 1.02, 0.0), Vector3.UP)
	var capture_outfit := _capture_outfit_arg()
	if not capture_outfit.is_empty() or "--capture-character-showcase" in OS.get_cmdline_user_args():
		call_deferred("_capture_review_frame", capture_outfit)


func _process(delta: float) -> void:
	if spinning and not dragging:
		pivot.rotation.y += delta * 0.12


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		dragging = event.pressed and event.position.x < get_viewport().get_visible_rect().size.x - 460.0
		last_mouse_x = event.position.x
	elif event is InputEventMouseMotion and dragging:
		pivot.rotation.y += (event.position.x - last_mouse_x) * 0.012
		last_mouse_x = event.position.x


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit:
		return
	match event.keycode:
		KEY_R:
			_randomize()
		KEY_F:
			_reset_view()
		KEY_Q, KEY_LEFT:
			_cycle_outfit(-1)
		KEY_E, KEY_RIGHT:
			_cycle_outfit(1)


func _build_stage() -> void:
	pivot = Node3D.new()
	pivot.name = "CharacterTurntable"
	pivot.rotation.y = PI
	add_child(pivot)
	visual = CHARACTER_VISUAL.new()
	visual.name = "Character"
	pivot.add_child(visual)

	var platform := MeshInstance3D.new()
	platform.name = "Platform"
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 1.05
	cylinder.bottom_radius = 1.12
	cylinder.height = 0.12
	cylinder.radial_segments = 24
	platform.mesh = cylinder
	platform.position.y = -0.07
	platform.material_override = _material(Color("151c22"), 0.90)
	add_child(platform)

	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.98
	torus.outer_radius = 1.018
	torus.rings = 32
	torus.ring_segments = 4
	ring.mesh = torus
	ring.position.y = 0.005
	ring.material_override = _material(Color("c85a21"), 0.74)
	add_child(ring)

	var floor := MeshInstance3D.new()
	var floor_mesh := BoxMesh.new()
	floor_mesh.size = Vector3(4.8, 0.08, 3.6)
	floor.mesh = floor_mesh
	floor.position = Vector3(0, -0.17, -0.25)
	floor.material_override = _material(Color("0a1015"), 0.92)
	add_child(floor)

	var backdrop := MeshInstance3D.new()
	var backdrop_mesh := BoxMesh.new()
	backdrop_mesh.size = Vector3(4.8, 2.8, 0.08)
	backdrop.mesh = backdrop_mesh
	backdrop.position = Vector3(0, 1.15, -0.82)
	backdrop.material_override = _material(Color("101921"), 0.96)
	add_child(backdrop)


func _build_interface() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(root)

	var title := Label.new()
	title.text = "NORTH ATLANTIC WARDROBE"
	title.position = Vector2(42, 34)
	title.add_theme_font_size_override("font_size", 28)
	root.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "Block-built working clothes - shared by NPCs and players"
	subtitle.position = Vector2(44, 72)
	subtitle.modulate = Color("a0adb4")
	root.add_child(subtitle)
	var hint := Label.new()
	hint.text = "Drag to inspect  |  F front view  |  Q / E outfits  |  R random character"
	hint.position = Vector2(44, 104)
	hint.modulate = Color("d8682a")
	root.add_child(hint)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	panel.offset_left = -450
	panel.offset_top = 20
	panel.offset_right = -20
	panel.offset_bottom = -20
	panel.add_theme_stylebox_override("panel", _panel_style())
	root.add_child(panel)
	var scroll := ScrollContainer.new()
	panel.add_child(scroll)
	var content := VBoxContainer.new()
	content.custom_minimum_size.x = 390
	content.add_theme_constant_override("separation", 8)
	scroll.add_child(content)

	_add_heading(content, "OUTFIT PRESETS")
	outfit_selector = OptionButton.new()
	outfit_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for preset in CHARACTER_CATALOG.outfit_presets():
		outfit_selector.add_item(str(preset.get("label", preset.get("id", ""))))
		preset_ids.append(str(preset.get("id", "")))
	outfit_selector.item_selected.connect(_outfit_selected)
	content.add_child(outfit_selector)
	var preset_actions := HBoxContainer.new()
	content.add_child(preset_actions)
	_add_button(preset_actions, "PREVIOUS", func(): _cycle_outfit(-1))
	_add_button(preset_actions, "RANDOM", _randomize)
	_add_button(preset_actions, "NEXT", func(): _cycle_outfit(1))

	var dressed_toggle := CheckButton.new()
	dressed_toggle.text = "Show wardrobe"
	dressed_toggle.button_pressed = true
	dressed_toggle.toggled.connect(_decorated_toggled)
	content.add_child(dressed_toggle)

	_add_heading(content, "BODY & FACE")
	_add_selector(content, "Body", &"body_presets", "body_id")
	_add_selector(content, "Hair", &"hair", "hair_id")
	_add_selector(content, "Facial hair", &"facial_hair", "facial_hair_id")
	_add_selector(content, "Face detail", &"face_surfaces", "face_texture_profile_id")
	_add_color(content, "Complexion", "skin_color")
	_add_color(content, "Hair colour", "hair_color")

	_add_heading(content, "CLOTHING")
	_add_selector(content, "Top", &"tops", "top_id")
	_add_selector(content, "Outerwear", &"outerwear", "outerwear_id")
	_add_selector(content, "Trousers", &"trousers", "trousers_id")
	_add_selector(content, "Footwear", &"footwear", "footwear_id")
	_add_selector(content, "Headwear", &"headwear", "headwear_id")
	_add_color(content, "Top colour", "top_color")
	_add_color(content, "Outer colour", "clothing_color")
	_add_color(content, "Trouser colour", "trousers_color")
	_add_color(content, "Footwear colour", "footwear_color")
	_add_color(content, "Headwear colour", "headwear_color")
	_add_color(content, "Trim / badge", "accent_color")

	_add_heading(content, "ACCESSORIES")
	_add_selector(content, "Eyewear", &"eyewear", "eyewear_id")
	_add_selector(content, "Mouth", &"face_accessories", "face_accessory_id")
	_add_selector(content, "Neckwear", &"neckwear", "neckwear_id")
	_add_selector(content, "Gloves", &"handwear", "handwear_id")
	_add_selector(content, "Work gear", &"utility_accessories", "utility_id")
	_add_color(content, "Accessory colour", "accessory_color")

	_add_heading(content, "COMPANY UNIFORM")
	_add_selector(content, "Uniform role", &"uniform_templates", "uniform_id")
	_add_color(content, "Company primary", "company_primary_color")
	_add_color(content, "Company secondary", "company_secondary_color")

	_add_heading(content, "CHARACTER RECORD")
	json_edit = TextEdit.new()
	json_edit.custom_minimum_size = Vector2(370, 220)
	json_edit.wrap_mode = TextEdit.LINE_WRAPPING_NONE
	json_edit.add_theme_font_size_override("font_size", 12)
	content.add_child(json_edit)
	var actions := HBoxContainer.new()
	content.add_child(actions)
	_add_button(actions, "APPLY JSON", _apply_json)
	_add_button(actions, "COPY JSON", _copy_json)
	_add_button(actions, "SAVE PRESET", _save_json)
	var view_actions := HBoxContainer.new()
	view_actions.add_theme_constant_override("separation", 10)
	content.add_child(view_actions)
	_add_button(view_actions, "FRONT VIEW", _reset_view)
	spin_toggle = CheckButton.new()
	spin_toggle.text = "Auto rotate"
	spin_toggle.button_pressed = false
	spin_toggle.toggled.connect(func(value: bool): spinning = value)
	view_actions.add_child(spin_toggle)
	status_label = Label.new()
	status_label.modulate = Color("84c7a4")
	content.add_child(status_label)


func _add_heading(parent: VBoxContainer, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", Color("d8682a"))
	label.add_theme_font_size_override("font_size", 15)
	parent.add_child(label)


func _add_selector(parent: VBoxContainer, label_text: String, slot: StringName, property: String) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 122
	row.add_child(label)
	var selector := OptionButton.new()
	selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(selector)
	var ids := PackedStringArray()
	for option in CHARACTER_CATALOG.options(slot):
		selector.add_item(str(option.get("label", option.get("id", ""))))
		ids.append(str(option.get("id", "")))
	selector.item_selected.connect(_selector_changed.bind(slot, property, ids))
	selectors[property] = {"control": selector, "ids": ids}


func _add_color(parent: VBoxContainer, label_text: String, property: String) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 122
	row.add_child(label)
	var picker := ColorPickerButton.new()
	picker.custom_minimum_size = Vector2(0, 30)
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.color = appearance.get(property)
	picker.color_changed.connect(_color_changed.bind(property))
	row.add_child(picker)
	selectors[property] = {"control": picker}


func _add_button(parent: Container, text: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(callback)
	parent.add_child(button)


func _outfit_selected(index: int) -> void:
	if index < 0 or index >= preset_ids.size():
		return
	active_preset_index = index
	_apply_outfit_preset(preset_ids[index])
	_apply()
	_sync_controls()
	_status("Loaded %s" % outfit_selector.get_item_text(index))


func _selector_changed(index: int, slot: StringName, property: String, ids: PackedStringArray) -> void:
	if index < 0 or index >= ids.size():
		return
	var item_id := ids[index]
	appearance.set(property, item_id)
	_apply_item_default_color(slot, item_id)
	_apply()
	_sync_color_controls()
	_status("Custom wardrobe edit")


func _color_changed(color: Color, property: String) -> void:
	appearance.set(property, color)
	_apply()


func _apply_outfit_preset(id: String) -> void:
	var preset := CHARACTER_CATALOG.outfit_preset(id)
	if preset.is_empty():
		return
	for property in [
		"body_id", "face_texture_profile_id", "top_id", "outerwear_id", "trousers_id", "footwear_id", "headwear_id",
		"facial_hair_id", "hair_id",
	]:
		if preset.has(property):
			appearance.set(property, str(preset[property]))
	for property in [
		"eyewear_id", "face_accessory_id", "neckwear_id", "handwear_id", "utility_id", "uniform_id",
	]:
		appearance.set(property, str(preset.get(property, "none")))
	for property in [
		"top_color", "clothing_color", "trousers_color", "footwear_color",
		"skin_color", "hair_color", "headwear_color", "accent_color", "accessory_color",
		"company_primary_color", "company_secondary_color",
	]:
		if preset.has(property):
			appearance.set(property, Color.from_string(str(preset[property]), appearance.get(property)))
	active_preset_index = maxi(0, preset_ids.find(id)) if not preset_ids.is_empty() else 0


func _apply_item_default_color(slot: StringName, id: String) -> void:
	var option := CHARACTER_CATALOG.option(slot, id)
	if not option.has("default_color"):
		return
	var property := ""
	match slot:
		&"tops": property = "top_color"
		&"outerwear": property = "clothing_color"
		&"trousers": property = "trousers_color"
		&"footwear": property = "footwear_color"
		&"headwear": property = "headwear_color"
		&"eyewear", &"face_accessories", &"neckwear", &"handwear", &"utility_accessories":
			property = "accessory_color"
	if not property.is_empty():
		appearance.set(property, Color.from_string(str(option.default_color), appearance.get(property)))


func _cycle_outfit(direction: int) -> void:
	if preset_ids.is_empty():
		return
	active_preset_index = wrapi(active_preset_index + direction, 0, preset_ids.size())
	_apply_outfit_preset(preset_ids[active_preset_index])
	_apply()
	_sync_controls()
	_status("Loaded %s" % preset_ids[active_preset_index])


func _randomize() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	if not preset_ids.is_empty():
		active_preset_index = rng.randi_range(0, preset_ids.size() - 1)
		_apply_outfit_preset(preset_ids[active_preset_index])
	var bodies := CHARACTER_CATALOG.ids(&"body_presets")
	appearance.body_id = bodies[rng.randi_range(0, bodies.size() - 1)]
	appearance.skin_color = COMPLEXIONS[rng.randi_range(0, COMPLEXIONS.size() - 1)]
	_apply()
	_sync_controls()
	_status("Randomized %s" % preset_ids[active_preset_index])


func _reset_view() -> void:
	spinning = false
	if spin_toggle != null:
		spin_toggle.set_pressed_no_signal(false)
	if pivot != null:
		pivot.rotation.y = PI
	_status("Front view")


func _apply_json() -> void:
	var parsed := CharacterAppearance.from_json_string(json_edit.text)
	if parsed == null:
		_status("Invalid appearance JSON", true)
		return
	appearance = parsed
	_apply()
	_sync_controls()
	_status("JSON applied")


func _copy_json() -> void:
	DisplayServer.clipboard_set(appearance.to_json_string())
	_status("Appearance JSON copied")


func _save_json() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://character_presets"))
	var file := FileAccess.open("user://character_presets/showcase_character.json", FileAccess.WRITE)
	if file == null:
		_status("Could not save preset", true)
		return
	file.store_string(appearance.to_json_string())
	_status("Saved to user://character_presets/showcase_character.json")


func _apply() -> void:
	visual.set_decorated(decorated)
	visual.apply_appearance(appearance)
	if json_edit != null:
		json_edit.text = appearance.to_json_string()


func _sync_controls() -> void:
	if outfit_selector != null and not preset_ids.is_empty():
		outfit_selector.select(clampi(active_preset_index, 0, preset_ids.size() - 1))
	for property in selectors:
		var entry: Dictionary = selectors[property]
		var control: Control = entry.control
		if control is OptionButton:
			var ids: PackedStringArray = entry.ids
			(control as OptionButton).select(ids.find(str(appearance.get(property))))
		elif control is ColorPickerButton:
			(control as ColorPickerButton).color = appearance.get(property)


func _sync_color_controls() -> void:
	for property in selectors:
		var control: Control = selectors[property].control
		if control is ColorPickerButton:
			(control as ColorPickerButton).color = appearance.get(property)


func _status(text: String, error := false) -> void:
	if status_label == null:
		return
	status_label.text = text
	status_label.modulate = Color("f05a47") if error else Color("84c7a4")


func _decorated_toggled(value: bool) -> void:
	decorated = value
	_apply()
	_status("Wardrobe visible" if value else "Approved base body")


func _material(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	return material


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.035, 0.043, 0.97)
	style.border_color = Color("34444d")
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	return style


func _capture_outfit_arg() -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-outfit="):
			return argument.trim_prefix("--capture-outfit=")
	return ""


func _capture_review_frame(outfit_id: String = "") -> void:
	spinning = false
	if not outfit_id.is_empty():
		_apply_outfit_preset(outfit_id)
		_apply()
		_sync_controls()
	pivot.rotation.y = PI + 0.10
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var suffix := outfit_id if not outfit_id.is_empty() else "review"
	var path := "user://character_showcase_%s.png" % suffix
	var error := image.save_png(path)
	print("CHARACTER_REVIEW_CAPTURE=%s ERROR=%d" % [ProjectSettings.globalize_path(path), error])
	get_tree().quit(0 if error == OK else 1)
