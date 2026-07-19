class_name ShippingLaneNetworkShowcase
extends Node3D

## F6 deterministic traffic lab. Lightweight data vessels exercise the same
## routes, blocks, berth queues, and authority snapshots intended for servers.

const WORLD_LAYOUT_GENERATOR := preload("res://scripts/world/world_layout_generator.gd")
const COASTAL_PORT_PLACER := preload("res://scripts/world/coastal_port_placer.gd")
const SEED := 77127
const PORT_COUNT := 10
const VESSEL_COUNT := 32

var _layout: WorldLayout
var _ports: Array[PortData] = []
var _network: ShippingLaneNetwork
var _simulator: ShippingLaneTrafficSimulator
var _camera: Camera3D
var _sea: MeshInstance3D
var _status: Label
var _traffic_status: Label
var _report_preview: TextEdit
var _focus_index := 0
var _ship_markers: Dictionary = {}
var _passage_lines: Dictionary = {}
var _state_materials: Dictionary = {}
var _simulation_speed := 120.0
var _paused := false
var _ui_elapsed := 0.0


func _ready() -> void:
	_build_environment()
	_status.text = "Generating deterministic lane graph..."
	await get_tree().process_frame
	_layout = WORLD_LAYOUT_GENERATOR.generate(SEED)
	var names := PackedStringArray()
	for index in range(PORT_COUNT):
		names.append("Traffic Port %02d" % (index + 1))
	var definitions: Array[PortDefinition] = COASTAL_PORT_PLACER.place_ports(
		_layout, PORT_COUNT, names)
	for definition in definitions:
		_ports.append(PortExpander.expand(definition, SEED, _layout))
	_network = ShippingLaneNetworkBuilder.new().build(_layout, _ports)
	_draw_coastlines()
	var gizmos := ShippingLaneDebugDraw.new()
	gizmos.name = "ShippingLaneDebugDraw"
	gizmos.configure(_network, 7200.0, true)
	add_child(gizmos)
	_reset_simulation()
	_focus_port(0)
	var graph := _network.summary()
	_status.text = (
		"SHIPPING LANE TRAFFIC LAB\n"
		+ "Q/E port   WASD pan   wheel zoom   Space pause   +/- speed   R reset   Ctrl+C copy\n"
		+ "cyan highways   yellow connectors   green/orange interlocking   purple queues\n"
		+ "mint passing zones   teal breakoffs   pale-green open-water passages\n"
		+ "blue ships moving   yellow signal wait   magenta berth wait\n"
		+ "%d ports | %d nodes | %d blocks | %d signals | checksum %s"
		% [PORT_COUNT, int(graph.nodes), int(graph.blocks), int(graph.signals),
			str(graph.network_checksum).left(12)]
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
		_camera.position += Vector3(input.x, 0.0, input.y) * _camera.size * 0.65 * delta
	if _sea != null:
		_sea.position.x = _camera.position.x
		_sea.position.z = _camera.position.z
	if _simulator != null and not _paused:
		_simulator.advance(delta * _simulation_speed)
		_update_ship_markers()
	_ui_elapsed += delta
	if _ui_elapsed >= 0.25:
		_ui_elapsed = 0.0
		_refresh_traffic_ui()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.ctrl_pressed and event.keycode == KEY_C:
			_copy_report()
		elif event.keycode == KEY_Q:
			_focus_port(_focus_index - 1)
		elif event.keycode == KEY_E:
			_focus_port(_focus_index + 1)
		elif event.keycode == KEY_SPACE:
			_paused = not _paused
		elif event.keycode == KEY_R:
			_reset_simulation()
		elif event.keycode in [KEY_EQUAL, KEY_KP_ADD]:
			_simulation_speed = minf(_simulation_speed * 2.0, 960.0)
		elif event.keycode in [KEY_MINUS, KEY_KP_SUBTRACT]:
			_simulation_speed = maxf(_simulation_speed * 0.5, 1.0)
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
	_build_ui()


func _build_ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var panel := ColorRect.new()
	panel.position = Vector2(18.0, 18.0)
	panel.size = Vector2(1110.0, 160.0)
	panel.color = Color(0.01, 0.02, 0.03, 0.88)
	canvas.add_child(panel)
	_status = Label.new()
	_status.position = Vector2(34.0, 28.0)
	_status.size = Vector2(1070.0, 145.0)
	_status.add_theme_font_size_override("font_size", 16)
	_status.modulate = Color(0.88, 0.94, 0.98)
	canvas.add_child(_status)
	var traffic_panel := ColorRect.new()
	traffic_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	traffic_panel.position = Vector2(-545.0, 18.0)
	traffic_panel.size = Vector2(527.0, 490.0)
	traffic_panel.color = Color(0.01, 0.02, 0.03, 0.92)
	canvas.add_child(traffic_panel)
	_traffic_status = Label.new()
	_traffic_status.position = Vector2(14.0, 12.0)
	_traffic_status.size = Vector2(499.0, 104.0)
	_traffic_status.add_theme_font_size_override("font_size", 15)
	traffic_panel.add_child(_traffic_status)
	var copy_button := Button.new()
	copy_button.text = "COPY VALIDATION REPORT"
	copy_button.position = Vector2(14.0, 118.0)
	copy_button.size = Vector2(499.0, 36.0)
	copy_button.pressed.connect(_copy_report)
	traffic_panel.add_child(copy_button)
	_report_preview = TextEdit.new()
	_report_preview.position = Vector2(14.0, 164.0)
	_report_preview.size = Vector2(499.0, 312.0)
	_report_preview.editable = false
	_report_preview.wrap_mode = TextEdit.LINE_WRAPPING_NONE
	traffic_panel.add_child(_report_preview)


func _reset_simulation() -> void:
	for marker_value in _ship_markers.values():
		(marker_value as Node).queue_free()
	_ship_markers.clear()
	for line_value in _passage_lines.values():
		(line_value as Node).queue_free()
	_passage_lines.clear()
	_simulator = ShippingLaneTrafficSimulator.new()
	_simulator.configure(_network, VESSEL_COUNT, SEED, _layout)
	_paused = false
	_build_ship_markers()
	_update_ship_markers()
	_refresh_traffic_ui()


func _build_ship_markers() -> void:
	for vessel in _simulator.vessel_records():
		var marker := Node3D.new()
		marker.name = str(vessel.get("id", "TrafficVessel"))
		var hull := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(float(vessel.get("beam_m", 10.0)), 5.0,
			float(vessel.get("length_m", 45.0)))
		hull.mesh = mesh
		hull.material_override = _state_material("planning")
		marker.add_child(hull)
		var label := Label3D.new()
		label.name = "State"
		label.position = Vector3(0.0, 9.0, 0.0)
		label.font_size = 20
		label.outline_size = 5
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		marker.add_child(label)
		add_child(marker)
		_ship_markers[str(vessel.get("id", ""))] = marker


func _update_ship_markers() -> void:
	for vessel in _simulator.vessel_records():
		var vessel_id := str(vessel.get("id", ""))
		var marker := _ship_markers.get(vessel_id) as Node3D
		if marker == null:
			continue
		var point := vessel.get("position", Vector2.ZERO) as Vector2
		marker.position = Vector3(point.x, 7.0, point.y)
		var heading := vessel.get("heading", Vector2(0.0, -1.0)) as Vector2
		marker.rotation.y = atan2(-heading.x, -heading.y)
		var state := str(vessel.get("state", "unknown"))
		(marker.get_child(0) as MeshInstance3D).material_override = _state_material(state)
		var label := marker.get_node("State") as Label3D
		label.text = "%s\n%s" % [vessel_id, state.replace("_", " ")]
		label.modulate = _state_color(state)
		_update_passage_line(vessel)


func _update_passage_line(vessel: Dictionary) -> void:
	var vessel_id := str(vessel.get("id", ""))
	var signature := "%s|%s|%d" % [vessel.get("source_token_id", ""),
		vessel.get("destination_token_id", ""), int(vessel.get("open_water_sections", 0))]
	var existing := _passage_lines.get(vessel_id) as MeshInstance3D
	if existing != null and str(existing.get_meta("signature", "")) == signature:
		return
	if existing != null:
		existing.queue_free()
		_passage_lines.erase(vessel_id)
	var vertices := PackedVector3Array()
	for raw_step in vessel.get("route_steps", []) as Array:
		var step := raw_step as Dictionary
		if str(step.get("kind", "")) != "open_water":
			continue
		var points := step.get("points", PackedVector2Array()) as PackedVector2Array
		for index in range(points.size() - 1):
			vertices.append(Vector3(points[index].x, 4.2, points[index].y))
			vertices.append(Vector3(points[index + 1].x, 4.2, points[index + 1].y))
	if vertices.is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	var line := MeshInstance3D.new()
	line.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.62, 1.0, 0.74, 0.68)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.no_depth_test = true
	line.material_override = material
	line.set_meta("signature", signature)
	add_child(line)
	_passage_lines[vessel_id] = line


