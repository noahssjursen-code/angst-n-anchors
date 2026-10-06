class_name WaveSurface
extends RefCounted

## Sea level — must match the ocean plane `y` (`WorldRenderer` / `_build_ocean`).
const WATER_LEVEL: float = -1.5

const WAVE_INTENSITY_MIN:  float = 0.0
const WAVE_INTENSITY_MAX:  float = 5.0
const WAVE_INTENSITY_STEP: float = 0.1
const MAX_EXTRAPOLATION_SECONDS: float = 0.12
const STALE_AFTER_SECONDS: float = 0.20

static var wave_intensity: float = 1.0
static var short_wave_factor: float = 0.0

static var _coupled_vessel: RigidBody3D = null
static var fft_system: Node = null
static var _sample_cache_frame: int = -1
static var _sample_cache: Dictionary = {}

## The requested setting remains editable; rendering and queries share the
## same gradually applied amplitude, owned by the running FFT simulation.
static func get_applied_wave_intensity() -> float:
	if is_instance_valid(fft_system) and "applied_wave_intensity" in fft_system:
		return float(fft_system.applied_wave_intensity)
	return wave_intensity

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

## Cached per-millisecond — the function is sampled multiple times per
## physics frame (once per buoyancy point, once per vertical-velocity
## query), and the value only depends on Time.get_ticks_msec(). At 9
## buoyancy samples × 2 calls per frame this was running 2 sin + pow +
## clampf 18× per physics tick.
static var _wem_cache_tick:  int   = -1
static var _wem_cache_value: float = 0.85

static func get_wave_energy_multiplier() -> float:
	var tick := Time.get_ticks_msec()
	if tick == _wem_cache_tick:
		return _wem_cache_value
	var t := tick * 0.001
	var gate := sin(t * 0.032) + sin(t * 0.011 + 1.7) * 0.22 - 0.72
	var rare := pow(clampf(gate * 1.9, 0.0, 1.0), 3.5)
	_wem_cache_value = 0.85 + rare * 0.6
	_wem_cache_tick  = tick
	return _wem_cache_value

static func set_coupled_vessel(body: RigidBody3D) -> void:
	# Compatibility registration: first valid vessel wins until the local
	# controller explicitly selects one. This removes last-writer-wins.
	if _coupled_vessel == null or not is_instance_valid(_coupled_vessel):
		_coupled_vessel = body


static func set_local_visual_vessel(body: RigidBody3D) -> void:
	_coupled_vessel = body


static func is_local_visual_vessel(body: RigidBody3D) -> bool:
	return (
		body != null
		and _coupled_vessel == body
		and is_instance_valid(_coupled_vessel)
	)

static func clear_coupled_vessel_if(body: RigidBody3D) -> void:
	if _coupled_vessel == body:
		_coupled_vessel = null

static func get_sim_time() -> float:
	return Time.get_ticks_msec() * 0.001


static func clear_sample_cache() -> void:
	_sample_cache.clear()
	_sample_cache_frame = -1

static func get_buoyancy_surface_height_at(x: float, z: float) -> float:
	return sample_at(x, z).height

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
	var keel_local_y := -hs.y * 0.5
	if "hull_stations" in b:
		var stations := b.get("hull_stations") as HullStations
		if stations != null:
			keel_local_y = stations.keel_y
	var keel_y: float = b.to_global(Vector3(0.0, keel_local_y, 0.0)).y
	var surf_raw: float = get_base_wave_height_at(bx, bz)
	
	var right := b.global_transform.basis.x
	var fwd := b.global_transform.basis.z

	# The absolute depth the keel is submerged under the wave
	var depth_below_surface: float = maxf(surf_raw - keel_y, 0.0)

	## Actual half-extents for a steep hull-footprint cutout. The previous
	## Mexican-hat ellipse formed a visible sloped moat between water and hull.
	## Keep the cutout comfortably inside the rendered shell. Water should meet
	## the hull, not reveal the anti-fouling surface through a hull-sized hole.
	var sx: float = maxf(hs.x * 0.30, 0.5)
	var sz: float = maxf(hs.z * 0.30, 0.5)
	var bow_frac := 0.0
	if "physics_profile" in b:
		var profile := b.get("physics_profile") as HullPhysicsProfile
		if profile != null:
			bow_frac = clampf(profile.bow_taper_fraction, 0.0, 0.45)
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
		"fwd_z": fwd.z,
		"bow_frac": bow_frac,
	}

static func get_vertical_velocity_at(x: float, z: float) -> float:
	return sample_at(x, z).velocity.y

static func get_surface_gradient_xz(x: float, z: float) -> Vector2:
	return sample_at(x, z).gradient_xz

static func get_surface_normal_at(x: float, z: float) -> Vector3:
	return sample_at(x, z).normal


