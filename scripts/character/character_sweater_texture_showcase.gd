class_name CharacterSweaterTextureShowcase
extends Node3D

## Isolated proof for textured JSON clothing. Only one approved body and one
## garment are present; this is intentionally not a wardrobe browser.

const MOTIONS: Array[StringName] = [
	WalkAnimator.IDLE,
	WalkAnimator.WALK,
	WalkAnimator.WAVE,
]
const CAPTURE_PHASES := {
	WalkAnimator.IDLE: 0.0,
	WalkAnimator.WALK: PI * 0.5,
	WalkAnimator.WAVE: 0.0,
}
const PALETTES := [
	{"name": "ISLENDER REFERENCE", "primary_color": Color("e5e1d5"), "secondary_color": Color("191d20")},
	{"name": "NORTH SEA", "primary_color": Color("18364e"), "secondary_color": Color("e0dcc7")},
	{"name": "HARBOUR COMPANY", "primary_color": Color("b54c2c"), "secondary_color": Color("172a3a")},
	{"name": "FISH PLANT", "primary_color": Color("285a52"), "secondary_color": Color("ded3b6")},
]

const PRODUCTION_SWEATER := "res://resources/data/models/characters/wardrobe/tops/wool_sweater.json"

var actor: NpcBase
var pivot: Node3D
var garment: CharacterGarment
var motion_label: Label
var palette_label: Label
var motion_index := 0
var palette_index := 0


func _ready() -> void:
	_build_actor()
	_build_interface()
	_select_motion(0)
	(get_node("Camera3D") as Camera3D).look_at(Vector3(0.0, 0.91, 0.0), Vector3.UP)
	if "--capture-texture-variants" in OS.get_cmdline_user_args():
		call_deferred("_capture_variant_set")
	elif "--capture-sweater-proof" in OS.get_cmdline_user_args():
		call_deferred("_capture_review_set")


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.keycode in [KEY_LEFT, KEY_Q]:
		_select_motion(motion_index - 1)
	elif event.keycode in [KEY_RIGHT, KEY_E]:
		_select_motion(motion_index + 1)
	elif event.keycode == KEY_V:
		_select_palette(palette_index + 1)


func _build_actor() -> void:
	pivot = Node3D.new()
	pivot.name = "CharacterPivot"
	pivot.rotation.y = PI
	add_child(pivot)
	actor = NpcBase.new()
	actor.name = "SweaterProofCharacter"
	actor.wardrobe_enabled = false
	actor.skin_color = Color("b98260")
	pivot.add_child(actor)
	garment = CharacterGarment.new()
	garment.name = "IslenderProductionSweater"
	actor.add_child(garment)
	_apply_palette()


func _build_interface() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := ColorRect.new()
	panel.position = Vector2(28, 26)
	panel.size = Vector2(500, 150)
	panel.color = Color(0.035, 0.052, 0.064, 0.92)
	layer.add_child(panel)
	var rows := VBoxContainer.new()
	rows.position = Vector2(20, 15)
	rows.size = Vector2(460, 124)
	rows.add_theme_constant_override("separation", 5)
	panel.add_child(rows)
	var title := Label.new()
	title.text = "TEXTURED GARMENT PROOF / ICELANDER"
	title.add_theme_font_size_override("font_size", 21)
	title.add_theme_color_override("font_color", Color("e8eceb"))
	rows.add_child(title)
	var scope := Label.new()
	scope.text = "Generated knit texture · JSON UV mesh · fitted articulated sleeves"
	scope.add_theme_color_override("font_color", Color("aab7bc"))
	rows.add_child(scope)
	motion_label = Label.new()
	motion_label.add_theme_font_size_override("font_size", 17)
	motion_label.add_theme_color_override("font_color", Color("df6d2f"))
	rows.add_child(motion_label)
	palette_label = Label.new()
	palette_label.add_theme_color_override("font_color", Color("d7c99f"))
	rows.add_child(palette_label)
	var hint := Label.new()
	hint.text = "Q / E or arrows: motion    V: shared-material palette"
	hint.add_theme_color_override("font_color", Color("819198"))
	rows.add_child(hint)


func _select_motion(index: int) -> void:
	motion_index = wrapi(index, 0, MOTIONS.size())
	var motion := MOTIONS[motion_index]
	motion_label.text = String(motion).to_upper().replace("_", " ")
	actor.animator.set_preview_motion(motion)


func _select_palette(index: int) -> void:
	palette_index = wrapi(index, 0, PALETTES.size())
	_apply_palette()


func _apply_palette() -> void:
	var palette: Dictionary = PALETTES[palette_index]
	if palette_label != null:
		palette_label.text = "PALETTE: " + str(palette.name)
	if not garment.attach(actor.visual, PRODUCTION_SWEATER, palette):
		push_error("Sweater showcase: garment failed to attach")


func _capture_variant_set() -> void:
	var output_dir := ProjectSettings.globalize_path("user://character_sweater_review")
	DirAccess.make_dir_recursive_absolute(output_dir)
	var views := [PI, PI - 0.52]
	var contact_cells: Array[Image] = []
	actor.animator.set_preview_pose(WalkAnimator.IDLE, 0.0, 0.72)
	for index in range(PALETTES.size()):
		palette_index = index
		_apply_palette()
		for view_yaw in views:
			pivot.rotation.y = float(view_yaw)
			for _frame in range(3):
				await get_tree().process_frame
			var image := get_viewport().get_texture().get_image()
			var cell := image.duplicate()
			cell.convert(Image.FORMAT_RGBA8)
			cell.resize(420, 420, Image.INTERPOLATE_LANCZOS)
			contact_cells.append(cell)
	_save_contact_sheet(contact_cells, output_dir.path_join("textured_uniform_variants.png"))
	get_tree().quit()


func _capture_review_set() -> void:
	var output_dir := ProjectSettings.globalize_path("user://character_sweater_review")
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
		motion_label.text = String(motion).to_upper().replace("_", " ")
		actor.animator.set_preview_pose(motion, float(CAPTURE_PHASES[motion]), 0.72)
		for view_name in views:
			pivot.rotation.y = float(views[view_name])
			for _frame in range(3):
				await get_tree().process_frame
			var image := get_viewport().get_texture().get_image()
			var path := output_dir.path_join("%02d_%s_%s.png" % [index + 1, String(motion), view_name])
			var error := image.save_png(path)
			print("SWEATER_CAPTURE=%s ERROR=%d" % [path, error])
			var cell := image.duplicate()
			cell.convert(Image.FORMAT_RGBA8)
			cell.resize(420, 420, Image.INTERPOLATE_LANCZOS)
			contact_cells.append(cell)
	_save_contact_sheet(contact_cells, output_dir.path_join("icelander_sweater_contact.png"))
	get_tree().quit()


func _save_contact_sheet(cells: Array[Image], path: String) -> void:
	var columns := 3
	var rows := ceili(float(cells.size()) / float(columns))
	var sheet := Image.create(420 * columns, 420 * rows, false, Image.FORMAT_RGBA8)
	sheet.fill(Color("20282d"))
	for index in range(cells.size()):
		var target := Vector2i((index % columns) * 420, (index / columns) * 420)
		sheet.blit_rect(cells[index], Rect2i(Vector2i.ZERO, cells[index].get_size()), target)
	var error := sheet.save_png(path)
	print("SWEATER_CONTACT=%s ERROR=%d" % [path, error])
