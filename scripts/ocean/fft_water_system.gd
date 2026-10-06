class_name FFTWaterSystem
extends Node

## FFT grid size — must match SIZE / LOG_SIZE in the fft_ocean_*.glsl compute
## shaders. This is the full-quality setting used by the approved water look.
const RESOLUTION = 512
const RESOLUTION_LOG2 = 9  # log2(RESOLUTION)
const MAX_WAVES = 4
const PHYSICS_QUERY_RESOLUTION = 128

const FFT_OCEAN_INIT = preload("res://resources/shaders/fft_ocean_init.glsl")
const FFT_OCEAN_PACK = preload("res://resources/shaders/fft_ocean_pack.glsl")
const FFT_OCEAN_UPDATE = preload("res://resources/shaders/fft_ocean_update.glsl")
const FFT_OCEAN_FFT_X = preload("res://resources/shaders/fft_ocean_fft_x.glsl")
const FFT_OCEAN_FFT_Y = preload("res://resources/shaders/fft_ocean_fft_y.glsl")
const FFT_OCEAN_ASSEMBLE = preload("res://resources/shaders/fft_ocean_assemble.glsl")
const FFT_OCEAN_PHYSICS_QUERY = preload("res://resources/shaders/fft_ocean_physics_query.glsl")

## How many compute frames between buoyancy readback requests.
## Readback is async (non-blocking) — this only caps request rate.
const BUOYANCY_READBACK_INTERVAL: int = 2

var rd: RenderingDevice
var uniform_set: RID

var pipeline_init: RID
var pipeline_pack: RID
var pipeline_update: RID
var pipeline_fft_x: RID
var pipeline_fft_y: RID
var pipeline_assemble: RID
var pipeline_physics_query: RID
var main_shader: RID
var physics_query_shader: RID
var _shader_rids: Array[RID] = []

var target_spectrum_tex: RID
var _spectrum_initialized := false
var applied_wave_intensity := 1.0
var wave_intensity_velocity := 0.0
const SPECTRUM_RESPONSE_SECONDS := 1.5
var initial_spectrum_tex: RID
var spectrum_tex: RID
var displacement_tex: RID
var slope_tex: RID
var buoyancy_tex: RID
var physics_query_tex: RID
var physics_previous_tex: RID
var spectrums_buffer: RID

var displacement_map_rd: Texture2DArrayRD
var slope_map_rd: Texture2DArrayRD
var buoyancy_map_rd: Texture2DArrayRD

var time: float = 0.0
var _last_wind := -1.0
var _last_storm := -1.0
var _last_short_wave := -1.0
@export var length_scales := Vector4(256.0, 64.0, 16.0, 4.0)
@export var depth: float = 100.0
@export var repeat_time: float = 200.0
@export var low_cutoff: float = 0.0001
@export var high_cutoff: float = 9000.0

# Jacobian ~1.0 on flat water; < 1 means pinching (breaking crest).
# bias 1.0 + tiny threshold = foam only where waves actually break.
# (bias 2.0 made biasedJacobian ~1 EVERYWHERE -> uniform foam wash.)
@export var foam_bias: float = 1.0
@export var foam_decay_rate: float = 0.08
@export var foam_add: float = 1.0
@export var foam_threshold: float = 0.05
@export var lambda := Vector2(0.5, 0.5)

var push_constant_params := PackedByteArray()
## Four 128² RGBA32F layers: height and XYZ water velocity.
var physics_query_data: Array[PackedFloat32Array] = []
var physics_query_snapshot_time: float = -1.0
var physics_query_completed_usec: int = 0
var physics_query_source_usec: int = 0
## Counts compute frames since the last buoyancy readback request.
var _readback_counter: int = 0
## Async GPU→CPU buoyancy download — never call blocking texture_get_data
## on the render device (that stalls the whole GPU and pegs utilization).
var _readback_in_flight: bool = false
var _async_received: int = 0
var _async_scratch: Array[PackedFloat32Array] = []
var _async_time_snapshot: float = 0.0
var _async_source_usec: int = 0
var _physics_query_uniform_set: RID
var _physics_query_push := PackedByteArray()
var _physics_query_has_previous: bool = false
var _gpu_fft_ms: float = -1.0
var _cpu_submit_ms: float = 0.0

