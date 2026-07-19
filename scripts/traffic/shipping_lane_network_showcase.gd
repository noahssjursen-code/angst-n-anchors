class_name ShippingLaneNetworkShowcase
extends Node3D

## F6 inspection scene for the static maritime traffic infrastructure.
## No vessels are spawned or simulated here.

const WORLD_LAYOUT_GENERATOR := preload("res://scripts/world/world_layout_generator.gd")
const COASTAL_PORT_PLACER := preload("res://scripts/world/coastal_port_placer.gd")
const SEED := 77127
const PORT_COUNT := 10

var _layout: WorldLayout
var _ports: Array[PortData] = []
var _camera: Camera3D
var _sea: MeshInstance3D
var _status: Label
var _focus_index := 0


func _ready() -> void:
	_build_environment()
	_status.text = "Generating deterministic lane graph…"
	await get_tree().process_frame
	_layout = WORLD_LAYOUT_GENERATOR.generate(SEED)
	var names := PackedStringArray()
	for index in range(PORT_COUNT):
		names.append("Traffic Port %02d" % (index + 1))
	var definitions: Array[PortDefinition] = COASTAL_PORT_PLACER.place_ports(
		_layout, PORT_COUNT, names)
	for definition in definitions:
		_ports.append(PortExpander.expand(definition, SEED, _layout))
	var network := ShippingLaneNetworkBuilder.new().build(_layout, _ports)
	_draw_coastlines()
	var gizmos := ShippingLaneDebugDraw.new()
	gizmos.name = "ShippingLaneDebugDraw"
	gizmos.configure(network, 7200.0, true)
	add_child(gizmos)
	_focus_port(0)
	var summary := network.summary()
	_status.text = (
		"SHIPPING LANE NETWORK — STATIC INFRASTRUCTURE ONLY\n"
		+ "Q / E  port region     WASD  pan     mouse wheel  zoom\n"
		+ "cyan  directional highways   yellow  connectors   green/orange  harbour interlocking\n"
		+ "orange rings  port gates   crosses  traffic signals   purple X  holding slots\n"
		+ "%d ports · %d nodes · %d blocks · %d signals · checksum %s"
		% [PORT_COUNT, int(summary.nodes), int(summary.blocks), int(summary.signals),
			str(summary.network_checksum).left(12)]
	)


func _process(delta: float) -> void:
	if _camera == null:
		return
	var input := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if Input.is_key_pressed(KEY_A): input.x -= 1.0
	if Input.is_key_pressed(KEY_D): input.x += 1.0
	if Input.is_key_pressed(KEY_W): input.y -= 1.0
	if Input.is_key_pressed(KEY_S): input.y += 1.0
	if input.length_squared() > 0.0:
		input = input.normalized()
		var speed := _camera.size * 0.65
		_camera.position += Vector3(input.x, 0.0, input.y) * speed * delta
	if _sea != null:
		_sea.position.x = _camera.position.x
		_sea.position.z = _camera.position.z


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_Q:
			_focus_port(_focus_index - 1)
		elif event.keycode == KEY_E:
			_focus_port(_focus_index + 1)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_camera.size = maxf(_camera.size * 0.82, 500.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_camera.size = minf(_camera.size * 1.22, 10000.0)


func _focus_port(index: int) -> void:
	if _ports.is_empty() or _camera == null:
		return
	_focus_index = posmod(index, _ports.size())
	var port := _ports[_focus_index]
	_camera.position = Vector3(port.world_position.x, 4000.0, port.world_position.z)
	_camera.size = 1800.0


func _build_environment() -> void:
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.015, 0.028, 0.042)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.72, 0.80, 0.88)
	environment.ambient_light_energy = 0.8
	environment_node.environment = environment
	add_child(environment_node)

	_camera = Camera3D.new()
	_camera.name = "InspectionCamera"
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 1800.0
	_camera.far = 20000.0
	_camera.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	_camera.current = true
	add_child(_camera)

	_sea = MeshInstance3D.new()
	var sea_mesh := BoxMesh.new()
	sea_mesh.size = Vector3(15000.0, 0.25, 15000.0)
	_sea.mesh = sea_mesh
	_sea.position.y = -0.3
	var sea_material := StandardMaterial3D.new()
	sea_material.albedo_color = Color(0.012, 0.075, 0.12)
	sea_material.roughness = 0.92
	_sea.material_override = sea_material
	add_child(_sea)

	var canvas := CanvasLayer.new()
	add_child(canvas)
	var panel := ColorRect.new()
	panel.position = Vector2(18.0, 18.0)
	panel.size = Vector2(920.0, 142.0)
	panel.color = Color(0.01, 0.02, 0.03, 0.88)
	canvas.add_child(panel)
	_status = Label.new()
	_status.position = Vector2(34.0, 30.0)
	_status.size = Vector2(890.0, 125.0)
	_status.add_theme_font_size_override("font_size", 17)
	_status.modulate = Color(0.88, 0.94, 0.98)
	canvas.add_child(_status)


func _draw_coastlines() -> void:
	var vertices := PackedVector3Array()
	for contour_raw in _layout.coastline_contours:
		var contour := contour_raw as PackedVector2Array
		for index in range(contour.size() - 1):
			vertices.append(Vector3(contour[index].x, 1.0, contour[index].y))
			vertices.append(Vector3(contour[index + 1].x, 1.0, contour[index + 1].y))
	if vertices.is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.58, 0.72, 0.62, 0.82)
	material.no_depth_test = true
	instance.material_override = material
	add_child(instance)
