extends SceneTree

## Presentation contract for the shared world lighting grade. This builds only
## the environment/lights, avoiding the FFT ocean in command-line validation.

const WORLD_RENDERER := preload("res://scripts/world/world_renderer.gd")

var _failures := PackedStringArray()


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var renderer := WORLD_RENDERER.new()
	renderer.enable_ocean_system = false
	root.add_child(renderer)
	await process_frame

	# Clear daylight: strong color separation, no paid volumetric pass.
	_apply_state(renderer, 0.50, 0.05, 0.0, 1.0, 0.0)
	var clear := renderer.get_lighting_debug_state()
	_check(float(clear["tonemap_exposure"]) <= 1.03, "day exposure preserves highlights")
	_check(float(clear["adjustment_contrast"]) >= 1.04, "grade has useful contrast")
	_check(float(clear["ambient_energy"]) >= 0.30, "day shadow detail remains readable")
	_check(float(clear["adjustment_saturation"]) >= 1.0, "grade preserves paint color")
	_check(float(clear["glow_intensity"]) < 0.5, "glow is restrained")
	_check(not bool(clear["volumetric_fog_enabled"]), "clear day skips volumetric fog")

	# Ordinary rain/haze must retain a readable foreground and remain cheap.
	_apply_state(renderer, 0.50, 0.72, 0.62, 0.76, 0.15)
	var rain := renderer.get_lighting_debug_state()
	_check(float(rain["fog_density"]) < 0.001, "rain haze does not bleach foreground")
	_check(not bool(rain["volumetric_fog_enabled"]), "ordinary rain skips volumetric fog")

	# Only genuinely poor visibility enables froxel fog.
	_apply_state(renderer, 0.20, 0.88, 0.75, 0.35, 0.72)
	var dense := renderer.get_lighting_debug_state()
	_check(bool(dense["volumetric_fog_enabled"]), "dense fog enables volumetric pass")
	_check(float(dense["volumetric_fog_density"]) < 0.012, "dense fog remains translucent")
	_check(float(dense["tonemap_exposure"]) <= 1.15, "fog does not lift whole frame")

	# Night remains navigable without becoming grey daylight.
	_apply_state(renderer, 0.0, 0.25, 0.0, 1.0, 0.0)
	var night := renderer.get_lighting_debug_state()
	_check(float(night["tonemap_exposure"]) <= 1.15, "night exposure is bounded")
	_check(float(night["ambient_energy"]) >= 0.09, "night silhouettes remain readable")

	renderer.queue_free()
	_finish()


func _apply_state(
		renderer: Node,
		time: float,
		cloud: float,
		rain: float,
		visibility: float,
		storm: float,
) -> void:
	var solar := SolarCycle.sample(time)
	var daylight := float(solar["daylight"])
	var direct_light := float(solar["direct_light"])
	var fog_t := 1.0 - visibility
	renderer.call("_apply_sun", solar, daylight, direct_light, cloud, storm)
	renderer.call("_apply_exposure", daylight, cloud, storm, fog_t)
	renderer.call("_apply_fog", solar, fog_t, daylight, cloud, storm)


func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures.append(label)


func _finish() -> void:
	if _failures.is_empty():
		print("WorldLightingGrade tests: all presentation checks passed")
		quit()
		return
	for failure in _failures:
		push_error("WorldLightingGrade test: " + failure)
	quit(1)