# Full temporal fidelity. GPU savings come from the frame cap, clipmap geometry,
# and non-blocking readback rather than reducing ocean simulation quality.
var _sim_timer: float = 0.0
const SIM_TICK_RATE: float = 60.0
const SIM_STEP: float = 1.0 / SIM_TICK_RATE

func _ready() -> void:
	applied_wave_intensity = WaveSurface.wave_intensity
	add_to_group("fft_water_system")
	var telemetry := get_node_or_null("/root/Telemetry")
	if telemetry != null and telemetry.has_method("register_provider"):
		telemetry.register_provider(&"ocean.fft", self, &"get_debug_stats", &"ocean", {
			"gpu_fft_ms": {"unit": "ms"},
			"cpu_submit_ms": {"unit": "ms"},
			"texture_mb": {"unit": "MB"},
			"readback_mb_s": {"unit": "MB/s"},
			"snapshot_age_ms": {"unit": "ms", "peak_mode": "latest"},
		})
	physics_query_data.resize(4)
	_async_scratch.resize(4)
	_physics_query_push.resize(16)
	push_constant_params.resize(80)
	rd = RenderingServer.get_rendering_device()
	if not rd:
		push_error("RenderingDevice not available")
		return
		
	_compile_shaders()
	_create_buffers_and_textures()
	_create_uniform_set()
	_init_spectrums()
	_run_init_pack()


func _exit_tree() -> void:
	var telemetry := get_node_or_null("/root/Telemetry")
	if telemetry != null and telemetry.has_method("unregister_provider"):
		telemetry.unregister_provider(&"ocean.fft", self)
	if rd == null:
		return
	if displacement_map_rd != null:
		displacement_map_rd.texture_rd_rid = RID()
	if slope_map_rd != null:
		slope_map_rd.texture_rd_rid = RID()
	if buoyancy_map_rd != null:
		buoyancy_map_rd.texture_rd_rid = RID()
	for rid in [uniform_set, _physics_query_uniform_set]:
		_free_rd_rid(rid)
	for rid in [
		pipeline_init,
		pipeline_pack,
		pipeline_update,
		pipeline_fft_x,
		pipeline_fft_y,
		pipeline_assemble,
		pipeline_physics_query,
	]:
		_free_rd_rid(rid)
	for rid in [
		target_spectrum_tex,
		initial_spectrum_tex,
		spectrum_tex,
		displacement_tex,
		slope_tex,
		buoyancy_tex,
		physics_query_tex,
		physics_previous_tex,
		spectrums_buffer,
	]:
		_free_rd_rid(rid)
	for rid in _shader_rids:
		_free_rd_rid(rid)
	_shader_rids.clear()


func _free_rd_rid(rid: RID) -> void:
	if rid.is_valid():
		rd.free_rid(rid)

func _process(delta: float) -> void:
	if not rd: return
	_collect_gpu_profile()
	
	_sim_timer += delta
	if _sim_timer < SIM_STEP:
		return
	
	var sim_delta = minf(_sim_timer, 0.1)
	_sim_timer = 0.0
	
	var previous_intensity := applied_wave_intensity
	applied_wave_intensity = lerpf(applied_wave_intensity, WaveSurface.wave_intensity, 1.0 - exp(-sim_delta / SPECTRUM_RESPONSE_SECONDS))
	wave_intensity_velocity = (applied_wave_intensity - previous_intensity) / sim_delta
	time += sim_delta
	_run_update_fft_assemble(sim_delta)

	_readback_counter += 1
	if _readback_counter >= BUOYANCY_READBACK_INTERVAL and not _readback_in_flight:
		_readback_counter = 0
		_kick_async_buoyancy_readback()