static func sample_at(x: float, z: float) -> WaterSample:
	var frame := Engine.get_physics_frames()
	if frame != _sample_cache_frame:
		_sample_cache_frame = frame
		_sample_cache.clear()
	var cache_key := Vector2i(roundi(x * 10.0), roundi(z * 10.0))
	if _sample_cache.has(cache_key):
		return _sample_cache[cache_key] as WaterSample
	var sample := WaterSample.flat()
	sample.shelter = LandField.sample_baked_shelter(Vector3(x, 0.0, z))
	if (
		fft_system == null
		or not "physics_query_data" in fft_system
		or fft_system.physics_query_data.size() < 4
		or fft_system.physics_query_data[0].is_empty()
	):
		_sample_cache[cache_key] = sample
		return sample

	var raw := _sample_query_raw(x, z)
	var scale := get_applied_wave_intensity() * get_wave_energy_multiplier() * 0.42 * sample.shelter
	sample.height = WATER_LEVEL + raw.x * scale
	sample.velocity = Vector3(raw.y, raw.z, raw.w) * scale
	# Height changes with both the FFT and the weather amplitude.
	if "wave_intensity_velocity" in fft_system:
		sample.velocity.y += raw.x * float(fft_system.wave_intensity_velocity) * get_wave_energy_multiplier() * 0.42 * sample.shelter
	sample.snapshot_time = float(fft_system.physics_query_snapshot_time)
	sample.age_seconds = float(fft_system.get_physics_query_age_seconds())
	sample.stale = sample.age_seconds > STALE_AFTER_SECONDS
	sample.valid = true
	if not sample.stale:
		sample.height += sample.velocity.y * minf(
			sample.age_seconds, MAX_EXTRAPOLATION_SECONDS
		)
	else:
		sample.velocity = Vector3.ZERO

	var e := 1.0
	var left := _sample_query_raw(x - e, z).x
	var right := _sample_query_raw(x + e, z).x
	var back := _sample_query_raw(x, z - e).x
	var forward := _sample_query_raw(x, z + e).x
	sample.gradient_xz = Vector2(
		(right - left) * 0.5 * scale,
		(forward - back) * 0.5 * scale
	)
	sample.normal = Vector3(
		-sample.gradient_xz.x, 1.0, -sample.gradient_xz.y
	).normalized()
	_sample_cache[cache_key] = sample
	return sample


static func _sample_query_raw(x: float, z: float) -> Vector4:
	var total := Vector4.ZERO
	var resolution := FFTWaterSystem.PHYSICS_QUERY_RESOLUTION
	for cascade in range(4):
		var length_scale := float(fft_system.length_scales[cascade])
		var u := fposmod(x / length_scale, 1.0)
		var v := fposmod(z / length_scale, 1.0)
		total += _bilinear_query_layer(
			fft_system.physics_query_data[cascade], resolution, u, v
		)
	return total


static func _bilinear_query_layer(
	data: PackedFloat32Array,
	resolution: int,
	u: float,
	v: float,
) -> Vector4:
	var px: float = u * float(resolution)
	var py: float = v * float(resolution)
	var x0 := int(floor(px)) % resolution
	var y0 := int(floor(py)) % resolution
	var x1 := (x0 + 1) % resolution
	var y1 := (y0 + 1) % resolution
	var fx: float = px - floor(px)
	var fy: float = py - floor(py)
	var a := _query_texel(data, resolution, x0, y0).lerp(
		_query_texel(data, resolution, x1, y0), fx
	)
	var b := _query_texel(data, resolution, x0, y1).lerp(
		_query_texel(data, resolution, x1, y1), fx
	)
	return a.lerp(b, fy)


static func _query_texel(
	data: PackedFloat32Array, resolution: int, x: int, y: int
) -> Vector4:
	var idx := (y * resolution + x) * 4
	return Vector4(data[idx], data[idx + 1], data[idx + 2], data[idx + 3])

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
	mat.set_shader_parameter("boat_coupling", Vector4(
		p["bx"], p["bz"], p["amp"], p["bow_frac"]
	))
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

	var edge := _hull_cut_edge(u, v, float(p.get("bow_frac", 0.0)))
	if edge >= 1.0:
		return 0.0
	return amp * (1.0 - smoothstep(0.82, 1.0, edge))


static func _hull_cut_edge(u: float, v: float, bow_frac: float) -> float:
	var width_factor := 1.0
	if bow_frac > 0.001:
		## Boat bow is local -Z. v=-1 is the stem; shoulder is the end of
		## the authored plan taper.
		var shoulder := -1.0 + bow_frac * 2.0
		if v < shoulder:
			width_factor = clampf((v + 1.0) / maxf(bow_frac * 2.0, 0.001), 0.04, 1.0)
	return maxf(absf(v), absf(u) / width_factor)
