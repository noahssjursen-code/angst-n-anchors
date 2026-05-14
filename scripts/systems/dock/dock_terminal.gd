class_name DockTerminal
extends StaticBody3D

@export var spawner_path: NodePath
@export var interact_range: float = 4.0
@export var terminal_size: Vector3 = Vector3(1.0, 1.2, 0.55)
@export var prompt_text: String = "Press E for ship terminal"

var _ui_layer: CanvasLayer
var _panel: Panel
var _prompt_label: Label


func _ready() -> void:
	_rebuild_terminal()
	if not Engine.is_editor_hint():
		_ensure_ui()


func _process(_delta: float) -> void:
	if Engine.is_editor_hint() or _prompt_label == null or _panel == null:
		return
	_prompt_label.visible = not _panel.visible and _player_can_interact()


func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if event.is_action_pressed("interact") and _player_can_interact():
		_show_menu()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel") and _panel != null and _panel.visible:
		_panel.visible = false
		get_viewport().set_input_as_handled()


func _rebuild_terminal() -> void:
	for child in get_children():
		child.queue_free()

	var shape := BoxShape3D.new()
	shape.size = terminal_size

	var collision := CollisionShape3D.new()
	collision.name = "TerminalCollision"
	collision.shape = shape
	collision.position = Vector3.UP * (terminal_size.y * 0.5)
	add_child(collision)

	var body := MeshBuilder.box(terminal_size, Color(0.18, 0.19, 0.18), 0.8, 0.05)
	body.name = "TerminalBody"
	body.position = Vector3.UP * (terminal_size.y * 0.5)
	add_child(body)

	var screen := MeshBuilder.box(Vector3(0.72, 0.38, 0.04), Color(0.04, 0.11, 0.12), 0.4, 0.0)
	screen.name = "TerminalScreen"
	screen.position = Vector3(0.0, 0.86, -terminal_size.z * 0.5 - 0.025)
	add_child(screen)


func _ensure_ui() -> void:
	_ui_layer = CanvasLayer.new()
	_ui_layer.name = "DockTerminalLayer"
	add_child(_ui_layer)

	_panel = Panel.new()
	_panel.name = "ShipSpawnPanel"
	_panel.visible = false
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.offset_left = -150.0
	_panel.offset_right = 150.0
	_panel.offset_top = -90.0
	_panel.offset_bottom = 90.0
	_ui_layer.add_child(_panel)

	var title := Label.new()
	title.text = "Ship Terminal"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 14.0
	title.offset_bottom = 42.0
	_panel.add_child(title)

	var spawn_button := Button.new()
	spawn_button.text = "Spawn Test Boat"
	spawn_button.set_anchors_preset(Control.PRESET_CENTER)
	spawn_button.offset_left = -105.0
	spawn_button.offset_right = 105.0
	spawn_button.offset_top = -18.0
	spawn_button.offset_bottom = 22.0
	spawn_button.pressed.connect(_spawn_selected_ship)
	_panel.add_child(spawn_button)

	var close_button := Button.new()
	close_button.text = "Close"
	close_button.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	close_button.offset_left = -70.0
	close_button.offset_right = 70.0
	close_button.offset_top = -54.0
	close_button.offset_bottom = -18.0
	close_button.pressed.connect(func() -> void: _panel.visible = false)
	_panel.add_child(close_button)

	_prompt_label = Label.new()
	_prompt_label.text = prompt_text
	_prompt_label.visible = false
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.add_theme_font_size_override("font_size", 20)
	_prompt_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt_label.offset_left = -190.0
	_prompt_label.offset_right = 190.0
	_prompt_label.offset_top = -88.0
	_prompt_label.offset_bottom = -48.0
	_ui_layer.add_child(_prompt_label)


func _show_menu() -> void:
	_ensure_ui()
	_panel.visible = true
	_prompt_label.visible = false


func _spawn_selected_ship() -> void:
	var spawner := get_node_or_null(spawner_path)
	if spawner != null and spawner.has_method("spawn_ship"):
		spawner.call("spawn_ship")
	if _panel != null:
		_panel.visible = false


func _player_can_interact() -> bool:
	var player := _nearest_player()
	if player == null:
		return false
	var camera := player.get_node_or_null("Camera3D") as Camera3D
	if camera == null:
		return true

	var from := camera.global_position
	var to := from - camera.global_transform.basis.z * interact_range
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [player.get_rid()]
	query.collide_with_areas = true
	query.collide_with_bodies = true

	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return false
	var collider := hit.get("collider") as Node
	return collider == self or (collider != null and is_ancestor_of(collider))


func _nearest_player() -> CharacterBody3D:
	for node in get_tree().get_nodes_in_group("player"):
		var body := node as CharacterBody3D
		if body != null and global_position.distance_to(body.global_position) <= interact_range:
			return body
	return null
