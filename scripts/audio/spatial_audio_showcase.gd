extends Node3D
## F6 listening room using production emitters and production camera controllers.
var _body: CharacterBody3D
var _camera: Camera3D
var _view: PlayerCamera
var _boat: RigidBody3D
var _boat_camera: BoatCamera
var _station: Node3D
var _audio: BoatAudioSystem
var _label: Label
var _mode := 0
var _moving := false
var _time := 0.0
var _wall: StaticBody3D

class DemoBoat extends BoatBody:
	func _ready() -> void: pass
	func _physics_process(_delta: float) -> void: pass

func _ready() -> void:
	assert(ShipyardPlaytestMode.active())
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("172a38")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.7
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -25, 0)
	add_child(sun)
	_box(self, Vector3(80, 0.1, 80), Vector3(0, -1, 0), Color("354c59"))
	_boat = DemoBoat.new()
	_boat.freeze = true
	add_child(_boat)
	_boat.position = Vector3(0, 0, -8)
	var engine_state := PropulsionComponent.new()
	engine_state.name = "PropulsionComponent"
	_boat.add_child(engine_state)
	engine_state.set_engine_running(true)
	_box(_boat, Vector3(4, 0.3, 12), Vector3.ZERO, Color("526b76"))
	var engine := Node3D.new()
	engine.name = "InstalledEngine"
	_boat.add_child(engine)
	engine.position = Vector3(0, 0.6, 3)
	_box(engine, Vector3(1.3, 1, 2), Vector3.ZERO, Color("edb653"))
	var sign := Label3D.new()
	sign.text = "ENGINE\nSound source"
	sign.position = Vector3(0, 2, 0)
	engine.add_child(sign)
	_audio = BoatAudioSystem.new()
	_boat.add_child(_audio)
	_audio._on_helm_activated()
	_station = Node3D.new()
	_boat.add_child(_station)
	_station.position = Vector3(0, 1.7, -3)
	_boat_camera = BoatCamera.new()
	_boat.add_child(_boat_camera)
	_boat_camera.begin_helm(_station)
	_body = CharacterBody3D.new()
	add_child(_body)
	_body.position = Vector3(7, 0, 2)
	_camera = Camera3D.new()
	_body.add_child(_camera)
	_camera.current = true
	_view = PlayerCamera.new()
	_body.add_child(_view)
	_view.bind(_body, _camera)
	_wall = StaticBody3D.new()
	add_child(_wall)
	_wall.position = Vector3(3, 1, -5)
	_wall.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.25, 4, 7)
	shape.shape = box
	_wall.add_child(shape)
	_box(_wall, box.size, Vector3.ZERO, Color("8b6f62"))
	var layer := CanvasLayer.new()
	add_child(layer)
	_label = Label.new()
	_label.position = Vector2(24, 22)
	_label.add_theme_font_size_override("font_size", 22)
	layer.add_child(_label)
	_mode = 3
	_boat_camera._mode = BoatCamera.Mode.THIRD_PERSON
	_boat_camera.current = true
	if OS.get_cmdline_user_args().has("--capture"):
		call_deferred("_capture_review")

func _box(parent: Node3D, size: Vector3, at: Vector3, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	mesh.material_override = material
	parent.add_child(mesh)
	mesh.position = at

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_1, KEY_2, KEY_3, KEY_4]:
			_mode = event.keycode - KEY_1
			_camera.current = _mode < 2
			_boat_camera.current = _mode >= 2
			_view._mode = PlayerCamera.CameraMode.FIRST_PERSON if _mode == 0 else PlayerCamera.CameraMode.THIRD_PERSON
			_view._apply_mode()
			_boat_camera._mode = BoatCamera.Mode.FIRST_PERSON if _mode == 2 else BoatCamera.Mode.THIRD_PERSON
		if event.keycode == KEY_M: _moving = not _moving
		if event.keycode == KEY_I:
			var engine := _boat.get_node("PropulsionComponent") as PropulsionComponent
			engine.set_engine_running(not engine.engine_running)
		if event.keycode == KEY_B:
			_wall.visible = not _wall.visible
			_wall.collision_layer = 1 if _wall.visible else 0
		if event.keycode == KEY_ESCAPE: Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if event.pressed else Input.MOUSE_MODE_VISIBLE
	if _mode < 2: _view.handle_input(event)

func _process(delta: float) -> void:
	_time += delta
	if _moving:
		_boat.position.x = sin(_time * 0.3) * 10.0
		_boat.rotation.y = sin(_time * 0.2) * 0.5
	if _mode < 2:
		var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		_body.position += _view.get_flat_basis() * Vector3(input.x, 0, input.y) * delta * 5
		_view.update(delta, Vector3.ZERO, input, true, false)
	var camera := get_viewport().get_camera_3d()
	var distance := camera.global_position.distance_to(_audio._engine_idle.global_position)
	_label.text = "SPATIAL AUDIO\n1 First person   2 Third person   3 Helm   4 Vehicle orbit\nWASD Move   Hold right mouse to look   Wheel zooms vehicle\nM Move boat   B Toggle wall   I Start/stop engine\n\n%s  |  Source distance %.1f m  |  Obstruction %.0f%%" % [
		["First person", "Third person", "Helm", "Vehicle orbit"][_mode], distance, _audio._engine_idle.obstruction * 100]


func _capture_review() -> void:
	var folder := "C:/Users/noahs/Pictures/machinescreenshots"
	DirAccess.make_dir_recursive_absolute(folder)
	await get_tree().create_timer(1.0).timeout
	for mode in [0, 1, 2, 3]:
		var event := InputEventKey.new()
		event.keycode = KEY_1 + mode
		event.pressed = true
		_unhandled_input(event)
		await get_tree().create_timer(0.8).timeout
		await RenderingServer.frame_post_draw
		var path := folder.path_join("spatial-audio-%s-mode-%d.png" % [str(Time.get_unix_time_from_system()).replace(".", "-"), mode])
		get_viewport().get_texture().get_image().save_png(path)
		print("SPATIAL CAPTURE ", path)
	get_tree().quit()
