class_name ShippingLaneNetworkShowcase
extends Node3D

## F6 deterministic traffic lab. Lightweight data vessels exercise the same
## routes, blocks, berth queues, and authority snapshots intended for servers.

const WORLD_LAYOUT_GENERATOR := preload("res://scripts/world/world_layout_generator.gd")
const COASTAL_PORT_PLACER := preload("res://scripts/world/coastal_port_placer.gd")
const PRESENTATION_POLICY := preload(
	"res://scripts/traffic/traffic_vessel_presentation_policy.gd")
const PREBUILT_CATALOG := preload("res://scripts/ship/prebuilt_vessel_catalog.gd")
const VESSEL_SPAWN := preload("res://scripts/ship/vessel_spawn.gd")
const WORLD_PORT_NAMES := preload("res://scripts/world/world_port_names.gd")
const DEFAULT_SEED := 42
## F6 uses the same world plane and first real ports, but only a representative
## local subset. The full 35-port/250-vessel fixture belongs to the profiler.
const PORT_COUNT := 10
const VESSEL_COUNT := 32
const FULL_VESSEL_RADIUS_M := 900.0
const PROXY_VESSEL_RADIUS_M := 3600.0
const MAXIMUM_FULL_VESSELS := 4

var _layout: WorldLayout
var _scenario_seed := DEFAULT_SEED
var _world_size_m := 40000.0
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
var _full_ships: Dictionary = {}
var _passage_lines: Dictionary = {}
var _state_materials: Dictionary = {}
var _simulation_speed := 120.0
var _paused := false
var _ui_elapsed := 0.0
var _presentation_elapsed := 0.0
var _presentation_summary: Dictionary = {}
var _materialization_ms := 0.0
var _prebuilt_entries: Array[Dictionary] = []


func _ready() -> void:
	_build_environment()
	for entry in PREBUILT_CATALOG.for_sale_entries():
		# The traffic lab exercises runtime-authored hulls, not the two frozen
		# hand-authored vessel-scene exceptions with owner-only systems.
		if HullCatalog.has_id(str(entry.get("hull_id", ""))):
			_prebuilt_entries.append(entry)
	_status.text = "Generating deterministic lane graph..."
	await get_tree().process_frame
	var settings := get_node_or_null("/root/GameSettings")
	if settings != null:
		_scenario_seed = int(settings.get("map_generation_seed"))
		_world_size_m = float(settings.get("map_world_size_m"))
	print("Shipping lane showcase: building fixture")
	var fixture := _build_fixture(_scenario_seed, _world_size_m)
	print("Shipping lane showcase: fixture built")
	_finish_fixture(fixture)


static func _build_fixture(seed: int, world_size_m: float) -> Dictionary:
	var layout := WORLD_LAYOUT_GENERATOR.generate(seed,
		WorldConfig.ARCHETYPE_PATH, world_size_m) as WorldLayout
	var names := PackedStringArray(WORLD_PORT_NAMES.NAMES)
	var definitions: Array[PortDefinition] = COASTAL_PORT_PLACER.place_ports(
		layout, PORT_COUNT, names)
	var ports: Array[PortData] = []
	for definition in definitions:
		ports.append(PortExpander.expand(definition, seed, layout))
	return {
		"layout": layout,
		"ports": ports,
		"network": ShippingLaneNetworkBuilder.new().build(layout, ports),
	}