func _kick_async_buoyancy_readback() -> void:
	_readback_in_flight = true
	_async_received = 0
	_async_time_snapshot = time
	_async_source_usec = Time.get_ticks_usec()
	for i in range(4):
		var err := rd.texture_get_data_async(
			physics_query_tex, i, Callable(self, "_on_buoyancy_async").bind(i)
		)
		if err != OK:
			push_warning("FFTWaterSystem: async buoyancy readback failed (%s)" % error_string(err))
			_readback_in_flight = false
			return


func _on_buoyancy_async(bytes: PackedByteArray, layer: int) -> void:
	if bytes.size() == PHYSICS_QUERY_RESOLUTION * PHYSICS_QUERY_RESOLUTION * 16:
		_async_scratch[layer] = bytes.to_float32_array()
	_async_received += 1
	if _async_received < 4:
		return
	for i in range(4):
		if not _async_scratch[i].is_empty():
			physics_query_data[i] = _async_scratch[i]
	physics_query_snapshot_time = _async_time_snapshot
	physics_query_completed_usec = Time.get_ticks_usec()
	physics_query_source_usec = _async_source_usec
	_readback_in_flight = false


func get_debug_stats() -> Dictionary:
	var resolution_f := float(RESOLUTION)
	# Persistent GPU textures:
	# target/initial/displacement: 4×RGBA32F each; spectrum: 8×RGBA32F;
	# slope: 4×RG32F; buoyancy: 4×R32F.
	var texture_bytes := resolution_f * resolution_f * (
		8.0 * 16.0 + 8.0 * 16.0 + 4.0 * 16.0 + 4.0 * 8.0 + 4.0 * 4.0
	)
	var query_resolution_f := float(PHYSICS_QUERY_RESOLUTION)
	var readback_mb_s := (
		query_resolution_f * query_resolution_f * 16.0 * 4.0
		* (SIM_TICK_RATE / float(BUOYANCY_READBACK_INTERVAL))
		/ (1024.0 * 1024.0)
	)
	var tile_dispatches := 2 * (RESOLUTION / 8) * (RESOLUTION / 8)
	var fft_dispatches := 2 * RESOLUTION
	return {
		"resolution": RESOLUTION,
		"cascades": MAX_WAVES,
		"sim_hz": SIM_TICK_RATE,
		"gpu_fft_ms": _gpu_fft_ms,
		"cpu_submit_ms": _cpu_submit_ms,
		"workgroups_per_tick": tile_dispatches + fft_dispatches,
		"texture_mb": texture_bytes / (1024.0 * 1024.0),
		"readback_mb_s": readback_mb_s,
		"readback_hz": SIM_TICK_RATE / float(BUOYANCY_READBACK_INTERVAL),
		"readback_in_flight": _readback_in_flight,
		"physics_query_resolution": PHYSICS_QUERY_RESOLUTION,
		"snapshot_age_ms": get_physics_query_age_seconds() * 1000.0,
	}


func get_physics_query_age_seconds() -> float:
	if physics_query_source_usec <= 0:
		return INF
	return float(Time.get_ticks_usec() - physics_query_source_usec) / 1_000_000.0


func _profile_enabled() -> bool:
	var hud := get_node_or_null("/root/DebugHud")
	return hud != null and hud.has_method("is_open") and bool(hud.call("is_open"))


func _collect_gpu_profile() -> void:
	if not _profile_enabled():
		return
	var begin_usec := -1
	var end_usec := -1
	for i in range(rd.get_captured_timestamps_count()):
		var marker := rd.get_captured_timestamp_name(i)
		if marker == "WaterFFT.Begin":
			begin_usec = int(rd.get_captured_timestamp_gpu_time(i))
		elif marker == "WaterFFT.End":
			end_usec = int(rd.get_captured_timestamp_gpu_time(i))
	if begin_usec >= 0 and end_usec >= begin_usec:
		# Godot 4.6's D3D12 backend reports these values at nanosecond scale
		# despite the API documentation describing microseconds. The old /1000
		# conversion produced impossible 700 ms samples in a 2 ms frame.
		var sample_ms := float(end_usec - begin_usec) / 1_000_000.0
		# Reject mismatched/ring-buffer timestamp pairs instead of poisoning the
		# running average. A single FFT tick cannot exceed this and sustain play.
		if sample_ms >= 0.0 and sample_ms < 50.0:
			_gpu_fft_ms = sample_ms if _gpu_fft_ms < 0.0 else lerpf(_gpu_fft_ms, sample_ms, 0.2)