func _refresh_traffic_ui() -> void:
	if _simulator == null or _traffic_status == null:
		return
	var data := _simulator.summary()
	_traffic_status.text = (
		"%s | %s | %.0fx | %.0f simulated seconds\n"
		+ "%d ships | %d trips | %d queued\n"
		+ "collisions %d | deadlocks %d | starved %d | route failures %d\n"
		+ "max queue %d | max wait %.0fs | signal stops %d"
	) % [str(data.get("status", "FAIL")), "PAUSED" if _paused else "RUNNING",
		_simulation_speed, float(data.get("simulated_seconds", 0.0)),
		int(data.get("vessel_count", 0)), int(data.get("trips_completed", 0)),
		int(data.get("active_port_queue", 0)), int(data.get("collisions", 0)),
		int(data.get("deadlocks", 0)), int(data.get("starved_vessels", 0)),
		int(data.get("route_failures", 0)),
		int(data.get("max_port_queue", 0)), float(data.get("max_wait_seconds", 0.0)),
		int(data.get("reservation_denials", 0))]
	_traffic_status.modulate = Color(0.35, 1.0, 0.55) \
		if str(data.get("status", "FAIL")) == "PASS" else Color(1.0, 0.55, 0.25)
	if _report_preview != null:
		_report_preview.text = _simulator.generate_report()


func _copy_report() -> void:
	if _simulator != null:
		DisplayServer.clipboard_set(_simulator.generate_report())


func _state_material(state: String) -> StandardMaterial3D:
	if _state_materials.has(state):
		return _state_materials[state] as StandardMaterial3D
	var material := StandardMaterial3D.new()
	material.albedo_color = _state_color(state)
	material.roughness = 0.65
	_state_materials[state] = material
	return material


static func _state_color(state: String) -> Color:
	match state:
		"traveling", "traveling_open_water", "departing": return Color(0.18, 0.78, 1.0)
		"waiting_signal": return Color(1.0, 0.78, 0.18)
		"waiting_berth": return Color(0.92, 0.35, 1.0)
		"docked": return Color(0.25, 1.0, 0.48)
		"route_failed": return Color(1.0, 0.12, 0.18)
		_: return Color(0.85, 0.9, 0.95)


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