func _finish_fixture(result: Dictionary) -> void:
	_layout = result.get("layout") as WorldLayout
	_ports.assign(result.get("ports", []))
	_network = result.get("network") as ShippingLaneNetwork
	if _layout == null or _network == null:
		_status.text = "TRAFFIC LAB BUILD FAILED"
		return
	_draw_coastlines()
	print("Shipping lane showcase: drawing network")
	var gizmos := ShippingLaneDebugDraw.new()
	gizmos.name = "ShippingLaneDebugDraw"
	gizmos.configure(_network, 7200.0, true)
	add_child(gizmos)
	print("Shipping lane showcase: configuring vessels")
	_reset_simulation()
	print("Shipping lane showcase: vessels configured")
	_focus_port(0)
	var graph := _network.summary()
	_status.text = (
		"SHIPPING LANE TRAFFIC LAB\n"
		+ "Q/E port   WASD pan   wheel zoom   Space pause   +/- speed   R reset   Ctrl+C copy\n"
		+ "cyan highways   yellow connectors   green/orange interlocking   purple queues\n"
		+ "mint passing lanes   cyan OFF ramps   green ON ramps   pale-green open-water passages\n"
		+ "blue ships moving   yellow signal wait   magenta berth wait\n"
		+ "seed %d | %d ports | %d nodes | %d blocks | %d signals | checksum %s"
		% [_scenario_seed, PORT_COUNT, int(graph.nodes), int(graph.blocks), int(graph.signals),
			str(graph.network_checksum).left(12)]
	)
	print("Shipping lane showcase ready: %d ports, %d vessels, %s" % [
		PORT_COUNT, VESSEL_COUNT, str(graph.network_checksum).left(12)])


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
		if _camera != null:
			_simulator.set_interest_centers(PackedVector2Array([
				Vector2(_camera.position.x, _camera.position.z)]))
		_simulator.advance(delta * _simulation_speed)
		_update_ship_markers()
	_presentation_elapsed += delta
	if _presentation_elapsed >= 0.5:
		_presentation_elapsed = 0.0
		_update_vessel_presentation()
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
			_simulation_speed = minf(_simulation_speed * 2.0, 7680.0)
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
	_clear_full_ships()
	for marker_value in _ship_markers.values():
		(marker_value as Node).queue_free()
	_ship_markers.clear()
	for line_value in _passage_lines.values():
		(line_value as Node).queue_free()
	_passage_lines.clear()
	_simulator = ShippingLaneTrafficSimulator.new()
	_simulator.configure(_network, VESSEL_COUNT, _scenario_seed, _layout)
	_paused = false
	_build_ship_markers()
	_update_ship_markers()
	_update_vessel_presentation()
	_refresh_traffic_ui()


func _build_ship_markers() -> void:
	for vessel in _simulator.vessel_records():
		var marker := Node3D.new()
		marker.name = str(vessel.get("id", "TrafficVessel"))
		var hull := MeshInstance3D.new()
		hull.name = "ProxyHull"
		var mesh := BoxMesh.new()
		mesh.size = Vector3(float(vessel.get("beam_m", 10.0)), 5.0,
			float(vessel.get("length_m", 45.0)))
		hull.mesh = mesh
		hull.material_override = _state_material("planning")
		hull.position.y = 3.0
		marker.add_child(hull)
		var label := Label3D.new()
		label.name = "State"
		label.position = Vector3(0.0, 14.0, 0.0)
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
		marker.position = Vector3(point.x, 0.6, point.y)
		var heading := vessel.get("heading", Vector2(0.0, -1.0)) as Vector2
		marker.rotation.y = atan2(-heading.x, -heading.y)
		var state := str(vessel.get("state", "unknown"))
		(marker.get_node("ProxyHull") as MeshInstance3D).material_override = _state_material(state)
		var label := marker.get_node("State") as Label3D
		label.text = "%s\n%s" % [vessel_id, state.replace("_", " ")]
		label.modulate = _state_color(state)
		_update_passage_line(vessel)