func _compile_shaders() -> void:
	pipeline_init = _load_shader_pipeline(FFT_OCEAN_INIT)
	pipeline_pack = _load_shader_pipeline(FFT_OCEAN_PACK)
	pipeline_update = _load_shader_pipeline(FFT_OCEAN_UPDATE)
	pipeline_fft_x = _load_shader_pipeline(FFT_OCEAN_FFT_X)
	pipeline_fft_y = _load_shader_pipeline(FFT_OCEAN_FFT_Y)
	pipeline_assemble = _load_shader_pipeline(FFT_OCEAN_ASSEMBLE)
	var query_version := &""
	var query_versions := FFT_OCEAN_PHYSICS_QUERY.get_version_list()
	if not query_versions.is_empty():
		query_version = query_versions[0]
	var query_spirv := FFT_OCEAN_PHYSICS_QUERY.get_spirv(query_version)
	physics_query_shader = rd.shader_create_from_spirv(query_spirv)
	_shader_rids.append(physics_query_shader)
	pipeline_physics_query = rd.compute_pipeline_create(physics_query_shader)

func _load_shader_pipeline(shader_file: RDShaderFile) -> RID:
	if shader_file == null:
		push_error("FftWaterSystem: Shader file is null")
		return RID()
	
	var versions = shader_file.get_version_list()
	var version_name = &""
	if not versions.is_empty():
		version_name = versions[0]
	
	var shader_spirv: RDShaderSPIRV = shader_file.get_spirv(version_name)
	if shader_spirv == null:
		push_error("FftWaterSystem: Failed to get spirv for shader with version " + str(version_name))
		return RID()
	var shader = rd.shader_create_from_spirv(shader_spirv)
	_shader_rids.append(shader)
	if not main_shader.is_valid():
		main_shader = shader
	return rd.compute_pipeline_create(shader)

