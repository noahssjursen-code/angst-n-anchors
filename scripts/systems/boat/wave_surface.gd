class_name WaveSurface
extends RefCounted

## Global height query h(x, z, t) plus a **first-order hull coupling** term.
##
## A real ocean is not a single-valued sheet that ignores solids: the hull displaces
## fluid, reflects/scatters waves, and exchanges momentum. We still use an analytic
## heightfield (cheap), but subtract a **local depression** near the registered vessel
## so crests are partly "relieved" where the boat sits — same math in
## `resources/shaders/ocean_waves.gdshader` via uniforms.
##
## Limits: no true volume conservation, no Kelvin wake, no breaking — upgrade path is
## SWE/FFT ocean or GPU simulation when you need production fidelity.

## Sea level — must match the ocean plane y-position in starting_island.gd.
const WATER_LEVEL: float = -1.5

const AMPLITUDE_1  := 0.30
const FREQUENCY_1  := 0.18
const SPEED_1      := 0.75
const DIR_1        := Vector2(1.0, 0.6)

const AMPLITUDE_2  := 0.12
const FREQUENCY_2  := 0.26
const SPEED_2      := 1.1
const DIR_2        := Vector2(-0.5, 1.0)

## Runtime multiplier for both wave trains (visual + buoyancy).
## WeatherLighting drives this by default, but it can still be set directly for
## independent wave tuning/debugging.
const WAVE_INTENSITY_MIN:  float = 0.0
const WAVE_INTENSITY_MAX:  float = 5.0
const WAVE_INTENSITY_STEP: float = 0.1

static var wave_intensity: float = 1.0

## One rigid hull that perturbs the heightfield (starting island). Clear on exit_tree.
static var _coupled_vessel: RigidBody3D = null


static func bump_wave_intensity(delta: float) -> void:
	set_wave_intensity(wave_intensity + delta)


static func set_wave_intensity(value: float) -> void:
	wave_intensity = clampf(value, WAVE_INTENSITY_MIN, WAVE_INTENSITY_MAX)


static func set_coupled_vessel(body: RigidBody3D) -> void:
	_coupled_vessel = body


static func clear_coupled_vessel_if(body: RigidBody3D) -> void:
	if _coupled_vessel == body:
		_coupled_vessel = null


## Seconds since engine start — same clock as the ocean shader (set via uniform).
static func get_sim_time() -> float:
	return Time.get_ticks_msec() * 0.001


## Undisturbed travelling-wave surface at (x,z): raw η(x,z,t), no hull dip.
## Buoyancy samples this so upward force follows wave phase without fighting the
## displacement depression under the hull (fluid-like heave vs spring-mounted sheet).
static func get_buoyancy_surface_height_at(x: float, z: float) -> float:
	return _wave_height_at_xy(x, z)


## Raw travelling sine stack only (no hull dip). Alias of `get_buoyancy_surface_height_at`.
static func get_base_wave_height_at(x: float, z: float) -> float:
	return get_buoyancy_surface_height_at(x, z)


## Effective free surface **including** hull displacement dip (visual / debug).
## Buoyancy must NOT use this — it couples lift to the hull's own trough and feels
## like a rigid sheet.
## Use `get_buoyancy_surface_height_at()` for submerged depth instead.
static func get_height_at(x: float, z: float) -> float:
	return _wave_height_at_xy(x, z) - _vessel_dip_at(x, z)


static func _hull_size_from_body(b: RigidBody3D) -> Vector3:
	var hs := Vector3(6.0, 2.0, 14.0)
	if "hull_size" in b:
		hs = b.get("hull_size")
	return hs


## Shared Gaussian displacement under the coupled hull.
## Used by the visual surface and effective `get_height_at()` query.
static func _vessel_displacement_params(b: RigidBody3D) -> Dictionary:
	var hs: Vector3 = _hull_size_from_body(b)
	var bx: float = b.global_position.x
	var bz: float = b.global_position.z
	var keel_y: float = b.global_position.y - hs.y * 0.5
	var surf_raw: float = _wave_height_at_xy(bx, bz)
	var immersion: float = clampf((surf_raw - keel_y) / maxf(hs.y, 0.01), 0.0, 2.8)
	var sx: float = maxf(hs.x * 0.62, 0.5)
	var sz: float = maxf(hs.z * 0.58, 0.5)
	var amp: float = 0.0
	if immersion > 0.0:
		var waterplane: float = hs.x * hs.z
		amp = immersion * (0.52 + 0.14 * sqrt(waterplane / 90.0))
		amp = minf(amp, 2.85)
	return {
		"amp": amp,
		"sx": sx,
		"sz": sz,
		"bx": bx,
		"bz": bz,
		"immersion": immersion,
	}