func _update_vessel_presentation() -> void:
	if _simulator == null or _camera == null:
		return
	var records := _simulator.vessel_records()
	_presentation_summary = PRESENTATION_POLICY.select(
		records,
		Vector2(_camera.position.x, _camera.position.z),
		FULL_VESSEL_RADIUS_M,
		PROXY_VESSEL_RADIUS_M,
		MAXIMUM_FULL_VESSELS,
	)
	var wanted := {}
	for vessel_id in _presentation_summary.get("full_ids", PackedStringArray()):
		wanted[str(vessel_id)] = true
	for vessel_id in _full_ships.keys():
		if not wanted.has(str(vessel_id)):
			_demote_full_ship(str(vessel_id))
	var started_us := Time.get_ticks_usec()
	for vessel_id in wanted:
		if not _full_ships.has(vessel_id):
			_promote_full_ship(str(vessel_id))
	_materialization_ms = float(Time.get_ticks_usec() - started_us) / 1000.0
	var proxy_ids := {}
	for vessel_id in _presentation_summary.get("proxy_ids", PackedStringArray()):
		proxy_ids[str(vessel_id)] = true
	for vessel_id in _ship_markers:
		var marker := _ship_markers[vessel_id] as Node3D
		var hull := marker.get_node_or_null("ProxyHull") as MeshInstance3D
		if hull != null:
			hull.visible = proxy_ids.has(str(vessel_id)) and not wanted.has(str(vessel_id))
		var label := marker.get_node_or_null("State") as Label3D
		if label != null:
			label.visible = proxy_ids.has(str(vessel_id)) or wanted.has(str(vessel_id))


func _promote_full_ship(vessel_id: String) -> void:
	var marker := _ship_markers.get(vessel_id) as Node3D
	if marker == null:
		return
	if _prebuilt_entries.is_empty():
		return
	var entry: Dictionary = _prebuilt_entries[abs(vessel_id.hash()) % _prebuilt_entries.size()]
	var record := {
		"uid": "traffic-lab-%s" % vessel_id,
		"hull_id": str(entry.get("hull_id", "")),
		"name": "Traffic %s" % vessel_id,
		"shaft_power_kw": float(entry.get("shaft_power_kw", 1.0)),
		"registration_id": str(entry.get("registration_id", "")),
		"brick_layout": (entry.get("prebuilt_layout", {}) as Dictionary).duplicate(true),
	}
	var ship := VESSEL_SPAWN.instantiate_from_record(record) as BoatBody
	if ship == null:
		return
	ship.name = "FullDetail"
	ship.freeze = true
	ship.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	_disable_simulation(ship)
	marker.add_child(ship)
	ship.position = Vector3.ZERO
	ship.rotation = Vector3.ZERO
	call_deferred("_disable_simulation", ship)
	_full_ships[vessel_id] = ship


func _demote_full_ship(vessel_id: String) -> void:
	var ship := _full_ships.get(vessel_id) as Node
	if ship != null and is_instance_valid(ship):
		ship.queue_free()
	_full_ships.erase(vessel_id)


func _clear_full_ships() -> void:
	for vessel_id in _full_ships.keys():
		_demote_full_ship(str(vessel_id))


func _disable_simulation(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	if node is CollisionObject3D:
		var collision := node as CollisionObject3D
		collision.collision_layer = 0
		collision.collision_mask = 0
	for child in node.get_children():
		_disable_simulation(child)


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
		+ "max queue %d | max wait %.0fs | signal stops %d\n"
		+ "presentation: %d full | %d proxy | %d data-only | promotion %.2f ms"
	) % [str(data.get("status", "FAIL")), "PAUSED" if _paused else "RUNNING",
		_simulation_speed, float(data.get("simulated_seconds", 0.0)),
		int(data.get("vessel_count", 0)), int(data.get("trips_completed", 0)),
		int(data.get("active_port_queue", 0)), int(data.get("collisions", 0)),
		int(data.get("deadlocks", 0)), int(data.get("starved_vessels", 0)),
		int(data.get("route_failures", 0)),
		int(data.get("max_port_queue", 0)), float(data.get("max_wait_seconds", 0.0)),
		int(data.get("reservation_denials", 0)),
		_full_ships.size(),
		(_presentation_summary.get("proxy_ids", PackedStringArray()) as PackedStringArray).size(),
		int(_presentation_summary.get("data_only_count", 0)), _materialization_ms]
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
