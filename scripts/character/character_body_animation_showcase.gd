class_name CharacterBodyAnimationShowcase
extends Node3D

## F6 review gate for the neutral character body and complete motion set.
## No wardrobe catalog is read by this scene.

const MOTIONS: Array[StringName] = [
	WalkAnimator.IDLE,
	WalkAnimator.WALK,
	WalkAnimator.RUN,
	WalkAnimator.TURN_LEFT,
	WalkAnimator.TURN_RIGHT,
	WalkAnimator.CROUCH,
	WalkAnimator.JUMP,
	WalkAnimator.WORK,
	WalkAnimator.WAVE,
]
const CAPTURE_PHASES := {
	WalkAnimator.IDLE: 0.0,
	WalkAnimator.WALK: PI * 0.5,
	WalkAnimator.RUN: PI * 0.5,
	WalkAnimator.TURN_LEFT: 0.0,
	WalkAnimator.TURN_RIGHT: 0.0,
	WalkAnimator.CROUCH: 0.0,
	WalkAnimator.JUMP: PI * 0.5,
	WalkAnimator.WORK: 0.0,
	WalkAnimator.WAVE: 0.0,
}

var actor: NpcBase
var pivot: Node3D
var motion_label: Label
var paused_label: Label
var motion_index := 0
var paused := false


func _ready() -> void:
	_build_body()
	_build_interface()
	_select_motion(0)
	(get_node("Camera3D") as Camera3D).look_at(Vector3(0.0, 0.91, 0.0), Vector3.UP)
	if "--capture-character-body" in OS.get_cmdline_user_args():
		call_deferred("_capture_review_set")


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_LEFT, KEY_Q:
			_select_motion(motion_index - 1)
		KEY_RIGHT, KEY_E:
			_select_motion(motion_index + 1)
		KEY_SPACE:
			paused = not paused
			paused_label.text = "PAUSED — pose inspection" if paused else "PLAYING"
			if paused:
				actor.animator.set_preview_pose(MOTIONS[motion_index], float(CAPTURE_PHASES[MOTIONS[motion_index]]))
			else:
				actor.animator.set_preview_motion(MOTIONS[motion_index])
		KEY_F:
			pivot.rotation.y = PI
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9:
			_select_motion(int(event.keycode - KEY_1))


func _build_body() -> void:
	pivot = Node3D.new()
	pivot.name = "BodyPivot"
	pivot.rotation.y = PI
	add_child(pivot)
	actor = NpcBase.new()
	actor.name = "NeutralCharacterBody"
	actor.wardrobe_enabled = false
	actor.skin_color = Color("b98260")
	actor.clothing_color = Color("344653")
	actor.trousers_color = Color("344653")
	if "--review-face-surface" in OS.get_cmdline_user_args():
		var appearance := CharacterAppearance.default_appearance()
		appearance.skin_color = actor.skin_color
		appearance.face_texture_profile_id = "face_surface_base"
		actor.apply_appearance(appearance)
	pivot.add_child(actor)


func _build_interface() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 34)
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_right", 34)
	margin.add_theme_constant_override("margin_bottom", 26)
	layer.add_child(margin)
	var rows := VBoxContainer.new()
	rows.alignment = BoxContainer.ALIGNMENT_BEGIN
	rows.add_theme_constant_override("separation", 7)
	margin.add_child(rows)
	var title := Label.new()
	title.text = "CHARACTER BODY / MOTION REVIEW"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color("e7ecee"))
	rows.add_child(title)
	var scope := Label.new()
	scope.text = "Neutral articulated body — wardrobe disabled"
	scope.add_theme_color_override("font_color", Color("9ba8ae"))
	rows.add_child(scope)
	motion_label = Label.new()
	motion_label.add_theme_font_size_override("font_size", 19)
	motion_label.add_theme_color_override("font_color", Color("df6d2f"))
	rows.add_child(motion_label)
	paused_label = Label.new()
	paused_label.text = "PLAYING"
	paused_label.add_theme_color_override("font_color", Color("81bda0"))
	rows.add_child(paused_label)
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 8
	rows.add_child(spacer)
	var hint := Label.new()
	hint.text = "Q / E or arrows: motion    1–9: direct select    Space: freeze pose    F: front view"
	hint.add_theme_color_override("font_color", Color("aab5ba"))
	rows.add_child(hint)


func _select_motion(index: int) -> void:
	motion_index = wrapi(index, 0, MOTIONS.size())
	var motion := MOTIONS[motion_index]
	motion_label.text = "%02d / %02d    %s" % [motion_index + 1, MOTIONS.size(), String(motion).to_upper().replace("_", " ")]
	if paused:
		actor.animator.set_preview_pose(motion, float(CAPTURE_PHASES[motion]))
	else:
		actor.animator.set_preview_motion(motion)


func _capture_review_set() -> void:
	paused = true
	paused_label.text = "CAPTURE POSE"
	var review_folder := "character_face_surface_review" if "--review-face-surface" in OS.get_cmdline_user_args() else "character_body_review"
	var output_dir := ProjectSettings.globalize_path("user://%s" % review_folder)
	DirAccess.make_dir_recursive_absolute(output_dir)
	var views := {
		"front": PI,
		"three_quarter": PI - 0.52,
		"side": PI - PI * 0.5,
	}
	var contact_cells: Array[Image] = []
	for index in range(MOTIONS.size()):
		motion_index = index
		var motion := MOTIONS[index]
		motion_label.text = "%02d / %02d    %s" % [index + 1, MOTIONS.size(), String(motion).to_upper().replace("_", " ")]
		actor.animator.set_preview_pose(motion, float(CAPTURE_PHASES[motion]), 0.72)
		for view_name in views:
			pivot.rotation.y = float(views[view_name])
			for _frame in range(3):
				await get_tree().process_frame
			var image := get_viewport().get_texture().get_image()
			var path := output_dir.path_join("%02d_%s_%s.png" % [index + 1, String(motion), view_name])
			var error := image.save_png(path)
			print("CHARACTER_BODY_CAPTURE=%s ERROR=%d" % [path, error])
			if view_name == "three_quarter":
				var cell := image.duplicate()
				cell.convert(Image.FORMAT_RGBA8)
				cell.resize(480, 450, Image.INTERPOLATE_LANCZOS)
				contact_cells.append(cell)
	_save_contact_sheet(contact_cells, output_dir.path_join("character_body_motion_contact.png"))
	get_tree().quit()


func _save_contact_sheet(cells: Array[Image], path: String) -> void:
	var columns := 3
	var rows := ceili(float(cells.size()) / float(columns))
	var sheet := Image.create(480 * columns, 450 * rows, false, Image.FORMAT_RGBA8)
	sheet.fill(Color("20282d"))
	for index in range(cells.size()):
		var target := Vector2i((index % columns) * 480, (index / columns) * 450)
		sheet.blit_rect(cells[index], Rect2i(Vector2i.ZERO, cells[index].get_size()), target)
	var error := sheet.save_png(path)
	print("CHARACTER_BODY_CONTACT=%s ERROR=%d" % [path, error])
