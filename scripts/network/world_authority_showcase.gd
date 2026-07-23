extends Node3D

## F6 inspect scene for the reliable world-authority seam. It intentionally
## uses WorldGateway exactly like gameplay code: no direct local-backend calls.

var _door_binding: WorldStateBinding
var _door_panel: MeshInstance3D
var _machine_lamp: OmniLight3D
var _status: Label
var _event_log: Label
var _door_open := false
var _door_x := 0.0
var _target_door_x := 0.0
var _operation_id := ""
var _last_event := "No authoritative events yet"


func _ready() -> void:
	_build_scene()
	WorldGateway.world_event.connect(_on_world_event)
	WorldGateway.command_completed.connect(_on_command_completed)
	WorldGateway.authority_error.connect(_on_authority_error)
	WorldGateway.begin_session_with_identity(false, "showcase-captain", "Authority Inspector", "showcase-world")
	_door_binding = WorldStateBinding.new()
	_door_binding.configure("showcase/warehouse-door", "door")
	_door_binding.authoritative_state_changed.connect(_on_door_state)
	_door_binding.command_rejected.connect(_on_binding_rejected)
	add_child(_door_binding)
	_door_binding.request("close", {"open": false})
	_update_hud()


func _exit_tree() -> void:
	if WorldGateway.world_event.is_connected(_on_world_event):
		WorldGateway.world_event.disconnect(_on_world_event)
	if WorldGateway.command_completed.is_connected(_on_command_completed):
		WorldGateway.command_completed.disconnect(_on_command_completed)
	if WorldGateway.authority_error.is_connected(_on_authority_error):
		WorldGateway.authority_error.disconnect(_on_authority_error)
	WorldGateway.stop_session()


func _process(delta: float) -> void:
	_door_x = move_toward(_door_x, _target_door_x, delta * 3.5)
	if _door_panel != null:
		_door_panel.position.x = _door_x


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_1:
			_door_binding.request("close" if _door_open else "open", {"open": not _door_open})
		KEY_2:
			_start_operation()
		KEY_3:
			_finish_operation()
		KEY_4:
			WorldGateway.query_projections()
		KEY_ESCAPE:
			get_tree().quit()


func _start_operation() -> void:
	if not _operation_id.is_empty():
		_last_event = "Equipment already has operation %s" % _operation_id
		_update_hud()
		return
	_operation_id = WorldGateway.next_request_id("showcase-operation").replace(":", "-")
	WorldGateway.send_command(
		WorldContracts.COMMAND_PORT_OPERATION_REQUEST,
		WorldContracts.port_operation_body(
			"showcase-port",
			"berth-a",
			"dock-pump-a",
			"showcase-vessel",
			"unload",
			"fresh_fish",
			"showcase-contract",
			_operation_id,
		),
	)


func _finish_operation() -> void:
	if _operation_id.is_empty():
		_last_event = "No running port operation"
		_update_hud()
		return
	WorldGateway.send_command(
		WorldContracts.COMMAND_PORT_OPERATION_COMPLETE,
		{"operation_id": _operation_id, "report": {"mass_kg": 1250.0}},
	)


func _on_door_state(state: Dictionary, _action: String, _event: Dictionary) -> void:
	_door_open = bool(state.get("open", false))
	_target_door_x = 2.4 if _door_open else 0.0
	_update_hud()


func _on_world_event(event: Dictionary) -> void:
	var body := event.get("body", {}) as Dictionary
	_last_event = "%s  r%d  by %s" % [
		str(event.get("type", "event")),
		int(event.get("revision", 0)),
		str(event.get("actor_id", "authority")),
	]
	if str(event.get("type", "")) == WorldContracts.EVENT_PORT_OPERATION_STARTED:
		_operation_id = str(body.get("operation_id", _operation_id))
	if str(event.get("type", "")) in [WorldContracts.EVENT_PORT_OPERATION_COMPLETED, WorldContracts.EVENT_PORT_OPERATION_STOPPED]:
		_operation_id = ""
	_machine_lamp.light_color = Color(0.25, 1.0, 0.48) if not _operation_id.is_empty() else Color(1.0, 0.45, 0.16)
	_update_hud()


