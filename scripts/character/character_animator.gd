class_name CharacterAnimator
extends Node

## Shared animation state machine for body-only and decorated characters.
## Pose generation is deterministic; callers replicate state + phase rather
## than bone transforms. Preview mode exists for the body review showcase.

const WALK_CYCLES_PER_M := 0.72
const RUN_CYCLES_PER_M := 0.86

var _actor: NpcBase
var _driver := WalkAnimator.new()
var _state: StringName = WalkAnimator.IDLE
var _phase := 0.0
var _time_s := 0.0
var _preview_mode := false
var _preview_frozen := false


func bind(actor: NpcBase) -> void:
	_actor = actor
	_driver.attach(actor)


func refresh_rig() -> void:
	if _actor != null:
		_driver.attach(_actor)


func set_locomotion(speed_m_s: float, delta: float) -> void:
	_preview_mode = false
	_preview_frozen = false
	if speed_m_s <= 0.15:
		_state = WalkAnimator.IDLE
	else:
		_state = WalkAnimator.RUN if speed_m_s >= 3.2 else WalkAnimator.WALK
		var cycles := RUN_CYCLES_PER_M if _state == WalkAnimator.RUN else WALK_CYCLES_PER_M
		_phase += speed_m_s * delta * cycles * TAU
	_driver.apply_pose(_state, _phase, _time_s, delta)


func set_walk_distance(distance_m: float) -> void:
	_preview_mode = false
	_preview_frozen = false
	_state = WalkAnimator.WALK
	_phase = distance_m * WALK_CYCLES_PER_M * TAU
	_driver.apply_pose(_state, _phase, _time_s, 1.0 / 60.0)


func set_idle() -> void:
	_preview_mode = false
	_preview_frozen = false
	_state = WalkAnimator.IDLE


func set_preview_motion(state: StringName) -> void:
	_preview_mode = true
	_preview_frozen = false
	_state = state
	_phase = 0.0
	_driver.apply_pose(_state, _phase, _time_s, 0.0, true)


func set_preview_pose(state: StringName, phase: float, time_s := 0.8) -> void:
	_preview_mode = true
	_preview_frozen = true
	_state = state
	_phase = phase
	_time_s = time_s
	_driver.apply_pose(_state, _phase, _time_s, 0.0, true)


func current_state() -> StringName:
	return _state


func _process(delta: float) -> void:
	_time_s += delta
	if _preview_mode and not _preview_frozen:
		match _state:
			WalkAnimator.WALK: _phase += delta * 4.2
			WalkAnimator.RUN: _phase += delta * 7.0
			WalkAnimator.JUMP: _phase += delta * 3.0
	_driver.apply_pose(_state, _phase, _time_s, delta)
