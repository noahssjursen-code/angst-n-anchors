class_name CharacterCreatorPanel
extends Control

signal confirmed(display_name: String, appearance: CharacterAppearance)
signal cancelled

var _appearance := CharacterAppearance.default_appearance()
var _name_field: LineEdit
var _confirm: Button
var _controls: CharacterAppearanceControls
var _character: CharacterVisual


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0.031, 0.039, 0.047, 0.94)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)

	var pad := Ui.margin(36)
	Ui.full_rect(pad)
	add_child(pad)
	var row := Ui.hbox(28)
	pad.add_child(row)

	var viewport_wrap := Ui.surface("Inset")
	viewport_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(viewport_wrap)
	var container := SubViewportContainer.new()
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container.stretch = true
	viewport_wrap.add_child(container)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(720, 900)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.transparent_bg = false
	container.add_child(viewport)
	var world := Node3D.new()
	viewport.add_child(world)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.125, 0.165, 0.196)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.72, 0.78, 0.82)
	environment.environment.ambient_light_energy = 0.7
	world.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, -30, 0)
	light.light_energy = 1.2
	world.add_child(light)
	_character = CharacterVisual.new()
	_character.rotation.y = PI - 0.25
	world.add_child(_character)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(0, 1.15, 3.5)
	camera.look_at(Vector3(0, 0.98, 0))
	camera.fov = 34

	var sheet := Ui.sheet()
	sheet.custom_minimum_size.x = 420
	row.add_child(sheet)
	var column := Ui.vbox(14)
	sheet.add_child(column)
	column.add_child(Ui.header("New captain  ·  01 of 03", "Create captain",
		"Name, look and kit. The company comes next."))
	column.add_child(Ui.field_label("Captain name"))
	_name_field = Ui.line_edit("Captain name")
	column.add_child(_name_field)
	var scroll := Ui.scroll()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	_controls = CharacterAppearanceControls.new()
	_controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_controls)
	_controls.appearance_changed.connect(func(value: CharacterAppearance) -> void:
		_appearance = value.duplicate()
		_character.apply_appearance(_appearance))
	_controls.motion_changed.connect(_character.play_motion)
	_controls.playback_speed_changed.connect(func(speed: float) -> void:
		_character.animation_player.speed_scale = speed)

	var actions := Ui.hbox(8)
	var back := Ui.button("Back", "ghost", func() -> void: cancelled.emit())
	actions.add_child(back)
	_confirm = Ui.button("Continue", "primary")
	_confirm.disabled = true
	_confirm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_confirm.pressed.connect(func() -> void:
		confirmed.emit(_name_field.text.strip_edges(), _appearance.duplicate()))
	actions.add_child(_confirm)
	column.add_child(actions)
	_name_field.text_changed.connect(func(text: String) -> void:
		_confirm.disabled = text.strip_edges().is_empty())


func open_with_existing(data: PlayerData) -> void:
	if not is_node_ready():
		await ready
	_appearance = data.appearance.duplicate() if data != null else CharacterAppearance.default_appearance()
	_name_field.text = data.display_name if data != null else ""
	_confirm.disabled = _name_field.text.strip_edges().is_empty()
	_controls.set_appearance(_appearance)
	_character.apply_appearance(_appearance)
	visible = true
	_name_field.grab_focus()
