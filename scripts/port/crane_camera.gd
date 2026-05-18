class_name CraneCamera
extends Camera3D

## Orbit camera that always frames the crane hook.
## - RMB hold + mouse move: orbit (yaw + pitch)
## - Scroll: zoom (distance)
## - Position is recomputed each frame from (target, yaw, pitch, distance).

## What the camera looks at. Usually the crane hook.
var target: Node3D = null

@export var distance: float = 14.0
@export var distance_min: float = 5.0
@export var distance_max: float = 32.0
@export var zoom_step: float = 1.4

@export var yaw_deg: float = 35.0
@export var pitch_deg: float = -38.0
@export var pitch_min_deg: float = -80.0
@export var pitch_max_deg: float = -5.0

@export var orbit_speed_deg: float = 0.25  # deg per pixel

var _orbiting: bool = false
var _enabled: bool = false


func set_enabled(on: bool) -> void:
	_enabled = on
	current = on
	if not on:
		_orbiting = false


func _process(_dt: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	_apply_transform()


func _unhandled_input(event: InputEvent) -> void:
	if not _enabled:
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		# LMB / RMB are reserved for the crane (hoist up / down) — orbit moved
		# to middle mouse button drag so it doesn't fight with hoist input.
		if mb.button_index == MOUSE_BUTTON_MIDDLE:
			_orbiting = mb.pressed
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			distance = clampf(distance - zoom_step, distance_min, distance_max)
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			distance = clampf(distance + zoom_step, distance_min, distance_max)
			get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseMotion and _orbiting:
		var m := event as InputEventMouseMotion
		yaw_deg = fposmod(yaw_deg - m.relative.x * orbit_speed_deg, 360.0)
		pitch_deg = clampf(pitch_deg - m.relative.y * orbit_speed_deg, pitch_min_deg, pitch_max_deg)
		get_viewport().set_input_as_handled()


func _apply_transform() -> void:
	var t := target.global_position
	var yaw := deg_to_rad(yaw_deg)
	var pitch := deg_to_rad(pitch_deg)

	# Spherical-to-Cartesian offset from target.
	var cp := cos(pitch)
	var offset := Vector3(
		distance * cp * sin(yaw),
		distance * -sin(pitch),
		distance * cp * cos(yaw),
	)
	global_position = t + offset
	look_at(t, Vector3.UP)
