class_name CharacterAnimator
extends Node

## Gameplay state selects Blender-authored clips on the shared imported rig.
var _state: StringName = &"idle"
var _actor: NpcBase
var _speed := 0.0
var _rate := 1.0
func bind(actor: NpcBase) -> void:
	_actor = actor
	refresh_rig()
func refresh_rig() -> void:
	if is_instance_valid(_actor) and _actor.visual != null:
		_actor.visual.play_motion(_state, _rate)
func set_locomotion(speed_m_s: float, delta: float) -> void:
	_speed = lerpf(_speed, maxf(0.0, speed_m_s), 1.0 - exp(-10.0 * maxf(delta, 0.0)))
	if _speed <= .15:
		_state = &"idle"
	else:
		var run_threshold := 1.9 if _state == &"run" else 2.3
		_state = &"run" if _speed > run_threshold else &"walk"
	# Nominal authored speeds: walk 1 m/s, run 3.75 m/s. Preserve game physics.
	_rate = 1.0 if _state == &"idle" else clampf(_speed / (3.75 if _state == &"run" else 1.0), .35, 2.3)
	refresh_rig()
func set_walk_distance(distance_m: float) -> void:
	_state = &"walk"
	if is_instance_valid(_actor) and _actor.visual != null:
		_actor.visual.set_walk_distance(distance_m)
func set_idle() -> void:
	_state = &"idle"
	_speed = 0.0
	_rate = 1.0
	refresh_rig()
func set_preview_motion(state: StringName) -> void:
	_state = state
	_rate = 1.0
	refresh_rig()
func set_preview_pose(state: StringName, _phase: float, _time_s := .8) -> void:
	_state = state
	refresh_rig()
func current_state() -> StringName:
	return _state
