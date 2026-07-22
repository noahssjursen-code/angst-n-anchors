class_name WalkAnimator
extends RefCounted

## Body-only procedural pose driver for the articulated character rig.
##
## The public name is retained while existing NPC callers migrate, but this is
## no longer a four-stick walk oscillator. Legs and arms are two-link chains.
## Their end targets are solved analytically every frame, giving planted feet,
## bending knees/elbows, and a single deterministic motion contract for NPCs,
## local players, and replicated players.

const CYCLES_PER_M := 0.72
const BLEND_RATE := 13.0

const IDLE := &"idle"
const WALK := &"walk"
const RUN := &"run"
const TURN_LEFT := &"turn_left"
const TURN_RIGHT := &"turn_right"
const CROUCH := &"crouch"
const JUMP := &"jump"
const WORK := &"work"
const WAVE := &"wave"

var _visual_root: Node3D
var _pelvis: Node3D
var _chest: Node3D
var _head: Node3D
var _arm_left: Node3D
var _arm_right: Node3D
var _forearm_left: Node3D
var _forearm_right: Node3D
var _hand_left: Node3D
var _hand_right: Node3D
var _leg_left: Node3D
var _leg_right: Node3D
var _shin_left: Node3D
var _shin_right: Node3D
var _foot_left: Node3D
var _foot_right: Node3D

var _pelvis_rest := Vector3.ZERO
var _chest_rest := Vector3.ZERO
var _head_rest := Vector3.ZERO
var _leg_upper_length := 0.41
var _leg_lower_length := 0.39
var _arm_upper_length := 0.30
var _arm_lower_length := 0.27
var _ready := false


func attach(npc: NpcBase) -> void:
	_ready = false
	if npc == null:
		return
	_visual_root = npc.visual
	_pelvis = npc.get_part("pelvis")
	_chest = npc.get_part("chest")
	_head = npc.get_part("head")
	_arm_left = npc.get_part("arm_left")
	_arm_right = npc.get_part("arm_right")
	_forearm_left = npc.get_part("forearm_left")
	_forearm_right = npc.get_part("forearm_right")
	_hand_left = npc.get_part("hand_left")
	_hand_right = npc.get_part("hand_right")
	_leg_left = npc.get_part("leg_left")
	_leg_right = npc.get_part("leg_right")
	_shin_left = npc.get_part("shin_left")
	_shin_right = npc.get_part("shin_right")
	_foot_left = npc.get_part("foot_left")
	_foot_right = npc.get_part("foot_right")
	_ready = _all_parts_valid()
	if not _ready:
		return
	_pelvis_rest = _pelvis.position
	_chest_rest = _chest.position
	_head_rest = _head.position
	_leg_upper_length = absf(_shin_left.position.y)
	_leg_lower_length = absf(_foot_left.position.y)
	_arm_upper_length = absf(_forearm_left.position.y)
	_arm_lower_length = absf(_hand_left.position.y)
	reset()


func is_ready() -> bool:
	return _ready and _all_parts_valid()


