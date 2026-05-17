class_name FFTWaterSystem
extends Node

const RESOLUTION = 1024
const MAX_WAVES = 4

var rd: RenderingDevice
var uniform_set: RID

var pipeline_init: RID
var pipeline_pack: RID
var pipeline_update: RID
var pipeline_fft_x: RID
var pipeline_fft_y: RID
var pipeline_assemble: RID

var initial_spectrum_tex: RID
var spectrum_tex: RID
var displacement_tex: RID
var slope_tex: RID
var buoyancy_tex: RID
var spectrums_buffer: RID

var displacement_map_rd: Texture2DArrayRD
var slope_map_rd: Texture2DArrayRD
var buoyancy_map_rd: Texture2DRD

var time: float = 0.0
var _last_wind := -1.0
var _last_storm := -1.0
var _last_short_wave := -1.0
@export var length_scales := Vector4(256.0, 64.0, 16.0, 4.0)
@export var depth: float = 100.0
@export var repeat_time: float = 200.0
@export var low_cutoff: float = 0.0001
@export var high_cutoff: float = 9000.0

@export var foam_bias: float = 2.0
@export var foam_decay_rate: float = 0.5
@export var foam_add: float = 1.0
@export var foam_threshold: float = 0.4
@export var lambda := Vector2(1.0, 1.0)

var push_constant_params := PackedByteArray()
var buoyancy_data := PackedFloat32Array()

func _ready() -> void:
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

func _process(delta: float) -> void:
	if not rd: return
	time += delta
	_run_update_fft_assemble(delta)
	
	var bytes = rd.texture_get_data(buoyancy_tex, 0)
	if bytes.size() == RESOLUTION * RESOLUTION * 4:
		buoyancy_data = bytes.to_float32_array()
		if Time.get_ticks_msec() % 1000 < 16:
			print("buoyancy_data[0]: ", buoyancy_data[0], " [500]: ", buoyancy_data[500])

var main_shader: RID

func _compile_shaders() -> void:
	var file = FileAccess.open("res://resources/shaders/fft_ocean_compute.glsl", FileAccess.READ)
	var base_code = file.get_as_text()
	var code_without_version = base_code.replace("#version 450", "")
	
	pipeline_init = _create_pipeline("#version 450\n#define PASS_INIT\n" + code_without_version)
	pipeline_pack = _create_pipeline("#version 450\n#define PASS_PACK\n" + code_without_version)
	pipeline_update = _create_pipeline("#version 450\n#define PASS_UPDATE\n" + code_without_version)
	pipeline_fft_x = _create_pipeline("#version 450\n#define PASS_FFT_X\n" + code_without_version)
	pipeline_fft_y = _create_pipeline("#version 450\n#define PASS_FFT_Y\n" + code_without_version)
	pipeline_assemble = _create_pipeline("#version 450\n#define PASS_ASSEMBLE\n" + code_without_version)

func _create_pipeline(src: String) -> RID:
	var shader_src = RDShaderSource.new()
	shader_src.set_stage_source(RenderingDevice.SHADER_STAGE_COMPUTE, src)
	var spirv = rd.shader_compile_spirv_from_source(shader_src)
	if spirv.compile_error_compute != "":
		push_error("Compute Shader Compile Error: ", spirv.compile_error_compute)
	var shader = rd.shader_create_from_spirv(spirv)
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
	fmt_r32.texture_type = RenderingDevice.TEXTURE_TYPE_2D
	buoyancy_tex = rd.texture_create(fmt_r32, RDTextureView.new())
	
	# Create Godot wrappers for spatial shader
	displacement_map_rd = Texture2DArrayRD.new()
	displacement_map_rd.texture_rd_rid = displacement_tex
	
	slope_map_rd = Texture2DArrayRD.new()
	slope_map_rd.texture_rd_rid = slope_tex
	
	buoyancy_map_rd = Texture2DRD.new()
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
	
	# Any pipeline is fine to query the set layout, as they all share set 0
	uniform_set = rd.uniform_set_create(uniforms, main_shader, 0)

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

func sync_weather(wind: float, storm: float, short_wave: float) -> void:
	if not rd or not spectrums_buffer.is_valid(): return
	
	if is_equal_approx(wind, _last_wind) and is_equal_approx(storm, _last_storm) and is_equal_approx(short_wave, _last_short_wave):
		return
		
	_last_wind = wind
	_last_storm = storm
	_last_short_wave = short_wave

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
		bytes.encode_float(offset + 4, 0.0) # angle
		bytes.encode_float(offset + 8, 1.0) # spread_blend
		bytes.encode_float(offset + 12, swell) # swell
		bytes.encode_float(offset + 16, 0.0081) # alpha
		bytes.encode_float(offset + 20, peak_omega) # peak_omega
		bytes.encode_float(offset + 24, 3.3) # gamma
		bytes.encode_float(offset + 28, sw_fade) # short_waves_fade
		
	rd.buffer_update(spectrums_buffer, 0, bytes.size(), bytes)
	_run_init_pack()

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
	push_constant_params.encode_float(76, 0.0) # pad

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
	_update_push_constants(delta)
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
	
	rd.compute_list_end()
	# rd.submit() and rd.sync() removed because we are on the global RenderingDevice
