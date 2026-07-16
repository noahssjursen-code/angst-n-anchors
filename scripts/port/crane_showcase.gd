@tool
class_name CraneShowcase
extends Node3D

## F6 inspect pad for harbour crane parts — one piece at a time.

const BULK_CRANE_SCRIPT := preload("res://scripts/port/bulk_crane.gd")

@export var orbit_yaw_deg := 35.0
@export var orbit_pitch_deg := -22.0
@export var orbit_distance := 52.0

var _crane: BulkCrane
var _camera: Camera3D
var _hud: Label
var _orbiting := false
var _orbit_yaw := 35.0
var _orbit_pitch := -22.0
var _focus_bucket := true
var _focus := Vector3(0.0, 4.0, -8.0)


func _ready() -> void:
	_orbit_yaw = orbit_yaw_deg
	_orbit_pitch = orbit_pitch_deg
	_ensure_environment()
	_ensure_camera()
	_ensure_hud()
	_ensure_pad()
	_ensure_scale_human()
	_spawn_crane()
	_focus_on_bucket()
	_update_camera()
	_refresh_hud()


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if _crane != null:
		_crane.playtest_input(delta)
		if _focus_bucket:
			_track_bucket_focus()
			_update_camera()
	_refresh_hud()


func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_HOME:
				_focus_bucket = false
				_orbit_yaw = orbit_yaw_deg
				_orbit_pitch = orbit_pitch_deg
				orbit_distance = 52.0
				_focus = Vector3(0.0, 4.0, -8.0)
				_update_camera()
			KEY_B:
				## Hard-focus the clamshell for bucket authoring.
				_focus_on_bucket()
				_update_camera()
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_orbiting = mb.pressed
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			orbit_distance = clampf(orbit_distance * 0.9, 3.0, 80.0)
			_update_camera()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			orbit_distance = clampf(orbit_distance * 1.1, 3.0, 80.0)
			_update_camera()
	if event is InputEventMouseMotion and _orbiting:
		var mm := event as InputEventMouseMotion
		_orbit_yaw -= mm.relative.x * 0.25
		_orbit_pitch = clampf(_orbit_pitch - mm.relative.y * 0.25, -80.0, 20.0)
		_update_camera()


func _focus_on_bucket() -> void:
	_focus_bucket = true
	orbit_distance = 9.0
	_orbit_yaw = 40.0
	_orbit_pitch = -18.0
	_track_bucket_focus()


func _track_bucket_focus() -> void:
	if _crane == null:
		return
	var bucket := _crane.get_bucket()
	if bucket == null or not is_instance_valid(bucket):
		_focus = Vector3(-1.5, 8.0, -18.0)
		return
	_focus = bucket.global_position + Vector3(0.0, -1.0, 0.0)


func _update_camera() -> void:
	if _camera == null:
		return
	var yaw := deg_to_rad(_orbit_yaw)
	var pitch := deg_to_rad(_orbit_pitch)
	var offset := Vector3(
		orbit_distance * cos(pitch) * sin(yaw),
		orbit_distance * sin(pitch) * -1.0,
		orbit_distance * cos(pitch) * cos(yaw),
	)
	_camera.global_position = _focus + offset
	_camera.look_at(_focus, Vector3.UP)


func _refresh_hud() -> void:
	if _hud == null:
		return
	var mode := "BUCKET FOCUS" if _focus_bucket else "crane overview"
	var lines: PackedStringArray = PackedStringArray([
		"CRANE SHOWCASE — %s" % mode,
		"B  bucket focus · Home  overview",
		"A D  slew · W S  boom · Q E  hoist · Space  jaws · RMB orbit",
		"",
	])
	if _crane != null:
		lines.append_array(_crane.get_status_lines())
	_hud.text = "\n".join(lines)


func _spawn_crane() -> void:
	if _crane != null and is_instance_valid(_crane):
		_crane.queue_free()
		_crane = null
	_crane = BULK_CRANE_SCRIPT.new() as BulkCrane
	_crane.name = "BulkCrane"
	add_child(_crane)
	_crane.position = Vector3.ZERO
	call_deferred("_pose_for_bucket_focus")


func _pose_for_bucket_focus() -> void:
	if _crane == null:
		return
	_crane.boom_angle_deg = 28.0
	_crane.hoist_length_m = 8.0
	_crane.bucket_open = 0.0
	_crane.set("_bucket_open_target", 0.0)


func _ensure_environment() -> void:
	if get_node_or_null("WorldEnvironment") != null:
		return
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.45, 0.62, 0.78)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.88, 0.95)
	env.ambient_light_energy = 0.55
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	sun.rotation_degrees = Vector3(-42.0, 35.0, 0.0)
	add_child(sun)


func _ensure_camera() -> void:
	_camera = get_node_or_null("Camera3D") as Camera3D
	if _camera == null:
		_camera = Camera3D.new()
		_camera.name = "Camera3D"
		add_child(_camera)
	_camera.current = true
	_camera.fov = 55.0


func _ensure_pad() -> void:
	if get_node_or_null("QuayPad") != null:
		return
	var pad := MeshInstance3D.new()
	pad.name = "QuayPad"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(16.0, 0.4, 16.0)
	pad.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.16, 0.16, 0.17)
	mat.roughness = 1.0
	pad.material_override = mat
	pad.position = Vector3(0.0, -0.2, 0.0)
	add_child(pad)


func _ensure_scale_human() -> void:
	if get_node_or_null("ScaleHuman") != null:
		return
	## Same 1.8 m NpcBase dummy as shipyard / F3+P scale probe.
	var human := NpcBase.new()
	human.name = "ScaleHuman"
	human.position = Vector3(2.2, 0.0, 0.8)
	add_child(human)
	var lbl := Label3D.new()
	lbl.name = "ScaleLabel"
	lbl.text = "1.8 m"
	lbl.font_size = 48
	lbl.pixel_size = 0.006
	lbl.position = Vector3(2.2, 2.15, 0.8)
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.modulate = Color(0.95, 0.8, 0.3)
	lbl.outline_size = 8
	add_child(lbl)


func _ensure_hud() -> void:
	if get_node_or_null("HUD") != null:
		_hud = get_node("HUD/Panel/Label") as Label
		return
	var layer := CanvasLayer.new()
	layer.name = "HUD"
	add_child(layer)
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.position = Vector2(16, 16)
	panel.custom_minimum_size = Vector2(360, 0)
	layer.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)
	_hud = Label.new()
	_hud.name = "Label"
	_hud.add_theme_font_size_override("font_size", 14)
	margin.add_child(_hud)
