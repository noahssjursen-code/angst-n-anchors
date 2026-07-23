class_name CharacterWorkwearShowcase
extends Node3D

## F6 review gate for the first production wardrobe collection. Every outfit is
## rendered on the same articulated NpcBase used by gameplay and player avatars.

const MOTIONS: Array[StringName] = [
	WalkAnimator.IDLE,
	WalkAnimator.WALK,
	WalkAnimator.WORK,
	WalkAnimator.WAVE,
]
const CAPTURE_PHASES := {
	WalkAnimator.IDLE: 0.0,
	WalkAnimator.WALK: PI * 0.5,
	WalkAnimator.WORK: 0.0,
	WalkAnimator.WAVE: 0.0,
}

var actor: NpcBase
var pivot: Node3D
var outfit_ids := PackedStringArray()
var outfit_index := 0
var motion_index := 0
var outfit_label: Label
var motion_label: Label
var interface_layer: CanvasLayer


func _ready() -> void:
	for preset_raw in CharacterCatalog.outfit_presets():
		outfit_ids.append(str((preset_raw as Dictionary).get("id", "")))
	_build_actor()
	_build_interface()
	_apply_selection()
	(get_node("Camera3D") as Camera3D).look_at(Vector3(0.0, 0.92, 0.0), Vector3.UP)
	if "--capture-workwear-library" in OS.get_cmdline_user_args():
		call_deferred("_capture_library")


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_Q, KEY_LEFT:
			outfit_index = wrapi(outfit_index - 1, 0, outfit_ids.size())
			_apply_selection()
		KEY_E, KEY_RIGHT:
			outfit_index = wrapi(outfit_index + 1, 0, outfit_ids.size())
			_apply_selection()
		KEY_W, KEY_UP:
			motion_index = wrapi(motion_index + 1, 0, MOTIONS.size())
			_apply_motion()
		KEY_S, KEY_DOWN:
			motion_index = wrapi(motion_index - 1, 0, MOTIONS.size())
			_apply_motion()
		KEY_F:
			pivot.rotation.y = PI


func _build_actor() -> void:
	pivot = Node3D.new()
	pivot.name = "CharacterPivot"
	pivot.rotation.y = PI - 0.45
	add_child(pivot)
	actor = NpcBase.new()
	actor.name = "ProductionWardrobeCharacter"
	actor.wardrobe_enabled = true
	actor.appearance = CharacterCatalog.appearance_preset(outfit_ids[0])
	pivot.add_child(actor)


func _build_interface() -> void:
	interface_layer = CanvasLayer.new()
	add_child(interface_layer)
	var panel := ColorRect.new()
	panel.position = Vector2(34, 30)
	panel.size = Vector2(520, 156)
	panel.color = Color(0.025, 0.037, 0.045, 0.93)
	interface_layer.add_child(panel)
	var rows := VBoxContainer.new()
	rows.position = Vector2(20, 15)
	rows.size = Vector2(480, 126)
	rows.add_theme_constant_override("separation", 5)
	panel.add_child(rows)
	var title := Label.new()
	title.text = "NORTH ATLANTIC WORKWEAR / PRODUCTION REVIEW"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color("e8eceb"))
	rows.add_child(title)
	outfit_label = Label.new()
	outfit_label.add_theme_font_size_override("font_size", 18)
	outfit_label.add_theme_color_override("font_color", Color("df6d2f"))
	rows.add_child(outfit_label)
	motion_label = Label.new()
	motion_label.add_theme_color_override("font_color", Color("d7c99f"))
	rows.add_child(motion_label)
	var scope := Label.new()
	scope.text = "Q / E: outfit    W / S: motion    F: front view"
	scope.add_theme_color_override("font_color", Color("8e9da4"))
	rows.add_child(scope)


func _apply_selection() -> void:
	if outfit_ids.is_empty():
		return
	var preset_id := outfit_ids[outfit_index]
	actor.apply_appearance(CharacterCatalog.appearance_preset(preset_id))
	var preset := CharacterCatalog.outfit_preset(preset_id)
	if outfit_label != null:
		outfit_label.text = str(preset.get("label", preset_id)).to_upper()
	_apply_motion()


func _apply_motion() -> void:
	var motion := MOTIONS[motion_index]
	if actor.animator != null:
		actor.animator.set_preview_motion(motion)
	if motion_label != null:
		motion_label.text = "MOTION: " + String(motion).to_upper().replace("_", " ")


func _capture_library() -> void:
	var output_dir := ProjectSettings.globalize_path("user://character_workwear_review")
	DirAccess.make_dir_recursive_absolute(output_dir)
	interface_layer.visible = false
	var views := {
		"front": PI,
		"three_quarter": PI - 0.48,
	}
	var cells: Array[Image] = []
	var capture_ids := _requested_capture_ids()
	for capture_index in range(capture_ids.size()):
		var index := outfit_ids.find(capture_ids[capture_index])
		if index < 0:
			push_warning("Unknown workwear capture preset: %s" % capture_ids[capture_index])
			continue
		outfit_index = index
		var preset_id := outfit_ids[index]
		actor.apply_appearance(CharacterCatalog.appearance_preset(preset_id))
		var motion := MOTIONS[index % MOTIONS.size()]
		actor.animator.set_preview_pose(motion, float(CAPTURE_PHASES[motion]), 0.72)
		for view_name in views:
			pivot.rotation.y = float(views[view_name])
			for _frame in range(4):
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var image := get_viewport().get_texture().get_image()
			var path := output_dir.path_join("%02d_%s_%s.png" % [index + 1, preset_id, view_name])
			var error := image.save_png(path)
			print("WORKWEAR_CAPTURE=%s ERROR=%d" % [path, error])
			var cell := image.duplicate()
			cell.convert(Image.FORMAT_RGBA8)
			cell.resize(420, 500, Image.INTERPOLATE_LANCZOS)
			cells.append(cell)
	_save_contact_sheet(cells, output_dir.path_join("character_workwear_contact.png"))
	get_tree().quit()


func _requested_capture_ids() -> PackedStringArray:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-workwear-presets="):
			var requested := argument.trim_prefix("--capture-workwear-presets=").split(",", false)
			if not requested.is_empty():
				return requested
	return outfit_ids


func _save_contact_sheet(cells: Array[Image], path: String) -> void:
	var columns := 4
	var rows := ceili(float(cells.size()) / float(columns))
	var sheet := Image.create(420 * columns, 500 * rows, false, Image.FORMAT_RGBA8)
	sheet.fill(Color("1a2228"))
	for index in range(cells.size()):
		var target := Vector2i((index % columns) * 420, (index / columns) * 500)
		sheet.blit_rect(cells[index], Rect2i(Vector2i.ZERO, cells[index].get_size()), target)
	var error := sheet.save_png(path)
	print("WORKWEAR_CONTACT=%s ERROR=%d" % [path, error])
