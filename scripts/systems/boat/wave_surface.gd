class_name WaveSurface
extends RefCounted

## Sea level — must match the ocean plane `y` (`WorldRenderer` / `_build_ocean`).
const WATER_LEVEL: float = -1.5

const WAVE_INTENSITY_MIN:  float = 0.0
const WAVE_INTENSITY_MAX:  float = 5.0
const WAVE_INTENSITY_STEP: float = 0.1

static var wave_intensity: float = 1.0
static var short_wave_factor: float = 0.0

static var _coupled_vessel: RigidBody3D = null
static var fft_system: Node = null

static func bump_wave_intensity(delta: float) -> void:
	set_wave_intensity(wave_intensity + delta)

static func set_wave_intensity(value: float) -> void:
	wave_intensity = clampf(value, 0.0, 5.0)

static func set_weather_short_wave_factor(wind: float, precip: float, storm: float) -> void:
	var x := clampf(precip, 0.0, 1.0)
	var y := clampf(wind, 0.0, 1.0)
	var storm_t := clampf(storm, 0.0, 1.0)
	var rainy_short := x * lerpf(1.0, 0.45, y)
	short_wave_factor = clampf(rainy_short * 0.78 + storm_t * 0.72, 0.0, 1.0)

static func get_wave_energy_multiplier() -> float:
	var t := get_sim_time()
	var gate := sin(t * 0.032) + sin(t * 0.011 + 1.7) * 0.22 - 0.72
	var rare := pow(clampf(gate * 1.9, 0.0, 1.0), 3.5)
	return 0.85 + rare * 0.6

static func set_coupled_vessel(body: RigidBody3D) -> void:
	_coupled_vessel = body

static func clear_coupled_vessel_if(body: RigidBody3D) -> void:
	if _coupled_vessel == body:
		_coupled_vessel = null

static func get_sim_time() -> float:
	return Time.get_ticks_msec() * 0.001

static func get_buoyancy_surface_height_at(x: float, z: float) -> float:
	if fft_system == null or fft_system.buoyancy_data.is_empty():
		return WATER_LEVEL
	
	var length_scale = fft_system.length_scales.x
	var res = 1024.0
	
	var u = fmod(x / length_scale, 1.0)
	var v = fmod(z / length_scale, 1.0)
	if u < 0.0: u += 1.0
	if v < 0.0: v += 1.0
	
	var px = int(u * res)
	var py = int(v * res)
	px = clamp(px, 0, int(res) - 1)
	py = clamp(py, 0, int(res) - 1)
	
	var idx = py * int(res) + px
	# Scale down the FFT raw height by 0.35 to match the visual shader's amp_scale tuning
	return WATER_LEVEL + fft_system.buoyancy_data[idx] * wave_intensity * get_wave_energy_multiplier() * 0.35

static func get_base_wave_height_at(x: float, z: float) -> float:
	return get_buoyancy_surface_height_at(x, z)

static func get_height_at(x: float, z: float) -> float:
	return get_buoyancy_surface_height_at(x, z) - _vessel_dip_at(x, z)

static func _hull_size_from_body(b: RigidBody3D) -> Vector3:
	var hs := Vector3(6.0, 2.0, 14.0)
	if "hull_size" in b:
		hs = b.get("hull_size")
	return hs

static func _vessel_displacement_params(b: RigidBody3D) -> Dictionary:
	var hs: Vector3 = _hull_size_from_body(b)
	var bx: float = b.global_position.x
	var bz: float = b.global_position.z
	var keel_y: float = b.global_position.y - hs.y * 0.5
	var surf_raw: float = get_base_wave_height_at(bx, bz)
	var immersion: float = clampf((surf_raw - keel_y) / maxf(hs.y, 0.01), 0.0, 2.8)
	var sx: float = maxf(hs.x * 0.62, 0.5)
	var sz: float = maxf(hs.z * 0.58, 0.5)
	var amp: float = 0.0
	if immersion > 0.0:
		var waterplane: float = hs.x * hs.z
		amp = immersion * (0.52 + 0.14 * sqrt(waterplane / 90.0))
		amp = minf(amp, 2.85)
	var vel_xz := Vector2(b.linear_velocity.x, b.linear_velocity.z)
	return {
		"amp": amp,
		"sx": sx,
		"sz": sz,
		"bx": bx,
		"bz": bz,
		"immersion": immersion,
		"vel_x": vel_xz.x,
		"vel_z": vel_xz.y
	}

static func get_vertical_velocity_at(x: float, z: float) -> float:
	# Velocity approximation is complex without retaining previous frame's grid.
	# For rigid body damping, 0 is acceptable as a baseline if we don't have true dy/dt.
	return 0.0

static func get_surface_gradient_xz(x: float, z: float) -> Vector2:
	var e = 1.0
	var h0 = get_buoyancy_surface_height_at(x - e, z)
	var h1 = get_buoyancy_surface_height_at(x + e, z)
	var h2 = get_buoyancy_surface_height_at(x, z - e)
	var h3 = get_buoyancy_surface_height_at(x, z + e)
	return Vector2((h1 - h0) / (2.0 * e), (h3 - h2) / (2.0 * e))

static func get_surface_normal_at(x: float, z: float) -> Vector3:
	var g: Vector2 = get_surface_gradient_xz(x, z)
	return Vector3(-g.x, 1.0, -g.y).normalized()

static func sync_ocean_coupling_to_shader(mat: ShaderMaterial) -> void:
	if mat == null:
		return
	if _coupled_vessel == null or not is_instance_valid(_coupled_vessel):
		mat.set_shader_parameter("boat_coupling", Vector4(0.0, 0.0, 0.0, 0.0))
		mat.set_shader_parameter("boat_coupling_axes", Vector2.ONE)
		mat.set_shader_parameter("boat_velocity", Vector2.ZERO)
		return
	var p: Dictionary = _vessel_displacement_params(_coupled_vessel)
	if p["immersion"] <= 0.0:
		mat.set_shader_parameter("boat_coupling", Vector4(p["bx"], p["bz"], 0.0, 0.0))
		mat.set_shader_parameter("boat_coupling_axes", Vector2(p["sx"], p["sz"]))
		mat.set_shader_parameter("boat_velocity", Vector2(p["vel_x"], p["vel_z"]))
		return
	mat.set_shader_parameter("boat_coupling", Vector4(p["bx"], p["bz"], p["amp"], 0.0))
	mat.set_shader_parameter("boat_coupling_axes", Vector2(p["sx"], p["sz"]))
	mat.set_shader_parameter("boat_velocity", Vector2(p["vel_x"], p["vel_z"]))

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
