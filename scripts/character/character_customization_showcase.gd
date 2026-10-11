class_name CharacterCustomizationShowcase
extends Node3D

var character: CharacterVisual
var controls: CharacterAppearanceControls
var _spin := false
var _status: Label
const DRAFT := "user://blender_character_studio.json"

func _ready() -> void:
	GameMenu.set_gameplay_hud_visible(false)
	character = CharacterVisual.new()
	character.rotation.y = PI - .22
	add_child(character)
	var camera := $Camera3D as Camera3D
	camera.position = Vector3(-.65, 1.2, 3.9)
	camera.look_at(Vector3(-.65,.98,0))
	camera.fov = 34
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(20,20)
	panel.custom_minimum_size = Vector2(340,0)
	panel.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	panel.offset_left = 20
	panel.offset_top = 20
	panel.offset_right = 360
	panel.offset_bottom = -20
	panel.theme = HudStyle.make_theme()
	layer.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 12)
	scroll.add_child(column)
	var title := Label.new()
	title.text = "CHARACTER STUDIO"
	title.add_theme_font_size_override("font_size", 24)
	column.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "Blender mariner • 1.80 m • shared rig"
	column.add_child(subtitle)
	controls = CharacterAppearanceControls.new()
	column.add_child(controls)
	controls.appearance_changed.connect(character.apply_appearance)
	controls.motion_changed.connect(character.play_motion)
	controls.playback_speed_changed.connect(func(speed: float) -> void: character.animation_player.speed_scale = speed)
	var spin := CheckButton.new()
	spin.text = "Turntable"
	spin.toggled.connect(func(value: bool) -> void: _spin = value)
	column.add_child(spin)
	var row := HBoxContainer.new()
	column.add_child(row)
	for label in ["Save look", "Load look", "Reset"]:
		var button := Button.new()
		button.text = label
		row.add_child(button)
		button.pressed.connect(_draft_action.bind(label))
	_status = Label.new()
	_status.text = "Drag on the character to turn • wheel to zoom"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_status)
	var args := OS.get_cmdline_user_args()
	if args.has("--capture"):
		await _capture(args)

func _process(delta: float) -> void:
	if _spin and character != null: character.rotation.y += delta * .45

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		character.rotation.y += event.relative.x * .01
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP: $Camera3D.fov = maxf(18, $Camera3D.fov-2)
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN: $Camera3D.fov = minf(50, $Camera3D.fov+2)

func _draft_action(action: String) -> void:
	if action == "Save look":
		var file := FileAccess.open(DRAFT, FileAccess.WRITE)
		if file == null:
			_status.text = "Could not save look."
			return
		file.store_string(controls.appearance.to_json_string())
		_status.text = "Look saved."
		return
	var appearance := CharacterAppearance.default_appearance()
	if action == "Load look":
		if not FileAccess.file_exists(DRAFT):
			_status.text = "No saved look yet."
			return
		appearance = CharacterAppearance.from_json_string(FileAccess.get_file_as_string(DRAFT))
		if appearance == null:
			_status.text = "Saved look could not be read."
			return
	controls.set_appearance(appearance)
	character.apply_appearance(appearance)
	_status.text = "Look loaded." if action == "Load look" else "Default look restored."

func _capture(args: PackedStringArray) -> void:
	var look := CharacterAppearance.default_appearance()
	if args.has("--sailor"):
		look.headwear_id = "cap"
		look.facial_hair_id = "moustache"
		look.face_accessory_id = "pipe"
		look.age = 45
	if args.has("--worker"):
		look = CharacterCatalog.appearance_preset("dock_worker")
		look.accent_color = Color(.95,.76,.055)
		look.top_color = Color(.18,.27,.32)
		look.skin_color = Color(.68,.45,.3)
	if args.has("--base"):
		look.top_id = "none"
		look.trousers_id = "none"
		look.footwear_id = "none"
	if args.has("--heavy"):
		look.build = 1.0
		look.belly = 1.0
		look.frame = 1.0
		look.age = 80
	controls.set_appearance(look)
	character.apply_appearance(look)
	if args.has("--walk"): character.play_motion(&"walk")
	for i in range(10): await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(args[args.find("--capture")+1])
	print("CHARACTER STUDIO CAPTURE ", character.animation_player.get_animation_list() if character.animation_player != null else [])
	get_tree().quit()