## ∂h_wave/∂t — wave part only; hull dip motion is ignored (slow vs wave frequency).
static func get_vertical_velocity_at(x: float, z: float) -> float:
	var t: float = get_sim_time()
	var d1: Vector2 = DIR_1.normalized()
	var d2: Vector2 = DIR_2.normalized()
	var a1: float = AMPLITUDE_1 * wave_intensity
	var a2: float = AMPLITUDE_2 * wave_intensity
	var ph1: float = (x * d1.x + z * d1.y) * FREQUENCY_1 + t * SPEED_1
	var ph2: float = (x * d2.x + z * d2.y) * FREQUENCY_2 + t * SPEED_2
	return cos(ph1) * SPEED_1 * a1 + cos(ph2) * SPEED_2 * a2


## ∂η/∂x and ∂η/∂z for the wave part (no hull dip). Used for surface normal & flow hints.
static func get_surface_gradient_xz(x: float, z: float) -> Vector2:
	var t: float = get_sim_time()
	var d1: Vector2 = DIR_1.normalized()
	var d2: Vector2 = DIR_2.normalized()
	var a1: float = AMPLITUDE_1 * wave_intensity
	var a2: float = AMPLITUDE_2 * wave_intensity
	var ph1: float = (x * d1.x + z * d1.y) * FREQUENCY_1 + t * SPEED_1
	var ph2: float = (x * d2.x + z * d2.y) * FREQUENCY_2 + t * SPEED_2
	var gx: float = cos(ph1) * a1 * FREQUENCY_1 * d1.x + cos(ph2) * a2 * FREQUENCY_2 * d2.x
	var gz: float = cos(ph1) * a1 * FREQUENCY_1 * d1.y + cos(ph2) * a2 * FREQUENCY_2 * d2.y
	return Vector2(gx, gz)


## Unit "up" of the free surface (small-slope normal from wave heightfield).
static func get_surface_normal_at(x: float, z: float) -> Vector3:
	var g: Vector2 = get_surface_gradient_xz(x, z)
	return Vector3(-g.x, 1.0, -g.y).normalized()


## Push hull dip uniforms so the ocean vertex shader matches `get_height_at()`.
static func sync_ocean_coupling_to_shader(mat: ShaderMaterial) -> void:
	if mat == null:
		return
	if _coupled_vessel == null or not is_instance_valid(_coupled_vessel):
		mat.set_shader_parameter("boat_coupling", Vector4(0.0, 0.0, 0.0, 0.0))
		mat.set_shader_parameter("boat_coupling_axes", Vector2.ONE)
		return
	var p: Dictionary = _vessel_displacement_params(_coupled_vessel)
	if p["immersion"] <= 0.0:
		mat.set_shader_parameter("boat_coupling", Vector4(p["bx"], p["bz"], 0.0, 0.0))
		mat.set_shader_parameter("boat_coupling_axes", Vector2(p["sx"], p["sz"]))
		return
	mat.set_shader_parameter("boat_coupling", Vector4(p["bx"], p["bz"], p["amp"], 0.0))
	mat.set_shader_parameter("boat_coupling_axes", Vector2(p["sx"], p["sz"]))


static func _wave_height_at_xy(x: float, z: float) -> float:
	var t: float = get_sim_time()
	var d1: Vector2 = DIR_1.normalized()
	var d2: Vector2 = DIR_2.normalized()
	var a1: float = AMPLITUDE_1 * wave_intensity
	var a2: float = AMPLITUDE_2 * wave_intensity
	var wave1: float = sin((x * d1.x + z * d1.y) * FREQUENCY_1 + t * SPEED_1) * a1
	var wave2: float = sin((x * d2.x + z * d2.y) * FREQUENCY_2 + t * SPEED_2) * a2
	return WATER_LEVEL + wave1 + wave2


static func _vessel_dip_at(x: float, z: float) -> float:
	if _coupled_vessel == null or not is_instance_valid(_coupled_vessel):
		return 0.0
	var p: Dictionary = _vessel_displacement_params(_coupled_vessel)
	var amp: float = p["amp"]
	if amp <= 0.0:
		return 0.0
	var sx: float = p["sx"]
	var sz: float = p["sz"]
	var u: float = (x - p["bx"]) / sx
	var v: float = (z - p["bz"]) / sz
	var dist2: float = u * u + v * v
	if dist2 > 22.0:
		return 0.0
	return amp * exp(-0.5 * dist2)
