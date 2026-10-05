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
	theme = HudStyle.make_theme()
	var backdrop := ColorRect.new()
	backdrop.color = Color(.025,.036,.044)
	add_child(backdrop)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","top","right","bottom"]: margin.add_theme_constant_override("margin_" + side, 24)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	margin.add_child(row)
	var container := SubViewportContainer.new()
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.stretch = true
	row.add_child(container)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(600,800)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(viewport)
	var world := Node3D.new()
	viewport.add_child(world)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(.025,.036,.044)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(.7,.76,.8)
	environment.environment.ambient_light_energy = .65
	world.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35,-30,0)
	light.light_energy = 1.2
	world.add_child(light)
	_character = CharacterVisual.new()
	_character.rotation.y = PI-.25
	world.add_child(_character)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(0,1.15,3.5)
	camera.look_at(Vector3(0,.98,0))
	camera.fov = 34
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = 340
	column.add_theme_constant_override("separation", 12)
	row.add_child(column)
	column.add_child(UiBuilder.title_label("CREATE CAPTAIN"))
	_name_field = LineEdit.new()
	_name_field.placeholder_text = "Captain name"
	column.add_child(_name_field)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_controls = CharacterAppearanceControls.new()
	_controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_controls)
	_controls.appearance_changed.connect(func(value: CharacterAppearance) -> void:
		_appearance = value.duplicate()
		_character.apply_appearance(_appearance))
	_controls.motion_changed.connect(_character.play_motion)
	_controls.playback_speed_changed.connect(func(speed: float) -> void: _character.animation_player.speed_scale = speed)
	_confirm = UiBuilder.button("CONTINUE")
	_confirm.disabled = true
	_confirm.pressed.connect(func() -> void: confirmed.emit(_name_field.text.strip_edges(), _appearance.duplicate()))
	_name_field.text_changed.connect(func(text: String) -> void: _confirm.disabled = text.strip_edges().is_empty())
	column.add_child(_confirm)
	var back := UiBuilder.button("BACK")
	back.pressed.connect(func() -> void: cancelled.emit())
	column.add_child(back)

func open_with_existing(data: PlayerData) -> void:
	if not is_node_ready(): await ready
	_appearance = data.appearance.duplicate() if data != null else CharacterAppearance.default_appearance()
	_name_field.text = data.display_name if data != null else ""
	_confirm.disabled = _name_field.text.strip_edges().is_empty()
	_controls.set_appearance(_appearance)
	_character.apply_appearance(_appearance)
	visible = true
	_name_field.grab_focus()
