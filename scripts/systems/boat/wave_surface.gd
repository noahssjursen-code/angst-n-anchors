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
	if fft_system == null or fft_system.buoyancy_data.size() < 4 or fft_system.buoyancy_data[0].is_empty():
		return WATER_LEVEL
	
	var h_total := 0.0
	for i in range(4):
		var length_scale = fft_system.length_scales[i]
		var res = 1024.0
		
		var u = fmod(x / length_scale, 1.0)
		var v = fmod(z / length_scale, 1.0)
		if u < 0.0: u += 1.0
		if v < 0.0: v += 1.0
		
		var px = clamp(int(u * res), 0, 1023)
		var py = clamp(int(v * res), 0, 1023)
		
		var idx = py * 1024 + px
		h_total += fft_system.buoyancy_data[i][idx]
	
	# Scale down the FFT raw height by 0.42 to match the visual shader's amp_scale tuning
	return WATER_LEVEL + h_total * wave_intensity * get_wave_energy_multiplier() * 0.42

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
	
	var right := b.global_transform.basis.x
	var fwd := b.global_transform.basis.z
	
	# The absolute depth the keel is submerged under the wave
	var depth_below_surface: float = maxf(surf_raw - keel_y, 0.0)
	
	# The Mexican Hat Wavelet crosses 0 dip at exactly D = 0.85.
	# By scaling sx and sz to 0.52, the edge of the physical boat (u = 0.5/0.52 = 0.96 => D = 0.85)
	# lands EXACTLY on the zero-crossing, creating a perfect airtight seal against the hull.
	var sx: float = maxf(hs.x * 0.52, 0.5)
	var sz: float = maxf(hs.z * 0.52, 0.5)
	var amp: float = 0.0
	
	if depth_below_surface > 0.0:
		# We MUST carve out the entire depth of the wave, plus a little extra (1.05x),
		# otherwise large waves will flood the deck because the hole isn't deep enough.
		amp = depth_below_surface * 1.05
		# The cap must be generous enough to handle storm waves cresting over the ship
		amp = minf(amp, hs.y * 3.8)
		
	var vel_xz := Vector2(b.linear_velocity.x, b.linear_velocity.z)
	return {
		"amp": amp,
		"sx": sx,
		"sz": sz,
		"bx": bx,
		"bz": bz,
		"immersion": depth_below_surface,
		"vel_x": vel_xz.x,
		"vel_z": vel_xz.y,
		"right_x": right.x,
		"right_z": right.z,
		"fwd_x": fwd.x,
		"fwd_z": fwd.z
	}

static func get_vertical_velocity_at(x: float, z: float) -> float:
	if fft_system == null or fft_system.buoyancy_data.size() < 4 or fft_system.prev_buoyancy_data.size() < 4 or fft_system.buoyancy_data[0].is_empty() or fft_system.prev_buoyancy_data[0].is_empty():
		return 0.0

	var dt = fft_system.prev_delta
	if dt <= 0.0001: return 0.0

	var h_now = 0.0
	var h_prev = 0.0
	for i in range(4):
		var length_scale = fft_system.length_scales[i]
		var res = 1024.0
		var u = fmod(x / length_scale, 1.0)
		var v = fmod(z / length_scale, 1.0)
		if u < 0.0: u += 1.0
		if v < 0.0: v += 1.0
		
		var px = clamp(int(u * res), 0, 1023)
		var py = clamp(int(v * res), 0, 1023)
		var idx = py * 1024 + px
		h_now += fft_system.buoyancy_data[i][idx]
		h_prev += fft_system.prev_buoyancy_data[i][idx]
	
	var dh = (h_now - h_prev) * wave_intensity * get_wave_energy_multiplier() * 0.42
	return dh / dt

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
		mat.set_shader_parameter("boat_basis", Vector4(p["right_x"], p["right_z"], p["fwd_x"], p["fwd_z"]))
		return
	mat.set_shader_parameter("boat_coupling", Vector4(p["bx"], p["bz"], p["amp"], 0.0))
	mat.set_shader_parameter("boat_coupling_axes", Vector2(p["sx"], p["sz"]))
	mat.set_shader_parameter("boat_velocity", Vector2(p["vel_x"], p["vel_z"]))
	mat.set_shader_parameter("boat_basis", Vector4(p["right_x"], p["right_z"], p["fwd_x"], p["fwd_z"]))

static func _vessel_dip_at(x: float, z: float) -> float:
	if _coupled_vessel == null or not is_instance_valid(_coupled_vessel):
		return 0.0
	var p: Dictionary = _vessel_displacement_params(_coupled_vessel)
	var amp: float = p["amp"]
	if amp <= 0.0:
		return 0.0
	var sx: float = p["sx"]
	var sz: float = p["sz"]
	
	var dx: float = x - p["bx"]
	var dz: float = z - p["bz"]
	
	var right_x: float = p["right_x"]
	var right_z: float = p["right_z"]
	var fwd_x: float = p["fwd_x"]
	var fwd_z: float = p["fwd_z"]
	
	var local_x: float = dx * right_x + dz * right_z
	var local_z: float = dx * fwd_x + dz * fwd_z
	
	var u: float = local_x / sx
	var v: float = local_z / sz
	
	var u2: float = u * u
	var v2: float = v * v
	var dist4: float = u2 * u2 + v2 * v2
	
	var D: float = dist4
	
	if D > 8.0:
		return 0.0
		
	var a: float = 1.8
	var b: float = 0.8
	var c: float = 0.5
	
	var exp_a: float = exp(-a * D)
	var exp_b: float = exp(-b * D)
	
	return amp * (exp_a - c * D * exp_b)