func _create_buffers_and_textures() -> void:
	# Spectrums buffer
	var buffer_bytes = PackedByteArray()
	buffer_bytes.resize(8 * 8 * 4) # 8 spectrums * 8 floats * 4 bytes
	buffer_bytes.fill(0)
	spectrums_buffer = rd.storage_buffer_create(buffer_bytes.size(), buffer_bytes)
	
	var common_usage = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT

	# Textures
	var fmt_rgba32 = RDTextureFormat.new()
	fmt_rgba32.width = RESOLUTION
	fmt_rgba32.height = RESOLUTION
	fmt_rgba32.depth = 1
	fmt_rgba32.mipmaps = 1
	fmt_rgba32.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	fmt_rgba32.usage_bits = common_usage
	fmt_rgba32.texture_type = RenderingDevice.TEXTURE_TYPE_2D_ARRAY
	fmt_rgba32.array_layers = 4
	
	var fmt_rgba32_8 = RDTextureFormat.new()
	fmt_rgba32_8.width = RESOLUTION
	fmt_rgba32_8.height = RESOLUTION
	fmt_rgba32_8.depth = 1
	fmt_rgba32_8.mipmaps = 1
	fmt_rgba32_8.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	fmt_rgba32_8.usage_bits = common_usage
	fmt_rgba32_8.texture_type = RenderingDevice.TEXTURE_TYPE_2D_ARRAY
	fmt_rgba32_8.array_layers = 8
	
	target_spectrum_tex = rd.texture_create(fmt_rgba32, RDTextureView.new())
	initial_spectrum_tex = rd.texture_create(fmt_rgba32, RDTextureView.new())
	spectrum_tex = rd.texture_create(fmt_rgba32_8, RDTextureView.new())
	displacement_tex = rd.texture_create(fmt_rgba32, RDTextureView.new())
	
	var fmt_rg32 = RDTextureFormat.new()
	fmt_rg32.width = RESOLUTION
	fmt_rg32.height = RESOLUTION
	fmt_rg32.depth = 1
	fmt_rg32.mipmaps = 1
	fmt_rg32.format = RenderingDevice.DATA_FORMAT_R32G32_SFLOAT
	fmt_rg32.usage_bits = common_usage
	fmt_rg32.texture_type = RenderingDevice.TEXTURE_TYPE_2D_ARRAY
	fmt_rg32.array_layers = 4
	slope_tex = rd.texture_create(fmt_rg32, RDTextureView.new())
	
	var fmt_r32 = RDTextureFormat.new()
	fmt_r32.width = RESOLUTION
	fmt_r32.height = RESOLUTION
	fmt_r32.depth = 1
	fmt_r32.mipmaps = 1
	fmt_r32.format = RenderingDevice.DATA_FORMAT_R32_SFLOAT
	fmt_r32.usage_bits = common_usage
	fmt_r32.texture_type = RenderingDevice.TEXTURE_TYPE_2D_ARRAY
	fmt_r32.array_layers = 4
	buoyancy_tex = rd.texture_create(fmt_r32, RDTextureView.new())

	var fmt_query = RDTextureFormat.new()
	fmt_query.width = PHYSICS_QUERY_RESOLUTION
	fmt_query.height = PHYSICS_QUERY_RESOLUTION
	fmt_query.depth = 1
	fmt_query.mipmaps = 1
	fmt_query.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	fmt_query.usage_bits = common_usage
	fmt_query.texture_type = RenderingDevice.TEXTURE_TYPE_2D_ARRAY
	fmt_query.array_layers = 4
	physics_query_tex = rd.texture_create(fmt_query, RDTextureView.new())
	physics_previous_tex = rd.texture_create(fmt_query, RDTextureView.new())
	
	# Create Godot wrappers for spatial shader
	displacement_map_rd = Texture2DArrayRD.new()
	displacement_map_rd.texture_rd_rid = displacement_tex
	
	slope_map_rd = Texture2DArrayRD.new()
	slope_map_rd.texture_rd_rid = slope_tex
	
	buoyancy_map_rd = Texture2DArrayRD.new()
	buoyancy_map_rd.texture_rd_rid = buoyancy_tex

func _create_uniform_set() -> void:
	var uniforms: Array[RDUniform] = []
	
	var u_spectrums = RDUniform.new()
	u_spectrums.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u_spectrums.binding = 0
	u_spectrums.add_id(spectrums_buffer)
	uniforms.append(u_spectrums)
	
	var u_initial = RDUniform.new()
	u_initial.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u_initial.binding = 1
	u_initial.add_id(initial_spectrum_tex)
	uniforms.append(u_initial)
	
	var u_spectrum = RDUniform.new()
	u_spectrum.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u_spectrum.binding = 2
	u_spectrum.add_id(spectrum_tex)
	uniforms.append(u_spectrum)
	
	var u_disp = RDUniform.new()
	u_disp.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u_disp.binding = 3
	u_disp.add_id(displacement_tex)
	uniforms.append(u_disp)
	
	var u_slope = RDUniform.new()
	u_slope.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u_slope.binding = 4
	u_slope.add_id(slope_tex)
	uniforms.append(u_slope)
	
	var u_buoyancy = RDUniform.new()
	u_buoyancy.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u_buoyancy.binding = 5
	u_buoyancy.add_id(buoyancy_tex)
	uniforms.append(u_buoyancy)
	
	var u_fourier = RDUniform.new()
	u_fourier.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u_fourier.binding = 6
	u_fourier.add_id(spectrum_tex)
	uniforms.append(u_fourier)
	
	var u_target := RDUniform.new()
	u_target.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u_target.binding = 7
	u_target.add_id(target_spectrum_tex)
	uniforms.append(u_target)

	# Any pipeline is fine to query the set layout, as they all share set 0
	uniform_set = rd.uniform_set_create(uniforms, main_shader, 0)

	var query_uniforms: Array[RDUniform] = []
	var query_source := RDUniform.new()
	query_source.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	query_source.binding = 0
	query_source.add_id(displacement_tex)
	query_uniforms.append(query_source)
	var query_target := RDUniform.new()
	query_target.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	query_target.binding = 1
	query_target.add_id(physics_query_tex)
	query_uniforms.append(query_target)
	var query_previous := RDUniform.new()
	query_previous.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	query_previous.binding = 2
	query_previous.add_id(physics_previous_tex)
	query_uniforms.append(query_previous)
	_physics_query_uniform_set = rd.uniform_set_create(
		query_uniforms, physics_query_shader, 0
	)