func _on_command_completed(_request_id: String, result: Dictionary) -> void:
	if not bool(result.get("ok", false)):
		_last_event = "REJECTED: %s" % str(result.get("message", "unknown"))
	_update_hud()


func _on_authority_error(code: String, message: String) -> void:
	_last_event = "%s: %s" % [code, message]
	_update_hud()


func _on_binding_rejected(code: String, message: String) -> void:
	_on_authority_error(code, message)


func _update_hud() -> void:
	if _status == null:
		return
	_status.text = "AUTHORITY  %s\nDOOR       %s  revision %d\nDOCK PUMP  %s" % [
		"LOCAL / SAME CONTRACT" if WorldGateway.is_ready() else "STARTING",
		"OPEN" if _door_open else "CLOSED",
		_door_binding.revision() if _door_binding != null else 0,
		"RUNNING  " + _operation_id if not _operation_id.is_empty() else "IDLE",
	]
	_event_log.text = "LAST FACT\n%s" % _last_event


func _build_scene() -> void:
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.025, 0.04, 0.055)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.22, 0.31, 0.38)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.environment = env
	add_child(environment)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, -28.0, 0.0)
	sun.light_color = Color(0.78, 0.88, 1.0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	add_child(sun)

	var camera := Camera3D.new()
	camera.position = Vector3(11.0, 8.0, 13.0)
	camera.look_at_from_position(camera.position, Vector3(0.0, 1.2, 0.0))
	add_child(camera)

	_add_box("Quay", Vector3(13.0, 0.35, 8.0), Vector3(0.0, -0.2, 0.0), Color(0.08, 0.095, 0.105))
	_add_box("Warehouse", Vector3(7.5, 4.5, 2.8), Vector3(-1.5, 2.15, -2.4), Color(0.23, 0.28, 0.3))
	_door_panel = _add_box("AuthorityDoor", Vector3(2.1, 2.9, 0.18), Vector3(0.0, 1.45, -0.92), Color(0.9, 0.34, 0.08))
	_add_box("PumpBase", Vector3(2.8, 0.3, 1.8), Vector3(3.5, 0.18, 1.0), Color(0.16, 0.18, 0.19))
	_add_box("PumpBody", Vector3(1.7, 1.35, 1.05), Vector3(3.5, 0.95, 1.0), Color(0.42, 0.5, 0.53))

	_machine_lamp = OmniLight3D.new()
	_machine_lamp.position = Vector3(3.5, 2.15, 1.0)
	_machine_lamp.light_color = Color(1.0, 0.45, 0.16)
	_machine_lamp.light_energy = 3.0
	_machine_lamp.omni_range = 4.0
	add_child(_machine_lamp)

	var canvas := CanvasLayer.new()
	add_child(canvas)
	var panel := ColorRect.new()
	panel.position = Vector2(28, 28)
	panel.size = Vector2(460, 260)
	panel.color = Color(0.018, 0.026, 0.034, 0.93)
	canvas.add_child(panel)
	var title := Label.new()
	title.position = Vector2(22, 18)
	title.text = "WORLD AUTHORITY LAB"
	title.add_theme_font_size_override("font_size", 24)
	panel.add_child(title)
	_status = Label.new()
	_status.position = Vector2(22, 58)
	_status.add_theme_color_override("font_color", Color(0.72, 0.9, 0.93))
	_status.add_theme_font_size_override("font_size", 15)
	panel.add_child(_status)
	_event_log = Label.new()
	_event_log.position = Vector2(22, 130)
	_event_log.add_theme_color_override("font_color", Color(1.0, 0.65, 0.3))
	panel.add_child(_event_log)
	var help := Label.new()
	help.position = Vector2(22, 205)
	help.text = "[1] DOOR   [2] START DOCK JOB   [3] COMPLETE   [4] REQUERY"
	help.add_theme_font_size_override("font_size", 12)
	panel.add_child(help)


func _add_box(label: String, size: Vector3, position: Vector3, color: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.82
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.name = label
	instance.mesh = mesh
	instance.position = position
	add_child(instance)
	return instance
