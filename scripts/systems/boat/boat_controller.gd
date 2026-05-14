@tool
class_name BoatController
extends Node

## Routes player input to the boat's components when seated at the helm.
## Activate/deactivate is called by CaptainsChair when the player boards or exits.
##
## Input mapping:
##   Throttle stage — W / S (move_forward / move_back) increments / decrements stage
##   Direct stage set — number keys 1..5 (astern..full ahead)
##   Rudder   — A / D  (move_left / move_right)
##   Thruster mode cycle — T (boat_docking_thrusters): Off → Bow-only → Crab → Off
##     Bow-only: Q/R yaw the bow (useful for swinging the bow at low speed)
##     Crab: Q/R pure lateral drift (bow + stern together)

@export var throttle_response: float = 1.8   # how fast throttle ramps (units/s)
@export var rudder_response:   float = 3.0
## Ordered throttle table. Index is the helm stage.
## Default stages:
## 0 full astern, 1 stop, 2 dead slow, 3 half, 4 full ahead.
@export var throttle_stage_values: PackedFloat32Array = PackedFloat32Array([
	-0.55, 0.0, 0.28, 0.56, 1.0
])
@export var stage_label_astem: String = "ASTERN"
@export var stage_label_stop: String = "STOP"
@export var stage_label_ahead: String = "AHEAD"

var _active: bool = false

## 0 = off, 1 = bow-only (yaw), 2 = crab (lateral drift)
var _thruster_mode: int = 0

var _throttle: float = 0.0
var _rudder:   float = 0.0
var _lateral:  float = 0.0
var _throttle_stage_idx: int = 1

@onready var _propulsion:    PropulsionComponent  = get_node_or_null("../PropulsionComponent")
@onready var _rudder_comp:   RudderComponent      = get_node_or_null("../RudderComponent")
@onready var _bow_thruster:  BowThrusterComponent = get_node_or_null("../BowThrusterComponent")
@onready var _boat_body: RigidBody3D = get_parent() as RigidBody3D

var _hud_layer: CanvasLayer
var _hud_label: Label


func activate() -> void:
	_active = true
	_ensure_hud()
	_set_hud_visible(true)


func deactivate() -> void:
	_active         = false
	_thruster_mode  = 0
	_throttle       = 0.0
	_rudder         = 0.0
	_lateral        = 0.0
	_throttle_stage_idx = _nearest_stage_idx(0.0)
	_push_to_components()
	_set_hud_visible(false)


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or not _active:
		return

	# Positive throttle = thrust along -body Z (Godot forward). JSON hulls are
	# authored with bow at +Z, so invert so W (move_forward) matches visual bow.
	if Input.is_action_just_pressed("boat_docking_thrusters"):
		_thruster_mode = (_thruster_mode + 1) % 3

	if Input.is_action_just_pressed("move_forward"):
		_step_throttle_stage(1)
	elif Input.is_action_just_pressed("move_back"):
		_step_throttle_stage(-1)

	# Boat mesh is authored with bow at +Z while propulsion uses Godot forward (-Z),
	# so invert stage command before sending to engine.
	var throttle_target: float = -_target_throttle_from_stage()
	var rudder_target:   float = Input.get_axis("move_left", "move_right")

	var lateral_target: float = 0.0
	if _thruster_mode > 0:
		lateral_target = Input.get_axis("boat_thrust_left", "boat_thrust_right")

	# Throttle and rudder ramp smoothly; crab thrust is immediate
	_throttle = move_toward(_throttle, throttle_target, throttle_response * delta)
	_rudder   = move_toward(_rudder,   rudder_target,   rudder_response   * delta)
	_lateral  = lateral_target

	_push_to_components()
	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint() or not _active:
		return
	if not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return

	match key_event.keycode:
		KEY_1:
			_set_stage_from_percent(0.0)
		KEY_2:
			_set_stage_from_percent(0.25)
		KEY_3:
			_set_stage_from_percent(0.5)
		KEY_4:
			_set_stage_from_percent(0.75)
		KEY_5:
			_set_stage_from_percent(1.0)
		KEY_X:
			_set_stage_stop()
		_:
			return
	get_viewport().set_input_as_handled()


func _push_to_components() -> void:
	if _propulsion   != null: _propulsion.throttle       = _throttle
	if _rudder_comp  != null: _rudder_comp.rudder_input  = _rudder
	if _bow_thruster != null:
		_bow_thruster.lateral_input = _lateral
		_bow_thruster.crab_mode = (_thruster_mode == 2)


func _step_throttle_stage(step: int) -> void:
	_throttle_stage_idx = clampi(_throttle_stage_idx + step, 0, _stage_count() - 1)


func _set_stage_stop() -> void:
	_throttle_stage_idx = _nearest_stage_idx(0.0)


func _set_stage_from_percent(percent: float) -> void:
	var pct := clampf(percent, 0.0, 1.0)
	var target := lerpf(0.0, 1.0, pct)
	var best_idx := _nearest_stage_idx(target)
	_throttle_stage_idx = best_idx


func _stage_count() -> int:
	return maxi(throttle_stage_values.size(), 2)


func _target_throttle_from_stage() -> float:
	if throttle_stage_values.is_empty():
		return 0.0
	var idx := clampi(_throttle_stage_idx, 0, throttle_stage_values.size() - 1)
	return clampf(throttle_stage_values[idx], -1.0, 1.0)


func _nearest_stage_idx(value: float) -> int:
	if throttle_stage_values.is_empty():
		return 0
	var best_idx := 0
	var best_err := INF
	for i in range(throttle_stage_values.size()):
		var err := absf(throttle_stage_values[i] - value)
		if err < best_err:
			best_err = err
			best_idx = i
	return best_idx


func _ensure_hud() -> void:
	if _hud_layer != null and is_instance_valid(_hud_layer):
		return
	_hud_layer = CanvasLayer.new()
	_hud_layer.name = "BoatHelmHUD"
	add_child(_hud_layer)

	_hud_label = Label.new()
	_hud_label.name = "Status"
	_hud_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_hud_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_hud_label.add_theme_font_size_override("font_size", 22)
	_hud_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_hud_label.offset_left = 20.0
	_hud_label.offset_top = 20.0
	_hud_label.offset_right = 620.0
	_hud_label.offset_bottom = 200.0
	_hud_layer.add_child(_hud_label)


func _set_hud_visible(on: bool) -> void:
	if _hud_layer != null:
		_hud_layer.visible = on


func _update_hud() -> void:
	if _hud_label == null:
		return
	var speed_mps := 0.0
	if _boat_body != null:
		speed_mps = _boat_body.linear_velocity.length()
	var speed_knots := speed_mps * 1.943844
	var stage_name := _throttle_stage_label(_target_throttle_from_stage())
	var stage_count := _stage_count()
	var thruster_str := (["", "  |  BOW", "  |  CRAB"] as Array)[_thruster_mode] as String
	_hud_label.text = (
		"Speed: %.1f kn\nThrottle: %s (%d/%d)%s\nSet: 1-5 | W/S step | X stop | T thruster"
		% [
			speed_knots,
			stage_name,
			_throttle_stage_idx + 1,
			stage_count,
			thruster_str,
		]
	)


func _throttle_stage_label(value: float) -> String:
	if value < -0.05:
		return stage_label_astem
	if value > 0.05:
		return stage_label_ahead
	return stage_label_stop