func apply_pose(state: StringName, phase: float, time_s: float, delta: float, snap := false) -> void:
	if not is_ready():
		return
	var blend := 1.0 if snap else 1.0 - exp(-BLEND_RATE * maxf(delta, 0.0001))
	var pelvis_offset := Vector3.ZERO
	var pelvis_rotation := Vector3.ZERO
	var chest_rotation := Vector3.ZERO
	var head_rotation := Vector3.ZERO
	var left_foot := Vector2(-(_leg_upper_length + _leg_lower_length - 0.004), 0.0)
	var right_foot := left_foot
	var left_foot_pitch := 0.0
	var right_foot_pitch := 0.0
	var left_leg_yaw := 0.0
	var right_leg_yaw := 0.0
	var left_foot_yaw := 0.0
	var right_foot_yaw := 0.0
	var left_hand := Vector2(-(_arm_upper_length + _arm_lower_length - 0.006), 0.0)
	var right_hand := left_hand

	match state:
		WALK:
			var bob := absf(sin(phase * 2.0)) * 0.011
			pelvis_offset.y = bob
			var left_cycle := phase
			var right_cycle := phase + PI
			left_foot = _gait_foot(left_cycle, 0.18, 0.055, pelvis_offset.y)
			right_foot = _gait_foot(right_cycle, 0.18, 0.055, pelvis_offset.y)
			left_foot_pitch = _gait_foot_pitch(left_cycle, 0.14)
			right_foot_pitch = _gait_foot_pitch(right_cycle, 0.14)
			left_hand = _swing_target(_arm_upper_length + _arm_lower_length - 0.018, sin(left_cycle) * 0.14)
			right_hand = _swing_target(_arm_upper_length + _arm_lower_length - 0.018, sin(right_cycle) * 0.14)
			pelvis_rotation.y = sin(phase) * 0.035
			pelvis_rotation.z = sin(phase) * 0.012
			chest_rotation = Vector3(-0.070, -sin(phase) * 0.075, -sin(phase) * 0.018)
			head_rotation.y = sin(phase) * 0.018
		RUN:
			var bob := absf(sin(phase * 2.0)) * 0.026
			pelvis_offset.y = bob
			var left_cycle := phase
			var right_cycle := phase + PI
			left_foot = _gait_foot(left_cycle, 0.27, 0.10, pelvis_offset.y)
			right_foot = _gait_foot(right_cycle, 0.27, 0.10, pelvis_offset.y)
			left_foot_pitch = _gait_foot_pitch(left_cycle, 0.23)
			right_foot_pitch = _gait_foot_pitch(right_cycle, 0.23)
			left_hand = _swing_target(_arm_upper_length + _arm_lower_length - 0.032, sin(left_cycle) * 0.215)
			right_hand = _swing_target(_arm_upper_length + _arm_lower_length - 0.032, sin(right_cycle) * 0.215)
			pelvis_rotation.y = sin(phase) * 0.055
			pelvis_rotation.z = sin(phase) * 0.020
			chest_rotation = Vector3(-0.180, -sin(phase) * 0.105, -sin(phase) * 0.026)
			head_rotation.x = 0.115
		TURN_LEFT, TURN_RIGHT:
			var direction := -1.0 if state == TURN_LEFT else 1.0
			var turn_amount := 0.40 + sin(time_s * 2.4) * 0.040
			pelvis_rotation.y = direction * turn_amount * 0.56
			chest_rotation.y = direction * turn_amount
			head_rotation.y = direction * 0.52
			left_foot.y = direction * 0.085
			right_foot.y = -direction * 0.085
			left_hand.y = direction * 0.055
			right_hand.y = -direction * 0.055
			left_leg_yaw = direction * 0.18
			right_leg_yaw = direction * 0.10
			left_foot_yaw = direction * 0.42
			right_foot_yaw = direction * 0.30
		CROUCH:
			pelvis_offset = Vector3(0.0, -0.23, 0.035)
			left_foot = Vector2(-(_leg_upper_length + _leg_lower_length - 0.23), -0.145)
			right_foot = Vector2(-(_leg_upper_length + _leg_lower_length - 0.23), 0.035)
			left_hand = Vector2(-0.34, -0.25)
			right_hand = Vector2(-0.34, -0.25)
			chest_rotation.x = -0.42
			head_rotation.x = 0.30
		JUMP:
			var jump_t := fposmod(phase, TAU)
			var height := maxf(0.0, sin(jump_t)) * 0.27
			pelvis_offset.y = height
			left_foot = Vector2(-0.47, -0.16)
			right_foot = Vector2(-0.55, 0.06)
			left_foot_pitch = 0.24
			right_foot_pitch = 0.14
			left_hand = Vector2(0.16, -0.17)
			right_hand = Vector2(0.16, -0.17)
			chest_rotation.x = -0.14
			head_rotation.x = 0.10
		WORK:
			var work_cycle := sin(time_s * 2.1)
			left_foot.y = -0.045
			right_foot.y = 0.045
			left_hand = Vector2(-0.37, -0.275 + work_cycle * 0.022)
			right_hand = Vector2(-0.37, -0.275 - work_cycle * 0.022)
			chest_rotation = Vector3(-0.15, work_cycle * 0.030, 0.0)
			head_rotation = Vector3(0.17, -work_cycle * 0.040, 0.0)
		WAVE:
			left_hand = Vector2(-0.525, 0.025)
			right_hand = Vector2(-0.035, -0.28 + sin(time_s * 4.5) * 0.045)
			chest_rotation.y = -0.08
			head_rotation.y = -0.14
		_:
			var breath := sin(time_s * 1.25)
			pelvis_offset.y = breath * 0.002
			chest_rotation = Vector3(breath * 0.006, sin(time_s * 0.41) * 0.009, breath * 0.003)
			head_rotation.y = sin(time_s * 0.34) * 0.018

	_lerp_position(_pelvis, _pelvis_rest + pelvis_offset, blend)
	_lerp_rotation(_pelvis, pelvis_rotation, blend)
	_lerp_position(_chest, _chest_rest, blend)
	_lerp_rotation(_chest, chest_rotation, blend)
	_lerp_position(_head, _head_rest, blend)
	_lerp_rotation(_head, head_rotation, blend)
	_solve_chain(_leg_left, _shin_left, _foot_left, _leg_upper_length, _leg_lower_length, left_foot, 1.0, left_foot_pitch, blend)
	_solve_chain(_leg_right, _shin_right, _foot_right, _leg_upper_length, _leg_lower_length, right_foot, 1.0, right_foot_pitch, blend)
	_solve_chain(_arm_left, _forearm_left, _hand_left, _arm_upper_length, _arm_lower_length, left_hand, -1.0, 0.0, blend)
	_solve_chain(_arm_right, _forearm_right, _hand_right, _arm_upper_length, _arm_lower_length, right_hand, -1.0, 0.0, blend)
	_leg_left.rotation.y = lerp_angle(_leg_left.rotation.y, left_leg_yaw, blend)
	_leg_right.rotation.y = lerp_angle(_leg_right.rotation.y, right_leg_yaw, blend)
	_foot_left.rotation.y = lerp_angle(_foot_left.rotation.y, left_foot_yaw, blend)
	_foot_right.rotation.y = lerp_angle(_foot_right.rotation.y, right_foot_yaw, blend)


