class_name AutonomousSimDebug
extends RefCounted

## Debug-only time multiplier for autonomous fleet sim (F3 panel: O slower · I faster).

const SPEED_STEPS: Array[float] = [1.0, 2.0, 5.0, 10.0, 25.0]

static var time_scale: float = 1.0


static func scaled_elapsed(active_at: int) -> float:
	if active_at <= 0:
		return 0.0
	var wall := maxf(0.0, AutonomousVesselSim.now_seconds() - float(active_at))
	return wall * maxf(time_scale, 0.0)


static func adjust_speed(step_delta: int) -> float:
	if SPEED_STEPS.is_empty():
		return time_scale
	var idx := SPEED_STEPS.find(time_scale)
	if idx < 0:
		idx = 0
	idx = clampi(idx + step_delta, 0, SPEED_STEPS.size() - 1)
	time_scale = SPEED_STEPS[idx]
	return time_scale


static func label() -> String:
	var scale := maxf(time_scale, 0.0)
	if scale <= 1.001:
		return "1×"
	if absf(scale - floorf(scale)) < 0.001:
		return "%d×" % int(scale)
	return "%.1f×" % scale