func _init_spectrums() -> void:
	var bytes = PackedByteArray()
	bytes.resize(8 * 8 * 4) # 8 spectrums, 8 floats each
	
	# Default parameters for a rough sea
	for i in range(8):
		var offset = i * 32
		bytes.encode_float(offset + 0, 1.0) # scale
		bytes.encode_float(offset + 4, 0.0) # angle
		bytes.encode_float(offset + 8, 1.0) # spread_blend
		bytes.encode_float(offset + 12, 1.0) # swell
		bytes.encode_float(offset + 16, 0.0081) # alpha
		bytes.encode_float(offset + 20, 9.81 / 10.0) # peak_omega (g/U10)
		bytes.encode_float(offset + 24, 3.3) # gamma
		bytes.encode_float(offset + 28, 0.01) # short_waves_fade
		
	rd.buffer_update(spectrums_buffer, 0, bytes.size(), bytes)

var _last_wind_angle := -10.0  # sentinel: outside the [-PI, PI] band
var weather_repack_count := 0

func sync_weather(wind: float, storm: float, short_wave: float, wind_angle: float = 0.0) -> void:
	if not rd or not spectrums_buffer.is_valid(): return

	# Presentation interpolates continuously; FFT spectrum changes are expensive
	# and only need repacking when the physical envelope moves meaningfully.
	var angle_delta := absf(wrapf(wind_angle - _last_wind_angle, -PI, PI))
	if (absf(wind - _last_wind) < 0.025
			and absf(storm - _last_storm) < 0.04
			and absf(short_wave - _last_short_wave) < 0.04
			and angle_delta < 0.08):
		return

	_last_wind = wind
	_last_storm = storm
	_last_short_wave = short_wave
	_last_wind_angle = wind_angle

	var w_speed = lerpf(4.0, 25.0, wind)
	var peak_omega = 9.81 / max(w_speed, 0.1)
	var sw_fade = lerpf(0.04, 0.001, short_wave)
	var scale = 1.0 # Base scale, wave_intensity controls dynamic amplitude directly in shader
	var swell = lerpf(1.0, 0.2, storm)

	var bytes = PackedByteArray()
	bytes.resize(8 * 8 * 4)
	for i in range(8):
		var offset = i * 32
		bytes.encode_float(offset + 0, scale) # scale
		bytes.encode_float(offset + 4, wind_angle) # angle (radians, world XZ)
		bytes.encode_float(offset + 8, 1.0) # spread_blend
		bytes.encode_float(offset + 12, swell) # swell
		bytes.encode_float(offset + 16, 0.0081) # alpha
		bytes.encode_float(offset + 20, peak_omega) # peak_omega
		bytes.encode_float(offset + 24, 3.3) # gamma
		bytes.encode_float(offset + 28, sw_fade) # short_waves_fade

	rd.buffer_update(spectrums_buffer, 0, bytes.size(), bytes)
	_run_init_pack()
	weather_repack_count += 1

func _update_push_constants(delta_time: float) -> void:
	push_constant_params.encode_float(0, time)
	push_constant_params.encode_float(4, delta_time)
	push_constant_params.encode_float(8, 9.81)
	push_constant_params.encode_float(12, repeat_time)
	push_constant_params.encode_float(16, depth)
	push_constant_params.encode_float(20, low_cutoff)
	push_constant_params.encode_float(24, high_cutoff)
	push_constant_params.encode_u32(28, 0) # seed
	push_constant_params.encode_u32(32, RESOLUTION)
	push_constant_params.encode_u32(36, int(length_scales.x))
	push_constant_params.encode_float(40, lambda.x)
	push_constant_params.encode_float(44, lambda.y)
	push_constant_params.encode_float(48, foam_bias)
	push_constant_params.encode_float(52, foam_decay_rate)
	push_constant_params.encode_float(56, foam_add)
	push_constant_params.encode_float(60, foam_threshold)
	push_constant_params.encode_u32(64, int(length_scales.y))
	push_constant_params.encode_u32(68, int(length_scales.z))
	push_constant_params.encode_u32(72, int(length_scales.w))
	push_constant_params.encode_float(76, 1.0 if not _spectrum_initialized else 1.0 - exp(-delta_time / SPECTRUM_RESPONSE_SECONDS))