func update(distance_walked_m: float) -> void:
	apply_pose(WALK, distance_walked_m * CYCLES_PER_M * TAU, 0.0, 1.0 / 60.0, true)


func update_idle(time_s: float) -> void:
	apply_pose(IDLE, 0.0, time_s, 1.0 / 60.0)


func reset() -> void:
	if not is_ready():
		return
	_pelvis.position = _pelvis_rest
	_chest.position = _chest_rest
	_head.position = _head_rest
	for part in [_pelvis, _chest, _head, _arm_left, _arm_right, _forearm_left, _forearm_right,
			_hand_left, _hand_right, _leg_left, _leg_right, _shin_left, _shin_right, _foot_left, _foot_right]:
		(part as Node3D).rotation = Vector3.ZERO
	if is_instance_valid(_visual_root):
		_visual_root.position = Vector3.ZERO


func _gait_foot(cycle: float, stride: float, lift: float, pelvis_y: float) -> Vector2:
	var travel := -sin(cycle) * stride
	# Lift only while the foot travels forward. Contact half stays level, giving
	# a readable planted phase instead of two permanently floating feet.
	var forward_velocity := maxf(0.0, cos(cycle))
	var height := sin(forward_velocity * PI * 0.5) * lift
	var standing_distance := _leg_upper_length + _leg_lower_length - 0.006
	var vertical_reach := sqrt(maxf(standing_distance * standing_distance - travel * travel, 0.001))
	return Vector2(-vertical_reach - pelvis_y + height, travel)


func _swing_target(reach: float, travel: float) -> Vector2:
	var vertical_reach := sqrt(maxf(reach * reach - travel * travel, 0.001))
	return Vector2(-vertical_reach, travel)


func _gait_foot_pitch(cycle: float, amount: float) -> float:
	# Toe rises during swing and settles level during the planted half-cycle.
	return maxf(0.0, cos(cycle)) * amount


func _solve_chain(upper: Node3D, lower: Node3D, end: Node3D, upper_length: float,
		lower_length: float, target: Vector2, bend_sign: float, end_pitch: float, blend: float) -> void:
	var distance := clampf(target.length(), absf(upper_length - lower_length) + 0.002, upper_length + lower_length - 0.002)
	var direction := atan2(-target.y, -target.x)
	var shoulder_offset := acos(clampf((upper_length * upper_length + distance * distance - lower_length * lower_length) / (2.0 * upper_length * distance), -1.0, 1.0))
	var inner := acos(clampf((upper_length * upper_length + lower_length * lower_length - distance * distance) / (2.0 * upper_length * lower_length), -1.0, 1.0))
	var joint_bend := PI - inner
	var upper_angle := direction + shoulder_offset * bend_sign
	var lower_angle := -joint_bend * bend_sign
	var end_angle := -(upper_angle + lower_angle) + end_pitch
	_lerp_rotation(upper, Vector3(upper_angle, 0.0, 0.0), blend)
	_lerp_rotation(lower, Vector3(lower_angle, 0.0, 0.0), blend)
	_lerp_rotation(end, Vector3(end_angle, 0.0, 0.0), blend)


func _lerp_position(node: Node3D, target: Vector3, weight: float) -> void:
	node.position = node.position.lerp(target, weight)


func _lerp_rotation(node: Node3D, target: Vector3, weight: float) -> void:
	node.rotation = Vector3(
		lerp_angle(node.rotation.x, target.x, weight),
		lerp_angle(node.rotation.y, target.y, weight),
		lerp_angle(node.rotation.z, target.z, weight)
	)


func _all_parts_valid() -> bool:
	for part in [_pelvis, _chest, _head, _arm_left, _arm_right, _forearm_left, _forearm_right,
			_hand_left, _hand_right, _leg_left, _leg_right, _shin_left, _shin_right, _foot_left, _foot_right]:
		if part == null or not is_instance_valid(part):
			return false
	return true