func _run_init_pack() -> void:
	_update_push_constants(0.0)
	var compute_list = rd.compute_list_begin()
	
	# INIT
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline_init)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	rd.compute_list_set_push_constant(compute_list, push_constant_params, push_constant_params.size())
	rd.compute_list_dispatch(compute_list, RESOLUTION / 8, RESOLUTION / 8, 1)
	
	rd.compute_list_add_barrier(compute_list)
	
	# PACK
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline_pack)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	rd.compute_list_set_push_constant(compute_list, push_constant_params, push_constant_params.size())
	rd.compute_list_dispatch(compute_list, RESOLUTION / 8, RESOLUTION / 8, 1)
	
	rd.compute_list_end()
	# rd.submit() and rd.sync() removed because we are on the global RenderingDevice


func _run_update_fft_assemble(delta: float) -> void:
	var profile := _profile_enabled()
	var cpu_begin := Time.get_ticks_usec()
	if profile:
		rd.capture_timestamp("WaterFFT.Begin")
	_update_push_constants(delta)
	_spectrum_initialized = true
	var compute_list = rd.compute_list_begin()
	
	# UPDATE
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline_update)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	rd.compute_list_set_push_constant(compute_list, push_constant_params, push_constant_params.size())
	rd.compute_list_dispatch(compute_list, RESOLUTION / 8, RESOLUTION / 8, 1)
	
	rd.compute_list_add_barrier(compute_list)
	
	# FFT X
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline_fft_x)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	rd.compute_list_set_push_constant(compute_list, push_constant_params, push_constant_params.size())
	rd.compute_list_dispatch(compute_list, 1, RESOLUTION, 1)
	
	rd.compute_list_add_barrier(compute_list)
	
	# FFT Y
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline_fft_y)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	rd.compute_list_set_push_constant(compute_list, push_constant_params, push_constant_params.size())
	rd.compute_list_dispatch(compute_list, 1, RESOLUTION, 1)
	
	rd.compute_list_add_barrier(compute_list)
	
	# ASSEMBLE
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline_assemble)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	rd.compute_list_set_push_constant(compute_list, push_constant_params, push_constant_params.size())
	rd.compute_list_dispatch(compute_list, RESOLUTION / 8, RESOLUTION / 8, 1)

	rd.compute_list_add_barrier(compute_list)
	_physics_query_push.encode_float(0, maxf(delta, 0.001))
	_physics_query_push.encode_u32(4, 1 if _physics_query_has_previous else 0)
	_physics_query_push.encode_u32(8, RESOLUTION)
	_physics_query_push.encode_u32(12, PHYSICS_QUERY_RESOLUTION)
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline_physics_query)
	rd.compute_list_bind_uniform_set(compute_list, _physics_query_uniform_set, 0)
	rd.compute_list_set_push_constant(
		compute_list, _physics_query_push, _physics_query_push.size()
	)
	rd.compute_list_dispatch(
		compute_list,
		PHYSICS_QUERY_RESOLUTION / 8,
		PHYSICS_QUERY_RESOLUTION / 8,
		4
	)
	_physics_query_has_previous = true
	
	rd.compute_list_end()
	if profile:
		rd.capture_timestamp("WaterFFT.End")
	var cpu_sample_ms := float(Time.get_ticks_usec() - cpu_begin) / 1000.0
	_cpu_submit_ms = lerpf(_cpu_submit_ms, cpu_sample_ms, 0.2)
	# rd.submit() and rd.sync() removed because we are on the global RenderingDevice
